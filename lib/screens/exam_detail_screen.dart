import 'package:flutter/material.dart';
import '../models/exam.dart';
import '../models/question.dart';
import '../services/database_api.dart';
import 'exam_barem_preview_screen.dart';
import 'question_detail_screen.dart';

class ExamDetailScreen extends StatefulWidget {
  final Exam exam;
  const ExamDetailScreen({super.key, required this.exam});

  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen> {
  late Future<List<Question>> _questionsInExam;
  List<Question> _currentQuestions = [];

  @override
  void initState() {
    super.initState();
    _loadExamQuestions();
  }

  void _loadExamQuestions() {
    setState(() {
      _questionsInExam = DatabaseApi.getQuestionsForExam(widget.exam.questionIds).then((qs) {
        _currentQuestions = qs;
        return qs;
      });
    });
  }

  void _showAddQuestionDialog() async {
    // Show loading while fetching all questions
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final allQuestions = await DatabaseApi.getQuestions();
    
    if (mounted) {
      Navigator.pop(context); // close loading
    }

    // Lọc ra các câu hỏi CHƯA ĐƯỢC THÊM vào đề thi này
    final availableQuestions = allQuestions.where((q) => !widget.exam.questionIds.contains(q.id)).toList();

    if (availableQuestions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kho câu hỏi đã trống hoặc tất cả câu hỏi đã được thêm vào đề này!')),
        );
      }
      return;
    }

    // Show Selection Dialog
    if (mounted) {
      showDialog(
        context: context,
        builder: (dialogCtx) {
          return AlertDialog(
            title: const Text('Chọn Câu Hỏi Từng Lập'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: availableQuestions.length,
                itemBuilder: (itemCtx, index) {
                  final q = availableQuestions[index];
                  return ListTile(
                    title: Text(q.title),
                    trailing: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(dialogCtx); 
                        await DatabaseApi.addQuestionToExam(widget.exam.id, q.id);
                        setState(() {
                          widget.exam.questionIds.add(q.id);
                        });
                        _loadExamQuestions();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar( 
                            const SnackBar(content: Text('✅ Đã thêm câu hỏi vào đề!'), backgroundColor: Colors.green),
                          );
                        }
                      },
                      child: const Text('Thêm'),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Đóng'),
              ),
            ],
          );
        },
      );
    }
  }

  void _onReorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final Question itemToMove = _currentQuestions.removeAt(oldIndex);
      _currentQuestions.insert(newIndex, itemToMove);
      
      // Update local exam object too
      widget.exam.questionIds.clear();
      widget.exam.questionIds.addAll(_currentQuestions.map((q) => q.id));
    });

    // Save permutation to MongoDB
    await DatabaseApi.updateExamQuestionOrder(widget.exam.id, widget.exam.questionIds);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu thứ tự mới!'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _confirmRemoveQuestion(String questionId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận Xóa'),
        content: const Text('Bạn có chắc muốn xóa câu hỏi này khỏi đề thi hiện tại không? (Dữ liệu trong Kho Câu Hỏi vẫn được giữ nguyên)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await DatabaseApi.removeQuestionFromExam(widget.exam.id, questionId);
              setState(() {
                widget.exam.questionIds.remove(questionId);
              });
              _loadExamQuestions();
              if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã xóa câu hỏi khỏi đề thi!')),
                 );
              }
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.exam.title),
        backgroundColor: Colors.deepPurpleAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.remove_red_eye),
            tooltip: 'Xem Xem Bảng Barem',
            onPressed: () {
              if (_currentQuestions.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Hãy thêm câu hỏi vào đề trước khi xem Barem!')),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ExamBaremPreviewScreen(
                    examTitle: widget.exam.title,
                    questions: _currentQuestions,
                  ),
                ),
              );
            },
          )
        ],
      ),
      body: FutureBuilder<List<Question>>(
        future: _questionsInExam,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Lỗi: ${snapshot.error}'));
          }

          if (_currentQuestions.isEmpty) {
            return const Center(
              child: Text(
                'Đề thi này chưa có câu hỏi nào.\nHãy ấn nút "Thêm Câu Hỏi" góc dưới nhé!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          // Calculate grand total 
          double grandTotal = 0;
          for (var q in _currentQuestions) {
             grandTotal += q.steps.fold(0.0, (sum, step) => sum + step.score);
          }

          return Column(
            children: [
              // Header Thông báo
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                color: Colors.deepPurple.shade50,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Số câu hỏi: ${_currentQuestions.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple),
                    ),
                    Text(
                      'Tổng Điểm: ${grandTotal.toStringAsFixed(2)} đ',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepPurple),
                    ),
                  ]
                ),
              ),
              const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                      'Mẹo: Dùng chuột kéo thả biểu tượng ≡ để xếp lại thứ tự ưu tiên các câu.',
                      style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)
                  )
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _currentQuestions.length,
                  onReorder: _onReorder,
                  itemBuilder: (context, index) {
                    final q = _currentQuestions[index];
                    final qTotal = q.steps.fold(0.0, (sum, step) => sum + step.score);
                    // Dùng id để định danh cho reorder
                    return Card(
                      key: ValueKey(q.id),
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.drag_handle, color: Colors.grey),
                        title: Text('Câu ${index + 1}: ${q.title}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Tổng điểm: ${qTotal.toStringAsFixed(2)} đ\n${q.content != null && q.content!.isNotEmpty ? "Bao gồm đề bài" : "Không có đề bài"}'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => QuestionDetailScreen(
                                question: q,
                                googleSheetUrl: widget.exam.googleSheetUrl,
                              ),
                            ),
                          ).then((_) => _loadExamQuestions());
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          tooltip: 'Xoá khỏi đề này',
                          onPressed: () => _confirmRemoveQuestion(q.id),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddQuestionDialog,
        icon: const Icon(Icons.add),
        label: const Text('Thêm Câu Hỏi từ Kho'),
        backgroundColor: Colors.deepPurpleAccent,
        foregroundColor: Colors.white,
      ),
    );
  }
}
