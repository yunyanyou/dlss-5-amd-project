# Official Mochizuki NR ASI payload (0.0.8.3)

Vendored payload for `dlssnr-amd.asi`:

- Base: `DLSSNR-AMD 0.0.8.3` (`931c50f`) + Direct ELF D3D12 passthrough (`6a9249f`)
- Plugin: `OptiScaler/plugins/dlssnr-amd.asi`
- Probe: `nr_present_probe.exe`
- Resources: `dlssnr-amd/` (shaders, ACO records/shaders, INT4 / performance / ultra data, language files)
- Extraction tools: `model-tools/dlssnr_extract_model.exe`, `model-tools/dlssnr-int4-weights.exe`
- Weight deltas: `experimental/dlssnr-small-experimental.delta`, `optimized/dlssnr-optimized.delta`
- ASI config templates: `ini/dlssnr-amd-optiscaler.ini`, `ini/dlssnr-amd-optiscaler-renodx.ini`
- Extra licenses: `Licenses/DearImGui-LICENSE.txt`, `Licenses/Inter-LICENSE.txt`

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
2026-11-09 against this tree (2,036 files, 314,453,294 bytes), which follows upstream's
payload byte for byte:

| File | SHA-256 |
|---|---|
| `OptiScaler/plugins/dlssnr-amd.asi` (9,420,855 B) | `bec9a8b24ddc9c9b5439ac648bc35ca9c888ca056b903871e5dde7a3db9ee1b4` |
| `nr_present_probe.exe` (262,448 B) | `87dd35d82cc9d43d6e9bc98bead17719e15c7f071a09ac45b77a702e1fabfa2a` |
| `model-tools/dlssnr_extract_model.exe` (1,382,912 B) | `9625bb72dfcd3861a44ad9ad9240c23db6915feae70c2adce5919548a99b543f` |
| `model-tools/dlssnr-int4-weights.exe` (1,859,072 B) | `3047d9416ac5bff2fe70e0445a36796907c002d3ec4b618375c9d8a7c61032a7` |
| `optimized/dlssnr-optimized.delta` (7,384,698 B) | `056a3702f01800498a7285ead35b41e3f21c47a1759fed60b12be75666847b07` |
| `experimental/dlssnr-small-experimental.delta` (2,031,749 B) | `8a2e7a655d2b6564357d31d56471607b60f467656a368a26960f138d1c961ac9` |
| `dlssnr-amd/lang/zh-CN.txt` (117,064 B, with BOM) | `965d89e4aa53fc0056d7fdccc13130c73d0d5f28d6d29afb2c13569a4fd3f9cb` |

These are the bytes in this tree, before packaging. `tools/release/package-signing.ps1`
appends an Authenticode certificate table to the staged copies, so the digests inside a
built package differ; `SIGNATURES.json` records `inputSha256` -> `signedSha256` and asserts
the PE payload is unchanged.

Provenance, measured rather than assumed: this ASI carries `nr_d3d12_asd` x5, `NR_LIN_IO` x2
and `shaders\d3d12` x1, and stamps itself `0.0.8.3`. The vendor's published `v0.0.8.3`
release ASI is 8,461,248 B (`659a369f0ad9eef051d82ae7d917d10d8394654ac64d5a678ae0feb869d321e7`)
with zero of those markers and no `dlssnr-amd/shaders/d3d12/` tree at all; those symbols come
from the vendor's unreleased `dev/0.0.8.4` branch. So this is a vendor development build
compiled by upstream and stamped `0.0.8.3` - not the vendor's published release. Describe it
as the Direct ELF payload, not as "the official 0.0.8.3 release". The payload source follows
upstream by explicit decision (see `docs/decisions.md`, 2026-11-09); switching to a different
vendor build stays a deliberate, separately verified step.

The CJK language files are not in the Windows package; they come from the matching
`DLSSNR-AMD-lang-CJK-*` asset of a release. Whatever is vendored is taken unchanged - no
re-signing, no BOM or line-ending normalisation, no patched bytes. Known gap as of
2026-11-09: the vendored `zh-CN.txt` is the 0.0.8.2-era pack (3,158 lines) while the ASI is
0.0.8.3-derived, so it has no entries for `Optimized layers`, `Ultra Performance` or
`CC_SILVER_AARDWOLD_OPTIMIZED` (0 hits; the 0.0.8.3 CJK asset has 1, 2 and 16) and still
describes Memory Guard as on by default. Those strings fall back to English in the `End`
menu until the language asset is refreshed.
