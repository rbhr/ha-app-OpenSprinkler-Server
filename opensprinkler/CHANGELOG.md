# Changelog

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
