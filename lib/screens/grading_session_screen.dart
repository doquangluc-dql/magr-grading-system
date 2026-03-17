import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/exam.dart';
import '../models/question.dart';
import '../services/database_api.dart';
import 'question_grading_screen.dart';
import 'submission_management_screen.dart';

class GradingSessionScreen extends StatefulWidget {
  final Exam exam;

  const GradingSessionScreen({super.key, required this.exam});

  @override
  State<GradingSessionScreen> createState() => _GradingSessionScreenState();
}

class _GradingSessionScreenState extends State<GradingSessionScreen> {
  late Future<List<Question>> _questionsFuture;
  late List<Question> _currentQuestions = [];
  bool _isCreatingSheet = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  void _loadQuestions() {
    setState(() {
      _questionsFuture = DatabaseApi.getQuestionsForExam(widget.exam.questionIds).then((qs) {
        _currentQuestions = qs;
        return qs;
      });
    });
  }

  Future<void> _connectGoogleSheet() async {
    setState(() => _isCreatingSheet = true);
    try {
      final url = Uri.parse('https://doquangluc-dql.app.n8n.cloud/webhook/create-googlesheet');
      // final url = Uri.parse('https://doquangluc-dql.app.n8n.cloud/webhook-test/create-googlesheet');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'examTitle': widget.exam.title,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final sheetId = data['spreadsheetId'];
        final sheetUrl = data['spreadsheetUrl'];

        if (sheetId == null || sheetUrl == null) {
          throw Exception('n8n trả về thiếu spreadsheetId hoặc spreadsheetUrl.');
        }

        await DatabaseApi.updateExamSheetInfo(widget.exam.id, sheetId, sheetUrl);
        
        setState(() {
          widget.exam.googleSheetId = sheetId;
          widget.exam.googleSheetUrl = sheetUrl;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Đã tạo Google Spreadsheet thành công!'), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception('Lỗi server n8n: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreatingSheet = false);
    }
  }

  Future<void> _createQuestionSheet(Question q) async {
    if (widget.exam.googleSheetUrl == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đang tạo Sheet cho: ${q.title}...'), duration: const Duration(seconds: 1)),
    );

    try {
      final url = Uri.parse('https://doquangluc-dql.app.n8n.cloud/webhook/create-sheet');
      // final url = Uri.parse('https://doquangluc-dql.app.n8n.cloud/webhook-test/create-sheet');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'spreadsheetUrl': widget.exam.googleSheetUrl,
          'sheetName': q.title,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✅ Đã tạo Sheet "${q.title}" thành công!'), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception('Lỗi: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi tạo Sheet: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openGoogleSheet() async {
    if (widget.exam.googleSheetUrl != null) {
      final url = Uri.parse(widget.exam.googleSheetUrl!);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể mở liên kết')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chọn câu để chấm: ${widget.exam.title}'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Question>>(
        future: _questionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Lỗi: ${snapshot.error}'));
          }

          final questions = snapshot.data ?? [];
          if (questions.isEmpty) {
            return const Center(
               child: Text(
                 'Kỳ thi này chưa có câu hỏi nào để chấm.\nHãy quay lại phần Thiết lập đề.',
                 textAlign: TextAlign.center,
                 style: TextStyle(color: Colors.grey, fontSize: 16),
               ),
            );
          }

          return Column(
            children: [
              // Google Sheets Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.indigo.shade50,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Google Sheets:',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                    if (widget.exam.googleSheetId == null)
                      ElevatedButton.icon(
                        onPressed: _isCreatingSheet ? null : _connectGoogleSheet,
                        icon: _isCreatingSheet 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo))
                            : const Icon(Icons.table_chart, size: 18),
                        label: Text(_isCreatingSheet ? 'Đang tạo...' : 'Tạo Spreadsheet'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          elevation: 1,
                        ),
                      )
                    else
                      TextButton.icon(
                        onPressed: _openGoogleSheet,
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Mở file Excel', style: TextStyle(decoration: TextDecoration.underline)),
                        style: TextButton.styleFrom(foregroundColor: Colors.green),
                      ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Bấm vào câu hỏi dưới đây để bắt đầu chấm bài.\nHoặc bấm biểu tượng thư mục để quản lý kho bài làm của câu đó.',
                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.indigo),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: questions.length,
                  itemBuilder: (context, index) {
                    final q = questions[index];
                    final totalScore = q.steps.fold(0.0, (sum, step) => sum + step.score);
                    
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade100,
                          child: Text('${index + 1}', style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(q.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Tổng điểm: ${totalScore.toStringAsFixed(2)} đ'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.folder_shared_outlined, color: Colors.orange),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => SubmissionManagementScreen(
                                      exam: widget.exam,
                                      question: q,
                                    ),
                                  ),
                                );
                              },
                              tooltip: 'Quản lý kho bài làm của câu này',
                            ),
                            if (widget.exam.googleSheetId != null)
                              IconButton(
                                icon: const Icon(Icons.add_to_photos, color: Colors.green, size: 20),
                                tooltip: 'Tạo Sheet cho câu hỏi này',
                                onPressed: () => _createQuestionSheet(q),
                              ),
                            const Icon(Icons.chevron_right, color: Colors.indigo),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => QuestionGradingScreen(
                                exam: widget.exam,
                                question: q,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
