# Official Mochizuki NR ASI payload (0.0.8.2)

Vendored, unmodified payload from the vendor package:

- Source: `DLSSNR-AMD-Vulkan-Windows-0.0.8.2-pre1-preview-x86_64`
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

## Fork notes (OptScaler(NR))

Identity, because the plugin's version resource is empty (`FileVersion=""`,
`FileVersionRaw=0.0.0.0`) and digests are the only identification available. Re-verified
2026-11-05 against this tree, which matches upstream's payload byte for byte:

| File | SHA-256 |
|---|---|
| `OptiScaler/plugins/dlssnr-amd.asi` (8,339,128 B) | `bfd964e1062f94884f1e4ba1c4862f6947116da3306b6481da4f2a6ea59d7763` |
| `nr_present_probe.exe` (262,448 B) | `87dd35d82cc9d43d6e9bc98bead17719e15c7f071a09ac45b77a702e1fabfa2a` |
| `model-tools/dlssnr_extract_model.exe` (1,230,744 B) | `5bc5e5c5ba3410d2323d5b36aaaa185149e42bf8a0f5aff5fc994f7b5a0ccfd5` |
| `model-tools/dlssnr-int4-weights.exe` (3,466,840 B) | `fbf2a9f205624d25edaf5704388f276abc64c32b80386774b30ac0908f4ec591` |
| `dlssnr-amd/lang/zh-CN.txt` (117,064 B, with BOM) | `965d89e4aa53fc0056d7fdccc13130c73d0d5f28d6d29afb2c13569a4fd3f9cb` |

The CJK language files are not in the Windows package; they come from the matching
`DLSSNR-AMD-lang-CJK-*` asset of the same release. Whatever the vendor ships is taken
unchanged - no re-signing, no BOM or line-ending normalisation, no patched bytes.

Why `pre1` and not the later `0.0.8.2` build, both measured rather than assumed: the two
are different builds of the same version string - same 8,339,128 bytes, 710,442 of them
different, scattered over 98 of 127 64 KiB blocks, so this is not a re-signature. We
carried the later build from 2026-11-04 to 2026-11-05, and the frame-generation behaviour
that motivated the hunt did not change with it (the discriminator is `game_fg_call`
adoption, see `docs/mochizuki.md`). So the payload follows upstream's choice, and moving to
a different vendor build stays a deliberate, separately verified step. For comparison, the
`0.0.8.2` release build digests are:

| File | SHA-256 (not shipped) |
|---|---|
| `dlssnr-amd.asi` | `50cc270c3d842e42ecf80e9fe0b9b0df1cfa100a68f07fefe3d019de036d3623` |
| `nr_present_probe.exe` | `ef3cd1a64efe9ee33a5dfecf87a7362be88759fdd7a36b0678914dc0079c0611` |
| `model-tools/dlssnr_extract_model.exe` | `abefb5ca0ae2b847f991b2453546c3c28694777ced28ffa85707a71bb81e714e` |
| `model-tools/dlssnr-int4-weights.exe` | `54a7a5a4f21d9ec488d4b355793e98cbad20285285cc73bd74a96398a766ef0e` |
| `dlssnr-amd/lang/zh-CN.txt` (no BOM) | `67a072d95114d39632b2dcf859368517e0f49462d71b6fcfe3abb6dcbe7cdfa9` |
