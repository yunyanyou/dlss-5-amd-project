# 2026-11-18: 宿主与 RR 插件的汉化自建线

- **宿主**：从 deYangar/OptiScaler_chs 源码自建（v0.9.5 = 原版 master 20261117 同步 + 键值 i18n，1,639 串）。补三处他们漏的：
  1. 侧边栏 tab 标签——`Tab` 结构自带 `displayLabel` 函数指针，静态表不能 LOC，给每个 tab 加 displayLabel lambda 输出中文，`label` 字段保持英文以匹配 `MenuBox::tab`；
  2. strings_map 补 None/Strength/Method/Neural (BaBa) 等 7 键（他们的扫描器对单词串有跳过启发式）；
  3. QuirksTabLabel 内部 LOC 化。
  MSBuild v143 x64 全量编译通过（子模块需 `git submodule update --init`）。打包走 `-OptiDir chs-build/host-release`（归一化布局 + font/fakenvapi/dlssg 补齐）。
- **RR ASI**：TheAutomatic/OpenRR-ASI 源码直改 51 处菜单串为简体中文（仅 zh，无 i18n 层）+ 菜单字体从 Inter 换 NotoSansCJKsc（embed_font 生成 68MB 头文件，Inter 无 CJK 字形）。MinGW-w64 14.2（winlibs 便携包）+ 本地 glslang 构建；三个兼容补丁：rr_pe_vkdevice.cpp 补 `<memory>`；gpu/src/weights.cpp 懒加载 `BCRYPT_SHA256_ALG_HANDLE`（mingw 头无 Win8 预开句柄宏）；vulkan_lazy.sh 的编译器尊重 `RR_MINGW_CC`。payload 的 openrr-amd.asi（3.2MB 桥接变体）换成自编独立版（24.6MB，内嵌 runtime + GPU 引擎），`openrr-amd/shaders/` 同步为新 ASI 配套的 94 个 spv，`shaders-gfx11/` 保留。
- 已知差异：MFG Unlocker 标签来自 OptiPatcher（第三方 ASI，未汉化）；Neural 锐化 pending 串等 CHS 上游每日流水线补齐后跟进。

# 2026-11-21: CHS 汉化目录全面审查——strings_map 转义损坏修复 + 管线可复现化

- **根因（系统性事故）**：11-21 凌晨合并 nightly-20261119 时重写 `strings_map.json` 把键里的 C 转义序列解码成了真实字符（`\n`→真实换行、`\\`→真实反斜杠），**293 个多行串键全部失配**——apply_patch 的注入器按源码转义形态精确匹配，从此这些 tooltip 整批回退英文（FG 输出下拉说明、Async/Reflex/AntiLag 提示、DLSS 预设描述、Output Scaling 行等 ~114 处注入点）。修复：按 CHS 仓库惯例重新 C 转义，与 HEAD 逐字节核对（0 缺失 0 值差异），重跑管线恢复 57 链 + 29 tooltip + 15 直注。
- **顺带修复**：2 个反斜杠翻倍显示 bug（`C:\Windows\Fonts`、`custom\%s\dlssg` 的中文值渲染成双反斜杠）；19 条真漏翻填齐（FG 输出三件套、HUDLess 四复选框+资源、Quirks / ASI、DLSSG 替换族），术语对齐既有惯例（HUDLess 大写 L、覆盖/扩展/跳过/UI 合成/交换链）。Quirks 族术语定稿为**特例**（tab"特例与 ASI"、卡片"特例 / ASI"、"生效的特例"）——"怪癖"直译在菜单语境读感差，弃用。
- **管线可复现化**（chs-build 本地，不外传）：tab 六标签汉化从"手工改生成树"（git restore 即丢）升格为 apply_patch.py 步骤 [5.5]，带行数/函数引用形状守卫（上游改 tab 表时警告跳过而非误删）；[4.1] splashText 改为容忍已注入树（原来 sys.exit(5)），整条管线现在可在已打过补丁的树上幂等重跑。
- **有意留英文**：version_check.cpp 的 3 条更新失败提示不 LOC 化——检查在异步线程跑，早于菜单 Init 时 LOC 会显示 `[MISSING]`，比英文更糟；面板 172 条双语串审查通过（口语化、术语一致、无错译）。
- 版式核对：`Preset J/K`、`PRESET A-O`、`FPS:`、格式串、`##ImGui ID`、字体名等 87 条 zh==EN 属技术名/占位符，保留。

# 2026-11-21: 打包载荷切换到上游在线拉取模型（pins + 缓存 + 校验）

- **决策**：退役树内 `payloads/`（约 600MB、含 import 工具的 RENAME/排除映射表），改用上游 v2.1 的 `tools/build/fetch-upstream.ps1` + `upstream-pins.json`：打包期解析 pin（zip 级 + 逐文件 SHA256）→ 缓存复用（`cache/downloads/`、`cache/upstream/`，`.stamp.json` 免重解）→ PE 头/尺寸校验 → 禁运名单（NVIDIA 权重/version.dll 拒绝进包）。输出布局与旧 import 工具的规范化布局同构，PACKAGE_RELEASE 的暂存代码几乎零改动。
- **保留的 fork 重放层**：dlssnr ini 调优不再用静态模板，改为 `tools/release/fork-overrides/dlssnr-amd-fork.ini`（delta：[RenoDX] Enabled、[NRControl] Language/Theme、[Layer1] 全段）在打包期合并进 vendor 模板——vendor 新增键自动存活。openrr ini 打包期注入 `Language = zh-CN`。
- **为何之前没跟**：三条顾虑里两条被他们的实现化解（缓存使每版本只下一次下载；本地 override 支持离线），第三条"当天最小工作量"恰是模型要消除的重复税——m3 换装时改了两次导入工具排除表就是 vendor 布局漂移对映射表的持续成本。
- **换来的行为变化**：OptiPatcher 从钉死的 v0.42 变为 rolling 源自动刷新（仅 PE 校验，无 sha——上游对此件的既有取舍）；上游删 release 资产会让新构建断供（缓存内的已验证包不受影响）；跟上游新版本 = 改 pins 一行 + 重打包。
- **验收**：fetch 构建的 zip 与 payloads 构建的 staging 逐文件对比——2732 项逐字节一致，9 项差异全部为预期（重放 ini×2、重建 exe×2、OptiPatcher rolling、SOURCES md 更新、SUMS/签名派生），removed 4 项为上游流水线有意丢弃的 standalone 内重复件，added 20 项为更全的路由许可证与 aco 目录项。离线复跑 0 下载。
