import 'dart:convert';

enum CollectionType { playlist, album, mix }

enum PlaylistCoverMode { lastPlayed, fixedTrack, localImage }

CollectionType collectionTypeFromJson(String? value) {
  return CollectionType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => CollectionType.playlist,
  );
}

PlaylistCoverMode playlistCoverModeFromJson(String? value) {
  return PlaylistCoverMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => PlaylistCoverMode.lastPlayed,
  );
}

class MusicCollection {
  const MusicCollection({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.type,
    required this.trackIds,
    this.artistIds = const <String>[],
    this.artworkUrl,
    this.artworkPath,
    this.editable = false,
    this.coverMode = PlaylistCoverMode.lastPlayed,
    this.coverTrackId,
    this.coverImagePath,
  });

  final String id;
  final String title;
  final String subtitle;
  final String description;
  final CollectionType type;
  final List<String> trackIds;
  final List<String> artistIds;
  final String? artworkUrl;
  final String? artworkPath;
  final bool editable;
  final PlaylistCoverMode coverMode;
  final String? coverTrackId;
  final String? coverImagePath;

  MusicCollection copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? description,
    CollectionType? type,
    List<String>? trackIds,
    List<String>? artistIds,
    String? artworkUrl,
    String? artworkPath,
    bool? editable,
    PlaylistCoverMode? coverMode,
    String? coverTrackId,
    String? coverImagePath,
    bool clearArtworkUrl = false,
    bool clearArtworkPath = false,
    bool clearCoverTrackId = false,
    bool clearCoverImagePath = false,
  }) {
    return MusicCollection(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      description: description ?? this.description,
      type: type ?? this.type,
      trackIds: trackIds ?? this.trackIds,
      artistIds: artistIds ?? this.artistIds,
      artworkUrl: clearArtworkUrl ? null : artworkUrl ?? this.artworkUrl,
      artworkPath: clearArtworkPath ? null : artworkPath ?? this.artworkPath,
      editable: editable ?? this.editable,
      coverMode: coverMode ?? this.coverMode,
      coverTrackId:
          clearCoverTrackId ? null : coverTrackId ?? this.coverTrackId,
      coverImagePath:
          clearCoverImagePath ? null : coverImagePath ?? this.coverImagePath,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'description': description,
      'type': type.name,
      'trackIds': trackIds,
      'artistIds': artistIds,
      'artworkUrl': artworkUrl,
      'artworkPath': artworkPath,
      'editable': editable,
      'coverMode': coverMode.name,
      'coverTrackId': coverTrackId,
      'coverImagePath': coverImagePath,
    };
  }

  factory MusicCollection.fromJson(Map<String, dynamic> json) {
    return MusicCollection(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled collection',
      subtitle: json['subtitle'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: collectionTypeFromJson(json['type'] as String?),
      trackIds:
          (json['trackIds'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .toList(),
      artistIds:
          (json['artistIds'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .toList(),
      artworkUrl: json['artworkUrl'] as String?,
      artworkPath: json['artworkPath'] as String?,
      editable: json['editable'] as bool? ?? false,
      coverMode: playlistCoverModeFromJson(json['coverMode'] as String?),
      coverTrackId: json['coverTrackId'] as String?,
      coverImagePath: json['coverImagePath'] as String?,
    );
  }

  static List<MusicCollection> listFromJson(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(MusicCollection.fromJson)
        .toList();
  }

  static String listToJson(List<MusicCollection> collections) {
    return jsonEncode(
      collections.map((collection) => collection.toJson()).toList(),
    );
  }
}
