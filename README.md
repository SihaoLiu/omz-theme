# AI Candy

**A responsive Oh My Zsh theme for the AI-assisted developer who works across containers, VMs, and bare metal.**

*Author: Sihao Liu <sihao@cs.ucla.edu>*

Ever SSH'd into a machine and wondered *"Wait, am I on the host or in a container?"* — This theme has your back.

## Features

- **Responsive Layout** — Adapts to terminal width and uses RPROMPT for sysinfo/AI in tight spaces
- **Container Detection** — Instantly know if you're in a container (magenta) or on the host (yellow)
- **OS & Kernel Info** — Full or compact, depending on width
- **SSH + Public IP** — SSH indicator plus external IP (or `(no-internet)`)
- **Git Status** — Branch, dirty marker, ahead/behind, stash count, and special states
- **GitHub Integration** — Username badge + PR number + CI status
- **AI Tools Status** — Claude/Codex/Gemini versions with update indicator
- **Toggle Modes** — Emoji/plaintext, path separator, and network on/off
- **Smart Caching** — Memory + SQLite/file caches with background refresh, zero prompt lag

## Demo

Watch the prompt gracefully adapt as your terminal shrinks. Short/min modes push system info + AI to RPROMPT (right side):

**Emoji Mode:**
```
# LONG MODE - Full details + AI tools + PR status
[✓]user@host(x.x.x.x)[GithubUser] 💻 [09:32:49 PDT] [~/project] [main][#42✓] [Red Hat Enterprise Linux 9.7 (Plow), Linux-5.14.0-611.13.1.el9_7.x86_64] [🤖1.0.18|🧠0.1.2504302|🔷0.1.9*]
-> %

# SHORT MODE - Sysinfo + AI move to RPROMPT
[✓]user@host(x.x.x.x)[GithubUser] 💻 [09:32:53 PDT] [~/project] [main][#42✓]
# RPROMPT: [Rhel-9.7, Linux-5.14.0] [🤖1.0.18|🧠0.1.2504302|🔷0.1.9*]
-> %

# MIN MODE - Truncated path
[✓]user@host(x.x.x.x)[GithubUser] 💻 [09:33:11 PDT] [~/proj/..] [main]
# RPROMPT: [Rhel-9.7, Linux-5.14.0]
-> %
```

**Plaintext Mode:**
```
# LONG MODE with long AI names (when width allows)
[OK]user@host(x.x.x.x)[GithubUser] H [09:32:49 PDT] [~/project] [main][#42 OK] [Red Hat Enterprise Linux 9.7 (Plow), Linux-5.14.0-611.13.1.el9_7.x86_64] [Claude:1.0.18|Codex:0.1.2504302|Gemini:0.1.9*]

# LONG MODE with short AI names
[OK]user@host(x.x.x.x)[GithubUser] H [09:32:49 PDT] [~/project] [main][#42 OK] [Red Hat Enterprise Linux 9.7 (Plow), Linux-5.14.0-611.13.1.el9_7.x86_64] [Cl:1.0.18|Cx:0.1.2504302|Gm:0.1.9*]
```

## Badge Reference

### Command Status

| Indicator | Meaning |
|-----------|---------|
| `[✓]` / `[OK]` | Last command succeeded (exit code 0) |
| `[✗N]` / `[ERRN]` | Last command failed with exit code N |

### Connection & Environment

| Indicator | Meaning |
|-----------|---------|
| `⚡` / `[SSH]` | Connected via SSH |
| `(x.x.x.x)` | Public IP address (green) |
| `(no-internet)` | No external connectivity (red) |

### GitHub Identity

| Indicator | Meaning |
|-----------|---------|
| `[username]` | GitHub username (from `gh` auth and/or `ssh -T git@github.com`) |
| `[gh|ssh]` (red) | Mismatch between `gh` and SSH identities |

### AI Tools

| Badge | Tool | Color |
|-------|------|-------|
| `🤖` / `Cl:` / `Claude:` | Claude Code | Coral |
| `🧠` / `Cx:` / `Codex:` | OpenAI Codex CLI | Light Gray |
| `🔷` / `Gm:` / `Gemini:` | Gemini CLI | Purple |

A red `*` after the version means an update is available.

### Container vs Host

| Indicator | Meaning |
|-----------|---------|
| `📦` / `C` (magenta) | You're inside a container |
| `💻` / `H` (yellow) | You're on the physical/VM host |

Detection uses `/run/.containerenv` — works great with Podman and other OCI runtimes.

### GitHub PR Status

| Indicator | Meaning |
|-----------|---------|
| `#N` | Pull request number N for current branch |
| `✓` / `OK` | All CI checks passed |
| `✗` / `X` | Some CI checks failed |
| `⏳` / `...` | CI checks still running |

Example: `#42✓` means PR #42 with all checks passing.

### Git Extended Status

| Indicator | Meaning |
|-----------|---------|
| `↑N` / `+N` | N commits ahead of upstream (need to push) |
| `↓N` / `-N` | N commits behind upstream (need to pull) |
| `⚑N` / `SN` | N stashed changes |
| `*` | Uncommitted changes in working directory |

Example: `main ↑2↓1⚑3` means branch `main`, 2 ahead, 1 behind, 3 stashes.

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
| `n` | Toggle network features (IP, GitHub, AI updates) |
| `t` | Show tool availability status |
| `u` | Refresh all cached prompt info |
| `h` | Show help |

### Path Display Modes (in git repos)

- **Space mode:** `[repo/root submodule relative/path]` — enables double-click to select path segments
- **Slash mode:** `[repo/root/submodule/relative/path]` — traditional path display
- **Note:** Space mode auto-disables when the current path contains spaces

## Installation

### Using Oh My Zsh

1. Clone this repo or download `ai-candy.zsh-theme`
2. Copy the theme to your Oh My Zsh themes directory:
   ```bash
   cp ai-candy.zsh-theme ~/.oh-my-zsh/custom/themes/
   ```
3. Set it in your `~/.zshrc`:
   ```bash
   ZSH_THEME="ai-candy"
   ```
4. Reload your shell:
   ```bash
   source ~/.zshrc
   ```

## Requirements

- Zsh 5.4+ (nameref support)
- [Oh My Zsh](https://ohmyz.sh/)
- A terminal with 256-color support (for the pretty colors)
- Optional: `sqlite3` for faster caching (falls back to file-based cache)
- Optional: `timeout`/`gtimeout` (coreutils) for network features
- Optional: `curl` for public IP display and AI update checks
- Optional: `gh` CLI for GitHub PR status badge
- Optional: `ssh` for GitHub identity badge
- Optional: `claude`, `codex`, and/or `gemini` CLI tools for AI status badges

## How It Works

The theme calculates the visible length of all prompt components and picks the best layout for your terminal width:

```
LONG  → Full OS name + full kernel + AI tools on the left (long AI names when space allows)
SHORT → Compact OS + kernel + AI tools move to RPROMPT
MIN   → Truncated path + compact sysinfo/AI on RPROMPT
```

Network lookups (public IP, GitHub identity/PR, AI update checks) run in the background and cache results — your prompt stays snappy. Toggle them with `n`.

## Why "AI Candy"?

Because knowing where you are—and what AI tools are at your fingertips—should be sweet, not stressful.

---

*Built for developers who live in terminals and talk to AI.*

## License

MIT License - see [LICENSE](LICENSE) for details.
