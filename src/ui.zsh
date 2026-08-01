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
  builtin print -r -- "${_AI_CANDY_BOX_V}    Enable aliases with AI_CANDY_ENABLE_SHORT_ALIASES=1           ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    u         Refresh all cached prompt info                      ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    e         Toggle emoji/plaintext mode                         ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    p         Toggle path separator (space/slash)                 ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    n         Toggle network features (IP, GitHub, AI updates)    ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    a         Toggle AI tools display (show/hide)                 ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    o         Toggle OS/kernel display (show/hide)                ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    off       Turn off all optional prompt features               ${_AI_CANDY_BOX_V}"
  builtin print -r -- "${_AI_CANDY_BOX_V}    on        Turn on all optional prompt features                ${_AI_CANDY_BOX_V}"
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
    "$_AI_CANDY_AI_PROCESS_CACHE_FILE"
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
  _AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT=()
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
  _AI_CANDY_REFRESH_REQUESTED=()
  _AI_CANDY_GIT_SNAPSHOT_RENDER_ID=-1
  _AI_CANDY_GIT_SNAPSHOT_CONTEXT=""
  _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_ID=-1
  _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_KEY=""
  _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_VALUE=""
  _AI_CANDY_GIT_CONFIG_GRAPH_RENDER_PROBE_FAILED=0
  _AI_CANDY_GIT_CONFIG_GRAPH_FAILURE_SEQUENCE=0
  _AI_CANDY_GIT_ROOT_IS_FALLBACK=0
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
  _AI_CANDY_GIT_ROOT_IS_FALLBACK=0
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
