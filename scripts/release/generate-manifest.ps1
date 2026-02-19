param(
    [string]$SourceDir = "dist",
    [string]$OutputFile = "release-manifest.txt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$root = Resolve-Path -LiteralPath $SourceDir
$rootPath = $root.Path
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputFile))

$files = Get-ChildItem -LiteralPath $rootPath -Recurse -File |
    Where-Object { $_.FullName -ne $outputFullPath } |
    Sort-Object FullName
if (-not $files) {
    throw "No files found under '$SourceDir'."
}

$lines = @(
foreach ($file in $files) {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    $relative = $file.FullName.Substring($rootPath.Length).TrimStart('\', '/').Replace('\', '/')
    "$hash *$relative"
}
)

Set-Content -LiteralPath $OutputFile -Value $lines -NoNewline:$false -Encoding ascii
Write-Host "Wrote $($lines.Count) entries to $OutputFile"
