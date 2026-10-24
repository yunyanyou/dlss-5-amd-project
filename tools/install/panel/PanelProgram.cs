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
            var stream = asm.GetManifestResourceStream("OptiScalerPanel." + name);
            if (stream == null) throw new FileNotFoundException("Missing embedded XAML " + name);
            return stream;
        }

        /// <summary>
        /// DialogTheme.xaml 是上游文件，里面写死了 assembly=OptScalerNR.Launcher
        /// （完整启动器的程序集名）。这里只在加载时把名字换成面板自己的，文件本身不动，
        /// 上游更新后仍然直接生效。
        /// </summary>
        public static ResourceDictionary LoadDialogTheme()
        {
            using (var stream = OpenXaml("DialogTheme.xaml"))
            using (var reader = new StreamReader(stream))
            {
                var text = reader.ReadToEnd().Replace("assembly=OptScalerNR.Launcher", "assembly=OptiScalerPanel");
                using (var buffer = new MemoryStream(System.Text.Encoding.UTF8.GetBytes(text)))
                {
                    return (ResourceDictionary)System.Windows.Markup.XamlReader.Load(buffer);
                }
            }
        }
    }
}
