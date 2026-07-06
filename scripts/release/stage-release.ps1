param(
    [string]$DistDir = "dist",
    [switch]$AllowMissing,
    [switch]$SkipManifest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")
$distPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot.Path $DistDir))

New-Item -ItemType Directory -Force -Path $distPath | Out-Null

$artifacts = @(
    @{
        Name = "Groovy.rbf"
        OutputName = "Groovy.rbf"
        Candidates = @(
            "Groovy.rbf",
            "output_files/Groovy.rbf"
        )
    },
    @{
        Name = "MiSTer_groovy"
        OutputName = "MiSTer_groovy"
        Candidates = @(
            "build/hps-src/bin/MiSTer_groovy",
            "build/hps-src/MiSTer_groovy",
            "hps_linux/src/MiSTer_groovy",
            "hps_linux/MiSTer_groovy"
        )
    },
    @{
        Name = "MiSTer_groovy_XDP"
        OutputName = "MiSTer_groovy_XDP"
        Candidates = @(
            "build/hps-src/bin/MiSTer_groovy_XDP",
            "build/hps-src/MiSTer_groovy_XDP",
            "hps_linux/src/MiSTer_groovy_XDP",
            "hps_linux/MiSTer_groovy_XDP"
        )
    },
    @{
        Name = "groovy_xdp_kern.o"
        OutputName = "groovy_xdp_kern.o"
        Candidates = @(
            "hps_linux/src/support/groovy/kernel/sergi/groovy_xdp_kern.o",
            "hps_linux/src/support/groovy/kernel/sergi/af_xdp_kern.o"
        )
    },
    @{
        Name = "libelf.so.1"
        OutputName = "libelf.so.1"
        Candidates = @(
            "hps_linux/src/lib/libelf/libelf.so.1",
            "hps_linux/src/lib/libelf/libelf.so",
            "hps_linux/src/support/groovy/kernel/lib/libelf/libelf.so.1",
            "hps_linux/src/support/groovy/kernel/lib/libelf/libelf.so"
        )
    }
)

$missing = New-Object System.Collections.Generic.List[string]
$copied = New-Object System.Collections.Generic.List[string]

foreach ($artifact in $artifacts) {
    $source = $null
    foreach ($candidate in $artifact.Candidates) {
        $candidatePath = Join-Path $repoRoot.Path $candidate
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            $source = $candidatePath
            break
        }
    }

    if (-not $source) {
        $missing.Add($artifact.Name)
        continue
    }

    $destination = Join-Path $distPath $artifact.OutputName
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $copied.Add($artifact.OutputName)
    Write-Host "Staged $($artifact.OutputName)"
}

if ($missing.Count -gt 0 -and -not $AllowMissing) {
    throw "Missing release artifact(s): $($missing -join ', ')"
}

if (-not $SkipManifest) {
    if ($copied.Count -eq 0) {
        throw "No release artifacts were staged."
    }

    $relativeDist = [System.IO.Path]::GetRelativePath($repoRoot.Path, $distPath)
    $manifestPath = Join-Path $relativeDist "release-manifest.txt"
    Push-Location -LiteralPath $repoRoot.Path
    try {
        & (Join-Path $PSScriptRoot "generate-manifest.ps1") -SourceDir $relativeDist -OutputFile $manifestPath
    }
    finally {
        Pop-Location
    }
}

if ($missing.Count -gt 0) {
    Write-Host "Missing optional artifact(s): $($missing -join ', ')"
}
