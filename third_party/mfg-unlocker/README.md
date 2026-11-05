# MFG Unlocker (external ASI plugin)

Vendor: https://github.com/dashdogy/MFG-Unlocker — "Universal MFG Unlocker", release **v1.7.0**
(tag `v1.7.0`, published 2026-10-25). License: **MIT**, Copyright (c) 2026 Michael Robles —
`LICENSE` here is the author's own file, unchanged.

## What is shipped

| file | bytes | sha256 |
|---|---|---|
| `assets/plugins/MFGUnlocker171.asi` | 14,445,568 | `e6b6e6b70a6ed3af839c9647a32fc22660ae6b2d655062c5c072246c91fc10c7` |

That digest is the author's own `MFGUnlocker.dll` from `MFGUnlocker-v1.7.0.zip` (see
`SHA256SUMS.txt`, kept verbatim from the release). The file is only **renamed** to
`MFGUnlocker171.asi` so an ASI loader picks it up, exactly as upstream OptScaler v1.14.0 ships it —
its `plugins/MFGUnlocker171.asi` hashes the same. Nothing in the binary is patched or recompiled.
The author's build is unsigned, so the release package adds our own Authenticode signature to it,
the same step `OptiPatcher.asi` goes through; the packaged digest therefore differs from the one
above while the code stays the vendor's.

The build path `OptiScaler-DLSSNR-PreSR-Multipass-main/build_mfg_unlocker.ps1` (submodule pin) is
**not** used for delivery: it pins a 2026-09-04 commit and `external/RTX40MFG-Unlock` is not
registered in `.gitmodules`, so its `git submodule update --init` cannot work. Treat the release
asset above as the source of truth.

## Why this plugin is part of the product

`dlssnr-amd.asi` applies neural rendering to the frame the frame generator is about to consume only
when it can **adopt** that generator's swap-chain proxy. Its gate is the *caller* of
`xefgSwapChainD3D12{Init,GetSwapChainPtr}` (`nr_asi_main.cpp`: `game_fg_call()` excludes addresses
inside OptiScaler's own module). When OptiScaler itself makes those calls — which it does, from
`framegen/xefg/XeFG_Dx12.cpp` — the plugin declines to adopt and falls back to running its layers
at the game's outer Present, so only 1 of every N presented frames carries NR: under XeSS frame
generation that alternation is a visible flicker.

An external unlocker module makes the same calls from its own image, so the plugin adopts the proxy
and logs `Present layers: the game's own frame generation (XeSS frame generation) ... once a game
frame, before frame generation`. That is also the vendor's supported combination; its ini says
"OptiScaler's own frame generation gets no such picture" about the DLSS-G HUD-less route.

This replaced the fork's in-host patch layer (`proxies/XeFGUnlock.h`, `proxies/XeLLUnLock.h`,
`proxies/XeFGPacing.h`, removed together with the `[XeFG]` keys `UnlockMFG`,
`MaxInterpolatedFrames` and `ExtraPacing`), which could never satisfy `game_fg_call` precisely
because it ran inside OptiScaler. `[XeFG] XeFGFlipQueue` and `XeFGDynamicMFG` are pass-throughs to
this plugin and are inert without it.
