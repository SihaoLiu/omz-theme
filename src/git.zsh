typeset -g _AI_CANDY_USE_OMZ_ASYNC=0
typeset -g _AI_CANDY_GIT_TOPOLOGY_GENERATION=0
typeset -g _AI_CANDY_GIT_TOPOLOGY_GENERATION_VALID=1
typeset -g _AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE="${_AI_CANDY_CACHE_DIR}/git_topology_generation"
typeset -g _AI_CANDY_GIT_METADATA_MAX_BYTES=$((16 * 1024))
typeset -gi _AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE=1
typeset -gi _AI_CANDY_GIT_METADATA_CONTEXT_PERSISTABLE=1
typeset -gi _AI_CANDY_GIT_METADATA_PROBE_FAILED=0
typeset -g _AI_CANDY_GIT_METADATA_ROOT_HINT=""
typeset -gi _AI_CANDY_GIT_ROOT_IS_FALLBACK=0
typeset -gi _AI_CANDY_GIT_VOLATILE_CONFIG_SEQUENCE
typeset -gA _AI_CANDY_GIT_VOLATILE_CONFIG_CONTENT_BY_PATH
typeset -gA _AI_CANDY_GIT_VOLATILE_CONFIG_GENERATION_BY_PATH
typeset -gA _AI_CANDY_GIT_VOLATILE_CONFIG_STAT_BY_PATH
typeset -gA _AI_CANDY_GIT_VOLATILE_CONFIG_STABLE_BY_PATH
typeset -gA _AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT
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
  _AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT=()
  _AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT=()
  _AI_CANDY_PP_CACHED_GIT_ROOT=""
  _AI_CANDY_GIT_ROOT_IS_FALLBACK=0
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
  _AI_CANDY_GIT_METADATA_ROOT_HINT=""
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
          if [[ -z "${GIT_WORK_TREE-}${GIT_COMMON_DIR-}" ]]; then
            _AI_CANDY_GIT_METADATA_ROOT_HINT="$candidate_dir"
          fi
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
  _AI_CANDY_GIT_ROOT_IS_FALLBACK=0
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
    if [[ -n "$_AI_CANDY_GIT_METADATA_ROOT_HINT" ]]; then
      _AI_CANDY_GIT_ROOT_IS_FALLBACK=1
      REPLY="$_AI_CANDY_GIT_METADATA_ROOT_HINT"
    else
      REPLY="NOT_GIT"
    fi
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

  local retry_after="${_AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT[$root_cache_key]-0}"
  if [[ "$retry_after" == <-> ]] && (( current_time < retry_after )); then
    REPLY="NOT_GIT"
    return 0
  fi

  # Compute git root
  local git_root=""
  integer git_status=0
  git_root=$(_ai_candy_run_local_probe \
    git rev-parse --show-toplevel 2>/dev/null) || git_status=$?
  if (( git_status != 0 && git_status != 128 )) || \
     (( git_status == 0 && ${#git_root} == 0 )); then
    local retry_ttl="${_AI_CANDY_GIT_PROBE_FAILURE_RETRY_TTL:-3}"
    if [[ "$retry_ttl" != <-> ]] || (( retry_ttl < 1 || retry_ttl > 30 )); then
      retry_ttl=3
    fi
    _AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT[$root_cache_key]=$((
      current_time + retry_ttl
    ))
    (( ${#_AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT} > \
       _AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD )) && \
      _ai_candy_mem_cache_cleanup git_root_retry
    REPLY="NOT_GIT"
    return 0
  fi
  _ai_candy_mem_cache_remove_key git_root_retry "$root_cache_key"
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
  integer root_is_fallback=$_AI_CANDY_GIT_ROOT_IS_FALLBACK
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
    (( root_is_fallback )) && break

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

  if (( root_is_fallback )); then
    REPLY="$result"
    return 0
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
typeset -g _AI_CANDY_GIT_PROBE_FAILURE_RETRY_TTL=3
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
  _AI_CANDY_GIT_HIDE_INFO=0
  _AI_CANDY_GIT_HIDE_DIRTY=0
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
  integer root_is_fallback=$_AI_CANDY_GIT_ROOT_IS_FALLBACK
  local context_key=""
  if (( root_is_fallback )); then
    context_key="fallback:${#git_root}:$git_root"
  else
    _ai_candy_git_context_cache_key "$git_root"
    context_key="$REPLY"
  fi
  if [[ "$_AI_CANDY_GIT_SNAPSHOT_RENDER_ID" == "$current_id" && \
        "$_AI_CANDY_GIT_SNAPSHOT_CONTEXT" == "$context_key" ]]; then
    return 0
  fi

  _AI_CANDY_GIT_SNAPSHOT_RENDER_ID="$current_id"
  _AI_CANDY_GIT_SNAPSHOT_CONTEXT="$context_key"
  _ai_candy_reset_git_snapshot
  [[ -n "$git_root" && "$git_root" != "NOT_GIT" ]] || return 0
  if (( root_is_fallback )); then
    _ai_candy_load_git_head_snapshot "$git_root"
    return $?
  fi
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
    local retry_ttl="${_AI_CANDY_GIT_PROBE_FAILURE_RETRY_TTL:-3}"
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

  (( _AI_CANDY_GIT_ROOT_IS_FALLBACK )) && return

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
  if (( _AI_CANDY_GIT_ROOT_IS_FALLBACK )); then
    _AI_CANDY_GIT_REMOTE_BRANCH_CACHE=""
    _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_ID="$current_id"
    _AI_CANDY_GIT_REMOTE_BRANCH_CACHE_CONTEXT="fallback:${#git_root}:$git_root"
    REPLY=""
    return 0
  fi
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
