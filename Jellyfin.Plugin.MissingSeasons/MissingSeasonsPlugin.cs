using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Controller.Configuration;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.MissingSeasons;

/// <summary>
/// Missing Seasons plugin for Jellyfin.
/// </summary>
public class MissingSeasonsPlugin : BasePlugin<BasePluginConfiguration>, IHasWebPages
{
    /// <inheritdoc />
    public override string Name => "Missing Seasons";

    /// <inheritdoc />
    public override Guid Id => Guid.Parse("a4b5c6d7-1234-5678-9abc-def012345678");

    /// <inheritdoc />
    public override string Description =>
        "Shows missing seasons in a series as grayed-out indicators using TMDB data.";

    /// <summary>
    /// Gets the current plugin instance.
    /// </summary>
    public static MissingSeasonsPlugin? Instance { get; private set; }

    internal IServerConfigurationManager ServerConfigurationManager { get; }

    /// <summary>
    /// Initializes a new instance of the <see cref="MissingSeasonsPlugin"/> class.
    /// </summary>
    public MissingSeasonsPlugin(
        IApplicationPaths applicationPaths,
        IXmlSerializer xmlSerializer,
        IServerConfigurationManager configurationManager)
        : base(applicationPaths, xmlSerializer)
    {
        Instance = this;
        ServerConfigurationManager = configurationManager;
    }

    /// <inheritdoc />
    public IEnumerable<PluginPageInfo> GetPages()
    {
        return Enumerable.Empty<PluginPageInfo>();
    }
}
