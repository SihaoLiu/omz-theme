# ============================================================================
# AI Candy - Oh My Zsh Theme
# Author: Sihao Liu <sihao@cs.ucla.edu>
# License: MIT
# Edit the modules and run scripts/build-theme.zsh instead of editing it directly.
# ============================================================================

builtin typeset -g _AI_CANDY_SOURCE_ALIASES_WERE_SET=0
builtin typeset -g _AI_CANDY_SOURCE_GLOB_SUBST_WAS_SET=0
builtin typeset -g _AI_CANDY_SOURCE_KSH_ARRAYS_WAS_SET=0
if [[ -o aliases ]]; then
  _AI_CANDY_SOURCE_ALIASES_WERE_SET=1
fi
if [[ -o globsubst ]]; then
  _AI_CANDY_SOURCE_GLOB_SUBST_WAS_SET=1
fi
if [[ -o ksharrays ]]; then
  _AI_CANDY_SOURCE_KSH_ARRAYS_WAS_SET=1
fi
builtin unsetopt aliases globsubst ksharrays

function _ai_candy_restore_source_options() {
  integer restore_aliases="${_AI_CANDY_SOURCE_ALIASES_WERE_SET:-0}"
  integer restore_glob_subst="${_AI_CANDY_SOURCE_GLOB_SUBST_WAS_SET:-0}"
  integer restore_ksh_arrays="${_AI_CANDY_SOURCE_KSH_ARRAYS_WAS_SET:-0}"
  builtin unset _AI_CANDY_SOURCE_ALIASES_WERE_SET \
    _AI_CANDY_SOURCE_GLOB_SUBST_WAS_SET _AI_CANDY_SOURCE_KSH_ARRAYS_WAS_SET
  if (( restore_aliases )); then
    builtin setopt aliases
  else
    builtin unsetopt aliases
  fi
  if (( restore_glob_subst )); then
    builtin setopt globsubst
  else
    builtin unsetopt globsubst
  fi
  if (( restore_ksh_arrays )); then
    builtin setopt ksharrays
  else
    builtin unsetopt ksharrays
  fi
}

# ============================================================================
# PYTHON VIRTUAL ENVIRONMENT - Disable default prompt modification
# ============================================================================
# We handle venv display ourselves in _ai_candy_compute_venv_direct() for consistent styling
export VIRTUAL_ENV_DISABLE_PROMPT=1

# ============================================================================
# ZSH VERSION CHECK - This theme requires zsh 5.4.2+
# ============================================================================
autoload -Uz is-at-least
if ! is-at-least 5.4.2; then
  builtin print -P "%F{red}[ai-candy.zsh-theme]%f Requires zsh 5.4.2+, current: $ZSH_VERSION"
  _ai_candy_restore_source_options
  builtin unfunction _ai_candy_restore_source_options
  return 1
fi

# Prefer Zsh builtins for local file operations. They avoid GNU/BSD command
# differences and cannot be shadowed by a slow executable earlier in PATH.
typeset -g _AI_CANDY_HAS_ZSH_FILE_BUILTINS=0
typeset -g _AI_CANDY_HAS_ZSH_CHMOD_BUILTIN=0
if builtin zmodload zsh/files 2>/dev/null && \
   (( $+builtins[zf_mkdir] && $+builtins[zf_rm] && \
      $+builtins[zf_mv] && $+builtins[zf_rmdir] )); then
  _AI_CANDY_HAS_ZSH_FILE_BUILTINS=1
fi
(( $+builtins[zf_chmod] )) && _AI_CANDY_HAS_ZSH_CHMOD_BUILTIN=1

function _ai_candy_chmod() {
  if (( _AI_CANDY_HAS_ZSH_CHMOD_BUILTIN )); then
    builtin zf_chmod "$@"
  else
    command chmod "$@"
  fi
}

typeset -g _AI_CANDY_HAS_ZSH_STAT_BUILTIN=0
if builtin zmodload -F zsh/stat b:zstat 2>/dev/null; then
  _AI_CANDY_HAS_ZSH_STAT_BUILTIN=1
fi

# zsh/datetime supplies the prompt's high-resolution session clock. zsh/system
# and zsh/zselect enable the native timeout and descriptor-lock fast paths.
typeset -g _AI_CANDY_HAS_ZSH_SYSTEM=0
typeset -g _AI_CANDY_HAS_ZSH_ZSELECT=0
typeset -g _AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=0
if builtin zmodload zsh/system 2>/dev/null; then
  _AI_CANDY_HAS_ZSH_SYSTEM=1
fi
if ! builtin zmodload zsh/datetime 2>/dev/null; then
  builtin print -P "%F{red}[ai-candy.zsh-theme]%f Requires the standard zsh/datetime module"
  _ai_candy_restore_source_options
  builtin unfunction _ai_candy_restore_source_options
  return 1
fi
if builtin zmodload zsh/zselect 2>/dev/null; then
  _AI_CANDY_HAS_ZSH_ZSELECT=1
fi
if (( _AI_CANDY_HAS_ZSH_SYSTEM && _AI_CANDY_HAS_ZSH_ZSELECT )); then
  _AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT=1
fi

typeset -g _AI_CANDY_PHYSICAL_PWD=""
function _ai_candy_capture_physical_pwd() {
  emulate -L zsh
  local captured_pwd=""

  if ! captured_pwd="$(builtin pwd -P 2>/dev/null)" || \
     [[ "$captured_pwd" != /* ]]; then
    _AI_CANDY_PHYSICAL_PWD=""
    return 1
  fi
  _AI_CANDY_PHYSICAL_PWD="$captured_pwd"
  return 0
}
_ai_candy_capture_physical_pwd || true

# ============================================================================
# COMMAND AVAILABILITY - Checked once at load time for performance
# ============================================================================
# These flags avoid repeated `command -v` calls throughout the file.
# Each flag is set to 1 if the command is available, 0 otherwise.
#
# Optional tools use lazy detection because shell-managed installations may not
# be in PATH when the theme first loads.

typeset -g _AI_CANDY_HAS_SQLITE3=0
typeset -g _AI_CANDY_HAS_TIMEOUT=0
typeset -g _AI_CANDY_TIMEOUT_CMD=""
typeset -g _AI_CANDY_SETSID_CMD=""
typeset -g _AI_CANDY_HAS_GH=0
typeset -g _AI_CANDY_HAS_SSH=0
typeset -g _AI_CANDY_HAS_CURL=0

# Optional tools are detected on first prompt render.
typeset -g _AI_CANDY_HAS_CLAUDE=0
typeset -g _AI_CANDY_HAS_CODEX=0
typeset -g _AI_CANDY_HAS_GEMINI=0
typeset -g _AI_CANDY_HAS_KIMI=0
typeset -g _AI_CANDY_AI_TOOLS_DETECTED=0  # Triggers one-time optional-tool detection

typeset -g _AI_CANDY_HASH_CMD=""
typeset -g _AI_CANDY_HAS_HASH_CMD=0

function _ai_candy_resolve_external_command() {
  emulate -L zsh
  local command_name="$1"
  local executable=""
  local path_entry candidate
  integer path_is_absolute=1
  REPLY=""

  [[ -n "$command_name" ]] || return 1
  if [[ "$command_name" == */* ]]; then
    [[ "$command_name" == /* ]] || return 1
    executable="$command_name"
  else
    for path_entry in "${path[@]}"; do
      if [[ "$path_entry" != /* ]]; then
        path_is_absolute=0
        break
      fi
    done
    if (( path_is_absolute )); then
      executable="${commands[$command_name]-}"
    else
      for path_entry in "${path[@]}"; do
        [[ "$path_entry" == /* ]] || continue
        if [[ "$path_entry" == "/" ]]; then
          candidate="/${command_name}"
        else
          candidate="${path_entry%/}/${command_name}"
        fi
        if [[ -x "$candidate" && ! -d "$candidate" ]]; then
          executable="$candidate"
          break
        fi
      done
    fi
  fi
  [[ -n "$executable" && -x "$executable" && ! -d "$executable" ]] || return 1
  REPLY="${executable:A}"
}

function _ai_candy_detect_core_commands() {
  _AI_CANDY_HAS_SQLITE3=0
  _AI_CANDY_HAS_TIMEOUT=0
  _AI_CANDY_TIMEOUT_CMD=""
  _AI_CANDY_SETSID_CMD=""
  _AI_CANDY_HAS_GH=0
  _AI_CANDY_HAS_SSH=0
  _AI_CANDY_HAS_CURL=0
  _AI_CANDY_HASH_CMD=""
  _AI_CANDY_HAS_HASH_CMD=0

  _ai_candy_resolve_external_command sqlite3 && _AI_CANDY_HAS_SQLITE3=1
  if (( _AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT )); then
    _AI_CANDY_HAS_TIMEOUT=1
    _AI_CANDY_TIMEOUT_CMD="zsh-native"
  elif _ai_candy_resolve_external_command timeout; then
    _AI_CANDY_HAS_TIMEOUT=1
    _AI_CANDY_TIMEOUT_CMD="$REPLY"
  elif _ai_candy_resolve_external_command gtimeout; then
    _AI_CANDY_HAS_TIMEOUT=1
    _AI_CANDY_TIMEOUT_CMD="$REPLY"
  fi
  _ai_candy_resolve_external_command setsid && _AI_CANDY_SETSID_CMD="$REPLY"
  _ai_candy_resolve_external_command gh && _AI_CANDY_HAS_GH=1
  _ai_candy_resolve_external_command ssh && _AI_CANDY_HAS_SSH=1
  _ai_candy_resolve_external_command curl && _AI_CANDY_HAS_CURL=1

  # Remote URLs are hashed before becoming persistent PR cache keys.
  if _ai_candy_resolve_external_command sha256sum; then
    _AI_CANDY_HASH_CMD="$REPLY"
    _AI_CANDY_HAS_HASH_CMD=1
  elif _ai_candy_resolve_external_command shasum; then
    _AI_CANDY_HASH_CMD="$REPLY"
    _AI_CANDY_HAS_HASH_CMD=1
  elif _ai_candy_resolve_external_command openssl; then
    _AI_CANDY_HASH_CMD="$REPLY"
    _AI_CANDY_HAS_HASH_CMD=1
  fi
}

function _ai_candy_detect_optional_commands() {
  _AI_CANDY_HAS_CLAUDE=0
  _AI_CANDY_HAS_CODEX=0
  _AI_CANDY_HAS_GEMINI=0
  _AI_CANDY_HAS_KIMI=0

  _ai_candy_resolve_external_command claude && _AI_CANDY_HAS_CLAUDE=1
  _ai_candy_resolve_external_command codex && _AI_CANDY_HAS_CODEX=1
  _ai_candy_resolve_external_command gemini && _AI_CANDY_HAS_GEMINI=1
  _ai_candy_resolve_external_command kimi && _AI_CANDY_HAS_KIMI=1
  _AI_CANDY_AI_TOOLS_DETECTED=1
}

_ai_candy_detect_core_commands

function _ai_candy_sleep_ticks() {
  local ticks="$1"
  if (( ${+builtins[zselect]} )); then
    builtin zselect -t "$ticks" 2>/dev/null || true
  else
    local -F seconds=$(( ticks / 100.0 ))
    command sleep "$seconds" 2>/dev/null || true
  fi
  return 0
}

function _ai_candy_terminal_codepoint_is_emoji_joinable() {
  integer codepoint="$1"
  (( (codepoint >= 0x2300 && codepoint <= 0x23ff) ||
      (codepoint >= 0x2600 && codepoint <= 0x27ff) ||
      (codepoint >= 0x1f000 && codepoint <= 0x1faff) ))
}

function _ai_candy_sanitize_terminal_text() {
  emulate -L zsh
  local LC_ALL=C
  local value="$1"
  local byte second third fourth pending_joiner_text=""
  integer index=1 length=${#value} code second_code third_code fourth_code width
  integer codepoint previous_joinable=0 pending_joiner=0
  REPLY=""

  while (( index <= length )); do
    byte="${value[index]}"
    code=$(( #byte ))
    width=0

    if (( code >= 32 && code <= 126 )); then
      if (( pending_joiner )); then
        REPLY+="?"
        pending_joiner=0
        pending_joiner_text=""
      fi
      REPLY+="$byte"
      previous_joinable=0
      (( index++ ))
      continue
    elif (( code < 128 )); then
      if (( pending_joiner )); then
        REPLY+="?"
        pending_joiner=0
        pending_joiner_text=""
      fi
      REPLY+="?"
      previous_joinable=0
      (( index++ ))
      continue
    fi

    if (( code >= 194 && code <= 223 && index + 1 <= length )); then
      second="${value[index+1]}"
      second_code=$(( #second ))
      (( second_code >= 128 && second_code <= 191 )) && width=2
      if (( code == 194 && second_code <= 159 )); then
        width=0
      fi
    elif (( code >= 224 && code <= 239 && index + 2 <= length )); then
      second="${value[index+1]}"
      third="${value[index+2]}"
      second_code=$(( #second ))
      third_code=$(( #third ))
      if (( third_code >= 128 && third_code <= 191 && (
            ( code == 224 && second_code >= 160 && second_code <= 191 ) ||
            ( code >= 225 && code <= 236 && second_code >= 128 && second_code <= 191 ) ||
            ( code == 237 && second_code >= 128 && second_code <= 159 ) ||
            ( code >= 238 && second_code >= 128 && second_code <= 191 ) ) )); then
        width=3
      fi
    elif (( code >= 240 && code <= 244 && index + 3 <= length )); then
      second="${value[index+1]}"
      third="${value[index+2]}"
      fourth="${value[index+3]}"
      second_code=$(( #second ))
      third_code=$(( #third ))
      fourth_code=$(( #fourth ))
      if (( third_code >= 128 && third_code <= 191 &&
            fourth_code >= 128 && fourth_code <= 191 && (
            ( code == 240 && second_code >= 144 && second_code <= 191 ) ||
            ( code >= 241 && code <= 243 && second_code >= 128 && second_code <= 191 ) ||
            ( code == 244 && second_code >= 128 && second_code <= 143 ) ) )); then
        width=4
      fi
    fi

    if (( width > 0 )); then
      case "$width" in
        2) codepoint=$(( (code - 192) * 64 + second_code - 128 )) ;;
        3) codepoint=$(( (code - 224) * 4096 + (second_code - 128) * 64 + third_code - 128 )) ;;
        4) codepoint=$(( (code - 240) * 262144 + (second_code - 128) * 4096 + (third_code - 128) * 64 + fourth_code - 128 )) ;;
      esac
      if (( pending_joiner )); then
        if _ai_candy_terminal_codepoint_is_emoji_joinable "$codepoint"; then
          REPLY+="$pending_joiner_text"
        else
          REPLY+="?"
        fi
        pending_joiner=0
        pending_joiner_text=""
      fi
      if (( codepoint == 8205 )); then
        if (( previous_joinable )); then
          pending_joiner=1
          pending_joiner_text="${value[index,index+width-1]}"
        else
          REPLY+="?"
        fi
        previous_joinable=0
        (( index += width ))
        continue
      fi
      if (( codepoint == 173 || codepoint == 1564 || codepoint == 6158 ||
            (codepoint >= 8203 && codepoint <= 8207 && codepoint != 8205) ||
            (codepoint >= 8232 && codepoint <= 8238) ||
            (codepoint >= 8288 && codepoint <= 8303) ||
            codepoint == 65279 ||
            (codepoint >= 65529 && codepoint <= 65531) ||
            (codepoint >= 917504 && codepoint <= 917631) )); then
        REPLY+="?"
      else
        REPLY+="${value[index,index+width-1]}"
      fi
      if _ai_candy_terminal_codepoint_is_emoji_joinable "$codepoint"; then
        previous_joinable=1
      elif (( codepoint != 65039 )); then
        previous_joinable=0
      fi
      (( index += width ))
    else
      if (( pending_joiner )); then
        REPLY+="?"
        pending_joiner=0
        pending_joiner_text=""
      fi
      REPLY+="?"
      previous_joinable=0
      (( index++ ))
    fi
  done
  (( pending_joiner )) && REPLY+="?"
}

function _ai_candy_prompt_escape_text() {
  _ai_candy_sanitize_terminal_text "$1"
  local value="$REPLY"

  value="${value//\%/%%}"
  [[ -o promptbang ]] && value="${value//\!/!!}"
  REPLY="$value"
}

# Optional tools are detected lazily in _ai_candy_compute_ai_tools_direct().

# ============================================================================
# COLOR CONSTANTS - Centralized color definitions for easy customization
# ============================================================================
# 256-color palette (FG[N] format)
typeset -g _AI_CANDY_CLR_TIME_MORNING=214      # Warm yellow (6am-12pm)
typeset -g _AI_CANDY_CLR_TIME_AFTERNOON=255    # Bright white (12pm-6pm)
typeset -g _AI_CANDY_CLR_TIME_EVENING=208      # Soft orange (6pm-10pm)
typeset -g _AI_CANDY_CLR_TIME_NIGHT=111        # Dim blue (10pm-6am)
typeset -g _AI_CANDY_CLR_TRUNCATED=240         # Gray for truncated path indicator
typeset -g _AI_CANDY_CLR_CLAUDE=173            # Coral
typeset -g _AI_CANDY_CLR_CODEX=250             # Light gray
typeset -g _AI_CANDY_CLR_GEMINI=141            # Purple
typeset -g _AI_CANDY_CLR_KIMI=75               # Sky blue
typeset -g _AI_CANDY_CLR_PR=213                # Pink - GitHub PR
typeset -g _AI_CANDY_CLR_USER_HOST=136         # Brown - user@host

# Standard color names (fg[name] format) - for reference/documentation
# cyan    - SSH indicator, system info
# green   - exit ok, ahead, CI pass, git branch
# red     - exit fail, behind, CI fail, update indicator
# yellow  - stash, jobs, CI pending, container badge host
# magenta - container badge
# white   - path segments, optional-tool brackets
# blue    - prompt arrow

typeset -g _AI_CANDY_SYM_CHECK=$'\xe2\x9c\x93'
typeset -g _AI_CANDY_SYM_CROSS=$'\xe2\x9c\x97'
typeset -g _AI_CANDY_SYM_UP=$'\xe2\x86\x91'
typeset -g _AI_CANDY_SYM_DOWN=$'\xe2\x86\x93'
typeset -g _AI_CANDY_SYM_STASH=$'\xe2\x9a\x91'
typeset -g _AI_CANDY_SYM_WARNING=$'\xe2\x9a\xa0'
typeset -g _AI_CANDY_SYM_JOBS=$'\xe2\x9a\x99'
typeset -g _AI_CANDY_SYM_PENDING=$'\xe2\x8f\xb3'
typeset -g _AI_CANDY_SYM_HOST=$'\xf0\x9f\x92\xbb'
typeset -g _AI_CANDY_SYM_BRANCH=$'\xf0\x9f\x94\x80'
typeset -g _AI_CANDY_SYM_CHERRY=$'\xf0\x9f\x8d\x92'
typeset -g _AI_CANDY_SYM_REWIND=$'\xe2\x8f\xaa'
typeset -g _AI_CANDY_SYM_SEARCH=$'\xf0\x9f\x94\x8d'
typeset -g _AI_CANDY_SYM_PLUG=$'\xf0\x9f\x94\x8c'
typeset -g _AI_CANDY_BOX_TL=$'\xe2\x95\x94'
typeset -g _AI_CANDY_BOX_TR=$'\xe2\x95\x97'
typeset -g _AI_CANDY_BOX_BL=$'\xe2\x95\x9a'
typeset -g _AI_CANDY_BOX_BR=$'\xe2\x95\x9d'
typeset -g _AI_CANDY_BOX_ML=$'\xe2\x95\xa0'
typeset -g _AI_CANDY_BOX_MR=$'\xe2\x95\xa3'
typeset -g _AI_CANDY_BOX_H=$'\xe2\x95\x90'
typeset -g _AI_CANDY_BOX_V=$'\xe2\x95\x91'

# Background colors for git path segments (256-color palette)
# Level 0 (outermost/top repo): light cyan
# Level 1 (first submodule): light yellow
# Level 2 (second submodule): light green
# Level 3+ (deeper): light magenta
typeset -ga _AI_CANDY_PATH_BG_COLORS=(159 229 157 225)

# Internal separator for git hierarchy cache (avoid common path characters).
# ASCII Unit Separator bytes are neutralized by the hierarchy encoder.
# IMPORTANT: When splitting strings with this separator in zsh, use:
#   ${(@ps.$sep.)string}   -- CORRECT (p flag + s.$var. syntax)
#   ${(@s:$sep:)string}    -- WRONG (s:X: requires literal X, not variable)
typeset -g _AI_CANDY_GIT_HIERARCHY_SEP=$'\x1f'

# GitHub username badge background color (white background for normal, red for mismatch)
typeset -g _AI_CANDY_CLR_GH_USER_BG=255        # White background
typeset -g _AI_CANDY_CLR_GH_USER_FG=16         # Black foreground
typeset -g _AI_CANDY_CLR_GH_USER_MISMATCH=196  # Bright red for username mismatch

# ============================================================================
# TIMING CONSTANTS - Centralized timeout and cache TTL settings
# ============================================================================
# All timing values in seconds for easy adjustment

# Network timeout (prevents hanging on slow/unreachable services)
typeset -g _AI_CANDY_NETWORK_TIMEOUT=3         # 3 seconds

# Local probe timeout (prevents optional local tools from blocking prompt startup)
typeset -g _AI_CANDY_LOCAL_PROMPT_TIMEOUT=0.25 # 250 milliseconds

# Background and user-requested probes do not block prompt rendering.
typeset -g _AI_CANDY_BACKGROUND_LOCAL_PROBE_TIMEOUT=1 # 1 second

# Process count timeout (tool instance counts are optional prompt decoration)
typeset -g _AI_CANDY_PROCESS_COUNT_TIMEOUT=0.05 # 50 milliseconds

# High frequency cache (fast-changing data, checked frequently)
typeset -g _AI_CANDY_CACHE_TTL_HIGH=30         # 30 seconds - PR status, CI checks

# Medium frequency cache (moderately changing data)
typeset -g _AI_CANDY_CACHE_TTL_MEDIUM=300      # 5 minutes - git status, GitHub username

# Low frequency cache (rarely changing data)
typeset -g _AI_CANDY_CACHE_TTL_LOW=3600        # 1 hour - system info, tool versions, auth status

# ============================================================================
# PATH & LAYOUT CONSTANTS - Centralized settings for path display and layout
# ============================================================================
# Maximum depth for git hierarchy traversal (prevents infinite loops)
typeset -g _AI_CANDY_GIT_HIERARCHY_MAX_DEPTH=20

# Bump when git hierarchy serialization changes in a way that makes old cache
# entries visually incorrect.
typeset -g _AI_CANDY_GIT_HIERARCHY_CACHE_VERSION=2

# Target width for path truncation
typeset -g _AI_CANDY_PATH_TARGET_WIDTH_DEFAULT=50  # Default target width
typeset -g _AI_CANDY_PATH_TARGET_WIDTH_SHORT=40    # Target width in short mode

# Layout margin - minimum free space to leave before switching to shorter format
# If remaining terminal width is less than this, trigger RPROMPT or shorter mode
typeset -g _AI_CANDY_LAYOUT_MARGIN=8

# ============================================================================
# TIMEOUT WRAPPER - Universal timeout command abstraction
# ============================================================================
# Provides consistent timeout behavior across Linux and macOS. The native Zsh
# implementation is fast and terminates descendants; external tools are a
# fallback for builds missing the standard modules.
#
# Usage: _ai_candy_run_with_timeout <timeout_seconds> <command> [args...]
# Returns: bounded command output unless the deadline expires
# Exit code: mirrors the command, with 124 reserved for an expired deadline
# Note: _AI_CANDY_HAS_TIMEOUT and _AI_CANDY_TIMEOUT_CMD are set in COMMAND AVAILABILITY section

typeset -g _AI_CANDY_TIMEOUT_OUTPUT_MAX_BYTES=$((256 * 1024))
typeset -g _AI_CANDY_TIMEOUT_STALE_FILES_SCANNED=0
typeset -g _AI_CANDY_TIMEOUT_TEMP_DIR=""
function _ai_candy_timeout_output_limit_bytes() {
  integer max_output_bytes=${_AI_CANDY_TIMEOUT_OUTPUT_MAX_BYTES:-262144}
  if (( max_output_bytes < 512 || max_output_bytes > 1048576 )); then
    max_output_bytes=262144
  fi
  REPLY="$max_output_bytes"
}

function _ai_candy_remove_timeout_files() {
  (( $# > 0 )) || return 0
  if (( _AI_CANDY_HAS_ZSH_FILE_BUILTINS )); then
    builtin zf_rm -f "$@" 2>/dev/null
  else
    command /bin/rm -f "$@" 2>/dev/null
  fi
}

function _ai_candy_cleanup_stale_timeout_files() {
  emulate -L zsh
  local temp_root="$1"
  local -a artifacts
  local artifact basename owner_pid

  # Y16 stops filename generation after one bounded batch. This avoids a full
  # directory scan when a previous shell left many timeout artifacts behind.
  artifacts=("${temp_root%/}"/ai-candy-timeout.<->.*(NY16))
  for artifact in "${artifacts[@]}"; do
    basename="${artifact:t}"
    owner_pid="${${basename#ai-candy-timeout.}%%.*}"
    [[ "$owner_pid" == <-> ]] || continue
    builtin kill -0 "$owner_pid" 2>/dev/null && continue
    _ai_candy_remove_timeout_files "$artifact"
  done
}

function _ai_candy_timeout_temp_directory() {
  emulate -L zsh
  local temp_base="${${TMPDIR:-/tmp}:A}"
  local temp_dir="$_AI_CANDY_TIMEOUT_TEMP_DIR"
  REPLY=""

  if [[ -n "$temp_dir" && -d "$temp_dir" && ! -L "$temp_dir" && \
        -O "$temp_dir" && -w "$temp_dir" ]]; then
    REPLY="$temp_dir"
    return 0
  fi
  _AI_CANDY_TIMEOUT_TEMP_DIR=""

  if [[ -d "$temp_base" && -w "$temp_base" && ! -L "$temp_base" ]] && \
     [[ -O "$temp_base" || -k "$temp_base" ]]; then
    temp_dir="${temp_base%/}/ai-candy-${EUID}"
    if [[ ! -e "$temp_dir" && ! -L "$temp_dir" ]]; then
      if (( _AI_CANDY_HAS_ZSH_FILE_BUILTINS )); then
        ( umask 077 && builtin zf_mkdir -m 700 "$temp_dir" ) 2>/dev/null || true
      else
        ( umask 077 && command mkdir -m 700 "$temp_dir" ) 2>/dev/null || true
      fi
    fi
    if [[ -d "$temp_dir" && ! -L "$temp_dir" && -O "$temp_dir" ]]; then
      _ai_candy_chmod 700 "$temp_dir" 2>/dev/null || true
      if [[ -w "$temp_dir" ]]; then
        _AI_CANDY_TIMEOUT_TEMP_DIR="$temp_dir"
        REPLY="$temp_dir"
        return 0
      fi
    fi
  fi

  if (( ${_AI_CANDY_CACHE_READY:-0} )) && [[ -d "$_AI_CANDY_CACHE_DIR" && \
       -w "$_AI_CANDY_CACHE_DIR" && ! -L "$_AI_CANDY_CACHE_DIR" ]]; then
    _AI_CANDY_TIMEOUT_TEMP_DIR="$_AI_CANDY_CACHE_DIR"
    REPLY="$_AI_CANDY_CACHE_DIR"
    return 0
  fi
  return 1
}

function _ai_candy_create_timeout_output_file() {
  emulate -L zsh
  local temp_root=""
  local output_file=""
  local process_pid="${sysparams[pid]-}"
  integer output_fd attempt
  REPLY=""
  [[ "$process_pid" == <-> ]] || process_pid="$$"

  _ai_candy_timeout_temp_directory || return 1
  temp_root="$REPLY"
  if (( ! _AI_CANDY_TIMEOUT_STALE_FILES_SCANNED )); then
    _ai_candy_cleanup_stale_timeout_files "$temp_root"
    _AI_CANDY_TIMEOUT_STALE_FILES_SCANNED=1
  fi
  for (( attempt=1; attempt<=8; attempt++ )); do
    output_file="${temp_root%/}/ai-candy-timeout.${process_pid}.${RANDOM}"
    if (( _AI_CANDY_HAS_ZSH_SYSTEM && ${+builtins[sysopen]} )); then
      if ! builtin sysopen -w -o create,excl -m 600 -u output_fd \
           "$output_file" 2>/dev/null; then
        continue
      fi
      exec {output_fd}>&-
    elif ! ( umask 077 && setopt noclobber && : > "$output_file" ) 2>/dev/null; then
      continue
    fi
    if [[ -f "$output_file" && ! -L "$output_file" ]]; then
      REPLY="$output_file"
      return 0
    fi
    _ai_candy_remove_timeout_files "$output_file"
  done
  return 1
}

function _ai_candy_print_timeout_output_file() {
  local output_file="$1"
  local chunk=""
  integer input_fd read_status=0

  if (( ! _AI_CANDY_HAS_ZSH_SYSTEM || ! ${+builtins[sysopen]} )); then
    [[ -f "$output_file" && ! -L "$output_file" ]] || return 1
    chunk="$(<"$output_file")"
    builtin print -rn -- "$chunk"
    return 0
  fi

  builtin sysopen -r -u input_fd "$output_file" 2>/dev/null || return 1
  while true; do
    chunk=""
    builtin sysread -i "$input_fd" -s 8192 chunk 2>/dev/null
    read_status=$?
    [[ -n "$chunk" ]] && builtin print -rn -- "$chunk"
    (( read_status == 0 )) || break
  done
  exec {input_fd}<&-
  return 0
}

function _ai_candy_capture_bounded_timeout_output() {
  emulate -L zsh
  local LC_ALL=C
  integer max_output_bytes="$1"
  integer written_bytes=0 overflowed=0 write_failed=0 read_status=0
  integer chunk_bytes remaining_bytes
  local chunk=""

  while true; do
    chunk=""
    if (( _AI_CANDY_HAS_ZSH_SYSTEM && ${+builtins[sysread]} )); then
      builtin sysread -i 0 -s 8192 chunk 2>/dev/null
      read_status=$?
    else
      IFS= builtin read -u 0 -r -k 8192 chunk
      read_status=$?
    fi

    chunk_bytes=${#chunk}
    if (( chunk_bytes > 0 )); then
      remaining_bytes=$(( max_output_bytes - written_bytes ))
      if (( remaining_bytes > 0 )); then
        if (( chunk_bytes > remaining_bytes )); then
          builtin print -rn -- "${chunk[1,remaining_bytes]}" 2>/dev/null || \
            write_failed=1
          written_bytes=$max_output_bytes
          overflowed=1
        else
          builtin print -rn -- "$chunk" 2>/dev/null || write_failed=1
          (( written_bytes += chunk_bytes ))
        fi
      else
        overflowed=1
      fi
    fi
    (( read_status == 0 )) || break
  done

  (( overflowed || write_failed )) && return 125
  return 0
}

function _ai_candy_run_bounded_output_command() {
  emulate -L zsh
  local output_file="$1"
  integer max_output_bytes="$2"
  integer capture_stderr=${_AI_CANDY_TIMEOUT_CAPTURE_STDERR:-0}
  shift 2
  local -a pipeline_status
  integer command_status capture_status

  if (( capture_stderr )); then
    "$@" 2>&1 | \
      _ai_candy_capture_bounded_timeout_output "$max_output_bytes" >| "$output_file"
    pipeline_status=("${pipestatus[@]}")
  else
    "$@" | _ai_candy_capture_bounded_timeout_output "$max_output_bytes" >| "$output_file"
    pipeline_status=("${pipestatus[@]}")
  fi
  command_status=${pipeline_status[1]:-125}
  capture_status=${pipeline_status[2]:-125}
  if (( command_status == 0 && capture_status != 0 )); then
    command_status=$capture_status
  fi
  return "$command_status"
}

function _ai_candy_redispatch_timeout_signal() {
  local signal_name="$1"
  local signal_number="$2"
  local trap_name="$3"
  local trap_was_set="$4"
  local trap_body="$5"
  local default_status="$6"

  if (( trap_was_set )); then
    functions[$trap_name]="$trap_body"
    "$trap_name" "$signal_number"
    return $?
  fi
  if [[ "$signal_name" == "INT" && -o interactive ]]; then
    return "$default_status"
  fi

  builtin unfunction "$trap_name" 2>/dev/null || true
  local process_pid="${sysparams[pid]-}"
  if [[ "$process_pid" == <-> ]]; then
    builtin kill "-${signal_name}" "$process_pid" 2>/dev/null || \
      builtin exit "$default_status"
    return "$default_status"
  fi
  builtin exit "$default_status"
}

function _ai_candy_run_native_timeout() {
  emulate -L zsh
  setopt localtraps
  unsetopt monitor

  integer entry_hup_trap_set=${+functions[TRAPHUP]}
  integer entry_int_trap_set=${+functions[TRAPINT]}
  integer entry_term_trap_set=${+functions[TRAPTERM]}
  local entry_hup_trap="${functions[TRAPHUP]-}"
  local entry_int_trap="${functions[TRAPINT]-}"
  local entry_term_trap="${functions[TRAPTERM]-}"

  local -F timeout_sec="$1"
  shift
  (( timeout_sec > 0 )) || return 124
  integer isolate_target=0
  [[ "${1-}" == command && "${2-}" == /* ]] && isolate_target=1

  _ai_candy_create_timeout_output_file || return 124
  local output_file="$REPLY"
  local completion_file=""
  local group_file=""
  if (( isolate_target )); then
    if ! _ai_candy_create_timeout_output_file; then
      _ai_candy_remove_timeout_files "$output_file"
      return 124
    fi
    completion_file="$REPLY"
    if ! _ai_candy_create_timeout_output_file; then
      _ai_candy_remove_timeout_files "$output_file" "$completion_file"
      return 124
    fi
    group_file="$REPLY"
  fi
  local timeout_marker="${output_file}.expired"
  local -a timeout_files=("$output_file" "$timeout_marker")
  (( isolate_target )) && timeout_files+=("$completion_file" "$group_file")
  integer timeout_marker_fd=-1
  integer timeout_watchdog_fd=-1
  integer timeout_parent_fd=-1
  if ! builtin sysopen -r -w -o create,excl,cloexec -m 600 \
       -u timeout_marker_fd "$timeout_marker" 2>/dev/null; then
    _ai_candy_remove_timeout_files "${timeout_files[@]}"
    return 124
  fi
  if ! builtin sysopen -r -o cloexec -u timeout_watchdog_fd \
       "$timeout_marker" 2>/dev/null; then
    exec {timeout_marker_fd}>&-
    _ai_candy_remove_timeout_files "${timeout_files[@]}"
    return 124
  fi
  if ! builtin sysopen -r -o cloexec -u timeout_parent_fd \
       "$timeout_marker" 2>/dev/null; then
    exec {timeout_watchdog_fd}<&-
    exec {timeout_marker_fd}>&-
    _ai_candy_remove_timeout_files "${timeout_files[@]}"
    return 124
  fi

  local child_pid=""
  local watchdog_pid=""
  local timeout_state=""
  local command_status=0
  local wrapper_status=0
  local interrupted_signal=""
  _ai_candy_timeout_output_limit_bytes
  integer max_output_bytes="$REPLY"
  integer timeout_ticks=$(( timeout_sec * 100 + 0.999 ))
  integer deadline_expired=0
  integer interrupted_status=0
  (( timeout_ticks < 1 )) && timeout_ticks=1

  builtin trap 'interrupted_signal=HUP; interrupted_status=129; if [[ -n "$child_pid" ]]; then _ai_candy_kill_timeout_process_group "$group_file" "$child_pid"; _ai_candy_kill_process_tree "$child_pid"; fi' HUP
  builtin trap 'interrupted_signal=INT; interrupted_status=130; if [[ -n "$child_pid" ]]; then _ai_candy_kill_timeout_process_group "$group_file" "$child_pid"; _ai_candy_kill_process_tree "$child_pid"; fi' INT
  builtin trap 'interrupted_signal=TERM; interrupted_status=143; if [[ -n "$child_pid" ]]; then _ai_candy_kill_timeout_process_group "$group_file" "$child_pid"; _ai_candy_kill_process_tree "$child_pid"; fi' TERM

  {
    {
      if (( isolate_target )); then
        _ai_candy_run_bounded_output_command \
          "$output_file" "$max_output_bytes" \
          _ai_candy_launch_timeout_supervisor zsh-native "" \
          "$completion_file" "$group_file" "$_AI_CANDY_SETSID_CMD" \
          "${@:2}"
      else
        _ai_candy_run_bounded_output_command \
          "$output_file" "$max_output_bytes" "$@"
      fi
      local child_status=$?
      builtin syswrite -o "$timeout_marker_fd" completed 2>/dev/null
      return "$child_status"
    } &
    child_pid=$!

    (
      local completion_state=""
      _ai_candy_sleep_ticks "$timeout_ticks"
      builtin sysread -i "$timeout_watchdog_fd" -s 16 \
        completion_state 2>/dev/null || true
      if [[ "$completion_state" != *completed* ]]; then
        builtin syswrite -o "$timeout_marker_fd" expired 2>/dev/null
        _ai_candy_kill_timeout_process_group "$group_file" "$child_pid"
        _ai_candy_kill_process_tree "$child_pid"
      fi
    ) &
    watchdog_pid=$!

    builtin wait "$child_pid" 2>/dev/null
    command_status=$?
    wrapper_status=$command_status

    builtin sysread -i "$timeout_parent_fd" -s 16 \
      timeout_state 2>/dev/null || true
    if [[ "$timeout_state" == *expired* ]]; then
      builtin wait "$watchdog_pid" 2>/dev/null || true
      watchdog_pid=""
      deadline_expired=1
      command_status=124
    else
      builtin kill -TERM "$watchdog_pid" 2>/dev/null
      builtin wait "$watchdog_pid" 2>/dev/null || true
      watchdog_pid=""
    fi
    child_pid=""

    if (( ! deadline_expired && isolate_target )); then
      if _ai_candy_read_timeout_completion_status "$completion_file"; then
        command_status="$REPLY"
        if (( command_status == 0 && wrapper_status == 125 )); then
          command_status=125
        fi
      else
        command_status=$wrapper_status
        (( command_status == 0 )) && command_status=125
      fi
    fi
    (( interrupted_status )) && command_status="$interrupted_status"
    if (( ! deadline_expired && command_status != 124 )); then
      _ai_candy_print_timeout_output_file "$output_file"
    fi
  } always {
    if [[ -n "$watchdog_pid" ]]; then
      builtin kill -TERM "$watchdog_pid" 2>/dev/null
      builtin wait "$watchdog_pid" 2>/dev/null || true
    fi
    if [[ -n "$child_pid" ]] && builtin kill -0 "$child_pid" 2>/dev/null; then
      _ai_candy_kill_timeout_process_group "$group_file" "$child_pid"
      _ai_candy_kill_process_tree "$child_pid"
      builtin wait "$child_pid" 2>/dev/null || true
    fi
    if (( timeout_parent_fd >= 0 )); then
      exec {timeout_parent_fd}<&-
      timeout_parent_fd=-1
    fi
    if (( timeout_watchdog_fd >= 0 )); then
      exec {timeout_watchdog_fd}<&-
      timeout_watchdog_fd=-1
    fi
    if (( timeout_marker_fd >= 0 )); then
      exec {timeout_marker_fd}>&-
      timeout_marker_fd=-1
    fi
    _ai_candy_remove_timeout_files "${timeout_files[@]}"
  }

  case "$interrupted_signal" in
    HUP)
      _ai_candy_redispatch_timeout_signal HUP 1 TRAPHUP \
        "$entry_hup_trap_set" "$entry_hup_trap" 129
      ;;
    INT)
      _ai_candy_redispatch_timeout_signal INT 2 TRAPINT \
        "$entry_int_trap_set" "$entry_int_trap" 130
      ;;
    TERM)
      _ai_candy_redispatch_timeout_signal TERM 15 TRAPTERM \
        "$entry_term_trap_set" "$entry_term_trap" 143
      ;;
  esac
  return "$command_status"
}

function _ai_candy_run_external_timeout() {
  emulate -L zsh
  setopt localtraps
  unsetopt monitor
  integer entry_hup_trap_set=${+functions[TRAPHUP]}
  integer entry_int_trap_set=${+functions[TRAPINT]}
  integer entry_term_trap_set=${+functions[TRAPTERM]}
  local entry_hup_trap="${functions[TRAPHUP]-}"
  local entry_int_trap="${functions[TRAPINT]-}"
  local entry_term_trap="${functions[TRAPTERM]-}"
  local timeout_command="$1"
  local timeout_sec="$2"
  shift 2
  local output_file=""
  local completion_file=""
  local group_file=""
  local completion_status=""
  local runner_pid=""
  local interrupted_signal=""
  integer command_status=124
  integer wrapper_status=124 completion_valid=0 deadline_expired=0
  integer interrupted_status=0
  _ai_candy_timeout_output_limit_bytes
  integer max_output_bytes="$REPLY"
  _ai_candy_create_timeout_output_file || return 124
  output_file="$REPLY"
  if ! _ai_candy_create_timeout_output_file; then
    _ai_candy_remove_timeout_files "$output_file"
    return 124
  fi
  completion_file="$REPLY"
  if ! _ai_candy_create_timeout_output_file; then
    _ai_candy_remove_timeout_files "$output_file" "$completion_file"
    return 124
  fi
  group_file="$REPLY"
  builtin trap 'interrupted_signal=HUP; interrupted_status=129; if [[ -n "$runner_pid" ]]; then _ai_candy_kill_timeout_process_group "$group_file" "$runner_pid"; _ai_candy_kill_process_tree "$runner_pid"; fi' HUP
  builtin trap 'interrupted_signal=INT; interrupted_status=130; if [[ -n "$runner_pid" ]]; then _ai_candy_kill_timeout_process_group "$group_file" "$runner_pid"; _ai_candy_kill_process_tree "$runner_pid"; fi' INT
  builtin trap 'interrupted_signal=TERM; interrupted_status=143; if [[ -n "$runner_pid" ]]; then _ai_candy_kill_timeout_process_group "$group_file" "$runner_pid"; _ai_candy_kill_process_tree "$runner_pid"; fi' TERM

  {
    {
      _ai_candy_run_bounded_output_command \
        "$output_file" "$max_output_bytes" \
        _ai_candy_launch_timeout_supervisor \
        "$timeout_command" "$timeout_sec" \
        "$completion_file" "$group_file" "$_AI_CANDY_SETSID_CMD" "$@"
      return $?
    } &
    runner_pid=$!
    builtin wait "$runner_pid" 2>/dev/null
    wrapper_status=$?
    runner_pid=""
    if _ai_candy_read_timeout_completion_status "$completion_file"; then
      completion_status="$REPLY"
      completion_valid=1
    fi
    if (( wrapper_status == 124 || wrapper_status == 137 )); then
      command_status=124
      deadline_expired=1
    elif (( completion_valid )); then
      command_status="$completion_status"
      if (( command_status == 0 && wrapper_status == 125 )); then
        command_status=125
      fi
    else
      command_status="$wrapper_status"
      (( command_status == 0 )) && command_status=125
    fi

    if (( interrupted_status )); then
      command_status=$interrupted_status
      deadline_expired=1
    fi
    if (( ! deadline_expired && command_status != 124 )); then
      _ai_candy_print_timeout_output_file "$output_file"
    fi
  } always {
    if [[ -n "$runner_pid" ]] && builtin kill -0 "$runner_pid" 2>/dev/null; then
      _ai_candy_kill_timeout_process_group "$group_file" "$runner_pid"
      _ai_candy_kill_process_tree "$runner_pid"
      builtin wait "$runner_pid" 2>/dev/null || true
    fi
    _ai_candy_remove_timeout_files \
      "$output_file" "$completion_file" "$group_file"
  }
  case "$interrupted_signal" in
    HUP)
      _ai_candy_redispatch_timeout_signal HUP 1 TRAPHUP \
        "$entry_hup_trap_set" "$entry_hup_trap" 129
      ;;
    INT)
      _ai_candy_redispatch_timeout_signal INT 2 TRAPINT \
        "$entry_int_trap_set" "$entry_int_trap" 130
      ;;
    TERM)
      _ai_candy_redispatch_timeout_signal TERM 15 TRAPTERM \
        "$entry_term_trap_set" "$entry_term_trap" 143
      ;;
  esac
  return "$command_status"
}

typeset -ga _AI_CANDY_TIMEOUT_PROCESS_TREE
typeset -gA _AI_CANDY_PROCESS_CHILDREN_BY_PARENT
typeset -gA _AI_CANDY_PROCESS_STATE_BY_PID

function _ai_candy_read_process_table() {
  local IFS=$' \t\n'
  REPLY=""
  if [[ -d /proc ]]; then
    setopt localoptions null_glob
    local proc_stat stat_contents stat_tail pid parent_pid process_state
    local -a fields
    for proc_stat in /proc/<->/stat(N); do
      stat_contents=$(<"$proc_stat") 2>/dev/null || continue
      stat_tail="${stat_contents##*) }"
      fields=(${=stat_tail})
      (( ${#fields} >= 2 )) || continue
      pid="${proc_stat:h:t}"
      process_state="${fields[1]}"
      parent_pid="${fields[2]}"
      [[ "$pid" == <-> && "$parent_pid" == <-> ]] || continue
      REPLY+="${pid} ${parent_pid} ${process_state}"$'\n'
    done
    return 0
  fi

  local ps_command=""
  [[ -x /bin/ps ]] && ps_command=/bin/ps
  [[ -n "$ps_command" || ! -x /usr/bin/ps ]] || ps_command=/usr/bin/ps
  if [[ -n "$ps_command" ]]; then
    REPLY=$("$ps_command" -ax -o pid= -o ppid= -o stat= 2>/dev/null) && \
      return 0
    REPLY=""
  fi
  return 1
}

function _ai_candy_index_process_table() {
  local IFS=$' \t\n'
  local process_table="$1"
  local line pid parent_pid process_state
  local -a fields

  _AI_CANDY_PROCESS_CHILDREN_BY_PARENT=()
  _AI_CANDY_PROCESS_STATE_BY_PID=()
  for line in "${(@f)process_table}"; do
    fields=(${=line})
    (( ${#fields} >= 3 )) || continue
    pid="${fields[1]}"
    parent_pid="${fields[2]}"
    process_state="${fields[3]}"
    [[ "$pid" == <-> && "$parent_pid" == <-> && \
       -n "$process_state" ]] || continue
    _AI_CANDY_PROCESS_CHILDREN_BY_PARENT[$parent_pid]+=" ${pid}"
    _AI_CANDY_PROCESS_STATE_BY_PID[$pid]="$process_state"
  done
}

function _ai_candy_collect_process_tree_from_index() {
  local IFS=$' \t\n'
  local root_pid="$1"
  local parent_pid pid children
  integer index=1

  _AI_CANDY_TIMEOUT_PROCESS_TREE=("$root_pid")
  while (( index <= ${#_AI_CANDY_TIMEOUT_PROCESS_TREE} )); do
    parent_pid="${_AI_CANDY_TIMEOUT_PROCESS_TREE[index]}"
    children="${_AI_CANDY_PROCESS_CHILDREN_BY_PARENT[$parent_pid]-}"
    for pid in ${=children}; do
      (( ${_AI_CANDY_TIMEOUT_PROCESS_TREE[(Ie)$pid]} )) || \
        _AI_CANDY_TIMEOUT_PROCESS_TREE+=("$pid")
    done
    (( index++ ))
  done
}

function _ai_candy_collect_process_tree() {
  local root_pid="$1"
  local process_table="${2-}"

  _AI_CANDY_TIMEOUT_PROCESS_TREE=("$root_pid")
  if (( $# < 2 )); then
    _ai_candy_read_process_table || return 0
    process_table="$REPLY"
  fi
  _ai_candy_index_process_table "$process_table"
  _ai_candy_collect_process_tree_from_index "$root_pid"
}

function _ai_candy_process_pid_is_active() {
  local process_pid="$1"
  local process_state=""

  [[ "$process_pid" == <-> ]] || return 1
  if [[ -d /proc ]]; then
    [[ -r "/proc/${process_pid}/stat" ]] || return 1
    local stat_contents=""
    stat_contents=$(<"/proc/${process_pid}/stat") 2>/dev/null || return 1
    local stat_tail="${stat_contents##*) }"
    process_state="${stat_tail[1]}"
  else
    local ps_command=""
    [[ -x /bin/ps ]] && ps_command=/bin/ps
    [[ -n "$ps_command" || ! -x /usr/bin/ps ]] || ps_command=/usr/bin/ps
    [[ -n "$ps_command" ]] || return 1
    process_state=$("$ps_command" -o stat= -p "$process_pid" 2>/dev/null) || \
      return 1
    process_state="${process_state//[[:space:]]/}"
  fi
  [[ -n "$process_state" && "${process_state[1]}" != "Z" ]]
}

function _ai_candy_kill_process_tree() {
  local root_pid="$1"
  local pid
  integer attempt index previous_count=-1

  [[ "$root_pid" == <-> ]] || return 0
  builtin kill -STOP "$root_pid" 2>/dev/null
  for attempt in {1..4}; do
    _ai_candy_collect_process_tree "$root_pid"
    for pid in "${_AI_CANDY_TIMEOUT_PROCESS_TREE[@]}"; do
      builtin kill -STOP "$pid" 2>/dev/null
    done
    (( ${#_AI_CANDY_TIMEOUT_PROCESS_TREE} == previous_count )) && break
    previous_count=${#_AI_CANDY_TIMEOUT_PROCESS_TREE}
  done
  for (( index=${#_AI_CANDY_TIMEOUT_PROCESS_TREE}; index>=2; index-- )); do
    pid="${_AI_CANDY_TIMEOUT_PROCESS_TREE[index]}"
    builtin kill -KILL "$pid" 2>/dev/null
  done
  builtin kill -KILL "$root_pid" 2>/dev/null
}

typeset -ga _AI_CANDY_BACKGROUND_PIDS
typeset -gA _AI_CANDY_BACKGROUND_IDENTITIES
typeset -g _AI_CANDY_BACKGROUND_JOB_LIMIT=16

function _ai_candy_background_pid_identity() {
  local IFS=$' \t\n'
  local background_pid="$1"
  local identity=""
  REPLY=""

  [[ "$background_pid" == <-> ]] || return 1
  if [[ -d /proc ]]; then
    [[ -r "/proc/${background_pid}/stat" ]] || return 1
    local stat_contents=""
    stat_contents=$(<"/proc/${background_pid}/stat") 2>/dev/null || return 1
    local stat_tail="${stat_contents##*) }"
    local -a stat_fields
    stat_fields=(${=stat_tail})
    (( ${#stat_fields} >= 20 )) || return 1
    identity="proc:${stat_fields[20]}"
  else
    local ps_command="/bin/ps"
    [[ -x "$ps_command" ]] || ps_command="${commands[ps]:-}"
    [[ -n "$ps_command" ]] || return 1
    identity=$("$ps_command" -o lstart= -p "$background_pid" 2>/dev/null) || \
      return 1
    identity="${identity//[[:space:]]/}"
    [[ -n "$identity" ]] || return 1
    identity="ps:${identity}"
  fi
  REPLY="$identity"
}

function _ai_candy_background_pid_parent_is_shell() {
  local IFS=$' \t\n'
  local background_pid="$1"
  local shell_pid="$$"
  local parent_pid=""

  [[ "$background_pid" == <-> ]] || return 1
  if [[ -d /proc ]]; then
    [[ -r "/proc/${background_pid}/stat" ]] || return 1
    local stat_contents=""
    stat_contents=$(<"/proc/${background_pid}/stat") 2>/dev/null || return 1
    local stat_tail="${stat_contents##*) }"
    local -a stat_fields
    stat_fields=(${=stat_tail})
    (( ${#stat_fields} >= 2 )) || return 1
    parent_pid="${stat_fields[2]}"
  else
    local ps_command="/bin/ps"
    [[ -x "$ps_command" ]] || ps_command="${commands[ps]:-}"
    [[ -n "$ps_command" ]] || return 1
    parent_pid=$("$ps_command" -o ppid= -p "$background_pid" 2>/dev/null)
    parent_pid="${parent_pid//[[:space:]]/}"
  fi
  [[ "$parent_pid" == "$shell_pid" ]]
}

function _ai_candy_register_background_pid() {
  local background_pid="${1:-}"
  local identity=""
  [[ "$background_pid" == <-> ]] || return 1
  _ai_candy_background_pid_parent_is_shell "$background_pid" || return 1
  _ai_candy_background_pid_identity "$background_pid" || return 1
  identity="$REPLY"
  if (( ${_AI_CANDY_BACKGROUND_PIDS[(Ie)$background_pid]} )); then
    _AI_CANDY_BACKGROUND_IDENTITIES[$background_pid]="$identity"
    return 0
  fi
  (( ${#_AI_CANDY_BACKGROUND_PIDS} >= _AI_CANDY_BACKGROUND_JOB_LIMIT )) && \
    _ai_candy_prune_registered_background_pids
  (( ${#_AI_CANDY_BACKGROUND_PIDS} < _AI_CANDY_BACKGROUND_JOB_LIMIT )) || \
    return 1
  _AI_CANDY_BACKGROUND_PIDS+=("$background_pid")
  _AI_CANDY_BACKGROUND_IDENTITIES[$background_pid]="$identity"
}

function _ai_candy_start_registered_background_worker() {
  emulate -L zsh
  setopt localoptions noerrexit noerrreturn
  (( $# )) || return 1
  (( ${_AI_CANDY_CACHE_READY:-0} )) || return 1
  if (( ${#_AI_CANDY_BACKGROUND_PIDS} >= _AI_CANDY_BACKGROUND_JOB_LIMIT )); then
    _ai_candy_prune_registered_background_pids
    (( ${#_AI_CANDY_BACKGROUND_PIDS} < _AI_CANDY_BACKGROUND_JOB_LIMIT )) || \
      return 1
  fi

  # Keep the worker waitable without publishing an interactive job notification.
  unsetopt monitor
  (
    _AI_CANDY_BACKGROUND_PIDS=()
    _AI_CANDY_BACKGROUND_IDENTITIES=()
    if (( ${+functions[_ai_candy_cache_drop_inherited_locks]} )); then
      _ai_candy_cache_drop_inherited_locks
    fi
    "$@"
  ) </dev/null &>/dev/null &
  local worker_pid=$!

  if _ai_candy_register_background_pid "$worker_pid"; then
    builtin disown %+ 2>/dev/null || true
    return 0
  fi
  _ai_candy_kill_process_tree "$worker_pid"
  builtin wait "$worker_pid" 2>/dev/null || true
  return 1
}

function _ai_candy_background_pid_is_owned() {
  local background_pid="$1"
  local expected_identity="${_AI_CANDY_BACKGROUND_IDENTITIES[$background_pid]-}"

  [[ "$background_pid" == <-> ]] || return 1
  if [[ -n "$expected_identity" ]]; then
    _ai_candy_background_pid_identity "$background_pid" || return 1
    [[ "$REPLY" == "$expected_identity" ]]
    return $?
  fi
  _ai_candy_background_pid_parent_is_shell "$background_pid"
}

function _ai_candy_prune_registered_background_pids() {
  local background_pid
  local -a owned_pids
  local -A owned_identities

  for background_pid in "${_AI_CANDY_BACKGROUND_PIDS[@]}"; do
    if _ai_candy_background_pid_is_owned "$background_pid"; then
      owned_pids+=("$background_pid")
      owned_identities[$background_pid]="${_AI_CANDY_BACKGROUND_IDENTITIES[$background_pid]-}"
    fi
  done
  _AI_CANDY_BACKGROUND_PIDS=("${owned_pids[@]}")
  _AI_CANDY_BACKGROUND_IDENTITIES=("${(@kv)owned_identities}")
}

function _ai_candy_stop_registered_background_jobs() {
  emulate -L zsh
  local background_pid process_pid process_state process_table=""
  local process_signature="" stopped_signature=""
  local -a owned_pids stopped_pids verified_pids descendants cleanup_pids
  local -A owned_identities stopped_pid_seen
  integer attempt index all_stopped forest_stable=0 descendant_alive

  for background_pid in "${_AI_CANDY_BACKGROUND_PIDS[@]}"; do
    if _ai_candy_background_pid_is_owned "$background_pid"; then
      owned_pids+=("$background_pid")
      owned_identities[$background_pid]="${_AI_CANDY_BACKGROUND_IDENTITIES[$background_pid]-}"
    fi
  done
  _AI_CANDY_BACKGROUND_PIDS=()
  _AI_CANDY_BACKGROUND_IDENTITIES=()
  (( ${#owned_pids} )) || return 0

  for background_pid in "${owned_pids[@]}"; do
    if builtin kill -STOP "$background_pid" 2>/dev/null; then
      stopped_pids+=("$background_pid")
      stopped_pid_seen[$background_pid]=1
    fi
  done
  for attempt in {1..25}; do
    _ai_candy_read_process_table || break
    process_table="$REPLY"
    _ai_candy_index_process_table "$process_table"
    process_signature=""
    all_stopped=1
    for background_pid in "${owned_pids[@]}"; do
      _ai_candy_collect_process_tree_from_index "$background_pid"
      process_signature+="${background_pid}:${(j:,:)_AI_CANDY_TIMEOUT_PROCESS_TREE};"
      for process_pid in "${_AI_CANDY_TIMEOUT_PROCESS_TREE[@]}"; do
        process_state="${_AI_CANDY_PROCESS_STATE_BY_PID[$process_pid]-}"
        if [[ -n "$process_state" && \
              "${process_state[1]}" != "T" && \
              "${process_state[1]}" != "Z" ]]; then
          all_stopped=0
        fi
        if builtin kill -STOP "$process_pid" 2>/dev/null && \
           [[ -z "${stopped_pid_seen[$process_pid]-}" ]]; then
          stopped_pids+=("$process_pid")
          stopped_pid_seen[$process_pid]=1
        fi
      done
    done
    if (( all_stopped )); then
      if [[ -n "$stopped_signature" && \
            "$process_signature" == "$stopped_signature" ]]; then
        forest_stable=1
        break
      fi
      stopped_signature="$process_signature"
    else
      stopped_signature=""
    fi
    _ai_candy_sleep_ticks 1
  done
  if (( ! forest_stable )); then
    for background_pid in "${owned_pids[@]}"; do
      if _ai_candy_background_pid_identity "$background_pid" && \
         [[ "$REPLY" == "${owned_identities[$background_pid]-}" ]] && \
         _ai_candy_background_pid_parent_is_shell "$background_pid"; then
        _ai_candy_kill_process_tree "$background_pid"
        builtin wait "$background_pid" 2>/dev/null || true
      fi
    done
    for process_pid in "${stopped_pids[@]}"; do
      builtin kill -CONT "$process_pid" 2>/dev/null
    done
    _AI_CANDY_TIMEOUT_PROCESS_TREE=()
    _AI_CANDY_PROCESS_CHILDREN_BY_PARENT=()
    _AI_CANDY_PROCESS_STATE_BY_PID=()
    return 0
  fi

  verified_pids=()
  descendants=()
  for background_pid in "${owned_pids[@]}"; do
    if _ai_candy_background_pid_identity "$background_pid" && \
       [[ "$REPLY" == "${owned_identities[$background_pid]-}" ]] && \
       _ai_candy_background_pid_parent_is_shell "$background_pid"; then
      verified_pids+=("$background_pid")
      _ai_candy_collect_process_tree_from_index "$background_pid"
      for (( index=${#_AI_CANDY_TIMEOUT_PROCESS_TREE}; index>=2; index-- )); do
        process_pid="${_AI_CANDY_TIMEOUT_PROCESS_TREE[index]}"
        descendants+=("$process_pid")
        builtin kill -TERM "$process_pid" 2>/dev/null
      done
      builtin kill -TERM "$background_pid" 2>/dev/null
    fi
  done
  # Do not leave a process stopped if its identity changes after STOP.
  for process_pid in "${stopped_pids[@]}"; do
    builtin kill -CONT "$process_pid" 2>/dev/null
  done
  cleanup_pids=("${verified_pids[@]}" "${descendants[@]}")
  if (( ! ${#cleanup_pids} )); then
    _AI_CANDY_TIMEOUT_PROCESS_TREE=()
    _AI_CANDY_PROCESS_CHILDREN_BY_PARENT=()
    _AI_CANDY_PROCESS_STATE_BY_PID=()
    return 0
  fi
  for attempt in {1..2}; do
    descendant_alive=0
    for process_pid in "${cleanup_pids[@]}"; do
      if _ai_candy_process_pid_is_active "$process_pid"; then
        descendant_alive=1
        break
      fi
    done
    (( descendant_alive )) || break
    _ai_candy_sleep_ticks 1
  done
  if (( descendant_alive )); then
    for process_pid in "${descendants[@]}"; do
      builtin kill -KILL "$process_pid" 2>/dev/null
    done
  fi
  for background_pid in "${verified_pids[@]}"; do
    integer root_is_owned=0
    if _ai_candy_background_pid_identity "$background_pid" && \
       [[ "$REPLY" == "${owned_identities[$background_pid]-}" ]] && \
       _ai_candy_background_pid_parent_is_shell "$background_pid"; then
      root_is_owned=1
      if (( descendant_alive )); then
        _ai_candy_kill_process_tree "$background_pid"
      fi
    fi
    if (( root_is_owned )) || ! _ai_candy_process_pid_is_active "$background_pid"; then
      builtin wait "$background_pid" 2>/dev/null || true
    fi
  done
  _AI_CANDY_TIMEOUT_PROCESS_TREE=()
  _AI_CANDY_PROCESS_CHILDREN_BY_PARENT=()
  _AI_CANDY_PROCESS_STATE_BY_PID=()
}

function _ai_candy_preexec_cleanup_for_exec() {
  emulate -L zsh
  setopt localoptions noerrexit noerrreturn extendedglob
  local REPLY=""

  local typed_command="${1:-}"
  local expanded_command="${2:-$typed_command}"
  local executed_command="${3:-$expanded_command}"
  local command_text="${executed_command:-${expanded_command:-$typed_command}}"
  local -a command_words command_starts
  command_words=( "${(z)command_text}" )
  integer index scan_index total=${#command_words} force_builtin expect_command=1
  local target_word=""

  command_starts=()
  for (( scan_index=1; scan_index<=total; scan_index++ )); do
    case "${command_words[scan_index]}" in
      '&&'|'||'|';'|'&'|'|'|'|&'|';;'|';&'|';;&'|$'\n'|')'|'{')
        expect_command=1
        continue
        ;;
    esac
    (( expect_command )) || continue
    case "${command_words[scan_index]}" in
      if|then|elif|else|while|until|do|for|select|repeat|case|function|time|coproc)
        continue
        ;;
    esac
    command_starts+=("$scan_index")
    expect_command=0
  done

  for index in "${command_starts[@]}"; do
    force_builtin=0
    while (( index <= total )) && \
          [[ "${command_words[index]}" == [A-Za-z_][A-Za-z0-9_]#=* ]]; do
      (( ++index ))
    done
    while [[ "${command_words[index]-}" == "noglob" || \
             "${command_words[index]-}" == "nocorrect" || \
             "${command_words[index]-}" == "!" ]]; do
      (( ++index ))
    done
    if [[ "${command_words[index]-}" == "command" ]]; then
      force_builtin=1
      (( ++index ))
      [[ "${command_words[index]-}" == "-p" ]] && (( ++index ))
    elif [[ "${command_words[index]-}" == "builtin" && \
            "${command_words[index+1]-}" == "exec" ]]; then
      force_builtin=1
      (( ++index ))
    fi

    [[ "${(Q)${command_words[index]-}}" == "exec" ]] || continue
    (( force_builtin || ! ${+functions[exec]} )) || continue

    (( ++index ))
    while (( index <= total )); do
      case "${command_words[index]}" in
        -a)
          (( index += 2 ))
          ;;
        -c|-l)
          (( ++index ))
          ;;
        --)
          (( ++index ))
          break
          ;;
        '<'|'>'|'>>'|'<<'|'<<<'|'<>'|'>&'|'<&'|'>|'|'&>')
          (( index += 2 ))
          ;;
        *)
          break
          ;;
      esac
    done
    (( index <= total )) || continue
    target_word="${command_words[index]}"
    case "$target_word" in
      '&&'|'||'|';'|'&'|'|'|'|&'|$'\n')
        continue
        ;;
    esac
    _ai_candy_stop_registered_background_jobs
    return 0
  done
  return 0
}

function _ai_candy_signal_cleanup() {
  local signal_name="$1"
  local trap_name="$2"
  local previous_trap="$3"
  local default_status="$4"
  shift 4

  _ai_candy_stop_registered_background_jobs
  if (( ${+functions[$previous_trap]} )); then
    "$previous_trap" "$@"
    return $?
  fi

  builtin unfunction "$trap_name" 2>/dev/null || true
  local process_pid="${sysparams[pid]-}"
  if [[ "$process_pid" == <-> ]]; then
    builtin kill "-${signal_name}" "$process_pid" 2>/dev/null || \
      builtin exit "$default_status"
    return "$default_status"
  fi
  builtin exit "$default_status"
}

function _ai_candy_install_signal_trap() {
  local trap_name="$1"
  local previous_trap="$2"
  local wrapper_name="$3"

  [[ "${functions[$trap_name]-}" == "${functions[$wrapper_name]-}" ]] && return 0
  if (( ${+functions[$trap_name]} )); then
    functions[$previous_trap]="${functions[$trap_name]}"
  else
    builtin unfunction "$previous_trap" 2>/dev/null || true
  fi
  functions[$trap_name]="${functions[$wrapper_name]}"
}

function _ai_candy_restore_owned_signal_trap() {
  local trap_name="$1"
  local previous_trap="$2"
  local wrapper_name="$3"

  [[ "${functions[$trap_name]-}" == "${functions[$wrapper_name]-}" ]] || return 0
  if (( ${+functions[$previous_trap]} )); then
    functions[$trap_name]="${functions[$previous_trap]}"
  else
    builtin unfunction "$trap_name" 2>/dev/null || true
  fi
}

function _AI_CANDY_TRAPHUP_WRAPPER() {
  _ai_candy_signal_cleanup HUP TRAPHUP _AI_CANDY_PREVIOUS_TRAPHUP 129 "$@"
}

function _AI_CANDY_TRAPINT_WRAPPER() {
  _ai_candy_signal_cleanup INT TRAPINT _AI_CANDY_PREVIOUS_TRAPINT 130 "$@"
}

function _AI_CANDY_TRAPTERM_WRAPPER() {
  _ai_candy_signal_cleanup TERM TRAPTERM _AI_CANDY_PREVIOUS_TRAPTERM 143 "$@"
}

function _ai_candy_install_signal_traps() {
  _ai_candy_restore_owned_signal_trap TRAPINT _AI_CANDY_PREVIOUS_TRAPINT \
    _AI_CANDY_TRAPINT_WRAPPER
  _ai_candy_install_signal_trap TRAPHUP _AI_CANDY_PREVIOUS_TRAPHUP \
    _AI_CANDY_TRAPHUP_WRAPPER
  _ai_candy_install_signal_trap TRAPTERM _AI_CANDY_PREVIOUS_TRAPTERM \
    _AI_CANDY_TRAPTERM_WRAPPER
}

function _ai_candy_run_with_timeout() {
  emulate -L zsh
  local timeout_sec="$1"
  local integer_part="${timeout_sec%%.*}"
  case "$timeout_sec" in
    <->|<->.<->|.<->) ;;
    *) return 124 ;;
  esac
  (( ${#timeout_sec} <= 32 )) || return 124
  [[ -n "$integer_part" ]] || integer_part=0
  while [[ ${#integer_part} -gt 1 && "$integer_part" == 0* ]]; do
    integer_part="${integer_part#0}"
  done
  (( ${#integer_part} <= 5 )) || return 124
  local -F timeout_value="$timeout_sec"
  shift
  (( timeout_value > 0 && timeout_value <= 86400 )) || return 124
  local -a command_args=("$@")
  local command_name="${command_args[1]-}"
  integer target_is_external=0

  if [[ -n "$command_name" ]]; then
    if _ai_candy_resolve_external_command "$command_name"; then
      command_args[1]="$REPLY"
      target_is_external=1
    elif [[ "$command_name" != */* ]] && \
         (( _AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT && ${+builtins[$command_name]} )); then
      command_args=(builtin "$command_name" "${command_args[@]:1}")
    else
      return 127
    fi
  fi

  if [[ "$_AI_CANDY_TIMEOUT_CMD" == /* ]]; then
    _ai_candy_run_external_timeout "$_AI_CANDY_TIMEOUT_CMD" "$timeout_sec" "${command_args[@]}"
  elif (( _AI_CANDY_HAS_ZSH_NATIVE_TIMEOUT )); then
    if (( target_is_external )); then
      _ai_candy_run_native_timeout "$timeout_sec" command "${command_args[@]}"
    else
      _ai_candy_run_native_timeout "$timeout_sec" "${command_args[@]}"
    fi
  else
    return 124
  fi
}

function _ai_candy_run_with_timeout_combined_output() {
  local _AI_CANDY_TIMEOUT_CAPTURE_STDERR=1
  _ai_candy_run_with_timeout "$@"
}

function _ai_candy_run_local_probe() {
  _ai_candy_run_with_timeout "${_AI_CANDY_LOCAL_PROMPT_TIMEOUT:-0.25}" "$@"
}

function _ai_candy_run_background_probe() {
  _ai_candy_run_with_timeout "${_AI_CANDY_BACKGROUND_LOCAL_PROBE_TIMEOUT:-1}" "$@"
}

function _ai_candy_run_process_count_probe() {
  _ai_candy_run_with_timeout "${_AI_CANDY_PROCESS_COUNT_TIMEOUT:-0.05}" "$@"
}

# ============================================================================
# CACHE DIRECTORY SETUP - Secure cache location in user's home directory
# ============================================================================
# Cache files are stored in $HOME/.cache/zsh-prompt/ with strict permissions
# to prevent information leakage on shared systems.
typeset -g _AI_CANDY_CACHE_DIR=""
if [[ "${XDG_CACHE_HOME:-}" == /* ]]; then
  _AI_CANDY_CACHE_DIR="${XDG_CACHE_HOME%/}/zsh-prompt"
elif [[ "${HOME:-}" == /* ]]; then
  _AI_CANDY_CACHE_DIR="${HOME%/}/.cache/zsh-prompt"
else
  _AI_CANDY_CACHE_DIR="/dev/null/ai-candy-cache-disabled"
fi
typeset -g _AI_CANDY_CACHE_READY=0

function _ai_candy_cache_init_dir() {
  [[ -L "$_AI_CANDY_CACHE_DIR" ]] && return 1

  if (( _AI_CANDY_HAS_ZSH_FILE_BUILTINS )); then
    ( umask 077 && builtin zf_mkdir -p -m 700 "$_AI_CANDY_CACHE_DIR" ) 2>/dev/null || return 1
  else
    ( umask 077 && command mkdir -p "$_AI_CANDY_CACHE_DIR" ) 2>/dev/null || return 1
  fi
  _ai_candy_chmod 700 "$_AI_CANDY_CACHE_DIR" 2>/dev/null || return 1

  [[ -d "$_AI_CANDY_CACHE_DIR" && -w "$_AI_CANDY_CACHE_DIR" ]] || return 1
  _AI_CANDY_CACHE_READY=1
}

_ai_candy_cache_init_dir || true

# ============================================================================
# CACHE FILE PATHS - Centralized definitions for all cache files
# ============================================================================
# System and prompt state caches
typeset -g _AI_CANDY_SYSINFO_CACHE_FILE="${_AI_CANDY_CACHE_DIR}/sysinfo_cache"
typeset -g _AI_CANDY_EMOJI_MODE_FILE="${_AI_CANDY_CACHE_DIR}/emoji_mode"
typeset -g _AI_CANDY_PATH_SEP_MODE_FILE="${_AI_CANDY_CACHE_DIR}/path_sep_mode"
typeset -g _AI_CANDY_NETWORK_MODE_FILE="${_AI_CANDY_CACHE_DIR}/network_mode"
typeset -g _AI_CANDY_AI_MODE_FILE="${_AI_CANDY_CACHE_DIR}/ai_mode"
typeset -g _AI_CANDY_OS_MODE_FILE="${_AI_CANDY_CACHE_DIR}/os_mode"

# Optional-tool version caches
typeset -g _AI_CANDY_CLAUDE_CACHE_FILE="${_AI_CANDY_CACHE_DIR}/claude_version_cache"
typeset -g _AI_CANDY_CODEX_CACHE_FILE="${_AI_CANDY_CACHE_DIR}/codex_version_cache"
typeset -g _AI_CANDY_GEMINI_CACHE_FILE="${_AI_CANDY_CACHE_DIR}/gemini_version_cache"
typeset -g _AI_CANDY_KIMI_CACHE_FILE="${_AI_CANDY_CACHE_DIR}/kimi_version_cache"

# GitHub integration caches
typeset -g _AI_CANDY_GH_AUTH_CACHE_FILE="${_AI_CANDY_CACHE_DIR}/gh_auth_status"
typeset -g _AI_CANDY_GH_USERNAME_GH_CACHE_FILE="${_AI_CANDY_CACHE_DIR}/gh_username_gh"
typeset -g _AI_CANDY_GH_USERNAME_SSH_CACHE_FILE="${_AI_CANDY_CACHE_DIR}/gh_username_ssh"

# Public IP cache (refreshes every 5 minutes)
typeset -g _AI_CANDY_PUBLIC_IP_CACHE_FILE="${_AI_CANDY_CACHE_DIR}/public_ip_cache"

# Lock file patterns (used with .d suffix for atomic mkdir locks)
typeset -g _AI_CANDY_GH_USERNAME_UPDATING_GH="${_AI_CANDY_CACHE_DIR}/gh_username_updating_gh.lock"
typeset -g _AI_CANDY_GH_USERNAME_UPDATING_SSH="${_AI_CANDY_CACHE_DIR}/gh_username_updating_ssh.lock"
typeset -g _AI_CANDY_GH_AUTH_UPDATING="${_AI_CANDY_CACHE_DIR}/gh_auth_updating.lock"
typeset -g _AI_CANDY_PUBLIC_IP_UPDATING="${_AI_CANDY_CACHE_DIR}/public_ip_updating.lock"
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
  set -m || exit 125
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
# Unicode 15.0 zero-width and East Asian wide/full-width intervals. The raw
# data is split lazily so ASCII-only prompts do not pay the table setup cost.
typeset -ga _AI_CANDY_PROMPT_ZERO_WIDTH_DATA=(
  '300-36f,483-489,591-5bd,5bf-5bf,5c1-5c2,5c4-5c5,5c7-5c7,610-61a,64b-65f,670-670,6d6-6dc,'\
  '6df-6e4,6e7-6e8,6ea-6ed,711-711,730-74a,7a6-7b0,7eb-7f3,7fd-7fd,816-819,81b-823,825-827,'\
  '829-82d,859-85b,898-89f,8ca-8e1,8e3-902,93a-93a,93c-93c,941-948,94d-94d,951-957,962-963,'\
  '981-981,9bc-9bc,9c1-9c4,9cd-9cd,9e2-9e3,9fe-9fe,a01-a02,a3c-a3c,a41-a42,a47-a48,a4b-a4d,'\
  'a51-a51,a70-a71,a75-a75,a81-a82,abc-abc,ac1-ac5,ac7-ac8,acd-acd,ae2-ae3,afa-aff,b01-b01,'\
  'b3c-b3c,b3f-b3f,b41-b44,b4d-b4d,b55-b56,b62-b63,b82-b82,bc0-bc0,bcd-bcd,c00-c00,c04-c04,'\
  'c3c-c3c,c3e-c40,c46-c48,c4a-c4d,c55-c56,c62-c63,c81-c81,cbc-cbc,cbf-cbf,cc6-cc6,ccc-ccd,'\
  'ce2-ce3,d00-d01,d3b-d3c,d41-d44,d4d-d4d,d62-d63,d81-d81,dca-dca,dd2-dd4,dd6-dd6,e31-e31,'\
  'e34-e3a,e47-e4e,eb1-eb1,eb4-ebc,ec8-ece,f18-f19,f35-f35,f37-f37,f39-f39,f71-f7e,f80-f84,'\
  'f86-f87,f8d-f97,f99-fbc,fc6-fc6,102d-1030,1032-1037,1039-103a,103d-103e,1058-1059,105e-1060,'\
  '1071-1074,1082-1082,1085-1086,108d-108d,109d-109d,135d-135f,1712-1714,1732-1733,1752-1753,'\
  '1772-1773,17b4-17b5,17b7-17bd,17c6-17c6,17c9-17d3,17dd-17dd,180b-180d,180f-180f,1885-1886,'\
  '18a9-18a9,1920-1922,1927-1928,1932-1932,1939-193b,1a17-1a18,1a1b-1a1b,1a56-1a56,1a58-1a5e,'\
  '1a60-1a60,1a62-1a62,1a65-1a6c,1a73-1a7c,1a7f-1a7f,1ab0-1ace,1b00-1b03,1b34-1b34,1b36-1b3a,'\
  '1b3c-1b3c,1b42-1b42,1b6b-1b73,1b80-1b81,1ba2-1ba5,1ba8-1ba9,1bab-1bad,1be6-1be6,1be8-1be9,'\
  '1bed-1bed,1bef-1bf1,1c2c-1c33,1c36-1c37,1cd0-1cd2,1cd4-1ce0,1ce2-1ce8,1ced-1ced,1cf4-1cf4,'\
  '1cf8-1cf9,1dc0-1dff,20d0-20f0,2cef-2cf1,2d7f-2d7f,2de0-2dff,302a-302d,3099-309a,a66f-a672,'\
  'a674-a67d,a69e-a69f,a6f0-a6f1,a802-a802,a806-a806,a80b-a80b,a825-a826,a82c-a82c,a8c4-a8c5,'\
  'a8e0-a8f1,a8ff-a8ff,a926-a92d,a947-a951,a980-a982,a9b3-a9b3,a9b6-a9b9,a9bc-a9bd,a9e5-a9e5,'\
  'aa29-aa2e,aa31-aa32,aa35-aa36,aa43-aa43,aa4c-aa4c,aa7c-aa7c,aab0-aab0,aab2-aab4,aab7-aab8,'\
  'aabe-aabf,aac1-aac1,aaec-aaed,aaf6-aaf6,abe5-abe5,abe8-abe8,abed-abed,fb1e-fb1e,fe00-fe0f,'\
  'fe20-fe2f,101fd-101fd,102e0-102e0,10376-1037a,10a01-10a03,10a05-10a06,10a0c-10a0f,'\
  '10a38-10a3a,10a3f-10a3f,10ae5-10ae6,10d24-10d27,10eab-10eac,10efd-10eff,10f46-10f50,'\
  '10f82-10f85,11001-11001,11038-11046,11070-11070,11073-11074,1107f-11081,110b3-110b6,'\
  '110b9-110ba,110c2-110c2,11100-11102,11127-1112b,1112d-11134,11173-11173,11180-11181,'\
  '111b6-111be,111c9-111cc,111cf-111cf,1122f-11231,11234-11234,11236-11237,1123e-1123e,'\
  '11241-11241,112df-112df,112e3-112ea,11300-11301,1133b-1133c,11340-11340,11366-1136c,'\
  '11370-11374,11438-1143f,11442-11444,11446-11446,1145e-1145e,114b3-114b8,114ba-114ba,'\
  '114bf-114c0,114c2-114c3,115b2-115b5,115bc-115bd,115bf-115c0,115dc-115dd,11633-1163a,'\
  '1163d-1163d,1163f-11640,116ab-116ab,116ad-116ad,116b0-116b5,116b7-116b7,1171d-1171f,'\
  '11722-11725,11727-1172b,1182f-11837,11839-1183a,1193b-1193c,1193e-1193e,11943-11943,'\
  '119d4-119d7,119da-119db,119e0-119e0,11a01-11a0a,11a33-11a38,11a3b-11a3e,11a47-11a47,'\
  '11a51-11a56,11a59-11a5b,11a8a-11a96,11a98-11a99,11c30-11c36,11c38-11c3d,11c3f-11c3f,'\
  '11c92-11ca7,11caa-11cb0,11cb2-11cb3,11cb5-11cb6,11d31-11d36,11d3a-11d3a,11d3c-11d3d,'\
  '11d3f-11d45,11d47-11d47,11d90-11d91,11d95-11d95,11d97-11d97,11ef3-11ef4,11f00-11f01,'\
  '11f36-11f3a,11f40-11f40,11f42-11f42,13440-13440,13447-13455,16af0-16af4,16b30-16b36,'\
  '16f4f-16f4f,16f8f-16f92,16fe4-16fe4,1bc9d-1bc9e,1cf00-1cf2d,1cf30-1cf46,1d167-1d169,'\
  '1d17b-1d182,1d185-1d18b,1d1aa-1d1ad,1d242-1d244,1da00-1da36,1da3b-1da6c,1da75-1da75,'\
  '1da84-1da84,1da9b-1da9f,1daa1-1daaf,1e000-1e006,1e008-1e018,1e01b-1e021,1e023-1e024,'\
  '1e026-1e02a,1e08f-1e08f,1e130-1e136,1e2ae-1e2ae,1e2ec-1e2ef,1e4ec-1e4ef,1e8d0-1e8d6,'\
  '1e944-1e94a,e0100-e01ef'
)

typeset -ga _AI_CANDY_PROMPT_WIDE_WIDTH_DATA=(
  '1100-115f,231a-231b,2329-232a,23e9-23ec,23f0-23f0,23f3-23f3,25fd-25fe,2614-2615,2648-2653,'\
  '267f-267f,2693-2693,26a1-26a1,26aa-26ab,26bd-26be,26c4-26c5,26ce-26ce,26d4-26d4,26ea-26ea,'\
  '26f2-26f3,26f5-26f5,26fa-26fa,26fd-26fd,2705-2705,270a-270b,2728-2728,274c-274c,274e-274e,'\
  '2753-2755,2757-2757,2795-2797,27b0-27b0,27bf-27bf,2b1b-2b1c,2b50-2b50,2b55-2b55,2e80-2e99,'\
  '2e9b-2ef3,2f00-2fd5,2ff0-2ffb,3000-303e,3041-3096,3099-30ff,3105-312f,3131-318e,3190-31e3,'\
  '31f0-321e,3220-3247,3250-4dbf,4e00-a48c,a490-a4c6,a960-a97c,ac00-d7a3,f900-faff,fe10-fe19,'\
  'fe30-fe52,fe54-fe66,fe68-fe6b,ff01-ff60,ffe0-ffe6,16fe0-16fe4,16ff0-16ff1,17000-187f7,'\
  '18800-18cd5,18d00-18d08,1aff0-1aff3,1aff5-1affb,1affd-1affe,1b000-1b122,1b132-1b132,'\
  '1b150-1b152,1b155-1b155,1b164-1b167,1b170-1b2fb,1f004-1f004,1f0cf-1f0cf,1f18e-1f18e,'\
  '1f191-1f19a,1f200-1f202,1f210-1f23b,1f240-1f248,1f250-1f251,1f260-1f265,1f300-1f320,'\
  '1f32d-1f335,1f337-1f37c,1f37e-1f393,1f3a0-1f3ca,1f3cf-1f3d3,1f3e0-1f3f0,1f3f4-1f3f4,'\
  '1f3f8-1f43e,1f440-1f440,1f442-1f4fc,1f4ff-1f53d,1f54b-1f54e,1f550-1f567,1f57a-1f57a,'\
  '1f595-1f596,1f5a4-1f5a4,1f5fb-1f64f,1f680-1f6c5,1f6cc-1f6cc,1f6d0-1f6d2,1f6d5-1f6d7,'\
  '1f6dc-1f6df,1f6eb-1f6ec,1f6f4-1f6fc,1f7e0-1f7eb,1f7f0-1f7f0,1f90c-1f93a,1f93c-1f945,'\
  '1f947-1f9ff,1fa70-1fa7c,1fa80-1fa88,1fa90-1fabd,1fabf-1fac5,1face-1fadb,1fae0-1fae8,'\
  '1faf0-1faf8,20000-2fffd,30000-3fffd'
)

typeset -ga _AI_CANDY_PROMPT_EMOJI_MODIFIER_BASE_DATA=(
  '261d-261d,26f9-26f9,270a-270c,270d-270d,1f385-1f385,1f3c2-1f3c4,1f3c7-1f3c7,1f3ca-1f3ca,'
  '1f3cb-1f3cc,1f442-1f443,1f446-1f450,1f466-1f46b,1f46c-1f46d,1f46e-1f478,1f47c-1f47c,'
  '1f481-1f483,1f485-1f487,1f48f-1f48f,1f491-1f491,1f4aa-1f4aa,1f574-1f575,1f57a-1f57a,'
  '1f590-1f590,1f595-1f596,1f645-1f647,1f64b-1f64f,1f6a3-1f6a3,1f6b4-1f6b5,1f6b6-1f6b6,'
  '1f6c0-1f6c0,1f6cc-1f6cc,1f90c-1f90c,1f90f-1f90f,1f918-1f918,1f919-1f91e,1f91f-1f91f,'
  '1f926-1f926,1f930-1f930,1f931-1f932,1f933-1f939,1f93c-1f93e,1f977-1f977,1f9b5-1f9b6,'
  '1f9b8-1f9b9,1f9bb-1f9bb,1f9cd-1f9cf,1f9d1-1f9dd,1fac3-1fac5,1faf0-1faf6,1faf7-1faf8'
)

typeset -g _AI_CANDY_PROMPT_WIDTH_TABLES_READY=0
typeset -ga _AI_CANDY_PROMPT_ZERO_WIDTH_RANGES=()
typeset -ga _AI_CANDY_PROMPT_WIDE_WIDTH_RANGES=()
typeset -ga _AI_CANDY_PROMPT_EMOJI_MODIFIER_BASE_RANGES=()
typeset -ga _AI_CANDY_PROMPT_MEASURED_CHARACTERS=()
typeset -ga _AI_CANDY_PROMPT_MEASURED_WIDTHS=()
typeset -ga _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_TEXTS=()
typeset -ga _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_WIDTHS=()
typeset -g _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_LIMIT=64

function _ai_candy_prompt_width_tables_init() {
  (( _AI_CANDY_PROMPT_WIDTH_TABLES_READY )) && return 0
  local zero_data="${(j::)_AI_CANDY_PROMPT_ZERO_WIDTH_DATA}"
  local wide_data="${(j::)_AI_CANDY_PROMPT_WIDE_WIDTH_DATA}"
  local modifier_base_data="${(j::)_AI_CANDY_PROMPT_EMOJI_MODIFIER_BASE_DATA}"
  _AI_CANDY_PROMPT_ZERO_WIDTH_RANGES=("${(@s:,:)zero_data}")
  _AI_CANDY_PROMPT_WIDE_WIDTH_RANGES=("${(@s:,:)wide_data}")
  _AI_CANDY_PROMPT_EMOJI_MODIFIER_BASE_RANGES=("${(@s:,:)modifier_base_data}")
  _AI_CANDY_PROMPT_WIDTH_TABLES_READY=1
}

function _ai_candy_prompt_codepoint_in_width_table() {
  integer code="$1"
  local table_name="$2"
  local interval=""
  integer low=1 high=0 midpoint range_start range_end

  case "$table_name" in
    zero) high=${#_AI_CANDY_PROMPT_ZERO_WIDTH_RANGES} ;;
    wide) high=${#_AI_CANDY_PROMPT_WIDE_WIDTH_RANGES} ;;
    modifier-base) high=${#_AI_CANDY_PROMPT_EMOJI_MODIFIER_BASE_RANGES} ;;
    *) return 1 ;;
  esac
  while (( low <= high )); do
    midpoint=$(( (low + high) / 2 ))
    case "$table_name" in
      zero) interval="${_AI_CANDY_PROMPT_ZERO_WIDTH_RANGES[midpoint]}" ;;
      wide) interval="${_AI_CANDY_PROMPT_WIDE_WIDTH_RANGES[midpoint]}" ;;
      modifier-base)
        interval="${_AI_CANDY_PROMPT_EMOJI_MODIFIER_BASE_RANGES[midpoint]}"
        ;;
    esac
    range_start=$(( 16#${interval%%-*} ))
    range_end=$(( 16#${interval##*-} ))
    if (( code < range_start )); then
      high=$(( midpoint - 1 ))
    elif (( code > range_end )); then
      low=$(( midpoint + 1 ))
    else
      return 0
    fi
  done
  return 1
}

function _ai_candy_prompt_decode_utf8_at() {
  emulate -L zsh
  local LC_ALL=C
  local text="$1"
  integer index="$2"
  local first_byte="${text[index]}"
  local second_byte="" third_byte="" fourth_byte=""
  integer first=$(( #first_byte ))
  integer second=0 third=0 fourth=0 codepoint=63 byte_count=1

  if (( first < 128 )); then
    codepoint="$first"
  elif (( first >= 194 && first <= 223 )); then
    second_byte="${text[index+1]}"
    second=$(( #second_byte ))
    codepoint=$(( (first - 192) * 64 + second - 128 ))
    byte_count=2
  elif (( first >= 224 && first <= 239 )); then
    second_byte="${text[index+1]}"
    third_byte="${text[index+2]}"
    second=$(( #second_byte ))
    third=$(( #third_byte ))
    codepoint=$(( (first - 224) * 4096 + \
      (second - 128) * 64 + third - 128 ))
    byte_count=3
  elif (( first >= 240 && first <= 244 )); then
    second_byte="${text[index+1]}"
    third_byte="${text[index+2]}"
    fourth_byte="${text[index+3]}"
    second=$(( #second_byte ))
    third=$(( #third_byte ))
    fourth=$(( #fourth_byte ))
    codepoint=$(( (first - 240) * 262144 + \
      (second - 128) * 4096 + (third - 128) * 64 + fourth - 128 ))
    byte_count=4
  fi
  reply=("$codepoint" "$byte_count" "${text[index,index+byte_count-1]}")
}

function _ai_candy_prompt_codepoint_width() {
  integer code="$1"

  if (( code == 0 || code < 32 || (code >= 127 && code < 160) )); then
    REPLY=0
  elif (( code < 0x0300 )); then
    REPLY=1
  elif (( (code >= 0x200b && code <= 0x200d) || \
          (code >= 0x2028 && code <= 0x202e) || \
          (code >= 0x2060 && code <= 0x2063) || \
          (code >= 0xe0020 && code <= 0xe007f) )); then
    REPLY=0
  else
    _ai_candy_prompt_width_tables_init
    if _ai_candy_prompt_codepoint_in_width_table "$code" zero; then
      REPLY=0
    elif _ai_candy_prompt_codepoint_in_width_table "$code" wide; then
      REPLY=2
    else
      REPLY=1
    fi
  fi
}

function _ai_candy_prompt_measure_text() {
  emulate -L zsh
  _ai_candy_sanitize_terminal_text "$1"
  local text="$REPLY"
  integer capture_characters="${2:-0}"
  local LC_ALL=C
  local character=""
  integer index=1 length=${#text} byte_count codepoint codepoint_width
  integer width=0 join_next=0 continuation=0 regional_pending=0
  integer last_base_width=0 last_base_codepoint=0 character_index=0
  integer cluster_width=0 cluster_last_index=0 cluster_width_increment=0

  if (( capture_characters )); then
    _AI_CANDY_PROMPT_MEASURED_CHARACTERS=()
    _AI_CANDY_PROMPT_MEASURED_WIDTHS=()
  fi
  while (( index <= length )); do
    _ai_candy_prompt_decode_utf8_at "$text" "$index"
    codepoint="${reply[1]}"
    byte_count="${reply[2]}"
    character="${reply[3]}"
    _ai_candy_prompt_codepoint_width "$codepoint"
    codepoint_width="$REPLY"
    character_index=$(( character_index + 1 ))
    continuation=0
    cluster_width_increment=0

    if (( codepoint == 0xfe0f )); then
      continuation=1
      if (( last_base_width == 1 )); then
        width=$(( width + 1 ))
        last_base_width=2
        cluster_width=2
      fi
      codepoint_width=0
    elif (( join_next && codepoint_width > 0 )); then
      continuation=1
      last_base_codepoint="$codepoint"
      codepoint_width=0
      join_next=0
    elif (( codepoint >= 0x1f3fb && codepoint <= 0x1f3ff )); then
      if _ai_candy_prompt_codepoint_in_width_table \
           "$last_base_codepoint" modifier-base; then
        continuation=1
        codepoint_width=0
        last_base_codepoint=0
      fi
    fi
    if (( codepoint_width == 0 && character_index > 1 )); then
      continuation=1
    fi
    if (( codepoint >= 0x1f1e6 && codepoint <= 0x1f1ff )); then
      if (( regional_pending )); then
        continuation=1
        cluster_width_increment="$codepoint_width"
        regional_pending=0
      else
        regional_pending=1
      fi
    else
      regional_pending=0
    fi

    if (( codepoint == 0x200d )); then
      join_next=1
    elif (( codepoint != 0xfe0f && codepoint_width > 0 )); then
      last_base_width="$codepoint_width"
      last_base_codepoint="$codepoint"
    fi
    width=$(( width + codepoint_width ))
    if (( capture_characters )); then
      _AI_CANDY_PROMPT_MEASURED_CHARACTERS+=("$character")
      if (( continuation && cluster_last_index > 0 )); then
        _AI_CANDY_PROMPT_MEASURED_WIDTHS[cluster_last_index]=0
        cluster_width=$(( cluster_width + cluster_width_increment ))
      else
        cluster_width="$codepoint_width"
      fi
      _AI_CANDY_PROMPT_MEASURED_WIDTHS+=("$cluster_width")
      cluster_last_index="$character_index"
    fi
    index=$(( index + byte_count ))
  done
  REPLY="$width"
}

function _ai_candy_prompt_text_width() {
  emulate -L zsh
  local text="$1"
  integer index

  for (( index=1; index<=${#_AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_TEXTS}; index++ )); do
    if [[ "${_AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_TEXTS[index]}" == "$text" ]]; then
      REPLY="${_AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_WIDTHS[index]}"
      return 0
    fi
  done

  _ai_candy_prompt_measure_text "$text" 0
  local measured_width="$REPLY"
  if (( ${#_AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_TEXTS} >= \
        _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_LIMIT )); then
    _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_TEXTS=()
    _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_WIDTHS=()
  fi
  _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_TEXTS+=("$text")
  _AI_CANDY_PROMPT_TEXT_WIDTH_CACHE_WIDTHS+=("$measured_width")
  REPLY="$measured_width"
}

function _ai_candy_prompt_text_tail_by_width() {
  emulate -L zsh
  integer target_width="${2:-0}"
  local character result=""
  integer index character_width width=0 visible_characters=0

  (( target_width > 0 )) || {
    REPLY=""
    return 0
  }
  _ai_candy_prompt_measure_text "$1" 1
  for (( index=${#_AI_CANDY_PROMPT_MEASURED_CHARACTERS}; index>=1; index-- )); do
    character="${_AI_CANDY_PROMPT_MEASURED_CHARACTERS[index]}"
    character_width="${_AI_CANDY_PROMPT_MEASURED_WIDTHS[index]}"
    (( width + character_width <= target_width )) || break
    result="${character}${result}"
    width=$(( width + character_width ))
    (( character_width > 0 )) && visible_characters=$(( visible_characters + 1 ))
  done
  (( visible_characters > 0 )) || result=""
  REPLY="$result"
}
# ============================================================================
# CACHE PRIMITIVES
# ============================================================================

typeset -g _AI_CANDY_CACHE_TIMESTAMP_MAX_DIGITS=12
typeset -g _AI_CANDY_CACHE_FILE_MAX_BYTES=$((256 * 1024))
typeset -g _AI_CANDY_CACHE_LINE_MAX_BYTES=$((64 * 1024))
typeset -g _AI_CANDY_CACHE_VALUE_MAX_BYTES=$((16 * 1024))
typeset -gA _AI_CANDY_CACHE_LOCK_FDS
typeset -gA _AI_CANDY_CACHE_LOCK_TOKENS

function _ai_candy_cache_file_limit_bytes() {
  local configured_limit="${_AI_CANDY_CACHE_FILE_MAX_BYTES:-262144}"
  if [[ "$configured_limit" != <-> || ${#configured_limit} -gt 7 ]] || \
     (( configured_limit < 1024 || configured_limit > 1048576 )); then
    configured_limit=262144
  fi
  REPLY="$configured_limit"
}

function _ai_candy_cache_line_limit_bytes() {
  local configured_limit="${_AI_CANDY_CACHE_LINE_MAX_BYTES:-65536}"
  _ai_candy_cache_file_limit_bytes
  local file_limit="$REPLY"
  if [[ "$configured_limit" != <-> || ${#configured_limit} -gt 6 ]] || \
     (( configured_limit < 128 || configured_limit > 65536 )); then
    configured_limit=65536
  fi
  (( configured_limit > file_limit )) && configured_limit="$file_limit"
  REPLY="$configured_limit"
}

function _ai_candy_cache_value_limit_bytes() {
  local configured_limit="${_AI_CANDY_CACHE_VALUE_MAX_BYTES:-16384}"
  if [[ "$configured_limit" != <-> || ${#configured_limit} -gt 5 ]] || \
     (( configured_limit < 128 || configured_limit > 16384 )); then
    configured_limit=16384
  fi
  REPLY="$configured_limit"
}

function _ai_candy_cache_value_is_within_limit() {
  emulate -L zsh
  local LC_ALL=C
  local value="$1"

  _ai_candy_cache_value_limit_bytes
  (( ${#value} <= REPLY ))
}

function _ai_candy_cache_timestamp_field_is_valid() {
  local timestamp="$1"

  [[ "$timestamp" == <-> ]] || return 1
  (( ${#timestamp} <= _AI_CANDY_CACHE_TIMESTAMP_MAX_DIGITS )) || return 1
}

function _ai_candy_cache_timestamp_is_valid() {
  local timestamp="$1"
  local current_time="${2:-$EPOCHSECONDS}"

  _ai_candy_cache_timestamp_field_is_valid "$timestamp" || return 1
  _ai_candy_cache_timestamp_field_is_valid "$current_time" || return 1
  (( timestamp <= current_time ))
}

function _ai_candy_cache_timestamp_is_fresh() {
  local timestamp="$1"
  local ttl="$2"
  local current_time="${3:-$EPOCHSECONDS}"

  [[ "$ttl" == <-> ]] || return 1
  _ai_candy_cache_timestamp_is_valid "$timestamp" "$current_time" || return 1
  (( current_time - timestamp < ttl ))
}

function _ai_candy_file_mtime() {
  emulate -L zsh
  local target_path="$1"
  local value=""

  if (( _AI_CANDY_HAS_ZSH_STAT_BUILTIN )); then
    local -a metadata
    if builtin zstat -A metadata +mtime -- "$target_path" 2>/dev/null; then
      value="${metadata[1]}"
    fi
  elif [[ "$OSTYPE" == darwin* ]]; then
    value=$(command stat -f %m "$target_path" 2>/dev/null)
  else
    value=$(command stat -c %Y "$target_path" 2>/dev/null)
  fi

  [[ "$value" == <-> ]] || value=0
  REPLY="$value"
}

function _ai_candy_cache_remove_path() {
  local target_path="$1"
  if (( _AI_CANDY_HAS_ZSH_FILE_BUILTINS )); then
    builtin zf_rm -f "$target_path" 2>/dev/null
  else
    command rm -f "$target_path" 2>/dev/null
  fi
}

function _ai_candy_cache_remove_directory() {
  local target_path="$1"
  if (( _AI_CANDY_HAS_ZSH_FILE_BUILTINS )); then
    builtin zf_rmdir "$target_path" 2>/dev/null
  else
    command rmdir "$target_path" 2>/dev/null
  fi
}

function _ai_candy_cache_discard_lock_directory() {
  emulate -L zsh
  setopt null_glob
  local lock_dir="$1"
  local entry

  if [[ -L "$lock_dir" ]]; then
    _ai_candy_cache_remove_path "$lock_dir"
    return 0
  fi
  [[ -d "$lock_dir" ]] || return 0
  for entry in "$lock_dir"/*(N); do
    [[ -f "$entry" || -L "$entry" ]] && _ai_candy_cache_remove_path "$entry"
  done
  _ai_candy_cache_remove_directory "$lock_dir"
}

function _ai_candy_cache_quarantine_expired_lock() {
  local lock_dir="$1"
  local stale_after="$2"
  local current_time="${EPOCHSECONDS:-}"
  local lock_mtime quarantine

  [[ -d "$lock_dir" && ! -L "$lock_dir" ]] || return 1
  [[ "$stale_after" == <-> || "$stale_after" == <->.<-> ]] || return 1
  (( stale_after > 0 )) || return 1
  [[ "$current_time" == <-> ]] || current_time=$(command date +%s 2>/dev/null)
  [[ "$current_time" == <-> ]] || return 1
  _ai_candy_file_mtime "$lock_dir"
  lock_mtime="$REPLY"
  (( lock_mtime > 0 && current_time - lock_mtime > stale_after )) || return 1

  quarantine="${lock_dir}.stale.$$.$RANDOM.$RANDOM"
  [[ ! -e "$quarantine" && ! -L "$quarantine" ]] || return 1
  if (( _AI_CANDY_HAS_ZSH_FILE_BUILTINS )); then
    builtin zf_mv -f "$lock_dir" "$quarantine" 2>/dev/null || return 1
  else
    command mv "$lock_dir" "$quarantine" 2>/dev/null || return 1
  fi
  _ai_candy_cache_discard_lock_directory "$quarantine"
  return 0
}

function _ai_candy_cache_lock_acquire() {
  local lock_dir="$1"
  local stale_after="${2:-0}"
  local max_wait_ticks="${3:-0}"
  local lock_file="${lock_dir}.flock"
  integer waited_ticks=0

  if [[ -n "${_AI_CANDY_CACHE_LOCK_FDS[$lock_dir]-}" || \
        -n "${_AI_CANDY_CACHE_LOCK_TOKENS[$lock_dir]-}" ]]; then
    return 1
  fi

  if (( _AI_CANDY_HAS_ZSH_SYSTEM )); then
    integer create_fd lock_fd
    if [[ ! -e "$lock_file" ]]; then
      if builtin sysopen -w -o create,excl -m 600 -u create_fd "$lock_file" 2>/dev/null; then
        exec {create_fd}>&-
      else
        [[ -f "$lock_file" && ! -L "$lock_file" ]] || return 1
      fi
    fi
    [[ -f "$lock_file" && ! -L "$lock_file" ]] || return 1

    while true; do
      if builtin zsystem flock -f lock_fd -t 0 "$lock_file" 2>/dev/null; then
        _AI_CANDY_CACHE_LOCK_FDS[$lock_dir]="$lock_fd"
        return 0
      fi
      (( waited_ticks >= max_wait_ticks )) && return 1
      _ai_candy_sleep_ticks 1
      (( waited_ticks++ ))
    done
  fi

  while true; do
    integer directory_created=0
    if (( _AI_CANDY_HAS_ZSH_FILE_BUILTINS )); then
      ( umask 077 && builtin zf_mkdir -m 700 "$lock_dir" ) 2>/dev/null && \
        directory_created=1
    else
      ( umask 077 && command mkdir -m 700 "$lock_dir" ) 2>/dev/null && \
        directory_created=1
    fi
    if (( directory_created )); then
      local token="owner.$$.$RANDOM.$RANDOM"
      if ( umask 077 && builtin print -r -- "$$" >| "${lock_dir}/${token}" ) 2>/dev/null; then
        _AI_CANDY_CACHE_LOCK_TOKENS[$lock_dir]="$token"
        return 0
      fi
      _ai_candy_cache_remove_directory "$lock_dir"
    fi

    _ai_candy_cache_quarantine_expired_lock "$lock_dir" "$stale_after" && continue
    (( waited_ticks >= max_wait_ticks )) && return 1
    _ai_candy_sleep_ticks 1
    (( waited_ticks++ ))
  done
}

function _ai_candy_cache_lock_release() {
  local lock_dir="$1"
  local lock_fd="${_AI_CANDY_CACHE_LOCK_FDS[$lock_dir]-}"
  if [[ "$lock_fd" == <-> ]]; then
    builtin zsystem flock -u "$lock_fd" 2>/dev/null
    _AI_CANDY_CACHE_LOCK_FDS[$lock_dir]=""
  else
    local token="${_AI_CANDY_CACHE_LOCK_TOKENS[$lock_dir]-}"
    if [[ -n "$token" && -f "${lock_dir}/${token}" && \
          ! -L "${lock_dir}/${token}" ]]; then
      _ai_candy_cache_remove_path "${lock_dir}/${token}"
      _ai_candy_cache_remove_directory "$lock_dir"
    fi
    _AI_CANDY_CACHE_LOCK_TOKENS[$lock_dir]=""
  fi
}

function _ai_candy_cache_drop_inherited_locks() {
  emulate -L zsh
  local lock_fd

  for lock_fd in "${(@v)_AI_CANDY_CACHE_LOCK_FDS}"; do
    [[ "$lock_fd" == <-> ]] && exec {lock_fd}>&-
  done
  _AI_CANDY_CACHE_LOCK_FDS=()
  _AI_CANDY_CACHE_LOCK_TOKENS=()
}

function _ai_candy_cache_atomic_write_unlocked() {
  local cache_file="$1"
  local content="$2"
  local owner_pid="${sysparams[pid]-$$}"
  local temp_file="${cache_file}.tmp.${owner_pid}.${RANDOM}.${RANDOM}"
  local write_status=0
  local LC_ALL=C

  _ai_candy_cache_file_limit_bytes
  (( ${#content} + 1 <= REPLY )) || return 1

  ( umask 077 && builtin print -r -- "$content" >| "$temp_file" ) || write_status=$?
  if (( write_status == 0 )); then
    _ai_candy_chmod 600 "$temp_file" 2>/dev/null || write_status=$?
  fi
  if (( write_status == 0 )); then
    if (( _AI_CANDY_HAS_ZSH_FILE_BUILTINS )); then
      builtin zf_mv -f "$temp_file" "$cache_file" 2>/dev/null || write_status=$?
    else
      command mv -f "$temp_file" "$cache_file" 2>/dev/null || write_status=$?
    fi
  fi

  (( write_status == 0 )) || _ai_candy_cache_remove_path "$temp_file"
  return "$write_status"
}

function _ai_candy_cache_write() {
  local cache_file="$1"
  local content="$2"
  local max_wait_ticks="${3:-${_AI_CANDY_CACHE_COMMIT_WAIT_TICKS:-250}}"
  local expected_epoch="${4:-}"
  local lock_dir="${cache_file}.lock.d"
  local write_status=0

  (( _AI_CANDY_CACHE_READY )) || return 1
  _ai_candy_cache_lock_acquire "$_AI_CANDY_CACHE_COMMIT_LOCK" \
    "$_AI_CANDY_CACHE_COMMIT_STALE_AFTER" "$max_wait_ticks" || return 1
  if [[ -n "$expected_epoch" ]] && \
     ! _ai_candy_cache_persistence_epoch_matches "$expected_epoch"; then
    _ai_candy_cache_lock_release "$_AI_CANDY_CACHE_COMMIT_LOCK"
    return 1
  fi
  if ! _ai_candy_cache_lock_acquire "$lock_dir" 300 "$max_wait_ticks"; then
    _ai_candy_cache_lock_release "$_AI_CANDY_CACHE_COMMIT_LOCK"
    return 1
  fi
  {
    _ai_candy_cache_atomic_write_unlocked "$cache_file" "$content" || write_status=$?
  } always {
    _ai_candy_cache_lock_release "$lock_dir"
    _ai_candy_cache_lock_release "$_AI_CANDY_CACHE_COMMIT_LOCK"
  }
  return "$write_status"
}

function _ai_candy_hex_encode() {
  emulate -L zsh
  local LC_ALL=C
  local input="$1"
  local byte
  local -a input_bytes byte_codes
  REPLY=""

  input_bytes=("${(@s::)input}")
  for byte in "${input_bytes[@]}"; do
    byte_codes+=($(( #byte )))
  done
  (( ${#byte_codes} )) && builtin printf -v REPLY '%02X' "${byte_codes[@]}"
}

function _ai_candy_hex_decode() {
  emulate -L zsh
  setopt localoptions extendedglob
  local encoded="$1"
  local escaped=""
  REPLY=""

  [[ "$encoded" != *[^0-9A-Fa-f]* && $(( ${#encoded} % 2 )) -eq 0 ]] || return 1
  escaped="${encoded//(#b)(??)/\\x${match[1]}}"
  builtin printf -v REPLY '%b' "$escaped"
}

function _ai_candy_cache_read_size_checked_file() {
  emulate -L zsh
  local LC_ALL=C
  local cache_file="$1"
  local content=""
  local -a metadata
  REPLY=""

  [[ -f "$cache_file" && ! -L "$cache_file" ]] || return 1
  (( _AI_CANDY_HAS_ZSH_STAT_BUILTIN )) || return 2
  builtin zstat -A metadata +size -- "$cache_file" 2>/dev/null || return 2
  [[ "${metadata[1]-}" == <-> ]] || return 2
  _ai_candy_cache_file_limit_bytes
  (( metadata[1] <= REPLY )) || return 2
  content="$(<"$cache_file")"
  _ai_candy_cache_file_limit_bytes
  (( ${#content} <= REPLY )) || return 2
  REPLY="$content"
}

function _ai_candy_cache_read_small_file() {
  emulate -L zsh
  local cache_file="$1"
  REPLY=""

  if (( _AI_CANDY_HAS_ZSH_STAT_BUILTIN )); then
    _ai_candy_cache_read_size_checked_file "$cache_file"
    return $?
  fi
  _ai_candy_cache_read_bounded_file "$cache_file"
}

function _ai_candy_cache_read_bounded_file() {
  emulate -L zsh
  local LC_ALL=C
  local cache_file="$1"
  local content=""
  integer read_status=0
  REPLY=""

  [[ -f "$cache_file" && ! -L "$cache_file" ]] || return 1
  if (( _AI_CANDY_HAS_ZSH_STAT_BUILTIN )); then
    local -a metadata
    builtin zstat -A metadata +size -- "$cache_file" 2>/dev/null || return 2
    [[ "${metadata[1]-}" == <-> ]] || return 2
    _ai_candy_cache_file_limit_bytes
    (( metadata[1] <= REPLY )) || return 2
  fi
  if (( ! _AI_CANDY_HAS_TIMEOUT )); then
    _ai_candy_cache_read_size_checked_file "$cache_file"
    return $?
  fi

  _ai_candy_cache_file_limit_bytes
  local _AI_CANDY_TIMEOUT_OUTPUT_MAX_BYTES="$REPLY"
  content=$(_ai_candy_run_with_timeout "${_AI_CANDY_CACHE_IO_TIMEOUT:-0.75}" \
    /bin/cat "$cache_file" 2>/dev/null) || read_status=$?
  (( read_status == 0 )) || return 2
  _ai_candy_cache_file_limit_bytes
  (( ${#content} <= REPLY )) || return 2
  REPLY="$content"
}

function _ai_candy_cache_hex_field_is_valid() {
  emulate -L zsh
  local encoded="$1"
  [[ -n "$encoded" && "$encoded" != *[^0-9A-Fa-f]* ]] || return 1
  (( ${#encoded} % 2 == 0 ))
}

function _ai_candy_cache_operation_token_is_valid() {
  emulate -L zsh
  local token="$1"
  local -a fields=("${(@s.:.)token}")

  (( ${#fields} == 3 )) || return 1
  [[ "${fields[1]}" == "v3" ]] || return 1
  _ai_candy_cache_hex_field_is_valid "${fields[2]}" || return 1
  [[ "${fields[3]}" == <-> ]] || return 1
  (( ${#fields[3]} <= 18 && fields[3] >= 1 ))
}

function _ai_candy_cache_record_is_valid() {
  emulate -L zsh
  local record_kind="$1"
  local line="$2"
  local -a fields=("${(@s:|:)line}")

  case "$record_kind" in
    persistent)
      (( ${#fields} == 3 )) || return 1
      _ai_candy_cache_hex_field_is_valid "${fields[1]}" || return 1
      [[ -z "${fields[2]}" ]] || \
        _ai_candy_cache_hex_field_is_valid "${fields[2]}" || return 1
      _ai_candy_cache_timestamp_is_valid "${fields[3]}"
      ;;
    operation)
      (( ${#fields} == 4 )) || return 1
      _ai_candy_cache_hex_field_is_valid "${fields[1]}" || return 1
      _ai_candy_cache_operation_token_is_valid "${fields[2]}" || return 1
      [[ "${fields[3]}" == "set" || "${fields[3]}" == "delete" ]] || return 1
      _ai_candy_cache_timestamp_field_is_valid "${fields[4]}"
      ;;
    *)
      return 1
      ;;
  esac
}

function _ai_candy_cache_read_validated_lines() {
  emulate -L zsh
  local LC_ALL=C
  local cache_file="$1"
  local record_kind="$2"
  local content line
  local -a lines
  integer max_lines=${_AI_CANDY_FILE_CACHE_MAX_LINES:-500}
  reply=()

  (( max_lines >= 1 && max_lines <= 2000 )) || max_lines=500
  _ai_candy_cache_read_bounded_file "$cache_file" || return $?
  content="$REPLY"
  [[ -n "$content" ]] || return 0
  lines=("${(@f)content}")
  (( ${#lines} <= max_lines )) || return 2
  _ai_candy_cache_line_limit_bytes
  local max_line_bytes="$REPLY"
  for line in "${lines[@]}"; do
    (( ${#line} <= max_line_bytes )) || return 2
    _ai_candy_cache_record_is_valid "$record_kind" "$line" || return 2
  done
  reply=("${lines[@]}")
}

function _ai_candy_cache_join_bounded_lines() {
  emulate -L zsh
  local LC_ALL=C
  local record_kind="$1"
  shift
  local -a lines=("$@")
  local line content
  integer max_lines=${_AI_CANDY_FILE_CACHE_MAX_LINES:-500}
  REPLY=""

  (( max_lines >= 1 && max_lines <= 2000 )) || max_lines=500
  _ai_candy_cache_line_limit_bytes
  local max_line_bytes="$REPLY"
  for line in "${lines[@]}"; do
    (( ${#line} <= max_line_bytes )) || return 1
    _ai_candy_cache_record_is_valid "$record_kind" "$line" || return 1
  done
  if [[ "$record_kind" == operation ]]; then
    (( ${#lines} <= max_lines )) || return 1
    content="${(F)lines}"
    _ai_candy_cache_file_limit_bytes
    (( ${#content} + 1 <= REPLY )) || return 1
  else
    while (( ${#lines} > max_lines )); do
      lines=("${lines[@]:1}")
    done
    while (( ${#lines} )); do
      content="${(F)lines}"
      _ai_candy_cache_file_limit_bytes
      (( ${#content} + 1 <= REPLY )) && break
      lines=("${lines[@]:1}")
    done
  fi
  (( ${#lines} )) || return 1
  REPLY="$content"
  reply=("${lines[@]}")
}

function _ai_candy_cache_get_line_by_prefix() {
  emulate -L zsh
  local cache_file="$1"
  local prefix="$2"
  local record_kind="$3"
  local prefix_len=${#prefix}
  local -a lines
  local entry
  integer index
  REPLY=""

  _ai_candy_cache_read_validated_lines "$cache_file" "$record_kind" || return $?
  lines=("${reply[@]}")
  for (( index=${#lines}; index>=1; index-- )); do
    entry="${lines[index]}"
    if [[ "${entry[1,prefix_len]}" == "$prefix" ]]; then
      REPLY="$entry"
      return 0
    fi
  done
  return 1
}

function _ai_candy_cache_update_line_by_prefix() {
  emulate -L zsh
  local cache_file="$1"
  local prefix="$2"
  local new_line="$3"
  local max_wait_ticks="${4:-${_AI_CANDY_CACHE_OPERATION_WAIT_TICKS:-200}}"
  local prefix_len=${#prefix}
  local lock_dir="${cache_file}.lock.d"
  local -a lines new_lines
  local entry content
  local write_status=0 read_status=0

  (( _AI_CANDY_CACHE_READY )) || return 1
  _ai_candy_cache_record_is_valid persistent "$new_line" || return 1
  _ai_candy_cache_lock_acquire "$lock_dir" 300 "$max_wait_ticks" || return 1
  {
    if [[ -f "$cache_file" ]]; then
      _ai_candy_cache_read_validated_lines "$cache_file" persistent || read_status=$?
      (( read_status == 0 )) && lines=("${reply[@]}")
      for entry in "${lines[@]}"; do
        [[ "${entry[1,prefix_len]}" == "$prefix" ]] || new_lines+=("$entry")
      done
    fi
    new_lines+=("$new_line")
    if _ai_candy_cache_join_bounded_lines persistent "${new_lines[@]}"; then
      content="$REPLY"
      _ai_candy_cache_atomic_write_unlocked "$cache_file" "$content" || write_status=$?
    else
      write_status=1
    fi
  } always {
    _ai_candy_cache_lock_release "$lock_dir"
  }
  return "$write_status"
}

function _ai_candy_cache_remove_line_by_prefix() {
  emulate -L zsh
  local cache_file="$1"
  local prefix="$2"
  local prefix_len=${#prefix}
  local lock_dir="${cache_file}.lock.d"
  local -a lines new_lines
  local entry content
  local write_status=0 read_status=0

  [[ -e "$cache_file" || -L "$cache_file" ]] || return 0
  [[ -f "$cache_file" && ! -L "$cache_file" ]] || return 1
  _ai_candy_cache_lock_acquire "$lock_dir" 300 200 || return 1
  {
    _ai_candy_cache_read_validated_lines "$cache_file" persistent || read_status=$?
    if (( read_status == 0 )); then
      lines=("${reply[@]}")
      for entry in "${lines[@]}"; do
        [[ "${entry[1,prefix_len]}" == "$prefix" ]] || new_lines+=("$entry")
      done
      if (( ${#new_lines} )); then
        _ai_candy_cache_join_bounded_lines persistent "${new_lines[@]}" || write_status=$?
        (( write_status )) || content="$REPLY"
        (( write_status )) || \
          _ai_candy_cache_atomic_write_unlocked "$cache_file" "$content" || write_status=$?
      else
        _ai_candy_cache_remove_path "$cache_file" || write_status=$?
      fi
    else
      _ai_candy_cache_remove_path "$cache_file" || write_status=$?
    fi
  } always {
    _ai_candy_cache_lock_release "$lock_dir"
  }
  return "$write_status"
}

# ============================================================================
# SESSION MEMORY CACHE
# ============================================================================

typeset -gA _AI_CANDY_MEM_CACHE_GIT_ROOT
typeset -gA _AI_CANDY_MEM_CACHE_GIT_ROOT_GENERATION
typeset -gA _AI_CANDY_MEM_CACHE_GIT_HIERARCHY
typeset -gA _AI_CANDY_MEM_CACHE_GH_PR
typeset -gA _AI_CANDY_MEM_CACHE_TOMBSTONES
typeset -g _AI_CANDY_MEM_CACHE_MAX_ENTRIES=100
typeset -g _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD=120

function _ai_candy_mem_cache_remove_key() {
  emulate -L zsh
  local cache_name="$1"
  local remove_key="$2"
  local candidate
  local -A kept kept_generation

  case "$cache_name" in
    git_root)
      for candidate in "${(@k)_AI_CANDY_MEM_CACHE_GIT_ROOT}"; do
        [[ "$candidate" == "$remove_key" ]] || \
          kept[$candidate]="${_AI_CANDY_MEM_CACHE_GIT_ROOT[$candidate]}"
      done
      _AI_CANDY_MEM_CACHE_GIT_ROOT=("${(@kv)kept}")
      for candidate in "${(@k)_AI_CANDY_MEM_CACHE_GIT_ROOT_GENERATION}"; do
        [[ "$candidate" == "$remove_key" ]] || \
          kept_generation[$candidate]="${_AI_CANDY_MEM_CACHE_GIT_ROOT_GENERATION[$candidate]}"
      done
      _AI_CANDY_MEM_CACHE_GIT_ROOT_GENERATION=("${(@kv)kept_generation}")
      ;;
    git_hierarchy)
      for candidate in "${(@k)_AI_CANDY_MEM_CACHE_GIT_HIERARCHY}"; do
        [[ "$candidate" == "$remove_key" ]] || \
          kept[$candidate]="${_AI_CANDY_MEM_CACHE_GIT_HIERARCHY[$candidate]}"
      done
      _AI_CANDY_MEM_CACHE_GIT_HIERARCHY=("${(@kv)kept}")
      ;;
    gh_pr)
      for candidate in "${(@k)_AI_CANDY_MEM_CACHE_GH_PR}"; do
        [[ "$candidate" == "$remove_key" ]] || \
          kept[$candidate]="${_AI_CANDY_MEM_CACHE_GH_PR[$candidate]}"
      done
      _AI_CANDY_MEM_CACHE_GH_PR=("${(@kv)kept}")
      ;;
    tombstone)
      for candidate in "${(@k)_AI_CANDY_MEM_CACHE_TOMBSTONES}"; do
        [[ "$candidate" == "$remove_key" ]] || \
          kept[$candidate]="${_AI_CANDY_MEM_CACHE_TOMBSTONES[$candidate]}"
      done
      _AI_CANDY_MEM_CACHE_TOMBSTONES=("${(@kv)kept}")
      ;;
    git_options)
      for candidate in "${(@k)_AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT}"; do
        [[ "$candidate" == "$remove_key" ]] || \
          kept[$candidate]="${_AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT[$candidate]}"
      done
      _AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT=("${(@kv)kept}")
      ;;
    git_remote)
      for candidate in "${(@k)_AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT}"; do
        [[ "$candidate" == "$remove_key" ]] || \
          kept[$candidate]="${_AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT[$candidate]}"
      done
      _AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT=("${(@kv)kept}")
      ;;
    git_snapshot_retry)
      for candidate in "${(@k)_AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT}"; do
        [[ "$candidate" == "$remove_key" ]] || \
          kept[$candidate]="${_AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT[$candidate]}"
      done
      _AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT=("${(@kv)kept}")
      ;;
    git_config_graph_timeout)
      for candidate in "${(@k)_AI_CANDY_GIT_CONFIG_GRAPH_TIMEOUT_BY_KEY}"; do
        [[ "$candidate" == "$remove_key" ]] || \
          kept[$candidate]="${_AI_CANDY_GIT_CONFIG_GRAPH_TIMEOUT_BY_KEY[$candidate]}"
      done
      _AI_CANDY_GIT_CONFIG_GRAPH_TIMEOUT_BY_KEY=("${(@kv)kept}")
      ;;
    git_stash)
      for candidate in "${(@k)_AI_CANDY_GIT_STASH_COUNT_BY_LOG}"; do
        [[ "$candidate" == "$remove_key" ]] || \
          kept[$candidate]="${_AI_CANDY_GIT_STASH_COUNT_BY_LOG[$candidate]}"
      done
      _AI_CANDY_GIT_STASH_COUNT_BY_LOG=("${(@kv)kept}")
      ;;
    refresh)
      for candidate in "${(@k)_AI_CANDY_REFRESH_REQUESTED}"; do
        [[ "$candidate" == "$remove_key" ]] || \
          kept[$candidate]="${_AI_CANDY_REFRESH_REQUESTED[$candidate]}"
      done
      _AI_CANDY_REFRESH_REQUESTED=("${(@kv)kept}")
      ;;
    *) return 1 ;;
  esac
}

function _ai_candy_mem_cache_cleanup() {
  emulate -L zsh
  local cache_name="$1"
  local max_entries=${_AI_CANDY_MEM_CACHE_MAX_ENTRIES:-100}
  local threshold=${_AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD:-120}
  local -a keys entries sorted
  local key value timestamp entry remove_key
  integer count to_remove index

  case "$cache_name" in
    git_root) keys=("${(@k)_AI_CANDY_MEM_CACHE_GIT_ROOT}") ;;
    git_hierarchy) keys=("${(@k)_AI_CANDY_MEM_CACHE_GIT_HIERARCHY}") ;;
    gh_pr) keys=("${(@k)_AI_CANDY_MEM_CACHE_GH_PR}") ;;
    tombstone) keys=("${(@k)_AI_CANDY_MEM_CACHE_TOMBSTONES}") ;;
    git_options) keys=("${(@k)_AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT}") ;;
    git_remote) keys=("${(@k)_AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT}") ;;
    git_snapshot_retry) keys=("${(@k)_AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT}") ;;
    git_stash) keys=("${(@k)_AI_CANDY_GIT_STASH_COUNT_BY_LOG}") ;;
    refresh) keys=("${(@k)_AI_CANDY_REFRESH_REQUESTED}") ;;
    *) return 1 ;;
  esac

  count=${#keys}
  (( count > threshold )) || return 0
  for key in "${keys[@]}"; do
    case "$cache_name" in
      git_root) value="${_AI_CANDY_MEM_CACHE_GIT_ROOT[$key]-}" ;;
      git_hierarchy) value="${_AI_CANDY_MEM_CACHE_GIT_HIERARCHY[$key]-}" ;;
      gh_pr) value="${_AI_CANDY_MEM_CACHE_GH_PR[$key]-}" ;;
      tombstone) value="${_AI_CANDY_MEM_CACHE_TOMBSTONES[$key]-}" ;;
      git_options) value="${_AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT[$key]-}" ;;
      git_remote) value="${_AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT[$key]-}" ;;
      git_snapshot_retry) value="${_AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT[$key]-}" ;;
      git_stash) value="${_AI_CANDY_GIT_STASH_COUNT_BY_LOG[$key]-}" ;;
      refresh) value="${_AI_CANDY_REFRESH_REQUESTED[$key]-}" ;;
    esac
    timestamp="${value##*|}"
    _ai_candy_cache_timestamp_is_valid "$timestamp" || timestamp=0
    entries+=("${timestamp}|${key}")
  done

  sorted=("${(@on)entries}")
  to_remove=$(( count - max_entries ))
  for (( index=1; index<=to_remove; index++ )); do
    entry="${sorted[index]}"
    remove_key="${entry#*|}"
    _ai_candy_mem_cache_remove_key "$cache_name" "$remove_key"
  done
}

# ============================================================================
# LAZY PERSISTENT CACHE
# ============================================================================

typeset -g _AI_CANDY_CACHE_DB_FILE="${_AI_CANDY_CACHE_DIR}/prompt_cache.db"
typeset -g _AI_CANDY_CACHE_BACKEND_OWNER_FILE="${_AI_CANDY_CACHE_DIR}/persistent_backend"
typeset -g _AI_CANDY_CACHE_BACKEND_STATE=0
typeset -g _AI_CANDY_CACHE_BACKEND="none"
typeset -g _AI_CANDY_CACHE_IO_TIMEOUT=0.75
typeset -g _AI_CANDY_CACHE_PROMPT_IO_TIMEOUT=0.05
typeset -gF _AI_CANDY_CACHE_BACKEND_RETRY_AFTER=0
typeset -gF _AI_CANDY_CACHE_BACKEND_RETRY_DELAY=1
typeset -g _AI_CANDY_CACHE_OPERATION_FILE="${_AI_CANDY_CACHE_DIR}/persist_operations"
typeset -g _AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE="${_AI_CANDY_CACHE_DIR}/persist_sequence"
typeset -g _AI_CANDY_CACHE_PERSISTENCE_EPOCH_FILE="${_AI_CANDY_CACHE_DIR}/persistent_epoch"
typeset -g _AI_CANDY_CACHE_COMMIT_LOCK="${_AI_CANDY_CACHE_DIR}/persist_commit.lock.d"
typeset -g _AI_CANDY_CACHE_COMMIT_STALE_AFTER=15
typeset -g _AI_CANDY_CACHE_COMMIT_WAIT_TICKS=250
typeset -g _AI_CANDY_CACHE_OPERATION_WAIT_TICKS=200
typeset -g _AI_CANDY_CACHE_OPERATION_RESERVE_WAIT_TICKS=2
typeset -g _AI_CANDY_CACHE_OPERATION_DELETE_WAIT_TICKS=5
typeset -g _AI_CANDY_CACHE_OPERATION_SEQUENCE_MAX=999999999999999999
typeset -g _AI_CANDY_CACHE_GENERATION_TOKEN_COUNTER=0

function _ai_candy_cache_generation_token_is_valid() {
  emulate -L zsh
  local epoch="$1"
  local -a fields
  local field

  if [[ "$epoch" == <-> ]]; then
    (( ${#epoch} <= _AI_CANDY_CACHE_TIMESTAMP_MAX_DIGITS ))
    return $?
  fi
  fields=("${(@s.:.)epoch}")
  (( ${#fields} == 5 )) || return 1
  [[ "${fields[1]}" == "v1" ]] || return 1
  [[ "${fields[2]}" == <-> || "${fields[2]}" == <->.<-> ]] || return 1
  (( ${#fields[2]} <= 24 )) || return 1
  [[ "${fields[3]}" == <-> && "${fields[4]}" == <-> && \
     "${fields[5]}" == <-> ]] || return 1
  for field in "${fields[@]:2}"; do
    (( ${#field} <= 20 )) || return 1
  done
}

function _ai_candy_cache_operation_sequence_state_is_valid() {
  emulate -L zsh
  local state="$1"
  local -a fields=("${(@s:|:)state}")

  (( ${#fields} == 2 )) || return 1
  _ai_candy_cache_generation_token_is_valid "${fields[1]}" || return 1
  [[ "${fields[2]}" == <-> ]] || return 1
  (( ${#fields[2]} <= 18 ))
}

function _ai_candy_cache_read_persistence_epoch() {
  REPLY=0
  if [[ ! -e "$_AI_CANDY_CACHE_PERSISTENCE_EPOCH_FILE" && \
        ! -L "$_AI_CANDY_CACHE_PERSISTENCE_EPOCH_FILE" ]]; then
    return 0
  fi
  [[ -f "$_AI_CANDY_CACHE_PERSISTENCE_EPOCH_FILE" && \
     ! -L "$_AI_CANDY_CACHE_PERSISTENCE_EPOCH_FILE" ]] || return 1
  _ai_candy_cache_read_small_file "$_AI_CANDY_CACHE_PERSISTENCE_EPOCH_FILE" || return 1
  local epoch="$REPLY"
  _ai_candy_cache_generation_token_is_valid "$epoch" || return 1
  REPLY="$epoch"
}

function _ai_candy_cache_persistence_epoch_matches() {
  local expected_epoch="$1"
  _ai_candy_cache_generation_token_is_valid "$expected_epoch" || return 1
  _ai_candy_cache_read_persistence_epoch || return 1
  [[ "$REPLY" == "$expected_epoch" ]]
}

function _ai_candy_cache_new_generation_token() {
  (( ++_AI_CANDY_CACHE_GENERATION_TOKEN_COUNTER ))
  local clock="${EPOCHREALTIME:-${EPOCHSECONDS:-0}.0}"
  local owner_pid="${sysparams[pid]-$$}"
  REPLY="v1:${clock}:${owner_pid}:${_AI_CANDY_CACHE_GENERATION_TOKEN_COUNTER}:${RANDOM}"
  _ai_candy_cache_generation_token_is_valid "$REPLY"
}

function _ai_candy_cache_advance_persistence_epoch_unlocked() {
  if [[ -e "$_AI_CANDY_CACHE_PERSISTENCE_EPOCH_FILE" || \
        -L "$_AI_CANDY_CACHE_PERSISTENCE_EPOCH_FILE" ]]; then
    [[ -f "$_AI_CANDY_CACHE_PERSISTENCE_EPOCH_FILE" && \
       ! -L "$_AI_CANDY_CACHE_PERSISTENCE_EPOCH_FILE" ]] || return 1
  fi
  _ai_candy_cache_new_generation_token || return 1
  local next_epoch="$REPLY"
  _ai_candy_cache_atomic_write_unlocked "$_AI_CANDY_CACHE_PERSISTENCE_EPOCH_FILE" \
    "$next_epoch" || return 1
  REPLY="$next_epoch"
}

function _ai_candy_cache_file_backend_artifact_exists() {
  local cache_file
  for cache_file in \
    "${_AI_CANDY_CACHE_DIR}/git_root_cache" \
    "${_AI_CANDY_CACHE_DIR}/git_hierarchy_cache" \
    "${_AI_CANDY_CACHE_DIR}/gh_pr_cache"; do
    [[ -e "$cache_file" || -L "$cache_file" ]] && return 0
  done
  return 1
}

function _ai_candy_cache_persistent_artifact_exists() {
  [[ -e "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" || -L "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" || \
     -e "$_AI_CANDY_CACHE_DB_FILE" || -L "$_AI_CANDY_CACHE_DB_FILE" ]] || \
    _ai_candy_cache_file_backend_artifact_exists
}

function _ai_candy_cache_file_backend_is_safe() {
  local cache_file
  for cache_file in \
    "${_AI_CANDY_CACHE_DIR}/git_root_cache" \
    "${_AI_CANDY_CACHE_DIR}/git_hierarchy_cache" \
    "${_AI_CANDY_CACHE_DIR}/gh_pr_cache"; do
    [[ ! -L "$cache_file" ]] || return 1
    [[ ! -e "$cache_file" || -f "$cache_file" ]] || return 1
  done
  return 0
}

function _ai_candy_cache_read_backend_owner() {
  REPLY=""
  [[ -f "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" && \
     ! -L "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" ]] || return 1
  _ai_candy_cache_read_small_file "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" || return 1
  local owner="$REPLY"
  [[ "$owner" == "sqlite" || "$owner" == "file" ]] || return 1
  REPLY="$owner"
}

function _ai_candy_cache_operation_is_current() {
  emulate -L zsh
  local hex_key="$1"
  local token="$2"
  local prefix="${hex_key}|"
  local -a fields
  integer read_status=0

  _ai_candy_cache_get_line_by_prefix \
    "$_AI_CANDY_CACHE_OPERATION_FILE" "$prefix" operation || read_status=$?
  (( read_status == 0 )) || return "$read_status"
  fields=("${(@s:|:)REPLY}")
  [[ "${fields[2]}" == "$token" ]]
}

function _ai_candy_cache_clear_operation_if_current_unlocked() {
  emulate -L zsh
  local hex_key="$1"
  local token="$2"
  local expected_epoch="$3"
  local prefix="${hex_key}|"
  local -a lines kept fields
  local line content
  integer removed=0 write_status=0 read_status=0

  [[ -e "$_AI_CANDY_CACHE_OPERATION_FILE" || -L "$_AI_CANDY_CACHE_OPERATION_FILE" ]] || return 0
  [[ -f "$_AI_CANDY_CACHE_OPERATION_FILE" && ! -L "$_AI_CANDY_CACHE_OPERATION_FILE" ]] || return 1
  if ! _ai_candy_cache_persistence_epoch_matches "$expected_epoch"; then
    write_status=1
  else
    _ai_candy_cache_read_validated_lines \
      "$_AI_CANDY_CACHE_OPERATION_FILE" operation || read_status=$?
  fi
  if (( write_status == 0 && read_status == 0 )); then
    lines=("${reply[@]}")
    for line in "${lines[@]}"; do
      if [[ "${line[1,${#prefix}]}" == "$prefix" ]]; then
        fields=("${(@s:|:)line}")
        if [[ "${fields[2]}" == "$token" ]]; then
          removed=1
          continue
        fi
      fi
      kept+=("$line")
    done
    if (( removed )); then
      if (( ${#kept} )); then
        if _ai_candy_cache_join_bounded_lines operation "${kept[@]}"; then
          content="$REPLY"
          _ai_candy_cache_atomic_write_unlocked \
            "$_AI_CANDY_CACHE_OPERATION_FILE" "$content" || write_status=$?
        else
          write_status=1
        fi
      else
        _ai_candy_cache_remove_path "$_AI_CANDY_CACHE_OPERATION_FILE" || write_status=$?
      fi
    fi
  elif (( write_status == 0 )); then
    write_status="$read_status"
  fi
  return "$write_status"
}

function _ai_candy_cache_clear_operation_if_current() {
  emulate -L zsh
  local max_wait_ticks="${4:-${_AI_CANDY_CACHE_OPERATION_WAIT_TICKS:-200}}"
  local lock_dir="${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d"
  integer clear_status=0

  _ai_candy_cache_lock_acquire "$lock_dir" 300 "$max_wait_ticks" || return 1
  {
    _ai_candy_cache_clear_operation_if_current_unlocked "$1" "$2" "$3" || \
      clear_status=$?
  } always {
    _ai_candy_cache_lock_release "$lock_dir"
  }
  return "$clear_status"
}

function _ai_candy_cache_reserve_operation_unlocked() {
  emulate -L zsh
  local action="$1"
  local cache_name="$2"
  local key="$3"
  local now="$4"
  local namespaced_key="${cache_name}:${key}"
  local expected_epoch=""
  local sequence_epoch=""
  local epoch_hex=""
  local token=""
  local line content sequence_content
  local -a lines current_lines new_lines fields sequence_fields token_fields
  integer reserve_status=0 sequence=0 line_sequence=0 reset_lines=0

  reply=()

  [[ "$action" == "set" || "$action" == "delete" ]] || return 1
  _ai_candy_cache_timestamp_is_valid "$now" || return 1
  _ai_candy_hex_encode "$namespaced_key"
  local hex_key="$REPLY"
  local prefix="${hex_key}|"

  if _ai_candy_cache_read_persistence_epoch; then
    expected_epoch="$REPLY"
  else
    reserve_status=1
  fi

  if (( reserve_status == 0 )) && \
     [[ -e "$_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE" || \
        -L "$_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE" ]]; then
    if [[ ! -f "$_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE" || \
          -L "$_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE" ]]; then
      reserve_status=1
    elif _ai_candy_cache_read_small_file "$_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE" && \
         _ai_candy_cache_operation_sequence_state_is_valid "$REPLY"; then
      sequence_fields=("${(@s:|:)REPLY}")
      sequence_epoch="${sequence_fields[1]}"
      if [[ "$sequence_epoch" == "$expected_epoch" ]]; then
        sequence="${sequence_fields[2]}"
      else
        reset_lines=1
      fi
    fi
  fi

  if (( reserve_status == 0 )) && \
     [[ -e "$_AI_CANDY_CACHE_OPERATION_FILE" || -L "$_AI_CANDY_CACHE_OPERATION_FILE" ]]; then
    if [[ ! -f "$_AI_CANDY_CACHE_OPERATION_FILE" || -L "$_AI_CANDY_CACHE_OPERATION_FILE" ]]; then
      reserve_status=1
    elif (( ! reset_lines )); then
      if _ai_candy_cache_read_validated_lines \
           "$_AI_CANDY_CACHE_OPERATION_FILE" operation; then
        lines=("${reply[@]}")
      else
        reserve_status=$?
      fi
    fi
  fi

  if (( reserve_status == 0 )); then
    _ai_candy_hex_encode "$expected_epoch"
    epoch_hex="$REPLY"
    if (( reset_lines )); then
      lines=()
    else
      for line in "${lines[@]}"; do
        fields=("${(@s:|:)line}")
        token_fields=("${(@s.:.)fields[2]}")
        if [[ "${token_fields[2]}" == "$epoch_hex" ]]; then
          current_lines+=("$line")
          line_sequence="${token_fields[3]}"
          (( line_sequence > sequence )) && sequence="$line_sequence"
        fi
      done
      lines=("${current_lines[@]}")
    fi
    if (( sequence >= _AI_CANDY_CACHE_OPERATION_SEQUENCE_MAX )); then
      reserve_status=1
    else
      (( sequence++ ))
      token="v3:${epoch_hex}:${sequence}"
      for line in "${lines[@]}"; do
        [[ "${line[1,${#prefix}]}" == "$prefix" ]] || new_lines+=("$line")
      done
      new_lines+=("${hex_key}|${token}|${action}|${now}")
      if _ai_candy_cache_join_bounded_lines operation "${new_lines[@]}"; then
        content="$REPLY"
        sequence_content="${expected_epoch}|${sequence}"
        _ai_candy_cache_atomic_write_unlocked \
          "$_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE" "$sequence_content" || \
          reserve_status=$?
        if (( reserve_status == 0 )); then
          _ai_candy_cache_atomic_write_unlocked \
            "$_AI_CANDY_CACHE_OPERATION_FILE" "$content" || reserve_status=$?
        fi
      else
        reserve_status=1
      fi
    fi
  fi
  (( reserve_status == 0 )) || return "$reserve_status"
  reply=("$hex_key" "$token" "$expected_epoch")
}

function _ai_candy_cache_reserve_operation() {
  emulate -L zsh
  local lock_dir="${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d"
  integer reserve_status=0

  _ai_candy_cache_lock_acquire "$lock_dir" 300 \
    "$_AI_CANDY_CACHE_OPERATION_RESERVE_WAIT_TICKS" || return 1
  {
    _ai_candy_cache_reserve_operation_unlocked "$@" || reserve_status=$?
  } always {
    _ai_candy_cache_lock_release "$lock_dir"
  }
  return "$reserve_status"
}

function _ai_candy_cache_commit_operation() {
  local action="$1"
  local cache_name="$2"
  local key="$3"
  local value="$4"
  local timestamp="$5"
  local hex_key="$6"
  local token="$7"
  local expected_epoch="$8"
  integer commit_status=0 operation_status=0 was_current=0

  _ai_candy_cache_lock_acquire "$_AI_CANDY_CACHE_COMMIT_LOCK" \
    "$_AI_CANDY_CACHE_COMMIT_STALE_AFTER" "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" || return 1
  {
    if ! _ai_candy_cache_persistence_epoch_matches "$expected_epoch"; then
      commit_status=1
    elif _ai_candy_cache_operation_is_current "$hex_key" "$token"; then
      was_current=1
      if [[ "$action" == "set" ]]; then
        _ai_candy_cache_persist_write_unlocked "$cache_name" "$key" "$value" "$timestamp" || \
          commit_status=$?
      else
        _ai_candy_cache_persist_delete_unlocked "$cache_name" "$key" || commit_status=$?
      fi
    else
      operation_status=$?
      (( operation_status == 1 )) || commit_status="$operation_status"
    fi
  } always {
    _ai_candy_cache_lock_release "$_AI_CANDY_CACHE_COMMIT_LOCK"
  }

  if (( was_current && commit_status == 0 )); then
    _ai_candy_cache_clear_operation_if_current \
      "$hex_key" "$token" "$expected_epoch" || commit_status=$?
  fi
  return "$commit_status"
}

function _ai_candy_cache_run_scheduled_operation() {
  local action="$1"
  local cache_name="$2"
  local key="$3"
  local value="$4"
  local timestamp="$5"
  local hex_key="$6"
  local token="$7"
  local persistence_epoch="$8"
  local operation_lock="${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d"

  _ai_candy_cache_lock_acquire "$operation_lock" 300 \
    "$_AI_CANDY_CACHE_OPERATION_WAIT_TICKS" || return 1
  _ai_candy_cache_lock_release "$operation_lock"

  if [[ "$_AI_CANDY_CACHE_BACKEND" == "none" ]]; then
    _AI_CANDY_CACHE_BACKEND_STATE=0
  fi
  _ai_candy_cache_commit_operation "$action" "$cache_name" "$key" "$value" \
    "$timestamp" "$hex_key" "$token" "$persistence_epoch"
}

function _ai_candy_cache_schedule_operation() {
  emulate -L zsh
  local action="$1"
  local cache_name="$2"
  local key="$3"
  local value="$4"
  local timestamp="$5"
  local now="${EPOCHSECONDS:-$timestamp}"
  local operation_lock="${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d"
  local reserve_wait_ticks="$_AI_CANDY_CACHE_OPERATION_RESERVE_WAIT_TICKS"
  local -a reservation
  integer schedule_status=0

  if [[ "$action" == "set" ]] && \
     ! _ai_candy_cache_value_is_within_limit "$value"; then
    return 1
  fi

  [[ "$action" == "delete" ]] && \
    reserve_wait_ticks="$_AI_CANDY_CACHE_OPERATION_DELETE_WAIT_TICKS"

  _ai_candy_cache_lock_acquire "$operation_lock" 300 \
    "$reserve_wait_ticks" || return 1
  {
    _ai_candy_cache_reserve_operation_unlocked \
      "$action" "$cache_name" "$key" "$now" || schedule_status=$?
    if (( schedule_status == 0 )); then
      reservation=("${reply[@]}")
      if (( ${#reservation} != 3 )); then
        schedule_status=1
      elif ! _ai_candy_start_registered_background_worker \
        _ai_candy_cache_run_scheduled_operation \
        "$action" "$cache_name" "$key" "$value" "$timestamp" \
        "${reservation[1]}" "${reservation[2]}" "${reservation[3]}"; then
        _ai_candy_cache_clear_operation_if_current_unlocked \
          "${reservation[1]}" "${reservation[2]}" "${reservation[3]}" || \
          builtin true
        schedule_status=1
      fi
    fi
  } always {
    _ai_candy_cache_lock_release "$operation_lock"
  }
  return "$schedule_status"
}

function _ai_candy_cache_backend_init_unlocked() {
  if (( _AI_CANDY_CACHE_BACKEND_STATE )); then
    if [[ "$_AI_CANDY_CACHE_BACKEND" == "none" ]]; then
      local -F current_clock="${EPOCHREALTIME:-${EPOCHSECONDS:-0}}"
      if (( ! ${_AI_CANDY_CACHE_FORCE_BACKEND_RETRY:-0} && \
            current_clock < _AI_CANDY_CACHE_BACKEND_RETRY_AFTER )); then
        return 1
      fi
      _AI_CANDY_CACHE_BACKEND_STATE=0
    fi
  fi
  if (( _AI_CANDY_CACHE_BACKEND_STATE )); then
    local cached_owner=""
    _ai_candy_cache_read_backend_owner && cached_owner="$REPLY"
    if [[ "$_AI_CANDY_CACHE_BACKEND" == "sqlite" && "$cached_owner" == "sqlite" && \
          -f "$_AI_CANDY_CACHE_DB_FILE" && ! -L "$_AI_CANDY_CACHE_DB_FILE" ]]; then
      return 0
    fi
    if [[ "$_AI_CANDY_CACHE_BACKEND" == "file" && "$cached_owner" == "file" ]] && \
       _ai_candy_cache_file_backend_is_safe; then
      return 0
    fi
    _AI_CANDY_CACHE_BACKEND_STATE=0
    _AI_CANDY_CACHE_BACKEND="none"
  fi

  _AI_CANDY_CACHE_BACKEND_STATE=1
  _AI_CANDY_CACHE_BACKEND="none"
  _AI_CANDY_CACHE_BACKEND_RETRY_AFTER=$(( \
    ${EPOCHREALTIME:-${EPOCHSECONDS:-0}} + _AI_CANDY_CACHE_BACKEND_RETRY_DELAY ))
  (( _AI_CANDY_CACHE_READY )) || return 1

  local owner=""
  if [[ -e "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" || -L "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" ]]; then
    _ai_candy_cache_read_backend_owner || return 1
    owner="$REPLY"
  else
    if [[ -e "$_AI_CANDY_CACHE_DB_FILE" || -L "$_AI_CANDY_CACHE_DB_FILE" ]]; then
      owner="sqlite"
    elif _ai_candy_cache_file_backend_artifact_exists; then
      owner="file"
    elif (( _AI_CANDY_HAS_SQLITE3 )); then
      owner="sqlite"
    else
      owner="file"
    fi

    [[ "$owner" != "sqlite" || ! -L "$_AI_CANDY_CACHE_DB_FILE" ]] || return 1
    [[ "$owner" != "file" ]] || _ai_candy_cache_file_backend_is_safe || return 1
    _ai_candy_cache_atomic_write_unlocked "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" "$owner" || return 1
  fi

  if [[ "$owner" == "sqlite" ]]; then
    (( _AI_CANDY_HAS_SQLITE3 )) || return 1
    [[ ! -L "$_AI_CANDY_CACHE_DB_FILE" && \
       ( ! -e "$_AI_CANDY_CACHE_DB_FILE" || -f "$_AI_CANDY_CACHE_DB_FILE" ) ]] || return 1
    if ! ( umask 077 && _ai_candy_run_with_timeout "$_AI_CANDY_CACHE_IO_TIMEOUT" \
          sqlite3 -batch -cmd '.timeout 500' "$_AI_CANDY_CACHE_DB_FILE" \
          'PRAGMA journal_mode=WAL;
           CREATE TABLE IF NOT EXISTS cache (
             key TEXT PRIMARY KEY,
             value TEXT NOT NULL,
             timestamp INTEGER NOT NULL
           );
           CREATE INDEX IF NOT EXISTS idx_cache_timestamp ON cache(timestamp);' \
          &>/dev/null ); then
      return 1
    fi
    _AI_CANDY_CACHE_BACKEND="sqlite"
    _AI_CANDY_CACHE_BACKEND_RETRY_AFTER=0
    _ai_candy_chmod 600 "$_AI_CANDY_CACHE_DB_FILE" 2>/dev/null
    return 0
  fi

  _ai_candy_cache_file_backend_is_safe || return 1
  _AI_CANDY_CACHE_BACKEND="file"
  _AI_CANDY_CACHE_BACKEND_RETRY_AFTER=0
  return 0
}

function _ai_candy_cache_backend_init() {
  local _AI_CANDY_CACHE_FORCE_BACKEND_RETRY=1
  local init_status=0

  _ai_candy_cache_lock_acquire "$_AI_CANDY_CACHE_COMMIT_LOCK" \
    "$_AI_CANDY_CACHE_COMMIT_STALE_AFTER" "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" || return 1
  {
    _ai_candy_cache_backend_init_unlocked || init_status=$?
  } always {
    _ai_candy_cache_lock_release "$_AI_CANDY_CACHE_COMMIT_LOCK"
  }
  return "$init_status"
}

function _ai_candy_cache_persist_read_unlocked() {
  emulate -L zsh
  local cache_name="$1"
  local key="$2"
  local namespaced_key="${cache_name}:${key}"
  local raw_output="" hex_value timestamp line prefix
  REPLY=""

  _ai_candy_hex_encode "$namespaced_key"
  local hex_key="$REPLY"
  local operation_prefix="${hex_key}|"
  local operation_status=0
  local operation_epoch=""
  local -a operation_fields operation_token_fields
  if _ai_candy_cache_get_line_by_prefix \
       "$_AI_CANDY_CACHE_OPERATION_FILE" "$operation_prefix" operation; then
    operation_fields=("${(@s:|:)REPLY}")
    operation_token_fields=("${(@s.:.)operation_fields[2]}")
    _ai_candy_cache_read_persistence_epoch || return 1
    operation_epoch="$REPLY"
    _ai_candy_hex_encode "$operation_epoch"
    [[ "${operation_token_fields[2]}" == "$REPLY" ]] && return 1
  else
    operation_status=$?
    (( operation_status == 1 )) || return 1
  fi
  _ai_candy_cache_backend_init_unlocked || return 1

  if [[ "$_AI_CANDY_CACHE_BACKEND" == "sqlite" ]]; then
    raw_output=$(_ai_candy_run_with_timeout "$_AI_CANDY_CACHE_IO_TIMEOUT" \
      sqlite3 -batch -noheader -cmd '.timeout 500' "$_AI_CANDY_CACHE_DB_FILE" \
      "SELECT hex(value) || '|' || timestamp FROM cache WHERE key = CAST(X'${hex_key}' AS TEXT) LIMIT 1;" \
      2>/dev/null) || return 1
    [[ -n "$raw_output" ]] || return 1
    hex_value="${raw_output%%|*}"
    timestamp="${raw_output#*|}"
  else
    local cache_file="${_AI_CANDY_CACHE_DIR}/${cache_name}_cache"
    prefix="${hex_key}|"
    _ai_candy_cache_get_line_by_prefix \
      "$cache_file" "$prefix" persistent || return 1
    line="$REPLY"
    local -a cache_fields=("${(@s:|:)line}")
    hex_value="${cache_fields[2]}"
    timestamp="${cache_fields[3]}"
  fi

  _ai_candy_cache_timestamp_is_valid "$timestamp" || return 1
  _ai_candy_cache_value_limit_bytes
  (( ${#hex_value} <= REPLY * 2 )) || return 1
  _ai_candy_hex_decode "$hex_value" || return 1
  REPLY="${REPLY}|${timestamp}"
  return 0
}

function _ai_candy_cache_persist_write_unlocked() {
  local LC_ALL=C
  local cache_name="$1"
  local key="$2"
  local value="$3"
  local timestamp="$4"
  local namespaced_key="${cache_name}:${key}"
  local hex_key hex_value
  local current_time="${EPOCHSECONDS:-}"

  _ai_candy_cache_timestamp_field_is_valid "$timestamp" || return 1
  _ai_candy_cache_timestamp_field_is_valid "$current_time" || return 1
  _ai_candy_cache_value_is_within_limit "$value" || return 1
  (( timestamp > current_time )) && timestamp="$current_time"
  _ai_candy_cache_backend_init_unlocked || return 1
  _ai_candy_hex_encode "$namespaced_key"
  hex_key="$REPLY"
  _ai_candy_hex_encode "$value"
  hex_value="$REPLY"

  if [[ "$_AI_CANDY_CACHE_BACKEND" == "sqlite" ]]; then
    _ai_candy_run_with_timeout "$_AI_CANDY_CACHE_IO_TIMEOUT" \
      sqlite3 -batch -cmd '.timeout 500' "$_AI_CANDY_CACHE_DB_FILE" \
      "INSERT OR REPLACE INTO cache (key, value, timestamp)
       VALUES (CAST(X'${hex_key}' AS TEXT), CAST(X'${hex_value}' AS TEXT), ${timestamp})
       ;" \
      &>/dev/null
  else
    local cache_file="${_AI_CANDY_CACHE_DIR}/${cache_name}_cache"
    local prefix="${hex_key}|"
    _ai_candy_cache_update_line_by_prefix "$cache_file" "$prefix" "${hex_key}|${hex_value}|${timestamp}"
  fi
}

function _ai_candy_cache_persist_delete_unlocked() {
  local cache_name="$1"
  local key="$2"
  local namespaced_key="${cache_name}:${key}"

  _ai_candy_cache_backend_init_unlocked || return 1
  _ai_candy_hex_encode "$namespaced_key"
  local hex_key="$REPLY"

  if [[ "$_AI_CANDY_CACHE_BACKEND" == "sqlite" ]]; then
    _ai_candy_run_with_timeout "$_AI_CANDY_CACHE_IO_TIMEOUT" \
      sqlite3 -batch -cmd '.timeout 500' "$_AI_CANDY_CACHE_DB_FILE" \
      "DELETE FROM cache WHERE key = CAST(X'${hex_key}' AS TEXT);" \
      &>/dev/null
  else
    local cache_file="${_AI_CANDY_CACHE_DIR}/${cache_name}_cache"
    _ai_candy_cache_remove_line_by_prefix "$cache_file" "${hex_key}|"
  fi
}

function _ai_candy_cache_persist_write() {
  local _AI_CANDY_CACHE_FORCE_BACKEND_RETRY=1
  local cache_name="$1"
  local key="$2"
  local value="$3"
  local timestamp="$4"
  local expected_epoch="${5:-}"
  local write_status=0

  _ai_candy_cache_lock_acquire "$_AI_CANDY_CACHE_COMMIT_LOCK" \
    "$_AI_CANDY_CACHE_COMMIT_STALE_AFTER" "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" || return 1
  {
    if [[ -n "$expected_epoch" ]] && \
       ! _ai_candy_cache_persistence_epoch_matches "$expected_epoch"; then
      write_status=1
    else
      _ai_candy_cache_persist_write_unlocked "$cache_name" "$key" "$value" \
        "$timestamp" || write_status=$?
    fi
  } always {
    _ai_candy_cache_lock_release "$_AI_CANDY_CACHE_COMMIT_LOCK"
  }
  return "$write_status"
}

function _ai_candy_cache_persist_read_with_waits() {
  local operation_wait_ticks="$1"
  local commit_wait_ticks="$2"
  shift 2
  local read_status=0
  local operation_lock="${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d"

  _ai_candy_cache_lock_acquire "$operation_lock" 300 "$operation_wait_ticks" || return 1
  if ! _ai_candy_cache_lock_acquire "$_AI_CANDY_CACHE_COMMIT_LOCK" \
    "$_AI_CANDY_CACHE_COMMIT_STALE_AFTER" "$commit_wait_ticks"; then
    _ai_candy_cache_lock_release "$operation_lock"
    return 1
  fi
  {
    _ai_candy_cache_persist_read_unlocked "$@" || read_status=$?
  } always {
    _ai_candy_cache_lock_release "$_AI_CANDY_CACHE_COMMIT_LOCK"
    _ai_candy_cache_lock_release "$operation_lock"
  }
  return "$read_status"
}

function _ai_candy_cache_persist_read() {
  local _AI_CANDY_CACHE_FORCE_BACKEND_RETRY=1
  _ai_candy_cache_persist_read_with_waits "$_AI_CANDY_CACHE_OPERATION_WAIT_TICKS" \
    "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" "$@"
}

function _ai_candy_cache_get() {
  local _AI_CANDY_CACHE_IO_TIMEOUT="${_AI_CANDY_CACHE_PROMPT_IO_TIMEOUT:-0.05}"
  local tombstone_key="$1:$2"
  local tombstone_time="${_AI_CANDY_MEM_CACHE_TOMBSTONES[$tombstone_key]-}"

  if [[ -n "$tombstone_time" ]]; then
    if _ai_candy_cache_timestamp_is_fresh "$tombstone_time" \
      "${_AI_CANDY_CACHE_TTL_MEDIUM:-300}"; then
      return 1
    fi
    _ai_candy_mem_cache_remove_key tombstone "$tombstone_key"
  fi
  if (( ! _AI_CANDY_CACHE_BACKEND_STATE )) && ! _ai_candy_cache_persistent_artifact_exists; then
    return 1
  fi
  _ai_candy_cache_persist_read_with_waits 0 0 "$1" "$2"
}

function _ai_candy_cache_set() {
  local cache_name="$1"
  local key="$2"
  local value="$3"
  local timestamp="$4"
  local memory_key="${5:-$key}"
  local tombstone_key="${cache_name}:${key}"

  [[ -n "${_AI_CANDY_MEM_CACHE_TOMBSTONES[$tombstone_key]-}" ]] && \
    _ai_candy_mem_cache_remove_key tombstone "$tombstone_key"

  case "$cache_name" in
    git_root) _AI_CANDY_MEM_CACHE_GIT_ROOT[$memory_key]="${value}|${timestamp}" ;;
    git_hierarchy) _AI_CANDY_MEM_CACHE_GIT_HIERARCHY[$memory_key]="${value}|${timestamp}" ;;
    gh_pr) _AI_CANDY_MEM_CACHE_GH_PR[$memory_key]="${value}|${timestamp}" ;;
  esac

  [[ "${_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE:-1}" == 1 ]] || return 0
  (( _AI_CANDY_CACHE_READY )) || return 0
  _ai_candy_cache_schedule_operation set "$cache_name" "$key" "$value" "$timestamp" || true
  return 0
}

function _ai_candy_cache_delete_key() {
  local cache_name="$1"
  local key="$2"
  local tombstone_key="${cache_name}:${key}"

  _AI_CANDY_MEM_CACHE_TOMBSTONES[$tombstone_key]="${EPOCHSECONDS:-0}"
  (( ${#_AI_CANDY_MEM_CACHE_TOMBSTONES} > _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )) && \
    _ai_candy_mem_cache_cleanup tombstone

  case "$cache_name" in
    git_root|git_hierarchy|gh_pr) _ai_candy_mem_cache_remove_key "$cache_name" "$key" ;;
  esac
  [[ "${_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE:-1}" == 1 ]] || return 0
  (( _AI_CANDY_CACHE_READY )) || return 0
  _ai_candy_cache_schedule_operation delete "$cache_name" "$key" "" \
    "${EPOCHSECONDS:-0}" || true
  return 0
}

# ============================================================================
# BOUNDED CLEANUP
# ============================================================================

typeset -g _AI_CANDY_CACHE_CLEANUP_INTERVAL=100
typeset -g _AI_CANDY_CACHE_MAX_AGE=$((7 * 24 * 3600))
typeset -g _AI_CANDY_FILE_CACHE_MAX_LINES=500
typeset -g _AI_CANDY_CACHE_CLEANUP_LAST_RUN=0

function _ai_candy_file_cache_prune_unlocked() {
  emulate -L zsh
  local cache_file="$1"
  local cutoff="$2"
  local record_kind="${3:-persistent}"
  local -a lines kept_reverse kept
  local line timestamp content
  integer index count=0 max_lines=${_AI_CANDY_FILE_CACHE_MAX_LINES:-500} read_status=0

  [[ -e "$cache_file" || -L "$cache_file" ]] || return 0
  [[ -f "$cache_file" && ! -L "$cache_file" ]] || return 1
  _ai_candy_cache_read_validated_lines "$cache_file" "$record_kind" || read_status=$?
  if (( read_status != 0 )); then
    [[ "$record_kind" == operation ]] && return "$read_status"
    _ai_candy_cache_remove_path "$cache_file"
    return $?
  fi
  lines=("${reply[@]}")
  for (( index=${#lines}; index>=1; index-- )); do
    line="${lines[index]}"
    timestamp="${line##*|}"
    if [[ "$record_kind" == operation ]]; then
      _ai_candy_cache_timestamp_field_is_valid "$timestamp" || continue
    else
      _ai_candy_cache_timestamp_is_valid "$timestamp" || continue
    fi
    if (( timestamp >= cutoff )); then
      kept_reverse+=("$line")
      (( ++count >= max_lines )) && break
    fi
  done
  kept=("${(@Oa)kept_reverse}")
  if (( ${#kept} < ${#lines} )); then
    if (( ${#kept} )); then
      _ai_candy_cache_join_bounded_lines "$record_kind" "${kept[@]}" || return 1
      content="$REPLY"
      _ai_candy_cache_atomic_write_unlocked "$cache_file" "$content"
    else
      _ai_candy_cache_remove_path "$cache_file"
    fi
  fi
}

function _ai_candy_file_cache_prune() {
  local cache_file="$1"
  local lock_dir="${cache_file}.lock.d"
  local prune_status=0

  [[ -f "$cache_file" ]] || return 0
  _ai_candy_cache_lock_acquire "$lock_dir" 300 100 || return 1
  {
    _ai_candy_file_cache_prune_unlocked "$@" || prune_status=$?
  } always {
    _ai_candy_cache_lock_release "$lock_dir"
  }
  return "$prune_status"
}

function _ai_candy_cache_cleanup_unlocked() {
  (( _AI_CANDY_CACHE_READY )) || return 0
  local max_age="${1:-$_AI_CANDY_CACHE_MAX_AGE}"
  local current_time=$EPOCHSECONDS
  local cutoff=$(( current_time - max_age ))
  local cache_file
  local -a simple_cache_files

  if [[ "$_AI_CANDY_CACHE_BACKEND" == "sqlite" ]]; then
    _ai_candy_run_with_timeout "$_AI_CANDY_CACHE_IO_TIMEOUT" \
      sqlite3 -batch -cmd '.timeout 500' "$_AI_CANDY_CACHE_DB_FILE" \
      "DELETE FROM cache WHERE timestamp < ${cutoff} OR timestamp > ${current_time};" &>/dev/null
  fi

  simple_cache_files=(
    "$_AI_CANDY_SYSINFO_CACHE_FILE"
    "$_AI_CANDY_CLAUDE_CACHE_FILE"
    "$_AI_CANDY_CODEX_CACHE_FILE"
    "$_AI_CANDY_GEMINI_CACHE_FILE"
    "$_AI_CANDY_KIMI_CACHE_FILE"
    "$_AI_CANDY_GH_AUTH_CACHE_FILE"
    "$_AI_CANDY_GH_USERNAME_GH_CACHE_FILE"
    "$_AI_CANDY_GH_USERNAME_SSH_CACHE_FILE"
    "$_AI_CANDY_PUBLIC_IP_CACHE_FILE"
  )
  for cache_file in "${simple_cache_files[@]}"; do
    [[ -f "$cache_file" ]] || continue
    _ai_candy_file_mtime "$cache_file"
    if (( REPLY > current_time || (REPLY > 0 && current_time - REPLY > max_age) )); then
      _ai_candy_cache_remove_path "$cache_file"
    fi
  done

  _ai_candy_file_cache_prune "${_AI_CANDY_CACHE_DIR}/git_root_cache" "$cutoff"
  _ai_candy_file_cache_prune "${_AI_CANDY_CACHE_DIR}/git_hierarchy_cache" "$cutoff"
  _ai_candy_file_cache_prune "${_AI_CANDY_CACHE_DIR}/gh_pr_cache" "$cutoff"
  _ai_candy_file_cache_prune_unlocked \
    "$_AI_CANDY_CACHE_OPERATION_FILE" "$cutoff" operation

}

function _ai_candy_cache_cleanup() {
  local cleanup_status=0
  local operation_lock="${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d"

  (( _AI_CANDY_CACHE_READY )) || return 0
  _ai_candy_cache_lock_acquire "$operation_lock" 300 100 || return 1
  if ! _ai_candy_cache_lock_acquire "$_AI_CANDY_CACHE_COMMIT_LOCK" \
    "$_AI_CANDY_CACHE_COMMIT_STALE_AFTER" "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS"; then
    _ai_candy_cache_lock_release "$operation_lock"
    return 1
  fi
  {
    _ai_candy_cache_cleanup_unlocked "$@" || cleanup_status=$?
  } always {
    _ai_candy_cache_lock_release "$_AI_CANDY_CACHE_COMMIT_LOCK"
    _ai_candy_cache_lock_release "$operation_lock"
  }
  return "$cleanup_status"
}

function _ai_candy_periodic_cache_cleanup() {
  emulate -L zsh
  setopt localoptions noerrexit noerrreturn

  local current_id="${_AI_CANDY_PROMPT_RENDER_ID:-0}"
  (( current_id - _AI_CANDY_CACHE_CLEANUP_LAST_RUN >= _AI_CANDY_CACHE_CLEANUP_INTERVAL )) || return 0
  _AI_CANDY_CACHE_CLEANUP_LAST_RUN="$current_id"
  _ai_candy_start_registered_background_worker _ai_candy_cache_cleanup || true
  return 0
}
# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Acquire a background lock using atomic mkdir to prevent TOCTOU race conditions
# Returns 0 if lock acquired, 1 if already locked (another process is running)
# Args: $1=lock_name (base path, will use .d suffix for directory lock)
# Args: $2=timeout (optional, defaults to _AI_CANDY_NETWORK_TIMEOUT)
# SECURITY: Uses mkdir which is atomic on POSIX systems, preventing race conditions
function _ai_candy_acquire_background_lock() {
  (( _AI_CANDY_CACHE_READY )) || return 1

  local lock_name="$1"
  local timeout="${2:-${_AI_CANDY_NETWORK_TIMEOUT:-5}}"
  local lock_dir="${lock_name}.d"
  local commit_wait_seconds=$(( (_AI_CANDY_CACHE_COMMIT_WAIT_TICKS + 99) / 100 ))
  local stale_after=$(( timeout + commit_wait_seconds + _AI_CANDY_CACHE_COMMIT_STALE_AFTER ))
  _ai_candy_cache_lock_acquire "$lock_dir" "$stale_after" 0
}

# Emoji mode toggle (1 = emoji-rich, 0 = plaintext)
# Persisted to file so it survives shell restarts
# (_AI_CANDY_EMOJI_MODE_FILE defined in CACHE FILE PATHS section)

function _ai_candy_load_boolean_setting() {
  local setting_file="$1"
  local default_value="$2"
  local value=""

  if (( _AI_CANDY_CACHE_READY )) && _ai_candy_cache_read_small_file "$setting_file"; then
    value="$REPLY"
  fi

  [[ "$value" == "0" || "$value" == "1" ]] || value="$default_value"
  REPLY="$value"
}

function _ai_candy_persist_boolean_setting() {
  _ai_candy_cache_write "$1" "$2" || true
}

_ai_candy_load_boolean_setting "$_AI_CANDY_EMOJI_MODE_FILE" 1
typeset -g _AI_CANDY_PROMPT_EMOJI_MODE="$REPLY"

_ai_candy_load_boolean_setting "$_AI_CANDY_PATH_SEP_MODE_FILE" 1
typeset -g _AI_CANDY_PROMPT_PATH_SEP_MODE="$REPLY"

_ai_candy_load_boolean_setting "$_AI_CANDY_NETWORK_MODE_FILE" 1
typeset -g _AI_CANDY_PROMPT_NETWORK_MODE="$REPLY"

_ai_candy_load_boolean_setting "$_AI_CANDY_AI_MODE_FILE" 1
typeset -g _AI_CANDY_PROMPT_AI_MODE="$REPLY"

_ai_candy_load_boolean_setting "$_AI_CANDY_OS_MODE_FILE" 1
typeset -g _AI_CANDY_PROMPT_OS_MODE="$REPLY"

# Toggle emoji mode
function _ai_candy_prompt_toggle_emoji() {
  emulate -L zsh
  if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
    _AI_CANDY_PROMPT_EMOJI_MODE=0
    _ai_candy_persist_boolean_setting "$_AI_CANDY_EMOJI_MODE_FILE" "0"
    builtin print -r -- "Switched to plaintext mode"
  else
    _AI_CANDY_PROMPT_EMOJI_MODE=1
    _ai_candy_persist_boolean_setting "$_AI_CANDY_EMOJI_MODE_FILE" "1"
    builtin print -r -- "Switched to emoji mode"
  fi
}

# Toggle path separator mode (/ vs space)
# Note: Space mode is disabled when current path contains spaces (would cause ambiguity)
function _ai_candy_prompt_toggle_path_sep() {
  emulate -L zsh
  if (( _AI_CANDY_PROMPT_PATH_SEP_MODE )); then
    # Currently in space mode, switch to slash mode (always allowed)
    _AI_CANDY_PROMPT_PATH_SEP_MODE=0
    _ai_candy_persist_boolean_setting "$_AI_CANDY_PATH_SEP_MODE_FILE" "0"
    builtin print -r -- "Slash mode: [repo/root/submodule/path/in/submodule]"
  else
    # Currently in slash mode, try to switch to space mode
    # Check if current path contains spaces
    if [[ "$PWD" == *" "* ]]; then
      builtin print -r -- "Cannot switch to space mode: current path contains spaces"
      _ai_candy_sanitize_terminal_text "$PWD"
      builtin print -r -- "Path: $REPLY"
      builtin print -r -- "Space mode would cause ambiguity with space-containing directory names."
      return 1
    fi
    _AI_CANDY_PROMPT_PATH_SEP_MODE=1
    _ai_candy_persist_boolean_setting "$_AI_CANDY_PATH_SEP_MODE_FILE" "1"
    builtin print -r -- "Space mode: [repo/root submodule path/in/submodule]"
  fi
}

# Toggle network mode (on/off)
# When off: all network-dependent features are disabled (both display and underlying calls)
# Affected features: public IP, GitHub identity/PR, and tool update checks.
function _ai_candy_prompt_toggle_network() {
  emulate -L zsh
  if (( _AI_CANDY_PROMPT_NETWORK_MODE )); then
    _AI_CANDY_PROMPT_NETWORK_MODE=0
    _ai_candy_persist_boolean_setting "$_AI_CANDY_NETWORK_MODE_FILE" "0"
    builtin print -r -- "Network mode: OFF"
    builtin print -r -- "Disabled: public IP, GitHub username/PR status, AI update checks"
  else
    _AI_CANDY_PROMPT_NETWORK_MODE=1
    _ai_candy_persist_boolean_setting "$_AI_CANDY_NETWORK_MODE_FILE" "1"
    builtin print -r -- "Network mode: ON"
    builtin print -r -- "Enabled: public IP, GitHub username/PR status, AI update checks"
  fi
}

# Toggle optional-tool display mode.
function _ai_candy_prompt_toggle_ai() {
  emulate -L zsh
  if (( _AI_CANDY_PROMPT_AI_MODE )); then
    _AI_CANDY_PROMPT_AI_MODE=0
    _ai_candy_persist_boolean_setting "$_AI_CANDY_AI_MODE_FILE" "0"
    builtin print -r -- "AI tools display: OFF"
  else
    _AI_CANDY_PROMPT_AI_MODE=1
    _ai_candy_persist_boolean_setting "$_AI_CANDY_AI_MODE_FILE" "1"
    builtin print -r -- "AI tools display: ON"
  fi
}

# Toggle OS/kernel display mode (show/hide)
function _ai_candy_prompt_toggle_os() {
  emulate -L zsh
  if (( _AI_CANDY_PROMPT_OS_MODE )); then
    _AI_CANDY_PROMPT_OS_MODE=0
    _ai_candy_persist_boolean_setting "$_AI_CANDY_OS_MODE_FILE" "0"
    builtin print -r -- "OS/kernel display: OFF"
  else
    _AI_CANDY_PROMPT_OS_MODE=1
    _ai_candy_persist_boolean_setting "$_AI_CANDY_OS_MODE_FILE" "1"
    builtin print -r -- "OS/kernel display: ON"
  fi
}

# Turn off all toggles (plaintext, slash separator, network disabled, ai hidden, os hidden)
function _ai_candy_prompt_all_off() {
  emulate -L zsh
  # 1. Plaintext mode (e)
  _AI_CANDY_PROMPT_EMOJI_MODE=0
  _ai_candy_persist_boolean_setting "$_AI_CANDY_EMOJI_MODE_FILE" "0"

  # 2. Slash separator (p)
  _AI_CANDY_PROMPT_PATH_SEP_MODE=0
  _ai_candy_persist_boolean_setting "$_AI_CANDY_PATH_SEP_MODE_FILE" "0"

  # 3. Network disabled (n)
  _AI_CANDY_PROMPT_NETWORK_MODE=0
  _ai_candy_persist_boolean_setting "$_AI_CANDY_NETWORK_MODE_FILE" "0"

  # 4. Optional tools hidden (a)
  _AI_CANDY_PROMPT_AI_MODE=0
  _ai_candy_persist_boolean_setting "$_AI_CANDY_AI_MODE_FILE" "0"

  # 5. OS hidden (o)
  _AI_CANDY_PROMPT_OS_MODE=0
  _ai_candy_persist_boolean_setting "$_AI_CANDY_OS_MODE_FILE" "0"

  builtin print -r -- "All toggles turned OFF:"
  builtin print -r -- "  - Emoji mode: OFF (Plaintext)"
  builtin print -r -- "  - Path separator: Slash (/)"
  builtin print -r -- "  - Network: DISABLED"
  builtin print -r -- "  - AI tools: HIDDEN"
  builtin print -r -- "  - OS/kernel: HIDDEN"
}

# Turn on all toggles (emoji, space separator, network enabled, ai visible, os visible)
function _ai_candy_prompt_all_on() {
  emulate -L zsh
  # 1. Emoji mode (e)
  _AI_CANDY_PROMPT_EMOJI_MODE=1
  _ai_candy_persist_boolean_setting "$_AI_CANDY_EMOJI_MODE_FILE" "1"

  # 2. Space separator (p)
  # The variable sets the preference, the render logic handles the fallback if path has spaces
  _AI_CANDY_PROMPT_PATH_SEP_MODE=1
  _ai_candy_persist_boolean_setting "$_AI_CANDY_PATH_SEP_MODE_FILE" "1"

  # 3. Network enabled (n)
  _AI_CANDY_PROMPT_NETWORK_MODE=1
  _ai_candy_persist_boolean_setting "$_AI_CANDY_NETWORK_MODE_FILE" "1"

  # 4. Optional tools visible (a)
  _AI_CANDY_PROMPT_AI_MODE=1
  _ai_candy_persist_boolean_setting "$_AI_CANDY_AI_MODE_FILE" "1"

  # 5. OS visible (o)
  _AI_CANDY_PROMPT_OS_MODE=1
  _ai_candy_persist_boolean_setting "$_AI_CANDY_OS_MODE_FILE" "1"

  builtin print -r -- "All toggles turned ON:"
  builtin print -r -- "  - Emoji mode: ON"
  builtin print -r -- "  - Path separator: Space (if valid)"
  builtin print -r -- "  - Network: ENABLED"
  builtin print -r -- "  - AI tools: VISIBLE"
  builtin print -r -- "  - OS/kernel: VISIBLE"
}

# Print emoji help/legend
function _ai_candy_prompt_emoji_help() {
  emulate -L zsh
  local border=""
  integer border_index
  for border_index in {1..66}; do
    border+="$_AI_CANDY_BOX_H"
  done
  local TOP="${_AI_CANDY_BOX_TL}${border}${_AI_CANDY_BOX_TR}"
  local MID="${_AI_CANDY_BOX_ML}${border}${_AI_CANDY_BOX_MR}"
  local BOT="${_AI_CANDY_BOX_BL}${border}${_AI_CANDY_BOX_BR}"

  builtin print -r -- ""
  builtin print -r -- "$TOP"
  builtin print -r -- "${_AI_CANDY_BOX_V}              ZSH Prompt Emoji/Symbol Reference                   ${_AI_CANDY_BOX_V}"
  builtin print -r -- "$MID"
  builtin print -r -- "${_AI_CANDY_BOX_V}  COMMAND STATUS                                                  ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    [${_AI_CANDY_SYM_CHECK}] / [OK]    Last command succeeded (exit code 0)            ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    [${_AI_CANDY_SYM_CROSS}N] / [ERRN] Last command failed with exit code N            ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    Example: [${_AI_CANDY_SYM_CROSS}127] means 'command not found'                     ${_AI_CANDY_BOX_V}"
  builtin print -r -- "$MID"
  builtin print -r -- "${_AI_CANDY_BOX_V}  CONNECTION & ENVIRONMENT                                        ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_NF_SSH}/ [SSH] Connected via SSH                                   ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_NF_CONTAINER} / C     Running inside a container                          ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_NF_TTY} / T     TTY session                                         ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_NF_GNOME}/ G     GNOME desktop                                       ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_NF_KDE} / K     KDE Plasma desktop                                  ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_NF_XFCE} / X     XFCE desktop                                        ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_NF_XORG} / O     Xorg session (generic X11)                          ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_HOST} / H     Other host environment                             ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    (x.x.x.x)  Public IP address (green=online, red=offline)      ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}               ${_AI_CANDY_SYM_WARNING} Privacy: IP is sent to external services         ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}               Use 'n' to disable network features if concerned   ${_AI_CANDY_BOX_V}"
  builtin print -r -- "$MID"
  builtin print -r -- "${_AI_CANDY_BOX_V}  GITHUB IDENTITY                                                 ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_NF_GITHUB}User /     GitHub username (white bg, black text)           ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    [Username]   Emoji mode: icon, Plaintext mode: brackets       ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}                 Detected via gh auth (active) & ssh -T github    ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_NF_GITHUB}A|B /      Mismatch warning (red) - A=gh, B=ssh identity    ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    [A|B]        Format: gh_user|ssh_user - check your config!    ${_AI_CANDY_BOX_V}"
  builtin print -r -- "$MID"
  builtin print -r -- "${_AI_CANDY_BOX_V}  GIT STATUS                                                      ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_UP}N / +N   N commits ahead of upstream (need to push)          ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_DOWN}N / -N   N commits behind upstream (need to pull)            ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_STASH}N / SN   N stashed changes                                   ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    *         Uncommitted changes in working directory            ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    Example: main ${_AI_CANDY_SYM_UP}2${_AI_CANDY_SYM_DOWN}1${_AI_CANDY_SYM_STASH}3 means branch 'main', 2 ahead,            ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}             1 behind, 3 stashes                                  ${_AI_CANDY_BOX_V}"
  builtin print -r -- "$MID"
  builtin print -r -- "${_AI_CANDY_BOX_V}  GIT SPECIAL STATES                                              ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_BRANCH} / [RB] Rebase in progress (with step/total if interactive) ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_BRANCH} / [MG] Merge in progress                                   ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_CHERRY} / [CP] Cherry-pick in progress                             ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_REWIND} / [RV] Revert in progress                                  ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_SEARCH} / [BI] Bisect in progress                                  ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_PLUG} / [DT] Detached HEAD state                                 ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    Example: ${_AI_CANDY_SYM_BRANCH}2/5 means interactive rebase at step 2 of 5        ${_AI_CANDY_BOX_V}"
  builtin print -r -- "$MID"
  builtin print -r -- "${_AI_CANDY_BOX_V}  GITHUB PR STATUS                                                ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    #N        Pull request number N for current branch            ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_CHECK} / OK    All CI checks passed                                ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_CROSS} / X     Some CI checks failed                               ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_PENDING} / ...   CI checks still running                            ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    Example: #42${_AI_CANDY_SYM_CHECK} means PR #42 with all checks passing            ${_AI_CANDY_BOX_V}"
  builtin print -r -- "$MID"
  builtin print -r -- "${_AI_CANDY_BOX_V}  AI CODING TOOLS                                                 ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    $_AI_CANDY_NF_CLAUDE / Cl:   Claude Code version                                ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    $_AI_CANDY_NF_CODEX / Cx:   OpenAI Codex version                               ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    $_AI_CANDY_NF_GEMINI / Gm:   Google Gemini CLI version                          ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    $_AI_CANDY_NF_KIMI / Km:   Moonshot Kimi version                              ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    *         Update available (shown after version)              ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    Example: ${_AI_CANDY_NF_CLAUDE}2.0.76* means Claude v2.0.76 with update available ${_AI_CANDY_BOX_V}"
  builtin print -r -- "$MID"
  builtin print -r -- "${_AI_CANDY_BOX_V}  SYSTEM INFO (shown in brackets at end of prompt)                ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    [OS, kernel] shows operating system and kernel version        ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    Emoji mode uses Nerd Font icons for OS/distro and kernel:     ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_NF_REDHAT} RHEL  ${_AI_CANDY_NF_UBUNTU} Ubuntu  ${_AI_CANDY_NF_CENTOS} CentOS  ${_AI_CANDY_NF_FEDORA} Fedora  ${_AI_CANDY_NF_ALMA} AlmaLinux  ${_AI_CANDY_NF_MACOS} macOS    ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_NF_APPLE} Darwin kernel    ${_AI_CANDY_NF_LINUX} Linux kernel                             ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    Example: [${_AI_CANDY_NF_REDHAT} 9.5, ${_AI_CANDY_NF_LINUX}-5.14.0] for RHEL 9.5 on Linux kernel       ${_AI_CANDY_BOX_V}"
  builtin print -r -- "$MID"
  builtin print -r -- "${_AI_CANDY_BOX_V}  OTHER                                                           ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ${_AI_CANDY_SYM_JOBS}N / JN   N background jobs running                           ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    ..        Path truncated (in narrow terminal)                 ${_AI_CANDY_BOX_V}"
  builtin print -r -- "$MID"
  builtin print -r -- "${_AI_CANDY_BOX_V}  PATH DISPLAY (in git repos)                                     ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    Space mode: [repo/root submodule relative/path]               ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    Slash mode: [repo/root/submodule/relative/path]               ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    Space mode enables double-click to select path segments       ${_AI_CANDY_BOX_V}"
  builtin print -r -- "$MID"
  builtin print -r -- "${_AI_CANDY_BOX_V}  QUICK COMMANDS                                                  ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    u         Refresh all cached prompt info                      ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    e         Toggle emoji/plaintext mode                         ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    p         Toggle path separator (space/slash)                 ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    n         Toggle network features (IP, GitHub, AI updates)    ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    a         Toggle AI tools display (show/hide)                 ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    h         Show this help                                      ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    t         Show tool availability status                       ${_AI_CANDY_BOX_V}"
  builtin print -r -- "$BOT"
  builtin print -r -- ""
}

# Tool availability status - shows which optional tools are installed
# and what features they enable
function _ai_candy_tool_status_line() {
  emulate -L zsh
  setopt localoptions extendedglob

  local content="$1"
  local inner="${INNER:-76}"
  local visible="${content//$'\e'\[[0-9;]##m/}"
  local visible_length=${#visible}
  local padding=$(( inner - visible_length ))
  (( padding < 0 )) && padding=0
  builtin printf "${_AI_CANDY_BOX_V}%s%*s${_AI_CANDY_BOX_V}\n" "$content" "$padding" ""
}

function _ai_candy_prompt_tool_status() {
  emulate -L zsh
  setopt localoptions extendedglob

  local GREEN=$'\e[32m'
  local RED=$'\e[31m'
  local YELLOW=$'\e[33m'
  local CYAN=$'\e[36m'
  local RESET=$'\e[0m'
  local CHECK="${GREEN}${_AI_CANDY_SYM_CHECK}${RESET}"
  local CROSS="${RED}${_AI_CANDY_SYM_CROSS}${RESET}"
  local WARN="${YELLOW}!${RESET}"
  local QMARK="${YELLOW}?${RESET}"

  # Total box width (including borders)
  local WIDTH=78
  local INNER=$((WIDTH - 2))  # Content width between borders

  # Border lines
  local TOP="${_AI_CANDY_BOX_TL}$(builtin printf "${_AI_CANDY_BOX_H}%.0s" {1..$INNER})${_AI_CANDY_BOX_TR}"
  local MID="${_AI_CANDY_BOX_ML}$(builtin printf "${_AI_CANDY_BOX_H}%.0s" {1..$INNER})${_AI_CANDY_BOX_MR}"
  local BOT="${_AI_CANDY_BOX_BL}$(builtin printf "${_AI_CANDY_BOX_H}%.0s" {1..$INNER})${_AI_CANDY_BOX_BR}"

  builtin print -r -- ""
  builtin print -r -- "$TOP"
  _ai_candy_tool_status_line "              Tool Availability Status"
  builtin print -r -- "$MID"
  _ai_candy_tool_status_line "  ${CYAN}TOGGLE MODES${RESET} (use single letter to toggle)"
  _ai_candy_tool_status_line ""

  # Emoji mode (e)
  local ZWS=$'\xe2\x80\x8b'  # Zero-width space affects string length only.
  if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
    _ai_candy_tool_status_line "    ${CHECK} e  Emoji mode      [${_AI_CANDY_SYM_CHECK}] ${_AI_CANDY_NF_SSH}$_AI_CANDY_NF_CLAUDE ${_AI_CANDY_SYM_UP}${_AI_CANDY_SYM_DOWN} ${_AI_CANDY_SYM_STASH}"
  else
    _ai_candy_tool_status_line "    ${CROSS} e  Plaintext mode  [OK] [SSH] Cl: +- S"
  fi

  # Path separator mode (p)
  if (( _AI_CANDY_PROMPT_PATH_SEP_MODE )); then
    _ai_candy_tool_status_line "    ${CHECK} p  Space separator [repo submodule path]"
  else
    _ai_candy_tool_status_line "    ${CROSS} p  Slash separator [repo/submodule/path]"
  fi

  # Network mode (n)
  if (( _AI_CANDY_PROMPT_NETWORK_MODE )); then
    _ai_candy_tool_status_line "    ${CHECK} n  Network enabled (IP, GitHub, AI updates)"
  else
    _ai_candy_tool_status_line "    ${CROSS} n  Network disabled"
  fi

  # Optional-tool display mode (a)
  if (( _AI_CANDY_PROMPT_AI_MODE )); then
    _ai_candy_tool_status_line "    ${CHECK} a  AI tools display enabled"
  else
    _ai_candy_tool_status_line "    ${CROSS} a  AI tools display hidden"
  fi

  # OS/kernel display mode (o)
  if (( _AI_CANDY_PROMPT_OS_MODE )); then
    _ai_candy_tool_status_line "    ${CHECK} o  OS/kernel display enabled"
  else
    _ai_candy_tool_status_line "    ${CROSS} o  OS/kernel display hidden"
  fi

  _ai_candy_tool_status_line ""
  builtin print -r -- "$MID"
  _ai_candy_tool_status_line "  ${CYAN}CORE TOOLS${RESET} (Performance & Caching)"
  _ai_candy_tool_status_line ""

  _ai_candy_cache_backend_init >/dev/null 2>&1

  # sqlite3
  if (( _AI_CANDY_HAS_SQLITE3 )); then
    _ai_candy_tool_status_line "    ${CHECK} sqlite3     - Persistent cache backend available"
  else
    _ai_candy_tool_status_line "    ${WARN} sqlite3     - Portable file cache active"
    _ai_candy_tool_status_line "                    Install: apt/brew install sqlite3"
  fi

  # timeout/gtimeout
  if (( _AI_CANDY_HAS_TIMEOUT )); then
    _ai_candy_tool_status_line "    ${CHECK} ${_AI_CANDY_TIMEOUT_CMD:t}     - Command timeout support"
  else
    _ai_candy_tool_status_line "    ${CROSS} timeout     - Network features DISABLED (gh, PR status)"
    _ai_candy_tool_status_line "                    Install: apt install coreutils"
    _ai_candy_tool_status_line "                             brew install coreutils"
  fi

  _ai_candy_tool_status_line ""
  builtin print -r -- "$MID"
  _ai_candy_tool_status_line "  ${CYAN}GITHUB INTEGRATION${RESET}"
  _ai_candy_tool_status_line ""

  # gh CLI
  if (( _AI_CANDY_HAS_GH )); then
    local gh_output=$(_ai_candy_run_local_probe gh --version 2>/dev/null)
    local gh_version=""
    [[ "$gh_output" =~ '[0-9]+\.[0-9]+\.[0-9]+' ]] && gh_version="$MATCH"
    _ai_candy_tool_status_line "    ${CHECK} gh          - GitHub CLI v${gh_version}"
    if (( _AI_CANDY_HAS_TIMEOUT )); then
      local auth_status=""
      local current_time=${EPOCHSECONDS}
      # Check cache first
      if _ai_candy_cache_read_small_file "$_AI_CANDY_GH_AUTH_CACHE_FILE"; then
        local auth_data="$REPLY"
        local cached_auth_status="${auth_data%%|*}"
        local cache_time="${auth_data#*|}"
        _ai_candy_gh_auth_cache_ttl "$cached_auth_status"
        if _ai_candy_cache_timestamp_is_fresh \
             "$cache_time" "$REPLY" "$current_time"; then
          auth_status="$cached_auth_status"
        fi
      fi
      # If no valid cache, check synchronously (user explicitly requested status)
      if [[ -z "$auth_status" ]]; then
        if _ai_candy_run_with_timeout "${_AI_CANDY_NETWORK_TIMEOUT:-5}" gh auth status &>/dev/null; then
          auth_status="1"
          _ai_candy_cache_write "$_AI_CANDY_GH_AUTH_CACHE_FILE" "1|${current_time}"
        else
          auth_status="?"
          _ai_candy_cache_write "$_AI_CANDY_GH_AUTH_CACHE_FILE" "?|${current_time}"
        fi
      fi
      # Display result
      if [[ "$auth_status" == "1" ]]; then
        _ai_candy_tool_status_line "                    Authenticated: PR status, CI checks"
      elif [[ "$auth_status" == "0" ]]; then
        _ai_candy_tool_status_line "                    ${WARN} Not authenticated (run: gh auth login)"
      else
        _ai_candy_tool_status_line "                    ${WARN} Authentication could not be verified"
      fi
    else
      _ai_candy_tool_status_line "                    ${WARN} Disabled (no timeout command)"
    fi
  else
    _ai_candy_tool_status_line "    ${CROSS} gh          - No PR/CI status in prompt"
    _ai_candy_tool_status_line "                    Install: https://cli.github.com"
  fi

  # hash command (for PR cache key generation)
  if (( _AI_CANDY_HAS_HASH_CMD )); then
    _ai_candy_tool_status_line "    ${CHECK} ${_AI_CANDY_HASH_CMD:t}    - Private PR cache keys"
  else
    _ai_candy_tool_status_line "    ${WARN} hash        - PR caching disabled (no SHA-256 tool)"
  fi

  # ssh
  if (( _AI_CANDY_HAS_SSH )); then
    _ai_candy_tool_status_line "    ${CHECK} ssh         - GitHub SSH identity detection"
  else
    _ai_candy_tool_status_line "    ${CROSS} ssh         - No SSH identity in prompt"
  fi

  # curl
  if (( _AI_CANDY_HAS_CURL )); then
    _ai_candy_tool_status_line "    ${CHECK} curl        - AI tool update checks, public IP display"
  else
    _ai_candy_tool_status_line "    ${WARN} curl        - No update notifications for AI tools"
    _ai_candy_tool_status_line "                    Public IP display disabled"
  fi

  _ai_candy_tool_status_line ""
  builtin print -r -- "$MID"
  _ai_candy_tool_status_line "  ${CYAN}CACHE STATUS${RESET}"
  _ai_candy_tool_status_line ""
  _ai_candy_sanitize_terminal_text "$_AI_CANDY_CACHE_DIR"
  local display_cache_dir="$REPLY"
  _ai_candy_tool_status_line "    Cache directory: ${display_cache_dir}"

  case "$_AI_CANDY_CACHE_BACKEND" in
    sqlite)
      local db_info=$(command du -h "$_AI_CANDY_CACHE_DB_FILE" 2>/dev/null)
      local db_size="${db_info%%[[:space:]]*}"
      _ai_candy_tool_status_line "    Persistent cache: ${CHECK} SQLite (${db_size:-0K})"
      ;;
    file)
      _ai_candy_tool_status_line "    Persistent cache: ${CHECK} Portable file"
      ;;
    *)
      _ai_candy_tool_status_line "    Persistent cache: ${CROSS} Memory only"
      ;;
  esac

  local -a cache_entries=("$_AI_CANDY_CACHE_DIR"/*(N))
  local cache_count=${#cache_entries}
  _ai_candy_tool_status_line "    Cache files:    ${cache_count} files"

  _ai_candy_tool_status_line ""
  builtin print -r -- "$MID"
  _ai_candy_tool_status_line "  ${CYAN}AI CODING TOOLS${RESET} (Version display in prompt)"
  _ai_candy_tool_status_line ""

  if (( _AI_CANDY_HAS_CLAUDE )); then
    local claude_output=$(_ai_candy_run_background_probe claude --version 2>/dev/null)
    local claude_ver=""
    [[ "$claude_output" =~ '[0-9]+\.[0-9]+\.[0-9]+' ]] && claude_ver="$MATCH"
    _ai_candy_tool_status_line "    ${CHECK} claude      - Claude Code v${claude_ver:-?}"
  elif (( ! _AI_CANDY_PROMPT_NETWORK_MODE )); then
    _ai_candy_tool_status_line "    ${QMARK} claude      - Network disabled"
  else
    _ai_candy_tool_status_line "    ${CROSS} claude      - Not installed"
    _ai_candy_tool_status_line "                    Install: npm i -g @anthropic-ai/claude-code"
  fi

  if (( _AI_CANDY_HAS_CODEX )); then
    local codex_output=$(_ai_candy_run_background_probe codex --version 2>/dev/null)
    local codex_ver=""
    [[ "$codex_output" =~ '[0-9]+\.[0-9]+\.[0-9]+' ]] && codex_ver="$MATCH"
    _ai_candy_tool_status_line "    ${CHECK} codex       - OpenAI Codex v${codex_ver:-?}"
  elif (( ! _AI_CANDY_PROMPT_NETWORK_MODE )); then
    _ai_candy_tool_status_line "    ${QMARK} codex       - Network disabled"
  else
    _ai_candy_tool_status_line "    ${CROSS} codex       - Not installed"
    _ai_candy_tool_status_line "                    Install: npm i -g @openai/codex"
  fi

  if (( _AI_CANDY_HAS_GEMINI )); then
    local gemini_output=$(_ai_candy_run_background_probe gemini --version 2>/dev/null)
    local gemini_ver=""
    [[ "$gemini_output" =~ '[0-9]+\.[0-9]+\.[0-9]+' ]] && gemini_ver="$MATCH"
    _ai_candy_tool_status_line "    ${CHECK} gemini      - Google Gemini v${gemini_ver:-?}"
  elif (( ! _AI_CANDY_PROMPT_NETWORK_MODE )); then
    _ai_candy_tool_status_line "    ${QMARK} gemini      - Network disabled"
  else
    _ai_candy_tool_status_line "    ${CROSS} gemini      - Not installed"
    _ai_candy_tool_status_line "                    Install: npm i -g @google/gemini-cli"
  fi

  if (( _AI_CANDY_HAS_KIMI )); then
    local kimi_output=$(_ai_candy_run_background_probe kimi --version 2>/dev/null)
    local kimi_ver=""
    [[ "$kimi_output" =~ '[0-9]+\.[0-9]+\.[0-9]+' ]] && kimi_ver="$MATCH"
    _ai_candy_tool_status_line "    ${CHECK} kimi        - Moonshot Kimi v${kimi_ver:-?}"
  elif (( ! _AI_CANDY_PROMPT_NETWORK_MODE )); then
    _ai_candy_tool_status_line "    ${QMARK} kimi        - Network disabled"
  else
    _ai_candy_tool_status_line "    ${CROSS} kimi        - Not installed"
    _ai_candy_tool_status_line "                    Install: https://kimi.com/code"
  fi

  _ai_candy_tool_status_line ""
  builtin print -r -- "$BOT"
  builtin print -r -- ""

}

# Manual cache refresh function - clears all prompt caches
# Force refresh of derived system, Git, PR, and tool data.
# Also re-detects command availability (useful after nvm/pyenv/etc. loads)
function _ai_candy_prompt_refresh_all_caches() {
  emulate -L zsh
  _ai_candy_stop_registered_background_jobs
  _ai_candy_detect_core_commands

  # Re-detect optional tools that may load after shell initialization.
  _ai_candy_detect_optional_commands

  local cache_file
  integer refresh_status=0
  local -a derived_cache_files=(
    "$_AI_CANDY_CACHE_DB_FILE"
    "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE"
    "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE"
    "${_AI_CANDY_CACHE_DB_FILE}-journal"
    "${_AI_CANDY_CACHE_DB_FILE}-shm"
    "${_AI_CANDY_CACHE_DB_FILE}-wal"
    "$_AI_CANDY_CACHE_OPERATION_FILE"
    "$_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE"
    "$_AI_CANDY_SYSINFO_CACHE_FILE"
    "${_AI_CANDY_CACHE_DIR}/git_root_cache"
    "${_AI_CANDY_CACHE_DIR}/git_hierarchy_cache"
    "${_AI_CANDY_CACHE_DIR}/gh_pr_cache"
    "$_AI_CANDY_GH_AUTH_CACHE_FILE"
    "$_AI_CANDY_GH_USERNAME_GH_CACHE_FILE"
    "$_AI_CANDY_GH_USERNAME_SSH_CACHE_FILE"
    "$_AI_CANDY_PUBLIC_IP_CACHE_FILE"
    "$_AI_CANDY_CLAUDE_CACHE_FILE"
    "$_AI_CANDY_CODEX_CACHE_FILE"
    "$_AI_CANDY_GEMINI_CACHE_FILE"
    "$_AI_CANDY_KIMI_CACHE_FILE"
  )
  if (( _AI_CANDY_CACHE_READY )); then
    local operation_lock="${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d"
    if ! _ai_candy_cache_lock_acquire "$operation_lock" 300 200; then
      builtin print -u2 -- "ai-candy: cache refresh could not acquire the operation lock"
      return 1
    fi
    if ! _ai_candy_cache_lock_acquire "$_AI_CANDY_CACHE_COMMIT_LOCK" \
      "$_AI_CANDY_CACHE_COMMIT_STALE_AFTER" "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS"; then
      _ai_candy_cache_lock_release "$operation_lock"
      builtin print -u2 -- "ai-candy: cache refresh could not acquire the commit lock"
      return 1
    fi
    {
      _ai_candy_cache_advance_persistence_epoch_unlocked || refresh_status=$?
      if (( refresh_status == 0 )); then
        for cache_file in "${derived_cache_files[@]}"; do
          _ai_candy_cache_remove_path "$cache_file" || refresh_status=$?
        done
      fi
    } always {
      _ai_candy_cache_lock_release "$_AI_CANDY_CACHE_COMMIT_LOCK"
      _ai_candy_cache_lock_release "$operation_lock"
    }
    if (( refresh_status != 0 )); then
      builtin print -u2 -- \
        "ai-candy: cache refresh could not update persistent state"
      return "$refresh_status"
    fi
  fi

  # The next persistent access lazily recreates the selected backend.
  _AI_CANDY_CACHE_BACKEND_STATE=0
  _AI_CANDY_CACHE_BACKEND="none"

  # Clear memory-based associative array caches
  _AI_CANDY_MEM_CACHE_GIT_ROOT=()
  _AI_CANDY_MEM_CACHE_GIT_ROOT_GENERATION=()
  _AI_CANDY_MEM_CACHE_GIT_HIERARCHY=()
  _AI_CANDY_MEM_CACHE_GH_PR=()
  _AI_CANDY_MEM_CACHE_TOMBSTONES=()
  _AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT=()
  _AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT=()
  _AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT=()
  _AI_CANDY_GIT_CONFIG_GRAPH_PATHS_BY_KEY=()
  _AI_CANDY_GIT_CONFIG_GRAPH_CONTEXT_BY_KEY=()
  _AI_CANDY_GIT_CONFIG_GRAPH_TIMEOUT_BY_KEY=()

  # Reset in-memory per-prompt caches
  _AI_CANDY_PROMPT_GH_PR_CACHE=""
  _AI_CANDY_PROMPT_GH_PR_CACHE_ID=-1
  _AI_CANDY_PROMPT_GIT_SPECIAL_CACHE=""
  _AI_CANDY_PROMPT_GIT_SPECIAL_CACHE_ID=-1
  _AI_CANDY_PROMPT_GIT_SPECIAL_CACHE_CONTEXT=""
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE=""
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_ID=-1
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_CONTEXT=""
  _AI_CANDY_SYSINFO_SESSION_READY=0
  _AI_CANDY_GH_AUTH_MEM_CACHE=""
  _AI_CANDY_GH_AUTH_MEM_CACHE_TIME=0
  _AI_CANDY_AI_PROCESS_COUNTS=(claude 0 codex 0 gemini 0 kimi 0)
  _AI_CANDY_AI_PROCESS_SNAPSHOT_TIME=0
  _AI_CANDY_AI_PROCESS_SNAPSHOT_ATTEMPT_TIME=0
  _AI_CANDY_REFRESH_REQUESTED=()
  _AI_CANDY_GIT_SNAPSHOT_RENDER_ID=-1
  _AI_CANDY_GIT_SNAPSHOT_CONTEXT=""
  _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_ID=-1
  _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_KEY=""
  _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_VALUE=""
  _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_PROBE_FAILED=0
  _AI_CANDY_GIT_CONFIG_GRAPH_FAILURE_SEQUENCE=0
  _AI_CANDY_SMART_PATH_CONTEXT_KEY=""
  _AI_CANDY_SMART_PATH_CONTEXT_TIMESTAMP=0
  _AI_CANDY_GIT_TOPOLOGY_GENERATION=0
  _AI_CANDY_GIT_TOPOLOGY_GENERATION_VALID=1

  builtin print -r -- "Prompt caches refreshed."
}

function _ai_candy_install_short_aliases() {
  emulate -L zsh
  [[ "${AI_CANDY_ENABLE_SHORT_ALIASES:-0}" == 1 ]] || return 0
  local -A short_aliases=(
    e _ai_candy_prompt_toggle_emoji
    p _ai_candy_prompt_toggle_path_sep
    n _ai_candy_prompt_toggle_network
    a _ai_candy_prompt_toggle_ai
    o _ai_candy_prompt_toggle_os
    off _ai_candy_prompt_all_off
    on _ai_candy_prompt_all_on
    t _ai_candy_prompt_tool_status
    u _ai_candy_prompt_refresh_all_caches
    h _ai_candy_prompt_emoji_help
  )
  local alias_name
  for alias_name in "${(@k)short_aliases}"; do
    (( ! $+aliases[$alias_name] && ! $+functions[$alias_name] )) || continue
    builtin alias "${alias_name}=${short_aliases[$alias_name]}"
  done
}
_ai_candy_install_short_aliases

typeset -g _AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE=0
typeset -g _AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE_ROOT=""
typeset -g _AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE_PATH=""
typeset -g _AI_CANDY_PROMPT_GIT_TOPOLOGY_INVALIDATE=0
typeset -g _AI_CANDY_PROMPT_GIT_REMOTE_INVALIDATE=0

function _ai_candy_prompt_git_command_affects_cached_status() {
  local command_text="$1"
  [[ -n "$command_text" ]] || return 1
  REPLY=""

  local -a words
  words=("${(z)command_text}")
  local word="" subcommand=""
  integer index sub_index

  for (( index=1; index<=${#words}; index++ )); do
    word="${(Q)words[index]}"
    [[ "${word:t}" == git ]] || continue
    sub_index=$(( index + 1 ))
    while (( sub_index <= ${#words} )); do
      word="${(Q)words[sub_index]}"
      case "$word" in
        -C|-c|--git-dir|--work-tree|--namespace)
          sub_index=$(( sub_index + 2 ))
          ;;
        --)
          sub_index=$(( sub_index + 1 ))
          break
          ;;
        --git-dir=*|--work-tree=*|--namespace=*|-*)
          sub_index=$(( sub_index + 1 ))
          ;;
        *) break ;;
      esac
    done

    subcommand="${(Q)words[sub_index]-}"
    case "$subcommand" in
      add|am|apply|bisect|branch|checkout|cherry-pick|clean|clone|commit|config|fetch|init|merge|mv|notes|pull|push|rebase|remote|reset|restore|revert|rm|stash|submodule|switch|tag|update-ref|worktree)
        REPLY="$subcommand"
        return 0
        ;;
    esac
  done

  return 1
}

function _ai_candy_prompt_mark_git_cache_invalidation() {
  emulate -L zsh
  setopt localoptions noerrexit noerrreturn
  local _AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
  local REPLY=""

  local typed_command="$1"
  local expanded_command="${2:-$typed_command}"
  local full_command="${3:-$expanded_command}"
  local command_text="${expanded_command:-${full_command:-$typed_command}}"

  _AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE=0
  _AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE_ROOT=""
  _AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE_PATH="$PWD"
  _AI_CANDY_PROMPT_GIT_TOPOLOGY_INVALIDATE=0
  _AI_CANDY_PROMPT_GIT_REMOTE_INVALIDATE=0

  if ! _ai_candy_prompt_git_command_affects_cached_status "$command_text"; then
    return 0
  fi
  local git_subcommand="$REPLY"

  [[ "$git_subcommand" == config ]] && _AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT=()

  [[ "$git_subcommand" == init || "$git_subcommand" == clone || \
     "$git_subcommand" == submodule || "$git_subcommand" == worktree ]] && \
    _AI_CANDY_PROMPT_GIT_TOPOLOGY_INVALIDATE=1
  [[ "$git_subcommand" == remote || "$git_subcommand" == config ]] && \
    _AI_CANDY_PROMPT_GIT_REMOTE_INVALIDATE=1

  _AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE=1

  local git_root="${_AI_CANDY_PP_CACHED_GIT_ROOT:-}"
  if [[ -z "$git_root" || "$git_root" == "NOT_GIT" ]]; then
    _ai_candy_get_cached_git_root
    git_root="$REPLY"
  fi

  if [[ -n "$git_root" && "$git_root" != "NOT_GIT" ]]; then
    _AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE_ROOT="$git_root"
  fi
  return 0
}

function _ai_candy_prompt_invalidate_git_status_cache_for_root() {
  local git_root="$1"
  [[ -n "$git_root" && "$git_root" != "NOT_GIT" ]] || return
  _ai_candy_git_context_cache_key "$git_root"
  local context_key="$REPLY"

  _AI_CANDY_PROMPT_GH_PR_CACHE=""
  _AI_CANDY_PROMPT_GH_PR_CACHE_ID=-1
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE=""
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_ID=-1
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_CONTEXT=""
  _AI_CANDY_GIT_SNAPSHOT_RENDER_ID=-1
  _AI_CANDY_GIT_SNAPSHOT_CONTEXT=""
  _AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT[$context_key]=""
  _ai_candy_mem_cache_remove_key git_snapshot_retry "$context_key"
}

function _ai_candy_prompt_invalidate_git_remote_cache_for_root() {
  _AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT=()
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE=""
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_ID=-1
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_CONTEXT=""
  _AI_CANDY_PROMPT_GH_PR_CACHE=""
  _AI_CANDY_PROMPT_GH_PR_CACHE_ID=-1
}

function _ai_candy_prompt_invalidate_git_topology_for_path() {
  local directory="$1"

  _ai_candy_record_git_topology_invalidation "$directory" || true
  _AI_CANDY_PP_CACHED_GIT_ROOT=""
  _AI_CANDY_SMART_PATH_CONTEXT_KEY=""
  _AI_CANDY_SMART_PATH_CONTEXT_TIMESTAMP=0
}

function _ai_candy_prompt_apply_git_cache_invalidation() {
  emulate -L zsh
  setopt localoptions noerrexit noerrreturn
  (( _AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE )) || return 0

  local git_root="$_AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE_ROOT"
  local command_path="$_AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE_PATH"
  local invalidate_topology="$_AI_CANDY_PROMPT_GIT_TOPOLOGY_INVALIDATE"
  local invalidate_remote="$_AI_CANDY_PROMPT_GIT_REMOTE_INVALIDATE"
  _AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE=0
  _AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE_ROOT=""
  _AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE_PATH=""
  _AI_CANDY_PROMPT_GIT_TOPOLOGY_INVALIDATE=0
  _AI_CANDY_PROMPT_GIT_REMOTE_INVALIDATE=0

  (( invalidate_topology )) && _ai_candy_prompt_invalidate_git_topology_for_path "$command_path"
  [[ -n "$git_root" ]] && _ai_candy_prompt_invalidate_git_status_cache_for_root "$git_root"
  (( invalidate_remote )) && _ai_candy_prompt_invalidate_git_remote_cache_for_root "$git_root"
  return 0
}

# Capture exit status before any other precmd runs
# IMPORTANT: Must be FIRST in precmd_functions to capture $? before other hooks modify it
_AI_CANDY_LAST_EXIT_STATUS=0
function _ai_candy_capture_exit_status() {
  _AI_CANDY_LAST_EXIT_STATUS=$?
  return 0
}
# Insert at the BEGINNING of precmd_functions array (not using add-zsh-hook which appends)
# This ensures we capture $? before other hooks (like zsh-syntax-highlighting) can modify it
autoload -Uz add-zsh-hook
# Ensure precmd_functions exists (for set -u compatibility)
typeset -ga precmd_functions
precmd_functions=(${precmd_functions[@]:#_ai_candy_capture_exit_status})
precmd_functions=(${precmd_functions[@]:#_ai_candy_prompt_apply_git_cache_invalidation})
precmd_functions=(
  _ai_candy_capture_exit_status
  _ai_candy_prompt_apply_git_cache_invalidation
  ${precmd_functions[@]}
)

# Per-prompt render id to avoid recomputing expensive segments multiple times
_AI_CANDY_PROMPT_RENDER_ID=0
function _ai_candy_prompt_bump_render_id() {
  emulate -L zsh
  (( ++_AI_CANDY_PROMPT_RENDER_ID ))
  return 0
}

add-zsh-hook -d preexec _ai_candy_prompt_mark_git_cache_invalidation \
  2>/dev/null || true
add-zsh-hook -d preexec _ai_candy_preexec_cleanup_for_exec \
  2>/dev/null || true
add-zsh-hook -d chpwd _ai_candy_capture_physical_pwd 2>/dev/null || true
add-zsh-hook chpwd _ai_candy_capture_physical_pwd
add-zsh-hook preexec _ai_candy_prompt_mark_git_cache_invalidation
add-zsh-hook preexec _ai_candy_preexec_cleanup_for_exec
add-zsh-hook zshexit _ai_candy_stop_registered_background_jobs
_ai_candy_install_signal_traps
add-zsh-hook precmd _ai_candy_prompt_bump_render_id
# ============================================================================
# PRECOMPUTED PROMPT PARTS - Computed once in precmd, used in PROMPT
# ============================================================================
# These variables are populated by _ai_candy_precmd_compute_prompt and used directly
# in PROMPT to avoid creating subshells for each prompt segment

# Precomputed prompt segment variables
typeset -g _AI_CANDY_PP_VENV=""           # Python virtual environment indicator
typeset -g _AI_CANDY_PP_EXIT=""           # Exit status indicator
typeset -g _AI_CANDY_PP_SSH=""            # SSH indicator
typeset -g _AI_CANDY_PP_USER_HOST=""      # user@host with color
typeset -g _AI_CANDY_PP_PUBLIC_IP=""      # Public IP address (cached)
typeset -g _AI_CANDY_PP_GH_USER=""        # GitHub username badge [Username]
typeset -g _AI_CANDY_PP_BADGE=""          # Host/container badge
typeset -g _AI_CANDY_PP_TIME=""           # Time with dynamic color
typeset -g _AI_CANDY_PP_PATH=""           # Smart path display
typeset -g _AI_CANDY_PP_GIT_INFO=""       # Git branch/status
typeset -g _AI_CANDY_PP_GIT_EXT=""        # Git extended status (ahead/behind/stash)
typeset -g _AI_CANDY_PP_GIT_SPECIAL=""    # Git special state (rebase/merge/etc)
typeset -g _AI_CANDY_PP_PR=""             # GitHub PR status
typeset -g _AI_CANDY_PP_SYSINFO_LEFT=""   # System info (left prompt, long mode only)
typeset -g _AI_CANDY_PP_AI_LEFT=""        # Optional tools in long mode
typeset -g _AI_CANDY_PP_JOBS=""           # Jobs indicator prefix
typeset -g _AI_CANDY_PP_RPROMPT=""        # Right prompt content

# Precompute all prompt segments in precmd (avoids subshells in PROMPT)
# ============================================================================
# PROMPT COMPONENT FUNCTIONS - Extracted for maintainability
# ============================================================================

# Compute Python virtual environment indicator
# Sets: _AI_CANDY_PP_VENV
# Displays: (venv_name) in yellow when a virtual environment is active
function _ai_candy_compute_venv_direct() {
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    local venv_name="${VIRTUAL_ENV:t}"  # Get basename of the path
    _ai_candy_prompt_escape_text "$venv_name"
    venv_name="$REPLY"
    _AI_CANDY_PP_VENV="%{$fg[yellow]%}(${venv_name})%{$reset_color%}"
  else
    _AI_CANDY_PP_VENV=""
  fi
}

# Compute exit status indicator
# Sets: _AI_CANDY_PP_EXIT
function _ai_candy_compute_exit_status_direct() {
  if [[ $_AI_CANDY_LAST_EXIT_STATUS -eq 0 ]]; then
    if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
      _AI_CANDY_PP_EXIT="%{$fg[green]%}[${_AI_CANDY_SYM_CHECK}]%{$reset_color%}"
    else
      _AI_CANDY_PP_EXIT="%{$fg[green]%}[OK]%{$reset_color%}"
    fi
  else
    if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
      _AI_CANDY_PP_EXIT="%{$fg[red]%}[${_AI_CANDY_SYM_CROSS}${_AI_CANDY_LAST_EXIT_STATUS}]%{$reset_color%}"
    else
      _AI_CANDY_PP_EXIT="%{$fg[red]%}[ERR${_AI_CANDY_LAST_EXIT_STATUS}]%{$reset_color%}"
    fi
  fi
}

# Compute time with dynamic color based on hour
# Sets: _AI_CANDY_PP_TIME
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
    time_color="%{$FG[$_AI_CANDY_CLR_TIME_MORNING]%}"
  elif (( hour_value >= 12 && hour_value < 18 )); then
    time_color="%{$FG[$_AI_CANDY_CLR_TIME_AFTERNOON]%}"
  elif (( hour_value >= 18 && hour_value < 22 )); then
    time_color="%{$FG[$_AI_CANDY_CLR_TIME_EVENING]%}"
  else
    time_color="%{$FG[$_AI_CANDY_CLR_TIME_NIGHT]%}"
  fi
  _AI_CANDY_PP_TIME="${time_color}[%D{%H:%M:%S %Z}]%{$reset_color%}"
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
# Sets: _AI_CANDY_PP_BADGE, _AI_CANDY_PP_SYSINFO_LEFT, _AI_CANDY_PP_AI_LEFT, _AI_CANDY_PP_RPROMPT
# May recompute: _AI_CANDY_PP_PATH (in min mode)
function _ai_candy_compute_layout_mode() {
  # Use precomputed sysinfo from global variables
  # In emoji mode, use versions with distro/kernel icons (, , , , )
  local os_long os_short kernel_long kernel_short
  if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
    os_long="$_AI_CANDY_PP_SYSINFO_OS_LONG_EMOJI"
    os_short="$_AI_CANDY_PP_SYSINFO_OS_SHORT_EMOJI"
    kernel_long="$_AI_CANDY_PP_SYSINFO_KERNEL_LONG_EMOJI"
    kernel_short="$_AI_CANDY_PP_SYSINFO_KERNEL_SHORT_EMOJI"
  else
    os_long="$_AI_CANDY_PP_SYSINFO_OS_LONG"
    os_short="$_AI_CANDY_PP_SYSINFO_OS_SHORT"
    kernel_long="$_AI_CANDY_PP_SYSINFO_KERNEL_LONG"
    kernel_short="$_AI_CANDY_PP_SYSINFO_KERNEL_SHORT"
  fi
  if (( ! _AI_CANDY_PROMPT_OS_MODE )); then
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
    (( _AI_CANDY_PROMPT_EMOJI_MODE )) && badge_icon="$_AI_CANDY_NF_CONTAINER" || badge_icon="C"
    badge_color="%{$fg[magenta]%}"
  elif [[ "${XDG_SESSION_TYPE:-}" == "tty" ]]; then
    # TTY session
    (( _AI_CANDY_PROMPT_EMOJI_MODE )) && badge_icon="$_AI_CANDY_NF_TTY" || badge_icon="T"
    badge_color="%{$fg[yellow]%}"
  elif [[ "$_desktop_lower" == *gnome* ]]; then
    # GNOME desktop (matches gnome, gnome-xorg, gnome-wayland, etc.)
    (( _AI_CANDY_PROMPT_EMOJI_MODE )) && badge_icon="$_AI_CANDY_NF_GNOME" || badge_icon="G"
    badge_color="%{$fg[yellow]%}"
  elif [[ "$_desktop_lower" == *kde* || "$_desktop_lower" == *plasma* ]]; then
    # KDE Plasma desktop
    (( _AI_CANDY_PROMPT_EMOJI_MODE )) && badge_icon="$_AI_CANDY_NF_KDE" || badge_icon="K"
    badge_color="%{$fg[yellow]%}"
  elif [[ "$_desktop_lower" == *xfce* ]]; then
    # XFCE desktop
    (( _AI_CANDY_PROMPT_EMOJI_MODE )) && badge_icon="$_AI_CANDY_NF_XFCE" || badge_icon="X"
    badge_color="%{$fg[yellow]%}"
  elif [[ "$_desktop_lower" == *xorg* ]]; then
    # Xorg session (generic X11)
    (( _AI_CANDY_PROMPT_EMOJI_MODE )) && badge_icon="$_AI_CANDY_NF_XORG" || badge_icon="O"
    badge_color="%{$fg[yellow]%}"
  else
    # Default: Host
    (( _AI_CANDY_PROMPT_EMOJI_MODE )) && badge_icon="$_AI_CANDY_SYM_HOST" || badge_icon="H"
    badge_color="%{$fg[yellow]%}"
  fi
  # In emoji mode, strip trailing space from Nerd Font environment icons
  (( _AI_CANDY_PROMPT_EMOJI_MODE )) && badge_icon="${badge_icon% }"
  _AI_CANDY_PP_BADGE=" ${badge_color}${badge_icon}%{$reset_color%}"

  # Parse the path once so layout can use its visible length before rendering.
  _ai_candy_prepare_smart_path_context

  # Calculate visible lengths (remove all prompt escape sequences)
  # NOTE: For segments containing %n, %m, %j etc., we must use actual values
  # Strips: %{...%}, %B/%b (bold), %U/%u (underline), %S/%s (standout),
  #         %F{...}/%f (fg color), %K{...}/%k (bg color)
  local git_len git_ext_len git_special_len ai_len ai_len_long pr_len
  local venv_len
  local path_len="${_AI_CANDY_SMART_PATH_TOTAL_LENGTH:-0}"
  local user_host_len gh_user_len exit_len ssh_len
  _ai_candy_prompt_markup_width "$_AI_CANDY_PP_GIT_INFO"; git_len="$REPLY"
  _ai_candy_prompt_markup_width "$_AI_CANDY_PP_GIT_EXT"; git_ext_len="$REPLY"
  _ai_candy_prompt_markup_width "$_AI_CANDY_PP_GIT_SPECIAL"; git_special_len="$REPLY"
  _ai_candy_prompt_markup_width "$_AI_CANDY_PP_AI_STATUS"; ai_len="$REPLY"
  _ai_candy_prompt_markup_width "$_AI_CANDY_PP_AI_STATUS_LONG"; ai_len_long="$REPLY"
  _ai_candy_prompt_markup_width "$_AI_CANDY_PP_PR"; pr_len="$REPLY"
  _ai_candy_prompt_markup_width "$_AI_CANDY_PP_GH_USER"; gh_user_len="$REPLY"
  _ai_candy_prompt_markup_width "$_AI_CANDY_PP_EXIT"; exit_len="$REPLY"
  _ai_candy_prompt_markup_width "$_AI_CANDY_PP_SSH"; ssh_len="$REPLY"
  _ai_candy_prompt_markup_width "$_AI_CANDY_PP_VENV"; venv_len="$REPLY"

  # user@host: %n@%m expands to actual username and hostname
  # Use actual values instead of literal "%n@%m" (4 chars)
  local actual_user="${(%):-%n}"
  local actual_host="${(%):-%m}"
  _ai_candy_prompt_text_width "${actual_user}@${actual_host}"
  user_host_len="$REPLY"

  # public_ip_len: (xxx.xxx.xxx.xxx) up to 17 chars, or (offline) 9 chars, or empty
  # NOTE: IPv4 only - see _ai_candy_public_ip_update_background for rationale
  local public_ip_len=0
  if [[ -n "$_AI_CANDY_PP_PUBLIC_IP" ]]; then
    _ai_candy_prompt_markup_width "$_AI_CANDY_PP_PUBLIC_IP"
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
  #   - _AI_CANDY_LAYOUT_MARGIN buffer to trigger shorter format before overflow
  _ai_candy_prompt_text_width " ${badge_icon}"
  local fixed_len=$((2 + _AI_CANDY_LAYOUT_MARGIN)) badge_len="$REPLY"

  # min_len excludes system info and optional tools.
  # pr_space: 1 space before PR if PR is present
  local pr_space=0
  (( pr_len > 0 )) && pr_space=1
  local min_len=$((venv_len + exit_len + ssh_len + user_host_len + public_ip_len + gh_user_len + badge_len + time_len + path_len + git_len + git_ext_len + git_special_len + pr_space + pr_len + fixed_len))

  # Calculate lengths for different layout modes
  local short_version="${os_short}${kernel_short}"
  local short_sysinfo_len=0
  if (( _AI_CANDY_PROMPT_OS_MODE )); then
    _ai_candy_prompt_text_width " [${short_version}]"
    short_sysinfo_len="$REPLY"
  fi
  local short_len=$((min_len + short_sysinfo_len))

  local ai_space=0
  [[ -n "$_AI_CANDY_PP_AI_STATUS" ]] && ai_space=1
  local short_ai_len=$((short_len + ai_len + ai_space))

  local long_version="${os_long}${kernel_long}"
  local long_sysinfo_len=0
  if (( _AI_CANDY_PROMPT_OS_MODE )); then
    _ai_candy_prompt_text_width " [${long_version}]"
    long_sysinfo_len="$REPLY"
  fi
  local long_len=$((min_len + long_sysinfo_len + ai_len + ai_space))
  local long_len_with_long_ai=$((min_len + long_sysinfo_len + ai_len_long + ai_space))

  # Decide layout mode
  local mode system_info ai_output=""

  if (( long_len <= COLUMNS )); then
    mode="long"
    (( _AI_CANDY_PROMPT_OS_MODE )) && system_info=" %{$fg[cyan]%}[${long_version}]%{$reset_color%}"
    if (( ! _AI_CANDY_PROMPT_EMOJI_MODE )) && [[ -n "$_AI_CANDY_PP_AI_STATUS_LONG" ]] && (( long_len_with_long_ai <= COLUMNS )); then
      ai_output=" $_AI_CANDY_PP_AI_STATUS_LONG"
    elif [[ -n "$_AI_CANDY_PP_AI_STATUS" ]]; then
      ai_output=" $_AI_CANDY_PP_AI_STATUS"
    fi
  elif (( short_ai_len <= COLUMNS )); then
    mode="short"
    (( _AI_CANDY_PROMPT_OS_MODE )) && system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
    [[ -n "$_AI_CANDY_PP_AI_STATUS" ]] && ai_output=" $_AI_CANDY_PP_AI_STATUS"
  elif (( short_len <= COLUMNS )); then
    mode="short"
    (( _AI_CANDY_PROMPT_OS_MODE )) && system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
    # Omit optional tools when they would overflow.
  else
    mode="min"
    (( _AI_CANDY_PROMPT_OS_MODE )) && system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
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
    _AI_CANDY_PP_SYSINFO_LEFT="$system_info"
    _AI_CANDY_PP_AI_LEFT="$ai_output"
    _AI_CANDY_PP_RPROMPT=""
  else
    _AI_CANDY_PP_SYSINFO_LEFT=""
    _AI_CANDY_PP_AI_LEFT=""
    _AI_CANDY_PP_RPROMPT="${system_info}${ai_output}"
  fi
}

# ============================================================================
# MAIN PROMPT COMPUTATION - Orchestrates all prompt components
# ============================================================================
# PERFORMANCE: Inline logic and use direct variable assignment to minimize subshells
# Target: reduce from 10-15 subshells to 2-4 per prompt

# Per-prompt git root cache (avoids repeated _ai_candy_get_cached_git_root calls)
typeset -g _AI_CANDY_PP_CACHED_GIT_ROOT=""

function _ai_candy_precmd_compute_prompt() {
  emulate -L zsh
  setopt localoptions noerrexit noerrreturn

  # Cache git root once per prompt (used by multiple functions)
  _ai_candy_get_cached_git_root
  _AI_CANDY_PP_CACHED_GIT_ROOT="$REPLY"

  # === Status indicators ===
  _ai_candy_compute_venv_direct
  _ai_candy_compute_exit_status_direct

  # SSH indicator
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    (( _AI_CANDY_PROMPT_EMOJI_MODE )) && _AI_CANDY_PP_SSH="%{$fg[cyan]%}${_AI_CANDY_NF_SSH}%{$reset_color%}" || _AI_CANDY_PP_SSH="%{$fg[cyan]%}[SSH]%{$reset_color%} "
  else
    _AI_CANDY_PP_SSH=""
  fi

  # User@host
  _AI_CANDY_PP_USER_HOST="%{$FG[$_AI_CANDY_CLR_USER_HOST]%}%n@%m%{$reset_color%}"

  # Public IP address (cached)
  _ai_candy_compute_public_ip_direct

  # GitHub username badge
  _ai_candy_compute_gh_username_direct

  # Time with dynamic color
  _ai_candy_compute_time_direct

  # Jobs indicator
  (( _AI_CANDY_PROMPT_EMOJI_MODE )) && _AI_CANDY_PP_JOBS="$_AI_CANDY_SYM_JOBS" || _AI_CANDY_PP_JOBS="J"

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
_AI_CANDY_PROMPT_GH_PR_CACHE=""
_AI_CANDY_PROMPT_GH_PR_CACHE_ID=-1
_AI_CANDY_PROMPT_GIT_SPECIAL_CACHE=""
_AI_CANDY_PROMPT_GIT_SPECIAL_CACHE_ID=-1
_AI_CANDY_PROMPT_GIT_SPECIAL_CACHE_CONTEXT=""

# System info cache (file-based, uses _AI_CANDY_CACHE_TTL_LOW - rarely changes)
# (_AI_CANDY_SYSINFO_CACHE_FILE defined in CACHE FILE PATHS section)

# Global variables for direct sysinfo assignment (avoids subshell)
typeset -g _AI_CANDY_PP_SYSINFO_OS_LONG=""
typeset -g _AI_CANDY_PP_SYSINFO_OS_SHORT=""
typeset -g _AI_CANDY_PP_SYSINFO_OS_LONG_EMOJI=""
typeset -g _AI_CANDY_PP_SYSINFO_OS_SHORT_EMOJI=""
typeset -g _AI_CANDY_PP_SYSINFO_KERNEL_LONG=""
typeset -g _AI_CANDY_PP_SYSINFO_KERNEL_SHORT=""
typeset -g _AI_CANDY_PP_SYSINFO_KERNEL_LONG_EMOJI=""
typeset -g _AI_CANDY_PP_SYSINFO_KERNEL_SHORT_EMOJI=""

# Nerd Font icons for OS/distro (using hex byte escapes for portability)
# macOS U+F0036 (nf-md-apple_finder), Darwin U+F179, Red Hat U+EF5D, Ubuntu U+EF72
# CentOS U+EF3D, Fedora U+F30A, AlmaLinux U+F31D, Linux U+F17C
typeset -g _AI_CANDY_NF_MACOS=$'\xf3\xb0\x80\xb6'  # U+F0036 nf-md-apple_finder
typeset -g _AI_CANDY_NF_APPLE=$'\xef\x85\xb9'      # U+F179 nf-fa-apple (for Darwin kernel)
typeset -g _AI_CANDY_NF_REDHAT=$'\xee\xbd\x9d'     # U+EF5D
typeset -g _AI_CANDY_NF_UBUNTU=$'\xee\xbd\xb2'     # U+EF72
typeset -g _AI_CANDY_NF_CENTOS=$'\xee\xbc\xbd'     # U+EF3D
typeset -g _AI_CANDY_NF_FEDORA=$'\xef\x8c\x8a'     # U+F30A
typeset -g _AI_CANDY_NF_ALMA=$'\xef\x8c\x9d'       # U+F31D
typeset -g _AI_CANDY_NF_LINUX=$'\xef\x85\xbc'      # U+F17C

# Optional tool icons use byte escapes for source portability.
typeset -g _AI_CANDY_NF_CLAUDE=$'\xef\x81\xa9 '    # U+F069 nf-fa-asterisk (+ space for 2-char width)
typeset -g _AI_CANDY_NF_GEMINI=$'\xef\x86\xa0 '    # U+F1A0 nf-fa-google (+ space for 2-char width)
typeset -g _AI_CANDY_NF_CODEX=$'\xee\x89\xbf '     # U+E27F nf-fae-atom (+ space for 2-char width)
typeset -g _AI_CANDY_NF_KIMI=$'\xef\x86\x86 '      # U+F186 nf-fa-moon_o (+ space for 2-char width)
typeset -g _AI_CANDY_NF_CONTAINER=$'\xef\x88\x9f'  # U+F21F nf-fa-docker
typeset -g _AI_CANDY_NF_SSH=$'\xf3\xb0\xa3\x80 '   # U+F08C0 nf-md-ssh (+ space for 2-char width)
typeset -g _AI_CANDY_NF_GITHUB=$'\xef\x82\x9b '    # U+F09B nf-fa-github (+ space for 2-char width)
typeset -g _AI_CANDY_NF_TTY=$'\xef\x87\xa4'        # U+F1E4 nf-fa-tty
typeset -g _AI_CANDY_NF_GNOME=$'\xef\x8d\xa1 '     # U+F361 nf-linux-gnome (+ space for 2-char width)
typeset -g _AI_CANDY_NF_KDE=$'\xef\x8c\xb2'        # U+F332 nf-linux-kde_plasma
typeset -g _AI_CANDY_NF_XFCE=$'\xef\x8d\xa8'       # U+F368 nf-linux-xfce
typeset -g _AI_CANDY_NF_XORG=$'\xef\x8d\xa9'       # U+F369 nf-linux-xorg

# Helper: Apply OS/distro icon replacements for emoji mode
_ai_candy_sysinfo_apply_os_icons() {
  local input="$1"
  # Distro replacements (order matters - more specific first)
  input="${input//macOS/${_AI_CANDY_NF_MACOS}}"
  input="${input//Red Hat Enterprise Linux/${_AI_CANDY_NF_REDHAT}}"
  input="${input//Rhel/${_AI_CANDY_NF_REDHAT}}"
  input="${input//Ubuntu/${_AI_CANDY_NF_UBUNTU}}"
  input="${input//CentOS/${_AI_CANDY_NF_CENTOS}}"
  input="${input//Centos/${_AI_CANDY_NF_CENTOS}}"
  input="${input//Fedora/${_AI_CANDY_NF_FEDORA}}"
  input="${input//AlmaLinux/${_AI_CANDY_NF_ALMA}}"
  input="${input//Almalinux/${_AI_CANDY_NF_ALMA}}"
  REPLY="$input"
}

# Kernel icons
_ai_candy_sysinfo_apply_kernel_icons() {
  local input="$1"
  input="${input//Darwin/${_AI_CANDY_NF_APPLE}}"
  input="${input//Linux/${_AI_CANDY_NF_LINUX}}"
  REPLY="$input"
}

function _ai_candy_sysinfo_set_emoji_variants() {
  _ai_candy_sysinfo_apply_os_icons "$_AI_CANDY_PP_SYSINFO_OS_LONG"
  _AI_CANDY_PP_SYSINFO_OS_LONG_EMOJI="$REPLY"
  _ai_candy_sysinfo_apply_os_icons "$_AI_CANDY_PP_SYSINFO_OS_SHORT"
  _AI_CANDY_PP_SYSINFO_OS_SHORT_EMOJI="$REPLY"
  _ai_candy_sysinfo_apply_kernel_icons "$_AI_CANDY_PP_SYSINFO_KERNEL_LONG"
  _AI_CANDY_PP_SYSINFO_KERNEL_LONG_EMOJI="$REPLY"
  _ai_candy_sysinfo_apply_kernel_icons "$_AI_CANDY_PP_SYSINFO_KERNEL_SHORT"
  _AI_CANDY_PP_SYSINFO_KERNEL_SHORT_EMOJI="$REPLY"
}

typeset -g _AI_CANDY_SYSINFO_SESSION_READY=0

# Direct-assignment version: writes result to _AI_CANDY_PP_SYSINFO_* global variables
# PERFORMANCE: Avoids 1 subshell by parsing cache directly into variables
function _ai_candy_compute_sysinfo_direct() {
  (( _AI_CANDY_PROMPT_OS_MODE )) || return 0
  (( _AI_CANDY_SYSINFO_SESSION_READY )) && return 0
  local current_time=${EPOCHSECONDS}

  # Check file cache (use zsh native file reading)
  if _ai_candy_cache_read_small_file "$_AI_CANDY_SYSINFO_CACHE_FILE"; then
    local cache_lines=("${(@f)REPLY}")
    local cache_time="${cache_lines[1]-}"
    if _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_AI_CANDY_CACHE_TTL_LOW" "$current_time"; then
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
          _AI_CANDY_PP_SYSINFO_OS_LONG="$REPLY"
          _ai_candy_prompt_escape_text "${decoded_fields[2]}"
          _AI_CANDY_PP_SYSINFO_OS_SHORT="$REPLY"
          _ai_candy_prompt_escape_text "${decoded_fields[3]}"
          _AI_CANDY_PP_SYSINFO_KERNEL_LONG="$REPLY"
          _ai_candy_prompt_escape_text "${decoded_fields[4]}"
          _AI_CANDY_PP_SYSINFO_KERNEL_SHORT="$REPLY"
          _ai_candy_sysinfo_set_emoji_variants
          _AI_CANDY_SYSINFO_SESSION_READY=1
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
  _ai_candy_cache_write "$_AI_CANDY_SYSINFO_CACHE_FILE" "${current_time}"$'\n'"${result}" 0 || true

  _ai_candy_prompt_escape_text "$os_long"
  os_long="$REPLY"
  _ai_candy_prompt_escape_text "$os_short"
  os_short="$REPLY"
  _ai_candy_prompt_escape_text "$kernel_long"
  kernel_long="$REPLY"
  _ai_candy_prompt_escape_text "$kernel_short"
  kernel_short="$REPLY"

  # Assign to global variables
  _AI_CANDY_PP_SYSINFO_OS_LONG="$os_long"
  _AI_CANDY_PP_SYSINFO_OS_SHORT="$os_short"
  _AI_CANDY_PP_SYSINFO_KERNEL_LONG="$kernel_long"
  _AI_CANDY_PP_SYSINFO_KERNEL_SHORT="$kernel_short"
  # Generate emoji versions with OS/distro and kernel icons
  _ai_candy_sysinfo_set_emoji_variants
  _AI_CANDY_SYSINFO_SESSION_READY=1
}
typeset -g _AI_CANDY_USE_OMZ_ASYNC=0
typeset -g _AI_CANDY_GIT_TOPOLOGY_GENERATION=0
typeset -g _AI_CANDY_GIT_TOPOLOGY_GENERATION_VALID=1
typeset -g _AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE="${_AI_CANDY_CACHE_DIR}/git_topology_generation"
typeset -g _AI_CANDY_GIT_METADATA_MAX_BYTES=$((16 * 1024))
typeset -gi _AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE=1
typeset -gi _AI_CANDY_GIT_METADATA_CONTEXT_PERSISTABLE=1
typeset -gi _AI_CANDY_GIT_METADATA_PROBE_FAILED=0
typeset -gi _AI_CANDY_GIT_VOLATILE_CONFIG_SEQUENCE
typeset -gA _AI_CANDY_GIT_VOLATILE_CONFIG_CONTENT_BY_PATH
typeset -gA _AI_CANDY_GIT_VOLATILE_CONFIG_GENERATION_BY_PATH
typeset -gA _AI_CANDY_GIT_VOLATILE_CONFIG_STAT_BY_PATH
typeset -gA _AI_CANDY_GIT_VOLATILE_CONFIG_STABLE_BY_PATH
typeset -gi _AI_CANDY_GIT_CONTEXT_KEY_RENDER_ID=-1
typeset -g _AI_CANDY_GIT_CONTEXT_KEY_INPUT=""
typeset -g _AI_CANDY_GIT_CONTEXT_KEY_VALUE=""

function _ai_candy_read_git_metadata_file() {
  emulate -L zsh
  local LC_ALL=C
  local metadata_file="$1"
  local configured_limit="${_AI_CANDY_GIT_METADATA_MAX_BYTES:-16384}"
  local content=""
  REPLY=""

  if [[ "$configured_limit" != <-> || ${#configured_limit} -gt 5 ]] || \
     (( configured_limit < 1024 || configured_limit > 65536 )); then
    configured_limit=16384
  fi
  [[ -f "$metadata_file" && ! -L "$metadata_file" ]] || return 1
  if (( _AI_CANDY_HAS_ZSH_STAT_BUILTIN )); then
    local -a metadata
    builtin zstat -A metadata +size -- "$metadata_file" 2>/dev/null || return 1
    [[ "${metadata[1]-}" == <-> ]] || return 1
    (( metadata[1] <= configured_limit )) || return 1
    content="$(<"$metadata_file")"
  else
    local _AI_CANDY_TIMEOUT_OUTPUT_MAX_BYTES="$configured_limit"
    content=$(_ai_candy_run_local_probe \
      /bin/cat "$metadata_file" 2>/dev/null) || return 1
  fi
  (( ${#content} <= configured_limit )) || return 1
  REPLY="$content"
}

function _ai_candy_read_git_topology_generation() {
  REPLY=0
  if [[ ! -e "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE" && \
        ! -L "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE" ]]; then
    return 0
  fi
  [[ -f "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE" && \
     ! -L "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE" ]] || return 1
  _ai_candy_cache_read_small_file "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE" || return 1
  local generation="$REPLY"
  _ai_candy_cache_generation_token_is_valid "$generation" || return 1
  REPLY="$generation"
}

function _ai_candy_apply_git_topology_generation() {
  local generation="$1"
  _ai_candy_cache_generation_token_is_valid "$generation" || return 1
  [[ "$generation" == "$_AI_CANDY_GIT_TOPOLOGY_GENERATION" ]] && return 0

  _AI_CANDY_GIT_TOPOLOGY_GENERATION="$generation"
  _AI_CANDY_MEM_CACHE_GIT_ROOT=()
  _AI_CANDY_MEM_CACHE_GIT_ROOT_GENERATION=()
  _AI_CANDY_MEM_CACHE_GIT_HIERARCHY=()
  _AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT=()
  _AI_CANDY_PP_CACHED_GIT_ROOT=""
  _AI_CANDY_SMART_PATH_CONTEXT_KEY=""
  _AI_CANDY_SMART_PATH_CONTEXT_TIMESTAMP=0
}

function _ai_candy_publish_git_topology_generation() {
  local generation="$1"

  (( _AI_CANDY_CACHE_READY )) || return 1
  _ai_candy_cache_generation_token_is_valid "$generation" || return 1
  if [[ -e "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE" || \
        -L "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE" ]]; then
    [[ -f "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE" && \
       ! -L "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE" ]] || return 1
  fi
  _ai_candy_cache_atomic_write_unlocked "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE" \
    "$generation"
}

function _ai_candy_sync_git_topology_generation() {
  (( _AI_CANDY_CACHE_READY )) || return 1
  if (( ! _AI_CANDY_GIT_TOPOLOGY_GENERATION_VALID )); then
    _ai_candy_cache_new_generation_token || return 1
    _ai_candy_apply_git_topology_generation "$REPLY"
    if _ai_candy_publish_git_topology_generation "$_AI_CANDY_GIT_TOPOLOGY_GENERATION"; then
      _AI_CANDY_GIT_TOPOLOGY_GENERATION_VALID=1
      return 0
    fi
    return 1
  fi
  if _ai_candy_read_git_topology_generation; then
    _AI_CANDY_GIT_TOPOLOGY_GENERATION_VALID=1
    _ai_candy_apply_git_topology_generation "$REPLY"
    return 0
  fi
  _ai_candy_cache_new_generation_token || return 1
  _ai_candy_apply_git_topology_generation "$REPLY"
  _AI_CANDY_GIT_TOPOLOGY_GENERATION_VALID=0
  if _ai_candy_publish_git_topology_generation "$_AI_CANDY_GIT_TOPOLOGY_GENERATION"; then
    _AI_CANDY_GIT_TOPOLOGY_GENERATION_VALID=1
    return 0
  fi
  return 1
}

function _ai_candy_git_topology_generation_for_path() {
  REPLY="$_AI_CANDY_GIT_TOPOLOGY_GENERATION"
}

function _ai_candy_record_git_topology_invalidation() {
  local invalidated_path="$1"

  [[ "$invalidated_path" == /* ]] || return 1
  _ai_candy_cache_new_generation_token || return 1
  local next_generation="$REPLY"
  _ai_candy_apply_git_topology_generation "$next_generation"
  if _ai_candy_publish_git_topology_generation "$next_generation"; then
    _AI_CANDY_GIT_TOPOLOGY_GENERATION_VALID=1
  else
    _AI_CANDY_GIT_TOPOLOGY_GENERATION_VALID=0
  fi
  return 0
}

function _ai_candy_git_config_override_context_key() {
  emulate -L zsh
  local LC_ALL=C
  local resolution_base="${1:-${_AI_CANDY_PHYSICAL_PWD:-$PWD}}"
  local command_resolution_base="${2:-$resolution_base}"
  local parameter_name="" parameter_value="" resolved_path="" path_base=""
  local count_value="${GIT_CONFIG_COUNT-}"
  local key_name="" value_name="" key_value="" config_value=""
  local -a fixed_parameters=(
    GIT_CONFIG
    GIT_CONFIG_GLOBAL
    GIT_CONFIG_SYSTEM
    GIT_CONFIG_NOSYSTEM
    GIT_CONFIG_PARAMETERS
  )
  integer index=0 entry_count=0 max_entries=128
  resolution_base="${resolution_base:A}"
  command_resolution_base="${command_resolution_base:A}"
  REPLY=""

  for parameter_name in "${fixed_parameters[@]}"; do
    (( ${+parameters[$parameter_name]} )) || continue
    parameter_value="${(P)parameter_name}"
    REPLY+="n${#parameter_name}:${parameter_name}"
    REPLY+="v${#parameter_value}:${parameter_value}"
    case "$parameter_name" in
      GIT_CONFIG|GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM)
        resolved_path="$parameter_value"
        if [[ -n "$resolved_path" ]]; then
          path_base="$resolution_base"
          [[ "$parameter_name" == GIT_CONFIG ]] && \
            path_base="$command_resolution_base"
          [[ "$resolved_path" == /* ]] || \
            resolved_path="${path_base}/${resolved_path}"
          resolved_path="${resolved_path:A}"
        fi
        REPLY+="p${#resolved_path}:${resolved_path}"
        ;;
    esac
  done

  if (( ${+GIT_CONFIG_COUNT} )); then
    REPLY+="n16:GIT_CONFIG_COUNTv${#count_value}:${count_value}"
    if [[ "$count_value" == <-> && ${#count_value} -le 3 ]] && \
       (( 10#$count_value <= max_entries )); then
      entry_count=$(( 10#$count_value ))
      for (( index=0; index<entry_count; index++ )); do
        key_name="GIT_CONFIG_KEY_${index}"
        value_name="GIT_CONFIG_VALUE_${index}"
        key_value=""
        config_value=""
        if (( ${+parameters[$key_name]} )); then
          key_value="${(P)key_name}"
          REPLY+="k1:${#key_value}:${key_value}"
        else
          REPLY+="k0:0:"
        fi
        if (( ${+parameters[$value_name]} )); then
          config_value="${(P)value_name}"
          REPLY+="v1:${#config_value}:${config_value}"
        else
          REPLY+="v0:0:"
        fi
      done
    else
      REPLY+="x${_AI_CANDY_PROMPT_RENDER_ID:-0}"
    fi
  fi
}

function _ai_candy_git_discovery_context_key() {
  emulate -L zsh
  local LC_ALL=C
  local git_dir="${GIT_DIR-}"
  local git_work_tree="${GIT_WORK_TREE-}"
  local git_common_dir="${GIT_COMMON_DIR-}"
  local git_ceiling="${GIT_CEILING_DIRECTORIES-}"
  local git_across_filesystems="${GIT_DISCOVERY_ACROSS_FILESYSTEM-}"
  local relative_base=""
  local resolved_git_dir=""
  local resolved_git_work_tree=""
  local resolved_git_common_dir=""
  integer has_config_override=$((
    ${+GIT_CONFIG} || ${+GIT_CONFIG_GLOBAL} || ${+GIT_CONFIG_SYSTEM} ||
    ${+GIT_CONFIG_NOSYSTEM} || ${+GIT_CONFIG_PARAMETERS} ||
    ${+GIT_CONFIG_COUNT}
  ))

  if (( ! ${+GIT_DIR} && ! ${+GIT_WORK_TREE} && ! ${+GIT_COMMON_DIR} && \
        ! ${+GIT_CEILING_DIRECTORIES} && \
        ! ${+GIT_DISCOVERY_ACROSS_FILESYSTEM} && ! has_config_override )); then
    REPLY=""
    return 0
  fi

  if [[ ( -n "$git_dir" && "$git_dir" != /* ) || \
        ( -n "$git_work_tree" && "$git_work_tree" != /* ) || \
        ( -n "$git_common_dir" && "$git_common_dir" != /* ) ]]; then
    relative_base="${_AI_CANDY_PHYSICAL_PWD:-${PWD:A}}"
  fi

  if [[ -n "$git_dir" ]]; then
    resolved_git_dir="$git_dir"
    if [[ "$resolved_git_dir" != /* ]]; then
      resolved_git_dir="${relative_base}/${resolved_git_dir}"
    fi
    resolved_git_dir="${resolved_git_dir:A}"
  fi
  if [[ -n "$git_work_tree" ]]; then
    resolved_git_work_tree="$git_work_tree"
    if [[ "$resolved_git_work_tree" != /* ]]; then
      resolved_git_work_tree="${relative_base}/${resolved_git_work_tree}"
    fi
    resolved_git_work_tree="${resolved_git_work_tree:A}"
  fi
  if [[ -n "$git_common_dir" ]]; then
    resolved_git_common_dir="$git_common_dir"
    if [[ "$resolved_git_common_dir" != /* ]]; then
      resolved_git_common_dir="${relative_base}/${resolved_git_common_dir}"
    fi
    resolved_git_common_dir="${resolved_git_common_dir:A}"
  fi

  REPLY="g${has_config_override}d${+GIT_DIR}:${#git_dir}:${git_dir}"
  REPLY+="w${+GIT_WORK_TREE}:${#git_work_tree}:${git_work_tree}"
  REPLY+="c${+GIT_COMMON_DIR}:${#git_common_dir}:${git_common_dir}"
  REPLY+="l${+GIT_CEILING_DIRECTORIES}:${#git_ceiling}:${git_ceiling}"
  REPLY+="a${+GIT_DISCOVERY_ACROSS_FILESYSTEM}:"
  REPLY+="${#git_across_filesystems}:${git_across_filesystems}"
  REPLY+="p${#relative_base}:${relative_base}"
  REPLY+="D${#resolved_git_dir}:${resolved_git_dir}"
  REPLY+="W${#resolved_git_work_tree}:${resolved_git_work_tree}"
  REPLY+="C${#resolved_git_common_dir}:${resolved_git_common_dir}"
  if (( has_config_override )); then
    local discovery_context="$REPLY"
    _ai_candy_git_config_override_context_key
    local config_override_context="$REPLY"
    REPLY="$discovery_context"
    REPLY+="g${#config_override_context}:${config_override_context}"
  fi
}

function _ai_candy_git_context_cache_key() {
  local git_root="$1"
  local home_value="${HOME-}"
  local xdg_config_home="${XDG_CONFIG_HOME-}"
  local discovery_context=""
  local root_config_context=""
  local resolved_git_dir=""
  local resolved_git_common_dir=""
  local external_config_context=""
  local common_config_context=""
  local worktree_config_context=""
  local effective_config_context=""
  local command_resolution_base="${_AI_CANDY_PHYSICAL_PWD:-${PWD:A}}"
  local config_resolution_base="$command_resolution_base"
  local context_cache_input=""
  integer render_id="${_AI_CANDY_PROMPT_RENDER_ID:-0}"

  if (( $# >= 2 )); then
    discovery_context="$2"
  else
    _ai_candy_git_discovery_context_key
    discovery_context="$REPLY"
  fi
  context_cache_input="r${#git_root}:${git_root}"
  context_cache_input+="c${#discovery_context}:${discovery_context}"
  context_cache_input+="h${+HOME}:${#home_value}:${home_value}"
  context_cache_input+="x${+XDG_CONFIG_HOME}:"
  context_cache_input+="${#xdg_config_home}:${xdg_config_home}"
  if (( render_id > 0 && \
        _AI_CANDY_GIT_CONTEXT_KEY_RENDER_ID == render_id )) && \
     [[ "$_AI_CANDY_GIT_CONTEXT_KEY_INPUT" == "$context_cache_input" ]]; then
    REPLY="$_AI_CANDY_GIT_CONTEXT_KEY_VALUE"
    return 0
  fi
  if [[ -n "$git_root" && "$git_root" != "NOT_GIT" ]] && \
     _ai_candy_resolve_git_dir "$git_root"; then
    config_resolution_base="$git_root"
    resolved_git_dir="$REPLY"
    if _ai_candy_resolve_git_common_dir "$git_root" "$resolved_git_dir"; then
      resolved_git_common_dir="$REPLY"
      _ai_candy_git_config_file_context_key \
        "${resolved_git_common_dir}/config"
      common_config_context="$REPLY"
      _ai_candy_git_config_file_context_key \
        "${resolved_git_dir}/config.worktree"
      worktree_config_context="$REPLY"
    fi
  fi
  if [[ "$discovery_context" == g1* && -n "$git_root" && \
        "$git_root" != "NOT_GIT" ]]; then
    _ai_candy_git_config_override_context_key \
      "$config_resolution_base" "$command_resolution_base"
    root_config_context="$REPLY"
  fi
  _ai_candy_git_external_config_context_key \
    "$config_resolution_base" "$command_resolution_base"
  external_config_context="$REPLY"
  if [[ -n "$resolved_git_dir" && -n "$resolved_git_common_dir" ]]; then
    _ai_candy_git_effective_config_context_key \
      "$command_resolution_base" "$git_root" "$resolved_git_dir" \
      "$resolved_git_common_dir" "$discovery_context" \
      "$external_config_context" "$common_config_context" \
      "$worktree_config_context"
    effective_config_context="$REPLY"
  fi

  REPLY="c${#discovery_context}:${discovery_context}"
  REPLY+="r${#git_root}:${git_root}"
  REPLY+="d${#resolved_git_dir}:${resolved_git_dir}"
  REPLY+="m${#resolved_git_common_dir}:${resolved_git_common_dir}"
  REPLY+="h${+HOME}:${#home_value}:${home_value}"
  REPLY+="x${+XDG_CONFIG_HOME}:${#xdg_config_home}:${xdg_config_home}"
  REPLY+="g${#root_config_context}:${root_config_context}"
  REPLY+="e${#external_config_context}:${external_config_context}"
  REPLY+="l${#common_config_context}:${common_config_context}"
  REPLY+="w${#worktree_config_context}:${worktree_config_context}"
  REPLY+="q${#effective_config_context}:${effective_config_context}"
  if (( render_id > 0 )); then
    _AI_CANDY_GIT_CONTEXT_KEY_RENDER_ID="$render_id"
    _AI_CANDY_GIT_CONTEXT_KEY_INPUT="$context_cache_input"
    _AI_CANDY_GIT_CONTEXT_KEY_VALUE="$REPLY"
  fi
}

function _ai_candy_run_git_probe_at_root() {
  emulate -L zsh
  local git_root="$1"
  shift
  local context_pwd="${_AI_CANDY_PHYSICAL_PWD:-${PWD:A}}"
  local resolved_context_path=""

  if (( ${+GIT_DIR} )) && [[ -n "$GIT_DIR" && "$GIT_DIR" != /* ]]; then
    resolved_context_path="${context_pwd}/${GIT_DIR}"
    local -x GIT_DIR="${resolved_context_path:A}"
  fi
  if (( ${+GIT_WORK_TREE} )) && \
     [[ -n "$GIT_WORK_TREE" && "$GIT_WORK_TREE" != /* ]]; then
    resolved_context_path="${context_pwd}/${GIT_WORK_TREE}"
    local -x GIT_WORK_TREE="${resolved_context_path:A}"
  fi
  if (( ${+GIT_COMMON_DIR} )) && \
     [[ -n "$GIT_COMMON_DIR" && "$GIT_COMMON_DIR" != /* ]]; then
    resolved_context_path="${context_pwd}/${GIT_COMMON_DIR}"
    local -x GIT_COMMON_DIR="${resolved_context_path:A}"
  fi
  # Keep GIT_CONFIG anchored to the calling shell when -C changes Git's cwd.
  if (( ${+GIT_CONFIG} )) && \
     [[ -n "$GIT_CONFIG" && "$GIT_CONFIG" != /* ]]; then
    resolved_context_path="${context_pwd}/${GIT_CONFIG}"
    local -x GIT_CONFIG="${resolved_context_path:A}"
  fi
  _ai_candy_run_local_probe git -C "$git_root" "$@"
}

function _ai_candy_git_current_directory_context_key() {
  emulate -L zsh
  local -A metadata
  REPLY=""

  (( _AI_CANDY_HAS_ZSH_STAT_BUILTIN )) || return 1
  builtin zstat -H metadata -- . 2>/dev/null || return 1
  [[ "${metadata[device]-}" == <-> && \
     "${metadata[inode]-}" == <-> ]] || return 1
  REPLY="d${#metadata[device]}:${metadata[device]}"
  REPLY+="i${#metadata[inode]}:${metadata[inode]}"
}

function _ai_candy_git_track_config_generation() {
  emulate -L zsh
  local physical_config_file="$1"
  local stat_signature="$2"
  integer mark_stable="${3:-0}"
  local content_identity=""
  local generation=""
  REPLY=""

  _ai_candy_read_git_metadata_file "$physical_config_file" || return 1
  content_identity="x${REPLY}"
  generation="${_AI_CANDY_GIT_VOLATILE_CONFIG_GENERATION_BY_PATH[$physical_config_file]-}"
  if [[ -z "$generation" ]] && \
     (( ${#_AI_CANDY_GIT_VOLATILE_CONFIG_GENERATION_BY_PATH} >= \
        _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )); then
    _AI_CANDY_GIT_VOLATILE_CONFIG_CONTENT_BY_PATH=()
    _AI_CANDY_GIT_VOLATILE_CONFIG_GENERATION_BY_PATH=()
    _AI_CANDY_GIT_VOLATILE_CONFIG_STAT_BY_PATH=()
    _AI_CANDY_GIT_VOLATILE_CONFIG_STABLE_BY_PATH=()
  fi
  if [[ -z "$generation" || \
        "${_AI_CANDY_GIT_VOLATILE_CONFIG_STABLE_BY_PATH[$physical_config_file]-0}" == 1 || \
        "${_AI_CANDY_GIT_VOLATILE_CONFIG_CONTENT_BY_PATH[$physical_config_file]-}" != \
          "$content_identity" ]]; then
    (( ++_AI_CANDY_GIT_VOLATILE_CONFIG_SEQUENCE ))
    generation="$_AI_CANDY_GIT_VOLATILE_CONFIG_SEQUENCE"
  fi
  _AI_CANDY_GIT_VOLATILE_CONFIG_GENERATION_BY_PATH[$physical_config_file]="$generation"
  _AI_CANDY_GIT_VOLATILE_CONFIG_STAT_BY_PATH[$physical_config_file]="$stat_signature"
  if (( mark_stable )); then
    _AI_CANDY_GIT_VOLATILE_CONFIG_CONTENT_BY_PATH[$physical_config_file]=""
    _AI_CANDY_GIT_VOLATILE_CONFIG_STABLE_BY_PATH[$physical_config_file]=1
  else
    _AI_CANDY_GIT_VOLATILE_CONFIG_CONTENT_BY_PATH[$physical_config_file]="$content_identity"
    _AI_CANDY_GIT_VOLATILE_CONFIG_STABLE_BY_PATH[$physical_config_file]=0
  fi
  REPLY="$generation"
}

function _ai_candy_git_config_file_context_key() {
  emulate -L zsh
  local config_file="$1"
  local physical_config_file="$config_file"
  local config_context=""
  local volatile_generation=""
  local stat_signature=""
  local -A metadata
  integer current_time=$EPOCHSECONDS

  if [[ ! -e "$config_file" && ! -L "$config_file" ]]; then
    REPLY="p${#physical_config_file}:${physical_config_file}e0l0"
    return 0
  fi
  [[ -L "$config_file" ]] && physical_config_file="${config_file:A}"
  config_context="p${#physical_config_file}:${physical_config_file}"

  if (( _AI_CANDY_HAS_ZSH_STAT_BUILTIN )) && \
     builtin zstat -H metadata -- "$config_file" 2>/dev/null; then
    config_context+="d${#metadata[device]}:${metadata[device]}"
    config_context+="i${#metadata[inode]}:${metadata[inode]}"
    config_context+="s${#metadata[size]}:${metadata[size]}"
    config_context+="m${#metadata[mtime]}:${metadata[mtime]}"
    config_context+="c${#metadata[ctime]}:${metadata[ctime]}"
    stat_signature="d${metadata[device]}i${metadata[inode]}"
    stat_signature+="s${metadata[size]}m${metadata[mtime]}c${metadata[ctime]}"
    # Whole-second stat fields cannot distinguish in-place rewrites. A bounded
    # session generation preserves hot caches without persisting config text.
    if (( metadata[mtime] >= current_time || \
          metadata[ctime] >= current_time )); then
      _AI_CANDY_GIT_METADATA_CONTEXT_PERSISTABLE=0
      if _ai_candy_git_track_config_generation \
           "$physical_config_file" "$stat_signature" 0; then
        volatile_generation="$REPLY"
      else
        _AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE=0
      fi
    else
      volatile_generation="${_AI_CANDY_GIT_VOLATILE_CONFIG_GENERATION_BY_PATH[$physical_config_file]-}"
      if [[ -n "$volatile_generation" ]]; then
        _AI_CANDY_GIT_METADATA_CONTEXT_PERSISTABLE=0
        if [[ "${_AI_CANDY_GIT_VOLATILE_CONFIG_STABLE_BY_PATH[$physical_config_file]-0}" != 1 || \
              "${_AI_CANDY_GIT_VOLATILE_CONFIG_STAT_BY_PATH[$physical_config_file]-}" != \
                "$stat_signature" ]]; then
          if _ai_candy_git_track_config_generation \
               "$physical_config_file" "$stat_signature" 1; then
            volatile_generation="$REPLY"
          else
            _AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE=0
          fi
        fi
      fi
    fi
    [[ -n "$volatile_generation" ]] && \
      config_context+="v${#volatile_generation}:${volatile_generation}"
    REPLY="$config_context"
    return 0
  fi
  _AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE=0
  _AI_CANDY_GIT_METADATA_CONTEXT_PERSISTABLE=0
  [[ -e "$config_file" ]] && config_context+="e1" || config_context+="e0"
  [[ -L "$config_file" ]] && config_context+="l1" || config_context+="l0"
  REPLY="$config_context"
}

function _ai_candy_git_external_config_context_key() {
  emulate -L zsh
  local resolution_base="${1:-${_AI_CANDY_PHYSICAL_PWD:-$PWD}}"
  local command_resolution_base="${2:-$resolution_base}"
  local config_path="" resolved_path="" git_executable=""
  local config_file_context="" external_context=""
  local home_value="${HOME-}"
  local xdg_config_home="${XDG_CONFIG_HOME-}"
  local nosystem_value="" nosystem_magnitude=""
  local -a config_paths config_bases system_paths
  local -A seen_paths
  integer config_index=0 path_index=0 skip_system_config=0
  REPLY=""

  [[ "$resolution_base" == /* ]] || resolution_base="${resolution_base:A}"
  [[ "$command_resolution_base" == /* ]] || \
    command_resolution_base="${command_resolution_base:A}"
  if (( ${+GIT_CONFIG} )) && [[ -n "$GIT_CONFIG" ]]; then
    config_paths+=("$GIT_CONFIG")
    config_bases+=("$command_resolution_base")
  fi
  if (( ${+GIT_CONFIG_GLOBAL} )); then
    if [[ -n "$GIT_CONFIG_GLOBAL" ]]; then
      config_paths+=("$GIT_CONFIG_GLOBAL")
      config_bases+=("$resolution_base")
    fi
  else
    if [[ -n "$xdg_config_home" ]]; then
      config_paths+=("${xdg_config_home%/}/git/config")
      config_bases+=("$resolution_base")
    elif [[ -n "$home_value" ]]; then
      config_paths+=("${home_value%/}/.config/git/config")
      config_bases+=("$resolution_base")
    fi
    if [[ -n "$home_value" ]]; then
      config_paths+=("${home_value%/}/.gitconfig")
      config_bases+=("$resolution_base")
    fi
  fi
  if (( ${+GIT_CONFIG_NOSYSTEM} )); then
    nosystem_value="${(L)GIT_CONFIG_NOSYSTEM}"
    case "$nosystem_value" in
      true|yes|on) skip_system_config=1 ;;
      *)
        nosystem_magnitude="$nosystem_value"
        if [[ "$nosystem_magnitude" == [+-]* ]]; then
          nosystem_magnitude="${nosystem_magnitude[2,-1]}"
        fi
        if [[ "$nosystem_magnitude" == <-> &&
              -n "${nosystem_magnitude//0/}" ]]; then
          skip_system_config=1
        fi
        ;;
    esac
  fi
  if (( ! skip_system_config )); then
    if (( ${+GIT_CONFIG_SYSTEM} )); then
      if [[ -n "$GIT_CONFIG_SYSTEM" ]]; then
        config_paths+=("$GIT_CONFIG_SYSTEM")
        config_bases+=("$resolution_base")
      fi
    else
      system_paths=(
        /etc/gitconfig
        /Library/Developer/CommandLineTools/usr/etc/gitconfig
        /Applications/Xcode.app/Contents/Developer/usr/etc/gitconfig
        /opt/homebrew/etc/gitconfig
        /usr/local/etc/gitconfig
        /opt/local/etc/gitconfig
      )
      for config_path in "${system_paths[@]}"; do
        config_paths+=("$config_path")
        config_bases+=("$resolution_base")
      done
      git_executable="${commands[git]-}"
      if [[ "$git_executable" == /* ]]; then
        config_paths+=("${git_executable:A:h:h}/etc/gitconfig")
        config_bases+=("$resolution_base")
      fi
    fi
  fi

  for (( config_index=1; config_index<=${#config_paths}; config_index++ )); do
    config_path="${config_paths[$config_index]}"
    resolution_base="${config_bases[$config_index]}"
    resolved_path="$config_path"
    [[ "$resolved_path" == /* ]] || \
      resolved_path="${resolution_base%/}/${resolved_path}"
    resolved_path="${resolved_path:A}"
    [[ -n "${seen_paths[$resolved_path]-}" ]] && continue
    seen_paths[$resolved_path]=1
    _ai_candy_git_config_file_context_key "$resolved_path"
    config_file_context="$REPLY"
    (( ++path_index ))
    external_context+="f${path_index}:${#config_file_context}:"
    external_context+="$config_file_context"
  done
  REPLY="$external_context"
}

function _ai_candy_git_metadata_context_key() {
  emulate -L zsh
  local path_value="$1"
  local physical_path="${path_value:A}"
  local candidate_dir="$physical_path"
  local git_marker=""
  local marker_detail=""
  local resolved_git_dir=""
  local resolved_git_common_dir=""
  local common_config_context=""
  local worktree_config_context=""
  local external_config_context=""
  local effective_config_context=""
  local discovery_context="${2-}"
  local metadata_prefix=""
  local ceiling_entry=""
  local -a ceiling_entries ceiling_paths
  integer candidate_is_start=1
  if (( $# < 2 )); then
    _ai_candy_git_discovery_context_key
    discovery_context="$REPLY"
  fi
  _AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE=1
  _AI_CANDY_GIT_METADATA_CONTEXT_PERSISTABLE=1
  _AI_CANDY_GIT_METADATA_PROBE_FAILED=0
  REPLY=""

  if (( ${+GIT_DIR} )); then
    _ai_candy_git_external_config_context_key "$physical_path" "$physical_path"
    external_config_context="$REPLY"
    metadata_prefix="g${#external_config_context}:${external_config_context}"
    if ! _ai_candy_resolve_git_dir "$physical_path"; then
      REPLY="${metadata_prefix}e0:"
      return 0
    fi
    resolved_git_dir="$REPLY"
    if ! _ai_candy_resolve_git_common_dir \
         "$physical_path" "$resolved_git_dir"; then
      REPLY="${metadata_prefix}e${#resolved_git_dir}:${resolved_git_dir}"
      return 0
    fi
    resolved_git_common_dir="$REPLY"
    _ai_candy_git_config_file_context_key \
      "${resolved_git_common_dir}/config"
    common_config_context="$REPLY"
    _ai_candy_git_config_file_context_key \
      "${resolved_git_dir}/config.worktree"
    worktree_config_context="$REPLY"
    _ai_candy_git_effective_config_context_key \
      "$physical_path" "$physical_path" "$resolved_git_dir" \
      "$resolved_git_common_dir" "$discovery_context" \
      "$external_config_context" "$common_config_context" \
      "$worktree_config_context"
    effective_config_context="$REPLY"
    REPLY="${metadata_prefix}d${#resolved_git_dir}:${resolved_git_dir}"
    REPLY+="m${#resolved_git_common_dir}:${resolved_git_common_dir}"
    REPLY+="c${#common_config_context}:${common_config_context}"
    REPLY+="w${#worktree_config_context}:${worktree_config_context}"
    REPLY+="q${#effective_config_context}:${effective_config_context}"
    return 0
  fi
  if (( ${+GIT_CEILING_DIRECTORIES} )); then
    ceiling_entries=("${(@s.:.)GIT_CEILING_DIRECTORIES}")
    for ceiling_entry in "${ceiling_entries[@]}"; do
      [[ "$ceiling_entry" == /* ]] || continue
      ceiling_paths+=("${ceiling_entry:A}")
    done
  fi

  while true; do
    if (( ! candidate_is_start && \
          ${ceiling_paths[(Ie)$candidate_dir]} )); then
      return 0
    fi
    git_marker="${candidate_dir%/}/.git"
    [[ "$candidate_dir" == "/" ]] && git_marker="/.git"
    if [[ -e "$git_marker" || -L "$git_marker" ]]; then
      _ai_candy_git_external_config_context_key \
        "$candidate_dir" "$physical_path"
      external_config_context="$REPLY"
      metadata_prefix="g${#external_config_context}:${external_config_context}"
      if _ai_candy_resolve_git_dir "$candidate_dir"; then
        resolved_git_dir="$REPLY"
        if _ai_candy_resolve_git_common_dir \
             "$candidate_dir" "$resolved_git_dir"; then
          resolved_git_common_dir="$REPLY"
          _ai_candy_git_config_file_context_key \
            "${resolved_git_common_dir}/config"
          common_config_context="$REPLY"
          _ai_candy_git_config_file_context_key \
            "${resolved_git_dir}/config.worktree"
          worktree_config_context="$REPLY"
          _ai_candy_git_effective_config_context_key \
            "$physical_path" "$candidate_dir" "$resolved_git_dir" \
            "$resolved_git_common_dir" "$discovery_context" \
            "$external_config_context" "$common_config_context" \
            "$worktree_config_context"
          effective_config_context="$REPLY"
          REPLY="${metadata_prefix}r${#candidate_dir}:${candidate_dir}"
          REPLY+="d${#resolved_git_dir}:${resolved_git_dir}"
          REPLY+="m${#resolved_git_common_dir}:${resolved_git_common_dir}"
          REPLY+="c${#common_config_context}:${common_config_context}"
          REPLY+="w${#worktree_config_context}:${worktree_config_context}"
          REPLY+="q${#effective_config_context}:${effective_config_context}"
          return 0
        fi
      fi
      marker_detail="${git_marker:A}"
      if [[ -f "$git_marker" && ! -L "$git_marker" ]] && \
         _ai_candy_read_git_metadata_file "$git_marker"; then
        marker_detail="$REPLY"
      fi
      REPLY="${metadata_prefix}i${#candidate_dir}:${candidate_dir}"
      REPLY+="v${#marker_detail}:${marker_detail}"
      return 0
    fi
    [[ "$candidate_dir" == "/" ]] && return 0
    candidate_dir="${candidate_dir:h}"
    candidate_is_start=0
  done
}

function _ai_candy_git_root_cache_requires_refresh() {
  emulate -L zsh
  local cached_root="$2"
  local validated_generation="${3:-0}"
  local metadata_context="${5:-}"

  _ai_candy_cache_generation_token_is_valid "$validated_generation" || \
    validated_generation=0
  [[ "$_AI_CANDY_GIT_TOPOLOGY_GENERATION" != "$validated_generation" ]] && return 0
  if [[ "$cached_root" == "NOT_GIT" ]]; then
    [[ -n "$metadata_context" ]] && return 0
    return 1
  fi
  [[ -n "$metadata_context" ]] || return 0
  return 1
}

function _ai_candy_path_has_git_metadata_context() {
  local candidate_dir="$1"
  local git_marker=""

  [[ -n "${GIT_DIR:-}${GIT_WORK_TREE:-}${GIT_COMMON_DIR:-}" ]] && return 0
  [[ "$candidate_dir" == /* ]] || return 1
  while true; do
    if [[ "$candidate_dir" == "/" ]]; then
      git_marker="/.git"
    else
      git_marker="${candidate_dir%/}/.git"
    fi
    [[ -e "$git_marker" || -L "$git_marker" ]] && return 0
    [[ "$candidate_dir" == "/" ]] && break
    candidate_dir="${candidate_dir:h}"
  done
  return 1
}

function _ai_candy_get_cached_git_root() {
  integer topology_persistence=1
  _ai_candy_sync_git_topology_generation || topology_persistence=0
  local current_dir="$PWD"
  integer physical_pwd_is_current=1
  _ai_candy_capture_physical_pwd || physical_pwd_is_current=0
  local current_physical_dir="${_AI_CANDY_PHYSICAL_PWD:-${current_dir:A}}"
  integer current_directory_is_identified=1
  _ai_candy_git_current_directory_context_key || \
    current_directory_is_identified=0
  local current_directory_context="$REPLY"
  _ai_candy_git_discovery_context_key
  local discovery_context="$REPLY"
  _ai_candy_git_metadata_context_key \
    "$current_physical_dir" "$discovery_context"
  local metadata_context="$REPLY"
  integer metadata_context_cacheable=$_AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE
  integer metadata_context_persistable=$_AI_CANDY_GIT_METADATA_CONTEXT_PERSISTABLE
  integer metadata_probe_failed=$_AI_CANDY_GIT_METADATA_PROBE_FAILED
  if (( metadata_probe_failed )); then
    REPLY="NOT_GIT"
    return 0
  fi
  if (( ! physical_pwd_is_current || ! current_directory_is_identified )); then
    metadata_context_cacheable=0
    metadata_context_persistable=0
  fi
  local root_cache_key="$current_dir"
  [[ -n "$discovery_context" ]] && topology_persistence=0
  if [[ -n "$discovery_context" || -n "$metadata_context" || \
        -n "$current_directory_context" ]]; then
    root_cache_key="c${#discovery_context}:${discovery_context}"
    root_cache_key+="m${#metadata_context}:${metadata_context}"
    root_cache_key+="i${#current_directory_context}:${current_directory_context}"
    root_cache_key+="p${#current_dir}:${current_dir}"
  fi
  local current_time=${EPOCHSECONDS}
  REPLY=""

  # Check memory cache first (fastest, no I/O)
  if (( metadata_context_cacheable )) && \
     [[ -n "${_AI_CANDY_MEM_CACHE_GIT_ROOT[$root_cache_key]-}" ]]; then
    local cached="${_AI_CANDY_MEM_CACHE_GIT_ROOT[$root_cache_key]}"
    local cached_root="${cached%|*}"
    local cache_time="${cached##*|}"
    local validated_generation="${_AI_CANDY_MEM_CACHE_GIT_ROOT_GENERATION[$root_cache_key]-0}"
    if _ai_candy_git_root_cache_requires_refresh "$current_dir" "$cached_root" \
         "$validated_generation" "$discovery_context" "$metadata_context"; then
      _ai_candy_mem_cache_remove_key git_root "$root_cache_key"
    elif _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_AI_CANDY_CACHE_TTL_MEDIUM" "$current_time"; then
      REPLY="$cached_root"
      return 0
    fi
  fi

  # Check persistent cache (SQLite or file)
  local cached_line=""
  local persistent_key="${_AI_CANDY_GIT_TOPOLOGY_GENERATION}:${root_cache_key}"
  if (( metadata_context_cacheable && metadata_context_persistable && \
        topology_persistence )) && \
     _ai_candy_cache_get "git_root" "$persistent_key"; then
    cached_line="$REPLY"
    # Format: value|timestamp (from _ai_candy_cache_get)
    local cache_time="${cached_line##*|}"
    local cached_root="${cached_line%|*}"

    if _ai_candy_git_root_cache_requires_refresh "$current_dir" "$cached_root" \
         "$_AI_CANDY_GIT_TOPOLOGY_GENERATION" "$discovery_context" \
         "$metadata_context"; then
      _ai_candy_cache_delete_key "git_root" "$persistent_key" >/dev/null 2>&1
    elif _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_AI_CANDY_CACHE_TTL_MEDIUM" "$current_time"; then
      # Update memory cache from persistent cache
      _AI_CANDY_MEM_CACHE_GIT_ROOT[$root_cache_key]="${cached_root}|${cache_time}"
      _AI_CANDY_MEM_CACHE_GIT_ROOT_GENERATION[$root_cache_key]="$_AI_CANDY_GIT_TOPOLOGY_GENERATION"
      REPLY="$cached_root"
      return 0
    fi
  fi

  # Compute git root
  local git_root=""
  integer git_status=0
  git_root=$(_ai_candy_run_local_probe \
    git rev-parse --show-toplevel 2>/dev/null) || git_status=$?
  if (( git_status != 0 && git_status != 128 )) || \
     (( git_status == 0 && ${#git_root} == 0 )); then
    REPLY="NOT_GIT"
    return 0
  fi
  if (( git_status == 128 )); then
    if [[ -z "$discovery_context" || \
          -n "${GIT_DIR:-}${GIT_WORK_TREE:-}${GIT_COMMON_DIR:-}" ]] && \
       _ai_candy_path_has_git_metadata_context "$current_physical_dir"; then
      REPLY="NOT_GIT"
      return 0
    fi
    git_root="NOT_GIT"
  fi

  # Update both caches
  if (( metadata_context_cacheable )); then
    _AI_CANDY_MEM_CACHE_GIT_ROOT[$root_cache_key]="${git_root}|${current_time}"
    _AI_CANDY_MEM_CACHE_GIT_ROOT_GENERATION[$root_cache_key]="$_AI_CANDY_GIT_TOPOLOGY_GENERATION"
    if (( metadata_context_persistable && topology_persistence )); then
      _ai_candy_cache_set "git_root" "$persistent_key" "$git_root" "$current_time" \
        "$root_cache_key"
    fi
  fi

  # Cleanup memory cache if it grows too large
  (( ${#_AI_CANDY_MEM_CACHE_GIT_ROOT} > _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )) && _ai_candy_mem_cache_cleanup "git_root"

  REPLY="$git_root"
}

# Path background colors defined in COLOR CONSTANTS section at file top

function _ai_candy_logicalize_path_from_pwd() {
  local physical_path="$1"
  local logical_pwd="${2:-$PWD}"
  local physical_pwd="${3:-${_AI_CANDY_PHYSICAL_PWD:-${PWD:A}}}"

  if [[ -z "$physical_path" || -z "$logical_pwd" || -z "$physical_pwd" ]]; then
    builtin print -r -- "$physical_path"
    return
  fi

  if [[ "$physical_pwd" == "$physical_path" ]]; then
    builtin print -r -- "$logical_pwd"
    return
  fi

  if [[ "$physical_pwd" == "$physical_path"/* ]]; then
    local suffix="${physical_pwd#$physical_path}"
    local suffix_len=${#suffix}
    local logical_len=${#logical_pwd}
    local suffix_start=$((logical_len - suffix_len + 1))

    if (( suffix_len <= logical_len )) && [[ "${logical_pwd[$suffix_start,-1]}" == "$suffix" ]]; then
      local root_len=$((logical_len - suffix_len))
      if (( root_len > 0 )); then
        builtin print -r -- "${logical_pwd[1,$root_len]}"
      else
        builtin print -r -- "/"
      fi
      return
    fi
  fi

  builtin print -r -- "$physical_path"
}

# Get git repository hierarchy (handles submodules)
# Returns: repo1<sep>repo2<sep>repo3<sep>current_subdir
# Where repo1 is outermost, repoN is innermost git root
# current_subdir is the path within the innermost repo (may be empty)
function _ai_candy_get_git_hierarchy() {
  local LC_ALL=C
  integer topology_persistence=1
  _ai_candy_sync_git_topology_generation || topology_persistence=0
  _ai_candy_git_discovery_context_key
  local discovery_context="$REPLY"
  [[ -n "$discovery_context" ]] && topology_persistence=0
  local current_time=${EPOCHSECONDS}
  local git_root="${_AI_CANDY_PP_CACHED_GIT_ROOT:-}"
  _ai_candy_git_context_cache_key "$git_root" "$discovery_context"
  local git_context="$REPLY"
  local cache_key="${_AI_CANDY_GIT_HIERARCHY_CACHE_VERSION:-1}:"
  cache_key+="${_AI_CANDY_GIT_TOPOLOGY_GENERATION}:"
  cache_key+="c${#git_context}:${git_context}p${#PWD}:${PWD}"
  local logical_pwd="$PWD"
  local physical_pwd="${_AI_CANDY_PHYSICAL_PWD:-${PWD:A}}"
  REPLY=""

  # Check memory cache first (fastest, no I/O)
  if [[ -n "${_AI_CANDY_MEM_CACHE_GIT_HIERARCHY[$cache_key]-}" ]]; then
    local cached="${_AI_CANDY_MEM_CACHE_GIT_HIERARCHY[$cache_key]}"
    local cache_time="${cached##*|}"
    local cached_result="${cached%|*}"
    if _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_AI_CANDY_CACHE_TTL_MEDIUM" "$current_time"; then
      REPLY="$cached_result"
      return 0
    fi
  fi

  # Check persistent cache (SQLite or file)
  local cached_line=""
  if (( topology_persistence )) && \
     _ai_candy_cache_get "git_hierarchy" "$cache_key"; then
    cached_line="$REPLY"
    # Format: value|timestamp
    local cache_time="${cached_line##*|}"
    local cached_result="${cached_line%|*}"

    if _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_AI_CANDY_CACHE_TTL_MEDIUM" "$current_time"; then
      # Update memory cache from persistent cache
      _AI_CANDY_MEM_CACHE_GIT_HIERARCHY[$cache_key]="${cached_result}|${cache_time}"
      REPLY="$cached_result"
      return 0
    fi
  fi

  # Build hierarchy from innermost to outermost
  local hierarchy=()
  local depth=0
  local max_depth=${_AI_CANDY_GIT_HIERARCHY_MAX_DEPTH:-20}
  if [[ -z "$git_root" || "$git_root" == "NOT_GIT" ]]; then
    git_root=$(builtin cd "$PWD" 2>/dev/null && _ai_candy_run_local_probe git rev-parse --show-toplevel 2>/dev/null)
  fi

  while [[ -n "$git_root" ]]; do
    (( depth >= max_depth )) && break
    (( depth++ ))

    local display_git_root=$(_ai_candy_logicalize_path_from_pwd "$git_root" "$logical_pwd" "$physical_pwd")
    hierarchy=("$display_git_root" "${hierarchy[@]}")  # prepend (outermost first)

    # Check for superproject
    local superproject=$(_ai_candy_run_git_probe_at_root "$git_root" \
      rev-parse --show-superproject-working-tree 2>/dev/null)
    [[ -z "$superproject" || "$superproject" == "$git_root" ]] && break

    git_root="$superproject"
  done

  # Build result: repo1<sep>repo2<sep>...<sep>subdir
  local result=""
  local sep="${_AI_CANDY_GIT_HIERARCHY_SEP:-:}"
  if (( ${#hierarchy[@]} > 0 )); then
    local innermost="${hierarchy[-1]}"
    local current_subdir=""
    [[ "$PWD" != "$innermost" ]] && current_subdir="${PWD#$innermost/}"

    # The internal separator is a control byte that POSIX filenames can still
    # contain. Neutralize it before serializing display-only path components.
    local component serialized_component
    for component in "${hierarchy[@]}"; do
      serialized_component="${component//${_AI_CANDY_GIT_HIERARCHY_SEP}/?}"
      [[ -n "$result" ]] && result+="$sep"
      result+="$serialized_component"
    done
    current_subdir="${current_subdir//${_AI_CANDY_GIT_HIERARCHY_SEP}/?}"
    result+="${sep}${current_subdir}"
  fi

  # Cache result in both memory and persistent cache
  _AI_CANDY_MEM_CACHE_GIT_HIERARCHY[$cache_key]="${result}|${current_time}"
  (( topology_persistence )) && \
    _ai_candy_cache_set "git_hierarchy" "$cache_key" "$result" "$current_time"

  # Cleanup memory cache if it grows too large
  (( ${#_AI_CANDY_MEM_CACHE_GIT_HIERARCHY} > _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )) && _ai_candy_mem_cache_cleanup "git_hierarchy"

  REPLY="$result"
}

# ============================================================================
# DIRECT ASSIGNMENT FUNCTIONS - Avoid subshells by writing to global variables
# ============================================================================

# A single porcelain-v2 snapshot owns all frequently changing Git facts.
typeset -g _AI_CANDY_GIT_SNAPSHOT_RENDER_ID=-1
typeset -g _AI_CANDY_GIT_SNAPSHOT_CONTEXT=""
typeset -g _AI_CANDY_GIT_SNAPSHOT_VALID=0
typeset -g _AI_CANDY_GIT_SNAPSHOT_STATUS_COMPLETE=0
typeset -g _AI_CANDY_GIT_SNAPSHOT_BRANCH=""
typeset -g _AI_CANDY_GIT_SNAPSHOT_UPSTREAM=""
typeset -g _AI_CANDY_GIT_SNAPSHOT_OID=""
typeset -g _AI_CANDY_GIT_SNAPSHOT_TAG=""
typeset -g _AI_CANDY_GIT_SNAPSHOT_DIRTY=0
typeset -g _AI_CANDY_GIT_SNAPSHOT_AHEAD=0
typeset -g _AI_CANDY_GIT_SNAPSHOT_BEHIND=0
typeset -g _AI_CANDY_GIT_SNAPSHOT_STASH=0
typeset -gA _AI_CANDY_GIT_STASH_COUNT_BY_LOG
typeset -g _AI_CANDY_GIT_HIDE_INFO=0
typeset -g _AI_CANDY_GIT_HIDE_DIRTY=0
typeset -g _AI_CANDY_GIT_CONFIG_CACHE_TTL=5
typeset -gA _AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT
typeset -g _AI_CANDY_GIT_SNAPSHOT_FAILURE_RETRY_TTL=3
typeset -gA _AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT

function _ai_candy_reset_git_snapshot() {
  _AI_CANDY_GIT_SNAPSHOT_VALID=0
  _AI_CANDY_GIT_SNAPSHOT_STATUS_COMPLETE=0
  _AI_CANDY_GIT_SNAPSHOT_BRANCH=""
  _AI_CANDY_GIT_SNAPSHOT_UPSTREAM=""
  _AI_CANDY_GIT_SNAPSHOT_OID=""
  _AI_CANDY_GIT_SNAPSHOT_TAG=""
  _AI_CANDY_GIT_SNAPSHOT_DIRTY=0
  _AI_CANDY_GIT_SNAPSHOT_AHEAD=0
  _AI_CANDY_GIT_SNAPSHOT_BEHIND=0
  _AI_CANDY_GIT_SNAPSHOT_STASH=0
}

function _ai_candy_load_git_head_snapshot() {
  local git_root="$1"
  local git_dir="" head_contents=""

  _ai_candy_resolve_git_dir "$git_root" || return 1
  git_dir="$REPLY"
  _ai_candy_read_git_metadata_file "${git_dir}/HEAD" || return 1
  head_contents="$REPLY"
  if [[ "$head_contents" == "ref: refs/heads/"* ]]; then
    _AI_CANDY_GIT_SNAPSHOT_BRANCH="${head_contents#ref: refs/heads/}"
    [[ -n "$_AI_CANDY_GIT_SNAPSHOT_BRANCH" ]] || return 1
  elif (( ${#head_contents} == 40 || ${#head_contents} == 64 )) && \
       [[ -z "${head_contents//[0-9A-Fa-f]/}" ]]; then
    _AI_CANDY_GIT_SNAPSHOT_BRANCH="(detached)"
    _AI_CANDY_GIT_SNAPSHOT_OID="$head_contents"
  else
    return 1
  fi
  _AI_CANDY_GIT_SNAPSHOT_VALID=1
}

function _ai_candy_load_git_stash_fallback() {
  emulate -L zsh
  local git_root="$1"
  local common_dir="" stash_log="" signature="" cached=""
  local cached_signature="" cached_fields="" cached_count="" count=""
  local -a mtime_data size_data

  _ai_candy_resolve_git_common_dir "$git_root" || return 0
  common_dir="$REPLY"
  stash_log="${common_dir}/logs/refs/stash"
  [[ -f "$stash_log" && ! -L "$stash_log" ]] || return 0

  if (( _AI_CANDY_HAS_ZSH_STAT_BUILTIN )) && \
     builtin zstat -A mtime_data +mtime -- "$stash_log" 2>/dev/null && \
     builtin zstat -A size_data +size -- "$stash_log" 2>/dev/null && \
     [[ "${mtime_data[1]-}" == <-> && "${size_data[1]-}" == <-> ]]; then
    signature="${mtime_data[1]}:${size_data[1]}"
    cached="${_AI_CANDY_GIT_STASH_COUNT_BY_LOG[$stash_log]-}"
    cached_signature="${cached%%|*}"
    cached_fields="${cached#*|}"
    cached_count="${cached_fields%%|*}"
    if [[ "$cached_signature" == "$signature" && "$cached_count" == <-> ]]; then
      _AI_CANDY_GIT_SNAPSHOT_STASH="$cached_count"
      return 0
    fi
  fi

  count=$(_ai_candy_run_git_probe_at_root "$git_root" \
    rev-list --walk-reflogs --count refs/stash 2>/dev/null) || count=""
  [[ "$count" == <-> && ${#count} -le 9 ]] || return 0
  _AI_CANDY_GIT_SNAPSHOT_STASH="$count"
  if [[ -n "$signature" ]]; then
    _AI_CANDY_GIT_STASH_COUNT_BY_LOG[$stash_log]="${signature}|${count}|${EPOCHSECONDS}"
    (( ${#_AI_CANDY_GIT_STASH_COUNT_BY_LOG} > \
       _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )) && \
      _ai_candy_mem_cache_cleanup git_stash
  fi
}

function _ai_candy_load_git_display_options() {
  local git_root="$1"
  _ai_candy_git_context_cache_key "$git_root"
  local context_key="$REPLY"
  local cached="${_AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT[$context_key]-}"
  local current_time="${EPOCHSECONDS}"
  local hide_info=0 hide_dirty=0
  integer cache_is_fresh=0

  if [[ -n "$cached" ]]; then
    local cache_time="${cached##*|}"
    local cached_options="${cached%|*}"
    if _ai_candy_cache_timestamp_is_fresh "$cache_time" \
         "$_AI_CANDY_GIT_CONFIG_CACHE_TTL" "$current_time"; then
      hide_info="${cached_options%%|*}"
      hide_dirty="${cached_options##*|}"
      cache_is_fresh=1
    fi
  fi

  if (( ! cache_is_fresh )); then
    local config_output="" line
    config_output=$(_ai_candy_run_git_probe_at_root "$git_root" \
      config --get-regexp \
      '^oh-my-zsh\.(hide-info|hide-dirty)$' 2>/dev/null) || config_output=""
    for line in "${(@f)config_output}"; do
      case "$line" in
        'oh-my-zsh.hide-info '*)
          hide_info=0
          [[ "$line" == 'oh-my-zsh.hide-info 1' ]] && hide_info=1
          ;;
        'oh-my-zsh.hide-dirty '*)
          hide_dirty=0
          [[ "$line" == 'oh-my-zsh.hide-dirty 1' ]] && hide_dirty=1
          ;;
      esac
    done
    _AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT[$context_key]="${hide_info}|${hide_dirty}|${current_time}"
    (( ${#_AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT} > _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )) && \
      _ai_candy_mem_cache_cleanup git_options
  fi

  _AI_CANDY_GIT_HIDE_INFO="$hide_info"
  _AI_CANDY_GIT_HIDE_DIRTY="$hide_dirty"
}

function _ai_candy_collect_git_snapshot() {
  local current_id="${_AI_CANDY_PROMPT_RENDER_ID:-0}"
  local git_root="${_AI_CANDY_PP_CACHED_GIT_ROOT:-NOT_GIT}"
  _ai_candy_git_context_cache_key "$git_root"
  local context_key="$REPLY"
  if [[ "$_AI_CANDY_GIT_SNAPSHOT_RENDER_ID" == "$current_id" && \
        "$_AI_CANDY_GIT_SNAPSHOT_CONTEXT" == "$context_key" ]]; then
    return 0
  fi

  _AI_CANDY_GIT_SNAPSHOT_RENDER_ID="$current_id"
  _AI_CANDY_GIT_SNAPSHOT_CONTEXT="$context_key"
  _ai_candy_reset_git_snapshot
  [[ -n "$git_root" && "$git_root" != "NOT_GIT" ]] || return 0
  _ai_candy_load_git_display_options "$git_root"

  local current_time="${EPOCHSECONDS}"
  local retry_after="${_AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT[$context_key]-0}"
  if [[ "$retry_after" == <-> ]] && (( current_time < retry_after )); then
    _ai_candy_load_git_head_snapshot "$git_root"
    return $?
  fi

  local -a status_args
  status_args=(status --porcelain=v2 --branch)
  [[ "${DISABLE_UNTRACKED_FILES_DIRTY:-}" == "true" ]] && status_args+=(--untracked-files=no)
  if [[ "${GIT_STATUS_IGNORE_SUBMODULES:-}" != "git" ]]; then
    status_args+=("--ignore-submodules=${GIT_STATUS_IGNORE_SUBMODULES:-dirty}")
  fi

  local snapshot=""
  local command_status=0
  snapshot=$(GIT_OPTIONAL_LOCKS=0 _ai_candy_run_local_probe git "${status_args[@]}" 2>/dev/null) || command_status=$?
  if (( command_status != 0 )); then
    local retry_ttl="${_AI_CANDY_GIT_SNAPSHOT_FAILURE_RETRY_TTL:-3}"
    if [[ "$retry_ttl" != <-> ]] || (( retry_ttl < 1 || retry_ttl > 30 )); then
      retry_ttl=3
    fi
    _AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT[$context_key]=$(( current_time + retry_ttl ))
    (( ${#_AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT} > \
       _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )) && \
      _ai_candy_mem_cache_cleanup git_snapshot_retry
    _ai_candy_load_git_head_snapshot "$git_root"
    return $?
  fi
  _ai_candy_mem_cache_remove_key git_snapshot_retry "$context_key"

  local line prefix rest
  for line in "${(@f)snapshot}"; do
    case "$line" in
      '# branch.oid '*)
        prefix='# branch.oid '
        _AI_CANDY_GIT_SNAPSHOT_OID="${line#$prefix}"
        ;;
      '# branch.head '*)
        prefix='# branch.head '
        _AI_CANDY_GIT_SNAPSHOT_BRANCH="${line#$prefix}"
        ;;
      '# branch.upstream '*)
        prefix='# branch.upstream '
        _AI_CANDY_GIT_SNAPSHOT_UPSTREAM="${line#$prefix}"
        ;;
      '# branch.ab +'*)
        prefix='# branch.ab +'
        rest="${line#$prefix}"
        _AI_CANDY_GIT_SNAPSHOT_AHEAD="${rest%% *}"
        _AI_CANDY_GIT_SNAPSHOT_BEHIND="${rest##* -}"
        ;;
      '# stash '*)
        prefix='# stash '
        _AI_CANDY_GIT_SNAPSHOT_STASH="${line#$prefix}"
        ;;
      '# '*) ;;
      ?*) _AI_CANDY_GIT_SNAPSHOT_DIRTY=1 ;;
    esac
  done

  [[ "$_AI_CANDY_GIT_SNAPSHOT_AHEAD" == <-> ]] || _AI_CANDY_GIT_SNAPSHOT_AHEAD=0
  [[ "$_AI_CANDY_GIT_SNAPSHOT_BEHIND" == <-> ]] || _AI_CANDY_GIT_SNAPSHOT_BEHIND=0
  [[ "$_AI_CANDY_GIT_SNAPSHOT_STASH" == <-> ]] || _AI_CANDY_GIT_SNAPSHOT_STASH=0
  (( _AI_CANDY_GIT_SNAPSHOT_STASH == 0 )) && \
    _ai_candy_load_git_stash_fallback "$git_root"
  if [[ "$_AI_CANDY_GIT_SNAPSHOT_BRANCH" == "(detached)" ]]; then
    _AI_CANDY_GIT_SNAPSHOT_TAG=$(_ai_candy_run_local_probe git describe --tags --exact-match HEAD 2>/dev/null) || \
      _AI_CANDY_GIT_SNAPSHOT_TAG=""
  fi
  _AI_CANDY_GIT_SNAPSHOT_STATUS_COMPLETE=1
  _AI_CANDY_GIT_SNAPSHOT_VALID=1
}

typeset -g _AI_CANDY_GIT_FORMATTED_INFO=""
typeset -g _AI_CANDY_GIT_FORMATTED_EXT=""

function _ai_candy_format_git_snapshot() {
  _AI_CANDY_GIT_FORMATTED_INFO=""
  _AI_CANDY_GIT_FORMATTED_EXT=""
  (( _AI_CANDY_GIT_SNAPSHOT_VALID )) || return 0

  local branch="$_AI_CANDY_GIT_SNAPSHOT_BRANCH"
  if [[ "$branch" == "(detached)" ]]; then
    branch="${_AI_CANDY_GIT_SNAPSHOT_TAG:-${_AI_CANDY_GIT_SNAPSHOT_OID[1,7]}}"
  fi
  _ai_candy_prompt_escape_text "$branch"
  branch="$REPLY"

  local upstream=""
  if (( ${+ZSH_THEME_GIT_SHOW_UPSTREAM} )) && [[ -n "$_AI_CANDY_GIT_SNAPSHOT_UPSTREAM" ]]; then
    _ai_candy_prompt_escape_text "$_AI_CANDY_GIT_SNAPSHOT_UPSTREAM"
    upstream=" -> ${REPLY}"
  fi
  local dirty=""
  if (( _AI_CANDY_GIT_SNAPSHOT_STATUS_COMPLETE )); then
    dirty="${ZSH_THEME_GIT_PROMPT_CLEAN:-}"
    (( _AI_CANDY_GIT_SNAPSHOT_DIRTY && ! _AI_CANDY_GIT_HIDE_DIRTY )) && \
      dirty="${ZSH_THEME_GIT_PROMPT_DIRTY:-}"
  fi
  if (( ! _AI_CANDY_GIT_HIDE_INFO )); then
    _AI_CANDY_GIT_FORMATTED_INFO="${ZSH_THEME_GIT_PROMPT_PREFIX:-}${branch}${upstream}${dirty}${ZSH_THEME_GIT_PROMPT_SUFFIX:-}"
  fi

  if (( _AI_CANDY_GIT_SNAPSHOT_AHEAD > 0 )); then
    if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
      _AI_CANDY_GIT_FORMATTED_EXT+="%{$fg[green]%}${_AI_CANDY_SYM_UP}${_AI_CANDY_GIT_SNAPSHOT_AHEAD}%{$reset_color%}"
    else
      _AI_CANDY_GIT_FORMATTED_EXT+="%{$fg[green]%}+${_AI_CANDY_GIT_SNAPSHOT_AHEAD}%{$reset_color%}"
    fi
  fi
  if (( _AI_CANDY_GIT_SNAPSHOT_BEHIND > 0 )); then
    if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
      _AI_CANDY_GIT_FORMATTED_EXT+="%{$fg[red]%}${_AI_CANDY_SYM_DOWN}${_AI_CANDY_GIT_SNAPSHOT_BEHIND}%{$reset_color%}"
    else
      _AI_CANDY_GIT_FORMATTED_EXT+="%{$fg[red]%}-${_AI_CANDY_GIT_SNAPSHOT_BEHIND}%{$reset_color%}"
    fi
  fi
  if (( _AI_CANDY_GIT_SNAPSHOT_STASH > 0 )); then
    if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
      _AI_CANDY_GIT_FORMATTED_EXT+="%{$fg[yellow]%}${_AI_CANDY_SYM_STASH}${_AI_CANDY_GIT_SNAPSHOT_STASH}%{$reset_color%}"
    else
      _AI_CANDY_GIT_FORMATTED_EXT+="%{$fg[yellow]%}S${_AI_CANDY_GIT_SNAPSHOT_STASH}%{$reset_color%}"
    fi
  fi
}

function _ai_candy_compute_git_info_direct() {
  if (( _AI_CANDY_USE_OMZ_ASYNC )); then
    local async_output="${_OMZ_ASYNC_OUTPUT[_ai_candy_git_prompt_async]-}"
    _AI_CANDY_PP_GIT_INFO="${async_output# }"
    _AI_CANDY_PP_GIT_EXT=""
    return 0
  fi

  _ai_candy_collect_git_snapshot
  _ai_candy_format_git_snapshot
  _AI_CANDY_PP_GIT_INFO="$_AI_CANDY_GIT_FORMATTED_INFO"
}

function _ai_candy_compute_git_extended_direct() {
  (( _AI_CANDY_USE_OMZ_ASYNC )) && return 0
  _ai_candy_collect_git_snapshot
  _ai_candy_format_git_snapshot
  _AI_CANDY_PP_GIT_EXT="$_AI_CANDY_GIT_FORMATTED_EXT"
}

function _ai_candy_resolve_git_dir() {
  local git_root="$1"
  local git_dir=""
  REPLY=""

  if (( ${+GIT_DIR} )); then
    git_dir="${GIT_DIR-}"
    [[ -n "$git_dir" && "$git_dir" != *$'\n'* ]] || return 1
    [[ "$git_dir" == /* ]] || \
      git_dir="${_AI_CANDY_PHYSICAL_PWD:-$PWD}/${git_dir}"
    git_dir="${git_dir:A}"
  else
    git_dir="${git_root}/.git"
    if [[ -f "$git_dir" ]]; then
      _ai_candy_read_git_metadata_file "$git_dir" || return 1
      local git_link="$REPLY"
      [[ "$git_link" == "gitdir: "* ]] || return 1
      git_link="${git_link#gitdir: }"
      if [[ "$git_link" == /* ]]; then
        git_dir="$git_link"
      else
        git_dir="${git_root}/${git_link}"
      fi
    fi
    git_dir="${git_dir:A}"
  fi

  [[ -d "$git_dir" ]] || return 1
  REPLY="$git_dir"
}

function _ai_candy_resolve_git_common_dir() {
  local git_root="$1"
  local git_dir="" common_dir="" common_link=""
  local common_file=""
  REPLY=""

  if (( $# >= 2 )); then
    git_dir="$2"
    [[ -d "$git_dir" ]] || return 1
  else
    _ai_candy_resolve_git_dir "$git_root" || return 1
    git_dir="$REPLY"
  fi
  common_dir="$git_dir"
  if (( ${+GIT_COMMON_DIR} )); then
    common_link="${GIT_COMMON_DIR-}"
    [[ -n "$common_link" && "$common_link" != *$'\n'* ]] || return 1
    if [[ "$common_link" == /* ]]; then
      common_dir="${common_link:A}"
    else
      common_dir="${_AI_CANDY_PHYSICAL_PWD:-$PWD}/${common_link}"
      common_dir="${common_dir:A}"
    fi
  else
    common_file="${git_dir}/commondir"
    if [[ -e "$common_file" || -L "$common_file" ]]; then
      [[ -f "$common_file" && ! -L "$common_file" ]] || return 1
      _ai_candy_read_git_metadata_file "$common_file" || return 1
      common_link="$REPLY"
      [[ -n "$common_link" && "$common_link" != *$'\n'* ]] || return 1
      if [[ "$common_link" == /* ]]; then
        common_dir="${common_link:A}"
      else
        common_dir="${git_dir}/${common_link}"
        common_dir="${common_dir:A}"
      fi
    fi
  fi
  [[ -d "$common_dir" ]] || return 1
  REPLY="$common_dir"
}

# Direct-assignment version of _git_special_state_cached
# PERFORMANCE: Sets _AI_CANDY_PP_GIT_SPECIAL directly (0 subshells)
# Uses _AI_CANDY_PP_CACHED_GIT_ROOT set in _ai_candy_precmd_compute_prompt
function _ai_candy_compute_git_special_direct() {
  local current_id="$_AI_CANDY_PROMPT_RENDER_ID"
  local git_root="$_AI_CANDY_PP_CACHED_GIT_ROOT"
  _ai_candy_git_context_cache_key "$git_root"
  local context_key="$REPLY"
  if [[ "$_AI_CANDY_PROMPT_GIT_SPECIAL_CACHE_ID" == "$current_id" && \
        "$_AI_CANDY_PROMPT_GIT_SPECIAL_CACHE_CONTEXT" == "$context_key" ]]; then
    _AI_CANDY_PP_GIT_SPECIAL="$_AI_CANDY_PROMPT_GIT_SPECIAL_CACHE"
    return
  fi

  _AI_CANDY_PP_GIT_SPECIAL=""
  [[ "$git_root" == "NOT_GIT" ]] && return

  _ai_candy_resolve_git_dir "$git_root" || return 0
  local git_dir="$REPLY"

  local state="" step="" total=""

  # Check for rebase
  if [[ -d "${git_dir}/rebase-merge" ]]; then
    _ai_candy_read_git_metadata_file "${git_dir}/rebase-merge/msgnum" && step="$REPLY"
    _ai_candy_read_git_metadata_file "${git_dir}/rebase-merge/end" && total="$REPLY"
    [[ -f "${git_dir}/rebase-merge/interactive" ]] && state="rebase-i" || state="rebase-m"
  elif [[ -d "${git_dir}/rebase-apply" ]]; then
    _ai_candy_read_git_metadata_file "${git_dir}/rebase-apply/next" && step="$REPLY"
    _ai_candy_read_git_metadata_file "${git_dir}/rebase-apply/last" && total="$REPLY"
    if [[ -f "${git_dir}/rebase-apply/rebasing" ]]; then
      state="rebase"
    elif [[ -f "${git_dir}/rebase-apply/applying" ]]; then
      state="am"
    else
      state="am/rebase"
    fi
  elif [[ -f "${git_dir}/MERGE_HEAD" ]]; then
    state="merge"
  elif [[ -f "${git_dir}/CHERRY_PICK_HEAD" ]]; then
    state="cherry"
  elif [[ -f "${git_dir}/REVERT_HEAD" ]]; then
    state="revert"
  elif [[ -f "${git_dir}/BISECT_LOG" ]]; then
    state="bisect"
  fi

  # Check for detached HEAD
  if [[ -z "$state" ]]; then
    local head_contents=""
    _ai_candy_read_git_metadata_file "${git_dir}/HEAD" && head_contents="$REPLY"
    [[ -n "$head_contents" && "$head_contents" != "ref: "* ]] && state="detached"
  fi

  [[ "$step" == <-> ]] || step=""
  [[ "$total" == <-> ]] || total=""

  # Format output
  if [[ -n "$state" ]]; then
    local icon="" color="%{$fg[magenta]%}"

    if (( _AI_CANDY_PROMPT_EMOJI_MODE )); then
      case "$state" in
        rebase*|am*) icon="$_AI_CANDY_SYM_BRANCH"; color="%{$fg[yellow]%}" ;;
        merge)       icon="$_AI_CANDY_SYM_BRANCH"; color="%{$fg[cyan]%}" ;;
        cherry)      icon="$_AI_CANDY_SYM_CHERRY"; color="%{$fg[red]%}" ;;
        revert)      icon="$_AI_CANDY_SYM_REWIND"; color="%{$fg[magenta]%}" ;;
        bisect)      icon="$_AI_CANDY_SYM_SEARCH"; color="%{$fg[blue]%}" ;;
        detached)    icon="$_AI_CANDY_SYM_PLUG"; color="%{$fg[red]%}" ;;
      esac
    else
      case "$state" in
        rebase*|am*) icon="RB"; color="%{$fg[yellow]%}" ;;
        merge)       icon="MG"; color="%{$fg[cyan]%}" ;;
        cherry)      icon="CP"; color="%{$fg[red]%}" ;;
        revert)      icon="RV"; color="%{$fg[magenta]%}" ;;
        bisect)      icon="BI"; color="%{$fg[blue]%}" ;;
        detached)    icon="DT"; color="%{$fg[red]%}" ;;
      esac
      icon="[${icon}]"  # Wrap in brackets for plaintext mode
    fi

    if [[ -n "$step" && -n "$total" ]]; then
      _AI_CANDY_PP_GIT_SPECIAL="${color}${icon}${step}/${total}%{$reset_color%}"
    else
      _AI_CANDY_PP_GIT_SPECIAL="${color}${icon}%{$reset_color%}"
    fi
  fi

  _AI_CANDY_PROMPT_GIT_SPECIAL_CACHE="$_AI_CANDY_PP_GIT_SPECIAL"
  _AI_CANDY_PROMPT_GIT_SPECIAL_CACHE_ID="$current_id"
  _AI_CANDY_PROMPT_GIT_SPECIAL_CACHE_CONTEXT="$context_key"
}

# Direct-assignment version of _gh_pr_status_cached
# PERFORMANCE: Sets _AI_CANDY_PP_PR directly (0 subshells)
# Uses three-tier caching: per-prompt -> memory -> persistent (SQLite/file)
function _ai_candy_compute_pr_status_direct() {
  local current_id="$_AI_CANDY_PROMPT_RENDER_ID"
  if [[ "$_AI_CANDY_PROMPT_GH_PR_CACHE_ID" == "$current_id" ]]; then
    _AI_CANDY_PP_PR="$_AI_CANDY_PROMPT_GH_PR_CACHE"
    return
  fi

  _AI_CANDY_PP_PR=""

  # Skip if network mode is disabled
  (( _AI_CANDY_PROMPT_NETWORK_MODE )) || return

  # Skip if no hash command available (needed for cache key generation)
  (( _AI_CANDY_HAS_HASH_CMD )) || return

  # Check if gh command exists
  (( _AI_CANDY_HAS_GH )) || return

  # Check if gh is authenticated
  _ai_candy_gh_is_authenticated || return

  # Get cached git remote/branch
  _ai_candy_get_cached_git_remote_branch
  local remote_branch="$REPLY"
  [[ -z "$remote_branch" ]] && return

  local remote_key="${remote_branch%%|*}"
  local branch="${remote_branch#*|}"
  local cache_key="${remote_key}|${branch}"
  local pr_number="" ci_status="none" cache_time=0
  local current_time=${EPOCHSECONDS}

  # The session cache owns the hot PR lookup path.
  # Memory cache format: "pr_number|ci_status|timestamp"
  if [[ -n "${_AI_CANDY_MEM_CACHE_GH_PR[$cache_key]-}" ]]; then
    local cached="${_AI_CANDY_MEM_CACHE_GH_PR[$cache_key]}"
    cache_time="${cached##*|}"
    local rest="${cached%|*}"
    ci_status="${rest##*|}"
    pr_number="${rest%|*}"
    if _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_AI_CANDY_CACHE_TTL_HIGH" "$current_time"; then
      # Valid memory cache, skip persistent cache lookup
      :  # Fall through to display logic
    else
      # Memory cache expired, check persistent cache
      pr_number="" ci_status="none" cache_time=0
    fi
  fi

  # Check persistent cache if memory cache miss/expired
  if [[ -z "$pr_number" ]]; then
    local cached_line=""
    if _ai_candy_cache_get "gh_pr" "$cache_key"; then
      cached_line="$REPLY"
      cache_time="${cached_line##*|}"
      local rest="${cached_line%|*}"
      ci_status="${rest##*|}"
      pr_number="${rest%|*}"
      _ai_candy_cache_timestamp_is_valid "$cache_time" "$current_time" || cache_time=0

      # Update memory cache from persistent cache
      if [[ -n "$pr_number" ]]; then
        _AI_CANDY_MEM_CACHE_GH_PR[$cache_key]="${pr_number}|${ci_status}|${cache_time}"
        # Cleanup memory cache if it grows too large
        (( ${#_AI_CANDY_MEM_CACHE_GH_PR} > _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )) && _ai_candy_mem_cache_cleanup "gh_pr"
      fi
    fi
  fi

  if [[ -n "$pr_number" && "$pr_number" != "-1" && "$pr_number" != <-> ]]; then
    _ai_candy_mem_cache_remove_key gh_pr "$cache_key"
    pr_number=""
    ci_status="none"
    cache_time=0
  fi
  case "$ci_status" in
    pass|fail|pending|none) ;;
    *) ci_status="none" ;;
  esac

  # Refresh if expired
  _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_AI_CANDY_CACHE_TTL_HIGH" "$current_time" || \
    _ai_candy_gh_pr_update_cache "$remote_key" "$branch"

  # Display PR if valid
  if [[ -n "$pr_number" && "$pr_number" != "-1" ]]; then
    local ci_indicator=""
    case "$ci_status" in
      pass)
        (( _AI_CANDY_PROMPT_EMOJI_MODE )) && ci_indicator="%{$fg[green]%}${_AI_CANDY_SYM_CHECK}" || ci_indicator="%{$fg[green]%}OK"
        ;;
      fail)
        (( _AI_CANDY_PROMPT_EMOJI_MODE )) && ci_indicator="%{$fg[red]%}${_AI_CANDY_SYM_CROSS}" || ci_indicator="%{$fg[red]%}X"
        ;;
      pending)
        (( _AI_CANDY_PROMPT_EMOJI_MODE )) && ci_indicator="%{$fg[yellow]%}${_AI_CANDY_SYM_PENDING}" || ci_indicator="%{$fg[yellow]%}..."
        ;;
    esac

    if [[ -n "$ci_indicator" ]]; then
      _AI_CANDY_PP_PR="%{$FG[$_AI_CANDY_CLR_PR]%}#${pr_number}${ci_indicator}%{$reset_color%}"
    else
      _AI_CANDY_PP_PR="%{$FG[$_AI_CANDY_CLR_PR]%}#${pr_number}%{$reset_color%}"
    fi
  fi

  _AI_CANDY_PROMPT_GH_PR_CACHE="$_AI_CANDY_PP_PR"
  _AI_CANDY_PROMPT_GH_PR_CACHE_ID="$current_id"
}

# Optional-tool version status for the prompt
# Uses cache to avoid network requests on every prompt
# Shared across all terminals for better efficiency (uses _AI_CANDY_CACHE_TTL_LOW)
# (Cache file paths defined in CACHE FILE PATHS section)

# Git remote hashes are stable for a repository and remain in session memory.
typeset -gA _AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT
typeset -g _AI_CANDY_GIT_REMOTE_BRANCH_CACHE=""
typeset -g _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_ID=-1
typeset -g _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_CONTEXT=""

# Hash sensitive strings (e.g., remote URLs) for cache keys.
# Args: $1=input string
# Returns: hash string
# PERFORMANCE: Uses _AI_CANDY_HASH_CMD detected at load time (no repeated command -v calls)
# NOTE: Caller must check _AI_CANDY_HAS_HASH_CMD before calling this function
function _ai_candy_hash_string() {
  local input="$1"
  local hash=""

  case "${_AI_CANDY_HASH_CMD:t}" in
    sha256sum)
      hash=$(builtin print -rn -- "$input" | \
        _ai_candy_run_local_probe "$_AI_CANDY_HASH_CMD" 2>/dev/null) || hash=""
      hash="${hash%% *}"
      ;;
    shasum)
      hash=$(builtin print -rn -- "$input" | \
        _ai_candy_run_local_probe "$_AI_CANDY_HASH_CMD" -a 256 2>/dev/null) || hash=""
      hash="${hash%% *}"
      ;;
    openssl)
      hash=$(builtin print -rn -- "$input" | \
        _ai_candy_run_local_probe "$_AI_CANDY_HASH_CMD" dgst -sha256 2>/dev/null) || hash=""
      hash="${hash##* }"
      ;;
  esac

  [[ ${#hash} -eq 64 && "$hash" != *[^0-9A-Fa-f]* ]] || hash=""

  REPLY="${(L)hash}"
}

# Get cached git remote key and branch (per-prompt cache)
# Returns: remote_key|branch or empty if not in git repo
# Uses _AI_CANDY_PP_CACHED_GIT_ROOT set in _ai_candy_precmd_compute_prompt
function _ai_candy_get_cached_git_remote_branch() {
  local current_id="$_AI_CANDY_PROMPT_RENDER_ID"
  local git_root="$_AI_CANDY_PP_CACHED_GIT_ROOT"
  _ai_candy_git_context_cache_key "$git_root"
  local context_key="$REPLY"
  if [[ "$_AI_CANDY_GIT_REMOTE_BRANCH_CACHE_ID" == "$current_id" && \
        "$_AI_CANDY_GIT_REMOTE_BRANCH_CACHE_CONTEXT" == "$context_key" ]]; then
    REPLY="$_AI_CANDY_GIT_REMOTE_BRANCH_CACHE"
    return 0
  fi

  if [[ "$git_root" == "NOT_GIT" ]]; then
    _AI_CANDY_GIT_REMOTE_BRANCH_CACHE=""
    _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_ID="$current_id"
    _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_CONTEXT="$context_key"
    REPLY=""
    return 0
  fi

  local remote_key=""
  local current_time="${EPOCHSECONDS}"
  local cached_remote="${_AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT[$context_key]-}"
  integer cache_is_fresh=0
  if [[ -n "$cached_remote" ]]; then
    local cache_time="${cached_remote##*|}"
    local cached_key="${cached_remote%|*}"
    if _ai_candy_cache_timestamp_is_fresh "$cache_time" \
         "$_AI_CANDY_GIT_CONFIG_CACHE_TTL" "$current_time"; then
      remote_key="$cached_key"
      cache_is_fresh=1
    fi
  fi
  if (( ! cache_is_fresh )); then
    local remote_url=$(_ai_candy_run_local_probe git config --get remote.origin.url 2>/dev/null)
    if [[ -n "$remote_url" ]]; then
      _ai_candy_hash_string "$remote_url"
      remote_key="$REPLY"
    fi
    _AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT[$context_key]="${remote_key:--}|${current_time}"
    (( ${#_AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT} > _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )) && \
      _ai_candy_mem_cache_cleanup git_remote
  fi
  [[ "$remote_key" == "-" ]] && remote_key=""

  local branch=""
  if _ai_candy_resolve_git_dir "$git_root"; then
    local head_contents=""
    _ai_candy_read_git_metadata_file "${REPLY}/HEAD" && head_contents="$REPLY"
    if [[ "$head_contents" == "ref: refs/heads/"* ]]; then
      branch="${head_contents#ref: refs/heads/}"
    fi
  fi

  if [[ -n "$remote_key" && -n "$branch" ]]; then
    _AI_CANDY_GIT_REMOTE_BRANCH_CACHE="${remote_key}|${branch}"
  else
    _AI_CANDY_GIT_REMOTE_BRANCH_CACHE=""
  fi
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_ID="$current_id"
  _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_CONTEXT="$context_key"
  REPLY="$_AI_CANDY_GIT_REMOTE_BRANCH_CACHE"
}

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
    builtin print -rn -- " ${_AI_CANDY_GIT_FORMATTED_INFO}${_AI_CANDY_GIT_FORMATTED_EXT}"
  fi
}

typeset _ai_candy_async_style=""
if (( $+functions[_omz_register_handler] && $+functions[_omz_async_request] )) && \
   { builtin zstyle -t ':omz:alpha:lib:git' async-prompt || \
     builtin zstyle -T ':omz:alpha:lib:git' async-prompt || \
     { builtin zstyle -s ':omz:alpha:lib:git' async-prompt _ai_candy_async_style && \
       [[ "$_ai_candy_async_style" == "force" ]]; }; }; then
  if _omz_register_handler _ai_candy_git_prompt_async; then
    _AI_CANDY_USE_OMZ_ASYNC=1
  fi
fi
unset _ai_candy_async_style
typeset -gi _AI_CANDY_GIT_CONFIG_GRAPH_FAILURE_SEQUENCE
typeset -gA _AI_CANDY_GIT_CONFIG_GRAPH_PATHS_BY_KEY
typeset -gA _AI_CANDY_GIT_CONFIG_GRAPH_CONTEXT_BY_KEY
typeset -gi _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_ID=-1
typeset -g _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_KEY=""
typeset -g _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_VALUE=""
typeset -gi _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_PROBE_FAILED=0
typeset -gA _AI_CANDY_GIT_CONFIG_GRAPH_TIMEOUT_BY_KEY

function _ai_candy_git_config_graph_paths_context_key() {
  emulate -L zsh
  local serialized_paths="$1"
  local config_path="" config_context=""
  local graph_context=""
  local -a config_paths
  integer path_index=0
  REPLY=""

  [[ -n "$serialized_paths" ]] && config_paths=("${(@f)serialized_paths}")
  for config_path in "${config_paths[@]}"; do
    _ai_candy_git_config_file_context_key "$config_path"
    config_context="$REPLY"
    (( ++path_index ))
    graph_context+="f${path_index}:${#config_context}:${config_context}"
  done
  REPLY="$graph_context"
}

function _ai_candy_git_scan_config_graph_paths() {
  emulate -L zsh
  setopt localoptions noerrexit noerrreturn
  local command_root="$1"
  local origin_base="$2"
  local origin="" entry="" raw_path="" config_path=""
  local key="" include_path="" include_base=""
  local phase=origins
  local -a config_paths
  local -A seen_paths
  integer completed=0 probe_failed=0 probe_timed_out=0 max_paths=128
  REPLY=""

  while IFS= builtin read -r -d $'\0' origin && \
        IFS= builtin read -r -d $'\0' entry; do
    if [[ -z "$origin" ]]; then
      case "$entry" in
        _AI_CANDY_CONFIG_GRAPH_INCLUDES) phase=includes ;;
        _AI_CANDY_CONFIG_GRAPH_DONE) completed=1; break ;;
        _AI_CANDY_CONFIG_GRAPH_PROBE_FAILED) probe_failed=1; break ;;
        _AI_CANDY_CONFIG_GRAPH_PROBE_TIMED_OUT) probe_timed_out=1; break ;;
        *) return 1 ;;
      esac
      continue
    fi

    config_path=""
    if [[ "$origin" == file:* ]]; then
      raw_path="${origin#file:}"
      [[ -n "$raw_path" && ${#raw_path} -le 4096 && \
         "$raw_path" != *$'\n'* ]] || return 1
      if [[ "$raw_path" == /* ]]; then
        config_path="${raw_path:a}"
      else
        config_path="${origin_base%/}/${raw_path}"
        config_path="${config_path:a}"
      fi
      if [[ -z "${seen_paths[$config_path]-}" ]]; then
        (( ${#config_paths} < max_paths )) || return 1
        seen_paths[$config_path]=1
        config_paths+=("$config_path")
      fi
    fi

    [[ "$phase" == includes ]] || continue
    [[ "$entry" == *$'\n'* ]] || return 1
    key="${entry%%$'\n'*}"
    include_path="${entry#*$'\n'}"
    [[ "${(L)key}" == include.path || \
       "${(L)key}" == includeif.*.path ]] || return 1
    [[ -n "$include_path" && ${#include_path} -le 4096 && \
       "$include_path" != *$'\n'* ]] || return 1
    [[ "$include_path" != '%(prefix)/'* ]] || return 1
    include_base="$command_root"
    [[ -n "$config_path" ]] && include_base="${config_path:h}"
    case "$include_path" in
      /*) config_path="$include_path" ;;
      '~') [[ -n "${HOME-}" ]] || return 1; config_path="$HOME" ;;
      '~/'*)
        [[ -n "${HOME-}" ]] || return 1
        config_path="${HOME%/}/${include_path#\~/}"
        ;;
      '~'*) return 1 ;;
      *) config_path="${include_base%/}/${include_path}" ;;
    esac
    config_path="${config_path:a}"
    if [[ -z "${seen_paths[$config_path]-}" ]]; then
      (( ${#config_paths} < max_paths )) || return 1
      seen_paths[$config_path]=1
      config_paths+=("$config_path")
    fi
  done < <(
    local _AI_CANDY_TIMEOUT_OUTPUT_MAX_BYTES=$((64 * 1024))
    local probe_status=0
    if _ai_candy_run_git_probe_at_root "$command_root" config --includes \
         --show-origin --null --name-only --list 2>/dev/null; then
      builtin print -rn -- $'\0_AI_CANDY_CONFIG_GRAPH_INCLUDES\0'
      local include_status=0
      _ai_candy_run_git_probe_at_root "$command_root" config --includes \
        --show-origin --null --path --get-regexp \
        '^include(if\..*)?\.path$' 2>/dev/null || include_status=$?
      if (( include_status == 0 || include_status == 1 )); then
        builtin print -rn -- $'\0_AI_CANDY_CONFIG_GRAPH_DONE\0'
      elif (( include_status == 124 )); then
        builtin print -rn -- $'\0_AI_CANDY_CONFIG_GRAPH_PROBE_TIMED_OUT\0'
      else
        builtin print -rn -- $'\0_AI_CANDY_CONFIG_GRAPH_PROBE_FAILED\0'
      fi
    else
      probe_status=$?
      if (( probe_status == 124 )); then
        builtin print -rn -- $'\0_AI_CANDY_CONFIG_GRAPH_PROBE_TIMED_OUT\0'
      else
        builtin print -rn -- $'\0_AI_CANDY_CONFIG_GRAPH_PROBE_FAILED\0'
      fi
    fi
  )

  (( ! probe_timed_out )) || return 2
  (( ! probe_failed )) || return 1
  (( completed )) || return 1
  REPLY="${(pj:\n:)config_paths}"
}

function _ai_candy_git_config_graph_context_key() {
  emulate -L zsh
  local command_root="$1" origin_base="$2" graph_key="$3"
  local serialized_paths="" graph_context="" timeout_record=""
  local retry_after="" timeout_context=""
  integer render_id="${_AI_CANDY_PROMPT_RENDER_ID:-0}"
  integer cached_entry=${+_AI_CANDY_GIT_CONFIG_GRAPH_PATHS_BY_KEY[$graph_key]}
  integer current_time=$EPOCHSECONDS
  REPLY=""

  if (( render_id > 0 && \
        _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_ID == render_id )) && \
     [[ "$_AI_CANDY_GIT_CONFIG_GRAPH_RENDER_KEY" == "$graph_key" ]]; then
    REPLY="$_AI_CANDY_GIT_CONFIG_GRAPH_RENDER_VALUE"
    (( _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_PROBE_FAILED )) && \
      _AI_CANDY_GIT_METADATA_PROBE_FAILED=1
    return 0
  fi
  _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_PROBE_FAILED=0

  if (( cached_entry )); then
    serialized_paths="${_AI_CANDY_GIT_CONFIG_GRAPH_PATHS_BY_KEY[$graph_key]}"
    _ai_candy_git_config_graph_paths_context_key "$serialized_paths"
    graph_context="$REPLY"
    if (( _AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE )) && \
       [[ "${_AI_CANDY_GIT_CONFIG_GRAPH_CONTEXT_BY_KEY[$graph_key]-}" == \
          "$graph_context" ]]; then
      REPLY="$graph_context"
      _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_ID="$render_id"
      _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_KEY="$graph_key"
      _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_VALUE="$REPLY"
      return 0
    fi
  fi

  timeout_record="${_AI_CANDY_GIT_CONFIG_GRAPH_TIMEOUT_BY_KEY[$graph_key]-}"
  if [[ "$timeout_record" == *"|"* ]]; then
    retry_after="${timeout_record%%|*}"
    timeout_context="${timeout_record#*|}"
  fi
  if [[ "$retry_after" == <-> && "$timeout_context" == x<-> ]] && \
     (( current_time < retry_after )); then
    _AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE=0
    _AI_CANDY_GIT_METADATA_CONTEXT_PERSISTABLE=0
    _AI_CANDY_GIT_METADATA_PROBE_FAILED=1
    _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_PROBE_FAILED=1
    REPLY="$timeout_context"
    _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_ID="$render_id"
    _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_KEY="$graph_key"
    _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_VALUE="$REPLY"
    return 0
  fi
  [[ -n "$timeout_record" ]] && \
    _ai_candy_mem_cache_remove_key git_config_graph_timeout "$graph_key"

  integer scan_status=0
  _ai_candy_git_scan_config_graph_paths \
    "$command_root" "$origin_base" || scan_status=$?
  if (( scan_status != 0 )); then
    (( ++_AI_CANDY_GIT_CONFIG_GRAPH_FAILURE_SEQUENCE ))
    _AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE=0
    _AI_CANDY_GIT_METADATA_CONTEXT_PERSISTABLE=0
    if (( scan_status == 2 )); then
      _AI_CANDY_GIT_METADATA_PROBE_FAILED=1
      _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_PROBE_FAILED=1
    fi
    REPLY="x${_AI_CANDY_GIT_CONFIG_GRAPH_FAILURE_SEQUENCE}"
    if (( scan_status == 2 )); then
      if (( ${#_AI_CANDY_GIT_CONFIG_GRAPH_TIMEOUT_BY_KEY} >= \
            _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )); then
        _AI_CANDY_GIT_CONFIG_GRAPH_TIMEOUT_BY_KEY=()
      fi
      _AI_CANDY_GIT_CONFIG_GRAPH_TIMEOUT_BY_KEY[$graph_key]="$(( current_time + 3 ))|${REPLY}"
    fi
    _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_ID="$render_id"
    _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_KEY="$graph_key"
    _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_VALUE="$REPLY"
    return 0
  fi
  serialized_paths="$REPLY"
  _ai_candy_git_config_graph_paths_context_key "$serialized_paths"
  graph_context="$REPLY"
  if (( ! _AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE )); then
    (( ++_AI_CANDY_GIT_CONFIG_GRAPH_FAILURE_SEQUENCE ))
    _AI_CANDY_GIT_METADATA_CONTEXT_PERSISTABLE=0
    REPLY="x${_AI_CANDY_GIT_CONFIG_GRAPH_FAILURE_SEQUENCE}"
    _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_ID="$render_id"
    _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_KEY="$graph_key"
    _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_VALUE="$REPLY"
    return 0
  fi
  if (( ! cached_entry && \
        ${#_AI_CANDY_GIT_CONFIG_GRAPH_PATHS_BY_KEY} >= \
          _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )); then
    _AI_CANDY_GIT_CONFIG_GRAPH_PATHS_BY_KEY=()
    _AI_CANDY_GIT_CONFIG_GRAPH_CONTEXT_BY_KEY=()
    _AI_CANDY_GIT_CONFIG_GRAPH_TIMEOUT_BY_KEY=()
  fi
  _AI_CANDY_GIT_CONFIG_GRAPH_PATHS_BY_KEY[$graph_key]="$serialized_paths"
  _AI_CANDY_GIT_CONFIG_GRAPH_CONTEXT_BY_KEY[$graph_key]="$graph_context"
  REPLY="$graph_context"
  _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_ID="$render_id"
  _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_KEY="$graph_key"
  _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_VALUE="$REPLY"
}

function _ai_candy_git_effective_config_context_key() {
  emulate -L zsh
  local command_root="$1" origin_base="$2" resolved_git_dir="$3"
  local resolved_git_common_dir="$4" discovery_context="$5"
  local external_context="$6" common_context="$7" worktree_context="$8"
  local head_context="" graph_context="" graph_key="v1"

  _ai_candy_git_config_file_context_key "${resolved_git_dir}/HEAD"
  head_context="$REPLY"
  if (( ${+GIT_CONFIG_PARAMETERS} || ${+GIT_CONFIG_COUNT} )); then
    graph_key+="o${#command_root}:${command_root}"
  fi
  graph_key+="b${#origin_base}:${origin_base}"
  graph_key+="d${#resolved_git_dir}:${resolved_git_dir}"
  graph_key+="m${#resolved_git_common_dir}:${resolved_git_common_dir}"
  graph_key+="c${#discovery_context}:${discovery_context}"
  graph_key+="e${#external_context}:${external_context}"
  graph_key+="l${#common_context}:${common_context}"
  graph_key+="w${#worktree_context}:${worktree_context}"
  graph_key+="h${#head_context}:${head_context}"
  _ai_candy_git_config_graph_context_key \
    "$command_root" "$origin_base" "$graph_key"
  graph_context="$REPLY"
  REPLY="h${#head_context}:${head_context}"
  REPLY+="g${#graph_context}:${graph_context}"
}
typeset -g _AI_CANDY_SMART_PATH_CONTEXT_KEY=""
typeset -g _AI_CANDY_SMART_PATH_CONTEXT_TIMESTAMP=0
typeset -g _AI_CANDY_SMART_PATH_FALLBACK=""
typeset -g _AI_CANDY_SMART_PATH_NUM_REPOS=0
typeset -g _AI_CANDY_SMART_PATH_TOTAL_LENGTH=0
typeset -g _AI_CANDY_SMART_PATH_SEPARATOR="/"
typeset -ga _AI_CANDY_SMART_PATH_SEGMENTS
typeset -ga _AI_CANDY_SMART_PATH_SEGMENT_LENGTHS
typeset -g _AI_CANDY_SMART_PATH_RENDER_KEY=""
typeset -g _AI_CANDY_SMART_PATH_RENDER_VALUE=""

function _ai_candy_abbreviate_home_path() {
  local candidate_path="$1"
  local home_value="${HOME:-}"
  REPLY="$candidate_path"

  [[ "$home_value" == /* ]] || return 0
  while [[ "$home_value" != "/" && "$home_value" == */ ]]; do
    home_value="${home_value%/}"
  done

  if [[ "$candidate_path" == "$home_value" ]]; then
    REPLY="~"
  elif [[ "$home_value" == "/" && "$candidate_path" == /* ]]; then
    REPLY="~${candidate_path}"
  elif [[ "$candidate_path" == "${home_value}/"* ]]; then
    integer suffix_start=$(( ${#home_value} + 1 ))
    REPLY="~${candidate_path[$suffix_start,-1]}"
  fi
}

function _ai_candy_smart_path_context_key() {
  local home_value="${HOME:-}"
  local git_root_value="${_AI_CANDY_PP_CACHED_GIT_ROOT:-NOT_GIT}"
  _ai_candy_git_context_cache_key "$git_root_value"
  local git_context="$REPLY"
  REPLY="${#PWD}:${PWD}|${#home_value}:${home_value}|"
  REPLY+="${#git_context}:${git_context}|${_AI_CANDY_PROMPT_PATH_SEP_MODE}|"
  REPLY+="${_AI_CANDY_GIT_HIERARCHY_CACHE_VERSION}"
}

function _ai_candy_prepare_smart_path_context() {
  local current_time="$EPOCHSECONDS"
  _ai_candy_smart_path_context_key
  local context_key="$REPLY"
  if [[ "$_AI_CANDY_SMART_PATH_CONTEXT_KEY" == "$context_key" ]] && \
     _ai_candy_cache_timestamp_is_fresh "$_AI_CANDY_SMART_PATH_CONTEXT_TIMESTAMP" \
       "$_AI_CANDY_CACHE_TTL_MEDIUM" "$current_time"; then
    return 0
  fi

  _AI_CANDY_SMART_PATH_RENDER_KEY=""
  _AI_CANDY_SMART_PATH_RENDER_VALUE=""
  _AI_CANDY_SMART_PATH_CONTEXT_KEY="$context_key"
  _AI_CANDY_SMART_PATH_CONTEXT_TIMESTAMP="$current_time"
  _AI_CANDY_SMART_PATH_FALLBACK=""
  _AI_CANDY_SMART_PATH_NUM_REPOS=0
  _AI_CANDY_SMART_PATH_TOTAL_LENGTH=0
  _AI_CANDY_SMART_PATH_SEPARATOR="/"
  _AI_CANDY_SMART_PATH_SEGMENTS=()
  _AI_CANDY_SMART_PATH_SEGMENT_LENGTHS=()

  _ai_candy_abbreviate_home_path "$PWD"
  local full_path="$REPLY"
  if [[ "$_AI_CANDY_PP_CACHED_GIT_ROOT" == "NOT_GIT" ]]; then
    _AI_CANDY_SMART_PATH_FALLBACK="$full_path"
    _ai_candy_prompt_text_width "$full_path"
    _AI_CANDY_SMART_PATH_TOTAL_LENGTH=$(( REPLY + 2 ))
    return 0
  fi

  _ai_candy_get_git_hierarchy
  local hierarchy_str="$REPLY"
  if [[ -z "$hierarchy_str" ]]; then
    _AI_CANDY_SMART_PATH_FALLBACK="$full_path"
    _ai_candy_prompt_text_width "$full_path"
    _AI_CANDY_SMART_PATH_TOTAL_LENGTH=$(( REPLY + 2 ))
    return 0
  fi

  local hierarchy_separator="${_AI_CANDY_GIT_HIERARCHY_SEP:-:}"
  local -a parts repos
  parts=("${(@ps.$hierarchy_separator.)hierarchy_str}")
  local subdir=""
  integer num_parts=${#parts}
  if (( num_parts > 0 )); then
    subdir="${parts[-1]}"
    repos=("${parts[@]:0:$(( num_parts - 1 ))}")
  fi

  _AI_CANDY_SMART_PATH_NUM_REPOS=${#repos}
  local repo parent display_path segment
  integer index total_length=2 has_space=0
  for (( index=1; index<=_AI_CANDY_SMART_PATH_NUM_REPOS; index++ )); do
    repo="${repos[index]}"
    if (( index == 1 )); then
      _ai_candy_abbreviate_home_path "$repo"
      display_path="$REPLY"
    else
      parent="${repos[index-1]}"
      display_path="${repo#$parent/}"
    fi
    _AI_CANDY_SMART_PATH_SEGMENTS+=("$display_path")
    _ai_candy_prompt_text_width "$display_path"
    _AI_CANDY_SMART_PATH_SEGMENT_LENGTHS+=("$REPLY")
  done
  if [[ -n "$subdir" ]]; then
    _AI_CANDY_SMART_PATH_SEGMENTS+=("$subdir")
    _ai_candy_prompt_text_width "$subdir"
    _AI_CANDY_SMART_PATH_SEGMENT_LENGTHS+=("$REPLY")
  fi

  for index in "${_AI_CANDY_SMART_PATH_SEGMENT_LENGTHS[@]}"; do
    (( total_length += index ))
  done
  (( ${#_AI_CANDY_SMART_PATH_SEGMENTS} > 1 )) && \
    (( total_length += ${#_AI_CANDY_SMART_PATH_SEGMENTS} - 1 ))
  _AI_CANDY_SMART_PATH_TOTAL_LENGTH="$total_length"

  [[ "$PWD" == *" "* ]] && has_space=1
  if (( ! has_space )); then
    for segment in "${_AI_CANDY_SMART_PATH_SEGMENTS[@]}"; do
      if [[ "$segment" == *" "* ]]; then
        has_space=1
        break
      fi
    done
  fi
  (( _AI_CANDY_PROMPT_PATH_SEP_MODE && ! has_space )) && \
    _AI_CANDY_SMART_PATH_SEPARATOR=" "
}

function _ai_candy_render_plain_smart_path() {
  local display_path="$1"
  integer target_width="${2:-0}"
  integer content_width tail_width display_width

  _ai_candy_prompt_text_width "$display_path"
  display_width="$REPLY"
  if (( target_width > 0 && display_width + 2 > target_width )); then
    content_width=$(( target_width - 2 ))
    (( content_width < 0 )) && content_width=0
    if (( content_width <= 2 )); then
      _ai_candy_prompt_text_tail_by_width "$display_path" "$content_width"
      display_path="$REPLY"
    else
      tail_width=$(( content_width - 2 ))
      _ai_candy_prompt_text_tail_by_width "$display_path" "$tail_width"
      display_path="..${REPLY}"
    fi
  fi

  _ai_candy_prompt_escape_text "$display_path"
  _AI_CANDY_PP_PATH="%{$fg[white]%}[${REPLY}]%{$reset_color%}"
}

function _ai_candy_compute_smart_path_direct() {
  local use_short="${1:-full}"
  integer requested_width="${2:-0}"
  _ai_candy_prepare_smart_path_context

  local prompt_bang="${options[promptbang]}"
  local render_key="${#use_short}:${use_short}|${requested_width}|${prompt_bang}|${_AI_CANDY_SMART_PATH_CONTEXT_TIMESTAMP}|${#_AI_CANDY_SMART_PATH_CONTEXT_KEY}:${_AI_CANDY_SMART_PATH_CONTEXT_KEY}"
  if [[ "$_AI_CANDY_SMART_PATH_RENDER_KEY" == "$render_key" ]]; then
    _AI_CANDY_PP_PATH="$_AI_CANDY_SMART_PATH_RENDER_VALUE"
    return 0
  fi

  integer total_length=$_AI_CANDY_SMART_PATH_TOTAL_LENGTH
  integer target_width=0
  if [[ "$use_short" == "short" ]]; then
    if (( requested_width > 0 )); then
      target_width=$requested_width
    else
      target_width=${_AI_CANDY_PATH_TARGET_WIDTH_SHORT:-40}
    fi
  elif (( requested_width > 0 && total_length > requested_width )); then
    target_width=$requested_width
  fi

  if [[ -n "$_AI_CANDY_SMART_PATH_FALLBACK" ]]; then
    _ai_candy_render_plain_smart_path \
      "$_AI_CANDY_SMART_PATH_FALLBACK" "$target_width"
    _AI_CANDY_SMART_PATH_RENDER_KEY="$render_key"
    _AI_CANDY_SMART_PATH_RENDER_VALUE="$_AI_CANDY_PP_PATH"
    return 0
  fi

  local -a segments=("${_AI_CANDY_SMART_PATH_SEGMENTS[@]}")
  local -a segment_lengths=("${_AI_CANDY_SMART_PATH_SEGMENT_LENGTHS[@]}")
  integer total_segments=${#segments}
  integer start_index=1

  if (( target_width > 0 && total_length > target_width )); then
    while (( start_index < total_segments && total_length > target_width )); do
      (( total_length -= segment_lengths[start_index] + 1 ))
      (( start_index++ ))
      (( start_index == 2 )) && (( total_length += 3 ))
    done
  fi

  if (( target_width > 0 && total_length > target_width )); then
    _ai_candy_abbreviate_home_path "$PWD"
    _ai_candy_render_plain_smart_path "$REPLY" "$target_width"
    _AI_CANDY_SMART_PATH_RENDER_KEY="$render_key"
    _AI_CANDY_SMART_PATH_RENDER_VALUE="$_AI_CANDY_PP_PATH"
    return 0
  fi

  local ESC=$'\e'
  local result="["
  local output_separator=""
  local segment bg_num
  integer index level
  if (( start_index > 1 )); then
    result+="%{$FG[$_AI_CANDY_CLR_TRUNCATED]%}..%{$reset_color%}${_AI_CANDY_SMART_PATH_SEPARATOR}"
  fi

  for (( index=start_index; index<=total_segments; index++ )); do
    _ai_candy_prompt_escape_text "${segments[index]}"
    segment="$REPLY"
    if (( index <= _AI_CANDY_SMART_PATH_NUM_REPOS )); then
      level=$(( index - start_index ))
      (( level >= ${#_AI_CANDY_PATH_BG_COLORS} )) && \
        level=$(( ${#_AI_CANDY_PATH_BG_COLORS} - 1 ))
      bg_num="${_AI_CANDY_PATH_BG_COLORS[level+1]}"
      result+="${output_separator}%{${ESC}[48;5;${bg_num}m${ESC}[38;5;16m%}${segment}%{$reset_color%}"
    else
      result+="${output_separator}%{$fg[white]%}${segment}%{$reset_color%}"
    fi
    output_separator="$_AI_CANDY_SMART_PATH_SEPARATOR"
  done

  _AI_CANDY_PP_PATH="${result}]"
  _AI_CANDY_SMART_PATH_RENDER_KEY="$render_key"
  _AI_CANDY_SMART_PATH_RENDER_VALUE="$_AI_CANDY_PP_PATH"
}
# Helper: check if versions differ (indicates update available or version changed)
# Returns: 0 if versions differ, 1 if same or missing
# Simplified logic: any difference triggers indicator, avoids semver parsing issues
_ai_candy_version_differs() {
  local installed="$1"
  local remote="$2"

  [[ -z "$installed" || -z "$remote" ]] && return 1
  [[ "$installed" != "$remote" ]] && return 0
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
  (( _AI_CANDY_HAS_SSH )) || return
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

# Combined optional-tool status uses compact or delimited display formats.
# Direct-assignment version: writes result to _AI_CANDY_PP_AI_STATUS global variable
# Plaintext mode also generates _AI_CANDY_PP_AI_STATUS_LONG with full names.
# PERFORMANCE: Avoids subshells by using direct variable assignment
typeset -g _AI_CANDY_PP_AI_STATUS=""
typeset -g _AI_CANDY_PP_AI_STATUS_LONG=""
typeset -gA _AI_CANDY_AI_PROCESS_COUNTS=(claude 0 codex 0 gemini 0 kimi 0)
typeset -g _AI_CANDY_AI_PROCESS_SNAPSHOT_TIME=0
typeset -g _AI_CANDY_AI_PROCESS_SNAPSHOT_TTL=30
typeset -g _AI_CANDY_AI_PROCESS_SNAPSHOT_ATTEMPT_TIME=0
typeset -g _AI_CANDY_AI_PROCESS_SNAPSHOT_RETRY_TTL=5
function _ai_candy_refresh_ai_process_counts() {
  local current_time=$EPOCHSECONDS
  if _ai_candy_cache_timestamp_is_fresh "$_AI_CANDY_AI_PROCESS_SNAPSHOT_TIME" \
       "$_AI_CANDY_AI_PROCESS_SNAPSHOT_TTL" "$current_time"; then
    return 0
  fi
  if _ai_candy_cache_timestamp_is_fresh "$_AI_CANDY_AI_PROCESS_SNAPSHOT_ATTEMPT_TIME" \
       "$_AI_CANDY_AI_PROCESS_SNAPSHOT_RETRY_TTL" "$current_time"; then
    return 0
  fi
  _AI_CANDY_AI_PROCESS_SNAPSHOT_ATTEMPT_TIME="$current_time"

  local process_table=""
  if [[ "$OSTYPE" == darwin* ]]; then
    process_table=$(_ai_candy_run_process_count_probe ps -U "$UID" -o comm= -o args= 2>/dev/null) || return 0
  else
    process_table=$(_ai_candy_run_process_count_probe ps -u "$UID" -o comm= -o args= 2>/dev/null) || return 0
  fi

  _AI_CANDY_AI_PROCESS_COUNTS=(claude 0 codex 0 gemini 0 kimi 0)
  _AI_CANDY_AI_PROCESS_SNAPSHOT_TIME="$current_time"

  local line process_name
  for line in "${(@f)process_table}"; do
    [[ -n "$line" && "$line" != *"--version"* ]] || continue
    line="${line#"${line%%[![:space:]]*}"}"
    process_name="${line%%[[:space:]]*}"
    process_name="${process_name:t}"
    case "$process_name" in
      claude|codex|kimi)
        _AI_CANDY_AI_PROCESS_COUNTS[$process_name]=$(( ${_AI_CANDY_AI_PROCESS_COUNTS[$process_name]:-0} + 1 ))
        ;;
      gemini)
        _AI_CANDY_AI_PROCESS_COUNTS[gemini]=$(( ${_AI_CANDY_AI_PROCESS_COUNTS[gemini]:-0} + 1 ))
        ;;
      node)
        if [[ "$line" == *'/bin/gemini'* ]]; then
          _AI_CANDY_AI_PROCESS_COUNTS[gemini]=$(( ${_AI_CANDY_AI_PROCESS_COUNTS[gemini]:-0} + 1 ))
        fi
        ;;
    esac
  done
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
    _ai_candy_version_differs "$installed_version" "$remote_version" && update_ind="%{$fg[red]%}*"

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
    ai_status="${(j::)short_results}"
    ai_status_long="${(j::)long_results}"
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
# Enhanced PROMPT with all new features:
# - Exit status indicator
# - SSH indicator (nf-md-ssh/[SSH])
# - Public IP address (green if online, red "offline" if offline, hidden if no curl)
# - GitHub username badge [Username] (white bg, black text; red if mismatch)
# - Session badge (Container/TTY/GNOME/KDE/XFCE/Xorg/Host with NF icons or C/T/G/K/X/O/H)
# - Time with timezone [HH:MM:SS TZ]
# - Smart path with git-aware coloring and submodule support
# - Git status with extended info (ahead/behind/stash) + special states (rebase/merge/bisect)
# - PR status with CI indicator
# - Background jobs counter
# - Adaptive RPROMPT for system info and optional tools
# - Toggles for symbols, network features, tools, help, and cache refresh
#
# Order: status, identity, session, time, path, Git, PR, system, tools, jobs
# Second line: -> %#
#
# PERFORMANCE: Uses precomputed variables (_AI_CANDY_PP_*) from precmd to avoid subshells
# All segments are computed once in _ai_candy_precmd_compute_prompt before prompt display
PROMPT='${_AI_CANDY_PP_VENV}${_AI_CANDY_PP_EXIT}${_AI_CANDY_PP_SSH}${_AI_CANDY_PP_USER_HOST}${_AI_CANDY_PP_PUBLIC_IP}${_AI_CANDY_PP_GH_USER}${_AI_CANDY_PP_BADGE} %B${_AI_CANDY_PP_TIME}%b ${_AI_CANDY_PP_PATH}${${_AI_CANDY_USE_OMZ_ASYNC:#1}:+${_AI_CANDY_PP_GIT_INFO:+ }${_AI_CANDY_PP_GIT_INFO}${_AI_CANDY_PP_GIT_EXT}}${${_AI_CANDY_USE_OMZ_ASYNC:#0}:+${_OMZ_ASYNC_OUTPUT[_ai_candy_git_prompt_async]-}}${_AI_CANDY_PP_GIT_SPECIAL}${_AI_CANDY_PP_PR:+ }${_AI_CANDY_PP_PR}${_AI_CANDY_PP_SYSINFO_LEFT}${_AI_CANDY_PP_AI_LEFT}%(1j. %{$fg[yellow]%}${_AI_CANDY_PP_JOBS}%j%{$reset_color%}.)
%{$fg[blue]%}->%{$fg_bold[blue]%} %#%{$reset_color%} '

# Right prompt: system info and optional tools in short/minimal modes
# Auto-hides when command line is long
RPROMPT='${_AI_CANDY_PP_RPROMPT}'

ZSH_THEME_GIT_PROMPT_PREFIX='%F{green}'
ZSH_THEME_GIT_PROMPT_SUFFIX='%f'
ZSH_THEME_GIT_PROMPT_DIRTY=' %F{red}*%F{green}'
ZSH_THEME_GIT_PROMPT_CLEAN=""

_ai_candy_restore_source_options
builtin unfunction _ai_candy_restore_source_options
