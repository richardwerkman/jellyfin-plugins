using System.Text.RegularExpressions;
using MediaBrowser.Controller.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.MissingSeasons;

/// <summary>
/// Hosted service that injects the Missing Seasons client script into the Jellyfin web interface.
/// </summary>
public partial class IndexHtmlService : IHostedService
{
    private readonly ILogger<IndexHtmlService> _logger;
    private readonly IServerConfigurationManager _configManager;
    private const string ScriptTag = "<script plugin=\"MissingSeasons\" version=\"1.0.0.0\" src=\"/MissingSeasons/ClientScript\"></script>";

    /// <summary>
    /// Initializes a new instance of the <see cref="IndexHtmlService"/> class.
    /// </summary>
    public IndexHtmlService(ILogger<IndexHtmlService> logger, IServerConfigurationManager configManager)
    {
        _logger = logger;
        _configManager = configManager;
    }

    /// <inheritdoc />
    public Task StartAsync(CancellationToken cancellationToken)
    {
        try
        {
            InjectScript();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to inject Missing Seasons script into index.html");
        }

        return Task.CompletedTask;
    }

    /// <inheritdoc />
    public Task StopAsync(CancellationToken cancellationToken)
    {
        try
        {
            RemoveScript();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to remove Missing Seasons script from index.html");
        }

        return Task.CompletedTask;
    }

    private string? GetIndexHtmlPath()
    {
        string[] possiblePaths =
        [
            Path.Combine(_configManager.ApplicationPaths.WebPath, "index.html"),
        ];

        foreach (var path in possiblePaths)
        {
            if (File.Exists(path))
            {
                return path;
            }
        }

        _logger.LogWarning("Could not find index.html in web client directory");
        return null;
    }

    private void InjectScript()
    {
        var indexPath = GetIndexHtmlPath();
        if (indexPath == null) return;

        var html = File.ReadAllText(indexPath);

        // Check if already injected
        if (html.Contains("plugin=\"MissingSeasons\"", StringComparison.Ordinal))
        {
            _logger.LogInformation("Missing Seasons script tag already present in index.html");
            return;
        }

        // Inject before </body>
        var newHtml = html.Replace("</body>", $"    {ScriptTag}\n</body>", StringComparison.OrdinalIgnoreCase);

        if (newHtml == html)
        {
            _logger.LogWarning("Could not find </body> tag in index.html");
            return;
        }

        File.WriteAllText(indexPath, newHtml);
        _logger.LogInformation("Injected Missing Seasons script tag into {Path}", indexPath);
    }

    private void RemoveScript()
    {
        var indexPath = GetIndexHtmlPath();
        if (indexPath == null) return;

        var html = File.ReadAllText(indexPath);

        if (!html.Contains("plugin=\"MissingSeasons\"", StringComparison.Ordinal))
        {
            return;
        }

        // Remove script tag (with optional surrounding whitespace/newline)
        var newHtml = ScriptTagRegex().Replace(html, string.Empty);

        File.WriteAllText(indexPath, newHtml);
        _logger.LogInformation("Removed Missing Seasons script tag from {Path}", indexPath);
    }

    [GeneratedRegex(@"\s*<script[^>]*plugin=""MissingSeasons""[^>]*></script>\s*", RegexOptions.IgnoreCase)]
    private static partial Regex ScriptTagRegex();
}
