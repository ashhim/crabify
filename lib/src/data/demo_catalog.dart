import '../models/artist_profile.dart';
import '../models/music_collection.dart';
import '../models/music_track.dart';

class DemoCatalog {
  static const String demoTrackIdPrefix = 'crab-tide-';
  static const Set<String> starterPlaylistIds = <String>{
    'playlist-crab-currents',
    'playlist-after-hours',
    'playlist-offline-kit',
  };

  static const List<String> genres = <String>[
    'Ambient',
    'Electronic',
    'Lo-Fi',
    'House',
    'Jazz',
    'World',
    'Acoustic',
    'Drum & Bass',
  ];

  static List<MusicTrack> onlineTracks() {
    return <MusicTrack>[
      _track(
        id: 'crab-tide-01',
        title: 'Moonlit Tide',
        artist: 'Coral Lane',
        album: 'Night Swell',
        url: 'https://samplelib.com/lib/preview/mp3/sample-15s.mp3',
        duration: 15,
        genre: 'Ambient',
        description:
            'Slow-blooming pads and a shoreline pulse built for late sessions.',
      ),
      _track(
        id: 'crab-tide-02',
        title: 'Shellphone',
        artist: 'Blue Current',
        album: 'Pocket Waves',
        url: 'https://samplelib.com/lib/preview/mp3/sample-12s.mp3',
        duration: 12,
        genre: 'Lo-Fi',
        description:
            'Warm tape flutter, sleepy keys, and a bassline that hugs the room.',
      ),
      _track(
        id: 'crab-tide-03',
        title: 'Harbor Lights',
        artist: 'Tidal Echo',
        album: 'Dockside FM',
        url: 'https://samplelib.com/lib/preview/mp3/sample-9s.mp3',
        duration: 9,
        genre: 'Electronic',
        description:
            'A glossy after-hours cut with neon chords and clipped drums.',
      ),
      _track(
        id: 'crab-tide-04',
        title: 'Salt Air Shuffle',
        artist: 'Crate of Sand',
        album: 'Beach Transit',
        url: 'https://samplelib.com/lib/preview/mp3/sample-6s.mp3',
        duration: 6,
        genre: 'House',
        description:
            'Percussive, minimal, and designed to feel like a boardwalk night ride.',
      ),
      _track(
        id: 'crab-tide-05',
        title: 'Deepwater Club',
        artist: 'Blue Current',
        album: 'Pocket Waves',
        url: 'https://samplelib.com/lib/preview/mp3/sample-3s.mp3',
        duration: 3,
        genre: 'House',
        description:
            'A tiny but punchy demo loop that still sells the club feel.',
      ),
      _track(
        id: 'crab-tide-06',
        title: 'Glass Reef',
        artist: 'Coral Lane',
        album: 'Night Swell',
        url: 'https://samplelib.com/lib/preview/mp3/sample-12s.mp3',
        duration: 12,
        genre: 'Ambient',
        description:
            'Shimmering textures and low-end movement for deep focus blocks.',
      ),
      _track(
        id: 'crab-tide-07',
        title: 'Low Tide Letters',
        artist: 'Tidal Echo',
        album: 'Dockside FM',
        url: 'https://samplelib.com/lib/preview/mp3/sample-15s.mp3',
        duration: 15,
        genre: 'Jazz',
        description: 'A soft hybrid between smoky keys and electronic space.',
      ),
      _track(
        id: 'crab-tide-08',
        title: 'Boardwalk Bloom',
        artist: 'Crate of Sand',
        album: 'Beach Transit',
        url: 'https://samplelib.com/lib/preview/mp3/sample-9s.mp3',
        duration: 9,
        genre: 'World',
        description:
            'Bright melodic fragments with a beachside breeze to them.',
      ),
    ];
  }

  static List<MusicCollection> starterPlaylists(List<MusicTrack> tracks) {
    final ids = tracks.map((track) => track.id).toList();
    return <MusicCollection>[
      MusicCollection(
        id: 'playlist-crab-currents',
        title: 'Crab Currents',
        subtitle: 'Your daily catch',
        description:
            'A tight, premium-feeling starter mix pulled from the live catalog.',
        type: CollectionType.playlist,
        trackIds: ids.take(4).toList(),
        editable: true,
      ),
      MusicCollection(
        id: 'playlist-after-hours',
        title: 'After Hours Surf',
        subtitle: 'Low light, high detail',
        description:
            'Night-drive textures, roomy drums, and slick dark surfaces.',
        type: CollectionType.playlist,
        trackIds: ids.skip(2).take(4).toList(),
        editable: true,
      ),
      MusicCollection(
        id: 'playlist-offline-kit',
        title: 'Offline Starter Kit',
        subtitle: 'Built for flights and dead zones',
        description:
            'A short queue that feels complete even when you lose connection.',
        type: CollectionType.playlist,
        trackIds: ids.reversed.take(4).toList().reversed.toList(),
        editable: true,
      ),
    ];
  }

  static Map<String, String> artistBlurbs = <String, String>{
    'coral-lane':
        'Coral Lane lives in the softer end of electronic music, somewhere between late-night ambient and cinematic drift.',
    'blue-current':
        'Blue Current builds concise, tactile loops designed for headphones, coding sessions, and rainy commutes.',
    'tidal-echo':
        'Tidal Echo leans melodic and reflective, blending clean keys with dark coastal atmosphere.',
    'crate-of-sand':
        'Crate of Sand makes rhythm-first sketches that feel playful, percussive, and beach-weather ready.',
  };

  static List<ArtistProfile> artistsFrom(
    List<MusicTrack> tracks,
    List<MusicCollection> collections,
  ) {
    final Map<String, List<MusicTrack>> grouped = <String, List<MusicTrack>>{};
    for (final track in tracks) {
      grouped.putIfAbsent(track.artistId, () => <MusicTrack>[]).add(track);
    }

    return grouped.entries.map((entry) {
      final artistTracks = entry.value;
      final artistName = artistTracks.first.artistName;
      final collectionIds =
          collections
              .where(
                (collection) => collection.trackIds.any(
                  (trackId) => artistTracks.any((track) => track.id == trackId),
                ),
              )
              .map((collection) => collection.id)
              .toSet()
              .toList();

      return ArtistProfile(
        id: entry.key,
        name: artistName,
        description:
            artistBlurbs[entry.key] ??
            '$artistName keeps the Crabify catalog feeling tactile, warm, and a little nocturnal.',
        topTrackIds: artistTracks.map((track) => track.id).take(5).toList(),
        collectionIds: collectionIds,
        artworkUrl: artistTracks.first.artworkUrl,
        artworkPath: artistTracks.first.artworkPath,
      );
    }).toList();
  }

  static List<MusicTrack> searchTracks(List<MusicTrack> tracks, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return tracks;
    }

    return tracks.where((track) {
      final haystack =
          <String>[
            track.title,
            track.artistName,
            track.albumTitle,
            track.genre ?? '',
          ].join(' ').toLowerCase();
      return haystack.contains(normalized);
    }).toList();
  }

  static MusicTrack _track({
    required String id,
    required String title,
    required String artist,
    required String album,
    required String url,
    required int duration,
    required String genre,
    required String description,
  }) {
    return MusicTrack(
      id: id,
      title: title,
      artistName: artist,
      artistId: _artistId(artist),
      albumTitle: album,
      albumId: _collectionId(album),
      artworkUrl: null,
      description: description,
      genre: genre,
      streamUrl: url,
      durationSeconds: duration,
      downloadable: true,
      isStreamable: true,
      origin: TrackOrigin.online,
    );
  }

  static String _artistId(String value) => value
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  static String _collectionId(String value) => value
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}
