# Container Candy 🍬

**A responsive Oh My Zsh theme for the AI-assisted developer who works across containers, VMs, and bare metal.**

Ever SSH'd into a machine and wondered *"Wait, am I on the host or in a container?"* — This theme has your back.

## Features

- **Responsive Design** — Automatically adapts to your terminal width (4-tier system)
- **Container Detection** — Instantly know if you're in a container (red) or on the host (cyan)
- **OS & Kernel Info** — See your distro and kernel version at a glance
- **AI Tools Status** — Track versions of Claude Code, OpenAI Codex, and Gemini CLI
- **Update Indicators** — Red `*` warns you when updates are available
- **Smart Caching** — Background version checks, zero prompt lag

## Demo

Watch the prompt gracefully adapt as your terminal shrinks:

```
# LONG MODE - Full details + AI tools
user@host [09:32:49 AM] [~/project] [main] [host, Red Hat Enterprise Linux 9.7 (Plow), linux-5.14.0-611.13.1.el9_7.x86_64] [CC 2.0.71][CX 0.73.0][GM 0.21.0 *]
-> %

# SHORT+AI MODE - Compact OS info + AI tools
user@host [09:32:53 AM] [~/project] [main] [host, rhel-9.7, linux-5.14.0] [CC 2.0.71][CX 0.73.0][GM 0.21.0 *]
-> %

# SHORT MODE - Compact OS info only
user@host [09:33:05 AM] [~/project] [main] [host, rhel-9.7, linux-5.14.0]
-> %

# MIN MODE - Just the essentials
user@host [09:33:11 AM] [~/project] [main]
-> %
```

## What Do Those Badges Mean?

| Badge | Tool | Color |
|-------|------|-------|
| `[CC x.y.z]` | Claude Code | Coral |
| `[CX x.y.z]` | OpenAI Codex CLI | Light Gray |
| `[GM x.y.z]` | Gemini CLI | Purple |

A red `*` after the version means an update is available!

## Container vs Host

| Indicator | Meaning |
|-----------|---------|
| `[container, ...]` (red) | You're inside a container |
| `[host, ...]` (cyan) | You're on the physical/VM host |

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
