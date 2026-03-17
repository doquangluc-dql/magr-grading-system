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

  static String _parseId(dynamic val) {
    if (val is String) return val;
    if (val is Map && val.containsKey('\$oid')) return val['\$oid'].toString();
    return val?.toString() ?? '';
  }

  factory GradingSession.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic d) {
      if (d == null) return DateTime.now();
      if (d is DateTime) return d;
      try {
        return DateTime.parse(d.toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    return GradingSession(
      id: _parseId(json['_id']),
      examId: _parseId(json['examId']),
      questionId: json['questionId'] != null ? _parseId(json['questionId']) : null,
      studentName: json['studentName']?.toString() ?? 'Ẩn danh',
      createdAt: parseDate(json['createdAt']),
      n8nStatus: (json['n8nStatus'] ?? 'Pending').toString(),
      sheetUrl: json['sheetUrl']?.toString(),
      studentImageBase64: json['studentImageBase64']?.toString(),
      errorDetails: json['errorDetails']?.toString(),
      score: json['score'] != null ? (json['score'] as num).toDouble() : null,
      feedback: json['feedback']?.toString(),
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
