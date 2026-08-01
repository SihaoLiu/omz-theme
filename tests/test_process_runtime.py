#!/usr/bin/env python3
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from tests.theme_test_support import (
    ROOT,
    THEME,
    process_is_running,
    run_zsh,
    wait_for_process_exit,
)


class ProcessRuntimeTest(unittest.TestCase):
    def test_dash_without_setsid_is_silent(self) -> None:
        dash = shutil.which("dash")
        if dash is None:
            self.skipTest("dash is not installed")

        true_command = shutil.which("true")
        if true_command is None:
            self.skipTest("true is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
command "$DASH" -c "$_AI_CANDY_TIMEOUT_SUPERVISOR_SCRIPT" \
  ai-candy-timeout "$COMPLETION_FILE" "$GROUP_FILE" "" \
  "$TRUE_COMMAND"
print -r -- "STATUS=$?"
""",
                cache_home=root / "cache",
                env={
                    "COMPLETION_FILE": str(root / "completion"),
                    "DASH": dash,
                    "GROUP_FILE": str(root / "group"),
                    "TRUE_COMMAND": true_command,
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("", result.stderr)
        self.assertEqual("STATUS=125\n", result.stdout)

    def _assert_timeout_stops_output_holding_orphan(
        self, timeout_setup: str, env: dict[str, str]
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            child_pid_file = root / "child.pid"
            child_pid = None
            try:
                result = run_zsh(
                    "\n".join(
                        [
                            'source "$1"',
                            timeout_setup,
                            r"""
start=$EPOCHREALTIME
_ai_candy_run_with_timeout 0.1 sh -c '
  sleep 30 &
  printf "%s\n" "$!" > "$CHILD_PID_FILE"
'
command_status=$?
elapsed=$(( EPOCHREALTIME - start ))
builtin print -r -- "STATUS=${command_status} ELAPSED=${elapsed}"
""",
                        ]
                    ),
                    cache_home=root / "cache",
                    env={"CHILD_PID_FILE": str(child_pid_file), **env},
                    timeout=3,
                )

                self.assertEqual(0, result.returncode, result.stderr)
                fields = dict(
                    field.split("=", maxsplit=1)
                    for field in result.stdout.strip().split()
                )
                self.assertEqual("124", fields["STATUS"])
                self.assertLess(float(fields["ELAPSED"]), 1.0)
                self.assertTrue(child_pid_file.is_file())
                child_pid = int(child_pid_file.read_text(encoding="ascii"))
                self.assertTrue(wait_for_process_exit(child_pid, 1))
            finally:
                if child_pid is None and child_pid_file.is_file():
                    child_pid = int(child_pid_file.read_text(encoding="ascii"))
                if child_pid is not None and process_is_running(child_pid):
                    os.kill(child_pid, signal.SIGKILL)

    def test_external_timeout_stops_output_holding_orphan(self) -> None:
        external_timeout = shutil.which("timeout")
        if external_timeout is None:
            self.skipTest("GNU-compatible timeout is not installed")

        self._assert_timeout_stops_output_holding_orphan(
            "\n".join(
                [
                    "_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0",
                    "_AI_CANDY_HAS_ZSH_SYSTEM=0",
                    '_AI_CANDY_TIMEOUT_CMD="$EXTERNAL_TIMEOUT"',
                ]
            ),
            {"EXTERNAL_TIMEOUT": external_timeout},
        )

    def test_native_timeout_stops_output_holding_orphan(self) -> None:
        self._assert_timeout_stops_output_holding_orphan(
            "_AI_CANDY_TIMEOUT_CMD=zsh-native", {}
        )

    def test_monitor_fallback_stops_output_holding_orphan(self) -> None:
        shell_probe = subprocess.run(
            ["/bin/sh", "-c", 'test -n "${BASH_VERSION-}"'], check=False
        )
        if shell_probe.returncode != 0:
            self.skipTest("the system /bin/sh does not provide Bash job control")

        self._assert_timeout_stops_output_holding_orphan(
            "_AI_CANDY_SETSID_CMD=\n_AI_CANDY_TIMEOUT_CMD=zsh-native", {}
        )

    def test_external_timeout_kills_a_term_ignoring_command(self) -> None:
        external_timeout = shutil.which("timeout")
        if external_timeout is None:
            self.skipTest("GNU-compatible timeout is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            child_pid_file = root / "child.pid"
            child_pid = None
            try:
                result = run_zsh(
                    r"""
source "$1"
_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_TIMEOUT_CMD="$EXTERNAL_TIMEOUT"
_ai_candy_run_with_timeout 0.1 sh -c '
  printf "%s\n" "$$" > "$CHILD_PID_FILE"
  trap "" TERM
  while :; do :; done
'
builtin print -r -- "STATUS=$?"
""",
                    cache_home=root / "cache",
                    env={
                        "CHILD_PID_FILE": str(child_pid_file),
                        "EXTERNAL_TIMEOUT": external_timeout,
                    },
                    timeout=3,
                )

                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual("STATUS=124\n", result.stdout)
                self.assertTrue(child_pid_file.is_file())
                child_pid = int(child_pid_file.read_text(encoding="ascii"))
                self.assertTrue(wait_for_process_exit(child_pid, 1))
            finally:
                if child_pid is None and child_pid_file.is_file():
                    child_pid = int(child_pid_file.read_text(encoding="ascii"))
                if child_pid is not None and process_is_running(child_pid):
                    os.kill(child_pid, signal.SIGKILL)

    def test_native_timeout_readers_have_independent_file_offsets(self) -> None:
        source = (ROOT / "src" / "bootstrap.zsh").read_text(encoding="utf-8")
        function_body = source.partition(
            "function _ai_candy_run_native_timeout() {"
        )[2].partition("\n}\n")[0]
        reader_fds = re.findall(
            r'builtin sysread -i "\$(timeout_[a-z_]+_fd)"', function_body
        )

        self.assertGreaterEqual(len(reader_fds), 2)
        self.assertGreaterEqual(len(set(reader_fds)), 2)
        self.assertNotIn("timeout_marker_fd", reader_fds)

    @unittest.skipUnless(Path("/proc").is_dir(), "Linux procfs is required")
    def test_process_table_uses_procfs_before_external_ps(self) -> None:
        source = (ROOT / "src" / "bootstrap.zsh").read_text(encoding="utf-8")
        function_body = source.partition(
            "function _ai_candy_read_process_table() {"
        )[2].partition("\n}\n")[0]

        self.assertLess(function_body.index("[[ -d /proc ]]"), function_body.index("ps"))

    def test_process_table_failure_discards_a_previous_process_tree(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_TIMEOUT_PROCESS_TREE=(111 222)
function _ai_candy_read_process_table() { return 1; }
_ai_candy_collect_process_tree 333
print -r -- "STATUS=$? TREE=${(j:,:)_AI_CANDY_TIMEOUT_PROCESS_TREE}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=0 TREE=333\n", result.stdout)

    def test_process_tree_parsing_ignores_ambient_ifs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
IFS=$'\x1f'
_ai_candy_collect_process_tree 100 $'100 1 S\n200 100 S\n300 200 S'
builtin print -r -- "TREE=${(j:,:)_AI_CANDY_TIMEOUT_PROCESS_TREE}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("TREE=100,200,300\n", result.stdout)

    @unittest.skipUnless(Path("/proc").is_dir(), "Linux procfs is required")
    def test_background_worker_registration_ignores_ambient_ifs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
saved_ifs="$IFS"
IFS=$'\x1f'
(command sleep 30) </dev/null &>/dev/null &!
worker_pid=$!
_ai_candy_register_background_pid "$worker_pid"
register_status=$?
registered_count=${#_AI_CANDY_BACKGROUND_PIDS}
if (( register_status == 0 )); then
  _ai_candy_stop_registered_background_jobs
else
  builtin kill -TERM "$worker_pid" 2>/dev/null || true
  builtin wait "$worker_pid" 2>/dev/null || true
fi
IFS="$saved_ifs"
if builtin kill -0 "$worker_pid" 2>/dev/null; then
  worker_state=alive
  builtin kill -KILL "$worker_pid" 2>/dev/null || true
  builtin wait "$worker_pid" 2>/dev/null || true
else
  worker_state=stopped
fi
builtin print -r -- \
  "STATUS=${register_status} COUNT=${registered_count} STATE=${worker_state}"
""",
                cache_home=Path(tmp) / "cache",
                timeout=5,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=0 COUNT=1 STATE=stopped\n", result.stdout)

    def test_cache_dependent_worker_is_not_started_without_a_cache(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            marker = root / "worker.started"
            result = run_zsh(
                r"""
source "$1"
function _ai_candy_test_cache_worker() {
  builtin print -r -- started >| "$MARKER"
  zselect -t 100
}
_AI_CANDY_CACHE_READY=0
_ai_candy_start_registered_background_worker _ai_candy_test_cache_worker
worker_status=$?
zselect -t 5
print -r -- "STATUS=${worker_status} JOBS=${#_AI_CANDY_BACKGROUND_PIDS} MARKER=$([[ -e $MARKER ]] && print yes || print no)"
_ai_candy_stop_registered_background_jobs
""",
                cache_home=root / "cache",
                env={"MARKER": str(marker)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=1 JOBS=0 MARKER=no\n", result.stdout)

    def test_theme_does_not_install_a_global_interrupt_trap(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
builtin unfunction TRAPINT 2>/dev/null || true
source "$1"
builtin print -r -- "TRAPINT=${+functions[TRAPINT]}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("TRAPINT=0\n", result.stdout)

    def test_theme_preserves_a_preexisting_interrupt_trap(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
function TRAPINT() { return 130; }
original_trap="${functions[TRAPINT]}"
source "$1"
if [[ "${functions[TRAPINT]}" == "$original_trap" ]]; then
  preserved=yes
else
  preserved=no
fi
builtin print -r -- "PRESERVED=${preserved}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("PRESERVED=yes\n", result.stdout)

    def test_signal_cleanup_stops_workers_and_preserves_existing_trap(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ready_file = root / "ready"
            release_file = root / "worker.release"
            trap_file = root / "trap.called"
            worker_pipe, worker_pipe_child = os.pipe()
            os.set_blocking(worker_pipe, False)
            shell = subprocess.Popen(
                [
                    "zsh",
                    "-fc",
                    r"""
function TRAPTERM() {
  builtin print -r -- called >| "$TRAP_FILE"
  return 143
}
source "$1"
(while [[ ! -e "$WORKER_RELEASE_FILE" ]]; do zselect -t 10; done) \
  </dev/null &>/dev/null &!
worker_pid=$!
exec {WORKER_SENTINEL_FD}>&-
_ai_candy_register_background_pid "$worker_pid"
builtin print -r -- ready >| "$READY_FILE"
while true; do zselect -t 100; done
""",
                    "zsh",
                    str(THEME),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                pass_fds=(worker_pipe_child,),
                env={
                    **os.environ,
                    "XDG_CACHE_HOME": str(root / "cache"),
                    "READY_FILE": str(ready_file),
                    "WORKER_RELEASE_FILE": str(release_file),
                    "WORKER_SENTINEL_FD": str(worker_pipe_child),
                    "TRAP_FILE": str(trap_file),
                },
            )
            os.close(worker_pipe_child)
            try:
                deadline = time.monotonic() + 5
                while not ready_file.exists() and shell.poll() is None:
                    self.assertLess(time.monotonic(), deadline)
                    time.sleep(0.01)
                if shell.poll() is not None:
                    stdout, stderr = shell.communicate()
                    self.fail(
                        f"shell exited early: {shell.returncode}\n"
                        f"stdout: {stdout}\nstderr: {stderr}"
                    )
                os.kill(shell.pid, signal.SIGTERM)
                worker_stopped = False
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    try:
                        worker_stopped = os.read(worker_pipe, 1) == b""
                    except (BlockingIOError, InterruptedError):
                        worker_stopped = False
                    if trap_file.exists() and worker_stopped:
                        break
                    time.sleep(0.01)
                self.assertTrue(trap_file.exists())
                self.assertTrue(worker_stopped)
                self.assertIsNone(shell.poll())
            finally:
                release_file.touch()
                if shell.poll() is None:
                    shell.kill()
                    shell.communicate()
                os.close(worker_pipe)

    def test_signal_cleanup_preserves_default_termination(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            ready_file = root / "ready"
            worker_file = root / "worker.pid"
            worker_pid = None
            shell = subprocess.Popen(
                [
                    "zsh",
                    "-fc",
                    r"""
source "$1"
(command sleep 30) </dev/null &>/dev/null &!
worker_pid=$!
_ai_candy_register_background_pid "$worker_pid"
builtin print -r -- "$worker_pid" >| "$WORKER_FILE"
builtin print -r -- ready >| "$READY_FILE"
while true; do zselect -t 100; done
""",
                    "zsh",
                    str(THEME),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={
                    **os.environ,
                    "XDG_CACHE_HOME": str(root / "cache"),
                    "READY_FILE": str(ready_file),
                    "WORKER_FILE": str(worker_file),
                },
            )
            try:
                deadline = time.monotonic() + 5
                while not ready_file.exists() and shell.poll() is None:
                    self.assertLess(time.monotonic(), deadline)
                    time.sleep(0.01)
                if shell.poll() is not None:
                    stdout, stderr = shell.communicate()
                    self.fail(
                        f"shell exited early: {shell.returncode}\n"
                        f"stdout: {stdout}\nstderr: {stderr}"
                    )
                worker_pid = int(worker_file.read_text(encoding="ascii"))

                os.kill(shell.pid, signal.SIGTERM)
                shell.wait(timeout=5)
                shell.communicate()
                deadline = time.monotonic() + 1
                while process_is_running(worker_pid) and time.monotonic() < deadline:
                    time.sleep(0.01)

                self.assertNotEqual(0, shell.returncode)
                self.assertFalse(process_is_running(worker_pid))
            finally:
                if shell.poll() is None:
                    shell.kill()
                    shell.communicate()
                if worker_pid is not None and process_is_running(worker_pid):
                    os.kill(worker_pid, signal.SIGKILL)

    def test_repeated_source_does_not_wrap_the_existing_signal_trap_again(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
typeset -gi trap_calls=0
function TRAPTERM() {
  (( ++trap_calls ))
  return 143
}
original_trap="${functions[TRAPTERM]}"
source "$1"
source "$1"
if [[ "${functions[_AI_CANDY_PREVIOUS_TRAPTERM]-}" == "$original_trap" ]]; then
  previous_preserved=yes
else
  previous_preserved=no
fi
builtin kill -TERM "$sysparams[pid]"
builtin print -r -- "PREVIOUS=${previous_preserved} CALLS=${trap_calls}"
""",
                cache_home=Path(tmp) / "cache",
                timeout=5,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("PREVIOUS=yes CALLS=1\n", result.stdout)

    def test_async_git_worker_cannot_spawn_an_unowned_persistence_child(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "work"
            work.mkdir()
            child_file = root / "child.pid"
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
function _ai_candy_cache_commit_operation() {
  builtin print -r -- "$sysparams[pid]" >| "$CHILD_FILE"
  zselect -t 3000
}
( _ai_candy_git_prompt_async >/dev/null ) </dev/null &>/dev/null &!
worker_pid=$!
for attempt in {1..500}; do
  builtin kill -0 "$worker_pid" 2>/dev/null || break
  zselect -t 1
done
for attempt in {1..100}; do
  [[ -f "$CHILD_FILE" ]] && break
  zselect -t 1
done
_ai_candy_stop_registered_background_jobs
child_alive=no
if [[ -f "$CHILD_FILE" ]]; then
  child_pid=$(<"$CHILD_FILE")
  if builtin kill -0 "$child_pid" 2>/dev/null; then
    child_alive=yes
    builtin kill -KILL "$child_pid" 2>/dev/null
  fi
fi
print -r -- "CHILD=${child_alive}"
""",
                cache_home=root / "cache",
                cwd=work,
                env={"CHILD_FILE": str(child_file)},
                timeout=8,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CHILD=no\n", result.stdout)

    def test_async_git_worker_cannot_spawn_a_delete_persistence_child(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "work"
            work.mkdir()
            child_file = root / "child.pid"
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
_ai_candy_cache_persist_write git_root "$PWD" NOT_GIT "$EPOCHSECONDS"
_ai_candy_mem_cache_remove_key git_root "$PWD"
git init -q
function _ai_candy_cache_commit_operation() {
  builtin print -r -- "$sysparams[pid]" >| "$CHILD_FILE"
  zselect -t 3000
}
( _ai_candy_git_prompt_async >/dev/null ) </dev/null &>/dev/null &!
worker_pid=$!
for attempt in {1..500}; do
  builtin kill -0 "$worker_pid" 2>/dev/null || break
  zselect -t 1
done
for attempt in {1..100}; do
  [[ -f "$CHILD_FILE" ]] && break
  zselect -t 1
done
_ai_candy_stop_registered_background_jobs
child_alive=no
if [[ -f "$CHILD_FILE" ]]; then
  child_pid=$(<"$CHILD_FILE")
  if builtin kill -0 "$child_pid" 2>/dev/null; then
    child_alive=yes
    builtin kill -KILL "$child_pid" 2>/dev/null
  fi
fi
print -r -- "CHILD=${child_alive}"
""",
                cache_home=root / "cache",
                cwd=work,
                env={"CHILD_FILE": str(child_file)},
                timeout=8,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CHILD=no\n", result.stdout)

    def test_shell_exit_does_not_allow_term_trap_process_escape(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            worker_script = root / "worker.sh"
            worker_pid_file = root / "worker.pid"
            escaped_pid_file = root / "escaped.pid"
            worker_script.write_text(
                "#!/bin/sh\n"
                "trap 'sleep 30 & echo $! > \"$ESCAPED_PID_FILE\"' TERM\n"
                'echo $$ > "$WORKER_PID_FILE"\n'
                "while :; do sleep 1; done\n",
                encoding="ascii",
            )
            worker_script.chmod(0o755)
            escaped_pid = None
            worker_pid = None
            try:
                result = run_zsh(
                    r"""
source "$1"
command "$WORKER_SCRIPT" </dev/null &>/dev/null &!
_ai_candy_register_background_pid "$!"
for attempt in {1..200}; do
  [[ -f "$WORKER_PID_FILE" ]] && break
  zselect -t 1
done
[[ -f "$WORKER_PID_FILE" ]]
""",
                    cache_home=root / "cache",
                    env={
                        "WORKER_SCRIPT": str(worker_script),
                        "WORKER_PID_FILE": str(worker_pid_file),
                        "ESCAPED_PID_FILE": str(escaped_pid_file),
                    },
                )
                self.assertEqual(0, result.returncode, result.stderr)
                worker_pid = int(worker_pid_file.read_text(encoding="ascii"))

                deadline = time.monotonic() + 1
                while not escaped_pid_file.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                if escaped_pid_file.exists():
                    escaped_pid = int(escaped_pid_file.read_text(encoding="ascii"))

                self.assertTrue(wait_for_process_exit(worker_pid, 0.5))
                if escaped_pid is not None:
                    self.assertTrue(wait_for_process_exit(escaped_pid, 0.5))
            finally:
                for pid in (escaped_pid, worker_pid):
                    if pid is None:
                        continue
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_kill_tree_does_not_resume_a_stopped_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            worker_script = root / "worker.zsh"
            root_pid_file = root / "root.pid"
            ready_file = root / "ready"
            escaped_pid_file = root / "escaped.pid"
            worker_script.write_text(
                "#!/usr/bin/env zsh\n"
                "function TRAPCONT() {\n"
                "  (command sleep 30) </dev/null &>/dev/null &\n"
                '  builtin print -r -- $! >| "$ESCAPED_PID_FILE"\n'
                "}\n"
                'builtin print -r -- $$ >| "$ROOT_PID_FILE"\n'
                "(command sleep 30) </dev/null &>/dev/null &\n"
                'builtin print -r -- ready >| "$READY_FILE"\n'
                "builtin wait\n",
                encoding="ascii",
            )
            worker_script.chmod(0o755)
            try:
                result = run_zsh(
                    r"""
source "$1"
command "$WORKER_SCRIPT" </dev/null &>/dev/null &!
worker_pid=$!
for attempt in {1..200}; do
  [[ -f "$READY_FILE" ]] && break
  zselect -t 1
done
[[ -f "$READY_FILE" ]] || return 70
function _ai_candy_process_pid_is_active() {
  zselect -t 5
  return 0
}
_ai_candy_kill_process_tree "$worker_pid"
builtin wait "$worker_pid" 2>/dev/null || true
for attempt in {1..100}; do
  [[ -f "$ESCAPED_PID_FILE" ]] && break
  zselect -t 1
done
escaped=no
if [[ -f "$ESCAPED_PID_FILE" ]]; then
  escaped_pid=$(<"$ESCAPED_PID_FILE")
  if builtin kill -0 "$escaped_pid" 2>/dev/null; then
    escaped=yes
    builtin kill -KILL "$escaped_pid" 2>/dev/null || true
  fi
fi
print -r -- "ESCAPED=${escaped}"
""",
                    cache_home=root / "cache",
                    env={
                        "WORKER_SCRIPT": str(worker_script),
                        "ROOT_PID_FILE": str(root_pid_file),
                        "READY_FILE": str(ready_file),
                        "ESCAPED_PID_FILE": str(escaped_pid_file),
                    },
                    timeout=8,
                )

                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual("ESCAPED=no\n", result.stdout)
            finally:
                for pid_file in (escaped_pid_file, root_pid_file):
                    if not pid_file.is_file():
                        continue
                    pid = int(pid_file.read_text(encoding="ascii"))
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_shell_exit_stops_registered_persistent_cache_worker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            pid_file = root / "worker.pid"
            completion_file = root / "completed"
            worker_pid = None
            try:
                result = run_zsh(
                    r"""
source "$1"
function _ai_candy_cache_persist_write_unlocked() {
  print -r -- "${sysparams[pid]}" >| "$WORKER_PID_FILE"
  sleep 30
  print -r -- done >| "$COMPLETION_FILE"
}
_ai_candy_cache_set git_root key value "$EPOCHSECONDS"
for attempt in {1..100}; do
  [[ -f "$WORKER_PID_FILE" ]] && break
  zselect -t 1
done
[[ -f "$WORKER_PID_FILE" ]]
""",
                    cache_home=root / "cache",
                    env={
                        "WORKER_PID_FILE": str(pid_file),
                        "COMPLETION_FILE": str(completion_file),
                    },
                )

                self.assertEqual(0, result.returncode, result.stderr)
                worker_pid = int(pid_file.read_text(encoding="ascii"))
                self.assertFalse(process_is_running(worker_pid))
                self.assertFalse(completion_file.exists())
            finally:
                if worker_pid is not None:
                    try:
                        os.kill(worker_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_shell_exit_kills_term_ignoring_worker_descendant(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            child_pid_file = root / "child.pid"
            child_pid = None
            try:
                result = run_zsh(
                    r"""
source "$1"
(
  (
    trap '' HUP INT TERM
    print -r -- "${sysparams[pid]}" >| "$CHILD_PID_FILE"
    while true; do zselect -t 100; done
  ) &
  wait
) </dev/null &>/dev/null &!
_ai_candy_register_background_pid "$!"
for attempt in {1..100}; do
  [[ -f "$CHILD_PID_FILE" ]] && break
  zselect -t 1
done
[[ -f "$CHILD_PID_FILE" ]]
""",
                    cache_home=root / "cache",
                    env={"CHILD_PID_FILE": str(child_pid_file)},
                )

                self.assertEqual(0, result.returncode, result.stderr)
                child_pid = int(child_pid_file.read_text(encoding="ascii"))
                deadline = time.monotonic() + 1.0
                while time.monotonic() < deadline:
                    if not process_is_running(child_pid):
                        break
                    time.sleep(0.01)
                else:
                    self.fail(f"worker descendant {child_pid} survived shell exit")
            finally:
                if child_pid is not None:
                    try:
                        os.kill(child_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_finished_background_jobs_are_pruned_from_registry(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
for iteration in {1..20}; do
  (true) &!
  _ai_candy_register_background_pid "$!"
done
zselect -t 5
_ai_candy_prune_registered_background_pids
print -r -- "COUNT=${#_AI_CANDY_BACKGROUND_PIDS}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("COUNT=0\n", result.stdout)

    def test_background_worker_registry_has_a_hard_limit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
function _test_background_worker() { command sleep 30; }
integer rejected=0
for iteration in {1..24}; do
  _ai_candy_start_registered_background_worker _test_background_worker || (( rejected++ ))
done
_ai_candy_prune_registered_background_pids
print -r -- "COUNT=${#_AI_CANDY_BACKGROUND_PIDS} REJECTED=${rejected} LIMIT=${_AI_CANDY_BACKGROUND_JOB_LIMIT}"
_ai_candy_stop_registered_background_jobs
""",
                cache_home=Path(tmp) / "cache",
                timeout=8,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("COUNT=16 REJECTED=8 LIMIT=16\n", result.stdout)

    def test_registration_failure_stops_and_reaps_the_started_worker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
typeset -g FAILED_WORKER_PID=0
function _ai_candy_register_background_pid() {
  FAILED_WORKER_PID="$1"
  return 1
}
function _test_background_worker() { command sleep 30; }
_ai_candy_start_registered_background_worker _test_background_worker
worker_status=$?
if builtin kill -0 "$FAILED_WORKER_PID" 2>/dev/null; then
  worker_state=alive
  builtin kill -KILL "$FAILED_WORKER_PID" 2>/dev/null || true
  builtin wait "$FAILED_WORKER_PID" 2>/dev/null || true
else
  worker_state=stopped
fi
print -r -- \
  "STATUS=${worker_status} COUNT=${#_AI_CANDY_BACKGROUND_PIDS} STATE=${worker_state}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=1 COUNT=0 STATE=stopped\n", result.stdout)

    def test_timeout_output_prefers_the_local_temporary_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            temp_dir = root / "tmp"
            temp_dir.mkdir()
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_TIMEOUT_STALE_FILES_SCANNED=0
_ai_candy_create_timeout_output_file || return 70
output_file="$REPLY"
print -r -- "ROOT=${output_file:h}"
_ai_candy_remove_timeout_files "$output_file"
""",
                cache_home=root / "cache",
                env={"TMPDIR": str(temp_dir)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        output_root = Path(result.stdout.strip().partition("=")[2])
        self.assertEqual(temp_dir, output_root.parent)

    def test_background_cleanup_does_not_signal_a_reused_pid_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
(command sleep 30) </dev/null &>/dev/null &!
worker_pid=$!
_ai_candy_register_background_pid "$worker_pid"
_AI_CANDY_BACKGROUND_IDENTITIES[$worker_pid]="mismatched-start"
_ai_candy_stop_registered_background_jobs
if builtin kill -0 "$worker_pid" 2>/dev/null; then
  state=alive
  builtin kill -KILL "$worker_pid" 2>/dev/null || true
  builtin wait "$worker_pid" 2>/dev/null || true
else
  state=stopped
fi
print -r -- "STATE=${state}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATE=alive\n", result.stdout)

    def test_background_cleanup_resumes_a_root_stopped_before_identity_loss(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
function _test_background_worker() {
  function TRAPCONT() {
    builtin print -r -- resumed >| "$RESUMED_FILE"
    exit 0
  }
  builtin print -r -- ready >| "$READY_FILE"
  while true; do
    zselect -t 100
  done
}
_test_background_worker </dev/null &>/dev/null &!
worker_pid=$!
_ai_candy_register_background_pid "$worker_pid" || return 70
for attempt in {1..100}; do
  [[ -f "$READY_FILE" ]] && break
  zselect -t 1
done
[[ -f "$READY_FILE" ]] || return 71
functions[_identity_before_failure]="${functions[_ai_candy_background_pid_identity]}"
typeset -gi IDENTITY_CALLS=0
function _ai_candy_background_pid_identity() {
  (( ++IDENTITY_CALLS ))
  (( IDENTITY_CALLS < 2 )) || return 1
  _identity_before_failure "$@"
}
_ai_candy_stop_registered_background_jobs
for attempt in {1..100}; do
  [[ -f "$RESUMED_FILE" ]] && break
  zselect -t 1
done
[[ -f "$RESUMED_FILE" ]] && state=resumed || state=stopped
builtin kill -KILL "$worker_pid" 2>/dev/null || true
builtin wait "$worker_pid" 2>/dev/null || true
builtin print -r -- "STATE=${state}"
""",
                cache_home=root / "cache",
                env={
                    "READY_FILE": str(root / "ready"),
                    "RESUMED_FILE": str(root / "resumed"),
                },
                timeout=3,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATE=resumed\n", result.stdout)

    def test_timeout_runner_localizes_hostile_shell_options(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
setopt KSH_ARRAYS SH_WORD_SPLIT GLOB_SUBST
output=$(_ai_candy_run_with_timeout 0.2 /bin/echo isolated) || return 70
builtin print -r -- "OUTPUT=${output} KSH=${options[ksharrays]}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("OUTPUT=isolated KSH=on\n", result.stdout)

    def test_background_cleanup_never_resumes_worker_body_after_child_kill(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
function _test_background_worker() {
  builtin print -r -- started >| "$STARTED_FILE"
  command sleep 30
  builtin print -r -- leaked >| "$LEAK_FILE"
}
_ai_candy_start_registered_background_worker _test_background_worker
for attempt in {1..100}; do
  [[ -f "$STARTED_FILE" ]] && break
  _ai_candy_sleep_ticks 1
done
[[ -f "$STARTED_FILE" ]] || exit 2
_ai_candy_stop_registered_background_jobs
_ai_candy_sleep_ticks 2
[[ -f "$LEAK_FILE" ]] && leaked=yes || leaked=no
print -r -- "LEAK=${leaked} COUNT=${#_AI_CANDY_BACKGROUND_PIDS}"
""",
                cache_home=root / "cache",
                env={
                    "LEAK_FILE": str(root / "leaked"),
                    "STARTED_FILE": str(root / "started"),
                },
                timeout=5,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("", result.stderr)
        self.assertEqual("LEAK=no COUNT=0\n", result.stdout)

    @unittest.skipUnless(Path("/proc").is_dir(), "Linux procfs is required")
    def test_missing_linux_pid_identity_never_falls_back_to_path_ps(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            marker = root / "ps.called"
            bin_dir.mkdir()
            fake_ps = bin_dir / "ps"
            fake_ps.write_text(
                "#!/bin/sh\nprintf 'called\\n' >> \"$PS_MARKER\"\nexit 1\n",
                encoding="ascii",
            )
            fake_ps.chmod(0o755)
            pid_max = int(Path("/proc/sys/kernel/pid_max").read_text(encoding="ascii"))
            result = run_zsh(
                r"""
source "$1"
_ai_candy_background_pid_identity "$DEAD_PID" || identity_status=$?
_ai_candy_background_pid_parent_is_shell "$DEAD_PID" || owner_status=$?
print -r -- "IDENTITY=${identity_status:-0} OWNER=${owner_status:-0}"
""",
                cache_home=root / "cache",
                env={
                    "DEAD_PID": str(pid_max + 1),
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "PS_MARKER": str(marker),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("IDENTITY=1 OWNER=1\n", result.stdout)
        self.assertFalse(marker.exists())

    def test_background_worker_does_not_leak_lock_into_parent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            tool = bin_dir / "version-tool"
            tool.write_text("#!/bin/sh\nprintf '%s\\n' 1.2.3\n", encoding="ascii")
            tool.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_CURL=0
_ai_candy_ai_tool_update_cache "${_AI_CANDY_CACHE_DIR}/version-tool" version-tool ignored
print -r -- "PARENT_LOCKS=${#_AI_CANDY_CACHE_LOCK_FDS}"
""",
                cache_home=root / "cache",
                env={"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("PARENT_LOCKS=0\n", result.stdout)

    def _assert_timeout_cleans_up_when_shell_is_terminated(
        self, timeout_setup: str, env_overrides: dict[str, str]
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            child_pid_file = root / "child.pid"
            env = {
                **os.environ,
                "XDG_CACHE_HOME": str(root / "cache"),
                "CHILD_PID_FILE": str(child_pid_file),
                **env_overrides,
            }
            process = subprocess.Popen(
                [
                    "zsh",
                    "-fc",
                    "\n".join(
                        [
                            'source "$1"',
                            timeout_setup,
                            r"""
_ai_candy_run_with_timeout 30 sh -c 'printenv PPID >/dev/null; echo $$ > "$CHILD_PID_FILE"; exec sleep 30'
builtin print -r -- SURVIVED
""",
                        ]
                    ),
                    "zsh",
                    str(THEME),
                ],
                cwd=ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            child_pid = None
            try:
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline and not child_pid_file.exists():
                    time.sleep(0.01)
                self.assertTrue(child_pid_file.exists(), "timeout child did not start")
                child_pid = int(child_pid_file.read_text(encoding="ascii"))
                process.send_signal(signal.SIGTERM)
                stdout, _ = process.communicate(timeout=3)

                self.assertNotEqual(0, process.returncode)
                self.assertNotIn("SURVIVED", stdout)

                deadline = time.monotonic() + 2
                while process_is_running(child_pid) and time.monotonic() < deadline:
                    time.sleep(0.02)
                if process_is_running(child_pid):
                    self.fail(
                        f"timeout child survived wrapper termination: {child_pid}"
                    )
            finally:
                if child_pid is not None:
                    try:
                        os.kill(child_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                if process.poll() is None:
                    process.kill()
                    process.communicate()

    def test_external_timeout_cleans_up_when_its_shell_is_terminated(self) -> None:
        external_timeout = shutil.which("timeout")
        if external_timeout is None:
            self.skipTest("GNU-compatible timeout is not installed")

        self._assert_timeout_cleans_up_when_shell_is_terminated(
            "\n".join(
                [
                    "_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0",
                    "_AI_CANDY_HAS_ZSH_SYSTEM=0",
                    '_AI_CANDY_TIMEOUT_CMD="$EXTERNAL_TIMEOUT"',
                ]
            ),
            {"EXTERNAL_TIMEOUT": external_timeout},
        )

    def test_native_timeout_cleans_up_when_its_shell_is_terminated(self) -> None:
        self._assert_timeout_cleans_up_when_shell_is_terminated(
            "_AI_CANDY_TIMEOUT_CMD=zsh-native", {}
        )

    def test_native_timeout_preserves_fast_command_output_and_status(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_TIMEOUT=0
_AI_CANDY_TIMEOUT_CMD=""
output=$(_ai_candy_run_with_timeout 0.5 sh -c 'printf result; exit 7')
command_status=$?
print -r -- "OUTPUT=${output}"
print -r -- "STATUS=${command_status}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("OUTPUT=result", result.stdout)
        self.assertIn("STATUS=7", result.stdout)

    def test_native_timeout_discards_partial_output_after_deadline(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_TIMEOUT=0
_AI_CANDY_TIMEOUT_CMD=""
output=$(_ai_candy_run_with_timeout 0.1 sh -c 'printf partial; sleep 1')
command_status=$?
print -r -- "STATUS=${command_status} BYTES=${#output}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=124 BYTES=0\n", result.stdout)

    def test_native_timeout_discards_output_from_reserved_status_124(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_TIMEOUT=0
_AI_CANDY_TIMEOUT_CMD=""
output=$(_ai_candy_run_with_timeout 1 sh -c 'printf partial; exit 124')
command_status=$?
print -r -- "STATUS=${command_status} BYTES=${#output}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=124 BYTES=0\n", result.stdout)

    def test_native_timeout_does_not_expire_an_unreaped_finished_child(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
typeset -g test_timeout_shell_pid="${sysparams[pid]}"
function _ai_candy_process_pid_is_active() {
  return 0
}
function _ai_candy_sleep_ticks() {
  (
    command sleep 1.5
    builtin kill -CONT "$test_timeout_shell_pid" 2>/dev/null
  ) </dev/null &>/dev/null &!
  builtin kill -STOP "$test_timeout_shell_pid"
  local marker_state=""
  local -a marker_files
  integer attempts=0
  while (( attempts < 100 )); do
    marker_files=("$_AI_CANDY_CACHE_DIR"/ai-candy-timeout.*.expired(N))
    if (( ${#marker_files} == 1 )); then
      marker_state="$(<"${marker_files[1]}")"
      [[ "$marker_state" == *completed* ]] && break
    fi
    command sleep 0.01
    (( ++attempts ))
  done
  [[ "$marker_state" == *completed* ]]
}
_ai_candy_run_native_timeout 0.1 command sleep 0.02
print -r -- "STATUS=$?"
""",
                cache_home=Path(tmp) / "cache",
                timeout=6,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=0\n", result.stdout)

    def test_native_timeout_redispatches_an_existing_signal_trap(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
typeset -gi trap_calls=0
typeset -g trap_signal=""
function TRAPTERM() {
  (( ++trap_calls ))
  trap_signal="$1"
  return 143
}
source "$1"
( zselect -t 5; builtin kill -TERM "$sysparams[ppid]" ) &!
_ai_candy_run_native_timeout 5 command sleep 5
command_status=$?
builtin print -r -- \
  "CALLS=${trap_calls} SIGNAL=${trap_signal} STATUS=${command_status}"
""",
                cache_home=Path(tmp) / "cache",
                timeout=5,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CALLS=1 SIGNAL=15 STATUS=143\n", result.stdout)

    def test_native_timeout_uses_a_signal_trap_installed_after_theme(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
typeset -gi trap_calls=0
typeset -g trap_signal=""
function TRAPTERM() {
  (( ++trap_calls ))
  trap_signal="$1"
  return 143
}
( zselect -t 5; builtin kill -TERM "$sysparams[ppid]" ) &!
_ai_candy_run_native_timeout 5 command sleep 5
command_status=$?
builtin print -r -- \
  "CALLS=${trap_calls} SIGNAL=${trap_signal} STATUS=${command_status}"
""",
                cache_home=Path(tmp) / "cache",
                timeout=5,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CALLS=1 SIGNAL=15 STATUS=143\n", result.stdout)

    def test_native_timeout_redispatches_an_existing_interrupt_trap(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
typeset -gi trap_calls=0
typeset -g trap_signal=""
function TRAPINT() {
  (( ++trap_calls ))
  trap_signal="$1"
  return 130
}
source "$1"
( zselect -t 5; builtin kill -INT "$sysparams[ppid]" ) &!
_ai_candy_run_native_timeout 5 command sleep 5
command_status=$?
builtin print -r -- \
  "CALLS=${trap_calls} SIGNAL=${trap_signal} STATUS=${command_status}"
""",
                cache_home=Path(tmp) / "cache",
                timeout=5,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CALLS=1 SIGNAL=2 STATUS=130\n", result.stdout)

    def test_native_timeout_preserves_noninteractive_default_interrupt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
( zselect -t 5; builtin kill -INT "$sysparams[ppid]" ) &!
_ai_candy_run_native_timeout 5 command sleep 5
builtin print -r -- SURVIVED
""",
                cache_home=Path(tmp) / "cache",
                timeout=5,
            )

        self.assertNotEqual(0, result.returncode)
        self.assertNotIn("SURVIVED", result.stdout)

    def test_native_timeout_returns_interrupt_status_in_an_interactive_shell(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cache_home = Path(tmp) / "cache"
            prompt_cache = cache_home / "zsh-prompt"
            prompt_cache.mkdir(parents=True)
            (prompt_cache / "network_mode").write_text("0\n", encoding="ascii")
            result = subprocess.run(
                [
                    "zsh",
                    "-dfi",
                    "-c",
                    r"""
source "$1"
parent_pid="${sysparams[pid]-$$}"
( zselect -t 5; builtin kill -INT "$parent_pid" ) &!
_ai_candy_run_native_timeout 5 command sleep 5
command_status=$?
builtin print -r -- "STATUS=${command_status}"
exit 0
""",
                    "zsh",
                    str(THEME),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={
                    **os.environ,
                    "TERM": "xterm-256color",
                    "XDG_CACHE_HOME": str(cache_home),
                },
                check=False,
                timeout=5,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("STATUS=130", result.stdout)

    def test_direct_exec_stops_registered_workers_before_replacing_the_shell(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            prompt_cache = cache_home / "zsh-prompt"
            prompt_cache.mkdir(parents=True)
            (prompt_cache / "network_mode").write_text("0\n", encoding="ascii")
            worker_file = root / "worker.pid"
            result_file = root / "result"
            commands = f'''\
source "{THEME}"
( sleep 30 ) </dev/null &>/dev/null &!
worker_pid=$!
_ai_candy_register_background_pid "$worker_pid"
print -r -- "$worker_pid" >| "{worker_file}"
exec /bin/sh -c 'if kill -0 "$1" 2>/dev/null; then printf alive; else printf stopped; fi > "$2"' sh "$worker_pid" "{result_file}"
'''
            shell = subprocess.run(
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
            worker_pid = int(worker_file.read_text(encoding="ascii").strip())
            if process_is_running(worker_pid):
                os.kill(worker_pid, signal.SIGKILL)
            result_text = result_file.read_text(encoding="ascii")

        self.assertEqual(0, shell.returncode, shell.stderr)
        self.assertEqual("stopped", result_text)

    def test_command_list_exec_stops_registered_workers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            prompt_cache = cache_home / "zsh-prompt"
            prompt_cache.mkdir(parents=True)
            (prompt_cache / "network_mode").write_text("0\n", encoding="ascii")
            worker_file = root / "worker.pid"
            result_file = root / "result"
            commands = f'''\
source "{THEME}"
( sleep 30 ) </dev/null &>/dev/null &!
worker_pid=$!
_ai_candy_register_background_pid "$worker_pid"
print -r -- "$worker_pid" >| "{worker_file}"
true && exec /bin/sh -c 'if kill -0 "$1" 2>/dev/null; then printf alive; else printf stopped; fi > "$2"' sh "$worker_pid" "{result_file}"
'''
            shell = subprocess.run(
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
            worker_pid = int(worker_file.read_text(encoding="ascii").strip())
            if process_is_running(worker_pid):
                os.kill(worker_pid, signal.SIGKILL)
            result_text = result_file.read_text(encoding="ascii")

        self.assertEqual(0, shell.returncode, shell.stderr)
        self.assertEqual("stopped", result_text)

    def test_command_list_preexec_hook_stops_registered_workers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
(command sleep 30) </dev/null &>/dev/null &!
worker_pid=$!
_ai_candy_register_background_pid "$worker_pid"
for hook in "${preexec_functions[@]}"; do
  "$hook" "true && exec /bin/true" "true && exec /bin/true" \
    "true && exec /bin/true"
done
process_state=$(/bin/ps -o stat= -p "$worker_pid" 2>/dev/null)
process_state="${process_state//[[:space:]]/}"
if [[ -n "$process_state" && "$process_state" != Z* ]]; then
  state=alive
  builtin kill -KILL "$worker_pid" 2>/dev/null || true
  builtin wait "$worker_pid" 2>/dev/null || true
else
  state=stopped
fi
print -r -- "STATE=${state}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATE=stopped\n", result.stdout)

    def test_exec_cleanup_preexec_hook_preserves_reply(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
(command sleep 30) </dev/null &>/dev/null &!
worker_pid=$!
_ai_candy_register_background_pid "$worker_pid"
REPLY=preserved
_ai_candy_preexec_cleanup_for_exec \
  'false && exec /bin/true' 'false && exec /bin/true' \
  'false && exec /bin/true'
builtin print -r -- "REPLY=${REPLY}"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("REPLY=preserved\n", result.stdout)

    def test_compound_command_exec_stops_registered_workers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
integer failures=0
for command_text in \
    'if true; then exec /bin/true; fi' \
    '{ exec /bin/true; }' \
    'for item in one; do exec /bin/true; done'; do
  (command sleep 30) </dev/null &>/dev/null &!
  worker_pid=$!
  _ai_candy_register_background_pid "$worker_pid"
  _ai_candy_preexec_cleanup_for_exec "$command_text" "$command_text" "$command_text"
  if _ai_candy_background_pid_is_owned "$worker_pid"; then
    (( failures++ ))
    _ai_candy_stop_registered_background_jobs
  fi
done
print -r -- "FAILURES=${failures}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("FAILURES=0\n", result.stdout)

    def test_exec_cleanup_handles_glob_substitution_without_changing_it(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
setopt globsubst
(command sleep 30) </dev/null &>/dev/null &!
worker_pid=$!
_ai_candy_register_background_pid "$worker_pid"
_ai_candy_preexec_cleanup_for_exec \
  'true || exec /bin/true' 'true || exec /bin/true' \
  'true || exec /bin/true'
if _ai_candy_background_pid_is_owned "$worker_pid"; then
  state=alive
  _ai_candy_stop_registered_background_jobs
else
  state=stopped
fi
print -r -- "STATE=${state} GLOB_SUBST=${options[globsubst]}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATE=stopped GLOB_SUBST=on\n", result.stdout)

    def test_exec_text_in_an_argument_does_not_stop_registered_workers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
(command sleep 30) </dev/null &>/dev/null &!
worker_pid=$!
_ai_candy_register_background_pid "$worker_pid"
_ai_candy_preexec_cleanup_for_exec \
  "print -r -- 'exec /bin/true'" "print -r -- 'exec /bin/true'"
if _ai_candy_background_pid_is_owned "$worker_pid"; then
  state=alive
else
  state=stopped
fi
_ai_candy_stop_registered_background_jobs
print -r -- "STATE=${state}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATE=alive\n", result.stdout)

    def test_exec_inside_a_subshell_does_not_stop_parent_workers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
(command sleep 30) </dev/null &>/dev/null &!
worker_pid=$!
_ai_candy_register_background_pid "$worker_pid"
_ai_candy_preexec_cleanup_for_exec \
  '( exec /bin/true )' '( exec /bin/true )' '( exec /bin/true )'
if _ai_candy_background_pid_is_owned "$worker_pid"; then
  state=alive
else
  state=stopped
fi
_ai_candy_stop_registered_background_jobs
print -r -- "STATE=${state}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATE=alive\n", result.stdout)

    def test_exec_cleanup_runs_after_other_theme_preexec_hooks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
function _ai_candy_prompt_mark_git_cache_invalidation() {
  (command sleep 30) </dev/null &>/dev/null &!
  worker_pid=$!
  _ai_candy_register_background_pid "$worker_pid"
}
for hook in "${preexec_functions[@]}"; do
  "$hook" "exec /bin/true" "exec /bin/true" "exec /bin/true"
done
process_state=$(/bin/ps -o stat= -p "$worker_pid" 2>/dev/null)
process_state="${process_state//[[:space:]]/}"
if [[ -n "$process_state" && "$process_state" != Z* ]]; then
  state=alive
  builtin kill -KILL "$worker_pid" 2>/dev/null || true
  builtin wait "$worker_pid" 2>/dev/null || true
else
  state=stopped
fi
print -r -- "STATE=${state}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATE=stopped\n", result.stdout)

    def test_native_timeout_stops_slow_command_within_budget(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_TIMEOUT=0
_AI_CANDY_TIMEOUT_CMD=""
start=$EPOCHREALTIME
_ai_candy_run_with_timeout 0.1 sh -c 'sleep 2'
command_status=$?
elapsed=$(( EPOCHREALTIME - start ))
print -r -- "STATUS=${command_status}"
print -r -- "ELAPSED=${elapsed}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("STATUS=124", result.stdout)
        elapsed_line = next(
            line for line in result.stdout.splitlines() if line.startswith("ELAPSED=")
        )
        elapsed = float(elapsed_line.partition("=")[2])
        self.assertGreater(elapsed, 0.06)
        self.assertLess(elapsed, 0.6)

    def test_native_timeout_terminates_descendant_processes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_TIMEOUT=0
_AI_CANDY_TIMEOUT_CMD=""
pid_file="${XDG_CACHE_HOME}/child.pid"
_ai_candy_run_with_timeout 0.1 sh -c 'sleep 5 & printf "%s\n" "$!" > "$1"; wait' sh "$pid_file"
command_status=$?
zselect -t 10
child_pid=$(<"$pid_file")
if kill -0 "$child_pid" 2>/dev/null; then
  process_state=""
  if [[ -r "/proc/${child_pid}/stat" ]]; then
    stat_tail="$(<"/proc/${child_pid}/stat")"
    stat_tail="${stat_tail##*) }"
    process_state="${stat_tail%% *}"
  fi
  if [[ "$process_state" == Z ]]; then
    alive=0
  else
    alive=1
    kill -KILL "$child_pid" 2>/dev/null
  fi
else
  alive=0
fi
print -r -- "STATUS=${command_status}"
print -r -- "ALIVE=${alive}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("STATUS=124", result.stdout)
        self.assertIn("ALIVE=0", result.stdout)

    def test_native_timeout_prevents_term_trap_process_escape(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            escaped_pid_file = root / "escaped.pid"
            escaped_pid = None
            try:
                result = run_zsh(
                    r"""
source "$1"
_AI_CANDY_TIMEOUT_CMD=zsh-native
_ai_candy_run_with_timeout 0.1 sh -c 'trap "sleep 30 </dev/null >/dev/null 2>&1 & printf \"%s\\n\" \$! > \"\$1\"; exit 0" TERM; while :; do :; done' sh "$ESCAPED_PID_FILE"
command_status=$?
for attempt in {1..100}; do
  [[ -f "$ESCAPED_PID_FILE" ]] && break
  zselect -t 1
done
if [[ -f "$ESCAPED_PID_FILE" ]]; then
  escaped_pid=$(<"$ESCAPED_PID_FILE")
  if kill -0 "$escaped_pid" 2>/dev/null; then
    alive=1
  else
    alive=0
  fi
else
  escaped_pid=""
  alive=0
fi
print -r -- "STATUS=${command_status}"
print -r -- "PID=${escaped_pid}"
print -r -- "ALIVE=${alive}"
""",
                    cache_home=root / "cache",
                    env={"ESCAPED_PID_FILE": str(escaped_pid_file)},
                )

                if escaped_pid_file.exists():
                    escaped_pid = int(escaped_pid_file.read_text(encoding="ascii"))
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertIn("STATUS=124", result.stdout)
                self.assertIn("ALIVE=0", result.stdout)
            finally:
                if escaped_pid is not None:
                    try:
                        os.kill(escaped_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

if __name__ == "__main__":
    unittest.main()
