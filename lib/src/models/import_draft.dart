class ImportDraft {
  const ImportDraft({
    required this.sourceAudioPath,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    this.genre,
    this.coverImagePath,
    this.embeddedArtworkBytes,
    this.embeddedArtworkMimeType,
    this.durationSeconds,
  });

  final String sourceAudioPath;
  final String title;
  final String artistName;
  final String albumTitle;
  final String? genre;
  final String? coverImagePath;
  final List<int>? embeddedArtworkBytes;
  final String? embeddedArtworkMimeType;
  final int? durationSeconds;

  bool get hasManualCover =>
      coverImagePath != null && coverImagePath!.trim().isNotEmpty;
  bool get hasEmbeddedArtwork =>
      embeddedArtworkBytes != null && embeddedArtworkBytes!.isNotEmpty;

  ImportDraft copyWith({
    String? sourceAudioPath,
    String? title,
    String? artistName,
    String? albumTitle,
    String? genre,
    String? coverImagePath,
    List<int>? embeddedArtworkBytes,
    String? embeddedArtworkMimeType,
    int? durationSeconds,
    bool clearCoverImagePath = false,
    bool clearEmbeddedArtwork = false,
  }) {
    return ImportDraft(
      sourceAudioPath: sourceAudioPath ?? this.sourceAudioPath,
      title: title ?? this.title,
      artistName: artistName ?? this.artistName,
      albumTitle: albumTitle ?? this.albumTitle,
      genre: genre ?? this.genre,
      coverImagePath:
          clearCoverImagePath ? null : coverImagePath ?? this.coverImagePath,
      embeddedArtworkBytes:
          clearEmbeddedArtwork
              ? null
              : embeddedArtworkBytes ?? this.embeddedArtworkBytes,
      embeddedArtworkMimeType:
          clearEmbeddedArtwork
              ? null
              : embeddedArtworkMimeType ?? this.embeddedArtworkMimeType,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }
}
