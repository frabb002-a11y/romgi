/// IGDB platform list sort key (see igdb.com weighted rating).
const double igdbBayesianM = 49;
const double igdbBayesianC = 66.9;

double igdbWeightedRating(
  double rating,
  int ratingCount, {
  double m = igdbBayesianM,
  double c = igdbBayesianC,
}) {
  return (ratingCount * rating + m * c) / (ratingCount + m);
}

/// User `rating` is 0–100; UI shows one decimal on a 0–10 scale.
double? igdbDisplayScoreFromRating(double? rating) {
  if (rating == null || rating.isNaN) return null;
  return (rating / 10).roundToDouble() == rating / 10
      ? rating / 10
      : double.parse((rating / 10).toStringAsFixed(1));
}

int compareIgdbRank(
  double weightedA,
  int votesA,
  int idA,
  double weightedB,
  int votesB,
  int idB,
) {
  if (weightedA != weightedB) {
    return weightedB.compareTo(weightedA);
  }
  if (votesA != votesB) {
    return votesB.compareTo(votesA);
  }
  return idA.compareTo(idB);
}
