class CommentGroup {
  final String tone;
  final List<String> comments;

  const CommentGroup({required this.tone, required this.comments});
}

class CommentOutput {
  final String inputText;
  final List<CommentGroup> groups;
  final DateTime generatedAt;

  const CommentOutput({
    required this.inputText,
    required this.groups,
    required this.generatedAt,
  });

  Map<String, dynamic> toJson() => {
        'inputText': inputText,
        'groups': groups.map((g) => {'tone': g.tone, 'comments': g.comments}).toList(),
        'generatedAt': generatedAt.toIso8601String(),
      };
}