param(
    [string]$MainMisterDir = "Main_MiSTer",
    [string]$OutputDir = "build/hps-src",
    [switch]$NoClean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")
$mainMisterPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot.Path $MainMisterDir))
$overlayPath = Join-Path $repoRoot.Path "hps_linux/src"
$outputPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot.Path $OutputDir))

function Assert-File {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing required file: $path"
    }
}

function Test-IsUnderPath {
    param(
        [string]$Path,
        [string]$Parent
    )

    $pathFull = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\', '/')
    return $pathFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $pathFull.StartsWith($parentFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
        $pathFull.StartsWith($parentFull + [System.IO.Path]::AltDirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Copy-TreeFiltered {
    param(
        [string]$Source,
        [string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    Get-ChildItem -LiteralPath $Source -Force -Recurse | ForEach-Object {
        $relative = [System.IO.Path]::GetRelativePath($Source, $_.FullName)
        $parts = $relative -split '[\\/]'
        if ($parts -contains ".git") {
            return
        }

        if (-not $_.PSIsContainer) {
            $extension = [System.IO.Path]::GetExtension($_.Name)
            if ($extension -in @(".d", ".elf", ".ll", ".o")) {
                return
            }
            if ($_.Name -in @("MiSTer_groovy", "MiSTer_groovy_XDP")) {
                return
            }
        }

        $target = Join-Path $Destination $relative
        if ($_.PSIsContainer) {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
        }
        else {
            $targetDir = Split-Path -Parent $target
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        }
    }
}

Assert-File $mainMisterPath "Makefile"
Assert-File $mainMisterPath "file_io.h"
Assert-File $mainMisterPath "input.h"
Assert-File $mainMisterPath "hardware.h"
Assert-File $mainMisterPath "lib/libco/arm.c"
Assert-File $overlayPath "Makefile"
Assert-File $overlayPath "support/groovy/groovy.cpp"

if ((Test-Path -LiteralPath $outputPath) -and -not $NoClean) {
    $repoBuildRoot = Join-Path $repoRoot.Path "build"
    $tempRoot = [System.IO.Path]::GetTempPath()
    if (-not (Test-IsUnderPath $outputPath $repoBuildRoot) -and -not (Test-IsUnderPath $outputPath $tempRoot)) {
        throw "Refusing to clean output outside build/ or temp: $outputPath"
    }
    Remove-Item -LiteralPath $outputPath -Recurse -Force
}

Copy-TreeFiltered -Source $mainMisterPath -Destination $outputPath
Copy-TreeFiltered -Source $overlayPath -Destination $outputPath

$mainCommit = "unknown"
$groovyCommit = "unknown"
try { $mainCommit = (git -C $mainMisterPath rev-parse HEAD).Trim() } catch {}
try { $groovyCommit = (git -C $repoRoot.Path rev-parse HEAD).Trim() } catch {}

$stamp = @(
    "Main_MiSTer source: $mainMisterPath"
    "Main_MiSTer commit: $mainCommit"
    "Groovy_MiSTer source: $($repoRoot.Path)"
    "Groovy_MiSTer commit: $groovyCommit"
    "Overlay source: $overlayPath"
)
Set-Content -LiteralPath (Join-Path $outputPath "groovy-build-source.txt") -Value $stamp -Encoding ascii

Write-Host "Prepared HPS source tree: $outputPath"
Write-Host "Build non-XDP: make -C `"$outputPath`" BASE=arm-none-linux-gnueabihf _AF_XDP=0"
Write-Host "Build XDP:     make -C `"$outputPath`" BASE=arm-none-linux-gnueabihf _AF_XDP=1"
