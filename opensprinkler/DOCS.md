# OpenSprinkler

Runs the [OpenSprinkler](https://opensprinkler.com/) Pi irrigation controller
firmware as a Home Assistant add-on. It works with or without sprinkler
hardware attached.

## Installation

1. Install the add-on and start it.
2. Open the web UI (**Open Web UI**, or `http://<your-ha-host>:88/`).
3. Default password is `opendoor` — change it in the UI immediately.

## Configuration

### Option: `require_hardware`

Default `false`.

Leave it off if Home Assistant runs somewhere with no sprinkler hardware — an
x86-64 box, or a Pi with no OpenSprinkler hat. The UI, programs, and
remote/HTTP/OTC stations all work; only local valves are unavailable.

Turn it on when local valves are the point. The firmware does **not** report
failing to open a GPIO device in a release build: the UI stays up, the add-on
stays green, programs appear to run, and no valve ever opens. With
`require_hardware` on, the add-on refuses to start instead, and the log says
why.

The add-on always logs which GPIO and I2C devices it found, whichever way this
is set — check the log after the first start.

## Hardware

On a Raspberry Pi, enable I2C on the host first (`dtparam=i2c_arm=on`) if you
use zone or sensor expanders, an RTC, or an ADS1115.

The add-on asks for four device nodes and uses whichever exist:

| Device | Used for |
|---|---|
| `/dev/gpiochip0` | station and sensor pins, Pi 1–4 |
| `/dev/gpiochip4` | station and sensor pins, Pi 5 (bcm2712) |
| `/dev/i2c-1` | expanders, RTC, ADS1115 on any recognised Pi |
| `/dev/i2c-0` | the same, on unrecognised hardware |

No elevated privilege is needed: lgpio is a character-device library, so it
does not want `/dev/mem` or `CAP_SYS_RAWIO`.

## Network access

Port 88 is published directly as well as being available through Home
Assistant, because other applications on the network talk to the controller's
HTTP API and cannot go through an ingress token.

**Do not change the HTTP port in the OpenSprinkler UI.** That value persists in
`iopts.dat` and wins over the add-on's port mapping, so changing it makes the
controller unreachable. Remap the host side instead if you need a different
port.

## Data

Everything the firmware persists lives in `/data/opensprinkler` inside the
add-on: `iopts.dat`, `sopts.dat`, `stns.dat`, `prog.dat`, `nvcon.dat`,
`done.dat`, `sens.dat`, `senadj.dat`, and a `logs/` directory. It survives
add-on updates and restarts, and is included in Home Assistant backups.

`sopts.dat` holds MQTT, SMTP and IFTTT credentials in the clear. Treat add-on
backups accordingly.

### Migrating an existing installation

Copy your existing `.dat` files into `/data/opensprinkler`.

If they come from firmware 2.2.1(5) or earlier, the persisted HTTP port is
`8080`, not `88`, and `iopts.dat` wins — so either change the port in the UI
after the first start, or remap the add-on's host port to reach it.

## Updating

Update through the add-on. **The firmware-update button in the OpenSprinkler UI
does not work here** and never did in a container: it shells out to
`updater.sh` in the data directory, which has to be a git checkout of the
firmware.

Each add-on release pins one exact firmware build. Which one is in the
changelog.

## Home Assistant integration

This add-on only runs the controller. To get entities in Home Assistant, add
the OpenSprinkler integration separately and point it at this add-on's host and
port 88.
