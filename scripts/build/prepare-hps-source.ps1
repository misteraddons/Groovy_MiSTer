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

function Get-RelativePathCompat {
    param(
        [string]$Base,
        [string]$Path
    )

    $baseFull = [System.IO.Path]::GetFullPath($Base)
    if (-not ($baseFull.EndsWith([System.IO.Path]::DirectorySeparatorChar) -or $baseFull.EndsWith([System.IO.Path]::AltDirectorySeparatorChar))) {
        $baseFull += [System.IO.Path]::DirectorySeparatorChar
    }

    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $baseUri = New-Object System.Uri($baseFull)
    $pathUri = New-Object System.Uri($pathFull)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Copy-TreeFiltered {
    param(
        [string]$Source,
        [string]$Destination,
        [string[]]$ExcludeRelativePaths = @()
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    Get-ChildItem -LiteralPath $Source -Force -Recurse | ForEach-Object {
        $relative = Get-RelativePathCompat -Base $Source -Path $_.FullName
        $relativeNorm = $relative.Replace('\', '/')
        foreach ($exclude in $ExcludeRelativePaths) {
            $excludeNorm = $exclude.Replace('\', '/').Trim('/')
            if ($relativeNorm.Equals($excludeNorm, [System.StringComparison]::OrdinalIgnoreCase) -or
                $relativeNorm.StartsWith($excludeNorm + "/", [System.StringComparison]::OrdinalIgnoreCase)) {
                return
            }
        }

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

function Replace-TextRequired {
    param(
        [ref]$Text,
        [string]$OldText,
        [string]$NewText,
        [string]$AlreadyPresentText,
        [string]$Description
    )

    if ($Text.Value.Contains($AlreadyPresentText)) {
        return $false
    }

    if (-not $Text.Value.Contains($OldText)) {
        throw "Unable to patch $Description."
    }

    $Text.Value = $Text.Value.Replace($OldText, $NewText)
    return $true
}

function Write-SourceText {
    param(
        [string]$Path,
        [string]$Text
    )

    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Update-GroovyMainSource {
    param([string]$Root)

    $cfgPath = Join-Path $Root "cfg.cpp"
    $cfgText = [System.IO.File]::ReadAllText($cfgPath).Replace("`r`n", "`n")
    $oldDirectVideo = '{ "DIRECT_VIDEO", (void*)(&(cfg.direct_video)), UINT8, 0, 1 },'
    $newDirectVideo = '{ "DIRECT_VIDEO", (void*)(&(cfg.direct_video)), UINT8, 0, 2 },'

    if ($cfgText.Contains($oldDirectVideo)) {
        $cfgText = $cfgText.Replace($oldDirectVideo, $newDirectVideo)
        Write-SourceText -Path $cfgPath -Text $cfgText
    }

    if ($cfgText -notmatch '\{\s*"DIRECT_VIDEO"\s*,\s*\(void\*\)\(&\(cfg\.direct_video\)\)\s*,\s*UINT8\s*,\s*0\s*,\s*2\s*\}') {
        throw "Generated cfg.cpp does not accept direct_video=2."
    }

    $makefilePath = Join-Path $Root "Makefile"
    $makefile = [System.IO.File]::ReadAllText($makefilePath).Replace("`r`n", "`n")
    $makefileRef = [ref]$makefile
    $null = Replace-TextRequired -Text $makefileRef -Description "Makefile AF_XDP default" -AlreadyPresentText "_AF_XDP ?= 0" `
        -OldText "endif`n`nINCLUDE`t= -I./" `
        -NewText "endif`n`n_AF_XDP ?= 0`n`nINCLUDE`t= -I./"
    $null = Replace-TextRequired -Text $makefileRef -Description "Makefile AF_XDP include paths" -AlreadyPresentText "support/groovy/kernel/lib/xdp-tools/headers" `
        -OldText "INCLUDE += -I./lib/serial_server/library`n" `
        -NewText @'
INCLUDE += -I./lib/serial_server/library

ifeq ($(_AF_XDP), 1)
INCLUDE += -I./support/groovy/kernel/lib/xdp-tools/headers
INCLUDE += -I./lib/libelf
INCLUDE += -I./lib/libbpf
INCLUDE += -I./lib/libxdp
endif
'@
    $null = Replace-TextRequired -Text $makefileRef -Description "Makefile Groovy project name" -AlreadyPresentText "PRJ = MiSTer_groovy" `
        -OldText "PRJ = MiSTer" `
        -NewText @'
ifeq ($(_AF_XDP), 1)
PRJ = MiSTer_groovy_XDP
else
PRJ = MiSTer_groovy
endif
'@
    $null = Replace-TextRequired -Text $makefileRef -Description "Makefile production source filter" -AlreadyPresentText 'CPP_SRC := $(filter-out %_unittest.cpp,$(CPP_SRC))' `
        -OldText "          `$`(wildcard ./support/*/*.cpp)`n`nIMG =" `
        -NewText "          `$`(wildcard ./support/*/*.cpp)`n`nCPP_SRC := `$`(filter-out %_unittest.cpp,`$`(CPP_SRC))`n`nIMG ="
    $null = Replace-TextRequired -Text $makefileRef -Description "Makefile GCC 10 C++ compatibility" -AlreadyPresentText "-Wno-class-memaccess -Wno-narrowing" `
        -OldText "-std=gnu++14 -Wno-class-memaccess" `
        -NewText "-std=gnu++14 -Wno-class-memaccess -Wno-narrowing"
    $null = Replace-TextRequired -Text $makefileRef -Description "Makefile AF_XDP libraries" -AlreadyPresentText "AFXDP_LIB = -Llib/libelf -lelf lib/libxdp/libxdp.a lib/libbpf/libbpf.a" `
        -OldText "IMLIB2_LIB  = -Llib/imlib2 -lfreetype -lbz2 -lpng16 -lz -lImlib2`n" `
        -NewText @'
IMLIB2_LIB  = -Llib/imlib2 -lfreetype -lbz2 -lpng16 -lz -lImlib2
ifeq ($(_AF_XDP), 1)
AFXDP_LIB = -Llib/libelf -lelf lib/libxdp/libxdp.a lib/libbpf/libbpf.a
endif
'@
    $null = Replace-TextRequired -Text $makefileRef -Description "Makefile link flags" -AlreadyPresentText '$(IMLIB2_LIB) $(AFXDP_LIB)' `
        -OldText 'LFLAGS	= -lc -lstdc++ -lm -lrt $(IMLIB2_LIB) -Llib/bluetooth -lbluetooth -lpthread' `
        -NewText 'LFLAGS	= -lc -lstdc++ -lm -lrt $(IMLIB2_LIB) $(AFXDP_LIB) -Llib/bluetooth -lbluetooth -lpthread'
    $null = Replace-TextRequired -Text $makefileRef -Description "Makefile AF_XDP define" -AlreadyPresentText "DFLAGS += -D_AF_XDP" `
        -OldText @'
ifeq ($(PROFILING),1)
	DFLAGS += -DPROFILING
endif

'@ `
        -NewText @'
ifeq ($(PROFILING),1)
	DFLAGS += -DPROFILING
endif

ifeq ($(_AF_XDP), 1)
	DFLAGS += -D_AF_XDP
endif

'@
    Write-SourceText -Path $makefilePath -Text $makefileRef.Value

    $supportPath = Join-Path $Root "support.h"
    $support = [System.IO.File]::ReadAllText($supportPath).Replace("`r`n", "`n")
    $supportRef = [ref]$support
    $null = Replace-TextRequired -Text $supportRef -Description "support.h Groovy include" -AlreadyPresentText 'support/groovy/groovy.h' `
        -OldText "// 3DO  support`n#include `"support/3do/3do.h`"`n" `
        -NewText "// 3DO  support`n#include `"support/3do/3do.h`"`n`n// GROOVY support`n#include `"support/groovy/groovy.h`"`n"
    Write-SourceText -Path $supportPath -Text $supportRef.Value

    $userIoHeaderPath = Join-Path $Root "user_io.h"
    $userIoHeader = [System.IO.File]::ReadAllText($userIoHeaderPath).Replace("`r`n", "`n")
    $userIoHeaderRef = [ref]$userIoHeader
    $null = Replace-TextRequired -Text $userIoHeaderRef -Description "user_io.h Groovy type helper" -AlreadyPresentText "char is_groovy();" `
        -OldText "char is_3do();`n" `
        -NewText "char is_3do();`nchar is_groovy();`n"
    Write-SourceText -Path $userIoHeaderPath -Text $userIoHeaderRef.Value

    $shmemHeaderPath = Join-Path $Root "shmem.h"
    $shmemHeader = [System.IO.File]::ReadAllText($shmemHeaderPath).Replace("`r`n", "`n")
    $shmemHeaderRef = [ref]$shmemHeader
    $null = Replace-TextRequired -Text $shmemHeaderRef -Description "shmem.h private mapping helper" -AlreadyPresentText "shmem_map_private" `
        -OldText "void *shmem_map(uint32_t address, uint32_t size);`n" `
        -NewText "void *shmem_map(uint32_t address, uint32_t size);`nvoid *shmem_map_private(uint32_t address, uint32_t size);`n"
    Write-SourceText -Path $shmemHeaderPath -Text $shmemHeaderRef.Value

    $shmemPath = Join-Path $Root "shmem.cpp"
    $shmem = [System.IO.File]::ReadAllText($shmemPath).Replace("`r`n", "`n")
    $shmemRef = [ref]$shmem
    $null = Replace-TextRequired -Text $shmemRef -Description "shmem.cpp private mapping helper" -AlreadyPresentText "shmem_map_private" `
        -OldText "int shmem_unmap(void* map, uint32_t size)`n" `
        -NewText @'
void *shmem_map_private(uint32_t address, uint32_t size)
{
	if (memfd < 0)
	{
		memfd = open("/dev/mem", O_RDWR | O_SYNC | O_CLOEXEC);
		if (memfd == -1)
		{
			printf("Error: Unable to open /dev/mem!\n");
			return 0;
		}
	}

	void *res = mmap(0, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, memfd, address);
	if (res == (void *)-1)
	{
		printf("Error: Unable to mmap private (0x%X, %d)!\n", address, size);
		return 0;
	}

	return res;
}

int shmem_unmap(void* map, uint32_t size)
'@
    Write-SourceText -Path $shmemPath -Text $shmemRef.Value

    $userIoPath = Join-Path $Root "user_io.cpp"
    $userIo = [System.IO.File]::ReadAllText($userIoPath).Replace("`r`n", "`n")
    $userIoRef = [ref]$userIo
    $null = Replace-TextRequired -Text $userIoRef -Description "user_io.cpp Groovy type helper" -AlreadyPresentText "char is_groovy()" `
        -OldText "static int is_no_type = 0;`n" `
        -NewText @'
static int is_groovy_type = 0;
char is_groovy()
{
	if (!is_groovy_type) is_groovy_type = strcasecmp(orig_name, "Groovy") ? 2 : 1;
	return (is_groovy_type == 1);
}

static int is_no_type = 0;
'@
    $null = Replace-TextRequired -Text $userIoRef -Description "user_io.cpp Groovy type reset" -AlreadyPresentText "`tis_groovy_type = 0;`n`tcore_name[0] = 0;" `
        -OldText "`tis_uneon_type = 0;`n`tcore_name[0] = 0;`n" `
        -NewText "`tis_uneon_type = 0;`n`tis_groovy_type = 0;`n`tcore_name[0] = 0;`n"
    $null = Replace-TextRequired -Text $userIoRef -Description "user_io.cpp Groovy left analog hook" -AlreadyPresentText "groovy_send_analog(joystick, 0" `
        -OldText @'
		DisableIO();
	}
}

void user_io_r_analog_joystick(unsigned char joystick, char valueX, char valueY)
'@ `
        -NewText @'
		DisableIO();
	}

	if (is_groovy()) groovy_send_analog(joystick, 0, valueX, valueY);
}

void user_io_r_analog_joystick(unsigned char joystick, char valueX, char valueY)
'@
    $null = Replace-TextRequired -Text $userIoRef -Description "user_io.cpp Groovy right analog hook" -AlreadyPresentText "groovy_send_analog(joystick, 1" `
        -OldText @'
		DisableIO();
	}
}

void user_io_digital_joystick(unsigned char joystick, uint32_t map, int newdir)
'@ `
        -NewText @'
		DisableIO();
	}

	if (is_groovy()) groovy_send_analog(joystick, 1, valueX, valueY);
}

void user_io_digital_joystick(unsigned char joystick, uint32_t map, int newdir)
'@
    $null = Replace-TextRequired -Text $userIoRef -Description "user_io.cpp Groovy digital joystick hook" -AlreadyPresentText "groovy_send_joystick(joystick, map)" `
        -OldText "`tregister_activity();`n}`n`nstatic uint8_t CSD" `
        -NewText "`tregister_activity();`n`tif (is_groovy()) groovy_send_joystick(joystick, map);`n}`n`nstatic uint8_t CSD"
    $null = Replace-TextRequired -Text $userIoRef -Description "user_io.cpp Groovy poll hook" -AlreadyPresentText "groovy_poll();" `
        -OldText "`tif (is_3do()) p3do_poll();`n`tprocess_ss(0);" `
        -NewText "`tif (is_3do()) p3do_poll();`n`tif (is_groovy()) groovy_poll();`n`tprocess_ss(0);"
    $null = Replace-TextRequired -Text $userIoRef -Description "user_io.cpp Groovy keyboard hook" -AlreadyPresentText "groovy_send_keyboard(key, press)" `
        -OldText "`tif (core_type == CORE_TYPE_8BIT)`n`t{`n`t`tuint32_t code = get_ps2_code(key);" `
        -NewText "`tif (core_type == CORE_TYPE_8BIT)`n`t{`n`t`tif (is_groovy()) groovy_send_keyboard(key, press);`n`t`tuint32_t code = get_ps2_code(key);"
    $null = Replace-TextRequired -Text $userIoRef -Description "user_io.cpp Groovy mouse hook" -AlreadyPresentText "groovy_send_mouse(ps2_mouse" `
        -OldText @'
				spi_w(ps2_mouse[2] | ((((uint16_t)b) << 1) & 0x100));
				DisableIO();
			}
'@ `
        -NewText @'
				spi_w(ps2_mouse[2] | ((((uint16_t)b) << 1) & 0x100));
				DisableIO();
				if (is_groovy()) groovy_send_mouse(ps2_mouse[0], ps2_mouse[1], ps2_mouse[2], (unsigned char)w);
			}
'@
    Write-SourceText -Path $userIoPath -Text $userIoRef.Value

    $menuPath = Join-Path $Root "menu.cpp"
    $menu = [System.IO.File]::ReadAllText($menuPath).Replace("`r`n", "`n")
    $menuRef = [ref]$menu
    $null = Replace-TextRequired -Text $menuRef -Description "menu.cpp Groovy file load hook" -AlreadyPresentText "groovy_user_io_file_gmc(selPath)" `
        -OldText @'
					else
					{
						user_io_file_tx(selPath, idx, opensave, 0, 0, load_addr);
						if (!store_name)
						{
							game_docs_init(selPath, user_io_get_file_crc());
							if (user_io_use_cheats()) cheats_init(selPath, user_io_get_file_crc());
						}
					}
'@ `
        -NewText @'
					else
					{
						if (is_groovy())
						{
							groovy_user_io_file_gmc(selPath);
						}
						else
						{
							user_io_file_tx(selPath, idx, opensave, 0, 0, load_addr);
							if (!store_name)
							{
								game_docs_init(selPath, user_io_get_file_crc());
								if (user_io_use_cheats()) cheats_init(selPath, user_io_get_file_crc());
							}
						}
					}
'@
    $null = Replace-TextRequired -Text $menuRef -Description "menu.cpp Groovy core switch stop hook" -AlreadyPresentText "groovy_stop();" `
        -OldText "`n`t`tif (isXmlName(Selected_tmp))`n" `
        -NewText "`n`t`tif (is_groovy()) groovy_stop();`n`n`t`tif (isXmlName(Selected_tmp))`n"
    $null = Replace-TextRequired -Text $menuRef -Description "menu.cpp Groovy secondary core switch stop hook" -AlreadyPresentText "case MENU_CORE_FILE_SELECTED2:`n`t`tif (is_groovy()) groovy_stop();" `
        -OldText "`tcase MENU_CORE_FILE_SELECTED2:`n`t`tfpga_load_rbf(Selected_tmp, selPath);" `
        -NewText "`tcase MENU_CORE_FILE_SELECTED2:`n`t`tif (is_groovy()) groovy_stop();`n`t`tfpga_load_rbf(Selected_tmp, selPath);"
    Write-SourceText -Path $menuPath -Text $menuRef.Value
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

$overlayExcludes = @(
    "Makefile",
    "input.cpp",
    "menu.cpp",
    "shmem.cpp",
    "shmem.h",
    "support.h",
    "user_io.cpp",
    "user_io.h"
)

Copy-TreeFiltered -Source $mainMisterPath -Destination $outputPath
Copy-TreeFiltered -Source $overlayPath -Destination $outputPath -ExcludeRelativePaths $overlayExcludes
Update-GroovyMainSource -Root $outputPath

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
    "Overlay excludes: $($overlayExcludes -join ', ')"
    "Applied patches: cfg.cpp direct_video=2, current Main Makefile Groovy targets, support/user_io/menu Groovy hooks, shmem private mapping"
)
Set-Content -LiteralPath (Join-Path $outputPath "groovy-build-source.txt") -Value $stamp -Encoding ascii

Write-Host "Prepared HPS source tree: $outputPath"
Write-Host "Build non-XDP: make -C `"$outputPath`" BASE=arm-none-linux-gnueabihf _AF_XDP=0"
Write-Host "Build XDP:     make -C `"$outputPath`" BASE=arm-none-linux-gnueabihf _AF_XDP=1"
