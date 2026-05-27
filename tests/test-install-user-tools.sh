#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${TMP_DIR}/bin" "${TMP_DIR}/home"

cat >"${TMP_DIR}/bin/curl" <<'STUB'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"${TEST_LOG}"
case "$*" in
    *debian.griffo.io*)
        while (($#)); do
            if [[ "$1" == "-o" ]]; then
                printf 'yazi repo key\n' >"$2"
                exit 0
            fi
            shift
        done
        printf 'yazi repo key\n'
        ;;
    *api.github.com/repos/jesseduffield/lazygit/releases/latest*)
        printf '{"tag_name":"v0.44.1"}\n'
        ;;
    *)
        printf '# curl stub\n'
        ;;
esac
STUB
chmod +x "${TMP_DIR}/bin/curl"

cat >"${TMP_DIR}/bin/gpg" <<'STUB'
#!/usr/bin/env bash
printf 'gpg %s\n' "$*" >>"${TEST_LOG}"
while (($#)); do
    if [[ "$1" == "-o" ]]; then
        printf 'dearmored key\n' >"$2"
        exit 0
    fi
    shift
done
STUB
chmod +x "${TMP_DIR}/bin/gpg"

cat >"${TMP_DIR}/bin/lsb_release" <<'STUB'
#!/usr/bin/env bash
printf 'jammy\n'
STUB
chmod +x "${TMP_DIR}/bin/lsb_release"

cat >"${TMP_DIR}/bin/sudo" <<'STUB'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"${TEST_LOG}"

if [[ "$1" == "tee" ]]; then
    cat >"${TEST_YAZI_SOURCE_LIST}"
fi

if [[ "$1" == "install" ]]; then
    cp "$2" "${TMP_DIR}/installed-lazygit"
fi
STUB
chmod +x "${TMP_DIR}/bin/sudo"

cat >"${TMP_DIR}/bin/git" <<'STUB'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >>"${TEST_LOG}"
if [[ "$1" == "clone" ]]; then
    mkdir -p "${@: -1}"
fi
STUB
chmod +x "${TMP_DIR}/bin/git"

cat >"${TMP_DIR}/bin/tar" <<'STUB'
#!/usr/bin/env bash
printf 'tar %s\n' "$*" >>"${TEST_LOG}"
touch lazygit
STUB
chmod +x "${TMP_DIR}/bin/tar"

cat >"${TMP_DIR}/bin/yarn" <<'STUB'
#!/usr/bin/env bash
printf 'yarn %s\n' "$*" >>"${TEST_LOG}"
STUB
chmod +x "${TMP_DIR}/bin/yarn"

export TEST_LOG="${TMP_DIR}/calls.log"
export TMP_DIR
export HOME="${TMP_DIR}/home"
export TEST_YAZI_KEYRING="${TMP_DIR}/debian.griffo.io.gpg"
export TEST_YAZI_SOURCE_LIST="${TMP_DIR}/debian.griffo.io.list"
export PATH="${TMP_DIR}/bin:${PATH}"
export NO_COLOR=1
export UBUNTU_INIT_YAZI_KEYRING="${TEST_YAZI_KEYRING}"
export UBUNTU_INIT_YAZI_SOURCE_LIST="${TEST_YAZI_SOURCE_LIST}"
export UBUNTU_INIT_NVIM_CONFIG_REPO="https://github.com/example/nvim.git"
export UBUNTU_INIT_LAZYGIT_COMMAND="test-lazygit"

touch "${TEST_LOG}"
"${ROOT_DIR}/scripts/install-user-tools.sh" >"${TMP_DIR}/output.log"

expected="${TMP_DIR}/expected.log"
cat >"${expected}" <<'EOF'
curl -sS https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc -o YAZI_KEY
gpg --dearmor --yes -o YAZI_KEYRING YAZI_KEY
sudo tee YAZI_SOURCE_LIST
sudo apt-get update
sudo apt-get install -y yazi file ffmpeg jq poppler-utils p7zip-full zoxide
sudo apt-get install -y zsh powerline tmux neovim git
curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh
git clone https://github.com/zsh-users/zsh-autosuggestions HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git HOME/.oh-my-zsh/custom/themes/powerlevel10k
git clone https://github.com/KyleDeng/tmux.conf HOME/.cache/ubuntu-init/tmux.conf
curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest
curl -Lo lazygit.tar.gz https://github.com/jesseduffield/lazygit/releases/download/v0.44.1/lazygit_0.44.1_Linux_x86_64.tar.gz
tar xf lazygit.tar.gz lazygit
sudo install lazygit -D -t /usr/local/bin/
git clone https://github.com/example/nvim.git HOME/.config/nvim
EOF

sed -i "s|${TEST_YAZI_KEYRING}|YAZI_KEYRING|g; s|${TEST_YAZI_SOURCE_LIST}|YAZI_SOURCE_LIST|g; s|${HOME}|HOME|g; s|/tmp/tmp\\.[^ ]*|YAZI_KEY|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"
grep -F "deb https://debian.griffo.io/apt jammy main" "${TEST_YAZI_SOURCE_LIST}" >/dev/null
grep -F "[OK] User tools setup finished" "${TMP_DIR}/output.log" >/dev/null
grep -F 'export PATH=$PATH:$HOME/.local/bin/' "${HOME}/.zshrc" >/dev/null
grep -F 'alias lg="lazygit"' "${HOME}/.zshrc" >/dev/null
grep -F 'ZSH_THEME="powerlevel10k/powerlevel10k"' "${HOME}/.zshrc" >/dev/null
grep -F 'plugins=(git z zsh-syntax-highlighting zsh-autosuggestions)' "${HOME}/.zshrc" >/dev/null

printf 'local tmux config\n' >"${HOME}/.tmux.conf"

cat >"${TMP_DIR}/bin/test-lazygit" <<'STUB'
#!/usr/bin/env bash
printf 'lazygit version stub\n'
STUB
chmod +x "${TMP_DIR}/bin/test-lazygit"

: >"${TEST_LOG}"
"${ROOT_DIR}/scripts/install-user-tools.sh" >"${TMP_DIR}/output-second.log"

cat >"${expected}" <<'EOF'
sudo apt-get update
sudo apt-get install -y yazi file ffmpeg jq poppler-utils p7zip-full zoxide
sudo apt-get install -y zsh powerline tmux neovim git
EOF

sed -i "s|${TEST_YAZI_KEYRING}|YAZI_KEYRING|g; s|${TEST_YAZI_SOURCE_LIST}|YAZI_SOURCE_LIST|g; s|${HOME}|HOME|g" "${TEST_LOG}"
diff -u "${expected}" "${TEST_LOG}"
grep -F "[WARN] Yazi repository key already exists, keeping it:" "${TMP_DIR}/output-second.log" >/dev/null
grep -F "[WARN] Yazi repository source already exists, keeping it:" "${TMP_DIR}/output-second.log" >/dev/null
grep -F "[WARN] oh-my-zsh already exists, keeping it:" "${TMP_DIR}/output-second.log" >/dev/null
grep -F "[WARN] lazygit already exists, skipping install" "${TMP_DIR}/output-second.log" >/dev/null
grep -F "[WARN] tmux config already exists, keeping it:" "${TMP_DIR}/output-second.log" >/dev/null
diff -u <(printf 'local tmux config\n') "${HOME}/.tmux.conf"

if [[ "$(grep -Fx 'alias lg="lazygit"' "${HOME}/.zshrc" | wc -l)" != "1" ]]; then
    printf 'lazygit alias should be present exactly once\n' >&2
    exit 1
fi
