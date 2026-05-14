// lib/data/models/idea_model.dart
import 'package:equatable/equatable.dart';

class IdeaModel extends Equatable {
  final int id;
  final String title;
  final String description;
  final List<String> steps;
  final String cta;
  final String niche;
  final String format;
  final String level;
  final String? dataset; // 'ideas', 'youth', 'seasonal', or null for generic

  const IdeaModel({
    required this.id,
    required this.title,
    required this.description,
    required this.steps,
    required this.cta,
    required this.niche,
    required this.format,
    required this.level,
    this.dataset,
  });

  factory IdeaModel.fromJson(Map<String, dynamic> json) {
    return IdeaModel(
      id: json['id'] as int,
      title: json['title'] as String,
      description: json['description'] as String,
      steps: List<String>.from(json['steps'] as List),
      cta: json['cta'] as String,
      niche: json['niche'] as String,
      format: json['format'] as String,
      level: json['level'] as String,
      dataset: json['dataset'] as String?,
    );
  }

  factory IdeaModel.fromMap(Map<String, dynamic> map) {
    return IdeaModel(
      id: map['id'] as int,
      title: map['title'] as String,
      description: map['description'] as String,
      steps: List<String>.from(map['steps'] as List),
      cta: map['cta'] as String,
      niche: map['niche'] as String,
      format: map['format'] as String,
      level: map['level'] as String,
      dataset: map['dataset'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'steps': steps,
      'cta': cta,
      'niche': niche,
      'format': format,
      'level': level,
      if (dataset != null) 'dataset': dataset,
    };
  }

  @override
  List<Object?> get props => [
    id,
    title,
    description,
    steps,
    cta,
    niche,
    format,
    level,
    dataset,
  ];
}
