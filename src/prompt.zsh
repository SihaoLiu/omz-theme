# ============================================================================
# PRECOMPUTED PROMPT PARTS - Computed once in precmd, used in PROMPT
# ============================================================================
# These variables are populated by _ai_candy_precmd_compute_prompt and used directly
# in PROMPT to avoid creating subshells for each prompt segment

# Precomputed prompt segment variables
typeset -g _PP_VENV=""           # Python virtual environment indicator
typeset -g _PP_EXIT=""           # Exit status indicator
typeset -g _PP_SSH=""            # SSH indicator
typeset -g _PP_USER_HOST=""      # user@host with color
typeset -g _PP_PUBLIC_IP=""      # Public IP address (cached)
typeset -g _PP_GH_USER=""        # GitHub username badge [Username]
typeset -g _PP_BADGE=""          # Host/container badge
typeset -g _PP_TIME=""           # Time with dynamic color
typeset -g _PP_PATH=""           # Smart path display
typeset -g _PP_GIT_INFO=""       # Git branch/status
typeset -g _PP_GIT_EXT=""        # Git extended status (ahead/behind/stash)
typeset -g _PP_GIT_SPECIAL=""    # Git special state (rebase/merge/etc)
typeset -g _PP_PR=""             # GitHub PR status
typeset -g _PP_SYSINFO_LEFT=""   # System info (left prompt, long mode only)
typeset -g _PP_AI_LEFT=""        # Optional tools in long mode
typeset -g _PP_JOBS=""           # Jobs indicator prefix
typeset -g _PP_RPROMPT=""        # Right prompt content

# Precompute all prompt segments in precmd (avoids subshells in PROMPT)
# ============================================================================
# PROMPT COMPONENT FUNCTIONS - Extracted for maintainability
# ============================================================================

# Compute Python virtual environment indicator
# Sets: _PP_VENV
# Displays: (venv_name) in yellow when a virtual environment is active
function _ai_candy_compute_venv_direct() {
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    local venv_name="${VIRTUAL_ENV:t}"  # Get basename of the path
    _ai_candy_prompt_escape_text "$venv_name"
    venv_name="$REPLY"
    _PP_VENV="%{$fg[yellow]%}(${venv_name})%{$reset_color%}"
  else
    _PP_VENV=""
  fi
}

# Compute exit status indicator
# Sets: _PP_EXIT
function _ai_candy_compute_exit_status_direct() {
  if [[ $_LAST_EXIT_STATUS -eq 0 ]]; then
    if (( _PROMPT_EMOJI_MODE )); then
      _PP_EXIT="%{$fg[green]%}[${_SYM_CHECK}]%{$reset_color%}"
    else
      _PP_EXIT="%{$fg[green]%}[OK]%{$reset_color%}"
    fi
  else
    if (( _PROMPT_EMOJI_MODE )); then
      _PP_EXIT="%{$fg[red]%}[${_SYM_CROSS}${_LAST_EXIT_STATUS}]%{$reset_color%}"
    else
      _PP_EXIT="%{$fg[red]%}[ERR${_LAST_EXIT_STATUS}]%{$reset_color%}"
    fi
  fi
}

# Compute time with dynamic color based on hour
# Sets: _PP_TIME
# Format: [HH:MM:SS TZ] where TZ is timezone abbreviation (e.g., PST, UTC)
function _ai_candy_compute_time_direct() {
  local hour=""
  if (( ${+EPOCHSECONDS} )); then
    builtin strftime -s hour "%H" "$EPOCHSECONDS"
  else
    hour=$(command date +%H)
  fi
  integer hour_value=$(( 10#$hour ))
  local time_color
  if (( hour_value >= 6 && hour_value < 12 )); then
    time_color="%{$FG[$_CLR_TIME_MORNING]%}"
  elif (( hour_value >= 12 && hour_value < 18 )); then
    time_color="%{$FG[$_CLR_TIME_AFTERNOON]%}"
  elif (( hour_value >= 18 && hour_value < 22 )); then
    time_color="%{$FG[$_CLR_TIME_EVENING]%}"
  else
    time_color="%{$FG[$_CLR_TIME_NIGHT]%}"
  fi
  _PP_TIME="${time_color}[%D{%H:%M:%S %Z}]%{$reset_color%}"
}

function _ai_candy_prompt_markup_width() {
  local value="$1"
  local visible="" token=""
  integer index=1 end found

  while (( index <= ${#value} )); do
    token="${value[index,index+1]}"
    if [[ "$token" == "%%" ]]; then
      visible+="%"
      (( index += 2 ))
      continue
    fi
    if [[ -o promptbang && "$token" == "!!" ]]; then
      visible+="!"
      (( index += 2 ))
      continue
    fi
    if [[ "$token" == "%{" ]]; then
      found=0
      for (( end=index+2; end<=${#value}-1; end++ )); do
        if [[ "${value[end,end+1]}" == "%}" ]]; then
          index=$(( end + 2 ))
          found=1
          break
        fi
      done
      (( found )) && continue
    fi
    if [[ "${value[index]}" == "%" && \
          "${value[index+1]}" == [FK] && \
          "${value[index+2]}" == "{" ]]; then
      found=0
      for (( end=index+3; end<=${#value}; end++ )); do
        if [[ "${value[end]}" == "}" ]]; then
          index=$(( end + 1 ))
          found=1
          break
        fi
      done
      (( found )) && continue
    fi
    if [[ "${value[index]}" == "%" && \
          "${value[index+1]}" == [BbUuSsfk] ]]; then
      (( index += 2 ))
      continue
    fi
    visible+="${value[index]}"
    (( index++ ))
  done
  _ai_candy_prompt_text_width "$visible"
}

# Compute layout mode based on terminal width
# Sets: _PP_BADGE, _PP_SYSINFO_LEFT, _PP_AI_LEFT, _PP_RPROMPT
# May recompute: _PP_PATH (in min mode)
function _ai_candy_compute_layout_mode() {
  # Use precomputed sysinfo from global variables
  # In emoji mode, use versions with distro/kernel icons (, , , , )
  local os_long os_short kernel_long kernel_short
  if (( _PROMPT_EMOJI_MODE )); then
    os_long="$_PP_SYSINFO_OS_LONG_EMOJI"
    os_short="$_PP_SYSINFO_OS_SHORT_EMOJI"
    kernel_long="$_PP_SYSINFO_KERNEL_LONG_EMOJI"
    kernel_short="$_PP_SYSINFO_KERNEL_SHORT_EMOJI"
  else
    os_long="$_PP_SYSINFO_OS_LONG"
    os_short="$_PP_SYSINFO_OS_SHORT"
    kernel_long="$_PP_SYSINFO_KERNEL_LONG"
    kernel_short="$_PP_SYSINFO_KERNEL_SHORT"
  fi
  if (( ! _PROMPT_OS_MODE )); then
    os_long=""
    os_short=""
    kernel_long=""
    kernel_short=""
  fi

  # Container/host/session badge (priority: Container > TTY > GNOME > KDE > XFCE > Xorg > Host)
  local badge_icon badge_color
  local _desktop_lower="${(L)${XDG_SESSION_DESKTOP:-}}"  # lowercase for case-insensitive matching
  if [[ -f /run/.containerenv ]]; then
    # Container environment
    (( _PROMPT_EMOJI_MODE )) && badge_icon="$_NF_CONTAINER" || badge_icon="C"
    badge_color="%{$fg[magenta]%}"
  elif [[ "${XDG_SESSION_TYPE:-}" == "tty" ]]; then
    # TTY session
    (( _PROMPT_EMOJI_MODE )) && badge_icon="$_NF_TTY" || badge_icon="T"
    badge_color="%{$fg[yellow]%}"
  elif [[ "$_desktop_lower" == *gnome* ]]; then
    # GNOME desktop (matches gnome, gnome-xorg, gnome-wayland, etc.)
    (( _PROMPT_EMOJI_MODE )) && badge_icon="$_NF_GNOME" || badge_icon="G"
    badge_color="%{$fg[yellow]%}"
  elif [[ "$_desktop_lower" == *kde* || "$_desktop_lower" == *plasma* ]]; then
    # KDE Plasma desktop
    (( _PROMPT_EMOJI_MODE )) && badge_icon="$_NF_KDE" || badge_icon="K"
    badge_color="%{$fg[yellow]%}"
  elif [[ "$_desktop_lower" == *xfce* ]]; then
    # XFCE desktop
    (( _PROMPT_EMOJI_MODE )) && badge_icon="$_NF_XFCE" || badge_icon="X"
    badge_color="%{$fg[yellow]%}"
  elif [[ "$_desktop_lower" == *xorg* ]]; then
    # Xorg session (generic X11)
    (( _PROMPT_EMOJI_MODE )) && badge_icon="$_NF_XORG" || badge_icon="O"
    badge_color="%{$fg[yellow]%}"
  else
    # Default: Host
    (( _PROMPT_EMOJI_MODE )) && badge_icon="$_SYM_HOST" || badge_icon="H"
    badge_color="%{$fg[yellow]%}"
  fi
  # In emoji mode, strip trailing space from Nerd Font environment icons
  (( _PROMPT_EMOJI_MODE )) && badge_icon="${badge_icon% }"
  _PP_BADGE=" ${badge_color}${badge_icon}%{$reset_color%}"

  # Parse the path once so layout can use its visible length before rendering.
  _ai_candy_prepare_smart_path_context

  # Calculate visible lengths (remove all prompt escape sequences)
  # NOTE: For segments containing %n, %m, %j etc., we must use actual values
  # Strips: %{...%}, %B/%b (bold), %U/%u (underline), %S/%s (standout),
  #         %F{...}/%f (fg color), %K{...}/%k (bg color)
  local git_len git_ext_len git_special_len ai_len ai_len_long pr_len
  local venv_len
  local path_len="${_SMART_PATH_TOTAL_LENGTH:-0}"
  local user_host_len gh_user_len exit_len ssh_len
  _ai_candy_prompt_markup_width "$_PP_GIT_INFO"; git_len="$REPLY"
  _ai_candy_prompt_markup_width "$_PP_GIT_EXT"; git_ext_len="$REPLY"
  _ai_candy_prompt_markup_width "$_PP_GIT_SPECIAL"; git_special_len="$REPLY"
  _ai_candy_prompt_markup_width "$_PP_AI_STATUS"; ai_len="$REPLY"
  _ai_candy_prompt_markup_width "$_PP_AI_STATUS_LONG"; ai_len_long="$REPLY"
  _ai_candy_prompt_markup_width "$_PP_PR"; pr_len="$REPLY"
  _ai_candy_prompt_markup_width "$_PP_GH_USER"; gh_user_len="$REPLY"
  _ai_candy_prompt_markup_width "$_PP_EXIT"; exit_len="$REPLY"
  _ai_candy_prompt_markup_width "$_PP_SSH"; ssh_len="$REPLY"
  _ai_candy_prompt_markup_width "$_PP_VENV"; venv_len="$REPLY"

  # user@host: %n@%m expands to actual username and hostname
  # Use actual values instead of literal "%n@%m" (4 chars)
  local actual_user="${(%):-%n}"
  local actual_host="${(%):-%m}"
  _ai_candy_prompt_text_width "${actual_user}@${actual_host}"
  user_host_len="$REPLY"

  # public_ip_len: (xxx.xxx.xxx.xxx) up to 17 chars, or (offline) 9 chars, or empty
  # NOTE: IPv4 only - see _ai_candy_public_ip_update_background for rationale
  local public_ip_len=0
  if [[ -n "$_PP_PUBLIC_IP" ]]; then
    _ai_candy_prompt_markup_width "$_PP_PUBLIC_IP"
    public_ip_len="$REPLY"
  fi

  # time_len: compute dynamically based on actual timezone abbreviation
  # Format: [HH:MM:SS TZ] where TZ varies (e.g., PST=3, UTC=3, CEST=4)
  local tz_abbrev
  if (( ${+EPOCHSECONDS} )); then
    builtin strftime -s tz_abbrev "%Z" "$EPOCHSECONDS"
  else
    tz_abbrev=$(command date +%Z)
  fi
  # [HH:MM:SS TZ] = 1 + 8 + 1 + tz_len + 1 = 11 + tz_len
  _ai_candy_prompt_text_width "[00:00:00 ${tz_abbrev}]"
  local time_len="$REPLY"

  # badge_len accounts for leading space + icon (" H" = 2 chars)
  # fixed_len includes:
  #   - 2 literal spaces in PROMPT (after BADGE, after TIME)
  #   - _LAYOUT_MARGIN buffer to trigger shorter format before overflow
  _ai_candy_prompt_text_width " ${badge_icon}"
  local fixed_len=$((2 + _LAYOUT_MARGIN)) badge_len="$REPLY"

  # min_len excludes system info and optional tools.
  # pr_space: 1 space before PR if PR is present
  local pr_space=0
  (( pr_len > 0 )) && pr_space=1
  local min_len=$((venv_len + exit_len + ssh_len + user_host_len + public_ip_len + gh_user_len + badge_len + time_len + path_len + git_len + git_ext_len + git_special_len + pr_space + pr_len + fixed_len))

  # Calculate lengths for different layout modes
  local short_version="${os_short}${kernel_short}"
  local short_sysinfo_len=0
  if (( _PROMPT_OS_MODE )); then
    _ai_candy_prompt_text_width " [${short_version}]"
    short_sysinfo_len="$REPLY"
  fi
  local short_len=$((min_len + short_sysinfo_len))

  local ai_space=0
  [[ -n "$_PP_AI_STATUS" ]] && ai_space=1
  local short_ai_len=$((short_len + ai_len + ai_space))

  local long_version="${os_long}${kernel_long}"
  local long_sysinfo_len=0
  if (( _PROMPT_OS_MODE )); then
    _ai_candy_prompt_text_width " [${long_version}]"
    long_sysinfo_len="$REPLY"
  fi
  local long_len=$((min_len + long_sysinfo_len + ai_len + ai_space))
  local long_len_with_long_ai=$((min_len + long_sysinfo_len + ai_len_long + ai_space))

  # Decide layout mode
  local mode system_info ai_output=""

  if (( long_len <= COLUMNS )); then
    mode="long"
    (( _PROMPT_OS_MODE )) && system_info=" %{$fg[cyan]%}[${long_version}]%{$reset_color%}"
    if (( ! _PROMPT_EMOJI_MODE )) && [[ -n "$_PP_AI_STATUS_LONG" ]] && (( long_len_with_long_ai <= COLUMNS )); then
      ai_output=" $_PP_AI_STATUS_LONG"
    elif [[ -n "$_PP_AI_STATUS" ]]; then
      ai_output=" $_PP_AI_STATUS"
    fi
  elif (( short_ai_len <= COLUMNS )); then
    mode="short"
    (( _PROMPT_OS_MODE )) && system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
    [[ -n "$_PP_AI_STATUS" ]] && ai_output=" $_PP_AI_STATUS"
  elif (( short_len <= COLUMNS )); then
    mode="short"
    (( _PROMPT_OS_MODE )) && system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
    # Omit optional tools when they would overflow.
  else
    mode="min"
    (( _PROMPT_OS_MODE )) && system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
  fi

  if [[ "$mode" == "min" ]]; then
    local available_path_width=$(( COLUMNS - (min_len - path_len) ))
    (( available_path_width < 4 )) && available_path_width=4
    _ai_candy_compute_smart_path_direct "short" "$available_path_width"
  else
    _ai_candy_compute_smart_path_direct "full"
  fi

  # Set output based on mode
  if [[ "$mode" == "long" ]]; then
    _PP_SYSINFO_LEFT="$system_info"
    _PP_AI_LEFT="$ai_output"
    _PP_RPROMPT=""
  else
    _PP_SYSINFO_LEFT=""
    _PP_AI_LEFT=""
    _PP_RPROMPT="${system_info}${ai_output}"
  fi
}

# ============================================================================
# MAIN PROMPT COMPUTATION - Orchestrates all prompt components
# ============================================================================
# PERFORMANCE: Inline logic and use direct variable assignment to minimize subshells
# Target: reduce from 10-15 subshells to 2-4 per prompt

# Per-prompt git root cache (avoids repeated _ai_candy_get_cached_git_root calls)
typeset -g _PP_CACHED_GIT_ROOT=""

function _ai_candy_precmd_compute_prompt() {
  emulate -L zsh
  setopt localoptions noerrexit noerrreturn

  # Cache git root once per prompt (used by multiple functions)
  _ai_candy_get_cached_git_root
  _PP_CACHED_GIT_ROOT="$REPLY"

  # === Status indicators ===
  _ai_candy_compute_venv_direct
  _ai_candy_compute_exit_status_direct

  # SSH indicator
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    (( _PROMPT_EMOJI_MODE )) && _PP_SSH="%{$fg[cyan]%}${_NF_SSH}%{$reset_color%}" || _PP_SSH="%{$fg[cyan]%}[SSH]%{$reset_color%} "
  else
    _PP_SSH=""
  fi

  # User@host
  _PP_USER_HOST="%{$FG[$_CLR_USER_HOST]%}%n@%m%{$reset_color%}"

  # Public IP address (cached)
  _ai_candy_compute_public_ip_direct

  # GitHub username badge
  _ai_candy_compute_gh_username_direct

  # Time with dynamic color
  _ai_candy_compute_time_direct

  # Jobs indicator
  (( _PROMPT_EMOJI_MODE )) && _PP_JOBS="$_SYM_JOBS" || _PP_JOBS="J"

  # === Git and GitHub status ===
  _ai_candy_compute_git_info_direct
  _ai_candy_compute_git_extended_direct
  _ai_candy_compute_git_special_direct
  _ai_candy_compute_pr_status_direct

  # === Optional tools and system info ===
  _ai_candy_compute_ai_tools_direct
  _ai_candy_compute_sysinfo_direct

  # === Layout mode (sets badge, path, sysinfo placement) ===
  _ai_candy_compute_layout_mode
  return 0
}

# Add to precmd hooks (runs after _ai_candy_prompt_bump_render_id)
add-zsh-hook precmd _ai_candy_precmd_compute_prompt
add-zsh-hook precmd _ai_candy_periodic_cache_cleanup

# Per-prompt caches for git/PR segments
# IMPORTANT: These must be initialized here (not just in _ai_candy_prompt_refresh_all_caches)
# to avoid "unset variable" errors when set -u (nounset) is enabled
_PROMPT_GH_PR_CACHE=""
_PROMPT_GH_PR_CACHE_ID=-1
_PROMPT_GIT_SPECIAL_CACHE=""
_PROMPT_GIT_SPECIAL_CACHE_ID=-1

# System info cache (file-based, uses _CACHE_TTL_LOW - rarely changes)
# (_SYSINFO_CACHE_FILE defined in CACHE FILE PATHS section)

# Global variables for direct sysinfo assignment (avoids subshell)
typeset -g _PP_SYSINFO_OS_LONG=""
typeset -g _PP_SYSINFO_OS_SHORT=""
typeset -g _PP_SYSINFO_OS_LONG_EMOJI=""
typeset -g _PP_SYSINFO_OS_SHORT_EMOJI=""
typeset -g _PP_SYSINFO_KERNEL_LONG=""
typeset -g _PP_SYSINFO_KERNEL_SHORT=""
typeset -g _PP_SYSINFO_KERNEL_LONG_EMOJI=""
typeset -g _PP_SYSINFO_KERNEL_SHORT_EMOJI=""

# Nerd Font icons for OS/distro (using hex byte escapes for portability)
# macOS U+F0036 (nf-md-apple_finder), Darwin U+F179, Red Hat U+EF5D, Ubuntu U+EF72
# CentOS U+EF3D, Fedora U+F30A, AlmaLinux U+F31D, Linux U+F17C
typeset -g _NF_MACOS=$'\xf3\xb0\x80\xb6'  # U+F0036 nf-md-apple_finder
typeset -g _NF_APPLE=$'\xef\x85\xb9'      # U+F179 nf-fa-apple (for Darwin kernel)
typeset -g _NF_REDHAT=$'\xee\xbd\x9d'     # U+EF5D
typeset -g _NF_UBUNTU=$'\xee\xbd\xb2'     # U+EF72
typeset -g _NF_CENTOS=$'\xee\xbc\xbd'     # U+EF3D
typeset -g _NF_FEDORA=$'\xef\x8c\x8a'     # U+F30A
typeset -g _NF_ALMA=$'\xef\x8c\x9d'       # U+F31D
typeset -g _NF_LINUX=$'\xef\x85\xbc'      # U+F17C

# Optional tool icons use byte escapes for source portability.
typeset -g _NF_CLAUDE=$'\xef\x81\xa9 '    # U+F069 nf-fa-asterisk (+ space for 2-char width)
typeset -g _NF_GEMINI=$'\xef\x86\xa0 '    # U+F1A0 nf-fa-google (+ space for 2-char width)
typeset -g _NF_CODEX=$'\xee\x89\xbf '     # U+E27F nf-fae-atom (+ space for 2-char width)
typeset -g _NF_KIMI=$'\xef\x86\x86 '      # U+F186 nf-fa-moon_o (+ space for 2-char width)
typeset -g _NF_CONTAINER=$'\xef\x88\x9f'  # U+F21F nf-fa-docker
typeset -g _NF_SSH=$'\xf3\xb0\xa3\x80 '   # U+F08C0 nf-md-ssh (+ space for 2-char width)
typeset -g _NF_GITHUB=$'\xef\x82\x9b '    # U+F09B nf-fa-github (+ space for 2-char width)
typeset -g _NF_TTY=$'\xef\x87\xa4'        # U+F1E4 nf-fa-tty
typeset -g _NF_GNOME=$'\xef\x8d\xa1 '     # U+F361 nf-linux-gnome (+ space for 2-char width)
typeset -g _NF_KDE=$'\xef\x8c\xb2'        # U+F332 nf-linux-kde_plasma
typeset -g _NF_XFCE=$'\xef\x8d\xa8'       # U+F368 nf-linux-xfce
typeset -g _NF_XORG=$'\xef\x8d\xa9'       # U+F369 nf-linux-xorg

# Helper: Apply OS/distro icon replacements for emoji mode
_ai_candy_sysinfo_apply_os_icons() {
  local input="$1"
  # Distro replacements (order matters - more specific first)
  input="${input//macOS/${_NF_MACOS}}"
  input="${input//Red Hat Enterprise Linux/${_NF_REDHAT}}"
  input="${input//Rhel/${_NF_REDHAT}}"
  input="${input//Ubuntu/${_NF_UBUNTU}}"
  input="${input//CentOS/${_NF_CENTOS}}"
  input="${input//Centos/${_NF_CENTOS}}"
  input="${input//Fedora/${_NF_FEDORA}}"
  input="${input//AlmaLinux/${_NF_ALMA}}"
  input="${input//Almalinux/${_NF_ALMA}}"
  REPLY="$input"
}

# Kernel icons
_ai_candy_sysinfo_apply_kernel_icons() {
  local input="$1"
  input="${input//Darwin/${_NF_APPLE}}"
  input="${input//Linux/${_NF_LINUX}}"
  REPLY="$input"
}

function _ai_candy_sysinfo_set_emoji_variants() {
  _ai_candy_sysinfo_apply_os_icons "$_PP_SYSINFO_OS_LONG"
  _PP_SYSINFO_OS_LONG_EMOJI="$REPLY"
  _ai_candy_sysinfo_apply_os_icons "$_PP_SYSINFO_OS_SHORT"
  _PP_SYSINFO_OS_SHORT_EMOJI="$REPLY"
  _ai_candy_sysinfo_apply_kernel_icons "$_PP_SYSINFO_KERNEL_LONG"
  _PP_SYSINFO_KERNEL_LONG_EMOJI="$REPLY"
  _ai_candy_sysinfo_apply_kernel_icons "$_PP_SYSINFO_KERNEL_SHORT"
  _PP_SYSINFO_KERNEL_SHORT_EMOJI="$REPLY"
}

typeset -g _SYSINFO_SESSION_READY=0

# Direct-assignment version: writes result to _PP_SYSINFO_* global variables
# PERFORMANCE: Avoids 1 subshell by parsing cache directly into variables
function _ai_candy_compute_sysinfo_direct() {
  (( _PROMPT_OS_MODE )) || return 0
  (( _SYSINFO_SESSION_READY )) && return 0
  local current_time=${EPOCHSECONDS}

  # Check file cache (use zsh native file reading)
  if _ai_candy_cache_read_small_file "$_SYSINFO_CACHE_FILE"; then
    local cache_lines=("${(@f)REPLY}")
    local cache_time="${cache_lines[1]-}"
    if _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_CACHE_TTL_LOW" "$current_time"; then
      local payload="${cache_lines[2]-}"
      local -a encoded_fields decoded_fields
      encoded_fields=("${(@s:|:)payload}")
      if (( ${#encoded_fields} == 5 )) && [[ "${encoded_fields[1]}" == "v2" ]]; then
        local encoded_field
        integer cache_valid=1
        for encoded_field in "${encoded_fields[@]:1}"; do
          if _ai_candy_hex_decode "$encoded_field"; then
            decoded_fields+=("$REPLY")
          else
            cache_valid=0
            break
          fi
        done
        if (( cache_valid )); then
          _ai_candy_prompt_escape_text "${decoded_fields[1]}"
          _PP_SYSINFO_OS_LONG="$REPLY"
          _ai_candy_prompt_escape_text "${decoded_fields[2]}"
          _PP_SYSINFO_OS_SHORT="$REPLY"
          _ai_candy_prompt_escape_text "${decoded_fields[3]}"
          _PP_SYSINFO_KERNEL_LONG="$REPLY"
          _ai_candy_prompt_escape_text "${decoded_fields[4]}"
          _PP_SYSINFO_KERNEL_SHORT="$REPLY"
          _ai_candy_sysinfo_set_emoji_variants
          _SYSINFO_SESSION_READY=1
          return
        fi
      fi
    fi
  fi

  # Compute system info (first call or cache expired)
  local os_long="" os_short=""
  local kernel_long="" kernel_short=""
  local uname_snapshot=""
  command -v uname &>/dev/null && \
    uname_snapshot=$(_ai_candy_run_local_probe uname -sr 2>/dev/null)
  local -a uname_fields=("${(@s: :)uname_snapshot}")
  local os_type="${uname_fields[1]-}"
  local kernel_full="${uname_fields[2]-}"

  if [[ "$os_type" == "Darwin" ]]; then
    if command -v sw_vers &>/dev/null; then
      local product_name=$(_ai_candy_run_local_probe sw_vers -productName 2>/dev/null)
      local product_version=$(_ai_candy_run_local_probe sw_vers -productVersion 2>/dev/null)
      if [[ -n "$product_name" && -n "$product_version" ]]; then
        os_long="$product_name $product_version"
        os_short="macOS-$product_version"
      fi
    fi
  elif [[ -f /etc/os-release ]]; then
    local pretty_name="" os_id="" version_id="" line value
    while IFS= builtin read -r line; do
      case "$line" in
        PRETTY_NAME=*)
          value="${line#*=}"
          pretty_name="${value%\"}"
          pretty_name="${pretty_name#\"}"
          ;;
        ID=*)
          value="${line#*=}"
          os_id="${value%\"}"
          os_id="${os_id#\"}"
          ;;
        VERSION_ID=*)
          value="${line#*=}"
          version_id="${value%\"}"
          version_id="${version_id#\"}"
          ;;
      esac
    done < /etc/os-release

    [[ -n "$pretty_name" ]] && os_long="$pretty_name"
    if [[ -n "$os_id" && -n "$version_id" ]]; then
      os_short="${(C)os_id}-$version_id"
    elif [[ -n "$os_id" ]]; then
      os_short="${(C)os_id}"
    fi
    [[ -z "$os_long" && -n "$os_short" ]] && os_long="$os_short"
  fi

  if [[ -n "$kernel_full" ]]; then
    local kernel_name="$os_type"
    [[ -z "$kernel_name" ]] && kernel_name="Unknown"
    kernel_long=", $kernel_name-$kernel_full"
    local kernel_short_ver="${kernel_full%%-*}"
    if [[ -n "$kernel_short_ver" ]]; then
      kernel_short=", $kernel_name-$kernel_short_ver"
    else
      kernel_short="$kernel_long"
    fi
  fi

  # Cache raw fields as hex so delimiters and prompt escapes remain data.
  local -a encoded_fields=()
  local sysinfo_field
  for sysinfo_field in "$os_long" "$os_short" "$kernel_long" "$kernel_short"; do
    _ai_candy_hex_encode "$sysinfo_field"
    encoded_fields+=("$REPLY")
  done
  local result="v2|${(j:|:)encoded_fields}"
  _ai_candy_cache_write "$_SYSINFO_CACHE_FILE" "${current_time}"$'\n'"${result}" 0 || true

  _ai_candy_prompt_escape_text "$os_long"
  os_long="$REPLY"
  _ai_candy_prompt_escape_text "$os_short"
  os_short="$REPLY"
  _ai_candy_prompt_escape_text "$kernel_long"
  kernel_long="$REPLY"
  _ai_candy_prompt_escape_text "$kernel_short"
  kernel_short="$REPLY"

  # Assign to global variables
  _PP_SYSINFO_OS_LONG="$os_long"
  _PP_SYSINFO_OS_SHORT="$os_short"
  _PP_SYSINFO_KERNEL_LONG="$kernel_long"
  _PP_SYSINFO_KERNEL_SHORT="$kernel_short"
  # Generate emoji versions with OS/distro and kernel icons
  _ai_candy_sysinfo_set_emoji_variants
  _SYSINFO_SESSION_READY=1
}
