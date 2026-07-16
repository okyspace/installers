# KServe installer

## Getting a specific version

```bash
./download.sh [VERSION] [CRD_REF]
```

`kserve-crd`, `kserve-resources`, and `kserve-runtime-configs` are all
published by the same KServe project under one shared version, so a single
`VERSION` argument pins all three (defaults to `v0.19.0` if omitted).
`CRD_REF` is a separate git ref (branch/tag/commit) used only for pulling
`kserve-crd` from source - it isn't published as a release asset or to the
OCI registry the way the other two charts are (defaults to `master`).

```bash
./download.sh                  # v0.19.0, kserve-crd from master
./download.sh v0.17.1           # pin all three charts to v0.17.1
./download.sh v0.17.1 release-0.17  # also pin kserve-crd's source ref
```

To see what versions are actually published before picking one:

```bash
./download.sh --list-versions                    # kserve-resources tags (default)
./download.sh --list-versions kserve-runtime-configs
```

(Requires `helm registry login ghcr.io` once beforehand, or `GHCR_USER`/
`GHCR_TOKEN` set - see the script's `ghcr_credentials()` for details.)

Each run also downloads controller + enabled-runtime container images into
`images/` (see `override-runtimes.yaml` for which runtimes are enabled -
keep that list in sync manually if you change it).

## Install

Run in order - `01` and `02` must exist before `03`'s ClusterServingRuntimes
are usable, and `02` needs cert-manager already installed (webhook CA
injection):

```bash
./01.install-crd.sh
./02.install-controller.sh
./03.install-runtimes.sh
```
