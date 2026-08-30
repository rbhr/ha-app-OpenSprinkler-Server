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
  workflow. The only place the firmware version is pinned. Both architectures
  name the same tag; the tag is a multi-arch manifest and the per-arch
  `--platform` resolves the right leg. **amd64 and aarch64 only** —
  `prepare-multi-arch-matrix` builds on native runners and has none for armv7,
  so it rejects that value outright.

  **The split builder actions do not read this file.** Only the old monolithic
  builder did, and Supervisor still does when a user builds the add-on locally
  from source. So the workflows parse the tag out of it in their `init` job and
  pass it to `build-image` as a `BUILD_FROM` build arg — leaving it out is a
  blank `FROM` and `base name (${BUILD_FROM}) should not be blank`. The init
  step also fails the run if the `build_from` entries disagree, since one
  `BUILD_FROM` is used for every architecture.
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
- **Ingress needs no proxy, and adding one would be a regression.** The UI
  derives its API base from `document.URL` — `home.js` does
  `document.URL.match( /(https?:\/\/.*)\/.*?/ )[ 1 ] + "/sp?pw=..."`, and the
  greedy `.*` takes everything up to the *last* slash — so behind ingress it
  produces `.../api/hassio_ingress/<token>/sp`, which Supervisor forwards to
  `/sp`. Verified end to end against a local stand-in for
  `supervisor/api/ingress.py`: the whole UI works and no request reached the
  add-on with a doubled slash.

  **Never set `ingress_entry`.** Supervisor builds the panel URL as
  `f"/api/hassio_ingress/{token}/"` and then appends `ingress_entry` to it
  *relative*, so `ingress_entry: /` yields `.../<token>//` and the add-on is
  asked for `//`. That shipped in 1.1.0 and broke the panel with OTF's "The
  requested page does not exist". `ha-app-C-Gate-Server` carries the same key
  — which is where its `//` came from, and why it needed hand-rolled routing.
  The key is for add-ons whose entry point is a file, e.g. deconz's
  `ingress_entry: ingress.html` (no leading slash).

  The `//` problem recorded in `ha-app-C-Gate-Server/CLAUDE.md` is therefore
  self-inflicted and does **not** generalise. Supervisor's route is `/ingress/{token}/{path:.*}` and its target
  is `f"http://{ip}:{port}/{path}"`, so a doubled slash only ever arrives
  because the *page* asked for one. C-Gate's did; OpenSprinkler's does not.
  Worth knowing, because `//` is a hard 404 here — the firmware routes `"/"`
  and `"/index.html"` explicitly and normalises nothing.
- **Add-on options must not shadow UI settings.** The firmware persists its own
  configuration in its data directory and exposes it in the web UI. Only things
  that must be decided before the binary starts belong in `config.yaml`.

  `password` and `ignore_password` are the two deliberate exceptions, added in
  1.2.0 because the sidebar panel is unusable-feeling when every browser has to
  be told the controller password. They are kept from becoming a shadow by
  being **optional and omitted from `options:`**, so Supervisor leaves them out
  of `options.json` entirely until the user sets one. Absent means "leave the
  controller alone"; set means "assert this on every start". Do not give either
  one a default — that would make every installation start overwriting its own
  UI settings. The same trick is the right answer for any future option that
  has to reach into the firmware's own configuration.
- **Reach into firmware settings over its HTTP API, never by writing `.dat`
  files.** `sopts.dat` is fixed 320-byte records (`MAX_SOPTS_SIZE`) with the
  password at index 0 as the md5 of the plaintext, and `iopts.dat` is one byte
  per option in enum order — both are internal layout that a firmware bump can
  move under us. `run.sh` instead waits for the controller's own server and
  calls `/sp?pw=&npw=&cpw=` and `/co?pw=&ipas=`, which are stable, documented,
  and validate what they are given. `/jo` is the readiness probe *and* the
  auth check: it answers 200 either way, with the full options when the
  password checks out and only `{"fwv":...}` when it does not, because
  `process_password()` is called there with `fwv_on_fail`.
- **There is no way to hand the UI a password.** The firmware serves `/` itself
  (`server_home`), the page is `var ver=…,ipas=…` plus a `<script>` pointing at
  `SOPT_JAVASCRIPTURL`, and `home.js` reads no query string — it prompts, then
  stores the hash per browser under `sites.Local`. The binary takes only `-d`.
  So the *only* lever that removes the prompt is `ipas`
  (`IOPT_IGNORE_PASSWORD`): `server_home` emits it into the page and `home.js`
  calls `savePassword( "" )` instead of asking. It is global —
  `process_password()` returns true for every request — so it unauthenticates
  port 88 too, and cannot be scoped to ingress. Anything that claims otherwise
  is proposing a proxy; see above for why there isn't one.

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
3. Verify the images landed. **Do not trust `gh run view --json status`
   alone** — it returns `completed` while jobs are still running, which is how
   a release once got reported as published while the manifest job was still
   going. Check that no job is unfinished:

   ```sh
   gh run view "$RID" --json status,jobs \
     -q '.status + " | unfinished: " + ([.jobs[] | select(.status != "completed")] | length | tostring)'
   ```

   Then check the registry directly — the GitHub Packages UI lags badly:

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

## Artwork

`opensprinkler/icon.png` and `logo.png` are generated by `art/mark.py` from
measurements of the OpenSprinkler wordmark. **Edit the script and re-render;
do not edit the PNGs.** The two deliberate departures from the measured
geometry, and why each is there, are documented in the script.

Artwork changes need **no release**: the store reads these from its clone of
this repository, not from the published image, so bumping `version:` would make
every user pull a new image for a cosmetic change. Merge to `main` and reload
the store.

## Not yet validated

**Nothing here has ever driven a real valve.** Every check so far — CI, the
local container runs, the ingress work — has been on hardware-free hosts. The
add-on reports which GPIO and I2C nodes it found at startup, and
`require_hardware` makes a missing one fatal, but the path from a program
running to a solenoid opening is untested.

Two specific unknowns behind that:

- Whether Supervisor tolerates a `devices:` entry whose node is absent. Docker
  Compose fails `up` outright on a missing device, which is why the firmware
  repo keeps `docker-compose.pi.yaml` as a separate overlay. This add-on
  declares four nodes and expects the missing ones to be skipped. If Supervisor
  turns out to be strict, that needs splitting or an option.
- Whether a Pi 5 resolves correctly. `init_lgpio()` picks gpiochip4 on bcm2712
  and gpiochip0 elsewhere, and both are declared, but only the firmware's own
  board detection decides — and it says nothing when it is wrong.
