# Jellyfin Missing Seasons Plugin

A Jellyfin plugin that displays missing seasons in your library as grayed-out, non-interactive indicators using TMDB metadata. Instantly see which seasons you're missing for any series.

![Missing Seasons Plugin Preview](screenshot.png)

## Features

- **Missing season detection** — Scans TMDB data to find seasons you don't have in your library
- **Grayed-out display** — Missing seasons appear with grayscale filter and "Not available" badge
- **Upcoming seasons** — Future seasons already listed on TMDB appear with an "Upcoming" badge and their release date shown at the bottom-left of the card
- **Episode count badge** — Shows the number of episodes in each missing season (using Jellyfin's native badge styling)
- **TMDB artwork** — Displays official poster art from The Movie Database
- **Adaptable display order** — Configure whether missing seasons are interleaved in their natural position or grouped after all available seasons (via plugin settings page)
- **Correct ordering** — Inserts missing seasons in chronological order among existing seasons
- **Non-interactive** — Missing season cards are unclickable and can't be played

## Requirements

- **Jellyfin 10.8+**
- Series must have TMDB metadata (automatic with default metadata providers)
- [FileTransformation plugin](https://github.com/jellyfin/jellyfin-plugin-filetransformation) installed on server (for v1.0.2+)

## Installation (Plugin Method — Recommended)

### Step 1: Add the Repository

1. Open Jellyfin **Dashboard** → **Plugins** → **Repositories**
2. Click **+ Add Repository**
3. Enter this URL:
   ```
   https://raw.githubusercontent.com/richardwerkman/jellyfin-missing-seasons-extension/main/manifest.json
   ```
4. Click **Save**

### Step 2: Install the Plugin

1. Go to **Plugins** → **Catalog**
2. Find **Missing Seasons** and click it
3. Click **Install**
4. Jellyfin will download and extract the plugin

### Step 3: Restart Jellyfin

1. Go to **Dashboard** → **Settings** (top right) → **Restart**
2. Wait for the server to restart (30-60 seconds)
3. Jellyfin will register the plugin with the FileTransformation service

### Step 4: Hard-Refresh Your Browser

After restart, do a **hard refresh** to clear the cached index.html:
- **Windows/Linux:** `Ctrl+Shift+R`
- **macOS:** `Cmd+Shift+R`

✅ **Done!** Navigate to any series with missing seasons and they should appear as grayed-out cards.

## Installation (Userscript Method — Alternative)

If you prefer a userscript instead of a server plugin:

1. Install [Tampermonkey](https://www.tampermonkey.net/) in your browser
2. Create a new script and paste the contents of [`missing-seasons.js`](missing-seasons.js) from this repo
3. Update the `@match` URL to match your Jellyfin instance:
   ```javascript
   // @match        https://your-jellyfin-server.com/*
   ```
4. Save and reload your Jellyfin web page

This method works in any browser without server changes, but requires Tampermonkey.

## How It Works

1. **Detection** — Plugin loads when you navigate to a series detail page
2. **Metadata lookup** — Reads the TMDB ID from Jellyfin's series metadata
3. **TMDB query** — Fetches season data from [The Movie Database API](https://www.themoviedb.org/)
4. **Comparison** — Compares TMDB seasons against your Jellyfin library
5. **Injection** — Creates missing season cards with TMDB artwork and inserts them in correct order
6. **Styling** — Uses Jellyfin's native `countIndicator` and `indicator` classes for episode badge (matching your theme)

## Architecture

- **Client-side JS** (`missing-seasons.js`) — Handles DOM manipulation, TMDB API calls, and card injection
- **C# Plugin** (`Jellyfin.Plugin.MissingSeasons`) — Serves the JS and manages FileTransformation integration
- **FileTransformation Plugin** — Dynamically injects the script tag into index.html at request time
- **Cache-busting middleware** — Strips conditional request headers to prevent 304 responses, ensuring the injected script is always delivered

## Uninstallation

### Plugin Method
1. Go to **Dashboard** → **Plugins**
2. Click the ⚙️ gear icon next to **Missing Seasons**
3. Click **Uninstall**
4. Restart Jellyfin

### Userscript Method
1. Open Tampermonkey dashboard
2. Click the trash icon next to "Jellyfin Missing Seasons"
3. Confirm deletion

## Troubleshooting

| Problem | Solution |
|---------|----------|
| No missing seasons appear | Check browser console (`F12`) for `[MissingSeasons]` log messages. Verify the series has TMDB metadata. |
| Script tag not in index.html | Ensure FileTransformation plugin is installed. Check Jellyfin logs for plugin startup errors. |
| Missing seasons appear but disappear on reload | Hard-refresh your browser (`Ctrl+Shift+R`) to clear cached index.html. |
| Wrong styling/colors | Hard-refresh browser. Missing seasons use Jellyfin's native indicator classes, so styling should match your theme automatically. |
| CORS errors in console | Verify you can access `https://api.themoviedb.org` from your network. Public TMDB API should be accessible. |
| Plugin says "Active" but nothing appears | Restart Jellyfin. FileTransformation plugin must fully initialize before the service is available. |

## Browser Support

- ✅ Chrome / Chromium (latest)
- ✅ Firefox (latest)
- ✅ Safari (latest)
- ✅ Edge (latest)

## Performance Notes

- **Minimal overhead** — Only activated on series detail pages
- **Network** — One TMDB API call per series (cached in memory during session)
- **Rendering** — Card injection happens once when the seasons section loads
- **MutationObserver** — Watches for dynamic content changes, with debouncing to prevent excessive re-renders

## Contributing

Issues, suggestions, and pull requests are welcome! Please open an issue on [GitHub](https://github.com/richardwerkman/jellyfin-missing-seasons-extension).

## License

MIT

## Credits

- [Jellyfin](https://jellyfin.org/) — Open-source media system
- [TMDB](https://www.themoviedb.org/) — Movie and TV data
- [FileTransformation Plugin](https://github.com/jellyfin/jellyfin-plugin-filetransformation) — Dynamic script injection
