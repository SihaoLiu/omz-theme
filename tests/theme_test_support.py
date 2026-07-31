#!/usr/bin/env python3
import os
import subprocess
import time
from pathlib import Path
from typing import Mapping, Optional


ROOT = Path(__file__).resolve().parents[1]
THEME = ROOT / "ai-candy.zsh-theme"
CACHE_SCHEDULING_BUDGET_MS = 300.0


def process_is_running(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False

    proc_stat = Path(f"/proc/{pid}/stat")
    if proc_stat.is_file():
        try:
            stat_tail = proc_stat.read_text(encoding="ascii").rsplit(") ", 1)[-1]
        except (FileNotFoundError, ProcessLookupError):
            return False
        if stat_tail.split(maxsplit=1)[0] == "Z":
            return False
    return True


def wait_for_process_exit(
    pid: int, timeout: float, stable_interval: float = 0.01
) -> bool:
    deadline = time.monotonic() + timeout
    stopped_since: Optional[float] = None
    while time.monotonic() < deadline:
        if process_is_running(pid):
            stopped_since = None
        else:
            now = time.monotonic()
            if stopped_since is None:
                stopped_since = now
            elif now - stopped_since >= stable_interval:
                return True
        time.sleep(0.001)
    return False


def run_zsh(
    script: str,
    *,
    cache_home: Path,
    cwd: Path = ROOT,
    env: Optional[Mapping[str, str]] = None,
    timeout: Optional[float] = None,
) -> subprocess.CompletedProcess[str]:
    shell_env = {
        **os.environ,
        "XDG_CACHE_HOME": str(cache_home),
        **(env or {}),
    }
    return subprocess.run(
        ["zsh", "-fc", script, "zsh", str(THEME)],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=shell_env,
        check=False,
        timeout=timeout,
    )
