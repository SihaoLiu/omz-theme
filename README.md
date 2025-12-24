# Container Candy

**A responsive Oh My Zsh theme for the AI-assisted developer who works across containers, VMs, and bare metal.**

Ever SSH'd into a machine and wondered *"Wait, am I on the host or in a container?"* — This theme has your back.

## Features

- **Responsive Design** — Automatically adapts to your terminal width (4-tier system)
- **Container Detection** — Instantly know if you're in a container (magenta) or on the host (yellow)
- **OS & Kernel Info** — See your distro and kernel version at a glance
- **Git Status** — Branch, staged/unstaged changes, and special states (rebase, merge, cherry-pick, bisect)
- **GitHub PR Status** — Shows PR number and CI status when current branch has an open PR
- **AI Tools Status** — Track versions of Claude Code, OpenAI Codex, and Gemini CLI
- **Update Indicators** — Red `*` warns you when updates are available
- **Emoji/Plaintext Modes** — Toggle between emoji-rich and plaintext display
- **Smart Caching** — Background version checks with SQLite or file-based cache, zero prompt lag

## Demo

Watch the prompt gracefully adapt as your terminal shrinks:

**Emoji Mode:**
```
# LONG MODE - Full details + AI tools + PR status
user@host [💻] [09:32:49] [~/project] [main][#42✓] [Red Hat Enterprise Linux 9.7 (Plow), Linux-5.14.0-611.13.1.el9_7.x86_64] [🤖1.0.18|🧠0.1.2504302|🔷0.1.9*]
-> %

# SHORT+AI MODE - Compact OS info + AI tools + PR status
user@host [💻] [09:32:53] [~/project] [main][#42✓] [Rhel-9.7, Linux-5.14.0] [🤖1.0.18|🧠0.1.2504302|🔷0.1.9*]
-> %

# SHORT MODE - Compact OS info only + PR status
user@host [💻] [09:33:05] [~/project] [main][#42✓] [Rhel-9.7, Linux-5.14.0]
-> %

# MIN MODE - Just the essentials
user@host [09:33:11] [~/project] [main]
-> %
```

**Plaintext Mode:**
```
# LONG MODE with long AI names (when width allows)
user@host [HOST] [09:32:49] [~/project] [main][#42 OK] [Red Hat Enterprise Linux 9.7 (Plow), Linux-5.14.0-611.13.1.el9_7.x86_64] [Claude:1.0.18|Codex:0.1.2504302|Gemini:0.1.9*]

# LONG MODE with short AI names
user@host [HOST] [09:32:49] [~/project] [main][#42 OK] [Red Hat Enterprise Linux 9.7 (Plow), Linux-5.14.0-611.13.1.el9_7.x86_64] [Cl:1.0.18|Cx:0.1.2504302|Gm:0.1.9*]
```

## Badge Reference

### AI Tools

| Badge | Tool | Color |
|-------|------|-------|
| `🤖` / `Cl:` / `Claude:` | Claude Code | Coral |
| `🧠` / `Cx:` / `Codex:` | OpenAI Codex CLI | Light Gray |
| `🔷` / `Gm:` / `Gemini:` | Gemini CLI | Purple |

A red `*` after the version means an update is available!

### Container vs Host

| Indicator | Meaning |
|-----------|---------|
| `📦` / `[CNTR]` (magenta) | You're inside a container |
| `💻` / `[HOST]` (yellow) | You're on the physical/VM host |

Detection uses `/run/.containerenv` — works great with Podman and other OCI runtimes.

### GitHub PR Status

| Indicator | Meaning |
|-----------|---------|
| `#N` | Pull request number N for current branch |
| `✓` / `OK` | All CI checks passed |
| `✗` / `X` | Some CI checks failed |
| `⏳` / `...` | CI checks still running |

Example: `#42✓` means PR #42 with all checks passing.

### Git Special States

| Indicator | Meaning |
|-----------|---------|
| `🔀` / `RB` | Rebase in progress (with step/total if interactive) |
| `🔀` / `MG` | Merge in progress |
| `🍒` / `CP` | Cherry-pick in progress |
| `🔍` / `BI` | Bisect in progress |
| `🔌` / `DT` | Detached HEAD state |

Example: `🔀2/5` means interactive rebase at step 2 of 5.

### Other Indicators

| Indicator | Meaning |
|-----------|---------|
| `⚙N` / `JN` | N background jobs running |
| `..` | Path truncated (in narrow terminal) |

## Quick Commands

| Command | Action |
|---------|--------|
| `e` | Toggle emoji/plaintext mode |
| `p` | Toggle path separator (space/slash) |
| `u` | Refresh all cached prompt info |
| `h` | Show help |

### Path Display Modes (in git repos)

- **Space mode:** `[repo/root submodule relative/path]` — enables double-click to select path segments
- **Slash mode:** `[repo/root/submodule/relative/path]` — traditional path display

## Installation

### Using Oh My Zsh

1. Clone this repo or download `container-candy.zsh-theme`
2. Copy the theme to your Oh My Zsh themes directory:
   ```bash
   cp container-candy.zsh-theme ~/.oh-my-zsh/custom/themes/
   ```
3. Set it in your `~/.zshrc`:
   ```bash
   ZSH_THEME="container-candy"
   ```
4. Reload your shell:
   ```bash
   source ~/.zshrc
   ```

## Requirements

- [Oh My Zsh](https://ohmyz.sh/)
- A terminal with 256-color support (for the pretty colors)
- Optional: `sqlite3` for faster caching (falls back to file-based cache)
- Optional: `gh` CLI for GitHub PR status badge
- Optional: `claude`, `codex`, and/or `gemini` CLI tools for AI status badges

## How It Works

The theme calculates the visible length of all prompt components and picks the best display tier for your current terminal width:

```
LONG      → Everything: full OS name, full kernel, AI tools
SHORT+AI  → Compact: os-id + version, short kernel, AI tools
SHORT     → Compact: os-id + version, short kernel, no AI
MIN       → Essential: user@host, time, path, git only
```

Version checks for AI tools run in the background and cache results for 1 hour — your prompt stays snappy.

## Why "Container Candy"?

Because knowing where you are should be sweet, not stressful.

---

*Built for developers who live in terminals and talk to AI.*

## License

MIT License - see [LICENSE](LICENSE) for details.
