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
  local -a owned_pids verified_pids descendants cleanup_pids
  local -A owned_identities
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
    builtin kill -STOP "$background_pid" 2>/dev/null
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
        builtin kill -STOP "$process_pid" 2>/dev/null
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
  for process_pid in "${descendants[@]}"; do
    builtin kill -CONT "$process_pid" 2>/dev/null
  done
  for background_pid in "${verified_pids[@]}"; do
    builtin kill -CONT "$background_pid" 2>/dev/null
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
