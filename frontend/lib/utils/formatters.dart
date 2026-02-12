const _nairaSymbol = '\u20A6';

String formatNaira(
  dynamic value, {
  int decimals = 2,
  bool compact = false,
}) {
  final parsed = value is num
      ? value.toDouble()
      : double.tryParse((value ?? "").toString()) ?? 0.0;
  final safeDecimals = decimals < 0 ? 0 : decimals;
  final abs = parsed.abs();

  if (compact) {
    if (abs >= 1000000000) {
      return "$_nairaSymbol${(parsed / 1000000000).toStringAsFixed(1)}B";
    }
    if (abs >= 1000000) {
      return "$_nairaSymbol${(parsed / 1000000).toStringAsFixed(1)}M";
    }
    if (abs >= 1000) {
      return "$_nairaSymbol${(parsed / 1000).toStringAsFixed(1)}K";
    }
  }

  final fixed = parsed.toStringAsFixed(safeDecimals);
  final parts = fixed.split(".");
  final chars = parts[0].split("").reversed.toList();
  final grouped = <String>[];
  for (int i = 0; i < chars.length; i++) {
    if (i > 0 && i % 3 == 0) {
      grouped.add(",");
    }
    grouped.add(chars[i]);
  }
  final whole = grouped.reversed.join();
  if (safeDecimals == 0) {
    return "$_nairaSymbol$whole";
  }
  return "$_nairaSymbol$whole.${parts[1]}";
}

String formatRelativeTime(dynamic rawIso) {
  final raw = (rawIso ?? "").toString().trim();
  if (raw.isEmpty) return "recent";
  try {
    final timestamp = DateTime.parse(raw).toLocal();
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return "just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours < 24) return "${diff.inHours}h ago";
    if (diff.inDays < 30) return "${diff.inDays}d ago";
    final months = (diff.inDays / 30).floor();
    if (months < 12) return "${months}mo ago";
    final years = (months / 12).floor();
    return "${years}y ago";
  } catch (_) {
    return "recent";
  }
}
