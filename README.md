# Crabify

<p align="center">
  <img src="assets/icon/logo.png" width="180" alt="Crabify Logo">
</p>

<p align="center">
  <b>Modern Flutter Music Player</b><br>
  Smooth Playback • Dynamic UI • Queue System • Offline Music • Audius Streaming
</p>

---

# 🎵 Overview

Crabify is a modern Flutter-based music player focused on smooth playback, responsive UI performance, dynamic theming, queue-based playback control, and local/offline music management.

The application combines:
- Online music streaming
- Offline/local playback
- Dynamic artwork-based UI
- Queue management
- Playlist systems
- Search & library management
- Background playback
- Persistent playback sessions

The architecture is optimized to reduce rebuild-heavy playback lag while maintaining a responsive user experience across Android and Windows.

---

# ✨ Core Features

## Playback System

- Play / Pause / Stop
- Next / Previous
- Queue-based playback
- Shuffle playback
- Repeat modes
- Background playback
- Notification controls
- Session restore
- Playback persistence
- Dynamic queue switching
- Smooth seek bar dragging
- Audio resume support

---

## Queue System

- Reorderable queue
- Queue sheet
- Fast queue switching
- Queue synchronization
- Queue persistence
- Queue add/remove
- Queue drag-and-drop
- Playback-safe queue mutations
- Real-time queue updates

---

## Music Library

- Liked songs
- Recent songs
- Offline songs
- Imported music
- Uploaded music
- Playlist management
- Artist pages
- Album pages
- Metadata editing
- Local music scanning
- Download management

---

## Search System

- Online music search
- Local track search
- Artist search
- Collection search
- Queue access from search
- Debounced search input
- Browse tags

---

## Now Playing Screen

- Dynamic artwork theming
- Animated controls
- Queue access
- PNG-based custom controls
- Artwork color extraction
- Smooth seek interactions
- Bottom-aligned controls
- Responsive layouts
- Hover animations

---

## Additional Features

- Sleep timer
- Import local audio
- Device scan import
- Cover image management
- Playlist editing
- Artist pinning
- Background session restore
- Local metadata overrides

---

# 🧠 Architecture

## State Management

Crabify uses:
- `Provider`
- `ChangeNotifier`

Playback state and library state are separated for rebuild optimization.

---

## Playback Engine

Playback is powered by:

```yaml
just_audio
audio_service
just_audio_background
just_audio_media_kit
```

Features include:
- Queue synchronization
- Session persistence
- Background playback
- Position throttling
- Deferred seek handling
- Playback recovery

---

## Performance Optimizations

### UI Optimization
- Narrow widget subscriptions
- Reduced rebuild scopes
- Queue-specific listeners
- Cached artwork palettes

### Playback Optimization
- Deferred seek commits
- Playback update throttling
- Session persistence debouncing
- Queue mutation optimization

### Rendering Optimization
- Local slider drag state
- Cached artwork colors
- Lightweight rebuild surfaces
- Fixed queue item extents

---

# 📁 Project Structure

```text
lib/
├── main.dart
├── src/
│
├── models/
│   ├── music_track.dart
│   ├── music_collection.dart
│   └── artist_profile.dart
│
├── screens/
│   ├── home_screen.dart
│   ├── search_screen.dart
│   ├── library_screen.dart
│   ├── liked_songs_screen.dart
│   ├── now_playing_screen.dart
│   └── detail_screen.dart
│
├── services/
│   ├── audio_player_service.dart
│   ├── library_service.dart
│   ├── download_service.dart
│   ├── local_storage_service.dart
│   └── sleep_timer_service.dart
│
├── widgets/
│   ├── mini_player.dart
│   ├── artwork_tile.dart
│   ├── track_tile.dart
│   └── surface_card.dart
│
└── theme/
    └── crabify_theme.dart
```

---

# 🎨 UI Features

## Dynamic Theming

Crabify extracts colors directly from album artwork and applies them to:
- Song title
- Artist name
- Shuffle button
- Previous button
- Next button
- Repeat button

The Play/Pause button maintains its custom PNG appearance independently.

---

## Custom Playback Controls

Custom PNG assets are used:

```text
assets/icon/icon.png
assets/icon/=.png
assets/icon/logo.png
```

Features:
- Animated transitions
- Rotation-based switching
- Hover effects
- Smooth opacity transitions

---

# 📦 Dependencies

```yaml
provider
just_audio
audio_service
just_audio_background
just_audio_media_kit
dio
shared_preferences
path_provider
permission_handler
file_picker
audio_metadata_reader
google_fonts
font_awesome_flutter
```

---

# 🚀 Installation

## Clone Repository

```bash
git clone https://github.com/your-username/crabify.git
cd crabify
```

---

## Install Dependencies

```bash
flutter pub get
```

---

## Run Application

```bash
flutter run
```

---

# 🔧 Build Commands

## Android APK

```bash
flutter build apk
```

---

## Windows Build

```bash
flutter build windows
```

---

# 📱 Supported Platforms

| Platform | Status |
|----------|--------|
| Android | ✅ |
| Windows | ✅ |
| Linux | ⚠️ Experimental |
| Web | ⚠️ Partial |
| iOS | ⚠️ Partial |

---

# ⚡ Performance Notes

Crabify includes multiple playback-time performance optimizations:

- Seek-bar lag reduction
- Queue rebuild minimization
- Narrow playback listeners
- Debounced persistence
- Cached artwork palette extraction
- Playback update throttling
- Queue reorder optimization

---

# 🛠 Technologies Used

| Technology | Purpose |
|------------|---------|
| Flutter | UI Framework |
| Dart | Programming Language |
| just_audio | Audio Playback |
| Provider | State Management |
| SharedPreferences | Persistence |
| Dio | Networking |
| Audio Service | Background Playback |
| Media Kit | Windows Audio Backend |

---

# 📸 Screenshots

```text
assets/screenshots/home.png
assets/screenshots/player.png
assets/screenshots/search.png
assets/screenshots/library.png
```

---

# 📄 License

This project is currently private.

---

# 👨‍💻 Developer

Developed by **ashhim**

---
