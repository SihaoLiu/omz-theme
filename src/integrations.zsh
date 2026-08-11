# Oh My Zsh async Git integration.
function _ai_candy_git_prompt_async() {
  emulate -L zsh
  setopt localoptions noerrexit noerrreturn
  local _AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0

  _ai_candy_get_cached_git_root
  _AI_CANDY_PP_CACHED_GIT_ROOT="$REPLY"
  _AI_CANDY_GIT_SNAPSHOT_RENDER_ID=-1
  _ai_candy_collect_git_snapshot || return 0
  _ai_candy_format_git_snapshot
  if [[ -n "${_AI_CANDY_GIT_FORMATTED_INFO}${_AI_CANDY_GIT_FORMATTED_EXT}" ]]; then
    builtin print -rn -- \
      " ${_AI_CANDY_GIT_FORMATTED_INFO}${_AI_CANDY_GIT_FORMATTED_EXT}"
  fi
}

typeset _ai_candy_async_style=""
if (( $+functions[_omz_register_handler] && $+functions[_omz_async_request] )) && \
   { builtin zstyle -t ':omz:alpha:lib:git' async-prompt || \
     builtin zstyle -T ':omz:alpha:lib:git' async-prompt || \
     { builtin zstyle -s ':omz:alpha:lib:git' async-prompt \
         _ai_candy_async_style && \
       [[ "$_ai_candy_async_style" == "force" ]]; }; }; then
  if _omz_register_handler _ai_candy_git_prompt_async; then
    _AI_CANDY_USE_OMZ_ASYNC=1
  fi
fi
unset _ai_candy_async_style

# Return success only when a stable remote version is newer than the installed one.
_ai_candy_update_available() {
  emulate -L zsh
  local installed="$1"
  local remote="$2"

  [[ "$installed" == <->.<->.<-> && "$remote" == <->.<->.<-> ]] || return 1

  local -a installed_parts=("${(@s:.:)installed}")
  local -a remote_parts=("${(@s:.:)remote}")
  local installed_part remote_part
  integer index

  for index in 1 2 3; do
    installed_part="${installed_parts[index]}"
    remote_part="${remote_parts[index]}"
    while [[ "$installed_part" == 0?* ]]; do
      installed_part="${installed_part#0}"
    done
    while [[ "$remote_part" == 0?* ]]; do
      remote_part="${remote_part#0}"
    done

    (( ${#remote_part} > ${#installed_part} )) && return 0
    (( ${#remote_part} < ${#installed_part} )) && return 1
    [[ "$remote_part" > "$installed_part" ]] && return 0
    [[ "$remote_part" < "$installed_part" ]] && return 1
  done
  return 1
}

function _ai_candy_valid_github_username() {
  local username="$1"
  (( ${#username} > 0 && ${#username} <= 100 )) && \
    [[ "$username" != *[^A-Za-z0-9-]* ]]
}

function _ai_candy_valid_ai_version() {
  local version="$1"
  (( ${#version} > 0 && ${#version} <= 100 )) && \
    [[ "$version" == [0-9]* && "$version" != *[^A-Za-z0-9._+-]* ]]
}

function _ai_candy_valid_ipv4_address() {
  local address="$1"
  local -a octets=("${(@s:.:)address}")
  local octet

  (( ${#address} <= 15 )) || return 1
  (( ${#octets} == 4 )) || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" == <-> ]] || return 1
    (( ${#octet} <= 3 )) || return 1
    (( 10#$octet <= 255 )) || return 1
  done
}

# Generic optional-tool version cache worker.
function _ai_candy_ai_tool_update_cache_worker() {
  local cache_file="$1"
  local cmd="$2"
  local version_url="$3"
  local allow_network="$4"
  local lock_file="$5"
  local net_timeout="$6"
  local persistence_epoch="$7"

  _ai_candy_acquire_background_lock "$lock_file" || return
  {
    local installed_version="" remote_version=""
    local version_output="" remote_payload=""
    local version_pattern='[0-9]+\.[0-9]+\.[0-9]+'
    local manifest_pattern='"version"[[:space:]]*:[[:space:]]*"([^"]+)"'

    version_output=$(_ai_candy_run_background_probe "$cmd" --version 2>/dev/null)
    [[ "$version_output" =~ $version_pattern ]] && installed_version="$MATCH"

    if [[ -n "$installed_version" && $_AI_CANDY_HAS_CURL -eq 1 && \
          "$allow_network" == 1 ]]; then
      remote_payload=$(_ai_candy_run_with_timeout "$net_timeout" curl -sL \
        --proto '=https' --proto-redir '=https' \
        --max-time "$net_timeout" "$version_url" 2>/dev/null)
      [[ "$remote_payload" =~ $manifest_pattern ]] && \
        remote_version="${match[1]}"
    fi

    if [[ -n "$installed_version" ]]; then
      local sep=$'\x1f'
      _ai_candy_cache_write "$cache_file" \
        "${installed_version}${sep}${remote_version}${sep}${EPOCHSECONDS}" \
        "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" "$persistence_epoch"
    fi
  } always {
    _ai_candy_cache_lock_release "${lock_file}.d"
  }
}

# Args: $1=cache_file, $2=command_name, $3=version_manifest_url
# The manifest URL is any JSON endpoint exposing a "version" field.
_ai_candy_ai_tool_update_cache() {
  setopt localoptions noerrexit

  local cache_file="$1"
  local cmd="$2"
  local version_url="$3"
  local allow_network="${4:-${_AI_CANDY_PROMPT_NETWORK_MODE:-0}}"
  local lock_file="${cache_file}.updating"
  local net_timeout="${_AI_CANDY_NETWORK_TIMEOUT:-5}"
  local persistence_epoch=""
  _ai_candy_cache_read_persistence_epoch || return
  persistence_epoch="$REPLY"

  _ai_candy_start_registered_background_worker _ai_candy_ai_tool_update_cache_worker \
    "$cache_file" "$cmd" "$version_url" "$allow_network" "$lock_file" \
    "$net_timeout" "$persistence_epoch"
}

function _ai_candy_ai_tools_update_caches_worker() {
  local allow_network="$1"
  local net_timeout="$2"
  local persistence_epoch="$3"
  shift 3

  while (( $# >= 3 )); do
    local cache_file="$1"
    local cmd="$2"
    local version_url="$3"
    shift 3
    _ai_candy_ai_tool_update_cache_worker "$cache_file" "$cmd" "$version_url" \
      "$allow_network" "${cache_file}.updating" "$net_timeout" \
      "$persistence_epoch"
  done
}

function _ai_candy_ai_tools_update_caches() {
  (( $# >= 3 )) || return 0
  local allow_network="$1"
  shift
  local persistence_epoch=""
  _ai_candy_cache_read_persistence_epoch || return
  persistence_epoch="$REPLY"

  _ai_candy_start_registered_background_worker _ai_candy_ai_tools_update_caches_worker \
    "$allow_network" "${_AI_CANDY_NETWORK_TIMEOUT:-5}" "$persistence_epoch" "$@"
}

# GitHub CLI authentication status cache (uses _AI_CANDY_CACHE_TTL_LOW)
# GitHub username cache files (uses _AI_CANDY_CACHE_TTL_MEDIUM)
# (All cache file paths defined in CACHE FILE PATHS section)

typeset -gA _AI_CANDY_REFRESH_REQUESTED
typeset -g _AI_CANDY_NETWORK_REFRESH_RETRY_DELAY=5
typeset -g _AI_CANDY_TOOL_REFRESH_RETRY_DELAY=30

function _ai_candy_request_background_refresh() {
  local refresh_key="$1"
  local retry_delay="$2"
  local current_time="${3:-$EPOCHSECONDS}"
  local request_time="${_AI_CANDY_REFRESH_REQUESTED[$refresh_key]-0}"

  if _ai_candy_cache_timestamp_is_fresh \
       "$request_time" "$retry_delay" "$current_time"; then
    return 1
  fi
  _AI_CANDY_REFRESH_REQUESTED[$refresh_key]="$current_time"
  (( ${#_AI_CANDY_REFRESH_REQUESTED} > _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )) && \
    _ai_candy_mem_cache_cleanup refresh
  return 0
}

# Get GitHub username via gh auth status.
function _ai_candy_gh_username_update_gh_worker() {
  local lock_file="$1"
  local cache_file="$2"
  local net_timeout="$3"
  local persistence_epoch="$4"

  _ai_candy_acquire_background_lock "$lock_file" || return
  {
    local username="" candidate="" first_candidate=""
    local auth_output="" line
    local account_pattern='account[[:space:]]+([^[:space:]]+)'
    auth_output=$(_ai_candy_run_with_timeout_combined_output \
      "$net_timeout" gh auth status)

    for line in "${(@f)auth_output}"; do
      if [[ "$line" =~ $account_pattern ]]; then
        candidate="${match[1]}"
        [[ -n "$first_candidate" ]] || first_candidate="$candidate"
      elif [[ "$line" == *'Active account:'*'true'* && -n "$candidate" ]]; then
        username="$candidate"
        break
      fi
    done
    [[ -n "$username" ]] || username="$first_candidate"
    _ai_candy_valid_github_username "$username" || username=""
    _ai_candy_cache_write "$cache_file" "${username}|${EPOCHSECONDS}" \
      "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" "$persistence_epoch"
  } always {
    _ai_candy_cache_lock_release "${lock_file}.d"
  }
}

function _ai_candy_gh_username_update_gh() {
  setopt localoptions noerrexit
  (( _AI_CANDY_HAS_TIMEOUT )) || return
  _ai_candy_request_background_refresh \
    gh-username-gh "$_AI_CANDY_NETWORK_REFRESH_RETRY_DELAY" || return

  local persistence_epoch=""
  _ai_candy_cache_read_persistence_epoch || return
  persistence_epoch="$REPLY"
  _ai_candy_start_registered_background_worker _ai_candy_gh_username_update_gh_worker \
    "$_AI_CANDY_GH_USERNAME_UPDATING_GH" "$_AI_CANDY_GH_USERNAME_GH_CACHE_FILE" \
    "${_AI_CANDY_NETWORK_TIMEOUT:-5}" "$persistence_epoch"
}

# Get GitHub username via ssh -T git@github.com.
function _ai_candy_gh_username_update_ssh_worker() {
  local lock_file="$1"
  local cache_file="$2"
  local net_timeout="$3"
  local persistence_epoch="$4"

  _ai_candy_acquire_background_lock "$lock_file" || return
  {
    local username="" ssh_output=""
    local greeting_pattern='Hi[[:space:]]+([^!]+)!'
    ssh_output=$(_ai_candy_run_with_timeout_combined_output "$net_timeout" \
      ssh -n -o ConnectTimeout="$net_timeout" -o BatchMode=yes -T git@github.com)
    [[ "$ssh_output" =~ $greeting_pattern ]] && username="${match[1]}"
    _ai_candy_valid_github_username "$username" || username=""
    _ai_candy_cache_write "$cache_file" "${username}|${EPOCHSECONDS}" \
      "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" "$persistence_epoch"
  } always {
    _ai_candy_cache_lock_release "${lock_file}.d"
  }
}

function _ai_candy_gh_username_update_ssh() {
  setopt localoptions noerrexit
  (( _AI_CANDY_HAS_SSH && _AI_CANDY_HAS_TIMEOUT )) || return
  _ai_candy_request_background_refresh \
    gh-username-ssh "$_AI_CANDY_NETWORK_REFRESH_RETRY_DELAY" || return

  local persistence_epoch=""
  _ai_candy_cache_read_persistence_epoch || return
  persistence_epoch="$REPLY"
  _ai_candy_start_registered_background_worker _ai_candy_gh_username_update_ssh_worker \
    "$_AI_CANDY_GH_USERNAME_UPDATING_SSH" "$_AI_CANDY_GH_USERNAME_SSH_CACHE_FILE" \
    "${_AI_CANDY_NETWORK_TIMEOUT:-5}" "$persistence_epoch"
}

# Direct-assignment version: writes result to _AI_CANDY_PP_GH_USER global variable
# PERFORMANCE: Avoids 3 subshells by reading cache files directly
function _ai_candy_compute_gh_username_direct() {
  # Skip if network mode is disabled
  if (( ! _AI_CANDY_PROMPT_NETWORK_MODE )); then
    _AI_CANDY_PP_GH_USER=""
    return
  fi

  local gh_user="" ssh_user=""
  local current_time=${EPOCHSECONDS}

  # Read gh username from cache file directly (no function call)
  if _ai_candy_cache_read_small_file "$_AI_CANDY_GH_USERNAME_GH_CACHE_FILE"; then
    local cache_gh_data="$REPLY"
    gh_user="${cache_gh_data%%|*}"
    local cache_gh_time="${cache_gh_data#*|}"
    # Trigger background refresh if expired
    if ! _ai_candy_cache_timestamp_is_fresh "$cache_gh_time" "$_AI_CANDY_CACHE_TTL_MEDIUM" "$current_time"; then
      (( _AI_CANDY_HAS_GH )) && _ai_candy_gh_username_update_gh
    fi
  else
    # No cache, trigger background refresh
    (( _AI_CANDY_HAS_GH )) && _ai_candy_gh_username_update_gh
  fi
  _ai_candy_valid_github_username "$gh_user" || gh_user=""

  # Read ssh username from cache file directly (no function call)
  if _ai_candy_cache_read_small_file "$_AI_CANDY_GH_USERNAME_SSH_CACHE_FILE"; then
    local cache_ssh_data="$REPLY"
    ssh_user="${cache_ssh_data%%|*}"
    local cache_ssh_time="${cache_ssh_data#*|}"
    # Trigger background refresh if expired
    if ! _ai_candy_cache_timestamp_is_fresh "$cache_ssh_time" "$_AI_CANDY_CACHE_TTL_MEDIUM" "$current_time"; then
      _ai_candy_gh_username_update_ssh
    fi
  else
    # No cache, trigger background refresh
    _ai_candy_gh_username_update_ssh
  fi
  _ai_candy_valid_github_username "$ssh_user" || ssh_user=""

  # Build badge and assign directly to _AI_CANDY_PP_GH_USER
  # Use $'\e' for an escape byte in direct assignment.
  # Emoji mode:  Username (icon, no brackets), Plaintext mode: [Username] (brackets, no icon)
  local ESC=$'\e'
  local badge_content=""
  if [[ -z "$gh_user" && -z "$ssh_user" ]]; then
    _AI_CANDY_PP_GH_USER=""
    return
  elif [[ -z "$gh_user" ]]; then
    badge_content="${ssh_user}"
  elif [[ -z "$ssh_user" ]]; then
    badge_content="${gh_user}"
  elif [[ "$gh_user" == "$ssh_user" ]]; then
    badge_content="${gh_user}"
  else
    # Mismatch case - use red background
    if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
      _AI_CANDY_PP_GH_USER="%{${ESC}[48;5;${_AI_CANDY_CLR_GH_USER_MISMATCH}m${ESC}[38;5;255m%}${_AI_CANDY_NF_GITHUB}${gh_user}|${ssh_user}%{$reset_color%}"
    else
      _AI_CANDY_PP_GH_USER="%{${ESC}[48;5;${_AI_CANDY_CLR_GH_USER_MISMATCH}m${ESC}[38;5;255m%}[${gh_user}|${ssh_user}]%{$reset_color%}"
    fi
    return
  fi

  # Normal case - white background
  if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
    _AI_CANDY_PP_GH_USER="%{${ESC}[48;5;${_AI_CANDY_CLR_GH_USER_BG}m${ESC}[38;5;${_AI_CANDY_CLR_GH_USER_FG}m%}${_AI_CANDY_NF_GITHUB}${badge_content}%{$reset_color%}"
  else
    _AI_CANDY_PP_GH_USER="%{${ESC}[48;5;${_AI_CANDY_CLR_GH_USER_BG}m${ESC}[38;5;${_AI_CANDY_CLR_GH_USER_FG}m%}[${badge_content}]%{$reset_color%}"
  fi
}

# ============================================================================
# PUBLIC IP ADDRESS - Cached detection with fallback providers
# ============================================================================
# Uses curl to fetch public IP from multiple providers with failover.
# Cache refreshes every 5 minutes (_AI_CANDY_CACHE_TTL_MEDIUM).
# Shows green (IP) if successful, red (offline) if all providers fail.
# Hidden if curl is not available.

# Background worker for public IP updates.
function _ai_candy_public_ip_update_worker() {
  local lock_file="$1"
  local cache_file="$2"
  local net_timeout="$3"
  local persistence_epoch="$4"

  _ai_candy_acquire_background_lock "$lock_file" || return
  {
    local ip=""
    local providers=(
      "https://checkip.amazonaws.com"
      "https://ifconfig.me"
      "https://icanhazip.com"
      "https://api.ipify.org"
    )
    local start_time="${EPOCHREALTIME:-$EPOCHSECONDS}"
    local elapsed remaining provider
    for provider in "${providers[@]}"; do
      elapsed=$(( ${EPOCHREALTIME:-$EPOCHSECONDS} - start_time ))
      remaining=$(( net_timeout - elapsed ))
      (( remaining <= 0 )) && break

      ip=$(_ai_candy_run_with_timeout "$remaining" curl -4 -s \
        --max-time "$remaining" "$provider" 2>/dev/null)
      _ai_candy_valid_ipv4_address "$ip" && break
      ip=""
    done
    _ai_candy_cache_write "$cache_file" "${ip}|${EPOCHSECONDS}" \
      "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" "$persistence_epoch"
  } always {
    _ai_candy_cache_lock_release "${lock_file}.d"
  }
}

function _ai_candy_public_ip_update_background() {
  setopt localoptions noerrexit
  (( _AI_CANDY_HAS_CURL && _AI_CANDY_HAS_TIMEOUT )) || return
  _ai_candy_request_background_refresh \
    public-ip "$_AI_CANDY_NETWORK_REFRESH_RETRY_DELAY" || return

  local persistence_epoch=""
  _ai_candy_cache_read_persistence_epoch || return
  persistence_epoch="$REPLY"
  _ai_candy_start_registered_background_worker _ai_candy_public_ip_update_worker \
    "$_AI_CANDY_PUBLIC_IP_UPDATING" "$_AI_CANDY_PUBLIC_IP_CACHE_FILE" \
    "${_AI_CANDY_NETWORK_TIMEOUT:-5}" "$persistence_epoch"
}

# Direct-assignment version: writes result to _AI_CANDY_PP_PUBLIC_IP global variable
# PERFORMANCE: Reads cache file directly without subshells
function _ai_candy_compute_public_ip_direct() {
  # Skip if network mode is disabled
  if (( ! _AI_CANDY_PROMPT_NETWORK_MODE )); then
    _AI_CANDY_PP_PUBLIC_IP=""
    return
  fi

  # Skip if curl is not available
  if (( ! _AI_CANDY_HAS_CURL )); then
    _AI_CANDY_PP_PUBLIC_IP=""
    return
  fi

  local ip=""
  local current_time=${EPOCHSECONDS}
  integer cache_was_read=0

  # Read from cache file directly
  if _ai_candy_cache_read_small_file "$_AI_CANDY_PUBLIC_IP_CACHE_FILE"; then
    cache_was_read=1
    local cache_data="$REPLY"
    ip="${cache_data%%|*}"
    local cache_time="${cache_data#*|}"
    if [[ -n "$ip" ]] && ! _ai_candy_valid_ipv4_address "$ip"; then
      ip=""
      cache_time=0
    fi

    # Trigger background refresh if expired (every 5 minutes)
    if ! _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_AI_CANDY_CACHE_TTL_MEDIUM" "$current_time"; then
      _ai_candy_public_ip_update_background
    fi
  else
    # No cache, trigger background refresh
    _ai_candy_public_ip_update_background
  fi

  # Build display string
  if [[ -n "$ip" ]]; then
    # Valid IP - show in green
    _AI_CANDY_PP_PUBLIC_IP="%{$fg[green]%}(${ip})%{$reset_color%}"
  elif (( cache_was_read )); then
    # Cache exists but IP is empty - no internet, show in red
    _AI_CANDY_PP_PUBLIC_IP="%{$fg[red]%}(offline)%{$reset_color%}"
  else
    # No cache yet - still loading
    _AI_CANDY_PP_PUBLIC_IP=""
  fi
}

# Memory cache for gh authentication status (fastest, no I/O)
typeset -g _AI_CANDY_GH_AUTH_MEM_CACHE=""
typeset -g _AI_CANDY_GH_AUTH_MEM_CACHE_TIME=0
typeset -g _AI_CANDY_GH_AUTH_REFRESH_RETRY_DELAY=4
# (_AI_CANDY_GH_AUTH_UPDATING defined in CACHE FILE PATHS section)

function _ai_candy_gh_auth_cache_ttl() {
  if [[ "$1" == "1" ]]; then
    REPLY="$_AI_CANDY_CACHE_TTL_LOW"
  else
    REPLY="$_AI_CANDY_GH_AUTH_REFRESH_RETRY_DELAY"
  fi
}

# Background worker for gh authentication status.
function _ai_candy_gh_auth_update_worker() {
  local lock_file="$1"
  local net_timeout="$2"
  local persistence_epoch="$3"

  _ai_candy_acquire_background_lock "$lock_file" || return
  {
    if _ai_candy_run_with_timeout "$net_timeout" gh auth status &>/dev/null; then
      _ai_candy_cache_write "$_AI_CANDY_GH_AUTH_CACHE_FILE" "1|${EPOCHSECONDS}" \
        "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" "$persistence_epoch"
    else
      _ai_candy_cache_write "$_AI_CANDY_GH_AUTH_CACHE_FILE" "?|${EPOCHSECONDS}" \
        "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" "$persistence_epoch"
    fi
  } always {
    _ai_candy_cache_lock_release "${lock_file}.d"
  }
}

function _ai_candy_gh_auth_update_background() {
  setopt localoptions noerrexit
  (( _AI_CANDY_HAS_TIMEOUT )) || return
  _ai_candy_request_background_refresh \
    gh-auth "$_AI_CANDY_GH_AUTH_REFRESH_RETRY_DELAY" || return

  local persistence_epoch=""
  _ai_candy_cache_read_persistence_epoch || return
  persistence_epoch="$REPLY"
  _ai_candy_start_registered_background_worker _ai_candy_gh_auth_update_worker \
    "$_AI_CANDY_GH_AUTH_UPDATING" "${_AI_CANDY_NETWORK_TIMEOUT:-5}" "$persistence_epoch"
}

# Check if gh is authenticated (cached with memory + file layers)
# PERFORMANCE: Never blocks - returns cached result and triggers background update if needed
# Returns 0 if authenticated, 1 if not (or unknown on first call)
function _ai_candy_gh_is_authenticated() {
  local current_time=${EPOCHSECONDS}
  local cache_ttl=""

  # Memory cache first (fastest, no I/O)
  _ai_candy_gh_auth_cache_ttl "$_AI_CANDY_GH_AUTH_MEM_CACHE"
  cache_ttl="$REPLY"
  if [[ -n "$_AI_CANDY_GH_AUTH_MEM_CACHE" ]] && \
     _ai_candy_cache_timestamp_is_fresh \
       "$_AI_CANDY_GH_AUTH_MEM_CACHE_TIME" "$cache_ttl" "$current_time"; then
    [[ "$_AI_CANDY_GH_AUTH_MEM_CACHE" == "1" ]] && return 0 || return 1
  fi

  # Check file cache
  if _ai_candy_cache_read_small_file "$_AI_CANDY_GH_AUTH_CACHE_FILE"; then
    local cache_data="$REPLY"
    local cached_status="${cache_data%%|*}"
    local cache_time="${cache_data#*|}"
    _ai_candy_gh_auth_cache_ttl "$cached_status"
    cache_ttl="$REPLY"

    if _ai_candy_cache_timestamp_is_fresh \
         "$cache_time" "$cache_ttl" "$current_time"; then
      # Update memory cache from file cache
      _AI_CANDY_GH_AUTH_MEM_CACHE="$cached_status"
      _AI_CANDY_GH_AUTH_MEM_CACHE_TIME="$cache_time"
      [[ "$cached_status" == "1" ]] && return 0 || return 1
    fi

    # Cache expired, use stale value but trigger background refresh
    [[ "$cached_status" == "0" || "$cached_status" == "1" ]] || cached_status="?"
    _AI_CANDY_GH_AUTH_MEM_CACHE="$cached_status"
    _AI_CANDY_GH_AUTH_MEM_CACHE_TIME=$(( current_time - _AI_CANDY_CACHE_TTL_LOW + _AI_CANDY_GH_AUTH_REFRESH_RETRY_DELAY ))
    _ai_candy_gh_auth_update_background
    [[ "$cached_status" == "1" ]] && return 0 || return 1
  fi

  # No cache at all - trigger background update and return "not authenticated"
  # This prevents blocking on first call; PR status will appear after background update completes
  _ai_candy_gh_auth_update_background
  return 1
}

# Update GitHub PR cache in a background worker.
function _ai_candy_gh_pr_update_cache_worker() {
  local remote_key="$1"
  local branch="$2"
  local lock_file="$3"
  local net_timeout="$4"
  local persistence_epoch="$5"

  _ai_candy_acquire_background_lock "$lock_file" || return
  {
    local pr_number="" ci_status="none" checks_output="" bucket
    local checks_status=124

    local -F start_time=$EPOCHREALTIME
    local -F elapsed=0 remaining=$net_timeout
    pr_number=$(_ai_candy_run_with_timeout "$remaining" gh pr view \
      --json number --jq '.number' -- "$branch" 2>/dev/null)
    [[ "$pr_number" == <-> ]] || pr_number="-1"
    if [[ "$pr_number" != "-1" ]]; then
      elapsed=$(( EPOCHREALTIME - start_time ))
      remaining=$(( net_timeout - elapsed ))
      if (( remaining > 0 )); then
        checks_output=$(_ai_candy_run_with_timeout "$remaining" gh pr checks \
          --json bucket --jq '.[].bucket' -- "$branch" 2>/dev/null)
        checks_status=$?
      fi
      for bucket in "${(@f)checks_output}"; do
        case "$bucket" in
          fail)
            ci_status="fail"
            break
            ;;
          pending|cancel)
            [[ "$ci_status" != "fail" ]] && ci_status="pending"
            ;;
          pass|skipping)
            [[ "$ci_status" == "none" ]] && ci_status="pass"
            ;;
          ?*)
            [[ "$ci_status" != "fail" ]] && ci_status="pending"
            ;;
        esac
      done
      if (( checks_status != 0 )) && [[ "$ci_status" != "fail" ]]; then
        ci_status="pending"
      fi
    fi

    local cache_key="${remote_key}|${branch}"
    _ai_candy_cache_persist_write "gh_pr" "$cache_key" \
      "${pr_number}|${ci_status}" "$EPOCHSECONDS" "$persistence_epoch"
  } always {
    _ai_candy_cache_lock_release "${lock_file}.d"
  }
}

# Cache format: pr_number|ci_status.
_ai_candy_gh_pr_update_cache() {
  setopt localoptions noerrexit
  (( _AI_CANDY_HAS_TIMEOUT )) || return

  local remote_key="$1"
  local branch="$2"
  _ai_candy_request_background_refresh \
    "gh-pr:${remote_key}|${branch}" \
    "$_AI_CANDY_NETWORK_REFRESH_RETRY_DELAY" || return
  local persistence_epoch=""
  _ai_candy_cache_read_persistence_epoch || return
  persistence_epoch="$REPLY"
  _ai_candy_start_registered_background_worker _ai_candy_gh_pr_update_cache_worker \
    "$remote_key" "$branch" "${_AI_CANDY_CACHE_DIR}/gh_pr_updating.lock" \
    "${_AI_CANDY_NETWORK_TIMEOUT:-5}" "$persistence_epoch"
}

# Emoji badges use comma-space separators; text badges use pipe separators.
# Direct-assignment version: writes result to _AI_CANDY_PP_AI_STATUS global variable
# Plaintext mode also generates _AI_CANDY_PP_AI_STATUS_LONG with full names.
# PERFORMANCE: Avoids subshells by using direct variable assignment
typeset -g _AI_CANDY_PP_AI_STATUS=""
typeset -g _AI_CANDY_PP_AI_STATUS_LONG=""
typeset -gA _AI_CANDY_AI_PROCESS_COUNTS=(claude 0 codex 0 gemini 0 kimi 0)
typeset -g _AI_CANDY_AI_PROCESS_SNAPSHOT_TIME=0
typeset -g _AI_CANDY_AI_PROCESS_SNAPSHOT_TTL=30
typeset -g _AI_CANDY_AI_PROCESS_SNAPSHOT_RETRY_TTL=5

function _ai_candy_ai_process_snapshot_is_valid() {
  local snapshot="$1"
  local current_time="${2:-$EPOCHSECONDS}"
  local -a fields=("${(@s:|:)snapshot}")
  local value
  integer index

  (( ${#fields} == 5 )) || return 1
  for (( index=1; index<=4; index++ )); do
    value="${fields[$index]}"
    [[ "$value" == <-> ]] && (( ${#value} <= 7 )) || return 1
  done
  _ai_candy_cache_timestamp_is_valid "${fields[5]}" "$current_time"
}

function _ai_candy_ai_process_count_update_worker() {
  local lock_file="$1"
  local cache_file="$2"
  local persistence_epoch="$3"

  _ai_candy_acquire_background_lock "$lock_file" || return
  {
    local process_table="" line process_name tool_name
    local node_tool_pattern='/bin/(claude|codex|gemini|kimi)([[:space:]]|$)'
    local -A counts=(claude 0 codex 0 gemini 0 kimi 0)

    if [[ "$OSTYPE" == darwin* ]]; then
      process_table=$(_ai_candy_run_background_probe \
        ps -U "$UID" -o comm= -o args= 2>/dev/null) || return
    else
      process_table=$(_ai_candy_run_background_probe \
        ps -u "$UID" -o comm= -o args= 2>/dev/null) || return
    fi

    for line in "${(@f)process_table}"; do
      [[ -n "$line" && "$line" != *"--version"* ]] || continue
      line="${line#"${line%%[![:space:]]*}"}"
      process_name="${line%%[[:space:]]*}"
      process_name="${process_name:t}"
      case "$process_name" in
        claude|codex|gemini|kimi)
          counts[$process_name]=$(( ${counts[$process_name]} + 1 ))
          ;;
        node)
          if [[ "$line" =~ $node_tool_pattern ]]; then
            tool_name="${match[1]}"
            counts[$tool_name]=$(( ${counts[$tool_name]} + 1 ))
          fi
          ;;
      esac
    done

    _ai_candy_cache_write "$cache_file" \
      "${counts[claude]}|${counts[codex]}|${counts[gemini]}|${counts[kimi]}|${EPOCHSECONDS}" \
      "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" "$persistence_epoch"
  } always {
    _ai_candy_cache_lock_release "${lock_file}.d"
  }
}

function _ai_candy_refresh_ai_process_counts() {
  local current_time="$EPOCHSECONDS"
  if _ai_candy_cache_timestamp_is_fresh "$_AI_CANDY_AI_PROCESS_SNAPSHOT_TIME" \
       "$_AI_CANDY_AI_PROCESS_SNAPSHOT_TTL" "$current_time"; then
    return 0
  fi

  if _ai_candy_cache_read_small_file "$_AI_CANDY_AI_PROCESS_CACHE_FILE"; then
    local snapshot="$REPLY"
    if _ai_candy_ai_process_snapshot_is_valid "$snapshot" "$current_time"; then
      local -a fields=("${(@s:|:)snapshot}")
      _AI_CANDY_AI_PROCESS_COUNTS=(
        claude "${fields[1]}"
        codex "${fields[2]}"
        gemini "${fields[3]}"
        kimi "${fields[4]}"
      )
      _AI_CANDY_AI_PROCESS_SNAPSHOT_TIME="${fields[5]}"
      if _ai_candy_cache_timestamp_is_fresh \
           "$_AI_CANDY_AI_PROCESS_SNAPSHOT_TIME" \
           "$_AI_CANDY_AI_PROCESS_SNAPSHOT_TTL" "$current_time"; then
        return 0
      fi
    fi
  fi

  _ai_candy_request_background_refresh ai-process-counts \
    "$_AI_CANDY_AI_PROCESS_SNAPSHOT_RETRY_TTL" "$current_time" || return 0
  local persistence_epoch=""
  _ai_candy_cache_read_persistence_epoch || return 0
  persistence_epoch="$REPLY"
  _ai_candy_start_registered_background_worker \
    _ai_candy_ai_process_count_update_worker \
    "${_AI_CANDY_AI_PROCESS_CACHE_FILE}.updating" \
    "$_AI_CANDY_AI_PROCESS_CACHE_FILE" "$persistence_epoch" || true
}

function _ai_candy_count_ai_instances() {
  local process_name="$1"
  REPLY="${_AI_CANDY_AI_PROCESS_COUNTS[$process_name]:-0}"
}

# Generic optional-tool status computation
# Sets caller-scoped variables: tool_result, tool_result_long
# Args: $1=has_flag (0/1), $2=cache_file, $3=cmd_name, $4=version_url,
#       $5=short_icon, $6=long_icon, $7=color_code, $8=long_name,
#       $9=process_name
function _ai_candy_compute_ai_tool_status() {
  local has_flag="$1" cache_file="$2" cmd_name="$3" version_url="$4"
  local short_icon="$5" long_icon="$6" color_code="$7"
  local long_name="$8" process_name="$9"

  tool_result=""
  tool_result_long=""

  (( has_flag )) || return

  local installed_version="" remote_version="" cache_time=0
  local current_time=${EPOCHSECONDS}
  integer refresh_needed=0

  if _ai_candy_cache_read_small_file "$cache_file"; then
    # Format: installed_version<SEP>remote_version<SEP>timestamp (SEP = \x1f Unit Separator)
    local sep=$'\x1f'
    local cache_data="$REPLY"
    IFS="$sep" builtin read -r installed_version remote_version cache_time \
      <<< "$cache_data"
    _ai_candy_cache_timestamp_is_valid "$cache_time" "$current_time" || cache_time=0
    _ai_candy_valid_ai_version "$installed_version" || installed_version=""
    _ai_candy_valid_ai_version "$remote_version" || remote_version=""
    (( _AI_CANDY_PROMPT_NETWORK_MODE )) || remote_version=""
    _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_AI_CANDY_CACHE_TTL_LOW" \
      "$current_time" || refresh_needed=1
  else
    refresh_needed=1
  fi

  if (( refresh_needed )); then
    if _ai_candy_request_background_refresh \
         "tool:${cache_file}" "$_AI_CANDY_TOOL_REFRESH_RETRY_DELAY" \
         "$current_time"; then
      refresh_jobs+=("$cache_file" "$cmd_name" "$version_url")
    fi
  fi

  if [[ -n "$installed_version" ]]; then
    local update_ind=""
    _ai_candy_update_available "$installed_version" "$remote_version" && update_ind="%{$fg[red]%}*"

    # Count running instances (strip whitespace, default to 0)
    _ai_candy_count_ai_instances "$process_name"
    local instance_count="$REPLY"
    instance_count="${instance_count//[^0-9]/}"  # Keep only digits
    : "${instance_count:=0}"  # Default to 0 if empty
    local count_str=""
    (( instance_count > 0 )) && count_str="(x${instance_count})"

    if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
      # Emoji mode: icon version*(xN)
      tool_result="%{$FG[$color_code]%}%B${short_icon}${installed_version}${update_ind}${count_str}%b%{$reset_color%}"
      tool_result_long="%{$FG[$color_code]%}%B${long_icon}${installed_version}${update_ind}${count_str}%b%{$reset_color%}"
    else
      # Text mode: Name(N):version*
      local count_suffix=""
      (( instance_count > 0 )) && count_suffix="(${instance_count})"
      tool_result="%{$FG[$color_code]%}%B${short_icon}${count_suffix}${installed_version}${update_ind}%b%{$reset_color%}"
      tool_result_long="%{$FG[$color_code]%}%B${long_name}${count_suffix}:${installed_version}${update_ind}%b%{$reset_color%}"
    fi
  fi
}

function _ai_candy_compute_ai_tools_direct() {
  # Skip if optional-tool display is disabled.
  if (( ! _AI_CANDY_PROMPT_AI_MODE )); then
    _AI_CANDY_PP_AI_STATUS=""
    _AI_CANDY_PP_AI_STATUS_LONG=""
    return
  fi

  # Detect optional tools on the first render, after shell managers load.
  if (( ! _AI_CANDY_AI_TOOLS_DETECTED )); then
    _ai_candy_detect_optional_commands
  fi

  if (( _AI_CANDY_HAS_CLAUDE || _AI_CANDY_HAS_CODEX || _AI_CANDY_HAS_GEMINI || _AI_CANDY_HAS_KIMI )); then
    _ai_candy_refresh_ai_process_counts
  fi

  local ai_status="" ai_status_long=""
  local -a short_results long_results refresh_jobs
  local tool_result tool_result_long  # Set by _ai_candy_compute_ai_tool_status

  local icon_s icon_l
  (( _AI_CANDY_PROMPT_EMOJI_MODE )) && icon_s="$_AI_CANDY_NF_CLAUDE" icon_l="$_AI_CANDY_NF_CLAUDE" || { icon_s="Cl:"; icon_l="Claude:"; }
  _ai_candy_compute_ai_tool_status "$_AI_CANDY_HAS_CLAUDE" "$_AI_CANDY_CLAUDE_CACHE_FILE" "claude" \
    "https://registry.npmjs.org/@anthropic-ai/claude-code/latest" "$icon_s" "$icon_l" "$_AI_CANDY_CLR_CLAUDE" \
    "Claude" "claude"
  [[ -n "$tool_result" ]] && short_results+=("$tool_result") && long_results+=("$tool_result_long")

  (( _AI_CANDY_PROMPT_EMOJI_MODE )) && icon_s="$_AI_CANDY_NF_CODEX" icon_l="$_AI_CANDY_NF_CODEX" || { icon_s="Cx:"; icon_l="Codex:"; }
  _ai_candy_compute_ai_tool_status "$_AI_CANDY_HAS_CODEX" "$_AI_CANDY_CODEX_CACHE_FILE" "codex" \
    "https://registry.npmjs.org/@openai/codex/latest" "$icon_s" "$icon_l" "$_AI_CANDY_CLR_CODEX" \
    "Codex" "codex"
  [[ -n "$tool_result" ]] && short_results+=("$tool_result") && long_results+=("$tool_result_long")

  (( _AI_CANDY_PROMPT_EMOJI_MODE )) && icon_s="$_AI_CANDY_NF_GEMINI" icon_l="$_AI_CANDY_NF_GEMINI" || { icon_s="Gm:"; icon_l="Gemini:"; }
  _ai_candy_compute_ai_tool_status "$_AI_CANDY_HAS_GEMINI" "$_AI_CANDY_GEMINI_CACHE_FILE" "gemini" \
    "https://registry.npmjs.org/@google/gemini-cli/latest" "$icon_s" "$icon_l" "$_AI_CANDY_CLR_GEMINI" \
    "Gemini" "gemini"
  [[ -n "$tool_result" ]] && short_results+=("$tool_result") && long_results+=("$tool_result_long")

  (( _AI_CANDY_PROMPT_EMOJI_MODE )) && icon_s="$_AI_CANDY_NF_KIMI" icon_l="$_AI_CANDY_NF_KIMI" || { icon_s="Km:"; icon_l="Kimi:"; }
  _ai_candy_compute_ai_tool_status "$_AI_CANDY_HAS_KIMI" "$_AI_CANDY_KIMI_CACHE_FILE" "kimi" \
    "https://code.kimi.com/kimi-code/latest.json" "$icon_s" "$icon_l" "$_AI_CANDY_CLR_KIMI" \
    "Kimi" "kimi"
  [[ -n "$tool_result" ]] && short_results+=("$tool_result") && long_results+=("$tool_result_long")

  (( ${#refresh_jobs} )) && \
    _ai_candy_ai_tools_update_caches "$_AI_CANDY_PROMPT_NETWORK_MODE" "${refresh_jobs[@]}"

  if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
    ai_status="${(j:, :)short_results}"
    ai_status_long="${(j:, :)long_results}"
  else
    ai_status="${(j:|:)short_results}"
    ai_status_long="${(j:|:)long_results}"
  fi

  # Wrap in brackets if any tools are present
  if [[ -n "$ai_status" ]]; then
    _AI_CANDY_PP_AI_STATUS="%{$fg[white]%}[${ai_status}%{$fg[white]%}]%{$reset_color%}"
    _AI_CANDY_PP_AI_STATUS_LONG="%{$fg[white]%}[${ai_status_long}%{$fg[white]%}]%{$reset_color%}"
  else
    _AI_CANDY_PP_AI_STATUS=""
    _AI_CANDY_PP_AI_STATUS_LONG=""
  fi
}
