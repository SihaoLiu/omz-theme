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
