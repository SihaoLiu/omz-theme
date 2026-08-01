# Isolated process-group protocol shared by native and external timeouts.

typeset -ga _AI_CANDY_TIMEOUT_BASH_ENVIRONMENT_NAMES=(
  BASHOPTS
  BASH_ARGC
  BASH_ARGV
  BASH_ARGV0
  BASH_COMMAND
  BASH_COMPAT
  BASH_ENV
  BASH_EXECUTION_STRING
  BASH_LINENO
  BASH_SOURCE
  BASH_SUBSHELL
  BASH_XTRACEFD
  BASHPID
  FUNCNAME
  SHELLOPTS
  SHLVL
)

typeset -g _AI_CANDY_TIMEOUT_GROUP_SCRIPT='
set +m
completion_file=$1
group_file=$2
shift 2
supervisor_pid=${AI_CANDY_TIMEOUT_SUPERVISOR_PID-}
unset AI_CANDY_TIMEOUT_SUPERVISOR_PID
case "$supervisor_pid" in
  ""|*[!0-9]*) exit 125 ;;
esac
exec 9<&-
( umask 077; printf "%s\n" "$$" > "$group_file" ) || exit 125
kill -USR1 "$supervisor_pid" 2>/dev/null || exit 125
kill -STOP "$$"
(
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASHOPTS+x}" = x ]; then
    set -- "BASHOPTS=$_AI_CANDY_TIMEOUT_TARGET_BASHOPTS" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASH_ARGC+x}" = x ]; then
    set -- "BASH_ARGC=$_AI_CANDY_TIMEOUT_TARGET_BASH_ARGC" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASH_ARGV+x}" = x ]; then
    set -- "BASH_ARGV=$_AI_CANDY_TIMEOUT_TARGET_BASH_ARGV" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASH_ARGV0+x}" = x ]; then
    set -- "BASH_ARGV0=$_AI_CANDY_TIMEOUT_TARGET_BASH_ARGV0" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASH_COMMAND+x}" = x ]; then
    set -- "BASH_COMMAND=$_AI_CANDY_TIMEOUT_TARGET_BASH_COMMAND" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASH_COMPAT+x}" = x ]; then
    set -- "BASH_COMPAT=$_AI_CANDY_TIMEOUT_TARGET_BASH_COMPAT" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASH_ENV+x}" = x ]; then
    set -- "BASH_ENV=$_AI_CANDY_TIMEOUT_TARGET_BASH_ENV" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASH_EXECUTION_STRING+x}" = x ]; then
    set -- "BASH_EXECUTION_STRING=$_AI_CANDY_TIMEOUT_TARGET_BASH_EXECUTION_STRING" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASH_LINENO+x}" = x ]; then
    set -- "BASH_LINENO=$_AI_CANDY_TIMEOUT_TARGET_BASH_LINENO" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASH_SOURCE+x}" = x ]; then
    set -- "BASH_SOURCE=$_AI_CANDY_TIMEOUT_TARGET_BASH_SOURCE" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASH_SUBSHELL+x}" = x ]; then
    set -- "BASH_SUBSHELL=$_AI_CANDY_TIMEOUT_TARGET_BASH_SUBSHELL" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASH_XTRACEFD+x}" = x ]; then
    set -- "BASH_XTRACEFD=$_AI_CANDY_TIMEOUT_TARGET_BASH_XTRACEFD" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_BASHPID+x}" = x ]; then
    set -- "BASHPID=$_AI_CANDY_TIMEOUT_TARGET_BASHPID" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_FUNCNAME+x}" = x ]; then
    set -- "FUNCNAME=$_AI_CANDY_TIMEOUT_TARGET_FUNCNAME" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_SHELLOPTS+x}" = x ]; then
    set -- "SHELLOPTS=$_AI_CANDY_TIMEOUT_TARGET_SHELLOPTS" "$@"
  fi
  if [ "${_AI_CANDY_TIMEOUT_TARGET_SHLVL+x}" = x ]; then
    set -- "SHLVL=$_AI_CANDY_TIMEOUT_TARGET_SHLVL" "$@"
  fi
  /usr/bin/env \
    -u _AI_CANDY_TIMEOUT_TARGET_BASHOPTS \
    -u _AI_CANDY_TIMEOUT_TARGET_BASH_ARGC \
    -u _AI_CANDY_TIMEOUT_TARGET_BASH_ARGV \
    -u _AI_CANDY_TIMEOUT_TARGET_BASH_ARGV0 \
    -u _AI_CANDY_TIMEOUT_TARGET_BASH_COMMAND \
    -u _AI_CANDY_TIMEOUT_TARGET_BASH_COMPAT \
    -u _AI_CANDY_TIMEOUT_TARGET_BASH_ENV \
    -u _AI_CANDY_TIMEOUT_TARGET_BASH_EXECUTION_STRING \
    -u _AI_CANDY_TIMEOUT_TARGET_BASH_LINENO \
    -u _AI_CANDY_TIMEOUT_TARGET_BASH_SOURCE \
    -u _AI_CANDY_TIMEOUT_TARGET_BASH_SUBSHELL \
    -u _AI_CANDY_TIMEOUT_TARGET_BASH_XTRACEFD \
    -u _AI_CANDY_TIMEOUT_TARGET_BASHPID \
    -u _AI_CANDY_TIMEOUT_TARGET_FUNCNAME \
    -u _AI_CANDY_TIMEOUT_TARGET_SHELLOPTS \
    -u _AI_CANDY_TIMEOUT_TARGET_SHLVL \
    "$@"
  target_status=$?
  ( umask 077; printf "%s\n" "$target_status" > "$completion_file" ) || \
    exit 125
  exit 0
) | /bin/cat
kill -USR2 "$supervisor_pid" 2>/dev/null || exit 125
kill -STOP "$$"
exit 125
'

typeset -g _AI_CANDY_TIMEOUT_SUPERVISOR_SCRIPT='
completion_file=$1
group_file=$2
setsid_command=$3
shift 3
[ "$#" -gt 0 ] || exit 125
group_pid=
group_ready=0
lifetime_ready=0
terminated=0
_ai_candy_kill_group() {
  if [ -n "$group_pid" ]; then
    kill -KILL "-$group_pid" 2>/dev/null || \
      kill -KILL "$group_pid" 2>/dev/null || :
  fi
}
trap "terminated=1; _ai_candy_kill_group" HUP INT TERM
trap "group_ready=1" USR1
trap "lifetime_ready=1" USR2
exec 9<&0 || exit 125
if [ -n "$setsid_command" ]; then
  AI_CANDY_TIMEOUT_SUPERVISOR_PID=$$ \
    "$setsid_command" /usr/bin/env "$@" <&9 &
else
  set -m 2>/dev/null || exit 125
  AI_CANDY_TIMEOUT_SUPERVISOR_PID=$$ /usr/bin/env "$@" <&9 &
fi
group_pid=$!
exec 9<&-
while [ "$group_ready" -eq 0 ]; do
  wait "$group_pid"
  if [ "$terminated" -ne 0 ]; then
    _ai_candy_kill_group
    wait "$group_pid" 2>/dev/null || :
    exit 143
  fi
  kill -0 "$group_pid" 2>/dev/null || exit 125
done
recorded_group=
IFS= read -r recorded_group < "$group_file" || :
[ "$recorded_group" = "$group_pid" ] || {
  _ai_candy_kill_group
  wait "$group_pid" 2>/dev/null || :
  exit 125
}
kill -CONT "-$group_pid" 2>/dev/null || {
  _ai_candy_kill_group
  wait "$group_pid" 2>/dev/null || :
  exit 125
}
while [ "$lifetime_ready" -eq 0 ]; do
  wait "$group_pid"
  if [ "$terminated" -ne 0 ]; then
    _ai_candy_kill_group
    wait "$group_pid" 2>/dev/null || :
    exit 143
  fi
  kill -0 "$group_pid" 2>/dev/null || break
done
_ai_candy_kill_group
wait "$group_pid" 2>/dev/null || :
[ "$terminated" -eq 0 ] || exit 143
[ "$lifetime_ready" -eq 1 ] || exit 125
exit 0
'

function _ai_candy_capture_timeout_target_environment() {
  emulate -L zsh
  local variable_name="" variable_type="" carrier_name=""
  reply=()
  for variable_name in "${_AI_CANDY_TIMEOUT_BASH_ENVIRONMENT_NAMES[@]}"; do
    reply+=(-u "$variable_name")
    carrier_name="_AI_CANDY_TIMEOUT_TARGET_${variable_name}"
    builtin unset "$carrier_name"
    (( ${+parameters[$variable_name]} )) || continue
    variable_type="${(tP)variable_name}"
    [[ "$variable_type" == *-export* ]] || continue
    builtin export "$carrier_name=${(P)variable_name}"
  done
}

function _ai_candy_launch_timeout_supervisor() {
  emulate -L zsh
  local timeout_command="$1" timeout_sec="$2"
  local completion_file="$3" group_file="$4" setsid_command="$5"
  shift 5
  _ai_candy_capture_timeout_target_environment
  local -a control_environment=("${reply[@]}")
  local -a group_command=(
    "${control_environment[@]}"
    /bin/sh -p -c "$_AI_CANDY_TIMEOUT_GROUP_SCRIPT"
    ai-candy-target "$completion_file" "$group_file" "$@"
  )
  local -a supervisor_command=(
    /usr/bin/env "${control_environment[@]}"
    /bin/sh -p -c "$_AI_CANDY_TIMEOUT_SUPERVISOR_SCRIPT"
    ai-candy-timeout "$completion_file" "$group_file" "$setsid_command"
    "${group_command[@]}"
  )
  if [[ "$timeout_command" == zsh-native ]]; then
    builtin command "${supervisor_command[@]}"
    return $?
  fi
  builtin command /usr/bin/env "$timeout_command" -k 0.1 "$timeout_sec" \
    "${supervisor_command[@]}"
}

function _ai_candy_read_timeout_completion_status() {
  local completion_file="$1"
  local completion_status=""
  REPLY=""
  [[ -f "$completion_file" && ! -L "$completion_file" ]] || return 1
  completion_status="$(<"$completion_file")"
  if [[ "$completion_status" != <-> || \
        ${#completion_status} -gt 3 ]] || \
     (( completion_status > 255 )); then
    return 1
  fi
  REPLY="$completion_status"
}

function _ai_candy_kill_timeout_process_group() {
  local group_file="$1"
  local root_pid="$2"
  local group_pid=""
  [[ -f "$group_file" && ! -L "$group_file" ]] || return 0
  group_pid="$(<"$group_file")"
  [[ "$group_pid" == <-> ]] || return 0
  (( group_pid > 1 )) || return 0
  _ai_candy_collect_process_tree "$root_pid"
  (( ${_AI_CANDY_TIMEOUT_PROCESS_TREE[(Ie)$group_pid]} )) || return 0
  builtin kill -KILL "-${group_pid}" 2>/dev/null || true
}
