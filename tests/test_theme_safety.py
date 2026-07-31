#!/usr/bin/env python3
import errno
import os
import pty
import re
import select
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from typing import Optional
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
THEME = ROOT / "ai-candy.zsh-theme"


def standalone_c1_or_invalid_offsets(data: bytes) -> list[int]:
    offsets: list[int] = []
    i = 0
    while i < len(data):
        byte = data[i]
        if byte < 0x80:
            i += 1
        elif 0x80 <= byte <= 0x9F:
            offsets.append(i)
            i += 1
        elif 0xC2 <= byte <= 0xDF:
            if i + 1 >= len(data) or not 0x80 <= data[i + 1] <= 0xBF:
                offsets.append(i)
                i += 1
                continue
            codepoint = ((byte & 0x1F) << 6) | (data[i + 1] & 0x3F)
            if 0x80 <= codepoint <= 0x9F:
                offsets.append(i)
            i += 2
        elif 0xE0 <= byte <= 0xEF:
            if i + 2 >= len(data):
                offsets.append(i)
                i += 1
                continue
            second = data[i + 1]
            third = data[i + 2]
            valid_second = (
                0xA0 <= second <= 0xBF
                if byte == 0xE0
                else 0x80 <= second <= (0x9F if byte == 0xED else 0xBF)
            )
            if not valid_second or not 0x80 <= third <= 0xBF:
                offsets.append(i)
                i += 1
                continue
            i += 3
        elif 0xF0 <= byte <= 0xF4:
            if i + 3 >= len(data):
                offsets.append(i)
                i += 1
                continue
            second = data[i + 1]
            third = data[i + 2]
            fourth = data[i + 3]
            if byte == 0xF0:
                valid_second = 0x90 <= second <= 0xBF
            elif byte == 0xF4:
                valid_second = 0x80 <= second <= 0x8F
            else:
                valid_second = 0x80 <= second <= 0xBF
            if (
                not valid_second
                or not 0x80 <= third <= 0xBF
                or not 0x80 <= fourth <= 0xBF
            ):
                offsets.append(i)
                i += 1
                continue
            i += 4
        else:
            offsets.append(i)
            i += 1
    return offsets


def strip_prompt_markup(value: str) -> str:
    value = re.sub(r"%\{.*?%\}", "", value)
    value = re.sub(r"%[BbUuSsfk]", "", value)
    value = re.sub(r"%[FK]\{.*?\}", "", value)
    return value


def render_path_for(
    logical_dir: Path, cache_home: Path, before_render: str = ""
) -> dict[str, str]:
    script = r"""
cd "$1" || exit 2
source "$2"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_AI_CANDY_PROMPT_PATH_SEP_MODE=0
eval "$3"
_ai_candy_prompt_bump_render_id
_ai_candy_get_cached_git_root
_AI_CANDY_PP_CACHED_GIT_ROOT="$REPLY"
_ai_candy_get_git_hierarchy
hierarchy="$REPLY"
print -r -- "HIER=${hierarchy//$_AI_CANDY_GIT_HIERARCHY_SEP/|}"
_ai_candy_compute_smart_path_direct full
print -r -- "PATH=$_AI_CANDY_PP_PATH"
"""
    result = subprocess.run(
        ["zsh", "-fc", script, "zsh", str(logical_dir), str(THEME), before_render],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={**os.environ, "XDG_CACHE_HOME": str(cache_home)},
    )
    if result.returncode != 0:
        raise AssertionError(
            f"path renderer exited with {result.returncode}\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )

    output: dict[str, str] = {}
    for line in result.stdout.splitlines():
        key, _, value = line.partition("=")
        output[key] = value
    return output


def run_git(args: list[str], cwd: Path) -> None:
    subprocess.run(["git", "-C", str(cwd), *args], check=True)


def make_repo_ahead_of_upstream(root: Path) -> Path:
    remote = root / "remote.git"
    work = root / "work"

    subprocess.run(["git", "init", "--bare", "-q", str(remote)], check=True)
    subprocess.run(["git", "init", "-q", str(work)], check=True)
    run_git(["config", "user.email", "test@example.com"], work)
    run_git(["config", "user.name", "Test User"], work)
    run_git(["switch", "-q", "-c", "main"], work)
    run_git(["remote", "add", "origin", str(remote)], work)

    (work / "tracked.txt").write_text("one\n", encoding="utf-8")
    run_git(["add", "tracked.txt"], work)
    run_git(["commit", "-q", "-m", "initial"], work)
    run_git(["push", "-q", "-u", "origin", "main"], work)

    (work / "tracked.txt").write_text("one\ntwo\n", encoding="utf-8")
    run_git(["commit", "-q", "-am", "second"], work)
    return work


def render_git_ext_around_push(work: Path, cache_home: Path) -> dict[str, str]:
    script = r"""
cd "$1" || exit 2
source "$2"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_AI_CANDY_PROMPT_EMOJI_MODE=1
_ai_candy_prompt_bump_render_id
_ai_candy_get_cached_git_root
_AI_CANDY_PP_CACHED_GIT_ROOT="$REPLY"
_ai_candy_compute_git_extended_direct
print -r -- "BEFORE=$_AI_CANDY_PP_GIT_EXT"
for fn in "${preexec_functions[@]}"; do
  "$fn" "git push" "git push" "git push"
done
git push -q
push_status=$?
_AI_CANDY_LAST_EXIT_STATUS=$push_status
for fn in "${precmd_functions[@]}"; do
  [[ "$fn" == "_ai_candy_capture_exit_status" ]] && continue
  "$fn"
done
print -r -- "PUSH_STATUS=$push_status"
print -r -- "AFTER=$_AI_CANDY_PP_GIT_EXT"
"""
    result = subprocess.run(
        ["zsh", "-fc", script, "zsh", str(work), str(THEME)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={**os.environ, "XDG_CACHE_HOME": str(cache_home)},
    )

    output: dict[str, str] = {}
    for line in result.stdout.splitlines():
        key, _, value = line.partition("=")
        output[key] = value
    return output


def run_public_ip_refresh_with_slow_curl(cache_home: Path, bin_dir: Path) -> None:
    script = r"""
source "$1"
_AI_CANDY_NETWORK_TIMEOUT=1
_AI_CANDY_HAS_CURL=1
rm -f "$_AI_CANDY_PUBLIC_IP_CACHE_FILE"
rmdir "${_AI_CANDY_PUBLIC_IP_UPDATING}.d" 2>/dev/null
_ai_candy_public_ip_update_background
deadline=$(( EPOCHSECONDS + 5 ))
while [[ ! -f "$_AI_CANDY_PUBLIC_IP_CACHE_FILE" && EPOCHSECONDS -lt deadline ]]; do
  sleep 0.05
done
[[ -f "$_AI_CANDY_PUBLIC_IP_CACHE_FILE" ]] || exit 3
"""
    subprocess.run(
        ["zsh", "-fc", script, "zsh", str(THEME)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={
            **os.environ,
            "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
            "XDG_CACHE_HOME": str(cache_home),
        },
    )


def write_command(bin_dir: Path, name: str, body: str) -> None:
    command = bin_dir / name
    command.write_text(f"#!/bin/sh\n{body}\n", encoding="utf-8")
    command.chmod(0o755)


def source_theme(cache_home: Path, bin_dir: Optional[Path] = None) -> None:
    env = {**os.environ, "XDG_CACHE_HOME": str(cache_home)}
    if bin_dir is not None:
        env["PATH"] = f"{bin_dir}{os.pathsep}{os.environ['PATH']}"

    script = r"""
source "$1"
print -r -- READY
"""
    subprocess.run(
        ["zsh", "-fc", script, "zsh", str(THEME)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )


def run_interactive_zsh(
    script: str,
    cache_home: Path,
    *,
    environment: Optional[dict[str, str]] = None,
    timeout: float = 5,
) -> tuple[int, str, bool]:
    child_environment = {
        **os.environ,
        "XDG_CACHE_HOME": str(cache_home),
        "TERM": "dumb",
        **(environment or {}),
    }
    child_pid, master_fd = pty.fork()
    if child_pid == 0:
        try:
            os.chdir(ROOT)
            os.execvpe(
                "zsh",
                ["zsh", "-dfi", "-c", script, "zsh", str(THEME)],
                child_environment,
            )
        finally:
            os._exit(127)

    output = bytearray()
    child_status: Optional[int] = None
    pty_open = True
    timed_out = False
    deadline = time.monotonic() + timeout
    try:
        while child_status is None:
            if pty_open:
                readable, _, _ = select.select([master_fd], [], [], 0.05)
                if readable:
                    try:
                        chunk = os.read(master_fd, 4096)
                    except OSError as error:
                        if error.errno != errno.EIO:
                            raise
                        pty_open = False
                    else:
                        if chunk:
                            output.extend(chunk)
                        else:
                            pty_open = False
            else:
                time.sleep(0.01)
            waited_pid, status = os.waitpid(child_pid, os.WNOHANG)
            if waited_pid == child_pid:
                child_status = status
            elif time.monotonic() >= deadline:
                timed_out = True
                os.kill(child_pid, 9)
                _, child_status = os.waitpid(child_pid, 0)

        while pty_open:
            readable, _, _ = select.select([master_fd], [], [], 0)
            if not readable:
                break
            try:
                chunk = os.read(master_fd, 4096)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                break
            if not chunk:
                break
            output.extend(chunk)
    finally:
        os.close(master_fd)
        if child_status is None:
            os.kill(child_pid, 9)
            _, child_status = os.waitpid(child_pid, 0)

    return (
        os.waitstatus_to_exitcode(child_status),
        output.decode("utf-8", errors="replace"),
        timed_out,
    )


def render_first_prompt(cache_home: Path, bin_dir: Optional[Path] = None) -> float:
    prompt_cache = cache_home / "zsh-prompt"
    prompt_cache.mkdir(parents=True, exist_ok=True)
    (prompt_cache / "network_mode").write_text("0\n", encoding="ascii")
    env = {**os.environ, "XDG_CACHE_HOME": str(cache_home)}
    if bin_dir is not None:
        env["PATH"] = f"{bin_dir}{os.pathsep}{os.environ['PATH']}"

    script = r"""
source "$1"
start=$EPOCHREALTIME
for fn in "${precmd_functions[@]}"; do
  "$fn"
done
elapsed=$(( EPOCHREALTIME - start ))
print -r -- "ELAPSED=${elapsed}"
print -r -- READY
"""
    result = subprocess.run(
        ["zsh", "-fc", script, "zsh", str(THEME)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    for line in result.stdout.splitlines():
        if line.startswith("ELAPSED="):
            return float(line.partition("=")[2])
    raise AssertionError(f"prompt timing was not reported: {result.stdout!r}")


def elapsed_seconds(action) -> float:
    start = time.monotonic()
    action()
    return time.monotonic() - start


class ThemeSafetyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = THEME.read_text(encoding="utf-8")
        cls.data = THEME.read_bytes()

    def test_zsh_syntax_is_valid(self) -> None:
        subprocess.run(["zsh", "-n", str(THEME)], check=True)

    def test_interactive_pty_reader_stops_at_end_of_file(self) -> None:
        with (
            mock.patch.object(pty, "fork", return_value=(12345, 9)),
            mock.patch.object(
                select,
                "select",
                side_effect=[([9], [], []), ([9], [], []), ([], [], [])],
            ) as select_mock,
            mock.patch.object(os, "read", return_value=b"") as read_mock,
            mock.patch.object(os, "waitpid", return_value=(12345, 0)),
            mock.patch.object(os, "close"),
        ):
            returncode, output, timed_out = run_interactive_zsh(
                ":", Path("unused-cache")
            )

        self.assertEqual(0, returncode)
        self.assertEqual("", output)
        self.assertFalse(timed_out)
        self.assertEqual(1, read_mock.call_count)
        self.assertEqual(1, select_mock.call_count)

    def test_source_has_no_raw_terminal_control_payload(self) -> None:
        self.assertNotIn(b"\x00", self.data)
        self.assertNotIn(b"\x07", self.data)
        self.assertNotIn(b"\x1b", self.data)
        self.assertEqual([], standalone_c1_or_invalid_offsets(self.data))

    def test_source_uses_locale_independent_unicode_bytes(self) -> None:
        self.assertIsNone(re.search(r"\$'[^']*\\[uU][0-9A-Fa-f]+", self.text))

    def test_source_scanner_rejects_encoded_controls_and_malformed_utf8(self) -> None:
        self.assertIn(0, standalone_c1_or_invalid_offsets(b"\xc2\x9b"))
        self.assertIn(0, standalone_c1_or_invalid_offsets(b"\xc2"))
        self.assertIn(0, standalone_c1_or_invalid_offsets(b"\xe0\x80\x80"))
        self.assertIn(0, standalone_c1_or_invalid_offsets(b"\xf4\x90\x80\x80"))
        self.assertEqual(
            [], standalone_c1_or_invalid_offsets("plain caf\u00e9".encode("utf-8"))
        )

    def test_disowned_background_jobs_do_not_inherit_tty_stdin(self) -> None:
        offenders: list[str] = []
        for line_number, line in enumerate(self.text.splitlines(), start=1):
            code = line.split("#", 1)[0]
            if "&!" in code and "</dev/null" not in code:
                offenders.append(f"{line_number}: {line.strip()}")

        self.assertEqual([], offenders)

    def test_registered_background_worker_is_silent_in_an_interactive_tty(
        self,
    ) -> None:
        script = r"""
source "$1"
_AI_CANDY_CACHE_READY=1
function _ai_candy_test_silent_worker() {
  command sleep 5
}
_ai_candy_start_registered_background_worker _ai_candy_test_silent_worker || exit 70
builtin print -r -- WORKER_STARTED
_ai_candy_stop_registered_background_jobs
"""
        with tempfile.TemporaryDirectory() as tmp:
            returncode, rendered_output, timed_out = run_interactive_zsh(
                script, Path(tmp) / "cache"
            )

        self.assertFalse(timed_out, rendered_output)
        self.assertEqual(0, returncode, rendered_output)
        self.assertIn("WORKER_STARTED", rendered_output)
        self.assertIsNone(
            re.search(r"(?m)^\[[0-9]+\]", rendered_output),
            rendered_output,
        )

    def test_timeout_backends_are_silent_in_an_interactive_tty(self) -> None:
        backends = [
            (
                "native",
                "_ai_candy_run_native_timeout 0.05 command sleep 0.2",
                {},
            )
        ]
        external_timeout = shutil.which("timeout") or shutil.which("gtimeout")
        if external_timeout is not None:
            backends.append(
                (
                    "external",
                    '_ai_candy_run_external_timeout "$EXTERNAL_TIMEOUT" '
                    "0.05 command sleep 0.2",
                    {"EXTERNAL_TIMEOUT": external_timeout},
                )
            )

        for backend, invocation, environment in backends:
            with self.subTest(backend=backend), tempfile.TemporaryDirectory() as tmp:
                script = f'''\
source "$1"
{invocation} >/dev/null 2>&1
builtin print -r -- TIMEOUT_DONE
'''
                returncode, output, timed_out = run_interactive_zsh(
                    script,
                    Path(tmp) / "cache",
                    environment=environment,
                )

            self.assertFalse(timed_out, output)
            self.assertEqual(0, returncode, output)
            self.assertIn("TIMEOUT_DONE", output)
            self.assertIsNone(re.search(r"(?m)^\[[0-9]+\]", output), output)

    def test_tool_status_is_silent_in_an_interactive_tty(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            write_command(
                bin_dir,
                "gh",
                """case "$1" in
  --version) printf '%s\\n' 'gh version 2.0.0' ;;
  auth) /bin/sleep 0.2; exit 1 ;;
esac""",
            )
            script = r"""
source "$1"
_AI_CANDY_HAS_GH=1
_AI_CANDY_HAS_TIMEOUT=1
_AI_CANDY_TIMEOUT_CMD=zsh-native
_AI_CANDY_NETWORK_TIMEOUT=0.05
command rm -f -- "$_AI_CANDY_GH_AUTH_CACHE_FILE"
_ai_candy_prompt_tool_status >/dev/null 2>&1
builtin print -r -- TOOL_STATUS_DONE
_ai_candy_stop_registered_background_jobs
"""
            returncode, output, timed_out = run_interactive_zsh(
                script,
                root / "cache",
                environment={"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"},
            )

        self.assertFalse(timed_out, output)
        self.assertEqual(0, returncode, output)
        self.assertIn("TOOL_STATUS_DONE", output)
        self.assertIsNone(re.search(r"(?m)^\[[0-9]+\]", output), output)

    def test_github_ssh_probe_cannot_read_from_tty(self) -> None:
        ssh_lines = [
            line.strip()
            for line in self.text.splitlines()
            if "ssh " in line
            and "git@github.com" in line
            and not line.lstrip().startswith("#")
        ]

        self.assertTrue(ssh_lines)
        self.assertTrue(
            any(" -n " in f" {line} " or "StdinNull=yes" in line for line in ssh_lines),
            ssh_lines,
        )

    def test_network_timeout_is_at_most_three_seconds(self) -> None:
        match = re.search(r"typeset -g _AI_CANDY_NETWORK_TIMEOUT=(\d+)", self.text)

        self.assertIsNotNone(match)
        self.assertLessEqual(int(match.group(1)), 3)

    def test_public_ip_refresh_uses_one_timeout_budget_for_all_providers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            bin_dir = root / "bin"
            bin_dir.mkdir()
            curl = bin_dir / "curl"
            curl.write_text("#!/bin/sh\nsleep 0.4\nexit 28\n", encoding="utf-8")
            curl.chmod(0o755)

            start = time.monotonic()
            run_public_ip_refresh_with_slow_curl(cache_home, bin_dir)
            elapsed = time.monotonic() - start

            self.assertLess(elapsed, 1.35)

    def test_sqlite_initialization_does_not_block_theme_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            bin_dir = root / "bin"
            bin_dir.mkdir()
            write_command(bin_dir, "sqlite3", "sleep 1\nexit 1")

            elapsed = elapsed_seconds(lambda: source_theme(cache_home, bin_dir))

            self.assertLess(elapsed, 0.75)

    def test_slow_sqlite_does_not_block_first_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            bin_dir = root / "bin"
            completion = root / "sqlite-completed"
            bin_dir.mkdir()
            write_command(
                bin_dir,
                "sqlite3",
                f"sleep 3\nprintf completed > '{completion}'\nexit 1",
            )

            elapsed = render_first_prompt(cache_home, bin_dir)

            self.assertFalse(completion.exists())
            self.assertLess(elapsed, 1.5)

    def test_slow_git_does_not_block_first_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            calls = root / "git-calls"
            bin_dir = root / "bin"
            bin_dir.mkdir()
            write_command(
                bin_dir,
                "git",
                f"printf 'called\\n' >> '{calls}'\n"
                "printf 'file:/tmp/config\\000partial'\n"
                "sleep 1\n"
                "exit 1",
            )

            elapsed = render_first_prompt(cache_home, bin_dir)

            self.assertEqual(["called"], calls.read_text(encoding="ascii").splitlines())
            self.assertLess(elapsed, 0.75)

    def test_git_status_124_does_not_trigger_a_second_probe(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            calls = root / "git-calls"
            bin_dir = root / "bin"
            bin_dir.mkdir()
            write_command(
                bin_dir,
                "git",
                f"printf 'called\\n' >> '{calls}'\n"
                "printf 'file:/tmp/config\\000partial'\n"
                "exit 124",
            )

            render_first_prompt(cache_home, bin_dir)

            self.assertEqual(["called"], calls.read_text(encoding="ascii").splitlines())

    def test_first_prompt_performance_helper_never_starts_network_work(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            marker = root / "network-called"
            bin_dir = root / "bin"
            bin_dir.mkdir()
            write_command(
                bin_dir,
                "curl",
                f"printf called > '{marker}'\nexit 1",
            )

            render_first_prompt(cache_home, bin_dir)
            time.sleep(0.05)

            self.assertFalse(marker.exists())

    def test_slow_sysinfo_commands_do_not_block_first_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            bin_dir = root / "bin"
            completion = root / "uname-completed"
            bin_dir.mkdir()
            write_command(
                bin_dir,
                "uname",
                f"sleep 3\nprintf completed > '{completion}'\nexit 1",
            )

            elapsed = render_first_prompt(cache_home, bin_dir)

            self.assertFalse(completion.exists())
            self.assertLess(elapsed, 1.5)

    def test_ai_process_count_does_not_block_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            prompt_cache = cache_home / "zsh-prompt"
            bin_dir = root / "bin"
            prompt_cache.mkdir(parents=True)
            bin_dir.mkdir()
            sep = "\x1f"
            now = str(int(time.time()))
            for cache_name in (
                "claude_version_cache",
                "codex_version_cache",
                "gemini_version_cache",
                "kimi_version_cache",
            ):
                (prompt_cache / cache_name).write_text(
                    f"1.2.3{sep}1.2.3{sep}{now}\n",
                    encoding="utf-8",
                )
            (prompt_cache / "ai_mode").write_text("1\n", encoding="utf-8")
            (prompt_cache / "network_mode").write_text("0\n", encoding="utf-8")
            for name in ("claude", "codex", "gemini", "kimi"):
                write_command(bin_dir, name, f"printf '%s\\n' '{name} 1.2.3'")
            for name in ("pgrep", "ps"):
                write_command(bin_dir, name, "sleep 1\nexit 0")

            elapsed = render_first_prompt(cache_home, bin_dir)

            self.assertLess(elapsed, 0.75)

    def test_cache_directory_setup_does_not_block_theme_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            bin_dir = root / "bin"
            bin_dir.mkdir()
            write_command(bin_dir, "mkdir", "sleep 1\nexit 1")
            write_command(bin_dir, "chmod", "sleep 1\nexit 1")

            elapsed = elapsed_seconds(lambda: source_theme(cache_home, bin_dir))

            self.assertLess(elapsed, 0.75)

    def test_symlinked_repo_root_uses_logical_path_in_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            real_repo = root / "real" / "repo"
            logical_repo = root / "link" / "repo"
            cache_home = root / "cache"
            real_repo.mkdir(parents=True)
            logical_repo.parent.mkdir()
            subprocess.run(["git", "-C", str(real_repo), "init", "-q"], check=True)
            logical_repo.symlink_to(real_repo)

            output = render_path_for(logical_repo, cache_home)

            self.assertEqual(f"{logical_repo}|", output["HIER"])
            self.assertEqual(f"[{logical_repo}]", strip_prompt_markup(output["PATH"]))
            self.assertNotIn(str(real_repo), output["HIER"])

    def test_symlinked_repo_subdir_uses_logical_path_in_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            real_repo = root / "real" / "repo"
            logical_repo = root / "link" / "repo"
            logical_subdir = logical_repo / "sub"
            cache_home = root / "cache"
            (real_repo / "sub").mkdir(parents=True)
            logical_repo.parent.mkdir()
            subprocess.run(["git", "-C", str(real_repo), "init", "-q"], check=True)
            logical_repo.symlink_to(real_repo)

            output = render_path_for(logical_subdir, cache_home)

            self.assertEqual(f"{logical_repo}|sub", output["HIER"])
            self.assertEqual(
                f"[{logical_repo}/sub]", strip_prompt_markup(output["PATH"])
            )
            self.assertNotIn(str(real_repo), output["HIER"])

    def test_path_display_neutralizes_terminal_control_characters(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "bad\x1b[31m\x07%F{red}"
            cache_home = root / "cache"
            repo.mkdir()
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)

            output = render_path_for(repo, cache_home)
            visible_path = strip_prompt_markup(output["PATH"])

            self.assertNotIn("\x1b", visible_path)
            self.assertNotIn("\x07", visible_path)
            self.assertIn("%%F{red}", output["PATH"])

    def test_path_display_neutralizes_unicode_direction_and_line_controls(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"

            for codepoint in (
                0x00AD,
                0x061C,
                0x180E,
                0x200B,
                0x200C,
                0x200D,
                0x2028,
                0x2029,
                0x202E,
                0x2060,
                0xFEFF,
                0xFFF9,
                0xE0001,
                0xE0020,
            ):
                with self.subTest(codepoint=hex(codepoint)):
                    control = chr(codepoint)
                    repo = root / f"repo-{codepoint:x}" / f"left{control}right"
                    repo.mkdir(parents=True)
                    subprocess.run(
                        ["git", "-C", str(repo), "init", "-q"], check=True
                    )

                    output = render_path_for(repo, cache_home)
                    visible_path = strip_prompt_markup(output["PATH"])

                    self.assertNotIn(control, visible_path)
                    self.assertIn("left?right", visible_path)

    def test_path_display_preserves_components_with_internal_separator_byte(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "left\x1fright"
            cache_home = root / "cache"
            repo.mkdir()
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)

            output = render_path_for(repo, cache_home)
            visible_path = strip_prompt_markup(output["PATH"])

            self.assertTrue(visible_path.endswith("/left?right]"), visible_path)

    def test_stale_git_hierarchy_cache_does_not_override_logical_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            real_repo = root / "real" / "repo"
            logical_repo = root / "link" / "repo"
            cache_home = root / "cache"
            real_repo.mkdir(parents=True)
            logical_repo.parent.mkdir()
            subprocess.run(["git", "-C", str(real_repo), "init", "-q"], check=True)
            logical_repo.symlink_to(real_repo)

            stale_cache = (
                f"bad='{real_repo}'\"$_AI_CANDY_GIT_HIERARCHY_SEP\"'{logical_repo}'; "
                '_AI_CANDY_MEM_CACHE_GIT_HIERARCHY[$PWD]="$bad|$EPOCHSECONDS"'
            )
            output = render_path_for(logical_repo, cache_home, stale_cache)

            self.assertEqual(f"{logical_repo}|", output["HIER"])
            self.assertEqual(f"[{logical_repo}]", strip_prompt_markup(output["PATH"]))
            self.assertNotIn(str(real_repo), output["HIER"])

    def test_git_push_refreshes_cached_ahead_count_before_next_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = make_repo_ahead_of_upstream(root)
            cache_home = root / "cache"

            output = render_git_ext_around_push(work, cache_home)

            self.assertEqual("0", output["PUSH_STATUS"])
            self.assertEqual("\u21911", strip_prompt_markup(output["BEFORE"]))
            self.assertEqual("", strip_prompt_markup(output["AFTER"]))


if __name__ == "__main__":
    unittest.main()
