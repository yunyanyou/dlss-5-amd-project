using System;
using System.IO;
using System.Reflection;
using System.Windows;

namespace OptScalerNR.Launcher
{
    /// <summary>
    /// 精简面板的入口。只开一个窗口：注入名、Wiki 推荐、OptiPatcher、配置预设、
    /// 画面分享码。风格与控件全部复用上游启动器（LauncherTheme / DialogTheme）。
    /// </summary>
    public static class Program
    {
        [STAThread]
        public static int Main(string[] args)
        {
            var dir = AppDomain.CurrentDomain.BaseDirectory;
            if (args != null && args.Length >= 1 && !string.IsNullOrWhiteSpace(args[0])
                && !args[0].StartsWith("-", StringComparison.Ordinal))
            {
                dir = args[0];
            }

            var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            // 运行期未处理异常落盘而不是闪退，方便定位（对齐启动器的做法）。
            app.DispatcherUnhandledException += delegate(object sender, System.Windows.Threading.DispatcherUnhandledExceptionEventArgs e)
            {
                try { File.WriteAllText(Path.Combine(Path.GetTempPath(), "optiscaler-panel-error.txt"), e.Exception.ToString()); } catch { }
                MessageBox.Show(e.Exception.Message, "OptiScaler");
                e.Handled = true;
            };
            Window window;
            try
            {
                window = PanelWindow.Create(dir);
            }
            catch (Exception ex)
            {
                try { File.WriteAllText(Path.Combine(Path.GetTempPath(), "optiscaler-panel-error.txt"), ex.ToString()); } catch { }
                MessageBox.Show(ex.Message, "OptiScaler");
                return 1;
            }

            app.MainWindow = window;
            window.Show();
            return app.Run();
        }

        public static Stream OpenXaml(string name)
        {
            var asm = Assembly.GetExecutingAssembly();
            using (var stream = asm.GetManifestResourceStream("OptiScalerPanel." + name))
            {
                if (stream == null) throw new FileNotFoundException("Missing embedded XAML " + name);
                // 上游 XAML（如 DialogTheme.xaml）里 xmlns:local 写死了 assembly=OptScalerNR.Launcher，
                // 直接 XamlReader.Load 会因类型解析失败崩溃（对话框里的 Trigger 首当其冲）。
                // 统一在这里换成面板自己的程序集名，DialogTheme.Resources() 与主窗口加载同路径。
                using (var reader = new StreamReader(stream))
                {
                    var text = reader.ReadToEnd().Replace("assembly=OptScalerNR.Launcher", "assembly=OptiScalerPanel");
                    return new MemoryStream(System.Text.Encoding.UTF8.GetBytes(text));
                }
            }
        }

        /// <summary>
        /// DialogTheme.xaml 是上游文件，加载时由 OpenXaml 统一替换程序集名，文件本身不动，
        /// 上游更新后仍然直接生效。
        /// </summary>
        public static ResourceDictionary LoadDialogTheme()
        {
            using (var stream = OpenXaml("DialogTheme.xaml"))
                return (ResourceDictionary)System.Windows.Markup.XamlReader.Load(stream);
        }
    }
}
