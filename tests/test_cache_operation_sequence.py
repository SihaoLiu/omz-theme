#!/usr/bin/env python3
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from tests.theme_test_support import ROOT, THEME, run_zsh


class CacheOperationSequenceTest(unittest.TestCase):
    def test_short_worker_lock_contention_does_not_drop_a_delete(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
functions[_scheduled_operation_without_hold]="${functions[_ai_candy_cache_run_scheduled_operation]}"
function _ai_candy_cache_run_scheduled_operation() {
  if [[ "$1" == set && "$4" == stale ]]; then
    local operation_lock="${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d"
    _ai_candy_cache_lock_acquire \
      "$operation_lock" 300 "$_AI_CANDY_CACHE_OPERATION_WAIT_TICKS" || return 80
    builtin print -r -- held >| "$HOLD_MARKER"
    _ai_candy_sleep_ticks 2
    _ai_candy_cache_lock_release "$operation_lock"
  fi
  _scheduled_operation_without_hold "$@"
}
_ai_candy_cache_set git_root key stale "$EPOCHSECONDS"
for attempt in {1..100}; do
  [[ -f "$HOLD_MARKER" ]] && break
  _ai_candy_sleep_ticks 1
done
[[ -f "$HOLD_MARKER" ]] || return 81
start=$EPOCHREALTIME
_ai_candy_cache_delete_key git_root key
elapsed_ms=$(( (EPOCHREALTIME - start) * 1000 ))
for attempt in {1..500}; do
  [[ ! -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]] && break
  _ai_candy_sleep_ticks 1
done
if _ai_candy_cache_persist_read git_root key; then
  value="$REPLY"
else
  value=missing
fi
printf 'VALUE=%s ELAPSED_MS=%.3f\n' "$value" "$elapsed_ms"
""",
                cache_home=root / "cache",
                env={"HOLD_MARKER": str(root / "held")},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("VALUE=missing", result.stdout)
        elapsed_ms = float(result.stdout.strip().rsplit("=", maxsplit=1)[1])
        self.assertLess(elapsed_ms, 100.0)

    def test_worker_launch_failure_rolls_back_under_the_reservation_lock(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
operation_lock="${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d"
function _ai_candy_start_registered_background_worker() {
  _ai_candy_cache_lock_acquire "$operation_lock" 300 0 || builtin true
  return 1
}
_ai_candy_cache_schedule_operation \
  set git_root key value "$EPOCHSECONDS"
schedule_status=$?
if [[ -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]]; then
  operation_state=present
else
  operation_state=missing
fi
_ai_candy_cache_lock_release "$operation_lock"
print -r -- "STATUS=${schedule_status} OPERATION=${operation_state}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertRegex(
            result.stdout,
            r"^STATUS=[1-9][0-9]* OPERATION=missing\n$",
        )

    def test_worker_launch_failure_releases_the_reserved_operation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
function _ai_candy_start_registered_background_worker() {
  return 1
}
_ai_candy_cache_schedule_operation \
  set git_root key value "$EPOCHSECONDS"
schedule_status=$?
if [[ -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]]; then
  operation_state=present
else
  operation_state=missing
fi
print -r -- "STATUS=${schedule_status} OPERATION=${operation_state}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertRegex(
            result.stdout,
            r"^STATUS=[1-9][0-9]* OPERATION=missing\n$",
        )

    def test_scheduler_rejects_oversized_values_before_reserving(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_VALUE_MAX_BYTES=1024
typeset -gi worker_starts=0
function _ai_candy_start_registered_background_worker() {
  (( worker_starts++ ))
  return 0
}
payload="${(l:1025::x:)}"
_ai_candy_cache_schedule_operation \
  set git_root key "$payload" "$EPOCHSECONDS"
schedule_status=$?
if [[ -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]]; then
  operation_state=present
else
  operation_state=missing
fi
print -r -- \
  "STATUS=${schedule_status} OPERATION=${operation_state} WORKERS=${worker_starts}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "STATUS=1 OPERATION=missing WORKERS=0\n",
            result.stdout,
        )

    def test_scheduler_is_independent_of_ksh_array_indexing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
setopt ksharrays
_ai_candy_cache_schedule_operation \
  set git_root key current "$EPOCHSECONDS"
schedule_status=$?
unsetopt ksharrays
read_status=1
for attempt in {1..100}; do
  if _ai_candy_cache_persist_read git_root key; then
    read_status=0
    break
  fi
  _ai_candy_sleep_ticks 1
done
print -r -- \
  "SCHEDULE=${schedule_status} READ=${read_status} VALUE=${REPLY:-missing}"
_ai_candy_stop_registered_background_jobs
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("SCHEDULE=0 READ=0 VALUE=current|", result.stdout)

    def test_async_persistence_preserves_same_second_write_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
functions[_persist_without_delay]="${functions[_ai_candy_cache_persist_write_unlocked]}"
function _ai_candy_cache_persist_write_unlocked() {
  [[ "$3" == old ]] && zselect -t 30
  _persist_without_delay "$@"
}
now=$EPOCHSECONDS
_ai_candy_cache_set git_root key old "$now"
start=$EPOCHREALTIME
_ai_candy_cache_set git_root key new "$now"
elapsed_ms=$(( (EPOCHREALTIME - start) * 1000 ))
for attempt in {1..500}; do
  [[ ! -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]] && break
  _ai_candy_sleep_ticks 1
done
_ai_candy_cache_persist_read git_root key
print -r -- "VALUE=${REPLY}"
printf 'ELAPSED_MS=%.3f\n' "$elapsed_ms"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("VALUE=new|", result.stdout)
        elapsed_line = next(
            line
            for line in result.stdout.splitlines()
            if line.startswith("ELAPSED_MS=")
        )
        self.assertLess(float(elapsed_line.partition("=")[2]), 100.0)

    def test_cache_delete_supersedes_an_older_async_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
functions[_persist_without_delay]="${functions[_ai_candy_cache_persist_write_unlocked]}"
function _ai_candy_cache_persist_write_unlocked() {
  zselect -t 30
  _persist_without_delay "$@"
}
_ai_candy_cache_set git_root key stale "$EPOCHSECONDS"
start=$EPOCHREALTIME
_ai_candy_cache_delete_key git_root key
elapsed_ms=$(( (EPOCHREALTIME - start) * 1000 ))
for attempt in {1..500}; do
  [[ ! -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]] && break
  _ai_candy_sleep_ticks 1
done
if _ai_candy_cache_persist_read git_root key; then
  print -r -- "VALUE=${REPLY}"
else
  print -r -- "VALUE=missing"
fi
printf 'ELAPSED_MS=%.3f\n' "$elapsed_ms"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("VALUE=missing", result.stdout)
        elapsed_line = next(
            line
            for line in result.stdout.splitlines()
            if line.startswith("ELAPSED_MS=")
        )
        self.assertLess(float(elapsed_line.partition("=")[2]), 100.0)

    def test_async_persistence_orders_operations_across_shells(self) -> None:
        for backend in ("file", "sqlite"):
            with self.subTest(backend=backend):
                if backend == "sqlite" and shutil.which("sqlite3") is None:
                    self.skipTest("sqlite3 is not installed")
                self._assert_cross_shell_cache_order(backend)

    def _assert_cross_shell_cache_order(self, backend: str) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            hold_file = root / "old-write-held"
            older_scheduled_file = root / "old-operations-scheduled"
            release_file = root / "release-old-write"
            scheduled_file = root / "new-operations-scheduled"
            env = {
                **os.environ,
                "XDG_CACHE_HOME": str(cache_home),
                "HOLD_FILE": str(hold_file),
                "OLDER_SCHEDULED_FILE": str(older_scheduled_file),
                "RELEASE_FILE": str(release_file),
                "SCHEDULED_FILE": str(scheduled_file),
                "CACHE_BACKEND": backend,
            }
            if backend == "sqlite":
                initialized = run_zsh(
                    r"""
source "$1"
_ai_candy_cache_backend_init
print -r -- "BACKEND=${_AI_CANDY_CACHE_BACKEND}"
""",
                    cache_home=cache_home,
                )
                self.assertEqual(0, initialized.returncode, initialized.stderr)
                self.assertEqual("BACKEND=sqlite\n", initialized.stdout)
            setup_backend = r"""
if [[ "$CACHE_BACKEND" == file ]]; then
  _AI_CANDY_CACHE_BACKEND_STATE=1
  _AI_CANDY_CACHE_BACKEND=file
else
  [[ -f "$_AI_CANDY_CACHE_DB_FILE" && ! -L "$_AI_CANDY_CACHE_DB_FILE" ]] || return 69
  _AI_CANDY_CACHE_BACKEND_STATE=1
  _AI_CANDY_CACHE_BACKEND=sqlite
fi
"""
            older_script = (
                r"""
source "$1"
"""
                + setup_backend
                + r"""
functions[_persist_without_hold]="${functions[_ai_candy_cache_persist_write_unlocked]}"
function _ai_candy_cache_persist_write_unlocked() {
  if [[ "$3" == old ]]; then
    print -r -- held >| "$HOLD_FILE"
    for attempt in {1..500}; do
      [[ -f "$RELEASE_FILE" ]] && break
      zselect -t 1
    done
    [[ -f "$RELEASE_FILE" ]] || return 70
  fi
  _persist_without_hold "$@"
}
_ai_candy_cache_set git_root ordered old "$EPOCHSECONDS"
for attempt in {1..500}; do
  [[ -f "$HOLD_FILE" ]] && break
  zselect -t 1
done
[[ -f "$HOLD_FILE" ]] || return 71
_ai_candy_cache_set git_root removed stale "$EPOCHSECONDS"
print -r -- scheduled >| "$OLDER_SCHEDULED_FILE"
for attempt in {1..500}; do
  [[ ! -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]] && break
  zselect -t 1
done
[[ ! -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]] || return 72
"""
            )
            newer_script = (
                r"""
source "$1"
"""
                + setup_backend
                + r"""
_ai_candy_cache_set git_root ordered new "$EPOCHSECONDS"
_ai_candy_cache_delete_key git_root removed
print -r -- scheduled >| "$SCHEDULED_FILE"
for attempt in {1..500}; do
  [[ ! -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]] && break
  zselect -t 1
done
[[ ! -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]] || return 73
_ai_candy_cache_persist_read git_root ordered
print -r -- "ORDERED=${REPLY}"
if _ai_candy_cache_persist_read git_root removed; then
  print -r -- "REMOVED=${REPLY}"
else
  print -r -- "REMOVED=missing"
fi
"""
            )

            older = subprocess.Popen(
                ["zsh", "-fc", older_script, "zsh", str(THEME)],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )
            try:
                deadline = time.monotonic() + 5
                while not hold_file.exists() and time.monotonic() < deadline:
                    if older.poll() is not None:
                        break
                    time.sleep(0.01)
                self.assertTrue(
                    hold_file.exists(), "old write never held the commit lock"
                )
                deadline = time.monotonic() + 5
                while not older_scheduled_file.exists() and time.monotonic() < deadline:
                    if older.poll() is not None:
                        break
                    time.sleep(0.01)
                self.assertTrue(
                    older_scheduled_file.exists(),
                    "old operations were not both recorded before the new operations",
                )

                newer = subprocess.Popen(
                    ["zsh", "-fc", newer_script, "zsh", str(THEME)],
                    cwd=ROOT,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=env,
                )
                deadline = time.monotonic() + 5
                while not scheduled_file.exists() and time.monotonic() < deadline:
                    if newer.poll() is not None:
                        break
                    time.sleep(0.01)
                self.assertTrue(
                    scheduled_file.exists(),
                    "new operations were not recorded while the old write was held",
                )
                release_file.touch()
                newer_stdout, newer_stderr = newer.communicate(timeout=8)
                older_stdout, older_stderr = older.communicate(timeout=8)
            finally:
                release_file.touch(exist_ok=True)
                for process in (locals().get("newer"), older):
                    if process is not None and process.poll() is None:
                        process.kill()
                        process.communicate()

            self.assertEqual(0, older.returncode, older_stderr)
            self.assertEqual(0, newer.returncode, newer_stderr)
            self.assertEqual("", older_stdout)
            self.assertIn("ORDERED=new|", newer_stdout)
            self.assertIn("REMOVED=missing", newer_stdout)

    def test_cache_delete_is_not_blocked_by_a_prior_future_clock_token(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
now=$EPOCHSECONDS
_ai_candy_cache_persist_write git_root key stale "$now" || return 70
_ai_candy_hex_encode 'git_root:key'
builtin print -r -- \
  "${REPLY}|v3:30:1|set|$(( now + 60 ))" >| \
  "$_AI_CANDY_CACHE_OPERATION_FILE"
builtin print -r -- "0|1" >| "$_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE"
_ai_candy_cache_delete_key git_root key
zselect -t 60
if _ai_candy_cache_persist_read git_root key; then
  print -r -- "VALUE=${REPLY}"
else
  print -r -- "VALUE=missing"
fi
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("VALUE=missing\n", result.stdout)

    def test_future_clock_orphan_does_not_block_a_new_cache_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
now=$EPOCHSECONDS
_ai_candy_hex_encode 'git_root:key'
builtin print -r -- \
  "${REPLY}|v3:30:1|set|$(( now + 60 ))" >| \
  "$_AI_CANDY_CACHE_OPERATION_FILE"
builtin print -r -- "0|1" >| "$_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE"
_ai_candy_cache_set git_root key current "$now"
zselect -t 60
if _ai_candy_cache_persist_read git_root key; then
  print -r -- "VALUE=${REPLY}"
else
  print -r -- "VALUE=missing"
fi
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("VALUE=current|", result.stdout)

    def test_operation_sequence_is_monotonic_when_timestamps_move_backward(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
now=$EPOCHSECONDS
_ai_candy_cache_reserve_operation set git_root key "$now" || return 70
first_token="${reply[2]}"
_ai_candy_cache_reserve_operation delete git_root key "$(( now - 60 ))" || \
  return 71
second_token="${reply[2]}"
state="$(<"$_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE")"
print -r -- "TOKENS=${first_token},${second_token} STATE=${state}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("TOKENS=v3:30:1,v3:30:2 STATE=0|2\n", result.stdout)

    def test_failed_cache_write_does_not_reveal_the_previous_value(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
now=$EPOCHSECONDS
_ai_candy_cache_persist_write git_root key stale "$now" || return 70
functions[_write_before_failure]="${functions[_ai_candy_cache_persist_write_unlocked]}"
function _ai_candy_cache_persist_write_unlocked() {
  [[ "$3" == current ]] && return 1
  _write_before_failure "$@"
}
_ai_candy_cache_set git_root key current "$now"
zselect -t 60
if _ai_candy_cache_persist_read git_root key; then
  print -r -- "VALUE=${REPLY}"
else
  print -r -- "VALUE=missing"
fi
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("VALUE=missing\n", result.stdout)

    def test_set_commit_survives_a_wall_clock_rollback(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
now=$EPOCHSECONDS
_ai_candy_cache_persist_write git_root key stale "$now" || return 70
_ai_candy_cache_reserve_operation set git_root key "$now" || return 71
reservation=("${reply[@]}")
zmodload -u zsh/datetime
typeset -g EPOCHSECONDS=$(( now - 60 ))
_ai_candy_cache_commit_operation set git_root key current "$now" \
  "${reservation[@]}" || return 72
_ai_candy_cache_persist_read git_root key || return 73
print -r -- "CLOCK=${EPOCHSECONDS} VALUE=${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = result.stdout.strip().split()
        clock = int(fields[0].partition("=")[2])
        value_timestamp = int(fields[1].rsplit("|", maxsplit=1)[1])
        self.assertIn("VALUE=current|", result.stdout)
        self.assertEqual(clock, value_timestamp)

    def test_delete_commit_survives_a_wall_clock_rollback(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
now=$EPOCHSECONDS
_ai_candy_cache_persist_write git_root key stale "$now" || return 70
_ai_candy_cache_reserve_operation delete git_root key "$now" || return 71
reservation=("${reply[@]}")
zmodload -u zsh/datetime
typeset -g EPOCHSECONDS=$(( now - 60 ))
_ai_candy_cache_commit_operation delete git_root key "" "$now" \
  "${reservation[@]}" || return 72
if _ai_candy_cache_persist_read git_root key; then
  print -r -- "VALUE=${REPLY}"
else
  print -r -- "VALUE=missing"
fi
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("VALUE=missing\n", result.stdout)

    def test_operation_line_limit_rejects_without_evicting_a_reservation(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_FILE_CACHE_MAX_LINES=2
now=$EPOCHSECONDS
_ai_candy_cache_reserve_operation set git_root victim "$now" || return 70
victim=("${reply[@]}")
_ai_candy_cache_reserve_operation set git_root first "$now" || return 71
_ai_candy_cache_reserve_operation set git_root second "$now"
reserve_status=$?
_ai_candy_cache_operation_is_current \
  "${victim[1]}" "${victim[2]}" || return 72
lines=("${(@f)$(<"$_AI_CANDY_CACHE_OPERATION_FILE")}")
print -r -- "STATUS=${reserve_status} LINES=${#lines} OPERATION=current"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertRegex(
            result.stdout,
            r"^STATUS=[1-9][0-9]* LINES=2 OPERATION=current\n$",
        )

    def test_operation_byte_limit_rejects_without_evicting_a_reservation(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_FILE_MAX_BYTES=1024
now=$EPOCHSECONDS
_ai_candy_cache_reserve_operation set git_root victim "$now" || return 70
victim=("${reply[@]}")
long_key="${(l:475::x:)}"
_ai_candy_cache_reserve_operation set git_root "$long_key" "$now"
reserve_status=$?
_ai_candy_cache_operation_is_current \
  "${victim[1]}" "${victim[2]}" || return 71
builtin zstat -A metadata +size -- "$_AI_CANDY_CACHE_OPERATION_FILE" || return 72
print -r -- \
  "STATUS=${reserve_status} SIZE=${metadata[1]} OPERATION=current"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(
            field.split("=", maxsplit=1)
            for field in result.stdout.strip().split()
        )
        self.assertNotEqual("0", fields["STATUS"])
        self.assertLessEqual(int(fields["SIZE"]), 1024)
        self.assertEqual("current", fields["OPERATION"])

    def test_wall_clock_rollback_keeps_independent_operations(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
now=$EPOCHSECONDS
_ai_candy_cache_reserve_operation set git_root first "$now" || return 70
first=("${reply[@]}")
_ai_candy_cache_reserve_operation set git_root second "$now" || return 71
second=("${reply[@]}")
first_line="${first[1]}|${first[2]}|set|$(( now + 60 ))"
second_line="${second[1]}|${second[2]}|set|$(( now + 60 ))"
_ai_candy_cache_atomic_write_unlocked "$_AI_CANDY_CACHE_OPERATION_FILE" \
  "${first_line}"$'\n'"${second_line}" || return 72
_ai_candy_cache_commit_operation set git_root first one "$now" \
  "${first[@]}" || return 73
_ai_candy_cache_commit_operation set git_root second two "$now" \
  "${second[@]}" || return 74
_ai_candy_cache_persist_read git_root first || return 75
first_value="$REPLY"
_ai_candy_cache_persist_read git_root second || return 76
print -r -- "FIRST=${first_value} SECOND=${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("FIRST=one|", result.stdout)
        self.assertIn(" SECOND=two|", result.stdout)

    def test_malformed_operation_journal_remains_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
now=$EPOCHSECONDS
_ai_candy_cache_persist_write git_root key stale "$now" || return 70
_ai_candy_cache_reserve_operation set git_root key "$now" || return 71
reservation=("${reply[@]}")
builtin print -r -- malformed >| "$_AI_CANDY_CACHE_OPERATION_FILE"
_ai_candy_cache_commit_operation set git_root key current "$now" \
  "${reservation[@]}"
commit_status=$?
journal=$(<"$_AI_CANDY_CACHE_OPERATION_FILE")
if _ai_candy_cache_persist_read git_root key; then
  value="$REPLY"
else
  value=missing
fi
print -r -- \
  "STATUS=${commit_status} JOURNAL=${journal} VALUE=${value}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertRegex(
            result.stdout,
            r"^STATUS=[1-9][0-9]* JOURNAL=malformed VALUE=missing\n$",
        )

    def test_reservation_does_not_replace_a_malformed_journal(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
now=$EPOCHSECONDS
builtin print -r -- malformed >| "$_AI_CANDY_CACHE_OPERATION_FILE"
_ai_candy_cache_reserve_operation set git_root key "$now"
reserve_status=$?
print -r -- \
  "STATUS=${reserve_status} JOURNAL=$(<"$_AI_CANDY_CACHE_OPERATION_FILE")"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertRegex(
            result.stdout,
            r"^STATUS=[1-9][0-9]* JOURNAL=malformed\n$",
        )

    def test_cleanup_preserves_a_future_operation_reservation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
now=$EPOCHSECONDS
_ai_candy_cache_reserve_operation set git_root key "$now" || return 70
reservation=("${reply[@]}")
builtin print -r -- \
  "${reservation[1]}|${reservation[2]}|set|$(( now + 60 ))" >| \
  "$_AI_CANDY_CACHE_OPERATION_FILE"
_ai_candy_file_cache_prune_unlocked \
  "$_AI_CANDY_CACHE_OPERATION_FILE" "$(( now - 60 ))" operation || return 71
_ai_candy_cache_operation_is_current \
  "${reservation[1]}" "${reservation[2]}" || return 72
print -r -- preserved
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("preserved\n", result.stdout)

    def test_old_epoch_worker_cannot_clear_a_reused_token(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
now=$EPOCHSECONDS
_ai_candy_cache_reserve_operation set git_root key "$now" || return 70
old=("${reply[@]}")
_ai_candy_prompt_refresh_all_caches >/dev/null || return 71
_ai_candy_cache_reserve_operation set git_root key "$now" || return 72
new=("${reply[@]}")
[[ "${old[2]}" != "${new[2]}" ]] || return 73
_ai_candy_cache_commit_operation set git_root key old "$now" "${old[@]}"
old_status=$?
(( old_status != 0 )) || return 74
_ai_candy_cache_operation_is_current "${new[1]}" "${new[2]}" || return 75
_ai_candy_cache_commit_operation set git_root key current "$now" \
  "${new[@]}" || return 76
_ai_candy_cache_persist_read git_root key || return 77
print -r -- "OLD_STATUS=${old_status} VALUE=${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("OLD_STATUS=1 VALUE=current|", result.stdout)

    def test_post_commit_refresh_cannot_clear_a_new_epoch_reservation(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
now=$EPOCHSECONDS
_ai_candy_cache_reserve_operation set git_root key "$now" || return 70
old=("${reply[@]}")
functions[_clear_without_refresh]="${functions[_ai_candy_cache_clear_operation_if_current]}"
typeset -ga replacement
function _ai_candy_cache_clear_operation_if_current() {
  _ai_candy_prompt_refresh_all_caches >/dev/null || return 71
  _ai_candy_cache_reserve_operation set git_root key "$now" || return 72
  replacement=("${reply[@]}")
  _clear_without_refresh "$@"
}
_ai_candy_cache_commit_operation set git_root key old "$now" \
  "${old[@]}"
old_status=$?
(( old_status != 0 )) || return 73
unfunction _ai_candy_cache_clear_operation_if_current
functions[_ai_candy_cache_clear_operation_if_current]="${functions[_clear_without_refresh]}"
_ai_candy_cache_operation_is_current \
  "${replacement[1]}" "${replacement[2]}" || return 74
_ai_candy_cache_commit_operation set git_root key current "$now" \
  "${replacement[@]}" || return 75
_ai_candy_cache_persist_read git_root key || return 76
print -r -- "OLD_STATUS=${old_status} VALUE=${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("OLD_STATUS=1 VALUE=current|", result.stdout)

    def test_partial_epoch_publication_cannot_adopt_old_reservations(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_FILE_CACHE_MAX_LINES=2
now=$EPOCHSECONDS
_ai_candy_cache_reserve_operation set git_root old-one "$now" || return 70
old_one=("${reply[@]}")
_ai_candy_cache_reserve_operation set git_root old-two "$now" || return 71
old_two=("${reply[@]}")
_ai_candy_cache_advance_persistence_epoch_unlocked || return 72
functions[_atomic_without_failure]="${functions[_ai_candy_cache_atomic_write_unlocked]}"
integer publication_writes=0
function _ai_candy_cache_atomic_write_unlocked() {
  if [[ "$1" == "$_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE" || \
        "$1" == "$_AI_CANDY_CACHE_OPERATION_FILE" ]]; then
    (( publication_writes++ ))
    (( publication_writes == 2 )) && return 1
  fi
  _atomic_without_failure "$@"
}
_ai_candy_cache_reserve_operation set git_root interrupted "$now"
interrupted_status=$?
(( interrupted_status != 0 )) || return 73
unfunction _ai_candy_cache_atomic_write_unlocked
functions[_ai_candy_cache_atomic_write_unlocked]="${functions[_atomic_without_failure]}"
_ai_candy_cache_reserve_operation set git_root recovered "$now" || return 74
recovered_token="${reply[2]}"
if _ai_candy_cache_operation_is_current "${old_one[1]}" "${old_one[2]}" || \
   _ai_candy_cache_operation_is_current "${old_two[1]}" "${old_two[2]}"; then
  old_state=current
else
  old_state=missing
fi
print -r -- \
  "INTERRUPTED=${interrupted_status} OLD=${old_state} TOKEN=${recovered_token}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertRegex(
            result.stdout,
            r"^INTERRUPTED=[1-9][0-9]* OLD=missing TOKEN=v[0-9]+:.*\n$",
        )

    def test_failed_cache_delete_does_not_reveal_the_previous_value(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
now=$EPOCHSECONDS
_ai_candy_cache_persist_write git_root key stale "$now" || return 70
function _ai_candy_cache_persist_delete_unlocked() {
  return 1
}
_ai_candy_cache_delete_key git_root key
zselect -t 60
if _ai_candy_cache_persist_read git_root key; then
  print -r -- "VALUE=${REPLY}"
else
  print -r -- "VALUE=missing"
fi
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("VALUE=missing\n", result.stdout)
