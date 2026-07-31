# Installation Details

The primary one-line installation command is in the
[README](../README.md#installation). The installer requires an existing Oh My
Zsh installation. It validates the downloaded standalone theme with Zsh before
atomically publishing it below the Oh My Zsh custom theme directory.

Downloads are restricted to HTTPS, bounded to 1 MiB, and have finite connection
and total deadlines. An identical installed theme is not replaced or backed up,
although unsafe group or other write permissions are removed. An upgrade
preserves the previous file beside the new theme.

Existing `.zshrc` files, including symbolic links, are never rewritten. The
installer prints the exact setting to change manually. If `.zshrc` does not
exist, the installer creates it from the installed Oh My Zsh template and
selects `ai-candy` there.

## Install Without Modifying .zshrc

To prevent the installer from creating a missing `.zshrc`:

```sh
sh -c 'installer_url="https://raw.githubusercontent.com/SihaoLiu/ai-candy/refs/heads/main/install.sh"; installer_max_bytes=262144; installer_limit_unit=512; [ -n "${BASH_VERSION:-}" ] && installer_limit_unit=1024; installer_limit_blocks=$(( (installer_max_bytes + installer_limit_unit - 1) / installer_limit_unit )); installer=$(mktemp) && (ulimit -f "$installer_limit_blocks" && exec curl -fsSL --proto "=https" --proto-redir "=https" --connect-timeout 5 --max-time 30 --max-filesize "$installer_max_bytes" -o "$installer" -- "$installer_url") && installer_size=$(LC_ALL=C wc -c < "$installer") && [ "$installer_size" -gt 0 ] && [ "$installer_size" -le "$installer_max_bytes" ] && sh "$installer" "$@"; status=$?; rm -f "${installer:-}"; exit "$status"' sh --no-modify-zshrc
```

## Mirrors And Reproducible Installs

`AI_CANDY_THEME_URL` may be exported before running the installer to use a
self-hosted HTTPS mirror of the standalone theme. Leave it unset for the
standard GitHub-hosted installation.

The one-line command follows the Oh My Zsh installer trust model and fetches the
current `main` branch. For a reproducible installation, inspect the script and
replace both raw URLs with URLs pinned to a reviewed tag or commit.

## Manual Installation

Clone the repository or download the standalone theme, then copy it into the
custom theme directory:

```sh
cp ai-candy.zsh-theme "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/"
```

Select it in `~/.zshrc`:

```sh
ZSH_THEME="ai-candy"
```

Start a new Zsh session or reload the configuration:

```sh
source ~/.zshrc
```

## Uninstallation

Select a different `ZSH_THEME` in `~/.zshrc`, then remove the installed theme:

```sh
rm "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/ai-candy.zsh-theme"
```

Upgrades keep prior theme files as `ai-candy.zsh-theme.backup.*`. They are not
removed automatically because they may be needed for recovery. List and review
them before deleting any that are no longer needed:

```sh
find "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes" \
  -type f -name 'ai-candy.zsh-theme.backup.*' -print
```
