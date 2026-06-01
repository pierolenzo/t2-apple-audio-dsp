#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

control=debian/control
version=$(awk '/^Version:/ { print $2; exit }' "$control")
package=$(awk '/^Package:/ { print $2; exit }' "$control")

if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "Error: dpkg-deb not found. Install dpkg-dev or run this on a Debian/Ubuntu build host." >&2
    exit 1
fi

install -d -m 0755 "$BUILD_DIR/DEBIAN"
install -m 0644 "$control" "$BUILD_DIR/DEBIAN/control"
install -m 0755 debian/postinst "$BUILD_DIR/DEBIAN/postinst"
if [ -f debian/postrm ]; then
    install -m 0755 debian/postrm "$BUILD_DIR/DEBIAN/postrm"
fi
if [ -f debian/copyright ]; then
    install -m 0644 debian/copyright "$BUILD_DIR/DEBIAN/copyright"
fi

# Copy all model configs to package (for postinst to select based on model)
install -d -m 0755 "$BUILD_DIR/usr/share/t2-apple-audio-dsp"
cp -a config "$BUILD_DIR/usr/share/t2-apple-audio-dsp/"

# Install FIRs, DSP graphs, and Lua scripts to /usr/share/t2-linux-audio (same as install.sh)
for model_dir in firs/*/; do
    if [ -d "$model_dir" ]; then
        model=$(basename "$model_dir")
        dest="$BUILD_DIR/usr/share/t2-linux-audio/${model}"
        install -d -m 0755 "$dest"
        find "$model_dir" -maxdepth 1 -type f -exec install -m 0644 {} "$dest/" \;
    fi
done

# Install copyright file for package managers (KDE Discover, etc.)
if [ -f debian/copyright ]; then
    install -d -m 0755 "$BUILD_DIR/usr/share/doc/${package}"
    install -m 0644 debian/copyright "$BUILD_DIR/usr/share/doc/${package}/copyright"
fi

#generate debian package
output="${package}_${version}_amd64.deb"
echo "Building package ${output}"
dpkg-deb --root-owner-group -Zgzip --build "$BUILD_DIR" "$output"
echo "Package built: ${output}"

# Generate SHA256 checksum and show package info
echo "Generating checksum..."
sha256sum "$output" > "${output}.sha256"
echo "Package info:"
echo "  SHA256: $(cat "${output}.sha256")"
echo "  Size:   $(ls -lh "$output" | awk '{print $5}')"
