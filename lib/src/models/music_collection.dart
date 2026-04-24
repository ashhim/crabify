import 'dart:convert';

enum CollectionType { playlist, album, mix }

CollectionType collectionTypeFromJson(String? value) {
  return CollectionType.values.firstWhere(
    (type) => type.name == value,
    orElse: () => CollectionType.playlist,
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
    this.artworkUrl,
    this.artworkPath,
    this.editable = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final String description;
  final CollectionType type;
  final List<String> trackIds;
  final String? artworkUrl;
  final String? artworkPath;
  final bool editable;

  MusicCollection copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? description,
    CollectionType? type,
    List<String>? trackIds,
    String? artworkUrl,
    String? artworkPath,
    bool? editable,
    bool clearArtworkUrl = false,
    bool clearArtworkPath = false,
  }) {
    return MusicCollection(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      description: description ?? this.description,
      type: type ?? this.type,
      trackIds: trackIds ?? this.trackIds,
      artworkUrl: clearArtworkUrl ? null : artworkUrl ?? this.artworkUrl,
      artworkPath: clearArtworkPath ? null : artworkPath ?? this.artworkPath,
      editable: editable ?? this.editable,
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
      'artworkUrl': artworkUrl,
      'artworkPath': artworkPath,
      'editable': editable,
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
      artworkUrl: json['artworkUrl'] as String?,
      artworkPath: json['artworkPath'] as String?,
      editable: json['editable'] as bool? ?? false,
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
