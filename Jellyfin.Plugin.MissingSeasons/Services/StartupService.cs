using System.Reflection;
using System.Runtime.Loader;
using Jellyfin.Plugin.MissingSeasons.Helpers;
using MediaBrowser.Model.Tasks;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;

namespace Jellyfin.Plugin.MissingSeasons.Services;

/// <summary>
/// Scheduled task that runs on startup to register the Missing Seasons script
/// with the FileTransformation plugin for index.html injection.
/// </summary>
public class StartupService : IScheduledTask
{
    private readonly ILogger<StartupService> _logger;

    /// <inheritdoc />
    public string Name => "MissingSeasons Startup";

    /// <inheritdoc />
    public string Key => "Jellyfin.Plugin.MissingSeasons.Startup";

    /// <inheritdoc />
    public string Description => "Registers Missing Seasons script injection with FileTransformation plugin";

    /// <inheritdoc />
    public string Category => "Startup Services";

    /// <summary>
    /// Initializes a new instance of the <see cref="StartupService"/> class.
    /// </summary>
    public StartupService(ILogger<StartupService> logger)
    {
        _logger = logger;
    }

    /// <inheritdoc />
    public Task ExecuteAsync(IProgress<double> progress, CancellationToken cancellationToken)
    {
        var payload = new JObject
        {
            { "id", "b1c2d3e4-5678-9abc-def0-123456789abc" },
            { "fileNamePattern", "index.html" },
            { "callbackAssembly", GetType().Assembly.FullName },
            { "callbackClass", typeof(IndexHtmlInjector).FullName },
            { "callbackMethod", nameof(IndexHtmlInjector.FileTransformer) }
        };

        Assembly? fileTransformationAssembly =
            AssemblyLoadContext.All.SelectMany(x => x.Assemblies)
                .FirstOrDefault(x => x.FullName?.Contains(".FileTransformation") ?? false);

        if (fileTransformationAssembly == null)
        {
            _logger.LogWarning("FileTransformation plugin not found. Missing Seasons script injection unavailable.");
            return Task.CompletedTask;
        }

        Type? pluginInterfaceType = fileTransformationAssembly
            .GetType("Jellyfin.Plugin.FileTransformation.PluginInterface");

        if (pluginInterfaceType == null)
        {
            _logger.LogWarning("FileTransformation PluginInterface type not found. Missing Seasons script injection unavailable.");
            return Task.CompletedTask;
        }

        _logger.LogInformation("Registering Missing Seasons for FileTransformation plugin.");
        pluginInterfaceType.GetMethod("RegisterTransformation")?.Invoke(null, [payload]);

        return Task.CompletedTask;
    }

    /// <inheritdoc />
    public IEnumerable<TaskTriggerInfo> GetDefaultTriggers()
    {
        yield return new TaskTriggerInfo
        {
            Type = TaskTriggerInfoType.StartupTrigger
        };
    }
}
