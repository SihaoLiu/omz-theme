#!/usr/bin/env zsh

emulate -L zsh
setopt errexit nounset pipe_fail

typeset -gr SCRIPT_DIR="${0:A:h}"
typeset -gr REPO_ROOT="${SCRIPT_DIR:h}"
typeset -gr THEME_FILE="${REPO_ROOT}/ai-candy.zsh-theme"
typeset -gr TAPE_FILE="${SCRIPT_DIR}/demo.tape"
typeset -gr PRIVACY_MARKER_FILE="${SCRIPT_DIR}/privacy-markers.zsh"
typeset -gr ACTUAL_HOME="${HOME:-}"
typeset -gr ACTUAL_XDG_DATA_HOME="${XDG_DATA_HOME:-}"
typeset -gr ACTUAL_USER="${USER:-${LOGNAME:-${USERNAME:-}}}"
typeset -gr ACTUAL_HOST="$(hostname 2>/dev/null || true)"
typeset -g _DEMO_PUBLICATION_ACTIVE=0
typeset -g _DEMO_PUBLICATION_BACKUP_DIR=""
typeset -g _DEMO_RENDERER_PID=""
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
  local session_file="${output_dir}/session.zsh"
  local temp_file
  temp_file=$(command mktemp "${output_dir}/.session.XXXXXX")

  command cat >| "$temp_file" <<'SESSION'
#!/usr/bin/env zsh

emulate -L zsh
setopt errexit nounset pipe_fail

typeset -gr fixture_dir="${0:A:h}"
export HOME="${fixture_dir}/home"
export XDG_DATA_HOME="${fixture_dir}/data"
export XDG_CACHE_HOME="${fixture_dir}/cache"
export XDG_CONFIG_HOME="${fixture_dir}/config"
export TMPDIR="${fixture_dir}/tmp"
export USER=demo LOGNAME=demo HOST=workstation HOSTNAME=workstation
export LANG=C TZ=UTC
unset SSH_CONNECTION SSH_CLIENT SSH_TTY
cd "${HOME}/src/ai-candy"

autoload -Uz colors
colors
typeset -gA FG
integer color
for color in {0..255}; do
  FG[$color]=$'\e['"38;5;${color}m"
done

AI_CANDY_ENABLE_SHORT_ALIASES=0
source "${fixture_dir}/ai-candy.zsh-theme"

typeset -g _DEMO_COLUMNS=160
typeset -g _DEMO_TITLE="RICH / LONG"
typeset -g _DEMO_MESSAGE=""

# A renderer regression must fail closed instead of reaching the network.
function _ai_candy_start_registered_background_worker() {
  builtin print -u2 -r -- "Demo fixture attempted background work: $1"
  return 1
}

function _demo_seed_caches() {
  local separator=$'\x1f'
  local now="$EPOCHSECONDS"

  _ai_candy_cache_write "$_AI_CANDY_PUBLIC_IP_CACHE_FILE" \
    "203.0.113.42|${now}"
  _ai_candy_cache_write "$_AI_CANDY_GH_USERNAME_GH_CACHE_FILE" \
    "demo-user|${now}"
  _ai_candy_cache_write "$_AI_CANDY_GH_USERNAME_SSH_CACHE_FILE" \
    "demo-user|${now}"
  _ai_candy_cache_write "$_AI_CANDY_CODEX_CACHE_FILE" \
    "1.2${separator}1.2${separator}${now}"
  _ai_candy_cache_write "$_AI_CANDY_GEMINI_CACHE_FILE" \
    "2.3${separator}2.3${separator}${now}"
}

function _demo_seed_path_context() {
  local git_root="${HOME}/src/ai-candy"
  local separator="/"
  (( _AI_CANDY_PROMPT_PATH_SEP_MODE )) && separator=" "

  _AI_CANDY_PP_CACHED_GIT_ROOT="$git_root"
  _ai_candy_smart_path_context_key
  _AI_CANDY_SMART_PATH_CONTEXT_KEY="$REPLY"
  _AI_CANDY_SMART_PATH_CONTEXT_TIMESTAMP="$EPOCHSECONDS"
  _AI_CANDY_SMART_PATH_FALLBACK=""
  _AI_CANDY_SMART_PATH_NUM_REPOS=3
  _AI_CANDY_SMART_PATH_TOTAL_LENGTH=16
  _AI_CANDY_SMART_PATH_SEPARATOR="$separator"
  _AI_CANDY_SMART_PATH_SEGMENTS=("~" "src" "ai-candy")
  _AI_CANDY_SMART_PATH_SEGMENT_LENGTHS=(1 3 8)
  _AI_CANDY_SMART_PATH_RENDER_KEY=""
  _AI_CANDY_SMART_PATH_RENDER_VALUE=""
}

function _demo_compute_prompt() {
  setopt localoptions noerrexit noerrreturn
  local pr_key="demo-remote|main"
  (( ++_AI_CANDY_PROMPT_RENDER_ID ))
  _AI_CANDY_USE_OMZ_ASYNC=0
  _AI_CANDY_LAST_EXIT_STATUS=0
  _AI_CANDY_PP_VENV=""
  _ai_candy_compute_exit_status_direct
  _AI_CANDY_PP_SSH=""
  _AI_CANDY_PP_USER_HOST="%{$FG[$_AI_CANDY_CLR_USER_HOST]%}demo@workstation%{$reset_color%}"

  _AI_CANDY_HAS_CURL=1
  _AI_CANDY_HAS_GH=1
  _AI_CANDY_HAS_SSH=1
  _ai_candy_compute_public_ip_direct
  _ai_candy_compute_gh_username_direct
  _AI_CANDY_PP_TIME="%{$FG[$_AI_CANDY_CLR_TIME_MORNING]%}[09:41:27 UTC]%{$reset_color%}"
  (( _AI_CANDY_PROMPT_EMOJI_MODE )) && \
    _AI_CANDY_PP_JOBS="$_AI_CANDY_SYM_JOBS" || _AI_CANDY_PP_JOBS="J"

  _AI_CANDY_GIT_SNAPSHOT_VALID=1
  _AI_CANDY_GIT_SNAPSHOT_STATUS_COMPLETE=1
  _AI_CANDY_GIT_SNAPSHOT_BRANCH=main
  _AI_CANDY_GIT_SNAPSHOT_UPSTREAM=origin/main
  _AI_CANDY_GIT_SNAPSHOT_OID=0123456789abcdef
  _AI_CANDY_GIT_SNAPSHOT_DIRTY=1
  _AI_CANDY_GIT_SNAPSHOT_AHEAD=2
  _AI_CANDY_GIT_SNAPSHOT_BEHIND=0
  _AI_CANDY_GIT_SNAPSHOT_STASH=1
  _AI_CANDY_GIT_HIDE_INFO=0
  _AI_CANDY_GIT_HIDE_DIRTY=0
  ZSH_THEME_GIT_SHOW_UPSTREAM=1
  _ai_candy_format_git_snapshot
  _AI_CANDY_PP_GIT_INFO="$_AI_CANDY_GIT_FORMATTED_INFO"
  _AI_CANDY_PP_GIT_EXT="$_AI_CANDY_GIT_FORMATTED_EXT"
  _AI_CANDY_PP_GIT_SPECIAL=""

  _AI_CANDY_GH_AUTH_MEM_CACHE=1
  _AI_CANDY_GH_AUTH_MEM_CACHE_TIME="$EPOCHSECONDS"
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_ID="$_AI_CANDY_PROMPT_RENDER_ID"
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE="$pr_key"
  _AI_CANDY_MEM_CACHE_GH_PR[$pr_key]="42|pass|${EPOCHSECONDS}"
  _AI_CANDY_PROMPT_GH_PR_CACHE_ID=-1
  _ai_candy_compute_pr_status_direct

  _AI_CANDY_AI_TOOLS_DETECTED=1
  _AI_CANDY_HAS_CLAUDE=0
  _AI_CANDY_HAS_CODEX=1
  _AI_CANDY_HAS_GEMINI=1
  _AI_CANDY_HAS_KIMI=0
  _AI_CANDY_AI_PROCESS_COUNTS=(claude 0 codex 1 gemini 0 kimi 0)
  _AI_CANDY_AI_PROCESS_SNAPSHOT_TIME="$EPOCHSECONDS"
  _ai_candy_compute_ai_tools_direct

  _AI_CANDY_PP_SYSINFO_OS_LONG="AlmaLinux-9.7"
  _AI_CANDY_PP_SYSINFO_OS_SHORT="Alma-9.7"
  _AI_CANDY_PP_SYSINFO_KERNEL_LONG=", Linux-5.14.0"
  _AI_CANDY_PP_SYSINFO_KERNEL_SHORT=", Linux-5.14"
  _ai_candy_sysinfo_set_emoji_variants

  _demo_seed_path_context
  COLUMNS="$_DEMO_COLUMNS"
  _ai_candy_compute_layout_mode
}

function _demo_render_prompt() {
  _demo_compute_prompt
  local evaluated_prompt="${(e)PROMPT}"
  local evaluated_rprompt="${(e)RPROMPT}"
  local first_line="$evaluated_prompt"
  local second_line=""
  integer left_width=0 right_width=0 right_column=0

  if [[ "$evaluated_prompt" == *$'\n'* ]]; then
    first_line="${evaluated_prompt%%$'\n'*}"
    second_line="${evaluated_prompt#*$'\n'}"
  fi
  builtin print -Pn -- "$first_line"
  if [[ -n "$evaluated_rprompt" ]]; then
    _ai_candy_prompt_markup_width "$first_line"
    left_width="$REPLY"
    _ai_candy_prompt_markup_width "$evaluated_rprompt"
    right_width="$REPLY"
    right_column=$(( COLUMNS - right_width + 1 ))
    if (( right_column > left_width + 1 )); then
      builtin print -Pn -- $'\e['"${right_column}G"
    else
      builtin print -n -- " "
    fi
    builtin print -Pn -- "$evaluated_rprompt"
  fi
  builtin print
  [[ -n "$second_line" ]] && builtin print -Pn -- "$second_line"
}

function _demo_show_frame() {
  builtin print -n -- $'\e[2J\e[H'
  builtin print -r -- "AI Candy | $_DEMO_TITLE"
  builtin print -r -- "Workspace: ~/src/ai-candy | Identity: demo@workstation"
  [[ -n "$_DEMO_MESSAGE" ]] && builtin print -r -- "$_DEMO_MESSAGE"
  builtin print
  _demo_render_prompt
}

function _demo_run_toggle() {
  local toggle_function="$1"
  local message_file="${TMPDIR}/toggle-message"
  "$toggle_function" >| "$message_file"
  _DEMO_MESSAGE="$(<"$message_file")"
  _ai_candy_cache_remove_path "$message_file"
}

_demo_seed_caches
_demo_show_frame
while IFS= builtin read -r demo_command; do
  case "$demo_command" in
    e)
      _demo_run_toggle _ai_candy_prompt_toggle_emoji
      _DEMO_TITLE="PLAIN / LONG"
      ;;
    p)
      _demo_run_toggle _ai_candy_prompt_toggle_path_sep
      _DEMO_TITLE="PLAIN / SLASH PATH"
      ;;
    n)
      _demo_run_toggle _ai_candy_prompt_toggle_network
      _DEMO_TITLE="NETWORK OFF"
      ;;
    a)
      _demo_run_toggle _ai_candy_prompt_toggle_ai
      _DEMO_TITLE="TOOLS OFF"
      ;;
    o)
      _demo_run_toggle _ai_candy_prompt_toggle_os
      _DEMO_TITLE="OS OFF"
      ;;
    off)
      _demo_run_toggle _ai_candy_prompt_all_off
      _DEMO_TITLE="ALL OPTIONAL FEATURES OFF"
      ;;
    on)
      _demo_run_toggle _ai_candy_prompt_all_on
      _DEMO_COLUMNS=160
      _DEMO_TITLE="RICH / LONG"
      ;;
    compact)
      _DEMO_COLUMNS=112
      _DEMO_MESSAGE="Layout: COMPACT"
      _DEMO_TITLE="RICH / COMPACT"
      ;;
    minimal)
      _DEMO_COLUMNS=72
      _DEMO_MESSAGE="Layout: MINIMAL"
      _DEMO_TITLE="RICH / MINIMAL"
      ;;
    clean)
      _DEMO_COLUMNS=160
      _DEMO_MESSAGE=""
      _DEMO_TITLE="RICH / LONG"
      ;;
    quit|exit)
      builtin print
      exit 0
      ;;
    *)
      _DEMO_MESSAGE="Commands: e p n a o off on compact minimal quit"
      ;;
  esac
  _demo_show_frame
done
SESSION
  command chmod 700 "$temp_file"
  command mv -f "$temp_file" "$session_file"
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
  [[ -f "$THEME_FILE" && ! -L "$THEME_FILE" ]] || {
    print -u2 -r -- "Theme source must be a regular file."
    return 1
  }
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
  local fixture_data="${output_dir}/data"
  local fixture_tmp="${output_dir}/tmp"
  local fixture_workspace="${fixture_home}/src/ai-candy"
  command mkdir -p "$fixture_workspace" "$fixture_cache" "$fixture_config" \
    "$fixture_data" "$fixture_tmp"
  command chmod 700 "$fixture_home" "$fixture_cache" "$fixture_config" \
    "$fixture_data" "$fixture_tmp" "${fixture_home}/src" "$fixture_workspace"

  local theme_copy="${output_dir}/ai-candy.zsh-theme"
  local theme_temp
  theme_temp=$(command mktemp "${output_dir}/.theme.XXXXXX")
  command cp "$THEME_FILE" "$theme_temp"
  command chmod 600 "$theme_temp"
  command mv -f "$theme_temp" "$theme_copy"

  _demo_write_session "$output_dir"
  local old_frame
  for old_frame in "$output_dir"/*.ansi(N); do
    command rm -f "$old_frame"
  done
  _demo_assert_private_text_absent "${output_dir}/session.zsh"
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

function _demo_stop_renderer() {
  setopt localoptions noerrexit
  local renderer_pid="$_DEMO_RENDERER_PID"
  local process_pid=""
  integer attempt previous_count=-1 index

  [[ "$renderer_pid" == <-> ]] || return 0
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
  _DEMO_RENDERER_PID=""
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
  return "$renderer_status"
}

function _demo_render_with_vhs() {
  setopt localoptions err_return
  local render_dir="${1:a}"
  local vhs_command="" ttyd_command="" ffmpeg_command=""
  local env_command=""
  local font_home="${ACTUAL_HOME:-${render_dir}/home}"
  local -a render_environment

  vhs_command=$(builtin whence -p vhs 2>/dev/null) || vhs_command=""
  ttyd_command=$(builtin whence -p ttyd 2>/dev/null) || ttyd_command=""
  ffmpeg_command=$(builtin whence -p ffmpeg 2>/dev/null) || ffmpeg_command=""
  [[ -x "$vhs_command" && -x "$ttyd_command" && -x "$ffmpeg_command" ]] || {
    print -u2 -r -- "Install VHS, ttyd, and ffmpeg to generate demo assets."
    return 1
  }
  env_command=$(builtin whence -p env 2>/dev/null) || env_command=""
  [[ -x "$env_command" ]] || {
    print -u2 -r -- "The env command is required for isolated rendering."
    return 1
  }
  render_environment=(
    HOME="$font_home"
    ZDOTDIR="${render_dir}/config"
    XDG_CACHE_HOME="${render_dir}/cache"
    XDG_CONFIG_HOME="${render_dir}/config"
    USER=demo
    LOGNAME=demo
    HOST=workstation
    HOSTNAME=workstation
    LANG=C
    TERM="${TERM:-xterm-256color}"
    PATH="${PATH:-/usr/bin:/bin}"
  )
  [[ -n "$ACTUAL_XDG_DATA_HOME" ]] && \
    render_environment+=(XDG_DATA_HOME="$ACTUAL_XDG_DATA_HOME")
  _demo_run_renderer_command "$render_dir" "$env_command" -i \
    "${render_environment[@]}" "$vhs_command" "$TAPE_FILE"
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

  local text_content="$(<"$text_output")"
  local expected_text
  local -a expected_texts=(
    "AI Candy |"
    "demo@workstation"
    "Network mode: OFF"
    "Disabled: public IP, GitHub username/PR status, AI update checks"
    "All toggles turned ON:"
    "Layout: MINIMAL"
  )
  for expected_text in "${expected_texts[@]}"; do
    if [[ "$text_content" != *"$expected_text"* ]]; then
      print -u2 -r -- "VHS output is missing expected demo content."
      return 1
    fi
  done

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
