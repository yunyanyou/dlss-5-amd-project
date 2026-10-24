using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;

namespace OptScalerNR.Launcher
{
    /// <summary>
    /// 游戏目录里的精简面板：切换注入名、看推荐、存/套 ini 预设、收发画面分享码。
    /// 复用主窗口的主题资源（LauncherTheme / DialogTheme）、分享码（MochizukiShareCode）
    /// 与预设（IniProfiles），只保留一个窗口。
    /// </summary>
    public static class PanelWindow
    {
        static readonly string[] Candidates = { "dxgi", "winmm", "d3d12", "winhttp", "wininet", "dbghelp", "version" };

        static Window _window;
        static string _dir;
        static string _theme = "auto";
        static Button _themeToggle, _maxBtn;
        static TextBlock _hardwareText;
        static StackPanel _list;
        static TextBlock _heroKicker, _heroTitle, _heroMonogram, _bottomStatus;
        static System.Windows.Controls.StackPanel _heroFacts;
        static System.Windows.Controls.ProgressBar _heroProgress;
        static System.Windows.Media.ImageBrush _heroBgBrush;
        static System.Windows.Shapes.Ellipse _bottomLed;
        static LocalArtwork.Scope _heroArtwork;
        static int _refreshGeneration;

        // ---- 兼容修复：检查结果缓存 + 控件 ----
        static TextBlock _compatSummary, _compatStatus;
        static Button _compatRepairBtn, _compatRestoreBtn, _compatHelpBtn;
        static CompatReport _compatReport;

        // 本栏（兼容诊断）触发的运行消息显示在本栏，不再挤到分享栏的状态行。
        static void CompatNote(string text)
        {
            if (_compatStatus != null) _compatStatus.Text = text ?? "";
        }

        // 后台填充的扫描结果（FolderGameScanner 的最佳候选 + wiki 建议），按目录缓存。
        static FileInfo _gameExeCache;
        static string _gameExeDir;
        static WikiAdvice AdviceHitCache;
        static string AdviceHitDir;

        // ---- ini 共享配置：字段与流程逐行对齐 MainController.Profiles.cs ----
        static IniProfiles _iniProfiles;
        static ComboBox _iniProfileCombo;
        static TextBox _iniSearchBox;
        static TextBlock _iniProfileStatus;
        static Button _iniSaveButton, _iniQuickSaveButton, _iniImportButton, _iniRenameButton, _iniDeleteButton, _iniApplyButton, _iniFolderButton;
        static string[] _iniProfileNames = new string[0];
        static string _iniSelectedProfile = "";
        static bool _iniUpdating, _iniPluginsEnabled, _iniInitialized, _panelBusy;
        static int _iniSelectionGeneration;
        static string _iniStatus = "", _iniStatusDetail = "";
        static System.Threading.Mutex _targetMutex;

        sealed class IniGameIdentity
        {
            public string Key, Directory, Name;
            public int Generation;
        }

        public static Window Create(string dir)
        {
            _dir = dir;
            LauncherTheme.Apply(_theme);
            var dialog = Program.LoadDialogTheme();
            if (Application.Current != null)
            {
                Application.Current.Resources.MergedDictionaries.Add(dialog);
                Application.Current.Resources.MergedDictionaries.Add(LauncherTheme.Resources);
            }

            using (var stream = Program.OpenXaml("PanelWindow.xaml"))
                _window = (Window)XamlReader.Load(stream);

            _list = (StackPanel)_window.FindName("LoaderList");
            _heroKicker = (TextBlock)_window.FindName("HeroKicker");
            _heroTitle = (TextBlock)_window.FindName("HeroTitle");
            _heroFacts = (System.Windows.Controls.StackPanel)_window.FindName("HeroFacts");
            _heroMonogram = (TextBlock)_window.FindName("HeroMonogram");
            _heroProgress = (System.Windows.Controls.ProgressBar)_window.FindName("HeroProgress");
            _heroBgBrush = (System.Windows.Media.ImageBrush)_window.FindName("HeroBgBrush");
            _heroArtwork = new LocalArtwork.Scope(_window.Dispatcher);
            _bottomStatus = (TextBlock)_window.FindName("BottomStatus");
            _bottomLed = (System.Windows.Shapes.Ellipse)_window.FindName("BottomLed");

            var close = (Button)_window.FindName("CloseBtn");
            close.Click += (s, e) => _window.Close();
            var min = (Button)_window.FindName("MinBtn");
            min.Click += (s, e) => _window.WindowState = WindowState.Minimized;
            _maxBtn = (Button)_window.FindName("MaxBtn");
            if (_maxBtn != null) _maxBtn.Click += (s, e) =>
                _window.WindowState = _window.WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
            _window.StateChanged += (s, e) =>
            {
                if (_window.WindowState == WindowState.Maximized)
                {
                    _window.BorderThickness = new Thickness(7);
                    if (_maxBtn != null) _maxBtn.Content = "\x25A3";
                }
                else
                {
                    _window.BorderThickness = new Thickness(1);
                    if (_maxBtn != null) _maxBtn.Content = "\x25A2";
                }
            };
            _hardwareText = (TextBlock)_window.FindName("HardwareInfo");
            _themeToggle = (Button)_window.FindName("ThemeToggle");
            InitThemeToggle();
            // 上游同款：圆角卡片靠显式 Clip 裁掉溢出的内容（Border.CornerRadius 不裁子元素）。
            var heroCard = _window.FindName("HeroCard") as System.Windows.Controls.Border;
            if (heroCard != null)
                heroCard.SizeChanged += delegate
                {
                    heroCard.Clip = new System.Windows.Media.RectangleGeometry(
                        new Rect(0, 0, heroCard.ActualWidth, heroCard.ActualHeight), 18, 18);
                };
            ((Button)_window.FindName("RefreshBtn")).Click += (s, e) => Refresh();
            ((Button)_window.FindName("QuickLogButton")).Click += (s, e) => OpenLog();
            Microsoft.Win32.SystemEvents.UserPreferenceChanged += OnSystemThemeChanged;
            _window.Closed += (s, e) => Microsoft.Win32.SystemEvents.UserPreferenceChanged -= OnSystemThemeChanged;
            ((System.Windows.Documents.Run)_window.FindName("AuthorCaption")).Text = " · 作者：";
            var author = (System.Windows.Documents.Hyperlink)_window.FindName("AuthorLink");
            author.RequestNavigate += (s, e) => { OpenUrl("https://github.com/TheAutomatic/dlss-5-amd-project"); e.Handled = true; };

            ((Button)_window.FindName("OptiBtn")).Click += (s, e) => InstallOptiPatcher();
            ((Button)_window.FindName("LogBtn")).Click += (s, e) => OpenLog();
            _compatSummary = (TextBlock)_window.FindName("CompatSummary");
            _compatStatus = (TextBlock)_window.FindName("CompatStatus");
            _compatRepairBtn = (Button)_window.FindName("CompatRepairBtn");
            _compatRestoreBtn = (Button)_window.FindName("CompatRestoreBtn");
            _compatHelpBtn = (Button)_window.FindName("CompatHelpBtn");
            if (_compatRepairBtn != null) _compatRepairBtn.Click += delegate { CompatRepair(); };
            if (_compatRestoreBtn != null) _compatRestoreBtn.Click += delegate { CompatRestore(); };
            if (_compatHelpBtn != null) _compatHelpBtn.Click += delegate { CompatHelp(); };
            InitProfiles();

            _window.DragOver += (s, e) =>
            {
                if (e.Data.GetDataPresent(DataFormats.FileDrop)) e.Effects = DragDropEffects.Copy;
            };
            _window.Drop += (s, e) =>
            {
                var files = e.Data.GetData(DataFormats.FileDrop) as string[];
                if (files == null || files.Length == 0) return;
                var path = files[0];
                if (File.Exists(path)) path = Path.GetDirectoryName(path);
                if (path != null)
                {
                    _dir = path;
                    Refresh();
                }
            };

            Refresh();
            return _window;
        }

        // ---------------------------------------------------------------- refresh
        static void Refresh()
        {
            RenderNow();
            // 上游同款：扫描/检查期间名字栏底部的进度条进入加载动画，完成后停止。
            if (_heroProgress != null) _heroProgress.IsIndeterminate = true;
            // 与上游启动器一致：窗口先渲染缓存，扫描 EXE、拉 Wiki、找封面都在后台做，完成后回填。
            var generation = ++_refreshGeneration;
            var dir = _dir;
            System.Threading.Tasks.Task.Run(delegate
            {
                if (!string.Equals(_gameExeDir, dir, StringComparison.OrdinalIgnoreCase))
                {
                    ExeCandidate best = null;
                    try
                    {
                        var scan = FolderGameScanner.ScanAsync(dir, System.Threading.CancellationToken.None, null).Result;
                        foreach (var candidate in scan.Candidates)
                            if (!candidate.Auxiliary && (best == null || candidate.Rank < best.Rank)) best = candidate;
                    }
                    catch { }
                    _gameExeCache = best == null ? null : new FileInfo(best.Path);
                    _gameExeDir = dir;
                }
                var advice = AdviceHitFor(dir);
                // hero 背景：本地封面图优先（Steam library_hero / header / 启动图），
                // 没有就用扫描到的游戏 EXE 的 Shell 图标。全部离线，不联网拉图。
                var hero = FindHeroImage(dir);
                var heroFromIcon = false;
                if (hero == null && _gameExeCache != null && File.Exists(_gameExeCache.FullName))
                {
                    hero = _gameExeCache.FullName;
                    heroFromIcon = true;
                }
                var compat = CheckCompat(dir);
                _window.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (generation != _refreshGeneration || !string.Equals(_dir, dir, StringComparison.OrdinalIgnoreCase)) return;
                    RenderNow();
                    UpdateCompatUi(compat);
                    if (_heroProgress != null) _heroProgress.IsIndeterminate = false;
                    LocalArtwork.Load(_heroArtwork, hero, heroFromIcon ? 256 : 1000, heroFromIcon, !heroFromIcon, delegate(System.Windows.Media.ImageSource image)
                    {
                        _heroBgBrush.ImageSource = image;
                        // 字母水印只在“图标已显示”时隐藏，其余情况（本地图/无图）保持可见。
                        if (_heroMonogram != null)
                            _heroMonogram.Visibility = heroFromIcon && image != null ? Visibility.Collapsed : Visibility.Visible;
                    });
                }));
            });
        }

        static void RenderNow()
        {
            _list.Children.Clear();
            var current = CurrentInjection();
            var occupied = Occupied();
            var advice = AdviceCached();
            var recommend = advice != null ? advice.Recommended : null;

            foreach (var name in Candidates)
            {
                var isOurs = current != null && string.Equals(current.Name, name, StringComparison.OrdinalIgnoreCase);
                var isOcc = occupied.Contains(name);
                var isRec = recommend != null && string.Equals(recommend, name + ".dll", StringComparison.OrdinalIgnoreCase);

                var row = new Border
                {
                    CornerRadius = new CornerRadius(6),
                    Padding = new Thickness(10, 7, 10, 7),
                    Margin = new Thickness(0, 0, 0, 6),
                    Cursor = System.Windows.Input.Cursors.Hand,
                    Background = isOurs ? LauncherTheme.Brush("ThemeSuccessBg")
                               : isOcc ? LauncherTheme.Brush("ThemeWarningBg")
                               : LauncherTheme.Brush("ThemeSubtle")
                };
                var stack = new StackPanel();
                stack.Children.Add(new TextBlock
                {
                    Text = name + ".dll",
                    FontSize = 12.5,
                    Foreground = isOurs ? LauncherTheme.Brush("ThemeSuccess")
                               : isOcc ? LauncherTheme.Brush("ThemeWarning")
                               : isRec ? LauncherTheme.Brush("ThemeAccent")
                               : LauncherTheme.Brush("ThemeInk")
                });
                var state = isOurs ? "当前注入" : isOcc ? "被占用" : isRec ? "Wiki 推荐" : "备用";
                stack.Children.Add(new TextBlock
                {
                    Text = state,
                    FontSize = 10.5,
                    Foreground = LauncherTheme.Brush("ThemeMuted"),
                    Margin = new Thickness(0, 1, 0, 0)
                });
                row.Child = stack;
                var capture = name;
                row.MouseLeftButtonUp += (s, e) => SwitchTo(capture);
                _list.Children.Add(row);
            }

            // Hero 卡：顶部小字=目录路径，大字=游戏名，说明区=分组标签行，底部=横排按钮。
            var exe = GameExe();
            var scanned = string.Equals(_gameExeDir, _dir, StringComparison.OrdinalIgnoreCase);
            _heroKicker.Text = _dir;
            var title = advice != null
                ? (advice.WikiName ?? FirstProfileName(advice.Profile)) : null;
            if (string.IsNullOrEmpty(title)) title = Path.GetFileName(_dir.TrimEnd('\\', '/'));
            _heroTitle.Text = title;
            _heroMonogram.Text = string.IsNullOrEmpty(title) ? "N"
                : title.Substring(0, 1).ToUpperInvariant();
            _heroFacts.Children.Clear();
            AddHeroFact("程序", exe != null ? exe.Name
                : scanned ? "未找到（可把游戏 EXE 拖进窗口指定）"
                : "正在扫描…", 0);
            if (advice == null)
            {
                AddHeroFact("Wiki", "正在获取 Wiki 与支持列表…", 1);
            }
            else
            {
                AddHeroFact("Wiki", WikiFact(advice), 1);
                AddHeroFact("OptiPatcher支持", OptiFact(advice), 2);
            }
            // 刷新时保留当前背景图：LocalArtwork 有缓存，同目录刷新返回同一实例不会重绘；
            // 清空再加载会闪。换目录时由新结果（或 null）自然替换。

            _bottomLed.Fill = current != null ? LauncherTheme.Brush("ThemeSuccess") : LauncherTheme.Brush("ThemeWarning");
            _bottomStatus.Text = current != null
                ? "已注入 " + current.Name + ".dll"
                : "未检测到注入";
            RefreshHardware();

            SelectGameProfiles();
        }

        static string WikiFact(WikiAdvice advice)
        {
            if (advice.Profile != null)
            {
                var alt = advice.Profile.Alternatives != null ? string.Join(" / ", advice.Profile.Alternatives) : "";
                return "Wiki 记录：首选 " + advice.Profile.Preferred
                    + (alt.Length > 0 ? "；备选 " + alt : "");
            }
            if (advice.WikiName != null)
            {
                return advice.WikiProxies != null && advice.WikiProxies.Length > 0
                    ? "Wiki 记录：" + advice.WikiName + " → " + string.Join(" / ", advice.WikiProxies)
                    : "Wiki 记录：" + advice.WikiName + "（未注明 DLL，可任选尝试）";
            }
            return "Wiki 记录：无此游戏记录";
        }
        static string OptiFact(WikiAdvice advice)
        {
            return advice.OptiDlss != null
                ? "Wiki 收录，支持 DLSS " + advice.OptiDlss + " / DLSS-FG " + advice.OptiFg
                : "Wiki 未收录此游戏";
        }

        // hero 卡说明行：左侧彩色小标签，右侧内容铺满剩余宽度并自动换行；
        // hero 卡固定深底（同上游），所以配色用固定低饱和色而不是主题资源。
        static void AddHeroFact(string tag, string text, int palette)
        {
            var back = new[]
            {
                System.Windows.Media.Color.FromRgb(0x2A, 0x3A, 0x4F),
                System.Windows.Media.Color.FromRgb(0x23, 0x40, 0x2F),
                System.Windows.Media.Color.FromRgb(0x46, 0x32, 0x1F),
            }[palette];
            var fore = new[]
            {
                System.Windows.Media.Color.FromRgb(0xA9, 0xC4, 0xE8),
                System.Windows.Media.Color.FromRgb(0x9B, 0xD8, 0xB4),
                System.Windows.Media.Color.FromRgb(0xE8, 0xC6, 0x9A),
            }[palette];
            var badgeBack = new System.Windows.Media.SolidColorBrush(back); badgeBack.Freeze();
            var badgeFore = new System.Windows.Media.SolidColorBrush(fore); badgeFore.Freeze();
            var ink = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0xDC, 0xE4, 0xEE)); ink.Freeze();

            var row = new System.Windows.Controls.DockPanel { Margin = new Thickness(0, 4, 0, 0) };
            var badge = new Border
            {
                Background = badgeBack,
                CornerRadius = new CornerRadius(4),
                Padding = new Thickness(7, 1.5, 7, 1.5),
                Margin = new Thickness(0, 0, 8, 0),
                VerticalAlignment = VerticalAlignment.Top,
                Child = new TextBlock { Text = tag, FontSize = 10, Foreground = badgeFore }
            };
            System.Windows.Controls.DockPanel.SetDock(badge, Dock.Left);
            row.Children.Add(badge);
            row.Children.Add(new TextBlock
            {
                Text = text,
                FontSize = 11.5,
                Foreground = ink,
                TextWrapping = TextWrapping.Wrap,
                VerticalAlignment = VerticalAlignment.Top
            });
            _heroFacts.Children.Add(row);
        }

        static string _hardwareDetails;

        /// <summary>底栏的硬件信息：与启动器同算法，从注册表挑物理独显，不声称游戏在用哪块。</summary>
        static void RefreshHardware()
        {
            if (_hardwareText == null) return;
            if (_hardwareDetails == null)
            {
                _hardwareDetails = ReadPhysicalAdapterName();
                if (string.IsNullOrWhiteSpace(_hardwareDetails)) _hardwareDetails = "GPU 信息不可用";
            }
            _hardwareText.Text = _hardwareDetails;
        }

        static readonly string[] NonPhysicalAdapterNames = { "virtual", "remote", "gameviewer", "uu", "parsec", "basic", "indirect", "rdp", "citrix", "vmware", "vnc", "displaylink" };

        static bool ContainsHardwareText(string value, string text)
        {
            return value.IndexOf(text, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        static int PhysicalAdapterRank(string name, string device)
        {
            foreach (var excluded in NonPhysicalAdapterNames)
                if (ContainsHardwareText(name, excluded)) return -1;
            if (!string.IsNullOrEmpty(device) && !device.StartsWith(@"PCI\", StringComparison.OrdinalIgnoreCase)) return -1;
            if (ContainsHardwareText(name, "NVIDIA")) return 0;
            if (ContainsHardwareText(name, "AMD") || ContainsHardwareText(name, "Radeon"))
            {
                bool integrated = ContainsHardwareText(name, "Vega") && !ContainsHardwareText(name, "RX Vega") || ContainsHardwareText(name, "Radeon(TM) Graphics") ||
                    ContainsHardwareText(name, "Radeon Graphics") || ContainsHardwareText(name, "Ryzen") ||
                    ContainsHardwareText(name, "Radeon 610M") || ContainsHardwareText(name, "Radeon 660M") ||
                    ContainsHardwareText(name, "Radeon 680M") || ContainsHardwareText(name, "Radeon 740M") ||
                    ContainsHardwareText(name, "Radeon 760M") || ContainsHardwareText(name, "Radeon 780M") ||
                    ContainsHardwareText(name, "Radeon 880M") || ContainsHardwareText(name, "Radeon 890M");
                return integrated ? 1 : 0;
            }
            if (ContainsHardwareText(name, "Intel")) return ContainsHardwareText(name, "Arc A") || ContainsHardwareText(name, "Arc B") ||
                ContainsHardwareText(name, "Arc(TM) A") || ContainsHardwareText(name, "Arc(TM) B") ? 0 : 2;
            return -1;
        }

        static string ReadPhysicalAdapterName()
        {
            string best = null;
            int bestRank = int.MaxValue;
            bool bestPrimary = false;
            string primary = "";
            try
            {
                using (var video = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"HARDWARE\DEVICEMAP\VIDEO"))
                    if (video != null) primary = Convert.ToString(video.GetValue(@"\Device\Video0"));
                const string machinePrefix = @"\Registry\Machine\";
                if (primary.StartsWith(machinePrefix, StringComparison.OrdinalIgnoreCase))
                    using (var mapped = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(primary.Substring(machinePrefix.Length)))
                        primary = mapped == null ? "" : Convert.ToString(mapped.GetValue("Driver"));
            }
            catch { }
            try
            {
                using (var root = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"))
                {
                    if (root != null) foreach (var name in root.GetSubKeyNames())
                    {
                        int index; if (name.Length != 4 || !int.TryParse(name, out index)) continue;
                        try
                        {
                            using (var key = root.OpenSubKey(name))
                            {
                                if (key == null) continue;
                                string gpu = Convert.ToString(key.GetValue("DriverDesc"));
                                if (string.IsNullOrWhiteSpace(gpu)) continue;
                                int rank = PhysicalAdapterRank(gpu, Convert.ToString(key.GetValue("MatchingDeviceId")));
                                if (rank < 0) continue;
                                bool isPrimary = primary.EndsWith(@"\" + name, StringComparison.OrdinalIgnoreCase);
                                if (best == null || rank < bestRank || (rank == bestRank && isPrimary && !bestPrimary))
                                {
                                    best = gpu; bestRank = rank; bestPrimary = isPrimary;
                                }
                            }
                        }
                        catch { }
                    }
                }
            }
            catch { }
            return best;
        }

        // ---------------------------------------------------------------- injection
        sealed class Loader
        {
            public string Name;
            public string Path;
        }

        static Loader CurrentInjection()
        {
            foreach (var n in Candidates)
            {
                var f = System.IO.Path.Combine(_dir, n + ".dll");
                if (File.Exists(f) && IsOurs(f)) return new Loader { Name = n, Path = f };
            }
            return null;
        }

        static List<string> Occupied()
        {
            var list = new List<string>();
            foreach (var n in Candidates)
            {
                var f = System.IO.Path.Combine(_dir, n + ".dll");
                if (File.Exists(f) && !IsOurs(f)) list.Add(n);
            }
            return list;
        }

        static bool IsOurs(string path)
        {
            try
            {
                var vi = FileVersionInfo.GetVersionInfo(path);
                return string.Equals(vi.ProductName, "OptiScaler", StringComparison.OrdinalIgnoreCase)
                    || string.Equals(vi.FileDescription, "OptiScaler", StringComparison.OrdinalIgnoreCase);
            }
            catch { return false; }
        }

        static void SwitchTo(string target)
        {
            var cur = CurrentInjection();
            if (cur == null) { PanelStatus("目录里没有找到 OptiScaler 的注入。"); return; }
            if (string.Equals(cur.Name, target, StringComparison.OrdinalIgnoreCase))
            {
                PanelStatus("已经是这个注入名了。");
                return;
            }
            var dest = System.IO.Path.Combine(_dir, target + ".dll");
            if (File.Exists(dest))
            {
                if (IsOurs(dest))
                {
                    var answer = DialogTheme.Show(_window, "旧的 " + target + ".dll 是我们之前的注入，删除它并改用当前这份？",
                        "确认", MessageBoxButton.YesNo, MessageBoxImage.Question);
                    if (answer != MessageBoxResult.Yes) return;
                    File.Delete(dest);
                }
                else
                {
                    PanelStatus(target + ".dll 被游戏或其它 mod 占用，不覆盖。");
                    return;
                }
            }
            try
            {
                File.Move(cur.Path, dest);
                PanelStatus("已切换到 " + target + ".dll，重启游戏生效。");
            }
            catch (Exception ex) { PanelStatus("切换失败：" + ex.Message); }
            Refresh();
        }

        // ---------------------------------------------------------------- theme
        // 与启动器一致：顶栏一个 ThemeToggle 按钮在 auto → light → dark 间循环切换。
        static void InitThemeToggle()
        {
            if (_themeToggle == null) return;
            _themeToggle.Click += (s, e) => SetTheme(_theme == "auto" ? "light" : _theme == "light" ? "dark" : "auto");
            RefreshThemeToggle();
        }

        static void SetTheme(string theme)
        {
            if (theme != "auto" && theme != "light" && theme != "dark") return;
            _theme = theme;
            LauncherTheme.Apply(theme);
            RefreshThemeToggle();
        }

        static void RefreshThemeToggle()
        {
            if (_themeToggle == null) return;
            _themeToggle.Content = _theme == "auto" ? "◐" : _theme == "light" ? "☀" : "☾";
            _themeToggle.ToolTip = "主题：" + ThemeName(_theme) + "（点击切换）";
        }

        static string ThemeName(string theme)
        {
            return theme == "light" ? "浅色" : theme == "dark" ? "深色" : "跟随系统";
        }

        static void OnSystemThemeChanged(object sender, Microsoft.Win32.UserPreferenceChangedEventArgs e)
        {
            if (_theme != "auto" || _window == null) return;
            _window.Dispatcher.BeginInvoke(new Action(() => LauncherTheme.Apply("auto")));
        }

        // ---------------------------------------------------------------- OptiPatcher
        const string OptiPatcherUrl = "https://github.com/optiscaler/OptiPatcher/releases/download/rolling/OptiPatcher.asi";

        static bool IsPeFile(string path)
        {
            try
            {
                var head = new byte[2];
                using (var fs = File.OpenRead(path))
                {
                    if (fs.Read(head, 0, 2) != 2) return false;
                }
                return head[0] == 0x4D && head[1] == 0x5A;
            }
            catch { return false; }
        }

        static void SetAsiPlugins(string value)
        {
            var ini = System.IO.Path.Combine(_dir, "OptiScaler.ini");
            if (!File.Exists(ini)) { CompatNote("目录里没有 OptiScaler.ini，无法写入 LoadAsiPlugins。"); return; }
            var text = File.ReadAllText(ini);
            if (System.Text.RegularExpressions.Regex.IsMatch(text, "(?m)^LoadAsiPlugins="))
                text = System.Text.RegularExpressions.Regex.Replace(text, "(?m)^LoadAsiPlugins=.*$", "LoadAsiPlugins=" + value);
            else if (System.Text.RegularExpressions.Regex.IsMatch(text, @"(?m)^\[Plugins\]"))
                text = System.Text.RegularExpressions.Regex.Replace(text, @"(?m)^(\[Plugins\][ \t]*)$", "$1\r\nLoadAsiPlugins=" + value);
            else
                text = text.TrimEnd() + "\r\n\r\n[Plugins]\r\nLoadAsiPlugins=" + value + "\r\n";
            File.WriteAllText(ini, text, new System.Text.UTF8Encoding(false));
        }

        static void InstallOptiPatcher()
        {
            // 命令行版流程：只有明确的 是/否 才生效；否 = 插件留在磁盘但不再加载（auto 读作 false）。
            var answer = DialogTheme.Show(_window, "是否安装 OptiPatcher（DLSS 伪装增强）？", "OptiPatcher",
                MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (answer != MessageBoxResult.Yes)
            {
                SetAsiPlugins("auto");
                CompatNote("已跳过 OptiPatcher（LoadAsiPlugins=auto，插件不会加载）。");
                return;
            }
            CompatNote("正在下载 OptiPatcher...");
            _window.Dispatcher.Invoke(() => { }, System.Windows.Threading.DispatcherPriority.Background);

            string downloaded = null;
            try
            {
                var tmp = System.IO.Path.Combine(System.IO.Path.GetTempPath(),
                    "OptiPatcher-" + Guid.NewGuid().ToString("N") + ".asi");
                var request = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(OptiPatcherUrl);
                request.Timeout = 30000;
                request.UserAgent = "OptiScalerPanel";
                using (var response = request.GetResponse())
                using (var input = response.GetResponseStream())
                using (var output = File.Create(tmp))
                {
                    input.CopyTo(output);
                }
                if (IsPeFile(tmp)) downloaded = tmp;
                else File.Delete(tmp);
            }
            catch { }

            var source = downloaded;
            if (source == null)
            {
                foreach (var candidate in new[]
                {
                    System.IO.Path.Combine(_dir, "plugins", "OptiPatcher.asi"),
                    System.IO.Path.Combine(_dir, "OptiScaler", "plugins", "OptiPatcher.asi")
                })
                {
                    if (File.Exists(candidate) && IsPeFile(candidate)) { source = candidate; break; }
                }
            }
            if (source == null)
            {
                CompatNote("OptiPatcher 下载失败，目录里也没有离线副本。");
                return;
            }

            try
            {
                var plugins = System.IO.Path.Combine(_dir, "plugins");
                if (!Directory.Exists(plugins)) Directory.CreateDirectory(plugins);
                File.Copy(source, System.IO.Path.Combine(plugins, "OptiPatcher.asi"), true);
                SetAsiPlugins("true");
                CompatNote("OptiPatcher 安装完成。");
            }
            catch (Exception ex) { CompatNote("安装失败：" + ex.Message); }
            finally
            {
                if (source == downloaded)
                {
                    try { File.Delete(downloaded); } catch { }
                }
            }
            Refresh();
        }

        static void OpenLog()
        {
            var log = System.IO.Path.Combine(_dir, "OptiScaler.log");
            if (File.Exists(log)) { try { Process.Start(new ProcessStartInfo(log) { UseShellExecute = true }); } catch { } }
            else CompatNote("还没有日志（进过一次游戏才会有 OptiScaler.log）。");
        }

        // ---------------------------------------------------------------- compat repair
        // 上游“兼容修复”：面板做只读检查（哈希对比），修复/恢复/保留交给包内 xess-compat.ps1
        // 的事务逻辑（备份 journal、原子替换、自动回滚）。布局、文案、对话框照抄上游。
        static readonly string[][] CompatGroups =
        {
            new[] { "sr", "XeSS 超分（DX12 / Vulkan）", "libxess.dll" },
            new[] { "dx11", "XeSS 超分（DX11）", "libxess_dx11.dll" },
            new[] { "fg", "XeSS 插帧 + XeLL（配套替换）", "libxess_fg.dll", "libxell.dll" },
            new[] { "fsr_fg", "AMD FidelityFX 帧生成（DX12）", "amd_fidelityfx_framegeneration_dx12.dll" },
            new[] { "fsr_upscaler", "AMD FidelityFX 超分（DX12）", "amd_fidelityfx_upscaler_dx12.dll" },
            new[] { "fsr_loader", "AMD FidelityFX 加载器（DX12）", "amd_fidelityfx_loader_dx12.dll" },
            new[] { "fsr_vk", "AMD FidelityFX 运行库（Vulkan）", "amd_fidelityfx_vk.dll" },
        };

        sealed class CompatFileState
        {
            public string Name, GameVersion, PackageVersion;
            public bool Same;
        }
        sealed class CompatGroupState
        {
            public string Id, Label;
            public bool Ready;
            public List<CompatFileState> Files = new List<CompatFileState>();
            public bool Different
            {
                get { foreach (var file in Files) if (!file.Same) return true; return false; }
            }
        }
        sealed class CompatReport
        {
            public List<CompatGroupState> Groups = new List<CompatGroupState>();
            public bool Active, ScriptReady;
            public List<string> RestoreFiles = new List<string>();
        }

        static string AppBase
        {
            get { return System.IO.Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location); }
        }

        static string Sha256File(string path)
        {
            try
            {
                if (!File.Exists(path)) return null;
                using (var stream = File.OpenRead(path))
                {
                    var sha = System.Security.Cryptography.SHA256.Create();
                    try { return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant(); }
                    finally { sha.Dispose(); }
                }
            }
            catch { return null; }
        }

        static string VersionOf(string path)
        {
            try { return FileVersionInfo.GetVersionInfo(path).FileVersion ?? ""; }
            catch { return ""; }
        }

        static CompatReport CheckCompat(string gameDir)
        {
            var report = new CompatReport();
            var packageDir = System.IO.Path.Combine(AppBase, "OptiScaler");
            report.ScriptReady = File.Exists(System.IO.Path.Combine(AppBase, "compat-repair.ps1"))
                && File.Exists(System.IO.Path.Combine(AppBase, "xess-compat.ps1"));
            foreach (var definition in CompatGroups)
            {
                var group = new CompatGroupState { Id = definition[0], Label = definition[1], Ready = true };
                for (var i = 2; i < definition.Length; i++)
                {
                    var name = definition[i];
                    var gamePath = System.IO.Path.Combine(gameDir, name);
                    var packagePath = System.IO.Path.Combine(packageDir, name);
                    var gameHash = Sha256File(gamePath);
                    var packageHash = Sha256File(packagePath);
                    if (packageHash == null) group.Ready = false;
                    group.Files.Add(new CompatFileState
                    {
                        Name = name,
                        GameVersion = File.Exists(gamePath) ? VersionOf(gamePath) : null,
                        PackageVersion = File.Exists(packagePath) ? VersionOf(packagePath) : null,
                        Same = gameHash != null && gameHash == packageHash
                    });
                }
                report.Groups.Add(group);
            }
            try
            {
                var journalPath = System.IO.Path.Combine(System.IO.Path.Combine(gameDir, "OptiScaler-compat-backup"), "active.json");
                if (File.Exists(journalPath))
                {
                    var journalText = File.ReadAllText(journalPath);
                    if (System.Text.RegularExpressions.Regex.IsMatch(journalText, @"""state""\s*:\s*""(pending|applied)"""))
                    {
                        report.Active = true;
                        foreach (System.Text.RegularExpressions.Match match in System.Text.RegularExpressions.Regex.Matches(journalText, @"""name""\s*:\s*""([^""]+)"""))
                            report.RestoreFiles.Add(match.Groups[1].Value);
                    }
                }
            }
            catch { }
            return report;
        }

        // 摘要文案与按钮可用性照抄上游 UpdateCompatibilitySummary。
        static void UpdateCompatUi(CompatReport report)
        {
            _compatReport = report;
            if (_compatSummary == null) return;
            var available = report.ScriptReady && !_panelBusy;
            // 与上游一致：摘要固定一句；面板仅在包不完整（脚本缺失）时说明原因。
            _compatSummary.Text = report.ScriptReady
                ? "启动、插帧或 XeSS 异常时可检查配套运行库；正常使用无需修复。"
                : "本目录缺少 compat-repair.ps1 / xess-compat.ps1，修复不可用（需完整拖入包）。";
            if (_compatRepairBtn != null) _compatRepairBtn.IsEnabled = available;
            if (_compatRestoreBtn != null) _compatRestoreBtn.IsEnabled = available && report.Active;
        }

        // 修复对话框：照抄上游 CreateCompatibilityDialog（非 restore 模式）。
        static void CompatRepair()
        {
            var report = _compatReport;
            if (report == null || !report.ScriptReady) return;
            var dialog = DialogTheme.Create(_window, "兼容修复与配套库替换", 650);
            var panel = new StackPanel { Margin = new Thickness(22) };
            Action<string> text = value => panel.Children.Add(new TextBlock { Text = value, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) });
            text(_dir);
            text("关闭游戏后，将自动把游戏目录中的配套运行库（XeSS、AMD FidelityFX 等）安全备份到 OptiScaler-compat-backup，并替换为本工具箱经过验证的最新配套组件。\n解决部分游戏中设置里无法开启 DLSS 帧生成 / FSR / XeSS，或因游戏自带 DLL 老旧冲突导致的异常。\n无改善可随时点击“恢复原文件”一键还原。");
            var selections = new Dictionary<string, System.Windows.Controls.CheckBox>();
            var proceed = new Button { Content = "备份并尝试修复", IsEnabled = false, MinWidth = 150, Margin = new Thickness(4) };
            DialogTheme.Primary(dialog, proceed);
            if (report.Active)
            {
                text("请先打开“恢复游戏原文件”，恢复上次修复，或保留当前文件并结束旧修复，再尝试其他组件。");
            }
            else
            {
                if (report.Groups.Count > 1)
                {
                    var selectAll = new Button
                    {
                        Content = "全选所有就绪组件",
                        HorizontalAlignment = HorizontalAlignment.Left,
                        Margin = new Thickness(0, 0, 0, 8),
                        Padding = new Thickness(8, 4, 8, 4)
                    };
                    selectAll.Click += delegate
                    {
                        var any = false;
                        foreach (var item in selections.Values)
                        {
                            if (!item.IsEnabled) continue;
                            item.IsChecked = true;
                            any = true;
                        }
                        if (any) proceed.IsEnabled = true;
                    };
                    panel.Children.Add(selectAll);
                }
                foreach (var group in report.Groups)
                {
                    var check = new System.Windows.Controls.CheckBox
                    {
                        Content = group.Label,
                        IsEnabled = group.Ready,
                        Margin = new Thickness(0, 6, 0, 6)
                    };
                    selections[group.Id] = check;
                    RoutedEventHandler changed = delegate
                    {
                        var any = false;
                        foreach (var item in selections.Values) if (item.IsChecked == true) any = true;
                        proceed.IsEnabled = any;
                    };
                    check.Checked += changed;
                    check.Unchecked += changed;
                    panel.Children.Add(check);
                    if (!group.Ready) text("安装包缺少有效配套文件，请重新解压完整包。");
                    foreach (var file in group.Files)
                    {
                        var gameVersion = file.GameVersion == null ? "无" : (file.GameVersion.Length == 0 ? "版本未知" : file.GameVersion);
                        var packageVersion = file.PackageVersion == null ? "无" : (file.PackageVersion.Length == 0 ? "版本未知" : file.PackageVersion);
                        text(file.Name + "\n游戏目录：" + gameVersion + "    包内：" + packageVersion
                            + (file.Same ? "（文件相同）" : "（文件不同或缺失）"));
                    }
                }
            }
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            buttons.Children.Add(new Button { Content = "取消", IsCancel = true, MinWidth = 90, Margin = new Thickness(4) });
            proceed.Click += delegate
            {
                var chosen = new List<string>();
                foreach (var item in selections) if (item.Value.IsChecked == true) chosen.Add(item.Key);
                dialog.Tag = chosen.ToArray();
                dialog.DialogResult = true;
            };
            buttons.Children.Add(proceed);
            panel.Children.Add(buttons);
            DialogTheme.SetContent(dialog, panel);
            if (dialog.ShowDialog() != true) return;
            var ids = string.Join(",", (string[])dialog.Tag);
            CompatNote("正在备份并修复配套库…");
            RunCompatScript("Repair", ids, delegate(bool ok, string message)
            {
                CompatNote(message);
                RefreshCompat();
            });
        }

        // 恢复对话框：照抄上游 restore 模式（含“保留当前文件并结束修复”分支）。
        static void CompatRestore()
        {
            var report = _compatReport;
            if (report == null || !report.ScriptReady || !report.Active) return;
            var dialog = DialogTheme.Create(_window, "恢复游戏原文件", 650);
            var panel = new StackPanel { Margin = new Thickness(22) };
            Action<string> text = value => panel.Children.Add(new TextBlock { Text = value, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 12) });
            text(_dir);
            text("关闭游戏后恢复上次修复前的文件，并移除修复时新增的文件。游戏更新过的文件不会被覆盖。若游戏已更新或希望保留现状，可选“保留当前文件并结束修复”：不恢复任何 DLL，保留全部备份，并允许再次修复。");
            if (report.RestoreFiles.Count > 0) text(string.Join("\n", report.RestoreFiles.ToArray()));
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
            buttons.Children.Add(new Button { Content = "取消", IsCancel = true, MinWidth = 90, Margin = new Thickness(4) });
            var keep = new Button { Content = "保留当前文件并结束修复", Margin = new Thickness(4) };
            keep.Click += delegate { dialog.Uid = "keep"; dialog.DialogResult = true; };
            buttons.Children.Add(keep);
            var restore = new Button { Content = "恢复原文件", IsDefault = true, MinWidth = 150, Margin = new Thickness(4) };
            DialogTheme.Primary(dialog, restore);
            restore.Click += delegate { dialog.DialogResult = true; };
            buttons.Children.Add(restore);
            panel.Children.Add(buttons);
            DialogTheme.SetContent(dialog, panel);
            if (dialog.ShowDialog() != true) return;
            var keepChosen = dialog.Uid == "keep";
            CompatNote(keepChosen ? "正在结束修复记录…" : "正在恢复原文件…");
            RunCompatScript(keepChosen ? "Keep" : "Restore", null, delegate(bool ok, string message)
            {
                CompatNote(message);
                RefreshCompat();
            });
        }

        // 帮助对话框：照抄上游 CreateCompatibilityHelpDialog 的 Q&A。
        static void CompatHelp()
        {
            var report = _compatReport;
            var dialog = DialogTheme.Create(_window, "关于兼容修复与配套库", 620);
            var panel = new StackPanel { Margin = new Thickness(22) };
            var statusBox = new Border
            {
                Background = LauncherTheme.Brush("ThemeSubtle"),
                BorderBrush = LauncherTheme.Brush("ThemeBorder"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(6),
                Padding = new Thickness(14, 10, 14, 10),
                Margin = new Thickness(0, 0, 0, 16)
            };
            var statusStack = new StackPanel();
            statusStack.Children.Add(new TextBlock
            {
                Text = "当前游戏配套文件状态",
                Foreground = LauncherTheme.Brush("ThemeSuccess"),
                FontWeight = FontWeights.SemiBold,
                FontSize = 12,
                Margin = new Thickness(0, 0, 0, 4)
            });
            statusStack.Children.Add(new TextBlock
            {
                Text = report != null && _compatSummary != null && _compatSummary.Text.Length > 0 ? _compatSummary.Text
                    : "选择游戏文件夹后自动检查配套运行库文件。",
                TextWrapping = TextWrapping.Wrap,
                FontSize = 12
            });
            statusBox.Child = statusStack;
            panel.Children.Add(statusBox);
            panel.Children.Add(new TextBlock
            {
                Text =
                    "【兼容修复常见问题 Q&A】\n\n" +
                    "1. 什么时候需要使用兼容修复？\n" +
                    "   • 游戏设置中的 DLSS 帧生成 / XeSS / FSR 选项灰显、无法开启或提示硬件不支持（部分游戏自带了较旧的配套 DLL）。\n" +
                    "   • 开启插帧后游戏闪退、报错，或插帧倍率受限。\n" +
                    "   • 游戏更新后自带的文件与 OptiScaler 补丁发生版本冲突。\n\n" +
                    "2. 兼容修复做了什么？\n" +
                    "   • 自动备份：将游戏目录中原有的配套 DLL（libxess.dll、amd_fidelityfx_*.dll 等）完整备份到游戏目录下的 OptiScaler-compat-backup 文件夹中。\n" +
                    "   • 配套替换：将本工具箱经过实测验证的配套运行库一键部署到游戏目录，替换厂商未更新的老旧文件，使补丁与游戏运行库完美协同。\n\n" +
                    "3. 如何还原或应对游戏更新？\n" +
                    "   • 若修复后没有改善或出现异常，随时点击“恢复原文件”即可一键无损还原。\n" +
                    "   • 游戏更新后若正常运行，可在还原窗口中选择“保留当前文件并结束修复”，安全清理旧记录。",
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 0, 0, 20)
            });
            var ok = new Button { Content = "确定", IsDefault = true, MinWidth = 90, Margin = new Thickness(4), HorizontalAlignment = HorizontalAlignment.Right };
            DialogTheme.Primary(dialog, ok);
            ok.Click += delegate { dialog.DialogResult = true; };
            panel.Children.Add(ok);
            DialogTheme.SetContent(dialog, panel);
            dialog.ShowDialog();
        }

        static void RunCompatScript(string action, string groupsCsv, Action<bool, string> done)
        {
            var script = System.IO.Path.Combine(AppBase, "compat-repair.ps1");
            if (_heroProgress != null) _heroProgress.IsIndeterminate = true;
            if (!File.Exists(script))
            {
                if (_heroProgress != null) _heroProgress.IsIndeterminate = false;
                done(false, "目录里没有 compat-repair.ps1，无法执行。");
                return;
            }
            var dir = _dir;
            System.Threading.Tasks.Task.Run(delegate
            {
                var output = "";
                var code = 1;
                try
                {
                    var info = new ProcessStartInfo
                    {
                        FileName = "powershell.exe",
                        Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + script + "\" -Action " + action
                            + " -GameDir \"" + dir + "\""
                            + (string.IsNullOrEmpty(groupsCsv) ? "" : " -Group " + groupsCsv),
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        StandardOutputEncoding = System.Text.Encoding.UTF8,
                        StandardErrorEncoding = System.Text.Encoding.UTF8
                    };
                    using (var process = Process.Start(info))
                    {
                        output = process.StandardOutput.ReadToEnd().Trim();
                        process.StandardError.ReadToEnd();
                        process.WaitForExit();
                        code = process.ExitCode;
                    }
                }
                catch (Exception ex) { output = ex.Message; }
                var message = output.StartsWith("OK:", StringComparison.Ordinal) ? output.Substring(3).Trim()
                            : output.StartsWith("ERROR:", StringComparison.Ordinal) ? output.Substring(6).Trim()
                            : output;
                var ok = code == 0;
                _window.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (_heroProgress != null) _heroProgress.IsIndeterminate = false;
                    done(ok, message);
                }));
            });
        }

        static void RefreshCompat()
        {
            var dir = _dir;
            System.Threading.Tasks.Task.Run(delegate
            {
                var report = CheckCompat(dir);
                _window.Dispatcher.BeginInvoke(new Action(delegate
                {
                    if (!string.Equals(_dir, dir, StringComparison.OrdinalIgnoreCase)) return;
                    UpdateCompatUi(report);
                }));
            });
        }

        // ---------------------------------------------------------------- ini profiles（照搬 MainController.Profiles.cs）
        // 与启动器相同的设置目录：预设库（ini-profiles）和按游戏的选择记录（ini-profiles.json）
        // 都与启动器共享，两个程序看到同一份状态。
        static string SettingsDir()
        {
            return System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OptScalerNR", "Launcher");
        }

        static void InitProfiles()
        {
            if (_iniInitialized) return;
            _iniInitialized = true;
            _iniProfileCombo = _window.FindName("IniProfileCombo") as ComboBox;
            _iniSearchBox = _window.FindName("IniSearchBox") as TextBox;
            _iniProfileStatus = _window.FindName("IniProfileStatus") as TextBlock;
            _iniSaveButton = _window.FindName("IniSaveButton") as Button;
            _iniQuickSaveButton = _window.FindName("IniQuickSaveButton") as Button;
            _iniImportButton = _window.FindName("IniImportButton") as Button;
            _iniRenameButton = _window.FindName("IniRenameButton") as Button;
            _iniDeleteButton = _window.FindName("IniDeleteButton") as Button;
            _iniApplyButton = _window.FindName("IniApplyButton") as Button;
            _iniFolderButton = _window.FindName("IniFolderButton") as Button;
            InitShareCode();
            try { _iniProfiles = new IniProfiles(SettingsDir()); }
            catch (Exception ex) { IniFailure(ex); }
            if (_iniProfileCombo != null) _iniProfileCombo.SelectionChanged += delegate { IniSelectionChanged(); };
            if (_iniSearchBox != null) _iniSearchBox.TextChanged += delegate { if (!_iniUpdating) PopulateIniProfiles(); };
            if (_iniSaveButton != null) _iniSaveButton.Click += delegate { PromptSaveIniProfile(); };
            if (_iniQuickSaveButton != null) _iniQuickSaveButton.Click += delegate {
                var game = CaptureIniGame();
                if (!CanUseIniGame(game)) return;
                SaveIniProfileCore(game, game.Name + " 保存配置");
            };
            if (_iniImportButton != null) _iniImportButton.Click += delegate { PromptImportIniProfile(); };
            if (_iniRenameButton != null) _iniRenameButton.Click += delegate { PromptRenameIniProfile(); };
            if (_iniDeleteButton != null) _iniDeleteButton.Click += delegate { PromptDeleteIniProfile(); };
            if (_iniApplyButton != null) _iniApplyButton.Click += delegate { ApplyIniProfile(); };
            if (_iniFolderButton != null) _iniFolderButton.Click += delegate {
                if (IniBusy() || _iniProfiles == null) return;
                try {
                    Directory.CreateDirectory(_iniProfiles.RootDirectory);
                    Process.Start(new ProcessStartInfo { FileName = _iniProfiles.RootDirectory, UseShellExecute = true });
                } catch (Exception ex) { IniFailure(ex); }
            };
            RefreshProfilesLanguage();
            SelectGameProfiles();
        }

        static void RefreshProfilesLanguage()
        {
            SetLabelText("IniHeading", "OptiScaler.ini 共享配置（整文件）");
            SetLabelText("IniSelectHint", "选择配置后点击“应用所选配置”。");
            if (_iniSaveButton != null) _iniSaveButton.Content = "保存…";
            if (_iniQuickSaveButton != null) _iniQuickSaveButton.Content = "快速保存";
            if (_iniImportButton != null) _iniImportButton.Content = "导入…";
            if (_iniRenameButton != null) _iniRenameButton.Content = "重命名…";
            if (_iniDeleteButton != null) _iniDeleteButton.Content = "删除";
            if (_iniApplyButton != null) _iniApplyButton.Content = "应用所选配置";
            if (_iniFolderButton != null) _iniFolderButton.Content = "配置文件夹";
            if (_iniSearchBox != null) _iniSearchBox.ToolTip = "搜索共享配置";
            RefreshShareCodeLanguage();
            PopulateIniProfiles();
            RenderIniStatus();
            RefreshProfileActions();
        }

        static void SetLabelText(string name, string text)
        {
            var block = _window.FindName(name) as TextBlock;
            if (block != null) block.Text = text;
        }

        // Called synchronously immediately after the panel's game directory is changed (incl. drag-drop).
        static void SelectGameProfiles()
        {
            _iniSelectionGeneration++;
            _iniUpdating = true;
            try
            {
                _iniSelectedProfile = "";
                _iniPluginsEnabled = false;
                _iniProfileNames = new string[0];
                _iniStatus = "";
                _iniStatusDetail = "";
                if (_iniProfileCombo != null) { _iniProfileCombo.SelectedIndex = -1; _iniProfileCombo.Items.Clear(); }
                if (_iniSearchBox != null) _iniSearchBox.Text = "";
                if (_iniProfiles != null)
                {
                    _iniProfileNames = _iniProfiles.List();
                    var game = CaptureIniGame();
                    if (game != null)
                    {
                        var saved = _iniProfiles.GetSelection(game.Key);
                        _iniSelectedProfile = FindIniName(saved);
                        _iniPluginsEnabled = _iniProfiles.GetPluginsForGame(game.Key, game.Directory);
                    }
                }
            }
            catch (Exception ex) { IniFailure(ex); }
            finally { _iniUpdating = false; }
            PopulateIniProfiles();
            RenderIniStatus();
            RefreshProfileActions();
        }

        static void RefreshProfileActions()
        {
            if (!_iniInitialized) return;
            var available = _iniProfiles != null && !IniBusy();
            var game = CaptureIniGame();
            var hasGame = available && game != null;
            var hasIni = hasGame && File.Exists(Path.Combine(game.Directory, "OptiScaler.ini"));
            RefreshShareCode(game != null && !IniBusy() && File.Exists(Path.Combine(game.Directory, "OptiScaler.ini")));
            var selected = hasGame && !string.IsNullOrEmpty(_iniSelectedProfile);
            if (_iniProfileCombo != null) _iniProfileCombo.IsEnabled = hasGame;
            if (_iniSearchBox != null) _iniSearchBox.IsEnabled = available;
            if (_iniSaveButton != null) _iniSaveButton.IsEnabled = hasIni;
            if (_iniQuickSaveButton != null) _iniQuickSaveButton.IsEnabled = hasIni;
            if (_iniImportButton != null) _iniImportButton.IsEnabled = hasGame;
            if (_iniRenameButton != null) _iniRenameButton.IsEnabled = selected;
            if (_iniDeleteButton != null) _iniDeleteButton.IsEnabled = selected;
            if (_iniApplyButton != null) _iniApplyButton.IsEnabled = hasIni;
            if (_iniFolderButton != null) _iniFolderButton.IsEnabled = available;
        }

        static bool IniBusy() { return _panelBusy; }

        static IniGameIdentity CaptureIniGame()
        {
            if (string.IsNullOrEmpty(_dir)) return null;
            try
            {
                var directory = Path.GetFullPath(_dir);
                var exe = GameExe();
                return new IniGameIdentity {
                    Key = "path:" + directory.ToLowerInvariant(),
                    Directory = directory,
                    Name = exe != null ? System.IO.Path.GetFileNameWithoutExtension(exe.Name)
                                       : System.IO.Path.GetFileName(directory.TrimEnd('\\', '/')),
                    Generation = _iniSelectionGeneration };
            }
            catch { return null; }
        }
        static bool CanUseIniGame(IniGameIdentity captured)
        {
            if (IniBusy()) { SetIniStatus("busy", ""); return false; }
            var current = CaptureIniGame();
            if (_iniProfiles == null) { SetIniStatus("metadata", ""); return false; }
            if (captured == null || current == null) { SetIniStatus("game", ""); return false; }
            if (captured.Generation != current.Generation || !string.Equals(captured.Key, current.Key, StringComparison.OrdinalIgnoreCase) || !SamePath(captured.Directory, current.Directory))
            { SetIniStatus("changed", ""); return false; }
            return true;
        }
        static bool SamePath(string a, string b)
        {
            return string.Equals(Path.GetFullPath(a), Path.GetFullPath(b), StringComparison.OrdinalIgnoreCase);
        }
        static string FindIniName(string name)
        {
            foreach (var item in _iniProfileNames) if (string.Equals(item, name, StringComparison.OrdinalIgnoreCase)) return item;
            return "";
        }
        static void PopulateIniProfiles()
        {
            if (_iniProfileCombo == null) return;
            _iniUpdating = true;
            try
            {
                var query = _iniSearchBox == null ? "" : _iniSearchBox.Text.Trim();
                _iniProfileCombo.Items.Clear();
                var current = new ComboBoxItem { Content = "当前游戏 INI", Tag = "" };
                _iniProfileCombo.Items.Add(current);
                ComboBoxItem chosen = string.IsNullOrEmpty(_iniSelectedProfile) ? current : null;
                foreach (var name in _iniProfileNames)
                {
                    var isSelected = string.Equals(name, _iniSelectedProfile, StringComparison.OrdinalIgnoreCase);
                    // Keep the active selection visible while filtering; Apply must never have a hidden target.
                    if (!isSelected && query.Length > 0 && name.IndexOf(query, StringComparison.OrdinalIgnoreCase) < 0) continue;
                    var item = new ComboBoxItem { Content = name, Tag = name };
                    _iniProfileCombo.Items.Add(item);
                    if (isSelected) chosen = item;
                }
                _iniProfileCombo.SelectedItem = chosen ?? current;
            }
            finally { _iniUpdating = false; }
        }
        static void IniSelectionChanged()
        {
            if (_iniUpdating || _iniProfileCombo == null) return;
            var game = CaptureIniGame();
            var selected = _iniProfileCombo.SelectedItem as ComboBoxItem;
            if (selected == null) return;
            if (!CanUseIniGame(game)) { PopulateIniProfiles(); return; }
            try
            {
                var name = selected.Tag as string ?? "";
                _iniProfiles.SetSelection(game.Key, name);
                _iniSelectedProfile = name;
                SetIniStatus("pending", "");
            }
            catch (Exception ex) { PopulateIniProfiles(); IniFailure(ex); }
            RefreshProfileActions();
        }

        static string PromptIniName(string title, string initial)
        {
            var dialog = DialogTheme.Create(_window, title, 450);
            var panel = new StackPanel { Margin = new Thickness(22) };
            panel.Children.Add(new TextBlock { Text = "配置名称", Margin = new Thickness(0, 0, 0, 8) });
            var name = new TextBox { Text = initial, MaxLength = 80 };
            panel.Children.Add(name);
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
            var cancel = new Button { Content = "取消", IsCancel = true, MinWidth = 85, Margin = new Thickness(4) };
            var accept = new Button { Content = "确定", IsDefault = true, MinWidth = 85, Margin = new Thickness(4) };
            accept.Click += delegate { if (!string.IsNullOrWhiteSpace(name.Text)) dialog.DialogResult = true; };
            DialogTheme.Primary(dialog, accept);
            buttons.Children.Add(cancel); buttons.Children.Add(accept); panel.Children.Add(buttons);
            DialogTheme.SetContent(dialog, panel);
            dialog.Loaded += delegate { name.Focus(); name.SelectAll(); };
            return dialog.ShowDialog() == true ? name.Text : null;
        }
        static void PromptSaveIniProfile()
        {
            var game = CaptureIniGame();
            if (!CanUseIniGame(game)) return;
            var name = PromptIniName("保存共享配置", game.Name + " 保存配置");
            if (name != null) SaveIniProfileCore(game, name);
        }
        static void PromptImportIniProfile()
        {
            var game = CaptureIniGame();
            if (!CanUseIniGame(game)) return;
            var picker = new Microsoft.Win32.OpenFileDialog { Title = "导入 OptiScaler.ini 配置", Filter = "INI (*.ini)|*.ini", CheckFileExists = true, RestoreDirectory = true };
            if (picker.ShowDialog(_window) != true || !CanUseIniGame(game)) return;
            var source = picker.FileName;
            var name = PromptIniName("导入共享配置", System.IO.Path.GetFileNameWithoutExtension(source));
            if (name != null) ImportIniProfileCore(game, source, name);
        }
        static void PromptRenameIniProfile()
        {
            var game = CaptureIniGame();
            var oldName = _iniSelectedProfile;
            if (!CanUseIniGame(game) || string.IsNullOrEmpty(oldName)) return;
            var name = PromptIniName("重命名共享配置", oldName);
            if (name != null) RenameIniProfileCore(game, oldName, name);
        }
        static void PromptDeleteIniProfile()
        {
            var game = CaptureIniGame();
            var name = _iniSelectedProfile;
            if (!CanUseIniGame(game) || string.IsNullOrEmpty(name)) return;
            if (DialogTheme.Show(_window, "删除共享配置“" + name + "”？所有游戏的该配置选择都会清除，游戏 INI 不会改变。",
                "删除配置", MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes)
                DeleteIniProfileCore(game, name);
        }

        static bool SaveIniProfileCore(IniGameIdentity game, string name)
        {
            if (!CanUseIniGame(game)) return false;
            try {
                var saved = _iniProfiles.Save(Path.Combine(game.Directory, "OptiScaler.ini"), name);
                _iniProfiles.SetSelection(game.Key, saved);
                ReloadIniProfiles(saved);
                SetIniStatus("saved", saved);
                return true;
            } catch (Exception ex) { IniFailure(ex); return false; }
        }
        static bool ImportIniProfileCore(IniGameIdentity game, string source, string name)
        {
            if (!CanUseIniGame(game)) return false;
            try {
                var imported = _iniProfiles.Import(source, name);
                _iniProfiles.SetSelection(game.Key, imported);
                ReloadIniProfiles(imported);
                SetIniStatus("imported", imported);
                return true;
            } catch (Exception ex) { IniFailure(ex); return false; }
        }
        static bool RenameIniProfileCore(IniGameIdentity game, string oldName, string newName)
        {
            if (!CanUseIniGame(game) || string.IsNullOrEmpty(oldName)) return false;
            try {
                _iniProfiles.Rename(oldName, newName);
                ReloadIniProfiles(_iniProfiles.GetSelection(game.Key));
                SetIniStatus("renamed", IniProfiles.CleanName(newName));
                return true;
            } catch (Exception ex) { IniFailure(ex); return false; }
        }
        static bool DeleteIniProfileCore(IniGameIdentity game, string name)
        {
            if (!CanUseIniGame(game) || string.IsNullOrEmpty(name)) return false;
            try {
                _iniProfiles.Delete(name);
                ReloadIniProfiles(_iniProfiles.GetSelection(game.Key));
                SetIniStatus("deleted", name);
                return true;
            } catch (Exception ex) { IniFailure(ex); return false; }
        }
        static bool ApplyIniProfile()
        {
            var game = CaptureIniGame();
            var name = _iniSelectedProfile;
            var plugins = _iniPluginsEnabled;
            if (!CanUseIniGame(game)) return false;
            var locked = false;
            var busy = false;
            try
            {
                if (!Directory.Exists(game.Directory)) throw new IniProfileException("game");
                locked = TryLockTarget(game.Directory);
                if (!locked) { SetIniStatus("locked", ""); return false; }
                SetBusy(true);
                busy = true;
                RefreshProfileActions();
                var backup = _iniProfiles.Apply(game.Directory, name, plugins);
                SetIniStatus("applied", Path.GetFileName(backup));
                return true;
            }
            catch (Exception ex) { IniFailure(ex); return false; }
            finally
            {
                if (locked) ReleaseLock();
                if (busy) SetBusy(false);
                RefreshProfileActions();
            }
        }
        static void ReloadIniProfiles(string selected)
        {
            _iniProfileNames = _iniProfiles.List();
            _iniSelectedProfile = FindIniName(selected);
            PopulateIniProfiles();
            RefreshProfileActions();
        }
        static void IniFailure(Exception error)
        {
            var specific = error as IniProfileException;
            SetIniStatus(specific == null ? "io" : specific.Code, "");
        }
        static void SetIniStatus(string status, string detail)
        {
            _iniStatus = status;
            _iniStatusDetail = detail ?? "";
            RenderIniStatus();
        }
        // 面板自己的提示（注入切换、OptiPatcher 安装、日志）也走这条状态行。
        static void PanelStatus(string text) { SetIniStatus("panel", text); }
        static void RenderIniStatus()
        {
            if (_iniProfileStatus == null) return;
            string text;
            switch (_iniStatus)
            {
                case "busy": text = "操作正在进行，请稍候。"; break;
                case "locked": text = "游戏文件夹已被另一个启动器锁定。"; break;
                case "changed": text = "游戏选择已改变，操作已取消。"; break;
                case "game": text = "请先选择游戏文件夹。"; break;
                case "metadata": text = "无法读取配置记录，请检查配置记录文件。"; break;
                case "noini": text = "游戏没有 OptiScaler.ini，请先安装。"; break;
                case "invalid": text = "不是有效的 OptiScaler.ini。"; break;
                case "extension": text = "只能导入 .ini 文件。"; break;
                case "source": text = "导入文件不存在。"; break;
                case "missing": text = "配置已不存在，请重新选择游戏以刷新列表。"; break;
                case "name": text = "请输入有效的配置名称。"; break;
                case "exists": text = "已有同名配置，请使用其他名称。"; break;
                case "pending": text = "已保存选择；点击“应用”后修改游戏 INI。"; break;
                case "saved": text = "已保存共享配置：" + _iniStatusDetail; break;
                case "imported": text = "已导入：" + _iniStatusDetail + "。点击“应用”切换。"; break;
                case "renamed": text = "已重命名：" + _iniStatusDetail; break;
                case "deleted": text = "已删除共享配置：" + _iniStatusDetail; break;
                case "applied": text = "已应用，请重启游戏。原 INI 备份：" + _iniStatusDetail; break;
                case "share-imported": text = "已换上同款画面，重启游戏后生效"; break;
                case "share-error": text = _iniStatusDetail; break;
                case "panel": text = _iniStatusDetail; break;
                case "io": text = "配置操作失败，请检查文件权限与可用空间。"; break;
                default: text = _iniProfiles == null ? "配置库不可用。"
                    : CaptureIniGame() == null ? "选择游戏以使用共享配置。"
                    : _iniProfileNames.Length == 0 ? "暂无共享配置。可保存当前游戏 INI 或导入。"
                    : "配置对所有游戏可见；选择与插件开关按游戏保存。"; break;
            }
            _iniProfileStatus.Text = text;
        }

        // ---------------------------------------------------------------- target lock（照搬 MainWindow.TryLockTarget）
        // 与启动器同名的全局互斥：面板和启动器写同一个游戏目录时互斥。
        static bool TryLockTarget(string dir)
        {
            ReleaseLock();
            var hash = Convert.ToBase64String(System.Security.Cryptography.SHA256.Create()
                .ComputeHash(System.Text.Encoding.UTF8.GetBytes((dir ?? "").ToLowerInvariant())))
                .Replace('+', '-').Replace('/', '_').TrimEnd('=');
            var name = @"Global\OptScalerNR.Launcher." + hash;
            bool created;
            _targetMutex = new System.Threading.Mutex(true, name, out created);
            if (created) return true;
            _targetMutex.Dispose();
            _targetMutex = null;
            return false;
        }

        static void ReleaseLock()
        {
            if (_targetMutex != null) {
                try { _targetMutex.ReleaseMutex(); } catch { }
                _targetMutex.Dispose();
                _targetMutex = null;
            }
        }

        static void SetBusy(bool busy)
        {
            _panelBusy = busy;
            RefreshProfileActions();
        }

        // ---------------------------------------------------------------- share codes（照搬 MainController.ShareCode.cs）
        static System.Windows.Controls.Button _styleOutButton;
        static System.Windows.Controls.Button _styleInButton;

        static void InitShareCode()
        {
            _styleOutButton = _window.FindName("StyleOutButton") as System.Windows.Controls.Button;
            if (_styleOutButton != null) _styleOutButton.Click += delegate { ShowShareCode(false); };
            _styleInButton = _window.FindName("StyleInButton") as System.Windows.Controls.Button;
            if (_styleInButton != null) _styleInButton.Click += delegate { ShowShareCode(true); };
        }

        static void RefreshShareCode(bool enabled)
        {
            RefreshShareCodeLanguage();
            if (_styleOutButton != null) _styleOutButton.IsEnabled = enabled;
            if (_styleInButton != null) _styleInButton.IsEnabled = enabled;
        }

        static void RefreshShareCodeLanguage()
        {
            var title = _window.FindName("StyleShareTitle") as TextBlock;
            var sub = _window.FindName("StyleShareSub") as TextBlock;
            if (title != null) title.Text = "画面风格分享";
            if (sub != null)
                sub.Text = "把你调好的画面风格变成一段分享码发给朋友，或粘贴别人的码换上同款画面";
            if (_styleOutButton != null)
            {
                _styleOutButton.Content = "晒出我的画面";
                _styleOutButton.ToolTip = "生成你当前画面风格的分享码（默认打开发出）";
            }
            if (_styleInButton != null)
            {
                _styleInButton.Content = "换上同款画面";
                _styleInButton.ToolTip = "粘贴别人的分享码，换上同款画面（默认打开导入）";
            }
        }

        // MZ code inside arbitrary pasted text (share text with a pitch line, chat quotes, anything)
        static readonly System.Text.RegularExpressions.Regex CodeInText = new System.Text.RegularExpressions.Regex(@"MZ[1-3]:[^;\r\n]*;[0-9A-Fa-f]{4}", System.Text.RegularExpressions.RegexOptions.Compiled);
        static string ExtractCode(string text)
        {
            if (text == null) return null;
            var match = CodeInText.Match(text);
            return match.Success ? match.Value : null;
        }

        static string ShareError(Exception error)
        {
            var code = error as MochizukiShareCode.CodeException;
            if (code == null) return "操作没成功，再试一次或检查文件权限。";
            switch (code.Reason) {
                case "prefix": return "没认出画面分享码。确认复制了完整的分享内容（里面会有一段 MZ 开头的字符）。";
                case "crc": return "内容好像没复制全，少了一截。把整段分享内容重新复制一遍试试？";
                case "index": return "这段分享码来自更新的版本，更新启动器后再试。";
                case "range": return "这段分享码的内容有问题，可能没复制全。";
                case "duplicate": return "这段分享码的内容有问题，可能没复制全。";
                case "encoding": return "游戏设置文件不是常见的编码，无法读取。";
                case "value": return "这段分享码的内容有问题，可能没复制全。";
                default: return "没认出画面分享码。确认复制了完整的分享内容。";
            }
        }

        static void ShowShareCode(bool import)
        {
            var game = CaptureIniGame();
            if (!CanUseIniGame(game)) return;
            string path = Path.Combine(game.Directory, "OptiScaler.ini");
            var exeInfo = GameExe();
            string executable = exeInfo != null ? exeInfo.FullName : null;
            if (!File.Exists(path)) { SetIniStatus("noini", ""); return; }
            try {
                var dialog = DialogTheme.Create(_window, "画面风格分享", 620);
                var panel = new StackPanel { Margin = new Thickness(22) };
                var modeRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 10) };
                var exportRadio = new RadioButton { Content = "导出（发出我的画面）", GroupName = "ShareCodeMode", Margin = new Thickness(0, 0, 14, 0) };
                var importRadio = new RadioButton { Content = "导入（换上别人的画面）", GroupName = "ShareCodeMode" };
                modeRow.Children.Add(exportRadio); modeRow.Children.Add(importRadio);
                panel.Children.Add(modeRow);
                var hint = new TextBlock { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 8) };
                panel.Children.Add(hint);
                var input = new TextBox
                {
                    TextWrapping = TextWrapping.Wrap, Height = 130, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                    Background = TryFindResourceString("ThemeSurface"),
                    Foreground = TryFindResourceString("ThemeInk"),
                    BorderBrush = TryFindResourceString("ThemeBorder"),
                    Padding = new Thickness(6, 4, 6, 4)
                };
                panel.Children.Add(input);
                var includeGame = new CheckBox { Content = "附带游戏名（朋友导入时会显示这段画面来自哪个游戏）", IsChecked = true, Margin = new Thickness(0, 10, 0, 0) };
                panel.Children.Add(includeGame);
                var sourceRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
                var pickIni = new Button { Content = "从 INI 文件读取…", MinWidth = 110, Margin = new Thickness(0, 0, 8, 0), Padding = new Thickness(10, 3, 10, 3) };
                var sourceHint = new TextBlock { Foreground = TryFindResourceString("ThemeMuted"), FontSize = 11, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 330 };
                sourceHint.Text = "默认：当前游戏的 OptiScaler.ini";
                sourceRow.Children.Add(pickIni); sourceRow.Children.Add(sourceHint);
                panel.Children.Add(sourceRow);
                var noteHint = new TextBlock { Text = "备注（可选，随分享码一起发过去）：", Foreground = TryFindResourceString("ThemeMuted"), FontSize = 11, Margin = new Thickness(0, 8, 0, 2) };
                var noteBox = new TextBox { Height = 26, Padding = new Thickness(6, 3, 6, 3), Background = TryFindResourceString("ThemeSurface"), Foreground = TryFindResourceString("ThemeInk"), BorderBrush = TryFindResourceString("ThemeBorder") };
                var notePlaceholder = "给这段画面起个名字，比如：夜之城 冷蓝电影感";
                noteBox.Text = notePlaceholder; noteBox.Foreground = TryFindResourceString("ThemeMuted");
                bool noteDirty = false;
                noteBox.GotFocus += delegate { if (!noteDirty) { noteBox.Text = ""; noteBox.Foreground = TryFindResourceString("ThemeInk"); } };
                noteBox.LostFocus += delegate { if (!noteDirty && noteBox.Text.Length == 0) { noteBox.Text = notePlaceholder; noteBox.Foreground = TryFindResourceString("ThemeMuted"); } };
                panel.Children.Add(noteHint); panel.Children.Add(noteBox);
                var summary = new TextBlock { TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 10) };
                panel.Children.Add(summary);
                byte[] exportedIni = null;
                string exportSourcePath = path;
                bool isExport = !import;
                Action renderMode = null;
                RoutedEventHandler switchMode = delegate {
                    var nowExport = exportRadio.IsChecked == true;
                    if (nowExport == isExport) return;
                    isExport = nowExport;
                    if (renderMode != null) renderMode();
                };
                exportRadio.Checked += switchMode; importRadio.Checked += switchMode;
                var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
                var close = new Button { Content = "关闭", MinWidth = 75, Margin = new Thickness(6) };
                close.Click += delegate { dialog.Close(); };
                var action = new Button { MinWidth = 100, Margin = new Thickness(6) };
                var apply = new Button { MinWidth = 110, Margin = new Thickness(6), IsEnabled = false, Visibility = Visibility.Collapsed };
                string validated = null, validatedGame = "";
                renderMode = delegate {
                    action.Content = isExport ? "复制分享码" : "解析";
                    apply.Content = "立即换上这套画面";
                    apply.Visibility = isExport ? Visibility.Collapsed : Visibility.Visible;
                    apply.IsEnabled = false; validated = null; validatedGame = "";
                    includeGame.Visibility = isExport ? Visibility.Visible : Visibility.Collapsed;
                    sourceRow.Visibility = noteHint.Visibility = noteBox.Visibility =
                        isExport ? Visibility.Visible : Visibility.Collapsed;
                    hint.Text = isExport
                        ? "你调好的画面风格会变成下面这段分享码（只含画面参数，不动其他设置）。复制后发给朋友或发到群里，TA 粘贴解析后就能用上一模一样的画面。"
                        : "粘贴别人分享的码（直接粘贴整段分享文本也行，会自动找出里面的码），解析预览后套用。";
                    input.IsReadOnly = isExport;
                    summary.Text = "";
                    if (isExport) {
                        if (exportedIni == null) exportedIni = File.ReadAllBytes(exportSourcePath);
                        input.Text = MochizukiShareCode.Encode(exportedIni, includeGame.IsChecked == true ? executable : null,
                                                               noteDirty ? MochizukiShareCode.SanitizeNote(noteBox.Text) : null);
                        var decoded = MochizukiShareCode.Decode(input.Text);
                        summary.Text = MochizukiShareCode.Summary(decoded, true);
                        if (MochizukiShareCode.NonDefaultCount(decoded) == 0)
                            summary.Text += "\n当前全部为默认值：分享码有效，导入方应用后将恢复同样的默认画面。";
                    } else {
                        input.Text = "";
                    }
                };
                input.TextChanged += delegate {
                    if (!isExport) {
                        validated = null; validatedGame = ""; apply.IsEnabled = false; summary.Text = "";
                        var code = ExtractCode(input.Text);
                        if (code == null) return;
                        try {
                            var values = MochizukiShareCode.Decode(code);
                            string tag = values.GameTag.Length > 0 ? "【" + values.GameTag + "】" : "";
                            string noteLine = values.Note.Length > 0 ? "（备注：" + values.Note + "）" : "";
                            summary.Text = "✨ 已识别" + tag + "同款画质（色调、质感等专属调校）" + noteLine;
                            validated = code; validatedGame = values.GameTag; apply.IsEnabled = true;
                        } catch (Exception ex) { summary.Text = ShareError(ex); }
                    }
                };
                includeGame.Checked += delegate { if (isExport && renderMode != null) renderMode(); };
                includeGame.Unchecked += delegate { if (isExport && renderMode != null) renderMode(); };
                noteBox.TextChanged += delegate {
                    if (!noteDirty && noteBox.Text == notePlaceholder) return;
                    noteDirty = true;
                    if (isExport && renderMode != null) renderMode();
                };
                pickIni.Click += delegate {
                    var dlg = new Microsoft.Win32.OpenFileDialog { Filter = "INI 文件|*.ini|所有文件|*.*", Title = "选择要导出的 INI" };
                    if (dlg.ShowDialog(dialog) == true)
                    {
                        try {
                            exportedIni = File.ReadAllBytes(dlg.FileName);
                            exportSourcePath = dlg.FileName;
                            sourceHint.Text = System.IO.Path.GetFileName(dlg.FileName);
                            if (isExport && renderMode != null) renderMode();
                        } catch (Exception ex) { SetIniStatus("share-error", ShareError(ex)); }
                    }
                };
                action.Click += delegate {
                    try {
                        if (isExport) { Clipboard.SetText(input.Text); return; }
                        if (!CanUseIniGame(game)) return;
                        var code = ExtractCode(input.Text);
                        var values = MochizukiShareCode.Decode(code);
                        int difference = MochizukiShareCode.DifferenceCount(File.ReadAllBytes(path), code);
                        summary.Text = (values.Note.Length > 0 ? "备注：" + values.Note + "\n" : "") +
                                       MochizukiShareCode.Summary(values, true) + "\n将更改 " + difference + " 项画面设置（其余风格参数恢复默认）。";
                        validated = code; validatedGame = values.GameTag; apply.IsEnabled = true;
                    } catch (Exception ex) { validated = null; apply.IsEnabled = false; summary.Text = ShareError(ex); }
                };
                apply.Click += delegate {
                    if (validated == null || !CanUseIniGame(game)) return;
                    if (validatedGame.Length > 0 && !MochizukiShareCode.GameTagMatches(validatedGame, executable) &&
                        DialogTheme.Show(dialog,
                            "这段画面来自「" + validatedGame + "」，和当前游戏不是同一个，还要换上吗？",
                            "游戏不一样", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
                    if (ApplyShareCode(game, validated)) dialog.Close();
                };
                buttons.Children.Add(close); buttons.Children.Add(action); buttons.Children.Add(apply);
                panel.Children.Add(buttons);
                DialogTheme.Primary(dialog, action); DialogTheme.SetContent(dialog, panel);

                exportRadio.IsChecked = !import; importRadio.IsChecked = import;
                renderMode();

                // Import mode: prefill only when the clipboard already holds a recognizable code —
                // never dump unrelated clipboard text into the box. Runs AFTER renderMode(),
                // whose import branch clears the input (and would wipe the prefill).
                if (import) {
                    try {
                        if (Clipboard.ContainsText()) {
                            var code = ExtractCode(Clipboard.GetText());
                            if (code != null) input.Text = code;
                        }
                    } catch { }
                }

                dialog.Loaded += delegate { if (!isExport) input.Focus(); };
                dialog.ShowDialog();
            } catch (Exception ex) { SetIniStatus("share-error", ShareError(ex)); }
        }

        // Theme brush lookup for controls built in code (avoids the white system-default chrome)
        static System.Windows.Media.Brush TryFindResourceString(string key)
        {
            var v = _window.TryFindResource(key);
            return v as System.Windows.Media.Brush ?? System.Windows.Media.Brushes.Transparent;
        }

        static bool ApplyShareCode(IniGameIdentity game, string code)
        {
            if (!CanUseIniGame(game)) return false;
            bool locked = false, busy = false; string temporary = null;
            try {
                string path = Path.Combine(game.Directory, "OptiScaler.ini");
                if (!File.Exists(path)) { SetIniStatus("noini", ""); return false; }
                locked = TryLockTarget(game.Directory);
                if (!locked) { SetIniStatus("locked", ""); return false; }
                SetBusy(true); busy = true; RefreshProfileActions();
                byte[] bytes = MochizukiShareCode.Apply(File.ReadAllBytes(path), code);
                temporary = path + ".stage-" + Guid.NewGuid().ToString("N");
                using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(bytes, 0, bytes.Length); stream.Flush(true); }
                string backup = path + ".bak-" + DateTime.Now.ToString("yyyyMMdd-HHmmss-fff") + "-" + Guid.NewGuid().ToString("N").Substring(0, 8);
                File.Replace(temporary, path, backup);
                SetIniStatus("share-imported", Path.GetFileName(backup)); return true;
            } catch (Exception ex) { SetIniStatus("share-error", ShareError(ex)); return false; }
            finally {
                if (temporary != null && File.Exists(temporary)) { try { File.Delete(temporary); } catch { } }
                if (locked) ReleaseLock();
                if (busy) SetBusy(false);
                RefreshProfileActions();
            }
        }

        // ---------------------------------------------------------------- helpers
        // EXE 识别走上游 FolderGameScanner（PE 导入表 + 目录优先级递归扫描），后台填充缓存。
        static FileInfo GameExe()
        {
            return string.Equals(_gameExeDir, _dir, StringComparison.OrdinalIgnoreCase) ? _gameExeCache : null;
        }

        // ---- wiki 检测：照搬 tools/proxy-switch.ps1 的两级检测 + OptiPatcher 支持列表 ----

        [System.Runtime.Serialization.DataContract]
        sealed class PanelProxyDoc
        {
            [System.Runtime.Serialization.DataMember(Name = "profiles")] public PanelProxyProfile[] Profiles;
        }
        [System.Runtime.Serialization.DataContract]
        sealed class PanelProxyProfile
        {
            [System.Runtime.Serialization.DataMember(Name = "id")] public string Id;
            [System.Runtime.Serialization.DataMember(Name = "names")] public string[] Names;
            [System.Runtime.Serialization.DataMember(Name = "pathSegments")] public string[] PathSegments;
            [System.Runtime.Serialization.DataMember(Name = "preferred")] public string Preferred;
            [System.Runtime.Serialization.DataMember(Name = "alternatives")] public string[] Alternatives;
        }

        sealed class WikiAdvice
        {
            public PanelProxyProfile Profile;
            public string WikiName;
            public string[] WikiProxies;
            public string OptiDlss, OptiFg;
            public string Recommended
            {
                get
                {
                    if (Profile != null && !string.IsNullOrEmpty(Profile.Preferred)) return Profile.Preferred;
                    if (WikiProxies != null && WikiProxies.Length > 0) return WikiProxies[0];
                    return null;
                }
            }
        }

        const string ProfileCatalogUrl = "https://raw.githubusercontent.com/TheAutomatic/dlss-5-amd-project/main/assets/compatibility/proxy-profiles.json";
        const string WikiUrl = "https://raw.githubusercontent.com/wiki/optiscaler/OptiScaler/Compatibility-List.md";
        const string OptiSupportUrl = "https://raw.githubusercontent.com/optiscaler/OptiPatcher/main/GameSupport.md";

        // Remote only for the catalogue: nothing is written to disk, and the copy embedded in
        // this EXE is the fallback when the network is unavailable - same as proxy-switch.ps1.
        static PanelProxyDoc LoadProfileCatalog()
        {
            var text = Fetch(ProfileCatalogUrl, 5000);
            if (!string.IsNullOrEmpty(text))
            {
                try { return JsonUtil.Read<PanelProxyDoc>(text); } catch { }
            }
            try
            {
                using (var stream = typeof(PanelWindow).Assembly.GetManifestResourceStream("OptiScalerPanel.proxy-profiles.json"))
                using (var reader = new StreamReader(stream))
                    return JsonUtil.Read<PanelProxyDoc>(reader.ReadToEnd());
            }
            catch { return null; }
        }

        // Profiles identify a game by (case-insensitive) folder-name segment containment, the
        // same rule as proxy-switch.ps1's Find-Profile: store launchers append the app id to
        // the folder ("Wuthering Waves(2002137)"), so containment is required; short segments
        // are skipped to avoid false hits.
        static PanelProxyProfile FindProfileIn(PanelProxyDoc doc, string folder)
        {
            if (doc == null || doc.Profiles == null) return null;
            var segments = folder.Split(new[] { '\\', '/' }, StringSplitOptions.RemoveEmptyEntries);
            foreach (var profile in doc.Profiles)
            {
                if (profile == null || profile.PathSegments == null) continue;
                foreach (var segment in profile.PathSegments)
                {
                    var needle = segment;
                    if (string.IsNullOrEmpty(needle) || needle.Length < 4) continue;
                    foreach (var actual in segments)
                        if (actual.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0) return profile;
                }
            }
            return null;
        }

        // Folder segments that say nothing about which game it is; matching on them would
        // hit unrelated rows (a folder called "game" would match any title containing it).
        static readonly string[] GenericSegments =
        {
            "game", "games", "bin", "binaries", "win64", "win32", "x64", "x86", "client",
            "content", "engine", "app", "apps", "rail_apps", "steamapps", "common",
            "windowsnoeditor", "windows", "project", "build", "release", "shipping"
        };

        // Folders and the wiki disagree on spacing and punctuation
        // ("GhostwireTokyo" vs "Ghostwire: Tokyo"), so compare without them.
        static string Normalize(string s)
        {
            if (string.IsNullOrEmpty(s)) return string.Empty;
            var t = s.ToLowerInvariant();
            foreach (var ch in new[] { ' ', '\t', ':', '-', '.', '(', ')', '\'', '"', '´', '\u2019' })
                t = t.Replace(ch.ToString(), string.Empty);
            return t;
        }

        static string[] GameNameCandidates(string folder)
        {
            return folder.Split(new[] { '\\', '/' }, StringSplitOptions.RemoveEmptyEntries)
                .Select(s => System.Text.RegularExpressions.Regex.Replace(s, @"\s*\(\d+\)\s*$", string.Empty))
                .Select(Normalize)
                .Where(s => s.Length >= 4 && Array.IndexOf(GenericSegments, s) < 0)
                .ToArray();
        }

        static string Fetch(string url, int timeoutMs)
        {
            try
            {
                var request = (System.Net.HttpWebRequest)System.Net.WebRequest.Create(url);
                request.Timeout = timeoutMs;
                request.UserAgent = "OptiScalerPanel";
                using (var response = request.GetResponse())
                using (var reader = new StreamReader(response.GetResponseStream()))
                    return reader.ReadToEnd();
            }
            catch { return null; }
        }

        // The catalogue only covers a handful of games, while the OptiScaler wiki lists every
        // tested one. Pull the proxy names out of the note column when no profile matched.
        static void GetWikiEntry(WikiAdvice advice, string folder)
        {
            var text = Fetch(WikiUrl, 10000);
            if (string.IsNullOrEmpty(text)) return;
            var names = GameNameCandidates(folder);
            var rxLink = new System.Text.RegularExpressions.Regex(@"\[([^\]]+)\]\([^)]*\)");
            var rxDll = new System.Text.RegularExpressions.Regex(@"(?i)\b(dxgi|winmm|d3d12|winhttp|wininet|dbghelp|version|d3d11|opengl32)\.dll\b");

            foreach (var line in text.Split('\n'))
            {
                var trimmed = line.Trim();
                if (!trimmed.StartsWith("|", StringComparison.Ordinal)) continue;
                var cells = trimmed.Trim('|').Split('|');
                if (cells.Length < 2) continue;

                var rawName = cells[0].Trim();
                var link = rxLink.Match(rawName);
                var name = link.Success ? link.Groups[1].Value.Trim() : rawName;
                if (System.Text.RegularExpressions.Regex.IsMatch(name, @"(?i)^\s*GAME\s*NAME\s*$")) continue;

                var nameNorm = Normalize(name);
                if (nameNorm.Length < 4) continue;
                if (!cells[1].Contains("✅")) continue;

                var hit = false;
                foreach (var n in names)
                {
                    if (n.Contains(nameNorm) || nameNorm.Contains(n)) { hit = true; break; }
                }
                if (!hit) continue;

                var dlls = rxDll.Matches(line).Cast<System.Text.RegularExpressions.Match>()
                    .Select(m => m.Groups[1].Value.ToLowerInvariant() + ".dll")
                    .Distinct()
                    .ToArray();

                // Keep the entry even without a DLL: "listed but no proxy recorded" is more
                // useful than "no record at all".
                advice.WikiName = name;
                advice.WikiProxies = dlls;
                return;
            }
        }

        // OptiPatcher support list. Upstream decides at runtime: the plugin's PatchResult()
        // returns true and OptiScaler then disables Dxgi/Vulkan spoofing itself. The table is
        // documentation only, so this is an advisory check, not a guarantee.
        static void GetOptiSupport(WikiAdvice advice, string folder)
        {
            var text = Fetch(OptiSupportUrl, 10000);
            if (string.IsNullOrEmpty(text)) return;
            var names = GameNameCandidates(folder);
            foreach (var line in text.Split('\n'))
            {
                var trimmed = line.Trim();
                if (!trimmed.StartsWith("|", StringComparison.Ordinal)) continue;
                var cells = trimmed.Trim('|').Split('|');
                if (cells.Length < 4) continue;
                var name = cells[0].Trim();
                // Skip the table header and the commented-out "GAME NAME" template row.
                if (System.Text.RegularExpressions.Regex.IsMatch(name, @"(?i)^game(\s+name)?$") ||
                    System.Text.RegularExpressions.Regex.IsMatch(name, @"^[-:\s]+$")) continue;
                var nameNorm = Normalize(name);
                if (nameNorm.Length < 4) continue;
                var hit = false;
                foreach (var n in names)
                {
                    if (n.Contains(nameNorm) || nameNorm.Contains(n)) { hit = true; break; }
                }
                if (!hit) continue;
                advice.OptiDlss = cells[1].Trim();
                advice.OptiFg = cells[2].Trim();
                return;
            }
        }

        // UI 线程读缓存；后台线程用 AdviceHitFor 拉取（打开窗口后异步执行，不阻塞渲染）。
        static WikiAdvice AdviceCached()
        {
            if (AdviceHitCache != null && string.Equals(AdviceHitDir, _dir, StringComparison.OrdinalIgnoreCase))
                return AdviceHitCache;
            return null;
        }

        static WikiAdvice AdviceHitFor(string dir)
        {
            if (AdviceHitCache != null && string.Equals(AdviceHitDir, dir, StringComparison.OrdinalIgnoreCase))
                return AdviceHitCache;
            AdviceHitDir = dir;
            var advice = new WikiAdvice();
            advice.Profile = FindProfileIn(LoadProfileCatalog(), dir);
            if (advice.Profile == null)
            {
                GetWikiEntry(advice, dir);
                GetOptiSupport(advice, dir);
            }
            AdviceHitCache = advice;
            return advice;
        }

        // hero 背景图：照上游 library-scan 的思路，在游戏目录里找 Steam library_hero / header /
        // 启动图，命名命中优先、否则按分辨率挑最佳横图；找不到回落到单字母 monogram。
        static string FindHeroImage(string dir)
        {
            try
            {
                var best = ""; long bestScore = 0;
                var queue = new Queue<KeyValuePair<string, int>>();
                queue.Enqueue(new KeyValuePair<string, int>(dir, 0));
                var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                var images = 0;
                while (queue.Count > 0 && images < 400)
                {
                    var item = queue.Dequeue();
                    if (!seen.Add(item.Key)) continue;
                    string[] files;
                    try { files = Directory.GetFiles(item.Key); } catch { continue; }
                    foreach (var file in files)
                    {
                        var ext = System.IO.Path.GetExtension(file);
                        if (!string.Equals(ext, ".jpg", StringComparison.OrdinalIgnoreCase) &&
                            !string.Equals(ext, ".jpeg", StringComparison.OrdinalIgnoreCase) &&
                            !string.Equals(ext, ".png", StringComparison.OrdinalIgnoreCase)) continue;
                        if (++images >= 400) break;
                        var name = System.IO.Path.GetFileName(file);
                        var named = System.Text.RegularExpressions.Regex.IsMatch(
                            name, @"(?i)^(?:\d+_)?(?:library_)?(?:hero|header)|splashscreen");
                        long area;
                        if (!TryImageSize(file, out area) && !named) continue;
                        var score = (named ? 100000000L : 0) + area;
                        if (score > bestScore) { bestScore = score; best = file; }
                    }
                    if (item.Value >= 3) continue;
                    string[] subs;
                    try { subs = Directory.GetDirectories(item.Key); } catch { continue; }
                    foreach (var sub in subs)
                    {
                        var low = System.IO.Path.GetFileName(sub).ToLowerInvariant();
                        if (low == "paks" || low == "shadercache" || low == ".git" || low == "node_modules" ||
                            low == "optiscaler" || low == "person-model" || low == "dlssnr-amd" ||
                            low == "redist" || low == "_commonredist" || low == "__installer" || low == "plugins") continue;
                        queue.Enqueue(new KeyValuePair<string, int>(sub, item.Value + 1));
                    }
                }
                return bestScore > 0 ? best : null;
            }
            catch { return null; }
        }

        static bool TryImageSize(string path, out long area)
        {
            area = 0;
            try
            {
                using (var stream = File.OpenRead(path))
                {
                    var frame = System.Windows.Media.Imaging.BitmapFrame.Create(stream,
                        System.Windows.Media.Imaging.BitmapCreateOptions.DelayCreation,
                        System.Windows.Media.Imaging.BitmapCacheOption.None);
                    var width = frame.PixelWidth;
                    var height = frame.PixelHeight;
                    if (width < 480 || height < 160) return false;
                    var ratio = (double)width / height;
                    if (ratio < 1.5 || ratio > 4.0) return false;
                    area = (long)width * height;
                    return true;
                }
            }
            catch { return false; }
        }

        static string FirstProfileName(PanelProxyProfile profile)
        {
            if (profile == null || profile.Names == null) return null;
            foreach (var name in profile.Names)
                if (!string.IsNullOrWhiteSpace(name)) return name.Trim();
            return null;
        }

        static void OpenUrl(string url)
        {
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
        }
    }
}
