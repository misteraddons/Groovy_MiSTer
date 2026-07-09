Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")
Push-Location -LiteralPath $repoRoot
try {
    function Assert-Contains {
        param([string]$Path, [string]$Text)
        $content = Get-Content -LiteralPath $Path -Raw
        if (-not $content.Contains($Text)) {
            throw "$Path is missing required safety invariant: $Text"
        }
    }

    function Assert-NotContains {
        param([string]$Path, [string]$Text)
        $content = Get-Content -LiteralPath $Path -Raw
        if ($content.Contains($Text)) {
            throw "$Path still contains unsafe implementation: $Text"
        }
    }

    foreach ($header in @("api/groovymister.h", "retroarch/src/deps/mister/groovymister.h")) {
        Assert-Contains $header "#define BUFFER_SIZE (MAX_FRAME_WIDTH * MAX_FRAME_HEIGHT * MAX_PIXEL_BYTES)"
        Assert-Contains $header "#define AUDIO_BUFFER_SIZE 32768"
    }

    $server = "hps_linux/src/support/groovy/groovy.cpp"
    foreach ($text in @("groovy_payload_bounds_valid", "groovy_copy_payload", "payload_bounds", "poc = nullptr", "key >= sizeof(key2sdl)", "groovy_xdp_cleanup", "blit_without_state")) {
        Assert-Contains $server $text
    }
    Assert-NotContains $server "recvfrom(sockfd, recvbufPtr"
    Assert-NotContains $server "memcpy((char *) (buffer + HEADER_OFFSET"

    foreach ($client in @("api/groovymister.cpp", "retroarch/src/deps/mister/groovymister.cpp")) {
        Assert-Contains $client "mtu != 0 && mtu != 1500 && mtu != 3800"
        Assert-Contains $client "F_GETFL"
        Assert-Contains $client "bytesToSend > BUFFER_SIZE"
        Assert-Contains $client "m_overlapped"
    }

    foreach ($rioHeader in @("api/rio.h", "retroarch/src/deps/mister/rio.h")) {
        Assert-Contains $rioHeader "defined(__MINGW32__)"
        Assert-Contains $rioHeader "typedef void *RIO_BUFFERID"
    }

    Assert-Contains "retroarch/src/gfx/gfx_mister.c" "gmw_init(mister_host"
    Assert-Contains "retroarch/src/gfx/gfx_mister.c" "Connection failed."
    Assert-Contains "rtl/sound.v" "samples_lost_sync"
    Assert-Contains "rtl/sound.v" "sound_start_audio"
    Assert-Contains "sys/sys_top.v" ".mode     ({1'b0,~lowlat"
    Assert-Contains "scripts/build/prepare-hps-source.ps1" 'CPP_SRC := `$`(filter-out %_unittest.cpp,`$`(CPP_SRC))'
    Assert-Contains "scripts/build/prepare-hps-source.ps1" "-Wno-class-memaccess -Wno-narrowing"
    Assert-Contains "scripts/release/stage-release.ps1" "Remove-Item -LiteralPath `$distPath -Recurse -Force"

    Write-Host "Protocol safety checks passed."
}
finally {
    Pop-Location
}
