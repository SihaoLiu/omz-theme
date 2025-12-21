# Helper: get visible length of a string with zsh prompt escapes stripped
_prompt_visible_len() {
  local str="$1"
  # Remove %{...%} zsh prompt escape sequences (zero-width markers)
  str=$(printf '%s' "$str" | sed 's/%{[^}]*}//g')
  printf '%d' "${#str}"
}

# Cache for prompt_dynamic_info to avoid double computation per prompt
_PROMPT_CACHE=""
_PROMPT_CACHE_KEY=""

# Function to build complete prompt info (host badge + system info + AI tools)
# Three-tier system: min (no extras) < short (compact system info) < long (full details + AI)
# Returns: "host_badge|system_info|ai_part" separated by pipes
# Cached per-prompt to avoid duplicate computation
function prompt_dynamic_info() {
  # Cache key: COLUMNS + PWD + last command exit status
  # This ensures cache is invalidated when terminal resizes or directory changes
  local cache_key="${COLUMNS}:${PWD}:$?"

  if [[ "$_PROMPT_CACHE_KEY" == "$cache_key" && -n "$_PROMPT_CACHE" ]]; then
    echo "$_PROMPT_CACHE"
    return
  fi
  local os_long="" os_short=""
  local kernel_long="" kernel_short=""
  local os_type=$(uname -s 2>/dev/null)

  if [[ "$os_type" == "Darwin" ]]; then
    # macOS: use sw_vers
    if command -v sw_vers &>/dev/null; then
      local product_name=$(sw_vers -productName 2>/dev/null)
      local product_version=$(sw_vers -productVersion 2>/dev/null)
      if [[ -n "$product_name" && -n "$product_version" ]]; then
        os_long="$product_name $product_version"
        os_short="macOS-$product_version"
      fi
    fi
  elif [[ -f /etc/os-release ]]; then
    # Linux: use /etc/os-release
    # Get PRETTY_NAME for long version
    local pretty_name=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    # Get ID-VERSION_ID for short version
    local os_id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    local version_id=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')

    if [[ -n "$pretty_name" ]]; then
      os_long="$pretty_name"
    fi
    if [[ -n "$os_id" && -n "$version_id" ]]; then
      # Capitalize first letter of os_id
      os_short="${(C)os_id}-$version_id"
    elif [[ -n "$os_id" ]]; then
      os_short="${(C)os_id}"
    fi
    # If no pretty_name, use short version for both
    [[ -z "$os_long" && -n "$os_short" ]] && os_long="$os_short"
  fi

  # Add kernel version if uname is available
  if command -v uname &>/dev/null; then
    local kernel_full=$(uname -r 2>/dev/null)
    if [[ -n "$kernel_full" ]]; then
      local kernel_name="$os_type"
      [[ -z "$kernel_name" ]] && kernel_name="Unknown"
      kernel_long=", $kernel_name-$kernel_full"
      # Extract just major.minor.patch for short version
      local kernel_short_ver=$(echo "$kernel_full" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
      if [[ -n "$kernel_short_ver" ]]; then
        kernel_short=", $kernel_name-$kernel_short_ver"
      else
        kernel_short="$kernel_long"
      fi
    fi
  fi

  # Determine container type and badge (4-char abbreviations)
  local container_type
  local badge_color
  if test -f /run/.containerenv; then
    container_type="CNTR"
    badge_color="%{$fg[magenta]%}"
  else
    container_type="HOST"
    badge_color="%{$fg[yellow]%}"
  fi

  # Calculate prompt lengths for all three tiers
  local git_info=$(git_prompt_info 2>/dev/null)
  local ai_info=$(ai_tools_status 2>/dev/null)
  local git_len=$(_prompt_visible_len "$git_info")
  local ai_len=$(_prompt_visible_len "$ai_info")

  # Core components (always present)
  local user_host_len=$((${#USER} + 1 + ${#HOST}))  # user@host
  local time_len=10                                  # [HH:MM:SS] 24-hour format
  local path_len=${#PWD}                             # current directory
  local fixed_len=7                                  # spaces and [] around path

  # Host/Container badge length: [Host] or [Container] + space
  local badge_len=$((${#container_type} + 3))  # +3 for [], space

  # MIN: user@host [time] [path] [git]
  local min_len=$((user_host_len + time_len + path_len + git_len + fixed_len))

  # SHORT: min + [Host/Container] + [os-short, kernel-short]
  local short_version="${os_short}${kernel_short}"
  local short_sysinfo_len=$((${#short_version} + 3))  # +3 for [], space
  local short_len=$((min_len + badge_len + short_sysinfo_len))

  # SHORT+AI: short + AI tools (+ 1 for space before AI)
  local ai_space=$([[ -n "$ai_info" ]] && echo 1 || echo 0)
  local short_ai_len=$((short_len + ai_len + ai_space))

  # LONG: min + badge + long system info + AI tools
  local long_version="${os_long}${kernel_long}"
  local long_sysinfo_len=$((${#long_version} + 3))  # +3 for [], space
  local long_len=$((min_len + badge_len + long_sysinfo_len + ai_len + ai_space))

  # Decide which tier to use based on COLUMNS
  # Priority: LONG > SHORT+AI > SHORT > MIN
  local host_badge=""
  local system_info=""
  local ai_output=""

  if (( long_len <= COLUMNS )); then
    # LONG mode: badge + full system info + AI tools
    host_badge=" ${badge_color}[${container_type}]%{$reset_color%}"
    system_info=" %{$fg[cyan]%}[${long_version}]%{$reset_color%}"
    [[ -n "$ai_info" ]] && ai_output=" $ai_info" || ai_output=""
  elif (( short_ai_len <= COLUMNS )); then
    # SHORT+AI mode: badge + short system info + AI tools
    host_badge=" ${badge_color}[${container_type}]%{$reset_color%}"
    system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
    [[ -n "$ai_info" ]] && ai_output=" $ai_info" || ai_output=""
  elif (( short_len <= COLUMNS )); then
    # SHORT mode: badge + short system info, no AI
    host_badge=" ${badge_color}[${container_type}]%{$reset_color%}"
    system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
    ai_output=""
  else
    # MIN mode: no badge, no system info, no AI
    host_badge=""
    system_info=""
    ai_output=""
  fi

  # Store in cache and return
  local result="${host_badge}|${system_info}|${ai_output}"
  _PROMPT_CACHE="$result"
  _PROMPT_CACHE_KEY="$cache_key"
  echo "$result"
}

# Extract host/container badge from prompt_dynamic_info
function host_container_badge() {
  local info=$(prompt_dynamic_info)
  echo "${info%%|*}"  # First part before first pipe
}

# Extract system info from prompt_dynamic_info
function system_info_status() {
  local info=$(prompt_dynamic_info)
  local rest="${info#*|}"  # Remove first part
  echo "${rest%%|*}"  # Second part before second pipe
}

# Extract AI status from prompt_dynamic_info
function ai_tools_status_conditional() {
  local info=$(prompt_dynamic_info)
  echo "${info##*|}"  # Last part after last pipe
}

# AI Coding Tools version status for prompt
# Uses cache to avoid network requests on every prompt
# Shared across all terminals for better efficiency
_AI_CACHE_TTL=3600  # Cache TTL in seconds (1 hour)
_CLAUDE_CACHE_FILE="${TMPDIR:-/tmp}/.claude_version_cache_${USER}"
_CODEX_CACHE_FILE="${TMPDIR:-/tmp}/.codex_version_cache_${USER}"
_GEMINI_CACHE_FILE="${TMPDIR:-/tmp}/.gemini_version_cache_${USER}"

# Helper: compare semantic versions, returns 0 if $1 > $2
_prompt_version_gt() {
  test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

# Update the Claude version cache (runs in background)
# Cache format: <local_version> <remote_version> <timestamp>
_claude_update_cache() {
  (
    local cache_file="$1"
    local installed_version
    local remote_version

    # Get local installed version
    installed_version=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    # Get remote latest version
    local changelog_url="https://raw.githubusercontent.com/anthropics/claude-code/refs/heads/main/CHANGELOG.md"
    remote_version=$(curl -s --max-time 5 "$changelog_url" | head -n 50 | grep "^## " | head -n 1 | sed 's/^## //')

    # Only update cache if we got the local version
    if [[ -n "$installed_version" ]]; then
      echo "$installed_version $remote_version $(date +%s)" > "$cache_file"
    fi
  ) &>/dev/null &
}

# Update the Codex version cache (runs in background)
# Note: /releases/latest endpoint excludes pre-releases, only returns stable releases
# Cache format: <local_version> <remote_version> <timestamp>
_codex_update_cache() {
  (
    local cache_file="$1"
    local installed_version
    local remote_version

    # Get local installed version
    installed_version=$(codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    # Get remote latest version
    local releases_url="https://api.github.com/repos/openai/codex/releases/latest"
    # Extract version from tag_name, handling formats like "rust-v0.73.0" or "v0.73.0"
    remote_version=$(curl -s --max-time 5 "$releases_url" | grep -o '"tag_name":[^,]*' | sed -E 's/.*"tag_name":"?.*-?v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

    # Only update cache if we got the local version
    if [[ -n "$installed_version" ]]; then
      echo "$installed_version $remote_version $(date +%s)" > "$cache_file"
    fi
  ) &>/dev/null &
}

# Update the Gemini CLI version cache (runs in background)
# Note: /releases/latest endpoint excludes pre-releases, only returns stable releases
# Cache format: <local_version> <remote_version> <timestamp>
_gemini_update_cache() {
  (
    local cache_file="$1"
    local installed_version
    local remote_version

    # Get local installed version
    installed_version=$(gemini --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    # Get remote latest version
    local releases_url="https://api.github.com/repos/google-gemini/gemini-cli/releases/latest"
    # Extract version from tag_name, handling formats like "v0.21.0" or "0.21.0"
    remote_version=$(curl -s --max-time 5 "$releases_url" | grep -o '"tag_name":[^,]*' | sed -E 's/.*"tag_name":"?.*-?v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

    # Only update cache if we got the local version
    if [[ -n "$installed_version" ]]; then
      echo "$installed_version $remote_version $(date +%s)" > "$cache_file"
    fi
  ) &>/dev/null &
}

# Get Claude Code status for prompt
function claude_code_status() {
  # Check if claude command exists
  if ! command -v claude &>/dev/null; then
    return
  fi

  local installed_version=""
  local remote_version=""
  local cache_time=0
  local current_time=$(date +%s)
  local update_available=false

  # Check cache for both local and remote versions
  if [[ -f "$_CLAUDE_CACHE_FILE" ]]; then
    read -r installed_version remote_version cache_time < "$_CLAUDE_CACHE_FILE"
    # Validate cache_time is a number
    if [[ ! "$cache_time" =~ ^[0-9]+$ ]]; then
      cache_time=0
    fi
    # Check if cache is still valid
    if (( current_time - cache_time > _AI_CACHE_TTL )); then
      # Cache expired, trigger background refresh
      _claude_update_cache "$_CLAUDE_CACHE_FILE"
    fi
  else
    # No cache, trigger background refresh
    _claude_update_cache "$_CLAUDE_CACHE_FILE"
  fi

  # If cache is empty or invalid, return nothing (background update in progress)
  if [[ -z "$installed_version" ]]; then
    return
  fi

  # Determine if update is available
  if [[ -n "$remote_version" ]] && _prompt_version_gt "$remote_version" "$installed_version"; then
    update_available=true
  fi

  # Output formatted status
  # Coral color: 173 (256-color) - dusty salmon/terracotta matching Claude Code branding
  if $update_available; then
    # Update available: [CC x.y.z *] with coral, * in red
    echo "%{$FG[173]%}[CC $installed_version %{$fg[red]%}*%{$FG[173]%}]%{$reset_color%}"
  else
    # Up to date: [CC x.y.z] all coral
    echo "%{$FG[173]%}[CC $installed_version]%{$reset_color%}"
  fi
}

# Get Codex status for prompt
function codex_status() {
  # Check if codex command exists
  if ! command -v codex &>/dev/null; then
    return
  fi

  local installed_version=""
  local remote_version=""
  local cache_time=0
  local current_time=$(date +%s)
  local update_available=false

  # Check cache for both local and remote versions
  if [[ -f "$_CODEX_CACHE_FILE" ]]; then
    read -r installed_version remote_version cache_time < "$_CODEX_CACHE_FILE"
    # Validate cache_time is a number
    if [[ ! "$cache_time" =~ ^[0-9]+$ ]]; then
      cache_time=0
    fi
    # Check if cache is still valid
    if (( current_time - cache_time > _AI_CACHE_TTL )); then
      # Cache expired, trigger background refresh
      _codex_update_cache "$_CODEX_CACHE_FILE"
    fi
  else
    # No cache, trigger background refresh
    _codex_update_cache "$_CODEX_CACHE_FILE"
  fi

  # If cache is empty or invalid, return nothing (background update in progress)
  if [[ -z "$installed_version" ]]; then
    return
  fi

  # Determine if update is available
  if [[ -n "$remote_version" ]] && _prompt_version_gt "$remote_version" "$installed_version"; then
    update_available=true
  fi

  # Output formatted status
  # Light gray color: 250
  if $update_available; then
    # Update available: [CX x.y.z *] with light gray, * in red
    echo "%{$FG[250]%}[CX $installed_version %{$fg[red]%}*%{$FG[250]%}]%{$reset_color%}"
  else
    # Up to date: [CX x.y.z] all light gray
    echo "%{$FG[250]%}[CX $installed_version]%{$reset_color%}"
  fi
}

# Get Gemini CLI status for prompt
function gemini_status() {
  # Check if gemini command exists
  if ! command -v gemini &>/dev/null; then
    return
  fi

  local installed_version=""
  local remote_version=""
  local cache_time=0
  local current_time=$(date +%s)
  local update_available=false

  # Check cache for both local and remote versions
  if [[ -f "$_GEMINI_CACHE_FILE" ]]; then
    read -r installed_version remote_version cache_time < "$_GEMINI_CACHE_FILE"
    # Validate cache_time is a number
    if [[ ! "$cache_time" =~ ^[0-9]+$ ]]; then
      cache_time=0
    fi
    # Check if cache is still valid
    if (( current_time - cache_time > _AI_CACHE_TTL )); then
      # Cache expired, trigger background refresh
      _gemini_update_cache "$_GEMINI_CACHE_FILE"
    fi
  else
    # No cache, trigger background refresh
    _gemini_update_cache "$_GEMINI_CACHE_FILE"
  fi

  # If cache is empty or invalid, return nothing (background update in progress)
  if [[ -z "$installed_version" ]]; then
    return
  fi

  # Determine if update is available
  if [[ -n "$remote_version" ]] && _prompt_version_gt "$remote_version" "$installed_version"; then
    update_available=true
  fi

  # Output formatted status
  # Purple color: 141 - Google purple-ish
  if $update_available; then
    # Update available: [GM x.y.z *] with purple, * in red
    echo "%{$FG[141]%}[GM $installed_version %{$fg[red]%}*%{$FG[141]%}]%{$reset_color%}"
  else
    # Up to date: [GM x.y.z] all purple
    echo "%{$FG[141]%}[GM $installed_version]%{$reset_color%}"
  fi
}

# Combined AI tools status
function ai_tools_status() {
  local ai_status=""
  local claude_st=$(claude_code_status)
  local codex_st=$(codex_status)
  local gemini_st=$(gemini_status)

  [[ -n "$claude_st" ]] && ai_status="$ai_status$claude_st"
  [[ -n "$codex_st" ]] && ai_status="$ai_status$codex_st"
  [[ -n "$gemini_st" ]] && ai_status="$ai_status$gemini_st"

  echo "$ai_status"
}

# Modified PROMPT with host badge, system info, and AI tools status
# Uses four-tier display: min < short < short+ai < long based on terminal width
# Order: user@host [Host/Container] [time] [path] [git] [system_info] [AI_tools]
PROMPT=$'%{$fg_bold[green]%}%n@%m%{$reset_color%}$(host_container_badge) %B%{$FG[214]%}[%D{%H:%M:%S}]%b%{$reset_color%} %{$fg[white]%}[%~]%{$reset_color%} $(git_prompt_info)$(system_info_status)$(ai_tools_status_conditional)\
%{$fg[blue]%}->%{$fg_bold[blue]%} %#%{$reset_color%} '

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg[green]%}["
ZSH_THEME_GIT_PROMPT_SUFFIX="]%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY=" %{$fg[red]%}*%{$fg[green]%}"
ZSH_THEME_GIT_PROMPT_CLEAN=""
