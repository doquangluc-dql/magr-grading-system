import 'barem_step.dart';

class Question {
  final String id;
  String title; // Cho phép Edit Tên Câu Hỏi
  String? content; // NỘI DUNG ĐỀ BÀI (MỚI)
  final DateTime createdAt;
  List<BaremStep> steps;

  Question({
    required this.id,
    required this.title,
    this.content,
    required this.createdAt,
    List<BaremStep>? steps,
  }) : this.steps = steps ?? [];

  factory Question.fromJson(Map<String, dynamic> json) {
    var rawSteps = json['steps'] as List<dynamic>? ?? [];
    List<BaremStep> parsedSteps = rawSteps
        .map((e) => BaremStep.fromJson(e as Map<String, dynamic>))
        .toList();

    return Question(
      id: json['_id']?.toString() ?? '',
      title: json['title'] as String? ?? 'Untitled',
      content: json['content'] as String?,
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt'].toString()) 
          : DateTime.now(),
      steps: parsedSteps,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) '_id': id,
      'title': title,
      'content': content,
      'createdAt': createdAt.toIso8601String(),
      'steps': steps.map((s) => s.toJson()).toList(),
    };
  }
}
