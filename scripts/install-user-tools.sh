#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly YAZI_KEYRING="${UBUNTU_INIT_YAZI_KEYRING:-/etc/apt/trusted.gpg.d/debian.griffo.io.gpg}"
readonly YAZI_SOURCE_LIST="${UBUNTU_INIT_YAZI_SOURCE_LIST:-/etc/apt/sources.list.d/debian.griffo.io.list}"
readonly OH_MY_ZSH_DIR="${UBUNTU_INIT_OH_MY_ZSH_DIR:-${HOME}/.oh-my-zsh}"
readonly ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-${OH_MY_ZSH_DIR}/custom}"
readonly TMUX_CONFIG_REPO="${UBUNTU_INIT_TMUX_CONFIG_REPO:-https://github.com/KyleDeng/tmux.conf}"
readonly TMUX_CONFIG_DIR="${UBUNTU_INIT_TMUX_CONFIG_DIR:-${HOME}/.cache/ubuntu-init/tmux.conf}"
readonly NVIM_CONFIG_REPO="${UBUNTU_INIT_NVIM_CONFIG_REPO:-https://github.com/KyleDeng/nvim.git}"
readonly NVIM_CONFIG_BRANCH="${UBUNTU_INIT_NVIM_CONFIG_BRANCH:-ver-0.12.0}"
readonly NVIM_CONFIG_DIR="${UBUNTU_INIT_NVIM_CONFIG_DIR:-${HOME}/.config/nvim}"
readonly LAZYGIT_COMMAND="${UBUNTU_INIT_LAZYGIT_COMMAND:-lazygit}"
readonly USER_ZSHRC="${UBUNTU_INIT_USER_ZSHRC:-${SCRIPT_DIR}/user.zshrc}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    readonly COLOR_BLUE=$'\033[34m'
    readonly COLOR_GREEN=$'\033[32m'
    readonly COLOR_YELLOW=$'\033[33m'
    readonly COLOR_RED=$'\033[31m'
    readonly COLOR_RESET=$'\033[0m'
else
    readonly COLOR_BLUE=""
    readonly COLOR_GREEN=""
    readonly COLOR_YELLOW=""
    readonly COLOR_RED=""
    readonly COLOR_RESET=""
fi

log() {
    local color="$1"
    local level="$2"
    shift 2

    printf "\n%s[%s]%s %s\n" "${color}" "${level}" "${COLOR_RESET}" "$*"
}

info() {
    log "${COLOR_BLUE}" "INFO" "$*"
}

success() {
    log "${COLOR_GREEN}" "OK" "$*"
}

warn() {
    log "${COLOR_YELLOW}" "WARN" "$*"
}

die() {
    printf "%s[ERROR]%s %s\n" "${COLOR_RED}" "${COLOR_RESET}" "$*" >&2
    exit 1
}

configure_yazi_repository() {
    local codename
    local key_file
    local keyring_file

    if [[ -f "${YAZI_KEYRING}" ]]; then
        warn "Yazi repository key already exists, keeping it: ${YAZI_KEYRING}"
    else
        info "Installing Yazi repository key"
        key_file="$(mktemp)"
        keyring_file="$(mktemp)"
        curl -sS https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc -o "${key_file}"
        gpg --dearmor --yes -o "${keyring_file}" "${key_file}"
        sudo install -m 0644 "${keyring_file}" "${YAZI_KEYRING}"
        rm -f "${key_file}" "${keyring_file}"
    fi

    if [[ -f "${YAZI_SOURCE_LIST}" ]]; then
        warn "Yazi repository source already exists, keeping it: ${YAZI_SOURCE_LIST}"
    else
        info "Configuring Yazi apt repository"
        codename="$(lsb_release -sc 2>/dev/null)"
        printf "deb https://debian.griffo.io/apt %s main\n" "${codename}" \
            | sudo tee "${YAZI_SOURCE_LIST}" >/dev/null
    fi
}

install_yazi() {
    local packages=(
        yazi
        file
        ffmpeg
        jq
        poppler-utils
        p7zip-full
        zoxide
    )

    configure_yazi_repository

    info "Installing Yazi and optional preview/navigation dependencies"
    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"
}

install_terminal_packages() {
    local packages=(
        zsh
        powerline
        tmux
        git
    )

    info "Installing terminal and editor packages"
    sudo apt-get install -y "${packages[@]}"
}

install_neovim() {
    info "Installing neovim"
    sudo add-apt-repository -y ppa:neovim-ppa/unstable
    sudo apt-get update
    sudo apt-get install -y neovim
}

clone_if_missing() {
    local repo="$1"
    local target="$2"
    shift 2

    if [[ -d "${target}" ]]; then
        warn "Repository already exists, keeping it: ${target}"
        return
    fi

    git clone "$@" "${repo}" "${target}"
}

install_oh_my_zsh() {
    if [[ -d "${OH_MY_ZSH_DIR}" ]]; then
        warn "oh-my-zsh already exists, keeping it: ${OH_MY_ZSH_DIR}"
    else
        info "Installing oh-my-zsh"
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
            sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        mkdir -p "${OH_MY_ZSH_DIR}"
    fi

    info "Installing zsh plugins and theme"
    mkdir -p "${ZSH_CUSTOM_DIR}/plugins" "${ZSH_CUSTOM_DIR}/themes"
    clone_if_missing \
        "https://github.com/zsh-users/zsh-autosuggestions" \
        "${ZSH_CUSTOM_DIR}/plugins/zsh-autosuggestions"
    clone_if_missing \
        "https://github.com/zsh-users/zsh-syntax-highlighting.git" \
        "${ZSH_CUSTOM_DIR}/plugins/zsh-syntax-highlighting"
    clone_if_missing \
        "https://github.com/romkatv/powerlevel10k.git" \
        "${ZSH_CUSTOM_DIR}/themes/powerlevel10k" \
        --depth=1
}

configure_zshrc() {
    local zshrc="${HOME}/.zshrc"

    info "Configuring .zshrc"
    touch "${zshrc}"

    if grep -q '^ZSH_THEME=' "${zshrc}"; then
        sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "${zshrc}"
    else
        printf 'ZSH_THEME="powerlevel10k/powerlevel10k"\n' >>"${zshrc}"
    fi

    if grep -q '^plugins=' "${zshrc}"; then
        sed -i 's|^plugins=.*|plugins=(git z zsh-syntax-highlighting zsh-autosuggestions)|' "${zshrc}"
    else
        printf 'plugins=(git z zsh-syntax-highlighting zsh-autosuggestions)\n' >>"${zshrc}"
    fi

}

append_user_zshrc() {
    local zshrc="${HOME}/.zshrc"

    info "Appending user .zshrc block"
    touch "${zshrc}"

    if [[ ! -f "${USER_ZSHRC}" ]]; then
        warn "user.zshrc not found, skipping append: ${USER_ZSHRC}"
        return
    fi

    if grep -Fxq '# >>> ubuntu_init user.zshrc >>>' "${zshrc}"; then
        warn "user.zshrc block already exists, keeping it: ${zshrc}"
        return
    fi

    {
        printf "\n# >>> ubuntu_init user.zshrc >>>\n"
        cat "${USER_ZSHRC}"
        printf "\n# <<< ubuntu_init user.zshrc <<<\n"
    } >>"${zshrc}"
}

install_tmux_config() {
    info "Installing tmux config"
    mkdir -p "$(dirname "${TMUX_CONFIG_DIR}")"
    clone_if_missing "${TMUX_CONFIG_REPO}" "${TMUX_CONFIG_DIR}"

    if [[ -f "${HOME}/.tmux.conf" ]]; then
        warn "tmux config already exists, keeping it: ${HOME}/.tmux.conf"
        return
    fi

    if [[ -f "${TMUX_CONFIG_DIR}/tmux.conf" ]]; then
        cp "${TMUX_CONFIG_DIR}/tmux.conf" "${HOME}/.tmux.conf"
    else
        warn "tmux.conf not found, skipping copy: ${TMUX_CONFIG_DIR}/tmux.conf"
    fi
}

install_lazygit() {
    local arch
    local asset_arch
    local version
    local temp_dir

    if command -v "${LAZYGIT_COMMAND}" >/dev/null 2>&1; then
        warn "lazygit already exists, skipping install"
        return
    fi

    info "Installing lazygit"
    arch="$(dpkg --print-architecture)"
    case "${arch}" in
        amd64)
            asset_arch="x86_64"
            ;;
        arm64)
            asset_arch="arm64"
            ;;
        *)
            die "Unsupported lazygit architecture: ${arch}"
            ;;
    esac

    version="$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" \
        | grep -Po '"tag_name": *"v\K[^"]*')"
    [[ -n "${version}" ]] || die "Failed to resolve latest lazygit version"
    temp_dir="$(mktemp -d)"

    (
        cd "${temp_dir}"
        curl -Lo lazygit.tar.gz \
            "https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_Linux_${asset_arch}.tar.gz"
        tar xf lazygit.tar.gz lazygit
        sudo install lazygit -D -t /usr/local/bin/
    )

    rm -rf "${temp_dir}"
}

install_neovim_config() {
    info "Installing neovim config"
    mkdir -p "$(dirname "${NVIM_CONFIG_DIR}")"
    clone_if_missing "${NVIM_CONFIG_REPO}" "${NVIM_CONFIG_DIR}" -b "${NVIM_CONFIG_BRANCH}"

    if [[ -d "${HOME}/.local/share/nvim/lazy/coc.nvim" ]]; then
        (
            cd "${HOME}/.local/share/nvim/lazy/coc.nvim"
            yarn install
            yarn build
        )
    else
        warn "coc.nvim is not installed yet; open nvim once, then run yarn install/build if needed"
    fi
}

print_manual_steps() {
    info "Optional manual steps"
    cat <<'EOF'
If you want zsh to be the default login shell, run:
  chsh -s "$(command -v zsh)"

Start nvim once to install plugins:
  nvim

Add the new SSH public key to GitHub and GitLab:
  cat ~/.ssh/id_ed25519.pub

Restart the WSL instance after changing the default shell.
EOF
}

main() {
    info "Requesting sudo permission"
    sudo -v

    install_yazi
    install_terminal_packages
    install_neovim
    install_oh_my_zsh
    configure_zshrc
    install_tmux_config
    install_lazygit
    install_neovim_config
    append_user_zshrc
    print_manual_steps

    success "User tools setup finished"
}

main "$@"
