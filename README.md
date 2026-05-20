# Prism

A native macOS app that pulls your Spotify library, sorts it into categories with a
local AI model, and lets you browse, play, and re-organize it — no cloud services,
no API costs.

Prism reads your liked songs, playlists, top tracks and recent plays, then groups
every track into clear categories by classifying its artist with a language model
running entirely on your Mac. You can browse the result, play tracks in-app, push a
category back to Spotify as a playlist, or export it to CSV.

## Download

**[⬇ Download the latest release](https://github.com/MotionPeak/Prism/releases/latest)**

Open the downloaded `.dmg` and drag **Prism** into your **Applications** folder.
The app is signed with a Developer ID and notarized by Apple, so it launches with
no Gatekeeper warnings.

Requires macOS 26 on an Apple Silicon Mac. On first launch you paste a free
Spotify Client ID — see **Setup** below (about two minutes).

## Features

- Syncs liked songs, all playlists, top tracks, recently played, and followed artists
- Categorizes the library by artist using a **local** model — Apple Intelligence
  (on-device, zero setup) or a local **Ollama** model. Nothing leaves your Mac.
- Browse your playlists and the tracks inside them
- Liked Songs management: multi-select tracks, move them to a playlist, or remove them
- Turn any category into a private Spotify playlist, or export it to CSV
- In-app playback via the Spotify Web Playback SDK — a player bar with a draggable
  seek bar and an animated now-playing indicator
- Caches the library locally so it opens instantly between launches

## Requirements

- macOS 26 (Tahoe) or later, on an Apple Silicon Mac
- Xcode 26 or later to build
- A **Spotify Premium** account — required for in-app playback, and for the app to
  function under Spotify's current development-mode rules
- For categorization, either:
  - **Apple Intelligence** enabled (System Settings) — on-device, no install, or
  - **Ollama** installed with a model pulled — see below

## Setup: your Spotify Client ID

Prism talks to Spotify through your own free developer app, so your listening data
only moves between your Mac and Spotify. Nothing is committed to this repository.

1. Open the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and log in.
2. Click **Create app**. Name it anything (for example, "Prism").
3. Under **Redirect URIs**, add this exact address:
   ```
   http://127.0.0.1:8888/callback
   ```
4. Tick the **Web API** checkbox, save, then open the app's **Settings**.
5. Copy the **Client ID**.

Paste the Client ID into Prism on first launch. It is stored in local `UserDefaults`;
the Spotify refresh token is stored in the macOS Keychain.

## Build and run

The repository includes a generated `Prism.xcodeproj`, so you can open it directly:

1. Open `Prism.xcodeproj` in Xcode.
2. Select the **Prism** target → **Signing & Capabilities** → choose your team.
3. Build and run (⌘R), paste your Client ID, and click **Connect Spotify**.

The project is defined by `project.yml` and generated with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). Regenerate it after editing
`project.yml`:

```sh
brew install xcodegen
xcodegen generate
```

## Categorizing with Ollama (optional)

Apple Intelligence works with no setup. To use a local Ollama model instead:

1. Install [Ollama](https://ollama.com) and make sure it is running.
2. Pull a model, for example: `ollama pull qwen2.5:7b`
3. In Prism: **Settings → Categorization → Local Model (Ollama)**, then pick the model.

## How categorization works

Spotify no longer exposes genre or catalog data to development-mode apps, so Prism
does not rely on it. Instead:

1. Prism collects the unique artists across your library.
2. A local model classifies each artist, by name, into one of about 15 broad
   categories (Hip-Hop & Rap, Rock, Electronic & Dance, Jazz & Blues, and so on).
3. Every track inherits its artist's category.

This runs entirely on your Mac — Apple Intelligence on-device, or Ollama locally.

## Playback

In-app playback uses the **Spotify Web Playback SDK** and requires Spotify Premium.
Right-click a track, or click its album art, and choose **Play**. A player bar
appears at the bottom of the window with transport controls and a seek bar, and the
currently playing track is marked with an animated indicator.

## Privacy

- Categorization runs entirely on-device or on your local machine.
- The Spotify refresh token is kept in the macOS Keychain; the access token lives only in memory.
- The app is sandboxed and requests only network access and user-selected file access (for CSV export).

## Project layout

```
Prism/
  Models/           Spotify API models and the normalized library model
  Services/         OAuth (PKCE), API client, Keychain, caching, Ollama, Web Playback SDK
  Categorization/   Name-based categorizer + Apple Intelligence and Ollama runners
  Export/           CSV export
  ViewModels/       AppModel — the observable app state
  Views/            SwiftUI interface
Tools/
  GenerateIcon.swift  Draws the app icon at every required size
```

## License

MIT — see [LICENSE](LICENSE).
