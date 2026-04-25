import 'dart:convert';

import 'music_collection.dart';

class ArtistProfile {
  const ArtistProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.topTrackIds,
    required this.collectionIds,
    this.artworkUrl,
    this.artworkPath,
    this.coverMode = PlaylistCoverMode.lastPlayed,
    this.coverTrackId,
    this.coverImagePath,
    this.hidden = false,
    this.pinned = false,
    this.manuallyAdded = false,
  });

  final String id;
  final String name;
  final String description;
  final List<String> topTrackIds;
  final List<String> collectionIds;
  final String? artworkUrl;
  final String? artworkPath;
  final PlaylistCoverMode coverMode;
  final String? coverTrackId;
  final String? coverImagePath;
  final bool hidden;
  final bool pinned;
  final bool manuallyAdded;

  ArtistProfile copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? topTrackIds,
    List<String>? collectionIds,
    String? artworkUrl,
    String? artworkPath,
    PlaylistCoverMode? coverMode,
    String? coverTrackId,
    String? coverImagePath,
    bool? hidden,
    bool? pinned,
    bool? manuallyAdded,
    bool clearArtworkUrl = false,
    bool clearArtworkPath = false,
    bool clearCoverTrackId = false,
    bool clearCoverImagePath = false,
  }) {
    return ArtistProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      topTrackIds: topTrackIds ?? this.topTrackIds,
      collectionIds: collectionIds ?? this.collectionIds,
      artworkUrl: clearArtworkUrl ? null : artworkUrl ?? this.artworkUrl,
      artworkPath: clearArtworkPath ? null : artworkPath ?? this.artworkPath,
      coverMode: coverMode ?? this.coverMode,
      coverTrackId:
          clearCoverTrackId ? null : coverTrackId ?? this.coverTrackId,
      coverImagePath:
          clearCoverImagePath ? null : coverImagePath ?? this.coverImagePath,
      hidden: hidden ?? this.hidden,
      pinned: pinned ?? this.pinned,
      manuallyAdded: manuallyAdded ?? this.manuallyAdded,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'topTrackIds': topTrackIds,
      'collectionIds': collectionIds,
      'artworkUrl': artworkUrl,
      'artworkPath': artworkPath,
      'coverMode': coverMode.name,
      'coverTrackId': coverTrackId,
      'coverImagePath': coverImagePath,
      'hidden': hidden,
      'pinned': pinned,
      'manuallyAdded': manuallyAdded,
    };
  }

  factory ArtistProfile.fromJson(Map<String, dynamic> json) {
    return ArtistProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown artist',
      description: json['description'] as String? ?? '',
      topTrackIds:
          (json['topTrackIds'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .toList(),
      collectionIds:
          (json['collectionIds'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .toList(),
      artworkUrl: json['artworkUrl'] as String?,
      artworkPath: json['artworkPath'] as String?,
      coverMode: playlistCoverModeFromJson(json['coverMode'] as String?),
      coverTrackId: json['coverTrackId'] as String?,
      coverImagePath: json['coverImagePath'] as String?,
      hidden: json['hidden'] as bool? ?? false,
      pinned: json['pinned'] as bool? ?? false,
      manuallyAdded: json['manuallyAdded'] as bool? ?? false,
    );
  }

  static List<ArtistProfile> listFromJson(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(ArtistProfile.fromJson)
        .toList();
  }

  static String listToJson(List<ArtistProfile> artists) {
    return jsonEncode(artists.map((artist) => artist.toJson()).toList());
  }
}
