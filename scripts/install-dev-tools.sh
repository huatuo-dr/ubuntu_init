#!/usr/bin/env bash
set -euo pipefail

readonly PYTHON_LINK="${UBUNTU_INIT_PYTHON_LINK:-/usr/bin/python}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    readonly COLOR_BLUE=$'\033[34m'
    readonly COLOR_GREEN=$'\033[32m'
    readonly COLOR_YELLOW=$'\033[33m'
    readonly COLOR_RESET=$'\033[0m'
else
    readonly COLOR_BLUE=""
    readonly COLOR_GREEN=""
    readonly COLOR_YELLOW=""
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

install_apt_packages() {
    local packages=(
        python3-pip
        python3.12
        python3.12-venv
        python3.10-venv
        aptitude
        build-essential
        libsystemd-dev
        lib32stdc++6
        clangd
        ripgrep
        fd-find
        neofetch
        curl
        net-tools
        lcov
        bear
        tofrodos
        vim
        xclip
        ninja-build
        cmake
        openssh-server
        fzf
        autoconf
        universal-ctags
    )

    info "Installing Python repository prerequisites"
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt-get update

    info "Installing common development packages"
    sudo apt-get install -y "${packages[@]}"
}

configure_python() {
    if [[ -e "${PYTHON_LINK}" || -L "${PYTHON_LINK}" ]]; then
        warn "Python command already exists, keeping it: ${PYTHON_LINK}"
        return
    fi

    info "Configuring python command"
    sudo ln -s python3.12 "${PYTHON_LINK}"
}

install_node() {
    local setup_script

    info "Installing Node.js and Yarn"
    setup_script="$(mktemp)"
    curl -fsSL https://deb.nodesource.com/setup_current.x -o "${setup_script}"
    sudo -E bash "${setup_script}"
    rm -f "${setup_script}"

    sudo apt-get install -y nodejs
    mkdir -p "${HOME}/.npm-global"
    npm config set prefix '~/.npm-global'
    npm install n -g
    sudo n stable
    npm install -g yarn
}

configure_ssh() {
    info "Preparing SSH directory"
    mkdir -p "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    touch "${HOME}/.ssh/authorized_keys"
    chmod 600 "${HOME}/.ssh/authorized_keys"

    if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
        warn "SSH ed25519 key already exists, keeping it: ${HOME}/.ssh/id_ed25519"
    else
        ssh-keygen -t ed25519 -f "${HOME}/.ssh/id_ed25519" -N ""
    fi
}

configure_git() {
    local gitignore_file="${HOME}/.gitignore_global"

    info "Configuring global git ignore"
    git config --global core.excludesfile "${gitignore_file}"
    git config --global core.editor vim
    git config --global core.autocrlf false
    git config --global color.ui auto
    git config --global credential.helper store
    git config --global core.quotepath false
    git config --global http.postBuffer 524288000
    touch "${gitignore_file}"

    if ! grep -Fxq ".tags" "${gitignore_file}"; then
        printf ".tags\n" >>"${gitignore_file}"
    fi
}

install_python_packages() {
    info "Installing Python packages"
    pip3 install pycryptodome
    pip3 install ecdsa
    pip3 install uv
}

main() {
    install_apt_packages
    configure_python
    install_node
    configure_ssh
    configure_git
    install_python_packages

    success "Common development tools setup finished"
}

main "$@"
