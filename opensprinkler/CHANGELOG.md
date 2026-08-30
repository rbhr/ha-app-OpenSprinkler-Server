# Changelog

## 1.2.1

- Corrects bad recovery advice given in 1.2.0. When the add-on could not
  authenticate to apply the `password` option, it suggested deleting
  `sopts.dat` to return to `opendoor`. **That does the opposite:** nothing
  recreates the file, and the firmware's password check reports a mismatch for
  every password when it cannot open it, so following the advice would have
  locked you out with no way in. The log message and the documentation now say
  what actually works — and the documentation now has a *Resetting a forgotten
  password* section explaining that it means a factory reset.
- Documentation only otherwise: the add-on behaves exactly as 1.2.0 did.
- No firmware change: still `v2.2.1.5-ospi.1`.

## 1.2.0

- Adds a **`password`** option. Set the controller's password in the add-on
  configuration and the add-on applies it over the firmware's HTTP API on every
  start, so Home Assistant holds it instead of it being something you typed
  into the UI once. Leave it unset and nothing is touched. It cannot recover a
  password you have forgotten — changing one needs the current one, so the
  add-on tries the configured value, then the factory `opendoor`, and warns in
  the log if neither is accepted.
- Adds an **`ignore_password`** option. With it on, the web UI opens with no
  password prompt, which is what makes the sidebar panel usable without typing
  the controller password into every browser. It sets the firmware's `ipas`
  option, which is global: **port 88 becomes unauthenticated too.** Off or
  unset, nothing changes.
- Both options are optional and absent from `options.json` until set, so an
  installation that ignores them behaves exactly as 1.1.1 did and the
  OpenSprinkler UI stays in charge of both settings.
- No firmware change: still `v2.2.1.5-ospi.1`.

## 1.1.1

- Fixes the ingress panel showing **"The requested page does not exist"**.
  1.1.0 set `ingress_entry: /`, but Supervisor appends that *relative* to a
  panel URL that already ends in a slash, so the add-on was asked for `//` —
  which the firmware's router treats as a hard 404. Removing the key gives `/`.
- Port 88 was never affected.

## 1.1.0

- Adds an **ingress panel**, so OpenSprinkler appears in the Home Assistant
  sidebar. No reverse proxy is involved: the UI derives its API base from
  `document.URL`, so it works unchanged behind ingress' path prefix.
- Port 88 is still published directly and is unaffected. Applications on the
  network that use the HTTP API keep working exactly as before — they cannot
  go through an ingress token, which is why both routes exist.

## 1.0.0

First release.

- Wraps `ghcr.io/rbhr/opensprinkler-firmware:v2.2.1.5-ospi.1` — upstream
  OpenSprinkler firmware 2.2.1(5) plus the Docker packaging fork.
- Runs with or without sprinkler hardware. The add-on logs which GPIO and I2C
  devices it found at startup, and the new `require_hardware` option turns a
  missing GPIO device from a silent no-op into a refusal to start.
- Web UI and HTTP API published directly on port 88, so other applications on
  the network can reach the controller.
- Firmware state is kept in `/data/opensprinkler`, away from Supervisor's
  `options.json`.
