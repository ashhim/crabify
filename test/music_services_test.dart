import 'package:crabify/src/models/music_track.dart';
import 'package:crabify/src/models/upload_draft.dart';
import 'package:crabify/src/services/audius_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MusicTrack validates Audius stream sources defensively', () {
    const validAudiusTrack = MusicTrack(
      id: '4gg0KO9',
      title: 'Valid',
      artistName: 'Artist',
      artistId: 'artist',
      albumTitle: 'Album',
      origin: TrackOrigin.online,
      streamUrl: 'https://api.audius.co/v1/tracks/4gg0KO9/stream',
      isStreamable: true,
    );

    const invalidAudiusTrack = MusicTrack(
      id: 'crab-tide-01',
      title: 'Invalid',
      artistName: 'Artist',
      artistId: 'artist',
      albumTitle: 'Album',
      origin: TrackOrigin.online,
      streamUrl: 'https://api.audius.co/v1/tracks/crab-tide-01/stream',
      isStreamable: true,
    );

    expect(validAudiusTrack.hasValidRemoteSource, isTrue);
    expect(validAudiusTrack.isPlayable, isTrue);
    expect(invalidAudiusTrack.hasValidRemoteSource, isFalse);
    expect(invalidAudiusTrack.isPlayable, isFalse);
  });

  test('MusicTrack treats non-empty local paths as playable local sources', () {
    const localTrack = MusicTrack(
      id: 'local-1',
      title: 'Offline',
      artistName: 'Crabify',
      artistId: 'crabify',
      albumTitle: 'Local',
      origin: TrackOrigin.local,
      localPath: r'C:\music\offline.mp3',
    );

    expect(localTrack.hasValidLocalSource, isTrue);
    expect(localTrack.isPlayable, isTrue);
  });

  test('Audius upload falls back to local-only success without a proxy', () async {
    final service = AudiusApiService();
    const draft = UploadDraft(
      title: 'Local upload',
      artistName: 'Crabify',
      genre: 'Electronic',
      description: 'A local-first upload test.',
      audioFilePath: 'song.mp3',
      rightsConfirmed: true,
    );

    final result = await service.submitUpload(draft);

    expect(result.submittedRemotely, isFalse);
    expect(result.message, contains('saved locally'));
  });
}
