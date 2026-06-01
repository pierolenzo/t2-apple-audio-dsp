# Installation paths (shared by standalone and deb install)

Both the standalone install script and the deb package install to the same locations.

## Files installed

| Purpose | Path |
|--------|------|
| WirePlumber DSP config | `/usr/share/wireplumber/wireplumber.conf.d/` - selected `*-dsp.conf` copied here |
| FIRs, DSP graphs, Lua scripts | `/usr/share/t2-linux-audio/<MODEL_DIR>/` - e.g. `16_1`, `16_2`, `16_4`, `9_1` - `.wav`, `.json`, `.lua` |

## Symlinks created

| Symlink | Target |
|---------|--------|
| `/usr/share/wireplumber/scripts/device/<name>.lua` | -> `/usr/share/t2-linux-audio/<MODEL_DIR>/<name>.lua` |

(One symlink per Lua script in the model directory.)

## Scripts

- **Standalone**: run `./install.sh` from the source tree (requires `config/` and `firs/`). Copies config and FIRs into the paths above and creates the symlinks.
- **Deb**: package installs files under `/usr/share/t2-apple-audio-dsp/config` and `/usr/share/t2-linux-audio`; postinst copies the selected config to `/usr/share/wireplumber/wireplumber.conf.d/` and creates Lua symlinks only (FIRs are already in place).

**Uninstall**: `./uninstall.sh` removes the project WirePlumber config, Lua symlinks, and known model directories under `/usr/share/t2-linux-audio` (full uninstall).
