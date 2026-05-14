class ScriptOutputModel {
  final String id;
  final String script;
  final String model;
  final int tokensUsed;
  final int executionTime;
  final DateTime timestamp;

  ScriptOutputModel({
    required this.id,
    required this.script,
    required this.model,
    required this.tokensUsed,
    required this.executionTime,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'script': script,
      'model': model,
      'tokensUsed': tokensUsed,
      'executionTime': executionTime,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ScriptOutputModel.fromMap(Map<String, dynamic> map) {
    return ScriptOutputModel(
      id: map['id'] ?? '',
      script: map['script'] ?? '',
      model: map['model'] ?? 'unknown',
      tokensUsed: map['tokensUsed'] ?? 0,
      executionTime: map['executionTime'] ?? 0,
      timestamp: map['timestamp'] is DateTime
          ? map['timestamp']
          : DateTime.parse(
              map['timestamp'] ?? DateTime.now().toIso8601String(),
            ),
    );
  }
}
