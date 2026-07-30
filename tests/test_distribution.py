#!/usr/bin/env python3
import subprocess
import os
import re
import shutil
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "scripts" / "build-theme.zsh"
PRIVACY_MARKERS = ROOT / "scripts" / "privacy-markers.zsh"
THEME = ROOT / "ai-candy.zsh-theme"
COMPATIBILITY_WORKFLOW = ROOT / ".github" / "workflows" / "compatibility.yml"
MODULES = (
    ROOT / "src" / "bootstrap.zsh",
    ROOT / "src" / "unicode-width.zsh",
    ROOT / "src" / "cache.zsh",
    ROOT / "src" / "ui.zsh",
    ROOT / "src" / "prompt.zsh",
    ROOT / "src" / "git.zsh",
    ROOT / "src" / "integrations.zsh",
    ROOT / "src" / "theme.zsh",
)


def private_markers() -> tuple[str, ...]:
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
    return tuple(result.stdout.splitlines())


def public_text_files(root: Path = ROOT) -> list[Path]:
    excluded_directories = {
        ".git",
        ".mypy_cache",
        ".pytest_cache",
        ".ruff_cache",
        "__pycache__",
        "temp",
    }
    binary_suffixes = {".gif", ".png", ".pyc"}
    listed = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if listed.returncode == 0:
        candidates = (root / name for name in listed.stdout.split("\0") if name)
    else:
        candidates = root.rglob("*")
    return sorted(
        path
        for path in candidates
        if path.is_file()
        and not any(
            part in excluded_directories for part in path.relative_to(root).parts
        )
        and path.suffix.lower() not in binary_suffixes
    )


class DistributionTest(unittest.TestCase):
    def test_supported_zsh_floor_matches_the_compatibility_image(self) -> None:
        bootstrap = (ROOT / "src" / "bootstrap.zsh").read_text(encoding="ascii")
        readme = (ROOT / "README.md").read_text(encoding="ascii")
        workflow = COMPATIBILITY_WORKFLOW.read_text(encoding="ascii")

        self.assertIn("if ! is-at-least 5.4.2; then", bootstrap)
        self.assertIn("Requires zsh 5.4.2+", bootstrap)
        self.assertEqual(2, readme.count("Zsh 5.4.2 or newer"))
        self.assertIn("Zsh 5.4.2 compatibility", workflow)
        self.assertIn('[[ "$ZSH_VERSION" == 5.4.2 ]]', workflow)

    def test_standalone_theme_declares_its_generation_source(self) -> None:
        theme = THEME.read_text(encoding="utf-8")

        self.assertIn(
            "Edit the modules and run scripts/build-theme.zsh instead of editing it directly.",
            theme,
        )

    def test_repository_ignores_local_agent_settings(self) -> None:
        ignored = (ROOT / ".gitignore").read_text(encoding="ascii").splitlines()

        for entry in (
            ".claude/",
            ".pytest_cache/",
            ".ruff_cache/",
            ".demo-publish.*/",
            "ai-candy.zsh-theme.tmp.*",
            "relative/",
        ):
            self.assertIn(entry, ignored)

    def test_compatibility_jobs_have_bounded_runtime(self) -> None:
        workflow = COMPATIBILITY_WORKFLOW.read_text(encoding="ascii")

        for job_name in ("ubuntu", "enterprise-linux", "macos", "zsh-5-4"):
            job = re.search(
                rf"^  {re.escape(job_name)}:\n(?P<body>.*?)(?=^  [a-z0-9-]+:\n|\Z)",
                workflow,
                re.MULTILINE | re.DOTALL,
            )
            self.assertIsNotNone(job, job_name)
            timeout = re.search(r"^    timeout-minutes: ([0-9]+)$", job["body"], re.MULTILINE)
            self.assertIsNotNone(timeout, job_name)
            self.assertLessEqual(int(timeout.group(1)), 30, job_name)

    def test_theme_sources_do_not_use_zsh_namerefs(self) -> None:
        nameref = re.compile(r"^[ \t]*(?:local|typeset)[ \t]+-n(?:[ \t]|$)", re.MULTILINE)
        findings = []

        for source in (*MODULES, THEME):
            if nameref.search(source.read_text(encoding="utf-8")):
                findings.append(source.name)

        self.assertEqual([], findings)

    def test_enterprise_linux_images_are_digest_pinned(self) -> None:
        workflow = COMPATIBILITY_WORKFLOW.read_text(encoding="ascii")
        image_lines = [
            line.strip()
            for line in workflow.splitlines()
            if line.strip().startswith("image: almalinux")
        ]

        self.assertEqual(2, len(image_lines))
        for line in image_lines:
            image = line.partition(": ")[2]
            name, separator, digest = image.partition("@sha256:")
            self.assertEqual("almalinux", name)
            self.assertEqual("@sha256:", separator)
            self.assertEqual(64, len(digest))
            self.assertTrue(
                all(character in "0123456789abcdef" for character in digest)
            )

    def test_public_text_discovery_includes_new_nested_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            nested = root / "docs" / "nested.txt"
            nested.parent.mkdir()
            nested.write_text("public\n", encoding="ascii")
            manifest = root / "demo-assets.sha256"
            manifest.write_text("digest\n", encoding="ascii")
            (root / "demo.gif").write_bytes(b"GIF89a")
            ignored = root / "temp" / "private.txt"
            ignored.parent.mkdir()
            ignored.write_text("private\n", encoding="ascii")

            discovered = public_text_files(root)

            self.assertEqual([manifest, nested], discovered)

    def test_standalone_theme_matches_canonical_modules(self) -> None:
        self.assertTrue(BUILD_SCRIPT.is_file(), BUILD_SCRIPT)
        self.assertTrue(all(module.is_file() for module in MODULES), MODULES)
        subprocess.run(
            ["zsh", str(BUILD_SCRIPT), "--check"],
            cwd=ROOT,
            check=True,
        )

    def test_theme_functions_use_the_project_namespace(self) -> None:
        definition = re.compile(
            r"^(?:function[ \t]+)?([A-Za-z_][A-Za-z0-9_]*)\(\)[ \t]*\{",
            re.MULTILINE,
        )
        findings = []

        for module in MODULES:
            for function_name in definition.findall(module.read_text(encoding="utf-8")):
                if not function_name.startswith(("_ai_candy_", "_AI_CANDY_")):
                    findings.append(f"{module.name}: {function_name}")

        self.assertEqual([], findings)

    def test_build_temporary_file_cannot_follow_a_symbolic_link(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project"
            scripts = project / "scripts"
            modules = project / "src"
            scripts.mkdir(parents=True)
            modules.mkdir()
            shutil.copy2(BUILD_SCRIPT, scripts / BUILD_SCRIPT.name)
            for module in MODULES:
                shutil.copy2(module, modules / module.name)
            shutil.copy2(THEME, project / THEME.name)
            victim = project / "victim"
            victim.write_text("keep\n", encoding="ascii")
            output = project / THEME.name
            attack = r"""
ln -s "$1" "${2}.tmp.$$" || exit 70
exec zsh "$3"
"""

            built = subprocess.run(
                [
                    "zsh",
                    "-fc",
                    attack,
                    "zsh",
                    str(victim),
                    str(output),
                    str(scripts / BUILD_SCRIPT.name),
                ],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(0, built.returncode, built.stderr)
            self.assertEqual("keep\n", victim.read_text(encoding="ascii"))
            self.assertTrue(output.is_file())
            self.assertFalse(output.is_symlink())

    def test_build_stops_without_publishing_after_termination(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project"
            scripts = project / "scripts"
            modules = project / "src"
            fake_bin = project / "bin"
            scripts.mkdir(parents=True)
            modules.mkdir()
            fake_bin.mkdir()
            shutil.copy2(BUILD_SCRIPT, scripts / BUILD_SCRIPT.name)
            for module in MODULES:
                shutil.copy2(module, modules / module.name)
            output = project / THEME.name
            output.write_text("original\n", encoding="ascii")
            fake_cat = fake_bin / "cat"
            fake_cat.write_text(
                '#!/bin/sh\nkill -TERM "$PPID"\nexec /bin/cat "$@"\n',
                encoding="ascii",
            )
            fake_cat.chmod(0o755)
            fake_rm = fake_bin / "rm"
            fake_rm.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
            fake_rm.chmod(0o755)

            built = subprocess.run(
                ["zsh", str(scripts / BUILD_SCRIPT.name)],
                cwd=project,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "PATH": f"{fake_bin}:/usr/bin:/bin"},
                check=False,
                timeout=8,
            )

            self.assertNotEqual(0, built.returncode)
            self.assertEqual("original\n", output.read_text(encoding="ascii"))

    def test_public_text_files_do_not_contain_machine_paths_or_secrets(self) -> None:
        forbidden = (
            "/" + "home/",
            "/" + "Users/",
            *private_markers(),
        )

        findings = []
        for path in public_text_files():
            text = path.read_text(encoding="utf-8")
            for marker in forbidden:
                if marker in text:
                    findings.append(f"{path.relative_to(ROOT)}: {marker}")

        self.assertEqual([], findings)

    def test_public_text_files_have_no_trailing_whitespace(self) -> None:
        findings = []
        for path in public_text_files():
            for line_number, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(), start=1
            ):
                if line.endswith((" ", "\t")):
                    findings.append(f"{path.relative_to(ROOT)}:{line_number}")

        self.assertEqual([], findings)

    def test_readme_downloads_installer_before_executing_it(self) -> None:
        readme = (ROOT / "README.md").read_text(encoding="utf-8")

        self.assertNotIn('sh -c "$(curl', readme)
        self.assertIn('curl -fsSL --proto "=https"', readme)
        self.assertIn("--connect-timeout 5 --max-time 30", readme)
        self.assertEqual(2, readme.count("installer_max_bytes=262144"))
        self.assertEqual(
            2, readme.count('--max-filesize "$installer_max_bytes"')
        )
        self.assertEqual(
            2, readme.count('ulimit -f "$installer_limit_blocks"')
        )
        self.assertIn('-o "$installer" -- "$installer_url"', readme)
        self.assertEqual(2, readme.count('wc -c < "$installer"'))
        self.assertIn('&& sh "$installer" "$@"', readme)

    def test_readme_documents_that_short_aliases_are_opt_in(self) -> None:
        readme = (ROOT / "README.md").read_text(encoding="utf-8")

        self.assertIn("Short aliases are disabled by default", readme)
        self.assertIn("AI_CANDY_ENABLE_SHORT_ALIASES=1", readme)


if __name__ == "__main__":
    unittest.main()
