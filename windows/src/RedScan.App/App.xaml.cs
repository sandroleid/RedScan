using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace RedScan.App;

public partial class App : Application
{
    private Window? _window;
    public static IntPtr WindowHandle { get; private set; }

    public static string LogPath { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "RedScan", "startup.log");

    public App()
    {
        try { if (File.Exists(LogPath) && new FileInfo(LogPath).Length > 1_000_000) File.Delete(LogPath); } catch { }
        Log("App-Start " + typeof(App).Assembly.GetName().Version);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Fatal("Unbehandelte Ausnahme", e.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, e) => { Log("Unbeobachtete Task-Ausnahme: " + e.Exception); e.SetObserved(); };
        UnhandledException += (_, e) => { Fatal("XAML-Ausnahme", e.Exception); };

        try { InitializeComponent(); }
        catch (Exception ex) { Fatal("App.xaml konnte nicht geladen werden", ex); throw; }
        Log("App.xaml geladen");
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            ThemeService.Initialize(Environment.GetCommandLineArgs());
            _window = new MainWindow();
            WindowHandle = WinRT.Interop.WindowNative.GetWindowHandle(_window);
            _window.Activate();
            Log("Fenster angezeigt");
        }
        catch (Exception ex)
        {
            Fatal("Hauptfenster konnte nicht erstellt werden", ex);
            throw;
        }
    }

    public static void Log(string message)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
            File.AppendAllText(LogPath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}  {message}{Environment.NewLine}");
        }
        catch { }
    }

    private static bool _fatalShown;
    private static void Fatal(string what, Exception? ex)
    {
        Log($"FEHLER: {what}: {ex}");
        if (_fatalShown || Environment.GetCommandLineArgs().Contains("--no-dialogs")) return;
        _fatalShown = true;
        // Win32-Meldung, weil die XAML-Oberfläche in diesem Zustand evtl. nicht funktioniert
        MessageBoxW(IntPtr.Zero,
            $"{what}.\n\n{ex?.GetType().Name}: {ex?.Message}\n\nDetails stehen in:\n{LogPath}",
            "RedScan – Fehler beim Start", 0x10);
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);
}
