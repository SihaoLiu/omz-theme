# Enhanced PROMPT with all new features:
# - Exit status indicator
# - SSH indicator (nf-md-ssh/[SSH])
# - Public IP address (green if online, red "offline" if offline, hidden if no curl)
# - GitHub username badge [Username] (white bg, black text; red if mismatch)
# - Session badge (Container/TTY/GNOME/KDE/XFCE/Xorg/Host with NF icons or C/T/G/K/X/O/H)
# - Time with timezone [HH:MM:SS TZ]
# - Smart path with git-aware coloring and submodule support
# - Git status with extended info (ahead/behind/stash) + special states (rebase/merge/bisect)
# - PR status with CI indicator
# - Background jobs counter
# - Adaptive RPROMPT for system info and optional tools
# - Toggles for symbols, network features, tools, help, and cache refresh
#
# Order: status, identity, session, time, path, Git, PR, system, tools, jobs
# Second line: -> %#
#
# PERFORMANCE: Uses precomputed variables (_AI_CANDY_PP_*) from precmd to avoid subshells
# All segments are computed once in _ai_candy_precmd_compute_prompt before prompt display
PROMPT='${_AI_CANDY_PP_VENV}${_AI_CANDY_PP_EXIT}${_AI_CANDY_PP_SSH}${_AI_CANDY_PP_USER_HOST}${_AI_CANDY_PP_PUBLIC_IP}${_AI_CANDY_PP_GH_USER}${_AI_CANDY_PP_BADGE} %B${_AI_CANDY_PP_TIME}%b ${_AI_CANDY_PP_PATH}${${_AI_CANDY_USE_OMZ_ASYNC:#1}:+${_AI_CANDY_PP_GIT_INFO:+ }${_AI_CANDY_PP_GIT_INFO}${_AI_CANDY_PP_GIT_EXT}}${${_AI_CANDY_USE_OMZ_ASYNC:#0}:+${_OMZ_ASYNC_OUTPUT[_ai_candy_git_prompt_async]-}}${_AI_CANDY_PP_GIT_SPECIAL}${_AI_CANDY_PP_PR:+ }${_AI_CANDY_PP_PR}${_AI_CANDY_PP_SYSINFO_LEFT}${_AI_CANDY_PP_AI_LEFT}%(1j. %{$fg[yellow]%}${_AI_CANDY_PP_JOBS}%j%{$reset_color%}.)
%{$fg[blue]%}->%{$fg_bold[blue]%} %#%{$reset_color%} '

# Right prompt: system info and optional tools in short/minimal modes
# Auto-hides when command line is long
RPROMPT='${_AI_CANDY_PP_RPROMPT}'

ZSH_THEME_GIT_PROMPT_PREFIX='%F{green}'
ZSH_THEME_GIT_PROMPT_SUFFIX='%f'
ZSH_THEME_GIT_PROMPT_DIRTY=' %F{red}*%F{green}'
ZSH_THEME_GIT_PROMPT_CLEAN=""

_ai_candy_restore_source_options
builtin unfunction _ai_candy_restore_source_options
