using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;

namespace Jellyfin.Plugin.MissingSeasons.Middleware;

/// <summary>
/// Startup filter that adds middleware to prevent conditional 304 responses for index.html.
/// This ensures the FileTransformation plugin can always patch the response body.
/// Without this, browsers may receive 304 Not Modified and use a stale cached version
/// of index.html that does not include the injected script tag.
/// </summary>
public class IndexHtmlCacheBustingStartupFilter : IStartupFilter
{
    /// <inheritdoc />
    public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next)
    {
        return app =>
        {
            app.Use(async (context, nextMiddleware) =>
            {
                var path = context.Request.Path.Value;
                if (path is not null && path.EndsWith("index.html", StringComparison.OrdinalIgnoreCase))
                {
                    // Remove conditional request headers so the static file middleware
                    // always returns 200 with the full response body.
                    // This allows the FileTransformation plugin to inject our script tag.
                    context.Request.Headers.Remove("If-Modified-Since");
                    context.Request.Headers.Remove("If-None-Match");

                    // Tell the browser not to cache index.html, so it always gets
                    // the latest (patched) version from the server.
                    context.Response.OnStarting(() =>
                    {
                        context.Response.Headers["Cache-Control"] = "no-store, no-cache, must-revalidate";
                        context.Response.Headers.Remove("Last-Modified");
                        context.Response.Headers.Remove("ETag");
                        return Task.CompletedTask;
                    });
                }

                await nextMiddleware();
            });

            next(app);
        };
    }
}
