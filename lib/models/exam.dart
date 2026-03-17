class Exam {
  final String id;
  final String title;
  final DateTime createdAt;
  List<String> questionIds;
  String? googleSheetId;
  String? googleSheetUrl;

  Exam({
    required this.id,
    required this.title,
    required this.createdAt,
    List<String>? questionIds,
    this.googleSheetId,
    this.googleSheetUrl,
  }) : this.questionIds = questionIds ?? [];

  factory Exam.fromJson(Map<String, dynamic> json) {
    var rawQuestionIds = json['questionIds'] as List<dynamic>? ?? [];
    List<String> parsedQuestionIds = rawQuestionIds.map((e) => e.toString()).toList();

    return Exam(
      id: json['_id']?.toString() ?? '',
      title: json['title'] as String? ?? 'Untitled',
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt'].toString()) 
          : DateTime.now(),
      questionIds: parsedQuestionIds,
      googleSheetId: json['googleSheetId'] as String?,
      googleSheetUrl: json['googleSheetUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) '_id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'questionIds': questionIds,
      'googleSheetId': googleSheetId,
      'googleSheetUrl': googleSheetUrl,
    };
  }
}
