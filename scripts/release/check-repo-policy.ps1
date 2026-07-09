Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")
Push-Location -LiteralPath $repoRoot
try {
    function Assert-True {
        param(
            [bool]$Condition,
            [string]$Message
        )

        if (-not $Condition) {
            throw $Message
        }
    }

    function Read-Text {
        param([string]$Path)
        return Get-Content -LiteralPath $Path -Raw
    }

    $deletedOrgFiles = @(git status --short -- '*.org' | Where-Object { $_ -match '^\s*D' })
    Assert-True ($deletedOrgFiles.Count -eq 0) "Tracked .org documentation files are deleted: $($deletedOrgFiles -join '; ')"

    $makefile = Read-Text "hps_linux/src/Makefile"
    Assert-True ($makefile -notmatch "-name '\*\.org'") "make clean must not delete tracked .org documentation"
    Assert-True ($makefile -match [regex]::Escape("support/groovy/kernel/lib/xdp-tools/headers")) "Makefile must include vendored XDP kernel headers for XDP builds"
    Assert-True ($makefile -match [regex]::Escape("-Llib/libelf -lelf")) "Makefile must link XDP builds against vendored libelf"

    $utils = Read-Text "hps_linux/src/support/groovy/utils.cpp"
    foreach ($pattern in @("strcpy(host,", "sprintf(numIRQ", "strcat(strAffinity2", 'sscanf(line, "%s')) {
        Assert-True ($utils -notmatch [regex]::Escape($pattern)) "utils.cpp still uses unsafe string assembly: $pattern"
    }

    $afXdpUser = Read-Text "hps_linux/src/support/groovy/kernel/sergi/af_xdp_user.c"
    foreach ($pattern in @('printf("pas ', 'printf("paquet ')) {
        Assert-True ($afXdpUser -notmatch [regex]::Escape($pattern)) "af_xdp_user.c still has scratch debug output: $pattern"
    }

    $groovy = Read-Text "hps_linux/src/support/groovy/groovy.cpp"
    Assert-True ($groovy -notmatch [regex]::Escape("struct ifreq ifr_flags")) "groovy.cpp uses ifr_flags as a variable name, which collides with net/if.h"
    foreach ($requiredText in @(
        "groovy_validate_command_packet",
        "groovy_note_invalid_packet",
        "[PACKET_DROP]",
        "[STATS]",
        "xdp_validate_udp_frame",
        "stat_xdp_rx_packets",
        "fflush(fp)",
        "setvbuf(fp, NULL, _IOLBF",
        "[LOG][file=/tmp/groovy.log",
        "stat_input_joy_packets",
        "stat_input_ps2_packets",
        "stat_input_keepalives",
        "stat_input_neutralizes",
        "groovy_neutralize_inputs",
        "[INPUT_STATS]",
        "[INPUT_NEUTRAL]"
    )) {
        Assert-True ($groovy -match [regex]::Escape($requiredText)) "groovy.cpp is missing packet validation or runtime stat hook: $requiredText"
    }
    Assert-True ($groovy -match '\(\s*sev\s*==\s*0\s*\|\|\s*sev\s*<=\s*doVerbose\s*\)') "LOG must always write severity 0 startup/error lines to the log file"

    $groovyTop = Read-Text "Groovy.sv"
    Assert-True ($groovyTop -match [regex]::Escape("inout  [45:0] HPS_BUS")) "Groovy.sv must use the current 46-bit framework HPS_BUS"
    Assert-True ($groovyTop -match [regex]::Escape("output        HDMI_BOB_DEINT")) "Groovy.sv must expose the current framework HDMI_BOB_DEINT port"
    Assert-True ($groovyTop -match [regex]::Escape("assign HDMI_BOB_DEINT = 0;")) "Groovy.sv must default HDMI_BOB_DEINT low"

    $hpsIo = Read-Text "sys/hps_io.sv"
    Assert-True ($hpsIo -match [regex]::Escape("inout      [45:0] HPS_BUS")) "hps_io.sv must use the current 46-bit framework HPS_BUS"
    Assert-True ($hpsIo -notmatch [regex]::Escape("HPS_BUS[48:46]")) "hps_io.sv still references removed framework capability bits"
    Assert-True ($hpsIo -match [regex]::Escape("{ioctl_rd, skip_add} <= req_io;")) "hps_io.sv is missing the current upload read handshake fix"

    Assert-True (Test-Path -LiteralPath "sys/emu_ports.vh") "Missing current framework emu_ports.vh include file"
    Assert-True (Test-Path -LiteralPath "sys/audio_out.sv") "Missing current SystemVerilog audio_out.sv"
    Assert-True (-not (Test-Path -LiteralPath "sys/audio_out.v")) "Obsolete sys/audio_out.v still exists"
    $ascal = Read-Text "sys/ascal.vhd"
    Assert-True ($ascal -match [regex]::Escape("bob_deint : IN std_logic := '0';")) "ascal.vhd must expose the current framework bob_deint port"
    $sysQip = Read-Text "sys/sys.qip"
    Assert-True ($sysQip -match [regex]::Escape("audio_out.sv")) "sys.qip must reference audio_out.sv"
    Assert-True ($sysQip -match [regex]::Escape("emu_ports.vh")) "sys.qip must include emu_ports.vh as a source file"

    $gitignore = Read-Text ".gitignore"
    foreach ($pattern in @("*.o", "*.d", "*.elf", "*.ll", "/build/", "dist/", "Main_MiSTer/")) {
        Assert-True ($gitignore -match [regex]::Escape($pattern)) ".gitignore is missing $pattern"
    }

    Assert-True (Test-Path -LiteralPath "scripts/build/prepare-hps-source.ps1") "Missing HPS source preparation script"
    $prepareHpsSource = Read-Text "scripts/build/prepare-hps-source.ps1"
    foreach ($requiredText in @("Main_MiSTer", "hps_linux/src", "build/hps-src")) {
        Assert-True ($prepareHpsSource -match [regex]::Escape($requiredText)) "HPS source preparation script does not mention $requiredText"
    }

    $trackedGeneratedOutputs = @(git ls-files -- '*.o' '*.ll' | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    Assert-True ($trackedGeneratedOutputs.Count -eq 0) "Generated outputs are still tracked: $($trackedGeneratedOutputs -join '; ')"

    $forbiddenTrackedPaths = @(
        "old-builds",
        "test-builds",
        "hps_linux/_old",
        "hps_linux/_Utility",
        "Groovy.rbf",
        "hps_linux/MiSTer_groovy",
        "hps_linux/MiSTer_groovy_XDP",
        "hps_linux/src/MiSTer_groovy",
        "hps_linux/src/MiSTer_groovy_XDP"
    )
    foreach ($path in $forbiddenTrackedPaths) {
        $tracked = @(git ls-files -- $path)
        Assert-True ($tracked.Count -eq 0) "Release payload path is tracked: $path"
    }

    $workflow = Read-Text ".github/workflows/build.yml"
    Assert-True ($workflow -match "check-repo-policy\.ps1") "CI must run the repository policy check"
    Assert-True ($workflow -match "test-protocol-safety\.ps1") "CI must run protocol safety checks"
    Assert-True ($workflow -match "test-audio-init\.ps1") "CI must run audio initialization regression checks"
    Assert-True ($workflow -match "api/groovymister\.cpp") "CI must compile the canonical client API"
    Assert-True ($workflow -match "retroarch/src/deps/mister/groovymister\.cpp") "CI must compile the active RetroArch client API"
    Assert-True ($workflow -match "BASE=arm-linux-gnueabihf") "CI must cross-compile the HPS server"

    Assert-True (Test-Path -LiteralPath "scripts/release/stage-release.ps1") "Missing release staging script"
    $stageRelease = Read-Text "scripts/release/stage-release.ps1"
    foreach ($artifact in @("Groovy.rbf", "MiSTer_groovy", "MiSTer_groovy_XDP", "groovy_xdp_kern.o", "libelf.so.1")) {
        Assert-True ($stageRelease -match [regex]::Escape($artifact)) "Release staging script does not mention $artifact"
    }
    Assert-True ($stageRelease -match [regex]::Escape("build/hps-artifacts/MiSTer_groovy")) "Release staging script must preserve both HPS build variants"
    Assert-True ($stageRelease -match [regex]::Escape("build/hps-src/bin/MiSTer_groovy")) "Release staging script must read prepared HPS build outputs"
    Assert-True ($stageRelease -match [regex]::Escape('Remove-Item -LiteralPath $distPath -Recurse -Force')) "Release staging must clear stale distribution contents by default"

    Write-Host "Repository policy checks passed."
}
finally {
    Pop-Location
}
