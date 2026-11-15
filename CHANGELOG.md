# Changelog

## 0.9.0 - 2026-11-15

First public release (beta).

- Manifest-driven installer: models, folders, sizes, SHA256 and custom nodes come from
  OpenLayer's own generated `requirements.json`.
- `-ModelSet Full` (all freely-licensed models) and `-ModelSet Klein` (FLUX.2 [klein] 4B only).
- Licence-restricted models only with `-IncludeLicenseRestricted -AcceptLicenses`.
- Resumable `.part` downloads with size + SHA256 verification and cached verification markers.
- ComfyUI Portable install/update, PyTorch CUDA check, version checks.
- Custom nodes via git or GitHub zip, Python requirements installed with torch pinned.
- Hugging Face repository-folder models (Florence-2) downloaded file by file.
- OpenLayer install through Adobe UPI with `/list` verification and -631 / -641 diagnostics.
- Custom node load check and FLUX.2 [klein] end-to-end generation test via the ComfyUI API.
- `-DryRun`, JSON report, exit codes 0 / 2 / 1.
- CI: PSScriptAnalyzer, Pester on Windows PowerShell 5.1 and PowerShell 7, weekly manifest sync.
