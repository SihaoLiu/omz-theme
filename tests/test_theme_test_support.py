#!/usr/bin/env python3
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tests.theme_test_support import run_zsh


class ThemeTestSupportTest(unittest.TestCase):
    def test_run_zsh_ignores_ambient_git_configuration(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ambient_home = root / "ambient-home"
            ambient_home.mkdir()
            config = ambient_home / ".gitconfig"
            config.write_text("[oh-my-zsh]\n\thide-info = 1\n", encoding="ascii")
            ambient = {
                "HOME": str(ambient_home),
                "XDG_CONFIG_HOME": str(ambient_home / "config"),
                "GIT_CONFIG_GLOBAL": str(config),
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "oh-my-zsh.hide-dirty",
                "GIT_CONFIG_VALUE_0": "1",
            }
            with mock.patch.dict(os.environ, ambient, clear=False):
                result = run_zsh(
                    r"""
hide_info=$(command git config --get oh-my-zsh.hide-info 2>/dev/null) || \
  hide_info=absent
hide_dirty=$(command git config --get oh-my-zsh.hide-dirty 2>/dev/null) || \
  hide_dirty=absent
print -r -- "CONFIG=${hide_info}:${hide_dirty}"
""",
                    cache_home=root / "cache",
                )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CONFIG=absent:absent\n", result.stdout)


if __name__ == "__main__":
    unittest.main()
