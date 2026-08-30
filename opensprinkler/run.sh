#!/bin/sh
set -e

OPTIONS_FILE="/data/options.json"
DATA_DIR="/data/opensprinkler"

# The firmware persists its HTTP port in iopts.dat and that value wins, but 88
# is what config.yaml maps and what ingress_port names, so a controller that
# has drifted off it is already broken for other reasons.
API="http://127.0.0.1:88"

# DEFAULT_PASSWORD in the firmware's defines.h -- md5 of "opendoor".
DEFAULT_PW_HASH="a6d82bced638de3def1e9bbb4983225c"

require_hardware="$(jq -r '.require_hardware // false' "$OPTIONS_FILE" 2>/dev/null || echo false)"

# Both of these are optional in the schema and absent unless the user sets
# them, which is the whole point: absent means "leave the controller's own
# setting alone". An empty password string is treated the same as absent.
password="$(jq -r '.password // ""' "$OPTIONS_FILE" 2>/dev/null || echo "")"
ignore_password="$(jq -r 'if .ignore_password == null then "" else (.ignore_password|tostring) end' "$OPTIONS_FILE" 2>/dev/null || echo "")"

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

# --- Login settings ---
#
# The password lives in the firmware's sopts.dat as the md5 of the plaintext
# (SOPT_PASSWORD, index 0), and the UI asks for it on first load: home.js
# prompts, hashes what you type, and remembers the hash per browser. There is
# no way to hand the page a password -- the firmware serves "/" itself, home.js
# reads no query string, and this add-on deliberately runs no proxy. So the two
# levers are the controller's own HTTP API, applied here after it comes up:
#
#   /sp?pw=<current>&npw=<new>&cpw=<new>   sets the password       (server_change_password)
#   /co?pw=<current>&ipas=<0|1>            sets IOPT_IGNORE_PASSWORD (server_change_options)
#
# ipas is what actually removes the prompt: server_home emits it into the page
# as `var ipas=1`, and home.js then calls savePassword("") instead of asking.
# It is global -- process_password() returns true for every request -- so it
# drops authentication on port 88 as well, which is why it is opt-in.
#
# Only hashes are ever passed on a command line; the plaintext stays in the
# variable. It is in /data/options.json in the clear either way, as all add-on
# options are.
seed_log() { echo "OpenSprinkler add-on: $*"; }

apply_login_settings() {
    want_pw=""
    [ -n "$password" ] && want_pw="$(printf '%s' "$password" | md5sum | cut -d' ' -f1)"

    # Wait for the HTTP server. /jo answers 200 either way -- the full options
    # when the password checks out, just {"fwv":...} when it does not, because
    # process_password() is called with fwv_on_fail -- so an unauthenticated
    # call is a clean readiness probe.
    n=0
    while ! curl -fsS -m 2 -o /dev/null "${API}/jo" 2>/dev/null; do
        n=$((n + 1))
        if [ "$n" -ge 60 ]; then
            seed_log "WARNING: the controller did not answer on ${API} within 60s."
            seed_log "         Login settings from the add-on configuration were not"
            seed_log "         applied this boot."
            return
        fi
        sleep 1
    done

    # Find a hash the controller accepts. /jo lists every non-hidden integer
    # option by its json name, so "ipas" in the body means the call
    # authenticated. want_pw is left unquoted so that an unset password drops
    # out of the list rather than probing an empty one.
    cur=""
    for cand in $want_pw "$DEFAULT_PW_HASH"; do
        if curl -fsS -m 5 "${API}/jo?pw=${cand}" 2>/dev/null | grep -q '"ipas"'; then
            cur="$cand"
            break
        fi
    done

    if [ -z "$cur" ]; then
        seed_log "WARNING: the controller accepted neither the configured password nor"
        seed_log "         the factory default, so its current password is unknown and"
        seed_log "         the API calls below cannot be authenticated. Login settings"
        seed_log "         from the add-on configuration were ignored this boot. Set"
        seed_log "         the password option to the one you are actually using, or"
        seed_log "         change it back in the UI. If it is lost, the only way back"
        seed_log "         is a factory reset -- see 'Resetting a forgotten password'"
        seed_log "         in the add-on documentation. Do NOT delete sopts.dat: it"
        seed_log "         is never recreated, and the password check then fails for"
        seed_log "         every password rather than falling back to the default."
        return
    fi

    # HTML_SUCCESS is 1. Anchor the match: the other result codes include 16,
    # 17, 18 and 19, and a bare '"result":1' is a prefix of all of them.
    ok='"result": *1[,}]'

    # Set it unconditionally rather than skipping when the probe above suggested
    # it is already right. If ipas happens to be on, process_password() returns
    # true for anything, so the probe proved nothing and the shortcut would
    # silently leave the old password in place -- to surface the moment ipas was
    # turned back off. sopt_save() compares before it writes, so a redundant
    # call costs a file read.
    if [ -n "$want_pw" ]; then
        if curl -fsS -m 5 "${API}/sp?pw=${cur}&npw=${want_pw}&cpw=${want_pw}" 2>/dev/null | grep -qE "$ok"; then
            cur="$want_pw"
            seed_log "Password applied from the add-on configuration."
        else
            seed_log "WARNING: the controller refused the new password; it is unchanged."
            return
        fi
    fi

    if [ -n "$ignore_password" ]; then
        want_ipas=0
        [ "$ignore_password" = "true" ] && want_ipas=1
        if ! curl -fsS -m 5 "${API}/co?pw=${cur}&ipas=${want_ipas}" 2>/dev/null | grep -qE "$ok"; then
            seed_log "WARNING: the controller refused the 'ignore password' change."
        elif [ "$want_ipas" = "1" ]; then
            seed_log "Password prompt disabled: the UI opens straight up. This applies"
            seed_log "  to port 88 as well as to the sidebar panel -- anything that can"
            seed_log "  reach the controller can now operate it."
        else
            seed_log "Password required: the UI prompts once per browser."
            # The prompt is back on, so the password matters again -- and if ipas
            # had been on, it was the only reason any of the calls above were
            # accepted. Confirm the hash we ended up with really works.
            if ! curl -fsS -m 5 "${API}/jo?pw=${cur}" 2>/dev/null | grep -q '"ipas"'; then
                seed_log "WARNING: but the password could not be confirmed afterwards, so"
                seed_log "         nobody may know it, and the prompt is now in the way."
                seed_log "         Set the password option as well, or turn this option"
                seed_log "         back on, before restarting."
            fi
        fi
    fi
}

# Run it alongside the firmware rather than before it, so the controller is
# started exactly once: it needs its own HTTP server up to be configured, and
# starting a throwaway instance first would take and release the GPIO lines a
# second time on every boot. The child outlives the exec below and is reparented
# to the firmware, which never reaps, so it lingers as one zombie entry after it
# finishes -- harmless, and cheaper than the alternative.
if [ -n "$password" ] || [ -n "$ignore_password" ]; then
    apply_login_settings &
fi

exec /OpenSprinkler/OpenSprinkler -d "$DATA_DIR"
