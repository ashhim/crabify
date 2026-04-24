import 'dart:convert';

enum TrackOrigin { online, local, downloaded, uploaded }

TrackOrigin trackOriginFromJson(String? value) {
  return TrackOrigin.values.firstWhere(
    (origin) => origin.name == value,
    orElse: () => TrackOrigin.online,
  );
}

class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.title,
    required this.artistName,
    required this.artistId,
    required this.albumTitle,
    required this.origin,
    this.albumId,
    this.artworkUrl,
    this.artworkPath,
    this.description,
    this.genre,
    this.streamUrl,
    this.localPath,
    this.durationSeconds,
    this.downloadable = false,
    this.isStreamable = false,
    this.releasedAt,
  });

  final String id;
  final String title;
  final String artistName;
  final String artistId;
  final String albumTitle;
  final String? albumId;
  final String? artworkUrl;
  final String? artworkPath;
  final String? description;
  final String? genre;
  final String? streamUrl;
  final String? localPath;
  final int? durationSeconds;
  final bool downloadable;
  final bool isStreamable;
  final TrackOrigin origin;
  final DateTime? releasedAt;

  Duration? get duration =>
      durationSeconds == null ? null : Duration(seconds: durationSeconds!);

  bool get hasValidId => id.trim().isNotEmpty;
  bool get isLocal => localPath != null && localPath!.isNotEmpty;
  bool get isAudiusStreamEndpoint =>
      (streamUrl ?? '').startsWith('https://api.audius.co/v1/tracks/');
  bool get hasValidAudiusTrackId =>
      RegExp(r'^[A-Za-z0-9]+$').hasMatch(id.trim());
  bool get hasValidRemoteSource {
    if (!isStreamable || streamUrl == null || streamUrl!.trim().isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(streamUrl!.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return false;
    }

    if (isAudiusStreamEndpoint) {
      return hasValidId && hasValidAudiusTrackId;
    }

    return true;
  }

  bool get isRemote => hasValidRemoteSource;
  bool get isPlayable => isLocal || isRemote;
  bool get isOfflineAvailable => isLocal;

  String get subtitle {
    if (albumTitle.trim().isEmpty) {
      return artistName;
    }
    return '$artistName - $albumTitle';
  }

  String get cacheKey => '$id-${origin.name}';

  MusicTrack copyWith({
    String? id,
    String? title,
    String? artistName,
    String? artistId,
    String? albumTitle,
    String? albumId,
    String? artworkUrl,
    String? artworkPath,
    String? description,
    String? genre,
    String? streamUrl,
    String? localPath,
    int? durationSeconds,
    bool? downloadable,
    bool? isStreamable,
    TrackOrigin? origin,
    DateTime? releasedAt,
    bool clearArtworkUrl = false,
    bool clearArtworkPath = false,
    bool clearStreamUrl = false,
    bool clearLocalPath = false,
  }) {
    return MusicTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      artistName: artistName ?? this.artistName,
      artistId: artistId ?? this.artistId,
      albumTitle: albumTitle ?? this.albumTitle,
      albumId: albumId ?? this.albumId,
      artworkUrl: clearArtworkUrl ? null : artworkUrl ?? this.artworkUrl,
      artworkPath: clearArtworkPath ? null : artworkPath ?? this.artworkPath,
      description: description ?? this.description,
      genre: genre ?? this.genre,
      streamUrl: clearStreamUrl ? null : streamUrl ?? this.streamUrl,
      localPath: clearLocalPath ? null : localPath ?? this.localPath,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      downloadable: downloadable ?? this.downloadable,
      isStreamable: isStreamable ?? this.isStreamable,
      origin: origin ?? this.origin,
      releasedAt: releasedAt ?? this.releasedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'artistName': artistName,
      'artistId': artistId,
      'albumTitle': albumTitle,
      'albumId': albumId,
      'artworkUrl': artworkUrl,
      'artworkPath': artworkPath,
      'description': description,
      'genre': genre,
      'streamUrl': streamUrl,
      'localPath': localPath,
      'durationSeconds': durationSeconds,
      'downloadable': downloadable,
      'isStreamable': isStreamable,
      'origin': origin.name,
      'releasedAt': releasedAt?.toIso8601String(),
    };
  }

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Unknown track',
      artistName: json['artistName'] as String? ?? 'Unknown artist',
      artistId:
          json['artistId'] as String? ??
          _slugify(json['artistName'] as String? ?? 'unknown-artist'),
      albumTitle: json['albumTitle'] as String? ?? '',
      albumId: json['albumId'] as String?,
      artworkUrl: json['artworkUrl'] as String?,
      artworkPath: json['artworkPath'] as String?,
      description: json['description'] as String?,
      genre: json['genre'] as String?,
      streamUrl: json['streamUrl'] as String?,
      localPath: json['localPath'] as String?,
      durationSeconds: json['durationSeconds'] as int?,
      downloadable: json['downloadable'] as bool? ?? false,
      isStreamable:
          json['isStreamable'] as bool? ??
          ((json['streamUrl'] as String?)?.isNotEmpty ?? false),
      origin: trackOriginFromJson(json['origin'] as String?),
      releasedAt:
          json['releasedAt'] == null
              ? null
              : DateTime.tryParse(json['releasedAt'] as String),
    );
  }

  static List<MusicTrack> listFromJson(String raw) {
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(MusicTrack.fromJson)
        .toList();
  }

  static String listToJson(List<MusicTrack> tracks) {
    return jsonEncode(tracks.map((track) => track.toJson()).toList());
  }
}

String _slugify(String value) {
  final normalized = value.toLowerCase().trim().replaceAll('&', 'and');
  return normalized
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}
