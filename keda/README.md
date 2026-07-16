# KEDA installer

## Getting a specific version

```bash
./download.sh [KEDA_VERSION] [HTTP_ADDON_VERSION]
```

`keda` and `keda-add-ons-http` are independently-versioned projects (e.g.
`keda` at `2.20.1`, the HTTP add-on at `0.15.0`) - they're separate,
optional arguments, not one shared version. Omit either (or both) to get
the latest published version for that chart instead.

```bash
./download.sh                    # latest of both
./download.sh 2.19.0              # pin keda, latest HTTP add-on
./download.sh 2.19.0 0.11.0       # pin both explicitly
```

Each run downloads, per chart:
- The Helm chart itself, into `charts/<name>/`
- Its images, saved to `<name>-images.tar`
- For `keda` only: the standalone CRD manifest, `keda-<version>-crds.yaml`
  (the HTTP add-on bundles its CRDs inline in its own chart instead, gated
  by its `crds.install` value - no separate manifest to fetch for it)

After downloading, update `install.sh`'s `VERSION=` variable to match the
`keda` version you just pulled - it's used to build the
`keda-${VERSION}-crds.yaml` filename applied via `kubectl apply
--server-side` (download.sh prints a reminder of this at the end).

## Install

```bash
./install.sh              # core KEDA operator + CRDs
./install-httpaddon.sh    # HTTP add-on (run after install.sh - it registers
                           # itself as an external scaler against KEDA)
```
