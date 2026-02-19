# Release Artifacts

Build outputs and release payloads are intentionally not tracked in this repository.

Use GitHub Releases for distributable files such as:

- `Groovy.rbf`
- `MiSTer_groovy`
- `MiSTer_groovy_XDP`
- emulator bundles (`*.7z`, `*.zip`)
- test/staging drops previously under `test-builds/` and `old-builds/`

## Suggested release workflow

1. Prepare the HPS build tree:
   - `pwsh -File scripts/build/prepare-hps-source.ps1`
2. Build HPS payloads from `build/hps-src` with the ARM 10.2.1 toolchain:
   - `make -C build/hps-src BASE=arm-none-linux-gnueabihf _AF_XDP=0`
   - `rm build/hps-src/support/groovy/groovy.cpp.o`
   - `make -C build/hps-src BASE=arm-none-linux-gnueabihf _AF_XDP=1`
3. Build FPGA artifacts into the repo root or `output_files/`.
4. Stage the expected release payloads and generate a checksum manifest:
   - `pwsh -File scripts/release/stage-release.ps1`
5. Upload `dist/*` to a GitHub Release.

The staging script expects these files after a full release build:

- `Groovy.rbf`
- `MiSTer_groovy`
- `MiSTer_groovy_XDP`
- `groovy_xdp_kern.o`
- `libelf.so.1`
