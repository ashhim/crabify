class UploadDraft {
  const UploadDraft({
    required this.title,
    required this.artistName,
    required this.genre,
    required this.description,
    required this.audioFilePath,
    required this.rightsConfirmed,
    this.coverImagePath,
    this.allowDownload = false,
  });

  final String title;
  final String artistName;
  final String genre;
  final String description;
  final String audioFilePath;
  final String? coverImagePath;
  final bool rightsConfirmed;
  final bool allowDownload;

  bool get isComplete =>
      title.trim().isNotEmpty &&
      artistName.trim().isNotEmpty &&
      genre.trim().isNotEmpty &&
      audioFilePath.trim().isNotEmpty &&
      rightsConfirmed;
}

class UploadSubmissionResult {
  const UploadSubmissionResult({
    required this.submittedRemotely,
    required this.message,
    this.remoteTrackId,
  });

  final bool submittedRemotely;
  final String message;
  final String? remoteTrackId;
}
