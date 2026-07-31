#!/usr/bin/env zsh

emulate -L zsh
setopt errexit nounset pipefail

typeset -r project_root="${0:A:h:h}"
typeset -r output_file="${project_root}/ai-candy.zsh-theme"
typeset -a theme_modules=(
  "${project_root}/src/bootstrap.zsh"
  "${project_root}/src/unicode-width.zsh"
  "${project_root}/src/cache.zsh"
  "${project_root}/src/ui.zsh"
  "${project_root}/src/prompt.zsh"
  "${project_root}/src/git.zsh"
  "${project_root}/src/git-config-graph.zsh"
  "${project_root}/src/smart-path.zsh"
  "${project_root}/src/integrations.zsh"
  "${project_root}/src/theme.zsh"
)

typeset module
for module in "${theme_modules[@]}"; do
  [[ -f "$module" ]] || {
    print -u2 -r -- "missing theme module: ${module#${project_root}/}"
    exit 1
  }
done

if [[ "${1:-}" == "--check" ]]; then
  [[ -f "$output_file" && ! -L "$output_file" ]] || {
    print -u2 -r -- "ai-candy.zsh-theme must be a regular file"
    exit 1
  }
  command cmp <(command cat "${theme_modules[@]}") "$output_file" >/dev/null || {
    print -u2 -r -- "ai-candy.zsh-theme is not generated from src modules"
    exit 1
  }
  exit 0
fi

[[ $# -eq 0 ]] || {
  print -u2 -r -- "usage: scripts/build-theme.zsh [--check]"
  exit 2
}

[[ ! -e "$output_file" || ( -f "$output_file" && ! -L "$output_file" ) ]] || {
  print -u2 -r -- "ai-candy.zsh-theme must be a regular file"
  exit 1
}

typeset temporary_file=""
function _remove_temporary_theme() {
  [[ -n "$temporary_file" ]] && command rm -f "$temporary_file"
}

function _abort_theme_build() {
  local exit_status="$1"
  _remove_temporary_theme
  trap - EXIT HUP INT TERM
  exit "$exit_status"
}

temporary_file=$(umask 077; command mktemp "${output_file}.tmp.XXXXXX")
trap _remove_temporary_theme EXIT
trap '_abort_theme_build 129' HUP
trap '_abort_theme_build 130' INT
trap '_abort_theme_build 143' TERM

command cat "${theme_modules[@]}" >| "$temporary_file"
command chmod 644 "$temporary_file"
command mv -f "$temporary_file" "$output_file"
temporary_file=""
trap - EXIT HUP INT TERM
