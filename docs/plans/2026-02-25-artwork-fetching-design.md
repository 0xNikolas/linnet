# Artwork Fetching Design

**Date:** 2026-02-25

## Overview

Add on-demand artwork fetching from external open-source repositories (MusicBrainz, Cover Art Archive, Wikipedia, Fanart.tv) to fill in missing album and artist artwork.

## Lookup Pipeline

### Album Art

1. **Text search** — query MusicBrainz API by album name + artist name → get `release-group` MBID
2. **Cover fetch** — GET front cover from Cover Art Archive by MBID
3. **Fingerprint fallback** (optional) — if text search fails and user has an AcoustID API key, fingerprint a track → resolve MBID → fetch cover

### Artist Images

1. **MusicBrainz** → search artist → get artist MBID → follow Wikidata/Wikipedia URL relation
2. **Wikipedia** → fetch page image (free, no key required)
3. **Fanart.tv** (optional) → if user provides API key, fetch higher-quality artist image

## Storage

Artwork stored as `Data?` on the SwiftData models (consistent with existing pattern):
- `Album.artworkData` — already exists
- `Artist.artworkData` — new property to add

When a track/album/artist is deleted from the library, their `artworkData` is deleted with them automatically (inline SwiftData property). No orphaned data.

## Trigger Points

- **Auto-fetch**: when a view appears showing an album/artist with nil artwork, trigger fetch with a loading indicator
- **Manual**: "Find Artwork" / "Refresh Artwork" context menu item on albums and artists
- **Rate limiting**: MusicBrainz requires max 1 request/second with a User-Agent header. Queue requests sequentially.

## API Keys (Settings)

New section in Settings:
- **AcoustID API Key** (optional) — enables fingerprint fallback for album art
- **Fanart.tv API Key** (optional) — enables higher-quality artist images

Both are free to obtain. Text-based MusicBrainz + Wikipedia lookup works with no keys.

## Key Files

| File | Purpose |
|---|---|
| `LinnetLibrary/Services/ArtworkService.swift` | Main service: orchestrates lookups, rate limiting, caching to models |
| `LinnetLibrary/Services/MusicBrainzClient.swift` | HTTP client for MusicBrainz search + Cover Art Archive |
| `LinnetLibrary/Services/AcoustIDClient.swift` | Optional fingerprint-based lookup |
| `LinnetLibrary/Services/FanartTVClient.swift` | Optional Fanart.tv artist image fetch |
| `LinnetLibrary/Models/Artist.swift` | Add `artworkData: Data?` property |
| Views (AlbumDetailView, ArtistDetailView, AlbumGridView, ListenNowView) | Add loading states + context menu artwork actions |

## MusicBrainz API Details

- Base URL: `https://musicbrainz.org/ws/2/`
- Format: JSON (`?fmt=json`)
- User-Agent required: `Linnet/1.0 (contact@example.com)`
- Rate limit: 1 req/sec
- Release group search: `/release-group/?query=releasegroup:{name} AND artist:{artist}&fmt=json`
- Artist search: `/artist/?query=artist:{name}&fmt=json`
- Artist relations (for Wikipedia URL): `/artist/{mbid}?inc=url-rels&fmt=json`

## Cover Art Archive API Details

- Base URL: `https://coverartarchive.org/`
- No auth needed
- Front cover: `/release-group/{mbid}/front-500` (redirects to image URL)

## Wikipedia Image Details

- From MusicBrainz artist URL relations, extract Wikipedia or Wikidata URL
- Wikidata → get Wikipedia page title → MediaWiki API thumbnail
- `https://en.wikipedia.org/api/rest_v1/page/summary/{title}` → `.thumbnail.source`

## Constraints

- No API keys required for basic operation (MusicBrainz + Cover Art Archive + Wikipedia)
- AcoustID and Fanart.tv are optional power-user features
- Must respect MusicBrainz 1 req/sec rate limit
- Artwork fetched on-demand, not during bulk scan
- Cache cleanup happens automatically via SwiftData model deletion
