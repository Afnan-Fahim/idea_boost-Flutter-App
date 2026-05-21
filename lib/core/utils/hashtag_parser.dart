/// Shared hashtag extraction and inline formatting patterns.
///
/// Supports multi-word hashtags such as `#problem solver` as a single token.
class HashtagParser {
  HashtagParser._();

  /// Matches `#tag` or `#multi word tag` (space-separated word characters).
  static final RegExp tokenPattern = RegExp(
    r'#[\p{L}\p{N}_]+(?:\s+[\p{L}\p{N}_]+)*',
    unicode: true,
  );

  /// Matches `**bold**` or hashtag tokens for rich-text rendering.
  static final RegExp inlineFormatPattern = RegExp(
    r'\*\*(.*?)\*\*|(#[\p{L}\p{N}_]+(?:\s+[\p{L}\p{N}_]+)*)',
    unicode: true,
  );

  /// Parse [input] and append unique hashtags into [tags].
  static void parseInto(String input, List<String> tags) {
    if (input.isEmpty) return;

    final matches = tokenPattern.allMatches(input);
    if (matches.isNotEmpty) {
      for (final match in matches) {
        final tag = cleanToken(match.group(0)!);
        if (tag.isNotEmpty && !tags.contains(tag)) {
          tags.add(tag);
        }
      }
      return;
    }

    for (final part in input.split(RegExp(r'[\s,]+'))) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final tag = trimmed.startsWith('#') ? trimmed : '#$trimmed';
      final cleaned = cleanToken(tag);
      if (cleaned.isNotEmpty && !tags.contains(cleaned)) {
        tags.add(cleaned);
      }
    }
  }

  static List<String> extractFromString(String value) {
    final tags = <String>[];
    parseInto(value, tags);
    return tags;
  }

  static List<String> extractFromDynamic(dynamic source) {
    final tags = <String>[];

    void addTag(dynamic value) {
      final text = value?.toString().trim() ?? '';
      if (text.isEmpty) return;
      final normalized = text.startsWith('#') ? text : '#$text';
      final cleaned = cleanToken(normalized);
      if (cleaned.isNotEmpty && !tags.contains(cleaned)) {
        tags.add(cleaned);
      }
    }

    void walk(dynamic value) {
      if (value == null) return;

      if (value is String) {
        final extracted = extractFromString(value);
        if (extracted.isNotEmpty) {
          for (final tag in extracted) {
            if (!tags.contains(tag)) tags.add(tag);
          }
        } else {
          for (final part in value.split(RegExp(r'[\s,]+'))) {
            if (part.trim().isNotEmpty) addTag(part);
          }
        }
        return;
      }

      if (value is Iterable) {
        for (final entry in value) {
          walk(entry);
        }
        return;
      }

      if (value is Map) {
        walk(value['hashtags']);
        walk(value['content']);
        walk(value['items']);
        walk(value['tags']);
        final category = value['category'];
        if (category is String && category.trim().isNotEmpty) {
          final categoryText = category.trim();
          if (categoryText.contains('#')) walk(categoryText);
        }
        return;
      }

      addTag(value);
    }

    walk(source);
    return tags;
  }

  /// Strip trailing punctuation from a hashtag token (keeps internal spaces).
  static String cleanToken(String hashtag) {
    var cleaned = hashtag.trim();
    cleaned = cleaned.replaceAll(
      RegExp(r'[^\p{L}\p{N}_#\s]+$', unicode: true),
      '',
    );
    return cleaned.trim();
  }
}
