# 2026-11-18: 宿主与 RR 插件的汉化自建线

- **宿主**：从 deYangar/OptiScaler_chs 源码自建（v0.9.5 = 原版 master 20261117 同步 + 键值 i18n，1,639 串）。补三处他们漏的：
  1. 侧边栏 tab 标签——`Tab` 结构自带 `displayLabel` 函数指针，静态表不能 LOC，给每个 tab 加 displayLabel lambda 输出中文，`label` 字段保持英文以匹配 `MenuBox::tab`；
  2. strings_map 补 None/Strength/Method/Neural (BaBa) 等 7 键（他们的扫描器对单词串有跳过启发式）；
  3. QuirksTabLabel 内部 LOC 化。
  MSBuild v143 x64 全量编译通过（子模块需 `git submodule update --init`）。打包走 `-OptiDir chs-build/host-release`（归一化布局 + font/fakenvapi/dlssg 补齐）。
- **RR ASI**：TheAutomatic/OpenRR-ASI 源码直改 51 处菜单串为简体中文（仅 zh，无 i18n 层）+ 菜单字体从 Inter 换 NotoSansCJKsc（embed_font 生成 68MB 头文件，Inter 无 CJK 字形）。MinGW-w64 14.2（winlibs 便携包）+ 本地 glslang 构建；三个兼容补丁：rr_pe_vkdevice.cpp 补 `<memory>`；gpu/src/weights.cpp 懒加载 `BCRYPT_SHA256_ALG_HANDLE`（mingw 头无 Win8 预开句柄宏）；vulkan_lazy.sh 的编译器尊重 `RR_MINGW_CC`。payload 的 openrr-amd.asi（3.2MB 桥接变体）换成自编独立版（24.6MB，内嵌 runtime + GPU 引擎），`openrr-amd/shaders/` 同步为新 ASI 配套的 94 个 spv，`shaders-gfx11/` 保留。
- 已知差异：MFG Unlocker 标签来自 OptiPatcher（第三方 ASI，未汉化）；Neural 锐化 pending 串等 CHS 上游每日流水线补齐后跟进。
