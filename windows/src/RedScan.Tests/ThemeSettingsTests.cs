using RedScan.Core;
using Xunit;

namespace RedScan.Tests;

public sealed class ThemeSettingsTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "redscan-tests-" + Guid.NewGuid().ToString("N"));
    private string SettingsPath => Path.Combine(_dir, "settings.json");

    public void Dispose()
    {
        try { Directory.Delete(_dir, true); } catch { }
    }

    [Fact]
    public void Load_MissingFile_DefaultsToDark()
        => Assert.Equal(AppTheme.Dark, ThemeSettings.Load(SettingsPath));

    [Theory]
    [InlineData("kaputt {")]
    [InlineData("")]
    [InlineData("[1,2]")]
    [InlineData("{ \"theme\": \"blau\" }")]
    [InlineData("{ \"theme\": 3 }")]
    [InlineData("{ }")]
    public void Load_InvalidContent_DefaultsToDark(string content)
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(SettingsPath, content);
        Assert.Equal(AppTheme.Dark, ThemeSettings.Load(SettingsPath));
    }

    [Theory]
    [InlineData(AppTheme.Light)]
    [InlineData(AppTheme.Dark)]
    public void SaveThenLoad_RoundTrips(AppTheme theme)
    {
        ThemeSettings.Save(SettingsPath, theme);
        Assert.Equal(theme, ThemeSettings.Load(SettingsPath));
    }

    [Fact]
    public void Save_WritesExpectedJson()
    {
        ThemeSettings.Save(SettingsPath, AppTheme.Light);
        Assert.Contains("\"theme\": \"light\"", File.ReadAllText(SettingsPath));
    }

    [Fact]
    public void Save_KeepsOtherKeys_AndOverwritesBrokenFile()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(SettingsPath, "{ \"other\": 42, \"theme\": \"dark\" }");
        ThemeSettings.Save(SettingsPath, AppTheme.Light);
        var text = File.ReadAllText(SettingsPath);
        Assert.Contains("\"other\": 42", text);
        Assert.Equal(AppTheme.Light, ThemeSettings.Load(SettingsPath));

        File.WriteAllText(SettingsPath, "kaputt");
        ThemeSettings.Save(SettingsPath, AppTheme.Light);
        Assert.Equal(AppTheme.Light, ThemeSettings.Load(SettingsPath));
    }

    [Fact]
    public void Load_IsCaseInsensitive()
    {
        Directory.CreateDirectory(_dir);
        File.WriteAllText(SettingsPath, "{ \"theme\": \"LIGHT\" }");
        Assert.Equal(AppTheme.Light, ThemeSettings.Load(SettingsPath));
    }

    [Fact]
    public void FromArgs_ParsesThemeOption()
    {
        Assert.Equal(AppTheme.Light, ThemeSettings.FromArgs(new[] { "RedScan.exe", "--autoscan", "--theme", "light" }));
        Assert.Equal(AppTheme.Dark, ThemeSettings.FromArgs(new[] { "--theme", "dark" }));
        Assert.Null(ThemeSettings.FromArgs(new[] { "--theme" }));
        Assert.Null(ThemeSettings.FromArgs(new[] { "--theme", "rot" }));
        Assert.Null(ThemeSettings.FromArgs(Array.Empty<string>()));
    }

    [Fact]
    public void FromArgs_DoesNotTouchStoredValue()
    {
        ThemeSettings.Save(SettingsPath, AppTheme.Dark);
        _ = ThemeSettings.FromArgs(new[] { "--theme", "light" });
        Assert.Equal(AppTheme.Dark, ThemeSettings.Load(SettingsPath));
    }
}
