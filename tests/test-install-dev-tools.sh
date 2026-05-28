#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/home"

cat >"${TMP_DIR}/bin/sudo" <<'STUB'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"${TEST_LOG}"

if [[ "$1" == "ln" ]]; then
    ln "$2" "$3" "$4"
fi
STUB
chmod +x "${TMP_DIR}/bin/sudo"

cat >"${TMP_DIR}/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"${TEST_LOG}"
while (($#)); do
    if [[ "$1" == "-o" ]]; then
        printf '# nodesource setup stub\n' >"$2"
        exit 0
    fi
    shift
done
STUB
chmod +x "${TMP_DIR}/bin/curl"

cat >"${TMP_DIR}/bin/git" <<'STUB'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >>"${TEST_LOG}"
STUB
chmod +x "${TMP_DIR}/bin/git"

cat >"${TMP_DIR}/bin/npm" <<'STUB'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >>"${TEST_LOG}"
STUB
chmod +x "${TMP_DIR}/bin/npm"

cat >"${TMP_DIR}/bin/pip3" <<'STUB'
#!/usr/bin/env bash
printf 'pip3 %s\n' "$*" >>"${TEST_LOG}"
STUB
chmod +x "${TMP_DIR}/bin/pip3"

cat >"${TMP_DIR}/bin/ssh-keygen" <<'STUB'
#!/usr/bin/env bash
printf 'ssh-keygen %s\n' "$*" >>"${TEST_LOG}"
while (($#)); do
    if [[ "$1" == "-f" ]]; then
        touch "$2" "$2.pub"
        exit 0
    fi
    shift
done
STUB
chmod +x "${TMP_DIR}/bin/ssh-keygen"

cat >"${TMP_DIR}/bin/mkdir" <<'STUB'
#!/usr/bin/env bash
printf 'mkdir %s\n' "$*" >>"${TEST_LOG}"
/usr/bin/mkdir "$@"
STUB
chmod +x "${TMP_DIR}/bin/mkdir"

export TEST_LOG="${TMP_DIR}/calls.log"
export HOME="${TMP_DIR}/home"
export PATH="${TMP_DIR}/bin:${PATH}"
export NO_COLOR=1
export UBUNTU_INIT_PYTHON_LINK="${TMP_DIR}/python"

touch "${TEST_LOG}"
"${ROOT_DIR}/scripts/install-dev-tools.sh" >"${TMP_DIR}/output.log"

expected="${TMP_DIR}/expected.log"
cat >"${expected}" <<'EOF'
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt-get update
sudo apt-get install -y python3-pip python3.12 python3.12-venv python3.10-venv aptitude build-essential libsystemd-dev lib32stdc++6 clangd ripgrep fd-find neofetch curl net-tools lcov bear tofrodos vim xclip ninja-build cmake openssh-server fzf autoconf universal-ctags
sudo ln -s python3.12 PYTHON_LINK
curl -fsSL https://deb.nodesource.com/setup_current.x -o NODE_SETUP
sudo -E bash NODE_SETUP
sudo apt-get install -y nodejs
mkdir -p HOME/.npm-global
npm config set prefix ~/.npm-global
npm install n -g
sudo n stable
npm install -g yarn
mkdir -p HOME/.ssh
ssh-keygen -t ed25519 -f HOME/.ssh/id_ed25519 -N 
git config --global core.excludesfile HOME/.gitignore_global
git config --global core.editor vim
git config --global core.autocrlf false
git config --global color.ui auto
git config --global credential.helper store
git config --global core.quotepath false
git config --global http.postBuffer 524288000
pip3 install pycryptodome
pip3 install ecdsa
pip3 install uv
EOF

sed -i "s|${UBUNTU_INIT_PYTHON_LINK}|PYTHON_LINK|g; s|${HOME}|HOME|g; s|/tmp/tmp\\.[^ ]*|NODE_SETUP|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"

[[ -d "${HOME}/.ssh" ]]
[[ -f "${HOME}/.ssh/authorized_keys" ]]
[[ -f "${HOME}/.ssh/id_ed25519" ]]
grep -Fx ".tags" "${HOME}/.gitignore_global" >/dev/null

: >"${TEST_LOG}"
"${ROOT_DIR}/scripts/install-dev-tools.sh" >"${TMP_DIR}/output-second.log"

if grep -F "sudo ln -s python3.12 PYTHON_LINK" "${TEST_LOG}" >/dev/null; then
    printf 'python symlink should not be recreated when it already exists\n' >&2
    exit 1
fi

if grep -F "ssh-keygen -t ed25519" "${TEST_LOG}" >/dev/null; then
    printf 'SSH key should not be regenerated when it already exists\n' >&2
    exit 1
fi

if [[ "$(grep -Fx ".tags" "${HOME}/.gitignore_global" | wc -l)" != "1" ]]; then
    printf '.tags should be present exactly once\n' >&2
    exit 1
fi
