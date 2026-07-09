param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sourcePath = Join-Path $repoRoot "hps_linux\src\support\groovy\groovy.cpp"
$source = Get-Content -LiteralPath $sourcePath -Raw

$setInitMatch = [regex]::Match($source, "static (?:void|bool) setInit\([\s\S]*?\n\}\r?\n\r?\nstatic (?:void|bool) setBlit\(")
if (-not $setInitMatch.Success) {
    throw "setInit not found"
}

$setInit = $setInitMatch.Value
$audioChannelsIndex = $setInit.IndexOf("audioChannels = (audio_chan <= 2) ? audio_chan : 0;")
$audioStatusIndex = $setInit.IndexOf("user_io_status_set(AUDIO_OPT, (uint32_t)(audioChannels != 0));")
$cachedAudioIndex = $setInit.IndexOf("fpga_audio = (audioChannels != 0);")
$fpgaInitIndex = $setInit.IndexOf("groovy_FPGA_init(1, audioRate, audioChannels, rgbMode);")

if ($audioChannelsIndex -lt 0) {
    throw "audioChannels assignment not found in setInit"
}

if ($audioStatusIndex -lt 0) {
    throw "setInit does not update AUDIO_OPT from audioChannels"
}

if ($cachedAudioIndex -lt 0) {
    throw "setInit does not update cached fpga_audio from audioChannels"
}

if ($fpgaInitIndex -lt 0) {
    throw "groovy_FPGA_init call not found in setInit"
}

if ($audioStatusIndex -lt $audioChannelsIndex -or $audioStatusIndex -gt $fpgaInitIndex) {
    throw "AUDIO_OPT must be updated after audioChannels is parsed and before groovy_FPGA_init"
}

if ($cachedAudioIndex -lt $audioStatusIndex -or $cachedAudioIndex -gt $fpgaInitIndex) {
    throw "cached fpga_audio must be updated after AUDIO_OPT and before groovy_FPGA_init"
}

$setCloseMatch = [regex]::Match($source, "static void setClose\([\s\S]*?\n\}\r?\n\r?\n#ifdef _AF_XDP")
if (-not $setCloseMatch.Success) {
    throw "setClose not found"
}

if (-not $setCloseMatch.Value.Contains("user_io_status_set(AUDIO_OPT, (uint32_t)0);")) {
    throw "setClose does not clear AUDIO_OPT"
}

if (-not $setCloseMatch.Value.Contains("fpga_audio = 0;")) {
    throw "setClose does not clear cached fpga_audio"
}
