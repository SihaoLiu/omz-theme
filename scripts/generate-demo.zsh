#!/usr/bin/env zsh

emulate -L zsh
setopt errexit nounset pipe_fail

typeset -gr SCRIPT_DIR="${0:A:h}"
typeset -gr REPO_ROOT="${SCRIPT_DIR:h}"
typeset -gr THEME_FILE="${REPO_ROOT}/ai-candy.zsh-theme"
typeset -gr TAPE_FILE="${SCRIPT_DIR}/demo.tape"
typeset -gr PRIVACY_MARKER_FILE="${SCRIPT_DIR}/privacy-markers.zsh"
typeset -gr VHS_IMAGE="ghcr.io/charmbracelet/vhs@sha256:9d5fc3dc0c160b0fb1d2212baff07e6bdf3fa9438c504a3237484567302fcf93"
typeset -gr ACTUAL_HOME="${HOME:-}"
typeset -gr ACTUAL_USER="${USER:-${LOGNAME:-${USERNAME:-}}}"
typeset -gr ACTUAL_HOST="$(hostname 2>/dev/null || true)"
typeset -g _DEMO_PUBLICATION_ACTIVE=0
typeset -g _DEMO_PUBLICATION_BACKUP_DIR=""
typeset -g _DEMO_RENDERER_PID=""
typeset -g _DEMO_DOCKER_COMMAND=""
typeset -g _DEMO_DOCKER_CONTAINER_NAME=""
typeset -ga _DEMO_RENDERER_PROCESS_TREE=()
typeset -g _DEMO_CLEANUP_STARTED=0
typeset -g _DEMO_CLEANUP_STATUS=0

[[ -f "$PRIVACY_MARKER_FILE" && ! -L "$PRIVACY_MARKER_FILE" ]] || {
  print -u2 -r -- "Privacy marker policy must be a regular file."
  exit 1
}
source "$PRIVACY_MARKER_FILE"

function _demo_usage() {
  print -r -- "Usage: ${0:t} [--prepare-only OUTPUT_DIR]"
}

function _demo_write_session() {
  local output_dir="$1"
  local session_file="${output_dir}/session.sh"
  local temp_file
  temp_file=$(command mktemp "${output_dir}/.session.XXXXXX")

  command cat >| "$temp_file" <<'SESSION'
#!/bin/sh
set -eu

fixture_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
mode=rich
message=""

show_frame() {
  printf '\033[2J\033[H'
  printf 'AI Candy | %s\n' "$1"
  printf 'Workspace: ~/src/ai-candy | Identity: demo@workstation\n'
  if [ -n "$message" ]; then
    printf '%s\n' "$message"
  fi
  printf '\n'
  command cat "${fixture_dir}/${mode}.ansi"
}

show_frame "RICH / LONG"
while IFS= read -r demo_command; do
  case "$demo_command" in
    e)
      mode=plain
      message="Switched to plaintext mode"
      title="PLAIN / LONG"
      ;;
    p)
      mode=slash
      message="Slash mode: [repo/project/submodule/path]"
      title="PLAIN / SLASH PATH"
      ;;
    n)
      mode=offline
      message="Network mode: OFF"
      title="NETWORK OFF"
      ;;
    a)
      mode=no-tools
      message="Coding-tool display: OFF"
      title="TOOLS OFF"
      ;;
    o)
      mode=no-os
      message="OS/kernel display: OFF"
      title="OS OFF"
      ;;
    off)
      mode=off
      message="All toggles turned OFF"
      title="ALL OPTIONAL FEATURES OFF"
      ;;
    on)
      mode=rich
      message="All toggles turned ON"
      title="RICH / LONG"
      ;;
    compact)
      mode=compact
      message="Layout: COMPACT"
      title="RICH / COMPACT"
      ;;
    minimal)
      mode=minimal
      message="Layout: MINIMAL"
      title="PLAIN / MINIMAL"
      ;;
    clean)
      mode=rich
      message=""
      title="RICH / LONG"
      ;;
    quit|exit)
      printf '\n'
      exit 0
      ;;
    *)
      message="Commands: e p n a o off on compact minimal quit"
      title="${mode}"
      ;;
  esac
  show_frame "$title"
done
SESSION
  command chmod 700 "$temp_file"
  command mv -f "$temp_file" "$session_file"
}

function _demo_path_segment() {
  local text="$1"
  local background="$2"
  local esc=$'\e'
  REPLY="%{${esc}[48;5;${background}m${esc}[38;5;16m%}${text}%{$reset_color%}"
}

function _demo_build_path() {
  local separator="$1"
  local compact="$2"
  local result="["

  if (( compact )); then
    result+="%{$FG[240]%}..%{$reset_color%}${separator}"
  else
    _demo_path_segment "~" 159
    result+="$REPLY${separator}"
    _demo_path_segment "src" 229
    result+="$REPLY${separator}"
  fi
  _demo_path_segment "ai-candy" 157
  result+="$REPLY]"
  REPLY="$result"
}

function _demo_render_frame() {
  local output_dir="$1"
  local name="$2"
  integer emoji="$3"
  local separator="$4"
  integer network="$5"
  integer tools="$6"
  integer os_info="$7"
  local layout="$8"
  local output_file="${output_dir}/${name}.ansi"
  local temp_file
  temp_file=$(command mktemp "${output_dir}/.${name}.XXXXXX")

  _PROMPT_EMOJI_MODE="$emoji"
  _LAST_EXIT_STATUS=0
  _ai_candy_compute_exit_status_direct

  local user_host="%{$FG[$_CLR_USER_HOST]%}demo@workstation%{$reset_color%}"
  local public_ip=""
  local github_user=""
  local pull_request=""
  if (( network )); then
    public_ip="%{$fg[green]%}(203.0.113.42)%{$reset_color%}"
    github_user="%{$fg[white]%}[demo-user]%{$reset_color%}"
    pull_request="%{$FG[$_CLR_PR]%}#42%{$fg[green]%}OK%{$reset_color%}"
  fi

  local badge="%{$fg[yellow]%}H%{$reset_color%}"
  (( emoji )) && badge="%{$fg[magenta]%}${_NF_CONTAINER}%{$reset_color%}"
  local fixed_time="%{$FG[$_CLR_TIME_MORNING]%}[09:41:27 UTC]%{$reset_color%}"

  integer compact_path=0
  [[ "$layout" == "minimal" ]] && compact_path=1
  _demo_build_path "$separator" "$compact_path"
  local path_display="$REPLY"

  _GIT_SNAPSHOT_VALID=1
  _GIT_SNAPSHOT_BRANCH="main"
  _GIT_SNAPSHOT_UPSTREAM="origin/main"
  _GIT_SNAPSHOT_OID="0123456789abcdef"
  _GIT_SNAPSHOT_DIRTY=1
  _GIT_SNAPSHOT_AHEAD=2
  _GIT_SNAPSHOT_BEHIND=0
  _GIT_SNAPSHOT_STASH=1
  _ai_candy_format_git_snapshot
  local git_display="${_GIT_FORMATTED_INFO}${_GIT_FORMATTED_EXT}"

  local system_display=""
  if (( os_info )); then
    if (( emoji )); then
      _ai_candy_sysinfo_apply_os_icons "AlmaLinux-9.7"
      local demo_os="$REPLY"
      _ai_candy_sysinfo_apply_kernel_icons ", Linux-5.14"
      system_display="%{$fg[cyan]%}[${demo_os}${REPLY}]%{$reset_color%}"
    else
      system_display="%{$fg[cyan]%}[Alma-9.7, Linux-5.14]%{$reset_color%}"
    fi
  fi

  local tools_display=""
  if (( tools )); then
    if (( emoji )); then
      tools_display="%{$fg[white]%}[%{$FG[$_CLR_CODEX]%}${_NF_CODEX}1.2%{$FG[$_CLR_GEMINI]%}${_NF_GEMINI}2.3%{$fg[white]%}]%{$reset_color%}"
    else
      tools_display="%{$fg[white]%}[%{$FG[$_CLR_CODEX]%}Cx:1.2%{$fg[white]%}|%{$FG[$_CLR_GEMINI]%}Gm:2.3%{$fg[white]%}]%{$reset_color%}"
    fi
  fi

  local prompt_line="${_PP_EXIT}${user_host}${public_ip}${github_user} ${badge} ${fixed_time} ${path_display} ${git_display}"
  [[ -n "$pull_request" ]] && prompt_line+=" ${pull_request}"
  local right_display="${system_display}${tools_display:+ ${tools_display}}"

  {
    if [[ "$layout" == "compact" ]]; then
      print -Pn -- "$prompt_line"
      print -Pn -- $'\e[98G'
      print -P -- "$right_display"
    elif [[ "$layout" == "minimal" ]]; then
      print -P -- "$prompt_line"
    else
      print -P -- "${prompt_line}${system_display:+ ${system_display}}${tools_display:+ ${tools_display}}"
    fi
    print -Pn -- "%{$fg[blue]%}->%{$fg_bold[blue]%} %%%{$reset_color%} "
  } >| "$temp_file"
  command chmod 600 "$temp_file"
  command mv -f "$temp_file" "$output_file"
}

function _demo_assert_private_text_absent() {
  local file="$1"
  local content="$(<"$file")"
  local marker=""
  local -a markers=("$ACTUAL_HOME" "$ACTUAL_USER" "$ACTUAL_HOST" "$REPO_ROOT")

  for marker in "${markers[@]}"; do
    [[ "$marker" == "root" || "$marker" == "demo" ]] && continue
    if (( ${#marker} < 4 )); then
      print -u2 -r -- \
        "Refusing to publish demo data with an unscannable identity marker."
      return 1
    fi
    if [[ "$content" == *"$marker"* ]]; then
      print -u2 -r -- "Refusing to publish demo data containing a local identity marker."
      return 1
    fi
  done
  for marker in "${_AI_CANDY_PRIVATE_MARKERS[@]}"; do
    if [[ -n "$marker" && "$content" == *"$marker"* ]]; then
      print -u2 -r -- "Refusing to publish demo data containing a credential marker."
      return 1
    fi
  done
}

function _demo_hash_file() {
  local file="$1"
  local candidate executable="" output=""
  REPLY=""

  for candidate in sha256sum shasum openssl; do
    executable=$(builtin whence -p "$candidate" 2>/dev/null) || continue
    [[ -n "$executable" && -x "$executable" ]] && break
    executable=""
  done
  [[ -n "$executable" ]] || {
    print -u2 -r -- "A SHA-256 command is required to publish demo assets."
    return 1
  }

  case "${executable:t}" in
    sha256sum) output=$(command "$executable" "$file") ;;
    shasum) output=$(command "$executable" -a 256 "$file") ;;
    openssl) output=$(command "$executable" dgst -sha256 "$file") ;;
  esac
  if [[ "${executable:t}" == openssl ]]; then
    REPLY="${output##* }"
  else
    REPLY="${output%%[[:space:]]*}"
  fi
  REPLY="${(L)REPLY}"
  [[ ${#REPLY} -eq 64 && "$REPLY" != *[^0-9a-f]* ]]
}

function _demo_validate_directory_target() {
  local directory="${1:a}"
  REPLY=""
  if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
    print -u2 -r -- "Demo directory must be a real directory: $directory"
    return 1
  fi
  REPLY="$directory"
}

function _demo_prepare_fixture() {
  setopt localoptions err_return
  local output_dir="${1:a}"
  _demo_validate_directory_target "$output_dir" || return 1
  command mkdir -p "$output_dir"
  _demo_validate_directory_target "$output_dir" || return 1
  command chmod 700 "$output_dir"

  local -a symlink_nodes=("$output_dir"/**/*(N@))
  if (( ${#symlink_nodes} )); then
    print -u2 -r -- "Fixture directory contains a symbolic link: ${symlink_nodes[1]}"
    return 1
  fi

  local fixture_home="${output_dir}/home"
  local fixture_cache="${output_dir}/cache"
  local fixture_config="${output_dir}/config"
  local fixture_tmp="${output_dir}/tmp"
  command mkdir -p "$fixture_home" "$fixture_cache" "$fixture_config" \
    "$fixture_tmp"
  command chmod 700 "$fixture_home" "$fixture_cache" "$fixture_config" \
    "$fixture_tmp"

  (
    export HOME="$fixture_home"
    export XDG_CACHE_HOME="$fixture_cache"
    export USER="demo"
    export HOST="workstation"
    export HOSTNAME="workstation"
    unset SSH_CONNECTION SSH_CLIENT SSH_TTY

    autoload -Uz colors
    colors
    typeset -gA FG
    local color
    for color in {0..255}; do
      FG[$color]=$'\e['"38;5;${color}m"
    done
    source "$THEME_FILE"
    _PROMPT_NETWORK_MODE=0
    _PROMPT_AI_MODE=0
    _PROMPT_OS_MODE=0
    _AI_CANDY_USE_OMZ_ASYNC=0

    _demo_render_frame "$output_dir" rich 1 " " 1 1 1 long
    _demo_render_frame "$output_dir" plain 0 " " 1 1 1 long
    _demo_render_frame "$output_dir" slash 0 "/" 1 1 1 long
    _demo_render_frame "$output_dir" offline 0 "/" 0 1 1 long
    _demo_render_frame "$output_dir" no-tools 0 "/" 0 0 1 long
    _demo_render_frame "$output_dir" no-os 0 "/" 0 0 0 long
    _demo_render_frame "$output_dir" off 0 "/" 0 0 0 minimal
    _demo_render_frame "$output_dir" compact 1 " " 1 1 1 compact
    _demo_render_frame "$output_dir" minimal 0 "/" 0 0 0 minimal
  )

  _demo_write_session "$output_dir"
  local fixture_file
  for fixture_file in "$output_dir"/*.ansi "$output_dir/session.sh"; do
    _demo_assert_private_text_absent "$fixture_file"
  done
}

function _demo_collect_renderer_process_tree() {
  local root_pid="$1"
  local process_table="" line="" process_pid="" parent_pid=""
  local proc_stat="" stat_contents="" stat_tail=""
  local -a fields proc_stats
  integer changed=1

  _DEMO_RENDERER_PROCESS_TREE=("$root_pid")
  if [[ "$OSTYPE" == linux* && -d /proc ]]; then
    proc_stats=(/proc/<->/stat(N))
    for proc_stat in "${proc_stats[@]}"; do
      [[ -r "$proc_stat" ]] || continue
      stat_contents="$(<"$proc_stat")"
      stat_tail="${stat_contents##*) }"
      fields=(${=stat_tail})
      (( ${#fields} >= 2 )) || continue
      process_pid="${proc_stat:h:t}"
      parent_pid="${fields[2]}"
      [[ "$process_pid" == <-> && "$parent_pid" == <-> ]] || continue
      process_table+="${process_pid} ${parent_pid}"$'\n'
    done
  else
    [[ -x /bin/ps ]] || return 0
    process_table=$(/bin/ps -ax -o pid= -o ppid= 2>/dev/null) || return 0
  fi
  while (( changed )); do
    changed=0
    for line in "${(@f)process_table}"; do
      fields=(${=line})
      (( ${#fields} >= 2 )) || continue
      process_pid="${fields[1]}"
      parent_pid="${fields[2]}"
      [[ "$process_pid" == <-> && "$parent_pid" == <-> ]] || continue
      if (( ${_DEMO_RENDERER_PROCESS_TREE[(Ie)$parent_pid]} && \
            ! ${_DEMO_RENDERER_PROCESS_TREE[(Ie)$process_pid]} )); then
        _DEMO_RENDERER_PROCESS_TREE+=("$process_pid")
        changed=1
      fi
    done
  done
}

function _demo_remove_docker_container() {
  local docker_command="$_DEMO_DOCKER_COMMAND"
  local container_name="$_DEMO_DOCKER_CONTAINER_NAME"
  integer attempt

  [[ -n "$docker_command" && -x "$docker_command" && \
     -n "$container_name" ]] || return 0
  for attempt in {1..6}; do
    command "$docker_command" rm -f "$container_name" \
      >/dev/null 2>&1 && return 0
    if (( ${+builtins[zselect]} )); then
      builtin zselect -t 5 2>/dev/null || true
    else
      command /bin/sleep 0.05 2>/dev/null || true
    fi
  done
  return 1
}

function _demo_stop_renderer() {
  setopt localoptions noerrexit
  local renderer_pid="$_DEMO_RENDERER_PID"
  local process_pid=""
  integer attempt previous_count=-1 index

  [[ "$renderer_pid" == <-> ]] || return 0
  _demo_remove_docker_container || true
  builtin kill -STOP "$renderer_pid" 2>/dev/null || true
  for attempt in {1..4}; do
    _demo_collect_renderer_process_tree "$renderer_pid"
    for process_pid in "${_DEMO_RENDERER_PROCESS_TREE[@]}"; do
      builtin kill -STOP "$process_pid" 2>/dev/null || true
    done
    (( ${#_DEMO_RENDERER_PROCESS_TREE} == previous_count )) && break
    previous_count=${#_DEMO_RENDERER_PROCESS_TREE}
  done
  for (( index=${#_DEMO_RENDERER_PROCESS_TREE}; index>=1; index-- )); do
    builtin kill -KILL "${_DEMO_RENDERER_PROCESS_TREE[index]}" \
      2>/dev/null || true
  done
  builtin wait "$renderer_pid" 2>/dev/null || true
  _demo_remove_docker_container || true
  _DEMO_RENDERER_PID=""
  _DEMO_DOCKER_COMMAND=""
  _DEMO_DOCKER_CONTAINER_NAME=""
  _DEMO_RENDERER_PROCESS_TREE=()
  return 0
}

function _demo_run_renderer_command() {
  local render_dir="$1"
  shift
  integer renderer_status=0

  (
    cd "$render_dir"
    exec "$@"
  ) &
  _DEMO_RENDERER_PID=$!
  builtin wait "$_DEMO_RENDERER_PID" || renderer_status=$?
  _DEMO_RENDERER_PID=""
  _DEMO_DOCKER_COMMAND=""
  _DEMO_DOCKER_CONTAINER_NAME=""
  return "$renderer_status"
}

function _demo_render_with_vhs() {
  setopt localoptions err_return
  local render_dir="${1:a}"
  local vhs_command="" ttyd_command="" ffmpeg_command=""
  local docker_command="" env_command=""

  vhs_command=$(builtin whence -p vhs 2>/dev/null) || vhs_command=""
  ttyd_command=$(builtin whence -p ttyd 2>/dev/null) || ttyd_command=""
  ffmpeg_command=$(builtin whence -p ffmpeg 2>/dev/null) || ffmpeg_command=""
  if [[ -x "$vhs_command" && -x "$ttyd_command" && -x "$ffmpeg_command" ]]; then
    env_command=$(builtin whence -p env 2>/dev/null) || env_command=""
    [[ -x "$env_command" ]] || {
      print -u2 -r -- "The env command is required for isolated rendering."
      return 1
    }
    _demo_run_renderer_command "$render_dir" "$env_command" -i \
      HOME="${render_dir}/home" \
      XDG_CACHE_HOME="${render_dir}/cache" \
      XDG_CONFIG_HOME="${render_dir}/config" \
      TMPDIR="${render_dir}/tmp" \
      USER=demo LOGNAME=demo HOST=workstation HOSTNAME=workstation \
      LANG=C TERM="${TERM:-xterm-256color}" PATH="${PATH:-/usr/bin:/bin}" \
      "$vhs_command" "$TAPE_FILE"
    return $?
  fi

  docker_command=$(builtin whence -p docker 2>/dev/null) || docker_command=""
  [[ -x "$docker_command" ]] || {
    print -u2 -r -- "Install VHS with ttyd and ffmpeg, or install Docker."
    return 1
  }
  _DEMO_DOCKER_COMMAND="$docker_command"
  _DEMO_DOCKER_CONTAINER_NAME="ai-candy-${render_dir:t}"
  _demo_run_renderer_command "$render_dir" "$docker_command" run --rm \
    --name "$_DEMO_DOCKER_CONTAINER_NAME" \
    --network none \
    --user "$(id -u):$(id -g)" \
    -e HOME=/work/home \
    -e XDG_CACHE_HOME=/work/cache \
    -e XDG_CONFIG_HOME=/work/config \
    -e TMPDIR=/work/tmp \
    -e USER=demo \
    -e LOGNAME=demo \
    -e HOST=workstation \
    -e HOSTNAME=workstation \
    -e LANG=C \
    -v "${TAPE_FILE}:/tape/demo.tape:ro" \
    -v "${render_dir}:/work:rw" \
    -w /work \
    "$VHS_IMAGE" /tape/demo.tape
}

function _demo_remove_publication_backup() {
  local backup_dir="$_DEMO_PUBLICATION_BACKUP_DIR"
  [[ -n "$backup_dir" ]] || return 0
  if [[ ! -e "$backup_dir" && ! -L "$backup_dir" ]]; then
    _DEMO_PUBLICATION_BACKUP_DIR=""
    return 0
  fi
  if [[ ! -d "$backup_dir" || -L "$backup_dir" || \
        "${backup_dir:h}" != "$REPO_ROOT" || \
        "${backup_dir:t}" != .demo-publish.* ]]; then
    print -u2 -r -- "Refusing to remove an invalid publication backup."
    return 1
  fi
  command rm -rf "$backup_dir" || {
    print -u2 -r -- "Could not remove publication backup: $backup_dir"
    return 1
  }
  _DEMO_PUBLICATION_BACKUP_DIR=""
}

function _demo_prepare_publication_backup() {
  local asset target backup_dir
  backup_dir=$(command mktemp -d "${REPO_ROOT}/.demo-publish.XXXXXX") || \
    return 1
  _DEMO_PUBLICATION_BACKUP_DIR="$backup_dir"
  command chmod 700 "$backup_dir"

  for asset in demo.gif demo.png demo-assets.sha256; do
    target="${REPO_ROOT}/${asset}"
    [[ ! -e "$target" && ! -L "$target" ]] && continue
    if [[ ! -f "$target" || -L "$target" ]]; then
      print -u2 -r -- "Demo publication target must be a regular file: $asset"
      _demo_remove_publication_backup
      return 1
    fi
    command cp -p "$target" "${backup_dir}/${asset}" || {
      _demo_remove_publication_backup
      return 1
    }
  done
}

function _demo_rollback_publication() {
  setopt localoptions noerrexit
  (( _DEMO_PUBLICATION_ACTIVE )) || return 0
  local backup_dir="$_DEMO_PUBLICATION_BACKUP_DIR"
  local asset backup target restore_temp=""
  integer rollback_status=0

  if [[ ! -d "$backup_dir" || -L "$backup_dir" || \
        "${backup_dir:h}" != "$REPO_ROOT" || \
        "${backup_dir:t}" != .demo-publish.* ]]; then
    print -u2 -r -- "Publication rollback has no valid recovery directory."
    return 1
  fi

  for asset in demo.gif demo.png demo-assets.sha256; do
    backup="${backup_dir}/${asset}"
    target="${REPO_ROOT}/${asset}"
    if [[ -f "$backup" && ! -L "$backup" ]]; then
      restore_temp=$(command mktemp "${REPO_ROOT}/.demo-restore.XXXXXX") || {
        rollback_status=1
        continue
      }
      if ! command cp -p "$backup" "$restore_temp"; then
        command rm -f "$restore_temp" 2>/dev/null || true
        rollback_status=1
        continue
      fi
      if ! command mv -f "$restore_temp" "$target"; then
        command rm -f "$restore_temp" 2>/dev/null || true
        rollback_status=1
      fi
    elif [[ -e "$backup" || -L "$backup" ]]; then
      rollback_status=1
    else
      command rm -f "$target" || rollback_status=1
    fi
  done
  if (( rollback_status )); then
    print -u2 -r -- \
      "Rollback failed; recovery copies remain in: $backup_dir"
    return 1
  fi
  _DEMO_PUBLICATION_ACTIVE=0
  _demo_remove_publication_backup
}

function _demo_publish_assets() {
  setopt localoptions err_return
  local work_dir="$1"
  local text_output="${work_dir}/demo.txt"
  local gif_output="${work_dir}/demo.gif"
  local png_output="${work_dir}/demo.png"
  local manifest_output="${work_dir}/demo-assets.sha256"

  local asset
  for asset in "$text_output" "$gif_output" "$png_output"; do
    [[ -f "$asset" && ! -L "$asset" && -s "$asset" ]] || {
      print -u2 -r -- "VHS output must be a non-empty regular file: ${asset:t}"
      return 1
    }
  done
  _demo_assert_private_text_absent "$text_output"

  local strings_command="" strings_output scan_status
  strings_command=$(builtin whence -p strings 2>/dev/null) || strings_command=""
  [[ -x "$strings_command" ]] || {
    print -u2 -r -- "The strings command is required for binary privacy checks."
    return 1
  }
  for asset in "$gif_output" "$png_output"; do
    scan_status=0
    strings_output=$(command mktemp "${work_dir}/.${asset:t}.strings.XXXXXX")
    command chmod 600 "$strings_output"
    command "$strings_command" -a "$asset" >| "$strings_output" || scan_status=$?
    if (( scan_status == 0 )); then
      _demo_assert_private_text_absent "$strings_output" || scan_status=$?
    fi
    command rm -f "$strings_output"
    (( scan_status == 0 )) || return "$scan_status"
  done

  [[ -f "$gif_output" && ! -L "$gif_output" && \
     -f "$png_output" && ! -L "$png_output" ]] || return 1
  local manifest_temp
  manifest_temp=$(command mktemp "${work_dir}/.demo-assets.XXXXXX")
  {
    _demo_hash_file "$gif_output"
    print -r -- "${REPLY}  demo.gif"
    _demo_hash_file "$png_output"
    print -r -- "${REPLY}  demo.png"
  } >| "$manifest_temp"
  command chmod 644 "$manifest_temp"
  command mv -f "$manifest_temp" "$manifest_output"

  command chmod 644 "$gif_output" "$png_output" "$manifest_output"
  _demo_prepare_publication_backup
  _DEMO_PUBLICATION_ACTIVE=1
  command mv -f "$gif_output" "${REPO_ROOT}/demo.gif"
  command mv -f "$png_output" "${REPO_ROOT}/demo.png"
  command mv -f "$manifest_output" "${REPO_ROOT}/demo-assets.sha256"
  _DEMO_PUBLICATION_ACTIVE=0
  _demo_remove_publication_backup
  print -r -- "Generated demo.gif, demo.png, and demo-assets.sha256"
}

if (( $# > 0 )); then
  if [[ "$1" == "--prepare-only" && $# == 2 ]]; then
    _demo_prepare_fixture "$2"
    exit 0
  fi
  _demo_usage >&2
  exit 2
fi

typeset -g work_dir=""
typeset -g scratch_dir="${REPO_ROOT}/temp"
typeset -g lock_file="${scratch_dir}/demo-generation.lock"
integer lock_fd
integer create_fd
_demo_validate_directory_target "$scratch_dir" || exit 1
command mkdir -p "$scratch_dir"
_demo_validate_directory_target "$scratch_dir" || exit 1
builtin zmodload zsh/system
builtin zmodload zsh/zselect 2>/dev/null || true
if [[ ! -e "$lock_file" && ! -L "$lock_file" ]]; then
  if builtin sysopen -w -o create,excl -m 600 -u create_fd "$lock_file" 2>/dev/null; then
    exec {create_fd}>&-
  fi
fi
if [[ ! -f "$lock_file" || -L "$lock_file" ]]; then
  print -u2 -r -- "Demo generation lock must be a regular file."
  exit 1
fi
if ! builtin zsystem flock -t 0 -f lock_fd "$lock_file"; then
  print -u2 -r -- "Another demo generation is already running."
  exit 1
fi

work_dir=$(command mktemp -d "${scratch_dir}/demo-render.XXXXXX")
_demo_validate_directory_target "$work_dir" || exit 1
command chmod 700 "$work_dir"
function _demo_remove_work_directory() {
  [[ -n "$work_dir" && -d "$work_dir" && ! -L "$work_dir" ]] && \
    command rm -rf "$work_dir"
}
function _demo_cleanup_generation() {
  setopt localoptions noerrexit
  if (( _DEMO_CLEANUP_STARTED )); then
    return "$_DEMO_CLEANUP_STATUS"
  fi
  _DEMO_CLEANUP_STARTED=1
  integer cleanup_status=0
  integer rollback_failed=0

  _demo_stop_renderer || cleanup_status=$?
  if (( _DEMO_PUBLICATION_ACTIVE )); then
    _demo_rollback_publication || {
      cleanup_status=$?
      rollback_failed=1
    }
  else
    _demo_remove_publication_backup || cleanup_status=$?
  fi
  if (( rollback_failed )); then
    print -u2 -r -- "Render data retained for manual recovery: $work_dir"
  else
    _demo_remove_work_directory || cleanup_status=$?
  fi
  _DEMO_CLEANUP_STATUS="$cleanup_status"
  return "$_DEMO_CLEANUP_STATUS"
}
function _demo_abort_generation() {
  local exit_status="$1"
  local process_pid="${sysparams[pid]-$$}"
  integer cleanup_status=0
  trap - EXIT HUP INT TERM
  _demo_cleanup_generation || cleanup_status=$?
  if [[ "$process_pid" == <-> ]]; then
    # Zsh 5.8 can resume the interrupted function after exit in a signal trap.
    # Cleanup is complete, so use an unblockable signal to prevent publication.
    builtin kill -KILL "$process_pid" 2>/dev/null || \
      builtin exit "$exit_status"
  fi
  builtin exit "$exit_status"
}
trap _demo_cleanup_generation EXIT
trap '_demo_abort_generation 129' HUP
trap '_demo_abort_generation 130' INT
trap '_demo_abort_generation 143' TERM
_demo_prepare_fixture "$work_dir" || builtin exit 1
_demo_render_with_vhs "$work_dir" || builtin exit 1
_demo_publish_assets "$work_dir" || builtin exit 1
_demo_cleanup_generation
work_dir=""
trap - EXIT HUP INT TERM
