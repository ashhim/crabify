class DeviceAudioCandidate {
  const DeviceAudioCandidate({
    required this.path,
    required this.title,
    required this.artistName,
    this.sourceUri,
    this.albumTitle,
    this.durationSeconds,
  });

  final String path;
  final String title;
  final String artistName;
  final String? sourceUri;
  final String? albumTitle;
  final int? durationSeconds;

  factory DeviceAudioCandidate.fromJson(Map<Object?, Object?> json) {
    return DeviceAudioCandidate(
      path: json['path']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown track',
      artistName: json['artistName']?.toString() ?? 'Unknown artist',
      sourceUri: json['sourceUri']?.toString(),
      albumTitle: json['albumTitle']?.toString(),
      durationSeconds: _toInt(json['durationSeconds']),
    );
  }

  static int? _toInt(Object? value) {
    return switch (value) {
      int intValue => intValue,
      num numValue => numValue.toInt(),
      String stringValue => int.tryParse(stringValue),
      _ => null,
    };
  }
}
