class GradingBatch {
  final String id;
  final String batchName; // Display name for this grading session
  final String examId;
  final String questionId;
  final String examTitle;
  final String questionTitle;
  final int totalItems;
  final int completedItems;
  final int failedItems; // New: track errors
  final String status; // 'Processing', 'Completed', 'Error'
  final String? sheetUrl; // New: link to Google Sheet
  final DateTime createdAt;

  GradingBatch({
    required this.id,
    required this.batchName,
    required this.examId,
    required this.questionId,
    required this.examTitle,
    required this.questionTitle,
    required this.totalItems,
    required this.completedItems,
    this.failedItems = 0,
    required this.status,
    this.sheetUrl,
    required this.createdAt,
  });

  static String _parseId(dynamic val) {
    if (val is String) return val;
    if (val is Map && val.containsKey('\$oid')) return val['\$oid'].toString();
    return val?.toString() ?? '';
  }

  factory GradingBatch.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic d) {
      if (d == null) return DateTime.now();
      if (d is DateTime) return d;
      try {
        return DateTime.parse(d.toString());
      } catch (_) {
        return DateTime.now();
      }
    }

    return GradingBatch(
      id: _parseId(json['_id']),
      batchName: json['batchName']?.toString() ?? 'Chấm bài',
      examId: _parseId(json['examId']),
      questionId: _parseId(json['questionId']),
      examTitle: json['examTitle']?.toString() ?? 'Chưa xác định',
      questionTitle: json['questionTitle']?.toString() ?? 'Chưa xác định',
      totalItems: (json['totalItems'] as num? ?? 0).toInt(),
      completedItems: (json['completedItems'] as num? ?? 0).toInt(),
      failedItems: (json['failedItems'] as num? ?? 0).toInt(),
      status: (json['status'] ?? 'Processing').toString(),
      sheetUrl: json['sheetUrl']?.toString(),
      createdAt: parseDate(json['createdAt']),
    );
  }
}
