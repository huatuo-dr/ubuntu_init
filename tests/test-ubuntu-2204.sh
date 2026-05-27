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
    cat >"${TEST_SOURCES_LIST}"
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

export TEST_LOG="${TMP_DIR}/calls.log"
export TEST_OUTPUT="${TMP_DIR}/output.log"
export TEST_SOURCES_LIST="${TMP_DIR}/sources.list"
export TEST_SOURCES_BACKUP="${TMP_DIR}/sources.list.bak"
export PATH="${TMP_DIR}/bin:${PATH}"
export NO_COLOR=1
export UBUNTU_INIT_DISABLE_SUDO_KEEPALIVE=1
export UBUNTU_INIT_APT_SOURCES_LIST="${TEST_SOURCES_LIST}"
export UBUNTU_INIT_DEV_TOOLS_SCRIPT="${TMP_DIR}/install-dev-tools.sh"
export UBUNTU_INIT_USER_TOOLS_SCRIPT="${TMP_DIR}/install-user-tools.sh"

printf 'original sources\n' >"${TEST_SOURCES_LIST}"

"${ROOT_DIR}/scripts/ubuntu-2204.sh" --yes >"${TEST_OUTPUT}"

expected="${TMP_DIR}/expected.log"
cat >"${expected}" <<'EOF'
sudo -v
sudo cp SOURCE_LIST SOURCE_LIST.bak
sudo tee SOURCE_LIST
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
install-dev-tools
install-user-tools
EOF

sed -i "s|${TEST_SOURCES_LIST}|SOURCE_LIST|g; s|${TEST_SOURCES_BACKUP}|SOURCE_LIST.bak|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"
diff -u <(printf 'original sources\n') "${TEST_SOURCES_BACKUP}"

grep -F "deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse" "${TEST_SOURCES_LIST}" >/dev/null
grep -F "deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse" "${TEST_SOURCES_LIST}" >/dev/null
grep -F "deb http://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse" "${TEST_SOURCES_LIST}" >/dev/null
grep -F "deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse" "${TEST_SOURCES_LIST}" >/dev/null

grep -F "[INFO] Requesting sudo permission" "${TEST_OUTPUT}" >/dev/null
grep -F "[INFO] Configuring Aliyun apt sources for Ubuntu 22.04" "${TEST_OUTPUT}" >/dev/null
grep -F "[INFO] Cleaning old apt cache" "${TEST_OUTPUT}" >/dev/null
grep -F "[INFO] Updating apt package lists" "${TEST_OUTPUT}" >/dev/null
grep -F "[INFO] Upgrading system packages" "${TEST_OUTPUT}" >/dev/null
grep -F "[OK] Ubuntu 22.04 WSL initialization finished" "${TEST_OUTPUT}" >/dev/null

if grep -q $'\033' "${TEST_OUTPUT}"; then
    printf 'NO_COLOR output should not contain ANSI color codes\n' >&2
    exit 1
fi

: >"${TEST_LOG}"
: >"${TEST_OUTPUT}"
rm -f "${TEST_SOURCES_BACKUP}"
printf 'original sources\n' >"${TEST_SOURCES_LIST}"

"${ROOT_DIR}/scripts/ubuntu-2204.sh" --yes --skip-upgrade --skip-user-tools >"${TEST_OUTPUT}"

cat >"${expected}" <<'EOF'
sudo -v
sudo cp SOURCE_LIST SOURCE_LIST.bak
sudo tee SOURCE_LIST
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
install-dev-tools
EOF

sed -i "s|${TEST_SOURCES_LIST}|SOURCE_LIST|g; s|${TEST_SOURCES_BACKUP}|SOURCE_LIST.bak|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"
grep -F "[WARN] Skipping system package upgrade" "${TEST_OUTPUT}" >/dev/null
grep -F "[WARN] Skipping user tools setup" "${TEST_OUTPUT}" >/dev/null

: >"${TEST_LOG}"
: >"${TEST_OUTPUT}"
rm -f "${TEST_SOURCES_BACKUP}"
printf 'original sources\n' >"${TEST_SOURCES_LIST}"

"${ROOT_DIR}/scripts/ubuntu-2204.sh" --yes --skip-dev-tools >"${TEST_OUTPUT}"

cat >"${expected}" <<'EOF'
sudo -v
sudo cp SOURCE_LIST SOURCE_LIST.bak
sudo tee SOURCE_LIST
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
install-user-tools
EOF

sed -i "s|${TEST_SOURCES_LIST}|SOURCE_LIST|g; s|${TEST_SOURCES_BACKUP}|SOURCE_LIST.bak|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"
grep -F "[WARN] Skipping development tools setup" "${TEST_OUTPUT}" >/dev/null

: >"${TEST_LOG}"
: >"${TEST_OUTPUT}"
printf 'original sources\n' >"${TEST_SOURCES_LIST}"
printf 'existing backup\n' >"${TEST_SOURCES_BACKUP}"

"${ROOT_DIR}/scripts/ubuntu-2204.sh" --yes --skip-upgrade --skip-dev-tools --skip-user-tools >"${TEST_OUTPUT}"

cat >"${expected}" <<'EOF'
sudo -v
sudo tee SOURCE_LIST
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update
EOF

sed -i "s|${TEST_SOURCES_LIST}|SOURCE_LIST|g; s|${TEST_SOURCES_BACKUP}|SOURCE_LIST.bak|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"
diff -u <(printf 'existing backup\n') "${TEST_SOURCES_BACKUP}"
grep -F "[WARN] Apt sources backup already exists, keeping it:" "${TEST_OUTPUT}" >/dev/null

: >"${TEST_LOG}"
: >"${TEST_OUTPUT}"

if printf 'n\n' | "${ROOT_DIR}/scripts/ubuntu-2204.sh" >"${TEST_OUTPUT}" 2>&1; then
    printf 'Expected confirmation rejection to fail\n' >&2
    exit 1
fi

if [[ -s "${TEST_LOG}" ]]; then
    printf 'Confirmation rejection should not run privileged commands\n' >&2
    exit 1
fi

grep -F "Continue? [y/N]" "${TEST_OUTPUT}" >/dev/null
grep -F "[ERROR] Aborted by user." "${TEST_OUTPUT}" >/dev/null
