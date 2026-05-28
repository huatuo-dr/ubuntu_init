#############################################
# User Configure
#############################################
source /etc/profile
export PATH=$PATH:$HOME/.local/bin/
export PATH=$PATH:$HOME/.npm-global/bin

# FZF
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export FZF_DEFAULT_OPTS='--height 90% --layout=reverse --border --preview "[[ $(file --mime {}) =~ binary ]] && echo {} is a binary file || (ccat --color=always {} || highlight -O ansi -l {} || cat {}) 2> /dev/null | head -500"'
export FZF_COMPLETION_TRIGGER='\'
export FZF_PREVIEW_COMMAND='echo "
# thefuck
eval $(thefuck --alias)
" >> ~/.zshrc[[ $(file --mime {}) =~ binary ]] && echo {} is a binary file || (ccat --color=always {} || highlight -O ansi -l {} || cat {}) 2> /dev/null | head -500'

# yzai
function ya() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}
export EDITOR='nvim'

# git
alias gitperson="git config user.name \"huatuo-dr\"; git config user.email \"dlkxiaok@163.com\""
alias gitshow="git config user.name; git config user.email"
alias gitlog="git log --graph --pretty=format:'%C(auto)%h %d %s %C(black)%C(bold)%cr' --all"
gitweb() {
  if [ -n "$1" ]; then
    url="$1"
  else
    url=$(git remote get-url origin)
  fi
  echo "$url" | sed -E \
    -e 's|ssh://git@([^/]+)/(.+)(\.git)?|https://\1/\2|' \
    -e 's|git@([^:]+):(.+)(\.git)?|https://\1/\2|'
}

# lazygit
alias lg="lazygit"

# Windows
export WE='/mnt/d/UbuntuDisk'

# claude
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="true"
alias skip_claude="claude --dangerously-skip-permissions"
alias teams_claude="export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1; claude --teammate-mode tmux"

# coedex
alias skip_codex="codex --dangerously-bypass-approvals-and-sandbox"

