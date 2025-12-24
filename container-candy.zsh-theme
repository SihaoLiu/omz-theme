# ============================================================================
# COLOR CONSTANTS - Centralized color definitions for easy customization
# ============================================================================
# 256-color palette (FG[N] format)
typeset -g _CLR_TIME_MORNING=214      # Warm yellow (6am-12pm)
typeset -g _CLR_TIME_AFTERNOON=255    # Bright white (12pm-6pm)
typeset -g _CLR_TIME_EVENING=208      # Soft orange (6pm-10pm)
typeset -g _CLR_TIME_NIGHT=111        # Dim blue (10pm-6am)
typeset -g _CLR_TRUNCATED=240         # Gray for truncated path indicator
typeset -g _CLR_CLAUDE=173            # Coral - Claude Code branding
typeset -g _CLR_CODEX=250             # Light gray - Codex
typeset -g _CLR_GEMINI=141            # Purple - Google Gemini
typeset -g _CLR_PR=213                # Pink - GitHub PR
typeset -g _CLR_USER_HOST=136         # Brown - user@host

# Standard color names (fg[name] format) - for reference/documentation
# cyan    - SSH indicator, system info
# green   - exit ok, ahead, CI pass, git branch
# red     - exit fail, behind, CI fail, update indicator
# yellow  - stash, jobs, CI pending, container badge host
# magenta - container badge
# white   - path segments, AI brackets
# blue    - prompt arrow

# Background colors for git path segments (256-color palette)
# Level 0 (outermost/top repo): light cyan
# Level 1 (first submodule): light yellow
# Level 2 (second submodule): light green
# Level 3+ (deeper): light magenta
typeset -ga _PATH_BG_COLORS=(159 229 157 225)

# Internal separator for git hierarchy cache (avoid collisions with ':' in paths)
# Uses ASCII Unit Separator (0x1f) which won't appear in filesystem paths.
# IMPORTANT: When splitting strings with this separator in zsh, use:
#   ${(@ps.$sep.)string}   -- CORRECT (p flag + s.$var. syntax)
#   ${(@s:$sep:)string}    -- WRONG (s:X: requires literal X, not variable)
typeset -g _GIT_HIERARCHY_SEP=$'\x1f'

# GitHub username badge background color (white background for normal, red for mismatch)
typeset -g _CLR_GH_USER_BG=255        # White background
typeset -g _CLR_GH_USER_FG=16         # Black foreground
typeset -g _CLR_GH_USER_MISMATCH=196  # Bright red for username mismatch

# ============================================================================
# TIMING CONSTANTS - Centralized timeout and cache TTL settings
# ============================================================================
# All timing values in seconds for easy adjustment

# Network timeout (prevents hanging on slow/unreachable services)
typeset -g _NETWORK_TIMEOUT=5         # 5 seconds

# High frequency cache (fast-changing data, checked frequently)
typeset -g _CACHE_TTL_HIGH=30         # 30 seconds - PR status, CI checks

# Medium frequency cache (moderately changing data)
typeset -g _CACHE_TTL_MEDIUM=300      # 5 minutes - git status, GitHub username

# Low frequency cache (rarely changing data)
typeset -g _CACHE_TTL_LOW=3600        # 1 hour - system info, AI versions, auth status

# ============================================================================
# CACHE DIRECTORY SETUP - Secure cache location in user's home directory
# ============================================================================
# Cache files are stored in $HOME/.cache/zsh-prompt/ with strict permissions
# to prevent information leakage on shared systems.
typeset -g _CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh-prompt"

# Initialize cache directory with secure permissions (700)
if [[ ! -d "$_CACHE_DIR" ]]; then
  mkdir -p "$_CACHE_DIR" 2>/dev/null
fi
chmod 700 "$_CACHE_DIR" 2>/dev/null

# ============================================================================
# TIMEOUT WRAPPER - Universal timeout command abstraction
# ============================================================================
# Provides consistent timeout behavior across Linux (timeout), macOS (gtimeout).
# SECURITY: If no timeout command is available, network-dependent features are
# disabled to prevent background process accumulation.
#
# Usage: _run_with_timeout <timeout_seconds> <command> [args...]
# Returns: command output on success, empty string on timeout or error
# Exit code: mirrors the underlying command's exit code

# Check for timeout command availability
typeset -g _HAS_TIMEOUT_CMD=0
if command -v timeout &>/dev/null || command -v gtimeout &>/dev/null; then
  _HAS_TIMEOUT_CMD=1
fi

function _run_with_timeout() {
  local timeout_sec="$1"
  shift
  if command -v timeout &>/dev/null; then
    timeout "$timeout_sec" "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$timeout_sec" "$@"
  else
    # No timeout available - caller should have checked _HAS_TIMEOUT_CMD
    # Return failure to signal the command cannot be safely executed
    return 124  # Same exit code as timeout uses
  fi
}

# ============================================================================
# MEMORY CACHE - Associative arrays for fast in-memory caching
# ============================================================================
# These reduce file I/O by caching values in memory with timestamps.
# Three-tier caching strategy:
#   1. Memory cache (fastest, per-shell session)
#   2. SQLite cache (fast, shared across shells)
#   3. File cache (fallback when sqlite3 unavailable)
#
# Cache format conventions:
#   Memory cache: cache[key] = "value|timestamp"
#   SQLite cache: key column = "namespace:actual_key", value column = "data", timestamp column separate
#   File cache:   each line = "key|value|timestamp"
#   All timestamps are EPOCHSECONDS (Unix time in seconds)
#
# IMPORTANT: _cache_get() returns unified "value|timestamp" format from all cache types
# This allows callers to parse results consistently regardless of backend
#
typeset -gA _MEM_CACHE_GIT_ROOT       # PWD -> git_root|timestamp
typeset -gA _MEM_CACHE_GIT_HIERARCHY  # PWD -> hierarchy|timestamp
typeset -gA _MEM_CACHE_GIT_EXT        # git_root -> ext_status|timestamp
typeset -gA _MEM_CACHE_GH_PR          # remote|branch -> pr_num|ci_status|timestamp

# Memory cache size limits (prevents unbounded growth)
typeset -g _MEM_CACHE_MAX_ENTRIES=100
typeset -g _MEM_CACHE_CLEANUP_THRESHOLD=120  # Cleanup when exceeding this

# Cleanup memory cache when it grows too large
# Removes oldest entries (by timestamp) to stay under limit
function _mem_cache_cleanup() {
  local cache_name="$1"
  local -A cache_ref
  local max_entries=${_MEM_CACHE_MAX_ENTRIES:-100}
  local threshold=${_MEM_CACHE_CLEANUP_THRESHOLD:-120}

  # Copy the appropriate cache to local variable for iteration
  case "$cache_name" in
    git_root)     cache_ref=("${(@kv)_MEM_CACHE_GIT_ROOT}") ;;
    git_hierarchy) cache_ref=("${(@kv)_MEM_CACHE_GIT_HIERARCHY}") ;;
    git_ext)      cache_ref=("${(@kv)_MEM_CACHE_GIT_EXT}") ;;
    gh_pr)        cache_ref=("${(@kv)_MEM_CACHE_GH_PR}") ;;
    *) return ;;
  esac

  local count=${#cache_ref}
  (( count <= threshold )) && return

  # Build array of "timestamp|key" for sorting
  local -a entries
  local key val timestamp
  # Correct zsh iteration: iterate over keys, look up values
  for key in "${(@k)cache_ref}"; do
    val="${cache_ref[$key]}"
    timestamp="${val##*|}"
    [[ "$timestamp" =~ ^[0-9]+$ ]] || timestamp=0
    entries+=("${timestamp}|${key}")
  done

  # Sort by timestamp (oldest first) and remove excess entries
  local -a sorted
  sorted=("${(@on)entries}")  # numeric sort ascending

  local to_remove=$(( count - max_entries ))
  local i entry remove_key
  for (( i=1; i<=to_remove; i++ )); do
    entry="${sorted[$i]}"
    remove_key="${entry#*|}"
    case "$cache_name" in
      git_root)     unset "_MEM_CACHE_GIT_ROOT[$remove_key]" ;;
      git_hierarchy) unset "_MEM_CACHE_GIT_HIERARCHY[$remove_key]" ;;
      git_ext)      unset "_MEM_CACHE_GIT_EXT[$remove_key]" ;;
      gh_pr)        unset "_MEM_CACHE_GH_PR[$remove_key]" ;;
    esac
  done
}

# ============================================================================
# SQLITE CACHE SYSTEM - High-performance key-value storage with file fallback
# ============================================================================
# Uses SQLite for efficient caching when available, falls back to file-based
# cache on systems without sqlite3 command.

# SQLite database file location (in secure cache directory)
typeset -g _CACHE_DB_FILE="${_CACHE_DIR}/prompt_cache.db"
typeset -g _CACHE_USE_SQLITE=0  # Will be set to 1 if sqlite3 is available

# Check if sqlite3 is available and initialize database
if command -v sqlite3 &>/dev/null; then
  # Initialize database schema (only creates if not exists)
  # Enable WAL mode for better concurrent write handling across multiple shells
  if sqlite3 "$_CACHE_DB_FILE" "
      PRAGMA journal_mode=WAL;
      CREATE TABLE IF NOT EXISTS cache (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_cache_timestamp ON cache(timestamp);
    " &>/dev/null; then
    _CACHE_USE_SQLITE=1
  else
    _CACHE_USE_SQLITE=0
  fi
fi

# Check if flock is available for file-based cache locking (fallback mode)
typeset -g _CACHE_HAS_FLOCK=0
if command -v flock &>/dev/null; then
  _CACHE_HAS_FLOCK=1
fi

# Generic cache get function - works with both SQLite and file cache
# Args: $1=cache_name (e.g., "git_root"), $2=key
# Returns: value|timestamp if found, empty otherwise
# Note: TTL check is done by caller for flexibility
# IMPORTANT: Unified return format is "value|timestamp" for both SQLite and file cache
function _cache_get() {
  local cache_name="$1"
  local key="$2"

  if (( _CACHE_USE_SQLITE )); then
    # SQLite query - returns "value|timestamp" format
    sqlite3 "$_CACHE_DB_FILE" "
      SELECT value || '|' || timestamp FROM cache
      WHERE key = '${cache_name}:${key//\'/\'\'}'
      LIMIT 1;
    " 2>/dev/null
  else
    # Fallback to file cache (in secure cache directory)
    # File format is: key<SEP>value<SEP>timestamp (SEP = \x1f to avoid key containing |)
    # Return format must be: value|timestamp (consistent with SQLite path)
    local cache_file="${_CACHE_DIR}/${cache_name}_cache"
    local sep=$'\x1f'
    local prefix="${key}${sep}"
    local line=$(_cache_get_line_by_prefix "$cache_file" "$prefix")
    if [[ -n "$line" ]]; then
      # Parse: key<sep>value<sep>timestamp -> return value|timestamp
      local rest="${line#*$sep}"      # Remove key<sep>
      local value="${rest%%$sep*}"    # Get value (before second sep)
      local timestamp="${rest#*$sep}" # Get timestamp (after second sep)
      echo "${value}|${timestamp}"
    fi
  fi
}

# Async cache set function - updates memory cache immediately, writes to SQLite/file in background
# PERFORMANCE: Non-blocking write avoids SQLite sync delays in prompt rendering
# Args: $1=cache_name, $2=key, $3=value, $4=timestamp
function _cache_set_async() {
  local cache_name="$1"
  local key="$2"
  local value="$3"
  local timestamp="$4"

  # 1. Immediately update memory cache (synchronous, very fast)
  case "$cache_name" in
    git_root)     _MEM_CACHE_GIT_ROOT[$key]="${value}|${timestamp}" ;;
    git_hierarchy) _MEM_CACHE_GIT_HIERARCHY[$key]="${value}|${timestamp}" ;;
    git_ext)      _MEM_CACHE_GIT_EXT[$key]="${value}|${timestamp}" ;;
    gh_pr)        _MEM_CACHE_GH_PR[$key]="${value}|${timestamp}" ;;
  esac

  # 2. Background write to persistent cache (non-blocking)
  if (( _CACHE_USE_SQLITE )); then
    (
      local escaped_key="${key//\'/\'\'}"
      local escaped_value="${value//\'/\'\'}"
      sqlite3 "$_CACHE_DB_FILE" "
        INSERT OR REPLACE INTO cache (key, value, timestamp)
        VALUES ('${cache_name}:${escaped_key}', '${escaped_value}', ${timestamp});
      " 2>/dev/null
    ) &!
  else
    (
      local cache_file="${_CACHE_DIR}/${cache_name}_cache"
      local sep=$'\x1f'
      local prefix="${key}${sep}"
      _cache_update_line_by_prefix "$cache_file" "$prefix" "${key}${sep}${value}${sep}${timestamp}"
    ) &!
  fi
}

# ============================================================================
# CACHE CLEANUP SYSTEM - Automatic cleanup to prevent unbounded cache growth
# ============================================================================
# Cleanup strategy:
#   - SQLite: Delete entries older than max_age (default 7 days)
#   - File caches: Remove lines older than max_age
#   - Memory caches: Handled by _mem_cache_cleanup (called on threshold)
#   - Periodic: Run cleanup every 100 prompts
#   - Startup: Run cleanup on shell startup (this file load)

# Cache cleanup constants
typeset -g _CACHE_CLEANUP_INTERVAL=100      # Run cleanup every N prompts
typeset -g _CACHE_MAX_AGE=$((7 * 24 * 3600)) # 7 days in seconds
typeset -g _FILE_CACHE_MAX_LINES=500        # Max lines per file cache

# Batch cache cleanup - removes expired entries
# Args: $1=max_age_seconds (optional, defaults to _CACHE_MAX_AGE)
function _cache_cleanup() {
  local max_age="${1:-$_CACHE_MAX_AGE}"
  local current_time=${EPOCHSECONDS:-$(date +%s)}
  local cutoff=$((current_time - max_age))

  # SQLite cleanup
  if (( _CACHE_USE_SQLITE )); then
    sqlite3 "$_CACHE_DB_FILE" "
      DELETE FROM cache WHERE timestamp < ${cutoff};
    " 2>/dev/null
  fi

  # File cache cleanup (for each known cache file)
  local cache_files=(
    "$_SYSINFO_CACHE_FILE"
    "$_CLAUDE_CACHE_FILE"
    "$_CODEX_CACHE_FILE"
    "$_GEMINI_CACHE_FILE"
    "$_GH_AUTH_CACHE_FILE"
    "$_GH_USERNAME_GH_CACHE_FILE"
    "$_GH_USERNAME_SSH_CACHE_FILE"
  )

  for cache_file in "${cache_files[@]}"; do
    [[ -f "$cache_file" ]] || continue
    # These simple caches have format: value timestamp or value|timestamp
    # Check if file is older than max_age and remove if so
    local file_time=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    if [[ -n "$file_time" ]] && (( current_time - file_time > max_age )); then
      rm -f "$cache_file" 2>/dev/null
    fi
  done

  # Multi-line file cache cleanup (git_root, git_hierarchy, gh_pr, git_ext)
  _file_cache_prune "${_CACHE_DIR}/git_root_cache" "$cutoff"
  _file_cache_prune "${_CACHE_DIR}/git_hierarchy_cache" "$cutoff"
  _file_cache_prune "${_CACHE_DIR}/gh_pr_cache" "$cutoff"
  _file_cache_prune "${_CACHE_DIR}/git_ext_cache" "$cutoff"

  # Clean up stale lock files (older than 5 minutes)
  local lock_cutoff=$((current_time - 300))
  setopt localoptions null_glob
  for lock_file in "${_CACHE_DIR}"/*.lock; do
    [[ -f "$lock_file" ]] || continue
    local lock_time=$(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null)
    if [[ -n "$lock_time" ]] && (( lock_time < lock_cutoff )); then
      rm -f "$lock_file" 2>/dev/null
    fi
  done
}

# Prune a multi-line file cache - removes entries older than cutoff timestamp
# File format: key<sep>value<sep>timestamp per line
# Args: $1=cache_file, $2=cutoff_timestamp
function _file_cache_prune() {
  local cache_file="$1"
  local cutoff="$2"
  local sep=$'\x1f'

  [[ -f "$cache_file" ]] || return

  local -a lines=("${(@f)$(<"$cache_file")}")
  local -a new_lines_rev=()
  local count=0
  local max_lines=${_FILE_CACHE_MAX_LINES:-500}

  # Keep newest entries by walking from the end
  local i line timestamp
  for (( i=${#lines[@]}; i>=1; i-- )); do
    line="${lines[$i]}"
    [[ -z "$line" ]] && continue
    # Extract timestamp (last field after separator)
    timestamp="${line##*$sep}"
    [[ ! "$timestamp" =~ ^[0-9]+$ ]] && continue

    if (( timestamp >= cutoff )); then
      new_lines_rev+=("$line")
      (( count++ ))
      (( count >= max_lines )) && break
    fi
  done

  # Reverse back to chronological order
  local -a new_lines=()
  for (( i=${#new_lines_rev[@]}; i>=1; i-- )); do
    new_lines+=("${new_lines_rev[$i]}")
  done

  # Rewrite file with valid entries only
  if (( ${#new_lines[@]} < ${#lines[@]} )); then
    ( umask 077 && printf '%s\n' "${new_lines[@]}" > "$cache_file" )
  fi
}

# Periodic cleanup hook - runs in background every N prompts
typeset -g _CACHE_CLEANUP_LAST_RUN=0

function _periodic_cache_cleanup() {
  local current_id="$_PROMPT_RENDER_ID"

  # Only run every _CACHE_CLEANUP_INTERVAL prompts
  (( current_id - _CACHE_CLEANUP_LAST_RUN < _CACHE_CLEANUP_INTERVAL )) && return
  _CACHE_CLEANUP_LAST_RUN="$current_id"

  # Run cleanup in background to avoid blocking prompt
  ( _cache_cleanup ) &!
}

# Startup cleanup (runs once when theme is loaded)
# This cleans up any stale cache from previous sessions
( _cache_cleanup ) &!

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

zmodload zsh/datetime 2>/dev/null

# Emoji mode toggle (1 = emoji-rich, 0 = plaintext)
# Persisted to file so it survives shell restarts
_EMOJI_MODE_FILE="${_CACHE_DIR}/emoji_mode"

# Load emoji mode from file or default to 1 (emoji-rich)
if [[ -f "$_EMOJI_MODE_FILE" ]]; then
  _PROMPT_EMOJI_MODE=$(<"$_EMOJI_MODE_FILE")
else
  _PROMPT_EMOJI_MODE=1
fi

# Path separator mode toggle (0 = '/', 1 = ' ' space)
# Space mode allows double-click selection of path segments in terminal
# Persisted to file so it survives shell restarts
_PATH_SEP_MODE_FILE="${_CACHE_DIR}/path_sep_mode"

# Load path separator mode from file or default to 1 (space mode)
if [[ -f "$_PATH_SEP_MODE_FILE" ]]; then
  _PROMPT_PATH_SEP_MODE=$(<"$_PATH_SEP_MODE_FILE")
else
  _PROMPT_PATH_SEP_MODE=1
fi

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
}

# Toggle path separator mode (/ vs space)
# Note: Space mode is disabled when current path contains spaces (would cause ambiguity)
function _prompt_toggle_path_sep() {
  if (( _PROMPT_PATH_SEP_MODE )); then
    # Currently in space mode, switch to slash mode (always allowed)
    _PROMPT_PATH_SEP_MODE=0
    echo "0" > "$_PATH_SEP_MODE_FILE"
    echo "Slash mode: [repo/root/submodule/path/in/submodule]"
  else
    # Currently in slash mode, try to switch to space mode
    # Check if current path contains spaces
    if [[ "$PWD" == *" "* ]]; then
      echo "Cannot switch to space mode: current path contains spaces"
      echo "Path: $PWD"
      echo "Space mode would cause ambiguity with space-containing directory names."
      return 1
    fi
    _PROMPT_PATH_SEP_MODE=1
    echo "1" > "$_PATH_SEP_MODE_FILE"
    echo "Space mode: [repo/root submodule path/in/submodule]"
  fi
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
  echo "║    💻 / H     Running on host machine                            ║"
  echo "║    📦 / C     Running inside a container                         ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  GITHUB IDENTITY                                                 ║"
  echo "║    [Username]   GitHub username (white bg, black text)           ║"
  echo "║                 Detected via gh auth and ssh -T git@github.com   ║"
  echo "║    [A|B]        Mismatch warning (red) - gh and ssh differ       ║"
  echo "║                 Check your GitHub authentication config!         ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  GIT STATUS                                                      ║"
  echo "║    ↑N / +N   N commits ahead of upstream (need to push)          ║"
  echo "║    ↓N / -N   N commits behind upstream (need to pull)            ║"
  echo "║    ⚑N / SN   N stashed changes                                   ║"
  echo "║    *         Uncommitted changes in working directory            ║"
  echo "║    Example: main ↑2↓1⚑3 means branch 'main', 2 ahead,            ║"
  echo "║             1 behind, 3 stashes                                  ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  GIT SPECIAL STATES                                              ║"
  echo "║    🔀 / RB   Rebase in progress (with step/total if interactive) ║"
  echo "║    🔀 / MG   Merge in progress                                   ║"
  echo "║    🍒 / CP   Cherry-pick in progress                             ║"
  echo "║    🔍 / BI   Bisect in progress                                  ║"
  echo "║    🔌 / DT   Detached HEAD state                                 ║"
  echo "║    Example: 🔀2/5 means interactive rebase at step 2 of 5        ║"
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
  echo "║  PATH DISPLAY (in git repos)                                     ║"
  echo "║    Space mode: [repo/root submodule relative/path]               ║"
  echo "║    Slash mode: [repo/root/submodule/relative/path]               ║"
  echo "║    Space mode enables double-click to select path segments       ║"
  echo "╠══════════════════════════════════════════════════════════════════╣"
  echo "║  QUICK COMMANDS                                                  ║"
  echo "║    u         Refresh all cached prompt info                      ║"
  echo "║    e         Toggle emoji/plaintext mode                         ║"
  echo "║    p         Toggle path separator (space/slash)                 ║"
  echo "║    h         Show this help                                      ║"
  echo "║    t         Show tool availability status                       ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
}

# Tool availability status - shows which optional tools are installed
# and what features they enable
function _prompt_tool_status() {
  local GREEN=$'\e[32m'
  local RED=$'\e[31m'
  local YELLOW=$'\e[33m'
  local CYAN=$'\e[36m'
  local RESET=$'\e[0m'
  local CHECK="${GREEN}✓${RESET}"
  local CROSS="${RED}✗${RESET}"
  local WARN="${YELLOW}!${RESET}"

  # Total box width (including borders)
  local WIDTH=78
  local INNER=$((WIDTH - 2))  # Content width between ║ borders

  # Helper: print a line with auto-padding
  # Strips ANSI codes to calculate visible length, then pads to INNER width
  _tsl() {
    local content="$1"
    # Strip ANSI escape codes to get visible text
    local visible="${content//\$\'\\e\[*m\'/}"  # doesn't work well, use sed
    visible=$(printf '%s' "$content" | sed 's/\x1b\[[0-9;]*m//g')
    local vlen=${#visible}
    local pad=$((INNER - vlen))
    if (( pad < 0 )); then pad=0; fi
    printf "║%s%*s║\n" "$content" "$pad" ""
  }

  # Border lines
  local TOP="╔$(printf '═%.0s' {1..$INNER})╗"
  local MID="╠$(printf '═%.0s' {1..$INNER})╣"
  local BOT="╚$(printf '═%.0s' {1..$INNER})╝"

  echo ""
  echo "$TOP"
  _tsl "              Tool Availability Status"
  echo "$MID"
  _tsl "  ${CYAN}CORE TOOLS${RESET} (Performance & Caching)"
  _tsl ""

  # sqlite3
  if command -v sqlite3 &>/dev/null; then
    _tsl "    ${CHECK} sqlite3     - Fast SQLite cache (FASTER prompts)"
  else
    _tsl "    ${CROSS} sqlite3     - Falling back to file cache (slower)"
    _tsl "                    Install: apt/brew install sqlite3"
  fi

  # timeout/gtimeout
  if command -v timeout &>/dev/null; then
    _tsl "    ${CHECK} timeout     - Command timeout support (Linux)"
  elif command -v gtimeout &>/dev/null; then
    _tsl "    ${CHECK} gtimeout    - Command timeout support (macOS)"
  else
    _tsl "    ${CROSS} timeout     - Network features DISABLED (gh, PR status)"
    _tsl "                    Install: apt install coreutils"
    _tsl "                             brew install coreutils"
  fi

  # flock
  if command -v flock &>/dev/null; then
    _tsl "    ${CHECK} flock       - File locking for cache safety"
  else
    _tsl "    ${WARN} flock       - Cache writes may race (minor issue)"
  fi

  _tsl ""
  echo "$MID"
  _tsl "  ${CYAN}GITHUB INTEGRATION${RESET}"
  _tsl ""

  # gh CLI
  if command -v gh &>/dev/null; then
    local gh_version=$(gh --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    _tsl "    ${CHECK} gh          - GitHub CLI v${gh_version}"
    if (( _HAS_TIMEOUT_CMD )); then
      if [[ -f "$_GH_AUTH_CACHE_FILE" ]]; then
        local auth_data=$(<"$_GH_AUTH_CACHE_FILE")
        if [[ "${auth_data%%|*}" == "1" ]]; then
          _tsl "                    Authenticated: PR status, CI checks"
        else
          _tsl "                    ${WARN} Not authenticated (run: gh auth login)"
        fi
      else
        _tsl "                    ${WARN} Auth status unknown (checking...)"
      fi
    else
      _tsl "                    ${WARN} Disabled (no timeout command)"
    fi
  else
    _tsl "    ${CROSS} gh          - No PR/CI status in prompt"
    _tsl "                    Install: https://cli.github.com"
  fi

  # ssh
  if command -v ssh &>/dev/null; then
    _tsl "    ${CHECK} ssh         - GitHub SSH identity detection"
  else
    _tsl "    ${CROSS} ssh         - No SSH identity in prompt"
  fi

  # curl
  if command -v curl &>/dev/null; then
    _tsl "    ${CHECK} curl        - AI tool update checks from NPM"
  else
    _tsl "    ${WARN} curl        - No update notifications for AI tools"
  fi

  _tsl ""
  echo "$MID"
  _tsl "  ${CYAN}AI CODING TOOLS${RESET} (Version display in prompt)"
  _tsl ""

  # Claude Code
  if command -v claude &>/dev/null; then
    local claude_ver=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    _tsl "    ${CHECK} claude      - Claude Code v${claude_ver:-?}"
  else
    _tsl "    ${CROSS} claude      - Not installed"
    _tsl "                    Install: npm i -g @anthropic-ai/claude-code"
  fi

  # Codex
  if command -v codex &>/dev/null; then
    local codex_ver=$(codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    _tsl "    ${CHECK} codex       - OpenAI Codex v${codex_ver:-?}"
  else
    _tsl "    ${CROSS} codex       - Not installed"
    _tsl "                    Install: npm i -g @openai/codex"
  fi

  # Gemini
  if command -v gemini &>/dev/null; then
    local gemini_ver=$(gemini --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    _tsl "    ${CHECK} gemini      - Google Gemini v${gemini_ver:-?}"
  else
    _tsl "    ${CROSS} gemini      - Not installed"
    _tsl "                    Install: npm i -g @google/gemini-cli"
  fi

  _tsl ""
  echo "$MID"
  _tsl "  ${CYAN}CACHE STATUS${RESET}"
  _tsl ""
  _tsl "    Cache directory: ${_CACHE_DIR}"

  if (( _CACHE_USE_SQLITE )); then
    local db_size=$(du -h "$_CACHE_DB_FILE" 2>/dev/null | cut -f1)
    _tsl "    SQLite cache:   ${CHECK} Active (${db_size:-0K})"
  else
    _tsl "    SQLite cache:   ${CROSS} Disabled (using file cache)"
  fi

  local cache_count=$(ls -1 "$_CACHE_DIR" 2>/dev/null | wc -l | tr -d ' ')
  _tsl "    Cache files:    ${cache_count} files"

  _tsl ""
  echo "$BOT"
  echo ""

  unfunction _tsl
}

# Aliases for quick commands
if (( ! $+aliases[e] && ! $+functions[e] )); then
  alias e='_prompt_toggle_emoji'
fi
if (( ! $+aliases[p] && ! $+functions[p] )); then
  alias p='_prompt_toggle_path_sep'
fi
if (( ! $+aliases[h] && ! $+functions[h] )); then
  alias h='_prompt_emoji_help'
fi
if (( ! $+aliases[t] && ! $+functions[t] )); then
  alias t='_prompt_tool_status'
fi

# Manual cache refresh function - clears all prompt caches
# Call this to force refresh of all cached data (system info, git, PR, AI tools)
function _prompt_refresh_all_caches() {
  # Clear SQLite cache if available
  if (( _CACHE_USE_SQLITE )); then
    sqlite3 "$_CACHE_DB_FILE" "
      DELETE FROM cache;
      VACUUM;
    " 2>/dev/null
  fi

  # Clear file-based caches by removing cache files (fallback mode)
  rm -f "$_SYSINFO_CACHE_FILE" 2>/dev/null
  rm -f "$_GIT_ROOT_CACHE_FILE" 2>/dev/null
  rm -f "$_GIT_HIERARCHY_CACHE_FILE" 2>/dev/null
  rm -f "$_GIT_EXT_CACHE_FILE" 2>/dev/null
  rm -f "$_GH_PR_CACHE_FILE" 2>/dev/null
  rm -f "$_GH_AUTH_CACHE_FILE" 2>/dev/null
  rm -f "$_GH_USERNAME_GH_CACHE_FILE" 2>/dev/null
  rm -f "$_GH_USERNAME_SSH_CACHE_FILE" 2>/dev/null
  rm -f "$_CLAUDE_CACHE_FILE" 2>/dev/null
  rm -f "$_CODEX_CACHE_FILE" 2>/dev/null
  rm -f "$_GEMINI_CACHE_FILE" 2>/dev/null

  # Clear memory-based associative array caches
  _MEM_CACHE_GIT_ROOT=()
  _MEM_CACHE_GIT_HIERARCHY=()
  _MEM_CACHE_GIT_EXT=()
  _MEM_CACHE_GH_PR=()

  # Reset in-memory per-prompt caches
  _PROMPT_GIT_INFO_CACHE=""
  _PROMPT_GIT_INFO_CACHE_ID=-1
  _PROMPT_GIT_EXT_CACHE=""
  _PROMPT_GIT_EXT_CACHE_ID=-1
  _PROMPT_GH_PR_CACHE=""
  _PROMPT_GH_PR_CACHE_ID=-1
  _PROMPT_GIT_SPECIAL_CACHE=""
  _PROMPT_GIT_SPECIAL_CACHE_ID=-1
  _GIT_REMOTE_BRANCH_CACHE=""
  _GIT_REMOTE_BRANCH_CACHE_ID=-1

  echo "Prompt caches refreshed."
}

# Alias for quick cache refresh
if (( ! $+aliases[u] && ! $+functions[u] )); then
  alias u='_prompt_refresh_all_caches'
fi

# Capture exit status before any other precmd runs
_LAST_EXIT_STATUS=0
function _capture_exit_status() {
  _LAST_EXIT_STATUS=$?
}
# Add as first precmd hook
autoload -Uz add-zsh-hook
add-zsh-hook precmd _capture_exit_status

# Per-prompt render id to avoid recomputing expensive segments multiple times
_PROMPT_RENDER_ID=0
function _prompt_bump_render_id() {
  (( _PROMPT_RENDER_ID++ ))
}
add-zsh-hook precmd _prompt_bump_render_id

# ============================================================================
# PRECOMPUTED PROMPT PARTS - Computed once in precmd, used in PROMPT
# ============================================================================
# These variables are populated by _precmd_compute_prompt and used directly
# in PROMPT to avoid creating subshells for each prompt segment

# Precomputed prompt segment variables
typeset -g _PP_EXIT=""           # Exit status indicator
typeset -g _PP_SSH=""            # SSH indicator
typeset -g _PP_USER_HOST=""      # user@host with color
typeset -g _PP_GH_USER=""        # GitHub username badge [Username]
typeset -g _PP_BADGE=""          # Host/container badge
typeset -g _PP_TIME=""           # Time with dynamic color
typeset -g _PP_PATH=""           # Smart path display
typeset -g _PP_GIT_INFO=""       # Git branch/status
typeset -g _PP_GIT_EXT=""        # Git extended status (ahead/behind/stash)
typeset -g _PP_GIT_SPECIAL=""    # Git special state (rebase/merge/etc)
typeset -g _PP_PR=""             # GitHub PR status
typeset -g _PP_SYSINFO_LEFT=""   # System info (left prompt, long mode only)
typeset -g _PP_AI_LEFT=""        # AI tools (left prompt, long mode only)
typeset -g _PP_JOBS=""           # Jobs indicator prefix
typeset -g _PP_RPROMPT=""        # Right prompt content

# Precompute all prompt segments in precmd (avoids subshells in PROMPT)
# PERFORMANCE: Inline logic and use direct variable assignment to minimize subshells
# Target: reduce from 10-15 subshells to 2-4 per prompt
function _precmd_compute_prompt() {
  # === Exit status ===
  if [[ $_LAST_EXIT_STATUS -eq 0 ]]; then
    if (( _PROMPT_EMOJI_MODE )); then
      _PP_EXIT="%{$fg[green]%}[✓]%{$reset_color%}"
    else
      _PP_EXIT="%{$fg[green]%}[OK]%{$reset_color%}"
    fi
  else
    if (( _PROMPT_EMOJI_MODE )); then
      _PP_EXIT="%{$fg[red]%}[✗${_LAST_EXIT_STATUS}]%{$reset_color%}"
    else
      _PP_EXIT="%{$fg[red]%}[ERR${_LAST_EXIT_STATUS}]%{$reset_color%}"
    fi
  fi

  # === SSH indicator ===
  if [[ -n "$SSH_CONNECTION" ]]; then
    if (( _PROMPT_EMOJI_MODE )); then
      _PP_SSH="%{$fg[cyan]%}⚡%{$reset_color%}"
    else
      _PP_SSH="%{$fg[cyan]%}[SSH]%{$reset_color%} "
    fi
  else
    _PP_SSH=""
  fi

  # === User@host with color (no function call needed) ===
  _PP_USER_HOST="%{$FG[$_CLR_USER_HOST]%}%n@%m%{$reset_color%}"

  # === GitHub username badge (direct assignment, no subshell) ===
  _compute_gh_username_direct  # Sets _PP_GH_USER directly

  # === Time with dynamic color ===
  local hour=""
  if (( ${+EPOCHSECONDS} )); then
    strftime -s hour "%H" "$EPOCHSECONDS"
  else
    hour=$(date +%H)
  fi
  local time_color
  if (( hour >= 6 && hour < 12 )); then
    time_color="%{$FG[$_CLR_TIME_MORNING]%}"
  elif (( hour >= 12 && hour < 18 )); then
    time_color="%{$FG[$_CLR_TIME_AFTERNOON]%}"
  elif (( hour >= 18 && hour < 22 )); then
    time_color="%{$FG[$_CLR_TIME_EVENING]%}"
  else
    time_color="%{$FG[$_CLR_TIME_NIGHT]%}"
  fi
  _PP_TIME="${time_color}[%D{%H:%M:%S}]%{$reset_color%}"

  # === Jobs indicator (inline _e jobs) ===
  if (( _PROMPT_EMOJI_MODE )); then
    _PP_JOBS="⚙"
  else
    _PP_JOBS="J"
  fi

  # === Git info (branch + dirty indicator) - 1 subshell for oh-my-zsh compat ===
  _compute_git_info_direct  # Sets _PP_GIT_INFO directly

  # === Git extended status (ahead/behind/stash) - direct assignment, no subshell ===
  _compute_git_extended_direct  # Sets _PP_GIT_EXT directly

  # === Git special state (rebase/merge/bisect/detached) - direct assignment, no subshell ===
  _compute_git_special_direct  # Sets _PP_GIT_SPECIAL directly

  # === GitHub PR status - direct assignment, no subshell ===
  _compute_pr_status_direct  # Sets _PP_PR directly

  # === AI tools status (direct assignment, no subshell) ===
  _compute_ai_tools_direct  # Sets _PP_AI_STATUS directly

  # === System info (direct assignment, no subshell) ===
  _compute_sysinfo_direct  # Sets _PP_SYSINFO_* directly

  # === Compute dynamic layout ===
  # Use precomputed sysinfo from global variables (no subshell)
  local os_long="$_PP_SYSINFO_OS_LONG"
  local os_short="$_PP_SYSINFO_OS_SHORT"
  local kernel_long="$_PP_SYSINFO_KERNEL_LONG"
  local kernel_short="$_PP_SYSINFO_KERNEL_SHORT"

  # Container/host badge (inline)
  local container_icon badge_color
  if [[ -f /run/.containerenv ]]; then
    (( _PROMPT_EMOJI_MODE )) && container_icon="📦" || container_icon="C"
    badge_color="%{$fg[magenta]%}"
  else
    (( _PROMPT_EMOJI_MODE )) && container_icon="💻" || container_icon="H"
    badge_color="%{$fg[yellow]%}"
  fi
  _PP_BADGE=" ${badge_color}${container_icon}%{$reset_color%}"

  # Calculate visible lengths for layout decision (inline, no subshells)
  # Pure zsh: remove %{...%} escape sequences and count remaining chars
  local _tmp git_len git_ext_len ai_len ai_len_long pr_len
  _tmp="${_PP_GIT_INFO}"; _tmp="${(S)_tmp//\%\{*\%\}/}"; git_len=${#_tmp}
  _tmp="${_PP_GIT_EXT}"; _tmp="${(S)_tmp//\%\{*\%\}/}"; git_ext_len=${#_tmp}
  _tmp="${_PP_AI_STATUS}"; _tmp="${(S)_tmp//\%\{*\%\}/}"; ai_len=${#_tmp}
  _tmp="${_PP_AI_STATUS_LONG}"; _tmp="${(S)_tmp//\%\{*\%\}/}"; ai_len_long=${#_tmp}
  _tmp="${_PP_PR}"; _tmp="${(S)_tmp//\%\{*\%\}/}"; pr_len=${#_tmp}

  local user_host_len=$((${#USER} + 1 + ${#HOST}))
  local time_len=10
  local path_len=${#PWD}
  local fixed_len=12
  local badge_len=3

  local min_len=$((user_host_len + time_len + path_len + git_len + git_ext_len + pr_len + fixed_len))
  local short_version="${os_short}${kernel_short}"
  local short_sysinfo_len=$((${#short_version} + 3))
  local short_len=$((min_len + badge_len + short_sysinfo_len))
  local ai_space=0
  [[ -n "$_PP_AI_STATUS" ]] && ai_space=1
  local short_ai_len=$((short_len + ai_len + ai_space))
  local long_version="${os_long}${kernel_long}"
  local long_sysinfo_len=$((${#long_version} + 3))
  local long_len=$((min_len + badge_len + long_sysinfo_len + ai_len + ai_space))
  # Calculate length with long AI names (Claude/Codex/Gemini instead of Cl:/Cx:/Gm:)
  local long_len_with_long_ai=$((min_len + badge_len + long_sysinfo_len + ai_len_long + ai_space))

  # Decide layout mode and set variables
  local mode path_mode="full"
  local system_info ai_output=""

  if (( long_len <= COLUMNS )); then
    mode="long"
    system_info=" %{$fg[cyan]%}[${long_version}]%{$reset_color%}"
    # In plaintext mode, try to use long AI names if width allows
    if (( ! _PROMPT_EMOJI_MODE )) && [[ -n "$_PP_AI_STATUS_LONG" ]] && (( long_len_with_long_ai <= COLUMNS )); then
      ai_output=" $_PP_AI_STATUS_LONG"
    elif [[ -n "$_PP_AI_STATUS" ]]; then
      ai_output=" $_PP_AI_STATUS"
    fi
  elif (( short_ai_len <= COLUMNS )); then
    mode="short"
    system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
    [[ -n "$_PP_AI_STATUS" ]] && ai_output=" $_PP_AI_STATUS"
  elif (( short_len <= COLUMNS )); then
    mode="short"
    system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
    [[ -n "$_PP_AI_STATUS" ]] && ai_output=" $_PP_AI_STATUS"
  else
    mode="min"
    path_mode="short"
    system_info=" %{$fg[cyan]%}[${short_version}]%{$reset_color%}"
    [[ -n "$_PP_AI_STATUS" ]] && ai_output=" $_PP_AI_STATUS"
  fi

  # === Smart path (direct assignment, no subshell) ===
  _compute_smart_path_direct "$path_mode"  # Sets _PP_PATH directly

  # Set system info and AI based on mode
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

# Add to precmd hooks (runs after _prompt_bump_render_id)
add-zsh-hook precmd _precmd_compute_prompt
add-zsh-hook precmd _periodic_cache_cleanup

# Per-prompt caches for git/PR segments
_PROMPT_GIT_INFO_CACHE=""
_PROMPT_GIT_INFO_CACHE_ID=-1
_PROMPT_GIT_EXT_CACHE=""
_PROMPT_GIT_EXT_CACHE_ID=-1
_PROMPT_GH_PR_CACHE=""
_PROMPT_GH_PR_CACHE_ID=-1

# Git extended status cache (file-based, uses _CACHE_TTL_MEDIUM)
_GIT_EXT_CACHE_FILE="${_CACHE_DIR}/git_ext_cache"

# System info cache (file-based, uses _CACHE_TTL_LOW - rarely changes)
_SYSINFO_CACHE_FILE="${_CACHE_DIR}/sysinfo_cache"

# Global variables for direct sysinfo assignment (avoids subshell)
typeset -g _PP_SYSINFO_OS_LONG=""
typeset -g _PP_SYSINFO_OS_SHORT=""
typeset -g _PP_SYSINFO_KERNEL_LONG=""
typeset -g _PP_SYSINFO_KERNEL_SHORT=""

# Direct-assignment version: writes result to _PP_SYSINFO_* global variables
# PERFORMANCE: Avoids 1 subshell by parsing cache directly into variables
function _compute_sysinfo_direct() {
  local current_time=${EPOCHSECONDS:-$(date +%s)}

  # Check file cache (use zsh native file reading)
  if [[ -f "$_SYSINFO_CACHE_FILE" ]]; then
    local cache_lines=("${(@f)$(<"$_SYSINFO_CACHE_FILE")}")
    local cache_time="${cache_lines[1]}"
    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time < _CACHE_TTL_LOW )); then
      local sysinfo="${cache_lines[2]}"
      _PP_SYSINFO_OS_LONG="${sysinfo%%|*}"
      local rest="${sysinfo#*|}"
      _PP_SYSINFO_OS_SHORT="${rest%%|*}"
      rest="${rest#*|}"
      _PP_SYSINFO_KERNEL_LONG="${rest%%|*}"
      _PP_SYSINFO_KERNEL_SHORT="${rest#*|}"
      return
    fi
  fi

  # Compute system info (first call or cache expired)
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

  # Assign to global variables
  _PP_SYSINFO_OS_LONG="$os_long"
  _PP_SYSINFO_OS_SHORT="$os_short"
  _PP_SYSINFO_KERNEL_LONG="$kernel_long"
  _PP_SYSINFO_KERNEL_SHORT="$kernel_short"
}

# Git root cache (file-based, uses _CACHE_TTL_MEDIUM)
_GIT_ROOT_CACHE_FILE="${_CACHE_DIR}/git_root_cache"

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
  local lock_file="${cache_file}.lock"

  # Inner function to do the actual update
  local new_content=""
  if [[ -f "$cache_file" ]]; then
    local lines=("${(@f)$(<"$cache_file")}")
    local entry
    for entry in "${lines[@]}"; do
      [[ "${entry:0:$prefix_len}" != "$prefix" ]] && new_content+="${entry}"$'\n'
    done
  fi
  new_content+="${new_line}"

  # Use flock for atomic write if available
  if (( _CACHE_HAS_FLOCK )); then
    # Hold the lock fd for the duration of the write.
    (
      exec {lock_fd}>"$lock_file" || exit 1
      flock -x -w 1 $lock_fd || exit 1
      print -r -- "$new_content" > "$temp_file"
      mv "$temp_file" "$cache_file" 2>/dev/null
    ) 2>/dev/null
  else
    # No flock available, write directly (accept potential race)
    print -r -- "$new_content" > "$temp_file"
    mv "$temp_file" "$cache_file" 2>/dev/null
  fi
}

# Get cached git root for current directory
function _get_cached_git_root() {
  local current_dir="$PWD"
  local current_time=${EPOCHSECONDS:-$(date +%s)}

  # Check memory cache first (fastest, no I/O)
  if [[ -n "${_MEM_CACHE_GIT_ROOT[$current_dir]}" ]]; then
    local cached="${_MEM_CACHE_GIT_ROOT[$current_dir]}"
    local cached_root="${cached%|*}"
    local cache_time="${cached##*|}"
    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time < _CACHE_TTL_MEDIUM )); then
      echo "$cached_root"
      return
    fi
  fi

  # Check persistent cache (SQLite or file)
  local cached_line=$(_cache_get "git_root" "$current_dir")
  if [[ -n "$cached_line" ]]; then
    # Format: value|timestamp (from _cache_get)
    local cache_time="${cached_line##*|}"
    local cached_root="${cached_line%|*}"

    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time < _CACHE_TTL_MEDIUM )); then
      # Update memory cache from persistent cache
      _MEM_CACHE_GIT_ROOT[$current_dir]="${cached_root}|${cache_time}"
      echo "$cached_root"
      return
    fi
  fi

  # Compute git root
  local git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  [[ -z "$git_root" ]] && git_root="NOT_GIT"

  # Update both caches
  _MEM_CACHE_GIT_ROOT[$current_dir]="${git_root}|${current_time}"
  _cache_set_async "git_root" "$current_dir" "$git_root" "$current_time"

  # Cleanup memory cache if it grows too large
  (( ${#_MEM_CACHE_GIT_ROOT} > _MEM_CACHE_CLEANUP_THRESHOLD )) && _mem_cache_cleanup "git_root"

  echo "$git_root"
}

# Git hierarchy cache (file-based, uses _CACHE_TTL_MEDIUM)
_GIT_HIERARCHY_CACHE_FILE="${_CACHE_DIR}/git_hierarchy_cache"

# Path background colors defined in COLOR CONSTANTS section at file top

# Get git repository hierarchy (handles submodules)
# Returns: repo1<sep>repo2<sep>repo3<sep>current_subdir
# Where repo1 is outermost, repoN is innermost git root
# current_subdir is the path within the innermost repo (may be empty)
function _get_git_hierarchy() {
  local current_time=${EPOCHSECONDS:-$(date +%s)}
  local cache_key="$PWD"

  # Check memory cache first (fastest, no I/O)
  if [[ -n "${_MEM_CACHE_GIT_HIERARCHY[$cache_key]}" ]]; then
    local cached="${_MEM_CACHE_GIT_HIERARCHY[$cache_key]}"
    local cache_time="${cached##*|}"
    local cached_result="${cached%|*}"
    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time < _CACHE_TTL_MEDIUM )); then
      echo "$cached_result"
      return
    fi
  fi

  # Check persistent cache (SQLite or file)
  local cached_line=$(_cache_get "git_hierarchy" "$cache_key")
  if [[ -n "$cached_line" ]]; then
    # Format: value|timestamp
    local cache_time="${cached_line##*|}"
    local cached_result="${cached_line%|*}"

    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time < _CACHE_TTL_MEDIUM )); then
      # Update memory cache from persistent cache
      _MEM_CACHE_GIT_HIERARCHY[$cache_key]="${cached_result}|${cache_time}"
      echo "$cached_result"
      return
    fi
  fi

  # Build hierarchy from innermost to outermost
  local hierarchy=()
  local dir="$PWD"
  local depth=0
  local max_depth=20

  while true; do
    (( depth >= max_depth )) && break
    (( depth++ ))
    local git_root=$(cd "$dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
    [[ -z "$git_root" ]] && break

    hierarchy=("$git_root" "${hierarchy[@]}")  # prepend (outermost first)

    # Check for superproject
    local superproject=$(cd "$git_root" 2>/dev/null && git rev-parse --show-superproject-working-tree 2>/dev/null)
    [[ -z "$superproject" || "$superproject" == "$dir" || "$superproject" == "$git_root" ]] && break

    dir="$superproject"
  done

  # Build result: repo1<sep>repo2<sep>...<sep>subdir
  local result=""
  local sep="${_GIT_HIERARCHY_SEP:-:}"
  local IFS="$sep"
  if (( ${#hierarchy[@]} > 0 )); then
    result="${hierarchy[*]}"
    # Add current subdirectory within innermost repo
    local innermost="${hierarchy[-1]}"
    if [[ "$PWD" != "$innermost" ]]; then
      result="${result}${sep}${PWD#$innermost/}"
    else
      result="${result}${sep}"  # empty subdir marker
    fi
  fi

  # Cache result in both memory and persistent cache
  _MEM_CACHE_GIT_HIERARCHY[$cache_key]="${result}|${current_time}"
  _cache_set_async "git_hierarchy" "$cache_key" "$result" "$current_time"

  # Cleanup memory cache if it grows too large
  (( ${#_MEM_CACHE_GIT_HIERARCHY} > _MEM_CACHE_CLEANUP_THRESHOLD )) && _mem_cache_cleanup "git_hierarchy"

  echo "$result"
}

# ============================================================================
# DIRECT ASSIGNMENT FUNCTIONS - Avoid subshells by writing to global variables
# ============================================================================

# Direct-assignment version of _git_prompt_info_cached
# PERFORMANCE: Sets _PP_GIT_INFO directly (1 subshell for oh-my-zsh compat)
function _compute_git_info_direct() {
  local git_root=$(_get_cached_git_root)
  if [[ "$git_root" == "NOT_GIT" ]]; then
    _PP_GIT_INFO=""
    return
  fi

  # oh-my-zsh compatibility: must call their function
  if (( $+functions[_omz_git_prompt_info] )); then
    _PP_GIT_INFO=$(_omz_git_prompt_info 2>/dev/null)
  elif (( $+functions[git_prompt_info] )); then
    _PP_GIT_INFO=$(git_prompt_info 2>/dev/null)
  else
    _PP_GIT_INFO=""
  fi
}

# Direct-assignment version of _git_extended_status_cached
# PERFORMANCE: Sets _PP_GIT_EXT directly (0 subshells)
function _compute_git_extended_direct() {
  local current_id="$_PROMPT_RENDER_ID"
  if [[ "$_PROMPT_GIT_EXT_CACHE_ID" == "$current_id" ]]; then
    _PP_GIT_EXT="$_PROMPT_GIT_EXT_CACHE"
    return
  fi

  _PP_GIT_EXT=""
  local git_root=$(_get_cached_git_root)
  [[ "$git_root" == "NOT_GIT" ]] && return

  local cache_key="${git_root}"
  local current_time=${EPOCHSECONDS:-$(date +%s)}

  # Check memory cache first (fastest, no I/O)
  if [[ -n "${_MEM_CACHE_GIT_EXT[$cache_key]}" ]]; then
    local cached="${_MEM_CACHE_GIT_EXT[$cache_key]}"
    local cache_time="${cached##*|}"
    local cached_result="${cached%|*}"
    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time < _CACHE_TTL_MEDIUM )); then
      _PP_GIT_EXT="$cached_result"
      _PROMPT_GIT_EXT_CACHE="$cached_result"
      _PROMPT_GIT_EXT_CACHE_ID="$current_id"
      return
    fi
  fi

  # Check persistent cache (SQLite or file)
  local cached_line=$(_cache_get "git_ext" "$cache_key")
  if [[ -n "$cached_line" ]]; then
    local cache_time="${cached_line##*|}"
    local cached_result="${cached_line%|*}"

    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time < _CACHE_TTL_MEDIUM )); then
      _MEM_CACHE_GIT_EXT[$cache_key]="${cached_result}|${cache_time}"
      _PP_GIT_EXT="$cached_result"
      _PROMPT_GIT_EXT_CACHE="$cached_result"
      _PROMPT_GIT_EXT_CACHE_ID="$current_id"
      return
    fi
  fi

  # Compute result
  local result=""

  # Get ahead/behind counts relative to upstream
  local upstream=$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null)
  if [[ -n "$upstream" ]]; then
    local counts=$(git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
    if [[ -n "$counts" ]]; then
      local ahead behind
      IFS=$'\t ' read -r ahead behind <<< "$counts"

      if [[ "$ahead" -gt 0 ]]; then
        if (( _PROMPT_EMOJI_MODE )); then
          result="${result}%{$fg[green]%}↑${ahead}%{$reset_color%}"
        else
          result="${result}%{$fg[green]%}+${ahead}%{$reset_color%}"
        fi
      fi
      if [[ "$behind" -gt 0 ]]; then
        if (( _PROMPT_EMOJI_MODE )); then
          result="${result}%{$fg[red]%}↓${behind}%{$reset_color%}"
        else
          result="${result}%{$fg[red]%}-${behind}%{$reset_color%}"
        fi
      fi
    fi
  fi

  # Get stash count (pure zsh)
  local stash_output stash_count=0
  stash_output=$(git stash list 2>/dev/null)
  [[ -n "$stash_output" ]] && stash_count=${#${(f)stash_output}}
  if [[ "$stash_count" -gt 0 ]]; then
    if (( _PROMPT_EMOJI_MODE )); then
      result="${result}%{$fg[yellow]%}⚑${stash_count}%{$reset_color%}"
    else
      result="${result}%{$fg[yellow]%}S${stash_count}%{$reset_color%}"
    fi
  fi

  # Update caches
  _MEM_CACHE_GIT_EXT[$cache_key]="${result}|${current_time}"
  _cache_set_async "git_ext" "$cache_key" "$result" "$current_time"
  (( ${#_MEM_CACHE_GIT_EXT} > _MEM_CACHE_CLEANUP_THRESHOLD )) && _mem_cache_cleanup "git_ext"

  _PP_GIT_EXT="$result"
  _PROMPT_GIT_EXT_CACHE="$result"
  _PROMPT_GIT_EXT_CACHE_ID="$current_id"
}

# Direct-assignment version of _git_special_state_cached
# PERFORMANCE: Sets _PP_GIT_SPECIAL directly (0 subshells)
function _compute_git_special_direct() {
  local current_id="$_PROMPT_RENDER_ID"
  if [[ "$_PROMPT_GIT_SPECIAL_CACHE_ID" == "$current_id" ]]; then
    _PP_GIT_SPECIAL="$_PROMPT_GIT_SPECIAL_CACHE"
    return
  fi

  _PP_GIT_SPECIAL=""
  local git_root=$(_get_cached_git_root)
  [[ "$git_root" == "NOT_GIT" ]] && return

  local git_dir="${git_root}/.git"
  # Handle worktrees
  if [[ -f "$git_dir" ]]; then
    local git_link=$(<"$git_dir")
    git_dir="${git_link#gitdir: }"
    git_dir="${git_dir%%[[:space:]]}"
  fi

  local state="" step="" total=""

  # Check for rebase
  if [[ -d "${git_dir}/rebase-merge" ]]; then
    [[ -f "${git_dir}/rebase-merge/msgnum" ]] && step=$(<"${git_dir}/rebase-merge/msgnum")
    [[ -f "${git_dir}/rebase-merge/end" ]] && total=$(<"${git_dir}/rebase-merge/end")
    [[ -f "${git_dir}/rebase-merge/interactive" ]] && state="rebase-i" || state="rebase-m"
  elif [[ -d "${git_dir}/rebase-apply" ]]; then
    [[ -f "${git_dir}/rebase-apply/next" ]] && step=$(<"${git_dir}/rebase-apply/next")
    [[ -f "${git_dir}/rebase-apply/last" ]] && total=$(<"${git_dir}/rebase-apply/last")
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
    local head_ref=$(git symbolic-ref HEAD 2>/dev/null)
    [[ -z "$head_ref" ]] && state="detached"
  fi

  # Format output
  if [[ -n "$state" ]]; then
    local icon="" color="%{$fg[magenta]%}"

    if (( _PROMPT_EMOJI_MODE )); then
      case "$state" in
        rebase*|am*) icon="🔀"; color="%{$fg[yellow]%}" ;;
        merge)       icon="🔀"; color="%{$fg[cyan]%}" ;;
        cherry|revert) icon="🍒"; color="%{$fg[red]%}" ;;
        bisect)      icon="🔍"; color="%{$fg[blue]%}" ;;
        detached)    icon="🔌"; color="%{$fg[red]%}" ;;
      esac
    else
      case "$state" in
        rebase*|am*) icon="RB"; color="%{$fg[yellow]%}" ;;
        merge)       icon="MG"; color="%{$fg[cyan]%}" ;;
        cherry|revert) icon="CP"; color="%{$fg[red]%}" ;;
        bisect)      icon="BI"; color="%{$fg[blue]%}" ;;
        detached)    icon="DT"; color="%{$fg[red]%}" ;;
      esac
    fi

    if [[ -n "$step" && -n "$total" ]]; then
      _PP_GIT_SPECIAL="${color}${icon}${step}/${total}%{$reset_color%}"
    else
      _PP_GIT_SPECIAL="${color}${icon}%{$reset_color%}"
    fi
  fi

  _PROMPT_GIT_SPECIAL_CACHE="$_PP_GIT_SPECIAL"
  _PROMPT_GIT_SPECIAL_CACHE_ID="$current_id"
}

# Direct-assignment version of _gh_pr_status_cached
# PERFORMANCE: Sets _PP_PR directly (0 subshells)
function _compute_pr_status_direct() {
  local current_id="$_PROMPT_RENDER_ID"
  if [[ "$_PROMPT_GH_PR_CACHE_ID" == "$current_id" ]]; then
    _PP_PR="$_PROMPT_GH_PR_CACHE"
    return
  fi

  _PP_PR=""

  # Check if gh command exists
  command -v gh &>/dev/null || return

  # Check if gh is authenticated
  _gh_is_authenticated || return

  # Get cached git remote/branch
  local remote_branch=$(_get_cached_git_remote_branch)
  [[ -z "$remote_branch" ]] && return

  local remote_key="${remote_branch%%|*}"
  local branch="${remote_branch#*|}"
  local cache_key="${remote_key}|${branch}"
  local pr_number="" ci_status="none" cache_time=0
  local current_time=${EPOCHSECONDS:-$(date +%s)}

  # Check persistent cache
  local cached_line=$(_cache_get "gh_pr" "$cache_key")
  if [[ -n "$cached_line" ]]; then
    cache_time="${cached_line##*|}"
    local rest="${cached_line%|*}"
    ci_status="${rest##*|}"
    pr_number="${rest%|*}"
    [[ ! "$cache_time" =~ ^[0-9]+$ ]] && cache_time=0
  fi

  # Refresh if expired
  (( current_time - cache_time > _CACHE_TTL_HIGH )) && _gh_pr_update_cache "$remote_key" "$branch"

  # Display PR if valid
  if [[ -n "$pr_number" && "$pr_number" != "-1" ]]; then
    local ci_indicator=""
    case "$ci_status" in
      pass)
        (( _PROMPT_EMOJI_MODE )) && ci_indicator="%{$fg[green]%}✓" || ci_indicator="%{$fg[green]%}OK"
        ;;
      fail)
        (( _PROMPT_EMOJI_MODE )) && ci_indicator="%{$fg[red]%}✗" || ci_indicator="%{$fg[red]%}X"
        ;;
      pending)
        (( _PROMPT_EMOJI_MODE )) && ci_indicator="%{$fg[yellow]%}⏳" || ci_indicator="%{$fg[yellow]%}..."
        ;;
    esac

    if [[ -n "$ci_indicator" ]]; then
      _PP_PR="%{$FG[$_CLR_PR]%}#${pr_number}${ci_indicator}%{$reset_color%}"
    else
      _PP_PR="%{$FG[$_CLR_PR]%}#${pr_number}%{$reset_color%}"
    fi
  fi

  _PROMPT_GH_PR_CACHE="$_PP_PR"
  _PROMPT_GH_PR_CACHE_ID="$current_id"
}

# Direct-assignment version of smart_path_display
# PERFORMANCE: Sets _PP_PATH directly (0 subshells when cached)
function _compute_smart_path_direct() {
  local use_short="$1"
  local full_path="${PWD/#$HOME/~}"

  # Check if we're in a git repo
  local git_root=$(_get_cached_git_root)

  if [[ "$git_root" == "NOT_GIT" ]]; then
    # Escape % to %% to prevent zsh prompt escape interpretation
    _PP_PATH="%{$fg[white]%}[${full_path//\%/%%}]%{$reset_color%}"
    return
  fi

  # Get full hierarchy
  local hierarchy_str=$(_get_git_hierarchy)

  if [[ -z "$hierarchy_str" ]]; then
    # Escape % to %% to prevent zsh prompt escape interpretation
    _PP_PATH="%{$fg[white]%}[${full_path//\%/%%}]%{$reset_color%}"
    return
  fi

  # Parse hierarchy (separator defined by _GIT_HIERARCHY_SEP)
  # Note: zsh s:X: syntax requires literal delimiter, use s.$sep. for variable
  local sep="${_GIT_HIERARCHY_SEP:-:}"
  local -a parts=("${(@ps.$sep.)hierarchy_str}")
  local num_parts=${#parts[@]}

  local subdir=""
  local repos=()
  if (( num_parts > 0 )); then
    subdir="${parts[-1]}"
    repos=("${parts[@]:0:$((num_parts-1))}")
  fi

  local num_repos=${#repos[@]}
  local segments=() segment_lengths=()

  for (( i=1; i<=num_repos; i++ )); do
    local repo="${repos[$i]}"
    local display_path=""

    if (( i == 1 )); then
      display_path="${repo/#$HOME/~}"
    else
      local parent="${repos[$((i-1))]}"
      display_path="${repo#$parent/}"
    fi

    segments+=("$display_path")
    segment_lengths+=(${#display_path})
  done

  [[ -n "$subdir" ]] && segments+=("$subdir") && segment_lengths+=(${#subdir})

  local total_segments=${#segments[@]}
  local total_len=2
  for len in "${segment_lengths[@]}"; do
    (( total_len += len ))
  done
  (( total_len += total_segments - 1 ))

  local start_idx=1
  if [[ "$use_short" == "short" ]] || (( ${2:-0} > 0 && total_len > ${2:-0} )); then
    local target_width=${2:-50}
    [[ "$use_short" == "short" ]] && target_width=40

    while (( start_idx < total_segments && total_len > target_width )); do
      (( total_len -= segment_lengths[$start_idx] + 1 ))
      (( start_idx++ ))
    done
  fi

  # Determine path separator
  local path_sep="/"
  local has_space_in_path=0
  [[ "$PWD" == *" "* ]] && has_space_in_path=1
  if (( ! has_space_in_path )); then
    for seg in "${segments[@]}"; do
      [[ "$seg" == *" "* ]] && has_space_in_path=1 && break
    done
  fi
  (( _PROMPT_PATH_SEP_MODE && ! has_space_in_path )) && path_sep=" "

  # Build result
  # NOTE: Use $'\e' for escape character in direct assignment
  local ESC=$'\e'
  local result="["
  local sep=""

  if (( start_idx > 1 )); then
    result="${result}%{$FG[$_CLR_TRUNCATED]%}..%{$reset_color%}${path_sep}"
  fi

  for (( i=start_idx; i<=total_segments; i++ )); do
    local seg="${segments[$i]}"
    # Escape % to %% to prevent zsh prompt escape interpretation
    seg="${seg//\%/%%}"

    if (( i <= num_repos )); then
      local level=$((i - start_idx))
      (( level >= ${#_PATH_BG_COLORS[@]} )) && level=$(( ${#_PATH_BG_COLORS[@]} - 1 ))
      local bg_num="${_PATH_BG_COLORS[$((level+1))]}"
      result="${result}${sep}%{${ESC}[48;5;${bg_num}m${ESC}[38;5;16m%}${seg}%{$reset_color%}"
    else
      result="${result}${sep}%{$fg[white]%}${seg}%{$reset_color%}"
    fi

    sep="$path_sep"
  done

  _PP_PATH="${result}]"
}

# AI Coding Tools version status for prompt
# Uses cache to avoid network requests on every prompt
# Shared across all terminals for better efficiency (uses _CACHE_TTL_LOW)
_CLAUDE_CACHE_FILE="${_CACHE_DIR}/claude_version_cache"
_CODEX_CACHE_FILE="${_CACHE_DIR}/codex_version_cache"
_GEMINI_CACHE_FILE="${_CACHE_DIR}/gemini_version_cache"

# GitHub PR cache (uses _CACHE_TTL_HIGH for fast-changing CI status)
_GH_PR_CACHE_FILE="${_CACHE_DIR}/gh_pr_cache"

# Git remote/branch cache (in-memory per-prompt, avoids repeated git calls)
_GIT_REMOTE_BRANCH_CACHE=""
_GIT_REMOTE_BRANCH_CACHE_ID=-1

# Hash sensitive strings (e.g., remote URLs) for cache keys.
# Args: $1=input string
# Returns: hash string
function _hash_string() {
  local input="$1"
  local hash=""

  if command -v sha256sum &>/dev/null; then
    hash=$(printf '%s' "$input" | sha256sum 2>/dev/null)
    hash="${hash%% *}"
  elif command -v shasum &>/dev/null; then
    hash=$(printf '%s' "$input" | shasum -a 256 2>/dev/null)
    hash="${hash%% *}"
  elif command -v openssl &>/dev/null; then
    hash=$(printf '%s' "$input" | openssl dgst -sha256 2>/dev/null)
    hash="${hash##* }"
  elif command -v cksum &>/dev/null; then
    hash=$(printf '%s' "$input" | cksum 2>/dev/null)
    hash="${hash%% *}"
  else
    hash="${#input}"
  fi

  print -r -- "$hash"
}

# Get cached git remote key and branch (per-prompt cache)
# Returns: remote_key|branch or empty if not in git repo
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
    local remote_key=$(_hash_string "$remote_url")
    [[ -z "$remote_key" ]] && remote_key="${#remote_url}"
    _GIT_REMOTE_BRANCH_CACHE="${remote_key}|${branch}"
  else
    _GIT_REMOTE_BRANCH_CACHE=""
  fi
  _GIT_REMOTE_BRANCH_CACHE_ID="$current_id"
  echo "$_GIT_REMOTE_BRANCH_CACHE"
}

# Helper: determine update type (major, minor, or patch)
# Returns: "major", "minor", "patch", or "" if no update
_version_update_type() {
  local installed="$1"
  local remote="$2"
  REPLY=""

  [[ -z "$installed" || -z "$remote" ]] && return 1

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
    REPLY="major"
    return 0
  elif (( rem_minor > inst_minor )); then
    REPLY="minor"
    return 0
  elif (( rem_patch > inst_patch )); then
    REPLY="patch"
    return 0
  fi

  return 1
}

# Generic AI tool version cache updater (runs in background)
# Args: $1=cache_file, $2=command_name, $3=npm_package_url
# Uses lock file to prevent multiple simultaneous background processes
_ai_tool_update_cache() {
  local cache_file="$1"
  local cmd="$2"
  local npm_url="$3"
  local lock_file="${cache_file}.updating"
  local net_timeout="${_NETWORK_TIMEOUT:-5}"

  # Check if update is already in progress (prevents process accumulation)
  if [[ -f "$lock_file" ]]; then
    # Check if lock is stale (older than 2x network timeout)
    local lock_time=$(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null)
    local current_time=${EPOCHSECONDS:-$(date +%s)}
    if [[ -n "$lock_time" ]] && (( current_time - lock_time < net_timeout * 2 )); then
      return  # Update already in progress
    fi
    # Stale lock, remove it
    rm -f "$lock_file" 2>/dev/null
  fi

  # Create lock file before spawning background process
  touch "$lock_file" 2>/dev/null || return

  # Pass variables to subshell
  (
    local installed_version
    local remote_version

    # Get local installed version
    installed_version=$($cmd --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)

    # Get remote latest version from NPM registry
    if command -v curl &>/dev/null; then
      remote_version=$(curl -s --max-time "$net_timeout" "$npm_url" 2>/dev/null | grep -o '"version":"[^"]*"' | sed 's/"version":"//; s/"//')
    fi

    # Only update cache if we got the local version
    if [[ -n "$installed_version" ]]; then
      local current_time=${EPOCHSECONDS:-$(date +%s)}
      echo "$installed_version $remote_version $current_time" > "$cache_file"
    fi

    # Remove lock file when done
    rm -f "$lock_file" 2>/dev/null
  ) &>/dev/null &!
  # &! immediately disowns, suppressing both start and end job notifications
}

# GitHub CLI authentication status cache (uses _CACHE_TTL_LOW)
typeset -g _GH_AUTH_CACHE_FILE="${_CACHE_DIR}/gh_auth_status"

# GitHub username cache files (uses _CACHE_TTL_MEDIUM)
typeset -g _GH_USERNAME_GH_CACHE_FILE="${_CACHE_DIR}/gh_username_gh"
typeset -g _GH_USERNAME_SSH_CACHE_FILE="${_CACHE_DIR}/gh_username_ssh"
typeset -g _GH_USERNAME_UPDATING_GH="${_CACHE_DIR}/gh_username_updating_gh.lock"
typeset -g _GH_USERNAME_UPDATING_SSH="${_CACHE_DIR}/gh_username_updating_ssh.lock"

# Get GitHub username via gh auth status (background update)
function _gh_username_update_gh() {
  # Requires timeout command to prevent gh from hanging indefinitely
  (( _HAS_TIMEOUT_CMD )) || return

  local lock_file="$_GH_USERNAME_UPDATING_GH"
  local cache_file="$_GH_USERNAME_GH_CACHE_FILE"
  local net_timeout="${_NETWORK_TIMEOUT:-5}"

  # Check if update is already in progress
  if [[ -f "$lock_file" ]]; then
    local lock_time=$(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null)
    local current_time=${EPOCHSECONDS:-$(date +%s)}
    if [[ -n "$lock_time" ]] && (( current_time - lock_time < net_timeout * 2 )); then
      return
    fi
    rm -f "$lock_file" 2>/dev/null
  fi

  touch "$lock_file" 2>/dev/null || return

  # Pass variables to subshell via environment
  (
    local username=""
    local auth_output

    # Parse username from gh auth status output
    auth_output=$(_run_with_timeout "$net_timeout" gh auth status 2>&1)

    # Extract username from "Logged in to github.com account USERNAME"
    username=$(echo "$auth_output" | grep -oE 'account [^ ]+' | head -n1 | sed 's/account //')

    local current_time=${EPOCHSECONDS:-$(date +%s)}
    if [[ -n "$username" ]]; then
      echo "${username}|${current_time}" > "$cache_file"
    else
      echo "|${current_time}" > "$cache_file"
    fi

    rm -f "$lock_file" 2>/dev/null
  ) &>/dev/null &!
}

# Get GitHub username via ssh -T git@github.com (background update)
# Note: ssh has built-in timeout support via ConnectTimeout, no external timeout needed
function _gh_username_update_ssh() {
  local lock_file="$_GH_USERNAME_UPDATING_SSH"
  local cache_file="$_GH_USERNAME_SSH_CACHE_FILE"
  local net_timeout="${_NETWORK_TIMEOUT:-5}"

  # Check if update is already in progress
  if [[ -f "$lock_file" ]]; then
    local lock_time=$(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null)
    local current_time=${EPOCHSECONDS:-$(date +%s)}
    if [[ -n "$lock_time" ]] && (( current_time - lock_time < net_timeout * 2 )); then
      return
    fi
    rm -f "$lock_file" 2>/dev/null
  fi

  touch "$lock_file" 2>/dev/null || return

  # Pass variables to subshell via environment
  (
    local username=""
    local ssh_output

    # Parse username from ssh output (ssh has built-in timeout via ConnectTimeout)
    ssh_output=$(ssh -o ConnectTimeout="$net_timeout" -o BatchMode=yes -T git@github.com 2>&1)

    # Extract username from "Hi USERNAME! You've successfully authenticated..."
    username=$(echo "$ssh_output" | grep -oE 'Hi [^!]+!' | head -n1 | sed 's/Hi //; s/!//')

    local current_time=${EPOCHSECONDS:-$(date +%s)}
    if [[ -n "$username" ]]; then
      echo "${username}|${current_time}" > "$cache_file"
    else
      echo "|${current_time}" > "$cache_file"
    fi

    rm -f "$lock_file" 2>/dev/null
  ) &>/dev/null &!
}

# Direct-assignment version: writes result to _PP_GH_USER global variable
# PERFORMANCE: Avoids 3 subshells by reading cache files directly
function _compute_gh_username_direct() {
  local gh_user="" ssh_user=""
  local current_time=${EPOCHSECONDS:-$(date +%s)}

  # Read gh username from cache file directly (no function call)
  if [[ -f "$_GH_USERNAME_GH_CACHE_FILE" ]]; then
    local cache_data=$(<"$_GH_USERNAME_GH_CACHE_FILE")
    gh_user="${cache_data%%|*}"
    local cache_time="${cache_data#*|}"
    # Trigger background refresh if expired
    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time > _CACHE_TTL_MEDIUM )); then
      command -v gh &>/dev/null && _gh_username_update_gh
    fi
  else
    # No cache, trigger background refresh
    command -v gh &>/dev/null && _gh_username_update_gh
  fi

  # Read ssh username from cache file directly (no function call)
  if [[ -f "$_GH_USERNAME_SSH_CACHE_FILE" ]]; then
    local cache_data=$(<"$_GH_USERNAME_SSH_CACHE_FILE")
    ssh_user="${cache_data%%|*}"
    local cache_time="${cache_data#*|}"
    # Trigger background refresh if expired
    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time > _CACHE_TTL_MEDIUM )); then
      _gh_username_update_ssh
    fi
  else
    # No cache, trigger background refresh
    _gh_username_update_ssh
  fi

  # Build badge and assign directly to _PP_GH_USER
  # NOTE: Use $'\e' for escape character in direct assignment (not \\e which is for echo)
  local ESC=$'\e'
  if [[ -z "$gh_user" && -z "$ssh_user" ]]; then
    _PP_GH_USER=""
  elif [[ -z "$gh_user" ]]; then
    _PP_GH_USER="%{${ESC}[48;5;${_CLR_GH_USER_BG}m${ESC}[38;5;${_CLR_GH_USER_FG}m%}[${ssh_user}]%{$reset_color%}"
  elif [[ -z "$ssh_user" ]]; then
    _PP_GH_USER="%{${ESC}[48;5;${_CLR_GH_USER_BG}m${ESC}[38;5;${_CLR_GH_USER_FG}m%}[${gh_user}]%{$reset_color%}"
  elif [[ "$gh_user" == "$ssh_user" ]]; then
    _PP_GH_USER="%{${ESC}[48;5;${_CLR_GH_USER_BG}m${ESC}[38;5;${_CLR_GH_USER_FG}m%}[${gh_user}]%{$reset_color%}"
  else
    _PP_GH_USER="%{${ESC}[48;5;${_CLR_GH_USER_MISMATCH}m${ESC}[38;5;255m%}[${gh_user}|${ssh_user}]%{$reset_color%}"
  fi
}

# Memory cache for gh authentication status (fastest, no I/O)
typeset -g _GH_AUTH_MEM_CACHE=""
typeset -g _GH_AUTH_MEM_CACHE_TIME=0
typeset -g _GH_AUTH_UPDATING="${_CACHE_DIR}/gh_auth_updating.lock"

# Background update for gh authentication status
function _gh_auth_update_background() {
  # Requires timeout command to prevent gh from hanging indefinitely
  (( _HAS_TIMEOUT_CMD )) || return

  local lock_file="$_GH_AUTH_UPDATING"
  local net_timeout="${_NETWORK_TIMEOUT:-5}"

  # Check if update is already in progress
  if [[ -f "$lock_file" ]]; then
    local lock_time=$(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null)
    local current_time=${EPOCHSECONDS:-$(date +%s)}
    if [[ -n "$lock_time" ]] && (( current_time - lock_time < net_timeout * 2 )); then
      return  # Update already in progress
    fi
    rm -f "$lock_file" 2>/dev/null
  fi

  touch "$lock_file" 2>/dev/null || return

  (
    local current_time=${EPOCHSECONDS:-$(date +%s)}
    if _run_with_timeout "$net_timeout" gh auth status &>/dev/null; then
      echo "1|${current_time}" > "$_GH_AUTH_CACHE_FILE"
    else
      echo "0|${current_time}" > "$_GH_AUTH_CACHE_FILE"
    fi
    rm -f "$lock_file" 2>/dev/null
  ) &>/dev/null &!
}

# Check if gh is authenticated (cached with memory + file layers)
# PERFORMANCE: Never blocks - returns cached result and triggers background update if needed
# Returns 0 if authenticated, 1 if not (or unknown on first call)
function _gh_is_authenticated() {
  local current_time=${EPOCHSECONDS:-$(date +%s)}

  # Memory cache first (fastest, no I/O)
  if [[ -n "$_GH_AUTH_MEM_CACHE" ]] && \
     (( current_time - _GH_AUTH_MEM_CACHE_TIME < _CACHE_TTL_LOW )); then
    [[ "$_GH_AUTH_MEM_CACHE" == "1" ]] && return 0 || return 1
  fi

  # Check file cache
  if [[ -f "$_GH_AUTH_CACHE_FILE" ]]; then
    local cache_data=$(<"$_GH_AUTH_CACHE_FILE")
    local cached_status="${cache_data%%|*}"
    local cache_time="${cache_data#*|}"

    if [[ "$cache_time" =~ ^[0-9]+$ ]] && (( current_time - cache_time < _CACHE_TTL_LOW )); then
      # Update memory cache from file cache
      _GH_AUTH_MEM_CACHE="$cached_status"
      _GH_AUTH_MEM_CACHE_TIME="$cache_time"
      [[ "$cached_status" == "1" ]] && return 0 || return 1
    fi

    # Cache expired, use stale value but trigger background refresh
    _GH_AUTH_MEM_CACHE="$cached_status"
    _GH_AUTH_MEM_CACHE_TIME="$current_time"  # Prevent repeated triggers
    _gh_auth_update_background
    [[ "$cached_status" == "1" ]] && return 0 || return 1
  fi

  # No cache at all - trigger background update and return "not authenticated"
  # This prevents blocking on first call; PR status will appear after background update completes
  _gh_auth_update_background
  return 1
}

# Update GitHub PR cache (runs in background)
# Cache format: pr_number|ci_status
# ci_status: "pass", "fail", "pending", or "none"
# Uses lock file to prevent multiple simultaneous background processes
_gh_pr_update_cache() {
  # Requires timeout command to prevent gh from hanging indefinitely
  (( _HAS_TIMEOUT_CMD )) || return

  local remote_key="$1"
  local branch="$2"
  local lock_file="${_CACHE_DIR}/gh_pr_updating.lock"
  local net_timeout="${_NETWORK_TIMEOUT:-5}"

  # Check if update is already in progress (prevents process accumulation)
  if [[ -f "$lock_file" ]]; then
    # Check if lock is stale (older than 2x network timeout)
    local lock_time=$(stat -c %Y "$lock_file" 2>/dev/null || stat -f %m "$lock_file" 2>/dev/null)
    local current_time=${EPOCHSECONDS:-$(date +%s)}
    if [[ -n "$lock_time" ]] && (( current_time - lock_time < net_timeout * 2 )); then
      return  # Update already in progress
    fi
    # Stale lock, remove it
    rm -f "$lock_file" 2>/dev/null
  fi

  # Create lock file before spawning background process
  touch "$lock_file" 2>/dev/null || return

  # Pass variables to subshell
  (
    # Check gh authentication first (uses cached result)
    if ! _gh_is_authenticated; then
      rm -f "$lock_file" 2>/dev/null
      return 0
    fi

    local pr_number
    local ci_status="none"

    # Use timeout command to prevent gh from hanging
    pr_number=$(_run_with_timeout "$net_timeout" gh pr view --json number --jq '.number' 2>/dev/null)

    if [[ -z "$pr_number" ]]; then
      pr_number="-1"
    else
      # Get CI status using gh pr checks --json for reliable parsing
      local checks_output
      # Use JSON output for reliable status detection
      checks_output=$(_run_with_timeout "$net_timeout" gh pr checks --json name,state 2>/dev/null)
      if [[ -n "$checks_output" && "$checks_output" != "[]" ]]; then
        # JSON format: [{"name":"...","state":"SUCCESS|FAILURE|PENDING|..."},...]
        # Possible states: SUCCESS, FAILURE, PENDING, CANCELLED, SKIPPED, QUEUED, ERROR
        if echo "$checks_output" | grep -qE '"state":"(FAILURE|ERROR)"'; then
          ci_status="fail"
        elif echo "$checks_output" | grep -qE '"state":"(PENDING|QUEUED)"'; then
          ci_status="pending"
        elif echo "$checks_output" | grep -qE '"state":"(CANCELLED|SKIPPED)"'; then
          # If only cancelled/skipped, treat as pending (not conclusive)
          if echo "$checks_output" | grep -qE '"state":"SUCCESS"'; then
            ci_status="pass"  # Has some successes
          else
            ci_status="pending"  # No clear pass/fail
          fi
        elif echo "$checks_output" | grep -qE '"state":"SUCCESS"'; then
          ci_status="pass"
        fi
      fi
    fi

    local current_time=${EPOCHSECONDS:-$(date +%s)}
    local cache_key="${remote_key}|${branch}"
    local cache_value="${pr_number}|${ci_status}"

    # Use the unified cache system
    if (( _CACHE_USE_SQLITE )); then
      local escaped_key="${cache_key//\'/\'\'}"
      local escaped_value="${cache_value//\'/\'\'}"
      sqlite3 "$_CACHE_DB_FILE" "
        INSERT OR REPLACE INTO cache (key, value, timestamp)
        VALUES ('gh_pr:${escaped_key}', '${escaped_value}', ${current_time});
      " 2>/dev/null
    else
      local cache_file="${_CACHE_DIR}/gh_pr_cache"
      local sep=$'\x1f'
      local prefix="${cache_key}${sep}"
      _cache_update_line_by_prefix "$cache_file" "$prefix" "${cache_key}${sep}${cache_value}${sep}${current_time}"
    fi

    # Remove lock file when done
    rm -f "$lock_file" 2>/dev/null
  ) &>/dev/null &!
}

# Combined AI tools status: [tool1tool2tool3] format (emoji) or [tool1|tool2|tool3] (plaintext)
# Direct-assignment version: writes result to _PP_AI_STATUS global variable
# In plaintext mode, also generates _PP_AI_STATUS_LONG with full names (Claude/Codex/Gemini)
# PERFORMANCE: Avoids subshells by using direct variable assignment
typeset -g _PP_AI_STATUS=""
typeset -g _PP_AI_STATUS_LONG=""

function _compute_ai_tools_direct() {
  local ai_status=""
  local ai_status_long=""
  local tool_result=""
  local tool_result_long=""

  # Claude Code - direct computation without subshell
  tool_result=""
  tool_result_long=""
  if command -v claude &>/dev/null; then
    local installed_version="" remote_version="" cache_time=0
    local current_time=${EPOCHSECONDS:-$(date +%s)}
    if [[ -f "$_CLAUDE_CACHE_FILE" ]]; then
      read -r installed_version remote_version cache_time < "$_CLAUDE_CACHE_FILE"
      [[ ! "$cache_time" =~ ^[0-9]+$ ]] && cache_time=0
      (( current_time - cache_time > _CACHE_TTL_LOW )) && \
        _ai_tool_update_cache "$_CLAUDE_CACHE_FILE" "claude" "https://registry.npmjs.org/@anthropic-ai/claude-code/latest"
    else
      _ai_tool_update_cache "$_CLAUDE_CACHE_FILE" "claude" "https://registry.npmjs.org/@anthropic-ai/claude-code/latest"
    fi
    if [[ -n "$installed_version" ]]; then
      local update_ind="" icon="" icon_long=""
      _version_update_type "$installed_version" "$remote_version" && update_ind="%{$fg[red]%}*"
      if (( _PROMPT_EMOJI_MODE )); then
        icon="🤖"
        icon_long="🤖"
      else
        icon="Cl:"
        icon_long="Claude:"
      fi
      tool_result="%{$FG[$_CLR_CLAUDE]%}${icon}${installed_version}${update_ind}%{$reset_color%}"
      tool_result_long="%{$FG[$_CLR_CLAUDE]%}${icon_long}${installed_version}${update_ind}%{$reset_color%}"
    fi
  fi
  if [[ -n "$tool_result" ]]; then
    ai_status="$tool_result"
    ai_status_long="$tool_result_long"
  fi

  # Codex - direct computation without subshell
  tool_result=""
  tool_result_long=""
  if command -v codex &>/dev/null; then
    local installed_version="" remote_version="" cache_time=0
    local current_time=${EPOCHSECONDS:-$(date +%s)}
    if [[ -f "$_CODEX_CACHE_FILE" ]]; then
      read -r installed_version remote_version cache_time < "$_CODEX_CACHE_FILE"
      [[ ! "$cache_time" =~ ^[0-9]+$ ]] && cache_time=0
      (( current_time - cache_time > _CACHE_TTL_LOW )) && \
        _ai_tool_update_cache "$_CODEX_CACHE_FILE" "codex" "https://registry.npmjs.org/@openai/codex/latest"
    else
      _ai_tool_update_cache "$_CODEX_CACHE_FILE" "codex" "https://registry.npmjs.org/@openai/codex/latest"
    fi
    if [[ -n "$installed_version" ]]; then
      local update_ind="" icon="" icon_long=""
      _version_update_type "$installed_version" "$remote_version" && update_ind="%{$fg[red]%}*"
      if (( _PROMPT_EMOJI_MODE )); then
        icon="🧠"
        icon_long="🧠"
      else
        icon="Cx:"
        icon_long="Codex:"
      fi
      tool_result="%{$FG[$_CLR_CODEX]%}${icon}${installed_version}${update_ind}%{$reset_color%}"
      tool_result_long="%{$FG[$_CLR_CODEX]%}${icon_long}${installed_version}${update_ind}%{$reset_color%}"
    fi
  fi
  if [[ -n "$tool_result" ]]; then
    local sep=""
    (( ! _PROMPT_EMOJI_MODE )) && sep="|"
    [[ -n "$ai_status" ]] && ai_status="${ai_status}${sep}"
    [[ -n "$ai_status_long" ]] && ai_status_long="${ai_status_long}${sep}"
    ai_status="${ai_status}${tool_result}"
    ai_status_long="${ai_status_long}${tool_result_long}"
  fi

  # Gemini - direct computation without subshell
  tool_result=""
  tool_result_long=""
  if command -v gemini &>/dev/null; then
    local installed_version="" remote_version="" cache_time=0
    local current_time=${EPOCHSECONDS:-$(date +%s)}
    if [[ -f "$_GEMINI_CACHE_FILE" ]]; then
      read -r installed_version remote_version cache_time < "$_GEMINI_CACHE_FILE"
      [[ ! "$cache_time" =~ ^[0-9]+$ ]] && cache_time=0
      (( current_time - cache_time > _CACHE_TTL_LOW )) && \
        _ai_tool_update_cache "$_GEMINI_CACHE_FILE" "gemini" "https://registry.npmjs.org/@google/gemini-cli/latest"
    else
      _ai_tool_update_cache "$_GEMINI_CACHE_FILE" "gemini" "https://registry.npmjs.org/@google/gemini-cli/latest"
    fi
    if [[ -n "$installed_version" ]]; then
      local update_ind="" icon="" icon_long=""
      _version_update_type "$installed_version" "$remote_version" && update_ind="%{$fg[red]%}*"
      if (( _PROMPT_EMOJI_MODE )); then
        icon="🔷"
        icon_long="🔷"
      else
        icon="Gm:"
        icon_long="Gemini:"
      fi
      tool_result="%{$FG[$_CLR_GEMINI]%}${icon}${installed_version}${update_ind}%{$reset_color%}"
      tool_result_long="%{$FG[$_CLR_GEMINI]%}${icon_long}${installed_version}${update_ind}%{$reset_color%}"
    fi
  fi
  if [[ -n "$tool_result" ]]; then
    local sep=""
    (( ! _PROMPT_EMOJI_MODE )) && sep="|"
    [[ -n "$ai_status" ]] && ai_status="${ai_status}${sep}"
    [[ -n "$ai_status_long" ]] && ai_status_long="${ai_status_long}${sep}"
    ai_status="${ai_status}${tool_result}"
    ai_status_long="${ai_status_long}${tool_result_long}"
  fi

  # Wrap in brackets if any tools are present
  if [[ -n "$ai_status" ]]; then
    _PP_AI_STATUS="%{$fg[white]%}[${ai_status}%{$fg[white]%}]%{$reset_color%}"
    _PP_AI_STATUS_LONG="%{$fg[white]%}[${ai_status_long}%{$fg[white]%}]%{$reset_color%}"
  else
    _PP_AI_STATUS=""
    _PP_AI_STATUS_LONG=""
  fi
}

# Enhanced PROMPT with all new features:
# - Exit status indicator (✓/OK or ✗N/ERRN)
# - SSH indicator (⚡/SSH)
# - GitHub username badge [Username] (white bg, black text; red if mismatch)
# - Container/Host badge (💻/H or 📦/C)
# - Time with dynamic color
# - Smart path with git-aware coloring and submodule support
# - Git status with extended info (ahead/behind/stash) + special states (rebase/merge/bisect)
# - PR status with CI indicator
# - Background jobs counter (⚙N/JN)
# - Adaptive RPROMPT for system info and AI tools
# - Toggle emoji/plaintext with 'e', help with 'h', refresh with 'u'
#
# Order: [exit][ssh]user@host[GHUser] [container] [time] [path] [git+ext+special][PR+CI] [sysinfo] [AI] [jobs]
# Second line: -> %#
#
# PERFORMANCE: Uses precomputed variables (_PP_*) from precmd to avoid subshells
# All segments are computed once in _precmd_compute_prompt before prompt display
PROMPT='${_PP_EXIT}${_PP_SSH}${_PP_USER_HOST}${_PP_GH_USER}${_PP_BADGE} %B${_PP_TIME}%b ${_PP_PATH} ${_PP_GIT_INFO}${_PP_GIT_EXT}${_PP_GIT_SPECIAL}${_PP_PR}${_PP_SYSINFO_LEFT}${_PP_AI_LEFT}%(1j. %{$fg[yellow]%}${_PP_JOBS}%j%{$reset_color%}.)
%{$fg[blue]%}->%{$fg_bold[blue]%} %#%{$reset_color%} '

# Right prompt: system info and AI tools in SHORT/MIN modes
# Auto-hides when command line is long
RPROMPT='${_PP_RPROMPT}'

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg[green]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY=" %{$fg[red]%}*%{$fg[green]%}"
ZSH_THEME_GIT_PROMPT_CLEAN=""
