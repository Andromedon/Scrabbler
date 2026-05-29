using UIKit;

namespace Scrabbler.Maui.Services;

public sealed class IosBackgroundTaskService : IBackgroundTaskService
{
    public async Task RunAsync(string name, Func<CancellationToken, Task> operation, CancellationToken cancellationToken = default)
    {
        await RunAsync<object?>(name, async token =>
        {
            await operation(token);
            return null;
        }, cancellationToken);
    }

    public async Task<T> RunAsync<T>(string name, Func<CancellationToken, Task<T>> operation, CancellationToken cancellationToken = default)
    {
        using var expiration = new CancellationTokenSource();
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, expiration.Token);
        var taskId = UIApplication.BackgroundTaskInvalid;
        var gate = new object();

        taskId = await MainThread.InvokeOnMainThreadAsync(() =>
            UIApplication.SharedApplication.BeginBackgroundTask(name, () =>
            {
                expiration.Cancel();
                EndBackgroundTask(ref taskId, gate);
            }));

        try
        {
            return await operation(linked.Token);
        }
        finally
        {
            EndBackgroundTask(ref taskId, gate);
        }
    }

    private static void EndBackgroundTask(ref nint taskId, object gate)
    {
        nint idToEnd;
        lock (gate)
        {
            if (taskId == UIApplication.BackgroundTaskInvalid)
            {
                return;
            }

            idToEnd = taskId;
            taskId = UIApplication.BackgroundTaskInvalid;
        }

        MainThread.BeginInvokeOnMainThread(() => UIApplication.SharedApplication.EndBackgroundTask(idToEnd));
    }
}
