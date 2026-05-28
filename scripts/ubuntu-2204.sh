#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly APT_SOURCES_LIST="${UBUNTU_INIT_APT_SOURCES_LIST:-/etc/apt/sources.list}"
readonly WSL_CONF="${UBUNTU_INIT_WSL_CONF:-/etc/wsl.conf}"
readonly DEV_TOOLS_SCRIPT="${UBUNTU_INIT_DEV_TOOLS_SCRIPT:-${SCRIPT_DIR}/install-dev-tools.sh}"
readonly USER_TOOLS_SCRIPT="${UBUNTU_INIT_USER_TOOLS_SCRIPT:-${SCRIPT_DIR}/install-user-tools.sh}"

ASSUME_YES=0
SKIP_UPGRADE=0
SKIP_DEV_TOOLS=0
SKIP_USER_TOOLS=0
SUDO_KEEPALIVE_PID=""

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
  --skip-upgrade    Skip system package upgrade.
  --skip-dev-tools  Skip development tools setup.
  --skip-user-tools Skip user tools setup.
  -h, --help        Show this help message.
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            -y | --yes)
                ASSUME_YES=1
                ;;
            --skip-upgrade)
                SKIP_UPGRADE=1
                ;;
            --skip-dev-tools)
                SKIP_DEV_TOOLS=1
                ;;
            --skip-user-tools)
                SKIP_USER_TOOLS=1
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

confirm_execution() {
    local answer

    if [[ "${ASSUME_YES}" == "1" ]]; then
        return
    fi

    cat <<EOF
This script will:
  - disable appending Windows PATH in WSL
  - configure Aliyun apt sources
  - clean apt cache and package lists
  - update apt package lists
  - upgrade installed system packages
  - run enabled setup scripts
EOF

    printf "Continue? [y/N] "
    read -r answer
    if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
        die "Aborted by user."
    fi
}

stop_sudo_keepalive() {
    if [[ -n "${SUDO_KEEPALIVE_PID}" ]]; then
        kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    fi
}

start_sudo_keepalive() {
    if [[ -n "${UBUNTU_INIT_DISABLE_SUDO_KEEPALIVE:-}" ]]; then
        return
    fi

    while true; do
        sudo -n true
        sleep 60
    done 2>/dev/null &
    SUDO_KEEPALIVE_PID="$!"
    trap stop_sudo_keepalive EXIT
}

configure_wsl_interop() {
    info "Configuring WSL interop"

    if [[ -f "${WSL_CONF}" ]] && grep -Fxq "appendWindowsPath = false" "${WSL_CONF}"; then
        warn "WSL Windows PATH interop is already disabled: ${WSL_CONF}"
        return
    fi

    {
        if [[ -f "${WSL_CONF}" ]]; then
            cat "${WSL_CONF}"
            printf "\n"
        fi
        printf "[interop]\n"
        printf "appendWindowsPath = false\n"
    } | sudo tee "${WSL_CONF}" >/dev/null
}

setup_apt_sources() {
    info "Configuring Aliyun apt sources for Ubuntu 22.04"

    if [[ -f "${APT_SOURCES_LIST}.bak" ]]; then
        warn "Apt sources backup already exists, keeping it: ${APT_SOURCES_LIST}.bak"
    else
        sudo cp "${APT_SOURCES_LIST}" "${APT_SOURCES_LIST}.bak"
    fi

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

install_system_build_packages() {
    local packages=(
        zlib1g-dev
        libbz2-dev
        libssl-dev
        libncurses5-dev
        libsqlite3-dev
        libreadline-dev
        tk-dev
        libgdbm-dev
        libdb-dev
        libpcap-dev
        xz-utils
        libexpat1-dev
        lib32ncurses5
        u-boot-tools
        mtd-utils
        scons
        libffi-dev
        zip
        lib32gcc1
        libc6-dev-i386
        libc6-i386
        libc6-dev
        liblzma-dev
        lib32z1
        libstdc++6
        libstdc++-11-dev
        gcc-multilib
        g++-multilib
        squashfs-tools
        bison
        bc
        flex
        kmod
        unzip
        p7zip-full
        rsync
        lzma
        imagemagick
        cpio
        lzop
        libboost-all-dev
    )

    info "Installing system build and embedded development packages"
    sudo apt-get install -y "${packages[@]}"
}

configure_user_groups() {
    info "Adding current user to dialout group"
    sudo usermod -a -G dialout "${USER}"
}

install_tree_sitter_cli() {
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm is not available, skipping tree-sitter-cli installation"
        return
    fi

    info "Installing tree-sitter-cli for Ubuntu 22.04"
    npm install -g tree-sitter-cli@0.22.6
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
    parse_args "$@"
    require_wsl
    require_ubuntu_2204
    confirm_execution

    info "Requesting sudo permission"
    sudo -v
    start_sudo_keepalive

    info "Ubuntu 22.04 WSL initialization starts"
    info "Script directory: ${SCRIPT_DIR}"

    configure_wsl_interop
    setup_apt_sources
    if [[ "${SKIP_UPGRADE}" == "1" ]]; then
        warn "Skipping system package upgrade"
    else
        upgrade_system_packages
    fi

    install_system_build_packages
    configure_user_groups

    if [[ "${SKIP_DEV_TOOLS}" == "1" ]]; then
        warn "Skipping development tools setup"
    else
        run_script "${DEV_TOOLS_SCRIPT}" "development tools setup"
    fi

    if [[ "${SKIP_USER_TOOLS}" == "1" ]]; then
        warn "Skipping user tools setup"
    else
        install_tree_sitter_cli
        run_script "${USER_TOOLS_SCRIPT}" "user tools setup"
    fi

    success "Ubuntu 22.04 WSL initialization finished"
}

main "$@"
