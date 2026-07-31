#!/usr/bin/env python3
import subprocess
import tempfile
import unittest
from pathlib import Path

from tests.theme_test_support import run_zsh


CONFIG_SWITCH_SCRIPT = r"""
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

case "$SWITCH_KIND" in
  count)
    export GIT_CONFIG_COUNT=2
    export GIT_CONFIG_KEY_0=remote.origin.url
    export GIT_CONFIG_VALUE_0=https://example.invalid/beta.git
    export GIT_CONFIG_KEY_1=oh-my-zsh.hide-info
    export GIT_CONFIG_VALUE_1=0
    ;;
  global-link)
    command rm "$CONFIG_LINK" || return 70
    command ln -s "$SECOND_CONFIG" "$CONFIG_LINK" || return 71
    ;;
  global-rewrite)
    command git config --global remote.origin.url \
      https://example.invalid/beta.git || return 70
    command git config --global oh-my-zsh.hide-info 0 || return 71
    ;;
  included-rewrite)
    command git config --file "$INCLUDED_CONFIG" remote.origin.url \
      https://example.invalid/beta.git || return 70
    command git config --file "$INCLUDED_CONFIG" oh-my-zsh.hide-info 0 || \
      return 71
    ;;
  included-create)
    command git config --file "$INCLUDED_CONFIG" remote.origin.url \
      https://example.invalid/beta.git || return 70
    command git config --file "$INCLUDED_CONFIG" oh-my-zsh.hide-info 0 || \
      return 71
    ;;
  branch)
    command git symbolic-ref HEAD refs/heads/feature || return 70
    ;;
  home)
    export HOME="$SECOND_CONFIG_ROOT"
    ;;
  xdg)
    export XDG_CONFIG_HOME="$SECOND_CONFIG_ROOT"
    ;;
  *) return 72 ;;
esac
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

direct_remote=$(command git config --get remote.origin.url 2>/dev/null) || \
  return 73
direct_hide=$(command git config --get oh-my-zsh.hide-info 2>/dev/null) || \
  return 74
builtin print -r -- \
  "ROOTS_EQUAL=$([[ $first_root == $second_root ]] && print yes || print no)"
builtin print -r -- \
  "CONTEXTS_EQUAL=$([[ $first_context == $second_context ]] && print yes || print no)"
builtin print -r -- \
  "BRANCHES=${first_remote_branch#*|}->${second_remote_branch#*|}"
builtin print -r -- \
  "REMOTE_KEYS_EQUAL=$([[ ${first_remote_branch%%|*} == ${second_remote_branch%%|*} ]] && print yes || print no)"
builtin print -r -- "HIDE_INFO=${first_hide_info}->${second_hide_info}"
builtin print -r -- "DIRECT=${direct_remote}|${direct_hide}"
"""


def configure_worktree_git_dir(git_dir: Path, work_tree: Path) -> None:
    subprocess.run(["git", "init", "--bare", "-q", str(git_dir)], check=True)
    for key, value in (
        ("core.bare", "false"),
        ("core.worktree", str(work_tree)),
    ):
        subprocess.run(
            ["git", f"--git-dir={git_dir}", "config", key, value], check=True
        )
    subprocess.run(
        [
            "git",
            f"--git-dir={git_dir}",
            "symbolic-ref",
            "HEAD",
            "refs/heads/main",
        ],
        check=True,
    )


def configure_repository(repo: Path) -> None:
    repo.mkdir()
    subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)
    subprocess.run(
        ["git", "-C", str(repo), "symbolic-ref", "HEAD", "refs/heads/main"],
        check=True,
    )


def configure_local_values(repo: Path) -> None:
    for key, value in (
        ("remote.origin.url", "https://example.invalid/alpha.git"),
        ("oh-my-zsh.hide-info", "1"),
    ):
        subprocess.run(["git", "-C", str(repo), "config", key, value], check=True)


def write_global_config(path: Path, remote: str, hide_info: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        '[remote "origin"]\n'
        f"\turl = https://example.invalid/{remote}\n"
        "[oh-my-zsh]\n"
        f"\thide-info = {hide_info}\n",
        encoding="ascii",
    )


def write_config_include(path: Path, included_path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "[include]\n" f"\tpath = {included_path}\n",
        encoding="ascii",
    )


def write_global_config_with_relative_include(
    path: Path,
    remote: str,
    hide_info: str,
    included_name: str,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        '[remote "origin"]\n'
        f"\turl = https://example.invalid/{remote}\n"
        "[oh-my-zsh]\n"
        f"\thide-info = {hide_info}\n"
        "[include]\n"
        f"\tpath = {included_name}\n",
        encoding="ascii",
    )


def write_branch_config_includes(
    path: Path,
    main_config: Path,
    feature_config: Path,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        '[includeIf "onbranch:main"]\n'
        f"\tpath = {main_config}\n"
        '[includeIf "onbranch:feature"]\n'
        f"\tpath = {feature_config}\n",
        encoding="ascii",
    )


class GitContextRuntimeTest(unittest.TestCase):
    def assert_config_switch(
        self,
        repo: Path,
        cache_home: Path,
        switch_kind: str,
        env=None,
        expected_branches: str = "main->main",
    ) -> None:
        result = run_zsh(
            CONFIG_SWITCH_SCRIPT,
            cache_home=cache_home,
            cwd=repo,
            env={"SWITCH_KIND": switch_kind, **(env or {})},
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "ROOTS_EQUAL=yes\n"
            "CONTEXTS_EQUAL=no\n"
            f"BRANCHES={expected_branches}\n"
            "REMOTE_KEYS_EQUAL=no\n"
            "HIDE_INFO=1->0\n"
            "DIRECT=https://example.invalid/beta.git|0\n",
            result.stdout,
        )

    def test_invalid_implicit_git_dir_cannot_reuse_a_positive_root(self) -> None:
        for marker_kind in ("gitfile", "symlink"):
            with (
                self.subTest(marker_kind=marker_kind),
                tempfile.TemporaryDirectory() as tmp,
            ):
                root = Path(tmp)
                work_tree = root / "work"
                git_dir = root / "valid.git"
                git_marker = work_tree / ".git"
                work_tree.mkdir()
                configure_worktree_git_dir(git_dir, work_tree)
                if marker_kind == "gitfile":
                    git_marker.write_text(f"gitdir: {git_dir}\n", encoding="ascii")
                else:
                    git_marker.symlink_to(git_dir, target_is_directory=True)

                result = run_zsh(
                    r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_get_cached_git_root
first_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$first_root"
_ai_candy_get_git_hierarchy
first_hierarchy="$REPLY"

if [[ "$MARKER_KIND" == gitfile ]]; then
  builtin print -r -- "gitdir: $MISSING_GIT_DIR" >| "$WORK_TREE/.git" || \
    return 70
else
  command rm "$WORK_TREE/.git" || return 71
  command ln -s "$MISSING_GIT_DIR" "$WORK_TREE/.git" || return 72
fi
(( ++_AI_CANDY_PROMPT_RENDER_ID ))
direct_root=$(command git rev-parse --show-toplevel 2>/dev/null) || \
  direct_root=NOT_GIT
_ai_candy_get_cached_git_root
second_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$second_root"
_ai_candy_get_git_hierarchy
second_hierarchy="$REPLY"
builtin print -r -- "ROOT=${first_root}->${second_root}"
builtin print -r -- \
  "HIERARCHY=${first_hierarchy:+set}->${second_hierarchy:+set}"
builtin print -r -- "DIRECT=${direct_root}"
""",
                    cache_home=root / "cache",
                    cwd=work_tree,
                    env={
                        "MARKER_KIND": marker_kind,
                        "MISSING_GIT_DIR": str(root / "missing.git"),
                        "WORK_TREE": str(work_tree),
                    },
                )

                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual(
                    f"ROOT={work_tree}->NOT_GIT\nHIERARCHY=set->\nDIRECT=NOT_GIT\n",
                    result.stdout,
                )

    def test_valid_implicit_git_dir_retarget_recomputes_the_worktree_root(
        self,
    ) -> None:
        for marker_kind in ("gitfile", "symlink"):
            with (
                self.subTest(marker_kind=marker_kind),
                tempfile.TemporaryDirectory() as tmp,
            ):
                root = Path(tmp)
                first_work_tree = root / "work-alpha"
                second_work_tree = root / "work-beta"
                first_git_dir = root / "alpha.git"
                second_git_dir = root / "beta.git"
                git_marker = first_work_tree / ".git"
                first_work_tree.mkdir()
                second_work_tree.mkdir()
                configure_worktree_git_dir(first_git_dir, first_work_tree)
                configure_worktree_git_dir(second_git_dir, second_work_tree)
                if marker_kind == "gitfile":
                    git_marker.write_text(
                        f"gitdir: {first_git_dir}\n", encoding="ascii"
                    )
                else:
                    git_marker.symlink_to(first_git_dir, target_is_directory=True)

                result = run_zsh(
                    r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
function _ai_candy_run_local_probe() {
  if [[ "$1" == git && "$2" == rev-parse && \
        "$3" == --show-toplevel ]]; then
    builtin print -r -- probe >> "$ROOT_PROBE_LOG"
  fi
  _ai_candy_run_with_timeout \
    "${_AI_CANDY_LOCAL_PROMPT_TIMEOUT:-0.25}" "$@"
}

_ai_candy_get_cached_git_root
first_root="$REPLY"
if [[ "$MARKER_KIND" == gitfile ]]; then
  builtin print -r -- "gitdir: $SECOND_GIT_DIR" >| \
    "$FIRST_WORK_TREE/.git" || return 70
else
  command rm "$FIRST_WORK_TREE/.git" || return 71
  command ln -s "$SECOND_GIT_DIR" "$FIRST_WORK_TREE/.git" || return 72
fi
direct_root=$(command git rev-parse --show-toplevel 2>/dev/null) || \
  return 73
_ai_candy_get_cached_git_root
second_root="$REPLY"
_ai_candy_get_cached_git_root
third_root="$REPLY"
local -a root_probes
root_probes=("${(@f)$(<"$ROOT_PROBE_LOG")}")
builtin print -r -- \
  "ROOT=${first_root}->${second_root}->${third_root}"
builtin print -r -- "DIRECT=${direct_root} PROBES=${#root_probes}"
""",
                    cache_home=root / "cache",
                    cwd=first_work_tree,
                    env={
                        "FIRST_WORK_TREE": str(first_work_tree),
                        "MARKER_KIND": marker_kind,
                        "ROOT_PROBE_LOG": str(root / "root-probes.log"),
                        "SECOND_GIT_DIR": str(second_git_dir),
                    },
                )

                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual(
                    f"ROOT={first_work_tree}->{second_work_tree}->"
                    f"{second_work_tree}\n"
                    f"DIRECT={second_work_tree} PROBES=2\n",
                    result.stdout,
                )

    def test_repository_config_changes_recompute_the_worktree_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            first_work_tree = root / "work-alpha"
            second_work_tree = root / "work-beta"
            git_dir = root / "repo.git"
            first_work_tree.mkdir()
            second_work_tree.mkdir()
            configure_worktree_git_dir(git_dir, first_work_tree)
            (first_work_tree / ".git").write_text(
                f"gitdir: {git_dir}\n", encoding="ascii"
            )

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
function _ai_candy_run_local_probe() {
  if [[ "$1" == git && "$2" == rev-parse && \
        "$3" == --show-toplevel ]]; then
    builtin print -r -- probe >> "$ROOT_PROBE_LOG"
  fi
  _ai_candy_run_with_timeout \
    "${_AI_CANDY_LOCAL_PROMPT_TIMEOUT:-0.25}" "$@"
}

_ai_candy_get_cached_git_root
first_root="$REPLY"
command git --git-dir="$GIT_DIR_PATH" config \
  core.worktree "$SECOND_WORK_TREE" || return 70
direct_second=$(command git rev-parse --show-toplevel 2>/dev/null) || \
  return 71
_ai_candy_get_cached_git_root
second_root="$REPLY"
command git --git-dir="$GIT_DIR_PATH" config core.bare true || return 72
direct_third=$(command git rev-parse --show-toplevel 2>/dev/null) || \
  direct_third=NOT_GIT
_ai_candy_get_cached_git_root
third_root="$REPLY"
local -a root_probes
root_probes=("${(@f)$(<"$ROOT_PROBE_LOG")}")
builtin print -r -- \
  "ROOT=${first_root}->${second_root}->${third_root}"
builtin print -r -- \
  "DIRECT=${direct_second}->${direct_third} PROBES=${#root_probes}"
""",
                cache_home=root / "cache",
                cwd=first_work_tree,
                env={
                    "GIT_DIR_PATH": str(git_dir),
                    "ROOT_PROBE_LOG": str(root / "root-probes.log"),
                    "SECOND_WORK_TREE": str(second_work_tree),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"ROOT={first_work_tree}->{second_work_tree}->NOT_GIT\n"
            f"DIRECT={second_work_tree}->NOT_GIT PROBES=3\n",
            result.stdout,
        )

    def test_same_second_same_size_config_rewrite_survives_theme_reload(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            first_work_tree = root / "work-alpha"
            second_work_tree = root / "work-bravo"
            git_dir = root / "repo.git"
            first_work_tree.mkdir()
            second_work_tree.mkdir()
            configure_worktree_git_dir(git_dir, first_work_tree)
            (first_work_tree / ".git").write_text(
                f"gitdir: {git_dir}\n", encoding="ascii"
            )

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
function _ai_candy_test_counted_local_probe() {
  if [[ "$1" == git && "$2" == rev-parse && \
        "$3" == --show-toplevel ]]; then
    builtin print -r -- probe >> "$ROOT_PROBE_LOG"
  fi
  _ai_candy_run_with_timeout \
    "${_AI_CANDY_LOCAL_PROMPT_TIMEOUT:-0.25}" "$@"
}
functions[_ai_candy_run_local_probe]="${functions[_ai_candy_test_counted_local_probe]}"

config_file="$GIT_DIR_PATH/config"
first_config="$(<"$config_file")"
second_config="${first_config//$FIRST_WORK_TREE/$SECOND_WORK_TREE}"
[[ "$first_config" != "$second_config" && \
   ${#first_config} == ${#second_config} ]] || return 70
while (( EPOCHREALTIME - EPOCHSECONDS > 0.05 )); do
  _ai_candy_sleep_ticks 1
done
builtin print -r -- "$first_config" >| "$config_file" || return 71
local -A first_metadata second_metadata
builtin zstat -H first_metadata -- "$config_file" || return 72
_ai_candy_get_cached_git_root
first_root="$REPLY"
_ai_candy_git_metadata_context_key "$_AI_CANDY_PHYSICAL_PWD"
first_context="$REPLY"
builtin print -r -- "$second_config" >| "$config_file" || return 73
builtin zstat -H second_metadata -- "$config_file" || return 74
for field in device inode size mtime ctime; do
  [[ "${first_metadata[$field]}" == "${second_metadata[$field]}" ]] || \
    return 75
done
rewrite_second=$EPOCHSECONDS
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
functions[_ai_candy_run_local_probe]="${functions[_ai_candy_test_counted_local_probe]}"
direct_root=$(command git rev-parse --show-toplevel 2>/dev/null) || return 76
_ai_candy_get_cached_git_root
second_root="$REPLY"
_ai_candy_git_metadata_context_key "$_AI_CANDY_PHYSICAL_PWD"
second_context="$REPLY"
while (( EPOCHSECONDS == rewrite_second )); do
  _ai_candy_sleep_ticks 1
done
_ai_candy_get_cached_git_root
third_root="$REPLY"
_ai_candy_get_cached_git_root
fourth_root="$REPLY"
local -a root_probes
root_probes=("${(@f)$(<"$ROOT_PROBE_LOG")}")
builtin print -r -- \
  "ROOT=${first_root}->${second_root}->${third_root}->${fourth_root}"
builtin print -r -- \
  "CONTEXT_EQUAL=$([[ "$first_context" == "$second_context" ]] && \
    builtin print yes || builtin print no)"
builtin print -r -- "DIRECT=${direct_root} PROBES=${#root_probes}"
""",
                cache_home=root / "cache",
                cwd=first_work_tree,
                env={
                    "FIRST_WORK_TREE": str(first_work_tree),
                    "GIT_DIR_PATH": str(git_dir),
                    "ROOT_PROBE_LOG": str(root / "root-probes.log"),
                    "SECOND_WORK_TREE": str(second_work_tree),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"ROOT={first_work_tree}->{second_work_tree}->"
            f"{second_work_tree}->{second_work_tree}\n"
            "CONTEXT_EQUAL=no\n"
            f"DIRECT={second_work_tree} PROBES=2\n",
            result.stdout,
        )

    def test_same_second_config_rewrite_is_seen_after_the_second_changes(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            first_work_tree = root / "work-alpha"
            second_work_tree = root / "work-bravo"
            git_dir = root / "repo.git"
            first_work_tree.mkdir()
            second_work_tree.mkdir()
            configure_worktree_git_dir(git_dir, first_work_tree)
            (first_work_tree / ".git").write_text(
                f"gitdir: {git_dir}\n", encoding="ascii"
            )

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
function _ai_candy_test_counted_local_probe() {
  if [[ "$1" == git && "$2" == rev-parse && \
        "$3" == --show-toplevel ]]; then
    builtin print -r -- probe >> "$ROOT_PROBE_LOG"
  fi
  _ai_candy_run_with_timeout \
    "${_AI_CANDY_LOCAL_PROMPT_TIMEOUT:-0.25}" "$@"
}
functions[_ai_candy_run_local_probe]="${functions[_ai_candy_test_counted_local_probe]}"

config_file="$GIT_DIR_PATH/config"
first_config="$(<"$config_file")"
second_config="${first_config//$FIRST_WORK_TREE/$SECOND_WORK_TREE}"
[[ "$first_config" != "$second_config" && \
   ${#first_config} == ${#second_config} ]] || return 70
while (( EPOCHREALTIME - EPOCHSECONDS > 0.05 )); do
  _ai_candy_sleep_ticks 1
done
builtin print -r -- "$first_config" >| "$config_file" || return 71
local -A first_metadata second_metadata
builtin zstat -H first_metadata -- "$config_file" || return 72
_ai_candy_get_cached_git_root
first_root="$REPLY"
builtin print -r -- "$second_config" >| "$config_file" || return 73
builtin zstat -H second_metadata -- "$config_file" || return 74
for field in device inode size mtime ctime; do
  [[ "${first_metadata[$field]}" == "${second_metadata[$field]}" ]] || \
    return 75
done
rewrite_second=$EPOCHSECONDS
while (( EPOCHSECONDS == rewrite_second )); do
  _ai_candy_sleep_ticks 1
done
direct_root=$(command git rev-parse --show-toplevel 2>/dev/null) || return 76
_ai_candy_get_cached_git_root
second_root="$REPLY"
local -a root_probes
root_probes=("${(@f)$(<"$ROOT_PROBE_LOG")}")
builtin print -r -- "ROOT=${first_root}->${second_root}"
builtin print -r -- "DIRECT=${direct_root} PROBES=${#root_probes}"
""",
                cache_home=root / "cache",
                cwd=first_work_tree,
                env={
                    "FIRST_WORK_TREE": str(first_work_tree),
                    "GIT_DIR_PATH": str(git_dir),
                    "ROOT_PROBE_LOG": str(root / "root-probes.log"),
                    "SECOND_WORK_TREE": str(second_work_tree),
                },
                timeout=5,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"ROOT={first_work_tree}->{second_work_tree}\n"
            f"DIRECT={second_work_tree} PROBES=2\n",
            result.stdout,
        )

    def test_logical_symlink_retarget_does_not_pollute_the_new_target_key(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            first_repo = root / "alpha"
            second_repo = root / "beta"
            first_child = first_repo / "child"
            second_child = second_repo / "child"
            logical_link = root / "current"
            configure_repository(first_repo)
            configure_repository(second_repo)
            first_child.mkdir()
            second_child.mkdir()
            logical_link.symlink_to(first_repo, target_is_directory=True)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
function _ai_candy_run_local_probe() {
  if [[ "$1" == git && "$2" == rev-parse && \
        "$3" == --show-toplevel ]]; then
    builtin print -r -- probe >> "$ROOT_PROBE_LOG"
  fi
  _ai_candy_run_with_timeout \
    "${_AI_CANDY_LOCAL_PROMPT_TIMEOUT:-0.25}" "$@"
}

builtin cd "$LOGICAL_LINK/child" || return 70
_ai_candy_get_cached_git_root
first_root="$REPLY"
command rm "$LOGICAL_LINK" || return 71
command ln -s "$SECOND_REPO" "$LOGICAL_LINK" || return 72
direct_still=$(command git rev-parse --show-toplevel 2>/dev/null) || return 73
_ai_candy_get_cached_git_root
still_root="$REPLY"
builtin cd "$FIXTURE_ROOT" || return 74
builtin cd "$LOGICAL_LINK/child" || return 75
direct_after=$(command git rev-parse --show-toplevel 2>/dev/null) || return 76
_ai_candy_get_cached_git_root
after_root="$REPLY"
local -a root_probes
root_probes=("${(@f)$(<"$ROOT_PROBE_LOG")}")
builtin print -r -- \
  "ROOT=${first_root}->${still_root}->${after_root}"
builtin print -r -- \
  "DIRECT=${direct_still}->${direct_after} PROBES=${#root_probes}"
""",
                cache_home=root / "cache",
                cwd=root,
                env={
                    "FIXTURE_ROOT": str(root),
                    "LOGICAL_LINK": str(logical_link),
                    "ROOT_PROBE_LOG": str(root / "root-probes.log"),
                    "SECOND_REPO": str(second_repo),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"ROOT={first_repo}->{first_repo}->{second_repo}\n"
            f"DIRECT={first_repo}->{second_repo} PROBES=2\n",
            result.stdout,
        )

    def test_external_directory_rename_does_not_pollute_a_reused_path(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            current_repo = root / "current"
            moved_repo = root / "moved"
            configure_repository(current_repo)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
function _ai_candy_run_local_probe() {
  if [[ "$1" == git && "$2" == rev-parse && \
        "$3" == --show-toplevel ]]; then
    builtin print -r -- probe >> "$ROOT_PROBE_LOG"
  fi
  _ai_candy_run_with_timeout \
    "${_AI_CANDY_LOCAL_PROMPT_TIMEOUT:-0.25}" "$@"
}

_ai_candy_get_cached_git_root
first_root="$REPLY"
functions[_ai_candy_test_capture_physical_pwd]="${functions[_ai_candy_capture_physical_pwd]}"
integer _AI_CANDY_TEST_RENAMED=0
function _ai_candy_capture_physical_pwd() {
  _ai_candy_test_capture_physical_pwd || return 1
  if (( ! _AI_CANDY_TEST_RENAMED )); then
    _AI_CANDY_TEST_RENAMED=1
    command mv "$CURRENT_REPO" "$MOVED_REPO" || builtin exit 70
    command git init -q "$CURRENT_REPO" || builtin exit 71
    command git -C "$CURRENT_REPO" symbolic-ref HEAD refs/heads/main || \
      builtin exit 72
  fi
  return 0
}
_ai_candy_get_cached_git_root
still_root="$REPLY"
direct_still=$(command git rev-parse --show-toplevel 2>/dev/null) || return 73
builtin cd "$FIXTURE_ROOT" || return 74
builtin cd "$CURRENT_REPO" || return 75
direct_after=$(command git rev-parse --show-toplevel 2>/dev/null) || return 76
_ai_candy_get_cached_git_root
after_root="$REPLY"
local -a root_probes
root_probes=("${(@f)$(<"$ROOT_PROBE_LOG")}")
builtin print -r -- \
  "ROOT=${first_root}->${still_root}->${after_root}"
builtin print -r -- \
  "DIRECT=${direct_still}->${direct_after} PROBES=${#root_probes}"
""",
                cache_home=root / "cache",
                cwd=current_repo,
                env={
                    "CURRENT_REPO": str(current_repo),
                    "FIXTURE_ROOT": str(root),
                    "MOVED_REPO": str(moved_repo),
                    "ROOT_PROBE_LOG": str(root / "root-probes.log"),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"ROOT={current_repo}->{moved_repo}->{current_repo}\n"
            f"DIRECT={moved_repo}->{current_repo} PROBES=3\n",
            result.stdout,
        )

    def test_invalid_common_dir_cannot_reuse_a_positive_root(self) -> None:
        for common_kind in ("file", "symlink"):
            with (
                self.subTest(common_kind=common_kind),
                tempfile.TemporaryDirectory() as tmp,
            ):
                root = Path(tmp)
                source = root / "source"
                common_dir = root / "common.git"
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
                subprocess.run(
                    ["git", "clone", "--bare", "-q", str(source), str(common_dir)],
                    check=True,
                )
                subprocess.run(
                    [
                        "git",
                        f"--git-dir={common_dir}",
                        "worktree",
                        "add",
                        "-q",
                        str(work_tree),
                        "HEAD",
                    ],
                    check=True,
                )
                work_git_dir = common_dir / "worktrees" / work_tree.name

                result = run_zsh(
                    r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_get_cached_git_root
first_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$first_root"
_ai_candy_get_git_hierarchy
first_hierarchy="$REPLY"
if [[ "$COMMON_KIND" == file ]]; then
  builtin print -r -- "$MISSING_COMMON_DIR" >| "$WORK_GIT_DIR/commondir" || \
    return 70
else
  command rm "$WORK_GIT_DIR/commondir" || return 71
  command ln -s "$MISSING_COMMON_FILE" "$WORK_GIT_DIR/commondir" || \
    return 72
fi
(( ++_AI_CANDY_PROMPT_RENDER_ID ))
direct_root=$(command git rev-parse --show-toplevel 2>/dev/null) || \
  direct_root=NOT_GIT
_ai_candy_get_cached_git_root
second_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$second_root"
_ai_candy_get_git_hierarchy
second_hierarchy="$REPLY"
builtin print -r -- "ROOT=${first_root}->${second_root}"
builtin print -r -- \
  "HIERARCHY=${first_hierarchy:+set}->${second_hierarchy:+set}"
builtin print -r -- "DIRECT=${direct_root}"
""",
                    cache_home=root / "cache",
                    cwd=work_tree,
                    env={
                        "COMMON_KIND": common_kind,
                        "MISSING_COMMON_DIR": str(root / "missing-common.git"),
                        "MISSING_COMMON_FILE": str(root / "missing-commondir"),
                        "WORK_GIT_DIR": str(work_git_dir),
                    },
                )

                self.assertEqual(0, result.returncode, result.stderr)
                self.assertEqual(
                    f"ROOT={work_tree}->NOT_GIT\nHIERARCHY=set->\nDIRECT=NOT_GIT\n",
                    result.stdout,
                )

    def test_config_count_overrides_partition_derived_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            configure_repository(repo)
            configure_local_values(repo)
            self.assert_config_switch(repo, root / "cache", "count")

    def test_global_config_symlink_retarget_partitions_derived_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            first_config = root / "alpha.config"
            second_config = root / "beta.config"
            config_link = root / "global.config"
            configure_repository(repo)
            write_global_config(first_config, "alpha.git", "1")
            write_global_config(second_config, "beta.git", "0")
            config_link.symlink_to(first_config)
            self.assert_config_switch(
                repo,
                root / "cache",
                "global-link",
                {
                    "CONFIG_LINK": str(config_link),
                    "GIT_CONFIG_GLOBAL": str(config_link),
                    "SECOND_CONFIG": str(second_config),
                },
            )

    def test_default_global_config_rewrite_partitions_derived_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            home = root / "home"
            configure_repository(repo)
            write_global_config(home / ".gitconfig", "alpha.git", "1")
            self.assert_config_switch(
                repo,
                root / "cache",
                "global-rewrite",
                {
                    "HOME": str(home),
                    "GIT_CONFIG_NOSYSTEM": "1",
                    "XDG_CONFIG_HOME": str(root / "xdg"),
                },
            )

    def test_false_nosystem_value_tracks_system_config_creation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            system_config = root / "system.config"
            configure_repository(repo)

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

command git config --file "$SYSTEM_CONFIG" remote.origin.url \
  https://example.invalid/system.git || return 70
command git config --file "$SYSTEM_CONFIG" oh-my-zsh.hide-info 1 || \
  return 71
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

direct_remote=$(command git config --get remote.origin.url) || return 72
direct_hide=$(command git config --get oh-my-zsh.hide-info) || return 73
builtin print -r -- \
  "CONTEXTS_EQUAL=$([[ $first_context == $second_context ]] && print yes || print no)"
builtin print -r -- \
  "FIRST_REMOTE_EMPTY=$([[ -z $first_remote_branch ]] && print yes || print no)"
builtin print -r -- \
  "SECOND_REMOTE_EMPTY=$([[ -z $second_remote_branch ]] && print yes || print no)"
builtin print -r -- "HIDE_INFO=${first_hide_info}->${second_hide_info}"
builtin print -r -- "DIRECT=${direct_remote}|${direct_hide}"
""",
                cache_home=root / "cache",
                cwd=repo,
                env={
                    "GIT_CONFIG_NOSYSTEM": "0",
                    "GIT_CONFIG_SYSTEM": str(system_config),
                    "HOME": str(root / "home"),
                    "SYSTEM_CONFIG": str(system_config),
                    "XDG_CONFIG_HOME": str(root / "xdg"),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "CONTEXTS_EQUAL=no\n"
            "FIRST_REMOTE_EMPTY=yes\n"
            "SECOND_REMOTE_EMPTY=no\n"
            "HIDE_INFO=0->1\n"
            "DIRECT=https://example.invalid/system.git|1\n",
            result.stdout,
        )

    def test_loaded_include_rewrite_partitions_derived_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            home = root / "home"
            included_config = root / "included.config"
            configure_repository(repo)
            write_global_config(included_config, "alpha.git", "1")
            write_config_include(home / ".gitconfig", included_config)
            self.assert_config_switch(
                repo,
                root / "cache",
                "included-rewrite",
                {
                    "HOME": str(home),
                    "GIT_CONFIG_NOSYSTEM": "1",
                    "INCLUDED_CONFIG": str(included_config),
                    "XDG_CONFIG_HOME": str(root / "xdg"),
                },
            )

    def test_missing_relative_include_creation_partitions_derived_state(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            home = root / "home"
            included_config = home / "included.config"
            configure_repository(repo)
            write_global_config_with_relative_include(
                home / ".gitconfig",
                "alpha.git",
                "1",
                included_config.name,
            )
            self.assert_config_switch(
                repo,
                root / "cache",
                "included-create",
                {
                    "HOME": str(home),
                    "GIT_CONFIG_NOSYSTEM": "1",
                    "INCLUDED_CONFIG": str(included_config),
                    "XDG_CONFIG_HOME": str(root / "xdg"),
                },
            )

    def test_onbranch_include_switch_partitions_pr_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            home = root / "home"
            main_config = root / "main.config"
            feature_config = root / "feature.config"
            configure_repository(repo)
            write_global_config(main_config, "alpha.git", "1")
            write_global_config(feature_config, "beta.git", "0")
            write_branch_config_includes(
                home / ".gitconfig",
                main_config,
                feature_config,
            )
            self.assert_config_switch(
                repo,
                root / "cache",
                "branch",
                {
                    "HOME": str(home),
                    "GIT_CONFIG_NOSYSTEM": "1",
                    "XDG_CONFIG_HOME": str(root / "xdg"),
                },
                expected_branches="main->feature",
            )

    def test_stable_config_graph_reuses_one_discovery_scan(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            child = repo / "child"
            home = root / "home"
            included_config = root / "included.config"
            configure_repository(repo)
            child.mkdir()
            write_global_config(included_config, "alpha.git", "1")
            write_config_include(home / ".gitconfig", included_config)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
functions[_ai_candy_test_original_local_probe]="${functions[_ai_candy_run_local_probe]}"
function _ai_candy_run_local_probe() {
  if (( ${@[(Ie)--show-origin]} )); then
    builtin print -r -- scan >> "$SCAN_LOG"
  fi
  _ai_candy_test_original_local_probe "$@"
}

_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_get_cached_git_root
git_root="$REPLY"
_ai_candy_git_context_cache_key "$git_root"
_ai_candy_load_git_display_options "$git_root"
_ai_candy_get_cached_git_remote_branch
local -a scans
scans=("${(@f)$(<"$SCAN_LOG")}")
first_count=${#scans}

(( ++_AI_CANDY_PROMPT_RENDER_ID ))
_ai_candy_get_cached_git_root
git_root="$REPLY"
_ai_candy_git_context_cache_key "$git_root"
_ai_candy_load_git_display_options "$git_root"
_ai_candy_get_cached_git_remote_branch
scans=("${(@f)$(<"$SCAN_LOG")}")
builtin print -r -- "SCANS=${first_count}->${#scans}"
""",
                cache_home=root / "cache",
                cwd=child,
                env={
                    "HOME": str(home),
                    "GIT_CONFIG_NOSYSTEM": "1",
                    "SCAN_LOG": str(root / "scan.log"),
                    "XDG_CONFIG_HOME": str(root / "xdg"),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("SCANS=2->2\n", result.stdout)

    def test_config_graph_scan_failure_is_not_cacheable(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            configure_repository(repo)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
function _ai_candy_git_scan_config_graph_paths() { return 1; }

_AI_CANDY_PROMPT_RENDER_ID=1
_ai_candy_get_cached_git_root
first_root="$REPLY"
_ai_candy_git_context_cache_key "$first_root"
first_context="$REPLY"
first_cacheable="$_AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE"
first_persistable="$_AI_CANDY_GIT_METADATA_CONTEXT_PERSISTABLE"

(( ++_AI_CANDY_PROMPT_RENDER_ID ))
_ai_candy_get_cached_git_root
second_root="$REPLY"
_ai_candy_git_context_cache_key "$second_root"
second_context="$REPLY"
builtin print -r -- \
  "ROOTS=${first_root}->${second_root}"
builtin print -r -- \
  "CONTEXTS_EQUAL=$([[ $first_context == $second_context ]] && print yes || print no)"
builtin print -r -- \
  "CACHEABLE=${first_cacheable}|${_AI_CANDY_GIT_METADATA_CONTEXT_CACHEABLE}"
builtin print -r -- \
  "PERSISTABLE=${first_persistable}|${_AI_CANDY_GIT_METADATA_CONTEXT_PERSISTABLE}"
""",
                cache_home=root / "cache",
                cwd=repo,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"ROOTS={repo}->{repo}\n"
            "CONTEXTS_EQUAL=no\n"
            "CACHEABLE=0|0\n"
            "PERSISTABLE=0|0\n",
            result.stdout,
        )

    def test_relative_config_tracks_the_current_shell_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            child = repo / "child"
            root_config = repo / "custom.config"
            child_config = child / "custom.config"
            configure_repository(repo)
            child.mkdir()
            write_global_config(root_config, "alpha.git", "1")
            write_global_config(child_config, "alpha.git", "1")

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

command git config --file "$CHILD_CONFIG" remote.origin.url \
  https://example.invalid/bravo.git || return 70
command git config --file "$CHILD_CONFIG" oh-my-zsh.hide-info 0 || return 71
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

direct_remote=$(command git config --get remote.origin.url) || return 72
direct_hide=$(command git config --get oh-my-zsh.hide-info) || return 73
builtin print -r -- \
  "ROOTS_EQUAL=$([[ $first_root == $second_root ]] && print yes || print no)"
builtin print -r -- \
  "CONTEXTS_EQUAL=$([[ $first_context == $second_context ]] && print yes || print no)"
builtin print -r -- \
  "REMOTE_KEYS_EQUAL=$([[ ${first_remote_branch%%|*} == ${second_remote_branch%%|*} ]] && print yes || print no)"
builtin print -r -- "HIDE_INFO=${first_hide_info}->${second_hide_info}"
builtin print -r -- "DIRECT=${direct_remote}|${direct_hide}"
""",
                cache_home=root / "cache",
                cwd=child,
                env={
                    "CHILD_CONFIG": str(child_config),
                    "GIT_CONFIG": "custom.config",
                    "GIT_CONFIG_NOSYSTEM": "1",
                    "HOME": str(root / "home"),
                    "XDG_CONFIG_HOME": str(root / "xdg"),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "ROOTS_EQUAL=yes\n"
            "CONTEXTS_EQUAL=no\n"
            "REMOTE_KEYS_EQUAL=no\n"
            "HIDE_INFO=1->0\n"
            "DIRECT=https://example.invalid/bravo.git|0\n",
            result.stdout,
        )

    def test_relative_global_config_tracks_the_git_command_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "repo"
            child = repo / "child"
            first_config = root / "alpha.config"
            second_config = root / "beta.config"
            config_link = repo / "global.config"
            configure_repository(repo)
            child.mkdir()
            write_global_config(first_config, "alpha.git", "1")
            write_global_config(second_config, "beta.git", "0")
            config_link.symlink_to(first_config)

            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_ai_candy_get_cached_git_root
git_root="$REPLY"
_ai_candy_git_context_cache_key "$git_root"
first_context="$REPLY"
_ai_candy_load_git_display_options "$git_root"
first_hide_info="$_AI_CANDY_GIT_HIDE_INFO"

command rm "$CONFIG_LINK" || return 70
command ln -s "$SECOND_CONFIG" "$CONFIG_LINK" || return 71
_ai_candy_git_context_cache_key "$git_root"
second_context="$REPLY"
_ai_candy_load_git_display_options "$git_root"
second_hide_info="$_AI_CANDY_GIT_HIDE_INFO"
direct_hide=$(command git -C "$git_root" config --get oh-my-zsh.hide-info) || \
  return 72
builtin print -r -- "ROOT=$git_root"
builtin print -r -- \
  "CONTEXTS_EQUAL=$([[ $first_context == $second_context ]] && print yes || print no)"
builtin print -r -- "HIDE_INFO=${first_hide_info}->${second_hide_info}"
builtin print -r -- "DIRECT=$direct_hide"
""",
                cache_home=root / "cache",
                cwd=child,
                env={
                    "CONFIG_LINK": str(config_link),
                    "GIT_CONFIG_GLOBAL": "global.config",
                    "SECOND_CONFIG": str(second_config),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            f"ROOT={repo}\nCONTEXTS_EQUAL=no\nHIDE_INFO=1->0\nDIRECT=0\n",
            result.stdout,
        )

    def test_home_and_xdg_config_roots_partition_derived_state(self) -> None:
        for config_kind in ("home", "xdg"):
            with (
                self.subTest(config_kind=config_kind),
                tempfile.TemporaryDirectory() as tmp,
            ):
                root = Path(tmp)
                repo = root / "repo"
                stable_home = root / "stable-home"
                first_root = root / "alpha"
                second_root = root / "beta"
                stable_home.mkdir()
                configure_repository(repo)
                if config_kind == "home":
                    first_config = first_root / ".gitconfig"
                    second_config = second_root / ".gitconfig"
                    env = {
                        "HOME": str(first_root),
                        "SECOND_CONFIG_ROOT": str(second_root),
                    }
                else:
                    first_config = first_root / "git" / "config"
                    second_config = second_root / "git" / "config"
                    env = {
                        "HOME": str(stable_home),
                        "XDG_CONFIG_HOME": str(first_root),
                        "SECOND_CONFIG_ROOT": str(second_root),
                    }
                write_global_config(first_config, "alpha.git", "1")
                write_global_config(second_config, "beta.git", "0")
                self.assert_config_switch(repo, root / "cache", config_kind, env)


if __name__ == "__main__":
    unittest.main()
