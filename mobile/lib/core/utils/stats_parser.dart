/// Safely parses an integer count from a stats API response.
/// Handles both [num] and [String] values defensively, since some backend
/// versions return stat counts as JSON strings instead of numbers.
int parseStatCount(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
