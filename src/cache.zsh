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

  [[ "$cache_file" == /* ]] || return 1
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

# Read status 1 means absent or unsafe, 2 invalid, and 3 transient I/O failure.
function _ai_candy_cache_read_size_checked_file() {
  emulate -L zsh
  local LC_ALL=C
  local cache_file="$1"
  local content=""
  local -a metadata
  REPLY=""

  [[ -f "$cache_file" && ! -L "$cache_file" ]] || return 1
  (( _AI_CANDY_HAS_ZSH_STAT_BUILTIN )) || return 3
  builtin zstat -A metadata +size -- "$cache_file" 2>/dev/null || return 3
  [[ "${metadata[1]-}" == <-> ]] || return 3
  _ai_candy_cache_file_limit_bytes
  (( metadata[1] <= REPLY )) || return 2
  content="$(<"$cache_file")" 2>/dev/null || return 3
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
    builtin zstat -A metadata +size -- "$cache_file" 2>/dev/null || return 3
    [[ "${metadata[1]-}" == <-> ]] || return 3
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
  (( read_status == 125 )) && return 2
  (( read_status == 0 )) || return 3
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

function _ai_candy_cache_read_validated_lines_for_file_mutation() {
  emulate -L zsh
  integer read_status=0

  _ai_candy_cache_read_validated_lines "$@" || read_status=$?
  if (( read_status == 3 )); then
    _ai_candy_sleep_ticks 1
    read_status=0
    _ai_candy_cache_read_validated_lines "$@" || read_status=$?
  fi
  return "$read_status"
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
      _ai_candy_cache_read_validated_lines_for_file_mutation \
        "$cache_file" persistent || read_status=$?
      if (( read_status > 2 )); then
        write_status=$read_status
      else
        (( read_status == 0 )) && lines=("${reply[@]}")
        for entry in "${lines[@]}"; do
          [[ "${entry[1,prefix_len]}" == "$prefix" ]] || new_lines+=("$entry")
        done
      fi
    fi
    if (( write_status == 0 )); then
      new_lines+=("$new_line")
      if _ai_candy_cache_join_bounded_lines persistent "${new_lines[@]}"; then
        content="$REPLY"
        _ai_candy_cache_atomic_write_unlocked "$cache_file" "$content" || write_status=$?
      else
        write_status=1
      fi
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
    _ai_candy_cache_read_validated_lines_for_file_mutation \
      "$cache_file" persistent || read_status=$?
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
    elif (( read_status <= 2 )); then
      _ai_candy_cache_remove_path "$cache_file" || write_status=$?
    else
      write_status=$read_status
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
    git_root_retry)
      for candidate in "${(@k)_AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT}"; do
        [[ "$candidate" == "$remove_key" ]] || \
          kept[$candidate]="${_AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT[$candidate]}"
      done
      _AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT=("${(@kv)kept}")
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
    git_root_retry) keys=("${(@k)_AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT}") ;;
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
      git_root_retry) value="${_AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT[$key]-}" ;;
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

function _ai_candy_cache_remove_sqlite_artifacts_unlocked() {
  local artifact
  for artifact in \
    "${_AI_CANDY_CACHE_DB_FILE}-wal" \
    "${_AI_CANDY_CACHE_DB_FILE}-shm" \
    "${_AI_CANDY_CACHE_DB_FILE}-journal" \
    "$_AI_CANDY_CACHE_DB_FILE"; do
    [[ -e "$artifact" || -L "$artifact" ]] || continue
    [[ -f "$artifact" || -L "$artifact" ]] || return 1
    _ai_candy_cache_remove_path "$artifact" || return 1
  done
}

function _ai_candy_cache_execute_sqlite_unlocked() {
  local sql="$1"
  REPLY=""
  local output=""
  output=$(umask 077; _ai_candy_run_with_timeout "$_AI_CANDY_CACHE_IO_TIMEOUT" \
    sqlite3 -batch -noheader -cmd '.timeout 500' "$_AI_CANDY_CACHE_DB_FILE" \
    "$sql" 2>&1)
  local sqlite_status=$?
  REPLY="$output"
  return "$sqlite_status"
}

function _ai_candy_cache_initialize_sqlite_unlocked() {
  _ai_candy_cache_execute_sqlite_unlocked \
    'PRAGMA journal_mode=WAL;
     CREATE TABLE IF NOT EXISTS cache (
       key TEXT PRIMARY KEY,
       value TEXT NOT NULL,
       timestamp INTEGER NOT NULL
     );
     CREATE INDEX IF NOT EXISTS idx_cache_timestamp ON cache(timestamp);'
}

function _ai_candy_cache_sqlite_error_is_corruption() {
  local error_output="$1"
  [[ "$error_output" == *'file is not a database'* || \
     "$error_output" == *'database disk image is malformed'* || \
     "$error_output" == *'malformed database schema'* || \
     "$error_output" == *'unsupported file format'* ]]
}

function _ai_candy_cache_recreate_sqlite_unlocked() {
  [[ ! -L "$_AI_CANDY_CACHE_DB_FILE" && \
     ( ! -e "$_AI_CANDY_CACHE_DB_FILE" || -f "$_AI_CANDY_CACHE_DB_FILE" ) ]] || return 1
  _ai_candy_cache_remove_sqlite_artifacts_unlocked || return 1
  _ai_candy_cache_initialize_sqlite_unlocked || return 1
  _ai_candy_chmod 600 "$_AI_CANDY_CACHE_DB_FILE" 2>/dev/null
  return 0
}

function _ai_candy_cache_execute_sqlite_with_recovery_unlocked() {
  local sql="$1"
  local sqlite_status=0
  local sqlite_error=""

  if _ai_candy_cache_execute_sqlite_unlocked "$sql"; then
    return 0
  else
    sqlite_status=$?
  fi
  sqlite_error="$REPLY"
  if ! _ai_candy_cache_sqlite_error_is_corruption "$sqlite_error"; then
    REPLY="$sqlite_error"
    return "$sqlite_status"
  fi
  _ai_candy_cache_recreate_sqlite_unlocked || return 1
  _ai_candy_cache_execute_sqlite_unlocked "$sql"
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
    if ! _ai_candy_cache_initialize_sqlite_unlocked; then
      local sqlite_error="$REPLY"
      [[ -f "$_AI_CANDY_CACHE_DB_FILE" && ! -L "$_AI_CANDY_CACHE_DB_FILE" ]] || return 1
      _ai_candy_cache_sqlite_error_is_corruption "$sqlite_error" || return 1
      _ai_candy_cache_recreate_sqlite_unlocked || return 1
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
    _ai_candy_cache_execute_sqlite_with_recovery_unlocked \
      "SELECT hex(value) || '|' || timestamp FROM cache WHERE key = CAST(X'${hex_key}' AS TEXT) LIMIT 1;" || return 1
    raw_output="$REPLY"
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
    _ai_candy_cache_execute_sqlite_with_recovery_unlocked \
      "INSERT OR REPLACE INTO cache (key, value, timestamp)
       VALUES (CAST(X'${hex_key}' AS TEXT), CAST(X'${hex_value}' AS TEXT), ${timestamp})
       ;"
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
    _ai_candy_cache_execute_sqlite_with_recovery_unlocked \
      "DELETE FROM cache WHERE key = CAST(X'${hex_key}' AS TEXT);"
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
  REPLY=""
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
  (( read_status == 0 )) || REPLY=""
  return "$read_status"
}

function _ai_candy_cache_persist_read() {
  local _AI_CANDY_CACHE_FORCE_BACKEND_RETRY=1
  _ai_candy_cache_persist_read_with_waits "$_AI_CANDY_CACHE_OPERATION_WAIT_TICKS" \
    "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" "$@"
}

function _ai_candy_cache_get() {
  (( ${_AI_CANDY_CACHE_READY:-0} )) || return 1
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
  _ai_candy_cache_read_validated_lines_for_file_mutation \
    "$cache_file" "$record_kind" || read_status=$?
  if (( read_status != 0 )); then
    [[ "$record_kind" == operation || read_status > 2 ]] && return "$read_status"
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
    _ai_candy_cache_execute_sqlite_with_recovery_unlocked \
      "DELETE FROM cache WHERE timestamp < ${cutoff} OR timestamp > ${current_time};"
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
    "$_AI_CANDY_AI_PROCESS_CACHE_FILE"
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
