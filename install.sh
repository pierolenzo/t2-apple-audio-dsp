#!/bin/bash
# SPDX-License-Identifier: MIT
# (C) 2025 Linux T2 Kernel Team
#
# Standalone install: run from the source directory. Installs to the same
# paths as the deb package; see INSTALL_PATHS.md.

set -euo pipefail
shopt -s nullglob

CONFIG_DIR="config"
FIRS_DIR="firs"
AUDIO_DIR="/usr/share/t2-linux-audio"
WP_CONFIG_DIR="/usr/share/wireplumber/wireplumber.conf.d"
WP_SCRIPT_DIR="/usr/share/wireplumber/scripts/device"
LEGACY_WP_CONFIG="/etc/wireplumber/wireplumber.conf.d/51-t2-dsp.conf"

# Model dict: "model_id dir_name ..." - add more models here.
MODEL_DICT="MacBookPro16,1 16_1 MacBookPro16,2 16_2 MacBookPro16,4 16_4 MacBookAir9,1 9_1"

die() {
  echo "Error: $*" >&2
  exit 1
}

get_model_dir() {
  local model="$1"

  set -- $MODEL_DICT
  while [ "$#" -ge 2 ]; do
    if [ "$1" = "$model" ]; then
      echo "$2"
      return 0
    fi
    shift 2
  done
  return 1
}

print_supported_models() {
  set -- $MODEL_DICT
  while [ "$#" -ge 2 ]; do
    echo "  - $1"
    shift 2
  done
}

rnnoise_plugin_path() {
  local path

  for path in \
    /usr/lib64/ladspa/librnnoise_ladspa.so \
    /usr/lib/ladspa/librnnoise_ladspa.so \
    /usr/lib/*/ladspa/librnnoise_ladspa.so
  do
    if [ -e "$path" ]; then
      echo "$path"
      return 0
    fi
  done
  return 1
}

patch_rnnoise_path() {
  local mic_json="$1"
  local current_path=""
  local plugin_path=""

  if ! grep -q 'librnnoise_ladspa\.so' "$mic_json"; then
    return 0
  fi

  current_path=$(sed -n 's/.*"plugin": "\([^"]*librnnoise_ladspa\.so\)".*/\1/p' "$mic_json" | head -n 1)
  if [ -n "$current_path" ] && [ -e "$current_path" ]; then
    return 0
  fi

  plugin_path=$(rnnoise_plugin_path) || die "RNNoise LADSPA plugin not found. Install noise-suppression-for-voice."
  echo "Using RNNoise LADSPA plugin: ${plugin_path}"
  sudo sed -i "s|\"plugin\": \"[^\"]*librnnoise_ladspa.so\"|\"plugin\": \"${plugin_path}\"|" "$mic_json"
}

cleanup_legacy_configs() {
  local old_model_id="$1"
  local path

  for path in \
    "/etc/pipewire/pipewire.conf.d/t2_${old_model_id}_speakers.conf" \
    "/etc/pipewire/pipewire.conf.d/t2_${old_model_id}_mic.conf" \
    "/etc/pipewire/pipewire.conf.d/10-t2_${old_model_id}_speakers.conf" \
    "/etc/pipewire/pipewire.conf.d/10-t2_${old_model_id}_mic.conf" \
    "$LEGACY_WP_CONFIG"
  do
    if sudo test -e "$path"; then
      echo "Removing legacy config: $path"
      sudo rm -f "$path"
    fi
  done
}

if [ ! -d "$CONFIG_DIR" ] || [ ! -d "$FIRS_DIR" ]; then
  die "Run this script from the source directory (must contain config/ and firs/)."
fi

MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
if [ -z "$MODEL" ]; then
  die "Could not detect computer model"
fi

MODEL_DIR=$(get_model_dir "$MODEL" || true)
if [ -z "$MODEL_DIR" ]; then
  echo "Error: Model '${MODEL}' is not supported" >&2
  echo "Supported models:" >&2
  print_supported_models >&2
  exit 1
fi

MODEL_CONFIG_DIR="${CONFIG_DIR}/${MODEL_DIR}"
MODEL_FIRS_DIR="${FIRS_DIR}/${MODEL_DIR}"
MODEL_AUDIO_DIR="${AUDIO_DIR}/${MODEL_DIR}"
CONF_FILES=("${MODEL_CONFIG_DIR}"/*-dsp.conf)
WAV_FILES=("${MODEL_FIRS_DIR}"/*.wav)
JSON_FILES=("${MODEL_FIRS_DIR}"/*.json)
LUA_FILES=("${MODEL_FIRS_DIR}"/*.lua)

[ -d "$MODEL_CONFIG_DIR" ] || die "Configuration not found for model: ${MODEL}"
[ -d "$MODEL_FIRS_DIR" ] || die "Audio data not found for model: ${MODEL}"
[ "${#CONF_FILES[@]}" -gt 0 ] || die "No WirePlumber DSP config found for ${MODEL_DIR}"
[ -f "${MODEL_FIRS_DIR}/graph.json" ] || die "Missing graph.json for ${MODEL_DIR}"
[ -f "${MODEL_FIRS_DIR}/mic.json" ] || die "Missing mic.json for ${MODEL_DIR}"
[ "${#WAV_FILES[@]}" -gt 0 ] || die "No FIR .wav files found for ${MODEL_DIR}"

echo "Detected model: ${MODEL} (using directory: ${MODEL_DIR})"
echo "Installing DSP config for ${MODEL}"

echo "Copying WirePlumber DSP config to ${WP_CONFIG_DIR}"
sudo install -d -m 0755 "$WP_CONFIG_DIR"
sudo install -m 0644 "${CONF_FILES[@]}" "$WP_CONFIG_DIR/"

echo "Copying FIRs, DSP graphs, and Lua scripts to ${MODEL_AUDIO_DIR}"
sudo install -d -m 0755 "$MODEL_AUDIO_DIR"
sudo install -m 0644 "${WAV_FILES[@]}" "$MODEL_AUDIO_DIR/"
sudo install -m 0644 "${JSON_FILES[@]}" "$MODEL_AUDIO_DIR/"
if [ "${#LUA_FILES[@]}" -gt 0 ]; then
  sudo install -m 0644 "${LUA_FILES[@]}" "$MODEL_AUDIO_DIR/"
fi

patch_rnnoise_path "${MODEL_AUDIO_DIR}/mic.json"

if [ "${#LUA_FILES[@]}" -gt 0 ]; then
  echo "Creating symlinks for WirePlumber Lua scripts"
  sudo install -d -m 0755 "$WP_SCRIPT_DIR"
  for lua_file in "${MODEL_AUDIO_DIR}"/*.lua; do
    sudo ln -sf "$lua_file" "${WP_SCRIPT_DIR}/$(basename "$lua_file")"
  done
fi

OLD_MODEL_ID=$(echo "$MODEL_DIR" | tr -d '_')
cleanup_legacy_configs "$OLD_MODEL_ID"

echo "Restarting WirePlumber and PipeWire for current user ...."
if command -v systemctl >/dev/null 2>&1; then
  if ! systemctl --user restart wireplumber pipewire pipewire-pulse; then
    echo "Warning: could not restart user PipeWire services. Log out and back in, or restart them manually." >&2
  fi
else
  echo "Warning: systemctl not found. Restart PipeWire and WirePlumber manually." >&2
fi

echo ""
echo "Installation complete!"
echo "The raw Apple Audio Device should now be hidden."
echo "Only the DSP-processed outputs should be visible."
echo "  - DSP Speakers"
echo "  - DSP Mic"
echo ""
echo "Note: You may need to log out and log back in for changes to fully take effect."
