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
