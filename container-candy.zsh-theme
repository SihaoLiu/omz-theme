# Function to detect if we're in a container and return colored status
function container_status() {
  local version=""
  if [[ -f /etc/os-release ]]; then
    local os_id=$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    local version_id=$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    if [[ -n "$os_id" && -n "$version_id" ]]; then
      version=", $os_id-$version_id"
    fi
  fi
  
  if test -f /run/.containerenv; then
    echo "%{$fg[red]%}(container$version)%{$reset_color%}"
  else
    echo "%{$fg[yellow]%}(physical$version)%{$reset_color%}"
  fi
}

# Modified PROMPT with container status
PROMPT=$'%{$fg_bold[green]%}%n@%m %{$reset_color%}$(container_status) %{$fg[blue]%}%D{[%X]} %{$reset_color%}%{$fg[white]%}[%~]%{$reset_color%} $(git_prompt_info)\
%{$fg[blue]%}->%{$fg_bold[blue]%} %#%{$reset_color%} '

ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg[green]%}["
ZSH_THEME_GIT_PROMPT_SUFFIX="]%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY=" %{$fg[red]%}*%{$fg[green]%}"
ZSH_THEME_GIT_PROMPT_CLEAN=""