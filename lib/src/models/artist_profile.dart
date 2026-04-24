class ArtistProfile {
  const ArtistProfile({
    required this.id,
    required this.name,
    required this.description,
    required this.topTrackIds,
    required this.collectionIds,
    this.artworkUrl,
    this.artworkPath,
  });

  final String id;
  final String name;
  final String description;
  final List<String> topTrackIds;
  final List<String> collectionIds;
  final String? artworkUrl;
  final String? artworkPath;

  ArtistProfile copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? topTrackIds,
    List<String>? collectionIds,
    String? artworkUrl,
    String? artworkPath,
    bool clearArtworkUrl = false,
    bool clearArtworkPath = false,
  }) {
    return ArtistProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      topTrackIds: topTrackIds ?? this.topTrackIds,
      collectionIds: collectionIds ?? this.collectionIds,
      artworkUrl: clearArtworkUrl ? null : artworkUrl ?? this.artworkUrl,
      artworkPath: clearArtworkPath ? null : artworkPath ?? this.artworkPath,
    );
  }
}
