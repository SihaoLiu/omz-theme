#!/usr/bin/env python3
import shutil
import os
import subprocess
import time
import tempfile
import unittest
from pathlib import Path

from tests.theme_test_support import run_zsh
from tests.theme_test_support import ROOT, THEME


class CacheRuntimeTest(unittest.TestCase):
    def test_cache_write_rejects_an_empty_path_without_a_cwd_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_ai_candy_cache_write "" value
write_status=$?
artifact=absent
[[ -e .lock.d.flock || -L .lock.d.flock ]] && artifact=present
print -r -- "STATUS=${write_status} ARTIFACT=${artifact}"
""",
                cache_home=root / "cache",
                cwd=root,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=1 ARTIFACT=absent\n", result.stdout)

    def test_file_cache_round_trip_preserves_ksh_arrays(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
setopt ksharrays
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=0
_AI_CANDY_CACHE_BACKEND=none
_ai_candy_cache_persist_write git_root key value "$EPOCHSECONDS"
write_status=$?
_ai_candy_cache_persist_read git_root key
read_status=$?
if [[ -o ksharrays ]]; then
  option_state=on
else
  option_state=off
fi
builtin print -r -- \
  "KSH=${option_state} WRITE=${write_status} READ=${read_status} VALUE=${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertRegex(
            result.stdout,
            r"^KSH=on WRITE=0 READ=0 VALUE=value\|[0-9]+\n$",
        )

    def test_cached_memory_only_state_adopts_a_backend_created_elsewhere(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=none
_AI_CANDY_CACHE_BACKEND_RETRY_AFTER=$(( EPOCHREALTIME + 60 ))
(
  _AI_CANDY_HAS_SQLITE3=0
  _AI_CANDY_CACHE_BACKEND_STATE=0
  _AI_CANDY_CACHE_BACKEND=none
  _ai_candy_cache_persist_write git_root key shared "$EPOCHSECONDS"
) || return 70
_ai_candy_cache_persist_read git_root key || return 71
print -r -- "BACKEND=${_AI_CANDY_CACHE_BACKEND} VALUE=${REPLY}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("BACKEND=file VALUE=shared|", result.stdout)

    def test_live_file_backend_revalidates_an_owner_changed_to_sqlite(self) -> None:
        if shutil.which("sqlite3") is None:
            self.skipTest("sqlite3 is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=0
_AI_CANDY_CACHE_BACKEND=none
_ai_candy_cache_persist_write git_root key file-old "$EPOCHSECONDS" || return 70
[[ "$_AI_CANDY_CACHE_BACKEND" == file ]] || return 71

_ai_candy_cache_remove_path "${_AI_CANDY_CACHE_DIR}/git_root_cache"
_ai_candy_cache_remove_path "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE"
command sqlite3 "$_AI_CANDY_CACHE_DB_FILE" \
  "CREATE TABLE cache (key TEXT PRIMARY KEY, value TEXT NOT NULL, timestamp INTEGER NOT NULL); INSERT INTO cache VALUES ('git_root:key', 'sqlite-new', ${EPOCHSECONDS});" || return 72
_ai_candy_cache_atomic_write_unlocked "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" sqlite || return 73

_ai_candy_cache_persist_write git_root key file-new "$EPOCHSECONDS"
live_status=$?
live_backend="$_AI_CANDY_CACHE_BACKEND"
file_state=$([[ -e "${_AI_CANDY_CACHE_DIR}/git_root_cache" ]] && print present || print absent)

_AI_CANDY_HAS_SQLITE3=1
_AI_CANDY_CACHE_BACKEND_STATE=0
_AI_CANDY_CACHE_BACKEND=none
_ai_candy_cache_persist_read git_root key || return 74
builtin print -r -- \
  "STATUS=${live_status} LIVE=${live_backend} FILE=${file_state} VALUE=${REPLY}"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("LIVE=none", result.stdout)
        self.assertIn("FILE=absent", result.stdout)
        self.assertIn("VALUE=sqlite-new|", result.stdout)
        status = int(result.stdout.split("STATUS=", 1)[1].split()[0])
        self.assertNotEqual(0, status)

    def test_sqlite_owner_does_not_fallback_to_file_for_a_write(self) -> None:
        if shutil.which("sqlite3") is None:
            self.skipTest("sqlite3 is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
now=$EPOCHSECONDS
_ai_candy_cache_persist_write git_root key old "$now" || return 70
initial_backend="$_AI_CANDY_CACHE_BACKEND"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=0
_AI_CANDY_CACHE_BACKEND=none
_ai_candy_cache_persist_write git_root key new "$now"
fallback_status=$?
fallback_backend="$_AI_CANDY_CACHE_BACKEND"
_AI_CANDY_HAS_SQLITE3=1
_AI_CANDY_CACHE_BACKEND_STATE=0
_AI_CANDY_CACHE_BACKEND=none
_ai_candy_cache_persist_read git_root key || return 71
builtin print -r -- \
  "INITIAL=${initial_backend} STATUS=${fallback_status} FALLBACK=${fallback_backend} VALUE=${REPLY}"
""",
                cache_home=root / "cache",
            )

            file_cache = root / "cache" / "zsh-prompt" / "git_root_cache"

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("INITIAL=sqlite", result.stdout)
            self.assertIn("FALLBACK=none", result.stdout)
            self.assertIn("VALUE=old|", result.stdout)
            status = int(result.stdout.split("STATUS=", 1)[1].split()[0])
            self.assertNotEqual(0, status)
            self.assertFalse(file_cache.exists())

    def test_sqlite_owner_does_not_fallback_to_file_for_a_delete(self) -> None:
        if shutil.which("sqlite3") is None:
            self.skipTest("sqlite3 is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_ai_candy_cache_persist_write git_root key old "$EPOCHSECONDS" || return 70
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=0
_AI_CANDY_CACHE_BACKEND=none
_ai_candy_cache_persist_delete_unlocked git_root key
fallback_status=$?
fallback_backend="$_AI_CANDY_CACHE_BACKEND"
_AI_CANDY_HAS_SQLITE3=1
_AI_CANDY_CACHE_BACKEND_STATE=0
_AI_CANDY_CACHE_BACKEND=none
_ai_candy_cache_persist_read git_root key || return 71
builtin print -r -- \
  "STATUS=${fallback_status} FALLBACK=${fallback_backend} VALUE=${REPLY}"
""",
                cache_home=root / "cache",
            )

            file_cache = root / "cache" / "zsh-prompt" / "git_root_cache"

            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("FALLBACK=none", result.stdout)
            self.assertIn("VALUE=old|", result.stdout)
            status = int(result.stdout.split("STATUS=", 1)[1].split()[0])
            self.assertNotEqual(0, status)
            self.assertFalse(file_cache.exists())

    def test_corrupt_sqlite_database_is_recreated_in_place(self) -> None:
        if shutil.which("sqlite3") is None:
            self.skipTest("sqlite3 is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_ai_candy_cache_persist_write git_root key old "$EPOCHSECONDS" || return 70
[[ "$_AI_CANDY_CACHE_BACKEND" == sqlite ]] || return 71
_ai_candy_cache_remove_path "${_AI_CANDY_CACHE_DB_FILE}-journal"
_ai_candy_cache_remove_path "${_AI_CANDY_CACHE_DB_FILE}-shm"
_ai_candy_cache_remove_path "${_AI_CANDY_CACHE_DB_FILE}-wal"
builtin print -r -- 'not a sqlite database' >| "$_AI_CANDY_CACHE_DB_FILE"
_AI_CANDY_CACHE_BACKEND_STATE=0
_AI_CANDY_CACHE_BACKEND=none

if _ai_candy_cache_persist_write git_root key new "$EPOCHSECONDS"; then
  write_state=ok
else
  write_state=failed
fi
if _ai_candy_cache_persist_read git_root key; then
  read_state=ok
  value="$REPLY"
else
  read_state=missing
  value="${REPLY:-empty}"
fi
owner=$(<"$_AI_CANDY_CACHE_BACKEND_OWNER_FILE")
file_cache="${_AI_CANDY_CACHE_DIR}/git_root_cache"
file_state=$([[ -e "$file_cache" ]] && print present || print absent)
builtin print -r -- \
  "WRITE=${write_state} READ=${read_state} VALUE=${value} BACKEND=${_AI_CANDY_CACHE_BACKEND} OWNER=${owner} FILE=${file_state}"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertRegex(
            result.stdout,
            r"^WRITE=ok READ=ok VALUE=new\|[0-9]+ "
            r"BACKEND=sqlite OWNER=sqlite FILE=absent\n$",
        )

    def test_runtime_sqlite_corruption_is_recreated_in_place(self) -> None:
        sqlite3 = shutil.which("sqlite3")
        if sqlite3 is None:
            self.skipTest("sqlite3 is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            seed = run_zsh(
                r"""
source "$1"
_ai_candy_cache_persist_write git_root key old "$EPOCHSECONDS" || return 70
command sqlite3 "$_AI_CANDY_CACHE_DB_FILE" \
  'PRAGMA wal_checkpoint(TRUNCATE);' >/dev/null || return 71
builtin print -r -- "$_AI_CANDY_CACHE_DB_FILE"
""",
                cache_home=cache_home,
            )
            self.assertEqual(0, seed.returncode, seed.stderr)
            database = Path(seed.stdout.strip())
            page_size = int(
                subprocess.check_output(
                    [sqlite3, str(database), "PRAGMA page_size;"], text=True
                ).strip()
            )
            root_page = int(
                subprocess.check_output(
                    [
                        sqlite3,
                        str(database),
                        "SELECT rootpage FROM sqlite_master WHERE name='cache';",
                    ],
                    text=True,
                ).strip()
            )
            self.assertGreater(root_page, 1)
            self.assertGreaterEqual(database.stat().st_size, page_size * root_page)
            invalid_page = b"invalid-sqlite-page"
            with database.open("r+b") as stream:
                stream.seek(page_size * (root_page - 1))
                stream.write(
                    (invalid_page * (page_size // len(invalid_page) + 1))[:page_size]
                )
            for suffix in ("-journal", "-shm", "-wal"):
                sidecar = Path(f"{database}{suffix}")
                if sidecar.exists() or sidecar.is_symlink():
                    sidecar.unlink()

            result = run_zsh(
                r"""
source "$1"
_ai_candy_cache_persist_read git_root key || true
integrity=$(command sqlite3 "$_AI_CANDY_CACHE_DB_FILE" \
  'PRAGMA quick_check;' 2>/dev/null)
if _ai_candy_cache_persist_write git_root key recovered "$EPOCHSECONDS"; then
  write_state=ok
else
  write_state=failed
fi
if _ai_candy_cache_persist_read git_root key; then
  read_state=ok
  value="$REPLY"
else
  read_state=missing
  value="${REPLY:-empty}"
fi
builtin print -r -- \
  "RECOVERY=${integrity} WRITE=${write_state} READ=${read_state} VALUE=${value} BACKEND=${_AI_CANDY_CACHE_BACKEND}"
""",
                cache_home=cache_home,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertRegex(
            result.stdout,
            r"^RECOVERY=ok WRITE=ok READ=ok VALUE=recovered\|[0-9]+ "
            r"BACKEND=sqlite\n$",
        )

    def test_sqlite_recovery_keeps_database_if_sidecar_removal_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
builtin print -r -- database >| "$_AI_CANDY_CACHE_DB_FILE"
builtin print -r -- wal >| "${_AI_CANDY_CACHE_DB_FILE}-wal"
typeset -ga removals=()
function _ai_candy_cache_remove_path() {
  removals+=("${1:t}")
  [[ "$1" != "${_AI_CANDY_CACHE_DB_FILE}-wal" ]] || return 1
  /bin/rm -f "$1"
}
if _ai_candy_cache_remove_sqlite_artifacts_unlocked; then
  state=ok
else
  state=failed
fi
db_state=$([[ -f "$_AI_CANDY_CACHE_DB_FILE" ]] && print present || print absent)
builtin print -r -- \
  "STATE=${state} DB=${db_state} REMOVALS=${(j:,:)removals}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "STATE=failed DB=present REMOVALS=prompt_cache.db-wal\n",
            result.stdout,
        )

    def test_transient_sqlite_failure_preserves_the_database(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            sqlite = bin_dir / "sqlite3"
            sqlite.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' 'Error: database is locked' >&2\n"
                "exit 1\n",
                encoding="ascii",
            )
            sqlite.chmod(0o755)
            result = run_zsh(
                r"""
source "$1"
_ai_candy_cache_atomic_write_unlocked \
  "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" sqlite || return 70
builtin print -r -- sentinel >| "$_AI_CANDY_CACHE_DB_FILE"
_AI_CANDY_CACHE_BACKEND_STATE=0
_AI_CANDY_CACHE_BACKEND=none
if _ai_candy_cache_backend_init; then
  state=ready
else
  state=failed
fi
builtin print -r -- \
  "STATE=${state} DB=$(<"$_AI_CANDY_CACHE_DB_FILE") OWNER=$(<"$_AI_CANDY_CACHE_BACKEND_OWNER_FILE") BACKEND=${_AI_CANDY_CACHE_BACKEND}"
""",
                cache_home=root / "cache",
                env={"PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}"},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            "STATE=failed DB=sentinel OWNER=sqlite BACKEND=none\n",
            result.stdout,
        )

    def test_failed_persistent_read_clears_reply(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_ai_candy_cache_atomic_write_unlocked \
  "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" sqlite || return 70
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_BACKEND_STATE=0
_AI_CANDY_CACHE_BACKEND=none
REPLY=stale
if _ai_candy_cache_persist_read git_root key; then
  state=hit
else
  state=missing
fi
builtin print -r -- "STATE=${state} REPLY=${REPLY:-empty}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATE=missing REPLY=empty\n", result.stdout)

    def test_contended_delete_cannot_restore_stale_persistent_data(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
_ai_candy_cache_persist_write git_hierarchy key old "$EPOCHSECONDS" || return 70
operation_lock="${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d"
command mkdir -m 700 "$operation_lock" || return 71
print -r -- holder >| "${operation_lock}/owner.existing"
_ai_candy_cache_delete_key git_hierarchy key
command rm -f "${operation_lock}/owner.existing"
command rmdir "$operation_lock"
if _ai_candy_cache_get git_hierarchy key; then
  print -r -- "VALUE=${REPLY}"
else
  print -r -- "VALUE=missing"
fi
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("VALUE=missing\n", result.stdout)

    def test_cold_prompt_rejects_an_oversized_line_cache(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_FILE_MAX_BYTES=1024
_ai_candy_cache_atomic_write_unlocked "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" file || return 70
_ai_candy_hex_encode 'git_root:key'
hex_key="$REPLY"
_ai_candy_hex_encode cached
hex_value="$REPLY"
cache_file="${_AI_CANDY_CACHE_DIR}/git_root_cache"
builtin print -r -- "${hex_key}|${hex_value}|${EPOCHSECONDS}" >| "$cache_file"
builtin print -r -- "${(l:4096::X:)}" >> "$cache_file"
start=$EPOCHREALTIME
if _ai_candy_cache_get git_root key; then
  state="hit:${REPLY}"
else
  state=missing
fi
elapsed=$(( EPOCHREALTIME - start ))
builtin print -r -- "STATE=${state} ELAPSED=${elapsed}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(
            field.split("=", maxsplit=1) for field in result.stdout.strip().split()
        )
        self.assertEqual("missing", fields["STATE"])
        self.assertLess(float(fields["ELAPSED"]), 0.2)

    def test_persistent_cache_rejects_values_above_the_configured_limit(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_VALUE_MAX_BYTES=1024
_ai_candy_cache_atomic_write_unlocked "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" file || return 70
_ai_candy_hex_encode 'git_root:key'
hex_key="$REPLY"
payload="${(l:1025::x:)}"
_ai_candy_hex_encode "$payload"
hex_value="$REPLY"
builtin print -r -- "${hex_key}|${hex_value}|${EPOCHSECONDS}" >| \
  "${_AI_CANDY_CACHE_DIR}/git_root_cache"
if _ai_candy_cache_persist_read git_root key; then
  read_state=hit
else
  read_state=missing
fi
if _ai_candy_cache_persist_write git_root other "$payload" "$EPOCHSECONDS"; then
  write_state=accepted
else
  write_state=rejected
fi
builtin print -r -- "READ=${read_state} WRITE=${write_state}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("READ=missing WRITE=rejected\n", result.stdout)

    def test_file_backend_supports_the_largest_allowed_value(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_ai_candy_cache_atomic_write_unlocked \
  "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" file || return 70
payload="${(l:16384::x:)}"
start="$EPOCHREALTIME"
if _ai_candy_cache_persist_write \
     git_root largest "$payload" "$EPOCHSECONDS"; then
  write_state=accepted
else
  write_state=rejected
fi
if _ai_candy_cache_persist_read git_root largest; then
  stored_value="${REPLY%|*}"
  stored_size="${#stored_value}"
else
  stored_size=missing
fi
oversized="${payload}x"
if _ai_candy_cache_persist_write \
     git_root oversized "$oversized" "$EPOCHSECONDS"; then
  oversized_state=accepted
else
  oversized_state=rejected
fi
elapsed=$(( EPOCHREALTIME - start ))
builtin print -r -- \
  "WRITE=${write_state} READ=${stored_size} OVERSIZED=${oversized_state} ELAPSED=${elapsed}"
""",
                cache_home=Path(tmp) / "cache",
                timeout=5,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(
            field.split("=", maxsplit=1) for field in result.stdout.strip().split()
        )
        self.assertEqual("accepted", fields["WRITE"])
        self.assertEqual("16384", fields["READ"])
        self.assertEqual("rejected", fields["OVERSIZED"])
        self.assertLess(float(fields["ELAPSED"]), 1.0)

    def test_hex_codec_is_fast_for_the_largest_supported_value(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
payload="${(l:16384::x:)}"
start="$EPOCHREALTIME"
_ai_candy_hex_encode "$payload" || return 70
encoded="$REPLY"
_ai_candy_hex_decode "$encoded" || return 71
elapsed=$(( EPOCHREALTIME - start ))
[[ "$REPLY" == "$payload" ]] || return 72
builtin print -r -- "ELAPSED=${elapsed}"
""",
                cache_home=Path(tmp) / "cache",
                timeout=5,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        elapsed = float(result.stdout.strip().partition("=")[2])
        self.assertLess(elapsed, 0.75)

    def test_cold_line_cache_read_uses_the_prompt_io_deadline(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_ai_candy_cache_atomic_write_unlocked "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" file || return 70
_ai_candy_hex_encode 'git_root:key'
hex_key="$REPLY"
_ai_candy_hex_encode cached
hex_value="$REPLY"
builtin print -r -- "${hex_key}|${hex_value}|${EPOCHSECONDS}" >| \
  "${_AI_CANDY_CACHE_DIR}/git_root_cache"
function _ai_candy_run_with_timeout() {
  builtin print -r -- "$1" >| "$DEADLINE_FILE"
  return 124
}
if _ai_candy_cache_get git_root key; then
  state=hit
else
  state=missing
fi
builtin print -r -- "STATE=${state} DEADLINE=$(<"$DEADLINE_FILE")"
""",
                cache_home=root / "cache",
                env={"DEADLINE_FILE": str(root / "deadline")},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATE=missing DEADLINE=0.05\n", result.stdout)

    def test_cold_prompt_fails_closed_on_an_oversized_operation_journal(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_FILE_MAX_BYTES=1024
_ai_candy_cache_atomic_write_unlocked "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" file || return 70
_ai_candy_hex_encode 'git_root:key'
hex_key="$REPLY"
_ai_candy_hex_encode cached
hex_value="$REPLY"
builtin print -r -- "${hex_key}|${hex_value}|${EPOCHSECONDS}" >| \
  "${_AI_CANDY_CACHE_DIR}/git_root_cache"
: >| "$_AI_CANDY_CACHE_OPERATION_FILE"
for index in {1..40}; do
  _ai_candy_hex_encode "git_root:other-${index}"
  builtin print -r -- \
    "${REPLY}|v3:30:${index}|set|${EPOCHSECONDS}" \
    >> "$_AI_CANDY_CACHE_OPERATION_FILE"
done
if _ai_candy_cache_get git_root key; then
  builtin print -r -- "STATE=hit:${REPLY}"
else
  builtin print -r -- "STATE=missing"
fi
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATE=missing\n", result.stdout)

    def test_cold_prompt_fails_closed_on_a_malformed_operation_journal(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_ai_candy_cache_atomic_write_unlocked "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" file || return 70
_ai_candy_hex_encode 'git_root:key'
hex_key="$REPLY"
_ai_candy_hex_encode cached
hex_value="$REPLY"
builtin print -r -- "${hex_key}|${hex_value}|${EPOCHSECONDS}" >| \
  "${_AI_CANDY_CACHE_DIR}/git_root_cache"
builtin print -r -- 'not-a-valid-operation-record' >| "$_AI_CANDY_CACHE_OPERATION_FILE"
if _ai_candy_cache_get git_root key; then
  builtin print -r -- "STATE=hit:${REPLY}"
else
  builtin print -r -- "STATE=missing"
fi
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATE=missing\n", result.stdout)

    def test_file_backend_recovers_from_an_oversized_regular_cache(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_AI_CANDY_CACHE_FILE_MAX_BYTES=1024
_ai_candy_cache_atomic_write_unlocked "$_AI_CANDY_CACHE_BACKEND_OWNER_FILE" file || return 70
cache_file="${_AI_CANDY_CACHE_DIR}/git_root_cache"
builtin print -r -- "${(l:4096::X:)}" >| "$cache_file"
_AI_CANDY_CACHE_BACKEND_STATE=0
_AI_CANDY_CACHE_BACKEND=none
_ai_candy_cache_persist_write git_root key recovered "$EPOCHSECONDS" || return 71
_ai_candy_cache_persist_read git_root key || return 72
builtin zstat -A metadata +size -- "$cache_file" || return 73
builtin print -r -- "VALUE=${REPLY} BYTES=${metadata[1]}"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        fields = dict(
            field.split("=", maxsplit=1) for field in result.stdout.strip().split()
        )
        self.assertTrue(fields["VALUE"].startswith("recovered|"))
        self.assertLessEqual(int(fields["BYTES"]), 1024)

    def test_cold_prompt_never_waits_for_a_contended_commit_lock(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            work = root / "work"
            work.mkdir()
            ready_file = root / "ready"
            release_file = root / "release"
            environment = {
                **os.environ,
                "XDG_CACHE_HOME": str(cache_home),
                "READY_FILE": str(ready_file),
                "RELEASE_FILE": str(release_file),
            }
            holder = subprocess.Popen(
                [
                    "zsh",
                    "-fc",
                    r"""
source "$1"
(( _AI_CANDY_HAS_ZSH_SYSTEM )) || return 77
_ai_candy_cache_lock_acquire "$_AI_CANDY_CACHE_COMMIT_LOCK" 300 0 || return 78
print -r -- ready >| "$READY_FILE"
while [[ ! -f "$RELEASE_FILE" ]]; do
  zselect -t 1
done
_ai_candy_cache_lock_release "$_AI_CANDY_CACHE_COMMIT_LOCK"
""",
                    "zsh",
                    str(THEME),
                ],
                cwd=work,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=environment,
            )
            try:
                deadline = time.monotonic() + 5
                while not ready_file.exists() and holder.poll() is None:
                    self.assertLess(time.monotonic(), deadline)
                    time.sleep(0.01)
                if holder.poll() is not None:
                    holder_stdout, holder_stderr = holder.communicate()
                    self.fail(
                        f"lock holder exited early: {holder.returncode}\n"
                        f"stdout: {holder_stdout}\nstderr: {holder_stderr}"
                    )
                result = run_zsh(
                    r"""
source "$1"
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=1
_AI_CANDY_USE_OMZ_ASYNC=0
_AI_CANDY_SYSINFO_SESSION_READY=0
command rm -f "$_AI_CANDY_SYSINFO_CACHE_FILE"
start=$EPOCHREALTIME
_ai_candy_precmd_compute_prompt
elapsed_ms=$(( (EPOCHREALTIME - start) * 1000 ))
builtin printf 'ELAPSED_MS=%.3f\n' "$elapsed_ms"
""",
                    cache_home=cache_home,
                    cwd=work,
                    timeout=5,
                )
            finally:
                release_file.touch()
                if holder.poll() is None:
                    holder.communicate(timeout=8)

        self.assertEqual(0, result.returncode, result.stderr)
        elapsed_line = next(
            line
            for line in result.stdout.splitlines()
            if line.startswith("ELAPSED_MS=")
        )
        self.assertLess(float(elapsed_line.partition("=")[2]), 200.0, result.stdout)

    def test_descriptor_lock_rejects_reentrant_acquisition(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
(( _AI_CANDY_HAS_ZSH_SYSTEM )) || return 77
lock_dir="${_AI_CANDY_CACHE_DIR}/reentrant.lock.d"
_ai_candy_cache_lock_acquire "$lock_dir" 300 0 || return 70
_ai_candy_cache_lock_acquire "$lock_dir" 300 0
second_status=$?
_ai_candy_cache_lock_release "$lock_dir"
builtin print -r -- "SECOND_STATUS=${second_status}"
""",
                cache_home=root / "cache",
            )

        if result.returncode == 77:
            self.skipTest("zsh/system is unavailable")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("SECOND_STATUS=1\n", result.stdout)

    def test_relative_xdg_cache_home_falls_back_to_a_stable_absolute_path(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            home = root / "home"
            start = root / "start"
            destination = root / "destination"
            home.mkdir()
            start.mkdir()
            destination.mkdir()
            result = run_zsh(
                r"""
source "$1"
initial="$_AI_CANDY_CACHE_DIR"
cd "$DESTINATION"
_ai_candy_cache_write "$_AI_CANDY_EMOJI_MODE_FILE" 1
print -r -- "INITIAL=${initial}"
print -r -- "AFTER=${_AI_CANDY_CACHE_DIR}"
""",
                cache_home=root / "unused",
                cwd=start,
                env={
                    "HOME": str(home),
                    "XDG_CACHE_HOME": "relative-cache",
                    "DESTINATION": str(destination),
                },
            )

            expected = home / ".cache" / "zsh-prompt"
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn(f"INITIAL={expected}", result.stdout)
            self.assertIn(f"AFTER={expected}", result.stdout)
            self.assertFalse((start / "relative-cache").exists())
            self.assertFalse((destination / "relative-cache").exists())

    def test_cold_git_prompt_never_waits_for_a_contended_descriptor_lock(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            repo = root / "repo"
            repo.mkdir()
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)
            ready_file = root / "ready"
            release_file = root / "release"
            environment = {
                **os.environ,
                "XDG_CACHE_HOME": str(cache_home),
                "READY_FILE": str(ready_file),
                "RELEASE_FILE": str(release_file),
            }
            holder = subprocess.Popen(
                [
                    "zsh",
                    "-fc",
                    r"""
source "$1"
(( _AI_CANDY_HAS_ZSH_SYSTEM )) || return 77
_ai_candy_cache_lock_acquire "${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d" 300 0 || return 78
print -r -- ready >| "$READY_FILE"
for attempt in {1..500}; do
  [[ -f "$RELEASE_FILE" ]] && break
  zselect -t 1
done
_ai_candy_cache_lock_release "${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d"
""",
                    "zsh",
                    str(THEME),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=environment,
            )
            try:
                deadline = time.monotonic() + 5
                while not ready_file.exists() and time.monotonic() < deadline:
                    if holder.poll() is not None:
                        break
                    time.sleep(0.01)
                self.assertTrue(ready_file.exists(), "lock holder did not start")
                result = run_zsh(
                    r"""
source "$1"
(( _AI_CANDY_HAS_ZSH_SYSTEM )) || return 77
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
functions[_lock_acquire_without_record]="${functions[_ai_candy_cache_lock_acquire]}"
typeset -gi max_operation_wait_ticks=0
function _ai_candy_cache_lock_acquire() {
  if [[ "$1" == "${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d" ]] && \
     (( ${3:-0} > max_operation_wait_ticks )); then
    max_operation_wait_ticks="${3:-0}"
  fi
  _lock_acquire_without_record "$@"
}
_ai_candy_get_cached_git_root
git_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$git_root"
_ai_candy_get_git_hierarchy
print -r -- "ROOT=${git_root} HIERARCHY=${REPLY}"
builtin print -r -- "MAX_WAIT_TICKS=${max_operation_wait_ticks}"
""",
                    cache_home=cache_home,
                    cwd=repo,
                    timeout=4,
                )
            finally:
                release_file.touch()
                if holder.poll() is None:
                    holder.communicate(timeout=8)

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn(f"ROOT={repo} HIERARCHY={repo}", result.stdout)
        wait_line = next(
            line
            for line in result.stdout.splitlines()
            if line.startswith("MAX_WAIT_TICKS=")
        )
        self.assertEqual("MAX_WAIT_TICKS=2", wait_line, result.stdout)

    def test_cold_git_prompt_never_waits_for_a_contended_fallback_lock(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            repo = root / "repo"
            repo.mkdir()
            subprocess.run(["git", "-C", str(repo), "init", "-q"], check=True)
            lock_dir = cache_home / "zsh-prompt" / "persist_operations.lock.d"
            lock_dir.mkdir(parents=True)
            (lock_dir / "owner.existing").write_text("holder\n", encoding="ascii")
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
functions[_lock_acquire_without_record]="${functions[_ai_candy_cache_lock_acquire]}"
typeset -gi max_operation_wait_ticks=0
function _ai_candy_cache_lock_acquire() {
  if [[ "$1" == "${_AI_CANDY_CACHE_OPERATION_FILE}.lock.d" ]] && \
     (( ${3:-0} > max_operation_wait_ticks )); then
    max_operation_wait_ticks="${3:-0}"
  fi
  _lock_acquire_without_record "$@"
}
_ai_candy_get_cached_git_root
git_root="$REPLY"
_AI_CANDY_PP_CACHED_GIT_ROOT="$git_root"
_ai_candy_get_git_hierarchy
print -r -- "ROOT=${git_root} HIERARCHY=${REPLY}"
builtin print -r -- "MAX_WAIT_TICKS=${max_operation_wait_ticks}"
""",
                cache_home=cache_home,
                cwd=repo,
                timeout=4,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn(f"ROOT={repo} HIERARCHY={repo}", result.stdout)
        wait_line = next(
            line
            for line in result.stdout.splitlines()
            if line.startswith("MAX_WAIT_TICKS=")
        )
        self.assertEqual("MAX_WAIT_TICKS=2", wait_line, result.stdout)

    def test_toggle_remains_usable_when_cache_persistence_is_unavailable(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            cache_home.mkdir()
            target = root / "untrusted-target"
            target.mkdir()
            (cache_home / "zsh-prompt").symlink_to(target, target_is_directory=True)
            result = run_zsh(
                r"""
setopt errexit
source "$1"
before=$_AI_CANDY_PROMPT_EMOJI_MODE
_ai_candy_prompt_toggle_emoji >/dev/null
print -r -- "BEFORE=${before} AFTER=${_AI_CANDY_PROMPT_EMOJI_MODE} CACHE=${_AI_CANDY_CACHE_READY}"
""",
                cache_home=cache_home,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("CACHE=0", result.stdout)
        self.assertRegex(result.stdout, r"BEFORE=([01]) AFTER=(?!\1)[01]")

    def test_commit_lock_is_not_stolen_within_its_supported_work_window(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            lock_dir = cache_home / "zsh-prompt" / "persist_commit.lock.d"
            lock_dir.mkdir(parents=True)
            owner_file = lock_dir / "owner.existing"
            owner_file.write_text("holder\n", encoding="ascii")
            held_time = time.time() - 8
            os.utime(lock_dir, (held_time, held_time))
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
function _ai_candy_sleep_ticks() { return 0; }
_ai_candy_cache_persist_write git_root key value "$EPOCHSECONDS"
lock_status=$?
print -r -- "STATUS=${lock_status} OWNER=$([[ -f "$OWNER_FILE" ]] && print present || print missing)"
""",
                cache_home=cache_home,
                env={"OWNER_FILE": str(owner_file)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=1 OWNER=present\n", result.stdout)

    def test_background_lock_covers_network_and_persistence_work(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            lock_dir = cache_home / "zsh-prompt" / "worker.lock.d"
            lock_dir.mkdir(parents=True)
            owner_file = lock_dir / "owner.existing"
            owner_file.write_text("holder\n", encoding="ascii")
            held_time = time.time() - 8
            os.utime(lock_dir, (held_time, held_time))
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_ZSH_SYSTEM=0
_AI_CANDY_NETWORK_TIMEOUT=3
_ai_candy_acquire_background_lock "${_AI_CANDY_CACHE_DIR}/worker.lock"
lock_status=$?
print -r -- "STATUS=${lock_status} OWNER=$([[ -f "$OWNER_FILE" ]] && print present || print missing)"
""",
                cache_home=cache_home,
                env={"OWNER_FILE": str(owner_file)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=1 OWNER=present\n", result.stdout)

    def test_refresh_cancels_an_inflight_persistent_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
functions[_persist_without_pause]="${functions[_ai_candy_cache_persist_write_unlocked]}"
function _ai_candy_cache_persist_write_unlocked() {
  print -r -- entered >| "$ENTERED_FILE"
  for attempt in {1..500}; do
    [[ -f "$RELEASE_FILE" ]] && break
    zselect -t 1
  done
  _persist_without_pause "$@"
}
_ai_candy_cache_set git_root key stale "$EPOCHSECONDS"
for attempt in {1..500}; do
  [[ -f "$ENTERED_FILE" ]] && break
  zselect -t 1
done
[[ -f "$ENTERED_FILE" ]] || return 70
(zselect -t 30; print -r -- release >| "$RELEASE_FILE") &!
start=$EPOCHREALTIME
_ai_candy_prompt_refresh_all_caches >/dev/null
elapsed=$(( EPOCHREALTIME - start ))
zselect -t 50
_AI_CANDY_CACHE_BACKEND_STATE=1
_AI_CANDY_CACHE_BACKEND=file
if _ai_candy_cache_persist_read git_root key; then
  print -r -- "VALUE=${REPLY}"
else
  print -r -- "VALUE=missing"
fi
print -r -- "ELAPSED=${elapsed}"
""",
                cache_home=root / "cache",
                env={
                    "ENTERED_FILE": str(root / "entered"),
                    "RELEASE_FILE": str(root / "release"),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("VALUE=missing", result.stdout)
        elapsed_line = next(
            line for line in result.stdout.splitlines() if line.startswith("ELAPSED=")
        )
        self.assertLess(float(elapsed_line.partition("=")[2]), 0.5)

    def test_refresh_cancels_a_reserved_write_before_commit(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
functions[_commit_without_pause]="${functions[_ai_candy_cache_commit_operation]}"
function _ai_candy_cache_commit_operation() {
  print -r -- entered >| "$ENTERED_FILE"
  while [[ ! -f "$RELEASE_FILE" ]]; do
    zselect -t 1
  done
  _commit_without_pause "$@"
}
_ai_candy_cache_set git_root key stale "$EPOCHSECONDS"
for attempt in {1..500}; do
  [[ -f "$ENTERED_FILE" ]] && break
  zselect -t 1
done
[[ -f "$ENTERED_FILE" ]] || return 70
_ai_candy_prompt_refresh_all_caches >/dev/null
print -r -- release >| "$RELEASE_FILE"
zselect -t 50
if _ai_candy_cache_persist_read git_root key; then
  print -r -- "VALUE=${REPLY}"
else
  print -r -- "VALUE=missing"
fi
""",
                cache_home=root / "cache",
                env={
                    "ENTERED_FILE": str(root / "entered"),
                    "RELEASE_FILE": str(root / "release"),
                },
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("VALUE=missing\n", result.stdout)

    def test_refresh_rejects_a_scheduled_write_from_another_shell(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            entered_file = root / "entered"
            release_file = root / "release"
            environment = {
                **os.environ,
                "XDG_CACHE_HOME": str(cache_home),
                "ENTERED_FILE": str(entered_file),
                "RELEASE_FILE": str(release_file),
            }
            writer = subprocess.Popen(
                [
                    "zsh",
                    "-fc",
                    r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
functions[_commit_without_pause]="${functions[_ai_candy_cache_commit_operation]}"
function _ai_candy_cache_commit_operation() {
  print -r -- entered >| "$ENTERED_FILE"
  while [[ ! -f "$RELEASE_FILE" ]]; do
    zselect -t 1
  done
  _commit_without_pause "$@"
}
_ai_candy_cache_set git_root key stale "$EPOCHSECONDS"
for attempt in {1..500}; do
  [[ -f "$RELEASE_FILE" ]] && break
  zselect -t 1
done
[[ -f "$RELEASE_FILE" ]] || return 70
zselect -t 50 || true
""",
                    "zsh",
                    str(THEME),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=environment,
            )
            try:
                deadline = time.monotonic() + 5
                while not entered_file.exists() and time.monotonic() < deadline:
                    if writer.poll() is not None:
                        break
                    time.sleep(0.01)
                self.assertTrue(
                    entered_file.exists(), "writer did not reach the journal"
                )

                refresh = run_zsh(
                    r"""
source "$1"
_ai_candy_prompt_refresh_all_caches >/dev/null
""",
                    cache_home=cache_home,
                )
                self.assertEqual(0, refresh.returncode, refresh.stderr)
                release_file.write_text("release\n", encoding="ascii")
                writer_stdout, writer_stderr = writer.communicate(timeout=8)
            finally:
                if writer.poll() is None:
                    writer.kill()
                    writer.communicate()

            readback = run_zsh(
                r"""
source "$1"
if _ai_candy_cache_persist_read git_root key; then
  print -r -- "VALUE=${REPLY}"
else
  print -r -- "VALUE=missing"
fi
""",
                cache_home=cache_home,
            )

        self.assertEqual(0, writer.returncode, writer_stderr)
        self.assertEqual("", writer_stdout)
        self.assertEqual(0, readback.returncode, readback.stderr)
        self.assertEqual("VALUE=missing\n", readback.stdout)

    def test_refresh_recovers_a_regular_persistence_epoch_file(self) -> None:
        for stale_epoch in ("garbage", "9" * 128, "999999999999"):
            with self.subTest(stale_epoch=stale_epoch[:16]):
                with tempfile.TemporaryDirectory() as tmp:
                    root = Path(tmp)
                    cache_home = root / "cache"
                    cache_dir = cache_home / "zsh-prompt"
                    cache_dir.mkdir(parents=True)
                    (cache_dir / "persistent_epoch").write_text(
                        f"{stale_epoch}\n", encoding="ascii"
                    )
                    result = run_zsh(
                        r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_ai_candy_prompt_refresh_all_caches >/dev/null || return 70
_ai_candy_cache_read_persistence_epoch || return 71
epoch="$REPLY"
_ai_candy_cache_set git_root key new "$EPOCHSECONDS"
for attempt in {1..500}; do
  if _ai_candy_cache_persist_read git_root key; then
    print -r -- "EPOCH=${epoch} VALUE=${REPLY}"
    return 0
  fi
  zselect -t 1
done
return 72
""",
                        cache_home=cache_home,
                    )

                self.assertEqual(0, result.returncode, result.stderr)
                self.assertRegex(result.stdout, r"^EPOCH=v1:[^ ]+ VALUE=new\|")

    def test_refresh_refuses_a_symlinked_persistence_epoch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            cache_dir = cache_home / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            victim = root / "victim"
            victim.write_text("keep\n", encoding="ascii")
            (cache_dir / "persistent_epoch").symlink_to(victim)

            result = run_zsh(
                r"""
source "$1"
_ai_candy_prompt_refresh_all_caches >/dev/null
print -r -- "STATUS=$?"
""",
                cache_home=cache_home,
            )
            victim_content = victim.read_text(encoding="ascii")

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("STATUS=1\n", result.stdout)
        self.assertEqual("keep\n", victim_content)

    def test_refresh_rejects_old_persistent_and_simple_file_writes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            ready_file = root / "ready"
            release_file = root / "release"
            environment = {
                **os.environ,
                "XDG_CACHE_HOME": str(cache_home),
                "READY_FILE": str(ready_file),
                "RELEASE_FILE": str(release_file),
            }
            writer = subprocess.Popen(
                [
                    "zsh",
                    "-fc",
                    r"""
source "$1"
_AI_CANDY_HAS_SQLITE3=0
_ai_candy_cache_read_persistence_epoch || return 70
captured_epoch="$REPLY"
print -r -- ready >| "$READY_FILE"
for attempt in {1..500}; do
  [[ -f "$RELEASE_FILE" ]] && break
  zselect -t 1
done
[[ -f "$RELEASE_FILE" ]] || return 71
_ai_candy_cache_write "$_AI_CANDY_PUBLIC_IP_CACHE_FILE" "203.0.113.42|${EPOCHSECONDS}" \
  "$_AI_CANDY_CACHE_COMMIT_WAIT_TICKS" "$captured_epoch"
file_status=$?
_ai_candy_cache_persist_write gh_pr key '42|pass' "$EPOCHSECONDS" "$captured_epoch"
persistent_status=$?
print -r -- "FILE=${file_status} PERSISTENT=${persistent_status}"
""",
                    "zsh",
                    str(THEME),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=environment,
            )
            try:
                deadline = time.monotonic() + 5
                while not ready_file.exists() and time.monotonic() < deadline:
                    if writer.poll() is not None:
                        break
                    time.sleep(0.01)
                self.assertTrue(ready_file.exists(), "writer did not capture its epoch")
                refresh = run_zsh(
                    r"""
source "$1"
_ai_candy_prompt_refresh_all_caches >/dev/null
""",
                    cache_home=cache_home,
                )
                self.assertEqual(0, refresh.returncode, refresh.stderr)
                release_file.write_text("release\n", encoding="ascii")
                writer_stdout, writer_stderr = writer.communicate(timeout=8)
            finally:
                if writer.poll() is None:
                    writer.kill()
                    writer.communicate()

            readback = run_zsh(
                r"""
source "$1"
ip_state=$([[ -e "$_AI_CANDY_PUBLIC_IP_CACHE_FILE" ]] && print present || print missing)
if _ai_candy_cache_persist_read gh_pr key; then
  pr_state="$REPLY"
else
  pr_state=missing
fi
print -r -- "IP=${ip_state} PR=${pr_state}"
""",
                cache_home=cache_home,
            )

        self.assertEqual(0, writer.returncode, writer_stderr)
        self.assertEqual("FILE=1 PERSISTENT=1\n", writer_stdout)
        self.assertEqual(0, readback.returncode, readback.stderr)
        self.assertEqual("IP=missing PR=missing\n", readback.stdout)

    def test_refresh_removes_sqlite_state_when_sqlite_is_temporarily_absent(
        self,
    ) -> None:
        if shutil.which("sqlite3") is None:
            self.skipTest("sqlite3 is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_ai_candy_cache_backend_init
[[ "$_AI_CANDY_CACHE_BACKEND" == sqlite ]] || return 71
_ai_candy_cache_persist_write git_root stale old "$EPOCHSECONDS"
original_path="$PATH"
path=("$EMPTY_BIN")
rehash
_ai_candy_prompt_refresh_all_caches >/dev/null
db_after_refresh=$([[ -e $_AI_CANDY_CACHE_DB_FILE ]] && print present || print absent)
PATH="$original_path"
rehash
_ai_candy_detect_core_commands
_AI_CANDY_CACHE_BACKEND_STATE=0
_AI_CANDY_CACHE_BACKEND=none
if _ai_candy_cache_persist_read git_root stale; then
  print -r -- "VALUE=${REPLY}"
else
  print -r -- "VALUE=missing"
fi
print -r -- "DB_AFTER_REFRESH=${db_after_refresh}"
""",
                cache_home=root / "cache",
                env={"EMPTY_BIN": str(root / "empty-bin")},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("VALUE=missing", result.stdout)
        self.assertIn("DB_AFTER_REFRESH=absent", result.stdout)

    def test_live_sqlite_shell_recovers_after_another_shell_refreshes(self) -> None:
        if shutil.which("sqlite3") is None:
            self.skipTest("sqlite3 is not installed")

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            ready_file = root / "reader-ready"
            refreshed_file = root / "refreshed"
            environment = {
                **os.environ,
                "XDG_CACHE_HOME": str(cache_home),
                "READY_FILE": str(ready_file),
                "REFRESHED_FILE": str(refreshed_file),
            }
            live_shell = subprocess.Popen(
                [
                    "zsh",
                    "-fc",
                    r"""
source "$1"
_ai_candy_cache_backend_init
[[ "$_AI_CANDY_CACHE_BACKEND" == sqlite ]] || return 72
print -r -- ready >| "$READY_FILE"
for attempt in {1..500}; do
  [[ -f "$REFRESHED_FILE" ]] && break
  zselect -t 1
done
[[ -f "$REFRESHED_FILE" ]] || return 73
if _ai_candy_cache_persist_read git_root missing; then
  return 76
fi
[[ "$_AI_CANDY_CACHE_BACKEND" == sqlite ]] || return 77
_ai_candy_cache_persist_write git_root live new "$EPOCHSECONDS" || return 74
_ai_candy_cache_persist_read git_root live || return 75
print -r -- "VALUE=${REPLY} BACKEND=${_AI_CANDY_CACHE_BACKEND}"
""",
                    "zsh",
                    str(THEME),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=environment,
            )
            try:
                deadline = time.monotonic() + 5
                while not ready_file.exists() and time.monotonic() < deadline:
                    if live_shell.poll() is not None:
                        break
                    time.sleep(0.01)
                self.assertTrue(
                    ready_file.exists(), "live shell did not initialize SQLite"
                )
                refresh = run_zsh(
                    r"""
source "$1"
_ai_candy_prompt_refresh_all_caches >/dev/null
print -r -- refreshed >| "$REFRESHED_FILE"
""",
                    cache_home=cache_home,
                    env={"REFRESHED_FILE": str(refreshed_file)},
                )
                self.assertEqual(0, refresh.returncode, refresh.stderr)
                live_stdout, live_stderr = live_shell.communicate(timeout=8)
            finally:
                if live_shell.poll() is None:
                    live_shell.kill()
                    live_shell.communicate()

        self.assertEqual(0, live_shell.returncode, live_stderr)
        self.assertIn("VALUE=new|", live_stdout)
        self.assertIn("BACKEND=sqlite", live_stdout)

    def test_cache_directory_does_not_require_timeout_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_HAS_TIMEOUT=0
_AI_CANDY_TIMEOUT_CMD=""
_AI_CANDY_CACHE_READY=0
_AI_CANDY_CACHE_DIR="${XDG_CACHE_HOME}/portable/zsh-prompt"
_ai_candy_cache_init_dir
print -r -- "READY=${_AI_CANDY_CACHE_READY}"
""",
                cache_home=cache_home,
            )

            cache_dir = cache_home / "portable" / "zsh-prompt"
            self.assertEqual(0, result.returncode, result.stderr)
            self.assertIn("READY=1", result.stdout)
            self.assertTrue(cache_dir.is_dir())
            self.assertEqual(0o700, cache_dir.stat().st_mode & 0o777)

    def test_cache_write_supports_nounset_without_zsh_system(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_file = root / "cache" / "zsh-prompt" / "value"
            result = run_zsh(
                r"""
autoload -Uz colors
colors
typeset -gA FG
for color in {0..255}; do FG[$color]=""; done
function zmodload() {
  [[ "$*" == *zsh/system* ]] && return 1
  builtin zmodload "$@"
}
setopt nounset
source "$1"
_ai_candy_cache_write "$CACHE_FILE" value
_AI_CANDY_PROMPT_NETWORK_MODE=0
_AI_CANDY_PROMPT_AI_MODE=0
_AI_CANDY_PROMPT_OS_MODE=0
_ai_candy_precmd_compute_prompt
print -r -- "VALUE=$(<"$CACHE_FILE") ROOT=${_AI_CANDY_PP_CACHED_GIT_ROOT}"
""",
                cache_home=root / "cache",
                env={"CACHE_FILE": str(cache_file)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("VALUE=value ROOT=", result.stdout)

    def test_cache_directory_rejects_a_symlinked_final_component(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            target = root / "target"
            cache_home.mkdir()
            target.mkdir()
            (cache_home / "zsh-prompt").symlink_to(target, target_is_directory=True)

            result = run_zsh(
                r"""
setopt errexit
source "$1"
[[ -o errexit ]]
print -r -- "READY=${_AI_CANDY_CACHE_READY}"
""",
                cache_home=cache_home,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("READY=0", result.stdout)

    @unittest.skipUnless(os.geteuid() == 0, "changing directory ownership requires root")
    def test_cache_directory_rejects_a_foreign_owner(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cache_home = root / "cache"
            cache_dir = cache_home / "zsh-prompt"
            cache_dir.mkdir(parents=True)
            os.chown(cache_dir, 1, 1)
            cache_dir.chmod(0o777)

            result = run_zsh(
                r"""
source "$1"
print -r -- "READY=${_AI_CANDY_CACHE_READY}"
""",
                cache_home=cache_home,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("READY=0\n", result.stdout)

    def test_refresh_clears_all_derived_cache_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            result = run_zsh(
                r"""
source "$1"
_ai_candy_cache_write "$_AI_CANDY_PUBLIC_IP_CACHE_FILE" "127.0.0.1|${EPOCHSECONDS}"
_ai_candy_cache_write "$_AI_CANDY_AI_PROCESS_CACHE_FILE" "1|2|3|4|${EPOCHSECONDS}"
print -r -- "PROCESS_BEFORE=$([[ -f $_AI_CANDY_AI_PROCESS_CACHE_FILE ]] && print present || print absent)"
_ai_candy_cache_atomic_write_unlocked "$_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE" "0|7"
_AI_CANDY_GH_AUTH_MEM_CACHE=1
_AI_CANDY_GH_AUTH_MEM_CACHE_TIME=$EPOCHSECONDS
_AI_CANDY_AI_PROCESS_SNAPSHOT_TIME=$EPOCHSECONDS
typeset -gA _AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT
_AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT[$PWD]=stale
typeset -gA _AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT
_AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT[$PWD]=stale
_AI_CANDY_GIT_STASH_COUNT_BY_LOG[$PWD]=stale
typeset -gA _AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT
_AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT[$PWD]=$(( EPOCHSECONDS + 3 ))
_AI_CANDY_GIT_CONFIG_GRAPH_PATHS_BY_KEY[$PWD]=stale
_AI_CANDY_GIT_CONFIG_GRAPH_CONTEXT_BY_KEY[$PWD]=stale
_AI_CANDY_GIT_CONFIG_GRAPH_TIMEOUT_BY_KEY[$PWD]="9999999999|x7"
_AI_CANDY_GIT_CONFIG_GRAPH_RENDER_ID=42
_AI_CANDY_GIT_CONFIG_GRAPH_RENDER_KEY="$PWD"
_AI_CANDY_GIT_CONFIG_GRAPH_RENDER_VALUE=x7
_AI_CANDY_GIT_CONFIG_GRAPH_RENDER_PROBE_FAILED=1
_AI_CANDY_GIT_CONFIG_GRAPH_FAILURE_SEQUENCE=7
_AI_CANDY_MEM_CACHE_TOMBSTONES[stale:key]=$EPOCHSECONDS
_ai_candy_prompt_refresh_all_caches >/dev/null
print -r -- "IP=$([[ -f $_AI_CANDY_PUBLIC_IP_CACHE_FILE ]] && print present || print absent)"
print -r -- "AUTH=${_AI_CANDY_GH_AUTH_MEM_CACHE:-empty}"
print -r -- "PROCESS=${_AI_CANDY_AI_PROCESS_SNAPSHOT_TIME}"
print -r -- "PROCESS_FILE=$([[ -f $_AI_CANDY_AI_PROCESS_CACHE_FILE ]] && print present || print absent)"
print -r -- "ROOT_RETRIES=${#_AI_CANDY_GIT_ROOT_RETRY_AFTER_BY_CONTEXT}"
print -r -- "REMOTE=${#_AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT}"
print -r -- "OPTIONS=${#_AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT}"
print -r -- "STASH_COUNTS=${#_AI_CANDY_GIT_STASH_COUNT_BY_LOG}"
print -r -- "GRAPH_PATHS=${#_AI_CANDY_GIT_CONFIG_GRAPH_PATHS_BY_KEY}"
print -r -- "GRAPH_CONTEXTS=${#_AI_CANDY_GIT_CONFIG_GRAPH_CONTEXT_BY_KEY}"
print -r -- "GRAPH_TIMEOUTS=${#_AI_CANDY_GIT_CONFIG_GRAPH_TIMEOUT_BY_KEY}"
print -r -- "GRAPH_RENDER=${_AI_CANDY_GIT_CONFIG_GRAPH_RENDER_ID}:${_AI_CANDY_GIT_CONFIG_GRAPH_RENDER_KEY}:${_AI_CANDY_GIT_CONFIG_GRAPH_RENDER_VALUE}:${_AI_CANDY_GIT_CONFIG_GRAPH_RENDER_PROBE_FAILED}"
print -r -- "GRAPH_FAILURE_SEQUENCE=${_AI_CANDY_GIT_CONFIG_GRAPH_FAILURE_SEQUENCE}"
print -r -- "TOMBSTONES=${#_AI_CANDY_MEM_CACHE_TOMBSTONES}"
print -r -- \
  "SEQUENCE=$([[ -f $_AI_CANDY_CACHE_OPERATION_SEQUENCE_FILE ]] && print present || print absent)"
""",
                cache_home=root / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("IP=absent", result.stdout)
        self.assertIn("PROCESS_BEFORE=present", result.stdout)
        self.assertIn("AUTH=empty", result.stdout)
        self.assertIn("PROCESS=0", result.stdout)
        self.assertIn("PROCESS_FILE=absent", result.stdout)
        self.assertIn("ROOT_RETRIES=0", result.stdout)
        self.assertIn("REMOTE=0", result.stdout)
        self.assertIn("OPTIONS=0", result.stdout)
        self.assertIn("STASH_COUNTS=0", result.stdout)
        self.assertIn("GRAPH_PATHS=0", result.stdout)
        self.assertIn("GRAPH_CONTEXTS=0", result.stdout)
        self.assertIn("GRAPH_TIMEOUTS=0", result.stdout)
        self.assertIn("GRAPH_RENDER=-1:::0", result.stdout)
        self.assertIn("GRAPH_FAILURE_SEQUENCE=0", result.stdout)
        self.assertIn("TOMBSTONES=0", result.stdout)
        self.assertIn("SEQUENCE=absent", result.stdout)

    def test_unavailable_cache_never_attempts_persistent_reads(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_READY=0
_AI_CANDY_CACHE_BACKEND_STATE=1
typeset -g PERSIST_READS=0
function _ai_candy_cache_persist_read_with_waits() {
  (( PERSIST_READS++ ))
  return 0
}
_ai_candy_cache_get git_root key >/dev/null
print -r -- "PERSIST_READS=${PERSIST_READS}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("PERSIST_READS=0\n", result.stdout)

    def test_memory_cache_cleanup_works_after_threshold(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_MEM_CACHE_MAX_ENTRIES=2
_AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD=2
_AI_CANDY_MEM_CACHE_GIT_ROOT=(
  first "one|1"
  second "two|2"
  third "three|3"
)
_ai_candy_mem_cache_cleanup git_root
print -r -- "COUNT=${#_AI_CANDY_MEM_CACHE_GIT_ROOT}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("COUNT=2", result.stdout)

    def test_tombstone_cache_is_bounded_after_unique_deletes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_AI_CANDY_MEM_CACHE_MAX_ENTRIES=2
_AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD=2
_ai_candy_cache_delete_key git_root first
_ai_candy_cache_delete_key git_root second
_ai_candy_cache_delete_key git_root third
print -r -- "COUNT=${#_AI_CANDY_MEM_CACHE_TOMBSTONES}"
""",
                cache_home=Path(tmp) / "cache",
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("COUNT=2\n", result.stdout)

    def test_git_session_maps_are_bounded_after_visiting_many_repositories(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("one", "two", "three"):
                git_dir = root / name / ".git"
                git_dir.mkdir(parents=True)
                (git_dir / "HEAD").write_text(
                    "ref: refs/heads/main\n", encoding="ascii"
                )
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_MEM_CACHE_MAX_ENTRIES=2
_AI_CANDY_MEM_CACHE_CLEANUP_THRESHOLD=2
function _ai_candy_run_local_probe() {
  [[ "$*" == git\ status\ * ]] && return 124
  [[ "$*" == *remote.origin.url* ]] && builtin print -r -- origin
  return 0
}
function _ai_candy_hash_string() { REPLY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef; }
for repo in "$REPO_ROOT"/one "$REPO_ROOT"/two "$REPO_ROOT"/three; do
  _ai_candy_load_git_display_options "$repo"
  _AI_CANDY_PP_CACHED_GIT_ROOT="$repo"
  (( ++_AI_CANDY_PROMPT_RENDER_ID ))
  _ai_candy_get_cached_git_remote_branch
  _ai_candy_collect_git_snapshot || true
done
print -r -- \
  "OPTIONS=${#_AI_CANDY_GIT_OMZ_OPTIONS_BY_CONTEXT} REMOTES=${#_AI_CANDY_GIT_REMOTE_KEY_BY_CONTEXT} RETRIES=${#_AI_CANDY_GIT_SNAPSHOT_RETRY_AFTER_BY_CONTEXT}"
""",
                cache_home=root / "cache",
                env={"REPO_ROOT": str(root)},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("OPTIONS=2 REMOTES=2 RETRIES=2\n", result.stdout)


    def test_executable_cache_keys_values_and_timestamps_remain_data(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            marker = root / "executed"
            payload = f'entry[$(command touch "{marker}")]'
            result = run_zsh(
                r"""
source "$1"
_AI_CANDY_CACHE_SCHEDULE_PERSISTENCE=0
_ai_candy_cache_set gh_pr "$PAYLOAD" "$PAYLOAD" "$EPOCHSECONDS"
memory_value="${_AI_CANDY_MEM_CACHE_GH_PR[$PAYLOAD]-}"
_ai_candy_cache_persist_write probe "$PAYLOAD" "$PAYLOAD" "$EPOCHSECONDS" || exit 2
_ai_candy_cache_persist_read probe "$PAYLOAD" || exit 3
persistent_value="$REPLY"
if _ai_candy_cache_timestamp_is_fresh "$PAYLOAD" 300 "$EPOCHSECONDS"; then
  timestamp_status=fresh
else
  timestamp_status=rejected
fi
print -r -- "MEMORY=${memory_value}"
print -r -- "PERSISTENT=${persistent_value}"
print -r -- "TIMESTAMP=${timestamp_status}"
""",
                cache_home=root / "cache",
                env={"PAYLOAD": payload},
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn(f"MEMORY={payload}|", result.stdout)
        self.assertIn(f"PERSISTENT={payload}|", result.stdout)
        self.assertIn("TIMESTAMP=rejected", result.stdout)
        self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
