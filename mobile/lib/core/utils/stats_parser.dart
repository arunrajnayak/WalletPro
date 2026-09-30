/// Safely parses an integer count from a stats API response.
/// Handles both [num] and [String] values defensively, since some backend
/// versions return stat counts as JSON strings instead of numbers.
int parseStatCount(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// Safely parses a double from any dynamic value (num, String, or null).
double parseDouble(dynamic value, {double fallback = 0.0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

