# Changelog

## 0.10.0 - 2026-11-15

- Interactive menu when run without action parameters: recommended / full / klein / custom install,
  dry run, cleanup, uninstall. Confirmations before downloading, restarting ComfyUI, installing
  Creative Cloud.
- Custom preset picker (`-Presets` or the menu) with live download size; restricted licences need
  typing ACCEPT.
- `-Cleanup`: download cache, partial files, orphan markers, old logs, test images, leftovers;
  interactive review of installed models.
- `-Uninstall`: removes the plugin, stops ComfyUI, deletes the install folder.
- `-Yes` and `-NonInteractive` for unattended runs.
- Fix: Int32 overflow computing missing bytes on Windows PowerShell 5.1; 15.9 GB cards count as 16 GB.

## 0.9.0 - 2026-11-15

First public release (beta).

- Manifest-driven installer: models, folders, sizes, SHA256 and custom nodes come from
  OpenLayer's own generated `requirements.json`.
- GPU advisor: rates every OpenLayer preset OK / TIGHT / SLOW for the detected VRAM (same rule as
  OpenLayer's Setup outlook) and marks a FAST PICK and a QUALITY PICK for each tool.
- Quality guide tailored to the GPU, printed at the end and saved as `Quality-Guide.txt`.
- `-ModelSet Auto` (default: every freely-licensed preset that fits the GPU), `Full` (all
  freely-licensed models) and `Klein` (FLUX.2 [klein] 4B only).
- Licence-restricted models only with `-IncludeLicenseRestricted -AcceptLicenses`.
- Resumable `.part` downloads with size + SHA256 verification and cached verification markers.
- ComfyUI Portable install/update, PyTorch CUDA check, version checks.
- Custom nodes via git or GitHub zip, Python requirements installed with torch pinned.
- Hugging Face repository-folder models (Florence-2) downloaded file by file.
- OpenLayer install through Adobe UPI with `/list` verification and -631 / -641 diagnostics.
- Custom node load check and FLUX.2 [klein] end-to-end generation test via the ComfyUI API.
- `-DryRun`, JSON report, exit codes 0 / 2 / 1.
- CI: PSScriptAnalyzer, Pester on Windows PowerShell 5.1 and PowerShell 7, weekly manifest sync.
