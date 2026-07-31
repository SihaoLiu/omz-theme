# Installation Details

The primary one-line installation command is in the
[README](../README.md#installation). The installer requires an existing Oh My
Zsh installation. It validates the downloaded standalone theme with Zsh before
atomically publishing it below the Oh My Zsh custom theme directory.

The theme download performed by the installer is restricted to HTTPS, bounded
to 1 MiB, and has finite connection and total deadlines. An identical installed
theme is not replaced or backed up, although unsafe group or other write
permissions are removed. An upgrade preserves the previous file beside the new
theme.

Existing `.zshrc` files, including symbolic links, are never rewritten. The
installer prints the exact setting to change manually. If `.zshrc` does not
exist, the installer creates it from the installed Oh My Zsh template and
selects `ai-candy` there.

## Install Without Modifying .zshrc

To prevent the installer from creating a missing `.zshrc`:

```sh
sh -c 'installer=$(curl -fsSL https://raw.githubusercontent.com/SihaoLiu/ai-candy/refs/heads/main/install.sh) && [ -n "$installer" ] && exec sh -c "$installer" sh "$@"' sh --no-modify-zshrc
```

## Confirm Before Installing

To require an explicit `CONFIRM` before installing or replacing a theme whose
content differs from the downloaded release:

```sh
sh -c 'installer=$(curl -fsSL https://raw.githubusercontent.com/SihaoLiu/ai-candy/refs/heads/main/install.sh) && [ -n "$installer" ] && exec sh -c "$installer" sh "$@"' sh --confirm
```

## Mirrors And Reproducible Installs

`AI_CANDY_THEME_URL` may be exported before running the installer to use a
self-hosted HTTPS mirror of the standalone theme. Leave it unset for the
standard GitHub-hosted installation.

The short command follows the Oh My Zsh installer trust model: it downloads and
executes the installer from the current `main` branch. Inspect the script before
running it when that trust model is not appropriate. For a reproducible
installation, use an installer URL pinned to a reviewed tag or commit and set
`AI_CANDY_THEME_URL` to the matching pinned theme URL.

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
