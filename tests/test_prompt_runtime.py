#!/usr/bin/env python3
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from tests.theme_test_support import ROOT, THEME, run_zsh


class PromptRuntimeTest(unittest.TestCase):
    def test_time_color_handles_leading_zero_with_octal_zeroes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            fake_date = bin_dir / "date"
            fake_date.write_text("#!/bin/sh\nprintf '08\\n'\n", encoding="ascii")
            fake_date.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
zmodload -u zsh/datetime
setopt octalzeroes
_ai_candy_compute_time_direct
expected="%{$FG[$_CLR_TIME_MORNING]%}"
if [[ "$_PP_TIME" == "${expected}"* ]]; then
  print -r -- TIME=morning
else
  print -r -- TIME=wrong
fi
""",
                cache_home=root / "cache",
                env={"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("", result.stderr)
        self.assertEqual("TIME=morning\n", result.stdout)

    def test_display_width_counts_wide_and_combining_characters(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
wide=$'a\xE4\xB8\xADe\xCC\x81'
emoji=$'\xF0\x9F\x98\x80'
modern_wide=$'\xF0\x97\x80\x80'
hebrew_combining=$'a\xD6\xB0'
watch=$'\xE2\x8C\x9A'
emoji_heart=$'\xE2\x9D\xA4\xEF\xB8\x8F'
emoji_zwj=$'\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9'
flag=$'\xF0\x9F\x87\xBA\xF0\x9F\x87\xB8'
modifier=$'\xF0\x9F\x8F\xBB'
modified_thumb=$'\xF0\x9F\x91\x8D\xF0\x9F\x8F\xBB'
_ai_candy_prompt_text_width "$wide"
wide_width="$REPLY"
_ai_candy_prompt_text_width "$emoji"
emoji_width="$REPLY"
_ai_candy_prompt_text_width "$modern_wide"
modern_width="$REPLY"
_ai_candy_prompt_text_width "$hebrew_combining"
hebrew_width="$REPLY"
_ai_candy_prompt_text_width "$watch"
watch_width="$REPLY"
_ai_candy_prompt_text_width "$emoji_heart"
heart_width="$REPLY"
_ai_candy_prompt_text_width "$emoji_zwj"
zwj_width="$REPLY"
_ai_candy_prompt_text_width "$flag"
flag_width="$REPLY"
_ai_candy_prompt_text_width "$modifier"
modifier_width="$REPLY"
_ai_candy_prompt_text_width "A${modifier}"
invalid_modifier_width="$REPLY"
_ai_candy_prompt_text_width "$modified_thumb"
print -r -- "WIDE=${wide_width} EMOJI=${emoji_width} MODERN=${modern_width} HEBREW=${hebrew_width} WATCH=${watch_width} HEART=${heart_width} ZWJ=${zwj_width} FLAG=${flag_width} MODIFIER=${modifier_width}/${invalid_modifier_width}/${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
                env={"LC_ALL": "C", "LANG": "C"},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "WIDE=4 EMOJI=2 MODERN=2 HEBREW=1 WATCH=2 HEART=2 "
            "ZWJ=2 FLAG=2 MODIFIER=2/3/2\n",
            result.stdout,
        )

    def test_plain_path_truncation_respects_terminal_cell_width(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_ai_candy_render_plain_smart_path "$WIDE_PATH" 10
plain="${_PP_PATH//\%\{*\%\}/}"
plain="${plain//\%[BbUuSsfk]/}"
plain="${plain//\%[FK]\{*\}/}"
_ai_candy_prompt_text_width "$plain"
print -r -- "WIDTH=${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
                env={"WIDE_PATH": "\u4e2d" * 6},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertLessEqual(int(result.stdout.partition("=")[2]), 10)

    def test_text_tail_does_not_split_combining_or_emoji_sequences(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
heart=$'\xE2\x9D\xA4\xEF\xB8\x8F'
joined=$'\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9'
combining=$'a\xD6\xB0'
flag=$'\xF0\x9F\x87\xBA\xF0\x9F\x87\xB8'
_ai_candy_prompt_text_tail_by_width "x${heart}y" 3
[[ "$REPLY" == "${heart}y" ]] && heart_three=yes || heart_three=no
_ai_candy_prompt_text_tail_by_width "x${heart}y" 2
[[ "$REPLY" == y ]] && heart_two=yes || heart_two=no
_ai_candy_prompt_text_tail_by_width "x${joined}y" 3
[[ "$REPLY" == "${joined}y" ]] && joined_three=yes || joined_three=no
_ai_candy_prompt_text_tail_by_width "x${joined}y" 2
[[ "$REPLY" == y ]] && joined_two=yes || joined_two=no
_ai_candy_prompt_text_tail_by_width "x${combining}y" 2
[[ "$REPLY" == "${combining}y" ]] && combining_two=yes || combining_two=no
_ai_candy_prompt_text_tail_by_width "x${combining}y" 1
[[ "$REPLY" == y ]] && combining_one=yes || combining_one=no
_ai_candy_prompt_text_tail_by_width "x${flag}y" 3
[[ "$REPLY" == "${flag}y" ]] && flag_three=yes || flag_three=no
_ai_candy_prompt_text_tail_by_width "x${flag}y" 2
[[ "$REPLY" == y ]] && flag_two=yes || flag_two=no
print -r -- "HEART=${heart_three}/${heart_two} ZWJ=${joined_three}/${joined_two} COMBINING=${combining_two}/${combining_one} FLAG=${flag_three}/${flag_two}"
""",
                cache_home=Path(tmp) / "cache",
                env={"LC_ALL": "C", "LANG": "C"},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "HEART=yes/yes ZWJ=yes/yes COMBINING=yes/yes FLAG=yes/yes\n",
            result.stdout,
        )

    def test_markup_width_preserves_escaped_prompt_literals(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
setopt promptbang
raw='evil%F{red}%{hidden%}!!'
_ai_candy_prompt_escape_text "$raw"
escaped="$REPLY"
_ai_candy_prompt_markup_width "$escaped"
reported="$REPLY"
rendered=$(print -Pn -- "$escaped")
_ai_candy_prompt_text_width "$rendered"
print -r -- "REPORTED=${reported} RENDERED=${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("REPORTED=23 RENDERED=23\n", result.stdout)

    def test_prompt_expected_misses_are_safe_with_err_return(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "work"
            work.mkdir()
            result = run_zsh(
                r"""
source "$1"
_PROMPT_NETWORK_MODE=0
_PROMPT_AI_MODE=0
_PROMPT_OS_MODE=0
setopt err_return
_ai_candy_precmd_compute_prompt
[[ -o errreturn ]]
builtin print -r -- AFTER_PROMPT
""",
                cache_home=root / "cache",
                cwd=work,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("AFTER_PROMPT\n", result.stdout)

    def test_runtime_primitives_ignore_user_functions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shadow_log = root / "shadow.log"
            result = run_zsh(
                r"""
function zstyle() {
  builtin print -r -- zstyle >> "$SHADOW_LOG"
  return 1
}
function _omz_register_handler() { return 0; }
function _omz_async_request() { return 0; }
source "$1"
function echo() { builtin print -r -- echo >> "$SHADOW_LOG"; }
function cd() { builtin print -r -- cd >> "$SHADOW_LOG"; builtin cd "$@"; }
function pwd() { builtin print -r -- pwd >> "$SHADOW_LOG"; builtin pwd "$@"; }
function read() { builtin print -r -- read >> "$SHADOW_LOG"; return 1; }
function strftime() { builtin print -r -- strftime >> "$SHADOW_LOG"; return 1; }
_ai_candy_compute_time_direct
_ai_candy_logicalize_path_from_pwd "$PWD" >/dev/null
_PP_CACHED_GIT_ROOT=""
_ai_candy_get_git_hierarchy
cache_file="${_CACHE_DIR}/shadow_version_cache"
sep=$'\x1f'
builtin print -r -- "1.2.3${sep}${sep}${EPOCHSECONDS}" >| "$cache_file"
tool_result=""
tool_result_long=""
_AI_PROCESS_COUNTS[codex]=0
_PROMPT_NETWORK_MODE=0
_PROMPT_EMOJI_MODE=0
_ai_candy_compute_ai_tool_status 1 "$cache_file" codex https://invalid.example \
  Cx: Cx: 15 Codex codex
_CACHE_READY=0
_ai_candy_prompt_toggle_emoji >/dev/null
if [[ -f "$SHADOW_LOG" ]]; then
  print -r -- "SHADOWED=${(j:,:)${(@f)$(<"$SHADOW_LOG")}}"
else
  print -r -- "SHADOWED=none"
fi
""",
                cache_home=root / "cache",
                env={"SHADOW_LOG": str(shadow_log)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("SHADOWED=none\n", result.stdout)

    def test_source_is_not_rewritten_by_caller_aliases(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
setopt aliases
alias date='false #'
alias pwd='false #'
alias read='false #'
alias echo='false #'
eval 'source "$1"'
source_status=$?
print -r -- "STATUS=${source_status} ALIASES=${options[aliases]}"
print -r -- "TIME_FUNCTION=${+functions[_ai_candy_compute_time_direct]}"
print -r -- "PROMPT_FUNCTION=${+functions[_ai_candy_precmd_compute_prompt]}"
print -r -- "DATE_ALIAS=$(alias date)"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("STATUS=0 ALIASES=on", result.stdout)
        self.assertIn("TIME_FUNCTION=1", result.stdout)
        self.assertIn("PROMPT_FUNCTION=1", result.stdout)
        self.assertIn("date='false #'", result.stdout)

    def test_source_restores_aliases_after_a_requirement_failure(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
fpath=()
setopt aliases
alias date='false #'
eval 'source "$1"'
source_status=$?
print -r -- "STATUS=${source_status} ALIASES=${options[aliases]}"
print -r -- "DATE_ALIAS=$(alias date)"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("STATUS=1 ALIASES=on", result.stdout)
        self.assertIn("date='false #'", result.stdout)

    def test_long_virtual_environment_name_selects_compact_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
COLUMNS=100
_PROMPT_OS_MODE=0
_PP_VENV="%{$fg[yellow]%}(${(l:150::v:)})%{$reset_color%}"
_PP_AI_STATUS=""
_PP_AI_STATUS_LONG=""
_PP_GIT_INFO=""
_PP_GIT_EXT=""
_PP_GIT_SPECIAL=""
_PP_PR=""
_PP_GH_USER=""
_PP_EXIT=""
_PP_SSH=""
_PP_PUBLIC_IP=""
typeset -g _TEST_PATH_CALLS=""
function _ai_candy_prepare_smart_path_context() { _SMART_PATH_TOTAL_LENGTH=1; }
function _ai_candy_compute_smart_path_direct() {
  _TEST_PATH_CALLS+="${1},"
  _PP_PATH="[x]"
}
_ai_candy_compute_layout_mode
print -r -- "CALLS=${_TEST_PATH_CALLS}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CALLS=short,\n", result.stdout)

    def test_failed_omz_async_registration_keeps_sync_git_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
function _omz_async_request() { return 0; }
function _omz_register_handler() { return 1; }
source "$1"
print -r -- "ENABLED=${_AI_CANDY_USE_OMZ_ASYNC}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("ENABLED=0\n", result.stdout)

    def test_interactive_hooks_are_noops_under_errexit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cache_home = Path(tmp) / "cache"
            prompt_cache = cache_home / "zsh-prompt"
            prompt_cache.mkdir(parents=True)
            (prompt_cache / "network_mode").write_text("0\n", encoding="ascii")
            commands = f'''\
setopt errexit
autoload -Uz colors
colors
source "{THEME}"
print -r -- AFTER_SOURCE
true
print -r -- AFTER_COMMAND
exit 0
'''
            result = subprocess.run(
                ["zsh", "-dfi"],
                cwd=ROOT,
                input=commands,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={
                    **os.environ,
                    "TERM": "xterm-256color",
                    "XDG_CACHE_HOME": str(cache_home),
                },
                check=False,
                timeout=8,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("AFTER_SOURCE", result.stdout)
        self.assertIn("AFTER_COMMAND", result.stdout)

    def test_git_branch_bang_is_preserved_with_prompt_bang_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            repo.mkdir()
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.email", "test@example.com"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.name", "Test User"],
                check=True,
            )
            (repo / "tracked").write_text("content\n", encoding="ascii")
            subprocess.run(["git", "-C", str(repo), "add", "tracked"], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "commit", "-q", "-m", "initial"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(repo), "switch", "-q", "-c", "feature!bang"],
                check=True,
            )
            result = run_zsh(
                r"""
setopt promptbang
source "$1"
_PP_CACHED_GIT_ROOT="$PWD"
_PROMPT_RENDER_ID=1
_ai_candy_collect_git_snapshot
_ai_candy_format_git_snapshot
print -P -r -- "${_GIT_FORMATTED_INFO}"
""",
                cache_home=root / "cache",
                cwd=repo,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("feature!bang", result.stdout)

    def test_git_branch_unicode_direction_and_line_controls_are_neutralized(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            repo.mkdir()
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.email", "test@example.com"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.name", "Test User"],
                check=True,
            )
            (repo / "tracked").write_text("content\n", encoding="ascii")
            subprocess.run(["git", "-C", str(repo), "add", "tracked"], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "commit", "-q", "-m", "initial"],
                check=True,
            )
            for codepoint in (0x2028, 0x2029, 0x202E):
                with self.subTest(codepoint=hex(codepoint)):
                    control = chr(codepoint)
                    subprocess.run(
                        [
                            "git",
                            "-C",
                            str(repo),
                            "switch",
                            "-q",
                            "-c",
                            f"feature-{codepoint:x}{control}txt",
                        ],
                        check=True,
                    )
                    result = run_zsh(
                        r"""
source "$1"
_PP_CACHED_GIT_ROOT="$PWD"
_PROMPT_RENDER_ID=1
_ai_candy_collect_git_snapshot
_ai_candy_format_git_snapshot
print -P -r -- "${_GIT_FORMATTED_INFO}"
""",
                        cache_home=root / "cache",
                        cwd=repo,
                    )

                    self.assertEqual(0, result.returncode, result.stderr)
                    self.assertNotIn(control, result.stdout)
                    self.assertIn(f"feature-{codepoint:x}?txt", result.stdout)


if __name__ == "__main__":
    unittest.main()
