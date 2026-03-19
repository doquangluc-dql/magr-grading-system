import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/question.dart';
import '../models/exam.dart';
import '../models/barem_step.dart';
import '../models/grading_session.dart';
import '../models/student_submission.dart';
import '../models/grading_batch.dart';

class DatabaseApi {
  // --- CONFIGURATION ---
  // Dùng localhost khi đang phát triển để test nhanh code mới
  // static const String _baseUrl = "http://localhost:3000"; 
  static const String _baseUrl = "https://magr-grading-system.onrender.com"; 
  static const String _dataSource = "Cluster0";
  static const String _database = "magr_db";

  // --- MEMORY CACHING ---
  static final Map<String, List<StudentSubmission>> _submissionsCache = {};
  static final Map<String, List<GradingSession>> _gradingsCache = {};

  static void clearCache() {
    _submissionsCache.clear();
    _gradingsCache.clear();
  }

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Access-Control-Request-Headers': '*',
  };

  static Future<Map<String, dynamic>> _query(String action, String collection, Map<String, dynamic> body) async {
    final url = Uri.parse("$_baseUrl/action/$action");
    final payload = {
      "dataSource": _dataSource,
      "database": _database,
      "collection": collection,
      ...body,
    };

    final response = await http.post(url, headers: _headers, body: jsonEncode(payload));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body);
    } else {
      throw Exception("MongoDB API Error (${response.statusCode}): ${response.body}");
    }
  }

  // Helper to convert MongoDB JSON to regular JSON (handling $oid)
  static Map<String, dynamic> _cleanDoc(Map<String, dynamic> doc) {
    if (doc.containsKey('_id') && doc['_id'] is Map && doc['_id'].containsKey('\$oid')) {
      doc['_id'] = doc['_id']['\$oid'];
    }
    return doc;
  }

  // --- QUESTION BANK APIs ---

  static Future<List<Question>> getQuestions() async {
    try {
      final res = await _query("find", "questions", {});
      final List documents = res['documents'] ?? [];
      return documents.map((doc) => Question.fromJson(_cleanDoc(doc))).toList();
    } catch (e) {
      print("Error fetching questions: $e");
      return [];
    }
  }

  static Future<void> insertQuestion(Question question) async {
    try {
      final doc = question.toJson();
      doc.remove('_id'); // Let MongoDB generate ID
      await _query("insertOne", "questions", {"document": doc});
    } catch (e) {
      print("Error inserting question: $e");
    }
  }

  static Future<void> updateQuestionBarem(String questionId, List<BaremStep> steps) async {
    try {
      final stepsJson = steps.map((s) => s.toJson()).toList();
      await _query("updateOne", "questions", {
        "filter": {"_id": {"\$oid": questionId}},
        "update": {"\$set": {"steps": stepsJson}}
      });
    } catch (e) {
      print("Error updating barem: $e");
    }
  }

  // --- EXAM MANAGEMENT APIs ---

  static Future<List<Exam>> getExams() async {
    try {
      final res = await _query("find", "exams", {});
      final List documents = res['documents'] ?? [];
      return documents.map((doc) => Exam.fromJson(_cleanDoc(doc))).toList();
    } catch (e) {
      print("Error fetching exams: $e");
      return [];
    }
  }

  static Future<void> insertExam(Exam exam) async {
    try {
      final doc = exam.toJson();
      doc.remove('_id');
      await _query("insertOne", "exams", {"document": doc});
    } catch (e) {
      print("Error inserting exam: $e");
    }
  }

  static Future<void> deleteExam(String examId) async {
    try {
      await _query("deleteOne", "exams", {"filter": {"_id": {"\$oid": examId}}});
      await _query("deleteMany", "submissions", {"filter": {"examId": examId}});
      await _query("deleteMany", "gradings", {"filter": {"examId": examId}});
      clearCache();
    } catch (e) {
      print("Error deleting exam: $e");
    }
  }

  static Future<void> updateExamTitle(String examId, String newTitle) async {
    try {
      await _query("updateOne", "exams", {
        "filter": {"_id": {"\$oid": examId}},
        "update": {"\$set": {"title": newTitle}}
      });
    } catch (e) {
      print("Error updating exam title: $e");
    }
  }

  static Future<void> updateExamSheetInfo(String examId, String sheetId, String sheetUrl) async {
    try {
      await _query("updateOne", "exams", {
        "filter": {"_id": {"\$oid": examId}},
        "update": {"\$set": {"googleSheetId": sheetId, "googleSheetUrl": sheetUrl}}
      });
    } catch (e) {
      print("Error updating exam sheet info: $e");
    }
  }

  static Future<void> addQuestionToExam(String examId, String questionId) async {
    try {
      await _query("updateOne", "exams", {
        "filter": {"_id": {"\$oid": examId}},
        "update": {"\$push": {"questionIds": questionId}}
      });
    } catch (e) {
      print("Error adding question to exam: $e");
    }
  }

  static Future<List<Question>> getQuestionsForExam(List<String> questionIds) async {
    if (questionIds.isEmpty) return [];
    try {
      final res = await _query("find", "questions", {
        "filter": {
          "_id": {
            "\$in": questionIds.map((id) => {"\$oid": id}).toList()
          }
        }
      });
      final List documents = res['documents'] ?? [];
      return documents.map((doc) => Question.fromJson(_cleanDoc(doc))).toList();
    } catch (e) {
      print("Error fetching questions for exam: $e");
      return [];
    }
  }

  static Future<void> updateQuestion(Question question) async {
    try {
      await _query("updateOne", "questions", {
        "filter": {"_id": {"\$oid": question.id}},
        "update": {
          "\$set": {
            "title": question.title,
            "content": question.content,
            "steps": question.steps.map((s) => s.toJson()).toList()
          }
        }
      });
    } catch (e) {
      print("Error updating question: $e");
    }
  }

  static Future<void> removeQuestionFromExam(String examId, String questionId) async {
    try {
      await _query("updateOne", "exams", {
        "filter": {"_id": {"\$oid": examId}},
        "update": {"\$pull": {"questionIds": questionId}}
      });
    } catch (e) {
      print("Error removing question from exam: $e");
    }
  }

  static Future<void> updateExamQuestionOrder(String examId, List<String> newQuestionIds) async {
    try {
      await _query("updateOne", "exams", {
        "filter": {"_id": {"\$oid": examId}},
        "update": {"\$set": {"questionIds": newQuestionIds}}
      });
    } catch (e) {
      print("Error updating order: $e");
    }
  }

  // --- STUDENT SUBMISSIONS APIs ---

  static Future<List<StudentSubmission>> getStudentSubmissionsForExam(
    String examId, {
    String? questionId, 
    String? searchTerm,
    bool includeImage = false,
    bool forceRefresh = false,
  }) async {
    final cacheKey = "${examId}_${questionId ?? 'all'}";
    final bool useCache = (searchTerm == null || searchTerm.isEmpty) && !includeImage && !forceRefresh;
    
    if (useCache && _submissionsCache.containsKey(cacheKey)) {
      return _submissionsCache[cacheKey]!;
    }

    try {
      Map<String, dynamic> filter = {"examId": examId};
      if (questionId != null) filter["questionId"] = questionId;
      if (searchTerm != null && searchTerm.isNotEmpty) {
        filter["studentName"] = {"\$regex": searchTerm, "\$options": "i"};
      }

      final body = {
        "filter": filter,
        "sort": {"createdAt": -1}
      };
      
      if (!includeImage) {
        body["projection"] = {"imageBase64": 0};
      }

      final res = await _query("find", "submissions", body);
      final List documents = res['documents'] ?? [];
      final result = documents.map((doc) => StudentSubmission.fromJson(_cleanDoc(doc))).toList();

      if (useCache) {
        _submissionsCache[cacheKey] = result;
      }
      return result;
    } catch (e) {
      print("Error fetching student submissions: $e");
      return [];
    }
  }

  static Future<StudentSubmission?> getStudentSubmissionById(String id) async {
    try {
      final res = await _query("findOne", "submissions", {"filter": {"_id": {"\$oid": id}}});
      final doc = res['document'];
      return doc != null ? StudentSubmission.fromJson(_cleanDoc(doc)) : null;
    } catch (e) {
      print("Error fetching submission by ID: $e");
      return null;
    }
  }

  static Future<StudentSubmission> insertStudentSubmission(StudentSubmission submission) async {
    try {
      final doc = submission.toJson();
      doc.remove('_id');
      final res = await _query("insertOne", "submissions", {"document": doc});
      
      // Lấy ID thật từ n8n/MongoDB trả về
      String realId = res['insertedId']?.toString() ?? '';
      submission.id = realId;

      _submissionsCache.remove("${submission.examId}_${submission.questionId}");
      _submissionsCache.remove("${submission.examId}_all");
      return submission;
    } catch (e) {
      print("Error inserting student submission: $e");
      rethrow;
    }
  }

  static Future<void> deleteStudentSubmission(String submissionId) async {
    try {
      final sub = await getStudentSubmissionById(submissionId);
      await _query("deleteOne", "submissions", {"filter": {"_id": {"\$oid": submissionId}}});
      if (sub != null) {
        _submissionsCache.remove("${sub.examId}_${sub.questionId}");
        _submissionsCache.remove("${sub.examId}_all");
      }
    } catch (e) {
      print("Error deleting student submission: $e");
    }
  }

  static Future<void> updateStudentSubmissionName(String submissionId, String newName) async {
    try {
      final sub = await getStudentSubmissionById(submissionId);
      await _query("updateOne", "submissions", {
        "filter": {"_id": {"\$oid": submissionId}},
        "update": {
          "\$set": {"studentName": newName}
        }
      });
      if (sub != null) {
        _submissionsCache.remove("${sub.examId}_${sub.questionId}");
        _submissionsCache.remove("${sub.examId}_all");
      }
    } catch (e) {
      print("Error updating student submission name: $e");
    }
  }

  // --- GRADING SESSIONS APIs ---

  static Future<List<GradingSession>> getGradingSessionsForExam(
    String examId, {
    String? questionId,
    String? searchTerm,
    bool includeImage = false,
    bool forceRefresh = false,
  }) async {
    final cacheKey = "${examId}_${questionId ?? 'all'}";
    final bool useCache = (searchTerm == null || searchTerm.isEmpty) && !includeImage && !forceRefresh;

    if (useCache && _gradingsCache.containsKey(cacheKey)) {
      return _gradingsCache[cacheKey]!;
    }

    try {
      Map<String, dynamic> filter = {"examId": examId};
      if (questionId != null) filter["questionId"] = questionId;
      if (searchTerm != null && searchTerm.isNotEmpty) {
        filter["studentName"] = {"\$regex": searchTerm, "\$options": "i"};
      }

      final body = {
        "filter": filter,
        "sort": {"createdAt": -1}
      };
      
      if (!includeImage) {
        body["projection"] = {"studentImageBase64": 0};
      }

      final res = await _query("find", "gradings", body);
      final List documents = res['documents'] ?? [];
      final result = documents.map((doc) => GradingSession.fromJson(_cleanDoc(doc))).toList();

      if (useCache) {
        _gradingsCache[cacheKey] = result;
      }
      return result;
    } catch (e) {
      print("Error fetching grading sessions: $e");
      return [];
    }
  }

  static Future<GradingSession?> getGradingSessionById(String id) async {
    try {
      final res = await _query("findOne", "gradings", {"filter": {"_id": {"\$oid": id}}});
      final doc = res['document'];
      return doc != null ? GradingSession.fromJson(_cleanDoc(doc)) : null;
    } catch (e) {
      print("Error fetching grading session by ID: $e");
      return null;
    }
  }

  static Future<void> insertGradingSession(GradingSession session) async {
    try {
      final doc = session.toJson();
      doc.remove('_id');
      await _query("insertOne", "gradings", {"document": doc});
      _gradingsCache.remove("${session.examId}_${session.questionId}");
      _gradingsCache.remove("${session.examId}_all");
    } catch (e) {
      print("Error inserting grading session: $e");
    }
  }

  // --- GRADING BATCHES APIs ---

  static Future<String?> startGradingBatch({
    required String examId,
    required String questionId,
    required String examTitle,
    required String questionTitle,
    required List<String> submissionIds,
    required String webhookUrl,
    required Map<String, dynamic> metadata,
    String? batchName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$_baseUrl/api/grading/start-batch"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "examId": examId,
          "questionId": questionId,
          "examTitle": examTitle,
          "questionTitle": questionTitle,
          "submissionIds": submissionIds,
          "webhookUrl": webhookUrl,
          "metadata": metadata,
          "batchName": batchName,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['batchId'];
      }
    } catch (e) {
      print("Error starting grading batch: $e");
    }
    return null;
  }

  static Future<List<GradingBatch>> getGradingBatches() async {
    try {
      final res = await _query("find", "grading_batches", {
        "sort": {"createdAt": -1}
      });
      final List documents = res['documents'] ?? [];
      return documents.map((doc) => GradingBatch.fromJson(_cleanDoc(doc))).toList();
    } catch (e) {
      print("Error fetching grading batches: $e");
      return [];
    }
  }

  static Future<List<GradingSession>> getSessionsForBatch(String batchId) async {
    try {
      final res = await _query("find", "gradings", {
        "filter": {"batchId": batchId},
        "sort": {"createdAt": -1}
      });
      final List documents = res['documents'] ?? [];
      return documents.map((doc) => GradingSession.fromJson(_cleanDoc(doc))).toList();
    } catch (e) {
      print("Error fetching cache for batch: $e");
      return [];
    }
  }
}
