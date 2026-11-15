#Requires -Version 5.1
<#
.SYNOPSIS
  Local, offline AI for Adobe Photoshop on Windows + NVIDIA: ComfyUI Portable, the OpenLayer
  Photoshop plugin, every custom node and every freely-licensed model OpenLayer can use.

.DESCRIPTION
  Unofficial community installer. Not affiliated with Adobe, Comfy Org, Black Forest Labs or
  the OpenLayer project. It does NOT install, activate or license Photoshop or Creative Cloud.

  What it does, idempotently and resumably:
    1. Pre-flight checks: Windows x64, NVIDIA GPU, VRAM, RAM, driver, free disk, curl, 7-Zip.
    2. Installs ComfyUI Portable (NVIDIA build) from the official Comfy-Org GitHub release,
       verified by SHA256 when GitHub publishes a digest, extracted atomically.
    3. Verifies PyTorch + CUDA inside ComfyUI's embedded Python.
    4. Reads OpenLayer's requirements manifest (generated from OpenLayer's own preset
       registry) and downloads every model whose licence is not restricted, each one
       size- and SHA256-verified, resumable (.part files), into the exact ComfyUI folder.
    5. Installs the ComfyUI custom node packages those presets need (git clone if Git is
       available, otherwise a GitHub zip), plus their Python requirements with the installed
       torch pinned so a custom node can never downgrade it.
    6. Installs the OpenLayer .ccx through Adobe's Unified Plugin Installer Agent and checks
       that Photoshop actually lists it.
    7. Starts ComfyUI on 127.0.0.1, confirms every custom node class is loaded, and runs an
       end-to-end FLUX.2 [klein] 4B generation through the ComfyUI API.
    8. Writes a JSON report (Logs\report-*.json and last-report.json).

  Exit codes: 0 = everything OK, 2 = finished with warnings / skipped steps, 1 = error.

.PARAMETER Root
  Install folder. Default: D:\AI\PhotoshopLocalAI if D: exists, otherwise C:\AI\PhotoshopLocalAI.
.PARAMETER ModelSet
  Full  (default) every model without a restricted licence (~126 GB) and the custom nodes they need.
  Klein only the FLUX.2 [klein] 4B stack (~12.5 GB, Apache-2.0) and the nodes its presets need.
.PARAMETER IncludeLicenseRestricted
  Also download non-commercial / research-only models (FLUX.1 dev, FLUX.2 dev, Qwen-Image 2.1).
  Requires -AcceptLicenses after you have read each licence.
.PARAMETER Sd15CheckpointUrl
  Optional direct URL of an SD 1.5 checkpoint (.safetensors). OpenLayer's Sketch to Image,
  SD inpaint and Style Reference presets need one; none is bundled because the choice is yours.
.PARAMETER DryRun
  Run the pre-flight checks, print what would be installed and the download size, then stop.
.PARAMETER RestartComfyUI
  If a ComfyUI from this install is already running, stop it and start it again so new custom
  nodes and updates are loaded. Only a process whose executable lives under -Root is touched.
.PARAMETER InstallCreativeCloud
  Install the Adobe Creative Cloud desktop app with winget if it is missing (needed by the
  plugin installer; sign in with any Adobe account, a free one works).
.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-LocalAI.ps1
.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-LocalAI.ps1 -ModelSet Klein -DryRun
.LINK
  https://github.com/brividich/local-ai-for-photoshop
#>
[CmdletBinding()]
param(
    [string]$Root = '',
    [ValidateSet('Full', 'Klein')][string]$ModelSet = 'Full',
    [switch]$IncludeLicenseRestricted,
    [switch]$AcceptLicenses,
    [string]$Sd15CheckpointUrl = '',
    [ValidateRange(1024, 65535)][int]$Port = 8188,
    [string]$ComfyArgs = '',
    [string]$ManifestPath = '',
    [switch]$SkipModels,
    [switch]$SkipCustomNodes,
    [switch]$SkipPlugin,
    [switch]$SkipTest,
    [switch]$NoStart,
    [switch]$UpdateComfyUI,
    [switch]$RestartComfyUI,
    [switch]$InstallCreativeCloud,
    [switch]$SkipHardwareCheck,
    [switch]$ForceRedownload,
    [switch]$DryRun,
    [ValidateRange(60, 7200)][int]$TestTimeoutSec = 900
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# =============================================================================================
# Constants
# =============================================================================================
$script:InstallerVersion = '0.9.0'
$script:ProjectRepo      = 'brividich/local-ai-for-photoshop'
$script:ManifestRawUrl   = "https://raw.githubusercontent.com/$($script:ProjectRepo)/main/manifest/openlayer-requirements.json"
$script:ComfyRepo        = 'Comfy-Org/ComfyUI'
$script:ComfyAssetRegex  = '^ComfyUI_windows_portable_nvidia\.7z$'
$script:PluginRepo       = 'MehranMarxian/OpenLayer'
$script:PluginRegex      = '^openlayer.*\.ccx$'
$script:KleinModels      = @('flux-2-klein-4b-fp8.safetensors', 'qwen_3_4b.safetensors', 'flux2-vae.safetensors')
$script:MinFreeMarginGB  = 10
$script:MinVramMiB       = 6144
$script:RecVramMiB       = 8192
$script:RecRamGB         = 16
$script:MinDriverMajor   = 580     # current portable build ships CUDA 13.0
$script:MinPsMajor       = 25      # Photoshop 2024 = 25.x (OpenLayer manifest minVersion 25.0.0)
$script:MinComfyVersion  = '0.9.1' # version the official FLUX.2 klein template was saved with
$script:UpiPath          = Join-Path ([string]${env:CommonProgramFiles} + '\') 'Adobe\Adobe Desktop Common\RemoteComponents\UPI\UnifiedPluginInstallerAgent\UnifiedPluginInstallerAgent.exe'
$script:UserAgent        = "local-ai-for-photoshop/$($script:InstallerVersion)"

# =============================================================================================
# Logging and report
# =============================================================================================
function Write-Step([string]$Message) { Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message) -ForegroundColor Cyan }
function Write-Ok([string]$Message)   { Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message) -ForegroundColor Green }
function Add-Warning([string]$Message) {
    Write-Warning $Message
    if ($script:Report) { [void]$script:Report.warnings.Add($Message) }
}
function Stop-Install([string]$Message) { throw $Message }

function New-Report {
    return [ordered]@{
        schema     = 'local-ai-for-photoshop/report/v2'
        installer  = $script:InstallerVersion
        started    = (Get-Date).ToString('o')
        finished   = $null
        status     = 'running'
        dryRun     = [bool]$DryRun
        root       = $script:Root
        parameters = [ordered]@{
            ModelSet = $ModelSet; IncludeLicenseRestricted = [bool]$IncludeLicenseRestricted; Port = $Port
            ComfyArgs = $ComfyArgs; SkipModels = [bool]$SkipModels; SkipCustomNodes = [bool]$SkipCustomNodes
            SkipPlugin = [bool]$SkipPlugin; SkipTest = [bool]$SkipTest; NoStart = [bool]$NoStart
            UpdateComfyUI = [bool]$UpdateComfyUI; RestartComfyUI = [bool]$RestartComfyUI
        }
        system      = [ordered]@{}
        comfyui     = [ordered]@{ status = 'pending' }
        cuda        = [ordered]@{ status = 'pending' }
        manifest    = [ordered]@{}
        models      = New-Object System.Collections.ArrayList
        customNodes = New-Object System.Collections.ArrayList
        plugin      = [ordered]@{ status = 'pending' }
        test        = [ordered]@{ status = 'pending' }
        warnings    = New-Object System.Collections.Generic.List[string]
        error       = $null
        log         = $script:LogFile
    }
}

function Save-Report {
    if (-not $script:Report) { return }
    try {
        $script:Report.finished = (Get-Date).ToString('o')
        $json = $script:Report | ConvertTo-Json -Depth 10
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText((Join-Path $script:Logs "report-$($script:RunStamp).json"), $json, $utf8)
        [System.IO.File]::WriteAllText((Join-Path $script:Root 'last-report.json'), $json, $utf8)
    } catch { Write-Warning "Could not write the JSON report: $_" }
}

# =============================================================================================
# Generic helpers
# =============================================================================================
function Get-FreeGB([string]$Path) {
    $drive = New-Object System.IO.DriveInfo([System.IO.Path]::GetPathRoot($Path))
    return [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N2} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

function ConvertTo-Sha256([string]$Digest) {
    # GitHub publishes "sha256:<hex>", Hugging Face the bare hex in lfs.oid.
    if (-not $Digest) { return '' }
    $hex = $Digest -replace '^sha256:', ''
    if ($hex -match '^[0-9a-fA-F]{64}$') { return $hex.ToLowerInvariant() }
    return ''
}

function ConvertTo-VersionObject([string]$Text) {
    $m = [regex]::Match([string]$Text, '\d+(\.\d+){1,3}')
    if ($m.Success) { return [version]$m.Value }
    return $null
}

function Get-RequestHeaders([string]$Url) {
    $h = @{ 'User-Agent' = $script:UserAgent }
    if ($Url -match '^https://huggingface\.co/' -and $env:HF_TOKEN) { $h['Authorization'] = "Bearer $($env:HF_TOKEN)" }
    if ($Url -match '^https://api\.github\.com/') {
        $h['Accept'] = 'application/vnd.github+json'
        if ($env:GITHUB_TOKEN) { $h['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
    }
    return $h
}

function Invoke-Json([string]$Url, [string]$Method = 'Get', $Body = $null, [int]$TimeoutSec = 60) {
    $params = @{ Uri = $Url; Method = $Method; Headers = (Get-RequestHeaders $Url); TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
    if ($null -ne $Body) { $params['Body'] = $Body }
    $response = Invoke-RestMethod @params
    # Windows PowerShell 5.1 returns a JSON array as one object: piping it unrolls the elements.
    return , @($response | ForEach-Object { $_ })
}

function Invoke-Native {
    # Runs a native command without letting stderr become a terminating error (PS 5.1 + 2>&1),
    # returns its output lines and leaves $LASTEXITCODE set.
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @(), [switch]$Quiet)
    $ErrorActionPreference = 'Continue'
    $lines = & $FilePath @Arguments 2>&1 | ForEach-Object { "$_" }
    if (-not $Quiet) { $lines | ForEach-Object { Write-Host "    $_" } }
    return , @($lines)
}

function Get-HttpErrorBody($ErrorRecord) {
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) { return $ErrorRecord.ErrorDetails.Message }
    try {
        $resp = $ErrorRecord.Exception.Response
        if ($resp) { return (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd() }
    } catch { }
    return $ErrorRecord.Exception.Message
}

# =============================================================================================
# Downloads with real resume and integrity checks
# =============================================================================================
function Test-FileIntegrity([string]$Path, [int64]$Size, [string]$Sha256) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $Path
    if ($Size -gt 0 -and $item.Length -ne $Size) { return $false }
    if (-not $Sha256) { return $true }
    # A marker keyed on size + mtime + expected hash avoids re-hashing multi-GB files on every run.
    $marker = "$Path.verified"
    $stamp = '{0}|{1}|{2}' -f $item.Length, $item.LastWriteTimeUtc.Ticks, $Sha256
    if ((Test-Path -LiteralPath $marker) -and ((Get-Content -LiteralPath $marker -Raw).Trim() -eq $stamp)) { return $true }
    Write-Step "Verifying SHA256: $(Split-Path $Path -Leaf)"
    $ok = ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ieq $Sha256)
    if ($ok) { Set-Content -LiteralPath $marker -Value $stamp -Encoding ASCII }
    return $ok
}

function Invoke-Download([string]$Url, [string]$Destination, [int64]$Size, [string]$Sha256) {
    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
    $leaf = Split-Path $Destination -Leaf
    if (-not $ForceRedownload -and (Test-FileIntegrity $Destination $Size $Sha256)) { Write-Step "Already present and verified: $leaf"; return }
    if (Test-Path -LiteralPath $Destination) {
        Write-Step "Replacing invalid or outdated file: $leaf"
        Remove-Item -LiteralPath $Destination -Force
        Remove-Item -LiteralPath "$Destination.verified" -Force -ErrorAction SilentlyContinue
    }
    $part = "$Destination.part"
    if ($ForceRedownload -and (Test-Path -LiteralPath $part)) { Remove-Item -LiteralPath $part -Force }
    if ((Test-Path -LiteralPath $part) -and $Size -gt 0 -and (Get-Item -LiteralPath $part).Length -gt $Size) {
        Remove-Item -LiteralPath $part -Force
    }
    $have = 0
    if (Test-Path -LiteralPath $part) { $have = (Get-Item -LiteralPath $part).Length }
    if (-not ($Size -gt 0 -and $have -eq $Size)) {
        if ($Size -gt 0 -and (Get-FreeGB $Destination) -lt ((($Size - $have) / 1GB) + 1)) {
            Stop-Install "Not enough disk space for $leaf ($(Format-Size ($Size - $have)) still to download)."
        }
        if ($have -gt 0) { Write-Step ('Resuming {0} at {1} of {2}' -f $leaf, (Format-Size $have), (Format-Size $Size)) }
        else { Write-Step ('Downloading {0} ({1})' -f $leaf, $(if ($Size -gt 0) { Format-Size $Size } else { 'unknown size' })) }
        $curlArgs = @('--fail', '--location', '--continue-at', '-', '--retry', '10', '--retry-delay', '5',
                      '--retry-all-errors', '--connect-timeout', '30', '--speed-limit', '10240', '--speed-time', '120',
                      '--output', $part)
        $headers = Get-RequestHeaders $Url
        foreach ($k in $headers.Keys) { $curlArgs += @('--header', ('{0}: {1}' -f $k, $headers[$k])) }
        $curlArgs += $Url
        & curl.exe @curlArgs
        if ($LASTEXITCODE -ne 0) { Stop-Install "Download interrupted (curl exit $LASTEXITCODE): $leaf. Run the installer again to resume." }
    }
    $length = (Get-Item -LiteralPath $part).Length
    if ($Size -gt 0 -and $length -ne $Size) { Stop-Install "Wrong size for ${leaf}: $length instead of $Size bytes. Run again to resume." }
    Move-Item -LiteralPath $part -Destination $Destination -Force
    if (-not (Test-FileIntegrity $Destination $Size $Sha256)) {
        Remove-Item -LiteralPath $Destination -Force
        Stop-Install "SHA256 mismatch for ${leaf}: file deleted, run the installer again."
    }
    if (-not $Sha256 -and $Size -gt 0) { Add-Warning "No published hash for ${leaf}: only the size was verified." }
    Write-Ok "OK: $leaf"
}

# =============================================================================================
# GitHub / Hugging Face metadata
# =============================================================================================
function Get-GitHubAsset([string]$Repo, [string]$Pattern, [switch]$LatestOnly) {
    $url = if ($LatestOnly) { "https://api.github.com/repos/$Repo/releases/latest" } else { "https://api.github.com/repos/$Repo/releases?per_page=30" }
    foreach ($release in (Invoke-Json $url)) {
        if ($release.draft) { continue }
        $asset = @($release.assets | Where-Object { $_.name -match $Pattern }) | Select-Object -First 1
        if ($asset) {
            $digest = ''
            if ($asset.PSObject.Properties['digest']) { $digest = [string]$asset.digest }
            return [pscustomobject]@{
                Name = [string]$asset.name; Url = [string]$asset.browser_download_url; Size = [int64]$asset.size
                Sha256 = (ConvertTo-Sha256 $digest); Tag = [string]$release.tag_name
            }
        }
    }
    Stop-Install "No release asset matching '$Pattern' found in $Repo."
}

function Get-HuggingFaceRepoFiles([string]$RepoId) {
    $entries = Invoke-Json "https://huggingface.co/api/models/$RepoId/tree/main?recursive=true"
    return @($entries | Where-Object { $_.type -eq 'file' } | ForEach-Object {
        $lfs = $null
        if ($_.PSObject.Properties['lfs']) { $lfs = $_.lfs }
        [pscustomobject]@{
            Path   = [string]$_.path
            Size   = $(if ($lfs) { [int64]$lfs.size } else { [int64]$_.size })
            Sha256 = $(if ($lfs) { ConvertTo-Sha256 ([string]$lfs.oid) } else { '' })
        }
    })
}

# =============================================================================================
# Manifest (OpenLayer requirements.json, generated from OpenLayer's preset registry)
# =============================================================================================
function Get-Manifest {
    $candidates = @()
    if ($ManifestPath) { $candidates += $ManifestPath }
    if ($PSScriptRoot) { $candidates += (Join-Path $PSScriptRoot 'manifest\openlayer-requirements.json') }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) {
            Write-Step "Manifest: $c"
            return (Get-Content -LiteralPath $c -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
    }
    $cache = Join-Path $script:Downloads 'openlayer-requirements.json'
    Write-Step "Manifest not found next to the script: downloading $($script:ManifestRawUrl)"
    Invoke-WebRequest -Uri $script:ManifestRawUrl -OutFile $cache -UseBasicParsing -Headers (Get-RequestHeaders $script:ManifestRawUrl) | Out-Null
    return (Get-Content -LiteralPath $cache -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Test-ModelRestricted($Model) {
    return [bool]($Model.PSObject.Properties['licenseGate'] -and $Model.licenseGate)
}

# Picks the models and custom node packages for the chosen model set.
# A preset is "enabled" when every model it needs is selected; a custom node package is
# installed when at least one enabled preset uses it. Presets that need no listed model
# (e.g. the Superprompt prompt enhancer) count only for the Full set.
function Resolve-InstallPlan($Manifest) {
    $allModels = @($Manifest.models)
    $selected = switch ($ModelSet) {
        'Klein' { @($allModels | Where-Object { $script:KleinModels -contains $_.modelName }) }
        default { @($allModels | Where-Object { $IncludeLicenseRestricted -or -not (Test-ModelRestricted $_) }) }
    }
    $restricted = @($selected | Where-Object { Test-ModelRestricted $_ })
    if ($restricted.Count -gt 0 -and -not $AcceptLicenses) {
        foreach ($m in $restricted) {
            Write-Host ("  {0}: {1} - {2}" -f $m.modelName, $m.licenseGate.name, $m.licenseGate.url) -ForegroundColor Yellow
        }
        Stop-Install '-IncludeLicenseRestricted needs -AcceptLicenses after you have read the licences listed above.'
    }
    $selectedKeys = @($selected | ForEach-Object { $_.key })
    $enabledPresets = @($Manifest.presets | Where-Object {
        $keys = @($_.modelKeys)
        ($keys.Count -gt 0 -or $ModelSet -eq 'Full') -and @($keys | Where-Object { $selectedKeys -notcontains $_ }).Count -eq 0
    })
    $nodeNames = @($enabledPresets | ForEach-Object { @($_.customNodePackages) } | Where-Object { $_ } | Sort-Object -Unique)
    $nodes = @($Manifest.customNodes | Where-Object { $nodeNames -contains $_.name })
    $skippedRestricted = @($allModels | Where-Object { (Test-ModelRestricted $_) -and ($selectedKeys -notcontains $_.key) })
    return [pscustomobject]@{
        Models = @($selected); CustomNodes = @($nodes); Presets = $enabledPresets; SkippedRestricted = $skippedRestricted
    }
}

function Get-ModelPath($Model) {
    $dir = Join-Path $script:ComfyDir (($Model.targetPath -replace '^models/', 'models\') -replace '/', '\')
    return (Join-Path $dir $Model.modelName)
}

function Get-ModelMissingBytes($Model) {
    if ($Model.layout -eq 'repo-folder') {
        if (Test-Path -LiteralPath (Get-ModelPath $Model)) { return 0 }
        return 0   # size unknown until the repository is listed
    }
    $path = Get-ModelPath $Model
    if (Test-ModelPresent $Model) { return 0 }
    $have = 0
    if (Test-Path -LiteralPath "$path.part") { $have = (Get-Item -LiteralPath "$path.part").Length }
    $size = 0
    if ($Model.PSObject.Properties['sizeBytes'] -and $Model.sizeBytes) { $size = [int64]$Model.sizeBytes }
    return [math]::Max(0, $size - $have)
}

function Test-ModelPresent($Model) {
    $path = Get-ModelPath $Model
    if (Test-Path -LiteralPath $path) {
        if ($Model.layout -eq 'repo-folder') { return $true }
        $size = 0
        if ($Model.PSObject.Properties['sizeBytes'] -and $Model.sizeBytes) { $size = [int64]$Model.sizeBytes }
        return ($size -le 0 -or (Get-Item -LiteralPath $path).Length -eq $size)
    }
    # Alternative file names OpenLayer accepts for the same loader (e.g. lucida.safetensors).
    if ($Model.PSObject.Properties['acceptedModelNames']) {
        foreach ($alt in @($Model.acceptedModelNames)) {
            if (Test-Path -LiteralPath (Join-Path (Split-Path $path -Parent) $alt)) { return $true }
        }
    }
    return $false
}

function Install-Model($Model) {
    $path = Get-ModelPath $Model
    $entry = [ordered]@{
        file = $Model.modelName; folder = $Model.targetFolder; label = $Model.label
        restricted = (Test-ModelRestricted $Model); status = 'pending'; verification = $null
    }
    try {
        if ($Model.layout -eq 'repo-folder') {
            $repoId = ([uri]$Model.downloadUrl).AbsolutePath.Trim('/')
            Write-Step "Model folder $($Model.modelName) (Hugging Face repo $repoId)"
            $files = Get-HuggingFaceRepoFiles $repoId
            foreach ($f in $files) {
                Invoke-Download "https://huggingface.co/$repoId/resolve/main/$((($f.Path -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')" (Join-Path $path ($f.Path -replace '/', '\')) $f.Size $f.Sha256
            }
            $entry.verification = 'per-file'
        } else {
            $sha = ''
            if ($Model.PSObject.Properties['sha256']) { $sha = ConvertTo-Sha256 ([string]$Model.sha256) }
            $size = 0
            if ($Model.PSObject.Properties['sizeBytes'] -and $Model.sizeBytes) { $size = [int64]$Model.sizeBytes }
            $alternative = $false
            if (-not (Test-Path -LiteralPath $path) -and (Test-ModelPresent $Model)) { $alternative = $true }
            if ($alternative) { Write-Step "Accepted alternative already present for $($Model.modelName)"; $entry.verification = 'alternative-file' }
            else {
                Invoke-Download $Model.downloadUrl $path $size $sha
                $entry.verification = $(if ($sha) { 'sha256' } else { 'size' })
            }
        }
        $entry.status = 'ok'
    } catch {
        $entry.status = 'failed'
        $entry.error = $_.Exception.Message
        Add-Warning "Model $($Model.modelName) failed: $($_.Exception.Message)"
    }
    [void]$script:Report.models.Add($entry)
}

# =============================================================================================
# Tools: 7-Zip, Git, Photoshop, Creative Cloud
# =============================================================================================
function Find-Executable([string[]]$Candidates, [string]$CommandName) {
    $hit = $Candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if ($hit) { return $hit }
    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-SevenZip {
    $paths = @((Join-Path $env:ProgramFiles '7-Zip\7z.exe'), (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe'))
    $seven = Find-Executable $paths '7z.exe'
    if ($seven) { return $seven }
    if ($DryRun) { return '(7-Zip would be installed with winget)' }
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) { Stop-Install '7-Zip and winget are both missing. Install 7-Zip from https://7-zip.org and run again.' }
    Write-Step 'Installing 7-Zip with winget.'
    [void](Invoke-Native $winget.Source @('install', '--id', '7zip.7zip', '--exact', '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements', '--silent'))
    if ($LASTEXITCODE -ne 0) { Stop-Install "7-Zip installation failed (winget exit $LASTEXITCODE)." }
    $seven = Find-Executable $paths '7z.exe'
    if (-not $seven) { Stop-Install '7-Zip was installed but 7z.exe was not found.' }
    return $seven
}

function Get-Git {
    return (Find-Executable @((Join-Path $env:ProgramFiles 'Git\cmd\git.exe')) 'git.exe')
}

function Find-Photoshop {
    $found = @()
    $base = Join-Path $env:ProgramFiles 'Adobe'
    if (Test-Path $base) {
        foreach ($dir in Get-ChildItem -Path $base -Directory -Filter 'Adobe Photoshop*' -ErrorAction SilentlyContinue) {
            $exe = Join-Path $dir.FullName 'Photoshop.exe'
            if (Test-Path $exe) {
                $v = (Get-Item $exe).VersionInfo
                $found += [pscustomobject]@{ Path = $exe; Major = $v.FileMajorPart; Version = $v.FileVersion }
            }
        }
    }
    return , @($found | Sort-Object Major -Descending)
}

function Test-OpenLayerInstalled {
    $out = Invoke-Native $script:UpiPath @('/list', 'all') -Quiet
    return [bool](($out -join "`n") -match '\bOpenLayer\b')
}

# =============================================================================================
# ComfyUI
# =============================================================================================
function Get-ComfyLocalVersion {
    $f = Join-Path $script:ComfyDir 'comfyui_version.py'
    if (-not (Test-Path $f)) { return $null }
    $m = [regex]::Match((Get-Content $f -Raw), '__version__\s*=\s*[''"]([^''"]+)[''"]')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Test-ComfyVersion([string]$Version, [string]$Source) {
    $have = ConvertTo-VersionObject $Version
    if (-not $have) { Add-Warning "Could not determine the ComfyUI version ($Source)."; return $false }
    if ($have -lt (ConvertTo-VersionObject $script:MinComfyVersion)) {
        Add-Warning "ComfyUI $Version ($Source) is older than $($script:MinComfyVersion): FLUX.2 klein may not work. Run again with -UpdateComfyUI."
        return $false
    }
    Write-Ok "ComfyUI $Version ($Source)"
    return $true
}

function Test-ComfyApi {
    try { $null = Invoke-RestMethod "http://127.0.0.1:$Port/system_stats" -TimeoutSec 3 -UseBasicParsing; return $true } catch { return $false }
}

function Get-ComfyProcess {
    # Only a process listening on our port whose executable lives under our install folder.
    try {
        $conn = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop | Select-Object -First 1
        $proc = Get-Process -Id $conn.OwningProcess -ErrorAction Stop
        if ($proc.Path -and $proc.Path.StartsWith($script:Root, [System.StringComparison]::OrdinalIgnoreCase)) { return $proc }
    } catch { }
    return $null
}

function Install-ComfyUI([string]$SevenZip) {
    $python = $script:Python
    if ((Test-Path $python) -and (Test-Path (Join-Path $script:ComfyDir 'main.py'))) {
        $before = Get-ComfyLocalVersion
        Write-Step "ComfyUI already installed (version $before)."
        $script:Report.comfyui.status = 'existing'
        $script:Report.comfyui.versionBefore = $before
        if ($UpdateComfyUI) {
            $updater = Join-Path $script:InstallDir 'update\update.py'
            if (-not (Test-Path $updater)) { Add-Warning "Updater not found: $updater"; return }
            if ((Test-ComfyApi) -and -not $RestartComfyUI) { Add-Warning "ComfyUI is running on port ${Port}: the old version stays active until it is restarted (use -RestartComfyUI)." }
            Write-Step 'Updating ComfyUI (official portable updater).'
            Push-Location $script:InstallDir
            try { [void](Invoke-Native $python @('-s', $updater, 'ComfyUI\')) } finally { Pop-Location }
            if ($LASTEXITCODE -ne 0) { Add-Warning "ComfyUI update exited with code $LASTEXITCODE." } else { $script:Report.comfyui.status = 'updated' }
            [void](Install-PythonRequirements (Join-Path $script:ComfyDir 'requirements.txt') 'ComfyUI')
            $script:NeedsRestart = $true
        }
        return
    }
    $asset = Get-GitHubAsset $script:ComfyRepo $script:ComfyAssetRegex -LatestOnly
    Write-Step "ComfyUI release: $($asset.Tag)"
    $archive = Join-Path $script:Downloads $asset.Name
    Invoke-Download $asset.Url $archive $asset.Size $asset.Sha256
    Write-Step 'Testing archive integrity.'
    [void](Invoke-Native $SevenZip @('t', $archive) -Quiet)
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $archive, "$archive.verified" -Force -ErrorAction SilentlyContinue
        Stop-Install 'The ComfyUI archive is corrupt: deleted, run again.'
    }
    $tmp = Join-Path $script:Root '_extract'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Write-Step 'Extracting ComfyUI Portable (temporary folder).'
    [void](Invoke-Native $SevenZip @('x', $archive, "-o$tmp", '-y') -Quiet)
    if ($LASTEXITCODE -ne 0) { Stop-Install 'ComfyUI extraction failed.' }
    $extracted = Get-ChildItem $tmp -Directory | Where-Object {
        (Test-Path (Join-Path $_.FullName 'python_embeded\python.exe')) -and (Test-Path (Join-Path $_.FullName 'ComfyUI\main.py'))
    } | Select-Object -First 1
    if (-not $extracted) { Stop-Install "Unexpected archive layout in $tmp" }
    if (Test-Path $script:InstallDir) {
        $backup = '{0}.incomplete-{1}' -f $script:InstallDir, (Get-Date -Format 'yyyyMMdd-HHmmss')
        Add-Warning "Incomplete installation found: renamed to $backup"
        Move-Item $script:InstallDir $backup
    }
    Move-Item $extracted.FullName $script:InstallDir
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "ComfyUI installed in $($script:InstallDir)"
    $script:Report.comfyui.status = 'installed'
    $script:Report.comfyui.release = $asset.Tag
}

function Test-Cuda {
    # Python code without double quotes: Windows PowerShell 5.1 mangles them for native commands.
    $code = "import torch,json,sys; ok=torch.cuda.is_available(); print(json.dumps({'torch':torch.__version__,'cuda':torch.version.cuda,'available':ok,'device':(torch.cuda.get_device_name(0) if ok else None)})); sys.exit(0 if ok else 1)"
    $out = Invoke-Native $script:Python @('-s', '-c', $code) -Quiet
    $exit = $LASTEXITCODE
    $json = $out | Where-Object { $_ -match '^\{.*\}$' } | Select-Object -Last 1
    if ($json) {
        $info = $json | ConvertFrom-Json
        $script:Report.cuda = [ordered]@{ status = $(if ($info.available) { 'ok' } else { 'unavailable' }); torch = $info.torch; cuda = $info.cuda; device = $info.device }
        Write-Ok "Torch $($info.torch) | CUDA $($info.cuda) | $($info.device)"
    } else {
        $script:Report.cuda = [ordered]@{ status = 'error'; output = ($out -join "`n") }
    }
    if ($exit -ne 0) { Stop-Install "CUDA is not available in ComfyUI's Python. Update the NVIDIA Studio driver and run again. Output: $($out -join ' ')" }
}

function Install-PythonRequirements([string]$RequirementsFile, [string]$Label) {
    if (-not (Test-Path -LiteralPath $RequirementsFile)) { return $true }
    # Pin the installed torch stack so no requirements file can replace the CUDA build.
    $constraints = Join-Path $script:Downloads 'torch-constraints.txt'
    $freeze = Invoke-Native $script:Python @('-s', '-m', 'pip', 'freeze', '--disable-pip-version-check') -Quiet
    $pins = @($freeze | Where-Object { $_ -match '^(torch|torchvision|torchaudio|xformers|numpy)==' })
    [System.IO.File]::WriteAllLines($constraints, [string[]]$pins)
    Write-Step "Installing Python requirements for $Label"
    [void](Invoke-Native $script:Python @('-s', '-m', 'pip', 'install', '-r', $RequirementsFile, '-c', $constraints,
                                           '--no-warn-script-location', '--disable-pip-version-check') -Quiet)
    if ($LASTEXITCODE -ne 0) { Add-Warning "pip install for $Label exited with code $LASTEXITCODE."; return $false }
    return $true
}

function Install-CustomNode($Package) {
    $uri = [uri]$Package.repoUrl
    $parts = $uri.AbsolutePath.Trim('/') -split '/'
    $owner = $parts[0]; $repo = $parts[1] -replace '\.git$', ''
    $target = Join-Path $script:ComfyDir "custom_nodes\$repo"
    $entry = [ordered]@{ name = $Package.name; repo = $Package.repoUrl; path = $target; classTypes = @($Package.classTypes); status = 'pending' }
    try {
        if (Test-Path -LiteralPath $target) {
            Write-Step "Custom node already present: $repo"
            $entry.status = 'existing'
        } else {
            $git = Get-Git
            if ($git) {
                Write-Step "Cloning $($Package.repoUrl)"
                [void](Invoke-Native $git @('clone', '--depth', '1', $Package.repoUrl, $target) -Quiet)
                if ($LASTEXITCODE -ne 0) { Stop-Install "git clone failed for $repo (exit $LASTEXITCODE)." }
                $entry.method = 'git'
            } else {
                $info = Invoke-Json "https://api.github.com/repos/$owner/$repo"
                $branch = [string]$info[0].default_branch
                $zip = Join-Path $script:Downloads "$repo-$branch.zip"
                Write-Step "Downloading $owner/$repo ($branch) as zip (install Git to make updates easier)"
                Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
                Invoke-Download "https://github.com/$owner/$repo/archive/refs/heads/$branch.zip" $zip 0 ''
                $tmp = Join-Path $script:Root "_extract-$repo"
                if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
                Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
                $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
                Move-Item $inner.FullName $target
                Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $zip, "$zip.verified" -Force -ErrorAction SilentlyContinue
                $entry.method = 'zip'
                $entry.branch = $branch
            }
            $entry.status = 'installed'
            $script:NeedsRestart = $true
        }
        $reqOk = Install-PythonRequirements (Join-Path $target 'requirements.txt') $repo
        $installPy = Join-Path $target 'install.py'
        if ($entry.status -eq 'installed' -and (Test-Path $installPy)) {
            Write-Step "Running install.py for $repo"
            Push-Location $target
            try { [void](Invoke-Native $script:Python @('-s', $installPy) -Quiet) } finally { Pop-Location }
            if ($LASTEXITCODE -ne 0) { Add-Warning "install.py for $repo exited with code $LASTEXITCODE."; $reqOk = $false }
        }
        if (-not $reqOk) { $entry.dependencies = 'warning' } else { $entry.dependencies = 'ok' }
    } catch {
        $entry.status = 'failed'
        $entry.error = $_.Exception.Message
        Add-Warning "Custom node $repo failed: $($_.Exception.Message)"
    }
    [void]$script:Report.customNodes.Add($entry)
}

function Write-StartScript {
    $extra = if ($ComfyArgs) { " $ComfyArgs" } else { '' }
    $content = @"
@echo off
title ComfyUI - Local AI for Photoshop
cd /d "$($script:InstallDir)"
"$($script:Python)" -s "ComfyUI\main.py" --windows-standalone-build --listen 127.0.0.1 --port $Port --preview-method auto$extra
pause
"@
    Set-Content -Path $script:StartScript -Value $content -Encoding ASCII
    Write-Step "Start script: $($script:StartScript)"
}

function Start-ComfyUI {
    $running = Test-ComfyApi
    if ($running -and $script:NeedsRestart) {
        $proc = Get-ComfyProcess
        if ($RestartComfyUI -and $proc) {
            Write-Step "Restarting ComfyUI (PID $($proc.Id)) to load the new components."
            Stop-Process -Id $proc.Id -Force
            for ($i = 0; $i -lt 15 -and (Test-ComfyApi); $i++) { Start-Sleep -Seconds 1 }
            $running = $false
        } else {
            Add-Warning 'ComfyUI was already running: restart it (or use -RestartComfyUI) to load new custom nodes and updates.'
        }
    }
    if ($running) { Write-Step "ComfyUI is running on port $Port."; return $true }
    if ($NoStart) { return $false }
    Write-Step 'Starting ComfyUI in a separate console.'
    Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "`"$($script:StartScript)`"") -WorkingDirectory $script:Root | Out-Null
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Seconds 2
        if (Test-ComfyApi) { return $true }
    }
    Add-Warning "ComfyUI did not answer within 4 minutes: check its console, then use $($script:StartScript)."
    return $false
}

function Test-CustomNodesLoaded {
    foreach ($entry in $script:Report.customNodes) {
        if ($entry.status -eq 'failed') { continue }
        $missing = @()
        foreach ($cls in $entry.classTypes) {
            # /object_info/<class> answers {} (HTTP 200) for an unknown class: check the payload.
            try {
                $res = Invoke-RestMethod "http://127.0.0.1:$Port/object_info/$([uri]::EscapeDataString($cls))" -TimeoutSec 30 -UseBasicParsing
                if (-not ($res -and $res.PSObject.Properties[$cls])) { $missing += $cls }
            } catch { $missing += $cls }
        }
        $entry.loaded = ($missing.Count -eq 0)
        if ($missing.Count -gt 0) {
            $entry.missingClasses = $missing
            Add-Warning "Custom node $($entry.name) is not loaded by ComfyUI (missing: $($missing -join ', ')). Check the ComfyUI console for import errors."
        }
    }
}

# =============================================================================================
# End-to-end test: FLUX.2 [klein] 4B distilled text-to-image through the ComfyUI API.
# Graph taken from the official Comfy-Org template image_flux2_klein_text_to_image.json
# ("Text to Image (FLUX.2 Klein 4B Distilled)"): 4 steps, cfg 1, zeroed negative.
# =============================================================================================
function New-KleinTestPrompt([int]$Width, [int]$Height, [string]$Prefix) {
    return [ordered]@{
        '70' = @{ class_type = 'UNETLoader';            inputs = @{ unet_name = 'flux-2-klein-4b-fp8.safetensors'; weight_dtype = 'default' } }
        '71' = @{ class_type = 'CLIPLoader';            inputs = @{ clip_name = 'qwen_3_4b.safetensors'; type = 'flux2'; device = 'default' } }
        '72' = @{ class_type = 'VAELoader';             inputs = @{ vae_name = 'flux2-vae.safetensors' } }
        '74' = @{ class_type = 'CLIPTextEncode';        inputs = @{ text = 'a red ceramic coffee mug on a wooden desk, soft window light, product photo'; clip = @('71', 0) } }
        '76' = @{ class_type = 'ConditioningZeroOut';   inputs = @{ conditioning = @('74', 0) } }
        '63' = @{ class_type = 'CFGGuider';             inputs = @{ model = @('70', 0); positive = @('74', 0); negative = @('76', 0); cfg = 1.0 } }
        '73' = @{ class_type = 'RandomNoise';           inputs = @{ noise_seed = [int64]42 } }
        '61' = @{ class_type = 'KSamplerSelect';        inputs = @{ sampler_name = 'euler' } }
        '62' = @{ class_type = 'Flux2Scheduler';        inputs = @{ steps = 4; width = $Width; height = $Height } }
        '66' = @{ class_type = 'EmptyFlux2LatentImage'; inputs = @{ width = $Width; height = $Height; batch_size = 1 } }
        '64' = @{ class_type = 'SamplerCustomAdvanced'; inputs = @{ noise = @('73', 0); guider = @('63', 0); sampler = @('61', 0); sigmas = @('62', 0); latent_image = @('66', 0) } }
        '65' = @{ class_type = 'VAEDecode';             inputs = @{ samples = @('64', 0); vae = @('72', 0) } }
        '9'  = @{ class_type = 'SaveImage';             inputs = @{ images = @('65', 0); filename_prefix = $Prefix } }
    }
}

function Get-ComboOptions($ObjectInfo, [string]$Node, [string]$InputName) {
    $spec = @($ObjectInfo.$Node.input.required.$InputName)
    $first = @($spec[0])
    if ($first.Count -eq 1 -and [string]$first[0] -eq 'COMBO' -and $spec.Count -gt 1) { return @($spec[1].options) }  # v3 schema
    return $first
}

function Invoke-KleinSelfTest {
    $base = "http://127.0.0.1:$Port"
    $w = 512; $h = 512
    $script:Report.test.resolution = "${w}x${h}"
    $script:Report.test.steps = 4
    foreach ($c in @(@('UNETLoader', 'unet_name', 'flux-2-klein-4b-fp8.safetensors'), @('CLIPLoader', 'clip_name', 'qwen_3_4b.safetensors'), @('VAELoader', 'vae_name', 'flux2-vae.safetensors'))) {
        try { $info = Invoke-RestMethod "$base/object_info/$($c[0])" -TimeoutSec 30 -UseBasicParsing }
        catch { Stop-Install "object_info/$($c[0]) unavailable: $(Get-HttpErrorBody $_)" }
        if ((Get-ComboOptions $info $c[0] $c[1]) -notcontains $c[2]) { Stop-Install "ComfyUI cannot see $($c[2]) ($($c[0])). Check the models folder or restart ComfyUI." }
    }
    foreach ($n in @('Flux2Scheduler', 'EmptyFlux2LatentImage', 'ConditioningZeroOut')) {
        $res = $null
        try { $res = Invoke-RestMethod "$base/object_info/$n" -TimeoutSec 30 -UseBasicParsing } catch { }
        if (-not ($res -and $res.PSObject.Properties[$n])) { Stop-Install "Node $n is missing: ComfyUI is too old for FLUX.2 klein. Run again with -UpdateComfyUI." }
    }
    $prefix = "LocalAIForPhotoshop/selftest-$($script:RunStamp)"
    $body = @{ prompt = (New-KleinTestPrompt $w $h $prefix); client_id = [guid]::NewGuid().ToString() } | ConvertTo-Json -Depth 10
    Write-Step "End-to-end test: FLUX.2 [klein] 4B, ${w}x${h}, 4 steps (the first model load can take a few minutes)."
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-RestMethod "$base/prompt" -Method Post -ContentType 'application/json; charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 60 -UseBasicParsing
    } catch { Stop-Install "ComfyUI rejected the workflow: $(Get-HttpErrorBody $_)" }
    if ($resp.PSObject.Properties['node_errors'] -and $resp.node_errors -and @($resp.node_errors.PSObject.Properties).Count -gt 0) {
        Stop-Install "Workflow validation errors: $($resp.node_errors | ConvertTo-Json -Depth 6 -Compress)"
    }
    $promptId = [string]$resp.prompt_id
    $script:Report.test.promptId = $promptId
    $entry = $null
    while ($sw.Elapsed.TotalSeconds -lt $TestTimeoutSec) {
        Start-Sleep -Seconds 3
        try { $hist = Invoke-RestMethod "$base/history/$promptId" -TimeoutSec 30 -UseBasicParsing } catch { continue }
        if (-not $hist.PSObject.Properties[$promptId]) { continue }
        $entry = $hist.$promptId
        if ($entry.status.status_str -eq 'error') {
            $msg = @($entry.status.messages | Where-Object { $_[0] -eq 'execution_error' } | ForEach-Object { $_[1].exception_message }) -join ' | '
            if (-not $msg) { $msg = $entry.status | ConvertTo-Json -Depth 6 -Compress }
            Stop-Install "Generation failed: $msg"
        }
        if ($entry.status.completed) { break }
    }
    $sw.Stop()
    if (-not ($entry -and $entry.status.completed)) {
        try { $null = Invoke-RestMethod "$base/interrupt" -Method Post -TimeoutSec 10 -UseBasicParsing } catch { }
        Stop-Install "Test not finished within $TestTimeoutSec s (raise -TestTimeoutSec on slow disks)."
    }
    $img = @($entry.outputs.'9'.images) | Select-Object -First 1
    if (-not $img) { Stop-Install 'Generation finished but returned no image.' }
    $outDir = Join-Path $script:ComfyDir 'output'
    $file = if ($img.subfolder) { Join-Path (Join-Path $outDir $img.subfolder) $img.filename } else { Join-Path $outDir $img.filename }
    if (-not (Test-Path -LiteralPath $file)) { Stop-Install "Output file not found: $file" }
    $len = (Get-Item -LiteralPath $file).Length
    $fs = [System.IO.File]::OpenRead($file)
    try { $sig = New-Object byte[] 8; [void]$fs.Read($sig, 0, 8) } finally { $fs.Dispose() }
    $isPng = (($sig -join ',') -eq '137,80,78,71,13,10,26,10')
    if (-not $isPng -or $len -lt 10240) { Stop-Install "Invalid output ($len bytes, PNG=$isPng): $file" }
    $script:Report.test.status = 'passed'
    $script:Report.test.seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $script:Report.test.output = $file
    Write-Ok ('Test passed in {0:N1} s: {1}' -f $sw.Elapsed.TotalSeconds, $file)
}

# =============================================================================================
# OpenLayer plugin
# =============================================================================================
function Install-OpenLayer {
    $photoshops = Find-Photoshop
    $script:Report.plugin.photoshop = @($photoshops | ForEach-Object { [ordered]@{ path = $_.Path; version = $_.Version } })
    if ($photoshops.Count -eq 0) { Add-Warning 'Photoshop not found in Program Files\Adobe: OpenLayer needs Photoshop 2024 or newer.' }
    else {
        foreach ($p in $photoshops) { Write-Step "Photoshop: $($p.Path) (v$($p.Version))" }
        if ($photoshops[0].Major -lt $script:MinPsMajor) { Add-Warning "Photoshop $($photoshops[0].Version) is older than 2024: OpenLayer may not load." }
    }
    $pkg = Get-GitHubAsset $script:PluginRepo $script:PluginRegex
    Write-Step "OpenLayer: $($pkg.Tag) ($($pkg.Name))"
    $ccx = Join-Path $script:Downloads $pkg.Name
    Invoke-Download $pkg.Url $ccx $pkg.Size $pkg.Sha256
    # Adobe's installer only finds Photoshop when the .ccx sits on the same drive.
    if ([System.IO.Path]::GetPathRoot($ccx) -ine [System.IO.Path]::GetPathRoot($env:ProgramFiles)) {
        $dir = Join-Path $env:TEMP 'LocalAIForPhotoshop'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Copy-Item -LiteralPath $ccx -Destination (Join-Path $dir $pkg.Name) -Force
        $ccx = Join-Path $dir $pkg.Name
    }
    $script:Report.plugin.release = $pkg.Tag
    $script:Report.plugin.package = $ccx

    if (-not (Test-Path $script:UpiPath)) {
        if ($InstallCreativeCloud) {
            $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
            if (-not $winget) { Stop-Install 'winget is not available: install Creative Cloud from adobe.com.' }
            Write-Step 'Installing the Adobe Creative Cloud desktop app (official winget package Adobe.CreativeCloud).'
            [void](Invoke-Native $winget.Source @('install', '--id', 'Adobe.CreativeCloud', '--exact', '--accept-package-agreements', '--accept-source-agreements'))
        }
        if (-not (Test-Path $script:UpiPath)) {
            Add-Warning "Adobe Creative Cloud is not installed (its plugin installer is missing). Install it (or use -InstallCreativeCloud), sign in with any Adobe account (a free one works), then run again or open: $ccx"
            $script:Report.plugin.status = 'downloaded_only'
            return
        }
    }
    if (Test-OpenLayerInstalled) {
        Write-Ok 'OpenLayer is already installed (verified with Adobe UPI). Open the .ccx to update it.'
        $script:Report.plugin.status = 'already_installed'
        return
    }
    if ($photoshops.Count -eq 0) { Add-Warning "Install Photoshop first, then open: $ccx"; $script:Report.plugin.status = 'downloaded_only'; return }

    Write-Step 'Installing OpenLayer through Adobe UPI.'
    # UPIA nearly always exits 0 and prints its result: parse the text, then verify with /list.
    $out = Invoke-Native $script:UpiPath @('/install', $ccx)
    $text = $out -join ' '
    $script:Report.plugin.upiOutput = ($out -join "`n")
    if ($text -match 'status\s*=\s*-631') {
        Add-Warning 'Adobe UPI -631: nobody is signed in to Creative Cloud. Open Creative Cloud, sign in (a free Adobe account works) and run again.'
    } elseif ($text -match 'status\s*=\s*-641') {
        Add-Warning 'Adobe UPI -641: run the installer from a NON-administrator PowerShell with Creative Cloud open.'
    }
    $ok = $false
    for ($i = 0; $i -lt 5 -and -not $ok; $i++) { Start-Sleep -Seconds 2; $ok = Test-OpenLayerInstalled }
    if ($ok) { Write-Ok 'OpenLayer installed and verified. Restart Photoshop if it was open.'; $script:Report.plugin.status = 'installed_verified' }
    else { Add-Warning "OpenLayer is not listed after installation. Double-click $ccx to install it manually."; $script:Report.plugin.status = 'install_unverified' }
}

# =============================================================================================
# Pre-flight
# =============================================================================================
function Invoke-Preflight {
    if (-not [Environment]::Is64BitOperatingSystem) { Stop-Install '64-bit Windows is required.' }
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { Stop-Install 'curl.exe not found (Windows 10 1803+ or Windows 11 required).' }
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin -and -not $SkipPlugin) { Add-Warning 'Running as administrator: Adobe''s plugin installer may refuse to work (-641). A normal PowerShell is recommended.' }

    $nvsmi = Find-Executable @((Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe')) 'nvidia-smi.exe'
    if (-not $nvsmi) { Stop-Install 'NVIDIA driver / nvidia-smi not found. Install the latest NVIDIA Studio driver, reboot and run again.' }
    $line = (Invoke-Native $nvsmi @('--query-gpu=name,memory.total,driver_version', '--format=csv,noheader,nounits') -Quiet) | Select-Object -First 1
    $gpu = @($line -split ',' | ForEach-Object { $_.Trim() })
    if ($gpu.Count -lt 3) { Stop-Install "Unexpected nvidia-smi output: $line" }
    $gpuName = $gpu[0]; $vramMiB = [int]$gpu[1]; $driver = $gpu[2]
    Write-Step ('GPU: {0} | VRAM {1:N1} GB | driver {2}' -f $gpuName, ($vramMiB / 1024), $driver)
    if ($gpuName -notmatch 'RTX') { Add-Warning 'The GPU is not an NVIDIA RTX: compatibility and speed are not guaranteed.' }
    if ($vramMiB -lt $script:MinVramMiB) {
        if ($SkipHardwareCheck) { Add-Warning 'VRAM below 6 GB: continuing because of -SkipHardwareCheck.' }
        else { Stop-Install ('Not enough VRAM: {0:N1} GB (minimum 6 GB, 8+ recommended). Use -SkipHardwareCheck to force.' -f ($vramMiB / 1024)) }
    } elseif ($vramMiB -lt $script:RecVramMiB) { Add-Warning 'VRAM below 8 GB: ComfyUI will offload to RAM and generation will be slower.' }
    $driverMajor = 0
    [void][int]::TryParse(($driver -split '\.')[0], [ref]$driverMajor)
    if ($driverMajor -gt 0 -and $driverMajor -lt $script:MinDriverMajor) {
        Add-Warning "Driver ${driver}: the current portable build uses CUDA 13.0 (driver $($script:MinDriverMajor)+ recommended)."
    }
    $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    Write-Step "RAM: $ramGB GB"
    if ($ramGB -lt $script:RecRamGB) { Add-Warning "Less than $($script:RecRamGB) GB of RAM: large text encoders may cause swapping." }
    $free = Get-FreeGB $script:Root
    Write-Step "Free space on $([System.IO.Path]::GetPathRoot($script:Root)): $free GB"
    $os = Get-CimInstance Win32_OperatingSystem
    $script:Report.system = [ordered]@{
        os = "$($os.Caption) $($os.Version)"; powershell = $PSVersionTable.PSVersion.ToString(); admin = $isAdmin
        gpu = $gpuName; vramGB = [math]::Round($vramMiB / 1024, 1); driver = $driver; ramGB = $ramGB; freeDiskGB = $free
        git = [bool](Get-Git)
    }
}

# =============================================================================================
# Main
# =============================================================================================
function Initialize-Context {
    if (-not $Root) {
        $drive = if (Test-Path 'D:\') { 'D:\' } else { 'C:\' }
        $Root = Join-Path $drive 'AI\PhotoshopLocalAI'
    }
    $script:Root        = [System.IO.Path]::GetFullPath($Root)
    $script:Downloads   = Join-Path $script:Root 'Downloads'
    $script:Logs        = Join-Path $script:Root 'Logs'
    $script:InstallDir  = Join-Path $script:Root 'ComfyUI_windows_portable'
    $script:ComfyDir    = Join-Path $script:InstallDir 'ComfyUI'
    $script:Python      = Join-Path $script:InstallDir 'python_embeded\python.exe'
    $script:StartScript = Join-Path $script:Root 'Start-ComfyUI.cmd'
    $script:RunStamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:NeedsRestart = $false
    foreach ($p in @($script:Root, $script:Downloads, $script:Logs)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    $script:LogFile = Join-Path $script:Logs "setup-$($script:RunStamp).log"
    try { Start-Transcript -Path $script:LogFile -ErrorAction Stop | Out-Null } catch { Write-Warning "Transcript unavailable: $_" }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $script:Report = New-Report
}

function Write-Summary {
    $r = $script:Report
    Write-Host ''
    Write-Step '==================== SUMMARY ===================='
    if ($r.system.Contains('gpu')) { Write-Step ('GPU          : {0} ({1} GB VRAM, driver {2})' -f $r.system.gpu, $r.system.vramGB, $r.system.driver) }
    Write-Step ('CUDA         : {0}' -f $r.cuda.status)
    Write-Step ('ComfyUI      : {0}' -f $r.comfyui.status)
    $okModels = @($r.models | Where-Object { $_.status -eq 'ok' }).Count
    Write-Step ('Models       : {0}/{1} OK' -f $okModels, $r.models.Count)
    $okNodes = @($r.customNodes | Where-Object { $_.status -ne 'failed' }).Count
    Write-Step ('Custom nodes : {0}/{1} OK' -f $okNodes, $r.customNodes.Count)
    Write-Step ('OpenLayer    : {0}' -f $r.plugin.status)
    Write-Step ('AI test      : {0}' -f $r.test.status)
    Write-Step ('Warnings     : {0}' -f $r.warnings.Count)
    Write-Step ('Result       : {0}' -f $r.status.ToUpperInvariant())
    if ($r.status -eq 'ok') { Write-Ok 'Open Photoshop > Plugins > OpenLayer.' }
    Write-Step "Report: $(Join-Path $script:Root 'last-report.json')"
    Write-Step "Log: $($script:LogFile)"
}

function Invoke-Main {
    $exitCode = 1
    try {
        Initialize-Context
        Write-Step "Local AI for Photoshop $($script:InstallerVersion) - ComfyUI + OpenLayer ($ModelSet model set)"
        Write-Host '  Unofficial installer, not affiliated with Adobe, Comfy Org or OpenLayer.' -ForegroundColor DarkGray

        Invoke-Preflight
        $manifest = Get-Manifest
        $plan = Resolve-InstallPlan $manifest
        $script:Report.manifest = [ordered]@{
            openLayerVersion = $manifest.pluginVersion; generatedAt = $manifest.generatedAt
            selectedModels = $plan.Models.Count; customNodes = @($plan.CustomNodes | ForEach-Object { $_.name })
            enabledPresets = @($plan.Presets | ForEach-Object { $_.id })
            skippedRestricted = @($plan.SkippedRestricted | ForEach-Object { $_.modelName })
        }

        # ---------------------------------------------------------------- plan and disk check
        $missingBytes = [int64]0
        if (-not $SkipModels) { foreach ($m in $plan.Models) { $missingBytes += (Get-ModelMissingBytes $m) } }
        if (-not (Test-Path $script:Python)) { $missingBytes += 10GB }   # ComfyUI archive + extraction, approximate
        if ($Sd15CheckpointUrl) { $missingBytes += 2GB }
        Write-Step ('Plan: {0} models, {1} custom node packages, {2} OpenLayer presets enabled, ~{3} to download.' -f `
            $plan.Models.Count, $plan.CustomNodes.Count, $plan.Presets.Count, (Format-Size $missingBytes))
        foreach ($m in $plan.SkippedRestricted) { Write-Host "  skipped (restricted licence): $($m.modelName) - $($m.licenseGate.name)" -ForegroundColor DarkGray }
        $needGB = [math]::Ceiling($missingBytes / 1GB) + $script:MinFreeMarginGB
        if ((Get-FreeGB $script:Root) -lt $needGB) { Stop-Install "Not enough free space: about $needGB GB needed on $([System.IO.Path]::GetPathRoot($script:Root))." }

        if ($DryRun) {
            Write-Host ''
            foreach ($m in $plan.Models) {
                $state = if (Test-ModelPresent $m) { 'present' } else { 'download' }
                Write-Host ('  [{0,-8}] {1,-60} {2}' -f $state, "$($m.targetFolder)/$($m.modelName)", $(if ($m.PSObject.Properties['sizeBytes'] -and $m.sizeBytes) { Format-Size $m.sizeBytes } else { 'folder' }))
            }
            foreach ($n in $plan.CustomNodes) { Write-Host "  [node    ] $($n.name)  $($n.repoUrl)" }
            $script:Report.status = 'dry-run'
            $script:Report.test.status = 'skipped'
            $exitCode = 0
            return $exitCode
        }

        $seven = Get-SevenZip
        Write-Step "7-Zip: $seven"
        Install-ComfyUI $seven
        $script:Report.comfyui.path = $script:InstallDir
        $script:Report.comfyui.version = Get-ComfyLocalVersion
        $script:Report.comfyui.versionOk = Test-ComfyVersion $script:Report.comfyui.version 'local files'
        Test-Cuda

        if (-not $SkipModels) {
            foreach ($m in $plan.Models) { Install-Model $m }
            if ($Sd15CheckpointUrl) {
                $name = [System.IO.Path]::GetFileName(([uri]$Sd15CheckpointUrl).AbsolutePath)
                if ($name -notmatch '\.(safetensors|ckpt)$') { $name = 'sd15-checkpoint.safetensors' }
                try { Invoke-Download $Sd15CheckpointUrl (Join-Path $script:ComfyDir "models\checkpoints\$name") 0 ''; [void]$script:Report.models.Add([ordered]@{ file = $name; folder = 'checkpoints'; status = 'ok'; verification = 'none' }) }
                catch { Add-Warning "SD 1.5 checkpoint download failed: $($_.Exception.Message)" }
            } elseif ($ModelSet -eq 'Full') {
                Add-Warning 'No SD 1.5 checkpoint: Sketch to Image, SD inpaint and Style Reference stay unavailable. Pass -Sd15CheckpointUrl or copy one into models\checkpoints.'
            }
        }
        if (-not $SkipCustomNodes) { foreach ($n in $plan.CustomNodes) { Install-CustomNode $n } }
        Write-StartScript
        if (-not $SkipPlugin) { Install-OpenLayer } else { $script:Report.plugin.status = 'skipped' }

        $ready = Start-ComfyUI
        $script:Report.comfyui.api = $(if ($ready) { "http://127.0.0.1:$Port" } else { $null })
        if ($ready) {
            try {
                $stats = Invoke-RestMethod "http://127.0.0.1:$Port/system_stats" -TimeoutSec 10 -UseBasicParsing
                $apiVersion = [string]$stats.system.comfyui_version
                $script:Report.comfyui.apiVersion = $apiVersion
                if ($apiVersion -and $script:Report.comfyui.version -and $apiVersion -ne $script:Report.comfyui.version) {
                    Add-Warning "The running ComfyUI ($apiVersion) is not the installed one ($($script:Report.comfyui.version)): restart it."
                }
                [void](Test-ComfyVersion $apiVersion 'running instance')
            } catch { Add-Warning "Reading /system_stats failed: $($_.Exception.Message)" }
            if (-not $SkipCustomNodes) { Test-CustomNodesLoaded }
        }

        $testFailed = $false
        $kleinModels = @($manifest.models | Where-Object { $script:KleinModels -contains $_.modelName })
        $kleinReady = ($kleinModels.Count -eq $script:KleinModels.Count) -and (@($kleinModels | Where-Object { -not (Test-ModelPresent $_) }).Count -eq 0)
        if ($SkipTest) { $script:Report.test.status = 'skipped'; $script:Report.test.reason = '-SkipTest' }
        elseif (-not $kleinReady) { $script:Report.test.status = 'skipped'; $script:Report.test.reason = 'FLUX.2 klein models missing'; Add-Warning 'End-to-end test skipped: FLUX.2 klein models are missing.' }
        elseif (-not $ready) { $script:Report.test.status = 'skipped'; $script:Report.test.reason = 'ComfyUI not running'; Add-Warning "End-to-end test skipped: ComfyUI is not running (start $($script:StartScript) and run again)." }
        else {
            try { Invoke-KleinSelfTest }
            catch {
                $testFailed = $true
                $script:Report.test.status = 'failed'
                $script:Report.test.error = $_.Exception.Message
                Write-Host ('TEST FAILED: ' + $_.Exception.Message) -ForegroundColor Red
            }
        }
        if ($ready -and -not $testFailed) { Start-Process "http://127.0.0.1:$Port" }

        $failedParts = @($script:Report.models | Where-Object { $_.status -eq 'failed' }).Count + @($script:Report.customNodes | Where-Object { $_.status -eq 'failed' }).Count
        if ($testFailed -or $failedParts -gt 0) { $script:Report.status = 'error'; $exitCode = 1 }
        elseif ($script:Report.warnings.Count -gt 0 -or $script:Report.test.status -ne 'passed') { $script:Report.status = 'warning'; $exitCode = 2 }
        else { $script:Report.status = 'ok'; $exitCode = 0 }
    } catch {
        Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
        if ($script:Report) { $script:Report.status = 'error'; $script:Report.error = $_.Exception.Message }
        $exitCode = 1
    } finally {
        if ($script:Report) { Write-Summary; Save-Report }
        try { Stop-Transcript | Out-Null } catch { }
    }
    return $exitCode
}

# Dot-sourcing (". .\Install-LocalAI.ps1") only loads the functions, for tests.
if ($MyInvocation.InvocationName -ne '.') {
    $code = @(Invoke-Main)
    exit ([int]$code[-1])
}
