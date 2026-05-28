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

if [[ "$1" == "install" && "$2" == "-m" && "$4" == "-d" ]]; then
    /usr/bin/mkdir -p "$5"
fi

if [[ "$1" == "install" && "$2" == "-m" && "$4" != "-d" ]]; then
    cp "$4" "$5"
fi

if [[ "$1" == "tee" ]]; then
    cat >"$2"
fi

if [[ "$1" == "rm" && "$2" == "-f" ]]; then
    rm -f "$3"
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
printf '# bazelisk setup stub\n'
STUB
chmod +x "${TMP_DIR}/bin/curl"

cat >"${TMP_DIR}/bin/gpg" <<'STUB'
#!/usr/bin/env bash
printf 'gpg %s\n' "$*" >>"${TEST_LOG}"
while (($#)); do
    if [[ "$1" == "-o" ]]; then
        printf 'keyring stub\n' >"$2"
        exit 0
    fi
    shift
done
STUB
chmod +x "${TMP_DIR}/bin/gpg"

cat >"${TMP_DIR}/bin/dpkg" <<'STUB'
#!/usr/bin/env bash
printf 'dpkg %s\n' "$*" >>"${TEST_LOG}"
printf 'amd64\n'
STUB
chmod +x "${TMP_DIR}/bin/dpkg"

cat >"${TMP_DIR}/bin/lsb_release" <<'STUB'
#!/usr/bin/env bash
printf 'lsb_release %s\n' "$*" >>"${TEST_LOG}"
printf 'jammy\n'
STUB
chmod +x "${TMP_DIR}/bin/lsb_release"

cat >"${TMP_DIR}/bin/git" <<'STUB'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >>"${TEST_LOG}"
STUB
chmod +x "${TMP_DIR}/bin/git"

cat >"${TMP_DIR}/bin/git-lfs" <<'STUB'
#!/usr/bin/env bash
printf 'git-lfs %s\n' "$*" >>"${TEST_LOG}"
STUB
chmod +x "${TMP_DIR}/bin/git-lfs"

cat >"${TMP_DIR}/bin/npm" <<'STUB'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >>"${TEST_LOG}"
if [[ "$*" == "install n -g" ]]; then
    /usr/bin/mkdir -p "${HOME}/.npm-global/bin"
    cat >"${HOME}/.npm-global/bin/n" <<'NSTUB'
#!/usr/bin/env bash
printf '%s %s\n' "$0" "$*" >>"${TEST_LOG}"
NSTUB
    chmod +x "${HOME}/.npm-global/bin/n"
fi
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
export UBUNTU_INIT_DOCKER_KEYRING="${TMP_DIR}/keyrings/docker.gpg"
export UBUNTU_INIT_DOCKER_SOURCE_LIST="${TMP_DIR}/sources/docker.list"
export UBUNTU_INIT_DOCKER_DAEMON_JSON="${TMP_DIR}/docker/daemon.json"
export UBUNTU_INIT_BAZELISK_BIN="${TMP_DIR}/bin/bazelisk"
export UBUNTU_INIT_BAZEL_BIN="${TMP_DIR}/bin/bazel"
export UBUNTU_INIT_POLICY_RC_D="${TMP_DIR}/policy-rc.d"

touch "${TEST_LOG}"
"${ROOT_DIR}/scripts/install-dev-tools.sh" >"${TMP_DIR}/output.log"

expected="${TMP_DIR}/expected.log"
cat >"${expected}" <<'EOF'
sudo tee POLICY_RC_D
sudo chmod +x POLICY_RC_D
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt-get update
sudo apt-get install -y python3-pip python3.12 python3.12-venv python3.10-venv aptitude build-essential libsystemd-dev lib32stdc++6 clangd ripgrep fd-find neofetch curl gnupg net-tools lcov bear tofrodos vim xclip ninja-build cmake openssh-server fzf autoconf universal-ctags git-lfs
sudo rm -f POLICY_RC_D
sudo ln -s python3.12 PYTHON_LINK
curl -fsSL https://deb.nodesource.com/setup_current.x -o NODE_SETUP
sudo -E bash NODE_SETUP
sudo apt-get install -y nodejs
mkdir -p HOME/.npm-global
npm config set prefix ~/.npm-global
npm install n -g
mkdir -p HOME/.local
HOME/.npm-global/bin/n stable
npm install -g yarn
dpkg --print-architecture
curl -fsSL https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64 -o BAZELISK_BIN_TMP
sudo install -m 0755 BAZELISK_BIN_TMP BAZELISK_BIN
sudo ln -s BAZELISK_BIN BAZEL_BIN
sudo apt-get remove -y docker docker-engine docker.io containerd runc docker-compose docker-compose-plugin
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release
sudo install -m 0755 -d DOCKER_KEYRING_DIR
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o DOCKER_GPG_KEY
gpg --dearmor -o DOCKER_KEYRING_TMP DOCKER_GPG_KEY
sudo install -m 0644 DOCKER_KEYRING_TMP DOCKER_KEYRING
sudo chmod a+r DOCKER_KEYRING
dpkg --print-architecture
lsb_release -cs
sudo install -m 0755 -d DOCKER_SOURCE_DIR
sudo tee DOCKER_SOURCE_LIST
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker TEST_USER
sudo install -m 0755 -d DOCKER_DAEMON_DIR
sudo tee DOCKER_DAEMON_JSON
sudo systemctl daemon-reload
sudo systemctl restart docker
mkdir -p HOME/.ssh
ssh-keygen -t ed25519 -f HOME/.ssh/id_ed25519 -N 
ssh-keygen -t rsa -b 4096 -f HOME/.ssh/id_rsa -N 
git config --global core.excludesfile HOME/.gitignore_global
git config --global core.editor vim
git config --global core.autocrlf false
git config --global color.ui auto
git config --global credential.helper store
git config --global core.quotepath false
git config --global http.postBuffer 524288000
git lfs install
pip3 install pycryptodome
pip3 install ecdsa
pip3 install uv
EOF

sed -i "s|${UBUNTU_INIT_PYTHON_LINK}|PYTHON_LINK|g; s|${HOME}|HOME|g" "${TEST_LOG}"
sed -i "s|${UBUNTU_INIT_DOCKER_SOURCE_LIST}|DOCKER_SOURCE_LIST|g; s|$(dirname "${UBUNTU_INIT_DOCKER_SOURCE_LIST}")|DOCKER_SOURCE_DIR|g" "${TEST_LOG}"
sed -i "s|${UBUNTU_INIT_DOCKER_DAEMON_JSON}|DOCKER_DAEMON_JSON|g; s|$(dirname "${UBUNTU_INIT_DOCKER_DAEMON_JSON}")|DOCKER_DAEMON_DIR|g" "${TEST_LOG}"
sed -i "s|${UBUNTU_INIT_DOCKER_KEYRING}|DOCKER_KEYRING|g; s|$(dirname "${UBUNTU_INIT_DOCKER_KEYRING}")|DOCKER_KEYRING_DIR|g" "${TEST_LOG}"
sed -i "s|${UBUNTU_INIT_BAZELISK_BIN}|BAZELISK_BIN|g; s|${UBUNTU_INIT_BAZEL_BIN}|BAZEL_BIN|g" "${TEST_LOG}"
sed -i "s|${UBUNTU_INIT_POLICY_RC_D}|POLICY_RC_D|g" "${TEST_LOG}"
sed -i "s|${USER}|TEST_USER|g" "${TEST_LOG}"
sed -i -E 's|(https://deb.nodesource.com/setup_current.x -o )/tmp/tmp\.[^ ]+|\1NODE_SETUP|g' "${TEST_LOG}"
sed -i -E 's|(https://github.com/bazelbuild/bazelisk/releases/latest/download/bazelisk-linux-amd64 -o )/tmp/tmp\.[^ ]+|\1BAZELISK_BIN_TMP|g' "${TEST_LOG}"
sed -i -E 's|sudo install -m 0755 /tmp/tmp\.[^ ]+ BAZELISK_BIN|sudo install -m 0755 BAZELISK_BIN_TMP BAZELISK_BIN|g' "${TEST_LOG}"
sed -i -E 's|(https://download.docker.com/linux/ubuntu/gpg -o )/tmp/tmp\.[^ ]+|\1DOCKER_GPG_KEY|g' "${TEST_LOG}"
sed -i -E 's|gpg --dearmor -o /tmp/tmp\.[^ ]+ /tmp/tmp\.[^ ]+|gpg --dearmor -o DOCKER_KEYRING_TMP DOCKER_GPG_KEY|g' "${TEST_LOG}"
sed -i -E 's|sudo install -m 0644 /tmp/tmp\.[^ ]+ DOCKER_KEYRING|sudo install -m 0644 DOCKER_KEYRING_TMP DOCKER_KEYRING|g' "${TEST_LOG}"
sed -i -E 's|sudo -E bash /tmp/tmp\.[^ ]+|sudo -E bash NODE_SETUP|g' "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"

[[ -d "${HOME}/.ssh" ]]
[[ -f "${HOME}/.ssh/authorized_keys" ]]
[[ -f "${HOME}/.ssh/id_ed25519" ]]
[[ -f "${HOME}/.ssh/id_rsa" ]]
grep -F "https://mirrors.aliyun.com/docker-ce/linux/ubuntu jammy stable" "${UBUNTU_INIT_DOCKER_SOURCE_LIST}" >/dev/null
grep -F "https://mirror.aliyuncs.com" "${UBUNTU_INIT_DOCKER_DAEMON_JSON}" >/dev/null
[[ ! -e "${UBUNTU_INIT_POLICY_RC_D}" ]]
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

if grep -F "ssh-keygen -t rsa" "${TEST_LOG}" >/dev/null; then
    printf 'RSA SSH key should not be regenerated when it already exists\n' >&2
    exit 1
fi

if [[ "$(grep -Fx ".tags" "${HOME}/.gitignore_global" | wc -l)" != "1" ]]; then
    printf '.tags should be present exactly once\n' >&2
    exit 1
fi
