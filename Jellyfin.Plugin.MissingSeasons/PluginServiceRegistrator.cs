using Jellyfin.Plugin.MissingSeasons.Middleware;
using MediaBrowser.Controller;
using MediaBrowser.Controller.Plugins;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;

namespace Jellyfin.Plugin.MissingSeasons;

/// <summary>
/// Registers plugin services with the DI container.
/// </summary>
public class PluginServiceRegistrator : IPluginServiceRegistrator
{
    /// <inheritdoc />
    public void RegisterServices(IServiceCollection serviceCollection, IServerApplicationHost applicationHost)
    {
        // Prevent 304 responses for index.html so FileTransformation can always
        // inject our script tag into the response body.
        serviceCollection.AddSingleton<IStartupFilter, IndexHtmlCacheBustingStartupFilter>();
    }
}
