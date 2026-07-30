#!/usr/bin/env python3
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from tests.theme_test_support import THEME, run_zsh


class GitRuntimeTest(unittest.TestCase):
    def test_git_config_failure_is_not_cached_as_not_git(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            child = repo / "child"
            bad_config = root / "bad.gitconfig"
            child.mkdir(parents=True)
            bad_config.write_text("[broken\n", encoding="ascii")
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)

            result = run_zsh(
                r"""
source "$1"
_ai_candy_get_cached_git_root
first="$REPLY"
GIT_CONFIG_GLOBAL=/dev/null
_ai_candy_get_cached_git_root
print -r -- "FIRST=${first} SECOND=${REPLY}"
_ai_candy_stop_registered_background_jobs
""",
                cache_home=root / "cache",
                cwd=child,
                env={"GIT_CONFIG_GLOBAL": str(bad_config)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(f"FIRST=NOT_GIT SECOND={repo}\n", result.stdout)

    def test_transient_root_probe_failure_is_not_cached_as_not_git(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            child = repo / "child"
            failure_marker = root / "probe.failed"
            child.mkdir(parents=True)
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)

            result = run_zsh(
                r"""
source "$1"
functions[_probe_without_transient_failure]="${functions[_ai_candy_run_local_probe]}"
function _ai_candy_run_local_probe() {
  if [[ "$1" == git && "$2" == rev-parse && "$3" == --show-toplevel && \
        ! -e "$FAILURE_MARKER" ]]; then
    builtin print -r -- failed >| "$FAILURE_MARKER"
    return 124
  fi
  _probe_without_transient_failure "$@"
}
_ai_candy_get_cached_git_root
first="$REPLY"
_ai_candy_get_cached_git_root
second="$REPLY"
print -r -- "FIRST=${first} SECOND=${second}"
_ai_candy_stop_registered_background_jobs
""",
                cache_home=root / "cache",
                cwd=child,
                env={"FAILURE_MARKER": str(failure_marker)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(f"FIRST=NOT_GIT SECOND={repo}\n", result.stdout)

    def test_git_directory_pointer_cannot_be_a_symbolic_link(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "work"
            git_dir = root / "metadata"
            pointer = root / "pointer"
            work.mkdir()
            git_dir.mkdir()
            pointer.write_text(f"gitdir: {git_dir}\n", encoding="ascii")
            (work / ".git").symlink_to(pointer)

            result = run_zsh(
                r"""
source "$1"
if _ai_candy_resolve_git_dir "$PWD"; then
  print -r -- "STATE=resolved:${REPLY}"
else
  print -r -- "STATE=rejected"
fi
""",
                cache_home=root / "cache",
                cwd=work,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATE=rejected\n", result.stdout)

    def test_topology_change_invalidates_positive_root_and_hierarchy_caches(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            outer = root / "outer"
            child = outer / "child"
            child.mkdir(parents=True)
            subprocess.run(["git", "-C", str(outer), "init", "-q"], check=True)
            result = run_zsh(
                r"""
source "$1"
cd "$CHILD"
_ai_candy_get_cached_git_root
before_root="$REPLY"
_PP_CACHED_GIT_ROOT="$before_root"
_ai_candy_get_git_hierarchy
before_hierarchy="$REPLY"
cd "$OUTER"
_ai_candy_prompt_mark_git_cache_invalidation \
  "git init -q child" "git init -q child" "git init -q child"
git init -q child
_LAST_EXIT_STATUS=$?
_ai_candy_prompt_apply_git_cache_invalidation
cd "$CHILD"
_ai_candy_get_cached_git_root
after_root="$REPLY"
_PP_CACHED_GIT_ROOT="$after_root"
_ai_candy_get_git_hierarchy
after_hierarchy="$REPLY"
print -r -- "BEFORE_ROOT=${before_root}"
print -r -- "AFTER_ROOT=${after_root}"
print -r -- "SAME_HIERARCHY=$([[ $before_hierarchy == $after_hierarchy ]] && print yes || print no)"
""",
                cache_home=root / "cache",
                cwd=child,
                env={"OUTER": str(outer), "CHILD": str(child)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn(f"BEFORE_ROOT={outer}", result.stdout)
        self.assertIn(f"AFTER_ROOT={child}", result.stdout)
        self.assertIn("SAME_HIERARCHY=no", result.stdout)

    def test_git_dash_c_topology_change_invalidates_other_path_caches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            control = root / "control"
            target = root / "target"
            child = target / "child"
            control.mkdir()
            child.mkdir(parents=True)
            result = run_zsh(
                r"""
source "$1"
cd "$CHILD"
_ai_candy_get_cached_git_root
before="$REPLY"
cd "$CONTROL"
_ai_candy_prompt_mark_git_cache_invalidation \
  "git -C $TARGET init -q" "git -C $TARGET init -q" "git -C $TARGET init -q"
git -C "$TARGET" init -q
_LAST_EXIT_STATUS=$?
_ai_candy_prompt_apply_git_cache_invalidation
cd "$CHILD"
_ai_candy_get_cached_git_root
print -r -- "BEFORE=${before} AFTER=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=control,
                env={
                    "CONTROL": str(control),
                    "TARGET": str(target),
                    "CHILD": str(child),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(f"BEFORE=NOT_GIT AFTER={target}\n", result.stdout)

    def test_absolute_git_path_invalidates_dash_c_topology_changes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            control = root / "control"
            target = root / "target"
            child = target / "child"
            control.mkdir()
            child.mkdir(parents=True)
            git_command = shutil.which("git") or "/usr/bin/git"
            result = run_zsh(
                r"""
source "$1"
cd "$CHILD"
_ai_candy_get_cached_git_root
before="$REPLY"
cd "$CONTROL"
command_text="$GIT_COMMAND -C $TARGET init -q"
_ai_candy_prompt_mark_git_cache_invalidation \
  "$command_text" "$command_text" "$command_text"
"$GIT_COMMAND" -C "$TARGET" init -q
_LAST_EXIT_STATUS=$?
_ai_candy_prompt_apply_git_cache_invalidation
cd "$CHILD"
_ai_candy_get_cached_git_root
print -r -- "BEFORE=${before} AFTER=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=control,
                env={
                    "CONTROL": str(control),
                    "TARGET": str(target),
                    "CHILD": str(child),
                    "GIT_COMMAND": git_command,
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(f"BEFORE=NOT_GIT AFTER={target}\n", result.stdout)

    def test_git_detection_handles_shell_syntax_and_quoted_text(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
if _ai_candy_prompt_git_command_affects_cached_status \
     "print -r -- '/usr/bin/git init'"; then
  quoted=marked
else
  quoted=ignored
fi
if _ai_candy_prompt_git_command_affects_cached_status \
     "true && command /usr/bin/git init"; then
  actual="marked:${REPLY}"
else
  actual=ignored
fi
if _ai_candy_prompt_git_command_affects_cached_status "! /usr/bin/git init -q"; then
  negated="marked:${REPLY}"
else
  negated=ignored
fi
if _ai_candy_prompt_git_command_affects_cached_status \
     "if /usr/bin/git init -q; then :; fi"; then
  conditional="marked:${REPLY}"
else
  conditional=ignored
fi
print -r -- "QUOTED=${quoted} ACTUAL=${actual} NEGATED=${negated} CONDITIONAL=${conditional}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "QUOTED=ignored ACTUAL=marked:init NEGATED=marked:init "
            "CONDITIONAL=marked:init\n",
            result.stdout,
        )

    def test_topology_generation_is_shared_with_a_fresh_shell(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            parent = root / "work"
            child = parent / "child"
            child.mkdir(parents=True)
            cache_home = root / "cache"
            first = run_zsh(
                r"""
source "$1"
_ai_candy_cache_persist_write git_root "0:$CHILD" NOT_GIT "$EPOCHSECONDS" || return 70
cd "$PARENT"
_ai_candy_prompt_mark_git_cache_invalidation "git init -q" "git init -q" "git init -q"
git init -q
_LAST_EXIT_STATUS=$?
_ai_candy_prompt_apply_git_cache_invalidation
print -r -- "GENERATION=${_GIT_TOPOLOGY_GENERATION}"
""",
                cache_home=cache_home,
                cwd=parent,
                env={"PARENT": str(parent), "CHILD": str(child)},
            )
            second = run_zsh(
                r"""
source "$1"
cd "$CHILD"
_ai_candy_get_cached_git_root
print -r -- "GENERATION=${_GIT_TOPOLOGY_GENERATION} ROOT=${REPLY}"
""",
                cache_home=cache_home,
                cwd=child,
                env={"CHILD": str(child)},
            )

        self.assertEqual(0, first.returncode, first.stderr)
        self.assertRegex(first.stdout, r"^GENERATION=v1:")
        self.assertEqual(0, second.returncode, second.stderr)
        self.assertRegex(
            second.stdout,
            rf"^GENERATION=v1:[^ ]+ ROOT={parent}\n$",
        )

    def test_failed_generation_write_does_not_restore_an_older_generation(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            parent = root / "work"
            child = parent / "child"
            child.mkdir(parents=True)
            result = run_zsh(
                r"""
source "$1"
_HAS_SQLITE3=0
_ai_candy_cache_persist_write git_root "0:$CHILD" NOT_GIT "$EPOCHSECONDS" || return 70
git -C "$PARENT" init -q || return 71
functions[_atomic_without_failure]="${functions[_ai_candy_cache_atomic_write_unlocked]}"
integer fail_generation_write=1
function _ai_candy_cache_atomic_write_unlocked() {
  if (( fail_generation_write )) && \
     [[ "$1" == "$_GIT_TOPOLOGY_GENERATION_FILE" ]]; then
    fail_generation_write=0
    return 1
  fi
  _atomic_without_failure "$@"
}
_ai_candy_record_git_topology_invalidation "$PARENT" || return 72
generation_after_failure="$_GIT_TOPOLOGY_GENERATION"
valid_after_failure="$_GIT_TOPOLOGY_GENERATION_VALID"
functions[_ai_candy_cache_atomic_write_unlocked]="${functions[_atomic_without_failure]}"
cd "$CHILD"
_ai_candy_get_cached_git_root
print -r -- "FAILED_GENERATION=${generation_after_failure} VALID=${valid_after_failure}"
print -r -- "GENERATION=${_GIT_TOPOLOGY_GENERATION} ROOT=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=parent,
                env={
                    "PARENT": str(parent),
                    "CHILD": str(child),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertRegex(
            result.stdout,
            rf"^FAILED_GENERATION=v1:[^ ]+ VALID=0\n"
            rf"GENERATION=v1:[^ ]+ ROOT={parent}\n$",
        )

    def test_unpublished_generation_keeps_the_session_git_cache_hot(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "work"
            probe_log = root / "git-root-probes"
            work.mkdir()
            subprocess.run(["git", "-C", str(work), "init", "-q"], check=True)
            result = run_zsh(
                r"""
source "$1"
functions[_ai_candy_probe_without_count]="${functions[_ai_candy_run_local_probe]}"
function _ai_candy_run_local_probe() {
  builtin print -r -- probe >> "$PROBE_LOG"
  _ai_candy_probe_without_count "$@"
}
_CACHE_READY=0
_ai_candy_record_git_topology_invalidation "$PWD"
generation="$_GIT_TOPOLOGY_GENERATION"
same=yes
for attempt in 1 2 3; do
  _ai_candy_get_cached_git_root
  [[ "$_GIT_TOPOLOGY_GENERATION" == "$generation" ]] || same=no
done
print -r -- "SAME=${same} ROOT=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=work,
                env={"PROBE_LOG": str(probe_log)},
            )
            probe_lines = probe_log.read_text(encoding="ascii").splitlines()

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(f"SAME=yes ROOT={work}\n", result.stdout)
        self.assertEqual(["probe"], probe_lines)

    def test_topology_invalidation_does_not_wait_for_a_contended_commit_lock(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            parent = root / "work"
            child = parent / "child"
            child.mkdir(parents=True)
            cache_home = root / "cache"
            result = run_zsh(
                r"""
source "$1"
_HAS_SQLITE3=0
_ai_candy_cache_persist_write git_root "0:$CHILD" NOT_GIT "$EPOCHSECONDS" || return 70
git -C "$PARENT" init -q || return 71
_HAS_ZSH_SYSTEM=0
command mkdir -p "$_CACHE_COMMIT_LOCK"
print -r -- holder >| "${_CACHE_COMMIT_LOCK}/owner.test"
start="$EPOCHREALTIME"
_ai_candy_record_git_topology_invalidation "$PARENT"
elapsed=$(( EPOCHREALTIME - start ))
print -r -- "ELAPSED=${elapsed} VALID=${_GIT_TOPOLOGY_GENERATION_VALID}"
""",
                cache_home=cache_home,
                env={"PARENT": str(parent), "CHILD": str(child)},
            )
            reader = run_zsh(
                r"""
source "$1"
cd "$CHILD"
_ai_candy_get_cached_git_root
print -r -- "GENERATION=${_GIT_TOPOLOGY_GENERATION} ROOT=${REPLY}"
""",
                cache_home=cache_home,
                cwd=child,
                env={"CHILD": str(child)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(
            field.split("=", maxsplit=1) for field in result.stdout.strip().split()
        )
        self.assertLess(float(fields["ELAPSED"]), 0.15)
        self.assertEqual("1", fields["VALID"])
        self.assertEqual(0, reader.returncode, reader.stderr)
        self.assertRegex(
            reader.stdout,
            rf"^GENERATION=v1:[^ ]+ ROOT={parent}\n$",
        )

    def test_failed_topology_publication_cannot_restore_a_stale_local_root(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            outer = root / "outer"
            child = outer / "child"
            child.mkdir(parents=True)
            subprocess.run(["git", "-C", str(outer), "init", "-q"], check=True)
            cache_home = root / "cache"
            ready_file = root / "ready"
            release_file = root / "release"
            environment = {
                "XDG_CACHE_HOME": str(cache_home),
                "CHILD": str(child),
                "READY_FILE": str(ready_file),
                "RELEASE_FILE": str(release_file),
            }
            stale_shell = subprocess.Popen(
                [
                    "zsh",
                    "-fc",
                    r"""
source "$1"
cd "$CHILD"
functions[_atomic_before_failure]="${functions[_ai_candy_cache_atomic_write_unlocked]}"
function _ai_candy_cache_atomic_write_unlocked() {
  if [[ "$1" == "$_GIT_TOPOLOGY_GENERATION_FILE" && \
        ! -f "$RELEASE_FILE" ]]; then
    return 1
  fi
  _atomic_before_failure "$@"
}
_ai_candy_record_git_topology_invalidation "$CHILD"
_ai_candy_get_cached_git_root
before="$REPLY"
print -r -- ready >| "$READY_FILE"
for attempt in {1..500}; do
  [[ -f "$RELEASE_FILE" ]] && break
  zselect -t 1
done
[[ -f "$RELEASE_FILE" ]] || return 70
_ai_candy_get_cached_git_root
print -r -- "BEFORE=${before} AFTER=${REPLY}"
""",
                    "zsh",
                    str(THEME),
                ],
                cwd=child,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, **environment},
            )
            try:
                deadline = time.monotonic() + 5
                while not ready_file.exists() and time.monotonic() < deadline:
                    if stale_shell.poll() is not None:
                        break
                    time.sleep(0.01)
                self.assertTrue(
                    ready_file.exists(), "stale shell did not fill its cache"
                )
                subprocess.run(["git", "-C", str(child), "init", "-q"], check=True)
                publisher = run_zsh(
                    r"""
source "$1"
_ai_candy_record_git_topology_invalidation "$CHILD"
""",
                    cache_home=cache_home,
                    cwd=child,
                    env={"CHILD": str(child)},
                )
                self.assertEqual(0, publisher.returncode, publisher.stderr)
                release_file.write_text("release\n", encoding="ascii")
                stale_stdout, stale_stderr = stale_shell.communicate(timeout=8)
            finally:
                if stale_shell.poll() is None:
                    stale_shell.kill()
                    stale_shell.communicate()

        self.assertEqual(0, stale_shell.returncode, stale_stderr)
        self.assertEqual(f"BEFORE={outer} AFTER={child}\n", stale_stdout)

    def test_git_init_invalidates_cached_non_repository_descendants(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "work"
            child = work / "child"
            child.mkdir(parents=True)
            result = run_zsh(
                r"""
source "$1"
cd child
_ai_candy_get_cached_git_root
before="$REPLY"
cd ..
_ai_candy_prompt_mark_git_cache_invalidation "git init -q" "git init -q" "git init -q"
git init -q
_LAST_EXIT_STATUS=$?
_ai_candy_prompt_apply_git_cache_invalidation
cd child
_ai_candy_get_cached_git_root
builtin print -r -- "BEFORE=${before} AFTER=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=work,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(f"BEFORE=NOT_GIT AFTER={work}\n", result.stdout)

    def test_non_repository_path_remains_absolute_without_home(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work = root / "work"
            work.mkdir()
            result = run_zsh(
                r"""
source "$1"
unset HOME
_PP_CACHED_GIT_ROOT=NOT_GIT
_SMART_PATH_CONTEXT_KEY=""
_ai_candy_prepare_smart_path_context
builtin print -r -- "PATH=${_SMART_PATH_FALLBACK}"
""",
                cache_home=root / "cache",
                cwd=work,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(f"PATH={work}\n", result.stdout)

    def test_non_repository_path_inside_home_is_abbreviated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / "home"
            work = home / "projects" / "plain" / "subdir"
            work.mkdir(parents=True)
            result = run_zsh(
                r"""
source "$1"
_PP_CACHED_GIT_ROOT=NOT_GIT
_SMART_PATH_CONTEXT_KEY=""
_ai_candy_prepare_smart_path_context
builtin print -r -- "PATH=${_SMART_PATH_FALLBACK}"
""",
                cache_home=root / "cache",
                cwd=work,
                env={"HOME": str(home)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("PATH=~/projects/plain/subdir\n", result.stdout)

    def test_repository_path_does_not_abbreviate_a_home_prefix_collision(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / "user"
            repo = root / "user2" / "repo"
            home.mkdir()
            repo.mkdir(parents=True)
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)
            result = run_zsh(
                r"""
source "$1"
_ai_candy_get_cached_git_root
_PP_CACHED_GIT_ROOT="$REPLY"
_SMART_PATH_CONTEXT_KEY=""
_ai_candy_prepare_smart_path_context
builtin print -r -- "PATH=${_SMART_PATH_SEGMENTS[1]}"
""",
                cache_home=root / "cache",
                cwd=repo,
                env={"HOME": str(home)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(f"PATH={repo}\n", result.stdout)

    def test_git_config_remote_url_immediately_invalidates_pr_cache_key(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            repo.mkdir()
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "remote",
                    "add",
                    "origin",
                    "https://example.invalid/one.git",
                ],
                check=True,
            )
            result = run_zsh(
                r"""
source "$1"
_PROMPT_RENDER_ID=1
_PP_CACHED_GIT_ROOT="$PWD"
_ai_candy_get_cached_git_remote_branch
before="$REPLY"
_ai_candy_prompt_mark_git_cache_invalidation \
  "git config remote.origin.url https://example.invalid/two.git" \
  "git config remote.origin.url https://example.invalid/two.git" \
  "git config remote.origin.url https://example.invalid/two.git"
git config remote.origin.url https://example.invalid/two.git
_LAST_EXIT_STATUS=$?
_ai_candy_prompt_apply_git_cache_invalidation
_ai_candy_get_cached_git_remote_branch
after="$REPLY"
print -r -- "SAME=$([[ $before == $after ]] && print yes || print no)"
""",
                cache_home=root / "cache",
                cwd=repo,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("SAME=no\n", result.stdout)

    def test_git_dash_c_remote_change_invalidates_the_target_cache(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            control = root / "control"
            target = root / "target"
            control.mkdir()
            target.mkdir()
            subprocess.run(["git", "-C", str(target), "init", "-q"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(target),
                    "remote",
                    "add",
                    "origin",
                    "https://example.invalid/one.git",
                ],
                check=True,
            )
            result = run_zsh(
                r"""
source "$1"
cd "$TARGET"
_PP_CACHED_GIT_ROOT="$TARGET"
_PROMPT_RENDER_ID=1
_ai_candy_get_cached_git_remote_branch
before="$REPLY"
cd "$CONTROL"
_PP_CACHED_GIT_ROOT=NOT_GIT
_ai_candy_prompt_mark_git_cache_invalidation \
  "git -C $TARGET remote set-url origin https://example.invalid/two.git" \
  "git -C $TARGET remote set-url origin https://example.invalid/two.git" \
  "git -C $TARGET remote set-url origin https://example.invalid/two.git"
git -C "$TARGET" remote set-url origin https://example.invalid/two.git
_LAST_EXIT_STATUS=$?
_ai_candy_prompt_apply_git_cache_invalidation
cd "$TARGET"
_PP_CACHED_GIT_ROOT="$TARGET"
(( ++_PROMPT_RENDER_ID ))
_ai_candy_get_cached_git_remote_branch
after="$REPLY"
print -r -- "SAME=$([[ $before == $after ]] && print yes || print no)"
""",
                cache_home=root / "cache",
                cwd=control,
                env={"CONTROL": str(control), "TARGET": str(target)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("SAME=no\n", result.stdout)


if __name__ == "__main__":
    unittest.main()
