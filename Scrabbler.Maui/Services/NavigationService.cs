namespace Scrabbler.Maui.Services;

public sealed class NavigationService
{
    public async Task PushAsync(Page page)
    {
        var navigation = CurrentNavigation;
        if (navigation is not null)
        {
            await navigation.PushAsync(page);
        }
    }

    public async Task PopToRootAsync()
    {
        var navigation = CurrentNavigation;
        if (navigation is not null)
        {
            await navigation.PopToRootAsync();
        }
    }

    private static INavigation? CurrentNavigation
    {
        get
        {
            var page = Application.Current?.Windows.FirstOrDefault()?.Page;
            return page?.Navigation;
        }
    }
}
