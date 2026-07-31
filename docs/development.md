# Development

Files under `src/` are the maintainable source of truth. The root
`ai-candy.zsh-theme` file is the generated standalone distribution used by Oh My
Zsh installations.

## Build And Test

Regenerate or verify the distribution:

```sh
zsh scripts/build-theme.zsh
zsh scripts/build-theme.zsh --check
```

Run the test suite:

```sh
python3 -m unittest discover -s tests -v
```

The tests cover cache concurrency and corruption, malformed timestamps, signal
cleanup, process deadlines, Git cache invalidation, prompt escaping, symlink
handling, startup behavior, and hot-path process counts.

Continuous integration exercises Ubuntu 22.04/24.04, AlmaLinux 9/10, and macOS
runners. A pinned Zsh 5.4.2 image checks the minimum supported shell. The macOS
runner exercises the BSD userland, while runtime tests also cover fallback paths
that do not depend on GNU coreutils.

## Demo Generation

Regenerate the animated terminal demo:

```sh
zsh scripts/generate-demo.zsh
```

The generator requires Zsh and Git plus either a local VHS toolchain or Docker.
Install VHS without `sudo` when Go is available:

```sh
GOBIN="$HOME/.local/bin" go install github.com/charmbracelet/vhs@v0.11.0
export PATH="$HOME/.local/bin:$PATH"
```

The Go command above installs VHS itself; `ttyd` and `ffmpeg` remain separate
dependencies. On macOS, `brew install vhs` installs the supported package and
its runtime dependencies. When the complete local toolchain is unavailable,
the generator uses a digest-pinned official VHS container. Docker may need
network access to obtain that image once, but the renderer runs with its network
disabled.

Host Zsh first renders the real theme into ANSI snapshots in a fresh synthetic
Git repository, an empty synthetic home, and a minimal environment. A
fail-closed worker stub rejects background work. Local or containerized VHS then
records a POSIX playback script, so the container does not need Zsh. A local VHS
process retains normal host filesystem and network access so it can resolve the
requested user-installed font; the container receives only the tape and fresh
render directory. The render directory is removed after generation.

`demo.gif` and the static `demo.png` frame are published only after text and
binary privacy checks pass; generation fails closed when `strings` is missing.
`demo-assets.sha256` records the reviewed output. Any digest change should come
from this generator and include a visual review of both assets; binary scanning
only checks metadata and cannot inspect text rendered into compressed pixels.
