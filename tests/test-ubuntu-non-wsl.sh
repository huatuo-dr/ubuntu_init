#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/home"

cat >"${TMP_DIR}/bin/sudo" <<'STUB'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"${TEST_LOG}"

if [[ "$1" == "mkdir" ]]; then
    shift
    /usr/bin/mkdir "$@"
fi

if [[ "$1" == "chmod" ]]; then
    shift
    /usr/bin/chmod "$@"
fi

if [[ "$1" == "tee" && "${2:-}" == "-a" ]]; then
    cat >>"$3"
elif [[ "$1" == "tee" ]]; then
    cat >"$2"
fi
STUB
chmod +x "${TMP_DIR}/bin/sudo"

cat >"${TMP_DIR}/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"${TEST_LOG}"
while (($#)); do
    if [[ "$1" == "-o" ]]; then
        printf 'downloaded file\n' >"$2"
        exit 0
    fi
    shift
done
STUB
chmod +x "${TMP_DIR}/bin/curl"

cat >"${TMP_DIR}/bin/unzip" <<'STUB'
#!/usr/bin/env bash
printf 'unzip %s\n' "$*" >>"${TEST_LOG}"
while (($#)); do
    if [[ "$1" == "-d" ]]; then
        /usr/bin/mkdir -p "$2"
        printf 'font stub\n' >"$2/HackNerdFont-Regular.ttf"
        exit 0
    fi
    shift
done
STUB
chmod +x "${TMP_DIR}/bin/unzip"

cat >"${TMP_DIR}/bin/fc-cache" <<'STUB'
#!/usr/bin/env bash
printf 'fc-cache %s\n' "$*" >>"${TEST_LOG}"
STUB
chmod +x "${TMP_DIR}/bin/fc-cache"

export TEST_LOG="${TMP_DIR}/calls.log"
export TEST_OUTPUT="${TMP_DIR}/output.log"
export HOME="${TMP_DIR}/home"
export PATH="${TMP_DIR}/bin:${PATH}"
export NO_COLOR=1
export UBUNTU_INIT_OS_RELEASE="${TMP_DIR}/os-release"
export UBUNTU_INIT_PROC_VERSION="${TMP_DIR}/proc-version"
export UBUNTU_INIT_SAMBA_CONF="${TMP_DIR}/smb.conf"
export UBUNTU_INIT_SHARE_DIR="${TMP_DIR}/share"
export UBUNTU_INIT_FONT_DIR="${TMP_DIR}/fonts"
export UBUNTU_INIT_CHROME_COMMAND="test-google-chrome"

printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"${UBUNTU_INIT_OS_RELEASE}"
printf 'Linux version generic\n' >"${UBUNTU_INIT_PROC_VERSION}"
touch "${UBUNTU_INIT_SAMBA_CONF}" "${TEST_LOG}"

"${ROOT_DIR}/scripts/ubuntu-non-wsl.sh" --yes >"${TEST_OUTPUT}"

expected="${TMP_DIR}/expected.log"
cat >"${expected}" <<'EOF'
sudo apt-get update
sudo apt-get install -y curl unzip fontconfig samba cifs-utils samba-common openssh-server
curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/Hack.zip -o HACK_ZIP
unzip -q HACK_ZIP -d HACK_DIR
fc-cache -f -v FONT_DIR
sudo mkdir -p SHARE_DIR
sudo chmod 777 -R SHARE_DIR
sudo tee -a SAMBA_CONF
sudo smbpasswd -a USER_NAME
sudo service smbd restart
curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o CHROME_DEB
sudo apt-get install -y CHROME_DEB
sudo systemctl enable ssh
sudo systemctl start ssh
EOF

sed -i "s|${UBUNTU_INIT_SHARE_DIR}|SHARE_DIR|g; s|${UBUNTU_INIT_SAMBA_CONF}|SAMBA_CONF|g; s|${UBUNTU_INIT_FONT_DIR}|FONT_DIR|g; s|${USER}|USER_NAME|g" "${TEST_LOG}"
sed -i -E 's|(Hack.zip -o )/tmp/tmp\.[^ ]+/Hack.zip|\1HACK_ZIP|g' "${TEST_LOG}"
sed -i -E 's|(unzip -q )/tmp/tmp\.[^ ]+/Hack.zip -d /tmp/tmp\.[^ ]+|\1HACK_ZIP -d HACK_DIR|g' "${TEST_LOG}"
sed -i -E 's|(google-chrome-stable_current_amd64.deb -o )/tmp/tmp\.[^ ]+\.deb|\1CHROME_DEB|g' "${TEST_LOG}"
sed -i -E 's|sudo apt-get install -y /tmp/tmp\.[^ ]+\.deb|sudo apt-get install -y CHROME_DEB|g' "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"

grep -F "[share]" "${UBUNTU_INIT_SAMBA_CONF}" >/dev/null
grep -F "path = ${UBUNTU_INIT_SHARE_DIR}" "${UBUNTU_INIT_SAMBA_CONF}" >/dev/null
[[ -f "${UBUNTU_INIT_FONT_DIR}/HackNerdFont-Regular.ttf" ]]

: >"${TEST_LOG}"
"${ROOT_DIR}/scripts/ubuntu-non-wsl.sh" --yes --skip-smbpasswd >"${TMP_DIR}/output-second.log"

if grep -F "sudo tee -a SAMBA_CONF" "${TEST_LOG}" >/dev/null; then
    printf 'Samba share block should not be appended twice\n' >&2
    exit 1
fi

if grep -F "sudo smbpasswd -a" "${TEST_LOG}" >/dev/null; then
    printf 'smbpasswd should be skipped with --skip-smbpasswd\n' >&2
    exit 1
fi

if [[ "$(grep -Fx "[share]" "${UBUNTU_INIT_SAMBA_CONF}" | wc -l)" != "1" ]]; then
    printf 'Samba share block should be present exactly once\n' >&2
    exit 1
fi
