# Official Mochizuki NR ASI payload (0.0.8.2)

Vendored, unmodified payload from the vendor package:

- Source: `DLSSNR-AMD-Vulkan-Windows-0.0.8.2-pre1-preview-x86_64`
- Plugin SHA-256: `bfd964e1062f94884f1e4ba1c4862f6947116da3306b6481da4f2a6ea59d7763`
  (8,339,128 bytes). The vendor's later `0.0.8.2-preview` release asset carries the same
  size but a different digest (`50cc270c3d842e42ecf80e9fe0b9b0df1cfa100a68f07fefe3d019de036d3623`,
  built 2026-11-02 10:41), so this payload is the pre-release, not that build. Verified
  2026-11-04 by downloading the release package from the project's package registry
  (project id 88319462) and hashing `optiscaler/asi/dlssnr-amd.asi`.
- Plugin: `optiscaler/asi/dlssnr-amd.asi`
- Probe: `optiscaler/asi/nr_present_probe.exe`
- Resources: `dlssnr-amd/` (shaders, ACO records/shaders, INT4 data, language files)
- Extraction tools: `model-tools/dlssnr_extract_model.exe`, `model-tools/dlssnr-int4-weights.exe`
- ASI config template: `ini/dlssnr-amd-optiscaler.ini`
- Extra licenses: `optiscaler/asi/DearImGui-LICENSE.txt`, `optiscaler/asi/Inter-LICENSE.txt`

Neural Rendering is owned by this plugin. The project no longer builds or ships
`MochizukiNrRuntime.dll`, and the host does not require it: it detects the loaded
`dlssnr-amd.asi` module at runtime and disables its own NR engine.

Installation copies this tree as-is into the game folder (`OptiScaler/plugins/dlssnr-amd.asi`,
`dlssnr-amd/*`, `model-tools/*`). Models are extracted from the user's
`nvngx_dlssnr.dll` with the tools above; only file names, layout and extraction
success are checked. There is deliberately no hash or version whitelist, so a
newer official plugin or resource set can replace these files.

Do not mix this resource tree with the retired built-in runtime's `dlssnr-amd`
shaders or ACO files. Upgrade and uninstall operate on the installed file
inventory, never on pattern guesses.
