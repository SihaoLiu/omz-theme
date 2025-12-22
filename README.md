# Container Candy 🍬

**A responsive Oh My Zsh theme for the AI-assisted developer who works across containers, VMs, and bare metal.**

Ever SSH'd into a machine and wondered *"Wait, am I on the host or in a container?"* — This theme has your back.

## Features

- **Responsive Design** — Automatically adapts to your terminal width (4-tier system)
- **Container Detection** — Instantly know if you're in a container (magenta) or on the host (yellow)
- **OS & Kernel Info** — See your distro and kernel version at a glance
- **GitHub PR Status** — Shows PR number when current branch has an open PR
- **AI Tools Status** — Track versions of Claude Code, OpenAI Codex, and Gemini CLI
- **Update Indicators** — Red `*` warns you when updates are available
- **Smart Caching** — Background version checks, zero prompt lag

## Demo

Watch the prompt gracefully adapt as your terminal shrinks:

```
# LONG MODE - Full details + AI tools + PR status
user@host [HOST] [09:32:49] [~/project] [main][#42] [Red Hat Enterprise Linux 9.7 (Plow), Linux-5.14.0-611.13.1.el9_7.x86_64] [CC 2.0.71][CX 0.73.0][GM 0.21.0 *]
-> %

# SHORT+AI MODE - Compact OS info + AI tools + PR status
user@host [HOST] [09:32:53] [~/project] [main][#42] [Rhel-9.7, Linux-5.14.0] [CC 2.0.71][CX 0.73.0][GM 0.21.0 *]
-> %

# SHORT MODE - Compact OS info only + PR status
user@host [HOST] [09:33:05] [~/project] [main][#42] [Rhel-9.7, Linux-5.14.0]
-> %

# MIN MODE - Just the essentials
user@host [09:33:11] [~/project] [main]
-> %
```

## What Do Those Badges Mean?

| Badge | Tool | Color |
|-------|------|-------|
| `[CC x.y.z]` | Claude Code | Coral |
| `[CX x.y.z]` | OpenAI Codex CLI | Light Gray |
| `[GM x.y.z]` | Gemini CLI | Purple |
| `[#123]` | GitHub PR Number | Pink |

A red `*` after the version means an update is available!

## Container vs Host

| Indicator | Meaning |
|-----------|---------|
| `[CNTR]` (magenta) | You're inside a container |
| `[HOST]` (yellow) | You're on the physical/VM host |

Detection uses `/run/.containerenv` — works great with Podman and other OCI runtimes.

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

Because knowing where you are should be sweet, not stressful. 🍭

---

*Built for developers who live in terminals and talk to AI.*
