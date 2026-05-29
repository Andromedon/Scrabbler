namespace Scrabbler.Maui.Services;

public interface IBackgroundTaskService
{
    Task RunAsync(string name, Func<CancellationToken, Task> operation, CancellationToken cancellationToken = default);

    Task<T> RunAsync<T>(string name, Func<CancellationToken, Task<T>> operation, CancellationToken cancellationToken = default);
}
