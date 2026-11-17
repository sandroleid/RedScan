using Windows.Storage.Pickers;

namespace RedScan.App;

public static class FilePicker
{
    public static async Task<string?> SaveAsync(string suggestedName, string typeName, string extension)
    {
        try
        {
            var picker = new FileSavePicker
            {
                SuggestedStartLocation = PickerLocationId.Desktop,
                SuggestedFileName = suggestedName
            };
            picker.FileTypeChoices.Add(typeName, new List<string> { extension });
            // Unverpackte Apps müssen den Picker mit dem Fensterhandle verbinden.
            WinRT.Interop.InitializeWithWindow.Initialize(picker, App.WindowHandle);
            var file = await picker.PickSaveFileAsync();
            return file?.Path;
        }
        catch
        {
            return null;
        }
    }
}
