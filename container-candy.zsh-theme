# Helper: get visible length of a string with zsh prompt escapes stripped
_prompt_visible_len() {
  local str="$1"
  # Remove %{...%} zsh prompt escape sequences (zero-width markers)
  # Process one %{...%} at a time: find first %{, then first %} after it
  while [[ "$str" == *'%{'*'%}'* ]]; do
    local prefix="${str%%\%\{*}"      # everything before first %{
    local rest="${str#*\%\{}"         # everything after first %{
    local suffix="${rest#*\%\}}"      # everything after first %} in rest
    str="${prefix}${suffix}"
  done
  printf '%d' "${#str}"
}

zmodload zsh/datetime 2>/dev/null

# Emoji mode toggle (1 = emoji-rich, 0 = plaintext)
# Persisted to file so it survives shell restarts
_EMOJI_MODE_FILE="${TMPDIR:-/tmp}/.prompt_emoji_mode_${USER}"

# Load emoji mode from file or default to 1 (emoji-rich)
if [[ -f "$_EMOJI_MODE_FILE" ]]; then
  _PROMPT_EMOJI_MODE=$(<"$_EMOJI_MODE_FILE")
else
  _PROMPT_EMOJI_MODE=1
fi

# Emoji/text mappings - returns emoji or text based on mode
# Usage: $(_e exit_ok) returns ✓ or [OK]
function _e() {
  local key="$1"
  if (( _PROMPT_EMOJI_MODE )); then
    case "$key" in
      exit_ok)    echo "✓" ;;
      exit_fail)  echo "✗" ;;
      ssh)        echo "⚡" ;;
      host)       echo "🖥️" ;;
      container)  echo "📦" ;;
      claude)     echo "🤖" ;;
      codex)      echo "🧠" ;;
      gemini)     echo "🔷" ;;
      ahead)      echo "↑" ;;
      behind)     echo "↓" ;;
      stash)      echo "⚑" ;;
      jobs)       echo "⚙" ;;
      pending)    echo "⏳" ;;
      pass)       echo "✓" ;;
      fail)       echo "✗" ;;
      update)     echo "*" ;;
      truncated)  echo ".." ;;
      *)          echo "$key" ;;  # fallback
    esac
  else
    case "$key" in
      exit_ok)    echo "OK" ;;
      exit_fail)  echo "ERR" ;;
      ssh)        echo "SSH" ;;
      host)       echo "H" ;;
      container)  echo "C" ;;
      claude)     echo "Cl:" ;;
      codex)      echo "Cx:" ;;
      gemini)     echo "Gm:" ;;
      ahead)      echo "+" ;;
      behind)     echo "-" ;;
      stash)      echo "S" ;;
      jobs)       echo "J" ;;
      pending)    echo "..." ;;
      pass)       echo "OK" ;;
      fail)       echo "X" ;;
      update)     echo "*" ;;
      truncated)  echo ".." ;;
      *)          echo "$key" ;;  # fallback
    esac
  fi
}

# Toggle emoji mode
function _prompt_toggle_emoji() {
  if (( _PROMPT_EMOJI_MODE )); then
    _PROMPT_EMOJI_MODE=0
    echo "0" > "$_EMOJI_MODE_FILE"
    echo "Switched to plaintext mode"
  else
    _PROMPT_EMOJI_MODE=1
    echo "1" > "$_EMOJI_MODE_FILE"
    echo "Switched to emoji mode"
  fi
  # Clear caches to force re-render
  _PROMPT_CACHE=""
  _PROMPT_CACHE_KEY=""
}

# Print emoji help/legend
function _prompt_emoji_help() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║              ZSH Prompt Emoji/Symbol Reference                   ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  COMMAND STATUS                                                  ║"
  echo "║    [✓] / [OK]    Last command succeeded (exit code 0)            ║"
  echo "║    [✗N] / [ERRN] Last command failed with exit code N            ║"
  echo "║    Example: [✗127] means 'command not found'                     ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  CONNECTION & ENVIRONMENT                                        ║"
  echo "║    ⚡ / [SSH] Connected via SSH                                  ║"
  echo "║    🖥️  / H     Running on host machine                            ║"
  echo "║    📦 / C     Running inside a container                         ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  GIT STATUS                                                      ║"
  echo "║    ↑N / +N   N commits ahead of upstream (need to push)          ║"
  echo "║    ↓N / -N   N commits behind upstream (need to pull)            ║"
  echo "║    ⚑N / SN   N stashed changes                                   ║"
  echo "║    *         Uncommitted changes in working directory            ║"
  echo "║    Example: main ↑2↓1⚑3 means branch 'main', 2 ahead,            ║"
  echo "║             1 behind, 3 stashes                                  ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  GITHUB PR STATUS                                                ║"
  echo "║    #N        Pull request number N for current branch            ║"
  echo "║    ✓ / OK    All CI checks passed                                ║"
  echo "║    ✗ / X     Some CI checks failed                               ║"
  echo "║    ⏳ / ...   CI checks still running                            ║"
  echo "║    Example: #42✓ means PR #42 with all checks passing            ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  AI CODING TOOLS                                                 ║"
  echo "║    🤖 / Cl:   Claude Code version                                ║"
  echo "║    🧠 / Cx:   OpenAI Codex version                               ║"
  echo "║    🔷 / Gm:   Google Gemini CLI version                          ║"
  echo "║    *         Update available (shown after version)              ║"
  echo "║    Example: 🤖2.0.76* means Claude v2.0.76 with update available ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  OTHER                                                           ║"
  echo "║    ⚙N / JN   N background jobs running                           ║"
  echo "║    ..        Path truncated (in narrow terminal)                 ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  QUICK COMMANDS                                                  ║"
  echo "║    u         Refresh all cached prompt info                      ║"
  echo "║    e         Toggle emoji/plaintext mode                         ║"
  echo "║    h         Show this help                                      ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
}

# Aliases for quick commands
alias e='_prompt_toggle_emoji'
alias h='_prompt_emoji_help'

# Manual cache refresh function - clears all prompt caches
# Call this to force refresh of all cached data (system info, git, PR, AI tools)
function _prompt_refresh_all_caches() {
  # Clear file-based caches by removing cache files
  rm -f "$_SYSINFO_CACHE_FILE" 2>/dev/null
  rm -f "$_GIT_ROOT_CACHE_FILE" 2>/dev/null
  rm -f "$_GIT_HIERARCHY_CACHE_FILE" 2>/dev/null
  rm -f "$_GIT_EXT_CACHE_FILE" 2>/dev/null
  rm -f "$_GH_PR_CACHE_FILE" 2>/dev/null
  rm -f "$_CLAUDE_CACHE_FILE" 2>/dev/null
  rm -f "$_CODEX_CACHE_FILE" 2>/dev/null
  rm -f "$_GEMINI_CACHE_FILE" 2>/dev/null

  # Reset in-memory per-prompt caches
  _PROMPT_CACHE=""
  _PROMPT_CACHE_KEY=""
  _PROMPT_GIT_INFO_CACHE=""
  _PROMPT_GIT_INFO_CACHE_ID=-1
  _PROMPT_GIT_EXT_CACHE=""
  _PROMPT_GIT_EXT_CACHE_ID=-1
  _PROMPT_GH_PR_CACHE=""
  _PROMPT_GH_PR_CACHE_ID=-1
  _GIT_REMOTE_BRANCH_CACHE=""
  _GIT_REMOTE_BRANCH_CACHE_ID=-1
  _SMART_PATH_CACHE=""
  _SMART_PATH_CACHE_KEY=""

  echo "Prompt caches refreshed."
}

# Alias for quick cache refresh
alias u='_prompt_refresh_all_caches'

# SSH session indicator
# Returns ⚡/[SSH] if connected via SSH, empty otherwise
# Plaintext mode wraps in brackets with trailing space, emoji mode shows just the symbol
function ssh_indicator() {
  if [[ -n "$SSH_CONNECTION" ]]; then
    if (( _PROMPT_EMOJI_MODE )); then
      echo "%{$fg[cyan]%}$(_e ssh)%{$reset_color%}"
    else
      echo "%{$fg[cyan]%}[$(_e ssh)]%{$reset_color%} "
    fi
  fi
}

# Capture exit status before any other precmd runs
_LAST_EXIT_STATUS=0
function _capture_exit_status() {
  _LAST_EXIT_STATUS=$?
}
# Add as first precmd hook
autoload -Uz add-zsh-hook
add-zsh-hook precmd _capture_exit_status

# Exit status indicator - shows success/failure with code, wrapped in brackets
function exit_status_indicator() {
  if [[ $_LAST_EXIT_STATUS -eq 0 ]]; then
    echo "%{$fg[green]%}[$(_e exit_ok)]%{$reset_color%}"
  else
    echo "%{$fg[red]%}[$(_e exit_fail)${_LAST_EXIT_STATUS}]%{$reset_color%}"
  fi
}

# Background jobs indicator
function jobs_indicator() {
  # Get job count using zsh's special %j which expands at prompt time
  # We return the icon/text based on mode, prompt handles the conditional
  echo "$(_e jobs)"
}

# Time display with dynamic color based on hour of day
# Morning (6-12): warm yellow, Afternoon (12-18): bright white
# Evening (18-22): soft orange, Night (22-6): dim blue
function time_with_color() {
  local hour=""
  if (( ${+EPOCHSECONDS} )); then
    strftime -s hour "%H" "$EPOCHSECONDS"
  else
    hour=$(date +%H)
  fi
  local color
  if (( hour >= 6 && hour < 12 )); then
    color="%{$FG[214]%}"    # Morning: warm yellow
  elif (( hour >= 12 && hour < 18 )); then
    color="%{$FG[255]%}"    # Afternoon: bright white
  elif (( hour >= 18 && hour < 22 )); then
    color="%{$FG[208]%}"    # Evening: soft orange
  else
    color="%{$FG[111]%}"    # Night: dim blue
  fi
  echo "${color}[%D{%H:%M:%S}]%{$reset_color%}"
}

# Cache for prompt_dynamic_info to avoid double computation per prompt
_PROMPT_CACHE=""
_PROMPT_CACHE_KEY=""

# Per-prompt render id to avoid recomputing expensive segments multiple times
_PROMPT_RENDER_ID=0
function _prompt_bump_render_id() {
  (( _PROMPT_RENDER_ID++ ))
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _prompt_bump_render_id

# Per-prompt caches for git/PR segments
_PROMPT_GIT_INFO_CACHE=""
_PROMPT_GIT_INFO_CACHE_ID=-1
_PROMPT_GIT_EXT_CACHE=""
_PROMPT_GIT_EXT_CACHE_ID=-1
_PROMPT_GH_PR_CACHE=""
_PROMPT_GH_PR_CACHE_ID=-1

# Git extended status cache (file-based, 5 min TTL)
_GIT_EXT_CACHE_FILE="${TMPDIR:-/tmp}/.git_ext_cache_${USER}"
_GIT_EXT_CACHE_TTL=300  # 5 minutes

# System info cache (file-based, 1 hour TTL - rarely changes)
_SYSINFO_CACHE_FILE="${TMPDIR:-/tmp}/.sysinfo_cache_${USER}"
_SYSINFO_CACHE_TTL=3600  # 1 hour

# Get cached system info (OS and kernel versions)
# Returns: os_long|os_short|kernel_long|kernel_short
# Cached to avoid subprocess calls on every prompt
function _get_cached_sysinfo() {
  local current_time=${EPOCHSECONDS:-$(date +%s)}

  # Check file cache (use zsh native file reading to avoid subprocesses)
  if [[ -f "$_SYSINFO_CACHE_FILE" ]]; then
    local cache_lines=("${(@f)$(<"$_SYSINFO_CACHE_FILE")}")
    local cache_time="${cache_lines[1]}"
    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time < _SYSINFO_CACHE_TTL )); then
      echo "${cache_lines[2]}"
      return
    fi
  fi

  # Compute system info
  local os_long="" os_short=""
  local kernel_long="" kernel_short=""
  local os_type=$(uname -s 2>/dev/null)

  if [[ "$os_type" == "Darwin" ]]; then
    if command -v sw_vers &>/dev/null; then
      local product_name=$(sw_vers -productName 2>/dev/null)
      local product_version=$(sw_vers -productVersion 2>/dev/null)
      if [[ -n "$product_name" && -n "$product_version" ]]; then
        os_long="$product_name $product_version"
        os_short="macOS-$product_version"
      fi
    fi
  elif [[ -f /etc/os-release ]]; then
    local pretty_name=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    local os_id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    local version_id=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')

    [[ -n "$pretty_name" ]] && os_long="$pretty_name"
    if [[ -n "$os_id" && -n "$version_id" ]]; then
      os_short="${(C)os_id}-$version_id"
    elif [[ -n "$os_id" ]]; then
      os_short="${(C)os_id}"
    fi
    [[ -z "$os_long" && -n "$os_short" ]] && os_long="$os_short"
  fi

  if command -v uname &>/dev/null; then
    local kernel_full=$(uname -r 2>/dev/null)
    if [[ -n "$kernel_full" ]]; then
      local kernel_name="$os_type"
      [[ -z "$kernel_name" ]] && kernel_name="Unknown"
      kernel_long=", $kernel_name-$kernel_full"
      local kernel_short_ver=$(echo "$kernel_full" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
      if [[ -n "$kernel_short_ver" ]]; then
        kernel_short=", $kernel_name-$kernel_short_ver"
      else
        kernel_short="$kernel_long"
      fi
    fi
  fi

  # Save to cache
  local result="${os_long}|${os_short}|${kernel_long}|${kernel_short}"
  echo "$current_time" > "$_SYSINFO_CACHE_FILE"
  echo "$result" >> "$_SYSINFO_CACHE_FILE"

  echo "$result"
}

# Smart path cache (in-memory per-prompt)
_SMART_PATH_CACHE=""
_SMART_PATH_CACHE_KEY=""

# Git root cache (file-based, 5 min TTL)
_GIT_ROOT_CACHE_FILE="${TMPDIR:-/tmp}/.git_root_cache_${USER}"
_GIT_ROOT_CACHE_TTL=300  # 5 minutes

# Cache helpers (literal prefix match to avoid regex/glob key issues)
# Optimized: use zsh native file reading instead of while-read loop
function _cache_get_line_by_prefix() {
  local cache_file="$1"
  local prefix="$2"
  local prefix_len=${#prefix}

  [[ ! -f "$cache_file" ]] && return

  # Read file into array (zsh native, no subprocess)
  local lines=("${(@f)$(<"$cache_file")}")
  local match=""
  local entry

  for entry in "${lines[@]}"; do
    [[ "${entry:0:$prefix_len}" == "$prefix" ]] && match="$entry"
  done

  [[ -n "$match" ]] && echo "$match"
}

function _cache_update_line_by_prefix() {
  local cache_file="$1"
  local prefix="$2"
  local new_line="$3"
  local prefix_len=${#prefix}
  local temp_file="${cache_file}.tmp.$$"

  # Build new content using zsh native operations
  local new_content=""
  if [[ -f "$cache_file" ]]; then
    local lines=("${(@f)$(<"$cache_file")}")
    local entry
    for entry in "${lines[@]}"; do
      [[ "${entry:0:$prefix_len}" != "$prefix" ]] && new_content+="${entry}"$'\n'
    done
  fi
  new_content+="${new_line}"

  # Write atomically
  print -r -- "$new_content" > "$temp_file"
  mv "$temp_file" "$cache_file" 2>/dev/null
}

# Get cached git root for current directory
function _get_cached_git_root() {
  local current_dir="$PWD"
  local current_time=${EPOCHSECONDS:-$(date +%s)}

  # Check file cache
  local prefix="${current_dir}|"
  local cached_line=$(_cache_get_line_by_prefix "$_GIT_ROOT_CACHE_FILE" "$prefix")
  if [[ -n "$cached_line" ]]; then
    local rest="${cached_line:${#prefix}}"
    local cached_root cache_time
    IFS='|' read -r cached_root cache_time <<< "$rest"

    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time < _GIT_ROOT_CACHE_TTL )); then
      echo "$cached_root"
      return
    fi
  fi

  # Compute git root
  local git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  [[ -z "$git_root" ]] && git_root="NOT_GIT"

  # Update file cache
  _cache_update_line_by_prefix "$_GIT_ROOT_CACHE_FILE" "$prefix" "${current_dir}|${git_root}|${current_time}"

  echo "$git_root"
}

# Git hierarchy cache (file-based, 5 min TTL)
_GIT_HIERARCHY_CACHE_FILE="${TMPDIR:-/tmp}/.git_hierarchy_cache_${USER}"
_GIT_HIERARCHY_CACHE_TTL=300  # 5 minutes

# Light background colors for path segments (black foreground)
# Level 0 (outermost/top repo): light cyan
# Level 1 (first submodule): light yellow
# Level 2 (second submodule): light green
# Level 3+ (deeper): light magenta
_PATH_BG_COLORS=(159 229 157 225)  # 256-color palette

# Get git repository hierarchy (handles submodules)
# Returns: repo1:repo2:repo3:...:current_subdir
# Where repo1 is outermost, repoN is innermost git root
# current_subdir is the path within the innermost repo (may be empty)
function _get_git_hierarchy() {
  local current_time=${EPOCHSECONDS:-$(date +%s)}
  local cache_key="$PWD"

  # Check cache
  local prefix="${cache_key}|"
  local cached_line=$(_cache_get_line_by_prefix "$_GIT_HIERARCHY_CACHE_FILE" "$prefix")
  if [[ -n "$cached_line" ]]; then
    local rest="${cached_line:${#prefix}}"
    local cached_result cache_time
    # Split on last |
    cache_time="${rest##*|}"
    cached_result="${rest%|*}"

    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time < _GIT_HIERARCHY_CACHE_TTL )); then
      echo "$cached_result"
      return
    fi
  fi

  # Build hierarchy from innermost to outermost
  local hierarchy=()
  local dir="$PWD"

  while true; do
    local git_root=$(cd "$dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
    [[ -z "$git_root" ]] && break

    hierarchy=("$git_root" "${hierarchy[@]}")  # prepend (outermost first)

    # Check for superproject
    local superproject=$(cd "$git_root" 2>/dev/null && git rev-parse --show-superproject-working-tree 2>/dev/null)
    [[ -z "$superproject" ]] && break

    dir="$superproject"
  done

  # Build result: repo1:repo2:...:subdir
  local result=""
  local IFS=':'
  if (( ${#hierarchy[@]} > 0 )); then
    result="${hierarchy[*]}"
    # Add current subdirectory within innermost repo
    local innermost="${hierarchy[-1]}"
    if [[ "$PWD" != "$innermost" ]]; then
      result="${result}:${PWD#$innermost/}"
    else
      result="${result}:"  # empty subdir marker
    fi
  fi

  # Cache result
  _cache_update_line_by_prefix "$_GIT_HIERARCHY_CACHE_FILE" "$prefix" "${cache_key}|${result}|${current_time}"

  echo "$result"
}

# Smart path display with git-aware coloring and submodule support
# Each git level gets a different light background color with black text
# When terminal width is limited, outermost paths are truncated first
function smart_path_display() {
  local full_path="${PWD/#$HOME/~}"
  local use_short="$1"  # "short" for narrow terminal mode
  local max_path_width="${2:-0}"  # optional max width for path

  # Check if we're in a git repo (using cached value)
  local git_root=$(_get_cached_git_root)

  if [[ "$git_root" == "NOT_GIT" ]]; then
    # Not in git repo - just show path in white
    echo "%{$fg[white]%}[${full_path}]%{$reset_color%}"
    return
  fi

  # Get full hierarchy
  local hierarchy_str=$(_get_git_hierarchy)

  if [[ -z "$hierarchy_str" ]]; then
    # Fallback to simple display
    echo "%{$fg[white]%}[${full_path}]%{$reset_color%}"
    return
  fi

  # Parse hierarchy (colon-separated: repo1:repo2:...:subdir)
  local parts=("${(@s/:/)hierarchy_str}")
  local num_parts=${#parts[@]}

  # Last part is the subdirectory within innermost repo (may be empty)
  local subdir=""
  local repos=()
  if (( num_parts > 0 )); then
    subdir="${parts[-1]}"
    repos=("${parts[@]:0:$((num_parts-1))}")
  fi

  local num_repos=${#repos[@]}

  # Build display segments: each repo shows its relative path from parent
  # Format: [repo1_rel/repo2_rel/repo3_rel/subdir]
  local segments=()
  local segment_lengths=()

  for (( i=1; i<=num_repos; i++ )); do
    local repo="${repos[$i]}"
    local display_path=""

    if (( i == 1 )); then
      # First repo: show full path (with ~ for home)
      display_path="${repo/#$HOME/~}"
    else
      # Submodule: show path relative to parent repo
      local parent="${repos[$((i-1))]}"
      display_path="${repo#$parent/}"
    fi

    segments+=("$display_path")
    segment_lengths+=(${#display_path})
  done

  # Add subdirectory as final segment (if not empty)
  if [[ -n "$subdir" ]]; then
    segments+=("$subdir")
    segment_lengths+=(${#subdir})
  fi

  local total_segments=${#segments[@]}

  # Calculate total visible length (segments + separators + brackets)
  local total_len=2  # for [ and ]
  for len in "${segment_lengths[@]}"; do
    (( total_len += len ))
  done
  (( total_len += total_segments - 1 ))  # for / separators

  # Determine which segments to show based on width
  # In short mode or if total is too long, truncate from outermost (left)
  local start_idx=1
  if [[ "$use_short" == "short" ]] || (( max_path_width > 0 && total_len > max_path_width )); then
    # Try to fit by removing outermost segments
    local target_width=${max_path_width:-50}
    [[ "$use_short" == "short" ]] && target_width=40

    while (( start_idx < total_segments && total_len > target_width )); do
      # Remove segment and its separator
      (( total_len -= segment_lengths[$start_idx] + 1 ))
      (( start_idx++ ))
    done
  fi

  # Build the colored path string
  local result="["
  local sep=""
  local color_idx=0

  # If we truncated, add indicator
  if (( start_idx > 1 )); then
    result="${result}%{$FG[240]%}$(_e truncated)%{$reset_color%}/"
  fi

  for (( i=start_idx; i<=total_segments; i++ )); do
    local seg="${segments[$i]}"

    # Determine color based on segment type
    if (( i <= num_repos )); then
      # This is a git repo root - use background color
      local level=$((i - start_idx))
      (( level >= ${#_PATH_BG_COLORS[@]} )) && level=$(( ${#_PATH_BG_COLORS[@]} - 1 ))
      local bg_num="${_PATH_BG_COLORS[$((level+1))]}"
      # Use ANSI escape: 48;5;N for 256-color background, 38;5;16 for black foreground
      result="${result}${sep}%{\e[48;5;${bg_num}m\e[38;5;16m%}${seg}%{$reset_color%}"
    else
      # This is subdirectory within innermost repo - no background
      result="${result}${sep}%{$fg[white]%}${seg}%{$reset_color%}"
    fi

    sep="/"
  done

  result="${result}]"
  echo "$result"
}

# Extended git status: ahead/behind remote + stash count
# Format: ↑N↓M⚑K where N=ahead, M=behind, K=stash count
# Cached to file with 5 min TTL to avoid slow git operations on every prompt
function git_extended_status() {
  # Check if we're in a git repo (using cached value)
  local git_root=$(_get_cached_git_root)
  if [[ "$git_root" == "NOT_GIT" ]]; then
    return
  fi

  local cache_key="${git_root}"
  local current_time=${EPOCHSECONDS:-$(date +%s)}

  # Check file cache
  local prefix="${cache_key}|"
  local cached_line=$(_cache_get_line_by_prefix "$_GIT_EXT_CACHE_FILE" "$prefix")
  if [[ -n "$cached_line" ]]; then
    local rest="${cached_line:${#prefix}}"
    local cached_result cache_time
    IFS='|' read -r cached_result cache_time <<< "$rest"

    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time < _GIT_EXT_CACHE_TTL )); then
      echo "$cached_result"
      return
    fi
  fi

  local result=""

  # Get ahead/behind counts relative to upstream
  local upstream=$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null)
  if [[ -n "$upstream" ]]; then
    local counts=$(git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
    if [[ -n "$counts" ]]; then
      local ahead behind
      IFS=$'\t ' read -r ahead behind <<< "$counts"

      # Show ahead indicator
      if [[ "$ahead" -gt 0 ]]; then
        result="${result}%{$fg[green]%}$(_e ahead)${ahead}%{$reset_color%}"
      fi
      # Show behind indicator
      if [[ "$behind" -gt 0 ]]; then
        result="${result}%{$fg[red]%}$(_e behind)${behind}%{$reset_color%}"
      fi
    fi
  fi

  # Get stash count
  local stash_count=0
  local _stash_line=""
  while IFS= read -r _stash_line; do
    (( stash_count++ ))
  done < <(git stash list 2>/dev/null)
  if [[ "$stash_count" -gt 0 ]]; then
    result="${result}%{$fg[yellow]%}$(_e stash)${stash_count}%{$reset_color%}"
  fi

  # Update file cache (filter out old entry, add new)
  _cache_update_line_by_prefix "$_GIT_EXT_CACHE_FILE" "$prefix" "${cache_key}|${result}|${current_time}"

  echo "$result"
}

# Per-prompt cached wrappers for git/PR segments
# NOTE: oh-my-zsh async git may not work reliably, so we call the worker function directly
function _git_prompt_info_cached() {
  local git_root=$(_get_cached_git_root)
  if [[ "$git_root" == "NOT_GIT" ]]; then
    return
  fi

  # Call oh-my-zsh's actual git prompt worker directly (bypasses broken async)
  _omz_git_prompt_info 2>/dev/null
}

function _git_extended_status_cached() {
  local current_id="$_PROMPT_RENDER_ID"
  if [[ "$_PROMPT_GIT_EXT_CACHE_ID" == "$current_id" ]]; then
    echo "$_PROMPT_GIT_EXT_CACHE"
    return
  fi

  local result=$(git_extended_status 2>/dev/null)
  _PROMPT_GIT_EXT_CACHE="$result"
  _PROMPT_GIT_EXT_CACHE_ID="$current_id"
  echo "$result"
}

function _gh_pr_status_cached() {
  local current_id="$_PROMPT_RENDER_ID"
  if [[ "$_PROMPT_GH_PR_CACHE_ID" == "$current_id" ]]; then
    echo "$_PROMPT_GH_PR_CACHE"
    return
  fi

  local result=$(gh_pr_status 2>/dev/null)
  _PROMPT_GH_PR_CACHE="$result"
  _PROMPT_GH_PR_CACHE_ID="$current_id"
  echo "$result"
}

# Function to build complete prompt info (host badge + system info + AI tools)
# Adaptive system: LONG mode shows all on left, SHORT/MIN move system/AI to RPROMPT
# Returns: "host_badge<SEP>system_info<SEP>ai_part<SEP>mode<SEP>path_mode" separated by <SEP>
# Note: Using ::: as delimiter to avoid conflicts with | used in AI tools plaintext mode
# mode: "long", "short", or "min" - determines RPROMPT usage
# path_mode: "full" or "short" - determines smart_path_display mode
# Cached per-prompt to avoid duplicate computation
function prompt_dynamic_info() {
  # Cache key: COLUMNS + PWD + last command exit status
  # This ensures cache is invalidated when terminal resizes or directory changes
  local cache_key="${COLUMNS}:${PWD}:$?"

  if [[ "$_PROMPT_CACHE_KEY" == "$cache_key" && -n "$_PROMPT_CACHE" ]]; then
    echo "$_PROMPT_CACHE"
    return
  fi

  # Get cached system info (avoids subprocess calls on every prompt)
  # Use zsh parameter expansion instead of cut to avoid subprocesses
  local sysinfo=$(_get_cached_sysinfo)
  local os_long="${sysinfo%%|*}"
  local _rest="${sysinfo#*|}"
  local os_short="${_rest%%|*}"
  _rest="${_rest#*|}"
  local kernel_long="${_rest%%|*}"
  local kernel_short="${_rest#*|}"

  # Determine container type and badge (emoji/text icons)
  local container_icon
  local badge_color
  if test -f /run/.containerenv; then
    container_icon="$(_e container)"
    badge_color="%{$fg[magenta]%}"
  else
    container_icon="$(_e host)"
    badge_color="%{$fg[yellow]%}"
  fi

  # Calculate prompt lengths for all tiers
  local git_info=$(_git_prompt_info_cached)
  local git_ext=$(_git_extended_status_cached)
  local ai_info=$(ai_tools_status)
  local pr_info=$(_gh_pr_status_cached)
  local git_len=$(_prompt_visible_len "$git_info")
  local git_ext_len=$(_prompt_visible_len "$git_ext")
  local ai_len=$(_prompt_visible_len "$ai_info")
  local pr_len=$(_prompt_visible_len "$pr_info")

  # Core components (always present, with new additions)
  local user_host_len=$((${#USER} + 1 + ${#HOST}))  # user@host
  local time_len=10                                  # [HH:MM:SS] 24-hour format
  local path_len=${#PWD}                             # current directory
  local fixed_len=12                                 # spaces, [], arrows, exit/ssh/jobs indicators

  # Host/Container badge length: emoji + space (emoji counts as ~2 chars visually)
  local badge_len=3  # emoji (2) + space (1)

  # MIN: user@host [time] [path] [git+ext] [pr]
  local min_len=$((user_host_len + time_len + path_len + git_len + git_ext_len + pr_len + fixed_len))

  # SHORT: min + [Host/Container] + [os-short, kernel-short]
  local short_version="${os_short}${kernel_short}"
  local short_sysinfo_len=$((${#short_version} + 3))  # +3 for [], space
  local short_len=$((min_len + badge_len + short_sysinfo_len))

  # SHORT+AI: short + AI tools (+ 1 for space before AI)
  local ai_space=0
  [[ -n "$ai_info" ]] && ai_space=1
  local short_ai_len=$((short_len + ai_len + ai_space))

  # LONG: min + badge + long system info + AI tools
  local long_version="${os_long}${kernel_long}"
  local long_sysinfo_len=$((${#long_version} + 3))  # +3 for [], space
  local long_len=$((min_len + badge_len + long_sysinfo_len + ai_len + ai_space))

  # Decide which tier to use based on COLUMNS
  # LONG: everything on left prompt
  # SHORT/MIN: system info + AI tools go to RPROMPT
  local host_badge=""
  local system_info=""
  local ai_output=""
  local mode=""
  local path_mode="full"

  if (( long_len <= COLUMNS )); then
    # LONG mode: badge + full system info + AI tools all on left
    mode="long"
    path_mode="full"
    host_badge=" ${badge_color}${container_icon}%{$reset_color%}"
    system_info=" %{$fg[cyan]%}[${long_version}]%{$reset_color%}"
    [[ -n "$ai_info" ]] && ai_output=" $ai_info" || ai_output=""
  elif (( short_ai_len <= COLUMNS )); then
    # SHORT+AI mode: badge on left, system info + AI to RPROMPT
    mode="short"
    path_mode="full"
    host_badge=" ${badge_color}${container_icon}%{$reset_color%}"
    system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
    [[ -n "$ai_info" ]] && ai_output=" $ai_info" || ai_output=""
  elif (( short_len <= COLUMNS )); then
    # SHORT mode: badge on left, system info + AI to RPROMPT
    mode="short"
    path_mode="full"
    host_badge=" ${badge_color}${container_icon}%{$reset_color%}"
    system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
    [[ -n "$ai_info" ]] && ai_output=" $ai_info" || ai_output=""
  else
    # MIN mode: badge on left (if fits), system info + AI to RPROMPT, use short path
    mode="min"
    path_mode="short"
    host_badge=" ${badge_color}${container_icon}%{$reset_color%}"
    system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
    [[ -n "$ai_info" ]] && ai_output=" $ai_info" || ai_output=""
  fi

  # Store in cache and return (using ::: as delimiter to avoid | conflicts)
  local result="${host_badge}:::${system_info}:::${ai_output}:::${mode}:::${path_mode}"
  _PROMPT_CACHE="$result"
  _PROMPT_CACHE_KEY="$cache_key"
  echo "$result"
}

# Extract host/container badge from prompt_dynamic_info
function host_container_badge() {
  local info=$(prompt_dynamic_info)
  echo "${info%%:::*}"  # First part before first :::
}

# Extract system info from prompt_dynamic_info
function system_info_status() {
  local info=$(prompt_dynamic_info)
  local rest="${info#*:::}"  # Remove first part
  echo "${rest%%:::*}"  # Second part before second :::
}

# Extract AI status from prompt_dynamic_info
function ai_tools_status_conditional() {
  local info=$(prompt_dynamic_info)
  local temp="${info#*:::}"   # Remove host_badge
  temp="${temp#*:::}"         # Remove system_info
  echo "${temp%%:::*}"        # Get ai_output before mode
}

# Get current mode (long, short, or min)
function get_prompt_mode() {
  local info=$(prompt_dynamic_info)
  local temp="${info#*:::}"   # Remove host_badge
  temp="${temp#*:::}"         # Remove system_info
  temp="${temp#*:::}"         # Remove ai_output
  echo "${temp%%:::*}"        # Get mode
}

# Get path mode (full or short)
function get_path_mode() {
  local info=$(prompt_dynamic_info)
  echo "${info##*:::}"        # Last part after last :::
}

# Conditional system info for left prompt (only in LONG mode)
function system_info_left() {
  local mode=$(get_prompt_mode)
  if [[ "$mode" == "long" ]]; then
    system_info_status
  fi
}

# Conditional AI tools for left prompt (only in LONG mode)
function ai_tools_left() {
  local mode=$(get_prompt_mode)
  if [[ "$mode" == "long" ]]; then
    ai_tools_status_conditional
  fi
}

# RPROMPT content (system info + AI tools in SHORT/MIN modes)
function rprompt_content() {
  local mode=$(get_prompt_mode)
  if [[ "$mode" != "long" ]]; then
    local sys_info=$(system_info_status)
    local ai_info=$(ai_tools_status_conditional)
    echo "${sys_info}${ai_info}"
  fi
}

# Smart path wrapper that respects mode
function smart_path_conditional() {
  local path_mode=$(get_path_mode)
  smart_path_display "$path_mode"
}

# AI Coding Tools version status for prompt
# Uses cache to avoid network requests on every prompt
# Shared across all terminals for better efficiency
_AI_CACHE_TTL=3600  # Cache TTL in seconds (1 hour)
_CLAUDE_CACHE_FILE="${TMPDIR:-/tmp}/.claude_version_cache_${USER}"
_CODEX_CACHE_FILE="${TMPDIR:-/tmp}/.codex_version_cache_${USER}"
_GEMINI_CACHE_FILE="${TMPDIR:-/tmp}/.gemini_version_cache_${USER}"

# GitHub PR cache
_GH_PR_CACHE_FILE="${TMPDIR:-/tmp}/.gh_pr_cache_${USER}"
_GH_PR_CACHE_TTL=300  # 5 minutes

# Git remote/branch cache (in-memory per-prompt, avoids repeated git calls)
_GIT_REMOTE_BRANCH_CACHE=""
_GIT_REMOTE_BRANCH_CACHE_ID=-1

# Get cached git remote URL and branch (per-prompt cache)
# Returns: remote_url|branch or empty if not in git repo
function _get_cached_git_remote_branch() {
  local current_id="$_PROMPT_RENDER_ID"
  if [[ "$_GIT_REMOTE_BRANCH_CACHE_ID" == "$current_id" ]]; then
    echo "$_GIT_REMOTE_BRANCH_CACHE"
    return
  fi

  local git_root=$(_get_cached_git_root)
  if [[ "$git_root" == "NOT_GIT" ]]; then
    _GIT_REMOTE_BRANCH_CACHE=""
    _GIT_REMOTE_BRANCH_CACHE_ID="$current_id"
    return
  fi

  local remote_url=$(git config --get remote.origin.url 2>/dev/null)
  local branch=$(git symbolic-ref --short HEAD 2>/dev/null)

  if [[ -n "$remote_url" && -n "$branch" ]]; then
    _GIT_REMOTE_BRANCH_CACHE="${remote_url}|${branch}"
  else
    _GIT_REMOTE_BRANCH_CACHE=""
  fi
  _GIT_REMOTE_BRANCH_CACHE_ID="$current_id"
  echo "$_GIT_REMOTE_BRANCH_CACHE"
}

# Helper: compare semantic versions, returns 0 if $1 > $2
_prompt_version_gt() {
  test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

# Helper: determine update type (major, minor, or patch)
# Returns: "major", "minor", "patch", or "" if no update
_version_update_type() {
  local installed="$1"
  local remote="$2"

  [[ -z "$installed" || -z "$remote" ]] && return

  # Parse version components
  local inst_major inst_minor inst_patch
  local rem_major rem_minor rem_patch

  inst_major=${installed%%.*}
  inst_minor=${installed#*.}
  inst_minor=${inst_minor%%.*}
  inst_patch=${installed##*.}

  rem_major=${remote%%.*}
  rem_minor=${remote#*.}
  rem_minor=${rem_minor%%.*}
  rem_patch=${remote##*.}

  if (( rem_major > inst_major )); then
    echo "major"
  elif (( rem_minor > inst_minor )); then
    echo "minor"
  elif (( rem_patch > inst_patch )); then
    echo "patch"
  fi
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

    # Get remote latest version from NPM registry
    local npm_url="https://registry.npmjs.org/@anthropic-ai/claude-code/latest"
    remote_version=$(curl -s --max-time 5 "$npm_url" | grep -o '"version":"[^"]*"' | sed 's/"version":"//; s/"//')

    # Only update cache if we got the local version
    if [[ -n "$installed_version" ]]; then
      local current_time=${EPOCHSECONDS:-$(date +%s)}
      echo "$installed_version $remote_version $current_time" > "$cache_file"
    fi
  ) &>/dev/null &
}

# Update the Codex version cache (runs in background)
# Cache format: <local_version> <remote_version> <timestamp>
_codex_update_cache() {
  (
    local cache_file="$1"
    local installed_version
    local remote_version

    # Get local installed version
    installed_version=$(codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    # Get remote latest version from NPM registry
    local npm_url="https://registry.npmjs.org/@openai/codex/latest"
    remote_version=$(curl -s --max-time 5 "$npm_url" | grep -o '"version":"[^"]*"' | sed 's/"version":"//; s/"//')

    # Only update cache if we got the local version
    if [[ -n "$installed_version" ]]; then
      local current_time=${EPOCHSECONDS:-$(date +%s)}
      echo "$installed_version $remote_version $current_time" > "$cache_file"
    fi
  ) &>/dev/null &
}

# Update the Gemini CLI version cache (runs in background)
# Cache format: <local_version> <remote_version> <timestamp>
_gemini_update_cache() {
  (
    local cache_file="$1"
    local installed_version
    local remote_version

    # Get local installed version
    installed_version=$(gemini --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    # Get remote latest version from NPM registry
    local npm_url="https://registry.npmjs.org/@google/gemini-cli/latest"
    remote_version=$(curl -s --max-time 5 "$npm_url" | grep -o '"version":"[^"]*"' | sed 's/"version":"//; s/"//')

    # Only update cache if we got the local version
    if [[ -n "$installed_version" ]]; then
      local current_time=${EPOCHSECONDS:-$(date +%s)}
      echo "$installed_version $remote_version $current_time" > "$cache_file"
    fi
  ) &>/dev/null &
}

# Get Claude Code status for prompt
# Uses 🤖 emoji with semantic version coloring for updates
function claude_code_status() {
  # Check if claude command exists
  if ! command -v claude &>/dev/null; then
    return
  fi

  local installed_version=""
  local remote_version=""
  local cache_time=0
  local current_time=${EPOCHSECONDS:-$(date +%s)}

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

  # Check update type and determine indicator color
  local update_type=$(_version_update_type "$installed_version" "$remote_version")
  local update_indicator=""

  # Show red star for any available update
  [[ -n "$update_type" ]] && update_indicator="%{$fg[red]%}*"

  # Output: 🤖version or 🤖version* (brackets added by ai_tools_status)
  # Coral color: 173 (256-color) - dusty salmon/terracotta matching Claude Code branding
  local icon="$(_e claude)"
  if [[ -n "$update_indicator" ]]; then
    echo "%{$FG[173]%}${icon}${installed_version}${update_indicator}%{$reset_color%}"
  else
    echo "%{$FG[173]%}${icon}${installed_version}%{$reset_color%}"
  fi
}

# Get Codex status for prompt
# Uses 🧠 emoji with semantic version coloring for updates
function codex_status() {
  # Check if codex command exists
  if ! command -v codex &>/dev/null; then
    return
  fi

  local installed_version=""
  local remote_version=""
  local cache_time=0
  local current_time=${EPOCHSECONDS:-$(date +%s)}

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

  # Check update type and determine indicator color
  local update_type=$(_version_update_type "$installed_version" "$remote_version")
  local update_indicator=""

  # Show red star for any available update
  [[ -n "$update_type" ]] && update_indicator="%{$fg[red]%}*"

  # Output: 🧠version or 🧠version* (brackets added by ai_tools_status)
  # Light gray color: 250
  local icon="$(_e codex)"
  if [[ -n "$update_indicator" ]]; then
    echo "%{$FG[250]%}${icon}${installed_version}${update_indicator}%{$reset_color%}"
  else
    echo "%{$FG[250]%}${icon}${installed_version}%{$reset_color%}"
  fi
}

# Get Gemini CLI status for prompt
# Uses 🔷 emoji with semantic version coloring for updates
function gemini_status() {
  # Check if gemini command exists
  if ! command -v gemini &>/dev/null; then
    return
  fi

  local installed_version=""
  local remote_version=""
  local cache_time=0
  local current_time=${EPOCHSECONDS:-$(date +%s)}

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

  # Check update type and determine indicator color
  local update_type=$(_version_update_type "$installed_version" "$remote_version")
  local update_indicator=""

  # Show red star for any available update
  [[ -n "$update_type" ]] && update_indicator="%{$fg[red]%}*"

  # Output: 🔷version or 🔷version* (brackets added by ai_tools_status)
  # Purple color: 141 - Google purple-ish
  local icon="$(_e gemini)"
  if [[ -n "$update_indicator" ]]; then
    echo "%{$FG[141]%}${icon}${installed_version}${update_indicator}%{$reset_color%}"
  else
    echo "%{$FG[141]%}${icon}${installed_version}%{$reset_color%}"
  fi
}

# Update GitHub PR cache (runs in background)
# Cache format: remote_url|branch_name|pr_number|ci_status|timestamp
# ci_status: "pass", "fail", "pending", or "none"
_gh_pr_update_cache() {
  (
    local cache_file="$1"
    local remote_url="$2"
    local branch="$3"

    local pr_number
    local ci_status="none"

    pr_number=$(gh pr view --json number --jq '.number' 2>/dev/null)

    if [[ -z "$pr_number" ]]; then
      pr_number="-1"
    else
      # Get CI status using gh pr checks
      local checks_output=$(gh pr checks 2>/dev/null)
      if [[ -n "$checks_output" ]]; then
        # Check for failures first
        if echo "$checks_output" | grep -q "fail\|X"; then
          ci_status="fail"
        # Then check for pending
        elif echo "$checks_output" | grep -q "pending\|-"; then
          ci_status="pending"
        # All passed
        elif echo "$checks_output" | grep -q "pass\|✓"; then
          ci_status="pass"
        fi
      fi
    fi

    local current_time=${EPOCHSECONDS:-$(date +%s)}
    local cache_key="${remote_url}|${branch}"
    local prefix="${cache_key}|"
    _cache_update_line_by_prefix "$cache_file" "$prefix" "${cache_key}|${pr_number}|${ci_status}|${current_time}"
  ) &>/dev/null &
}

# Get GitHub PR status for prompt
# Displays  icon with PR number and CI status indicator
function gh_pr_status() {
  # Check if gh command exists
  if ! command -v gh &>/dev/null; then
    return
  fi

  # Get cached git remote/branch (avoids git calls on every prompt)
  local remote_branch=$(_get_cached_git_remote_branch)
  if [[ -z "$remote_branch" ]]; then
    return
  fi

  local remote_url="${remote_branch%%|*}"
  local branch="${remote_branch#*|}"

  local cache_key="${remote_url}|${branch}"
  local pr_number=""
  local ci_status="none"
  local cache_time=0
  local current_time=${EPOCHSECONDS:-$(date +%s)}

  # Check cache (new format: key|pr_number|ci_status|timestamp)
  local prefix="${cache_key}|"
  local cached_line=$(_cache_get_line_by_prefix "$_GH_PR_CACHE_FILE" "$prefix")
  if [[ -n "$cached_line" ]]; then
    local rest="${cached_line:${#prefix}}"
    IFS='|' read -r pr_number ci_status cache_time <<< "$rest"

    # Validate cache_time
    if [[ ! "$cache_time" =~ ^[0-9]+$ ]]; then
      cache_time=0
    fi
  fi

  # Check if cache expired or missing
  if (( current_time - cache_time > _GH_PR_CACHE_TTL )); then
    # Trigger background refresh
    _gh_pr_update_cache "$_GH_PR_CACHE_FILE" "$remote_url" "$branch"
  fi

  # Display PR number with CI status if available and valid
  if [[ -n "$pr_number" && "$pr_number" != "-1" ]]; then
    # Determine CI indicator
    local ci_indicator=""
    case "$ci_status" in
      pass)    ci_indicator="%{$fg[green]%}$(_e pass)" ;;
      fail)    ci_indicator="%{$fg[red]%}$(_e fail)" ;;
      pending) ci_indicator="%{$fg[yellow]%}$(_e pending)" ;;
    esac

    # Pink color: FG[213], using  icon
    if [[ -n "$ci_indicator" ]]; then
      echo "%{$FG[213]%}#${pr_number}${ci_indicator}%{$reset_color%}"
    else
      echo "%{$FG[213]%}#${pr_number}%{$reset_color%}"
    fi
  fi
}

# Combined AI tools status: [tool1tool2tool3] format (emoji) or [tool1|tool2|tool3] (plaintext)
function ai_tools_status() {
  local ai_status=""
  local claude_st=$(claude_code_status)
  local codex_st=$(codex_status)
  local gemini_st=$(gemini_status)

  # Determine separator based on mode (| for plaintext, none for emoji)
  local sep=""
  (( ! _PROMPT_EMOJI_MODE )) && sep="|"

  # Concatenate all tools with separator in plaintext mode
  if [[ -n "$claude_st" ]]; then
    ai_status="$claude_st"
  fi
  if [[ -n "$codex_st" ]]; then
    [[ -n "$ai_status" ]] && ai_status="$ai_status$sep"
    ai_status="$ai_status$codex_st"
  fi
  if [[ -n "$gemini_st" ]]; then
    [[ -n "$ai_status" ]] && ai_status="$ai_status$sep"
    ai_status="$ai_status$gemini_st"
  fi

  # Wrap in brackets if any tools are present
  if [[ -n "$ai_status" ]]; then
    echo "%{$fg[white]%}[${ai_status}%{$fg[white]%}]%{$reset_color%}"
  fi
}

# Enhanced PROMPT with all new features:
# - Exit status indicator (✓/OK or ✗N/ERRN)
# - SSH indicator (⚡/SSH)
# - Container/Host badge (🖥️/H or 📦/C)
# - Time with dynamic color
# - Smart path with git-aware coloring and submodule support
# - Git status with extended info (ahead/behind/stash)
# - PR status with CI indicator
# - Background jobs counter (⚙N/JN)
# - Adaptive RPROMPT for system info and AI tools
# - Toggle emoji/plaintext with 'e', help with 'h', refresh with 'u'
#
# Order: [exit][ssh]user@host [container] [time] [path] [git+ext][PR+CI] [sysinfo] [AI] [jobs]
# Second line: -> %#
# Note: user@host uses brown color (FG[136]) to distinguish from exit status
PROMPT=$'$(exit_status_indicator)$(ssh_indicator)%{$FG[136]%}%n@%m%{$reset_color%}$(host_container_badge) %B$(time_with_color)%b $(smart_path_conditional) $(_git_prompt_info_cached)$(_git_extended_status_cached)$(_gh_pr_status_cached)$(system_info_left)$(ai_tools_left)%(1j. %{$fg[yellow]%}$(jobs_indicator)%j%{$reset_color%}.)
%{$fg[blue]%}->%{$fg_bold[blue]%} %#%{$reset_color%} '

# Right prompt: system info and AI tools in SHORT/MIN modes
# Auto-hides when command line is long
RPROMPT='$(rprompt_content)'

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg[green]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY=" %{$fg[red]%}*%{$fg[green]%}"
ZSH_THEME_GIT_PROMPT_CLEAN=""
