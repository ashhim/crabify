import 'dart:convert';

enum TrackOrigin { online, local, downloaded, uploaded }

class ArtistCredit {
  const ArtistCredit({required this.id, required this.name});

  final String id;
  final String name;
}

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
    this.artistNames = const <String>[],
    this.artistIds = const <String>[],
    this.albumId,
    this.artworkUrl,
    this.artworkPath,
    this.description,
    this.genre,
    this.streamUrl,
    this.localPath,
    this.sourcePath,
    this.durationSeconds,
    this.downloadable = false,
    this.isStreamable = false,
    this.releasedAt,
  });

  final String id;
  final String title;
  final String artistName;
  final String artistId;
  final List<String> artistNames;
  final List<String> artistIds;
  final String albumTitle;
  final String? albumId;
  final String? artworkUrl;
  final String? artworkPath;
  final String? description;
  final String? genre;
  final String? streamUrl;
  final String? localPath;
  final String? sourcePath;
  final int? durationSeconds;
  final bool downloadable;
  final bool isStreamable;
  final TrackOrigin origin;
  final DateTime? releasedAt;

  Duration? get duration =>
      durationSeconds == null ? null : Duration(seconds: durationSeconds!);

  bool get hasValidId => id.trim().isNotEmpty;
  bool get isLocal => localPath != null && localPath!.trim().isNotEmpty;
  bool get hasValidLocalSource => isLocal;
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
  bool get isPlayable => hasValidLocalSource || isRemote;
  bool get isOfflineAvailable => isLocal;
  List<String> get creditedArtistNames {
    final names =
        artistNames.isNotEmpty ? sanitizeArtistNames(artistNames) : _parseArtistNames(artistName);
    return names.isEmpty ? <String>['Unknown artist'] : names;
  }

  List<String> get creditedArtistIds {
    final ids =
        artistIds.isNotEmpty
            ? artistIds.map(canonicalArtistIdentity).toList()
            : creditedArtistNames.map(canonicalArtistIdentity).toList();
    final deduped = <String>[];
    for (final id in ids) {
      if (id.isEmpty || deduped.contains(id)) {
        continue;
      }
      deduped.add(id);
    }
    return deduped.isEmpty
        ? <String>[canonicalArtistIdentity(artistId.isEmpty ? artistName : artistId)]
        : deduped;
  }

  List<ArtistCredit> get artistCredits {
    final names = creditedArtistNames;
    final ids = creditedArtistIds;
    final credits = <ArtistCredit>[];
    for (var index = 0; index < names.length; index += 1) {
      final name = names[index];
      final id =
          index < ids.length && ids[index].trim().isNotEmpty
              ? ids[index]
              : canonicalArtistIdentity(name);
      if (credits.any((credit) => credit.id == id)) {
        continue;
      }
      credits.add(ArtistCredit(id: id, name: name));
    }
    return credits.isEmpty
        ? <ArtistCredit>[
          ArtistCredit(
            id: canonicalArtistIdentity(artistId.isEmpty ? artistName : artistId),
            name: artistName.isEmpty ? 'Unknown artist' : artistName,
          ),
        ]
        : credits;
  }

  bool hasArtistIdentity(String candidate) {
    final normalized = canonicalArtistIdentity(candidate);
    if (normalized.isEmpty) {
      return false;
    }
    return creditedArtistIds.contains(normalized);
  }

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
    List<String>? artistNames,
    List<String>? artistIds,
    String? albumTitle,
    String? albumId,
    String? artworkUrl,
    String? artworkPath,
    String? description,
    String? genre,
    String? streamUrl,
    String? localPath,
    String? sourcePath,
    int? durationSeconds,
    bool? downloadable,
    bool? isStreamable,
    TrackOrigin? origin,
    DateTime? releasedAt,
    bool clearArtworkUrl = false,
    bool clearArtworkPath = false,
    bool clearDescription = false,
    bool clearGenre = false,
    bool clearAlbumId = false,
    bool clearStreamUrl = false,
    bool clearLocalPath = false,
    bool clearSourcePath = false,
  }) {
    return MusicTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      artistName: artistName ?? this.artistName,
      artistId: artistId ?? this.artistId,
      artistNames: artistNames ?? this.artistNames,
      artistIds: artistIds ?? this.artistIds,
      albumTitle: albumTitle ?? this.albumTitle,
      albumId: clearAlbumId ? null : albumId ?? this.albumId,
      artworkUrl: clearArtworkUrl ? null : artworkUrl ?? this.artworkUrl,
      artworkPath: clearArtworkPath ? null : artworkPath ?? this.artworkPath,
      description: clearDescription ? null : description ?? this.description,
      genre: clearGenre ? null : genre ?? this.genre,
      streamUrl: clearStreamUrl ? null : streamUrl ?? this.streamUrl,
      localPath: clearLocalPath ? null : localPath ?? this.localPath,
      sourcePath: clearSourcePath ? null : sourcePath ?? this.sourcePath,
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
      'artistNames': artistNames,
      'artistIds': artistIds,
      'albumTitle': albumTitle,
      'albumId': albumId,
      'artworkUrl': artworkUrl,
      'artworkPath': artworkPath,
      'description': description,
      'genre': genre,
      'streamUrl': streamUrl,
      'localPath': localPath,
      'sourcePath': sourcePath,
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
          canonicalArtistIdentity(json['artistName'] as String? ?? 'unknown-artist'),
      artistNames:
          sanitizeArtistNames(
            (json['artistNames'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<String>(),
          ),
      artistIds:
          sanitizeArtistNames(
            (json['artistIds'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<String>(),
          ).map(canonicalArtistIdentity).toList(),
      albumTitle: json['albumTitle'] as String? ?? '',
      albumId: json['albumId'] as String?,
      artworkUrl: json['artworkUrl'] as String?,
      artworkPath: json['artworkPath'] as String?,
      description: json['description'] as String?,
      genre: json['genre'] as String?,
      streamUrl: json['streamUrl'] as String?,
      localPath: json['localPath'] as String?,
      sourcePath: json['sourcePath'] as String?,
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

List<String> sanitizeArtistNames(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final rawValue in values) {
    final value = rawValue.trim();
    final key = canonicalArtistIdentity(value);
    if (value.isEmpty || key.isEmpty || seen.contains(key)) {
      continue;
    }
    seen.add(key);
    result.add(value);
  }
  return result;
}

List<String> parseArtistNames(String value) => _parseArtistNames(value);

String buildArtistDisplayName(Iterable<String> values) {
  final names = sanitizeArtistNames(values);
  if (names.isEmpty) {
    return 'Unknown artist';
  }
  return names.join(', ');
}

List<String> _parseArtistNames(String value) {
  return sanitizeArtistNames(
    value
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty),
  );
}

String canonicalArtistIdentity(String value) {
  final normalized = value.toLowerCase().trim();
  if (normalized.isEmpty) {
    return '';
  }
  return normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '');
}
