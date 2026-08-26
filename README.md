# OpenSprinkler Add-on Repository

A Home Assistant add-on repository containing one add-on: **OpenSprinkler**,
the [OpenSprinkler](https://opensprinkler.com/) Pi irrigation controller
firmware, packaged for Home Assistant and usable with or without sprinkler
hardware attached.

## Installation

Add this repository in Home Assistant — **Settings → Add-ons → Add-on Store →
⋮ → Repositories** — and paste:

```
https://github.com/rbhr/ha-app-OpenSprinkler-Server
```

Then install **OpenSprinkler** from the store. See
[the add-on documentation](opensprinkler/DOCS.md) for configuration.

## How this relates to the firmware

This repository contains **no firmware source**. The add-on image is built
`FROM` the multi-arch image published by
[rbhr/OpenSprinkler-Firmware](https://github.com/rbhr/OpenSprinkler-Firmware) —
a fork of
[OpenSprinkler/OpenSprinkler-Firmware](https://github.com/OpenSprinkler/OpenSprinkler-Firmware)
that adds Docker packaging — and adds only the Home Assistant contract on top:
the manifest, the add-on labels, and an entrypoint that reads `options.json`.

That keeps the two repositories from drifting apart, and makes pulling in an
upstream firmware release a one-line-per-architecture change here:

```
upstream ──► merge into the fork ──► tag a release ──► fork CI publishes the image
                                                   ──► bump opensprinkler/build.yaml
                                                   ──► release this add-on
```

`opensprinkler/build.yaml` is the only place the firmware version is pinned.

## Licence

The add-on's own files — manifest, entrypoint, workflows, documentation — are
MIT; see [LICENSE](LICENSE). The published **image** contains the OpenSprinkler
firmware, which is GPLv3, and is labelled accordingly.
