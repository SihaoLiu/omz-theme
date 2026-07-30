typeset -g _AI_CANDY_USE_OMZ_ASYNC=0
typeset -g _GIT_TOPOLOGY_GENERATION=0
typeset -g _GIT_TOPOLOGY_GENERATION_VALID=1
typeset -g _GIT_TOPOLOGY_GENERATION_FILE="${_CACHE_DIR}/git_topology_generation"
typeset -g _GIT_METADATA_MAX_BYTES=$((16 * 1024))

function _ai_candy_read_git_metadata_file() {
  emulate -L zsh
  local LC_ALL=C
  local metadata_file="$1"
  local configured_limit="${_GIT_METADATA_MAX_BYTES:-16384}"
  local content=""
  REPLY=""

  if [[ "$configured_limit" != <-> || ${#configured_limit} -gt 5 ]] || \
     (( configured_limit < 1024 || configured_limit > 65536 )); then
    configured_limit=16384
  fi
  [[ -f "$metadata_file" && ! -L "$metadata_file" ]] || return 1
  if (( _HAS_ZSH_STAT_BUILTIN )); then
    local -a metadata
    builtin zstat -A metadata +size -- "$metadata_file" 2>/dev/null || return 1
    [[ "${metadata[1]-}" == <-> ]] || return 1
    (( metadata[1] <= configured_limit )) || return 1
    content="$(<"$metadata_file")"
  else
    local _TIMEOUT_OUTPUT_MAX_BYTES="$configured_limit"
    content=$(_ai_candy_run_local_probe \
      /bin/cat "$metadata_file" 2>/dev/null) || return 1
  fi
  (( ${#content} <= configured_limit )) || return 1
  REPLY="$content"
}

function _ai_candy_read_git_topology_generation() {
  REPLY=0
  if [[ ! -e "$_GIT_TOPOLOGY_GENERATION_FILE" && \
        ! -L "$_GIT_TOPOLOGY_GENERATION_FILE" ]]; then
    return 0
  fi
  [[ -f "$_GIT_TOPOLOGY_GENERATION_FILE" && \
     ! -L "$_GIT_TOPOLOGY_GENERATION_FILE" ]] || return 1
  _ai_candy_cache_read_small_file "$_GIT_TOPOLOGY_GENERATION_FILE" || return 1
  local generation="$REPLY"
  _ai_candy_cache_generation_token_is_valid "$generation" || return 1
  REPLY="$generation"
}

function _ai_candy_apply_git_topology_generation() {
  local generation="$1"
  _ai_candy_cache_generation_token_is_valid "$generation" || return 1
  [[ "$generation" == "$_GIT_TOPOLOGY_GENERATION" ]] && return 0

  _GIT_TOPOLOGY_GENERATION="$generation"
  _MEM_CACHE_GIT_ROOT=()
  _MEM_CACHE_GIT_ROOT_GENERATION=()
  _MEM_CACHE_GIT_HIERARCHY=()
  _GIT_SNAPSHOT_RETRY_AFTER_BY_ROOT=()
  _PP_CACHED_GIT_ROOT=""
  _SMART_PATH_CONTEXT_KEY=""
  _SMART_PATH_CONTEXT_TIMESTAMP=0
}

function _ai_candy_publish_git_topology_generation() {
  local generation="$1"

  (( _CACHE_READY )) || return 1
  _ai_candy_cache_generation_token_is_valid "$generation" || return 1
  if [[ -e "$_GIT_TOPOLOGY_GENERATION_FILE" || \
        -L "$_GIT_TOPOLOGY_GENERATION_FILE" ]]; then
    [[ -f "$_GIT_TOPOLOGY_GENERATION_FILE" && \
       ! -L "$_GIT_TOPOLOGY_GENERATION_FILE" ]] || return 1
  fi
  _ai_candy_cache_atomic_write_unlocked "$_GIT_TOPOLOGY_GENERATION_FILE" \
    "$generation"
}

function _ai_candy_sync_git_topology_generation() {
  (( _CACHE_READY )) || return 1
  if (( ! _GIT_TOPOLOGY_GENERATION_VALID )); then
    _ai_candy_cache_new_generation_token || return 1
    _ai_candy_apply_git_topology_generation "$REPLY"
    if _ai_candy_publish_git_topology_generation "$_GIT_TOPOLOGY_GENERATION"; then
      _GIT_TOPOLOGY_GENERATION_VALID=1
      return 0
    fi
    return 1
  fi
  if _ai_candy_read_git_topology_generation; then
    _GIT_TOPOLOGY_GENERATION_VALID=1
    _ai_candy_apply_git_topology_generation "$REPLY"
    return 0
  fi
  _ai_candy_cache_new_generation_token || return 1
  _ai_candy_apply_git_topology_generation "$REPLY"
  _GIT_TOPOLOGY_GENERATION_VALID=0
  if _ai_candy_publish_git_topology_generation "$_GIT_TOPOLOGY_GENERATION"; then
    _GIT_TOPOLOGY_GENERATION_VALID=1
    return 0
  fi
  return 1
}

function _ai_candy_git_topology_generation_for_path() {
  REPLY="$_GIT_TOPOLOGY_GENERATION"
}

function _ai_candy_record_git_topology_invalidation() {
  local invalidated_path="$1"

  [[ "$invalidated_path" == /* ]] || return 1
  _ai_candy_cache_new_generation_token || return 1
  local next_generation="$REPLY"
  _ai_candy_apply_git_topology_generation "$next_generation"
  if _ai_candy_publish_git_topology_generation "$next_generation"; then
    _GIT_TOPOLOGY_GENERATION_VALID=1
  else
    _GIT_TOPOLOGY_GENERATION_VALID=0
  fi
  return 0
}

function _ai_candy_git_root_cache_requires_refresh() {
  local path_value="$1"
  local cached_root="$2"
  local validated_generation="${3:-0}"

  _ai_candy_cache_generation_token_is_valid "$validated_generation" || \
    validated_generation=0
  [[ "$_GIT_TOPOLOGY_GENERATION" != "$validated_generation" ]] && return 0
  if [[ "$cached_root" == "NOT_GIT" ]]; then
    [[ -e "${path_value}/.git" ]]
    return $?
  fi
  [[ ! -e "${cached_root}/.git" ]]
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
  local current_time=${EPOCHSECONDS}
  REPLY=""

  # Check memory cache first (fastest, no I/O)
  if [[ -n "${_MEM_CACHE_GIT_ROOT[$current_dir]-}" ]]; then
    local cached="${_MEM_CACHE_GIT_ROOT[$current_dir]}"
    local cached_root="${cached%|*}"
    local cache_time="${cached##*|}"
    local validated_generation="${_MEM_CACHE_GIT_ROOT_GENERATION[$current_dir]-0}"
    if _ai_candy_git_root_cache_requires_refresh "$current_dir" "$cached_root" \
         "$validated_generation"; then
      _ai_candy_mem_cache_remove_key git_root "$current_dir"
    elif _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_CACHE_TTL_MEDIUM" "$current_time"; then
      REPLY="$cached_root"
      return 0
    fi
  fi

  # Check persistent cache (SQLite or file)
  local cached_line=""
  local persistent_key="${_GIT_TOPOLOGY_GENERATION}:${current_dir}"
  if (( topology_persistence )) && _ai_candy_cache_get "git_root" "$persistent_key"; then
    cached_line="$REPLY"
    # Format: value|timestamp (from _ai_candy_cache_get)
    local cache_time="${cached_line##*|}"
    local cached_root="${cached_line%|*}"

    if _ai_candy_git_root_cache_requires_refresh "$current_dir" "$cached_root" \
         "$_GIT_TOPOLOGY_GENERATION"; then
      _ai_candy_cache_delete_key "git_root" "$persistent_key" >/dev/null 2>&1
    elif _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_CACHE_TTL_MEDIUM" "$current_time"; then
      # Update memory cache from persistent cache
      _MEM_CACHE_GIT_ROOT[$current_dir]="${cached_root}|${cache_time}"
      _MEM_CACHE_GIT_ROOT_GENERATION[$current_dir]="$_GIT_TOPOLOGY_GENERATION"
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
    if _ai_candy_path_has_git_metadata_context "$current_dir"; then
      REPLY="NOT_GIT"
      return 0
    fi
    git_root="NOT_GIT"
  fi

  # Update both caches
  _MEM_CACHE_GIT_ROOT[$current_dir]="${git_root}|${current_time}"
  _MEM_CACHE_GIT_ROOT_GENERATION[$current_dir]="$_GIT_TOPOLOGY_GENERATION"
  if (( topology_persistence )); then
    _ai_candy_cache_set "git_root" "$persistent_key" "$git_root" "$current_time" \
      "$current_dir"
  fi

  # Cleanup memory cache if it grows too large
  (( ${#_MEM_CACHE_GIT_ROOT} > _MEM_CACHE_CLEANUP_THRESHOLD )) && _ai_candy_mem_cache_cleanup "git_root"

  REPLY="$git_root"
}

# Path background colors defined in COLOR CONSTANTS section at file top

function _ai_candy_logicalize_path_from_pwd() {
  local physical_path="$1"
  local logical_pwd="${2:-$PWD}"
  local physical_pwd="${3:-$(builtin pwd -P 2>/dev/null)}"

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
  integer topology_persistence=1
  _ai_candy_sync_git_topology_generation || topology_persistence=0
  local current_time=${EPOCHSECONDS}
  local cache_key="${_GIT_HIERARCHY_CACHE_VERSION:-1}:${_GIT_TOPOLOGY_GENERATION}:$PWD"
  local logical_pwd="$PWD"
  local physical_pwd="$(builtin pwd -P 2>/dev/null)"
  REPLY=""

  # Check memory cache first (fastest, no I/O)
  if [[ -n "${_MEM_CACHE_GIT_HIERARCHY[$cache_key]-}" ]]; then
    local cached="${_MEM_CACHE_GIT_HIERARCHY[$cache_key]}"
    local cache_time="${cached##*|}"
    local cached_result="${cached%|*}"
    if _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_CACHE_TTL_MEDIUM" "$current_time"; then
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

    if _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_CACHE_TTL_MEDIUM" "$current_time"; then
      # Update memory cache from persistent cache
      _MEM_CACHE_GIT_HIERARCHY[$cache_key]="${cached_result}|${cache_time}"
      REPLY="$cached_result"
      return 0
    fi
  fi

  # Build hierarchy from innermost to outermost
  local hierarchy=()
  local depth=0
  local max_depth=${_GIT_HIERARCHY_MAX_DEPTH:-20}
  local git_root="${_PP_CACHED_GIT_ROOT:-}"
  if [[ -z "$git_root" || "$git_root" == "NOT_GIT" ]]; then
    git_root=$(builtin cd "$PWD" 2>/dev/null && _ai_candy_run_local_probe git rev-parse --show-toplevel 2>/dev/null)
  fi

  while [[ -n "$git_root" ]]; do
    (( depth >= max_depth )) && break
    (( depth++ ))

    local display_git_root=$(_ai_candy_logicalize_path_from_pwd "$git_root" "$logical_pwd" "$physical_pwd")
    hierarchy=("$display_git_root" "${hierarchy[@]}")  # prepend (outermost first)

    # Check for superproject
    local superproject=$(builtin cd "$git_root" 2>/dev/null && _ai_candy_run_local_probe git rev-parse --show-superproject-working-tree 2>/dev/null)
    [[ -z "$superproject" || "$superproject" == "$git_root" ]] && break

    git_root="$superproject"
  done

  # Build result: repo1<sep>repo2<sep>...<sep>subdir
  local result=""
  local sep="${_GIT_HIERARCHY_SEP:-:}"
  local IFS="$sep"
  if (( ${#hierarchy[@]} > 0 )); then
    local innermost="${hierarchy[-1]}"
    local current_subdir=""
    [[ "$PWD" != "$innermost" ]] && current_subdir="${PWD#$innermost/}"

    # The internal separator is a control byte that POSIX filenames can still
    # contain. Neutralize it before serializing display-only path components.
    local component
    local -a serialized_hierarchy=()
    for component in "${hierarchy[@]}"; do
      serialized_hierarchy+=("${component//${_GIT_HIERARCHY_SEP}/?}")
    done
    current_subdir="${current_subdir//${_GIT_HIERARCHY_SEP}/?}"
    result="${serialized_hierarchy[*]}${sep}${current_subdir}"
  fi

  # Cache result in both memory and persistent cache
  _MEM_CACHE_GIT_HIERARCHY[$cache_key]="${result}|${current_time}"
  (( topology_persistence )) && \
    _ai_candy_cache_set "git_hierarchy" "$cache_key" "$result" "$current_time"

  # Cleanup memory cache if it grows too large
  (( ${#_MEM_CACHE_GIT_HIERARCHY} > _MEM_CACHE_CLEANUP_THRESHOLD )) && _ai_candy_mem_cache_cleanup "git_hierarchy"

  REPLY="$result"
}

# ============================================================================
# DIRECT ASSIGNMENT FUNCTIONS - Avoid subshells by writing to global variables
# ============================================================================

# A single porcelain-v2 snapshot owns all frequently changing Git facts.
typeset -g _GIT_SNAPSHOT_RENDER_ID=-1
typeset -g _GIT_SNAPSHOT_ROOT=""
typeset -g _GIT_SNAPSHOT_VALID=0
typeset -g _GIT_SNAPSHOT_STATUS_COMPLETE=0
typeset -g _GIT_SNAPSHOT_BRANCH=""
typeset -g _GIT_SNAPSHOT_UPSTREAM=""
typeset -g _GIT_SNAPSHOT_OID=""
typeset -g _GIT_SNAPSHOT_TAG=""
typeset -g _GIT_SNAPSHOT_DIRTY=0
typeset -g _GIT_SNAPSHOT_AHEAD=0
typeset -g _GIT_SNAPSHOT_BEHIND=0
typeset -g _GIT_SNAPSHOT_STASH=0
typeset -g _GIT_HIDE_INFO=0
typeset -g _GIT_HIDE_DIRTY=0
typeset -g _GIT_CONFIG_CACHE_TTL=5
typeset -gA _GIT_OMZ_OPTIONS_BY_ROOT
typeset -g _GIT_SNAPSHOT_FAILURE_RETRY_TTL=3
typeset -gA _GIT_SNAPSHOT_RETRY_AFTER_BY_ROOT

function _ai_candy_reset_git_snapshot() {
  _GIT_SNAPSHOT_VALID=0
  _GIT_SNAPSHOT_STATUS_COMPLETE=0
  _GIT_SNAPSHOT_BRANCH=""
  _GIT_SNAPSHOT_UPSTREAM=""
  _GIT_SNAPSHOT_OID=""
  _GIT_SNAPSHOT_TAG=""
  _GIT_SNAPSHOT_DIRTY=0
  _GIT_SNAPSHOT_AHEAD=0
  _GIT_SNAPSHOT_BEHIND=0
  _GIT_SNAPSHOT_STASH=0
}

function _ai_candy_load_git_head_snapshot() {
  local git_root="$1"
  local git_dir="" head_contents=""

  _ai_candy_resolve_git_dir "$git_root" || return 1
  git_dir="$REPLY"
  _ai_candy_read_git_metadata_file "${git_dir}/HEAD" || return 1
  head_contents="$REPLY"
  if [[ "$head_contents" == "ref: refs/heads/"* ]]; then
    _GIT_SNAPSHOT_BRANCH="${head_contents#ref: refs/heads/}"
    [[ -n "$_GIT_SNAPSHOT_BRANCH" ]] || return 1
  elif (( ${#head_contents} == 40 || ${#head_contents} == 64 )) && \
       [[ -z "${head_contents//[0-9A-Fa-f]/}" ]]; then
    _GIT_SNAPSHOT_BRANCH="(detached)"
    _GIT_SNAPSHOT_OID="$head_contents"
  else
    return 1
  fi
  _GIT_SNAPSHOT_VALID=1
}

function _ai_candy_load_git_display_options() {
  local git_root="$1"
  local cached="${_GIT_OMZ_OPTIONS_BY_ROOT[$git_root]-}"
  local current_time="${EPOCHSECONDS}"
  local hide_info=0 hide_dirty=0
  integer cache_is_fresh=0

  if [[ -n "$cached" ]]; then
    local cache_time="${cached##*|}"
    local cached_options="${cached%|*}"
    if _ai_candy_cache_timestamp_is_fresh "$cache_time" \
         "$_GIT_CONFIG_CACHE_TTL" "$current_time"; then
      hide_info="${cached_options%%|*}"
      hide_dirty="${cached_options##*|}"
      cache_is_fresh=1
    fi
  fi

  if (( ! cache_is_fresh )); then
    local config_output="" line
    config_output=$(_ai_candy_run_local_probe git -C "$git_root" config --get-regexp \
      '^oh-my-zsh\.(hide-info|hide-dirty)$' 2>/dev/null) || config_output=""
    for line in "${(@f)config_output}"; do
      [[ "$line" == 'oh-my-zsh.hide-info 1' ]] && hide_info=1
      [[ "$line" == 'oh-my-zsh.hide-dirty 1' ]] && hide_dirty=1
    done
    _GIT_OMZ_OPTIONS_BY_ROOT[$git_root]="${hide_info}|${hide_dirty}|${current_time}"
    (( ${#_GIT_OMZ_OPTIONS_BY_ROOT} > _MEM_CACHE_CLEANUP_THRESHOLD )) && \
      _ai_candy_mem_cache_cleanup git_options
  fi

  _GIT_HIDE_INFO="$hide_info"
  _GIT_HIDE_DIRTY="$hide_dirty"
}

function _ai_candy_collect_git_snapshot() {
  local current_id="${_PROMPT_RENDER_ID:-0}"
  local git_root="${_PP_CACHED_GIT_ROOT:-NOT_GIT}"
  if [[ "$_GIT_SNAPSHOT_RENDER_ID" == "$current_id" && \
        "$_GIT_SNAPSHOT_ROOT" == "$git_root" ]]; then
    return 0
  fi

  _GIT_SNAPSHOT_RENDER_ID="$current_id"
  _GIT_SNAPSHOT_ROOT="$git_root"
  _ai_candy_reset_git_snapshot
  [[ -n "$git_root" && "$git_root" != "NOT_GIT" ]] || return 0
  _ai_candy_load_git_display_options "$git_root"

  local current_time="${EPOCHSECONDS}"
  local retry_after="${_GIT_SNAPSHOT_RETRY_AFTER_BY_ROOT[$git_root]-0}"
  if [[ "$retry_after" == <-> ]] && (( current_time < retry_after )); then
    _ai_candy_load_git_head_snapshot "$git_root"
    return $?
  fi

  local -a status_args
  status_args=(status --porcelain=v2 --branch --show-stash)
  [[ "${DISABLE_UNTRACKED_FILES_DIRTY:-}" == "true" ]] && status_args+=(--untracked-files=no)
  if [[ "${GIT_STATUS_IGNORE_SUBMODULES:-}" != "git" ]]; then
    status_args+=("--ignore-submodules=${GIT_STATUS_IGNORE_SUBMODULES:-dirty}")
  fi

  local snapshot=""
  local command_status=0
  snapshot=$(GIT_OPTIONAL_LOCKS=0 _ai_candy_run_local_probe git "${status_args[@]}" 2>/dev/null) || command_status=$?
  if (( command_status != 0 )); then
    local retry_ttl="${_GIT_SNAPSHOT_FAILURE_RETRY_TTL:-3}"
    if [[ "$retry_ttl" != <-> ]] || (( retry_ttl < 1 || retry_ttl > 30 )); then
      retry_ttl=3
    fi
    _GIT_SNAPSHOT_RETRY_AFTER_BY_ROOT[$git_root]=$(( current_time + retry_ttl ))
    (( ${#_GIT_SNAPSHOT_RETRY_AFTER_BY_ROOT} > \
       _MEM_CACHE_CLEANUP_THRESHOLD )) && \
      _ai_candy_mem_cache_cleanup git_snapshot_retry
    _ai_candy_load_git_head_snapshot "$git_root"
    return $?
  fi
  _ai_candy_mem_cache_remove_key git_snapshot_retry "$git_root"

  local line prefix rest
  for line in "${(@f)snapshot}"; do
    case "$line" in
      '# branch.oid '*)
        prefix='# branch.oid '
        _GIT_SNAPSHOT_OID="${line#$prefix}"
        ;;
      '# branch.head '*)
        prefix='# branch.head '
        _GIT_SNAPSHOT_BRANCH="${line#$prefix}"
        ;;
      '# branch.upstream '*)
        prefix='# branch.upstream '
        _GIT_SNAPSHOT_UPSTREAM="${line#$prefix}"
        ;;
      '# branch.ab +'*)
        prefix='# branch.ab +'
        rest="${line#$prefix}"
        _GIT_SNAPSHOT_AHEAD="${rest%% *}"
        _GIT_SNAPSHOT_BEHIND="${rest##* -}"
        ;;
      '# stash '*)
        prefix='# stash '
        _GIT_SNAPSHOT_STASH="${line#$prefix}"
        ;;
      '# '*) ;;
      ?*) _GIT_SNAPSHOT_DIRTY=1 ;;
    esac
  done

  [[ "$_GIT_SNAPSHOT_AHEAD" == <-> ]] || _GIT_SNAPSHOT_AHEAD=0
  [[ "$_GIT_SNAPSHOT_BEHIND" == <-> ]] || _GIT_SNAPSHOT_BEHIND=0
  [[ "$_GIT_SNAPSHOT_STASH" == <-> ]] || _GIT_SNAPSHOT_STASH=0
  if [[ "$_GIT_SNAPSHOT_BRANCH" == "(detached)" ]]; then
    _GIT_SNAPSHOT_TAG=$(_ai_candy_run_local_probe git describe --tags --exact-match HEAD 2>/dev/null) || \
      _GIT_SNAPSHOT_TAG=""
  fi
  _GIT_SNAPSHOT_STATUS_COMPLETE=1
  _GIT_SNAPSHOT_VALID=1
}

typeset -g _GIT_FORMATTED_INFO=""
typeset -g _GIT_FORMATTED_EXT=""

function _ai_candy_format_git_snapshot() {
  _GIT_FORMATTED_INFO=""
  _GIT_FORMATTED_EXT=""
  (( _GIT_SNAPSHOT_VALID )) || return 0

  local branch="$_GIT_SNAPSHOT_BRANCH"
  if [[ "$branch" == "(detached)" ]]; then
    branch="${_GIT_SNAPSHOT_TAG:-${_GIT_SNAPSHOT_OID[1,7]}}"
  fi
  _ai_candy_prompt_escape_text "$branch"
  branch="$REPLY"

  local upstream=""
  if (( ${+ZSH_THEME_GIT_SHOW_UPSTREAM} )) && [[ -n "$_GIT_SNAPSHOT_UPSTREAM" ]]; then
    _ai_candy_prompt_escape_text "$_GIT_SNAPSHOT_UPSTREAM"
    upstream=" -> ${REPLY}"
  fi
  local dirty=""
  if (( _GIT_SNAPSHOT_STATUS_COMPLETE )); then
    dirty="${ZSH_THEME_GIT_PROMPT_CLEAN:-}"
    (( _GIT_SNAPSHOT_DIRTY && ! _GIT_HIDE_DIRTY )) && \
      dirty="${ZSH_THEME_GIT_PROMPT_DIRTY:-}"
  fi
  if (( ! _GIT_HIDE_INFO )); then
    _GIT_FORMATTED_INFO="${ZSH_THEME_GIT_PROMPT_PREFIX:-}${branch}${upstream}${dirty}${ZSH_THEME_GIT_PROMPT_SUFFIX:-}"
  fi

  if (( _GIT_SNAPSHOT_AHEAD > 0 )); then
    if (( _PROMPT_EMOJI_MODE )); then
      _GIT_FORMATTED_EXT+="%{$fg[green]%}${_SYM_UP}${_GIT_SNAPSHOT_AHEAD}%{$reset_color%}"
    else
      _GIT_FORMATTED_EXT+="%{$fg[green]%}+${_GIT_SNAPSHOT_AHEAD}%{$reset_color%}"
    fi
  fi
  if (( _GIT_SNAPSHOT_BEHIND > 0 )); then
    if (( _PROMPT_EMOJI_MODE )); then
      _GIT_FORMATTED_EXT+="%{$fg[red]%}${_SYM_DOWN}${_GIT_SNAPSHOT_BEHIND}%{$reset_color%}"
    else
      _GIT_FORMATTED_EXT+="%{$fg[red]%}-${_GIT_SNAPSHOT_BEHIND}%{$reset_color%}"
    fi
  fi
  if (( _GIT_SNAPSHOT_STASH > 0 )); then
    if (( _PROMPT_EMOJI_MODE )); then
      _GIT_FORMATTED_EXT+="%{$fg[yellow]%}${_SYM_STASH}${_GIT_SNAPSHOT_STASH}%{$reset_color%}"
    else
      _GIT_FORMATTED_EXT+="%{$fg[yellow]%}S${_GIT_SNAPSHOT_STASH}%{$reset_color%}"
    fi
  fi
}

function _ai_candy_compute_git_info_direct() {
  if (( _AI_CANDY_USE_OMZ_ASYNC )); then
    local async_output="${_OMZ_ASYNC_OUTPUT[_ai_candy_git_prompt_async]-}"
    _PP_GIT_INFO="${async_output# }"
    _PP_GIT_EXT=""
    return 0
  fi

  _ai_candy_collect_git_snapshot
  _ai_candy_format_git_snapshot
  _PP_GIT_INFO="$_GIT_FORMATTED_INFO"
}

function _ai_candy_compute_git_extended_direct() {
  (( _AI_CANDY_USE_OMZ_ASYNC )) && return 0
  _ai_candy_collect_git_snapshot
  _ai_candy_format_git_snapshot
  _PP_GIT_EXT="$_GIT_FORMATTED_EXT"
}

function _ai_candy_resolve_git_dir() {
  local git_root="$1"
  local git_dir="${git_root}/.git"
  REPLY=""

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
    git_dir="${git_dir:A}"
  fi

  [[ -d "$git_dir" ]] || return 1
  REPLY="$git_dir"
}

# Direct-assignment version of _git_special_state_cached
# PERFORMANCE: Sets _PP_GIT_SPECIAL directly (0 subshells)
# Uses _PP_CACHED_GIT_ROOT set in _ai_candy_precmd_compute_prompt
function _ai_candy_compute_git_special_direct() {
  local current_id="$_PROMPT_RENDER_ID"
  if [[ "$_PROMPT_GIT_SPECIAL_CACHE_ID" == "$current_id" ]]; then
    _PP_GIT_SPECIAL="$_PROMPT_GIT_SPECIAL_CACHE"
    return
  fi

  _PP_GIT_SPECIAL=""
  [[ "$_PP_CACHED_GIT_ROOT" == "NOT_GIT" ]] && return

  _ai_candy_resolve_git_dir "$_PP_CACHED_GIT_ROOT" || return 0
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

    if (( _PROMPT_EMOJI_MODE )); then
      case "$state" in
        rebase*|am*) icon="$_SYM_BRANCH"; color="%{$fg[yellow]%}" ;;
        merge)       icon="$_SYM_BRANCH"; color="%{$fg[cyan]%}" ;;
        cherry)      icon="$_SYM_CHERRY"; color="%{$fg[red]%}" ;;
        revert)      icon="$_SYM_REWIND"; color="%{$fg[magenta]%}" ;;
        bisect)      icon="$_SYM_SEARCH"; color="%{$fg[blue]%}" ;;
        detached)    icon="$_SYM_PLUG"; color="%{$fg[red]%}" ;;
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
# Uses three-tier caching: per-prompt -> memory -> persistent (SQLite/file)
function _ai_candy_compute_pr_status_direct() {
  local current_id="$_PROMPT_RENDER_ID"
  if [[ "$_PROMPT_GH_PR_CACHE_ID" == "$current_id" ]]; then
    _PP_PR="$_PROMPT_GH_PR_CACHE"
    return
  fi

  _PP_PR=""

  # Skip if network mode is disabled
  (( _PROMPT_NETWORK_MODE )) || return

  # Skip if no hash command available (needed for cache key generation)
  (( _HAS_HASH_CMD )) || return

  # Check if gh command exists
  (( _HAS_GH )) || return

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
  if [[ -n "${_MEM_CACHE_GH_PR[$cache_key]-}" ]]; then
    local cached="${_MEM_CACHE_GH_PR[$cache_key]}"
    cache_time="${cached##*|}"
    local rest="${cached%|*}"
    ci_status="${rest##*|}"
    pr_number="${rest%|*}"
    if _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_CACHE_TTL_HIGH" "$current_time"; then
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
        _MEM_CACHE_GH_PR[$cache_key]="${pr_number}|${ci_status}|${cache_time}"
        # Cleanup memory cache if it grows too large
        (( ${#_MEM_CACHE_GH_PR} > _MEM_CACHE_CLEANUP_THRESHOLD )) && _ai_candy_mem_cache_cleanup "gh_pr"
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
  _ai_candy_cache_timestamp_is_fresh "$cache_time" "$_CACHE_TTL_HIGH" "$current_time" || \
    _ai_candy_gh_pr_update_cache "$remote_key" "$branch"

  # Display PR if valid
  if [[ -n "$pr_number" && "$pr_number" != "-1" ]]; then
    local ci_indicator=""
    case "$ci_status" in
      pass)
        (( _PROMPT_EMOJI_MODE )) && ci_indicator="%{$fg[green]%}${_SYM_CHECK}" || ci_indicator="%{$fg[green]%}OK"
        ;;
      fail)
        (( _PROMPT_EMOJI_MODE )) && ci_indicator="%{$fg[red]%}${_SYM_CROSS}" || ci_indicator="%{$fg[red]%}X"
        ;;
      pending)
        (( _PROMPT_EMOJI_MODE )) && ci_indicator="%{$fg[yellow]%}${_SYM_PENDING}" || ci_indicator="%{$fg[yellow]%}..."
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

typeset -g _SMART_PATH_CONTEXT_KEY=""
typeset -g _SMART_PATH_CONTEXT_TIMESTAMP=0
typeset -g _SMART_PATH_FALLBACK=""
typeset -g _SMART_PATH_NUM_REPOS=0
typeset -g _SMART_PATH_TOTAL_LENGTH=0
typeset -g _SMART_PATH_SEPARATOR="/"
typeset -ga _SMART_PATH_SEGMENTS
typeset -ga _SMART_PATH_SEGMENT_LENGTHS
typeset -g _SMART_PATH_RENDER_KEY=""
typeset -g _SMART_PATH_RENDER_VALUE=""

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

function _ai_candy_prepare_smart_path_context() {
  local current_time="$EPOCHSECONDS"
  local home_value="${HOME:-}"
  local git_root_value="${_PP_CACHED_GIT_ROOT:-NOT_GIT}"
  local context_key="${#PWD}:${PWD}|${#home_value}:${home_value}|${#git_root_value}:${git_root_value}|${_PROMPT_PATH_SEP_MODE}|${_GIT_HIERARCHY_CACHE_VERSION}"
  if [[ "$_SMART_PATH_CONTEXT_KEY" == "$context_key" ]] && \
     _ai_candy_cache_timestamp_is_fresh "$_SMART_PATH_CONTEXT_TIMESTAMP" \
       "$_CACHE_TTL_MEDIUM" "$current_time"; then
    return 0
  fi

  _SMART_PATH_RENDER_KEY=""
  _SMART_PATH_RENDER_VALUE=""
  _SMART_PATH_CONTEXT_KEY="$context_key"
  _SMART_PATH_CONTEXT_TIMESTAMP="$current_time"
  _SMART_PATH_FALLBACK=""
  _SMART_PATH_NUM_REPOS=0
  _SMART_PATH_TOTAL_LENGTH=0
  _SMART_PATH_SEPARATOR="/"
  _SMART_PATH_SEGMENTS=()
  _SMART_PATH_SEGMENT_LENGTHS=()

  _ai_candy_abbreviate_home_path "$PWD"
  local full_path="$REPLY"
  if [[ "$_PP_CACHED_GIT_ROOT" == "NOT_GIT" ]]; then
    _SMART_PATH_FALLBACK="$full_path"
    _ai_candy_prompt_text_width "$full_path"
    _SMART_PATH_TOTAL_LENGTH=$(( REPLY + 2 ))
    return 0
  fi

  _ai_candy_get_git_hierarchy
  local hierarchy_str="$REPLY"
  if [[ -z "$hierarchy_str" ]]; then
    _SMART_PATH_FALLBACK="$full_path"
    _ai_candy_prompt_text_width "$full_path"
    _SMART_PATH_TOTAL_LENGTH=$(( REPLY + 2 ))
    return 0
  fi

  local hierarchy_separator="${_GIT_HIERARCHY_SEP:-:}"
  local -a parts repos
  parts=("${(@ps.$hierarchy_separator.)hierarchy_str}")
  local subdir=""
  integer num_parts=${#parts}
  if (( num_parts > 0 )); then
    subdir="${parts[-1]}"
    repos=("${parts[@]:0:$(( num_parts - 1 ))}")
  fi

  _SMART_PATH_NUM_REPOS=${#repos}
  local repo parent display_path segment
  integer index total_length=2 has_space=0
  for (( index=1; index<=_SMART_PATH_NUM_REPOS; index++ )); do
    repo="${repos[index]}"
    if (( index == 1 )); then
      _ai_candy_abbreviate_home_path "$repo"
      display_path="$REPLY"
    else
      parent="${repos[index-1]}"
      display_path="${repo#$parent/}"
    fi
    _SMART_PATH_SEGMENTS+=("$display_path")
    _ai_candy_prompt_text_width "$display_path"
    _SMART_PATH_SEGMENT_LENGTHS+=("$REPLY")
  done
  if [[ -n "$subdir" ]]; then
    _SMART_PATH_SEGMENTS+=("$subdir")
    _ai_candy_prompt_text_width "$subdir"
    _SMART_PATH_SEGMENT_LENGTHS+=("$REPLY")
  fi

  for index in "${_SMART_PATH_SEGMENT_LENGTHS[@]}"; do
    (( total_length += index ))
  done
  (( ${#_SMART_PATH_SEGMENTS} > 1 )) && (( total_length += ${#_SMART_PATH_SEGMENTS} - 1 ))
  _SMART_PATH_TOTAL_LENGTH="$total_length"

  [[ "$PWD" == *" "* ]] && has_space=1
  if (( ! has_space )); then
    for segment in "${_SMART_PATH_SEGMENTS[@]}"; do
      if [[ "$segment" == *" "* ]]; then
        has_space=1
        break
      fi
    done
  fi
  (( _PROMPT_PATH_SEP_MODE && ! has_space )) && _SMART_PATH_SEPARATOR=" "
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
  _PP_PATH="%{$fg[white]%}[${REPLY}]%{$reset_color%}"
}

function _ai_candy_compute_smart_path_direct() {
  local use_short="${1:-full}"
  integer requested_width="${2:-0}"
  _ai_candy_prepare_smart_path_context

  local prompt_bang="${options[promptbang]}"
  local render_key="${#use_short}:${use_short}|${requested_width}|${prompt_bang}|${_SMART_PATH_CONTEXT_TIMESTAMP}|${#_SMART_PATH_CONTEXT_KEY}:${_SMART_PATH_CONTEXT_KEY}"
  if [[ "$_SMART_PATH_RENDER_KEY" == "$render_key" ]]; then
    _PP_PATH="$_SMART_PATH_RENDER_VALUE"
    return 0
  fi

  integer total_length=$_SMART_PATH_TOTAL_LENGTH
  integer target_width=0
  if [[ "$use_short" == "short" ]]; then
    if (( requested_width > 0 )); then
      target_width=$requested_width
    else
      target_width=${_PATH_TARGET_WIDTH_SHORT:-40}
    fi
  elif (( requested_width > 0 && total_length > requested_width )); then
    target_width=$requested_width
  fi

  if [[ -n "$_SMART_PATH_FALLBACK" ]]; then
    _ai_candy_render_plain_smart_path "$_SMART_PATH_FALLBACK" "$target_width"
    _SMART_PATH_RENDER_KEY="$render_key"
    _SMART_PATH_RENDER_VALUE="$_PP_PATH"
    return 0
  fi

  local -a segments=("${_SMART_PATH_SEGMENTS[@]}")
  local -a segment_lengths=("${_SMART_PATH_SEGMENT_LENGTHS[@]}")
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
    _SMART_PATH_RENDER_KEY="$render_key"
    _SMART_PATH_RENDER_VALUE="$_PP_PATH"
    return 0
  fi

  local ESC=$'\e'
  local result="["
  local output_separator=""
  local segment bg_num
  integer index level
  if (( start_index > 1 )); then
    result+="%{$FG[$_CLR_TRUNCATED]%}..%{$reset_color%}${_SMART_PATH_SEPARATOR}"
  fi

  for (( index=start_index; index<=total_segments; index++ )); do
    _ai_candy_prompt_escape_text "${segments[index]}"
    segment="$REPLY"
    if (( index <= _SMART_PATH_NUM_REPOS )); then
      level=$(( index - start_index ))
      (( level >= ${#_PATH_BG_COLORS} )) && level=$(( ${#_PATH_BG_COLORS} - 1 ))
      bg_num="${_PATH_BG_COLORS[level+1]}"
      result+="${output_separator}%{${ESC}[48;5;${bg_num}m${ESC}[38;5;16m%}${segment}%{$reset_color%}"
    else
      result+="${output_separator}%{$fg[white]%}${segment}%{$reset_color%}"
    fi
    output_separator="$_SMART_PATH_SEPARATOR"
  done

  _PP_PATH="${result}]"
  _SMART_PATH_RENDER_KEY="$render_key"
  _SMART_PATH_RENDER_VALUE="$_PP_PATH"
}

# Optional-tool version status for the prompt
# Uses cache to avoid network requests on every prompt
# Shared across all terminals for better efficiency (uses _CACHE_TTL_LOW)
# (Cache file paths defined in CACHE FILE PATHS section)

# Git remote hashes are stable for a repository and remain in session memory.
typeset -gA _GIT_REMOTE_KEY_BY_ROOT
typeset -g _GIT_REMOTE_BRANCH_CACHE=""
typeset -g _GIT_REMOTE_BRANCH_CACHE_ID=-1

# Hash sensitive strings (e.g., remote URLs) for cache keys.
# Args: $1=input string
# Returns: hash string
# PERFORMANCE: Uses _HASH_CMD detected at load time (no repeated command -v calls)
# NOTE: Caller must check _HAS_HASH_CMD before calling this function
function _ai_candy_hash_string() {
  local input="$1"
  local hash=""

  case "${_HASH_CMD:t}" in
    sha256sum)
      hash=$(builtin print -rn -- "$input" | \
        _ai_candy_run_local_probe "$_HASH_CMD" 2>/dev/null) || hash=""
      hash="${hash%% *}"
      ;;
    shasum)
      hash=$(builtin print -rn -- "$input" | \
        _ai_candy_run_local_probe "$_HASH_CMD" -a 256 2>/dev/null) || hash=""
      hash="${hash%% *}"
      ;;
    openssl)
      hash=$(builtin print -rn -- "$input" | \
        _ai_candy_run_local_probe "$_HASH_CMD" dgst -sha256 2>/dev/null) || hash=""
      hash="${hash##* }"
      ;;
  esac

  [[ ${#hash} -eq 64 && "$hash" != *[^0-9A-Fa-f]* ]] || hash=""

  REPLY="${(L)hash}"
}

# Get cached git remote key and branch (per-prompt cache)
# Returns: remote_key|branch or empty if not in git repo
# Uses _PP_CACHED_GIT_ROOT set in _ai_candy_precmd_compute_prompt
function _ai_candy_get_cached_git_remote_branch() {
  local current_id="$_PROMPT_RENDER_ID"
  if [[ "$_GIT_REMOTE_BRANCH_CACHE_ID" == "$current_id" ]]; then
    REPLY="$_GIT_REMOTE_BRANCH_CACHE"
    return 0
  fi

  if [[ "$_PP_CACHED_GIT_ROOT" == "NOT_GIT" ]]; then
    _GIT_REMOTE_BRANCH_CACHE=""
    _GIT_REMOTE_BRANCH_CACHE_ID="$current_id"
    REPLY=""
    return 0
  fi

  local git_root="$_PP_CACHED_GIT_ROOT"
  local remote_key=""
  local current_time="${EPOCHSECONDS}"
  local cached_remote="${_GIT_REMOTE_KEY_BY_ROOT[$git_root]-}"
  integer cache_is_fresh=0
  if [[ -n "$cached_remote" ]]; then
    local cache_time="${cached_remote##*|}"
    local cached_key="${cached_remote%|*}"
    if _ai_candy_cache_timestamp_is_fresh "$cache_time" \
         "$_GIT_CONFIG_CACHE_TTL" "$current_time"; then
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
    _GIT_REMOTE_KEY_BY_ROOT[$git_root]="${remote_key:--}|${current_time}"
    (( ${#_GIT_REMOTE_KEY_BY_ROOT} > _MEM_CACHE_CLEANUP_THRESHOLD )) && \
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
    _GIT_REMOTE_BRANCH_CACHE="${remote_key}|${branch}"
  else
    _GIT_REMOTE_BRANCH_CACHE=""
  fi
  _GIT_REMOTE_BRANCH_CACHE_ID="$current_id"
  REPLY="$_GIT_REMOTE_BRANCH_CACHE"
}

function _ai_candy_git_prompt_async() {
  emulate -L zsh
  setopt localoptions noerrexit noerrreturn
  local _CACHE_SCHEDULE_PERSISTENCE=0

  _ai_candy_get_cached_git_root
  _PP_CACHED_GIT_ROOT="$REPLY"
  _GIT_SNAPSHOT_RENDER_ID=-1
  _ai_candy_collect_git_snapshot || return 0
  _ai_candy_format_git_snapshot
  if [[ -n "${_GIT_FORMATTED_INFO}${_GIT_FORMATTED_EXT}" ]]; then
    builtin print -rn -- " ${_GIT_FORMATTED_INFO}${_GIT_FORMATTED_EXT}"
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
