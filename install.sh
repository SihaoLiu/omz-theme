#!/bin/sh

set -eu

LC_ALL=C
export LC_ALL
umask 077

theme_name="ai-candy"
theme_url_default="https://raw.githubusercontent.com/SihaoLiu/ai-candy/refs/heads/main/ai-candy.zsh-theme"
theme_url=${AI_CANDY_THEME_URL:-$theme_url_default}
theme_max_bytes=1048576
theme_limit_blocks=$(( (theme_max_bytes + 511) / 512 ))
modify_zshrc=1
confirm_install=0
theme_temp=""
config_temp=""
theme_backup_temp=""
published_backup=""
theme_changed=0

usage() {
  printf '%s\n' "Usage: install.sh [--no-modify-zshrc] [--confirm]"
}

fail() {
  printf 'ai-candy: %s\n' "$1" >&2
  exit 1
}

cleanup_temporary_files() {
  if [ -n "$theme_temp" ]; then
    rm -f "$theme_temp"
  fi
  if [ -n "$config_temp" ]; then
    rm -f "$config_temp"
  fi
  if [ -n "$theme_backup_temp" ]; then
    rm -f "$theme_backup_temp"
  fi
}

abort_on_signal() {
  signal_status=$1
  trap - EXIT HUP INT TERM
  cleanup_temporary_files
  exit "$signal_status"
}

trap cleanup_temporary_files EXIT
trap 'abort_on_signal 129' HUP
trap 'abort_on_signal 130' INT
trap 'abort_on_signal 143' TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-modify-zshrc)
      modify_zshrc=0
      ;;
    --confirm)
      confirm_install=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      fail "unknown option: $1"
      ;;
  esac
  shift
done

[ -n "${HOME:-}" ] || fail "HOME is not set"
command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v cmp >/dev/null 2>&1 || fail "cmp is required"
command -v zsh >/dev/null 2>&1 || fail "zsh is required"
command -v mktemp >/dev/null 2>&1 || fail "mktemp is required"

omz_dir=${ZSH:-"$HOME/.oh-my-zsh"}
custom_dir=${ZSH_CUSTOM:-"$omz_dir/custom"}
theme_dir="$custom_dir/themes"
theme_file="$theme_dir/$theme_name.zsh-theme"

[ -f "$omz_dir/oh-my-zsh.sh" ] || \
  fail "Oh My Zsh was not found at $omz_dir"
mkdir -p "$theme_dir" || fail "cannot create $theme_dir"
if [ ! -d "$theme_dir" ] || [ ! -w "$theme_dir" ]; then
  fail "theme directory is not writable: $theme_dir"
fi

if [ -L "$theme_file" ]; then
  fail "refusing to replace symbolic link: $theme_file"
fi
if [ -e "$theme_file" ] && [ ! -f "$theme_file" ]; then
  fail "theme target is not a regular file: $theme_file"
fi

theme_temp=$(mktemp "$theme_dir/.ai-candy.zsh-theme.tmp.XXXXXX") || \
  fail "cannot create a temporary theme file"
if ! (
  ulimit -f "$theme_limit_blocks" || exit 1
  exec curl -fsSL --proto '=https' --proto-redir '=https' \
    --connect-timeout 5 --max-time 30 \
    --max-filesize "$theme_max_bytes" -o "$theme_temp" -- "$theme_url"
); then
  fail "theme download failed"
fi
if [ ! -f "$theme_temp" ] || [ -L "$theme_temp" ]; then
  fail "downloaded theme is not a regular file"
fi
[ -s "$theme_temp" ] || fail "downloaded theme is empty"
theme_size=$(LC_ALL=C command wc -c < "$theme_temp") || \
  fail "cannot measure downloaded theme"
[ "$theme_size" -le "$theme_max_bytes" ] || \
  fail "downloaded theme exceeds size limit"
grep -Fq '# AI Candy - Oh My Zsh Theme' "$theme_temp" || \
  fail "downloaded file is not the ai-candy theme"
grep -Fq 'builtin unfunction _ai_candy_restore_source_options' "$theme_temp" || \
  fail "downloaded theme is incomplete"
zsh -n "$theme_temp" || fail "downloaded theme has invalid Zsh syntax"

if [ -f "$theme_file" ] && cmp -s "$theme_temp" "$theme_file"; then
  chmod u+rw,go-w "$theme_file" || fail "cannot secure theme permissions"
  rm -f "$theme_temp"
  theme_temp=""
else
  if [ "$confirm_install" -eq 1 ]; then
    printf 'Install ai-candy at %s? Type CONFIRM to proceed: ' "$theme_file"
    response=""
    IFS= read -r response || true
    if [ "$response" != "CONFIRM" ]; then
      rm -f "$theme_temp"
      theme_temp=""
      trap - EXIT HUP INT TERM
      cleanup_temporary_files
      printf '%s\n' "Skipped ai-candy installation."
      exit 0
    fi
  fi

  if [ -f "$theme_file" ]; then
    theme_backup_temp=$(mktemp "${theme_file}.backup.XXXXXX") || \
      fail "cannot create a theme backup"
    cp -p "$theme_file" "$theme_backup_temp" || \
      fail "cannot back up the existing theme"
  fi
  chmod 644 "$theme_temp" || fail "cannot set theme permissions"
  mv -f "$theme_temp" "$theme_file" || fail "cannot publish the theme"
  theme_temp=""
  if [ -n "$theme_backup_temp" ]; then
    published_backup="$theme_backup_temp"
    theme_backup_temp=""
  fi
  theme_changed=1
fi

config_root=${ZDOTDIR:-$HOME}
zshrc="$config_root/.zshrc"
config_changed=0

if [ "$modify_zshrc" -eq 1 ]; then
  if [ ! -e "$zshrc" ] && [ ! -L "$zshrc" ]; then
    config_template="$omz_dir/templates/zshrc.zsh-template"
    if [ -f "$config_template" ] && [ ! -L "$config_template" ]; then
      mkdir -p "$config_root" || fail "cannot create $config_root"
      config_temp=$(mktemp "$config_root/.zshrc.ai-candy.tmp.XXXXXX") || \
        fail "cannot create a temporary Zsh configuration"
      cp -p "$config_template" "$config_temp" || \
        fail "cannot copy the Oh My Zsh configuration template"
      theme_line_count=$(grep -Ec \
        '^(export[[:space:]]+)?ZSH_THEME[[:space:]]*=' \
        "$config_template" 2>/dev/null || true)
      if [ "$theme_line_count" = 1 ]; then
        awk '
          /^(export[[:space:]]+)?ZSH_THEME[[:space:]]*=/ {
            print "ZSH_THEME=\"ai-candy\""
            next
          }
          { print }
        ' "$config_template" > "$config_temp" || \
          fail "cannot select ai-candy in the Oh My Zsh template"
        zsh -n "$config_temp" || \
          fail "generated Zsh configuration has invalid syntax"
        mv -f "$config_temp" "$zshrc" || fail "cannot create $zshrc"
        config_temp=""
        config_changed=1
      else
        rm -f "$config_temp"
        config_temp=""
        printf '%s\n' \
          "ai-candy: set ZSH_THEME=\"ai-candy\" in $zshrc to activate the theme" >&2
      fi
    else
      printf '%s\n' \
        "ai-candy: set ZSH_THEME=\"ai-candy\" in $zshrc to activate the theme" >&2
    fi
  else
    printf '%s\n' \
      "ai-candy: $zshrc was not modified; set ZSH_THEME=\"ai-candy\" manually" >&2
  fi
fi

trap - EXIT HUP INT TERM
cleanup_temporary_files

if [ "$theme_changed" -eq 1 ]; then
  printf 'Installed ai-candy at %s\n' "$theme_file"
  if [ -n "$published_backup" ]; then
    printf 'Backed up the previous theme at %s\n' "$published_backup"
  fi
else
  printf 'ai-candy is already current at %s\n' "$theme_file"
fi
if [ "$modify_zshrc" -eq 0 ]; then
  printf 'Set ZSH_THEME="ai-candy" in %s to activate it.\n' "$zshrc"
elif [ "$config_changed" -eq 1 ]; then
  printf 'Selected ai-candy in %s.\n' "$zshrc"
fi
printf '%s\n' "Start a new Zsh session to use the theme."
