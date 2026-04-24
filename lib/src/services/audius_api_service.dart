import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/music_track.dart';
import '../models/upload_draft.dart';

class AudiusApiService {
  AudiusApiService()
    : _dio = Dio(
        BaseOptions(
          receiveTimeout: const Duration(seconds: 12),
          connectTimeout: const Duration(seconds: 12),
        ),
      );

  static const String _seedBaseUrl = 'https://api.audius.co';
  static const String _bearerToken = String.fromEnvironment(
    'AUDIUS_BEARER_TOKEN',
  );
  static const String _uploadProxyEndpoint = String.fromEnvironment(
    'CRABIFY_UPLOAD_PROXY',
  );

  final Dio _dio;
  String? _discoveredBaseUrl;
  Future<String>? _discoveryRequest;

  bool get hasUploadProxy => _uploadProxyEndpoint.isNotEmpty;
  String get seedBaseUrl => _seedBaseUrl;

  Future<List<MusicTrack>> fetchTrendingTracks({int limit = 12}) async {
    await discoverProviderUrl();
    final baseUrl = seedBaseUrl;
    debugPrint('[Audius] Fetching trending tracks from $baseUrl');

    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/v1/tracks/trending',
      queryParameters: <String, dynamic>{'limit': limit * 3, 'time': 'week'},
      options: Options(headers: _headers),
    );

    final tracks =
        _extractDataList(
          response.data,
        ).map(_mapTrack).where(_isPlayableAudiusTrack).take(limit).toList();

    if (tracks.isEmpty) {
      throw StateError('Audius returned no playable trending tracks.');
    }

    debugPrint('[Audius] Trending tracks loaded: ${tracks.length}');
    return tracks;
  }

  Future<List<MusicTrack>> searchTracks(String query, {int limit = 12}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return fetchTrendingTracks(limit: limit);
    }

    await discoverProviderUrl();
    final baseUrl = seedBaseUrl;
    debugPrint('[Audius] Searching "$trimmed"');

    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/v1/tracks/search',
      queryParameters: <String, dynamic>{'query': trimmed, 'limit': limit * 3},
      options: Options(headers: _headers),
    );

    final tracks = _filterRelevantTracks(
      _extractDataList(
        response.data,
      ).map(_mapTrack).where(_isPlayableAudiusTrack),
      trimmed,
      limit: limit,
    );

    debugPrint('[Audius] Search matches kept: ${tracks.length}');
    return tracks;
  }

  Future<String> discoverProviderUrl() async {
    if (_discoveredBaseUrl != null && _discoveredBaseUrl!.isNotEmpty) {
      return _discoveredBaseUrl!;
    }
    if (_discoveryRequest != null) {
      return _discoveryRequest!;
    }

    _discoveryRequest = _discoverProviderUrl();
    final discovered = await _discoveryRequest!;
    _discoveryRequest = null;
    return discovered;
  }

  Future<String> fetchFreshStreamUrl(MusicTrack track) async {
    await discoverProviderUrl();
    final baseUrl = seedBaseUrl;
    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/v1/tracks/${track.id}/stream',
      queryParameters: const <String, dynamic>{'no_redirect': true},
      options: Options(headers: _headers),
    );

    final url = response.data?['data'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError(
        'Audius did not return a stream URL for ${track.title}.',
      );
    }

    debugPrint('[Audius] Fresh stream URL resolved for ${track.id}');
    return url;
  }

  String resolveStreamUrlById(String trackId) {
    return Uri(
      scheme: 'https',
      host: 'api.audius.co',
      path: '/v1/tracks/$trackId/stream',
    ).toString();
  }

  String resolveStreamUrl(MusicTrack track) {
    return resolveStreamUrlById(track.id);
  }

  Future<bool> submitUpload(UploadDraft draft) async {
    if (!hasUploadProxy) {
      return false;
    }

    final formData = FormData.fromMap(<String, dynamic>{
      'title': draft.title,
      'artist': draft.artistName,
      'genre': draft.genre,
      'description': draft.description,
      'allowDownload': draft.allowDownload,
      'audio': await MultipartFile.fromFile(draft.audioFilePath),
      if (draft.coverImagePath != null && draft.coverImagePath!.isNotEmpty)
        'cover': await MultipartFile.fromFile(draft.coverImagePath!),
    });

    try {
      await _dio.postUri(
        Uri.parse(_uploadProxyEndpoint),
        data: formData,
        options: Options(headers: _headers),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Map<String, String> get _headers {
    if (_bearerToken.isEmpty) {
      return const <String, String>{};
    }

    return <String, String>{'Authorization': 'Bearer $_bearerToken'};
  }

  List<Map<String, dynamic>> _extractDataList(Map<String, dynamic>? payload) {
    final data = payload?['data'];
    if (data is List<dynamic>) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    return <Map<String, dynamic>>[];
  }

  MusicTrack _mapTrack(Map<String, dynamic> json) {
    final artwork = _asMap(json['artwork']);
    final artist = _asMap(json['user']);
    final artistPicture = _asMap(artist?['profile_picture']);
    final access = _asMap(json['access']);

    final id = json['id']?.toString() ?? 'audius-${json.hashCode}';
    final title = json['title'] as String? ?? 'Untitled track';
    final artistName =
        artist?['name'] as String? ??
        artist?['handle'] as String? ??
        'Audius Artist';
    final artistId =
        artist?['id']?.toString() ??
        artistName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    final albumTitle = switch (json['album_backlink']) {
      Map<String, dynamic> album => album['title'] as String? ?? '',
      String value => value,
      _ => '',
    };
    final downloadable =
        _asBool(json['is_downloadable']) ??
        _asBool(json['downloadable']) ??
        _asBool(access?['download']) ??
        false;
    final streamable =
        _asBool(json['is_streamable']) ?? _asBool(access?['stream']) ?? false;
    final artworkUrl =
        _artworkUrlFrom(artwork) ?? _artworkUrlFrom(artistPicture);

    return MusicTrack(
      id: id,
      title: title,
      artistName: artistName,
      artistId: artistId,
      albumTitle: albumTitle,
      artworkUrl: artworkUrl,
      description: json['description'] as String?,
      genre: json['genre'] as String?,
      streamUrl: streamable ? resolveStreamUrlById(id) : null,
      durationSeconds: _asInt(json['duration']),
      downloadable: downloadable,
      isStreamable: streamable,
      origin: TrackOrigin.online,
      releasedAt:
          json['release_date'] == null && json['releaseDate'] == null
              ? null
              : DateTime.tryParse(
                (json['release_date'] ?? json['releaseDate']) as String,
              ),
    );
  }

  Future<String> _discoverProviderUrl() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _seedBaseUrl,
        options: Options(headers: _headers),
      );
      final providers =
          (response.data?['data'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .where((provider) => provider.startsWith('http'))
              .toList();
      _discoveredBaseUrl =
          providers.contains(_seedBaseUrl)
              ? _seedBaseUrl
              : providers.isNotEmpty
              ? providers.first
              : _seedBaseUrl;
      debugPrint('[Audius] Provider discovered: $_discoveredBaseUrl');
      return _discoveredBaseUrl!;
    } catch (error) {
      debugPrint(
        '[Audius] Provider discovery failed, using $_seedBaseUrl: $error',
      );
      _discoveredBaseUrl = _seedBaseUrl;
      return _discoveredBaseUrl!;
    }
  }

  Map<String, dynamic>? _asMap(Object? value) {
    return value is Map<String, dynamic> ? value : null;
  }

  bool? _asBool(Object? value) {
    return switch (value) {
      bool boolValue => boolValue,
      num numberValue => numberValue != 0,
      String stringValue => switch (stringValue.toLowerCase()) {
        'true' || '1' => true,
        'false' || '0' => false,
        _ => null,
      },
      _ => null,
    };
  }

  int? _asInt(Object? value) {
    return switch (value) {
      int intValue => intValue,
      num numberValue => numberValue.toInt(),
      String stringValue => int.tryParse(stringValue),
      _ => null,
    };
  }

  String? _artworkUrlFrom(Map<String, dynamic>? artwork) {
    if (artwork == null) {
      return null;
    }

    for (final key in const <String>[
      '1000x1000',
      '480x480',
      '150x150',
      '_1000x1000',
      '_480x480',
      '_150x150',
    ]) {
      final value = artwork[key] as String?;
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }

  bool _isPlayableAudiusTrack(MusicTrack track) {
    return track.isStreamable &&
        track.streamUrl != null &&
        track.streamUrl!.isNotEmpty;
  }

  List<MusicTrack> _filterRelevantTracks(
    Iterable<MusicTrack> tracks,
    String query, {
    required int limit,
  }) {
    final normalized = query.trim().toLowerCase();
    final terms =
        normalized
            .split(RegExp(r'\s+'))
            .where((term) => term.trim().isNotEmpty)
            .toList();

    final scored =
        tracks
            .map((track) {
              final title = track.title.toLowerCase();
              final artist = track.artistName.toLowerCase();
              final album = track.albumTitle.toLowerCase();
              final searchable = '$title $artist $album';

              var score = 0;
              if (title == normalized || artist == normalized) {
                score += 300;
              }
              if (title.contains(normalized)) {
                score += 180;
              }
              if (artist.contains(normalized)) {
                score += 140;
              }
              if (searchable.contains(normalized)) {
                score += 80;
              }

              var matchedTerms = 0;
              for (final term in terms) {
                if (title.contains(term)) {
                  matchedTerms += 1;
                  score += 30;
                  continue;
                }
                if (artist.contains(term)) {
                  matchedTerms += 1;
                  score += 24;
                  continue;
                }
                if (album.contains(term)) {
                  matchedTerms += 1;
                  score += 12;
                }
              }

              if (terms.isNotEmpty && matchedTerms == terms.length) {
                score += 60;
              }

              return (track: track, score: score);
            })
            .where((entry) {
              if (normalized.length <= 2) {
                return entry.score >= 140;
              }
              return entry.score >= 60;
            })
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));

    return scored.take(limit).map((entry) => entry.track).toList();
  }
}
