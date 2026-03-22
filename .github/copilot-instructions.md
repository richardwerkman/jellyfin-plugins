# Jellyfin Missing Seasons — Copilot Instructions

## Project Overview

A Jellyfin server plugin that injects client-side JavaScript to display missing seasons as grayed-out cards using TMDB metadata. Zero configuration — just install via repository and restart.

- **Current version**: 1.0.4.0
- **Target framework**: .NET 9 / `net9.0`
- **Plugin GUID**: `a4b5c6d7-1234-5678-9abc-def012345678` (dashes stripped in some API calls: `a4b5c6d7123456789abcdef012345678`)
- **Plugin name**: `Missing Seasons`
- **Repository manifest URL**: `https://raw.githubusercontent.com/richardwerkman/jellyfin-missing-seasons-extension/main/manifest.json`
- **GitHub repo**: `https://github.com/richardwerkman/jellyfin-missing-seasons-extension`

---

## Architecture

```
missing-seasons.js (userscript alternative, root)
Jellyfin.Plugin.MissingSeasons/
├── MissingSeasonsPlugin.cs           — Plugin registration, GUID, version
├── Jellyfin.Plugin.MissingSeasons.csproj
├── Middleware/
│   └── IndexHtmlCacheBustingStartupFilter.cs  — IStartupFilter, added v1.0.2.0
├── Services/
│   └── StartupService.cs            — IScheduledTask, registers with FileTransformation
├── Web/
│   └── missing-seasons.js           — Embedded resource, served at /MissingSeasons/ClientScript
artifacts/
├── missing-seasons-1.0.1.0.zip  …
└── missing-seasons-1.0.4.0.zip
scripts/
├── deploy-local.sh    — Spin up a local Jellyfin Docker instance for development
└── release.sh         — Build, package, update manifest, commit, tag, and push
local-dev/             — Gitignored; created by deploy-local.sh
├── config/            — Jellyfin config & plugin DLL
└── media/shows/       — Stub test media (Breaking Bad S1+S3)
manifest.json          — Jellyfin plugin repository manifest
README.md
```

### Key Components

**`missing-seasons.js`** (embedded resource)
- Entry point: `init()` — hooks into `viewshow`, `hashchange`, MutationObserver
- `processSeries(itemId)` — orchestrates TMDB + Jellyfin API calls
- `buildMissingSeasonCard(season)` — creates DOM card with TMDB poster
- `injectMissingSeasons(cards)` — inserts cards in chronological order
- Episode count badge uses native Jellyfin classes: `<div class="cardIndicators"><div class="countIndicator indicator">N</div></div>`
- Missing cards get CSS classes: `card missing-season-card`; pointer-events disabled
- CSS style: `.missing-season-card .cardIndicators { pointer-events: none !important; }`

**`IndexHtmlCacheBustingStartupFilter.cs`** (added v1.0.2.0)
- Implements `IStartupFilter`
- Strips `If-Modified-Since` and `If-None-Match` headers from `index.html` requests
- Sets `Cache-Control: no-store` on responses; removes `Last-Modified` and `ETag`
- Purpose: Prevents 304 responses that bypass FileTransformation injection

**`StartupService.cs`**
- Registers the plugin's JS with the FileTransformation plugin on startup
- Injects `<script src="/MissingSeasons/ClientScript"></script>` into `index.html`

---

## TMDB API

- Uses Jellyfin's internal/public TMDB API key
- Endpoint pattern: `https://api.themoviedb.org/3/tv/{tmdbId}/season/{n}?api_key={key}`
- TMDB poster URL: `https://image.tmdb.org/t/p/w300{poster_path}`

---

## Build & Release Process

Important! Only release when explicitly asked.

Use the release script — it handles everything automatically:

```bash
./scripts/release.sh <version> "<changelog>"
# Example:
./scripts/release.sh 1.0.5.0 "Fix episode count badge on Jellyfin 10.12"
```

What the script does:
1. Validates the working tree is clean and version doesn't already exist
2. Bumps `AssemblyVersion`, `FileVersion`, and `Version` in `.csproj`
3. Builds Release
4. Packages `artifacts/missing-seasons-<version>.zip`
5. Computes MD5 checksum
6. Prepends the new entry to `manifest.json`
7. Commits, tags `v<version>`, and pushes both to origin

**Prerequisites**: clean working tree, no uncommitted changes.

### Manual process (if script unavailable)

1. Edit version in `.csproj` (3 fields: `AssemblyVersion`, `FileVersion`, `Version`)
2. `dotnet build -c Release Jellyfin.Plugin.MissingSeasons/Jellyfin.Plugin.MissingSeasons.csproj`
3. `zip -j artifacts/missing-seasons-X.X.X.X.zip Jellyfin.Plugin.MissingSeasons/bin/Release/net9.0/Jellyfin.Plugin.MissingSeasons.dll`
4. `md5 -q artifacts/missing-seasons-X.X.X.X.zip` → paste checksum into `manifest.json`
5. Prepend new version entry to `manifest.json` `versions` array; `sourceUrl` points to `https://github.com/richardwerkman/jellyfin-missing-seasons-extension/raw/main/artifacts/`
6. `git add .csproj artifacts/ manifest.json && git commit -m "vX.X.X.X: ..." && git push origin main`

---

## Local Development (Docker)

Spin up an isolated Jellyfin instance on `http://localhost:8097` with test media pre-loaded:

```bash
./scripts/deploy-local.sh
```

Prerequisites: Docker CLI + colima (`brew install docker colima && colima start`).

What it does:
1. Detects/starts colima or Docker Desktop automatically
2. Builds the plugin (Release)
3. Creates `local-dev/media/shows/Breaking Bad (2008)/` with stub S1+S3 episodes (S2, S4, S5 will show as missing in the plugin)
4. Copies the built DLL to `local-dev/config/plugins/MissingSeasons_<version>/`
5. Starts `jellyfin/jellyfin:latest` as `jellyfin-missing-seasons-test` on port 8097
6. Attempts to auto-complete the setup wizard; if that fails (Jellyfin 10.11 requires a browser session), prompts for manual wizard completion
7. Adds the TV Shows library pointing at `/media/shows`

**One-time manual wizard step** (first run only):
Jellyfin 10.11+ protects wizard endpoints with a session token, so the script falls back to manual setup:
1. Open http://localhost:8097 in a browser
2. Complete the 5-step wizard — username: `admin`, password: `admin123`, library: Shows → `/media/shows`
3. Re-run the script — it will detect the completed wizard and skip the setup

After the library scan finishes, open Breaking Bad in the Jellyfin UI — seasons 2, 4, and 5 should appear as missing.

**FileTransformation note**: script injection via the server's FileTransformation plugin requires that plugin to also be installed in the local instance. For functional testing without it, you can verify the plugin JS logic by injecting the script manually in browser devtools: `fetch('/MissingSeasons/ClientScript').then(r=>r.text()).then(t=>eval(t))`

```bash
# Stop
docker rm -f jellyfin-missing-seasons-test

# Rebuild plugin and redeploy
./scripts/deploy-local.sh

# Follow logs
docker logs -f jellyfin-missing-seasons-test
```

`local-dev/` is gitignored — config, DLL, and media are never committed.

---

## Deployment to Jellyfin Server

Install Jellyfin Missing Seasons on your local Jellyfin server

### Install plugin via API
```bash
curl -s -o /dev/null -w "%{http_code}" -X POST \
  "{{serverinstance}}/Packages/Installed/Missing%20Seasons?assemblyGuid=a4b5c6d7123456789abcdef012345678&version=1.0.X.0&repositoryUrl=https%3A%2F%2Fraw.githubusercontent.com%2Frichardwerkman%2Fjellyfin-missing-seasons-extension%2Fmain%2Fmanifest.json" \
  -H "Authorization: MediaBrowser Token=\"<API_KEY>\""
```

### Restart server
```bash
curl -s -o /dev/null -w "%{http_code}" -X POST \
  "{{serverinstance}}/System/Restart" \
  -H "Authorization: MediaBrowser Token=\"<API_KEY>\""
```

### Verify active
```bash
sleep 30 && curl -s "{{serverinstance}}/Plugins" \
  -H "Authorization: MediaBrowser Token=\"<API_KEY>\"" | \
  python3 -c "import sys,json; [print(p['Name'],'v'+p['Version'],'-',p['Status']) for p in json.load(sys.stdin) if 'Missing' in p.get('Name','')]"
```

---

## Jellyfin Native Styling

Episode count badges must use native Jellyfin classes to match theme styling:
```html
<div class="cardIndicators">
  <div class="countIndicator indicator">N</div>
</div>
```
- `cardIndicators` — absolute-positioned container (top-right of card image), from `indicators.scss`
- `countIndicator indicator` — circular badge, theme accent color, from `indicators.scss`
- Source: `jellyfin-web/v10.11.6/src/components/indicators/indicators.scss` and `cardBuilder.js`

Do **not** use custom hardcoded colors (e.g., `#00a4dc`) — always use native classes.

---

## Known Issues / Gotchas

- If `If-Modified-Since` / `If-None-Match` headers are not stripped from `index.html` requests, Jellyfin returns a 304, and FileTransformation never gets to inject the `<script>` tag. The cache-busting middleware fixes this.
- FileTransformation plugin must be installed and initialized before `StartupService` runs. If missing, the script tag won't be injected.
- Plugin GUID in code (`Plugin.cs`) must match the GUID in `manifest.json`.
- The `manifest.json` `checksum` field must be the **MD5** hash (not SHA256) of the zip file. Use `md5 -q` on macOS.
- When testing with Playwright/headless Chrome, set `localStorage` with Jellyfin credentials before navigating to series pages.
