#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin"

cat >"${TMP_DIR}/bin/sudo" <<'STUB'
#!/usr/bin/env bash
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

cat >"${TMP_DIR}/install-zsh-nvim.sh" <<'STUB'
#!/usr/bin/env bash
printf 'install-zsh-nvim\n' >>"${TEST_LOG}"
STUB
chmod +x "${TMP_DIR}/install-zsh-nvim.sh"

export TEST_LOG="${TMP_DIR}/calls.log"
export TEST_SOURCES_LIST="${TMP_DIR}/sources.list"
export TEST_SOURCES_BACKUP="${TMP_DIR}/sources.list.bak"
export PATH="${TMP_DIR}/bin:${PATH}"
export UBUNTU_INIT_APT_SOURCES_LIST="${TEST_SOURCES_LIST}"
export UBUNTU_INIT_DEV_TOOLS_SCRIPT="${TMP_DIR}/install-dev-tools.sh"
export UBUNTU_INIT_ZSH_NVIM_SCRIPT="${TMP_DIR}/install-zsh-nvim.sh"

printf 'original sources\n' >"${TEST_SOURCES_LIST}"

"${ROOT_DIR}/scripts/ubuntu-2204.sh" >/dev/null

expected="${TMP_DIR}/expected.log"
cat >"${expected}" <<'EOF'
sudo -v
sudo cp SOURCE_LIST SOURCE_LIST.bak
sudo tee SOURCE_LIST
sudo apt-get update
install-dev-tools
install-zsh-nvim
EOF

sed -i "s|${TEST_SOURCES_LIST}|SOURCE_LIST|g; s|${TEST_SOURCES_BACKUP}|SOURCE_LIST.bak|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"
diff -u <(printf 'original sources\n') "${TEST_SOURCES_BACKUP}"

grep -F "deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse" "${TEST_SOURCES_LIST}" >/dev/null
grep -F "deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse" "${TEST_SOURCES_LIST}" >/dev/null
grep -F "deb http://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse" "${TEST_SOURCES_LIST}" >/dev/null
grep -F "deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse" "${TEST_SOURCES_LIST}" >/dev/null
