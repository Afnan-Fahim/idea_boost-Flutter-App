import 'package:cloud_firestore/cloud_firestore.dart';

class HistoryItem {
  final String id;
  final String type;
  final String prompt;
  final Map<String, dynamic> output;
  final DateTime generatedAt;
  final Map<String, dynamic> meta;

  HistoryItem({
    required this.id,
    required this.type,
    required this.prompt,
    required this.output,
    required this.generatedAt,
    required this.meta,
  });

  factory HistoryItem.fromFirestore(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final genAt = data['generatedAt'];
    DateTime parsed;
    if (genAt is Timestamp) {
      parsed = genAt.toDate();
    } else if (genAt is String) {
      parsed = DateTime.tryParse(genAt) ?? DateTime.now();
    } else {
      parsed = DateTime.now();
    }

    final rawOutput = data['output'];
    final parsedOutput = rawOutput is Map<String, dynamic>
        ? rawOutput
        : <String, dynamic>{'value': rawOutput};

    final rawMeta = data['meta'];
    final parsedMeta = rawMeta is Map<String, dynamic>
        ? rawMeta
        : <String, dynamic>{};

    return HistoryItem(
      id: doc.id,
      type: data['type'] as String? ?? '',
      prompt: data['prompt'] as String? ?? '',
      output: Map<String, dynamic>.from(parsedOutput),
      generatedAt: parsed,
      meta: Map<String, dynamic>.from(parsedMeta),
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type,
    'prompt': prompt,
    'output': output,
    'generatedAt': generatedAt.toIso8601String(),
    'meta': meta,
  };
}
