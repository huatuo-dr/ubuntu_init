#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"

cat >"${TMP_DIR}/bin/sudo" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "rm" && "$2" == "-rf" && "${3:-}" == /var/lib/apt/lists/* ]]; then
    printf 'sudo rm -rf /var/lib/apt/lists/*\n' >>"${TEST_LOG}"
    exit 0
fi

printf 'sudo %s\n' "$*" >>"${TEST_LOG}"

if [[ "$1" == "cp" ]]; then
    cp "$2" "${TEST_SOURCES_BACKUP}"
    exit 0
fi

if [[ "$1" == "tee" ]]; then
    if [[ "${2:-}" == "${TEST_WSL_CONF}" ]]; then
        cat >"${TEST_WSL_CONF}"
    else
        cat >"${TEST_SOURCES_FILE}"
    fi
    exit 0
fi

exit 0
STUB
chmod +x "${TMP_DIR}/bin/sudo"

cat >"${TMP_DIR}/install-dev-tools.sh" <<'STUB'
#!/usr/bin/env bash
printf 'install-dev-tools\n' >>"${TEST_LOG}"
STUB
chmod +x "${TMP_DIR}/install-dev-tools.sh"

cat >"${TMP_DIR}/install-user-tools.sh" <<'STUB'
#!/usr/bin/env bash
printf 'install-user-tools\n' >>"${TEST_LOG}"
STUB
chmod +x "${TMP_DIR}/install-user-tools.sh"

cat >"${TMP_DIR}/bin/npm" <<'STUB'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >>"${TEST_LOG}"
exit 0
STUB
chmod +x "${TMP_DIR}/bin/npm"

export TEST_LOG="${TMP_DIR}/calls.log"
export TEST_OUTPUT="${TMP_DIR}/output.log"
export TEST_OS_RELEASE="${TMP_DIR}/os-release"
export TEST_PROC_VERSION="${TMP_DIR}/proc-version"
export TEST_PROC_OSRELEASE="${TMP_DIR}/osrelease"
export TEST_SOURCES_FILE="${TMP_DIR}/ubuntu.sources"
export TEST_SOURCES_BACKUP="${TMP_DIR}/ubuntu.sources.bak"
export TEST_WSL_CONF="${TMP_DIR}/wsl.conf"
export PATH="${TMP_DIR}/bin:${PATH}"
export NO_COLOR=1
export UBUNTU_INIT_DISABLE_SUDO_KEEPALIVE=1
export UBUNTU_INIT_OS_RELEASE="${TEST_OS_RELEASE}"
export UBUNTU_INIT_PROC_VERSION="${TEST_PROC_VERSION}"
export UBUNTU_INIT_PROC_OSRELEASE="${TEST_PROC_OSRELEASE}"
export UBUNTU_INIT_APT_SOURCES_FILE="${TEST_SOURCES_FILE}"
export UBUNTU_INIT_WSL_CONF="${TEST_WSL_CONF}"
export UBUNTU_INIT_DEV_TOOLS_SCRIPT="${TMP_DIR}/install-dev-tools.sh"
export UBUNTU_INIT_USER_TOOLS_SCRIPT="${TMP_DIR}/install-user-tools.sh"

printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"${TEST_OS_RELEASE}"
printf 'Linux version Microsoft WSL\n' >"${TEST_PROC_VERSION}"
printf 'microsoft-standard-WSL2\n' >"${TEST_PROC_OSRELEASE}"
printf 'original sources\n' >"${TEST_SOURCES_FILE}"

"${ROOT_DIR}/scripts/ubuntu-2404.sh" --yes >"${TEST_OUTPUT}"

expected="${TMP_DIR}/expected.log"
cat >"${expected}" <<'EOF'
sudo -v
sudo tee WSL_CONF
sudo cp SOURCE_FILE SOURCE_FILE.bak
sudo tee SOURCE_FILE
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
sudo apt-get install -y zlib1g-dev libbz2-dev libssl-dev libncurses5-dev libsqlite3-dev libreadline-dev tk-dev libgdbm-dev libdb-dev libpcap-dev xz-utils libexpat1-dev lib32ncurses6 u-boot-tools mtd-utils scons libffi-dev zip lib32gcc-s1 libc6-dev-i386 libc6-i386 libc6-dev liblzma-dev lib32z1 libstdc++6 libstdc++-11-dev gcc-multilib g++-multilib squashfs-tools bison bc flex kmod unzip p7zip-full rsync lzma imagemagick cpio lzop libboost-all-dev
sudo usermod -a -G dialout USER_NAME
install-dev-tools
npm install -g tree-sitter-cli
install-user-tools
EOF

sed -i "s|${TEST_SOURCES_FILE}|SOURCE_FILE|g; s|${TEST_SOURCES_BACKUP}|SOURCE_FILE.bak|g; s|${TEST_WSL_CONF}|WSL_CONF|g; s|dialout ${USER}|dialout USER_NAME|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"
diff -u <(printf 'original sources\n') "${TEST_SOURCES_BACKUP}"
grep -F "[interop]" "${TEST_WSL_CONF}" >/dev/null
grep -F "appendWindowsPath = false" "${TEST_WSL_CONF}" >/dev/null

grep -F "Types: deb" "${TEST_SOURCES_FILE}" >/dev/null
grep -F "URIs: http://mirrors.aliyun.com/ubuntu/" "${TEST_SOURCES_FILE}" >/dev/null
grep -F "Suites: noble noble-updates noble-backports noble-security" "${TEST_SOURCES_FILE}" >/dev/null
grep -F "Components: main restricted universe multiverse" "${TEST_SOURCES_FILE}" >/dev/null
grep -F "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg" "${TEST_SOURCES_FILE}" >/dev/null

grep -F "[INFO] Requesting sudo permission" "${TEST_OUTPUT}" >/dev/null
grep -F "[INFO] Configuring Aliyun apt sources for Ubuntu 24.04" "${TEST_OUTPUT}" >/dev/null
grep -F "[INFO] Cleaning old apt cache" "${TEST_OUTPUT}" >/dev/null
grep -F "[INFO] Updating apt package lists" "${TEST_OUTPUT}" >/dev/null
grep -F "[INFO] Upgrading system packages" "${TEST_OUTPUT}" >/dev/null
grep -F "[OK] Ubuntu 24.04 WSL initialization finished" "${TEST_OUTPUT}" >/dev/null

if grep -q $'\033' "${TEST_OUTPUT}"; then
    printf 'NO_COLOR output should not contain ANSI color codes\n' >&2
    exit 1
fi

: >"${TEST_LOG}"
: >"${TEST_OUTPUT}"
rm -f "${TEST_SOURCES_BACKUP}"
printf 'original sources\n' >"${TEST_SOURCES_FILE}"

"${ROOT_DIR}/scripts/ubuntu-2404.sh" --yes --skip-upgrade --skip-user-tools >"${TEST_OUTPUT}"

cat >"${expected}" <<'EOF'
sudo -v
sudo cp SOURCE_FILE SOURCE_FILE.bak
sudo tee SOURCE_FILE
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
sudo apt-get install -y zlib1g-dev libbz2-dev libssl-dev libncurses5-dev libsqlite3-dev libreadline-dev tk-dev libgdbm-dev libdb-dev libpcap-dev xz-utils libexpat1-dev lib32ncurses6 u-boot-tools mtd-utils scons libffi-dev zip lib32gcc-s1 libc6-dev-i386 libc6-i386 libc6-dev liblzma-dev lib32z1 libstdc++6 libstdc++-11-dev gcc-multilib g++-multilib squashfs-tools bison bc flex kmod unzip p7zip-full rsync lzma imagemagick cpio lzop libboost-all-dev
sudo usermod -a -G dialout USER_NAME
install-dev-tools
EOF

sed -i "s|${TEST_SOURCES_FILE}|SOURCE_FILE|g; s|${TEST_SOURCES_BACKUP}|SOURCE_FILE.bak|g; s|${TEST_WSL_CONF}|WSL_CONF|g; s|dialout ${USER}|dialout USER_NAME|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"
grep -F "[WARN] Skipping system package upgrade" "${TEST_OUTPUT}" >/dev/null
grep -F "[WARN] Skipping user tools setup" "${TEST_OUTPUT}" >/dev/null

: >"${TEST_LOG}"
: >"${TEST_OUTPUT}"
rm -f "${TEST_SOURCES_BACKUP}"
printf 'original sources\n' >"${TEST_SOURCES_FILE}"

"${ROOT_DIR}/scripts/ubuntu-2404.sh" --yes --skip-dev-tools >"${TEST_OUTPUT}"

cat >"${expected}" <<'EOF'
sudo -v
sudo cp SOURCE_FILE SOURCE_FILE.bak
sudo tee SOURCE_FILE
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
sudo apt-get install -y zlib1g-dev libbz2-dev libssl-dev libncurses5-dev libsqlite3-dev libreadline-dev tk-dev libgdbm-dev libdb-dev libpcap-dev xz-utils libexpat1-dev lib32ncurses6 u-boot-tools mtd-utils scons libffi-dev zip lib32gcc-s1 libc6-dev-i386 libc6-i386 libc6-dev liblzma-dev lib32z1 libstdc++6 libstdc++-11-dev gcc-multilib g++-multilib squashfs-tools bison bc flex kmod unzip p7zip-full rsync lzma imagemagick cpio lzop libboost-all-dev
sudo usermod -a -G dialout USER_NAME
npm install -g tree-sitter-cli
install-user-tools
EOF

sed -i "s|${TEST_SOURCES_FILE}|SOURCE_FILE|g; s|${TEST_SOURCES_BACKUP}|SOURCE_FILE.bak|g; s|${TEST_WSL_CONF}|WSL_CONF|g; s|dialout ${USER}|dialout USER_NAME|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"
grep -F "[WARN] Skipping development tools setup" "${TEST_OUTPUT}" >/dev/null

: >"${TEST_LOG}"
: >"${TEST_OUTPUT}"
printf 'original sources\n' >"${TEST_SOURCES_FILE}"
printf 'existing backup\n' >"${TEST_SOURCES_BACKUP}"

"${ROOT_DIR}/scripts/ubuntu-2404.sh" --yes --skip-upgrade --skip-dev-tools --skip-user-tools >"${TEST_OUTPUT}"

cat >"${expected}" <<'EOF'
sudo -v
sudo tee SOURCE_FILE
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
sudo apt-get install -y zlib1g-dev libbz2-dev libssl-dev libncurses5-dev libsqlite3-dev libreadline-dev tk-dev libgdbm-dev libdb-dev libpcap-dev xz-utils libexpat1-dev lib32ncurses6 u-boot-tools mtd-utils scons libffi-dev zip lib32gcc-s1 libc6-dev-i386 libc6-i386 libc6-dev liblzma-dev lib32z1 libstdc++6 libstdc++-11-dev gcc-multilib g++-multilib squashfs-tools bison bc flex kmod unzip p7zip-full rsync lzma imagemagick cpio lzop libboost-all-dev
sudo usermod -a -G dialout USER_NAME
EOF

sed -i "s|${TEST_SOURCES_FILE}|SOURCE_FILE|g; s|${TEST_SOURCES_BACKUP}|SOURCE_FILE.bak|g; s|${TEST_WSL_CONF}|WSL_CONF|g; s|dialout ${USER}|dialout USER_NAME|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"
diff -u <(printf 'existing backup\n') "${TEST_SOURCES_BACKUP}"
grep -F "[WARN] Apt sources backup already exists, keeping it:" "${TEST_OUTPUT}" >/dev/null

: >"${TEST_LOG}"
: >"${TEST_OUTPUT}"

if printf 'n\n' | "${ROOT_DIR}/scripts/ubuntu-2404.sh" >"${TEST_OUTPUT}" 2>&1; then
    printf 'Expected confirmation rejection to fail\n' >&2
    exit 1
fi

if [[ -s "${TEST_LOG}" ]]; then
    printf 'Confirmation rejection should not run privileged commands\n' >&2
    exit 1
fi

grep -F "Continue? [y/N]" "${TEST_OUTPUT}" >/dev/null
grep -F "[ERROR] Aborted by user." "${TEST_OUTPUT}" >/dev/null

: >"${TEST_LOG}"
: >"${TEST_OUTPUT}"
rm -f "${TEST_SOURCES_BACKUP}" "${TEST_WSL_CONF}"
printf 'Linux version generic\n' >"${TEST_PROC_VERSION}"
printf 'generic\n' >"${TEST_PROC_OSRELEASE}"
printf 'original sources\n' >"${TEST_SOURCES_FILE}"

"${ROOT_DIR}/scripts/ubuntu-2404.sh" --yes --skip-upgrade --skip-dev-tools --skip-user-tools >"${TEST_OUTPUT}"

cat >"${expected}" <<'EOF'
sudo -v
sudo cp SOURCE_FILE SOURCE_FILE.bak
sudo tee SOURCE_FILE
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
sudo apt-get install -y zlib1g-dev libbz2-dev libssl-dev libncurses5-dev libsqlite3-dev libreadline-dev tk-dev libgdbm-dev libdb-dev libpcap-dev xz-utils libexpat1-dev lib32ncurses6 u-boot-tools mtd-utils scons libffi-dev zip lib32gcc-s1 libc6-dev-i386 libc6-i386 libc6-dev liblzma-dev lib32z1 libstdc++6 libstdc++-11-dev gcc-multilib g++-multilib squashfs-tools bison bc flex kmod unzip p7zip-full rsync lzma imagemagick cpio lzop libboost-all-dev
sudo usermod -a -G dialout USER_NAME
EOF

sed -i "s|${TEST_SOURCES_FILE}|SOURCE_FILE|g; s|${TEST_SOURCES_BACKUP}|SOURCE_FILE.bak|g; s|${TEST_WSL_CONF}|WSL_CONF|g; s|dialout ${USER}|dialout USER_NAME|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"
[[ ! -f "${TEST_WSL_CONF}" ]]
grep -F "[WARN] Non-WSL environment detected, skipping WSL interop configuration" "${TEST_OUTPUT}" >/dev/null
