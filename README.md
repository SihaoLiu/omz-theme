# AI Candy

![AI Candy Demo](demo.gif)

AI Candy is a responsive Oh My Zsh theme for developers who move between
macOS, Linux, containers, virtual machines, and remote hosts. It adapts to the
terminal width while presenting Git state, system context, and optional coding
tool integrations without blocking the prompt on network requests.

The theme supports macOS, Red Hat Enterprise Linux-compatible releases 9 and
10, and Ubuntu 22.04 and 24.04. It requires Oh My Zsh and Zsh 5.4.2 or newer.

Author: Sihao Liu <sihao@cs.ucla.edu>

## Installation

Install the theme with one command:

```sh
sh -c 'installer_url="https://raw.githubusercontent.com/SihaoLiu/ai-candy/refs/heads/main/install.sh"; installer_max_bytes=262144; installer_limit_unit=512; [ -n "${BASH_VERSION:-}" ] && installer_limit_unit=1024; installer_limit_blocks=$(( (installer_max_bytes + installer_limit_unit - 1) / installer_limit_unit )); installer=$(mktemp) && (ulimit -f "$installer_limit_blocks" && exec curl -fsSL --proto "=https" --proto-redir "=https" --connect-timeout 5 --max-time 30 --max-filesize "$installer_max_bytes" -o "$installer" -- "$installer_url") && installer_size=$(LC_ALL=C wc -c < "$installer") && [ "$installer_size" -gt 0 ] && [ "$installer_size" -le "$installer_max_bytes" ] && sh "$installer" "$@"; status=$?; rm -f "${installer:-}"; exit "$status"' sh
```

The installer requires an existing Oh My Zsh installation. Existing `.zshrc`
files are left unchanged; set the theme manually when prompted:

```sh
ZSH_THEME="ai-candy"
```

Start a new Zsh session or run `source ~/.zshrc` after installation. See the
[installation guide](docs/installation.md) for manual installation, installer
options, upgrade behavior, and uninstallation.

## Documentation

- [Installation and upgrades](docs/installation.md)
- [Requirements, configuration, and prompt layout](docs/configuration.md)
- [Cache architecture, security, and privacy](docs/architecture.md)
- [Development, testing, and demo generation](docs/development.md)

Licensed under the [MIT License](LICENSE).
