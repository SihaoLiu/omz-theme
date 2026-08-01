#!/usr/bin/env python3
import hashlib
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from tests.theme_test_support import run_zsh


class CommandRuntimeTest(unittest.TestCase):
    def test_sleep_ticks_is_safe_with_errexit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
setopt errexit
_ai_candy_sleep_ticks 1
builtin print -r -- survived
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("survived\n", result.stdout)

    def test_optional_tool_detection_requires_external_executables(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            empty_bin = root / "bin"
            empty_bin.mkdir()
            result = run_zsh(
                r"""
function claude() { return 0; }
function codex() { return 0; }
function gemini() { return 0; }
function kimi() { return 0; }
path=("$EMPTY_BIN")
rehash
source "$1"
_ai_candy_prompt_refresh_all_caches >/dev/null
print -r -- "TOOLS=${_AI_CANDY_HAS_CLAUDE}${_AI_CANDY_HAS_CODEX}${_AI_CANDY_HAS_GEMINI}${_AI_CANDY_HAS_KIMI}"
""",
                cache_home=root / "cache",
                env={"EMPTY_BIN": str(empty_bin)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("TOOLS=0000\n", result.stdout)

    def test_theme_source_does_not_call_a_shadowed_module_loader(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shadow_log = root / "shadowed"
            result = run_zsh(
                r"""
function zmodload() { print -r -- called >| "$SHADOW_LOG"; }
source "$1"
print -r -- "SHADOWED=$([[ -f $SHADOW_LOG ]] && print yes || print no)"
""",
                cache_home=root / "cache",
                env={"SHADOW_LOG": str(shadow_log)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("SHADOWED=no\n", result.stdout)

    def test_native_timeout_uses_unshadowed_zsh_primitives(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shadow_log = root / "shadowed"
            result = run_zsh(
                r"""
source "$1"
function kill() { print -r -- kill >> "$SHADOW_LOG"; }
function zselect() { command sleep 1; }
_AI_CANDY_TIMEOUT_CMD=zsh-native
start=$EPOCHREALTIME
_ai_candy_run_with_timeout 0.05 /bin/sleep 1
command_status=$?
elapsed=$(( EPOCHREALTIME - start ))
print -r -- "STATUS=${command_status}"
print -r -- "ELAPSED=${elapsed}"
print -r -- "SHADOWED=$([[ -f $SHADOW_LOG ]] && print yes || print no)"
""",
                cache_home=root / "cache",
                env={"SHADOW_LOG": str(shadow_log)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("STATUS=124", result.stdout)
        self.assertIn("SHADOWED=no", result.stdout)
        elapsed_line = next(
            line for line in result.stdout.splitlines() if line.startswith("ELAPSED=")
        )
        self.assertLess(float(elapsed_line.partition("=")[2]), 0.5)

    def test_bash_monitor_fallback_ignores_inherited_shellopts(self) -> None:
        shell_probe = subprocess.run(
            ["/bin/sh", "-c", 'test -n "${BASH_VERSION-}"'],
            check=False,
        )
        if shell_probe.returncode != 0:
            self.skipTest("/bin/sh is not Bash")

        backends = [("native", "zsh-native")]
        external_timeout = shutil.which("timeout")
        if external_timeout is not None:
            backends.append(("external", external_timeout))

        for backend_name, timeout_command in backends:
            with (
                self.subTest(backend=backend_name),
                tempfile.TemporaryDirectory() as tmp,
            ):
                result = run_zsh(
                    r"""
source "$1"
_AI_CANDY_TIMEOUT_CMD="$TIMEOUT_COMMAND"
_AI_CANDY_SETSID_CMD=""
export SHELLOPTS=errexit:nounset:noclobber:xtrace
output=$(_ai_candy_run_with_timeout 0.2 /bin/echo isolated)
command_status=$?
setopt null_glob
artifacts=("${_AI_CANDY_CACHE_DIR}"/ai-candy-timeout.*(N))
print -r -- "STATUS=${command_status} OUTPUT=${output} ARTIFACTS=${#artifacts}"
""",
                    cache_home=Path(tmp) / "cache",
                    env={"TIMEOUT_COMMAND": timeout_command},
                )

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual("", result.stderr)
            self.assertEqual("STATUS=0 OUTPUT=isolated ARTIFACTS=0\n", result.stdout)

    def test_bash_monitor_fallback_ignores_exported_control_functions(self) -> None:
        shell_probe = subprocess.run(
            ["/bin/sh", "-c", 'test -n "${BASH_VERSION-}"'],
            check=False,
        )
        if shell_probe.returncode != 0:
            self.skipTest("/bin/sh is not Bash")

        backends = [("native", "zsh-native")]
        external_timeout = shutil.which("timeout")
        if external_timeout is not None:
            backends.append(("external", external_timeout))

        for backend_name, timeout_command in backends:
            with (
                self.subTest(backend=backend_name),
                tempfile.TemporaryDirectory() as tmp,
            ):
                root = Path(tmp)
                marker = root / "started"
                result = run_zsh(
                    r"""
source "$1"
_AI_CANDY_TIMEOUT_CMD="$TIMEOUT_COMMAND"
_AI_CANDY_SETSID_CMD=""
output=$(_ai_candy_run_with_timeout 0.2 /bin/sh -c '
  printf started > "$STARTED_MARKER"
  printf isolated
')
command_status=$?
setopt null_glob
artifacts=("${_AI_CANDY_CACHE_DIR}"/ai-candy-timeout.*(N))
print -r -- "STATUS=${command_status} OUTPUT=${output} STARTED=$([[ -f $STARTED_MARKER ]] && print yes || print no) ARTIFACTS=${#artifacts}"
""",
                    cache_home=root / "cache",
                    env={
                        "BASH_FUNC_kill%%": "() { return 1; }",
                        "STARTED_MARKER": str(marker),
                        "TIMEOUT_COMMAND": timeout_command,
                    },
                )

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertEqual("", result.stderr)
            self.assertEqual(
                "STATUS=0 OUTPUT=isolated STARTED=yes ARTIFACTS=0\n",
                result.stdout,
            )

    def test_timeout_preserves_bash_target_option_environment(self) -> None:
        if not Path("/bin/bash").is_file():
            self.skipTest("Bash is not installed at /bin/bash")

        shell_probe = subprocess.run(
            ["/bin/sh", "-c", 'test -n "${BASH_VERSION-}"'],
            check=False,
        )
        shell_is_bash = shell_probe.returncode == 0
        backends = [("native-setsid", "zsh-native", "setsid")]
        if shell_is_bash:
            backends.append(("native-monitor", "zsh-native", "monitor"))
        external_timeout = shutil.which("timeout")
        if external_timeout is not None:
            backends.append(
                ("external-setsid", external_timeout, "setsid")
            )
            if shell_is_bash:
                backends.append(
                    ("external-monitor", external_timeout, "monitor")
                )
        environments = [
            ("default", "", ""),
            ("exported", "noclobber", "nullglob"),
        ]
        target_script = r"""
set -e
value=$(false; printf ok)
option_state=
if shopt -qo posix; then option_state+=1; else option_state+=0; fi
if shopt -qo privileged; then option_state+=1; else option_state+=0; fi
if shopt -qo noclobber; then option_state+=1; else option_state+=0; fi
if shopt -q nullglob; then option_state+=1; else option_state+=0; fi
printf "%s:%s:%s:%s" "$option_state" "$value" \
  "${AI_CANDY_BASH_ENV_LOADED-no}" "${BASH_ARGV0-unset}"
"""

        for backend_name, timeout_command, setsid_mode in backends:
            for environment_name, shellopts, bashopts in environments:
                with (
                    self.subTest(backend=backend_name, environment=environment_name),
                    tempfile.TemporaryDirectory() as tmp,
                ):
                    root = Path(tmp)
                    bash_env = root / "bash-env"
                    bash_env.write_text(
                        "export AI_CANDY_BASH_ENV_LOADED=yes\n", encoding="ascii"
                    )
                    target_env = {
                        **os.environ,
                        "BASH_ARGV0": "ai-candy-target",
                        "BASHOPTS": bashopts,
                        "BASH_ENV": str(bash_env),
                        "SHELLOPTS": shellopts,
                    }
                    direct = subprocess.run(
                        ["/bin/bash", "-c", target_script],
                        check=False,
                        env=target_env,
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    )
                    result = run_zsh(
                        r"""
source "$1"
_AI_CANDY_TIMEOUT_CMD="$TIMEOUT_COMMAND"
[[ "$SETSID_MODE" == monitor ]] && _AI_CANDY_SETSID_CMD=""
output=$(_ai_candy_run_with_timeout 1 /bin/bash -c "$TARGET_SCRIPT")
command_status=$?
print -r -- "STATUS=${command_status} OUTPUT=${output}"
""",
                        cache_home=root / "cache",
                        env={
                            "BASH_ARGV0": "ai-candy-target",
                            "BASHOPTS": bashopts,
                            "BASH_ENV": str(bash_env),
                            "SETSID_MODE": setsid_mode,
                            "SHELLOPTS": shellopts,
                            "TARGET_SCRIPT": target_script,
                            "TIMEOUT_COMMAND": timeout_command,
                        },
                    )

                self.assertEqual(0, direct.returncode, direct.stderr)
                self.assertEqual("", direct.stderr)
                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual("", result.stderr)
                self.assertEqual(
                    f"STATUS={direct.returncode} OUTPUT={direct.stdout}\n",
                    result.stdout,
                )

    def test_timeout_control_shells_ignore_bash_startup_environment(self) -> None:
        if not Path("/bin/bash").is_file():
            self.skipTest("Bash is not installed at /bin/bash")

        shell_probe = subprocess.run(
            ["/bin/sh", "-c", 'test -n "${BASH_VERSION-}"'],
            check=False,
        )
        shell_is_bash = shell_probe.returncode == 0
        backends = [("native-setsid", "zsh-native", "setsid")]
        if shell_is_bash:
            backends.append(("native-monitor", "zsh-native", "monitor"))
        external_timeout = shutil.which("timeout")
        if external_timeout is not None:
            backends.append(
                ("external-setsid", external_timeout, "setsid")
            )
            if shell_is_bash:
                backends.append(
                    ("external-monitor", external_timeout, "monitor")
                )

        target_env = {
            **os.environ,
            "BASH_COMPAT": "not-valid",
            "BASH_XTRACEFD": "99",
        }
        direct = subprocess.run(
            ["/bin/bash", "-c", "printf quiet"],
            check=False,
            env=target_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(0, direct.returncode, direct.stderr)
        self.assertEqual("quiet", direct.stdout)

        for backend_name, timeout_command, setsid_mode in backends:
            with (
                self.subTest(backend=backend_name),
                tempfile.TemporaryDirectory() as tmp,
            ):
                result = run_zsh(
                    r"""
source "$1"
_AI_CANDY_TIMEOUT_CMD="$TIMEOUT_COMMAND"
[[ "$SETSID_MODE" == monitor ]] && _AI_CANDY_SETSID_CMD=""
output=$(_ai_candy_run_with_timeout 1 /bin/bash -c 'printf quiet')
command_status=$?
print -r -- "STATUS=${command_status} OUTPUT=${output}"
""",
                    cache_home=Path(tmp) / "cache",
                    env={
                        "BASH_COMPAT": "not-valid",
                        "BASH_XTRACEFD": "99",
                        "SETSID_MODE": setsid_mode,
                        "TIMEOUT_COMMAND": timeout_command,
                    },
                )

                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual("STATUS=0 OUTPUT=quiet\n", result.stdout)
                for variable_name in ("BASH_COMPAT", "BASH_XTRACEFD"):
                    self.assertEqual(
                        direct.stderr.count(variable_name),
                        result.stderr.count(variable_name),
                        result.stderr,
                    )

    def test_timeout_preserves_exported_bash_environment_for_any_target(
        self,
    ) -> None:
        selected_names = (
            "BASH_ARGV0",
            "BASH_COMMAND",
            "BASH_EXECUTION_STRING",
            "BASH_SUBSHELL",
            "BASHPID",
            "SHLVL",
        )
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
direct=$(/usr/bin/env)
wrapped=$(_ai_candy_run_with_timeout 1 /usr/bin/env)
print -r -- DIRECT
print -r -- "$direct"
print -r -- WRAPPED
print -r -- "$wrapped"
""",
                cache_home=Path(tmp) / "cache",
                env={
                    "BASH_ARGV0": "ai-candy-argv0",
                    "BASH_COMMAND": "ai-candy-command",
                    "BASH_EXECUTION_STRING": "ai-candy-execution",
                    "BASH_SUBSHELL": "7",
                    "BASHPID": "123",
                    "SHLVL": "41",
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("", result.stderr)
        direct_text, separator, wrapped_text = result.stdout.partition("\nWRAPPED\n")
        self.assertEqual("\nWRAPPED\n", separator)

        def selected_environment(text: str) -> dict[str, str]:
            selected = {}
            for line in text.splitlines():
                name, equals, value = line.partition("=")
                if equals and name in selected_names:
                    selected[name] = value
            return selected

        direct_environment = selected_environment(
            direct_text.removeprefix("DIRECT\n")
        )
        wrapped_environment = selected_environment(wrapped_text)
        self.assertEqual(set(selected_names), set(direct_environment))
        self.assertEqual(direct_environment, wrapped_environment)
        self.assertNotIn("_AI_CANDY_TIMEOUT_TARGET_", wrapped_text)

    def test_timeout_environment_carriers_do_not_persist_in_the_shell(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
export BASH_COMMAND=ai-candy-test-command
_ai_candy_run_with_timeout 1 /bin/true
carrier_count=0
for variable_name in "${_AI_CANDY_TIMEOUT_BASH_ENVIRONMENT_NAMES[@]}"; do
  carrier_name="_AI_CANDY_TIMEOUT_TARGET_${variable_name}"
  (( ${+parameters[$carrier_name]} )) && (( carrier_count++ ))
done
print -r -- "CARRIERS=${carrier_count}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CARRIERS=0\n", result.stdout)

    def test_timeout_control_argv_does_not_expose_saved_environment(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            started = root / "started"
            marker = f"ai-candy-sensitive-{root.name}"
            shell_env = {
                **os.environ,
                "BASH_COMMAND": marker,
                "STARTED_MARKER": str(started),
                "XDG_CACHE_HOME": str(root / "cache"),
            }
            process = subprocess.Popen(
                [
                    "zsh",
                    "-fc",
                    r"""
source "$1"
output=$(_ai_candy_run_with_timeout 2 /bin/sh -c '
  printf started > "$STARTED_MARKER"
  sleep 1
  printf complete
')
command_status=$?
print -r -- "STATUS=${command_status} OUTPUT=${output}"
""",
                    "zsh",
                    str(Path(__file__).resolve().parents[1] / "ai-candy.zsh-theme"),
                ],
                cwd=Path(__file__).resolve().parents[1],
                env=shell_env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            try:
                deadline = time.monotonic() + 1.0
                while time.monotonic() < deadline and not started.is_file():
                    time.sleep(0.005)
                self.assertTrue(started.is_file())
                if Path("/proc").is_dir():
                    process_commands = []
                    for command_line in Path("/proc").glob("[0-9]*/cmdline"):
                        try:
                            command = command_line.read_bytes().replace(b"\0", b" ")
                        except (FileNotFoundError, PermissionError, ProcessLookupError):
                            continue
                        process_commands.append(
                            command.decode(errors="surrogateescape")
                        )
                    process_table = "\n".join(process_commands)
                else:
                    ps = shutil.which("ps")
                    if ps is None:
                        self.skipTest("A process command-line source is required")
                    process_table = subprocess.run(
                        [ps, "-axo", "command="],
                        check=True,
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    ).stdout
            finally:
                stdout, stderr = process.communicate(timeout=3)

        self.assertNotIn(marker, process_table)
        self.assertEqual(0, process.returncode, stderr)
        self.assertEqual("", stderr)
        self.assertEqual("STATUS=0 OUTPUT=complete\n", stdout)

    def test_external_timeout_is_absolute_and_kills_term_ignoring_commands(
        self,
    ) -> None:
        if shutil.which("timeout") is None:
            self.skipTest("GNU-compatible timeout is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
function timeout() { print -r -- SHADOWED; }
source "$1"
_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
_ai_candy_detect_core_commands
functions[$_AI_CANDY_TIMEOUT_CMD]='print -r -- SHADOWED'
print -r -- "COMMAND=${_AI_CANDY_TIMEOUT_CMD}"
start=$EPOCHREALTIME
_ai_candy_run_with_timeout 0.1 sh -c 'trap "" TERM; while :; do :; done'
command_status=$?
elapsed=$(( EPOCHREALTIME - start ))
print -r -- "STATUS=${command_status}"
print -r -- "ELAPSED=${elapsed}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        command_line = next(
            line for line in result.stdout.splitlines() if line.startswith("COMMAND=")
        )
        self.assertTrue(command_line.partition("=")[2].startswith("/"), result.stdout)
        self.assertNotIn("SHADOWED", result.stdout)
        status_line = next(
            line for line in result.stdout.splitlines() if line.startswith("STATUS=")
        )
        self.assertEqual(124, int(status_line.partition("=")[2]))
        elapsed_line = next(
            line for line in result.stdout.splitlines() if line.startswith("ELAPSED=")
        )
        self.assertLess(float(elapsed_line.partition("=")[2]), 0.7)

    def test_zero_timeout_does_not_start_external_fallback(self) -> None:
        external_timeout = shutil.which("timeout")
        if external_timeout is None:
            self.skipTest("GNU-compatible timeout is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            marker = root / "started"
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_TIMEOUT_CMD="$EXTERNAL_TIMEOUT"
start=$EPOCHREALTIME
output=$(_ai_candy_run_with_timeout 0 sh -c '
  printf started > "$ZERO_TIMEOUT_MARKER"
  printf unexpected
')
command_status=$?
elapsed=$(( EPOCHREALTIME - start ))
setopt null_glob
artifacts=("${_AI_CANDY_CACHE_DIR}"/ai-candy-timeout.*(N))
print -r -- "STATUS=${command_status} BYTES=${#output} STARTED=$([[ -f $ZERO_TIMEOUT_MARKER ]] && print yes || print no) ARTIFACTS=${#artifacts} ELAPSED=${elapsed}"
""",
                cache_home=root / "cache",
                env={
                    "EXTERNAL_TIMEOUT": external_timeout,
                    "ZERO_TIMEOUT_MARKER": str(marker),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(
            field.split("=", maxsplit=1) for field in result.stdout.strip().split()
        )
        self.assertEqual("124", fields["STATUS"])
        self.assertEqual("0", fields["BYTES"])
        self.assertEqual("no", fields["STARTED"])
        self.assertEqual("0", fields["ARTIFACTS"])
        self.assertLess(float(fields["ELAPSED"]), 0.5)

    def test_invalid_timeout_expression_is_rejected_without_evaluation(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            marker = root / "started"
            result = run_zsh(
                r"""
source "$1"
print -r -- before
output=$(_ai_candy_run_with_timeout '1/0' /bin/sh -c \
  'printf started > "$INVALID_TIMEOUT_MARKER"')
command_status=$?
print -r -- "STATUS=${command_status} BYTES=${#output}"
print -r -- after
""",
                cache_home=root / "cache",
                env={"INVALID_TIMEOUT_MARKER": str(marker)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("", result.stderr)
        self.assertEqual("before\nSTATUS=124 BYTES=0\nafter\n", result.stdout)
        self.assertFalse(marker.exists())

    def test_oversized_timeout_is_rejected_without_diagnostics(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            marker = root / "started"
            result = run_zsh(
                r"""
source "$1"
for timeout_sec in 999999999999999999 9999999999999999999; do
  output=$(_ai_candy_run_with_timeout "$timeout_sec" /bin/sh -c \
    'printf started > "$OVERSIZED_TIMEOUT_MARKER"')
  command_status=$?
  print -r -- "${timeout_sec}:${command_status}:${#output}"
done
""",
                cache_home=root / "cache",
                env={"OVERSIZED_TIMEOUT_MARKER": str(marker)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("", result.stderr)
        self.assertEqual(
            "999999999999999999:124:0\n9999999999999999999:124:0\n",
            result.stdout,
        )
        self.assertFalse(marker.exists())

    def test_external_timeout_bounds_captured_output(self) -> None:
        external_timeout = shutil.which("timeout")
        if external_timeout is None:
            self.skipTest("GNU-compatible timeout is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_TIMEOUT_CMD="$EXTERNAL_TIMEOUT"
_AI_CANDY_TIMEOUT_OUTPUT_MAX_BYTES=4096
output=$(_ai_candy_run_with_timeout 2 sh -c '
  i=0
  while [ "$i" -lt 128 ]; do
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
                env={"EXTERNAL_TIMEOUT": external_timeout},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(
            field.split("=", maxsplit=1) for field in result.stdout.strip().split()
        )
        self.assertEqual("125", fields["STATUS"])
        self.assertEqual(4096, int(fields["BYTES"]))
        self.assertEqual("0", fields["ARTIFACTS"])

    def test_external_timeout_discards_partial_output_after_deadline(self) -> None:
        external_timeout = shutil.which("timeout")
        if external_timeout is None:
            self.skipTest("GNU-compatible timeout is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_TIMEOUT_CMD="$EXTERNAL_TIMEOUT"
output=$(_ai_candy_run_with_timeout 0.1 sh -c 'printf partial; sleep 1')
command_status=$?
print -r -- "STATUS=${command_status} BYTES=${#output}"
""",
                cache_home=Path(tmp) / "cache",
                env={"EXTERNAL_TIMEOUT": external_timeout},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=124 BYTES=0\n", result.stdout)

    def test_external_timeout_preserves_fast_status_137_output(self) -> None:
        external_timeout = shutil.which("timeout")
        if external_timeout is None:
            self.skipTest("GNU-compatible timeout is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_TIMEOUT_CMD="$EXTERNAL_TIMEOUT"
output=$(_ai_candy_run_with_timeout 2 sh -c 'printf complete; exit 137')
command_status=$?
print -r -- "STATUS=${command_status} OUTPUT=${output}"
""",
                cache_home=Path(tmp) / "cache",
                env={"EXTERNAL_TIMEOUT": external_timeout},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=137 OUTPUT=complete\n", result.stdout)

    def test_external_timeout_fallback_preserves_small_multiline_output(self) -> None:
        external_timeout = shutil.which("timeout")
        if external_timeout is None:
            self.skipTest("GNU-compatible timeout is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_TIMEOUT_CMD="$EXTERNAL_TIMEOUT"
output=$(_ai_candy_run_with_timeout 2 sh -c 'printf "alpha\\nbeta\\n"')
command_status=$?
print -r -- "STATUS=${command_status}"
print -r -- "$output"
""",
                cache_home=Path(tmp) / "cache",
                env={"EXTERNAL_TIMEOUT": external_timeout},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=0\nalpha\nbeta\n", result.stdout)

    def test_external_timeout_fallback_preserves_combined_stderr_status(self) -> None:
        external_timeout = shutil.which("timeout")
        if external_timeout is None:
            self.skipTest("GNU-compatible timeout is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_TIMEOUT_CMD="$EXTERNAL_TIMEOUT"
output=$(_ai_candy_run_with_timeout_combined_output 2 sh -c '
  printf diagnostic >&2
  exit 7
')
print -r -- "STATUS=$? OUTPUT=${output}"
""",
                cache_home=Path(tmp) / "cache",
                env={"EXTERNAL_TIMEOUT": external_timeout},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=7 OUTPUT=diagnostic\n", result.stdout)

    def test_stale_timeout_cleanup_processes_one_bounded_batch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
for index in {1..64}; do
  print -r -- stale >| \
    "${_AI_CANDY_CACHE_DIR}/ai-candy-timeout.$((900000000 + index)).artifact"
done
_ai_candy_cleanup_stale_timeout_files "$_AI_CANDY_CACHE_DIR"
setopt null_glob
artifacts=("${_AI_CANDY_CACHE_DIR}"/ai-candy-timeout.*(N))
print -r -- "REMOVED=$((64 - ${#artifacts})) REMAINING=${#artifacts}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("REMOVED=16 REMAINING=48\n", result.stdout)

    def test_output_cap_does_not_limit_files_written_by_the_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "command-output"
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_TIMEOUT_OUTPUT_MAX_BYTES=4096
output=$(_ai_candy_run_with_timeout 2 sh -c '
  dd if=/dev/zero of="$1" bs=1024 count=16 2>/dev/null
  printf complete
' sh "$TARGET_FILE")
command_status=$?
file_bytes=$(command wc -c < "$TARGET_FILE")
print -r -- "STATUS=${command_status} OUTPUT=${output} FILE_BYTES=${file_bytes// /}"
""",
                cache_home=root / "cache",
                env={"TARGET_FILE": str(target)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "STATUS=0 OUTPUT=complete FILE_BYTES=16384\n",
            result.stdout,
        )

    def test_bounded_output_reports_a_capture_write_failure(self) -> None:
        if not Path("/dev/full").exists():
            self.skipTest("this platform does not provide /dev/full")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_ai_candy_run_bounded_output_command /dev/full 4096 sh -c 'printf captured'
print -r -- "STATUS=$?"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertNotEqual("STATUS=0\n", result.stdout)

    def test_combined_timeout_preserves_small_stderr_and_status(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
output=$(_ai_candy_run_with_timeout_combined_output 2 sh -c '
  printf diagnostic >&2
  exit 7
')
print -r -- "STATUS=$? OUTPUT=${output}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=7 OUTPUT=diagnostic\n", result.stdout)

    def test_combined_timeout_bounds_stderr(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_TIMEOUT_OUTPUT_MAX_BYTES=4096
output=$(_ai_candy_run_with_timeout_combined_output 2 sh -c '
  i=0
  while [ "$i" -lt 128 ]; do
    printf 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef >&2
    i=$((i + 1))
  done
')
command_status=$?
print -r -- "STATUS=${command_status} BYTES=${#output}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(
            field.split("=", maxsplit=1) for field in result.stdout.strip().split()
        )
        self.assertEqual("125", fields["STATUS"])
        self.assertEqual(4096, int(fields["BYTES"]))

    def test_hash_helper_uses_an_external_executable(self) -> None:
        if shutil.which("sha256sum") is None:
            self.skipTest("sha256sum is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
function sha256sum() { print -r -- FORGED; }
function printf() { print -r -- FORGED; }
source "$1"
functions[$_AI_CANDY_HASH_CMD]='print -r -- FORGED'
print -r -- "COMMAND=${_AI_CANDY_HASH_CMD}"
_ai_candy_hash_string abc
print -r -- "HASH=${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        command_line = next(
            line for line in result.stdout.splitlines() if line.startswith("COMMAND=")
        )
        self.assertTrue(command_line.partition("=")[2].startswith("/"), result.stdout)
        self.assertNotIn("FORGED", result.stdout)
        self.assertIn(f"HASH={hashlib.sha256(b'abc').hexdigest()}\n", result.stdout)

    def test_hash_helper_bounds_a_stalled_executable(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            hash_tool = root / "sha256sum"
            hash_tool.write_text(
                "#!/bin/sh\n"
                "/bin/cat >/dev/null\n"
                "/bin/sleep 1\n"
                "printf '%064d  -\\n' 0\n",
                encoding="ascii",
            )
            hash_tool.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HASH_CMD="$HASH_TOOL"
_AI_CANDY_HAS_HASH_CMD=1
_AI_CANDY_LOCAL_PROMPT_TIMEOUT=0.1
start_time=$EPOCHREALTIME
_ai_candy_hash_string https://example.invalid/repository.git
elapsed_ms=$(( (EPOCHREALTIME - start_time) * 1000 ))
builtin printf 'HASH=%s ELAPSED_MS=%.3f\n' "$REPLY" "$elapsed_ms"
""",
                cache_home=root / "cache",
                env={"HASH_TOOL": str(hash_tool)},
                timeout=3,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(item.split("=", 1) for item in result.stdout.split())
        self.assertEqual("", fields["HASH"])
        self.assertLess(float(fields["ELAPSED_MS"]), 700.0, result.stdout)

    def test_hash_helper_rejects_an_incomplete_digest(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            hash_tool = root / "sha256sum"
            hash_tool.write_text(
                "#!/bin/sh\nprintf '%s  -\\n' abcdef\n",
                encoding="ascii",
            )
            hash_tool.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HASH_CMD="$HASH_TOOL"
_AI_CANDY_HAS_HASH_CMD=1
_ai_candy_hash_string input
builtin print -r -- "HASH=${REPLY}"
""",
                cache_home=root / "cache",
                env={"HASH_TOOL": str(hash_tool)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("HASH=\n", result.stdout)

    def test_external_resolver_skips_relative_path_entries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            relative_bin = root / "relative-bin"
            trusted_bin = root / "trusted-bin"
            work_dir = root / "work"
            relative_bin.mkdir()
            trusted_bin.mkdir()
            work_dir.mkdir()
            relative_helper = relative_bin / "theme-helper"
            relative_helper.write_text(
                "#!/bin/sh\nprintf '%s\\n' relative\n", encoding="ascii"
            )
            relative_helper.chmod(0o755)
            trusted_helper = trusted_bin / "theme-helper"
            trusted_helper.write_text(
                "#!/bin/sh\nprintf '%s\\n' trusted\n", encoding="ascii"
            )
            trusted_helper.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_ai_candy_resolve_external_command theme-helper
print -r -- "COMMAND=${REPLY}"
output=$(_ai_candy_run_with_timeout 0.5 theme-helper)
print -r -- "OUTPUT=${output}"
""",
                cache_home=root / "cache",
                cwd=work_dir,
                env={
                    "PATH": (
                        f"../relative-bin{os.pathsep}{trusted_bin}"
                        f"{os.pathsep}{os.environ['PATH']}"
                    )
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn(f"COMMAND={trusted_helper}\n", result.stdout)
        self.assertIn("OUTPUT=trusted\n", result.stdout)


if __name__ == "__main__":
    unittest.main()
