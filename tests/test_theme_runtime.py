#!/usr/bin/env python3
import os
import shlex
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from tests.theme_test_support import run_zsh


class ThemeRuntimeTest(unittest.TestCase):
    def test_help_discloses_and_lists_all_short_aliases(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_ai_candy_prompt_emoji_help
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("AI_CANDY_ENABLE_SHORT_ALIASES=1", result.stdout)
        for command in ("o", "off", "on"):
            self.assertRegex(result.stdout, rf"(?m)^.*\s{command}\s+.*$")

    def test_logical_git_path_treats_metacharacters_literally(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
value=$(_ai_candy_logicalize_path_from_pwd \
  '/physical/repo[1]' '/logical/repo[1]/child' \
  '/physical/repo[1]/child')
print -r -- "VALUE=${value}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("VALUE=/logical/repo[1]\n", result.stdout)

    @staticmethod
    def _make_git_repo(path: Path) -> None:
        path.mkdir()
        subprocess.run(["git", "init", "-q", str(path)], check=True)
        subprocess.run(
            ["git", "-C", str(path), "symbolic-ref", "HEAD", "refs/heads/main"],
            check=True,
        )

    def test_git_root_cache_is_promoted_in_parent_shell(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            self._make_git_repo(repo)
            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do FG[$color]=""; done
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_ai_candy_precmd_compute_prompt
print -r -- "ROOT_COUNT=${#_AI_CANDY_MEM_CACHE_GIT_ROOT}"
""",
                cache_home=root / "cache",
                cwd=repo,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("ROOT_COUNT=1", result.stdout)

    def test_theme_source_does_not_start_sqlite(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log_file = root / "sqlite.log"
            sqlite = bin_dir / "sqlite3"
            sqlite.write_text(
                "#!/bin/sh\nprintf '%s\\n' called >> \"$SQLITE_LOG\"\nexit 1\n",
                encoding="ascii",
            )
            sqlite.chmod(0o755)
            result = run_zsh(
                'source "$1"\nprint -r -- READY\n',
                cache_home=root / "cache",
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "SQLITE_LOG": str(log_file),
                },
            )

            sqlite_was_started = log_file.exists()

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("READY\n", result.stdout)
        self.assertFalse(sqlite_was_started)

    def test_native_timeout_is_preferred_when_zsh_modules_are_available(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                'source "$1"\nprint -r -- "TIMEOUT=${_AI_CANDY_TIMEOUT_CMD}"\n',
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("TIMEOUT=zsh-native\n", result.stdout)

    def test_native_timeout_does_not_invoke_shadowing_shell_functions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "work"
            work.mkdir()
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_TIMEOUT_CMD=zsh-native
function git() { print -r -- /forged/root; }
_ai_candy_get_cached_git_root
print -r -- "ROOT=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=work,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("ROOT=NOT_GIT\n", result.stdout)

    def test_sysinfo_uses_one_uname_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log_file = root / "uname.log"
            uname = bin_dir / "uname"
            uname.write_text(
                "#!/bin/sh\n"
                'printf \'%s\\n\' "$*" >> "$UNAME_LOG"\n'
                'case "$*" in\n'
                "  -s) printf '%s\\n' Linux ;;\n"
                "  -r) printf '%s\\n' 6.8.0-test ;;\n"
                "  -sr) printf '%s\\n' 'Linux 6.8.0-test' ;;\n"
                "esac\n",
                encoding="ascii",
            )
            uname.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=0
_ai_candy_compute_sysinfo_direct
print -r -- "OS=${_AI_CANDY_PP_SYSINFO_OS_LONG}"
print -r -- "KERNEL=${_AI_CANDY_PP_SYSINFO_KERNEL_LONG}"
""",
                cache_home=root / "cache",
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "UNAME_LOG": str(log_file),
                },
            )
            uname_calls = log_file.read_text(encoding="ascii").splitlines()

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(["-sr"], uname_calls)
        self.assertIn("OS=", result.stdout)
        self.assertIn("KERNEL=, Linux-6.8.0-test", result.stdout)

    def test_warm_prompt_does_not_query_sqlite(self) -> None:
        sqlite_command = shutil.which("sqlite3")
        if sqlite_command is None:
            self.skipTest("sqlite3 is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            self._make_git_repo(repo)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log_file = root / "sqlite.log"
            sqlite = bin_dir / "sqlite3"
            sqlite.write_text(
                "#!/bin/sh\nprintf '%s\\n' called >> \"$SQLITE_LOG\"\nexec "
                f'{shlex.quote(sqlite_command)} "$@"\n',
                encoding="ascii",
            )
            sqlite.chmod(0o755)
            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do FG[$color]=""; done
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_ai_candy_precmd_compute_prompt
for attempt in {1..500}; do
  [[ ! -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]] && break
  zselect -t 1
done
[[ ! -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]] || return 70
[[ -s "$SQLITE_LOG" ]] || return 71
: >| "$SQLITE_LOG"
_ai_candy_precmd_compute_prompt
for attempt in {1..500}; do
  [[ ! -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]] && break
  zselect -t 1
done
[[ ! -s "$_AI_CANDY_CACHE_OPERATION_FILE" ]] || return 72
[[ ! -s "$SQLITE_LOG" ]] || return 73
print -r -- "WARM_SQLITE=idle"
""",
                cache_home=root / "cache",
                cwd=repo,
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "SQLITE_LOG": str(log_file),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("WARM_SQLITE=idle\n", result.stdout)

    def test_sqlite_persistence_round_trips_special_values(self) -> None:
        if shutil.which("sqlite3") is None:
            self.skipTest("sqlite3 is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
key=$'path with \'quotes\' and \x1f separators'
value=$'value \'quoted\' \x1f caf\xc3\xa9'
_ai_candy_cache_persist_write test "$key" "$value" "$EPOCHSECONDS"
write_status=$?
_ai_candy_cache_persist_read test "$key"
read_status=$?
print -r -- "WRITE=${write_status}"
print -r -- "READ=${read_status}"
print -r -- "VALUE=${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("WRITE=0", result.stdout)
        self.assertIn("READ=0", result.stdout)
        self.assertIn("VALUE=value 'quoted' \x1f caf\u00e9", result.stdout)

    def test_sqlite_database_is_private(self) -> None:
        if shutil.which("sqlite3") is None:
            self.skipTest("sqlite3 is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            cache_home = Path(tmp) / "cache"
            result = run_zsh(
                r"""
source "$1"
_ai_candy_cache_persist_write test key value "$EPOCHSECONDS"
print -r -- "BACKEND=${_AI_CANDY_CACHE_BACKEND}"
""",
                cache_home=cache_home,
            )
            database = cache_home / "zsh-prompt" / "prompt_cache.db"
            database_mode = database.stat().st_mode & 0o777

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("BACKEND=sqlite", result.stdout)
        self.assertEqual(0o600, database_mode)

    def test_sqlite_write_uses_legacy_compatible_replace_syntax(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log_file = root / "sqlite.log"
            sqlite = bin_dir / "sqlite3"
            sqlite.write_text(
                "#!/bin/sh\n"
                'for argument in "$@"; do\n'
                '  case "$argument" in\n'
                "    *'ON CONFLICT'*) exit 9 ;;\n"
                "    *'INSERT OR REPLACE'*) printf '%s\\n' replace >> \"$SQLITE_LOG\" ;;\n"
                "  esac\n"
                "done\n"
                "exit 0\n",
                encoding="ascii",
            )
            sqlite.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_ai_candy_cache_persist_write test key value "$EPOCHSECONDS"
print -r -- "STATUS=$?"
print -r -- "SYNTAX=$([[ -f "$SQLITE_LOG" ]] && print replace || print missing)"
""",
                cache_home=root / "cache",
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "SQLITE_LOG": str(log_file),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("STATUS=0", result.stdout)
        self.assertIn("SYNTAX=replace", result.stdout)

    def test_sqlite_backend_rejects_a_symlinked_database(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            cache_dir = cache_home / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            target = root / "target"
            target.write_text("sentinel\n", encoding="ascii")
            (cache_dir / "prompt_cache.db").symlink_to(target)
            result = run_zsh(
                r"""
source "$1"
_ai_candy_cache_backend_init
print -r -- "BACKEND=${_AI_CANDY_CACHE_BACKEND}"
""",
                cache_home=cache_home,
            )
            target_content = target.read_text(encoding="ascii")

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("BACKEND=none", result.stdout)
        self.assertEqual("sentinel\n", target_content)

    def test_bsd_stat_fallback_does_not_use_gnu_option_terminator(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log_file = root / "stat.log"
            stat = bin_dir / "stat"
            stat.write_text(
                "#!/bin/sh\nprintf '%s\\n' \"$*\" > \"$STAT_LOG\"\nprintf '%s\\n' 123\n",
                encoding="ascii",
            )
            stat.chmod(0o755)
            probe = root / "probe"
            probe.write_text("data\n", encoding="ascii")
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_STAT_BUILTIN=0
OSTYPE=darwin
_ai_candy_file_mtime "$PROBE_FILE"
print -r -- "MTIME=${REPLY}"
print -r -- "ARGS=$(<"$STAT_LOG")"
""",
                cache_home=root / "cache",
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "PROBE_FILE": str(probe),
                    "STAT_LOG": str(log_file),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("MTIME=123", result.stdout)
        self.assertIn(f"ARGS=-f %m {probe}", result.stdout)
        self.assertNotIn(" -- ", result.stdout)

    def test_external_file_command_fallback_preserves_path_lookup(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            file_path = root / "file"
            directory = root / "directory"
            file_path.write_text("data\n", encoding="ascii")
            directory.mkdir()
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_FILE_BUILTINS=0
_ai_candy_cache_remove_path "$FILE_PATH"
_ai_candy_cache_remove_directory "$DIRECTORY_PATH"
print -r -- "FILE=$([[ -e "$FILE_PATH" ]] && print present || print absent)"
print -r -- "DIRECTORY=$([[ -e "$DIRECTORY_PATH" ]] && print present || print absent)"
""",
                cache_home=root / "cache",
                env={
                    "FILE_PATH": str(file_path),
                    "DIRECTORY_PATH": str(directory),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("FILE=absent", result.stdout)
        self.assertIn("DIRECTORY=absent", result.stdout)

    def test_concurrent_file_cache_writers_preserve_all_entries(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
cache_file="${_AI_CANDY_CACHE_DIR}/concurrent_cache"
for index in {1..60}; do
  _ai_candy_hex_encode "key${index}"
  hex_key="$REPLY"
  _ai_candy_hex_encode "value${index}"
  hex_value="$REPLY"
  _ai_candy_cache_update_line_by_prefix \
    "$cache_file" "${hex_key}|" "${hex_key}|${hex_value}|${EPOCHSECONDS}" \
    1000 &
done
wait
lines=("${(@f)$(<"$cache_file")}")
print -r -- "COUNT=${#lines}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("COUNT=60", result.stdout)

    def test_directory_lock_fallback_recovers_an_expired_lock(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lock_dir = root / "cache.lock.d"
            lock_dir.mkdir()
            old_time = time.time() - 3600
            os.utime(lock_dir, (old_time, old_time))
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_SYSTEM=0
_ai_candy_cache_lock_acquire "$LOCK_DIR" 1 0
lock_status=$?
(( lock_status == 0 )) && _ai_candy_cache_lock_release "$LOCK_DIR"
print -r -- "STATUS=${lock_status} EXISTS=$([[ -d "$LOCK_DIR" ]] && print 1 || print 0)"
""",
                cache_home=root / "cache",
                env={"LOCK_DIR": str(lock_dir)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=0 EXISTS=0\n", result.stdout)

    def test_directory_lock_release_requires_the_owner_token(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_SYSTEM=0
_ai_candy_cache_lock_acquire "$LOCK_DIR" 300 0 || exit 3
command mv "$LOCK_DIR" "${LOCK_DIR}.old"
command mkdir -m 700 "$LOCK_DIR"
_ai_candy_cache_lock_release "$LOCK_DIR"
print -r -- "REPLACEMENT=$([[ -d "$LOCK_DIR" ]] && print present || print missing)"
""",
                cache_home=root / "cache",
                env={"LOCK_DIR": str(root / "cache.lock.d")},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("REPLACEMENT=present\n", result.stdout)

    def test_new_git_metadata_self_heals_cached_non_repository_result(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "work"
            work.mkdir()
            result = run_zsh(
                r"""
source "$1"
_ai_candy_get_cached_git_root
print -r -- "BEFORE=${REPLY}"
git init -q
_ai_candy_get_cached_git_root
print -r -- "AFTER=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=work,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("BEFORE=NOT_GIT", result.stdout)
        self.assertIn(f"AFTER={work}", result.stdout)

    def test_topology_invalidation_survives_many_unrelated_changes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            parent = root / "work"
            child = parent / "child"
            child.mkdir(parents=True)
            result = run_zsh(
                r"""
source "$1"
cd "$CHILD"
_ai_candy_get_cached_git_root
print -r -- "BEFORE=${REPLY}"
cd "$PARENT"
_ai_candy_prompt_mark_git_cache_invalidation "git init -q" "git init -q" "git init -q"
git init -q
_AI_CANDY_LAST_EXIT_STATUS=$?
_ai_candy_prompt_apply_git_cache_invalidation
for index in {1..32}; do
  _ai_candy_record_git_topology_invalidation "/unrelated/${index}"
done
cd "$CHILD"
_ai_candy_get_cached_git_root
print -r -- "AFTER=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=child,
                env={"PARENT": str(parent), "CHILD": str(child)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("BEFORE=NOT_GIT", result.stdout)
        self.assertIn(f"AFTER={parent}", result.stdout)

    def test_persistent_non_repository_cache_self_heals_after_git_init(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "work"
            work.mkdir()
            result = run_zsh(
                r"""
source "$1"
_ai_candy_sync_git_topology_generation || exit 2
cache_key="${_AI_CANDY_GIT_TOPOLOGY_GENERATION}:$PWD"
_ai_candy_cache_persist_write git_root "$cache_key" NOT_GIT "$EPOCHSECONDS" || exit 3
unset "_AI_CANDY_MEM_CACHE_GIT_ROOT[$PWD]"
git init -q
_ai_candy_get_cached_git_root
print -r -- "ROOT=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=work,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn(f"ROOT={work}", result.stdout)

    def test_failed_mutating_git_command_invalidates_cached_status(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            self._make_git_repo(repo)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_PROMPT_RENDER_ID=7
_AI_CANDY_GIT_SNAPSHOT_RENDER_ID=7
_AI_CANDY_GIT_SNAPSHOT_CONTEXT="$PWD"
_ai_candy_prompt_mark_git_cache_invalidation "git reset --hard missing-ref" "git reset --hard missing-ref" "git reset --hard missing-ref"
git reset --hard missing-ref >/dev/null 2>&1
_AI_CANDY_LAST_EXIT_STATUS=$?
_ai_candy_prompt_apply_git_cache_invalidation
print -r -- "SNAPSHOT=${_AI_CANDY_GIT_SNAPSHOT_RENDER_ID}"
""",
                cache_home=root / "cache",
                cwd=repo,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("SNAPSHOT=-1", result.stdout)

    def test_branch_snapshot_refreshes_and_escapes_prompt_metacharacters(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            self._make_git_repo(repo)
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.email", "test@example.com"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.name", "Test User"],
                check=True,
            )
            (repo / "tracked").write_text("content\n", encoding="ascii")
            subprocess.run(["git", "-C", str(repo), "add", "tracked"], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "commit", "-q", "-m", "initial"],
                check=True,
            )
            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do FG[$color]=""; done
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_ai_candy_prompt_bump_render_id
_ai_candy_precmd_compute_prompt
print -r -- "BEFORE=${_AI_CANDY_PP_GIT_INFO}"
git switch -q -c 'evil%F{red}'
_ai_candy_prompt_bump_render_id
_ai_candy_precmd_compute_prompt
print -r -- "AFTER=${_AI_CANDY_PP_GIT_INFO}"
""",
                cache_home=root / "cache",
                cwd=repo,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("main", result.stdout)
        self.assertIn("evil%%F{red}", result.stdout)

    def test_git_snapshot_uses_one_status_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log_file = root / "git.log"
            git = bin_dir / "git"
            git.write_text(
                "#!/bin/sh\n"
                'printf \'%s\\n\' "$*" >> "$GIT_LOG"\n'
                "printf '%s\\n' '# branch.oid 0123456789abcdef' '# branch.head main' '# branch.upstream origin/main' '# branch.ab +2 -3' '# stash 4' '? untracked'\n",
                encoding="ascii",
            )
            git.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_collect_git_snapshot
calls=("${(@f)$(<"$GIT_LOG")}")
status_calls=0
config_calls=0
for call in "${calls[@]}"; do
  [[ "$call" == status\ * ]] && (( status_calls++ ))
  [[ "$call" == *' config --get-regexp '* ]] && (( config_calls++ ))
done
print -r -- "STATUS_CALLS=${status_calls} CONFIG_CALLS=${config_calls}"
print -r -- "SNAPSHOT=${_AI_CANDY_GIT_SNAPSHOT_BRANCH}|${_AI_CANDY_GIT_SNAPSHOT_AHEAD}|${_AI_CANDY_GIT_SNAPSHOT_BEHIND}|${_AI_CANDY_GIT_SNAPSHOT_STASH}|${_AI_CANDY_GIT_SNAPSHOT_DIRTY}"
""",
                cache_home=root / "cache",
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "GIT_LOG": str(log_file),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("STATUS_CALLS=1 CONFIG_CALLS=1", result.stdout)
        self.assertIn("SNAPSHOT=main|2|3|4|1", result.stdout)

    def test_git_snapshot_does_not_require_status_show_stash(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            bin_dir = root / "bin"
            log_file = root / "git.log"
            repo.mkdir()
            bin_dir.mkdir()
            real_git = shutil.which("git") or "/usr/bin/git"
            subprocess.run([real_git, "-C", str(repo), "init", "-q"], check=True)
            subprocess.run(
                [real_git, "-C", str(repo), "config", "user.name", "Demo"],
                check=True,
            )
            subprocess.run(
                [real_git, "-C", str(repo), "config", "user.email", "demo@example.com"],
                check=True,
            )
            (repo / "tracked").write_text("base\n", encoding="ascii")
            subprocess.run([real_git, "-C", str(repo), "add", "tracked"], check=True)
            subprocess.run(
                [real_git, "-C", str(repo), "commit", "-qm", "base"], check=True
            )
            (repo / "tracked").write_text("stashed\n", encoding="ascii")
            subprocess.run([real_git, "-C", str(repo), "stash", "push", "-qm", "one"], check=True)
            (repo / "tracked").write_text("dirty\n", encoding="ascii")

            git = bin_dir / "git"
            git.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$GIT_LOG\"\n"
                "case \" $* \" in\n"
                "  *' --show-stash '*) exit 129 ;;\n"
                "  *) exec \"$REAL_GIT\" \"$@\" ;;\n"
                "esac\n",
                encoding="ascii",
            )
            git.chmod(0o755)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_collect_git_snapshot || return 70
first="${_AI_CANDY_GIT_SNAPSHOT_STATUS_COMPLETE}:${_AI_CANDY_GIT_SNAPSHOT_DIRTY}:${_AI_CANDY_GIT_SNAPSHOT_STASH}"
_AI_CANDY_PROMPT_RENDER_ID=2
_ai_candy_collect_git_snapshot || return 71
second="${_AI_CANDY_GIT_SNAPSHOT_STATUS_COMPLETE}:${_AI_CANDY_GIT_SNAPSHOT_DIRTY}:${_AI_CANDY_GIT_SNAPSHOT_STASH}"
calls=0
for line in "${(@f)$(<"$GIT_LOG")}"; do
  [[ "$line" == *' rev-list '* ]] && (( calls++ ))
done
builtin print -r -- "SNAPSHOT=${first}/${second} FALLBACK_CALLS=${calls}"
""",
                cache_home=root / "cache",
                cwd=repo,
                env={
                    "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}",
                    "REAL_GIT": real_git,
                    "GIT_LOG": str(log_file),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "SNAPSHOT=1:1:1/1:1:1 FALLBACK_CALLS=1\n", result.stdout
        )

    def test_omz_async_git_handler_is_registered_when_available(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
typeset -g REGISTERED=""
function _omz_async_request() { :; }
function _omz_register_handler() { REGISTERED="$1"; }
source "$1"
print -r -- "ENABLED=${_AI_CANDY_USE_OMZ_ASYNC}"
print -r -- "REGISTERED=${REGISTERED}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("ENABLED=1", result.stdout)
        self.assertIn("REGISTERED=_ai_candy_git_prompt_async", result.stdout)

    def test_git_invalidation_precedes_the_omz_async_request_hook(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
autoload -Uz add-zsh-hook
typeset -ga precmd_functions=(_omz_async_request)
function _omz_async_request() { return 0; }
function _omz_register_handler() { return 0; }
zstyle ':omz:alpha:lib:git' async-prompt force
source "$1"
print -r -- \
  "CAPTURE=${precmd_functions[(i)_ai_candy_capture_exit_status]} INVALIDATE=${precmd_functions[(i)_ai_candy_prompt_apply_git_cache_invalidation]} CONTEXT=${precmd_functions[(i)_ai_candy_prompt_sync_async_git_context]} ASYNC=${precmd_functions[(i)_omz_async_request]}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "CAPTURE=1 INVALIDATE=2 CONTEXT=3 ASYNC=4\n", result.stdout
        )

    def test_omz_async_git_handler_respects_explicit_disable(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
zstyle ':omz:alpha:lib:git' async-prompt no
typeset -g REGISTERED=""
function _omz_async_request() { :; }
function _omz_register_handler() { REGISTERED="$1"; }
source "$1"
print -r -- "ENABLED=${_AI_CANDY_USE_OMZ_ASYNC}"
print -r -- "REGISTERED=${REGISTERED}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("ENABLED=0", result.stdout)
        self.assertIn("REGISTERED=\n", result.stdout)

    def test_external_remote_change_refreshes_the_pr_cache_key(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            self._make_git_repo(repo)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "remote",
                    "add",
                    "origin",
                    "https://example.test/one.git",
                ],
                check=True,
            )
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_GIT_CONFIG_CACHE_TTL=0
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_get_cached_git_remote_branch
print -r -- "FIRST=${REPLY%%|*}"
/bin/sh -c 'git remote set-url origin https://example.test/two.git'
_AI_CANDY_PROMPT_RENDER_ID=2
_ai_candy_get_cached_git_remote_branch
print -r -- "SECOND=${REPLY%%|*}"
""",
                cache_home=root / "cache",
                cwd=repo,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        keys = [line.partition("=")[2] for line in result.stdout.splitlines()]
        self.assertEqual(2, len(keys), result.stdout)
        self.assertTrue(all(keys))
        self.assertNotEqual(keys[0], keys[1])

    def test_git_topology_invalidation_uses_the_actual_subcommand(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_ai_candy_prompt_mark_git_cache_invalidation \
  "git commit -m init" "git commit -m init" "git commit -m init"
print -r -- "STATUS=${_AI_CANDY_PROMPT_GIT_CACHE_INVALIDATE}"
print -r -- "TOPOLOGY=${_AI_CANDY_PROMPT_GIT_TOPOLOGY_INVALIDATE}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("STATUS=1", result.stdout)
        self.assertIn("TOPOLOGY=0", result.stdout)

    def test_prompt_renders_with_nounset_enabled(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do
  FG[$color]=""
done
setopt nounset
unset VIRTUAL_ENV SSH_CONNECTION XDG_SESSION_DESKTOP XDG_SESSION_TYPE
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_ai_candy_precmd_compute_prompt
print -r -- READY
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("READY\n", result.stdout)
        self.assertEqual("", result.stderr)

    def test_theme_sources_cleanly_with_nounset_without_omz_colors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                'setopt nounset\nsource "$1"\nprint -r -- READY\n',
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("READY\n", result.stdout)
        self.assertEqual("", result.stderr)

    def test_prompt_tolerates_optional_probe_failures_with_errexit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            uname = bin_dir / "uname"
            uname.write_text("#!/bin/sh\nexit 1\n", encoding="ascii")
            uname.chmod(0o755)
            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do FG[$color]=""; done
setopt errexit nounset pipefail
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=1
_ai_candy_precmd_compute_prompt
[[ -o errexit ]]
print -r -- READY
""",
                cache_home=root / "cache",
                cwd=root,
                env={"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("READY\n", result.stdout)

    def test_ssh_username_refresh_accepts_status_one_with_errexit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            ssh = bin_dir / "ssh"
            ssh.write_text(
                "#!/bin/sh\nprintf '%s\\n' 'Hi fixture-user! Authentication succeeded.' >&2\nexit 1\n",
                encoding="ascii",
            )
            ssh.chmod(0o755)
            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do FG[$color]=""; done
setopt errexit nounset pipefail
source "$1"
_AI_CANDY_NETWORK_TIMEOUT=1
_ai_candy_gh_username_update_ssh
for attempt in {1..300}; do
  if [[ -f "$_AI_CANDY_GH_USERNAME_SSH_CACHE_FILE" ]]; then
    break
  fi
  zselect -t 1 || true
done
[[ -f "$_AI_CANDY_GH_USERNAME_SSH_CACHE_FILE" ]]
cache_value=$(<"$_AI_CANDY_GH_USERNAME_SSH_CACHE_FILE")
print -r -- "CACHE=${cache_value%%|*}"
""",
                cache_home=root / "cache",
                env={"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CACHE=fixture-user\n", result.stdout)

    def test_malformed_sysinfo_cache_does_not_crash_with_nounset(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            (cache_dir / "sysinfo_cache").write_text(
                f"{int(time.time())}\n",
                encoding="ascii",
            )
            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do FG[$color]=""; done
setopt nounset
source "$1"
_AI_CANDY_PROMPT_OS_MODE=1
_ai_candy_compute_sysinfo_direct
print -r -- READY
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("READY\n", result.stdout)

    def test_oversized_cache_timestamp_is_treated_as_invalid(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            oversized = "9" * 100
            (cache_dir / "sysinfo_cache").write_text(
                f"{oversized}\nv2||||\n",
                encoding="ascii",
            )
            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do FG[$color]=""; done
setopt nounset
source "$1"
_AI_CANDY_PROMPT_OS_MODE=1
_ai_candy_compute_sysinfo_direct
print -r -- READY
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("READY\n", result.stdout)

    def test_corrupted_display_caches_cannot_inject_prompt_escapes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            now = str(int(time.time()))
            separator = "\x1f"
            (cache_dir / "public_ip_cache").write_text(
                f"%F{{red}}|{now}\n", encoding="ascii"
            )
            (cache_dir / "gh_username_gh").write_text(
                f"%F{{red}}|{now}\n", encoding="ascii"
            )
            (cache_dir / "claude_version_cache").write_text(
                f"%F{{red}}{separator}1.2.3{separator}{now}\n", encoding="ascii"
            )
            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do FG[$color]=""; done
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=1
_AI_CANDY_HAS_GH=0
_AI_CANDY_HAS_SSH=0
_AI_CANDY_HAS_CURL=1
function _ai_candy_public_ip_update_background() { :; }
_ai_candy_compute_public_ip_direct
_ai_candy_compute_gh_username_direct
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=1
_AI_CANDY_AI_TOOLS_DETECTED=1
_AI_CANDY_HAS_CLAUDE=1
_AI_CANDY_HAS_CODEX=0
_AI_CANDY_HAS_GEMINI=0
_AI_CANDY_HAS_KIMI=0
_AI_CANDY_AI_PROCESS_SNAPSHOT_TIME=$EPOCHSECONDS
_ai_candy_compute_ai_tools_direct
function _ai_candy_gh_is_authenticated() { return 0; }
function _ai_candy_get_cached_git_remote_branch() { REPLY='remote|branch'; }
function _ai_candy_gh_pr_update_cache() { :; }
_AI_CANDY_PROMPT_NETWORK_MODE=1
_AI_CANDY_HAS_GH=1
_AI_CANDY_HAS_HASH_CMD=1
_AI_CANDY_PROMPT_RENDER_ID=9
_AI_CANDY_MEM_CACHE_GH_PR['remote|branch']="%F{red}|pass|${EPOCHSECONDS}"
_ai_candy_compute_pr_status_direct
print -r -- "PUBLIC=${_AI_CANDY_PP_PUBLIC_IP}"
print -r -- "GH=${_AI_CANDY_PP_GH_USER}"
print -r -- "AI=${_AI_CANDY_PP_AI_STATUS}"
print -r -- "PR=${_AI_CANDY_PP_PR}"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("PUBLIC=", result.stdout)
        for prefix in ("GH=", "AI=", "PR="):
            self.assertIn(f"{prefix}\n", result.stdout)
        self.assertNotIn("%F{red}", result.stdout)

    def test_oversized_ipv4_octet_is_rejected_without_arithmetic_errors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
if _ai_candy_valid_ipv4_address "999999999999999999999999999999999999.1.1.1"; then
  print -r -- ACCEPTED
else
  print -r -- REJECTED
fi
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode)
        self.assertEqual("REJECTED\n", result.stdout)
        self.assertEqual("", result.stderr)

    def test_disabled_os_segment_does_not_shorten_the_layout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
COLUMNS=160
_AI_CANDY_PROMPT_EMOJI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_AI_CANDY_PP_SYSINFO_OS_LONG="${(l:200::X:)}"
_AI_CANDY_PP_SYSINFO_OS_SHORT="${(l:200::X:)}"
_AI_CANDY_PP_SYSINFO_KERNEL_LONG=""
_AI_CANDY_PP_SYSINFO_KERNEL_SHORT=""
_AI_CANDY_PP_AI_STATUS=""
_AI_CANDY_PP_AI_STATUS_LONG=""
_AI_CANDY_PP_GIT_INFO=""
_AI_CANDY_PP_GIT_EXT=""
_AI_CANDY_PP_GIT_SPECIAL=""
_AI_CANDY_PP_PR=""
_AI_CANDY_PP_GH_USER=""
_AI_CANDY_PP_EXIT=""
_AI_CANDY_PP_SSH=""
_AI_CANDY_PP_PUBLIC_IP=""
_AI_CANDY_PP_CACHED_GIT_ROOT="NOT_GIT"
typeset -g _TEST_PATH_CALLS=""
function _ai_candy_compute_smart_path_direct() {
  _TEST_PATH_CALLS+="${1},"
  _AI_CANDY_PP_PATH="[x]"
}
_ai_candy_compute_layout_mode
print -r -- "CALLS=${_TEST_PATH_CALLS}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CALLS=full,\n", result.stdout)

    def test_git_status_timeout_is_not_retried(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            status_log = root / "status.log"
            result = run_zsh(
                r"""
source "$1"
function _ai_candy_run_local_probe() {
  local argument saw_git=0 saw_status=0
  for argument in "$@"; do
    [[ "$argument" == git ]] && saw_git=1
    [[ "$argument" == status ]] && saw_status=1
  done
  if (( saw_git && saw_status )); then
    print -r -- called >> "$STATUS_LOG"
    return 124
  fi
  return 1
}
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_collect_git_snapshot
calls=0
if [[ -f "$STATUS_LOG" ]]; then
  entries=("${(@f)$(<"$STATUS_LOG")}")
  calls=${#entries}
fi
print -r -- "STATUS_CALLS=${calls}"
""",
                cache_home=root / "cache",
                env={"STATUS_LOG": str(status_log)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS_CALLS=1\n", result.stdout)

    def test_failed_git_snapshot_uses_head_and_short_retry_backoff(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            status_log = root / "snapshot-status.log"
            self._make_git_repo(repo)
            subprocess.run(
                ["git", "-C", str(repo), "symbolic-ref", "HEAD", "refs/heads/main"],
                check=True,
            )
            result = run_zsh(
                r"""
source "$1"
functions[_probe_without_snapshot_failure]="${functions[_ai_candy_run_local_probe]}"
function _ai_candy_run_local_probe() {
  local argument saw_status=0
  for argument in "$@"; do
    [[ "$argument" == status ]] && saw_status=1
  done
  if (( saw_status )); then
    builtin print -r -- called >> "$STATUS_LOG"
    return 125
  fi
  _probe_without_snapshot_failure "$@"
}
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_collect_git_snapshot
first="${_AI_CANDY_GIT_SNAPSHOT_VALID}:${_AI_CANDY_GIT_SNAPSHOT_BRANCH}"
ZSH_THEME_GIT_PROMPT_CLEAN=CLEAN
_ai_candy_format_git_snapshot
first_info="$_AI_CANDY_GIT_FORMATTED_INFO"
_AI_CANDY_PROMPT_RENDER_ID=2
_ai_candy_collect_git_snapshot
status_calls=0
if [[ -f "$STATUS_LOG" ]]; then
  calls=("${(@f)$(<"$STATUS_LOG")}")
  status_calls=${#calls}
fi
print -r -- \
  "FIRST=${first} SECOND=${_AI_CANDY_GIT_SNAPSHOT_VALID}:${_AI_CANDY_GIT_SNAPSHOT_BRANCH} CALLS=${status_calls} INFO=${first_info}"
""",
                cache_home=root / "cache",
                cwd=repo,
                env={"STATUS_LOG": str(status_log)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("FIRST=1:main SECOND=1:main CALLS=1", result.stdout)
        self.assertIn("main", result.stdout)
        self.assertNotIn("CLEAN", result.stdout)

    def test_bare_git_commands_do_not_crash_with_nounset(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
setopt nounset
_ai_candy_prompt_git_command_affects_cached_status "git" || true
_ai_candy_prompt_git_command_affects_cached_status "command git --" || true
_ai_candy_prompt_git_command_affects_cached_status "sudo -n git" || true
print -r -- READY
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("READY\n", result.stdout)

    def test_expired_auth_cache_observes_background_refresh_promptly(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            (cache_dir / "gh_auth_cache").write_text("0|1\n", encoding="ascii")
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_GH_AUTH_REFRESH_RETRY_DELAY=3
function _ai_candy_gh_auth_update_background() {
  _ai_candy_cache_write "$_AI_CANDY_GH_AUTH_CACHE_FILE" "1|${EPOCHSECONDS}"
}
if _ai_candy_gh_is_authenticated; then before=1; else before=0; fi
(( _AI_CANDY_GH_AUTH_MEM_CACHE_TIME -= 4 ))
if _ai_candy_gh_is_authenticated; then after=1; else after=0; fi
print -r -- "BEFORE=${before} AFTER=${after}"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("BEFORE=0 AFTER=1\n", result.stdout)

    def test_raw_c1_bytes_are_neutralized_but_utf8_is_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_ai_candy_prompt_escape_text $'A\x9b31mB'
_ai_candy_hex_encode "$REPLY"
print -r -- "C1=${REPLY}"
_ai_candy_prompt_escape_text $'caf\xc3\xa9-\xf0\x9f\x98\x80-100%'
_ai_candy_hex_encode "$REPLY"
print -r -- "UTF8=${REPLY}"
_ai_candy_prompt_escape_text $'\xe1\x80A'
_ai_candy_hex_encode "$REPLY"
print -r -- "INVALID3=${REPLY}"
_ai_candy_prompt_escape_text $'\xf1\x80\x80A'
_ai_candy_hex_encode "$REPLY"
print -r -- "INVALID4=${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("C1=413F33316D42", result.stdout)
        self.assertIn("UTF8=636166C3A92DF09F98802D3130302525", result.stdout)
        self.assertIn("INVALID3=3F3F41", result.stdout)
        self.assertIn("INVALID4=3F3F3F41", result.stdout)

    def test_malformed_and_future_timestamps_trigger_refresh(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            (cache_dir / "public_ip_cache").write_text(
                "203.0.113.42|invalid\n", encoding="ascii"
            )
            result = run_zsh(
                r"""
source "$1"
typeset -g REFRESH_CALLS=0
_AI_CANDY_PROMPT_NETWORK_MODE=1
_AI_CANDY_HAS_CURL=1
function _ai_candy_public_ip_update_background() { (( REFRESH_CALLS++ )); }
_ai_candy_compute_public_ip_direct
_ai_candy_cache_timestamp_is_fresh "$(( EPOCHSECONDS + 10000 ))" 300 "$EPOCHSECONDS"
future_status=$?
print -r -- "IP=${_AI_CANDY_PP_PUBLIC_IP} REFRESH=${REFRESH_CALLS} FUTURE=${future_status}"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("203.0.113.42", result.stdout)
        self.assertIn("REFRESH=1 FUTURE=1", result.stdout)

    def test_fresh_negative_public_ip_cache_suppresses_refresh(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            (cache_dir / "public_ip_cache").write_text(
                f"|{int(time.time())}\n", encoding="ascii"
            )
            result = run_zsh(
                r"""
autoload -Uz colors
colors
source "$1"
typeset -g REFRESH_CALLS=0
_AI_CANDY_PROMPT_NETWORK_MODE=1
_AI_CANDY_HAS_CURL=1
function _ai_candy_public_ip_update_background() { (( REFRESH_CALLS++ )); }
_ai_candy_compute_public_ip_direct
_ai_candy_compute_public_ip_direct
print -r -- "CALLS=${REFRESH_CALLS} DISPLAY=${_AI_CANDY_PP_PUBLIC_IP}"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("CALLS=0", result.stdout)
        self.assertIn("offline", result.stdout)

    def test_expired_negative_public_ip_cache_requests_refresh(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_dir = root / "cache" / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            (cache_dir / "public_ip_cache").write_text("|1\n", encoding="ascii")
            result = run_zsh(
                r"""
source "$1"
typeset -g REFRESH_CALLS=0
_AI_CANDY_PROMPT_NETWORK_MODE=1
_AI_CANDY_HAS_CURL=1
function _ai_candy_public_ip_update_background() { (( REFRESH_CALLS++ )); }
_ai_candy_compute_public_ip_direct
print -r -- "CALLS=${REFRESH_CALLS}"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("CALLS=1\n", result.stdout)

    def test_future_git_root_timestamp_is_recomputed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            self._make_git_repo(repo)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_MEM_CACHE_GIT_ROOT[$PWD]="/wrong|$(( EPOCHSECONDS + 10000 ))"
_ai_candy_get_cached_git_root
print -r -- "ROOT=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=repo,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(f"ROOT={repo}\n", result.stdout)

    def test_theme_does_not_delete_preexisting_user_functions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
function _append_ai_tool() { print -r -- USER_APPEND; }
function _tsl() { print -r -- USER_TSL; }
_AI_CANDY_PROMPT_AI_MODE=1
_AI_CANDY_AI_TOOLS_DETECTED=1
_AI_CANDY_HAS_CLAUDE=0
_AI_CANDY_HAS_CODEX=0
_AI_CANDY_HAS_GEMINI=0
_AI_CANDY_HAS_KIMI=0
_ai_candy_compute_ai_tools_direct
_AI_CANDY_PROMPT_NETWORK_MODE=0
_ai_candy_prompt_tool_status >/dev/null
_append_ai_tool
_tsl
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("USER_APPEND\nUSER_TSL\n", result.stdout)

    def test_theme_does_not_replace_generic_user_functions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
function _cache_write() { print -r -- USER_CACHE_WRITE; }
function _prompt_measure_text() { print -r -- USER_MEASURE_TEXT; }
source "$1"
_cache_write
_prompt_measure_text
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("USER_CACHE_WRITE\nUSER_MEASURE_TEXT\n", result.stdout)

    def test_short_aliases_are_opt_in_and_preserve_user_symbols(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            default_result = run_zsh(
                r"""
source "$1"
print -r -- "DEFAULT=${+aliases[e]}${+aliases[p]}${+aliases[u]}"
""",
                cache_home=Path(tmp) / "default-cache",
            )
            enabled_result = run_zsh(
                r"""
alias e='print existing-alias'
function n() { print -r -- existing-function; }
AI_CANDY_ENABLE_SHORT_ALIASES=1
source "$1"
print -r -- "E=${aliases[e]}"
print -r -- "N=${functions[n]}"
print -r -- "P=${aliases[p]}"
""",
                cache_home=Path(tmp) / "enabled-cache",
            )

        self.assertEqual(0, default_result.returncode, default_result.stderr)
        self.assertEqual("DEFAULT=000\n", default_result.stdout)
        self.assertEqual(0, enabled_result.returncode, enabled_result.stderr)
        self.assertIn("E=print existing-alias", enabled_result.stdout)
        self.assertIn("existing-function", enabled_result.stdout)
        self.assertIn("P=_ai_candy_prompt_toggle_path_sep", enabled_result.stdout)

    def test_source_restores_options_and_prompt_handles_ksh_arrays(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
setopt ksharrays globsubst
source "$1" || return
print -r -- "OPTIONS=${options[ksharrays]}:${options[globsubst]}"
_ai_candy_prompt_measure_text "ab" 0
print -r -- "WIDTH=${REPLY}"
autoload -Uz colors
colors
COLUMNS=120
_ai_candy_precmd_compute_prompt
print -r -- "PROMPT=ok"
""",
                cache_home=Path(tmp) / "cache",
                timeout=4,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("OPTIONS=on:on", result.stdout)
        self.assertIn("WIDTH=2", result.stdout)
        self.assertIn("PROMPT=ok", result.stdout)

    def test_source_preserves_a_readonly_legacy_global_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            legacy_name = "_CACHE" + "_DIR"
            result = run_zsh(
                r"""
typeset -gr "${LEGACY_GLOBAL}=reserved"
source "$1" || return
print -r -- "VALUE=${(P)LEGACY_GLOBAL}"
""",
                cache_home=Path(tmp) / "cache",
                env={"LEGACY_GLOBAL": legacy_name},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("VALUE=reserved\n", result.stdout)

    def test_omz_git_visibility_settings_and_exact_tags_are_preserved(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            self._make_git_repo(repo)
            (repo / "tracked").write_text("base\n", encoding="ascii")
            subprocess.run(["git", "-C", str(repo), "add", "tracked"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "-c",
                    "user.name=Demo",
                    "-c",
                    "user.email=demo@example.invalid",
                    "commit",
                    "-qm",
                    "initial",
                ],
                check=True,
            )
            subprocess.run(["git", "-C", str(repo), "tag", "v1.0.0"], check=True)
            (repo / "tracked").write_text("dirty\n", encoding="ascii")

            def render(extra: str) -> subprocess.CompletedProcess[str]:
                return run_zsh(
                    rf"""
autoload -Uz colors
colors
typeset -gA FG
for color in {{0..255}}; do FG[$color]=""; done
source "$1"
{extra}
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_collect_git_snapshot
_ai_candy_format_git_snapshot
print -r -- "INFO=${{_AI_CANDY_GIT_FORMATTED_INFO}}"
""",
                    cache_home=root / "cache",
                    cwd=repo,
                )

            subprocess.run(
                ["git", "-C", str(repo), "config", "oh-my-zsh.hide-info", "1"],
                check=True,
            )
            hidden = render("")
            subprocess.run(
                ["git", "-C", str(repo), "config", "--unset", "oh-my-zsh.hide-info"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(repo), "config", "oh-my-zsh.hide-dirty", "1"],
                check=True,
            )
            clean = render("")
            subprocess.run(
                ["git", "-C", str(repo), "config", "--unset", "oh-my-zsh.hide-dirty"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(repo), "checkout", "-q", "--detach", "v1.0.0"],
                check=True,
            )
            tagged = render("")

        self.assertEqual(0, hidden.returncode, hidden.stderr)
        self.assertEqual("INFO=\n", hidden.stdout)
        self.assertEqual(0, clean.returncode, clean.stderr)
        self.assertNotIn("*", clean.stdout)
        self.assertEqual(0, tagged.returncode, tagged.stderr)
        self.assertIn("v1.0.0", tagged.stdout)

    def test_external_omz_config_change_is_observed_after_cache_expiry(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            self._make_git_repo(repo)
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.email", "test@example.com"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.name", "Test User"],
                check=True,
            )
            (repo / "tracked").write_text("content\n", encoding="ascii")
            subprocess.run(["git", "-C", str(repo), "add", "tracked"], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "commit", "-q", "-m", "initial"],
                check=True,
            )
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_GIT_CONFIG_CACHE_TTL=0
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_collect_git_snapshot
_ai_candy_format_git_snapshot
print -r -- "BEFORE=${_AI_CANDY_GIT_FORMATTED_INFO}"
/bin/sh -c 'git config oh-my-zsh.hide-info 1'
_AI_CANDY_PROMPT_RENDER_ID=2
_ai_candy_collect_git_snapshot
_ai_candy_format_git_snapshot
print -r -- "AFTER=${_AI_CANDY_GIT_FORMATTED_INFO}"
""",
                cache_home=root / "cache",
                cwd=repo,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        before_line = next(
            line for line in result.stdout.splitlines() if line.startswith("BEFORE=")
        )
        self.assertIn("main", before_line)
        self.assertIn("AFTER=\n", result.stdout)

    def test_git_snapshot_handles_expected_misses_with_errexit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            self._make_git_repo(repo)
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.email", "test@example.com"],
                check=True,
            )
            subprocess.run(
                ["git", "-C", str(repo), "config", "user.name", "Test User"],
                check=True,
            )
            (repo / "tracked.txt").write_text("content\n", encoding="ascii")
            subprocess.run(["git", "-C", str(repo), "add", "tracked.txt"], check=True)
            subprocess.run(
                ["git", "-C", str(repo), "commit", "-q", "-m", "initial"],
                check=True,
            )
            result = run_zsh(
                r"""
autoload -Uz colors
colors
setopt errexit nounset pipefail
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_collect_git_snapshot
print -r -- "BRANCH=${_AI_CANDY_GIT_SNAPSHOT_VALID}"
git checkout -q --detach
_AI_CANDY_PROMPT_RENDER_ID=2
_ai_candy_collect_git_snapshot
print -r -- "DETACHED=${_AI_CANDY_GIT_SNAPSHOT_VALID} TAG=${_AI_CANDY_GIT_SNAPSHOT_TAG}"
""",
                cache_home=root / "cache",
                cwd=repo,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("BRANCH=1", result.stdout)
        self.assertIn("DETACHED=1 TAG=", result.stdout)

    def test_invalid_boolean_settings_use_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cache_home = Path(tmp) / "cache"
            cache_dir = cache_home / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            for setting in (
                "emoji_mode",
                "path_sep_mode",
                "network_mode",
                "ai_mode",
                "os_mode",
            ):
                (cache_dir / setting).write_text("invalid\n", encoding="ascii")

            result = run_zsh(
                r"""
source "$1"
print -r -- "VALUES=${_AI_CANDY_PROMPT_EMOJI_MODE}${_AI_CANDY_PROMPT_PATH_SEP_MODE}${_AI_CANDY_PROMPT_NETWORK_MODE}${_AI_CANDY_PROMPT_AI_MODE}${_AI_CANDY_PROMPT_OS_MODE}"
""",
                cache_home=cache_home,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("VALUES=11111", result.stdout)

    def test_symlinked_boolean_setting_is_not_read(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            cache_dir = cache_home / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            victim = root / "victim"
            victim.write_text("0\n", encoding="ascii")
            (cache_dir / "emoji_mode").symlink_to(victim)

            result = run_zsh(
                r"""
source "$1"
print -r -- "EMOJI=${_AI_CANDY_PROMPT_EMOJI_MODE}"
""",
                cache_home=cache_home,
            )
            victim_content = victim.read_text(encoding="ascii")

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("EMOJI=1\n", result.stdout)
        self.assertEqual("0\n", victim_content)

    def test_exit_status_hook_captures_the_previous_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
false
_ai_candy_capture_exit_status
print -r -- "STATUS=${_AI_CANDY_LAST_EXIT_STATUS}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=1\n", result.stdout)

    def test_repeated_source_registers_each_hook_once(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
source "$1"
for hook in _ai_candy_capture_exit_status _ai_candy_prompt_apply_git_cache_invalidation _ai_candy_prompt_bump_render_id _ai_candy_precmd_compute_prompt _ai_candy_periodic_cache_cleanup; do
  matches=("${(@)precmd_functions:#${hook}}")
  print -r -- "${hook}=$(( ${#precmd_functions} - ${#matches} ))"
done
matches=("${(@)preexec_functions:#_ai_candy_prompt_mark_git_cache_invalidation}")
print -r -- "_ai_candy_prompt_mark_git_cache_invalidation=$(( ${#preexec_functions} - ${#matches} ))"
matches=("${(@)zshexit_functions:#_ai_candy_stop_registered_background_jobs}")
print -r -- "_ai_candy_stop_registered_background_jobs=$(( ${#zshexit_functions} - ${#matches} ))"
matches=("${(@)chpwd_functions:#_ai_candy_capture_physical_pwd}")
print -r -- "_ai_candy_capture_physical_pwd=$(( ${#chpwd_functions} - ${#matches} ))"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        for line in result.stdout.splitlines():
            self.assertTrue(line.endswith("=1"), line)

    def test_virtual_environment_name_is_prompt_escaped(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
autoload -Uz colors
colors
source "$1"
VIRTUAL_ENV='/tmp/venv%F{red}'
_ai_candy_compute_venv_direct
print -r -- "VENV=${_AI_CANDY_PP_VENV}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("venv%%F{red}", result.stdout)

    def test_ai_version_worker_is_bounded_and_releases_lock(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            tool = bin_dir / "slow-tool"
            tool.write_text("#!/bin/sh\nsleep 2\n", encoding="ascii")
            tool.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
cache_file="${_AI_CANDY_CACHE_DIR}/slow_tool_cache"
start=$EPOCHREALTIME
_ai_candy_ai_tool_update_cache "$cache_file" slow-tool 'https://invalid.example/version'
worker_pid="${_AI_CANDY_BACKGROUND_PIDS[-1]-}"
[[ "$worker_pid" == <-> ]] || exit 3
deadline=$(( EPOCHREALTIME + 1.8 ))
while _ai_candy_background_pid_is_owned "$worker_pid" && (( EPOCHREALTIME < deadline )); do
  zselect -t 1
done
elapsed=$(( EPOCHREALTIME - start ))
print -r -- "WORKER=$(_ai_candy_background_pid_is_owned "$worker_pid" && print running || print stopped)"
print -r -- "LOCK=$([[ -e ${cache_file}.updating.d ]] && print present || print absent)"
print -r -- "ELAPSED=${elapsed}"
""",
                cache_home=root / "cache",
                env={"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("WORKER=stopped", result.stdout)
        self.assertIn("LOCK=absent", result.stdout)
        elapsed_line = next(
            line for line in result.stdout.splitlines() if line.startswith("ELAPSED=")
        )
        self.assertLess(float(elapsed_line.partition("=")[2]), 1.5)


if __name__ == "__main__":
    unittest.main()
