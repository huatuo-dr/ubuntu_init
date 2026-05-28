#!/usr/bin/env bash
set -euo pipefail

readonly PYTHON_LINK="${UBUNTU_INIT_PYTHON_LINK:-/usr/bin/python}"
readonly DOCKER_KEYRING="${UBUNTU_INIT_DOCKER_KEYRING:-/etc/apt/keyrings/docker.gpg}"
readonly DOCKER_SOURCE_LIST="${UBUNTU_INIT_DOCKER_SOURCE_LIST:-/etc/apt/sources.list.d/docker.list}"
readonly DOCKER_DAEMON_JSON="${UBUNTU_INIT_DOCKER_DAEMON_JSON:-/etc/docker/daemon.json}"
readonly BAZELISK_BIN="${UBUNTU_INIT_BAZELISK_BIN:-/usr/local/bin/bazelisk}"
readonly BAZEL_BIN="${UBUNTU_INIT_BAZEL_BIN:-/usr/local/bin/bazel}"
readonly POLICY_RC_D="${UBUNTU_INIT_POLICY_RC_D:-/usr/sbin/policy-rc.d}"

POLICY_RC_D_CREATED=0

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

die() {
    printf "[ERROR] %s\n" "$*" >&2
    exit 1
}

disable_service_autostart() {
    if [[ -e "${POLICY_RC_D}" ]]; then
        warn "policy-rc.d already exists, keeping it: ${POLICY_RC_D}"
        return
    fi

    info "Temporarily disabling service autostart during apt installation"
    sudo tee "${POLICY_RC_D}" >/dev/null <<'EOF'
#!/bin/sh
exit 101
EOF
    sudo chmod +x "${POLICY_RC_D}"
    POLICY_RC_D_CREATED=1
}

restore_service_autostart() {
    if [[ "${POLICY_RC_D_CREATED}" != "1" ]]; then
        return
    fi

    sudo rm -f "${POLICY_RC_D}"
    POLICY_RC_D_CREATED=0
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
        gnupg
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
        git-lfs
    )

    disable_service_autostart
    trap restore_service_autostart EXIT

    info "Installing Python repository prerequisites"
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt-get update

    info "Installing common development packages"
    sudo apt-get install -y "${packages[@]}"
    restore_service_autostart
    trap - EXIT
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
    local n_command="${HOME}/.npm-global/bin/n"
    local n_prefix="${HOME}/.local"
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
    if [[ ! -x "${n_command}" ]]; then
        die "n was not installed at expected path: ${n_command}"
    fi
    mkdir -p "${n_prefix}"
    N_PREFIX="${n_prefix}" "${n_command}" stable
    export PATH="${n_prefix}/bin:${PATH}"
    npm install -g yarn
}

install_bazelisk() {
    local arch
    local asset_arch
    local binary_file

    if [[ -x "${BAZELISK_BIN}" ]]; then
        warn "Bazelisk already exists, skipping install"
    else
        info "Installing Bazelisk"
        arch="$(dpkg --print-architecture)"
        case "${arch}" in
            amd64)
                asset_arch="amd64"
                ;;
            arm64)
                asset_arch="arm64"
                ;;
            *)
                die "Unsupported Bazelisk architecture: ${arch}"
                ;;
        esac

        binary_file="$(mktemp)"
        curl -fsSL \
            "https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-${asset_arch}" \
            -o "${binary_file}"
        sudo install -m 0755 "${binary_file}" "${BAZELISK_BIN}"
        rm -f "${binary_file}"
    fi

    if [[ -e "${BAZEL_BIN}" || -L "${BAZEL_BIN}" ]]; then
        warn "bazel command already exists, keeping it"
    else
        sudo ln -s "${BAZELISK_BIN}" "${BAZEL_BIN}"
    fi
}

configure_docker_repository() {
    local arch
    local codename
    local key_file
    local keyring_file

    if [[ -f "${DOCKER_KEYRING}" ]]; then
        warn "Docker GPG keyring already exists, keeping it: ${DOCKER_KEYRING}"
    else
        info "Installing Docker GPG key"
        sudo install -m 0755 -d "$(dirname "${DOCKER_KEYRING}")"

        key_file="$(mktemp)"
        keyring_file="$(mktemp)"
        rm -f "${keyring_file}"
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${key_file}"
        gpg --dearmor -o "${keyring_file}" "${key_file}"
        sudo install -m 0644 "${keyring_file}" "${DOCKER_KEYRING}"
        sudo chmod a+r "${DOCKER_KEYRING}"
        rm -f "${key_file}" "${keyring_file}"
    fi

    if [[ -f "${DOCKER_SOURCE_LIST}" ]]; then
        warn "Docker apt source already exists, keeping it: ${DOCKER_SOURCE_LIST}"
        return
    fi

    info "Configuring Aliyun Docker apt source"
    arch="$(dpkg --print-architecture)"
    codename="$(lsb_release -cs)"
    sudo install -m 0755 -d "$(dirname "${DOCKER_SOURCE_LIST}")"
    printf 'deb [arch=%s signed-by=%s] https://mirrors.aliyun.com/docker-ce/linux/ubuntu %s stable\n' \
        "${arch}" "${DOCKER_KEYRING}" "${codename}" | sudo tee "${DOCKER_SOURCE_LIST}" >/dev/null
}

configure_docker_daemon() {
    if [[ -f "${DOCKER_DAEMON_JSON}" ]]; then
        warn "Docker daemon config already exists, keeping it: ${DOCKER_DAEMON_JSON}"
        return 1
    fi

    info "Configuring Docker registry mirrors"
    sudo install -m 0755 -d "$(dirname "${DOCKER_DAEMON_JSON}")"
    sudo tee "${DOCKER_DAEMON_JSON}" >/dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://mirror.aliyuncs.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
EOF
}

restart_docker_service() {
    if ! command -v systemctl >/dev/null 2>&1; then
        warn "systemctl is not available, skip Docker service restart"
        return
    fi

    sudo systemctl daemon-reload || warn "Failed to reload systemd daemon for Docker"
    sudo systemctl restart docker || warn "Failed to restart Docker service"
}

install_docker() {
    info "Removing old Docker packages if present"
    sudo apt-get remove -y docker docker-engine docker.io containerd runc docker-compose docker-compose-plugin || true

    info "Installing Docker prerequisites"
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release

    configure_docker_repository

    info "Installing Docker CE and Compose v2"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    info "Enabling Docker service"
    sudo systemctl enable docker || warn "Failed to enable Docker service"
    sudo systemctl start docker || warn "Failed to start Docker service"

    info "Adding current user to docker group"
    sudo usermod -aG docker "${USER}"

    if configure_docker_daemon; then
        restart_docker_service
    else
        warn "Docker daemon config was not changed, skip automatic Docker restart"
    fi
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

    if [[ -f "${HOME}/.ssh/id_rsa" ]]; then
        warn "SSH RSA key already exists, keeping it: ${HOME}/.ssh/id_rsa"
    else
        ssh-keygen -t rsa -b 4096 -f "${HOME}/.ssh/id_rsa" -N ""
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

    if command -v git-lfs >/dev/null 2>&1; then
        git lfs install
    else
        warn "git-lfs is not available, skipping git lfs install"
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
    install_bazelisk
    install_docker
    configure_ssh
    configure_git
    install_python_packages

    success "Common development tools setup finished"
}

main "$@"
