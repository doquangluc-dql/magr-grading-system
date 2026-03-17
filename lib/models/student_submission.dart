class StudentSubmission {
  String id;
  String examId;
  String questionId; // NEW: Associate with a specific question
  String studentName;
  String imageBase64;
  DateTime createdAt;

  StudentSubmission({
    required this.id,
    required this.examId,
    required this.questionId,
    required this.studentName,
    required this.imageBase64,
    required this.createdAt,
  });

  factory StudentSubmission.fromJson(Map<String, dynamic> json) {
    return StudentSubmission(
      id: json['_id']?.toString() ?? '',
      examId: json['examId'] as String,
      questionId: json['questionId'] as String? ?? '', // Support legacy or handle missing
      studentName: json['studentName'] as String,
      imageBase64: json['imageBase64'] as String? ?? '',
      createdAt: json['createdAt'] is DateTime
          ? json['createdAt']
          : DateTime.parse(json['createdAt'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) '_id': id,
      'examId': examId,
      'questionId': questionId,
      'studentName': studentName,
      'imageBase64': imageBase64,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
