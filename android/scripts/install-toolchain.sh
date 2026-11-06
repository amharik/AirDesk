#!/usr/bin/env bash
set -euo pipefail

SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
CMDLINE_TOOLS_VERSION="${CMDLINE_TOOLS_VERSION:-13114758}"
ARCH="$(uname -m)"
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
fi

log() {
    printf '[airdesk-toolchain] %s\n' "$*"
}

install_base_packages() {
    local packages=()
    if ! command -v java >/dev/null 2>&1 || ! command -v javac >/dev/null 2>&1; then
        packages+=("openjdk-17-jdk-headless")
    else
        local java_major
        java_major="$(java -version 2>&1 | awk -F'"' '/version/ {print $2; exit}' | cut -d. -f1)"
        if [ "$java_major" != "17" ]; then
            packages+=("openjdk-17-jdk-headless")
        fi
    fi
    command -v unzip >/dev/null 2>&1 || packages+=("unzip")
    command -v curl >/dev/null 2>&1 || packages+=("curl")
    if [ "${#packages[@]}" -eq 0 ]; then
        return
    fi
    log "Installing ${packages[*]}"
    $SUDO apt-get update -qq
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}"
}

install_amd64_runtime_for_aapt2() {
    local list_file="/tmp/airdesk-amd64.list"
    local state_dir="/tmp/airdesk-amd64-apt"
    mkdir -p "$state_dir/lists/partial" "$state_dir/cache/archives/partial"
    cat >"$list_file" <<'EOF'
deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy main universe
deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy-updates main universe
deb [arch=amd64] http://archive.ubuntu.com/ubuntu jammy-security main universe
EOF
    $SUDO dpkg --add-architecture amd64
    local apt_opts=(
        -o "Dir::Etc::sourcelist=$list_file"
        -o "Dir::Etc::sourceparts=-"
        -o "Dir::State::lists=$state_dir/lists"
        -o "Dir::Cache=$state_dir/cache"
        -o "APT::Architectures::=amd64"
    )
    $SUDO apt-get "${apt_opts[@]}" update -qq
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" install -y -qq \
        libc6:amd64 libgcc-s1:amd64
}

install_base_packages

JAVA_MAJOR="$(java -version 2>&1 | awk -F'"' '/version/ {print $2; exit}' | cut -d. -f1)"
if [ "$JAVA_MAJOR" != "17" ]; then
    log "JDK 17 is required, found Java major '$JAVA_MAJOR'"
    exit 1
fi
log "Java: $(java -version 2>&1 | head -n 1)"

TOOLS_DIR="$SDK_ROOT/cmdline-tools/latest"
SDKMANAGER="$TOOLS_DIR/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    url="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"
    log "Downloading command-line tools: $url"
    curl -fL --retry 3 --connect-timeout 20 -o "$tmp_dir/tools.zip" "$url"
    unzip -q "$tmp_dir/tools.zip" -d "$tmp_dir/extracted"
    mkdir -p "$SDK_ROOT/cmdline-tools"
    rm -rf "$TOOLS_DIR"
    mv "$tmp_dir/extracted/cmdline-tools" "$TOOLS_DIR"
fi

log "Accepting Android SDK licenses"
set +o pipefail
yes | "$SDKMANAGER" --sdk_root="$SDK_ROOT" --licenses >/dev/null || true
set -o pipefail

log "Installing platform-tools, platforms;android-35 and build-tools;35.0.0"
"$SDKMANAGER" --sdk_root="$SDK_ROOT" --install \
    "platform-tools" \
    "platforms;android-35" \
    "build-tools;35.0.0"

"$SDKMANAGER" --sdk_root="$SDK_ROOT" --version
"$SDKMANAGER" --sdk_root="$SDK_ROOT" --list_installed | grep -E \
    'build-tools;35\.0\.0|platforms;android-35|platform-tools'

if [ "$ARCH" = "aarch64" ]; then
    AAPT2="$SDK_ROOT/build-tools/35.0.0/aapt2"
    if ! "$AAPT2" version >/dev/null 2>&1; then
        log "aapt2 is an x86-64 binary; enabling QEMU user emulation"
        if ! command -v qemu-x86_64-static >/dev/null 2>&1; then
            $SUDO apt-get update -qq
            $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq qemu-user-static
        fi
        if [ ! -e /lib64/ld-linux-x86-64.so.2 ]; then
            install_amd64_runtime_for_aapt2
        fi
    fi
    if ! "$AAPT2" version >/dev/null 2>&1; then
        log "aapt2 still cannot execute on $ARCH; install qemu-user-static and amd64 glibc"
        exit 1
    fi
    log "aapt2 on $ARCH: $("$AAPT2" version 2>&1)"
fi

log "Android SDK ready at $SDK_ROOT"
