using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.UI;

namespace RedScan.App;

/// <summary>
/// Animiertes Radar mit Blips für gefundene Geräte – Nachbau der macOS-RadarView.
/// </summary>
public sealed class RadarView : Grid
{
    private static readonly Color Red = Color.FromArgb(255, 0xE8, 0x22, 0x30);
    private static readonly Color RedBright = Color.FromArgb(255, 0xFF, 0x56, 0x61);
    private static readonly Color Bg = Color.FromArgb(255, 0x0D, 0x08, 0x09);

    private const double SweepSeconds = 2.4;
    private const int SweepWedges = 90; // 90 × 2° = 180° Schweif

    private readonly Canvas _canvas = new() { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private readonly Canvas _blipLayer = new();
    private Canvas? _sweep;
    private RotateTransform? _sweepRotation;
    private Storyboard? _storyboard;
    private double _size;

    private bool _active;
    private IReadOnlyList<string> _blips = Array.Empty<string>();

    public RadarView()
    {
        Children.Add(_canvas);
        SizeChanged += (_, _) => Rebuild();
        Unloaded += (_, _) => _storyboard?.Stop();
        Loaded += (_, _) => ApplyActive();
    }

    /// <summary>Aktualisiert Sweep-Animation und Geräte-Punkte.</summary>
    public void Update(bool active, IEnumerable<string> blipIps)
    {
        _blips = blipIps.Where(ip => !string.IsNullOrWhiteSpace(ip)).Distinct().ToList();
        DrawBlips();
        if (active != _active) { _active = active; ApplyActive(); }
    }

    private static Color WithAlpha(Color c, double a) => Color.FromArgb((byte)Math.Round(Math.Clamp(a, 0, 1) * 255), c.R, c.G, c.B);

    private void Rebuild()
    {
        double s = Math.Floor(Math.Min(ActualWidth, ActualHeight));
        if (s <= 0 || Math.Abs(s - _size) < 0.5) return;
        _size = s;
        double r = s / 2;

        _storyboard?.Stop();
        _canvas.Children.Clear();
        _canvas.Width = s;
        _canvas.Height = s;

        // Hintergrund
        var bgBrush = new RadialGradientBrush
        {
            Center = new Point(0.5, 0.5),
            GradientOrigin = new Point(0.5, 0.5),
            RadiusX = 0.5,
            RadiusY = 0.5,
        };
        bgBrush.GradientStops.Add(new GradientStop { Color = WithAlpha(Red, 0.18), Offset = 0 });
        bgBrush.GradientStops.Add(new GradientStop { Color = WithAlpha(Bg, 0.2), Offset = 1 });
        _canvas.Children.Add(new Ellipse { Width = s, Height = s, Fill = bgBrush });

        // Ringe
        var ringBrush = new SolidColorBrush(WithAlpha(Red, 0.22));
        for (int i = 1; i < 5; i++)
        {
            double d = s * i / 4;
            var ring = new Ellipse { Width = d, Height = d, Stroke = ringBrush, StrokeThickness = 1 };
            Canvas.SetLeft(ring, r - d / 2);
            Canvas.SetTop(ring, r - d / 2);
            _canvas.Children.Add(ring);
        }

        // Fadenkreuz
        var lineBrush = new SolidColorBrush(WithAlpha(Red, 0.15));
        var v = new Rectangle { Width = 1, Height = s, Fill = lineBrush };
        Canvas.SetLeft(v, r - 0.5);
        var h = new Rectangle { Width = s, Height = 1, Fill = lineBrush };
        Canvas.SetTop(h, r - 0.5);
        _canvas.Children.Add(v);
        _canvas.Children.Add(h);

        // Sweep: Schweif aus Kreissegmenten mit ansteigender Deckkraft (wie AngularGradient 0 → 0,55)
        _sweep = new Canvas { Width = s, Height = s, RenderTransformOrigin = new Point(0.5, 0.5) };
        _sweepRotation = new RotateTransform();
        _sweep.RenderTransform = _sweepRotation;
        double step = 180.0 / SweepWedges;
        for (int k = 0; k < SweepWedges; k++)
        {
            double a0 = -180 + k * step;
            double a1 = a0 + step + 0.35; // leichte Überlappung gegen Haarlinien
            double alpha = 0.55 * (k + 1) / SweepWedges;
            _sweep.Children.Add(Wedge(r, a0, Math.Min(a1, 0), new SolidColorBrush(WithAlpha(RedBright, alpha))));
        }
        _canvas.Children.Add(_sweep);

        var anim = new DoubleAnimation
        {
            From = 0,
            To = 360,
            Duration = new Duration(TimeSpan.FromSeconds(SweepSeconds)),
            RepeatBehavior = RepeatBehavior.Forever,
        };
        Storyboard.SetTarget(anim, _sweepRotation);
        Storyboard.SetTargetProperty(anim, "Angle");
        _storyboard = new Storyboard();
        _storyboard.Children.Add(anim);

        // Blips
        _blipLayer.Width = s;
        _blipLayer.Height = s;
        _canvas.Children.Add(_blipLayer);
        DrawBlips();

        // Eigene Position in der Mitte
        AddDot(_canvas, r, r, 13, WithAlpha(Red, 0.35));
        AddDot(_canvas, r, r, 5, Color.FromArgb(255, 255, 255, 255));

        ApplyActive();
    }

    private static Path Wedge(double r, double fromDeg, double toDeg, Brush fill)
    {
        static Point P(double r, double deg) =>
            new(r + r * Math.Cos(deg * Math.PI / 180), r + r * Math.Sin(deg * Math.PI / 180));

        var fig = new PathFigure { StartPoint = new Point(r, r), IsClosed = true, IsFilled = true };
        fig.Segments.Add(new LineSegment { Point = P(r, fromDeg) });
        fig.Segments.Add(new ArcSegment
        {
            Point = P(r, toDeg),
            Size = new Size(r, r),
            SweepDirection = SweepDirection.Clockwise,
            IsLargeArc = false,
        });
        var geo = new PathGeometry();
        geo.Figures.Add(fig);
        return new Path { Data = geo, Fill = fill };
    }

    private static void AddDot(Canvas target, double x, double y, double d, Color c)
    {
        var e = new Ellipse { Width = d, Height = d, Fill = new SolidColorBrush(c) };
        Canvas.SetLeft(e, x - d / 2);
        Canvas.SetTop(e, y - d / 2);
        target.Children.Add(e);
    }

    private void DrawBlips()
    {
        _blipLayer.Children.Clear();
        if (_size <= 0) return;
        double r = _size / 2;
        foreach (var ip in _blips)
        {
            var p = Position(ip, _size);
            AddDot(_blipLayer, r + p.X, r + p.Y, 12, WithAlpha(RedBright, 0.28)); // Leuchten
            AddDot(_blipLayer, r + p.X, r + p.Y, 6, RedBright);
        }
    }

    private void ApplyActive()
    {
        if (_sweep == null || _storyboard == null) return;
        if (_active)
        {
            _sweep.Visibility = Visibility.Visible;
            _storyboard.Begin();
        }
        else
        {
            _storyboard.Stop();
            _sweep.Visibility = Visibility.Collapsed;
        }
    }

    /// <summary>Gleiche Verteilung wie macOS: goldener Winkel nach letztem Oktett.</summary>
    public static Point Position(string ip, double size)
    {
        var last = ip.Split('.').LastOrDefault();
        double n = int.TryParse(last, out var v) ? v : 1;
        double a = n * 2.399963;
        double rr = (0.22 + (n % 11) / 15) * size / 2;
        return new Point(Math.Cos(a) * rr, Math.Sin(a) * rr);
    }
}
