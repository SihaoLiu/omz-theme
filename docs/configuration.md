# Configuration

AI Candy provides adaptive long, short, and minimal layouts. Depending on the
available tools and enabled settings, the prompt can show Git state, GitHub pull
request and CI status, public IPv4 and SSH indicators, operating-system details,
and installed coding-tool versions.

Git special-state indicators cover rebase, merge, cherry-pick, revert, bisect,
and detached HEAD. The prompt also shows background job count, command status,
virtual environment, session type, and time zone.

## Compatibility

The supported environments are:

- macOS with Zsh 5.4.2 or newer
- Red Hat Enterprise Linux-compatible releases 9 and 10
- Ubuntu 22.04 and 24.04

The version of Bash shipped by macOS does not affect this theme. Oh My Zsh
themes execute in Zsh, and the runtime code does not invoke Bash.

## Requirements

Required:

- Zsh 5.4.2 or newer
- The standard `zsh/datetime` module
- Oh My Zsh
- A terminal with 256-color support
- A Nerd Font when emoji mode is enabled

Optional integrations:

- `git` with porcelain-v2 support for repository status and path hierarchy;
  stash counts fall back to the reflog on Git versions older than 2.35
- `sqlite3` for the persistent cache backend
- `curl` for public IP and tool update checks
- `gh` for GitHub identity, pull request, and CI status
- `ssh` for GitHub SSH identity detection
- Supported coding-tool CLIs for their version badges

GNU `timeout`, `gtimeout`, `flock`, and `xxd` are not required. The theme uses
standard Zsh modules for timeouts, locking, file operations, and cache encoding.
GNU `timeout` or `gtimeout` remains a fallback for Zsh builds that omit
`zsh/system` or `zsh/zselect`.

## Quick Commands

Short aliases are disabled by default. Enable them before Oh My Zsh loads the
theme:

```zsh
AI_CANDY_ENABLE_SHORT_ALIASES=1
```

When enabled, the theme creates these aliases only when the name is not already
an alias or function:

| Command | Action |
|---|---|
| `e` | Toggle emoji and plain-text modes |
| `p` | Toggle space and slash path separators |
| `n` | Toggle all network-backed features |
| `a` | Toggle coding-tool badges |
| `o` | Toggle OS and kernel information |
| `off` | Disable optional display and network modes |
| `on` | Enable optional display and network modes |
| `t` | Show integration and cache status |
| `u` | Clear derived caches and re-detect commands |
| `h` | Show the built-in badge reference |

To disable asynchronous Git through the same Oh My Zsh setting used by its Git
library:

```zsh
zstyle ':omz:alpha:lib:git' async-prompt no
```

This opt-out favors immediately fresh Git state and runs one bounded
porcelain-v2 status probe per prompt. Keep asynchronous Git enabled for the
lowest latency in large working trees.

## Layout

The prompt chooses among three layouts:

```text
LONG   Full path, system information, and tool status on the left
SHORT  Compact system information and optional tool status on the right
MIN    Truncated path with compact right-prompt information
```

The theme uses Oh My Zsh's asynchronous prompt API for Git status when that API
is available and enabled. Its synchronous fallback obtains the changing Git
facts from one porcelain-v2 status snapshot per render. If a repository status
snapshot exceeds its deadline or output bound, the theme still displays the
branch from Git metadata and briefly backs off before trying the full status
again. Repository-level `oh-my-zsh.hide-info` and `oh-my-zsh.hide-dirty`
settings are honored, including exact tag names for detached commits.
