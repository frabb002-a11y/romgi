/// One IGDB game row shown when browsing catalog gaps (no ROM match).
class IgdbCatalogEntry {
  final String platform;
  final int gameId;
  final String name;
  final double rating;
  final int ratingCount;
  final double weighted;

  const IgdbCatalogEntry({
    required this.platform,
    required this.gameId,
    required this.name,
    required this.rating,
    required this.ratingCount,
    required this.weighted,
  });

  double get displayScore => (rating / 10 * 10).round() / 10;
}
