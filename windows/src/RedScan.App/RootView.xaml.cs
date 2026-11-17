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
        VM = new MainViewModel();
        _dispatcher = DispatcherQueue.GetForCurrentThread();
        InitializeComponent();
        VM.Toast += ShowToast;
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
