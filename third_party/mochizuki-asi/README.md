# Official Mochizuki NR ASI payload (0.0.8.2)

Vendored, unmodified payload from the vendor package:

- Sources: `DLSSNR-AMD-Vulkan-Windows-0.0.8.2-preview-x86_64.zip` (release `v0.0.8.2`,
  2026-11-02T10:46:41Z, tag commit `c53878b5`) plus `DLSSNR-AMD-lang-CJK-0.0.8.2.zip` for
  `dlssnr-amd/lang/{ja,ko,zh-CN}.txt` and `lang/fonts/`. Both come from the release asset
  list at `https://gitlab.com/mochizuki0323/DLSSNR-AMD/-/releases/v0.0.8.2` (project id
  88319462); the Windows package does not contain the CJK language files.
- Every file in this tree is byte-identical to those two packages. The plugin's own version
  resource is empty (`FileVersion=""`, `FileVersionRaw=0.0.0.0`), so the digests below are
  the only identification available. Re-verified 2026-11-04 by hashing all 1139 files.

| File | SHA-256 |
|---|---|
| `OptiScaler/plugins/dlssnr-amd.asi` (8,339,128 B) | `50cc270c3d842e42ecf80e9fe0b9b0df1cfa100a68f07fefe3d019de036d3623` |
| `nr_present_probe.exe` | `ef3cd1a64efe9ee33a5dfecf87a7362be88759fdd7a36b0678914dc0079c0611` |
| `model-tools/dlssnr_extract_model.exe` | `abefb5ca0ae2b847f991b2453546c3c28694777ced28ffa85707a71bb81e714e` |
| `model-tools/dlssnr-int4-weights.exe` | `54a7a5a4f21d9ec488d4b355793e98cbad20285285cc73bd74a96398a766ef0e` |
| `dlssnr-amd/lang/zh-CN.txt` | `67a072d95114d39632b2dcf859368517e0f49462d71b6fcfe3abb6dcbe7cdfa9` |

The asi is self-signed `CN=DLSSNR-AMD (self-signed)`, valid from 2026-11-02 10:41 UTC; the
pre-release we carried until 2026-11-04 (`bfd964e1062f94884f1e4ba1c4862f6947116da3306b6481da4f2a6ea59d7763`)
had the same size and a certificate issued the same day at 08:15 UTC. Everything else in the
tree - shaders, ACO records, INT4 data, both ini templates, `English.txt`, the licenses -
did not change between the two builds.
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
