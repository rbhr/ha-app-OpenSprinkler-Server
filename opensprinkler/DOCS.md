# OpenSprinkler

Runs the [OpenSprinkler](https://opensprinkler.com/) Pi irrigation controller
firmware as a Home Assistant add-on. It works with or without sprinkler
hardware attached.

## Installation

1. Install the add-on and start it.
2. Open the web UI (**Open Web UI**, or `http://<your-ha-host>:88/`).
3. Default password is `opendoor` — change it in the UI, or set the
   `password` option below and let the add-on do it.

## Configuration

### Option: `password`

Optional; unset by default.

The controller's own password — the one the web UI asks for on first load. Set
it here and the add-on applies it to the controller every time it starts, so
Home Assistant is where you keep it rather than a value you have to remember
having typed into the UI once.

Leave it unset and the add-on does not touch the password at all; whatever is
in the UI stands.

Two things to know:

- **It cannot rescue a password you have forgotten.** Changing the password
  requires the current one, so on each start the add-on tries the value you
  configured (nothing to do if it already matches), then the factory default
  `opendoor`. If neither is accepted, it logs a warning explaining that and
  starts normally with the password unchanged. Deleting
  `/data/opensprinkler/sopts.dat` returns the controller to `opendoor`, and
  loses the MQTT, SMTP and IFTTT settings stored alongside it.
- **It does not stop the UI asking.** The password prompt is the UI's, and
  there is no way to answer it on your behalf. It appears once per browser and
  is remembered after that. If what you want is no prompt, see below.

### Option: `ignore_password`

Optional; unset by default.

Set it to `true` and the web UI opens straight into the controller with no
password prompt — including from the sidebar panel, where Home Assistant has
already authenticated you.

**This is not ingress-only.** The firmware has a single "ignore password"
setting, and it makes every request unauthenticated: anything that can reach
port 88 on your network can start and stop watering. Turn it on only if you are
comfortable with that, or drop the `88/tcp` port mapping so ingress is the only
way in.

Set it to `false` and the add-on restores the prompt. Leave it unset and the
add-on does not touch the setting, so the **Ignore password** checkbox in the
OpenSprinkler UI stays in charge.

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

There are two ways in, and both are deliberate.

**The sidebar panel** (ingress) is the everyday one. It needs no port, no
address, and no separate Home Assistant authentication — though the
OpenSprinkler UI still asks for the controller's own password the first time
each browser opens it, unless `ignore_password` is on.

**Port 88 published directly** is for everything else: other applications on
the network that use the controller's HTTP API cannot go through an ingress
token. This is also the address to give the Home Assistant OpenSprinkler
integration.

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
