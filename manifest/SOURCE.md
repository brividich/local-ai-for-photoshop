# Manifest provenance

`openlayer-requirements.json` is **generated, not hand-written**. It is the `requirements.json`
produced by OpenLayer's own setup-pack build (`npm run setup-pack`), which derives every model,
target folder, size, SHA256, licence gate and custom node package from OpenLayer's preset registry.

| Field | Value |
| --- | --- |
| OpenLayer version | 0.41.0 |
| OpenLayer commit | `aeebbbe4aa5bd3bdebca2e9b865e2a68dec29589` |
| Upstream | https://github.com/MehranMarxian/OpenLayer |
| Licence | MIT (OpenLayer) |

Do not edit it by hand: the `Update OpenLayer manifest` workflow rebuilds it from the latest
OpenLayer release every week and opens a pull request when something changed.
