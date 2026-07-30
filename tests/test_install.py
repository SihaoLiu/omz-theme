#!/usr/bin/env python3
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Optional


ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "install.sh"
THEME = ROOT / "ai-candy.zsh-theme"
THEME_URL = (
    "https://raw.githubusercontent.com/SihaoLiu/ai-candy/"
    "refs/heads/main/ai-candy.zsh-theme"
)
THEME_MAX_BYTES = 1048576


class InstallerTest(unittest.TestCase):
    def prepare_installation(self, root: Path) -> tuple[Path, Path, Path, Path]:
        home = root / "home"
        omz = root / "oh-my-zsh"
        fake_bin = root / "bin"
        curl_log = root / "curl.log"
        home.mkdir()
        fake_bin.mkdir()
        (omz / "templates").mkdir(parents=True)
        (omz / "oh-my-zsh.sh").write_text("# fixture\n", encoding="ascii")
        (omz / "templates" / "zshrc.zsh-template").write_text(
            'ZSH_THEME="robbyrussell"\nsource "$ZSH/oh-my-zsh.sh"\n',
            encoding="ascii",
        )
        curl = fake_bin / "curl"
        curl.write_text(
            "#!/bin/sh\n"
            "output=\n"
            "url=\n"
            "secure_protocol=0\n"
            "secure_redirect=0\n"
            "connect_timeout=0\n"
            "total_timeout=0\n"
            "max_filesize=0\n"
            'while [ "$#" -gt 0 ]; do\n'
            '  case "$1" in\n'
            "    -o) shift; output=$1 ;;\n"
            "    --proto) shift; [ \"$1\" = '=https' ] && secure_protocol=1 ;;\n"
            "    --proto-redir) shift; [ \"$1\" = '=https' ] && secure_redirect=1 ;;\n"
            '    --connect-timeout) shift; [ "$1" -gt 0 ] && connect_timeout=1 ;;\n'
            '    --max-time) shift; [ "$1" -gt 0 ] && total_timeout=1 ;;\n'
            '    --max-filesize) shift; [ "$1" -eq 1048576 ] && max_filesize=1 ;;\n'
            "    http://*|https://*) url=$1 ;;\n"
            "  esac\n"
            "  shift\n"
            "done\n"
            '[ "$secure_protocol$secure_redirect$connect_timeout$total_timeout$max_filesize" = 11111 ] || exit 64\n'
            '[ "$(ulimit -f)" -le 2048 ] || exit 64\n'
            'printf \'%s\\n\' "$url" > "$CURL_LOG"\n'
            'if [ "${FAIL_DOWNLOAD:-0}" = 1 ]; then\n'
            '  printf partial > "$output"\n'
            "  exit 22\n"
            "fi\n"
            'if [ "${BYPASS_FILE_LIMIT:-0}" = 1 ]; then\n'
            '  rm -f "$output"\n'
            '  ln "$DOWNLOAD_SOURCE" "$output"\n'
            "  exit 0\n"
            "fi\n"
            'cp "$DOWNLOAD_SOURCE" "$output"\n',
            encoding="ascii",
        )
        curl.chmod(0o755)
        return home, omz, fake_bin, curl_log

    def run_installer(
        self,
        root: Path,
        *arguments: str,
        zshrc_text: Optional[str] = None,
        extra_env: Optional[dict[str, str]] = None,
        existing_theme: Optional[bytes] = None,
        stdin_text: Optional[str] = None,
    ) -> subprocess.CompletedProcess[str]:
        home, omz, fake_bin, curl_log = self.prepare_installation(root)
        if zshrc_text is not None:
            (home / ".zshrc").write_text(zshrc_text, encoding="ascii")
        if existing_theme is not None:
            theme_dir = omz / "custom" / "themes"
            theme_dir.mkdir(parents=True)
            (theme_dir / THEME.name).write_bytes(existing_theme)
        env = {
            **os.environ,
            "HOME": str(home),
            "ZSH": str(omz),
            "PATH": f"{fake_bin}:/usr/bin:/bin",
            "CURL_LOG": str(curl_log),
            "DOWNLOAD_SOURCE": str(THEME),
        }
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            ["sh", str(INSTALLER), *arguments],
            cwd=root,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            input=stdin_text,
            check=False,
        )

    def test_installer_uses_posix_shell_syntax(self) -> None:
        result = subprocess.run(
            ["sh", "-n", str(INSTALLER)],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

        self.assertEqual(0, result.returncode, result.stderr)

        installer = INSTALLER.read_text(encoding="ascii")
        self.assertIn('-o "$theme_temp" -- "$theme_url"', installer)

    def test_installer_does_not_rewrite_an_existing_zshrc(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / "home"
            original_zshrc = (
                'export ZSH="$HOME/.oh-my-zsh"\n'
                'ZSH_THEME="robbyrussell"\n'
                'source "$ZSH/oh-my-zsh.sh"\n'
            )
            result = self.run_installer(root, zshrc_text=original_zshrc)
            zshrc = home / ".zshrc"
            target = root / "oh-my-zsh" / "custom" / "themes" / THEME.name
            backup = home / ".zshrc.ai-candy-backup"

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(THEME.read_bytes(), target.read_bytes())
            self.assertEqual(0o644, target.stat().st_mode & 0o777)
            self.assertEqual(original_zshrc, zshrc.read_text(encoding="ascii"))
            self.assertFalse(backup.exists())
            self.assertIn('set ZSH_THEME="ai-candy" manually', result.stderr)
            self.assertEqual(THEME_URL + "\n", (root / "curl.log").read_text())
            self.assertEqual([], list(target.parent.glob(".ai-candy.*")))

    def test_installer_creates_zshrc_from_the_omz_template(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / "home"
            result = self.run_installer(root)
            zshrc = home / ".zshrc"

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(
                'ZSH_THEME="ai-candy"\nsource "$ZSH/oh-my-zsh.sh"\n',
                zshrc.read_text(encoding="ascii"),
            )
            self.assertFalse((home / ".zshrc.ai-candy-backup").exists())

    def test_download_failure_preserves_existing_theme(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home, omz, fake_bin, curl_log = self.prepare_installation(root)
            theme_dir = omz / "custom" / "themes"
            theme_dir.mkdir(parents=True)
            target = theme_dir / THEME.name
            target.write_text("existing\n", encoding="ascii")
            result = subprocess.run(
                ["sh", str(INSTALLER)],
                cwd=root,
                env={
                    **os.environ,
                    "HOME": str(home),
                    "ZSH": str(omz),
                    "PATH": f"{fake_bin}:/usr/bin:/bin",
                    "CURL_LOG": str(curl_log),
                    "DOWNLOAD_SOURCE": str(THEME),
                    "FAIL_DOWNLOAD": "1",
                },
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertNotEqual(0, result.returncode)
            self.assertEqual("existing\n", target.read_text(encoding="ascii"))
            self.assertEqual([], list(theme_dir.glob(".ai-candy.*")))

    def test_oversized_download_preserves_existing_theme(self) -> None:
        previous_theme = b"existing theme\n"

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            download = root / "oversized-theme"
            download.write_bytes(b"X" * (THEME_MAX_BYTES + 1))
            result = self.run_installer(
                root,
                "--no-modify-zshrc",
                existing_theme=previous_theme,
                extra_env={
                    "BYPASS_FILE_LIMIT": "1",
                    "DOWNLOAD_SOURCE": str(download),
                },
            )
            theme_dir = root / "oh-my-zsh" / "custom" / "themes"
            target = theme_dir / THEME.name

            self.assertNotEqual(0, result.returncode)
            self.assertIn("downloaded theme exceeds size limit", result.stderr)
            self.assertEqual(previous_theme, target.read_bytes())
            self.assertEqual([], list(theme_dir.glob(f"{THEME.name}.backup.*")))
            self.assertEqual([], list(theme_dir.glob(".ai-candy.*")))

    def test_file_limit_stops_an_oversized_download(self) -> None:
        previous_theme = b"existing theme\n"

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            download = root / "oversized-theme"
            download.write_bytes(b"X" * (THEME_MAX_BYTES + 1))
            result = self.run_installer(
                root,
                "--no-modify-zshrc",
                existing_theme=previous_theme,
                extra_env={"DOWNLOAD_SOURCE": str(download)},
            )
            theme_dir = root / "oh-my-zsh" / "custom" / "themes"
            target = theme_dir / THEME.name

            self.assertNotEqual(0, result.returncode)
            self.assertIn("theme download failed", result.stderr)
            self.assertEqual(previous_theme, target.read_bytes())
            self.assertEqual([], list(theme_dir.glob(f"{THEME.name}.backup.*")))
            self.assertEqual([], list(theme_dir.glob(".ai-candy.*")))

    def test_invalid_downloads_preserve_existing_theme(self) -> None:
        payloads = {
            "empty": b"",
            "wrong-file": b"#!/bin/sh\nexit 0\n",
            "incomplete-theme": (
                b"#!/bin/sh\n# AI Candy - Oh My Zsh Theme\nexit 0\n"
            ),
            "invalid-zsh": (
                b"#!/bin/sh\n"
                b"# AI Candy - Oh My Zsh Theme\n"
                b"builtin unfunction _ai_candy_restore_source_options\n"
                b"if then\n"
            ),
        }
        previous_theme = b"existing theme\n"

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name, payload in payloads.items():
                with self.subTest(payload=name):
                    case_root = root / name
                    case_root.mkdir()
                    download = case_root / "download"
                    download.write_bytes(payload)
                    result = self.run_installer(
                        case_root,
                        "--no-modify-zshrc",
                        existing_theme=previous_theme,
                        extra_env={"DOWNLOAD_SOURCE": str(download)},
                    )
                    theme_dir = (
                        case_root / "oh-my-zsh" / "custom" / "themes"
                    )
                    target = theme_dir / THEME.name

                    self.assertNotEqual(0, result.returncode)
                    self.assertEqual(previous_theme, target.read_bytes())
                    self.assertEqual(
                        [], list(theme_dir.glob(f"{THEME.name}.backup.*"))
                    )
                    self.assertEqual([], list(theme_dir.glob(".ai-candy.*")))

    def test_installer_refuses_a_symbolic_link_theme_target(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home, omz, fake_bin, curl_log = self.prepare_installation(root)
            theme_dir = omz / "custom" / "themes"
            theme_dir.mkdir(parents=True)
            victim = root / "victim"
            victim.write_text("private\n", encoding="ascii")
            (theme_dir / THEME.name).symlink_to(victim)
            result = subprocess.run(
                ["sh", str(INSTALLER)],
                cwd=root,
                env={
                    **os.environ,
                    "HOME": str(home),
                    "ZSH": str(omz),
                    "PATH": f"{fake_bin}:/usr/bin:/bin",
                    "CURL_LOG": str(curl_log),
                    "DOWNLOAD_SOURCE": str(THEME),
                },
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertNotEqual(0, result.returncode)
            self.assertEqual("private\n", victim.read_text(encoding="ascii"))

    def test_heredoc_content_in_existing_zshrc_is_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home, omz, fake_bin, curl_log = self.prepare_installation(root)
            zshrc = home / ".zshrc"
            original_zshrc = (
                "cat <<'CONFIG'\n"
                'ZSH_THEME="text-only"\n'
                'source "$ZSH/oh-my-zsh.sh"\n'
                "CONFIG\n"
                'ZSH_THEME="robbyrussell"\n'
                'source "$ZSH/oh-my-zsh.sh"\n'
            )
            zshrc.write_text(original_zshrc, encoding="ascii")
            result = subprocess.run(
                ["sh", str(INSTALLER)],
                cwd=root,
                env={
                    **os.environ,
                    "HOME": str(home),
                    "ZSH": str(omz),
                    "PATH": f"{fake_bin}:/usr/bin:/bin",
                    "CURL_LOG": str(curl_log),
                    "DOWNLOAD_SOURCE": str(THEME),
                },
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(original_zshrc, zshrc.read_text(encoding="ascii"))
            self.assertFalse((home / ".zshrc.ai-candy-backup").exists())
            self.assertIn("was not modified", result.stderr)

    def test_no_modify_option_leaves_existing_zshrc_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / "home"
            original_zshrc = 'ZSH_THEME="robbyrussell"\nsource "$ZSH/oh-my-zsh.sh"\n'
            result = self.run_installer(
                root,
                "--no-modify-zshrc",
                zshrc_text=original_zshrc,
            )
            zshrc = home / ".zshrc"

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(original_zshrc, zshrc.read_text(encoding="ascii"))
            self.assertFalse((home / ".zshrc.ai-candy-backup").exists())

    def test_identical_theme_is_not_replaced_or_backed_up(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home, omz, fake_bin, curl_log = self.prepare_installation(root)
            theme_dir = omz / "custom" / "themes"
            theme_dir.mkdir(parents=True)
            target = theme_dir / THEME.name
            target.write_bytes(THEME.read_bytes())
            target.chmod(0o600)
            result = subprocess.run(
                ["sh", str(INSTALLER), "--no-modify-zshrc"],
                cwd=root,
                env={
                    **os.environ,
                    "HOME": str(home),
                    "ZSH": str(omz),
                    "PATH": f"{fake_bin}:/usr/bin:/bin",
                    "CURL_LOG": str(curl_log),
                    "DOWNLOAD_SOURCE": str(THEME),
                },
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(0o600, target.stat().st_mode & 0o777)
            self.assertIn("already current", result.stdout)
            self.assertEqual([], list(theme_dir.glob(f"{THEME.name}.backup.*")))

    def test_identical_theme_removes_group_and_other_write_permissions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home, omz, fake_bin, curl_log = self.prepare_installation(root)
            theme_dir = omz / "custom" / "themes"
            theme_dir.mkdir(parents=True)
            target = theme_dir / THEME.name
            target.write_bytes(THEME.read_bytes())
            target.chmod(0o666)
            result = subprocess.run(
                ["sh", str(INSTALLER), "--no-modify-zshrc"],
                cwd=root,
                env={
                    **os.environ,
                    "HOME": str(home),
                    "ZSH": str(omz),
                    "PATH": f"{fake_bin}:/usr/bin:/bin",
                    "CURL_LOG": str(curl_log),
                    "DOWNLOAD_SOURCE": str(THEME),
                },
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(0, target.stat().st_mode & 0o022)
            self.assertEqual(THEME.read_bytes(), target.read_bytes())
            self.assertIn("already current", result.stdout)
            self.assertEqual([], list(theme_dir.glob(f"{THEME.name}.backup.*")))

    def test_upgrade_preserves_the_previous_theme(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            previous_theme = b"previous ai-candy theme\n"
            result = self.run_installer(
                root,
                "--no-modify-zshrc",
                existing_theme=previous_theme,
            )
            theme_dir = root / "oh-my-zsh" / "custom" / "themes"
            backups = list(theme_dir.glob(f"{THEME.name}.backup.*"))

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(THEME.read_bytes(), (theme_dir / THEME.name).read_bytes())
            self.assertEqual(1, len(backups), backups)
            self.assertEqual(previous_theme, backups[0].read_bytes())
            self.assertIn(str(backups[0]), result.stdout)

    def test_confirm_option_can_cancel_an_upgrade(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            previous_theme = b"previous ai-candy theme\n"
            result = self.run_installer(
                root,
                "--no-modify-zshrc",
                "--confirm",
                existing_theme=previous_theme,
                stdin_text="SKIP\n",
            )
            theme_dir = root / "oh-my-zsh" / "custom" / "themes"
            target = theme_dir / THEME.name

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual(previous_theme, target.read_bytes())
            self.assertEqual([], list(theme_dir.glob(f"{THEME.name}.backup.*")))
            self.assertIn("Skipped ai-candy installation", result.stdout)


if __name__ == "__main__":
    unittest.main()
