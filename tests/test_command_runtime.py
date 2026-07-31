#!/usr/bin/env python3
import hashlib
import os
import shutil
import tempfile
import unittest
from pathlib import Path

from tests.theme_test_support import run_zsh


class CommandRuntimeTest(unittest.TestCase):
    def test_sleep_ticks_is_safe_with_errexit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
setopt errexit
_ai_candy_sleep_ticks 1
builtin print -r -- survived
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("survived\n", result.stdout)

    def test_optional_tool_detection_requires_external_executables(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            empty_bin = root / "bin"
            empty_bin.mkdir()
            result = run_zsh(
                r"""
function claude() { return 0; }
function codex() { return 0; }
function gemini() { return 0; }
function kimi() { return 0; }
path=("$EMPTY_BIN")
rehash
source "$1"
_ai_candy_prompt_refresh_all_caches >/dev/null
print -r -- "TOOLS=${_AI_CANDY_HAS_CLAUDE}${_AI_CANDY_HAS_CODEX}${_AI_CANDY_HAS_GEMINI}${_AI_CANDY_HAS_KIMI}"
""",
                cache_home=root / "cache",
                env={"EMPTY_BIN": str(empty_bin)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("TOOLS=0000\n", result.stdout)

    def test_theme_source_does_not_call_a_shadowed_module_loader(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shadow_log = root / "shadowed"
            result = run_zsh(
                r"""
function zmodload() { print -r -- called >| "$SHADOW_LOG"; }
source "$1"
print -r -- "SHADOWED=$([[ -f $SHADOW_LOG ]] && print yes || print no)"
""",
                cache_home=root / "cache",
                env={"SHADOW_LOG": str(shadow_log)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("SHADOWED=no\n", result.stdout)

    def test_native_timeout_uses_unshadowed_zsh_primitives(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shadow_log = root / "shadowed"
            result = run_zsh(
                r"""
source "$1"
function kill() { print -r -- kill >> "$SHADOW_LOG"; }
function zselect() { command sleep 1; }
_AI_CANDY_TIMEOUT_CMD=zsh-native
start=$EPOCHREALTIME
_ai_candy_run_with_timeout 0.05 /bin/sleep 1
command_status=$?
elapsed=$(( EPOCHREALTIME - start ))
print -r -- "STATUS=${command_status}"
print -r -- "ELAPSED=${elapsed}"
print -r -- "SHADOWED=$([[ -f $SHADOW_LOG ]] && print yes || print no)"
""",
                cache_home=root / "cache",
                env={"SHADOW_LOG": str(shadow_log)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("STATUS=124", result.stdout)
        self.assertIn("SHADOWED=no", result.stdout)
        elapsed_line = next(
            line for line in result.stdout.splitlines() if line.startswith("ELAPSED=")
        )
        self.assertLess(float(elapsed_line.partition("=")[2]), 0.5)

    def test_external_timeout_is_absolute_and_kills_term_ignoring_commands(
        self,
    ) -> None:
        if shutil.which("timeout") is None:
            self.skipTest("GNU-compatible timeout is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
function timeout() { print -r -- SHADOWED; }
source "$1"
_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
_ai_candy_detect_core_commands
functions[$_AI_CANDY_TIMEOUT_CMD]='print -r -- SHADOWED'
print -r -- "COMMAND=${_AI_CANDY_TIMEOUT_CMD}"
start=$EPOCHREALTIME
_ai_candy_run_with_timeout 0.1 sh -c 'trap "" TERM; while :; do :; done'
command_status=$?
elapsed=$(( EPOCHREALTIME - start ))
print -r -- "STATUS=${command_status}"
print -r -- "ELAPSED=${elapsed}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        command_line = next(
            line for line in result.stdout.splitlines() if line.startswith("COMMAND=")
        )
        self.assertTrue(command_line.partition("=")[2].startswith("/"), result.stdout)
        self.assertNotIn("SHADOWED", result.stdout)
        status_line = next(
            line for line in result.stdout.splitlines() if line.startswith("STATUS=")
        )
        self.assertIn(int(status_line.partition("=")[2]), (124, 137))
        elapsed_line = next(
            line for line in result.stdout.splitlines() if line.startswith("ELAPSED=")
        )
        self.assertLess(float(elapsed_line.partition("=")[2]), 0.7)

    def test_external_timeout_bounds_captured_output(self) -> None:
        external_timeout = shutil.which("timeout")
        if external_timeout is None:
            self.skipTest("GNU-compatible timeout is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_TIMEOUT_CMD="$EXTERNAL_TIMEOUT"
_AI_CANDY_TIMEOUT_OUTPUT_MAX_BYTES=4096
output=$(_ai_candy_run_with_timeout 2 sh -c '
  i=0
  while [ "$i" -lt 128 ]; do
    printf 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    i=$((i + 1))
  done
')
command_status=$?
setopt null_glob
artifacts=("${_AI_CANDY_CACHE_DIR}"/ai-candy-timeout.*(N))
print -r -- "STATUS=${command_status} BYTES=${#output} ARTIFACTS=${#artifacts}"
""",
                cache_home=Path(tmp) / "cache",
                env={"EXTERNAL_TIMEOUT": external_timeout},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(
            field.split("=", maxsplit=1) for field in result.stdout.strip().split()
        )
        self.assertEqual("125", fields["STATUS"])
        self.assertEqual(4096, int(fields["BYTES"]))
        self.assertEqual("0", fields["ARTIFACTS"])

    def test_external_timeout_fallback_preserves_small_multiline_output(self) -> None:
        external_timeout = shutil.which("timeout")
        if external_timeout is None:
            self.skipTest("GNU-compatible timeout is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_TIMEOUT_CMD="$EXTERNAL_TIMEOUT"
output=$(_ai_candy_run_with_timeout 2 sh -c 'printf "alpha\\nbeta\\n"')
command_status=$?
print -r -- "STATUS=${command_status}"
print -r -- "$output"
""",
                cache_home=Path(tmp) / "cache",
                env={"EXTERNAL_TIMEOUT": external_timeout},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=0\nalpha\nbeta\n", result.stdout)

    def test_external_timeout_fallback_preserves_combined_stderr_status(self) -> None:
        external_timeout = shutil.which("timeout")
        if external_timeout is None:
            self.skipTest("GNU-compatible timeout is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_TIMEOUT_CMD="$EXTERNAL_TIMEOUT"
output=$(_ai_candy_run_with_timeout_combined_output 2 sh -c '
  printf diagnostic >&2
  exit 7
')
print -r -- "STATUS=$? OUTPUT=${output}"
""",
                cache_home=Path(tmp) / "cache",
                env={"EXTERNAL_TIMEOUT": external_timeout},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=7 OUTPUT=diagnostic\n", result.stdout)

    def test_stale_timeout_cleanup_processes_one_bounded_batch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
for index in {1..64}; do
  print -r -- stale >| \
    "${_AI_CANDY_CACHE_DIR}/ai-candy-timeout.$((900000000 + index)).artifact"
done
_ai_candy_cleanup_stale_timeout_files "$_AI_CANDY_CACHE_DIR"
setopt null_glob
artifacts=("${_AI_CANDY_CACHE_DIR}"/ai-candy-timeout.*(N))
print -r -- "REMOVED=$((64 - ${#artifacts})) REMAINING=${#artifacts}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("REMOVED=16 REMAINING=48\n", result.stdout)

    def test_output_cap_does_not_limit_files_written_by_the_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "command-output"
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_TIMEOUT_OUTPUT_MAX_BYTES=4096
output=$(_ai_candy_run_with_timeout 2 sh -c '
  dd if=/dev/zero of="$1" bs=1024 count=16 2>/dev/null
  printf complete
' sh "$TARGET_FILE")
command_status=$?
file_bytes=$(command wc -c < "$TARGET_FILE")
print -r -- "STATUS=${command_status} OUTPUT=${output} FILE_BYTES=${file_bytes// /}"
""",
                cache_home=root / "cache",
                env={"TARGET_FILE": str(target)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "STATUS=0 OUTPUT=complete FILE_BYTES=16384\n",
            result.stdout,
        )

    def test_bounded_output_reports_a_capture_write_failure(self) -> None:
        if not Path("/dev/full").exists():
            self.skipTest("this platform does not provide /dev/full")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_ai_candy_run_bounded_output_command /dev/full 4096 sh -c 'printf captured'
print -r -- "STATUS=$?"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertNotEqual("STATUS=0\n", result.stdout)

    def test_combined_timeout_preserves_small_stderr_and_status(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
output=$(_ai_candy_run_with_timeout_combined_output 2 sh -c '
  printf diagnostic >&2
  exit 7
')
print -r -- "STATUS=$? OUTPUT=${output}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=7 OUTPUT=diagnostic\n", result.stdout)

    def test_combined_timeout_bounds_stderr(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_TIMEOUT_OUTPUT_MAX_BYTES=4096
output=$(_ai_candy_run_with_timeout_combined_output 2 sh -c '
  i=0
  while [ "$i" -lt 128 ]; do
    printf 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef >&2
    i=$((i + 1))
  done
')
command_status=$?
print -r -- "STATUS=${command_status} BYTES=${#output}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(
            field.split("=", maxsplit=1) for field in result.stdout.strip().split()
        )
        self.assertEqual("125", fields["STATUS"])
        self.assertEqual(4096, int(fields["BYTES"]))

    def test_hash_helper_uses_an_external_executable(self) -> None:
        if shutil.which("sha256sum") is None:
            self.skipTest("sha256sum is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
function sha256sum() { print -r -- FORGED; }
function printf() { print -r -- FORGED; }
source "$1"
functions[$_AI_CANDY_HASH_CMD]='print -r -- FORGED'
print -r -- "COMMAND=${_AI_CANDY_HASH_CMD}"
_ai_candy_hash_string abc
print -r -- "HASH=${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        command_line = next(
            line for line in result.stdout.splitlines() if line.startswith("COMMAND=")
        )
        self.assertTrue(command_line.partition("=")[2].startswith("/"), result.stdout)
        self.assertNotIn("FORGED", result.stdout)
        self.assertIn(f"HASH={hashlib.sha256(b'abc').hexdigest()}\n", result.stdout)

    def test_hash_helper_bounds_a_stalled_executable(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            hash_tool = root / "sha256sum"
            hash_tool.write_text(
                "#!/bin/sh\n"
                "/bin/cat >/dev/null\n"
                "/bin/sleep 1\n"
                "printf '%064d  -\\n' 0\n",
                encoding="ascii",
            )
            hash_tool.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HASH_CMD="$HASH_TOOL"
_AI_CANDY_HAS_HASH_CMD=1
_AI_CANDY_LOCAL_PROMPT_TIMEOUT=0.1
start_time=$EPOCHREALTIME
_ai_candy_hash_string https://example.invalid/repository.git
elapsed_ms=$(( (EPOCHREALTIME - start_time) * 1000 ))
builtin printf 'HASH=%s ELAPSED_MS=%.3f\n' "$REPLY" "$elapsed_ms"
""",
                cache_home=root / "cache",
                env={"HASH_TOOL": str(hash_tool)},
                timeout=3,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(item.split("=", 1) for item in result.stdout.split())
        self.assertEqual("", fields["HASH"])
        self.assertLess(float(fields["ELAPSED_MS"]), 700.0, result.stdout)

    def test_hash_helper_rejects_an_incomplete_digest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            hash_tool = root / "sha256sum"
            hash_tool.write_text(
                "#!/bin/sh\nprintf '%s  -\\n' abcdef\n",
                encoding="ascii",
            )
            hash_tool.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HASH_CMD="$HASH_TOOL"
_AI_CANDY_HAS_HASH_CMD=1
_ai_candy_hash_string input
builtin print -r -- "HASH=${REPLY}"
""",
                cache_home=root / "cache",
                env={"HASH_TOOL": str(hash_tool)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("HASH=\n", result.stdout)

    def test_external_resolver_skips_relative_path_entries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            relative_bin = root / "relative-bin"
            trusted_bin = root / "trusted-bin"
            work_dir = root / "work"
            relative_bin.mkdir()
            trusted_bin.mkdir()
            work_dir.mkdir()
            relative_helper = relative_bin / "theme-helper"
            relative_helper.write_text(
                "#!/bin/sh\nprintf '%s\\n' relative\n", encoding="ascii"
            )
            relative_helper.chmod(0o755)
            trusted_helper = trusted_bin / "theme-helper"
            trusted_helper.write_text(
                "#!/bin/sh\nprintf '%s\\n' trusted\n", encoding="ascii"
            )
            trusted_helper.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_ai_candy_resolve_external_command theme-helper
print -r -- "COMMAND=${REPLY}"
output=$(_ai_candy_run_with_timeout 0.5 theme-helper)
print -r -- "OUTPUT=${output}"
""",
                cache_home=root / "cache",
                cwd=work_dir,
                env={
                    "PATH": (
                        f"../relative-bin{os.pathsep}{trusted_bin}"
                        f"{os.pathsep}{os.environ['PATH']}"
                    )
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn(f"COMMAND={trusted_helper}\n", result.stdout)
        self.assertIn("OUTPUT=trusted\n", result.stdout)


if __name__ == "__main__":
    unittest.main()
