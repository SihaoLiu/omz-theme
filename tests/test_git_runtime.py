#!/usr/bin/env python3
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from tests.theme_test_support import THEME, run_zsh


def configure_bare_git_dir(
    git_dir: Path,
    branch: str,
    remote: str,
    hide_info: str,
    work_tree=None,
) -> None:
    subprocess.run(["git", "init", "--bare", "-q", str(git_dir)], check=True)
    config = [
        ("remote.origin.url", f"https://example.invalid/{remote}"),
        ("oh-my-zsh.hide-info", hide_info),
    ]
    if work_tree is not None:
        config[:0] = [("core.bare", "false"), ("core.worktree", str(work_tree))]
    for key, value in config:
        subprocess.run(
            ["git", f"--git-dir={git_dir}", "config", key, value], check=True
        )
    subprocess.run(
        [
            "git",
            f"--git-dir={git_dir}",
            "symbolic-ref",
            "HEAD",
            f"refs/heads/{branch}",
        ],
        check=True,
    )


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
_AI_CANDY_PP_CACHED_GIT_ROOT="$before_root"
_ai_candy_get_git_hierarchy
before_hierarchy="$REPLY"
cd "$OUTER"
_ai_candy_prompt_mark_git_cache_invalidation \
  "git init -q child" "git init -q child" "git init -q child"
git init -q child
_AI_CANDY_LAST_EXIT_STATUS=$?
_ai_candy_prompt_apply_git_cache_invalidation
cd "$CHILD"
_ai_candy_get_cached_git_root
after_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$after_root"
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

    def test_external_nested_repository_invalidates_a_positive_root_cache(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            outer = root / "outer"
            inner = outer / "inner"
            inner.mkdir(parents=True)
            subprocess.run(["git", "-C", str(outer), "init", "-q"], check=True)

            result = run_zsh(
                r"""
source "$1"
_ai_candy_get_cached_git_root
before="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$before"
_ai_candy_get_git_hierarchy
before_hierarchy="$REPLY"
command git -C "$INNER" init -q || return 70
_ai_candy_get_cached_git_root
after="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$after"
_ai_candy_get_git_hierarchy
after_hierarchy="$REPLY"
builtin print -r -- "BEFORE=${before} AFTER=${after}"
builtin print -r -- "BEFORE_HIERARCHY=${before_hierarchy}"
builtin print -r -- "AFTER_HIERARCHY=${after_hierarchy}"
""",
                cache_home=root / "cache",
                cwd=inner,
                env={"INNER": str(inner)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"BEFORE={outer} AFTER={inner}\n"
            f"BEFORE_HIERARCHY={outer}\x1finner\n"
            f"AFTER_HIERARCHY={inner}\x1f\n",
            result.stdout,
        )

    def test_explicit_git_directory_partitions_the_root_cache(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            original = root / "original"
            child = original / "child"
            alternate = root / "alternate"
            child.mkdir(parents=True)
            alternate.mkdir()
            subprocess.run(["git", "-C", str(original), "init", "-q"], check=True)
            subprocess.run(["git", "-C", str(alternate), "init", "-q"], check=True)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_ai_candy_get_cached_git_root
before="$REPLY"
export GIT_DIR="$ALTERNATE/.git"
export GIT_WORK_TREE="$ALTERNATE"
direct=$(command git rev-parse --show-toplevel 2>/dev/null) || return 70
_ai_candy_get_cached_git_root
after="$REPLY"
_ai_candy_get_cached_git_root
builtin print -r -- \
  "BEFORE=${before} DIRECT=${direct} AFTER=${after} WARM=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=child,
                env={"ALTERNATE": str(alternate)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"BEFORE={original} DIRECT={alternate} "
            f"AFTER={alternate} WARM={alternate}\n",
            result.stdout,
        )

    def test_git_ceiling_partitions_the_root_cache(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            child = repo / "child"
            child.mkdir(parents=True)
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_ai_candy_get_cached_git_root
before="$REPLY"
export GIT_CEILING_DIRECTORIES="$REPO"
if command git rev-parse --show-toplevel >/dev/null 2>&1; then
  direct=GIT
else
  direct=NOT_GIT
fi
_ai_candy_get_cached_git_root
after="$REPLY"
_ai_candy_get_cached_git_root
builtin print -r -- \
  "BEFORE=${before} DIRECT=${direct} AFTER=${after} WARM=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=child,
                env={"REPO": str(repo)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"BEFORE={repo} DIRECT=NOT_GIT AFTER=NOT_GIT WARM=NOT_GIT\n",
            result.stdout,
        )

    def test_git_ceiling_context_detects_an_external_nested_repository(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            outer = root / "outer"
            inner = outer / "inner"
            inner.mkdir(parents=True)
            subprocess.run(["git", "-C", str(outer), "init", "-q"], check=True)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
export GIT_CEILING_DIRECTORIES="$CEILING"
_ai_candy_get_cached_git_root
before="$REPLY"
command git -C "$INNER" init -q || return 70
direct=$(command git rev-parse --show-toplevel 2>/dev/null) || return 71
_ai_candy_get_cached_git_root
builtin print -r -- \
  "BEFORE=${before} DIRECT=${direct} AFTER=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=inner,
                env={"CEILING": str(root), "INNER": str(inner)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"BEFORE={outer} DIRECT={inner} AFTER={inner}\n",
            result.stdout,
        )

    def test_git_discovery_context_owns_all_derived_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work_tree = root / "work"
            alternate_git_dir = root / "alternate.git"
            work_tree.mkdir()
            subprocess.run(
                ["git", "-C", str(work_tree), "init", "-q"], check=True
            )
            subprocess.run(
                [
                    "git",
                    f"--git-dir={work_tree / '.git'}",
                    "symbolic-ref",
                    "HEAD",
                    "refs/heads/alpha",
                ],
                check=True,
            )
            subprocess.run(
                [
                    "git",
                    f"--git-dir={work_tree / '.git'}",
                    "config",
                    "remote.origin.url",
                    "https://example.invalid/alpha.git",
                ],
                check=True,
            )
            subprocess.run(
                [
                    "git",
                    f"--git-dir={work_tree / '.git'}",
                    "config",
                    "oh-my-zsh.hide-info",
                    "1",
                ],
                check=True,
            )
            subprocess.run(
                ["git", "init", "--bare", "-q", str(alternate_git_dir)],
                check=True,
            )
            subprocess.run(
                [
                    "git",
                    f"--git-dir={alternate_git_dir}",
                    "symbolic-ref",
                    "HEAD",
                    "refs/heads/beta",
                ],
                check=True,
            )
            subprocess.run(
                [
                    "git",
                    f"--git-dir={alternate_git_dir}",
                    "config",
                    "remote.origin.url",
                    "https://example.invalid/beta.git",
                ],
                check=True,
            )
            (alternate_git_dir / "MERGE_HEAD").write_text(
                "0" * 40 + "\n", encoding="ascii"
            )

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
export GIT_WORK_TREE="$WORK_TREE"
export GIT_DIR=.git
_ai_candy_get_cached_git_root
first_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$first_root"
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_get_cached_git_remote_branch
first_remote_branch="$REPLY"
_ai_candy_load_git_display_options "$first_root"
first_hide_info="$_AI_CANDY_GIT_HIDE_INFO"
_ai_candy_collect_git_snapshot
first_snapshot_branch="$_AI_CANDY_GIT_SNAPSHOT_BRANCH"
_ai_candy_compute_git_special_direct
first_special="$_AI_CANDY_PP_GIT_SPECIAL"

export GIT_DIR=../alternate.git
_ai_candy_get_cached_git_root
second_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$second_root"
_ai_candy_get_cached_git_remote_branch
second_remote_branch="$REPLY"
_ai_candy_load_git_display_options "$second_root"
second_hide_info="$_AI_CANDY_GIT_HIDE_INFO"
_ai_candy_collect_git_snapshot
second_snapshot_branch="$_AI_CANDY_GIT_SNAPSHOT_BRANCH"
_ai_candy_compute_git_special_direct
second_special="$_AI_CANDY_PP_GIT_SPECIAL"

direct_branch=$(command git symbolic-ref --short HEAD 2>/dev/null) || return 70
direct_remote=$(command git config --get remote.origin.url 2>/dev/null) || return 71
builtin print -r -- "ROOTS_EQUAL=$([[ $first_root == $second_root ]] && print yes || print no)"
builtin print -r -- "FIRST_BRANCH=${first_remote_branch#*|}"
builtin print -r -- "SECOND_BRANCH=${second_remote_branch#*|}"
builtin print -r -- "REMOTE_KEYS_EQUAL=$([[ ${first_remote_branch%%|*} == ${second_remote_branch%%|*} ]] && print yes || print no)"
builtin print -r -- "HIDE_INFO=${first_hide_info}->${second_hide_info}"
builtin print -r -- "SNAPSHOT=${first_snapshot_branch}->${second_snapshot_branch}"
builtin print -r -- "SPECIAL=${first_special:+set}->${second_special:+set}"
builtin print -r -- "DIRECT=${direct_branch}|${direct_remote}"
""",
                cache_home=root / "cache",
                cwd=work_tree,
                env={"WORK_TREE": str(work_tree)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "ROOTS_EQUAL=yes\n"
            "FIRST_BRANCH=alpha\n"
            "SECOND_BRANCH=beta\n"
            "REMOTE_KEYS_EQUAL=no\n"
            "HIDE_INFO=1->0\n"
            "SNAPSHOT=alpha->beta\n"
            "SPECIAL=->set\n"
            "DIRECT=beta|https://example.invalid/beta.git\n",
            result.stdout,
        )

    def test_relative_git_context_uses_its_physical_working_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work_tree = root / "work"
            first_control = root / "first"
            second_control = root / "second"
            work_tree.mkdir()
            first_control.mkdir()
            second_control.mkdir()

            first_git_dir = first_control / "repo.git"
            second_git_dir = second_control / "repo.git"
            for git_dir, branch, remote, hide_info in (
                (first_git_dir, "alpha", "alpha.git", "1"),
                (second_git_dir, "beta", "beta.git", "0"),
            ):
                configure_bare_git_dir(
                    git_dir, branch, remote, hide_info
                )
            (second_git_dir / "MERGE_HEAD").write_text(
                "0" * 40 + "\n", encoding="ascii"
            )

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
export GIT_DIR=repo.git
export GIT_WORK_TREE="$WORK_TREE"
_AI_CANDY_PROMPT_RENDER_ID=1

builtin cd "$FIRST_CONTROL" || return 70
_ai_candy_get_cached_git_root
first_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$first_root"
_ai_candy_get_cached_git_remote_branch
first_remote_branch="$REPLY"
_ai_candy_load_git_display_options "$first_root"
first_hide_info="$_AI_CANDY_GIT_HIDE_INFO"
_ai_candy_collect_git_snapshot
first_snapshot_branch="$_AI_CANDY_GIT_SNAPSHOT_BRANCH"
_ai_candy_compute_git_special_direct
first_special="$_AI_CANDY_PP_GIT_SPECIAL"

builtin cd "$SECOND_CONTROL" || return 71
_ai_candy_get_cached_git_root
second_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$second_root"
_ai_candy_get_cached_git_remote_branch
second_remote_branch="$REPLY"
_ai_candy_load_git_display_options "$second_root"
second_hide_info="$_AI_CANDY_GIT_HIDE_INFO"
_ai_candy_collect_git_snapshot
second_snapshot_branch="$_AI_CANDY_GIT_SNAPSHOT_BRANCH"
_ai_candy_compute_git_special_direct
second_special="$_AI_CANDY_PP_GIT_SPECIAL"

builtin print -r -- \
  "ROOTS_EQUAL=$([[ $first_root == $second_root ]] && print yes || print no)"
builtin print -r -- "BRANCHES=${first_remote_branch#*|}->${second_remote_branch#*|}"
builtin print -r -- "HIDE_INFO=${first_hide_info}->${second_hide_info}"
builtin print -r -- \
  "SNAPSHOT=${first_snapshot_branch}->${second_snapshot_branch}"
builtin print -r -- "SPECIAL=${first_special:+set}->${second_special:+set}"
""",
                cache_home=root / "cache",
                cwd=first_control,
                env={
                    "FIRST_CONTROL": str(first_control),
                    "SECOND_CONTROL": str(second_control),
                    "WORK_TREE": str(work_tree),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "ROOTS_EQUAL=yes\n"
            "BRANCHES=alpha->beta\n"
            "HIDE_INFO=1->0\n"
            "SNAPSHOT=alpha->beta\n"
            "SPECIAL=->set\n",
            result.stdout,
        )

    def test_explicit_git_symlink_retarget_partitions_derived_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            work_tree = root / "work"
            first_git_dir = root / "alpha.git"
            second_git_dir = root / "beta.git"
            git_link = root / "git-link"
            work_tree.mkdir()

            for git_dir, branch, remote, hide_info in (
                (first_git_dir, "alpha", "alpha.git", "1"),
                (second_git_dir, "beta", "beta.git", "0"),
            ):
                configure_bare_git_dir(git_dir, branch, remote, hide_info)
            (second_git_dir / "MERGE_HEAD").write_text(
                "0" * 40 + "\n", encoding="ascii"
            )
            git_link.symlink_to(first_git_dir, target_is_directory=True)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
export GIT_DIR="$GIT_LINK"
export GIT_WORK_TREE="$WORK_TREE"
_AI_CANDY_PROMPT_RENDER_ID=1

_ai_candy_git_discovery_context_key
first_context="$REPLY"
_ai_candy_get_cached_git_root
first_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$first_root"
_ai_candy_get_cached_git_remote_branch
first_remote_branch="$REPLY"
_ai_candy_load_git_display_options "$first_root"
first_hide_info="$_AI_CANDY_GIT_HIDE_INFO"
_ai_candy_collect_git_snapshot
first_snapshot_branch="$_AI_CANDY_GIT_SNAPSHOT_BRANCH"
_ai_candy_compute_git_special_direct
first_special="$_AI_CANDY_PP_GIT_SPECIAL"

command rm "$GIT_LINK" || return 70
command ln -s "$SECOND_GIT_DIR" "$GIT_LINK" || return 71
(( ++_AI_CANDY_PROMPT_RENDER_ID ))
_ai_candy_git_discovery_context_key
second_context="$REPLY"
_ai_candy_get_cached_git_root
second_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$second_root"
_ai_candy_get_cached_git_remote_branch
second_remote_branch="$REPLY"
_ai_candy_load_git_display_options "$second_root"
second_hide_info="$_AI_CANDY_GIT_HIDE_INFO"
_ai_candy_collect_git_snapshot
second_snapshot_branch="$_AI_CANDY_GIT_SNAPSHOT_BRANCH"
_ai_candy_compute_git_special_direct
second_special="$_AI_CANDY_PP_GIT_SPECIAL"

direct_branch=$(command git symbolic-ref --short HEAD 2>/dev/null) || return 72
direct_remote=$(command git config --get remote.origin.url 2>/dev/null) || return 73
builtin print -r -- \
  "ROOTS_EQUAL=$([[ $first_root == $second_root ]] && print yes || print no)"
builtin print -r -- \
  "CONTEXTS_EQUAL=$([[ $first_context == $second_context ]] && print yes || print no)"
builtin print -r -- "BRANCHES=${first_remote_branch#*|}->${second_remote_branch#*|}"
builtin print -r -- \
  "REMOTE_KEYS_EQUAL=$([[ ${first_remote_branch%%|*} == ${second_remote_branch%%|*} ]] && print yes || print no)"
builtin print -r -- "HIDE_INFO=${first_hide_info}->${second_hide_info}"
builtin print -r -- \
  "SNAPSHOT=${first_snapshot_branch}->${second_snapshot_branch}"
builtin print -r -- "SPECIAL=${first_special:+set}->${second_special:+set}"
builtin print -r -- "DIRECT=${direct_branch}|${direct_remote}"
""",
                cache_home=root / "cache",
                cwd=work_tree,
                env={
                    "SECOND_GIT_DIR": str(second_git_dir),
                    "GIT_LINK": str(git_link),
                    "WORK_TREE": str(work_tree),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "ROOTS_EQUAL=yes\n"
            "CONTEXTS_EQUAL=no\n"
            "BRANCHES=alpha->beta\n"
            "REMOTE_KEYS_EQUAL=no\n"
            "HIDE_INFO=1->0\n"
            "SNAPSHOT=alpha->beta\n"
            "SPECIAL=->set\n"
            "DIRECT=beta|https://example.invalid/beta.git\n",
            result.stdout,
        )

    def test_implicit_git_dir_retarget_partitions_all_derived_state(self) -> None:
        for marker_kind in ("symlink", "gitfile"):
            with self.subTest(marker_kind=marker_kind), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                work_tree = root / "work"
                first_git_dir = root / "alpha.git"
                second_git_dir = root / "beta.git"
                git_marker = work_tree / ".git"
                work_tree.mkdir()

                for git_dir, branch, remote, hide_info in (
                    (first_git_dir, "alpha", "alpha.git", "1"),
                    (second_git_dir, "beta", "beta.git", "0"),
                ):
                    configure_bare_git_dir(
                        git_dir,
                        branch,
                        remote,
                        hide_info,
                        work_tree,
                    )
                (second_git_dir / "MERGE_HEAD").write_text(
                    "0" * 40 + "\n", encoding="ascii"
                )
                if marker_kind == "symlink":
                    git_marker.symlink_to(first_git_dir, target_is_directory=True)
                else:
                    git_marker.write_text(
                        f"gitdir: {first_git_dir}\n", encoding="ascii"
                    )

                result = run_zsh(
                    r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_AI_CANDY_PROMPT_RENDER_ID=1
functions[_hierarchy_probe_without_count]="${functions[_ai_candy_run_git_probe_at_root]}"
function _ai_candy_run_git_probe_at_root() {
  if [[ "$2" == rev-parse && \
        "$3" == --show-superproject-working-tree ]]; then
    builtin print -r -- call >>! "$PROBE_MARKER"
  fi
  _hierarchy_probe_without_count "$@"
}

_ai_candy_get_cached_git_root
first_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$first_root"
_ai_candy_git_context_cache_key "$first_root"
first_context="$REPLY"
_ai_candy_get_cached_git_remote_branch
first_remote_branch="$REPLY"
_ai_candy_load_git_display_options "$first_root"
first_hide_info="$_AI_CANDY_GIT_HIDE_INFO"
_ai_candy_collect_git_snapshot
first_snapshot_branch="$_AI_CANDY_GIT_SNAPSHOT_BRANCH"
_ai_candy_compute_git_special_direct
first_special="$_AI_CANDY_PP_GIT_SPECIAL"
_ai_candy_get_git_hierarchy
first_hierarchy="$REPLY"
_ai_candy_prepare_smart_path_context
first_smart_context="$_AI_CANDY_SMART_PATH_CONTEXT_KEY"

if [[ "$MARKER_KIND" == symlink ]]; then
  command rm "$WORK_TREE/.git" || return 70
  command ln -s "$SECOND_GIT_DIR" "$WORK_TREE/.git" || return 71
else
  builtin print -r -- "gitdir: $SECOND_GIT_DIR" >| "$WORK_TREE/.git" || \
    return 72
fi
(( ++_AI_CANDY_PROMPT_RENDER_ID ))

_ai_candy_get_cached_git_root
second_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$second_root"
_ai_candy_git_context_cache_key "$second_root"
second_context="$REPLY"
_ai_candy_get_cached_git_remote_branch
second_remote_branch="$REPLY"
_ai_candy_load_git_display_options "$second_root"
second_hide_info="$_AI_CANDY_GIT_HIDE_INFO"
_ai_candy_collect_git_snapshot
second_snapshot_branch="$_AI_CANDY_GIT_SNAPSHOT_BRANCH"
_ai_candy_compute_git_special_direct
second_special="$_AI_CANDY_PP_GIT_SPECIAL"
_ai_candy_get_git_hierarchy
second_hierarchy="$REPLY"
_ai_candy_prepare_smart_path_context
second_smart_context="$_AI_CANDY_SMART_PATH_CONTEXT_KEY"

direct_branch=$(command git symbolic-ref --short HEAD 2>/dev/null) || return 73
direct_remote=$(command git config --get remote.origin.url 2>/dev/null) || \
  return 74
typeset -a hierarchy_probe_lines
hierarchy_probe_lines=("${(@f)$(<"$PROBE_MARKER")}")
builtin print -r -- \
  "ROOTS_EQUAL=$([[ $first_root == $second_root ]] && print yes || print no)"
builtin print -r -- \
  "CONTEXTS_EQUAL=$([[ $first_context == $second_context ]] && print yes || print no)"
builtin print -r -- \
  "SMART_CONTEXTS_EQUAL=$([[ $first_smart_context == $second_smart_context ]] && print yes || print no)"
builtin print -r -- \
  "HIERARCHIES_EQUAL=$([[ $first_hierarchy == $second_hierarchy ]] && print yes || print no)"
builtin print -r -- "HIERARCHY_PROBES=${#hierarchy_probe_lines}"
builtin print -r -- \
  "BRANCHES=${first_remote_branch#*|}->${second_remote_branch#*|}"
builtin print -r -- \
  "REMOTE_KEYS_EQUAL=$([[ ${first_remote_branch%%|*} == ${second_remote_branch%%|*} ]] && print yes || print no)"
builtin print -r -- "HIDE_INFO=${first_hide_info}->${second_hide_info}"
builtin print -r -- \
  "SNAPSHOT=${first_snapshot_branch}->${second_snapshot_branch}"
builtin print -r -- "SPECIAL=${first_special:+set}->${second_special:+set}"
builtin print -r -- "DIRECT=${direct_branch}|${direct_remote}"
""",
                    cache_home=root / "cache",
                    cwd=work_tree,
                    env={
                        "MARKER_KIND": marker_kind,
                        "PROBE_MARKER": str(root / "hierarchy-probes"),
                        "SECOND_GIT_DIR": str(second_git_dir),
                        "WORK_TREE": str(work_tree),
                    },
                )

                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual(
                    "ROOTS_EQUAL=yes\n"
                    "CONTEXTS_EQUAL=no\n"
                    "SMART_CONTEXTS_EQUAL=no\n"
                    "HIERARCHIES_EQUAL=yes\n"
                    "HIERARCHY_PROBES=2\n"
                    "BRANCHES=alpha->beta\n"
                    "REMOTE_KEYS_EQUAL=no\n"
                    "HIDE_INFO=1->0\n"
                    "SNAPSHOT=alpha->beta\n"
                    "SPECIAL=->set\n"
                    "DIRECT=beta|https://example.invalid/beta.git\n",
                    result.stdout,
                )

    def test_implicit_common_dir_retarget_partitions_derived_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            first_common_dir = root / "alpha.git"
            second_common_dir = root / "beta.git"
            work_tree = root / "work"
            source.mkdir()
            subprocess.run(["git", "-C", str(source), "init", "-q"], check=True)
            (source / "README").write_text("fixture\n", encoding="ascii")
            subprocess.run(["git", "-C", str(source), "add", "README"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(source),
                    "-c",
                    "user.name=Fixture User",
                    "-c",
                    "user.email=fixture@example.invalid",
                    "commit",
                    "-q",
                    "-m",
                    "fixture",
                ],
                check=True,
            )
            for common_dir, remote, hide_info in (
                (first_common_dir, "alpha.git", "1"),
                (second_common_dir, "beta.git", "0"),
            ):
                subprocess.run(
                    ["git", "clone", "--bare", "-q", str(source), str(common_dir)],
                    check=True,
                )
                subprocess.run(
                    [
                        "git",
                        f"--git-dir={common_dir}",
                        "config",
                        "remote.origin.url",
                        f"https://example.invalid/{remote}",
                    ],
                    check=True,
                )
                subprocess.run(
                    [
                        "git",
                        f"--git-dir={common_dir}",
                        "config",
                        "oh-my-zsh.hide-info",
                        hide_info,
                    ],
                    check=True,
                )
            subprocess.run(
                [
                    "git",
                    f"--git-dir={first_common_dir}",
                    "worktree",
                    "add",
                    "-q",
                    "-b",
                    "shared",
                    str(work_tree),
                    "HEAD",
                ],
                check=True,
            )
            commit = subprocess.run(
                ["git", "-C", str(work_tree), "rev-parse", "HEAD"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            subprocess.run(
                [
                    "git",
                    f"--git-dir={second_common_dir}",
                    "update-ref",
                    "refs/heads/shared",
                    commit,
                ],
                check=True,
            )
            work_git_dir = first_common_dir / "worktrees" / work_tree.name

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_get_cached_git_root
first_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$first_root"
_ai_candy_git_context_cache_key "$first_root"
first_context="$REPLY"
_ai_candy_get_cached_git_remote_branch
first_remote_branch="$REPLY"
_ai_candy_load_git_display_options "$first_root"
first_hide_info="$_AI_CANDY_GIT_HIDE_INFO"
_ai_candy_prepare_smart_path_context
first_smart_context="$_AI_CANDY_SMART_PATH_CONTEXT_KEY"

builtin print -r -- "$SECOND_COMMON_DIR" >| "$WORK_GIT_DIR/commondir" || \
  return 70
(( ++_AI_CANDY_PROMPT_RENDER_ID ))
_ai_candy_get_cached_git_root
second_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$second_root"
_ai_candy_git_context_cache_key "$second_root"
second_context="$REPLY"
_ai_candy_get_cached_git_remote_branch
second_remote_branch="$REPLY"
_ai_candy_load_git_display_options "$second_root"
second_hide_info="$_AI_CANDY_GIT_HIDE_INFO"
_ai_candy_prepare_smart_path_context
second_smart_context="$_AI_CANDY_SMART_PATH_CONTEXT_KEY"

direct_remote=$(command git config --get remote.origin.url 2>/dev/null) || \
  return 71
direct_common=$(command git rev-parse --git-common-dir 2>/dev/null) || return 72
builtin print -r -- \
  "ROOTS_EQUAL=$([[ $first_root == $second_root ]] && print yes || print no)"
builtin print -r -- \
  "CONTEXTS_EQUAL=$([[ $first_context == $second_context ]] && print yes || print no)"
builtin print -r -- \
  "SMART_CONTEXTS_EQUAL=$([[ $first_smart_context == $second_smart_context ]] && print yes || print no)"
builtin print -r -- \
  "BRANCHES=${first_remote_branch#*|}->${second_remote_branch#*|}"
builtin print -r -- \
  "REMOTE_KEYS_EQUAL=$([[ ${first_remote_branch%%|*} == ${second_remote_branch%%|*} ]] && print yes || print no)"
builtin print -r -- "HIDE_INFO=${first_hide_info}->${second_hide_info}"
builtin print -r -- "DIRECT=${direct_common}|${direct_remote}"
""",
                cache_home=root / "cache",
                cwd=work_tree,
                env={
                    "SECOND_COMMON_DIR": str(second_common_dir),
                    "WORK_GIT_DIR": str(work_git_dir),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "ROOTS_EQUAL=yes\n"
            "CONTEXTS_EQUAL=no\n"
            "SMART_CONTEXTS_EQUAL=no\n"
            "BRANCHES=shared->shared\n"
            "REMOTE_KEYS_EQUAL=no\n"
            "HIDE_INFO=1->0\n"
            f"DIRECT={second_common_dir}|https://example.invalid/beta.git\n",
            result.stdout,
        )

    def test_relative_git_context_preserves_submodule_hierarchy(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "source"
            parent = root / "parent"
            nested = parent / "nested"
            deep = nested / "deep"
            source.mkdir()
            parent.mkdir()
            subprocess.run(["git", "-C", str(source), "init", "-q"], check=True)
            (source / "README").write_text("fixture\n", encoding="ascii")
            subprocess.run(["git", "-C", str(source), "add", "README"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(source),
                    "-c",
                    "user.name=Fixture User",
                    "-c",
                    "user.email=fixture@example.invalid",
                    "commit",
                    "-q",
                    "-m",
                    "fixture",
                ],
                check=True,
            )
            subprocess.run(["git", "-C", str(parent), "init", "-q"], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(parent),
                    "-c",
                    "protocol.file.allow=always",
                    "submodule",
                    "add",
                    "-q",
                    str(source),
                    "nested",
                ],
                check=True,
            )
            deep.mkdir()

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
export GIT_DIR=../../.git/modules/nested
export GIT_WORK_TREE=..
_ai_candy_get_cached_git_root
_AI_CANDY_PP_CACHED_GIT_ROOT="$REPLY"
_ai_candy_get_git_hierarchy
parts=("${(@ps.$_AI_CANDY_GIT_HIERARCHY_SEP.)REPLY}")
builtin print -r -- "PARTS=${#parts}"
builtin print -r -- "PARENT=${parts[1]}"
builtin print -r -- "NESTED=${parts[2]}"
builtin print -r -- "SUBDIR=${parts[3]}"
""",
                cache_home=root / "cache",
                cwd=deep,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"PARTS=3\nPARENT={parent}\nNESTED={nested}\nSUBDIR=deep\n",
            result.stdout,
        )

    def test_discovery_variables_partition_root_and_hierarchy_caches(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            child = repo / "child"
            marker = root / "git-probes"
            child.mkdir(parents=True)
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
functions[_probe_without_discovery_count]="${functions[_ai_candy_run_local_probe]}"
function _ai_candy_run_local_probe() {
  local command_line=" $* "
  if [[ "$1" == git && \
        "$command_line" == *' rev-parse --show-toplevel '* ]]; then
    builtin print -r -- --show-toplevel >>! "$PROBE_MARKER"
  elif [[ "$1" == git && \
          "$command_line" == *' rev-parse --show-superproject-working-tree '* ]]; then
    builtin print -r -- --show-superproject-working-tree >>! "$PROBE_MARKER"
  fi
  _probe_without_discovery_count "$@"
}
function read_git_context() {
  _ai_candy_get_cached_git_root
  roots+=("$REPLY")
  _AI_CANDY_PP_CACHED_GIT_ROOT="$REPLY"
  _ai_candy_get_git_hierarchy
  hierarchies+=("$REPLY")
}
typeset -a roots hierarchies probes
read_git_context
export GIT_COMMON_DIR="$REPO/.git"
read_git_context
unset GIT_COMMON_DIR
export GIT_DISCOVERY_ACROSS_FILESYSTEM=1
read_git_context
unset GIT_DISCOVERY_ACROSS_FILESYSTEM
read_git_context
probes=("${(@f)$(<"$PROBE_MARKER")}")
root_probes=${#${(M)probes:#--show-toplevel}}
hierarchy_probes=${#${(M)probes:#--show-superproject-working-tree}}
builtin print -r -- "ROOTS_EQUAL=$([[ ${roots[1]} == $REPO && ${roots[2]} == $REPO && ${roots[3]} == $REPO && ${roots[4]} == $REPO ]] && print yes || print no)"
builtin print -r -- "HIERARCHIES_EQUAL=$([[ ${hierarchies[1]} == ${hierarchies[2]} && ${hierarchies[1]} == ${hierarchies[3]} && ${hierarchies[1]} == ${hierarchies[4]} ]] && print yes || print no)"
builtin print -r -- "PROBES=${root_probes}|${hierarchy_probes}"
""",
                cache_home=root / "cache",
                cwd=child,
                env={"PROBE_MARKER": str(marker), "REPO": str(repo)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "ROOTS_EQUAL=yes\n"
            "HIERARCHIES_EQUAL=yes\n"
            "PROBES=3|3\n",
            result.stdout,
        )

    def test_nondefault_discovery_context_stays_in_session_memory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            child = repo / "child"
            child.mkdir(parents=True)
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)

            result = run_zsh(
                r"""
source "$1"
integer persistent_writes=0
function _ai_candy_cache_set() {
  (( ++persistent_writes ))
  return 0
}
export GIT_DISCOVERY_ACROSS_FILESYSTEM=1
_ai_candy_get_cached_git_root
_AI_CANDY_PP_CACHED_GIT_ROOT="$REPLY"
_ai_candy_get_git_hierarchy
builtin print -r -- "PERSISTENT_WRITES=${persistent_writes}"
""",
                cache_home=root / "cache",
                cwd=child,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("PERSISTENT_WRITES=0\n", result.stdout)

    def test_external_parent_repository_invalidates_a_negative_root_cache(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            parent = root / "parent"
            child = parent / "child"
            child.mkdir(parents=True)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_ai_candy_get_cached_git_root
before="$REPLY"
command git -C "$PARENT" init -q || return 70
direct=$(command git rev-parse --show-toplevel 2>/dev/null) || return 71
_ai_candy_get_cached_git_root
builtin print -r -- \
  "BEFORE=${before} DIRECT=${direct} AFTER=${REPLY}"
""",
                cache_home=root / "cache",
                cwd=child,
                env={"PARENT": str(parent)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"BEFORE=NOT_GIT DIRECT={parent} AFTER={parent}\n",
            result.stdout,
        )

    def test_symlinked_repository_root_cache_stays_hot(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            control = root / "control"
            real_repo = root / "real"
            real_child = real_repo / "child"
            link = root / "link"
            marker = root / "root-probes"
            control.mkdir()
            real_child.mkdir(parents=True)
            subprocess.run(
                ["git", "-C", str(real_repo), "init", "-q"],
                check=True,
            )
            link.symlink_to(real_repo, target_is_directory=True)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
unsetopt chase_links
builtin cd "$LINK/child"
logical_pwd="$PWD"
functions[_root_probe_without_count]="${functions[_ai_candy_run_local_probe]}"
function _ai_candy_run_local_probe() {
  if [[ "$1" == git && "$2" == rev-parse && "$3" == --show-toplevel ]]; then
    builtin print -r -- call >>! "$PROBE_MARKER"
  fi
  _root_probe_without_count "$@"
}
_ai_candy_get_cached_git_root
first="$REPLY"
_ai_candy_get_cached_git_root
second="$REPLY"
typeset -a root_probes
root_probes=("${(@f)$(<"$PROBE_MARKER")}")
builtin print -r -- \
  "PWD=${logical_pwd} FIRST=${first} SECOND=${second} CALLS=${#root_probes}"
""",
                cache_home=root / "cache",
                cwd=control,
                env={
                    "LINK": str(link),
                    "PROBE_MARKER": str(marker),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"PWD={link / 'child'} FIRST={real_repo} "
            f"SECOND={real_repo} CALLS=1\n",
            result.stdout,
        )

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
_AI_CANDY_LAST_EXIT_STATUS=$?
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
_AI_CANDY_LAST_EXIT_STATUS=$?
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
_AI_CANDY_LAST_EXIT_STATUS=$?
_ai_candy_prompt_apply_git_cache_invalidation
print -r -- "GENERATION=${_AI_CANDY_GIT_TOPOLOGY_GENERATION}"
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
print -r -- "GENERATION=${_AI_CANDY_GIT_TOPOLOGY_GENERATION} ROOT=${REPLY}"
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
_AI_CANDY_HAS_SQLITE3=0
_ai_candy_cache_persist_write git_root "0:$CHILD" NOT_GIT "$EPOCHSECONDS" || return 70
git -C "$PARENT" init -q || return 71
functions[_atomic_without_failure]="${functions[_ai_candy_cache_atomic_write_unlocked]}"
integer fail_generation_write=1
function _ai_candy_cache_atomic_write_unlocked() {
  if (( fail_generation_write )) && \
     [[ "$1" == "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE" ]]; then
    fail_generation_write=0
    return 1
  fi
  _atomic_without_failure "$@"
}
_ai_candy_record_git_topology_invalidation "$PARENT" || return 72
generation_after_failure="$_AI_CANDY_GIT_TOPOLOGY_GENERATION"
valid_after_failure="$_AI_CANDY_GIT_TOPOLOGY_GENERATION_VALID"
functions[_ai_candy_cache_atomic_write_unlocked]="${functions[_atomic_without_failure]}"
cd "$CHILD"
_ai_candy_get_cached_git_root
print -r -- "FAILED_GENERATION=${generation_after_failure} VALID=${valid_after_failure}"
print -r -- "GENERATION=${_AI_CANDY_GIT_TOPOLOGY_GENERATION} ROOT=${REPLY}"
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
_AI_CANDY_CACHE_READY=0
_ai_candy_record_git_topology_invalidation "$PWD"
generation="$_AI_CANDY_GIT_TOPOLOGY_GENERATION"
same=yes
for attempt in 1 2 3; do
  _ai_candy_get_cached_git_root
  [[ "$_AI_CANDY_GIT_TOPOLOGY_GENERATION" == "$generation" ]] || same=no
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
_AI_CANDY_HAS_SQLITE3=0
_ai_candy_cache_persist_write git_root "0:$CHILD" NOT_GIT "$EPOCHSECONDS" || return 70
git -C "$PARENT" init -q || return 71
_AI_CANDY_HAS_ZSH_SYSTEM=0
command mkdir -p "$_AI_CANDY_CACHE_COMMIT_LOCK"
print -r -- holder >| "${_AI_CANDY_CACHE_COMMIT_LOCK}/owner.test"
start="$EPOCHREALTIME"
_ai_candy_record_git_topology_invalidation "$PARENT"
elapsed=$(( EPOCHREALTIME - start ))
print -r -- "ELAPSED=${elapsed} VALID=${_AI_CANDY_GIT_TOPOLOGY_GENERATION_VALID}"
""",
                cache_home=cache_home,
                env={"PARENT": str(parent), "CHILD": str(child)},
            )
            reader = run_zsh(
                r"""
source "$1"
cd "$CHILD"
_ai_candy_get_cached_git_root
print -r -- "GENERATION=${_AI_CANDY_GIT_TOPOLOGY_GENERATION} ROOT=${REPLY}"
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
  if [[ "$1" == "$_AI_CANDY_GIT_TOPOLOGY_GENERATION_FILE" && \
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
_AI_CANDY_LAST_EXIT_STATUS=$?
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
_AI_CANDY_PP_CACHED_GIT_ROOT=NOT_GIT
_AI_CANDY_SMART_PATH_CONTEXT_KEY=""
_ai_candy_prepare_smart_path_context
builtin print -r -- "PATH=${_AI_CANDY_SMART_PATH_FALLBACK}"
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
_AI_CANDY_PP_CACHED_GIT_ROOT=NOT_GIT
_AI_CANDY_SMART_PATH_CONTEXT_KEY=""
_ai_candy_prepare_smart_path_context
builtin print -r -- "PATH=${_AI_CANDY_SMART_PATH_FALLBACK}"
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
_AI_CANDY_PP_CACHED_GIT_ROOT="$REPLY"
_AI_CANDY_SMART_PATH_CONTEXT_KEY=""
_ai_candy_prepare_smart_path_context
builtin print -r -- "PATH=${_AI_CANDY_SMART_PATH_SEGMENTS[1]}"
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
_AI_CANDY_PROMPT_RENDER_ID=1
_AI_CANDY_PP_CACHED_GIT_ROOT="$PWD"
_ai_candy_get_cached_git_remote_branch
before="$REPLY"
_ai_candy_prompt_mark_git_cache_invalidation \
  "git config remote.origin.url https://example.invalid/two.git" \
  "git config remote.origin.url https://example.invalid/two.git" \
  "git config remote.origin.url https://example.invalid/two.git"
git config remote.origin.url https://example.invalid/two.git
_AI_CANDY_LAST_EXIT_STATUS=$?
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
_AI_CANDY_PP_CACHED_GIT_ROOT="$TARGET"
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_get_cached_git_remote_branch
before="$REPLY"
cd "$CONTROL"
_AI_CANDY_PP_CACHED_GIT_ROOT=NOT_GIT
_ai_candy_prompt_mark_git_cache_invalidation \
  "git -C $TARGET remote set-url origin https://example.invalid/two.git" \
  "git -C $TARGET remote set-url origin https://example.invalid/two.git" \
  "git -C $TARGET remote set-url origin https://example.invalid/two.git"
git -C "$TARGET" remote set-url origin https://example.invalid/two.git
_AI_CANDY_LAST_EXIT_STATUS=$?
_ai_candy_prompt_apply_git_cache_invalidation
cd "$TARGET"
_AI_CANDY_PP_CACHED_GIT_ROOT="$TARGET"
(( ++_AI_CANDY_PROMPT_RENDER_ID ))
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
