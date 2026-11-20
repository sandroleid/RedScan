using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using RedScan.Core;

namespace RedScan.App;

public sealed partial class RootView : UserControl
{
    public MainViewModel VM { get; }
    private readonly DispatcherQueue _dispatcher;

    public RootView()
    {
        App.Log("Oberfläche wird aufgebaut");
        VM = new MainViewModel();
        _dispatcher = DispatcherQueue.GetForCurrentThread();
        InitializeComponent();
        VM.Toast += ShowToast;
        Loaded += OnLoaded;
        VM.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(MainViewModel.IsScanning) or nameof(MainViewModel.DeviceCount))
                UpdateRadar();
        };
        Loaded += (_, _) => UpdateRadar();
        App.Log("Oberfläche aufgebaut");
    }

    /// <summary>Kommandozeile: --autoscan startet sofort einen Scan, --dump &lt;Pfad&gt; speichert das Ergebnis als JSON.</summary>
    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        var args = Environment.GetCommandLineArgs();
        if (!args.Contains("--autoscan")) return;
        int t = Array.IndexOf(args, "--target");
        if (t >= 0 && t + 1 < args.Length) VM.CustomTarget = args[t + 1];
        App.Log($"Autoscan gestartet (Ziel: {VM.NetCidr})");
        try
        {
            await VM.StartAsync();
            App.Log($"Autoscan fertig: {VM.DeviceCount} Geräte, {VM.TotalOpenPorts} offene Ports");
            int i = Array.IndexOf(args, "--dump");
            if (i >= 0 && i + 1 < args.Length)
            {
                VM.DumpJson(args[i + 1]);
                App.Log("Ergebnis gespeichert: " + args[i + 1]);
            }
        }
        catch (Exception ex) { App.Log("Autoscan-Fehler: " + ex); }
    }

    private void UpdateRadar()
    {
        if (_dispatcher.HasThreadAccess) Radar.Update(VM.IsScanning, VM.RadarBlips);
        else _dispatcher.TryEnqueue(() => Radar.Update(VM.IsScanning, VM.RadarBlips));
    }

    private void OnShowDevices(object sender, RoutedEventArgs e) => VM.ShowHistory = false;
    private void OnShowHistory(object sender, RoutedEventArgs e) => VM.ShowHistory = true;
    private void OnCloseDetail(object sender, RoutedEventArgs e) => VM.SelectedDevice = null;

    private void OnSearchChanged(object sender, TextChangedEventArgs e)
    {
        if (sender is TextBox tb) VM.SearchText = tb.Text;
    }

    private void OnDeviceSelected(object sender, SelectionChangedEventArgs e)
    {
        if (e.AddedItems.Count > 0 && e.AddedItems[0] is Device d) VM.Select(d);
    }

    private void OnWakeKnown(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is KnownDevice k)
            VM.WakeKnownCommand.Execute(k);
    }

    private DispatcherQueueTimer? _toastTimer;
    private void ShowToast(string text)
    {
        _dispatcher.TryEnqueue(() =>
        {
            ToastText.Text = text;
            ToastHost.Visibility = Visibility.Visible;
            _toastTimer?.Stop();
            _toastTimer = _dispatcher.CreateTimer();
            _toastTimer.Interval = TimeSpan.FromSeconds(3.5);
            _toastTimer.IsRepeating = false;
            _toastTimer.Tick += (_, _) => ToastHost.Visibility = Visibility.Collapsed;
            _toastTimer.Start();
        });
    }
}
