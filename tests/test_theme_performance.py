#!/usr/bin/env python3
import os
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from tests.theme_test_support import CACHE_SCHEDULING_BUDGET_MS, run_zsh


class ThemePerformanceTest(unittest.TestCase):
    def test_warm_prompt_p95_stays_below_ten_milliseconds(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "work"
            work.mkdir()
            result = run_zsh(
                r"""
autoload -Uz colors
colors
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_AI_CANDY_HAS_GH=0
_AI_CANDY_HAS_SSH=0
_AI_CANDY_HAS_CURL=0
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_precmd_compute_prompt
for iteration in {1..80}; do
  (( _AI_CANDY_PROMPT_RENDER_ID++ ))
  start=$EPOCHREALTIME
  _ai_candy_precmd_compute_prompt
  builtin printf '%.6f\n' "$(( (EPOCHREALTIME - start) * 1000 ))"
done
""",
                cache_home=root / "cache",
                cwd=work,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        samples = sorted(float(line) for line in result.stdout.splitlines())
        self.assertEqual(80, len(samples))
        p95 = samples[75]
        self.assertLess(p95, 10.0, f"p95={p95:.3f}ms max={samples[-1]:.3f}ms")

    def test_warm_network_cache_hits_start_no_network_commands(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / "zsh-prompt"
            bin_dir = root / "bin"
            marker = root / "network-called"
            cache_dir.mkdir(parents=True)
            bin_dir.mkdir()
            now = int(time.time())
            (cache_dir / "network_mode").write_text("1\n", encoding="ascii")
            (cache_dir / "public_ip_cache").write_text(
                f"203.0.113.42|{now}\n", encoding="ascii"
            )
            for name in ("gh_username_gh", "gh_username_ssh"):
                (cache_dir / name).write_text(f"demo-user|{now}\n", encoding="ascii")
            for name in ("curl", "gh", "ssh"):
                executable = bin_dir / name
                executable.write_text(
                    "#!/bin/sh\n"
                    'printf "%s\\n" "$0 $*" >> "$NETWORK_MARKER"\n'
                    "exit 1\n",
                    encoding="ascii",
                )
                executable.chmod(0o755)

            result = run_zsh(
                r"""
autoload -Uz colors
colors
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_AI_CANDY_PROMPT_NETWORK_MODE=1
_AI_CANDY_PROMPT_AI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_precmd_compute_prompt
(( _AI_CANDY_PROMPT_RENDER_ID++ ))
_ai_candy_precmd_compute_prompt
zselect -t 5
print -r -- READY
""",
                cache_home=root / "cache",
                cwd=root,
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "NETWORK_MARKER": str(marker),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("READY\n", result.stdout)
        self.assertFalse(marker.exists())

    def test_repeated_text_width_measurement_reuses_the_exact_result(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
typeset -gi WIDTH_MEASURE_CALLS=0
functions[_measure_text_without_cache]="${functions[_ai_candy_prompt_measure_text]}"
function _ai_candy_prompt_measure_text() {
  (( ++WIDTH_MEASURE_CALLS ))
  _measure_text_without_cache "$@"
}
_ai_candy_prompt_text_width $'same \xE4\xB8\xAD text'
first_width="$REPLY"
_ai_candy_prompt_text_width $'same \xE4\xB8\xAD text'
second_width="$REPLY"
print -r -- \
  "CALLS=${WIDTH_MEASURE_CALLS} FIRST=${first_width} SECOND=${second_width}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CALLS=1 FIRST=12 SECOND=12\n", result.stdout)

    def test_unchanged_smart_path_render_is_reused(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "long-directory-name" / "child"
            work.mkdir(parents=True)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_PP_CACHED_GIT_ROOT=NOT_GIT
typeset -gi PATH_RENDER_CALLS=0
functions[_render_path_without_cache]="${functions[_ai_candy_render_plain_smart_path]}"
function _ai_candy_render_plain_smart_path() {
  (( ++PATH_RENDER_CALLS ))
  _render_path_without_cache "$@"
}
_ai_candy_compute_smart_path_direct short 18
first_path="$_AI_CANDY_PP_PATH"
_ai_candy_compute_smart_path_direct short 18
second_path="$_AI_CANDY_PP_PATH"
_ai_candy_compute_smart_path_direct short 16
print -r -- \
  "CALLS=${PATH_RENDER_CALLS} SAME=$([[ "$first_path" == "$second_path" ]] && print yes || print no)"
""",
                cache_home=root / "cache",
                cwd=work,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CALLS=2 SAME=yes\n", result.stdout)

    def test_smart_path_render_tracks_prompt_bang(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "path!literal"
            work.mkdir()
            result = run_zsh(
                r"""
autoload -Uz colors
colors
source "$1"
fg[white]=""
reset_color=""
_AI_CANDY_PP_CACHED_GIT_ROOT=NOT_GIT
unsetopt promptbang
_ai_candy_compute_smart_path_direct full
first=$(print -P -- "$_AI_CANDY_PP_PATH")
setopt promptbang
_ai_candy_compute_smart_path_direct full
second=$(print -P -- "$_AI_CANDY_PP_PATH")
print -r -- "FIRST=${first} SECOND=${second}"
""",
                cache_home=root / "cache",
                cwd=work,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("path!literal", result.stdout.partition(" SECOND=")[0])
        self.assertIn("SECOND=", result.stdout)
        self.assertIn("path!literal", result.stdout.partition(" SECOND=")[2])

    def test_ai_process_snapshot_is_stable_for_slow_and_failed_probes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
typeset -gi STARTS=0
typeset -gi PROBE_CALLS=0
function _ai_candy_run_background_probe() {
  (( ++PROBE_CALLS ))
  return 1
}
function _ai_candy_start_registered_background_worker() {
  [[ "$1" == _ai_candy_ai_process_count_update_worker ]] || return 71
  (( ++STARTS ))
  return 0
}
_AI_CANDY_AI_PROCESS_SNAPSHOT_TIME=$(( EPOCHSECONDS - 29 ))
_ai_candy_refresh_ai_process_counts
cached_starts="$STARTS"
_AI_CANDY_AI_PROCESS_COUNTS=(claude 0 codex 4 gemini 0 kimi 0)
_AI_CANDY_AI_PROCESS_SNAPSHOT_TIME=1
_ai_candy_refresh_ai_process_counts
_ai_candy_refresh_ai_process_counts
print -r -- "TTL=${_AI_CANDY_AI_PROCESS_SNAPSHOT_TTL} CACHED_STARTS=${cached_starts} STARTS=${STARTS} PROBES=${PROBE_CALLS} COUNT=${_AI_CANDY_AI_PROCESS_COUNTS[codex]} TIME=${_AI_CANDY_AI_PROCESS_SNAPSHOT_TIME} REQUESTED=${#_AI_CANDY_REFRESH_REQUESTED}"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "TTL=30 CACHED_STARTS=0 STARTS=1 PROBES=0 "
            "COUNT=4 TIME=1 REQUESTED=1\n",
            result.stdout,
        )

    def test_ai_process_worker_counts_node_wrapped_tools(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
function _ai_candy_acquire_background_lock() { return 0; }
function _ai_candy_cache_lock_release() { return 0; }
function _ai_candy_run_background_probe() {
  builtin print -r -- "node node /opt/tools/bin/claude"
  builtin print -r -- "node node /opt/tools/bin/codex"
  builtin print -r -- "node node /opt/tools/bin/gemini"
  builtin print -r -- "node node /opt/tools/bin/kimi"
}
function _ai_candy_cache_write() {
  builtin print -r -- "SNAPSHOT=$2"
}
_ai_candy_ai_process_count_update_worker lock cache epoch
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertRegex(result.stdout, r"^SNAPSHOT=1\|1\|1\|1\|[0-9]+\n$")

    def test_smart_path_strips_literal_metacharacter_parent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_PROMPT_PATH_SEP_MODE=0
_AI_CANDY_PP_CACHED_GIT_ROOT='/repo[1]'
function _ai_candy_get_git_hierarchy() {
  REPLY="/repo[1]${_AI_CANDY_GIT_HIERARCHY_SEP}/repo[1]/child${_AI_CANDY_GIT_HIERARCHY_SEP}"
}
_ai_candy_prepare_smart_path_context
print -r -- "SEGMENTS=${(j:|:)_AI_CANDY_SMART_PATH_SEGMENTS}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("SEGMENTS=/repo[1]|child\n", result.stdout)

    def test_layout_identity_length_uses_no_external_commands(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            marker = root / "identity.called"
            for name in ("whoami", "hostname"):
                executable = bin_dir / name
                executable.write_text(
                    "#!/bin/sh\n"
                    'printf called >> "$IDENTITY_MARKER"\n'
                    "/bin/sleep 1\n"
                    f"printf '%s\\n' fixture-{name}\n",
                    encoding="ascii",
                )
                executable.chmod(0o755)

            result = run_zsh(
                r"""
source "$1"
PATH="$SLOW_BIN:$PATH"
unset USER HOST HOSTNAME
COLUMNS=200
_AI_CANDY_PROMPT_EMOJI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_AI_CANDY_PP_AI_STATUS=""
_AI_CANDY_PP_AI_STATUS_LONG=""
_AI_CANDY_PP_GIT_INFO=""
_AI_CANDY_PP_GIT_EXT=""
_AI_CANDY_PP_GIT_SPECIAL=""
_AI_CANDY_PP_PR=""
_AI_CANDY_PP_GH_USER=""
_AI_CANDY_PP_EXIT=""
_AI_CANDY_PP_SSH=""
_AI_CANDY_PP_PUBLIC_IP=""
_AI_CANDY_PP_VENV=""
function _ai_candy_prepare_smart_path_context() { _AI_CANDY_SMART_PATH_TOTAL_LENGTH=1; }
function _ai_candy_compute_smart_path_direct() { _AI_CANDY_PP_PATH="[x]"; }
start_time=$EPOCHREALTIME
_ai_candy_compute_layout_mode
elapsed_ms=$(( (EPOCHREALTIME - start_time) * 1000 ))
if [[ -f "$IDENTITY_MARKER" ]]; then
  called=yes
else
  called=no
fi
builtin printf 'CALLED=%s ELAPSED_MS=%.3f\n' "$called" "$elapsed_ms"
""",
                cache_home=root / "cache",
                env={
                    "IDENTITY_MARKER": str(marker),
                    "SLOW_BIN": str(bin_dir),
                },
                timeout=4,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(item.split("=", 1) for item in result.stdout.split())
        self.assertEqual("no", fields["CALLED"])
        self.assertLess(float(fields["ELAPSED_MS"]), 200.0, result.stdout)

    def test_minimal_layout_truncates_a_long_non_git_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / ("long-directory-" * 8)
            work.mkdir()
            result = run_zsh(
                r"""
source "$1"
COLUMNS=20
_AI_CANDY_PP_CACHED_GIT_ROOT=NOT_GIT
_ai_candy_compute_smart_path_direct short "$COLUMNS"
plain="$_AI_CANDY_PP_PATH"
plain="${(S)plain//\%\{*\%\}/}"
plain="${plain//\%[BbUuSsfk]/}"
plain="${(S)plain//\%[FK]\{*\}/}"
print -r -- "WIDTH=${#plain} PATH=${plain}"
""",
                cache_home=root / "cache",
                cwd=work,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(item.split("=", 1) for item in result.stdout.split(maxsplit=1))
        self.assertLessEqual(int(fields["WIDTH"]), 20, result.stdout)
        self.assertTrue(fields["PATH"].startswith("[.."), result.stdout)

    def test_minimal_layout_renders_only_the_selected_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
COLUMNS=1
_AI_CANDY_PROMPT_EMOJI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_AI_CANDY_PP_AI_STATUS=""
_AI_CANDY_PP_AI_STATUS_LONG=""
_AI_CANDY_PP_GIT_INFO=""
_AI_CANDY_PP_GIT_EXT=""
_AI_CANDY_PP_GIT_SPECIAL=""
_AI_CANDY_PP_PR=""
_AI_CANDY_PP_GH_USER=""
_AI_CANDY_PP_EXIT=""
_AI_CANDY_PP_SSH=""
_AI_CANDY_PP_PUBLIC_IP=""
typeset -g _TEST_PATH_CALLS=""
function _ai_candy_prepare_smart_path_context() {
  _AI_CANDY_SMART_PATH_TOTAL_LENGTH=120
}
function _ai_candy_compute_smart_path_direct() {
  _TEST_PATH_CALLS+="${1},"
  _AI_CANDY_PP_PATH="${(l:120::x:)}"
}
_ai_candy_compute_layout_mode
print -r -- "CALLS=${_TEST_PATH_CALLS}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CALLS=short,\n", result.stdout)

    def test_native_timeout_has_no_fixed_fifty_millisecond_poll(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_TIMEOUT_CMD=zsh-native
start=$EPOCHREALTIME
for iteration in {1..5}; do
  _ai_candy_run_with_timeout 1 true
done
elapsed_ms=$(( (EPOCHREALTIME - start) * 1000 ))
printf 'ELAPSED_MS=%.3f\n' "$elapsed_ms"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        elapsed_ms = float(result.stdout.strip().split("=", 1)[1])
        self.assertLess(elapsed_ms, 175.0, result.stdout)

    def test_persistent_cache_write_is_deferred_from_parent_prompt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            marker = root / "persisted"
            result = run_zsh(
                r"""
source "$1"
functions[_commit_without_delay]="${functions[_ai_candy_cache_commit_operation]}"
function _ai_candy_cache_commit_operation() {
  zselect -t 30
  _commit_without_delay "$@"
}
function _ai_candy_cache_persist_write_unlocked() {
  zselect -t 30
  print -r -- done >| "$PERSIST_MARKER"
}
start=$EPOCHREALTIME
_ai_candy_cache_set git_root key value "$EPOCHSECONDS"
elapsed_ms=$(( (EPOCHREALTIME - start) * 1000 ))
for attempt in {1..100}; do
  [[ -f "$PERSIST_MARKER" ]] && break
  zselect -t 1
done
persisted=0
[[ -f "$PERSIST_MARKER" ]] && persisted=1
printf 'ELAPSED_MS=%.3f PERSISTED=%d\n' "$elapsed_ms" "$persisted"
""",
                cache_home=root / "cache",
                env={"PERSIST_MARKER": str(marker)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(item.split("=", 1) for item in result.stdout.split())
        self.assertLess(
            float(fields["ELAPSED_MS"]),
            CACHE_SCHEDULING_BUDGET_MS,
            result.stdout,
        )
        self.assertEqual("1", fields["PERSISTED"])

    def test_native_timeout_avoids_external_file_helpers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log_file = root / "helpers.log"
            for command_name in ("mktemp", "cat"):
                real_command = shutil.which(command_name)
                self.assertIsNotNone(real_command)
                command = bin_dir / command_name
                command.write_text(
                    "#!/bin/sh\n"
                    "printf '%s\\n' helper >> \"$HELPER_LOG\"\n"
                    f'exec {shlex.quote(real_command)} "$@"\n',
                    encoding="ascii",
                )
                command.chmod(0o755)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_TIMEOUT=0
_AI_CANDY_TIMEOUT_CMD=""
output=$(_ai_candy_run_with_timeout 0.5 /bin/sh -c 'printf result')
print -r -- "OUTPUT=${output}"
print -r -- "HELPERS=$([[ -f "$HELPER_LOG" ]] && print used || print none)"
""",
                cache_home=root / "cache",
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "HELPER_LOG": str(log_file),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("OUTPUT=result", result.stdout)
        self.assertIn("HELPERS=none", result.stdout)

    def test_system_information_is_loaded_once_per_session(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            cache_file = cache_dir / "sysinfo_cache"
            fields = ("First OS", "First", ", Linux-1", ", Linux-1")
            payload = "v2|" + "|".join(
                field.encode("utf-8").hex().upper() for field in fields
            )
            cache_file.write_text(
                f"{int(time.time())}\n{payload}\n",
                encoding="ascii",
            )
            result = run_zsh(
                r"""
source "$1"
_ai_candy_compute_sysinfo_direct
print -r -- "FIRST=${_AI_CANDY_PP_SYSINFO_OS_LONG}"
_ai_candy_cache_write "$_AI_CANDY_SYSINFO_CACHE_FILE" "${EPOCHSECONDS}\nSecond OS|Second|, Linux-2|, Linux-2"
_ai_candy_compute_sysinfo_direct
print -r -- "SECOND=${_AI_CANDY_PP_SYSINFO_OS_LONG}"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("FIRST=First OS", result.stdout)
        self.assertIn("SECOND=First OS", result.stdout)

    def test_ai_instance_counts_use_one_process_table_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / "zsh-prompt"
            bin_dir = root / "bin"
            cache_dir.mkdir(parents=True)
            bin_dir.mkdir()
            now = str(int(time.time()))
            separator = "\x1f"
            for cache_name in (
                "claude_version_cache",
                "codex_version_cache",
                "gemini_version_cache",
                "kimi_version_cache",
            ):
                (cache_dir / cache_name).write_text(
                    f"1.2.3{separator}1.2.3{separator}{now}\n",
                    encoding="utf-8",
                )
            (cache_dir / "network_mode").write_text("0\n", encoding="ascii")
            log_file = root / "process.log"

            for tool in ("claude", "codex", "gemini", "kimi"):
                command = bin_dir / tool
                command.write_text("#!/bin/sh\nexit 0\n", encoding="ascii")
                command.chmod(0o755)

            process_output = (
                "claude claude\n"
                "codex codex\n"
                "node node /opt/tools/bin/gemini\n"
                "kimi kimi\n"
            )
            for command_name in ("pgrep", "ps"):
                command = bin_dir / command_name
                command.write_text(
                    "#!/bin/sh\n"
                    "printf '%s\\n' called >> \"$PROCESS_LOG\"\n"
                    f"printf '%b' {process_output!r}\n",
                    encoding="ascii",
                )
                command.chmod(0o755)

            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do FG[$color]=""; done
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=1
_ai_candy_compute_ai_tools_direct
calls=("${(@f)$(<"$PROCESS_LOG")}")
print -r -- "CALLS=${#calls}"
""",
                cache_home=root / "cache",
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "PROCESS_LOG": str(log_file),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("CALLS=1", result.stdout)

    def test_full_and_short_paths_share_parsed_context(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do FG[$color]=""; done
source "$1"
typeset -g HIERARCHY_CALLS=0
function _ai_candy_get_git_hierarchy() {
  (( HIERARCHY_CALLS++ ))
  REPLY="${PWD}${_AI_CANDY_GIT_HIERARCHY_SEP}"
}
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_compute_smart_path_direct full
_ai_candy_compute_smart_path_direct short
print -r -- "CALLS=${HIERARCHY_CALLS}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("CALLS=1", result.stdout)

    def test_unchanged_path_context_is_reused_across_prompt_renders(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do FG[$color]=""; done
source "$1"
typeset -g HIERARCHY_CALLS=0
function _ai_candy_get_git_hierarchy() {
  (( HIERARCHY_CALLS++ ))
  REPLY="${PWD}${_AI_CANDY_GIT_HIERARCHY_SEP}"
}
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_compute_smart_path_direct full
_AI_CANDY_PROMPT_RENDER_ID=2
_ai_candy_compute_smart_path_direct full
print -r -- "CALLS=${HIERARCHY_CALLS}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("CALLS=1", result.stdout)

    def test_git_hierarchy_reuses_the_cached_repository_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log_file = root / "git.log"
            real_git = shutil.which("git")
            self.assertIsNotNone(real_git)
            git = bin_dir / "git"
            git.write_text(
                "#!/bin/sh\n"
                'printf \'%s\\n\' "$*" >> "$GIT_LOG"\n'
                f'exec {shlex.quote(real_git)} "$@"\n',
                encoding="ascii",
            )
            git.chmod(0o755)

            result = run_zsh(
                r"""
source "$1"
_ai_candy_get_cached_git_root
_AI_CANDY_PP_CACHED_GIT_ROOT="$REPLY"
_ai_candy_get_git_hierarchy
calls=("${(@f)$(<"$GIT_LOG")}")
show_root=("${(@)calls:#*rev-parse --show-toplevel*}")
print -r -- "SHOW_ROOT=$(( ${#calls} - ${#show_root} ))"
""",
                cache_home=root / "cache",
                cwd=repo,
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "GIT_LOG": str(log_file),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("SHOW_ROOT=1", result.stdout)

    def test_git_hierarchy_cache_version_changes_the_memory_key(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_GIT_HIERARCHY_CACHE_VERSION=1
_ai_candy_get_git_hierarchy
_ai_candy_get_git_hierarchy
first_count=${#_AI_CANDY_MEM_CACHE_GIT_HIERARCHY}
_AI_CANDY_GIT_HIERARCHY_CACHE_VERSION=2
_ai_candy_get_git_hierarchy
print -r -- "FIRST=${first_count} SECOND=${#_AI_CANDY_MEM_CACHE_GIT_HIERARCHY}"
""",
                cache_home=root / "cache",
                cwd=root,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("FIRST=1 SECOND=2\n", result.stdout)

    def test_git_remote_hash_is_reused_across_prompt_renders(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "symbolic-ref", "HEAD", "refs/heads/main"],
                check=True,
            )
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "remote",
                    "add",
                    "origin",
                    "https://example.invalid/repo.git",
                ],
                check=True,
            )
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log_file = root / "git.log"
            real_git = shutil.which("git")
            self.assertIsNotNone(real_git)
            git = bin_dir / "git"
            git.write_text(
                "#!/bin/sh\n"
                'printf \'%s\\n\' "$*" >> "$GIT_LOG"\n'
                f'exec {shlex.quote(real_git)} "$@"\n',
                encoding="ascii",
            )
            git.chmod(0o755)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_get_cached_git_remote_branch
first="$REPLY"
_AI_CANDY_PROMPT_RENDER_ID=2
_ai_candy_get_cached_git_remote_branch
second="$REPLY"
calls=("${(@f)$(<"$GIT_LOG")}")
remote_calls=0
graph_calls=0
for call in "${calls[@]}"; do
  [[ "$call" == "config --get remote.origin.url" ]] && \
    (( ++remote_calls ))
  [[ "$call" == *" config --includes --show-origin "* ]] && \
    (( ++graph_calls ))
done
print -r -- \
  "REMOTE_CALLS=${remote_calls} GRAPH_CALLS=${graph_calls} TOTAL=${#calls}"
print -r -- "SAME=$([[ "$first" == "$second" ]] && print yes || print no)"
""",
                cache_home=root / "cache",
                cwd=repo,
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "GIT_LOG": str(log_file),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("REMOTE_CALLS=1 GRAPH_CALLS=2 TOTAL=3", result.stdout)
        self.assertIn("SAME=yes", result.stdout)

    def test_tool_status_does_not_spawn_sed_for_each_line(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log_file = root / "sed.log"
            sed = bin_dir / "sed"
            sed.write_text(
                '#!/bin/sh\nprintf \'%s\\n\' called >> "$SED_LOG"\nexec /bin/sed "$@"\n',
                encoding="ascii",
            )
            sed.chmod(0o755)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_HAS_GH=0
_AI_CANDY_HAS_SSH=0
_AI_CANDY_HAS_CURL=0
_AI_CANDY_HAS_CLAUDE=0
_AI_CANDY_HAS_CODEX=0
_AI_CANDY_HAS_GEMINI=0
_AI_CANDY_HAS_KIMI=0
_ai_candy_prompt_tool_status >/dev/null
print -r -- "SED=$([[ -f "$SED_LOG" ]] && print used || print unused)"
""",
                cache_home=root / "cache",
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "SED_LOG": str(log_file),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("SED=unused", result.stdout)

    def test_ssh_identity_probe_has_a_total_deadline(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            ssh = bin_dir / "ssh"
            ssh.write_text("#!/bin/sh\nsleep 2\n", encoding="ascii")
            ssh.chmod(0o755)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SSH=1
_AI_CANDY_NETWORK_TIMEOUT=0.2
start=$EPOCHREALTIME
_ai_candy_gh_username_update_ssh
worker_pid="${_AI_CANDY_BACKGROUND_PIDS[-1]-}"
[[ "$worker_pid" == <-> ]] || exit 3
deadline=$(( EPOCHREALTIME + 1.0 ))
while _ai_candy_background_pid_is_owned "$worker_pid" && (( EPOCHREALTIME < deadline )); do
  zselect -t 1
done
elapsed=$(( EPOCHREALTIME - start ))
print -r -- "WORKER=$(_ai_candy_background_pid_is_owned "$worker_pid" && print running || print stopped)"
print -r -- "ELAPSED=${elapsed}"
""",
                cache_home=root / "cache",
                env={"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("WORKER=stopped", result.stdout)
        elapsed_line = next(
            line for line in result.stdout.splitlines() if line.startswith("ELAPSED=")
        )
        self.assertLess(float(elapsed_line.partition("=")[2]), 0.8)

    def test_pr_worker_shares_one_network_deadline(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_GH=1
_AI_CANDY_NETWORK_TIMEOUT=3
_AI_CANDY_GH_AUTH_MEM_CACHE=1
_AI_CANDY_GH_AUTH_MEM_CACHE_TIME=$EPOCHSECONDS
function _ai_candy_run_with_timeout() {
  local timeout="$1"
  shift
  if [[ "$1 $2 $3" == "gh pr view" ]]; then
    builtin print -r -- "VIEW=${timeout}" >>! "$TIMEOUTS_FILE"
    while [[ ! -e "$RELEASE_FILE" ]]; do
      zselect -t 1
    done
    zselect -t 20
    builtin print -r -- 42
    return 0
  fi
  if [[ "$1 $2 $3" == "gh pr checks" ]]; then
    builtin print -r -- "CHECKS=${timeout}" >>! "$TIMEOUTS_FILE"
    return 124
  fi
  return 124
}
function _ai_candy_cache_persist_write() { return 0; }
_ai_candy_gh_pr_update_cache remote branch
worker_pid="${_AI_CANDY_BACKGROUND_PIDS[-1]-}"
[[ "$worker_pid" == <-> ]] || exit 3
builtin print -r -- release >| "$RELEASE_FILE"
deadline=$(( EPOCHREALTIME + 1.5 ))
while _ai_candy_background_pid_is_owned "$worker_pid" && (( EPOCHREALTIME < deadline )); do
  zselect -t 1
done
print -r -- "WORKER=$(_ai_candy_background_pid_is_owned "$worker_pid" && print running || print stopped)"
[[ -f "$TIMEOUTS_FILE" ]] && builtin print -r -- "$(<"$TIMEOUTS_FILE")"
""",
                cache_home=root / "cache",
                env={
                    "RELEASE_FILE": str(root / "release"),
                    "TIMEOUTS_FILE": str(root / "timeouts"),
                },
                timeout=5,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("WORKER=stopped", result.stdout)
        timeouts = {
            key: float(value)
            for key, value in (
                line.split("=", 1)
                for line in result.stdout.splitlines()
                if "=" in line and not line.startswith("WORKER=")
            )
        }
        self.assertEqual(3.0, timeouts["VIEW"])
        self.assertGreater(timeouts["CHECKS"], 0.0)
        self.assertLess(timeouts["CHECKS"], timeouts["VIEW"] - 0.1)


if __name__ == "__main__":
    unittest.main()
