#!/usr/bin/env python3
import os
import hashlib
import signal
import shutil
import socket
import struct
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from tests.theme_test_support import process_is_running


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts" / "generate-demo.zsh"
TAPE = ROOT / "scripts" / "demo.tape"
PRIVACY_MARKERS = ROOT / "scripts" / "privacy-markers.zsh"
VALID_DEMO_OUTPUT = (
    "printf '%s\\n' 'AI Candy |' 'demo@workstation' 'Network mode: OFF' "
    "'Disabled: public IP, GitHub username/PR status, AI update checks' "
    "'All toggles turned ON:' 'Layout: MINIMAL' > demo.txt\n"
)


def copy_demo_sources(project: Path) -> Path:
    scripts_dir = project / "scripts"
    scripts_dir.mkdir(parents=True)
    shutil.copy2(GENERATOR, scripts_dir / GENERATOR.name)
    shutil.copy2(TAPE, scripts_dir / TAPE.name)
    shutil.copy2(PRIVACY_MARKERS, scripts_dir / PRIVACY_MARKERS.name)
    shutil.copy2(ROOT / "ai-candy.zsh-theme", project / "ai-candy.zsh-theme")
    return scripts_dir


def private_markers() -> list[str]:
    result = subprocess.run(
        [
            "zsh",
            "-fc",
            'source "$1"; print -rl -- "${_AI_CANDY_PRIVATE_MARKERS[@]}"',
            "zsh",
            str(PRIVACY_MARKERS),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return result.stdout.splitlines()


class DemoGenerationTest(unittest.TestCase):
    def test_renderer_must_capture_the_real_theme_session(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project"
            fake_bin = project / "bin"
            scripts_dir = copy_demo_sources(project)
            fake_bin.mkdir()
            renderer = fake_bin / "vhs"
            renderer.write_text(
                "#!/bin/sh\n"
                "printf 'cursor only\\n' > demo.txt\n"
                "printf 'gif\\n' > demo.gif\n"
                "printf 'png\\n' > demo.png\n",
                encoding="ascii",
            )
            renderer.chmod(0o755)
            for name in ("ttyd", "ffmpeg"):
                executable = fake_bin / name
                executable.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
                executable.chmod(0o755)

            generated = subprocess.run(
                [shutil.which("zsh") or "zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "PATH": f"{fake_bin}:/usr/bin:/bin"},
                check=False,
                timeout=8,
            )

            self.assertNotEqual(0, generated.returncode)
            self.assertIn("expected demo content", generated.stderr)
            self.assertFalse((project / "demo.gif").exists())
            self.assertFalse((project / "demo.png").exists())

    def test_private_identity_in_renderer_output_prevents_publication(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            project = root / "project"
            private_home = root / "private-home"
            fake_bin = project / "bin"
            scripts_dir = copy_demo_sources(project)
            private_home.mkdir()
            fake_bin.mkdir()
            old_assets = {
                "demo.gif": b"old-gif\n",
                "demo.png": b"old-png\n",
                "demo-assets.sha256": b"old-manifest\n",
            }
            for name, content in old_assets.items():
                (project / name).write_bytes(content)

            renderer = fake_bin / "vhs"
            renderer.write_text(
                "#!/bin/sh\n"
                f"printf '%s\\n' '{private_home}' > demo.txt\n"
                "printf 'new-gif\\n' > demo.gif\n"
                "printf 'new-png\\n' > demo.png\n",
                encoding="ascii",
            )
            renderer.chmod(0o755)
            for name in ("ttyd", "ffmpeg"):
                executable = fake_bin / name
                executable.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
                executable.chmod(0o755)

            generated = subprocess.run(
                ["zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={
                    **os.environ,
                    "HOME": str(private_home),
                    "PATH": f"{fake_bin}:/usr/bin:/bin",
                },
                check=False,
                timeout=8,
            )

            self.assertNotEqual(0, generated.returncode)
            self.assertIn("local identity marker", generated.stderr)
            for name, content in old_assets.items():
                self.assertEqual(content, (project / name).read_bytes(), name)
            self.assertEqual([], list(project.glob(".demo-publish.*")))
            self.assertEqual([], list((project / "temp").glob("demo-render.*")))

    def test_interrupted_publication_restores_previous_assets(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project"
            fake_bin = project / "bin"
            scripts_dir = copy_demo_sources(project)
            fake_bin.mkdir()
            old_assets = {
                "demo.gif": b"old-gif\n",
                "demo.png": b"old-png\n",
                "demo-assets.sha256": b"old-manifest\n",
            }
            for name, content in old_assets.items():
                (project / name).write_bytes(content)

            renderer = fake_bin / "vhs"
            renderer.write_text(
                "#!/bin/sh\n"
                f"{VALID_DEMO_OUTPUT}"
                "printf 'new-gif\\n' > demo.gif\n"
                "printf 'new-png\\n' > demo.png\n",
                encoding="ascii",
            )
            renderer.chmod(0o755)
            for name in ("ttyd", "ffmpeg"):
                executable = fake_bin / name
                executable.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
                executable.chmod(0o755)

            signal_marker = project / "publish-signaled"
            real_mv = shutil.which("mv") or "/bin/mv"
            fake_mv = fake_bin / "mv"
            fake_mv.write_text(
                "#!/bin/sh\n"
                "last=\n"
                'for argument in "$@"; do last=$argument; done\n'
                f"'{real_mv}' \"$@\" || exit $?\n"
                f"if [ \"$last\" = '{project / 'demo.gif'}' ] && "
                f"[ ! -e '{signal_marker}' ]; then\n"
                f"  : > '{signal_marker}'\n"
                '  kill -TERM "$PPID"\n'
                "fi\n",
                encoding="ascii",
            )
            fake_mv.chmod(0o755)

            generated = subprocess.run(
                ["zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "PATH": f"{fake_bin}:/usr/bin:/bin"},
                check=False,
                timeout=8,
            )

            self.assertNotEqual(0, generated.returncode)
            self.assertTrue(signal_marker.is_file())
            for name, content in old_assets.items():
                self.assertEqual(content, (project / name).read_bytes(), name)

    def test_failed_rollback_retains_complete_recovery_copies(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project"
            fake_bin = project / "bin"
            scripts_dir = copy_demo_sources(project)
            fake_bin.mkdir()
            old_assets = {
                "demo.gif": b"old-gif\n",
                "demo.png": b"old-png\n",
                "demo-assets.sha256": b"old-manifest\n",
            }
            for name, content in old_assets.items():
                (project / name).write_bytes(content)

            renderer = fake_bin / "vhs"
            renderer.write_text(
                "#!/bin/sh\n"
                f"{VALID_DEMO_OUTPUT}"
                "printf 'new-gif\\n' > demo.gif\n"
                "printf 'new-png\\n' > demo.png\n",
                encoding="ascii",
            )
            renderer.chmod(0o755)
            for name in ("ttyd", "ffmpeg"):
                executable = fake_bin / name
                executable.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
                executable.chmod(0o755)

            signal_marker = project / "publish-signaled"
            real_mv = shutil.which("mv") or "/bin/mv"
            fake_mv = fake_bin / "mv"
            fake_mv.write_text(
                "#!/bin/sh\n"
                "source_path=$2\n"
                "last=\n"
                'for argument in "$@"; do last=$argument; done\n'
                f"if [ \"$last\" = '{project / 'demo.gif'}' ] && "
                f"[ -e '{signal_marker}' ]; then\n"
                '  case "$source_path" in\n'
                "    */.demo-restore.*) exit 73 ;;\n"
                "  esac\n"
                "fi\n"
                f"'{real_mv}' \"$@\" || exit $?\n"
                f"if [ \"$last\" = '{project / 'demo.gif'}' ] && "
                f"[ ! -e '{signal_marker}' ]; then\n"
                f"  : > '{signal_marker}'\n"
                '  kill -TERM "$PPID"\n'
                "fi\n",
                encoding="ascii",
            )
            fake_mv.chmod(0o755)

            generated = subprocess.run(
                ["zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "PATH": f"{fake_bin}:/usr/bin:/bin"},
                check=False,
                timeout=8,
            )

            self.assertNotEqual(0, generated.returncode)
            self.assertIn("recovery copies", generated.stderr.lower())
            backups = list(project.glob(".demo-publish.*"))
            self.assertEqual(
                1,
                len(backups),
                f"stderr: {generated.stderr}\nentries: {list(project.iterdir())}",
            )
            for name, content in old_assets.items():
                self.assertEqual(content, (backups[0] / name).read_bytes(), name)
            self.assertTrue(list((project / "temp").glob("demo-render.*")))

    def test_generation_stops_without_publishing_after_termination(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project"
            fake_bin = project / "bin"
            scripts_dir = copy_demo_sources(project)
            fake_bin.mkdir()
            ready_file = project / "renderer.ready"
            renderer = fake_bin / "vhs"
            renderer.write_text(
                "#!/bin/sh\n"
                f"{VALID_DEMO_OUTPUT}"
                "printf 'gif\\n' > demo.gif\n"
                "printf 'png\\n' > demo.png\n"
                f"printf 'ready\\n' > '{ready_file}'\n"
                "sleep 0.5\n",
                encoding="ascii",
            )
            renderer.chmod(0o755)
            for name in ("ttyd", "ffmpeg"):
                executable = fake_bin / name
                executable.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
                executable.chmod(0o755)
            fake_rm = fake_bin / "rm"
            fake_rm.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
            fake_rm.chmod(0o755)

            generated = subprocess.Popen(
                ["zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "PATH": f"{fake_bin}:/usr/bin:/bin"},
            )
            try:
                deadline = time.monotonic() + 5
                while not ready_file.exists() and generated.poll() is None:
                    self.assertLess(time.monotonic(), deadline)
                    time.sleep(0.01)
                self.assertTrue(ready_file.exists(), "renderer did not start")
                os.kill(generated.pid, signal.SIGTERM)
                stdout, stderr = generated.communicate(timeout=8)
            finally:
                if generated.poll() is None:
                    generated.kill()
                    generated.communicate()

            self.assertNotEqual(0, generated.returncode, f"{stdout}\n{stderr}")
            self.assertFalse((project / "demo.gif").exists())
            self.assertFalse((project / "demo.png").exists())

    def test_termination_stops_a_long_running_renderer_tree_promptly(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project"
            fake_bin = project / "bin"
            scripts_dir = copy_demo_sources(project)
            fake_bin.mkdir()
            ready_file = project / "renderer.ready"
            renderer_pid_file = project / "renderer.pid"
            child_pid_file = project / "renderer-child.pid"
            renderer = fake_bin / "vhs"
            renderer.write_text(
                "#!/bin/sh\n"
                f"{VALID_DEMO_OUTPUT}"
                "printf 'gif\\n' > demo.gif\n"
                "printf 'png\\n' > demo.png\n"
                f"printf '%s\\n' \"$$\" > '{renderer_pid_file}'\n"
                "sleep 30 &\n"
                f"printf '%s\\n' \"$!\" > '{child_pid_file}'\n"
                f"printf 'ready\\n' > '{ready_file}'\n"
                "wait\n",
                encoding="ascii",
            )
            renderer.chmod(0o755)
            for name in ("ttyd", "ffmpeg"):
                executable = fake_bin / name
                executable.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
                executable.chmod(0o755)

            generated = subprocess.Popen(
                ["zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "PATH": f"{fake_bin}:/usr/bin:/bin"},
            )
            renderer_pid = None
            child_pid = None
            try:
                deadline = time.monotonic() + 5
                while not ready_file.exists() and generated.poll() is None:
                    self.assertLess(time.monotonic(), deadline)
                    time.sleep(0.01)
                self.assertTrue(ready_file.exists(), "renderer did not start")
                renderer_pid = int(renderer_pid_file.read_text(encoding="ascii"))
                child_pid = int(child_pid_file.read_text(encoding="ascii"))

                started = time.monotonic()
                os.kill(generated.pid, signal.SIGTERM)
                stdout, stderr = generated.communicate(timeout=3)
                elapsed = time.monotonic() - started
                self.assertLess(elapsed, 1.5, f"{stdout}\n{stderr}")
                deadline = time.monotonic() + 1
                while (
                    process_is_running(renderer_pid) or process_is_running(child_pid)
                ) and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertFalse(process_is_running(renderer_pid))
                self.assertFalse(process_is_running(child_pid))
            finally:
                if generated.poll() is None:
                    generated.kill()
                for process_pid in (renderer_pid, child_pid):
                    if process_pid is not None and process_is_running(process_pid):
                        os.kill(process_pid, signal.SIGKILL)
                generated.communicate(timeout=2)

            self.assertNotEqual(0, generated.returncode)
            self.assertFalse((project / "demo.gif").exists())
            self.assertFalse((project / "demo.png").exists())

    def test_renderer_cannot_publish_symbolic_link_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project"
            fake_bin = project / "bin"
            scripts_dir = copy_demo_sources(project)
            fake_bin.mkdir()
            victims = [project / "victim.gif", project / "victim.png"]
            for victim in victims:
                victim.write_text("keep\n", encoding="ascii")
                victim.chmod(0o600)
            renderer = fake_bin / "vhs"
            renderer.write_text(
                "#!/bin/sh\n"
                f"{VALID_DEMO_OUTPUT}"
                f"ln -s '{victims[0]}' demo.gif\n"
                f"ln -s '{victims[1]}' demo.png\n",
                encoding="ascii",
            )
            renderer.chmod(0o755)
            for name in ("ttyd", "ffmpeg"):
                executable = fake_bin / name
                executable.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
                executable.chmod(0o755)

            generated = subprocess.run(
                [shutil.which("zsh") or "zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "PATH": f"{fake_bin}:/usr/bin:/bin"},
                check=False,
                timeout=8,
            )

            self.assertNotEqual(0, generated.returncode)
            for victim in victims:
                self.assertEqual("keep\n", victim.read_text(encoding="ascii"))
                self.assertEqual(0o600, victim.stat().st_mode & 0o777)
            self.assertFalse((project / "demo.gif").is_symlink())
            self.assertFalse((project / "demo.png").is_symlink())

    def test_generation_rejects_a_symbolic_link_scratch_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            project = root / "project"
            fake_bin = project / "bin"
            external_scratch = root / "external-scratch"
            scripts_dir = copy_demo_sources(project)
            fake_bin.mkdir()
            external_scratch.mkdir()
            marker = external_scratch / "keep"
            marker.write_text("keep\n", encoding="ascii")
            (project / "temp").symlink_to(external_scratch, target_is_directory=True)

            generated = subprocess.run(
                [shutil.which("zsh") or "zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "PATH": f"{fake_bin}:/usr/bin:/bin"},
                check=False,
                timeout=8,
            )

            self.assertNotEqual(0, generated.returncode)
            self.assertEqual([marker], list(external_scratch.iterdir()))

    def test_renderer_does_not_receive_preexisting_scratch_contents(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            project = root / "project"
            fake_bin = project / "bin"
            scripts_dir = copy_demo_sources(project)
            fake_bin.mkdir()
            stale_dir = project / "temp" / "demo"
            stale_dir.mkdir(parents=True)
            sentinel = stale_dir / "private.txt"
            sentinel.write_text("must-not-be-mounted\n", encoding="ascii")
            capture = project / "renderer.cwd"
            renderer = fake_bin / "vhs"
            renderer.write_text(
                "#!/bin/sh\n"
                f"pwd > '{capture}'\n"
                f"{VALID_DEMO_OUTPUT}"
                "printf 'gif\\n' > demo.gif\n"
                "printf 'png\\n' > demo.png\n",
                encoding="ascii",
            )
            renderer.chmod(0o755)
            for name in ("ttyd", "ffmpeg"):
                executable = fake_bin / name
                executable.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
                executable.chmod(0o755)

            generated = subprocess.run(
                [shutil.which("zsh") or "zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={
                    **os.environ,
                    "PATH": f"{fake_bin}:/usr/bin:/bin",
                },
                check=False,
                timeout=8,
            )

            self.assertEqual(0, generated.returncode, generated.stderr)
            render_dir = Path(capture.read_text(encoding="ascii").strip())
            self.assertEqual(project / "temp", render_dir.parent)
            self.assertTrue(render_dir.name.startswith("demo-render."))
            self.assertFalse(render_dir.exists())
            self.assertEqual(
                "must-not-be-mounted\n", sentinel.read_text(encoding="ascii")
            )

    def test_generation_lock_cannot_follow_a_symbolic_link(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project"
            work_dir = project / "temp"
            fake_bin = project / "bin"
            scripts_dir = copy_demo_sources(project)
            work_dir.mkdir()
            fake_bin.mkdir()
            victim = project / "victim"
            victim.write_text("keep\n", encoding="ascii")
            (work_dir / "demo-generation.lock").symlink_to(victim)

            generated = subprocess.run(
                [shutil.which("zsh") or "zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "PATH": f"{fake_bin}:/usr/bin:/bin"},
                check=False,
                timeout=8,
            )

            self.assertNotEqual(0, generated.returncode)
            self.assertEqual("keep\n", victim.read_text(encoding="ascii"))

    def test_fixture_preparation_rejects_existing_symbolic_link_nodes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixture_dir = root / "fixture"
            fixture_dir.mkdir()
            victim = root / "victim"
            victim.write_text("keep\n", encoding="ascii")
            (fixture_dir / "session.zsh").symlink_to(victim)

            prepared = subprocess.run(
                ["zsh", str(GENERATOR), "--prepare-only", str(fixture_dir)],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertNotEqual(0, prepared.returncode)
            self.assertEqual("keep\n", victim.read_text(encoding="ascii"))

    def test_fixture_preparation_rejects_unscannable_identity_markers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fake_bin = root / "bin"
            fixture_dir = root / "fixture"
            fake_bin.mkdir()
            hostname = fake_bin / "hostname"
            hostname.write_text("#!/bin/sh\nprintf '%s\\n' xy\n", encoding="ascii")
            hostname.chmod(0o755)

            prepared = subprocess.run(
                [
                    shutil.which("zsh") or "zsh",
                    str(GENERATOR),
                    "--prepare-only",
                    str(fixture_dir),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={
                    **os.environ,
                    "PATH": f"{fake_bin}:/usr/bin:/bin",
                    "HOME": str(root / "home"),
                    "USER": "ab",
                },
                check=False,
            )

            self.assertNotEqual(0, prepared.returncode)
            self.assertIn("identity marker", prepared.stderr)

    def test_local_renderer_preserves_font_home_and_isolates_shell_config(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            project = root / "project"
            fake_bin = project / "bin"
            scripts_dir = copy_demo_sources(project)
            fake_bin.mkdir()
            font_home = root / "font-home"
            font_data = root / "font-data"
            font_home.mkdir()
            font_data.mkdir()
            capture = project / "renderer.env"
            renderer = fake_bin / "vhs"
            renderer.write_text(
                f"""#!/bin/sh
{{
  printf 'HOME=%s\\n' "$HOME"
  printf 'ZDOTDIR=%s\\n' "$ZDOTDIR"
  printf 'XDG_DATA_HOME=%s\\n' "${{XDG_DATA_HOME-unset}}"
  printf 'XDG_CACHE_HOME=%s\\n' "$XDG_CACHE_HOME"
  printf 'XDG_CONFIG_HOME=%s\\n' "$XDG_CONFIG_HOME"
  printf 'TMPDIR=%s\\n' "${{TMPDIR-unset}}"
  printf 'USER=%s\\n' "$USER"
  printf 'HOST=%s\\n' "$HOST"
  printf 'PRIVATE=%s\\n' "${{DEMO_PRIVATE_TOKEN-unset}}"
}} > '{capture}'
{VALID_DEMO_OUTPUT}printf 'gif\\n' > demo.gif
printf 'png\\n' > demo.png
""",
                encoding="ascii",
            )
            renderer.chmod(0o755)
            for name in ("ttyd", "ffmpeg"):
                executable = fake_bin / name
                executable.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
                executable.chmod(0o755)

            generated = subprocess.run(
                [shutil.which("zsh") or "zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={
                    **os.environ,
                    "PATH": f"{fake_bin}:/usr/bin:/bin",
                    "HOME": str(font_home),
                    "XDG_DATA_HOME": str(font_data),
                    "DEMO_PRIVATE_TOKEN": "must-not-be-inherited",
                },
                check=False,
                timeout=8,
            )

            self.assertEqual(0, generated.returncode, generated.stderr)
            captured = capture.read_text(encoding="ascii")
            values = dict(line.split("=", 1) for line in captured.splitlines())
            fixture = Path(values["XDG_CACHE_HOME"]).parent
            self.assertEqual(project / "temp", fixture.parent)
            self.assertTrue(fixture.name.startswith("demo-render."))
            self.assertEqual(str(font_home), values["HOME"])
            self.assertEqual(str(font_data), values["XDG_DATA_HOME"])
            self.assertEqual(str(fixture / "config"), values["ZDOTDIR"])
            self.assertEqual(str(fixture / "cache"), values["XDG_CACHE_HOME"])
            self.assertEqual(str(fixture / "config"), values["XDG_CONFIG_HOME"])
            self.assertEqual("unset", values["TMPDIR"])
            self.assertIn("USER=demo", captured)
            self.assertIn("HOST=workstation", captured)
            self.assertIn("PRIVATE=unset", captured)

    def test_missing_local_renderer_dependencies_do_not_fall_back_to_docker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project"
            fake_bin = project / "bin"
            scripts_dir = copy_demo_sources(project)
            fake_bin.mkdir()
            capture = project / "docker.called"
            docker = fake_bin / "docker"
            docker.write_text(
                f"#!/bin/sh\nprintf 'called\\n' > '{capture}'\nexit 99\n",
                encoding="ascii",
            )
            docker.chmod(0o755)

            generated = subprocess.run(
                [shutil.which("zsh") or "zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={
                    **os.environ,
                    "PATH": f"{fake_bin}:/usr/bin:/bin",
                },
                check=False,
                timeout=8,
            )

            self.assertNotEqual(0, generated.returncode)
            self.assertIn("VHS, ttyd, and ffmpeg", generated.stderr)
            self.assertFalse(capture.exists())

    def test_binary_privacy_scan_fails_closed_without_strings(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project"
            fake_bin = project / "bin"
            scripts_dir = copy_demo_sources(project)
            fake_bin.mkdir()
            renderer = fake_bin / "vhs"
            renderer.write_text(
                "#!/bin/sh\n"
                f"{VALID_DEMO_OUTPUT}"
                "printf 'gif\\n' > demo.gif\n"
                "printf 'png\\n' > demo.png\n",
                encoding="ascii",
            )
            renderer.chmod(0o755)
            for name in ("ttyd", "ffmpeg"):
                executable = fake_bin / name
                executable.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
                executable.chmod(0o755)
            for name in (
                "hostname",
                "mkdir",
                "chmod",
                "mktemp",
                "cat",
                "cp",
                "env",
                "mv",
                "rm",
                "id",
            ):
                executable = shutil.which(name)
                self.assertIsNotNone(executable, name)
                (fake_bin / name).symlink_to(executable)

            generated = subprocess.run(
                [shutil.which("zsh") or "zsh", str(scripts_dir / GENERATOR.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "PATH": str(fake_bin)},
                check=False,
                timeout=8,
            )

            self.assertNotEqual(0, generated.returncode)
            self.assertIn("strings", generated.stderr)

    def test_fixture_is_synthetic_network_free_and_interactive(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fixture_dir = Path(tmp) / "fixture"
            prepared = subprocess.run(
                ["zsh", str(GENERATOR), "--prepare-only", str(fixture_dir)],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(0, prepared.returncode, prepared.stderr)

            session = fixture_dir / "session.zsh"
            fixture_theme = fixture_dir / "ai-candy.zsh-theme"
            self.assertTrue(session.is_file())
            self.assertTrue(fixture_theme.is_file())
            self.assertTrue((fixture_dir / "data").is_dir())
            self.assertEqual(
                (ROOT / "ai-candy.zsh-theme").read_bytes(),
                fixture_theme.read_bytes(),
            )
            subprocess.run(["zsh", "-n", str(session)], check=True)
            session_text = session.read_text(encoding="ascii")
            self.assertIn("ai-candy.zsh-theme", session_text)
            self.assertIn("PROMPT", session_text)
            self.assertIn("RPROMPT", session_text)
            self.assertIn("_ai_candy_format_git_snapshot", session_text)
            self.assertIn("_ai_candy_compute_gh_username_direct", session_text)
            self.assertIn("_ai_candy_prompt_toggle_network", session_text)
            self.assertIn(
                'export XDG_DATA_HOME="${fixture_dir}/data"', session_text
            )
            self.assertEqual([], list(fixture_dir.glob("*.ansi")))

            recorded = subprocess.run(
                [str(session)],
                cwd=fixture_dir,
                input="e\np\nn\na\no\noff\non\ncompact\nminimal\nquit\n",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            self.assertEqual(0, recorded.returncode, recorded.stderr)
            self.assertEqual("", recorded.stderr)
            self.assertIn("demo@workstation", recorded.stdout)
            self.assertIn("203.0.113.42", recorded.stdout)
            self.assertIn("~/src/ai-candy", recorded.stdout)
            self.assertIn("Network mode: OFF", recorded.stdout)
            self.assertIn(
                "Disabled: public IP, GitHub username/PR status, AI update checks",
                recorded.stdout,
            )
            self.assertIn("All toggles turned ON", recorded.stdout)
            self.assertIn("Layout: COMPACT", recorded.stdout)
            self.assertIn("Layout: MINIMAL", recorded.stdout)

            fixture_text = "\n".join(
                path.read_text(encoding="utf-8", errors="strict")
                for path in sorted(fixture_dir.iterdir())
                if path.is_file() and path.name != "ai-candy.zsh-theme"
            )
            forbidden = [
                str(Path.home()),
                os.environ.get("USER", ""),
                socket.gethostname(),
                *private_markers(),
            ]
            for marker in forbidden:
                if len(marker) >= 4 and marker not in {"root", "demo"}:
                    self.assertNotIn(marker, fixture_text)
            self.assertNotIn("checkip.amazonaws.com", session_text)
            self.assertNotIn("api.ipify.org", session_text)

    def test_demo_assets_have_declared_generation_sources(self) -> None:
        self.assertTrue(GENERATOR.is_file())
        self.assertTrue(TAPE.is_file())
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("![AI Candy Demo](demo.gif)", readme)
        tape = TAPE.read_text(encoding="utf-8")
        self.assertIn("Output demo.gif", tape)
        self.assertIn("Screenshot demo.png", tape)
        self.assertIn('Set Shell "zsh"', tape)
        self.assertIn('Type "exec ./session.zsh"', tape)
        self.assertIn("Set LetterSpacing 0", tape)

    def test_committed_demo_assets_have_expected_formats(self) -> None:
        gif_data = (ROOT / "demo.gif").read_bytes()
        png_data = (ROOT / "demo.png").read_bytes()

        self.assertIn(gif_data[:6], (b"GIF87a", b"GIF89a"))
        self.assertEqual((1920, 360), struct.unpack("<HH", gif_data[6:10]))
        self.assertGreater(gif_data.count(b"\x21\xf9\x04"), 1)

        self.assertEqual(b"\x89PNG\r\n\x1a\n", png_data[:8])
        self.assertEqual(b"IHDR", png_data[12:16])
        self.assertEqual((1920, 360), struct.unpack(">II", png_data[16:24]))

        forbidden = (
            str(Path.home()),
            os.environ.get("USER", ""),
            socket.gethostname(),
            str(ROOT),
            *private_markers(),
        )
        for marker in forbidden:
            if len(marker) >= 4 and marker not in {"root", "demo"}:
                encoded = marker.encode("utf-8")
                self.assertNotIn(encoded, gif_data)
                self.assertNotIn(encoded, png_data)

    def test_committed_demo_assets_match_reviewed_digests(self) -> None:
        manifest = ROOT / "demo-assets.sha256"
        entries: dict[str, str] = {}
        for line in manifest.read_text(encoding="ascii").splitlines():
            digest, separator, filename = line.partition("  ")
            self.assertEqual("  ", separator)
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
            self.assertNotIn(filename, entries)
            entries[filename] = digest

        self.assertEqual({"demo.gif", "demo.png"}, set(entries))
        for filename, expected in entries.items():
            actual = hashlib.sha256((ROOT / filename).read_bytes()).hexdigest()
            self.assertEqual(expected, actual)


if __name__ == "__main__":
    unittest.main()
