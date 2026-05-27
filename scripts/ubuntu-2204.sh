#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() {
    printf "\n[INFO] %s\n" "$*"
}

die() {
    printf "[ERROR] %s\n" "$*" >&2
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

main() {
    require_wsl
    require_ubuntu_2204

    info "Requesting sudo permission"
    sudo -v

    info "Ubuntu 22.04 WSL initialization starts"
    info "Script directory: ${SCRIPT_DIR}"
    info "Next: install development tools"
    info "Next: install zsh and neovim environment"
}

main "$@"
