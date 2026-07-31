# Cache Architecture, Security, And Privacy

## Cache Design

The parent Zsh process owns the hot key-value cache for Git and pull-request
data. Small permission-restricted result files carry topology generations,
public IP data, GitHub identities, and tool versions from background workers
back to the parent shell. Prompt renders read those local files without running
network commands.

On a cold key-value miss, the prompt may attempt one non-waiting persistent
lookup with a 50 ms I/O deadline. An ordinary cache write reserves its key with
a metadata update whose lock wait is capped at 20 ms. A deletion may wait up to
50 ms so short worker contention cannot leave an older persistent value behind.
Backend writes remain in registered background workers.

SQLite or a portable line-file backend provides a cold, cross-session cache.
The persistent backend is initialized only on its first use. The first backend
selection is recorded in `persistent_backend`; every live shell revalidates that
owner instead of silently falling back to a different format. This prevents
SQLite and line-file writers from becoming competing authorities. The `u`
command clears the derived backend state and lets the next access select again.

Both backends use the same validated expiration rules. Parent-shell memory
updates are immediate. File updates use atomic same-directory renames and Zsh
descriptor locks, with a conservative directory-lock fallback for builds
lacking `zsh/system`. Cross-shell reservations use persistent, epoch-scoped
monotonic tokens rather than wall-clock time, so clock corrections cannot
reverse cache operation order. A versioned persistence epoch prevents a
background task started in another shell from restoring stale data after `u`.
SQLite is therefore optional persistence, not a requirement for a fast warm
prompt. If the operation journal reaches its configured bound, a new
persistence reservation is skipped rather than evicting an active reservation.
Git configuration metadata participates in repository cache identities. On
filesystems with whole-second timestamps, a bounded session-only content
generation distinguishes in-place rewrites; configuration text is never
persisted and is discarded on the next stable metadata observation. Git itself
resolves the active `include.path` and `includeIf` graph. The theme retains only
the discovered file paths and their bounded fingerprints, rescanning when a
file or branch selector changes. Graph discovery is timeout- and size-bounded;
an incomplete or unsupported graph disables caching for that context. A
relative `GIT_CONFIG` path is resolved from the shell's physical working
directory before internal `git -C` calls, so probes and their cache identities
read the same file.

Cache data is stored below:

```text
${XDG_CACHE_HOME:-$HOME/.cache}/zsh-prompt
```

The final cache directory must not be a symbolic link. Its mode is restricted
to `0700`; regular cache files and the SQLite database use `0600`. Remote URLs
are hashed before they become persistent pull-request cache keys. Theme-owned
files are size-checked and symbolic links are not read. The line backend and
operation journal are limited to 256 KiB, 500 records, and 64 KiB per record;
malformed records fail closed. Cleanup is bounded and runs periodically rather
than during theme startup. Native timeout capture files use a private directory
below `TMPDIR` when possible and fall back to the cache directory; each capture
is limited to 256 KiB.

## Network And Privacy

Network mode is enabled by default. When short aliases are enabled, `n` toggles
it. Disabling network mode prevents the theme from starting public IP, GitHub,
and update-check requests.

When enabled, the theme may contact:

- `checkip.amazonaws.com`, `ifconfig.me`, `icanhazip.com`, or `api.ipify.org`
  to determine the public IPv4 address
- GitHub through `gh` and `ssh`
- the public release endpoints for installed coding tools

These services receive the network metadata inherent to an outbound request.
The theme does not read or persist authentication tokens. Authentication
remains inside the installed `gh` and `ssh` clients. Local caches can contain
derived information such as repository paths, public IP addresses, usernames,
and tool versions, and are protected by the cache-directory permissions
described above.

No runtime cache or machine-local scratch data belongs in the repository.
Automated tests reject common private-key markers, access-token prefixes, and
absolute macOS/Linux home-directory paths in public text files.
