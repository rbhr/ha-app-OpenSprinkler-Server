# Changelog

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
