#!/usr/bin/env bash
set -euo pipefail

readonly OS_RELEASE_FILE="${UBUNTU_INIT_OS_RELEASE:-/etc/os-release}"
readonly PROC_VERSION_FILE="${UBUNTU_INIT_PROC_VERSION:-/proc/version}"
readonly PROC_OSRELEASE_FILE="${UBUNTU_INIT_PROC_OSRELEASE:-/proc/sys/kernel/osrelease}"
readonly SAMBA_CONF="${UBUNTU_INIT_SAMBA_CONF:-/etc/samba/smb.conf}"
readonly SHARE_DIR="${UBUNTU_INIT_SHARE_DIR:-/home/share}"
readonly FONT_DIR="${UBUNTU_INIT_FONT_DIR:-${HOME}/.local/share/fonts}"
readonly HACK_FONT_URL="${UBUNTU_INIT_HACK_FONT_URL:-https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/Hack.zip}"
readonly CHROME_DEB_URL="${UBUNTU_INIT_CHROME_DEB_URL:-https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb}"
readonly CHROME_COMMAND="${UBUNTU_INIT_CHROME_COMMAND:-google-chrome}"

ASSUME_YES=0
SKIP_SMBPASSWD=0

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

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -y, --yes          Run without interactive confirmation.
  --skip-smbpasswd  Skip interactive Samba password setup.
  -h, --help        Show this help message.
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            -y | --yes)
                ASSUME_YES=1
                ;;
            --skip-smbpasswd)
                SKIP_SMBPASSWD=1
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
        shift
    done
}

require_non_wsl() {
    if grep -qiE 'microsoft|wsl' "${PROC_VERSION_FILE}" 2>/dev/null ||
        grep -qiE 'microsoft|wsl' "${PROC_OSRELEASE_FILE}" 2>/dev/null; then
        die "This script should run outside WSL."
    fi
}

require_supported_ubuntu() {
    # shellcheck disable=SC1090
    source "${OS_RELEASE_FILE}"

    if [[ "${ID}" != "ubuntu" ]]; then
        die "This script should run on Ubuntu."
    fi

    case "${VERSION_ID}" in
        22.04 | 24.04)
            ;;
        *)
            die "This script should run on Ubuntu 22.04 or 24.04."
            ;;
    esac
}

confirm_execution() {
    local answer

    if [[ "${ASSUME_YES}" == "1" ]]; then
        return
    fi

    cat <<EOF
This script will:
  - install Hack Nerd Font
  - install and configure Samba share
  - install Google Chrome
  - enable and start SSH service
EOF

    printf "Continue? [y/N] "
    read -r answer
    if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
        die "Aborted by user."
    fi
}

install_apt_packages() {
    local packages=(
        curl
        unzip
        fontconfig
        samba
        cifs-utils
        samba-common
        openssh-server
    )

    info "Installing non-WSL desktop/server packages"
    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"
}

install_hack_font() {
    local temp_dir
    local font_zip

    if find "${FONT_DIR}" -maxdepth 1 -type f -name 'Hack*.ttf' 2>/dev/null | grep -q .; then
        warn "Hack font already exists, skipping install: ${FONT_DIR}"
        return
    fi

    info "Installing Hack Nerd Font"
    temp_dir="$(mktemp -d)"
    font_zip="${temp_dir}/Hack.zip"

    curl -fsSL "${HACK_FONT_URL}" -o "${font_zip}"
    unzip -q "${font_zip}" -d "${temp_dir}/Hack"
    mkdir -p "${FONT_DIR}"
    find "${temp_dir}/Hack" -type f -name 'Hack*.ttf' -exec cp {} "${FONT_DIR}/" \;
    fc-cache -f -v "${FONT_DIR}"
    rm -rf "${temp_dir}"
}

configure_samba() {
    info "Configuring Samba share"
    sudo mkdir -p "${SHARE_DIR}"
    sudo chmod 777 -R "${SHARE_DIR}"

    if [[ -f "${SAMBA_CONF}" ]] && grep -Fxq "[share]" "${SAMBA_CONF}"; then
        warn "Samba share block already exists, keeping it: ${SAMBA_CONF}"
    else
        sudo tee -a "${SAMBA_CONF}" >/dev/null <<EOF

[share]
    path = ${SHARE_DIR}
    available = yes
    browseable = yes
    public = no
    writable = yes
EOF
    fi

    if [[ "${SKIP_SMBPASSWD}" == "1" ]]; then
        warn "Skipping Samba password setup"
    else
        sudo smbpasswd -a "${USER}"
    fi

    sudo service smbd restart
}

install_chrome() {
    local chrome_deb
    local arch

    if command -v "${CHROME_COMMAND}" >/dev/null 2>&1; then
        warn "Google Chrome already exists, skipping install"
        return
    fi

    arch="$(dpkg --print-architecture)"
    if [[ "${arch}" != "amd64" ]]; then
        warn "Google Chrome only ships an amd64 package, skipping install on: ${arch}"
        return
    fi

    info "Installing Google Chrome"
    chrome_deb="$(mktemp --suffix=.deb)"
    curl -fsSL "${CHROME_DEB_URL}" -o "${chrome_deb}"
    sudo apt-get install -y "${chrome_deb}"
    rm -f "${chrome_deb}"
}

start_ssh_service() {
    info "Enabling and starting SSH service"
    sudo systemctl enable ssh
    sudo systemctl start ssh
}

main() {
    parse_args "$@"
    require_non_wsl
    require_supported_ubuntu
    confirm_execution

    install_apt_packages
    install_hack_font
    configure_samba
    install_chrome
    start_ssh_service

    success "Ubuntu non-WSL setup finished"
}

main "$@"
