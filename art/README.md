# Mark

`mark.py` generates `opensprinkler/icon.png` and `opensprinkler/logo.png`.
It needs only Python 3 and `rsvg-convert`:

```sh
python3 art/mark.py art && cp art/icon.png art/logo.png opensprinkler/
```

The spray is measured from the OpenSprinkler wordmark rather than drawn by eye
— droplet positions, radii and the two colours are all sampled from it, and the
two deliberate departures from those measurements are documented in the script.

Changing these images needs **no add-on release**: the Home Assistant store
reads them from its clone of this repository, not from the published image.
Bumping `version:` for artwork would make every user pull a new image for a
cosmetic change. Merge to `main` and reload the store instead.
