#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
# Unit tests: run with  Invoke-Pester ./tests
BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:ScriptPath = Join-Path $script:RepoRoot 'Install-LocalAI.ps1'
    . $script:ScriptPath
    $script:Manifest = Get-Content (Join-Path $script:RepoRoot 'manifest/openlayer-requirements.json') -Raw | ConvertFrom-Json
    $script:LogFile = Join-Path ([IO.Path]::GetTempPath()) 'lafp-test.log'
    $script:Root = [IO.Path]::GetTempPath()
}

Describe 'Script file' {
    It 'parses without errors' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:ScriptPath, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }
}

Describe 'Manifest' {
    It 'has schema version 1' { $script:Manifest.schemaVersion | Should -Be 1 }
    It 'lists models with the fields the installer reads' {
        foreach ($m in $script:Manifest.models) {
            $m.modelName | Should -Not -BeNullOrEmpty
            $m.targetPath | Should -Match '^models/'
            $m.downloadUrl | Should -Match '^https://'
            $m.layout | Should -BeIn @('file', 'repo-folder')
            if ($m.layout -eq 'file') { [int64]$m.sizeBytes | Should -BeGreaterThan 0 }
        }
    }
    It 'contains the FLUX.2 klein stack used by the self-test' {
        foreach ($name in $script:KleinModels) { @($script:Manifest.models.modelName) | Should -Contain $name }
    }
}

Describe 'Resolve-InstallPlan' {
    BeforeEach { $IncludeLicenseRestricted = $false; $AcceptLicenses = $false }

    It 'Full never selects licence-restricted models by default' {
        $ModelSet = 'Full'
        $plan = Resolve-InstallPlan $script:Manifest
        @($plan.Models | Where-Object { Test-ModelRestricted $_ }).Count | Should -Be 0
        $plan.SkippedRestricted.Count | Should -BeGreaterThan 0
    }
    It 'Full selects the klein stack and the inpaint crop-and-stitch node' {
        $ModelSet = 'Full'
        $plan = Resolve-InstallPlan $script:Manifest
        foreach ($name in $script:KleinModels) { @($plan.Models.modelName) | Should -Contain $name }
        @($plan.CustomNodes.name) | Should -Contain 'comfyui-inpaint-cropandstitch'
    }
    It 'Klein selects exactly three models' {
        $ModelSet = 'Klein'
        $plan = Resolve-InstallPlan $script:Manifest
        $plan.Models.Count | Should -Be 3
        @($plan.CustomNodes.name) | Should -Not -Contain 'ComfyUI-GGUF'
    }
    It 'refuses restricted models without -AcceptLicenses' {
        $ModelSet = 'Full'; $IncludeLicenseRestricted = $true
        { Resolve-InstallPlan $script:Manifest } | Should -Throw '*AcceptLicenses*'
    }
    It 'allows restricted models with -AcceptLicenses' {
        $ModelSet = 'Full'; $IncludeLicenseRestricted = $true; $AcceptLicenses = $true
        $plan = Resolve-InstallPlan $script:Manifest
        $plan.Models.Count | Should -Be $script:Manifest.models.Count
    }
}

Describe 'GPU advisor' {
    It 'rates the FLUX.2 klein text-to-image preset comfortable on 16 GB and offloading on 6 GB' {
        $o16 = Get-PresetOutlook $script:Manifest (16GB)
        ($o16 | Where-Object Id -eq 'txt2img-flux2-klein').Expectation | Should -Be 'comfortable'
        $o6 = Get-PresetOutlook $script:Manifest (6GB)
        ($o6 | Where-Object Id -eq 'txt2img-flux2-klein').Expectation | Should -Be 'offloads'
    }
    It 'Auto installs more on a bigger GPU and never restricted models by default' {
        $ModelSet = 'Auto'; $IncludeLicenseRestricted = $false; $AcceptLicenses = $false
        $small = Resolve-InstallPlan $script:Manifest (Get-PresetOutlook $script:Manifest (8GB))
        $big = Resolve-InstallPlan $script:Manifest (Get-PresetOutlook $script:Manifest (24GB))
        $big.Models.Count | Should -BeGreaterThan $small.Models.Count
        @($big.Models | Where-Object { Test-ModelRestricted $_ }).Count | Should -Be 0
    }
    It 'picks a heavier, better preset for quality than for speed on 16 GB' {
        $IncludeLicenseRestricted = $false
        $picks = Get-ToolPicks (Get-PresetOutlook $script:Manifest (16GB))
        $t2i = $picks | Where-Object Tool -eq 'Text to Image'
        $t2i.Fast.Id | Should -Be 'txt2img-flux2-klein'
        (Get-QualityScore $t2i.Quality.Id) | Should -BeGreaterThan (Get-QualityScore $t2i.Fast.Id)
        $t2i.Quality.Restricted | Should -BeFalse
        ($picks | Where-Object Tool -eq 'Upscale').Quality.Id | Should -Be 'upscale-seedvr2-3b'
    }
    It 'writes a quality guide that names the upscaler' {
        $IncludeLicenseRestricted = $false
        $guide = Get-QualityGuide (Get-PresetOutlook $script:Manifest (16GB)) (16GB)
        ($guide -join "`n") | Should -Match 'SeedVR2'
        ($guide -join "`n") | Should -Match '1536 px'
    }
    It 'Auto refuses to run without a VRAM figure' {
        $ModelSet = 'Auto'
        { Resolve-InstallPlan $script:Manifest $null } | Should -Throw '*VRAM*'
    }
}

Describe 'Helpers' {
    It 'normalises GitHub and Hugging Face digests' {
        $hex = 'AB' * 32
        ConvertTo-Sha256 "sha256:$hex" | Should -Be $hex.ToLowerInvariant()
        ConvertTo-Sha256 $hex | Should -Be $hex.ToLowerInvariant()
        ConvertTo-Sha256 'not-a-hash' | Should -Be ''
    }
    It 'parses ComfyUI versions' {
        (ConvertTo-VersionObject 'v0.45.0') | Should -Be ([version]'0.45.0')
        (ConvertTo-VersionObject '0.9.1') -lt (ConvertTo-VersionObject '0.10.0') | Should -BeTrue
    }
    It 'verifies file integrity and writes a marker' {
        $f = Join-Path ([IO.Path]::GetTempPath()) ("lafp-" + [guid]::NewGuid() + '.bin')
        [IO.File]::WriteAllText($f, 'hello')
        $sha = (Get-FileHash $f -Algorithm SHA256).Hash.ToLowerInvariant()
        Test-FileIntegrity $f 5 $sha | Should -BeTrue
        Test-Path "$f.verified" | Should -BeTrue
        Test-FileIntegrity $f 5 ('0' * 64) | Should -BeFalse
        Test-FileIntegrity $f 6 $sha | Should -BeFalse
        Remove-Item $f, "$f.verified" -Force
    }
}

Describe 'Self-test workflow' {
    It 'uses the node classes of the official FLUX.2 klein distilled template' {
        $p = New-KleinTestPrompt 512 512 'x'
        $classes = @($p.Values | ForEach-Object { $_.class_type })
        foreach ($c in 'UNETLoader', 'CLIPLoader', 'VAELoader', 'CLIPTextEncode', 'ConditioningZeroOut', 'CFGGuider',
                       'RandomNoise', 'KSamplerSelect', 'Flux2Scheduler', 'EmptyFlux2LatentImage', 'SamplerCustomAdvanced',
                       'VAEDecode', 'SaveImage') { $classes | Should -Contain $c }
        $p['71'].inputs.type | Should -Be 'flux2'
        $p['62'].inputs.steps | Should -Be 4
        $p['63'].inputs.cfg | Should -Be 1.0
    }
    It 'references only nodes that exist in the graph' {
        $p = New-KleinTestPrompt 512 512 'x'
        foreach ($node in $p.Values) {
            foreach ($v in $node.inputs.Values) {
                if ($v -is [array] -and $v.Count -eq 2 -and $v[0] -is [string]) { $p.Contains($v[0]) | Should -BeTrue }
            }
        }
    }
}
