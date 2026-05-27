#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APT_SOURCES_LIST="${UBUNTU_INIT_APT_SOURCES_LIST:-/etc/apt/sources.list}"
readonly DEV_TOOLS_SCRIPT="${UBUNTU_INIT_DEV_TOOLS_SCRIPT:-${SCRIPT_DIR}/install-dev-tools.sh}"
readonly ZSH_NVIM_SCRIPT="${UBUNTU_INIT_ZSH_NVIM_SCRIPT:-${SCRIPT_DIR}/install-zsh-nvim.sh}"

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

require_wsl() {
    if ! grep -qi microsoft /proc/version; then
        die "This script should run inside WSL."
    fi
}

require_ubuntu_2204() {
    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID}" != "ubuntu" || "${VERSION_ID}" != "22.04" ]]; then
        die "This script should run on Ubuntu 22.04."
    fi
}

setup_apt_sources() {
    info "Configuring Aliyun apt sources for Ubuntu 22.04"

    sudo cp "${APT_SOURCES_LIST}" "${APT_SOURCES_LIST}.bak"
    sudo tee "${APT_SOURCES_LIST}" >/dev/null <<'EOF'
deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
EOF

    info "Cleaning old apt cache"
    sudo apt-get clean
    sudo rm -rf /var/lib/apt/lists/*

    info "Updating apt package lists"
    sudo apt-get update
}

upgrade_system_packages() {
    info "Upgrading system packages"
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
}

run_script() {
    local script_path="$1"
    local script_name="$2"

    if [[ ! -f "${script_path}" ]]; then
        die "Missing ${script_name} script: ${script_path}"
    fi

    info "Running ${script_name}"
    bash "${script_path}"
}

main() {
    require_wsl
    require_ubuntu_2204

    info "Requesting sudo permission"
    sudo -v

    info "Ubuntu 22.04 WSL initialization starts"
    info "Script directory: ${SCRIPT_DIR}"

    setup_apt_sources
    upgrade_system_packages
    run_script "${DEV_TOOLS_SCRIPT}" "development tools setup"
    run_script "${ZSH_NVIM_SCRIPT}" "zsh and neovim setup"

    success "Ubuntu 22.04 WSL initialization finished"
}

main "$@"
