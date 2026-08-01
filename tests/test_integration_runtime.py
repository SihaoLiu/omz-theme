#!/usr/bin/env python3
import os
import tempfile
import unittest
from pathlib import Path

from tests.theme_test_support import run_zsh


class IntegrationRuntimeTest(unittest.TestCase):
    def test_network_refreshes_are_deduplicated_in_the_parent_shell(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_TIMEOUT=1
_AI_CANDY_HAS_CURL=1
_AI_CANDY_HAS_GH=1
_AI_CANDY_HAS_SSH=1
typeset -g STARTS=0
function _ai_candy_start_registered_background_worker() {
  (( STARTS++ ))
  return 0
}
for attempt in {1..2}; do
  _ai_candy_gh_username_update_gh
  _ai_candy_gh_username_update_ssh
  _ai_candy_public_ip_update_background
  _ai_candy_gh_pr_update_cache remote branch
done
print -r -- "STARTS=${STARTS} REQUESTED=${#_AI_CANDY_REFRESH_REQUESTED}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STARTS=4 REQUESTED=4\n", result.stdout)

    def test_pr_worker_queries_the_captured_branch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            command_log = root / "gh.log"
            gh = bin_dir / "gh"
            gh.write_text(
                "#!/bin/sh\n"
                'printf \'%s\\n\' "$*" >> "$GH_LOG"\n'
                'case "$*" in\n'
                "  *'pr view'*) printf '%s\\n' 42 ;;\n"
                "  *'pr checks'*) printf '%s\\n' pass ;;\n"
                "esac\n",
                encoding="ascii",
            )
            gh.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=none
_AI_CANDY_CACHE_BACKEND_RETRY_AFTER=$(( EPOCHREALTIME + 60 ))
_AI_CANDY_HAS_GH=1
_ai_candy_gh_pr_update_cache remote 'feature/captured'
for attempt in {1..500}; do
  if _ai_candy_cache_persist_read gh_pr 'remote|feature/captured'; then
    print -r -- "VALUE=${REPLY}"
    return 0
  fi
  zselect -t 1
done
return 70
""",
                cache_home=root / "cache",
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "GH_LOG": str(command_log),
                },
            )

            commands = command_log.read_text(encoding="ascii").splitlines()

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("VALUE=42|pass|", result.stdout)
        self.assertEqual(2, len(commands), commands)
        self.assertTrue(all("feature/captured" in command for command in commands))
        self.assertTrue(
            all(command.endswith(" -- feature/captured") for command in commands),
            commands,
        )

    def test_cold_tool_cache_populates_without_network_access(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            local_log = root / "local.log"
            network_log = root / "network.log"
            tool = bin_dir / "codex"
            tool.write_text(
                "#!/bin/sh\nprintf '%s\\n' called > \"$LOCAL_LOG\"\n"
                "printf '%s\\n' 'codex-cli 1.2.3'\n",
                encoding="ascii",
            )
            tool.chmod(0o755)
            curl = bin_dir / "curl"
            curl.write_text(
                "#!/bin/sh\nprintf '%s\\n' called > \"$NETWORK_LOG\"\n"
                "printf '%s\\n' '{\"version\":\"9.9.9\"}'\n",
                encoding="ascii",
            )
            curl.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=1
_AI_CANDY_PROMPT_EMOJI_MODE=0
_AI_CANDY_AI_TOOLS_DETECTED=1
_AI_CANDY_HAS_CLAUDE=0
_AI_CANDY_HAS_CODEX=1
_AI_CANDY_HAS_GEMINI=0
_AI_CANDY_HAS_KIMI=0
_AI_CANDY_HAS_CURL=1
function _ai_candy_refresh_ai_process_counts() { _AI_CANDY_AI_PROCESS_COUNTS[codex]=0; }
_ai_candy_compute_ai_tools_direct
for attempt in {1..500}; do
  [[ -s "$_AI_CANDY_CODEX_CACHE_FILE" ]] && break
  zselect -t 1
done
[[ -s "$_AI_CANDY_CODEX_CACHE_FILE" ]] || return 70
_ai_candy_compute_ai_tools_direct
print -r -- "STATUS=${_AI_CANDY_PP_AI_STATUS}"
print -r -- "LOCAL=$([[ -f $LOCAL_LOG ]] && print yes || print no)"
print -r -- "NETWORK=$([[ -f $NETWORK_LOG ]] && print yes || print no)"
""",
                cache_home=root / "cache",
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "LOCAL_LOG": str(local_log),
                    "NETWORK_LOG": str(network_log),
                },
                timeout=8,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("1.2.3", result.stdout)
        self.assertIn("LOCAL=yes", result.stdout)
        self.assertIn("NETWORK=no", result.stdout)

    def test_background_version_probe_allows_a_slow_local_cli(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            tool = bin_dir / "slow-tool"
            tool.write_text(
                "#!/bin/sh\nsleep 0.4\nprintf '%s\\n' 'slow-tool 1.2.3'\n",
                encoding="ascii",
            )
            tool.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
cache_file="${_AI_CANDY_CACHE_DIR}/slow_tool_cache"
_ai_candy_ai_tool_update_cache "$cache_file" slow-tool 'https://invalid.example/version' 0
deadline=$(( EPOCHREALTIME + 3.0 ))
while [[ ! -s "$cache_file" ]] && (( EPOCHREALTIME < deadline )); do
  zselect -t 1
done
if [[ -s "$cache_file" ]]; then
  print -r -- "CACHE=$(<"$cache_file")"
else
  print -r -- "CACHE=missing"
fi
_ai_candy_stop_registered_background_jobs
""",
                cache_home=root / "cache",
                env={"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"},
                timeout=5,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("CACHE=1.2.3", result.stdout)

    def test_tool_version_redirects_remain_https_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            curl_log = root / "curl.log"
            bin_dir.mkdir()
            for name, body in (
                ("codex", "printf '%s\\n' 'codex 1.2.3'"),
                (
                    "curl",
                    "printf '%s\\n' \"$*\" > \"$CURL_LOG\"\n"
                    "printf '%s\\n' '{\"version\":\"2.0.0\"}'",
                ),
            ):
                command = bin_dir / name
                command.write_text(f"#!/bin/sh\n{body}\n", encoding="ascii")
                command.chmod(0o755)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_CURL=1
function _ai_candy_acquire_background_lock() { return 0; }
function _ai_candy_cache_lock_release() { return 0; }
function _ai_candy_run_background_probe() {
  builtin print -r -- "codex 1.2.3"
}
function _ai_candy_run_with_timeout() {
  shift
  command "$@"
}
function _ai_candy_cache_write() { return 0; }
_ai_candy_cache_read_persistence_epoch
epoch="$REPLY"
_ai_candy_ai_tool_update_cache_worker \
  "$_AI_CANDY_CODEX_CACHE_FILE" codex \
  https://example.invalid/version 1 \
  "${_AI_CANDY_CODEX_CACHE_FILE}.updating" 1 \
  "$epoch"
""",
                cache_home=root / "cache",
                env={
                    "CURL_LOG": str(curl_log),
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                },
            )
            arguments = curl_log.read_text(encoding="ascii")

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("--proto =https", arguments)
        self.assertIn("--proto-redir =https", arguments)

    def test_tool_status_allows_a_slow_local_cli(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            tool = bin_dir / "kimi"
            tool.write_text(
                "#!/bin/sh\nsleep 0.4\nprintf '%s\\n' 'kimi 1.2.3'\n",
                encoding="ascii",
            )
            tool.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_GH=0
_AI_CANDY_HAS_CLAUDE=0
_AI_CANDY_HAS_CODEX=0
_AI_CANDY_HAS_GEMINI=0
_AI_CANDY_HAS_KIMI=1
_ai_candy_prompt_tool_status
""",
                cache_home=root / "cache",
                env={"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"},
                timeout=3,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("Moonshot Kimi v1.2.3", result.stdout)

    def test_cold_tool_refreshes_share_one_worker_per_shell(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=1
_AI_CANDY_AI_TOOLS_DETECTED=1
_AI_CANDY_HAS_CLAUDE=1
_AI_CANDY_HAS_CODEX=1
_AI_CANDY_HAS_GEMINI=1
_AI_CANDY_HAS_KIMI=1
typeset -g STARTS=0
function _ai_candy_refresh_ai_process_counts() { return 0; }
function _ai_candy_start_registered_background_worker() {
  [[ "$1" == _ai_candy_ai_tools_update_caches_worker ]] || return 71
  (( STARTS++ ))
}
_ai_candy_compute_ai_tools_direct
_ai_candy_compute_ai_tools_direct
print -r -- "STARTS=${STARTS} REQUESTED=${#_AI_CANDY_REFRESH_REQUESTED}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STARTS=1 REQUESTED=4\n", result.stdout)

    def test_cold_gh_auth_refreshes_share_one_worker_per_shell(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_TIMEOUT=1
typeset -gi STARTS=0
function _ai_candy_start_registered_background_worker() {
  [[ "$1" == _ai_candy_gh_auth_update_worker ]] || return 71
  (( ++STARTS ))
  return 0
}
_ai_candy_gh_auth_update_background
_ai_candy_gh_auth_update_background
builtin print -r -- "STARTS=${STARTS} REQUESTED=${#_AI_CANDY_REFRESH_REQUESTED}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STARTS=1 REQUESTED=1\n", result.stdout)

    def test_failed_tool_refresh_retries_and_manual_refresh_releases_throttle(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=1
_AI_CANDY_AI_TOOLS_DETECTED=1
_AI_CANDY_HAS_CLAUDE=0
_AI_CANDY_HAS_CODEX=1
_AI_CANDY_HAS_GEMINI=0
_AI_CANDY_HAS_KIMI=0
_AI_CANDY_TOOL_REFRESH_RETRY_DELAY=30
typeset -g STARTS=0
function _ai_candy_refresh_ai_process_counts() { return 0; }
function _ai_candy_start_registered_background_worker() {
  [[ "$1" == _ai_candy_ai_tools_update_caches_worker ]] || return 71
  (( STARTS++ ))
  return 0
}
_ai_candy_compute_ai_tools_direct
_ai_candy_compute_ai_tools_direct
first_starts="$STARTS"
_AI_CANDY_REFRESH_REQUESTED[tool:$_AI_CANDY_CODEX_CACHE_FILE]=$((
  EPOCHSECONDS - _AI_CANDY_TOOL_REFRESH_RETRY_DELAY - 1
))
_ai_candy_compute_ai_tools_direct
retry_starts="$STARTS"
_ai_candy_prompt_refresh_all_caches >/dev/null
_AI_CANDY_AI_TOOLS_DETECTED=1
_AI_CANDY_HAS_CLAUDE=0
_AI_CANDY_HAS_CODEX=1
_AI_CANDY_HAS_GEMINI=0
_AI_CANDY_HAS_KIMI=0
_ai_candy_compute_ai_tools_direct
print -r -- "STARTS=${first_starts}/${retry_starts}/${STARTS} REQUESTED=${#_AI_CANDY_REFRESH_REQUESTED}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STARTS=1/2/3 REQUESTED=1\n", result.stdout)

    def test_pr_worker_does_not_spawn_an_auth_refresh_worker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            gh = bin_dir / "gh"
            gh.write_text(
                "#!/bin/sh\n"
                'case "$*" in\n'
                "  *'pr view'*) printf '%s\\n' 42 ;;\n"
                "  *'pr checks'*) printf '%s\\n' pass ;;\n"
                "esac\n",
                encoding="ascii",
            )
            gh.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
_AI_CANDY_HAS_GH=1
function _ai_candy_gh_is_authenticated() {
  print -r -- called >| "$AUTH_CALLED_FILE"
  (command sleep 5) </dev/null &>/dev/null &!
  print -r -- "$!" >| "$NESTED_PID_FILE"
  return 0
}
_ai_candy_gh_pr_update_cache remote branch
pr_worker="${_AI_CANDY_BACKGROUND_PIDS[-1]-}"
for attempt in {1..500}; do
  _ai_candy_background_pid_is_owned "$pr_worker" || break
  zselect -t 1
done
nested_alive=no
if [[ -f "$NESTED_PID_FILE" ]]; then
  nested_pid=$(<"$NESTED_PID_FILE")
  if builtin kill -0 "$nested_pid" 2>/dev/null; then
    nested_alive=yes
    builtin kill -KILL "$nested_pid" 2>/dev/null
  fi
fi
print -r -- "AUTH_CALLED=$([[ -f $AUTH_CALLED_FILE ]] && print yes || print no)"
print -r -- "NESTED_ALIVE=${nested_alive}"
""",
                cache_home=root / "cache",
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "AUTH_CALLED_FILE": str(root / "auth-called"),
                    "NESTED_PID_FILE": str(root / "nested-pid"),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("AUTH_CALLED=no\nNESTED_ALIVE=no\n", result.stdout)

    def test_auth_timeout_uses_the_short_refresh_interval(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_ai_candy_cache_read_persistence_epoch || return 70
epoch="$REPLY"
function _ai_candy_run_with_timeout() { return 124; }
_ai_candy_gh_auth_update_worker \
  "$_AI_CANDY_GH_AUTH_UPDATING" 0.01 "$epoch" || return 71
typeset -gi REFRESH_CALLS=0
function _ai_candy_gh_auth_update_background() {
  (( ++REFRESH_CALLS ))
}
_AI_CANDY_GH_AUTH_REFRESH_RETRY_DELAY=0
_ai_candy_gh_is_authenticated || true
print -r -- "REFRESH_CALLS=${REFRESH_CALLS}"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("REFRESH_CALLS=1\n", result.stdout)

    def test_tool_status_does_not_report_unknown_auth_as_logged_out(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_GH=1
_AI_CANDY_HAS_TIMEOUT=1
_AI_CANDY_HAS_CLAUDE=0
_AI_CANDY_HAS_CODEX=0
_AI_CANDY_HAS_GEMINI=0
_AI_CANDY_HAS_KIMI=0
_ai_candy_cache_write "$_AI_CANDY_GH_AUTH_CACHE_FILE" "?|${EPOCHSECONDS}"
_ai_candy_prompt_tool_status
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("Authentication could not be verified", result.stdout)
        self.assertNotIn("Not authenticated", result.stdout)

    def test_pr_check_buckets_have_one_conservative_mapping(self) -> None:
        cases = (
            ("pass\nfail\n", 1, "fail"),
            ("pass\npending\n", 8, "pending"),
            ("pass\ncancel\n", 0, "pending"),
            ("skipping\n", 0, "pass"),
            ("pass\n", 0, "pass"),
            ("", 0, "none"),
        )
        for buckets, check_exit, expected in cases:
            with self.subTest(buckets=buckets), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                bin_dir = root / "bin"
                bin_dir.mkdir()
                gh = bin_dir / "gh"
                gh.write_text(
                    "#!/bin/sh\n"
                    'case "$*" in\n'
                    "  *'auth status'*) exit 0 ;;\n"
                    "  *'pr view'*) printf '%s\\n' 42 ;;\n"
                    "  *'pr checks'*) printf '%s' \"$CHECK_BUCKETS\"; "
                    'exit "$CHECK_EXIT" ;;\n'
                    "esac\n",
                    encoding="ascii",
                )
                gh.chmod(0o755)
                result = run_zsh(
                    r"""
source "$1"
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
_AI_CANDY_HAS_GH=1
_AI_CANDY_GH_AUTH_MEM_CACHE=1
_AI_CANDY_GH_AUTH_MEM_CACHE_TIME=$EPOCHSECONDS
_ai_candy_gh_pr_update_cache remote branch
for attempt in {1..500}; do
  if _ai_candy_cache_persist_read gh_pr 'remote|branch'; then
    print -r -- "VALUE=${REPLY}"
    return 0
  fi
  zselect -t 1
done
return 70
""",
                    cache_home=root / "cache",
                    env={
                        "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                        "CHECK_BUCKETS": buckets,
                        "CHECK_EXIT": str(check_exit),
                    },
                )

                self.assertEqual(0, result.returncode, result.stderr)
                self.assertIn(f"VALUE=42|{expected}|", result.stdout)

    def test_partial_pr_check_output_cannot_be_cached_as_pass(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            gh = bin_dir / "gh"
            gh.write_text(
                "#!/bin/sh\n"
                'case "$*" in\n'
                "  *'auth status'*) exit 0 ;;\n"
                "  *'pr view'*) printf '%s\\n' 42 ;;\n"
                "  *'pr checks'*) printf '%s\\n' pass; sleep 5 ;;\n"
                "esac\n",
                encoding="ascii",
            )
            gh.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
_AI_CANDY_HAS_GH=1
_AI_CANDY_GH_AUTH_MEM_CACHE=1
_AI_CANDY_GH_AUTH_MEM_CACHE_TIME=$EPOCHSECONDS
_AI_CANDY_NETWORK_TIMEOUT=0.1
_ai_candy_gh_pr_update_cache remote branch
for attempt in {1..500}; do
  if _ai_candy_cache_persist_read gh_pr 'remote|branch'; then
    print -r -- "VALUE=${REPLY}"
    return 0
  fi
  zselect -t 1
done
return 70
""",
                cache_home=root / "cache",
                env={"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"},
                timeout=5,
            )

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("VALUE=42|pending|", result.stdout)


if __name__ == "__main__":
    unittest.main()
