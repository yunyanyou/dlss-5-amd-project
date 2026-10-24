using System;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Markup;

namespace OptScalerNR.Launcher
{
    public static class Program
    {
        public static DateTime StartedUtc { get; private set; }

        [STAThread]
        public static int Main(string[] args)
        {
            StartedUtc = DateTime.UtcNow;
            var app = new Application();
            app.ShutdownMode = ShutdownMode.OnMainWindowClose;
            // --slim [目录]: 游戏目录里的精简面板，跳过游戏库/安装流程。
            Window window;
            try
            {
                if (args != null && args.Length >= 1 && string.Equals(args[0], "--slim", StringComparison.OrdinalIgnoreCase))
                {
                    var slimDir = args.Length >= 2 ? args[1] : AppDomain.CurrentDomain.BaseDirectory;
                    window = SlimWindow.Create(slimDir);
                }
                else
                {
                    window = MainController.Create(args);
                }
            }
            catch (Exception ex)
            {
                try { File.WriteAllText(Path.Combine(Path.GetTempPath(), "opti-slim-error.txt"), ex.ToString()); } catch { }
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
            var stream = asm.GetManifestResourceStream("OptScalerNR.Launcher." + name);
            if (stream == null)
                throw new FileNotFoundException("Missing embedded XAML " + name);
            return stream;
        }
    }
}
