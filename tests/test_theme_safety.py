#!/usr/bin/env python3
import subprocess
import unittest
from pathlib import Path


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
            i += 2
        elif 0xE0 <= byte <= 0xEF:
            i += 3
        elif 0xF0 <= byte <= 0xF4:
            i += 4
        else:
            offsets.append(i)
            i += 1
    return offsets


class ThemeSafetyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = THEME.read_text(encoding="utf-8")
        cls.data = THEME.read_bytes()

    def test_zsh_syntax_is_valid(self) -> None:
        subprocess.run(["zsh", "-n", str(THEME)], check=True)

    def test_source_has_no_raw_terminal_control_payload(self) -> None:
        self.assertNotIn(b"\x00", self.data)
        self.assertNotIn(b"\x07", self.data)
        self.assertNotIn(b"\x1b", self.data)
        self.assertEqual([], standalone_c1_or_invalid_offsets(self.data))

    def test_disowned_background_jobs_do_not_inherit_tty_stdin(self) -> None:
        offenders: list[str] = []
        for line_number, line in enumerate(self.text.splitlines(), start=1):
            code = line.split("#", 1)[0]
            if "&!" in code and "</dev/null" not in code:
                offenders.append(f"{line_number}: {line.strip()}")

        self.assertEqual([], offenders)

    def test_github_ssh_probe_cannot_read_from_tty(self) -> None:
        ssh_lines = [
            line.strip()
            for line in self.text.splitlines()
            if "ssh " in line and "git@github.com" in line and not line.lstrip().startswith("#")
        ]

        self.assertTrue(ssh_lines)
        self.assertTrue(
            any(" -n " in f" {line} " or "StdinNull=yes" in line for line in ssh_lines),
            ssh_lines,
        )


if __name__ == "__main__":
    unittest.main()
