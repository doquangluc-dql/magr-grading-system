class GradingSession {
  String id;
  String examId;
  String? questionId; // NEW: To track which question this session belongs to
  String studentName;
  DateTime createdAt;
  String n8nStatus; // e.g. 'Pending', 'Success', 'Failed'
  String? sheetUrl;
  String? studentImageBase64; 
  String? errorDetails;
  double? score; // NEW
  String? feedback; // NEW

  GradingSession({
    required this.id,
    required this.examId,
    this.questionId,
    required this.studentName,
    required this.createdAt,
    this.n8nStatus = 'Pending',
    this.sheetUrl,
    this.studentImageBase64,
    this.errorDetails,
    this.score,
    this.feedback,
  });

  factory GradingSession.fromJson(Map<String, dynamic> json) {
    return GradingSession(
      id: json['_id']?.toString() ?? '',
      examId: json['examId'] as String,
      questionId: json['questionId'] as String?,
      studentName: json['studentName'] as String,
      createdAt: json['createdAt'] is DateTime
          ? json['createdAt']
          : DateTime.parse(json['createdAt'].toString()),
      n8nStatus: json['n8nStatus'] as String? ?? 'Pending',
      sheetUrl: json['sheetUrl'] as String?,
      studentImageBase64: json['studentImageBase64'] as String?,
      errorDetails: json['errorDetails'] as String?,
      score: json['score'] != null ? (json['score'] as num).toDouble() : null,
      feedback: json['feedback'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) '_id': id,
      'examId': examId,
      if (questionId != null) 'questionId': questionId,
      'studentName': studentName,
      'createdAt': createdAt.toIso8601String(),
      'n8nStatus': n8nStatus,
      if (sheetUrl != null) 'sheetUrl': sheetUrl,
      if (studentImageBase64 != null) 'studentImageBase64': studentImageBase64,
      if (errorDetails != null) 'errorDetails': errorDetails,
      if (score != null) 'score': score,
      if (feedback != null) 'feedback': feedback,
    };
  }
}
