import 'package:flutter/material.dart';
import '../models/question.dart';
import '../models/exam.dart';
import '../services/database_api.dart';
import 'barem_create_screen.dart';
import 'exam_detail_screen.dart';
import 'question_detail_screen.dart';
import 'grading_session_screen.dart';
import 'submission_management_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0; // Default to 'Kỳ Thi' tab
  final TextEditingController _titleController = TextEditingController();
  late Future<List<Question>> _questionsFuture;
  late Future<List<Exam>> _examsFuture;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
    _loadExams();
  }

  void _loadQuestions() {
    setState(() {
      _questionsFuture = DatabaseApi.getQuestions();
    });
  }

  void _loadExams() {
    setState(() {
      _examsFuture = DatabaseApi.getExams();
    });
  }

  void _showCreateQuestionDialog() {
    _titleController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tạo Bài Thi Mới'),
          content: TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'Nhập tên câu hỏi (VD: Câu 1: Giải PT)',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_titleController.text.trim().isNotEmpty) {
                  final newQuestion = Question(
                    id: '', // MongoDB will generate this safely now
                    title: _titleController.text.trim(),
                    createdAt: DateTime.now(),
                  );
                  Navigator.pop(context); // Close dialog early
                  await DatabaseApi.insertQuestion(newQuestion);
                  _loadQuestions(); // Refresh list after insert
                }
              },
              child: const Text('Tạo mới'),
            ),
          ],
        );
      },
    );
  }

  void _showCreateExamDialog() {
    _titleController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tạo Kỳ Thi Mới'),
          content: TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'Nhập tên kỳ thi (VD: Giữa kỳ Toán)',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_titleController.text.trim().isNotEmpty) {
                  final newExam = Exam(
                    id: '', // MongoDB will generate
                    title: _titleController.text.trim(),
                    createdAt: DateTime.now(),
                  );
                  Navigator.pop(context); 
                  await DatabaseApi.insertExam(newExam);
                  _loadExams(); 
                }
              },
              child: const Text('Tạo mới'),
            ),
          ],
        );
      },
    );
  }

  void _showRenameExamDialog(Exam exam) {
    _titleController.text = exam.title;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Đổi Tên Kỳ Thi'),
          content: TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              hintText: 'Nhập tên kỳ thi mới',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newTitle = _titleController.text.trim();
                if (newTitle.isNotEmpty && newTitle != exam.title) {
                  Navigator.pop(context); 
                  await DatabaseApi.updateExamTitle(exam.id, newTitle);
                  _loadExams();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã đổi tên kỳ thi!')),
                    );
                  }
                } else {
                  Navigator.pop(context);
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteExam(Exam exam) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Xác nhận Xóa Kỳ Thi'),
          content: Text('Bạn có chắc muốn xóa kỳ thi "${exam.title}"? \n\nLưu ý: Tất cả các bài nộp và kết quả chấm của kỳ thi này cũng sẽ bị xóa khỏi hệ thống.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await DatabaseApi.deleteExam(exam.id);
                _loadExams();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã xóa kỳ thi thành công!'), backgroundColor: Colors.red),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Xóa', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildExamsTab() {
    return FutureBuilder<List<Exam>>(
      future: _examsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Đã có lỗi xảy ra: ${snapshot.error}'));
        }
        
        final exams = snapshot.data ?? [];

        if (exams.isEmpty) {
          return const Center(
            child: Text(
              'Chưa có kỳ thi nào.\nHãy nhấn nút + để tạo kỳ thi đầu tiên!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: exams.length,
          itemBuilder: (context, index) {
            final exam = exams[index];
            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Colors.deepPurpleAccent,
                          child: Icon(Icons.assignment, color: Colors.white),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            exam.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.grey, size: 20),
                          onPressed: () => _showRenameExamDialog(exam),
                          tooltip: 'Đổi Tên',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          onPressed: () => _confirmDeleteExam(exam),
                          tooltip: 'Xóa Kỳ Thi',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Số câu hỏi: ${exam.questionIds.length}'),
                    Text('Tạo ngày: ${exam.createdAt.day}/${exam.createdAt.month}/${exam.createdAt.year}'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ExamDetailScreen(exam: exam),
                              ),
                            ).then((_) => _loadExams());
                          },
                          icon: const Icon(Icons.settings, size: 18),
                          label: const Text('Đề Thi'),
                          style: TextButton.styleFrom(foregroundColor: Colors.deepPurpleAccent),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => GradingSessionScreen(exam: exam),
                              ),
                            ).then((_) => _loadExams());
                          },
                          icon: const Icon(Icons.grading, size: 18),
                          label: const Text('Chấm Thi'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuestionBankTab() {
    return FutureBuilder<List<Question>>(
      future: _questionsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Đã có lỗi xảy ra: ${snapshot.error}'));
        }
        
        final questions = snapshot.data ?? [];

        if (questions.isEmpty) {
          return const Center(
            child: Text(
              'Chưa có bài thi/câu hỏi nào.\nHãy nhấn nút + để tạo bài thi đầu tiên!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: questions.length,
          itemBuilder: (context, index) {
            final question = questions[index];
            final totalScore = question.steps.fold(0.0, (sum, step) => sum + step.score);
            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: const CircleAvatar(
                  backgroundColor: Colors.blueAccent,
                  child: Icon(Icons.note_alt, color: Colors.white),
                ),
                title: Text(
                  question.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                subtitle: Text(
                  'Tổng Điểm: $totalScore\nTạo ngày: ${question.createdAt.day}/${question.createdAt.month}/${question.createdAt.year}',
                ),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => QuestionDetailScreen(question: question),
                    ),
                  ).then((_) {
                    // Update views when navigating back
                    _loadQuestions();
                    _loadExams();
                  });
                },
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MAGR - Hệ thống Chấm Thi'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: _currentIndex == 0 ? _buildExamsTab() : _buildQuestionBankTab(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _currentIndex == 0 ? _showCreateExamDialog : _showCreateQuestionDialog,
        icon: const Icon(Icons.add),
        label: Text(_currentIndex == 0 ? 'Thêm Kì Thi' : 'Thêm Câu Hỏi'),
        backgroundColor: _currentIndex == 0 ? Colors.deepPurpleAccent : Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: _currentIndex == 0 ? Colors.deepPurpleAccent : Colors.blueAccent,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            _loadExams();
            _loadQuestions();
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Kỳ Thi',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_books),
            label: 'Kho Bài Thi',
          ),
        ],
      ),
    );
  }
}
