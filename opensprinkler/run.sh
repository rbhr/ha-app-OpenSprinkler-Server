#!/bin/sh
set -e

OPTIONS_FILE="/data/options.json"
DATA_DIR="/data/opensprinkler"

require_hardware="$(jq -r '.require_hardware // false' "$OPTIONS_FILE" 2>/dev/null || echo false)"

echo "OpenSprinkler add-on starting..."

# --- Persistent data ---
#
# Supervisor owns /data and writes options.json into it. The firmware writes
# iopts.dat, sopts.dat, stns.dat, prog.dat, nvcon.dat, done.dat, sens.dat and
# senadj.dat plus a logs/ directory into whatever -d names, so give it a
# subdirectory of its own instead of letting the two share. get_filename_
# fullpath() appends the trailing slash itself but never creates the directory.
mkdir -p "$DATA_DIR"

# --- Hardware probe ---
#
# init_lgpio() opens gpiochip4 on a Pi 5 (bcm2712) and gpiochip0 on every
# earlier board, falling back 4 -> 0. Each failure path is a DEBUG_PRINTLN,
# which compiles to nothing in a release build: with no GPIO the web UI still
# comes up, programs still appear to run, and no valve ever opens. Nothing in
# the firmware will tell you. So say it here.

found_gpio=""
for CHIP in /dev/gpiochip0 /dev/gpiochip4; do
    if [ -e "$CHIP" ]; then
        echo "  GPIO:  ${CHIP} present"
        found_gpio="yes"
    fi
done

found_i2c=""
for BUS in /dev/i2c-1 /dev/i2c-0; do
    if [ -e "$BUS" ]; then
        echo "  I2C:   ${BUS} present"
        found_i2c="yes"
    fi
done
[ -n "$found_i2c" ] || echo "  I2C:   none present (no expanders, RTC or ADS1115)"

if [ -z "$found_gpio" ]; then
    if [ "$require_hardware" = "true" ]; then
        # stdout, not stderr: Docker multiplexes the two as separate streams and
        # does not preserve ordering between them, so a fatal line on stderr
        # surfaces above the probe output that explains it. The container log is
        # the only consumer here, and a readable order beats the convention.
        echo "FATAL: require_hardware is on, but no GPIO character device is available."
        echo "       Expected /dev/gpiochip0 (Pi 1-4) or /dev/gpiochip4 (Pi 5)."
        echo "       Check the host exposes it, and that I2C is enabled"
        echo "       (dtparam=i2c_arm=on) if you are using expanders."
        exit 1
    fi
    echo "  GPIO:  none present"
    echo "  WARNING: no GPIO device, so local stations cannot be switched. The web"
    echo "           UI, programs, and remote/HTTP/OTC stations all still work, but"
    echo "           no local valve will open. Set require_hardware to make this"
    echo "           condition stop the add-on instead of warning."
fi

echo "  Data:  ${DATA_DIR}"

exec /OpenSprinkler/OpenSprinkler -d "$DATA_DIR"
