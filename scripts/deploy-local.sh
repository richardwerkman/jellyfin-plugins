#!/usr/bin/env bash
# deploy-local.sh — Spin up a local Jellyfin instance for plugin development.
#
# What it does:
#   1. Ensures Docker Desktop is installed and running
#   2. Builds the plugin (Release)
#   3. Creates stub test media: Breaking Bad with S1+S3 present (S2, S4, S5 missing)
#   4. Copies the plugin DLL into local-dev/config/plugins/
#   5. Starts Jellyfin in a Docker container on http://localhost:8097
#   6. Auto-completes the setup wizard (admin / admin123)
#   7. Adds a TV Shows library pointing at the test media
#
# Re-running this script will rebuild the plugin, update the local DLL,
# and restart the container with the latest code.
#
# Usage:
#   ./scripts/deploy-local.sh
#
# Stop the container:
#   docker rm -f jellyfin-missing-seasons-test

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_DEV_DIR="$REPO_ROOT/local-dev"
CONFIG_DIR="$LOCAL_DEV_DIR/config"
MEDIA_DIR="$LOCAL_DEV_DIR/media"
JELLYFIN_PORT=8097
CONTAINER_NAME="jellyfin-missing-seasons-test"
ADMIN_USER="admin"
ADMIN_PASS="admin123"

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { echo "▶ $*"; }
err()  { echo "✗ $*" >&2; exit 1; }
ok()   { echo "✔ $*"; }

get_version() {
  grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
    "$REPO_ROOT/Jellyfin.Plugin.MissingSeasons/Jellyfin.Plugin.MissingSeasons.csproj" \
    | head -1
}

# ── Step 1: Docker ────────────────────────────────────────────────────────────

check_docker() {
  # Install docker CLI if missing
  if ! command -v docker &>/dev/null; then
    if command -v brew &>/dev/null; then
      log "Docker CLI not found — installing docker + colima via Homebrew..."
      brew install docker colima
    else
      err "Docker is not installed. Install it from https://www.docker.com/products/docker-desktop/ and re-run."
    fi
  fi

  # If docker daemon is already reachable, nothing to do
  if docker info &>/dev/null 2>&1; then
    return
  fi

  # Try colima first (lightweight, no GUI needed)
  if command -v colima &>/dev/null; then
    local colima_status
    colima_status=$(colima status 2>&1 || true)
    if echo "$colima_status" | grep -q "Running"; then
      ok "Colima already running."
    else
      log "Starting colima runtime..."
      colima start --cpu 2 --memory 4
    fi
    return
  fi

  # Fall back to Docker Desktop
  if [[ -d "/Applications/Docker.app" ]]; then
    log "Starting Docker Desktop..."
    open /Applications/Docker.app
    local i
    for i in $(seq 1 45); do
      sleep 2
      if docker info &>/dev/null 2>&1; then
        ok "Docker Desktop is ready."
        return
      fi
    done
    err "Docker Desktop did not start within 90 s. Start it manually and re-run."
  fi

  err "No Docker runtime found. Run: brew install docker colima && colima start"
}

# ── Step 2: Build plugin ──────────────────────────────────────────────────────

build_plugin() {
  log "Building plugin (Release)..."
  dotnet build -c Release \
    "$REPO_ROOT/Jellyfin.Plugin.MissingSeasons/Jellyfin.Plugin.MissingSeasons.csproj" \
    --nologo -v q
  ok "Plugin built (v$(get_version))."
}

# ── Step 3: Test media ────────────────────────────────────────────────────────
# Breaking Bad has 5 seasons on TMDB (tmdbid=1396).
# We put S1 and S3 on disk so S2, S4 and S5 appear as missing in the plugin.

create_test_media() {
  local show_dir="$MEDIA_DIR/shows/Breaking Bad (2008)"
  if [[ -d "$show_dir" ]]; then
    ok "Test media already exists (skipping)."
    return
  fi

  log "Creating test media — Breaking Bad S1+S3 (S2, S4, S5 will show as missing)..."
  mkdir -p "$show_dir/Season 01" "$show_dir/Season 03"

  for ep in 01 02 03 04 05 06 07; do
    touch "$show_dir/Season 01/Breaking Bad S01E${ep}.mkv"
  done
  for ep in 01 02 03 04 05 06 07 08 09 10 11 12 13; do
    touch "$show_dir/Season 03/Breaking Bad S03E${ep}.mkv"
  done
  ok "Test media created."

  # The Boys (TMDB id: 76479) — S1-S3 on disk; S4 missing; S5 upcoming 2026-04-07
  local boys_dir="$MEDIA_DIR/shows/The Boys (2019)"
  log "Creating test media — The Boys S1-S3 (S4 missing, S5 upcoming 2026-04-07)..."
  mkdir -p "$boys_dir/Season 01" "$boys_dir/Season 02" "$boys_dir/Season 03"

  for ep in 01 02 03 04 05 06 07 08; do
    touch "$boys_dir/Season 01/The Boys S01E${ep}.mkv"
  done
  for ep in 01 02 03 04 05 06 07 08; do
    touch "$boys_dir/Season 02/The Boys S02E${ep}.mkv"
  done
  for ep in 01 02 03 04 05 06 07 08; do
    touch "$boys_dir/Season 03/The Boys S03E${ep}.mkv"
  done
  ok "The Boys test media created."
}

# ── Step 4a: Ensure FileTransformation plugin is installed ────────────────────
# The Missing Seasons plugin requires the FileTransformation plugin from
# IAmParadox27 to inject its client script into index.html.

ensure_file_transformation_plugin() {
  local ft_version="2.5.5.0"
  local ft_dir="$CONFIG_DIR/plugins/FileTransformation_${ft_version}"
  local ft_dll="$ft_dir/Jellyfin.Plugin.FileTransformation.dll"

  if [[ -f "$ft_dll" ]]; then
    ok "FileTransformation plugin already installed."
    return
  fi

  log "Downloading FileTransformation plugin v${ft_version}..."
  mkdir -p "$ft_dir"
  local zip_url="https://github.com/IAmParadox27/jellyfin-plugin-file-transformation/releases/download/${ft_version}/Release-10.10.7.zip"
  local tmp_zip
  tmp_zip=$(mktemp /tmp/ft-plugin-XXXXXX.zip)

  if ! curl -sfL "$zip_url" -o "$tmp_zip"; then
    err "Failed to download FileTransformation plugin. Check your internet connection."
  fi

  if ! unzip -p "$tmp_zip" Jellyfin.Plugin.FileTransformation.dll > "$ft_dll"; then
    err "Failed to extract FileTransformation plugin DLL."
  fi

  rm -f "$tmp_zip"
  ok "FileTransformation plugin installed."
}

# ── Step 4b: Copy plugin DLL ──────────────────────────────────────────────────

copy_plugin() {
  local version
  version=$(get_version)
  local plugin_dir="$CONFIG_DIR/plugins/MissingSeasons_${version}"
  local dll_src="$REPO_ROOT/Jellyfin.Plugin.MissingSeasons/bin/Release/net9.0/Jellyfin.Plugin.MissingSeasons.dll"

  # Remove any old plugin version directories to avoid ambiguous route conflicts
  for old_dir in "$CONFIG_DIR/plugins/MissingSeasons_"*/; do
    if [[ "$old_dir" != "${plugin_dir}/" ]]; then
      rm -rf "$old_dir"
    fi
  done

  mkdir -p "$plugin_dir"
  cp "$dll_src" "$plugin_dir/"
  ok "Plugin DLL v${version} ready in local-dev."
}

# ── Step 5: Start Jellyfin ────────────────────────────────────────────────────

start_jellyfin() {
  docker rm -f "$CONTAINER_NAME" &>/dev/null || true

  mkdir -p "$CONFIG_DIR"
  log "Starting Jellyfin container..."
  docker run -d \
    --name "$CONTAINER_NAME" \
    -p "${JELLYFIN_PORT}:8096" \
    -v "${CONFIG_DIR}:/config" \
    -v "${MEDIA_DIR}:/media:ro" \
    -e JELLYFIN_PublishedServerUrl="http://localhost:${JELLYFIN_PORT}" \
    jellyfin/jellyfin:latest \
    > /dev/null

  ok "Container started."
}

# ── Step 6: Wait for readiness ────────────────────────────────────────────────

wait_for_jellyfin() {
  log "Waiting for Jellyfin to be ready..."
  local base="http://localhost:${JELLYFIN_PORT}"
  local i
  for i in $(seq 1 40); do
    sleep 3
    if curl -sf "${base}/health" &>/dev/null; then
      # Give startup tasks a moment to fully complete before touching wizard endpoints
      sleep 5
      ok "Jellyfin is ready."
      return
    fi
  done
  err "Jellyfin did not start within 2 min. Check logs: docker logs $CONTAINER_NAME"
}

# Wait for the /Startup/User endpoint to accept requests (not blocked by startup middleware)
wait_for_startup_endpoints() {
  local base="http://localhost:${JELLYFIN_PORT}"
  local i
  for i in $(seq 1 20); do
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "${base}/Startup/Configuration")
    if [[ "$http_code" == "200" ]]; then
      return
    fi
    sleep 2
  done
}

# ── Step 7: Auto-configure (wizard + library) ─────────────────────────────────

configure_jellyfin() {
  local base="http://localhost:${JELLYFIN_PORT}"

  # Check if setup wizard still needs completing
  local wizard_done
  wizard_done=$(curl -sf "${base}/System/Info/Public" \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('StartupWizardCompleted',True))" \
    2>/dev/null || echo "True")

  if [[ "$wizard_done" == "False" ]]; then
    log "Completing setup wizard..."

    # Wait until startup controller endpoints are no longer blocked
    wait_for_startup_endpoints

    curl -sf -X POST "${base}/Startup/Configuration" \
      -H "Content-Type: application/json" \
      -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}' \
      &>/dev/null || true

    # Retry /Startup/User until it succeeds (can still be blocked briefly)
    local user_ok="false"
    local u
    for u in $(seq 1 10); do
      local code
      code=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${base}/Startup/User" \
        -H "Content-Type: application/json" \
        -d "{\"Name\":\"${ADMIN_USER}\",\"Password\":\"${ADMIN_PASS}\"}")
      if [[ "$code" == "204" || "$code" == "200" ]]; then
        user_ok="true"
        break
      fi
      sleep 2
    done

    if [[ "$user_ok" != "true" ]]; then
      log "Warning: could not set admin credentials via API — you may need to complete the wizard manually."
    fi

    curl -sf -X POST "${base}/Startup/Complete" &>/dev/null || true
    sleep 2
    ok "Setup wizard completed."
  fi

  # Authenticate
  local auth_json token
  auth_json=$(curl -sf -X POST "${base}/Users/AuthenticateByName" \
    -H "Content-Type: application/json" \
    -H 'X-Emby-Authorization: MediaBrowser Client="LocalDeploy", Device="Script", DeviceId="localdeploy", Version="1.0"' \
    -d "{\"Username\":\"${ADMIN_USER}\",\"Pw\":\"${ADMIN_PASS}\"}" \
    2>/dev/null || echo "")

  token=$(echo "$auth_json" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessToken'])" 2>/dev/null || echo "")

  if [[ -z "$token" ]]; then
    log "Could not authenticate automatically."
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────┐"
    echo "  │  One-time manual setup required (Jellyfin wizard)           │"
    echo "  │                                                             │"
    echo "  │  1. Open http://localhost:${JELLYFIN_PORT} in your browser           │"
    echo "  │  2. Complete the 5-step setup wizard                        │"
    echo "  │     • Server name: anything                                 │"
    echo "  │     • Username: ${ADMIN_USER}  Password: ${ADMIN_PASS}              │"
    echo "  │     • Add library: Shows → /media/shows                     │"
    echo "  │  3. Re-run ./scripts/deploy-local.sh to verify setup        │"
    echo "  └─────────────────────────────────────────────────────────────┘"
    echo ""
    print_summary
    return
  fi

  local auth_header="MediaBrowser Token=\"${token}\""

  # Add TV Shows library if not already present
  local libs has_shows
  libs=$(curl -sf "${base}/Library/VirtualFolders" \
    -H "Authorization: ${auth_header}" 2>/dev/null || echo "[]")

  has_shows=$(echo "$libs" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(any(l.get('CollectionType')=='tvshows' for l in d))" \
    2>/dev/null || echo "False")

  if [[ "$has_shows" == "False" ]]; then
    log "Adding TV Shows library..."
    curl -sf -X POST \
      "${base}/Library/VirtualFolders?name=Shows&collectionType=tvshows&refreshLibrary=true" \
      -H "Content-Type: application/json" \
      -H "Authorization: ${auth_header}" \
      -d '{"Paths":["/media/shows"],"LibraryOptions":{"EnableRealtimeMonitor":true,"PathInfos":[{"Path":"/media/shows"}]}}' \
      &>/dev/null || true
    ok "TV Shows library added — a scan will start automatically."
  else
    ok "TV Shows library already configured."
  fi

  print_summary
}

print_summary() {
  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "  Jellyfin  →  http://localhost:${JELLYFIN_PORT}"
  echo "  Username  :  ${ADMIN_USER}"
  echo "  Password  :  ${ADMIN_PASS}"
  echo ""
  echo "  Test show : Breaking Bad"
  echo "    On disk  : Season 1, Season 3"
  echo "    On TMDB  : Seasons 1–5"
  echo "    Missing  : 2, 4, 5  ← displayed by the plugin"
  echo ""
  echo "  Test show : The Boys (TMDB id: 76479)"
  echo "    On disk  : Season 1, Season 2, Season 3"
  echo "    On TMDB  : Seasons 1–5"
  echo "    Missing  : 4  ← displayed by the plugin"
  echo "    Upcoming : 5 (2026-04-07)  ← upcoming date badge"
  echo ""
  echo "  After the library scan finishes, open the Breaking Bad"
  echo "  series page to see the missing seasons plugin in action."
  echo ""
  echo "  Logs    :  docker logs -f ${CONTAINER_NAME}"
  echo "  Stop    :  docker rm -f ${CONTAINER_NAME}"
  echo "  Restart :  ./scripts/deploy-local.sh"
  echo "════════════════════════════════════════════════════════"
}

# ── Main ──────────────────────────────────────────────────────────────────────

check_docker
build_plugin
create_test_media
ensure_file_transformation_plugin
copy_plugin
start_jellyfin
wait_for_jellyfin
configure_jellyfin
