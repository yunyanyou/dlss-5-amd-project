using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
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
        static StackPanel _list;
        static TextBlock _gameText, _wikiText, _optiText, _topStatus, _bottomStatus, _shareHint;
        static System.Windows.Shapes.Ellipse _led, _bottomLed;
        static ComboBox _presetCombo;
        static TextBox _codeBox;

        public static Window Create(string dir)
        {
            _dir = dir;
            LauncherTheme.Apply("dark");
            var dialog = Program.LoadDialogTheme();
            if (Application.Current != null)
            {
                Application.Current.Resources.MergedDictionaries.Add(dialog);
                Application.Current.Resources.MergedDictionaries.Add(LauncherTheme.Resources);
            }

            using (var stream = Program.OpenXaml("PanelWindow.xaml"))
                _window = (Window)XamlReader.Load(stream);

            _list = (StackPanel)_window.FindName("LoaderList");
            _gameText = (TextBlock)_window.FindName("GameText");
            _wikiText = (TextBlock)_window.FindName("WikiText");
            _optiText = (TextBlock)_window.FindName("OptiText");
            _topStatus = (TextBlock)_window.FindName("TopStatus");
            _bottomStatus = (TextBlock)_window.FindName("BottomStatus");
            _shareHint = (TextBlock)_window.FindName("ShareHint");
            _led = (System.Windows.Shapes.Ellipse)_window.FindName("StatusLed");
            _bottomLed = (System.Windows.Shapes.Ellipse)_window.FindName("BottomLed");
            _presetCombo = (ComboBox)_window.FindName("PresetCombo");
            _codeBox = (TextBox)_window.FindName("CodeBox");

            var close = (Button)_window.FindName("CloseBtn");
            close.Click += (s, e) => _window.Close();
            var min = (Button)_window.FindName("MinBtn");
            min.Click += (s, e) => _window.WindowState = WindowState.Minimized;
            var author = (TextBlock)_window.FindName("AuthorLink");
            author.MouseLeftButtonUp += (s, e) => OpenUrl("https://github.com/TheAutomatic/dlss-5-amd-project");

            ((Button)_window.FindName("FolderBtn")).Click += (s, e) => OpenDir();
            ((Button)_window.FindName("ExportBtn")).Click += (s, e) => ExportCode();
            ((Button)_window.FindName("ImportBtn")).Click += (s, e) => ImportCode();
            ((Button)_window.FindName("OptiBtn")).Click += (s, e) => InstallOptiPatcher();
            ((Button)_window.FindName("LogBtn")).Click += (s, e) => OpenLog();
            ((Button)_window.FindName("PresetSaveBtn")).Click += (s, e) => SavePreset();
            ((Button)_window.FindName("PresetApplyBtn")).Click += (s, e) => ApplyPreset();
            ((Button)_window.FindName("PresetDeleteBtn")).Click += (s, e) => DeletePreset();

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
            _list.Children.Clear();
            var current = CurrentInjection();
            var occupied = Occupied();
            var profile = ProfileHit();
            var recommend = profile != null ? profile.Preferred : null;

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

            var exe = GameExe();
            _gameText.Text = exe != null ? "游戏　" + exe.Name : "游戏　未找到 EXE";
            _wikiText.Text = profile != null
                ? "Wiki　首选 " + profile.Preferred + (profile.Alternatives != null && profile.Alternatives.Length > 0 ? "　备选 " + string.Join(" / ", profile.Alternatives) : "")
                : "Wiki　无此游戏记录";
            _optiText.Text = HasOptiPatcher() ? "OptiPatcher　已安装" : "OptiPatcher　未安装";

            _topStatus.Text = current != null ? "已注入 " + current.Name + ".dll" : "未检测到注入";
            _led.Fill = current != null ? LauncherTheme.Brush("ThemeSuccess") : LauncherTheme.Brush("ThemeAccent");
            _bottomLed.Fill = _led.Fill;
            _bottomStatus.Text = Path.GetFileName(_dir.TrimEnd('\\', '/'));

            ReloadPresets();
        }

        static void ReloadPresets()
        {
            _presetCombo.Items.Clear();
            var names = new IniProfiles(SettingsDir()).List();
            if (names.Length == 0)
            {
                _presetCombo.Items.Add("（还没有预设）");
                _presetCombo.SelectedIndex = 0;
                return;
            }
            foreach (var n in names) _presetCombo.Items.Add(n);
            _presetCombo.SelectedIndex = 0;
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
            if (cur == null) { _shareHint.Text = "目录里没有找到 OptiScaler 的注入。"; return; }
            if (string.Equals(cur.Name, target, StringComparison.OrdinalIgnoreCase))
            {
                _shareHint.Text = "已经是这个注入名了。";
                return;
            }
            var dest = System.IO.Path.Combine(_dir, target + ".dll");
            if (File.Exists(dest))
            {
                if (IsOurs(dest))
                {
                    var answer = MessageBox.Show("旧的 " + target + ".dll 是我们之前的注入，删除它并改用当前这份？",
                        "确认", MessageBoxButton.YesNo, MessageBoxImage.Question);
                    if (answer != MessageBoxResult.Yes) return;
                    File.Delete(dest);
                }
                else
                {
                    _shareHint.Text = target + ".dll 被游戏或其它 mod 占用，不覆盖。";
                    return;
                }
            }
            try
            {
                File.Move(cur.Path, dest);
                _shareHint.Text = "已切换到 " + target + ".dll，重启游戏生效。";
            }
            catch (Exception ex) { _shareHint.Text = "切换失败：" + ex.Message; }
            Refresh();
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
            if (!File.Exists(ini)) { _shareHint.Text = "目录里没有 OptiScaler.ini，无法写入 LoadAsiPlugins。"; return; }
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
            _shareHint.Text = "正在下载 OptiPatcher...";
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
                _shareHint.Text = "OptiPatcher 下载失败，目录里也没有离线副本。";
                return;
            }

            try
            {
                var plugins = System.IO.Path.Combine(_dir, "plugins");
                if (!Directory.Exists(plugins)) Directory.CreateDirectory(plugins);
                File.Copy(source, System.IO.Path.Combine(plugins, "OptiPatcher.asi"), true);
                SetAsiPlugins("true");
                _shareHint.Text = "OptiPatcher 安装完成。";
            }
            catch (Exception ex) { _shareHint.Text = "安装失败：" + ex.Message; }
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
            else _shareHint.Text = "还没有日志（进过一次游戏才会有 OptiScaler.log）。";
        }

        // ---------------------------------------------------------------- look codes
        static void ExportCode()
        {
            var ini = System.IO.Path.Combine(_dir, "OptiScaler.ini");
            if (!File.Exists(ini)) { _shareHint.Text = "当前目录没有 OptiScaler.ini。"; return; }
            try
            {
                var exe = GameExe();
                var game = exe != null ? System.IO.Path.GetFileNameWithoutExtension(exe.Name) : "";
                var code = MochizukiShareCode.Encode(File.ReadAllBytes(ini), game);
                _codeBox.Text = code;
                Clipboard.SetText(code);
                _shareHint.Text = "分享码已复制，发到群里让别人粘贴。";
            }
            catch (Exception ex) { _shareHint.Text = "导出失败：" + ex.Message; }
        }

        static void ImportCode()
        {
            var raw = _codeBox.Text;
            if (string.IsNullOrWhiteSpace(raw))
            {
                try { raw = Clipboard.GetText(); } catch { }
            }
            if (string.IsNullOrWhiteSpace(raw)) { _shareHint.Text = "先粘贴一段分享文字或码。"; return; }
            MochizukiShareCode.DecodedCode decoded;
            try { decoded = MochizukiShareCode.Decode(raw); }
            catch (Exception ex) { _shareHint.Text = "分享码无效：" + ex.Message; return; }

            var summary = MochizukiShareCode.Summary(decoded, true);
            var answer = MessageBox.Show("识别到：" + summary + "\n\n应用到当前游戏？", "确认",
                MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (answer != MessageBoxResult.Yes) return;
            try
            {
                var ini = System.IO.Path.Combine(_dir, "OptiScaler.ini");
                if (!File.Exists(ini)) { _shareHint.Text = "当前目录没有 OptiScaler.ini。"; return; }
                var backup = ini + ".bak-" + DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
                File.Copy(ini, backup, true);
                var rewritten = MochizukiShareCode.Apply(File.ReadAllBytes(ini), raw);
                File.WriteAllBytes(ini, rewritten);
                _shareHint.Text = "已换上这套画面（备份 " + System.IO.Path.GetFileName(backup) + "），重启游戏生效。";
            }
            catch (Exception ex) { _shareHint.Text = "应用失败：" + ex.Message; }
        }

        // ---------------------------------------------------------------- presets
        static string SettingsDir()
        {
            return System.IO.Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OptiScalerNR");
        }

        static void SavePreset()
        {
            var ini = System.IO.Path.Combine(_dir, "OptiScaler.ini");
            if (!File.Exists(ini)) { _shareHint.Text = "当前目录没有 OptiScaler.ini。"; return; }
            var name = Prompt("给这套配置起个名字", DateTime.Now.ToString("yyyyMMdd-HHmm", CultureInfo.InvariantCulture));
            if (string.IsNullOrWhiteSpace(name)) return;
            try
            {
                var saved = new IniProfiles(SettingsDir()).Save(ini, name);
                _shareHint.Text = "已保存预设「" + saved + "」。";
                ReloadPresets();
            }
            catch (Exception ex) { _shareHint.Text = "保存失败：" + ex.Message; }
        }

        static void ApplyPreset()
        {
            var name = _presetCombo.SelectedItem as string;
            if (string.IsNullOrEmpty(name) || name.StartsWith("（", StringComparison.Ordinal)) { _shareHint.Text = "还没有可套用的预设。"; return; }
            var answer = MessageBox.Show("套用「" + name + "」到当前游戏？\n\n当前 ini 会先备份。", "确认",
                MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (answer != MessageBoxResult.Yes) return;
            try
            {
                var ini = System.IO.Path.Combine(_dir, "OptiScaler.ini");
                if (File.Exists(ini))
                    File.Copy(ini, ini + ".bak-" + DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture), true);
                new IniProfiles(SettingsDir()).Apply(_dir, name, false);
                _shareHint.Text = "已套用「" + name + "」，重启游戏生效。";
            }
            catch (Exception ex) { _shareHint.Text = "套用失败：" + ex.Message; }
        }

        static void DeletePreset()
        {
            var name = _presetCombo.SelectedItem as string;
            if (string.IsNullOrEmpty(name) || name.StartsWith("（", StringComparison.Ordinal)) return;
            var answer = MessageBox.Show("删除预设「" + name + "」？", "确认", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (answer != MessageBoxResult.Yes) return;
            try
            {
                new IniProfiles(SettingsDir()).Delete(name);
                _shareHint.Text = "已删除「" + name + "」。";
                ReloadPresets();
            }
            catch (Exception ex) { _shareHint.Text = "删除失败：" + ex.Message; }
        }

        // ---------------------------------------------------------------- helpers
        static readonly string[] ExeExcludeStart =
        {
            "setup", "install", "unins", "crash", "unitycrash", "vc_redist", "dxsetup",
            "easyanticheat", "eac_", "battleye", "beclient", "beservice", "unrealcef",
            "webview", "cefsubprocess", "shadercompile", "bugsplat", "crs-",
            "redprelauncher", "larilauncher", "2klauncher"
        };
        static readonly string[] ExeExcludeEnd =
        {
            "prelauncher", "launcher", "crashreport", "crashhandler", "crs-handler",
            "errorreporter", "updater", "patcher", "uninstaller", "benchmark", "dedicatedserver"
        };
        static readonly string[] ExeExcludeName = { "gamelaunchhelper", "person-worker", "activationui", "cleanup", "touchup", "config" };

        static FileInfo GameExe()
        {
            try
            {
                var files = new DirectoryInfo(_dir).GetFiles("*.exe");
                FileInfo best = null;
                var bestRank = 99;
                foreach (var f in files)
                {
                    var n = f.Name.ToLowerInvariant();
                    var stem = System.IO.Path.GetFileNameWithoutExtension(n);
                    var skip = false;
                    foreach (var s in ExeExcludeStart) if (n.StartsWith(s, StringComparison.Ordinal)) { skip = true; break; }
                    if (!skip) foreach (var s in ExeExcludeEnd) if (stem.EndsWith(s, StringComparison.Ordinal)) { skip = true; break; }
                    if (!skip) foreach (var s in ExeExcludeName) if (stem == s) { skip = true; break; }
                    if (skip) continue;
                    var rank = n.EndsWith("wingdk-shipping.exe", StringComparison.Ordinal) ? 0
                             : n.EndsWith("-win64-shipping.exe", StringComparison.Ordinal) ? 1
                             : n.EndsWith("shipping.exe", StringComparison.Ordinal) ? 2 : 3;
                    if (rank < bestRank || (rank == bestRank && best != null && f.Length > best.Length))
                    {
                        best = f;
                        bestRank = rank;
                    }
                }
                return best;
            }
            catch { return null; }
        }

        static bool HasOptiPatcher()
        {
            return File.Exists(System.IO.Path.Combine(_dir, "plugins", "OptiPatcher.asi"))
                || File.Exists(System.IO.Path.Combine(_dir, "OptiScaler", "plugins", "OptiPatcher.asi"));
        }

        sealed class ProfileEntry
        {
            public string Preferred;
            public string[] Alternatives;
        }

        static ProfileEntry ProfileHitCache;
        static string ProfileHitDir;

        static ProfileEntry ProfileHit()
        {
            if (ProfileHitCache != null && string.Equals(ProfileHitDir, _dir, StringComparison.OrdinalIgnoreCase))
                return ProfileHitCache;
            ProfileHitDir = _dir;
            ProfileHitCache = null;
            try
            {
                using (var recommendations = new ProxyRecommendations(SettingsDir()))
                {
                    var game = new GameInfo { Root = _dir };
                    var profile = recommendations.Match(game);
                    if (profile == null) return null;
                    ProfileHitCache = new ProfileEntry { Preferred = profile.Preferred, Alternatives = profile.Alternatives };
                    return ProfileHitCache;
                }
            }
            catch { return null; }
        }

        static void OpenUrl(string url)
        {
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
        }

        static void OpenDir()
        {
            try { Process.Start(new ProcessStartInfo("explorer.exe", "\"" + _dir + "\"") { UseShellExecute = true }); } catch { }
        }

        static string Prompt(string caption, string initial)
        {
            var dialog = new Window
            {
                Title = caption,
                Width = 380,
                Height = 150,
                WindowStyle = WindowStyle.ToolWindow,
                WindowStartupLocation = WindowStartupLocation.CenterOwner,
                Owner = _window,
                Background = LauncherTheme.Brush("ThemeBackground"),
                Foreground = LauncherTheme.Brush("ThemeInk")
            };
            var grid = new Grid { Margin = new Thickness(16) };
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var box = new TextBox { Text = initial, Height = 30, Margin = new Thickness(0, 0, 0, 12) };
            var ok = new Button { Content = "确定", Width = 90, Height = 30, HorizontalAlignment = HorizontalAlignment.Right };
            ok.Click += (s, e) => { dialog.DialogResult = true; dialog.Close(); };
            Grid.SetRow(box, 0);
            Grid.SetRow(ok, 1);
            grid.Children.Add(box);
            grid.Children.Add(ok);
            dialog.Content = grid;
            return dialog.ShowDialog() == true ? box.Text : null;
        }
    }
}
