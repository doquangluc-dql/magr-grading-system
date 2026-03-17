import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

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
  bool _isSelectionMode = false; // NEW: Toggle between Vault View and Selection Mode
  bool _isUploading = false; // NEW: For image picking
  final ImagePicker _picker = ImagePicker(); // NEW: For image picking
  String? _processingStudentName;
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
      _isSelectionMode = false; // Exit selection mode after done
    });
    _loadHistory(); // Refresh history backgroundly
  }

  // --- VAULT FEATURES MERGED ---

  Future<void> _pickAndUploadImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isEmpty) return;

    setState(() => _isUploading = true);

    try {
      for (var image in images) {
        Uint8List bytes = await image.readAsBytes();
        String base64 = base64Encode(bytes);
        
        final submission = StudentSubmission(
          id: '',
          examId: widget.exam.id,
          questionId: widget.question.id,
          studentName: image.name,
          imageBase64: base64,
          createdAt: DateTime.now(),
        );
        
        await DatabaseApi.insertStudentSubmission(submission);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã tải lên ${images.length} bài làm!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải ảnh: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
        _loadSubmissions(forceRefresh: true);
      }
    }
  }

  void _confirmDelete(StudentSubmission sub) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa bài làm "${sub.studentName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await DatabaseApi.deleteStudentSubmission(sub.id);
              _loadSubmissions(forceRefresh: true);
            }, 
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(StudentSubmission sub) {
    final controller = TextEditingController(text: sub.studentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên bài làm / MSSV'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Tên mới / MSSV', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(ctx);
                await DatabaseApi.updateStudentSubmissionName(sub.id, newName);
                _loadSubmissions(forceRefresh: true);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFullImage(StudentSubmission sub) async {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));

    try {
      final fullSub = await DatabaseApi.getStudentSubmissionById(sub.id);
      Navigator.pop(context); // Remove loading

      if (fullSub == null || fullSub.imageBase64.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể tải ảnh'), backgroundColor: Colors.red));
        return;
      }

      showDialog(
        context: context,
        builder: (ctx) => Dialog.fullscreen(
          child: Container(
            color: Colors.black,
            child: Column(
              children: [
                AppBar(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  title: Text(fullSub.studentName),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ),
                Expanded(
                  child: InteractiveViewer(
                    child: Image.memory(base64Decode(fullSub.imageBase64), fit: BoxFit.contain),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red));
    }
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
          if (_isUploading) const LinearProgressIndicator(),
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
                  // Toolbar
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: 'Tìm học sinh...',
                                  prefixIcon: const Icon(Icons.search, size: 20),
                                  suffixIcon: _searchController.text.isNotEmpty 
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 20),
                                        onPressed: () {
                                          _searchController.clear();
                                          _loadSubmissions();
                                        },
                                      )
                                    : null,
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onSubmitted: (_) => _loadSubmissions(),
                              ),
                            ),
                            if (!_isSelectionMode && !_isProcessing)
                              IconButton(
                                icon: const Icon(Icons.add_photo_alternate_outlined, color: Colors.indigo),
                                onPressed: _pickAndUploadImages,
                                tooltip: 'Thêm bài làm',
                              ),
                            if (_isSelectionMode)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    final allSelected = _gradableItems.every((i) => i.isSelected);
                                    for (var i in _gradableItems) i.isSelected = !allSelected;
                                  });
                                },
                                child: const Text('Tất cả'),
                              ),
                          ],
                        ),
                        if (!_isLoadingSubmissions && _gradableItems.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Tổng số: ${_gradableItems.length} bài nộp',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                                ),
                                if (_isSelectionMode)
                                  Text(
                                    'Đã chọn: ${_gradableItems.where((i) => i.isSelected).length}',
                                    style: const TextStyle(fontSize: 12, color: Colors.indigo, fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                          ),
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
                                const Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey),
                                const SizedBox(height: 16),
                                const Text('Kho bài làm đang trống.', style: TextStyle(color: Colors.grey)),
                                ElevatedButton.icon(
                                  onPressed: _pickAndUploadImages,
                                  icon: const Icon(Icons.upload),
                                  label: const Text('Tải ảnh bài làm lên'),
                                )
                              ],
                            )
                          )
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: _gradableItems.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = _gradableItems[index];
                              final isCurrent = _processingStudentName == item.submission.studentName;
                              
                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isSelectionMode) ...[
                                      Icon(
                                        item.isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                        color: item.isSelected ? Colors.indigo : Colors.grey,
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    // Styled Thumbnail
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.indigo.withOpacity(0.1)),
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          if (item.submission.imageBase64.isNotEmpty)
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: Image.memory(
                                                base64Decode(item.submission.imageBase64), 
                                                width: 40, height: 40, fit: BoxFit.cover
                                              ),
                                            )
                                          else
                                            const Icon(Icons.image_outlined, size: 24, color: Colors.indigo),
                                          
                                          if (isCurrent)
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black26,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Center(
                                                child: SizedBox(
                                                  width: 18, height: 18,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                title: Text(item.submission.studentName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  item.error != null 
                                    ? 'Lỗi: ${item.error}' 
                                    : 'Tải lên: ${item.submission.createdAt.day}/${item.submission.createdAt.month} ${item.submission.createdAt.hour}:${item.submission.createdAt.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(fontSize: 11, color: item.error != null ? Colors.red : Colors.grey),
                                ),
                                trailing: _isSelectionMode 
                                  ? null 
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
                                          onPressed: () => _showRenameDialog(item.submission),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                          onPressed: () => _confirmDelete(item.submission),
                                        ),
                                      ],
                                    ),
                                onTap: () {
                                  if (_isSelectionMode) {
                                    setState(() => item.isSelected = !item.isSelected);
                                  } else {
                                    _showFullImage(item.submission);
                                  }
                                },
                              );
                            },
                          ),
                  ),
                  
                  // Bottom Actions
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: _isSelectionMode
                        ? Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => setState(() => _isSelectionMode = false),
                                  child: const Text('Hủy'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('BẮT ĐẦU CHẤM'),
                                  onPressed: _gradableItems.any((i) => i.isSelected) ? _processSelected : null,
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                                ),
                              ),
                            ],
                          )
                        : ElevatedButton.icon(
                            icon: _isProcessing 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.checklist),
                            onPressed: _isProcessing 
                              ? null 
                              : () => setState(() {
                                  if (_gradableItems.isNotEmpty) _isSelectionMode = true;
                                }),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isProcessing ? Colors.grey : Colors.indigo,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                            ),
                            label: Text(_isProcessing 
                              ? 'ĐANG XỬ LÝ: ${_processingStudentName ?? "..."}' 
                              : 'CHỌN BÀI ĐỂ CHẤM'),
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
