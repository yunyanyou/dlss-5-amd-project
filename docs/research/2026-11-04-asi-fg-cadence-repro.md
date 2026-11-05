# DLSSNR-AMD 0.0.8.2 ASI: FG multiplier is guessed, not read, under a forked OptiScaler

For pasting into an upstream issue (gitlab.com/mochizuki0323/DLSSNR-AMD). We do not file upstream
issues in this fork; this stays as the measurement record.

> **2026-11-05 更正**：这里写的是「倍率靠猜、于是多跑几次 + 页脚 ms 抖」。它**不是**逐帧画面闪烁的
> 原因。闪烁的真因是插件没能 adopt 插帧的 swap chain（`game_fg_call()` 拒绝来自 OptiScaler 自己模块
> 的调用），见 [mochizuki.md](../mochizuki.md) 的 "Flicker under OptiScaler's frame generation" 与
> [decisions.md](../decisions.md) 2026-11-05 那条。下面 Setup 里那句 "the picture both jitter" 按此理解。

## Setup

- Plugin: official `dlssnr-amd.asi` from `DLSSNR-AMD-Vulkan-Windows-0.0.8.2-preview-x86_64`
- Host: a fork of OptiScaler (OptScaler(NR) v1.14.0), `[FrameGen] Enabled=true`,
  `FGInput=dlssg`, `FGOutput=xefg`, `[XeFG] InterpolationCount=2` (3 presents per game frame)
- Game: Neverness to Everness, `HTGame.exe`, D3D12, NR at Present, `[RenoDX] Enabled = 1`

## Symptom

NR Control's footer ms and the picture both jitter, only while frame generation is on.

## Evidence

`dlssnr-amd.log` (the plugin's own estimate, two runs of the same game):

```
[nr] Present layers: 3.983 presents per game frame: frame generation detected (4x);
     source=stable timing; RenoDX layers run on every present,
     motion scaled by 1/multiplier (NRPresentFrames=0)
[nr] Present layers: 2.933 presents per game frame: frame generation now 3x;
     source=stable timing; RenoDX layers run on every present,
     motion scaled by 1/multiplier (NRPresentFrames=0)
```

`OptiScaler.log` at the same moment, five consecutive windows, all identical:

```
XeFGPacing::ReportStats XeFG pacing: 3X, real frame 18.20 ms (55.0 fps), ...
XeFGPacing::ReportStats XeFG pacing: 3X, real frame 16.64 ms (60.1 fps), ...
XeFGPacing::ReportStats XeFG pacing: 3X, real frame 18.18 ms (55.0 fps), ...
XeFGPacing::ReportStats XeFG pacing: 3X, real frame 18.32 ms (54.6 fps), ...
XeFGPacing::ReportStats XeFG pacing: 3X, real frame 16.51 ms (60.6 fps), ...
```

The chain is a steady 3X. `source=stable timing` means `DLSSG.MultiFrameCount` was not
available to the plugin, so the factor came from present intervals; the host's own
inter-present gap swings between 12.97 and 33.46 ms, and the estimate lands on 4x as often
as on 3x. With `NRPresentFrames = 0` (the default: NR runs at every Present, motion scaled
by the multiplier), a 4x estimate scales motion by 1/4 on a 3x chain, which mis-warps NR's
history. That is the visible jitter, and the footer ms moves with it.

## Workaround in use

`[RenoDX] NRPresentFrames = 1` (NR Control: Present frames -> "First present per game
frame"). Confirmed by the user: the jitter and the jumping ms both stop. This is a per-game
manual change; the fork deliberately does not set it from the installer, because it is the
vendor's default.

## What would fix it

Either of:

1. Let the plugin ask the host for the real frame-generation multiplier instead of inferring
   it from present timing (the host knows it exactly: it is what drives `XeFG pacing: 3X`).
   A stable signal the plugin can read - an Nvngx/Streamline query, a shared memory block, or
   an OptiScaler-exported function - would remove the guess entirely.
2. Or, when the multiplier is only estimable, require two consecutive windows to agree before
   applying a new value to motion scaling (the cadence detector already has hysteresis for the
   layer count; motion scaling appears to take the raw estimate), and/or clamp the scale to the
   nearest integer multiplier rather than the fractional estimate.

## Questions

- Is `DLSSG.MultiFrameCount` the only channel you read the factor from? If OptiScaler reports
  its own FG factor elsewhere, which name should a fork set?
- Should `NRPresentFrames = 0` be the default at all when the factor is estimated rather than
  reported? Once-per-game-frame is the only mode that is wrong-proof under an estimate.
