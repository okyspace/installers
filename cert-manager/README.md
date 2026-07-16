# cert-manager installer

## Getting a specific version

```bash
./download.sh [VERSION]
```

Unlike the keda/kserve installers, this one does **not** resolve "latest"
dynamically - `VERSION` defaults to a version hardcoded in the script
(`v1.20.3` at time of writing). Check the top of `download.sh` if you want
to confirm or bump that default; otherwise just pass the version you want
explicitly:

```bash
./download.sh            # the hardcoded default
./download.sh v1.16.3    # pin explicitly
```

Downloads the chart as `cert-manager-<version>.tgz` (install.sh references
this file directly, not an extracted directory - update `install.sh`'s
`CHART=` line if you bump the version) and saves its images to
`cert-manager-images.tar`.

Note: `override.yaml` currently sets `crds.enabled: true` - CRDs are
templated and installed directly by `helm upgrade --install` in
`install.sh`, no separate `kubectl apply` step. (A separate-CRD-install
setup, gated by `crds.enabled: false` plus applying a matching static
manifest yourself, avoids Helm's large-CRD annotation-size issue on
upgrade - worth revisiting if that bites you, but it's not how this is
currently wired.)

## Install

```bash
./install.sh
```
