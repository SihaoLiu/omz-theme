# Function to detect if we're in a container and return colored status
function container_status() {
  if test -f /run/.containerenv; then
    echo "%{$fg[red]%}(container)%{$reset_color%}"
  else
    echo "%{$fg[yellow]%}(physical)%{$reset_color%}"
  fi
}

# Modified PROMPT with container status
PROMPT=$'%{$fg_bold[green]%}%n@%m %{$reset_color%}$(container_status) %{$fg[blue]%}%D{[%X]} %{$reset_color%}%{$fg[white]%}[%~]%{$reset_color%} $(git_prompt_info)\
%{$fg[blue]%}->%{$fg_bold[blue]%} %#%{$reset_color%} '

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg[green]%}["
ZSH_THEME_GIT_PROMPT_SUFFIX="]%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY=" %{$fg[red]%}*%{$fg[green]%}"
ZSH_THEME_GIT_PROMPT_CLEAN=""