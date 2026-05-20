# Prism

A native macOS app that pulls your Spotify library and splits it into a spectrum of
categories — sorted on-device, with no cloud services and no API costs.

Prism reads your liked songs, playlists, top tracks and recent plays, resolves the genres
behind every track, then groups everything into clear categories using Apple's on-device
Apple Intelligence model. You can browse each category, export it to CSV, or push it back
to Spotify as a real playlist with one click.

## Features

- Syncs liked songs, all playlists, top tracks (short/medium/long term), recently played, and followed artists
- Categorizes your library with the on-device Apple Intelligence model — fully offline, free, private
- Falls back to deterministic genre rules automatically if Apple Intelligence is unavailable
- Creates each category as a private playlist in your Spotify account
- Exports any category, or the whole library, to CSV
- Caches everything locally so it opens instantly between launches

## Requirements

- macOS 26 (Tahoe) or later, on an Apple Silicon Mac
- Xcode 26 or later to build
- Apple Intelligence enabled (System Settings → Apple Intelligence & Siri) for the on-device categorizer — Prism falls back to genre rules if it is off
- A free Spotify account

## Setup: your Spotify Client ID

Prism talks to Spotify with your own free developer app, so your listening data only
moves between your Mac and Spotify. Nothing is committed to this repository.

1. Open the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and log in.
2. Click **Create app**. Name it anything (for example, "Prism").
3. Under **Redirect URIs**, add this exact address:
   ```
   http://127.0.0.1:8888/callback
   ```
4. Tick the **Web API** checkbox, save, then open the app's **Settings**.
5. Copy the **Client ID**.

You paste this Client ID into Prism on first launch. It is stored in your local
`UserDefaults`; the Spotify refresh token is stored in the macOS Keychain.

## Build and run

This repository includes a generated `Prism.xcodeproj`, so you can just open it:

1. Open `Prism.xcodeproj` in Xcode.
2. Select the **Prism** target → **Signing & Capabilities** → choose your team.
3. Build and run (⌘R).
4. Paste your Spotify Client ID, click **Connect Spotify**, and approve access in the browser.

The project is defined by `project.yml` and generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen).
To regenerate it after changing `project.yml`:

```sh
brew install xcodegen
xcodegen generate
```

To regenerate the app icon after editing the artwork script:

```sh
swift Tools/GenerateIcon.swift
```

## How categorization works

Spotify retired its audio-features and recommendation endpoints, so Prism categorizes
using **artist genres plus track and album metadata** — the data Spotify still exposes.

1. Prism collects the genre tags from every artist in your library.
2. The on-device model groups those fine-grained genres into 8–14 broad categories.
3. Each track is placed into the category that most of its genres point to.
4. Genres the model leaves out are matched to the closest category by shared keywords.

The "Genre Rules" engine (selectable in Settings) does step 2–3 with a fixed keyword map
instead of the model — instant, but less nuanced.

## Privacy

- Categorization runs entirely on-device. No track data is sent anywhere except Spotify's own API.
- The Spotify refresh token lives in the macOS Keychain; the access token is kept only in memory.
- The app is sandboxed and requests only network access and user-selected file access (for CSV export).

## Project layout

```
Prism/
  Models/           Spotify API models and the normalized library model
  Services/         OAuth (PKCE), API client, loopback redirect server, Keychain, caching
  Categorization/   Apple Intelligence categorizer + rule-based fallback
  Export/           CSV export
  ViewModels/       AppModel — the observable app state
  Views/            SwiftUI interface
Tools/
  GenerateIcon.swift  Draws the app icon at every required size
```

## License

MIT — see [LICENSE](LICENSE).
