#!/bin/sh
# SPDX-License-Identifier: MIT
# (C) 2025 Linux T2 Kernel Team
# Verify that all T2 Apple Audio DSP files are installed (see INSTALL_PATHS.md).

set -e
OK=0
MISSING=0
MODEL_DICT="MacBookPro16,1 16_1 MacBookPro16,2 16_2 MacBookPro16,4 16_4 MacBookAir9,1 9_1"

get_model_dir() {
    model="$1"
    set -- $MODEL_DICT
    while [ $# -ge 2 ]; do
        if [ "$1" = "$model" ]; then
            echo "$2"
            return 0
        fi
        shift 2
    done
    return 1
}

check() {
    if [ -e "$1" ]; then
        echo "  OK   $1"
        OK=$((OK + 1))
    else
        echo "  MISS $1"
        MISSING=$((MISSING + 1))
    fi
}

echo "=== WirePlumber DSP config ==="
dsp_conf="/usr/share/wireplumber/wireplumber.conf.d/51-t2-dsp.conf"
check "$dsp_conf"

echo ""
echo "=== Audio data: /usr/share/t2-linux-audio/<model>/ ==="
MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
MODEL_DIR=$(get_model_dir "$MODEL" || true)
if [ -n "$MODEL_DIR" ]; then
    MODELS="$MODEL_DIR"
    DETECTED_SUPPORTED=1
    echo "Detected model: $MODEL (checking $MODEL_DIR)"
else
    MODELS="16_1 16_2 16_4 9_1"
    DETECTED_SUPPORTED=0
    echo "Could not detect supported model; checking all known model directories."
fi

for model in $MODELS; do
    dir="/usr/share/t2-linux-audio/$model"
    if [ -d "$dir" ]; then
        check "$dir"
        check "$dir/graph.json"
        check "$dir/mic.json"
        if ls "$dir"/*.lua 1>/dev/null 2>&1; then
            for lua_file in "$dir"/*.lua; do
                check "$lua_file"
            done
        fi
        # At least one .wav
        if ls "$dir"/*.wav 1>/dev/null 2>&1; then
            echo "  OK   $dir/*.wav (present)"
            OK=$((OK + 1))
        else
            echo "  MISS $dir/*.wav"
            MISSING=$((MISSING + 1))
        fi
    else
        if [ "$DETECTED_SUPPORTED" -eq 1 ]; then
            echo "  MISS $dir"
            MISSING=$((MISSING + 1))
        else
            echo "  skip $dir (not present)"
        fi
    fi
done

echo ""
echo "=== Lua symlinks: /usr/share/wireplumber/scripts/device/ -> t2-linux-audio ==="
FOUND_LUA=0
for model in $MODELS; do
    for lua_file in /usr/share/t2-linux-audio/"$model"/*.lua; do
        [ -e "$lua_file" ] || continue
        FOUND_LUA=1
        lua_name=$(basename "$lua_file")
        t2_lua="/usr/share/wireplumber/scripts/device/$lua_name"
        if [ -L "$t2_lua" ]; then
            target=$(readlink -f "$t2_lua" 2>/dev/null || readlink "$t2_lua" 2>/dev/null)
            if [ "$target" = "$lua_file" ]; then
                echo "  OK   $t2_lua -> $target"
                OK=$((OK + 1))
            else
                echo "  MISS $t2_lua -> $target (expected $lua_file)"
                MISSING=$((MISSING + 1))
            fi
        else
            echo "  MISS $t2_lua (symlink)"
            MISSING=$((MISSING + 1))
        fi
    done
done

if [ "$FOUND_LUA" -eq 0 ]; then
    echo "  skip no Lua scripts installed for the present model data"
fi

echo ""
if [ "$MISSING" -eq 0 ]; then
    echo "All checked files present ($OK items)."
    exit 0
else
    echo "Some items missing ($MISSING). Re-run install: ./install.sh or reinstall the t2-apple-audio-dsp package"
    exit 1
fi
