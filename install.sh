#!/usr/bin/env bash
# =============================================================================
# buysg bootstrap installer (macOS / Linux) - compiled-lib edition
#
#   curl -fsSL https://raw.githubusercontent.com/kyle2207/buysg-installer/main/install.sh | bash
#
# POSIX sibling of install.ps1. Same flow, same pinned SDK URLs:
#   1. Detect OS/arch -> wheel platform tags (SDK tag + core-wheel match)
#   2. Ensure Python 3.12 (auto-install: brew on macOS, apt/dnf/pyenv on Linux)
#   3. Download the compiled core wheel from the repo's latest GitHub Release
#   4. Download broker SDKs from the brokers' OFFICIAL sites (unzip fubon)
#   5. venv + pip install everything (deps from PyPI)
#   6. Create the buysg command (~/.local/bin); user data in
#      ${XDG_DATA_HOME:-~/.local/share}/buysg/home (config auto-generated)
#   7. Run "buysg doctor"
#
# Commands: buysg / login / preview / balance / cancel / accounts / doctor / update / uninstall / help
# NOTE: keep install.ps1 and install.sh in sync (same versions / URLs / flow).
# =============================================================================
set -euo pipefail

REPO='kyle2207/buysg-installer'
REPO_API="https://api.github.com/repos/${REPO}"
RAW_INSTALL="https://raw.githubusercontent.com/${REPO}/main/install.sh"

ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/buysg"
HOME2="$ROOT/home"
VENV="$ROOT/venv"
WHEELS="$ROOT/wheels"
BIN_DIR="$HOME/.local/bin"          # conventionally on PATH; buysg symlink lands here

ESUN_BASE='https://www.esunsec.com.tw/trading-platforms/api-trading/binary-packages'
FUBON_BASE='https://www.fbs.com.tw/TradeAPI_SDK/fubon_binary'

step() { printf '\033[36m==> %s\033[0m\n' "$1"; }
info() { printf '    %s\n' "$1"; }
fail() { printf '\033[31m[ERROR] %s\033[0m\n' "$1" >&2; exit 1; }

# --- 1. platform detection --------------------------------------------------------
# Sets: OS (macos|linux), ARCH (x86_64|arm64), SDK_TAG (broker wheel platform tag),
#       CORE_OS / CORE_ARCH (substrings to match the buysg core-wheel release asset).
detect_platform() {
    local s m
    s="$(uname -s)"
    m="$(uname -m)"
    case "$s" in
        Darwin) OS='macos' ;;
        Linux)  OS='linux' ;;
        *)      fail "unsupported OS '$s' (buysg supports macOS and Linux here; Windows uses install.ps1)" ;;
    esac
    case "$m" in
        x86_64|amd64) ARCH='x86_64' ;;
        arm64|aarch64) ARCH='arm64' ;;
        *) fail "unsupported CPU arch '$m'" ;;
    esac
    # broker SDK wheel platform tag (must match the pinned catalog below).
    # Intel Mac (macos/x86_64) intentionally unsupported -- fail fast here to match the
    # core-wheel CI (release_core.yml builds win_amd64 / linux_x86_64 / macosx_arm64 only),
    # instead of proceeding to install Python + download SDKs then dying at the core-wheel step.
    if [ "$OS" = 'linux' ] && [ "$ARCH" = 'x86_64' ]; then
        SDK_TAG='manylinux_2_17_x86_64.manylinux2014_x86_64'; CORE_OS='linux'; CORE_ARCH='x86_64'
    elif [ "$OS" = 'macos' ] && [ "$ARCH" = 'arm64' ]; then
        SDK_TAG='macosx_11_0_arm64'; CORE_OS='macosx'; CORE_ARCH='arm64'
    else
        fail "unsupported platform $OS/$ARCH -- install.sh supports Linux x86_64 and macOS Apple Silicon (arm64) only (Intel Mac and Linux ARM are not built; see release_core.yml). Windows: use install.ps1."
    fi
}

# broker SDK download list for the detected platform (echoes "name url" per line).
# Mirror of install.ps1 $SdkCatalog. E.SUN 2.2.0 (.whl), Fubon 2.2.8 (.zip -> one .whl).
sdk_catalog() {
    local tag="$SDK_TAG"
    echo "esun_trade-2.2.0-cp37-abi3-${tag}.whl ${ESUN_BASE}/esun_trade-2.2.0-cp37-abi3-${tag}.whl"
    echo "esun_marketdata-2.2.0-cp37-abi3-${tag}.whl ${ESUN_BASE}/esun_marketdata-2.2.0-cp37-abi3-${tag}.whl"
    echo "fubon_neo-2.2.8-cp37-abi3-${tag}.zip ${FUBON_BASE}/fubon_neo-2.2.8-cp37-abi3-${tag}.zip"
}

# --- 2. Python 3.12 ---------------------------------------------------------------
find_py312() {
    local cand ver
    for cand in python3.12 python3; do
        if command -v "$cand" >/dev/null 2>&1; then
            ver="$("$cand" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null || true)"
            if [ "$ver" = '3.12' ]; then PY="$cand"; return 0; fi
        fi
    done
    return 1
}

ensure_python() {
    step "Checking Python 3.12 (required: compiled core targets cp312)"
    if find_py312; then info "Python: $($PY --version 2>&1)"; return; fi
    step "Python 3.12 not found -- attempting auto-install"
    if [ "$OS" = 'macos' ]; then
        if command -v brew >/dev/null 2>&1; then
            brew install python@3.12
        else
            fail "Homebrew not found. Install it (https://brew.sh) or Python 3.12 (https://www.python.org/downloads), then re-run."
        fi
    else
        info "This may prompt for your sudo password."
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y python3.12 python3.12-venv
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y python3.12
        elif command -v pyenv >/dev/null 2>&1; then
            pyenv install -s 3.12
            eval "$(pyenv init -)" || true
        else
            fail "No supported installer (apt/dnf/pyenv). Install Python 3.12 manually, then re-run."
        fi
    fi
    find_py312 || fail "Python 3.12 still not found after install attempt. Install it manually, then re-run."
    info "Python: $($PY --version 2>&1)"
}

# --- 3. core wheel from latest GitHub Release -------------------------------------
# Selects the release asset whose name is buysg-* and matches this platform
# (CORE_OS + CORE_ARCH substrings). Robust to the exact macOS-version tag.
download_core() {
    step "Fetching latest release info"
    local rel_json name url
    rel_json="$WHEELS/.release.json"
    curl -fsSL -H 'User-Agent: buysg-installer' "${REPO_API}/releases/latest" -o "$rel_json"
    # parse with python (guaranteed present by now); the JSON is read from a FILE path in
    # argv -- not stdin -- because stdin is already taken by this heredoc (the program).
    # || true: read returns non-zero on empty output (no matching asset); the
    # emptiness check below reports it properly instead of set -e killing us here.
    read -r name url < <("$PY" - "$rel_json" "$CORE_OS" "$CORE_ARCH" <<'PYEOF'
import json,sys
path,core_os,core_arch=sys.argv[1],sys.argv[2],sys.argv[3]
with open(path,encoding='utf-8') as f: data=json.load(f)
for a in data.get("assets",[]):
    n=a["name"]
    if n.startswith("buysg-") and n.endswith(".whl") and core_os in n and core_arch in n:
        print(n, a["browser_download_url"]); break
PYEOF
) || true
    [ -n "${name:-}" ] || fail "no buysg core wheel for ${CORE_OS}/${CORE_ARCH} in the latest release (has CI built it yet?)"
    CORE_WHL="$WHEELS/$name"
    if [ ! -f "$CORE_WHL" ]; then
        step "Downloading core: $name"
        curl -fsSL "$url" -o "$CORE_WHL"
    else
        info "core cached: $name"
    fi
}

# --- 4. broker SDKs ---------------------------------------------------------------
download_sdks() {
    step "Downloading broker SDKs from official sites (cached if present)"
    local name url dst
    while read -r name url; do
        dst="$WHEELS/$name"
        if [ ! -f "$dst" ]; then
            info "downloading $name ..."
            curl -fsSL "$url" -o "$dst"
        else
            info "cached: $name"
        fi
        case "$name" in
            *.zip) ( cd "$WHEELS" && unzip -o -q "$dst" ) ;;
        esac
    done < <(sdk_catalog)

    # prune stale broker wheels from older versions (e.g. fubon 2.0.1) so pip does not
    # install a stale duplicate alongside the current one
    local expected
    expected="$(sdk_catalog | awk '{print $1}' | sed 's/\.zip$/.whl/')"
    for w in "$WHEELS"/esun_*.whl "$WHEELS"/fubon_*.whl; do
        [ -e "$w" ] || continue
        if ! grep -qxF "$(basename "$w")" <<<"$expected"; then
            info "removing stale SDK wheel: $(basename "$w")"; rm -f "$w"
        fi
    done
}

# --- 5. venv + install ------------------------------------------------------------
install_all() {
    VENV_PY="$VENV/bin/python"
    if [ ! -x "$VENV_PY" ]; then
        step "Creating virtualenv (Python 3.12)"
        "$PY" -m venv "$VENV"
    fi
    step "Installing core + broker SDKs (deps auto-resolved from PyPI)"
    "$VENV_PY" -m pip install --upgrade pip --quiet
    for w in "$WHEELS"/esun_*.whl "$WHEELS"/fubon_*.whl; do
        [ -e "$w" ] || continue
        "$VENV_PY" -m pip install "$w" --quiet
    done
    "$VENV_PY" -m pip install "$CORE_WHL" --force-reinstall --upgrade --quiet
    [ -x "$VENV/bin/buysg" ] || fail "buysg entry point was not created -- pip install failed, see errors above."
}

# --- 6. command shim + PATH -------------------------------------------------------
create_shim() {
    step "Creating the buysg command"
    mkdir -p "$BIN_DIR"
    cat > "$BIN_DIR/buysg" <<SHIM
#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT}"
export BUYSG_HOME="\$ROOT/home"
case "\${1:-}" in
  update)
    if "\$ROOT/venv/bin/buysg" check-update; then
      exit 0
    fi
    echo "Updating buysg to the latest release..."
    curl -fsSL "${RAW_INSTALL}" | bash
    exit \$? ;;
  uninstall)
    echo "This removes: \$ROOT  and the buysg command."
    echo "NOTE: home/config and home/certificates are deleted too -- back them up first!"
    printf "Remove? (y/n): "; read -r ans
    [ "\$ans" = y ] || { echo "Cancelled."; exit 0; }
    rm -f "${BIN_DIR}/buysg"
    rm -rf "\$ROOT"
    echo "Removed."
    exit 0 ;;
esac
cd "\$BUYSG_HOME"
exec "\$ROOT/venv/bin/buysg" "\$@"
SHIM
    chmod +x "$BIN_DIR/buysg"

    case ":$PATH:" in
        *":$BIN_DIR:"*) : ;;  # already on PATH
        *)
            local profile
            case "${SHELL:-}" in
                */zsh) profile="$HOME/.zshrc" ;;
                */bash) profile="$HOME/.bashrc" ;;
                *) profile="$HOME/.profile" ;;
            esac
            if ! grep -qsF "$BIN_DIR" "$profile" 2>/dev/null; then
                printf '\n# added by buysg installer\nexport PATH="%s:$PATH"\n' "$BIN_DIR" >> "$profile"
            fi
            info "Added $BIN_DIR to PATH in $profile (open a new terminal, or: export PATH=\"$BIN_DIR:\$PATH\")"
            export PATH="$BIN_DIR:$PATH"
            ;;
    esac
}

# --- main -------------------------------------------------------------------------
main() {
    command -v curl  >/dev/null 2>&1 || fail "curl is required"
    command -v unzip >/dev/null 2>&1 || fail "unzip is required"
    detect_platform
    step "Install location: $ROOT  (user data: home/)  platform: $OS/$ARCH"
    mkdir -p "$ROOT" "$HOME2" "$WHEELS" "$BIN_DIR"
    ensure_python
    download_core
    download_sdks
    install_all
    create_shim

    echo
    if [ ! -d "$HOME2/certificates/esun" ] && [ ! -d "$HOME2/certificates/fubon" ]; then
        printf '\033[33m[ONE MORE STEP] Put your broker certificates here:\033[0m\n'
        info "$HOME2/certificates/<esun|fubon>/<name>/"
        info "(esun: SDK config.ini + cert file / fubon: just the .pfx --"
        info " a config.ini template is auto-generated by 'buysg doctor')"
        echo
    fi
    step "Running health check (buysg doctor)"
    "$BIN_DIR/buysg" doctor || true

    echo
    printf '\033[32mInstall finished. Commands:\033[0m\n'
    info "buysg            # interactive order menu"
    info "buysg login      # sign in / register (Google or Facebook)"
    info "buysg preview    # view current gift list (no broker login)"
    info "buysg balance    # account balance + upcoming settlements"
    info "buysg cancel     # cancel pending orders (pick by stock code)"
    info "buysg accounts   # set default accounts"
    info "buysg doctor     # health check"
    info "buysg version    # show version / check for updates"
    info "buysg update     # update (only if a newer release exists)"
    info "buysg uninstall  # remove everything"
    info "buysg help       # full command list"
    echo
    info "Privacy: broker credentials stay on THIS machine only, are used solely to"
    info "log in via the brokers' OFFICIAL SDKs, and are never uploaded. Details:"
    info "https://github.com/${REPO}/blob/main/PRIVACY.md"
}

main "$@"
