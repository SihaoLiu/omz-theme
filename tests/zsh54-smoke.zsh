#!/usr/bin/env zsh

setopt errexit nounset pipefail

function validate_zsh54_theme() {
  [[ "$ZSH_VERSION" == 5.4.2 ]]
  zsh scripts/build-theme.zsh --check
  zsh -n ai-candy.zsh-theme

  _AI_CANDY_TIMEOUT_CMD=zsh-native
  [[ "$(_ai_candy_run_with_timeout 0.2 print -r -- ready)" == ready ]]

  _ai_candy_prompt_text_width $'a\xE4\xB8\xAD'
  [[ "$REPLY" == 3 ]]

  local -x GIT_CONFIG_COUNT=1
  local -x GIT_CONFIG_KEY_0=oh-my-zsh.hide-info
  local -x GIT_CONFIG_VALUE_0=1
  _ai_candy_git_discovery_context_key
  local first_git_context="$REPLY"
  GIT_CONFIG_VALUE_0=0
  _ai_candy_git_discovery_context_key
  [[ -n "$first_git_context" && "$REPLY" != "$first_git_context" ]]
  unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0

  _AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
  _ai_candy_get_cached_git_root
  [[ "$REPLY" == /work ]]

  _AI_CANDY_CACHE_BACKEND_STATE=1
  _AI_CANDY_CACHE_BACKEND=file
  local cache_time=$EPOCHSECONDS
  _ai_candy_cache_reserve_operation set probe key "$cache_time"
  local -a reservation
  reservation=("${reply[@]}")
  [[ "${reservation[2]}" == v3:* ]]
  _ai_candy_cache_commit_operation set probe key value "$cache_time" \
    "${reservation[@]}"
  _ai_candy_cache_persist_read probe key
  [[ "$REPLY" == value\|* ]]

  local IFS=$'\x1f'
  _ai_candy_collect_process_tree 100 $'100 1 S\n200 100 S\n300 200 S'
  [[ "${(j:,:)_AI_CANDY_TIMEOUT_PROCESS_TREE}" == 100,200,300 ]]

  (zselect -t 300) &!
  local background_pid=$!
  _ai_candy_register_background_pid "$background_pid"
  _ai_candy_stop_registered_background_jobs
  integer attempt
  for attempt in {1..20}; do
    ! kill -0 "$background_pid" 2>/dev/null && break
    _ai_candy_sleep_ticks 1
  done
  ! kill -0 "$background_pid" 2>/dev/null

  function _ai_candy_zsh54_worker() { zselect -t 300; }
  _ai_candy_start_registered_background_worker _ai_candy_zsh54_worker
  background_pid="${_AI_CANDY_BACKGROUND_PIDS[-1]}"
  [[ "$background_pid" == <-> ]]
  _ai_candy_stop_registered_background_jobs
  for attempt in {1..20}; do
    ! kill -0 "$background_pid" 2>/dev/null && break
    _ai_candy_sleep_ticks 1
  done
  ! kill -0 "$background_pid" 2>/dev/null
}

export XDG_CACHE_HOME=/tmp/ai-candy-cache
export LC_ALL=C
export LANG=C

typeset -gr _AI_CANDY_ZSH54_FIXTURE_DIR="$(
  mktemp -d "${TMPDIR:-/tmp}/ai-candy-zsh54.XXXXXX"
)"
trap 'command rm -rf -- "$_AI_CANDY_ZSH54_FIXTURE_DIR"' EXIT
{
  print -r -- '#!/bin/sh'
  print -r -- 'if [ "$#" -eq 2 ] && [ "$1" = rev-parse ] && [ "$2" = --show-toplevel ]; then'
  print -r -- '  printf "%s\n" /work'
  print -r -- '  exit 0'
  print -r -- 'fi'
  print -r -- 'exit 2'
} >| "$_AI_CANDY_ZSH54_FIXTURE_DIR/git"
chmod 700 "$_AI_CANDY_ZSH54_FIXTURE_DIR/git"
export PATH="$_AI_CANDY_ZSH54_FIXTURE_DIR:$PATH"
rehash

autoload -Uz colors
colors
source ./ai-candy.zsh-theme

_ai_candy_hex_encode x
[[ "$REPLY" == 78 ]]

validate_zsh54_theme
