import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../models/exam.dart';
import '../models/question.dart';
import '../models/grading_session.dart';
import '../models/student_submission.dart';
import '../services/database_api.dart';
import 'submission_management_screen.dart';

class QuestionGradingScreen extends StatefulWidget {
  final Exam exam;
  final Question question;

  const QuestionGradingScreen({
    super.key,
    required this.exam,
    required this.question,
  });

  @override
  State<QuestionGradingScreen> createState() => _QuestionGradingScreenState();
}

class _GradableSubmission {
  final StudentSubmission submission;
  String status; // 'Pending', 'Uploading', 'Success', 'Failed'
  String? error;
  String? sheetUrl;
  bool isSelected;

  _GradableSubmission({
    required this.submission,
    this.status = 'Pending',
    this.isSelected = false,
  });
}

class _QuestionGradingScreenState extends State<QuestionGradingScreen> {
  final List<_GradableSubmission> _gradableItems = [];
  late Future<List<GradingSession>> _historyFuture;
  bool _isLoadingSubmissions = false;
  bool _isProcessing = false;
  String? _processingStudentName; // NEW
  final TextEditingController _searchController = TextEditingController();

  final String _n8nWebhookUrl = 'https://doquangluc-dql.app.n8n.cloud/webhook/magr-grading-webhook';
  // final String _n8nWebhookUrl = 'https://doquangluc-dql.app.n8n.cloud/webhook-test/magr-grading-webhook';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _loadAll({bool forceRefresh = false}) {
    _loadSubmissions(forceRefresh: forceRefresh);
  }

  Future<void> _loadSubmissions({bool forceRefresh = false}) async {
    setState(() {
      _isLoadingSubmissions = true;
    });
    try {
      final subs = await DatabaseApi.getStudentSubmissionsForExam(
        widget.exam.id,
        questionId: widget.question.id,
        searchTerm: _searchController.text.trim(),
        includeImage: false, // Enable caching & high performance
        forceRefresh: forceRefresh,
      );
      setState(() {
        _gradableItems.clear();
        _gradableItems.addAll(subs.map((s) => _GradableSubmission(submission: s)));
      });
    } finally {
      setState(() {
        _isLoadingSubmissions = false;
      });
    }
  }

  void _loadHistory({bool forceRefresh = false}) {
    setState(() {
      _historyFuture = DatabaseApi.getGradingSessionsForExam(
        widget.exam.id,
        questionId: widget.question.id,
        forceRefresh: forceRefresh,
      );
    });
  }


  Future<void> _processSelected() async {
    if (_isProcessing) return;

    final selectedItems = _gradableItems.where((item) => item.isSelected && item.status != 'Success').toList();
    if (selectedItems.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    for (var item in selectedItems) {
      if (!mounted) break;
      setState(() {
        item.status = 'Uploading';
        _processingStudentName = item.submission.studentName;
      });

      try {
        var request = http.MultipartRequest('POST', Uri.parse(_n8nWebhookUrl));
        // Gather ALL metadata into a single object to prevent n8n from creating multiple binary files for Unicode fields
        final metadata = {
          'examId': widget.exam.id,
          'examTitle': widget.exam.title,
          'questionId': widget.question.id,
          'questionTitle': widget.question.title,
          'questionContent': widget.question.content ?? "",
          'googleSheetId': widget.exam.googleSheetId, // Pass the sheet ID
          'studentName': item.submission.studentName,
          'barem': widget.question.steps.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            return {
              'step_id': index + 1,
              'content': step.latexCode,
              'score': step.score,
            };
          }).toList(),
        };
        
        request.fields['data'] = jsonEncode(metadata);

        // Optimization check: If image is missing (lazy loaded), fetch it now
        String imageBase64 = item.submission.imageBase64;
        if (imageBase64.isEmpty) {
          final fullSub = await DatabaseApi.getStudentSubmissionById(item.submission.id);
          if (fullSub != null && fullSub.imageBase64.isNotEmpty) {
            imageBase64 = fullSub.imageBase64;
          } else {
             throw Exception("Không thể tải ảnh bài làm");
          }
        }

        Uint8List imageBytes = base64Decode(imageBase64);
        var multipartFile = http.MultipartFile.fromBytes(
          'studentImage',
          imageBytes,
          filename: '${item.submission.studentName}.jpg',
          contentType: MediaType('image', 'jpeg'),
        );
        request.files.add(multipartFile);

        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          item.sheetUrl = data['sheetUrl'];
          item.status = 'Success';
          
          // Parse score and feedback if available
          final double? score = data['score'] != null ? (data['score'] as num).toDouble() : null;
          final String? feedback = data['feedback'];

          final session = GradingSession(
            id: '',
            examId: widget.exam.id,
            questionId: widget.question.id,
            studentName: item.submission.studentName,
            createdAt: DateTime.now(),
            n8nStatus: 'Success',
            sheetUrl: item.sheetUrl,
            studentImageBase64: item.submission.imageBase64,
            score: score,
            feedback: feedback,
          );
          await DatabaseApi.insertGradingSession(session);
        } else {
          item.status = 'Failed';
          String detailedError = 'Lỗi server: ${response.statusCode}';
          try {
            final errorData = jsonDecode(response.body);
            if (errorData['error'] != null) {
              detailedError = errorData['error'];
            }
          } catch (_) {}
          
          item.error = detailedError;
          
          final session = GradingSession(
            id: '',
            examId: widget.exam.id,
            questionId: widget.question.id,
            studentName: item.submission.studentName,
            createdAt: DateTime.now(),
            n8nStatus: 'Failed',
            studentImageBase64: item.submission.imageBase64,
            errorDetails: detailedError, // Save detail
          );
          await DatabaseApi.insertGradingSession(session);
        }
      } catch (e) {
        item.status = 'Failed';
        item.error = e.toString();
      }
      
      if (mounted) setState(() {});
    }

    setState(() {
      _isProcessing = false;
      _processingStudentName = null;
    });
    _loadHistory(); // Refresh history backgroundly
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.question.title}'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white),
            onPressed: _showHistoryDialog,
            tooltip: 'Xem lịch sử chấm',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () { _loadAll(forceRefresh: true); },
            tooltip: 'Làm mới danh sách (Tải lại từ server)',
          )
        ],
      ),
      body: Column(
        children: [
          // Submissions Selection Area
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 4)],
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                   // Search Bar for repository
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Tìm học sinh...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            _loadSubmissions();
                          },
                        ),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onSubmitted: (_) => _loadSubmissions(),
                    ),
                  ),
                  const Divider(height: 1),
                   Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                         Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text('Kho bài làm riêng của câu: ${widget.question.title}', style: const TextStyle(fontWeight: FontWeight.bold)),
                             Text('Số bài đã chọn: ${_gradableItems.where((i)=>i.isSelected).length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                           ],
                         ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => setState(() {
                                 final allSelected = _gradableItems.every((i) => i.isSelected);
                                 for(var i in _gradableItems) i.isSelected = !allSelected;
                              }),
                              child: const Text('Tất cả'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.indigo),
                              onPressed: () {
                                Navigator.push(
                                  context, 
                                  MaterialPageRoute(builder: (ctx) => SubmissionManagementScreen(
                                    exam: widget.exam,
                                    question: widget.question,
                                  ))
                                ).then((_) => _loadSubmissions());
                              },
                              tooltip: 'Thêm bài làm mới vào kho',
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _isLoadingSubmissions 
                      ? const Center(child: CircularProgressIndicator())
                      : _gradableItems.isEmpty 
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.search_off, size: 48, color: Colors.grey),
                                const SizedBox(height: 16),
                                const Text('Chưa có bài làm nào.', style: TextStyle(color: Colors.grey)),
                                TextButton(
                                  onPressed: () {
                                     Navigator.push(
                                      context, 
                                      MaterialPageRoute(builder: (ctx) => SubmissionManagementScreen(
                                        exam: widget.exam,
                                        question: widget.question,
                                      ))
                                    ).then((_) => _loadSubmissions());
                                  }, 
                                  child: const Text('Tải bài làm lên ngay')
                                )
                              ],
                            )
                          )
                        : ListView.builder(
                            itemCount: _gradableItems.length,
                            itemBuilder: (context, index) {
                              final item = _gradableItems[index];
                              return CheckboxListTile(
                                value: item.isSelected,
                                onChanged: _isProcessing ? null : (val) => setState(() => item.isSelected = val ?? false),
                                dense: true,
                                secondary: _getStatusIcon(item.status),
                                title: Text(item.submission.studentName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                subtitle: Row(
                                  children: [
                                    if (item.submission.imageBase64.isNotEmpty)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: Image.memory(
                                          base64Decode(item.submission.imageBase64), 
                                          width: 32, 
                                          height: 32, 
                                          fit: BoxFit.cover
                                        ),
                                      )
                                    else
                                      const Icon(Icons.image_outlined, size: 14, color: Colors.grey),
                                    const SizedBox(width: 8),
                                    if (item.error != null)
                                      Expanded(child: Text(item.error!, style: const TextStyle(color: Colors.red, fontSize: 11), overflow: TextOverflow.ellipsis))
                                    else 
                                      Text('Ngày tải: ${item.submission.createdAt.day}/${item.submission.createdAt.month}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        icon: _isProcessing 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.send),
                        onPressed: _isProcessing ? null : _processSelected,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo, 
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                        ),
                        label: Text(_isProcessing 
                          ? 'ĐANG CHẤM: ${_processingStudentName ?? "..."}' 
                          : 'BẮT ĐẦU CHẤM BÀI ĐÃ CHỌN'),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showHistoryDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _HistoryDialog(
        examId: widget.exam.id,
        questionId: widget.question.id,
        onShowDetail: (session) => _showHistoryDetail(context, session),
      ),
    );
  }

  Future<void> _showHistoryDetail(BuildContext context, GradingSession session) async {
    // Show loading
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));
    
    try {
      final fullSession = await DatabaseApi.getGradingSessionById(session.id);
      Navigator.pop(context); // Remove loading

      if (fullSession == null) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Kết quả: ${fullSession.studentName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (fullSession.studentImageBase64 != null && fullSession.studentImageBase64!.isNotEmpty)
                  Container(
                    height: 250,
                    width: double.maxFinite,
                    decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                    child: Builder(
                      builder: (context) {
                        try {
                           // Remove data URI prefix if present
                          String base64Str = fullSession.studentImageBase64!;
                          if (base64Str.contains(',')) {
                            base64Str = base64Str.split(',').last;
                          }
                          return InteractiveViewer(
                            child: Image.memory(
                              base64Decode(base64Str.trim()),
                              errorBuilder: (context, error, stackTrace) => const Center(child: Text('Lỗi hiển thị ảnh')),
                            ),
                          );
                        } catch (e) {
                          return const Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey));
                        }
                      }
                    ),
                  )
                else
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey))),
                
                const SizedBox(height: 16),
                _buildInfoRow('Trạng thái', fullSession.n8nStatus, 
                  color: fullSession.n8nStatus == 'Success' ? Colors.green : Colors.red),
                
                if (fullSession.score != null)
                  _buildInfoRow('Điểm số', '${fullSession.score} đ', isBold: true),
                
                if (fullSession.feedback != null && fullSession.feedback!.isNotEmpty)
                  _buildInfoRow('Nhận xét', fullSession.feedback!),
                
                if (fullSession.errorDetails != null && fullSession.errorDetails!.isNotEmpty)
                  _buildInfoRow('Chi tiết lỗi', fullSession.errorDetails!, color: Colors.red),

                if (fullSession.sheetUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: ElevatedButton.icon(
                      onPressed: () {
                         // Note: User should use url_launcher for this
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Mở link: ${fullSession.sheetUrl}')));
                      }, 
                      icon: const Icon(Icons.table_view), 
                      label: const Text('Mở Bảng Điểm')
                    ),
                  )
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))
          ],
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Widget _buildInfoRow(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(
            value, 
            style: TextStyle(
              fontSize: 14, 
              color: color ?? Colors.black87, 
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal
            )
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _getStatusIcon(String status) {
    switch (status) {
      case 'Uploading':
        return const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
      case 'Pending':
        return const Icon(Icons.circle_outlined, size: 16, color: Colors.grey);
      case 'Success':
        return const Icon(Icons.check_circle, size: 16, color: Colors.green);
      case 'Failed':
        return const Icon(Icons.error, size: 16, color: Colors.red);
      default:
        return const Icon(Icons.help_outline, size: 16);
    }
  }
}

class _HistoryDialog extends StatefulWidget {
  final String examId;
  final String? questionId;
  final Function(GradingSession) onShowDetail;

  const _HistoryDialog({
    required this.examId,
    this.questionId,
    required this.onShowDetail,
  });

  @override
  State<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends State<_HistoryDialog> {
  final TextEditingController _historySearchController = TextEditingController();
  late Future<List<GradingSession>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    setState(() {
      _historyFuture = DatabaseApi.getGradingSessionsForExam(
        widget.examId,
        questionId: widget.questionId,
        searchTerm: _historySearchController.text.trim(),
        includeImage: false, // Optimize
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('LỊCH SỬ CHẤM BÀI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _historySearchController,
              decoration: InputDecoration(
                hintText: 'Tìm học sinh trong lịch sử...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onSubmitted: (_) => _loadHistory(),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<GradingSession>>(
                future: _historyFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final sessions = snapshot.data ?? [];
                  if (sessions.isEmpty) {
                    return const Center(child: Text('Không có dữ liệu lịch sử.'));
                  }
                  return ListView.separated(
                    itemCount: sessions.length,
                    separatorBuilder: (ctx, i) => const Divider(),
                    itemBuilder: (context, index) {
                      final s = sessions[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          s.n8nStatus == 'Success' ? Icons.check_circle : Icons.error,
                          color: s.n8nStatus == 'Success' ? Colors.green : Colors.red,
                        ),
                        title: Text(s.studentName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ngày: ${s.createdAt.day}/${s.createdAt.month} ${s.createdAt.hour}:${s.createdAt.minute.toString().padLeft(2, '0')}'),
                            if (s.n8nStatus == 'Failed' && s.errorDetails != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Lỗi: ${s.errorDetails}',
                                  style: const TextStyle(color: Colors.red, fontSize: 11, fontStyle: FontStyle.italic),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => widget.onShowDetail(s),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
