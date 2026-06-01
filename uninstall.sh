#!/bin/bash
# SPDX-License-Identifier: MIT
# (C) 2025 Linux T2 Kernel Team
# Removes all files installed by install.sh or the deb (see INSTALL_PATHS.md).

set -euo pipefail
echo "Uninstalling T2 Apple Audio DSP configs"

echo "Removing WirePlumber DSP config"
sudo rm -f /usr/share/wireplumber/wireplumber.conf.d/51-t2-dsp.conf
sudo rm -f /etc/wireplumber/wireplumber.conf.d/51-t2-dsp.conf

echo "Removing old PipeWire config if present"
for old_model_id in 161 162 164 91; do
  sudo rm -f "/etc/pipewire/pipewire.conf.d/t2_${old_model_id}_speakers.conf"
  sudo rm -f "/etc/pipewire/pipewire.conf.d/t2_${old_model_id}_mic.conf"
  sudo rm -f "/etc/pipewire/pipewire.conf.d/10-t2_${old_model_id}_speakers.conf"
  sudo rm -f "/etc/pipewire/pipewire.conf.d/10-t2_${old_model_id}_mic.conf"
done

echo "Removing Lua script symlinks from /usr/share/wireplumber/scripts/device"
sudo rm -f /usr/share/wireplumber/scripts/device/t2-force-unmute.lua

echo "Removing audio data (FIRs, graphs, Lua) from /usr/share/t2-linux-audio"
for model in 16_1 16_2 16_4 9_1; do
  sudo rm -rf "/usr/share/t2-linux-audio/$model"
done
sudo rmdir /usr/share/t2-linux-audio 2>/dev/null || true

echo "Restarting Pipewire for current user ...."
if command -v systemctl >/dev/null 2>&1; then
  if ! systemctl --user restart wireplumber pipewire pipewire-pulse; then
    echo "Warning: could not restart user PipeWire services. Log out and back in, or restart them manually." >&2
  fi
else
  echo "Warning: systemctl not found. Restart PipeWire and WirePlumber manually." >&2
fi
echo "Done."
