#!/bin/bash
# Measures GPU and CPU+GPU power with HiDPI on vs off, using powermetrics (needs sudo).
# Usage: sudo scripts/measure-power.sh [seconds per phase, default 40]
# PortableHiDPI must be installed in /Applications with a resolution already chosen.
# Leave the Mac idle while it runs; the external monitor blinks twice.
set -euo pipefail
SECS=${1:-40}
USER_NAME=${SUDO_USER:?run with sudo}
APP=/Applications/PortableHiDPI.app

measure() { # phase label
    powermetrics --samplers cpu_power,gpu_power -i 2000 -n $((SECS / 2)) 2>/dev/null |
        awk -v label="$1" '
            /^GPU Power:/ { g += $3; ng++ }
            /^Combined Power \(CPU \+ GPU \+ ANE\):/ { c += $8; nc++ }
            END { printf "%-4s GPU %6.0f mW   CPU+GPU+ANE %6.0f mW\n", label, g / ng, c / nc }'
}

sudo -u "$USER_NAME" open "$APP"; sleep 10
measure ON
pkill -TERM -f "$APP/Contents/MacOS/PortableHiDPI" || true; sleep 10
measure OFF
sudo -u "$USER_NAME" open "$APP"
