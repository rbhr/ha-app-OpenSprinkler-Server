# Working on this repository

A Home Assistant add-on repository wrapping the OpenSprinkler Pi irrigation
controller firmware. It deliberately contains **no firmware source**.

## The one idea to keep intact

`opensprinkler/Dockerfile` is `FROM ${BUILD_FROM}`, and `BUILD_FROM` comes from
`opensprinkler/build.yaml`, which names an image published by
[rbhr/OpenSprinkler-Firmware](https://github.com/rbhr/OpenSprinkler-Firmware).
Everything this repository adds is the Home Assistant contract on top of an
image that already works standalone under plain Docker.

The sibling C-Gate pair (`ha-app-C-Gate-Server` and `C-Gate-Server-Container`)
shows the failure mode this avoids: they carry duplicate copies of `web/main.go`,
`config/`, `tag/` and the whole C-Gate distribution, and the two drift.

**Do not vendor firmware source, build the firmware here, or float the base on
`:master`.** Supervisor caches by add-on version, so a floating base means the
add-on version no longer identifies what a user is running.

## Layout

- `opensprinkler/config.yaml` — add-on manifest. **`version:` is the published
  image tag**, so it must be bumped for every release.
- `opensprinkler/build.yaml` — the Home Assistant builder's config, *not* a
  workflow. The only place the firmware version is pinned. All three
  architectures name the same tag; the tag is a multi-arch manifest and the
  builder's per-arch `--platform` resolves the right one. **amd64 and aarch64
  only** — `prepare-multi-arch-matrix` builds on native runners and has none
  for armv7, so it rejects that value outright.
- `opensprinkler/run.sh` — the entrypoint. Reads `options.json`, creates the
  data directory, probes for hardware, then `exec`s the firmware as PID 1.
- `.github/workflows/test-build.yaml` — named that way so it is not mistaken
  for `opensprinkler/build.yaml`.

## Things that will bite

- **`CMD []` in the Dockerfile is load-bearing.** The base image sets
  `CMD ["/OpenSprinkler/OpenSprinkler", "-d", "/data"]`. Without clearing it,
  Docker passes those to `ENTRYPOINT ["/run.sh"]` as arguments and the firmware
  gets the wrong data directory.
- **The firmware writes to whatever `-d` names, and Supervisor owns `/data`.**
  `run.sh` passes `/data/opensprinkler` to keep `.dat` files and `logs/` away
  from `options.json`. `get_filename_fullpath()` (`utils.cpp`) appends the
  trailing slash but never creates the directory — `run.sh` must `mkdir -p`.
- **GPIO failure is silent.** `init_lgpio()` (`gpio.cpp`) opens gpiochip4 on a
  Pi 5 and gpiochip0 elsewhere, falling back 4 → 0; every failure path is a
  `DEBUG_PRINTLN`, which compiles to nothing in a release build. The UI stays
  up, the add-on stays green, and no valve opens. That is the entire reason
  `run.sh` probes and the `require_hardware` option exists.
- **The base image must be a public GHCR package.** `GITHUB_TOKEN` is scoped to
  this repository and cannot pull a private package from
  `rbhr/OpenSprinkler-Firmware`.
- **Add-on options must not shadow UI settings.** The firmware persists its own
  configuration in its data directory and exposes it in the web UI. Only things
  that must be decided before the binary starts belong in `config.yaml`.

## Testing locally

**Pass `--pull`.** Without it Docker reuses whatever it already has under that
tag, and `:master` in particular moves. A cached base from weeks earlier builds
and runs perfectly while silently being the wrong firmware — the symptom is the
controller answering on 8080 rather than 88, because the port default changed
in `b97ccd9`.

```sh
cd opensprinkler
docker build --pull --build-arg BUILD_FROM=ghcr.io/rbhr/opensprinkler-firmware:<tag> -t os-addon .

mkdir -p /tmp/osdata && echo '{"require_hardware": false}' > /tmp/osdata/options.json
docker run --rm -p 8888:88 -v /tmp/osdata:/data os-addon
```

Check the startup banner reports the hardware it found, that the UI answers on
8888, and that `.dat` files land in `/tmp/osdata/opensprinkler` rather than
`/tmp/osdata`.

## Releasing

Branch, PR, merge — `main` is not committed to directly. Then:

1. Bump `version:` in `opensprinkler/config.yaml` and add a `CHANGELOG.md`
   entry (both under `opensprinkler/`). If the firmware changed, bump the tags
   in `build.yaml` too and say which build in the changelog.
2. `git tag vX.Y.Z && git push origin vX.Y.Z`, then `gh release create vX.Y.Z`.
   Publishing the release triggers `.github/workflows/publish.yaml`.
3. Verify the images landed — the GitHub Packages UI lags badly:

```sh
repo=rbhr/aarch64-opensprinkler
token=$(curl -s "https://ghcr.io/token?scope=repository:${repo}:pull&service=ghcr.io" | jq -r .token)
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $token" \
  -H "Accept: application/vnd.oci.image.index.v1+json" \
  "https://ghcr.io/v2/${repo}/manifests/X.Y.Z"
```

4. Home Assistant still shows the old version until Supervisor re-pulls its
   cached clone: **Settings → Add-ons → Add-on Store → ⋮ → Check for updates**,
   or `ha store reload`. The ⋮ menu on the add-on's own page does not do it.

## Pulling in a new firmware release

In `rbhr/OpenSprinkler-Firmware`: `git fetch upstream && git merge
upstream/master`, then tag and release it — its `CLAUDE.md` has the conflict
surface and the tag scheme. Then here: bump the tags in `build.yaml`, bump
`version:` in `config.yaml`, changelog, release.

## Not yet done

- `icon.png` and `logo.png` are missing; Home Assistant falls back to a generic
  icon until they are added.
- Ingress is not enabled. It looks viable — the UI derives its API base from
  `document.URL` rather than using root-absolute paths — but it is unverified.
  See the plan notes; port 88 must keep working regardless, because other
  applications on the network use the HTTP API.
