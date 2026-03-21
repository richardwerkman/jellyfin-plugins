// ==UserScript==
// @name         Jellyfin Missing Seasons
// @namespace    jellyfin-missing-seasons
// @version      1.0.0
// @description  Shows missing seasons in a series as grayed-out indicators using TMDB data.
// @match        */web/index.html*
// @match        */web/*
// @grant        none
// ==/UserScript==

// Jellyfin Missing Seasons Plugin
// Uses the same public TMDB API key that Jellyfin's server uses internally.
// No configuration needed — just install and go.
(function () {
    'use strict';

    const PLUGIN_ID = 'jellyfin-missing-seasons';
    const TMDB_BASE_URL = 'https://api.themoviedb.org/3';
    const TMDB_IMAGE_BASE = 'https://image.tmdb.org/t/p';
    // Same public TMDB v3 key used by Jellyfin server internally
    const TMDB_API_KEY = '4219e299c89411838049ab0dab19ebd5';
    const POLL_INTERVAL_MS = 500;
    const MAX_POLL_ATTEMPTS = 40;

    // ── Helpers ──────────────────────────────────────────────────────────

    function log(...args) {
        console.log('[MissingSeasons]', ...args);
    }

    function warn(...args) {
        console.warn('[MissingSeasons]', ...args);
    }

    function escapeHtml(str) {
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }

    // ── CSS Injection ────────────────────────────────────────────────────

    function injectStyles() {
        if (document.getElementById(`${PLUGIN_ID}-styles`)) return;

        const style = document.createElement('style');
        style.id = `${PLUGIN_ID}-styles`;
        style.textContent = `
            .missing-season-card {
                opacity: 0.4;
                pointer-events: none;
                user-select: none;
                position: relative;
                filter: grayscale(100%);
                transition: opacity 0.3s ease;
            }

            .missing-season-card .cardBox {
                cursor: default !important;
            }

            .missing-season-card .cardScalable {
                cursor: default !important;
            }

            .missing-season-card a {
                pointer-events: none !important;
                cursor: default !important;
            }

            .missing-season-card .cardOverlayButton,
            .missing-season-card .cardOverlayFab,
            .missing-season-card .btnCardOptions {
                display: none !important;
            }

            .missing-season-badge {
                position: absolute;
                top: 8px;
                left: 8px;
                background: rgba(0, 0, 0, 0.75);
                color: #ccc;
                padding: 2px 8px;
                border-radius: 3px;
                font-size: 0.75em;
                font-weight: 600;
                z-index: 10;
                letter-spacing: 0.5px;
                text-transform: uppercase;
            }

            .missing-season-card .cardIndicators {
                pointer-events: none !important;
            }
        `;
        document.head.appendChild(style);
    }

    // ── TMDB API ─────────────────────────────────────────────────────────

    async function tmdbFetch(path) {
        const separator = path.includes('?') ? '&' : '?';
        const url = `${TMDB_BASE_URL}${path}${separator}api_key=${TMDB_API_KEY}`;
        const response = await fetch(url);

        if (!response.ok) {
            warn(`TMDB API error: ${response.status} for ${path}`);
            return null;
        }

        return response.json();
    }

    async function getTmdbSeasons(tmdbId) {
        const data = await tmdbFetch(`/tv/${tmdbId}`);
        if (!data || !data.seasons) return [];

        const now = new Date();

        return data.seasons
            .filter(s => {
                // Exclude "Specials" (season 0)
                if (s.season_number === 0) return false;
                // Only include released seasons
                if (!s.air_date) return false;
                return new Date(s.air_date) <= now;
            })
            .map(s => ({
                seasonNumber: s.season_number,
                name: s.name,
                episodeCount: s.episode_count,
                airDate: s.air_date,
                posterPath: s.poster_path,
                overview: s.overview
            }));
    }

    // ── Jellyfin API Helpers ─────────────────────────────────────────────

    function getJellyfinApiClient() {
        if (window.ApiClient) return window.ApiClient;
        if (window.Emby && window.Emby.ServerConnections) {
            return window.Emby.ServerConnections.currentApiClient();
        }
        try {
            const sc = window.ServerConnections || window.connectionManager;
            if (sc) return sc.currentApiClient();
        } catch (e) { /* ignore */ }
        return null;
    }

    function getJellyfinUserId() {
        const api = getJellyfinApiClient();
        if (!api) return null;
        try {
            return api.getCurrentUserId();
        } catch (e) {
            return null;
        }
    }

    async function getJellyfinSeriesInfo(itemId) {
        const api = getJellyfinApiClient();
        if (!api) return null;

        const userId = getJellyfinUserId();
        if (!userId) return null;

        try {
            return await api.getItem(userId, itemId);
        } catch (e) {
            warn('Failed to get series info:', e);
            return null;
        }
    }

    async function getJellyfinSeasons(seriesId) {
        const api = getJellyfinApiClient();
        if (!api) return [];

        const userId = getJellyfinUserId();
        if (!userId) return [];

        try {
            const result = await api.getSeasons(seriesId, { userId });
            return result.Items || [];
        } catch (e) {
            warn('Failed to get seasons:', e);
            return [];
        }
    }

    // ── URL / Route Helpers ──────────────────────────────────────────────

    function getSeriesIdFromUrl() {
        const hash = window.location.hash || '';
        const search = window.location.search || '';
        const fullUrl = hash + search;

        let match = fullUrl.match(/[?&]id=([a-f0-9]+)/i);
        if (match) return match[1];

        match = window.location.pathname.match(/\/items\/([a-f0-9]+)/i);
        if (match) return match[1];

        return null;
    }

    // ── Card Builder ─────────────────────────────────────────────────────

    function buildMissingSeasonCard(season) {
        const card = document.createElement('div');
        card.setAttribute('data-missing-season', season.seasonNumber);
        card.className = 'card overflowPortraitCard scalableCard overflowPortraitCard-scalable missing-season-card';

        // Sanitize poster path: must be a TMDB image path like /abc123.jpg
        const safePosterPath = season.posterPath && /^\/[a-zA-Z0-9_\-.]+\.\w+$/.test(season.posterPath)
            ? season.posterPath
            : null;

        card.innerHTML = `
            <div class="cardBox cardBox-bottompadded">
                <div class="cardScalable">
                    <div class="cardPadder cardPadder-overflowPortrait"></div>
                    <div class="cardContent">
                        <div class="cardImageContainer coveredImage cardContent-shadow itemAction lazy">
                            <div class="missing-season-badge">Not available</div>
                            <div class="cardIndicators">
                                <div class="countIndicator indicator">${season.episodeCount}</div>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="cardFooter">
                    <div class="cardText cardTextCentered">${escapeHtml(season.name || 'Season ' + season.seasonNumber)}</div>
                </div>
            </div>
        `;

        // Set background image via DOM property to avoid style-injection
        const imgContainer = card.querySelector('.cardImageContainer');
        if (safePosterPath) {
            imgContainer.style.backgroundImage = `url('${TMDB_IMAGE_BASE}/w300${safePosterPath}')`;
            imgContainer.style.backgroundSize = 'cover';
            imgContainer.style.backgroundPosition = 'center';
        } else {
            imgContainer.style.background = '#1a1a1a';
        }

        return card;
    }

    // ── Core Logic ───────────────────────────────────────────────────────

    async function processSeries(itemId) {
        const seriesInfo = await getJellyfinSeriesInfo(itemId);
        if (!seriesInfo || seriesInfo.Type !== 'Series') return;

        // Extract TMDB ID from Jellyfin's stored provider IDs
        const tmdbId = seriesInfo.ProviderIds && seriesInfo.ProviderIds.Tmdb;
        if (!tmdbId) {
            log(`No TMDB ID found for "${seriesInfo.Name}". Skipping.`);
            return;
        }

        log(`Processing "${seriesInfo.Name}" (TMDB: ${tmdbId})`);

        // Fetch data in parallel
        const [tmdbSeasons, jellyfinSeasons] = await Promise.all([
            getTmdbSeasons(tmdbId),
            getJellyfinSeasons(itemId)
        ]);

        if (!tmdbSeasons.length) {
            log('No TMDB seasons found or API error.');
            return;
        }

        // Determine which seasons are in Jellyfin
        const localSeasonNumbers = new Set(
            jellyfinSeasons.map(s => s.IndexNumber).filter(n => n != null)
        );

        // Find missing seasons
        const missingSeasons = tmdbSeasons.filter(s => !localSeasonNumbers.has(s.seasonNumber));

        if (!missingSeasons.length) {
            log(`"${seriesInfo.Name}" has all released seasons.`);
            return;
        }

        log(`Found ${missingSeasons.length} missing season(s):`, missingSeasons.map(s => s.name));

        injectMissingSeasons(missingSeasons, localSeasonNumbers, tmdbSeasons);
    }

    function injectMissingSeasons(missingSeasons, localSeasonNumbers, allTmdbSeasons) {
        let attempts = 0;

        function tryInject() {
            // Remove previously injected missing season cards
            document.querySelectorAll('[data-missing-season]').forEach(el => el.remove());

            // Find the items container that holds season cards
            const containers = document.querySelectorAll('.itemsContainer');
            let seasonContainer = null;

            for (const container of containers) {
                const section = container.closest('.verticalSection');
                if (section) {
                    const header = section.querySelector('.sectionTitle');
                    if (header && /season/i.test(header.textContent)) {
                        seasonContainer = container;
                        break;
                    }
                }
            }

            // Fallback: childrenCollapsible section
            if (!seasonContainer) {
                const childrenSection = document.querySelector('#childrenCollapsible .itemsContainer');
                if (childrenSection) seasonContainer = childrenSection;
            }

            if (!seasonContainer) {
                attempts++;
                if (attempts < MAX_POLL_ATTEMPTS) {
                    setTimeout(tryInject, POLL_INTERVAL_MS);
                } else {
                    warn('Could not find seasons container after polling.');
                }
                return;
            }

            // Build all season numbers in order
            const allSeasonNumbers = allTmdbSeasons.map(s => s.seasonNumber).sort((a, b) => a - b);

            // Map existing cards by season number
            const existingCards = seasonContainer.querySelectorAll('.card');
            const existingCardMap = new Map();

            existingCards.forEach(card => {
                const cardText = card.querySelector('.cardText');
                if (cardText) {
                    const match = cardText.textContent.match(/Season\s+(\d+)/i);
                    if (match) {
                        existingCardMap.set(parseInt(match[1], 10), card);
                    }
                }
            });

            // Insert missing season cards in correct order
            for (const season of missingSeasons) {
                const card = buildMissingSeasonCard(season);

                let inserted = false;
                for (let i = allSeasonNumbers.length - 1; i >= 0; i--) {
                    const sn = allSeasonNumbers[i];
                    if (sn < season.seasonNumber) {
                        const refCard = existingCardMap.get(sn) || seasonContainer.querySelector(`[data-missing-season="${sn}"]`);
                        if (refCard) {
                            if (refCard.nextSibling) {
                                seasonContainer.insertBefore(card, refCard.nextSibling);
                            } else {
                                seasonContainer.appendChild(card);
                            }
                            inserted = true;
                            break;
                        }
                    }
                }

                if (!inserted) {
                    if (seasonContainer.children.length > 0) {
                        const firstExistingSeason = Math.min(...Array.from(localSeasonNumbers));
                        if (season.seasonNumber < firstExistingSeason) {
                            seasonContainer.insertBefore(card, seasonContainer.firstChild);
                        } else {
                            seasonContainer.appendChild(card);
                        }
                    } else {
                        seasonContainer.appendChild(card);
                    }
                }
            }

            log('Missing season cards injected.');
        }

        tryInject();
    }

    // ── Page Navigation Handler ──────────────────────────────────────────

    let lastProcessedId = null;
    let processingTimeout = null;

    function processSeasonsOnCurrentPage() {
        const itemId = getSeriesIdFromUrl();
        if (!itemId) return;

        if (itemId === lastProcessedId) {
            lastProcessedId = null;
        }

        lastProcessedId = itemId;

        clearTimeout(processingTimeout);
        processingTimeout = setTimeout(() => {
            processSeries(itemId).catch(e => warn('Error processing series:', e));
        }, 1000);
    }

    // ── Initialization ───────────────────────────────────────────────────

    function init() {
        log('Plugin loaded.');
        injectStyles();

        // Jellyfin SPA navigation
        document.addEventListener('viewshow', () => {
            setTimeout(processSeasonsOnCurrentPage, 500);
        });

        window.addEventListener('hashchange', () => {
            setTimeout(processSeasonsOnCurrentPage, 500);
        });

        // MutationObserver for dynamic content
        const observer = new MutationObserver((mutations) => {
            for (const mutation of mutations) {
                if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                    for (const node of mutation.addedNodes) {
                        if (node.nodeType === Node.ELEMENT_NODE && node.querySelector) {
                            if (node.querySelector('#childrenCollapsible') || node.id === 'childrenCollapsible') {
                                processSeasonsOnCurrentPage();
                                return;
                            }
                        }
                    }
                }
            }
        });

        observer.observe(document.body, { childList: true, subtree: true });

        processSeasonsOnCurrentPage();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
