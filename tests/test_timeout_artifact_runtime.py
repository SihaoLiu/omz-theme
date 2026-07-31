#!/usr/bin/env python3
import os
import tempfile
import unittest
from pathlib import Path

from tests.theme_test_support import run_zsh


class TimeoutArtifactRuntimeTest(unittest.TestCase):
    def test_native_timeout_refuses_a_symlinked_marker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            output_file = root / "timeout-output"
            marker_file = root / "timeout-output.expired"
            victim_file = root / "victim"
            victim_file.write_text("private\n", encoding="ascii")
            marker_file.symlink_to(victim_file)
            result = run_zsh(
                r"""
source "$1"
function _ai_candy_create_timeout_output_file() {
  : >| "$TEST_OUTPUT_FILE"
  REPLY="$TEST_OUTPUT_FILE"
}
_AI_CANDY_TIMEOUT_CMD=zsh-native
_ai_candy_run_with_timeout 0.05 sleep 1
print -r -- "STATUS=$?"
""",
                cache_home=root / "cache",
                env={"TEST_OUTPUT_FILE": str(output_file)},
            )
            victim_content = victim_file.read_text(encoding="ascii")

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("STATUS=124", result.stdout)
        self.assertEqual("private\n", victim_content)

    def test_timeout_fallback_removes_stale_private_output(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            private_temp = root / f"ai-candy-{os.geteuid()}"
            private_temp.mkdir(mode=0o700)
            stale_file = private_temp / "ai-candy-timeout.99999999.1"
            stale_file.write_text("private output\n", encoding="ascii")
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_READY=0
_AI_CANDY_TIMEOUT_STALE_FILES_SCANNED=0
_ai_candy_create_timeout_output_file || return 70
output_file="$REPLY"
if [[ -e "$STALE_FILE" || -L "$STALE_FILE" ]]; then
  stale_state=present
else
  stale_state=missing
fi
_ai_candy_remove_timeout_files "$output_file"
print -r -- "STALE=${stale_state}"
""",
                cache_home=root / "cache",
                env={"STALE_FILE": str(stale_file), "TMPDIR": str(root)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STALE=missing\n", result.stdout)

    def test_native_timeout_bounds_captured_output_and_removes_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_TIMEOUT_OUTPUT_MAX_BYTES=4096
output=$(_ai_candy_run_with_timeout 2 sh -c '
  i=0
  while [ "$i" -lt 16384 ]; do
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
                timeout=8,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(
            field.split("=", maxsplit=1) for field in result.stdout.strip().split()
        )
        self.assertNotEqual("0", fields["STATUS"])
        self.assertLessEqual(int(fields["BYTES"]), 4096)
        self.assertEqual("0", fields["ARTIFACTS"])


if __name__ == "__main__":
    unittest.main()
