import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/exam.dart';
import '../models/question.dart';
import '../models/student_submission.dart';
import '../services/database_api.dart';

class SubmissionManagementScreen extends StatefulWidget {
  final Exam exam;
  final Question question;

  const SubmissionManagementScreen({
    super.key, 
    required this.exam,
    required this.question,
  });

  @override
  State<SubmissionManagementScreen> createState() => _SubmissionManagementScreenState();
}

class _SubmissionManagementScreenState extends State<SubmissionManagementScreen> {
  late Future<List<StudentSubmission>> _submissionsFuture;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  void _loadSubmissions({bool forceRefresh = false}) {
    setState(() {
      _submissionsFuture = DatabaseApi.getStudentSubmissionsForExam(
        widget.exam.id,
        questionId: widget.question.id,
        searchTerm: _searchController.text.trim(),
        includeImage: false, 
        forceRefresh: forceRefresh,
      );
    });
  }

  Future<void> _pickAndUploadImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isEmpty) return;

    setState(() {
      _isUploading = true;
    });

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
          SnackBar(
            content: Text('Đã tải lên ${images.length} ảnh bài làm cho ${widget.question.title}!'), 
            backgroundColor: Colors.green
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải ảnh: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() {
        _isUploading = false;
      });
      _loadSubmissions();
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
              _loadSubmissions();
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
          decoration: const InputDecoration(
            labelText: 'Tên mới / MSSV',
            border: OutlineInputBorder(),
          ),
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
                _loadSubmissions();
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFullImage(StudentSubmission sub) async {
    // Show loading indicator
    showDialog(
      context: context, 
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator())
    );

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
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    child: Image.memory(
                      base64Decode(fullSub.imageBase64),
                      fit: BoxFit.contain,
                    ),
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.question.title}'),
            Text(widget.exam.title, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadSubmissions(forceRefresh: true),
            tooltip: 'Tải lại từ server',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm tên học sinh / ảnh...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _loadSubmissions();
                  },
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onSubmitted: (_) => _loadSubmissions(),
            ),
          ),
          
          if (_isUploading)
            const LinearProgressIndicator(),
            
          Expanded(
            child: FutureBuilder<List<StudentSubmission>>(
              future: _submissionsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final subs = snapshot.data ?? [];
                
                if (subs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('Không tìm thấy bài làm nào.', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 24),
                        if (_searchController.text.isEmpty)
                          ElevatedButton.icon(
                            onPressed: _isUploading ? null : _pickAndUploadImages,
                            icon: const Icon(Icons.add_photo_alternate),
                            label: const Text('TẢI BÀI LÀM LÊN'),
                          )
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: subs.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final s = subs[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.indigo.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.image, color: Colors.indigo),
                      ),
                      title: Text(
                        s.studentName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Tải lên: ${s.createdAt.day.toString().padLeft(2, '0')}/${s.createdAt.month.toString().padLeft(2, '0')} ${s.createdAt.hour.toString().padLeft(2, '0')}:${s.createdAt.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                            onPressed: () => _showRenameDialog(s),
                            tooltip: 'Đổi tên / MSSV',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            onPressed: () => _confirmDelete(s),
                            tooltip: 'Xóa bài làm',
                          ),
                        ],
                      ),
                      onTap: () => _showFullImage(s),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isUploading ? null : _pickAndUploadImages,
        icon: const Icon(Icons.add_photo_alternate),
        label: const Text('Thêm bài làm'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
    );
  }
}
