#!/usr/bin/env python3
import os
import re
import subprocess
import tempfile
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


def strip_prompt_markup(value: str) -> str:
    value = re.sub(r"%\{.*?%\}", "", value)
    value = re.sub(r"%[BbUuSsfk]", "", value)
    value = re.sub(r"%[FK]\{.*?\}", "", value)
    return value


def render_path_for(logical_dir: Path, cache_home: Path) -> dict[str, str]:
    script = r"""
cd "$1" || exit 2
source "$2"
_PROMPT_NETWORK_MODE=0
_PROMPT_AI_MODE=0
_PROMPT_OS_MODE=0
_PROMPT_PATH_SEP_MODE=0
_prompt_bump_render_id
_PP_CACHED_GIT_ROOT=$(_get_cached_git_root)
hierarchy=$(_get_git_hierarchy)
print -r -- "HIER=${hierarchy//$_GIT_HIERARCHY_SEP/|}"
_compute_smart_path_direct full
print -r -- "PATH=$_PP_PATH"
"""
    result = subprocess.run(
        ["zsh", "-fc", script, "zsh", str(logical_dir), str(THEME)],
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
            self.assertEqual(f"[{logical_repo}/sub]", strip_prompt_markup(output["PATH"]))
            self.assertNotIn(str(real_repo), output["HIER"])


if __name__ == "__main__":
    unittest.main()
