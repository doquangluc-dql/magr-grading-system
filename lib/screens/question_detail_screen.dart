import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:http/http.dart' as http;
import '../models/question.dart';
import '../services/database_api.dart';
import 'barem_create_screen.dart';

class QuestionDetailScreen extends StatefulWidget {
  final Question question;
  final String? googleSheetUrl;
  const QuestionDetailScreen({super.key, required this.question, this.googleSheetUrl});

  @override
  State<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends State<QuestionDetailScreen> {
  late Question _currentQuestion;
  bool _isEditingTitle = false;
  late TextEditingController _titleController;
  bool _isCreatingSheet = false;

  @override
  void initState() {
    super.initState();
    _currentQuestion = widget.question;
    _titleController = TextEditingController(text: _currentQuestion.title);
  }
  
  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _saveTitle() async {
    final newTitle = _titleController.text.trim();
    if (newTitle.isNotEmpty && newTitle != _currentQuestion.title) {
      setState(() {
         _currentQuestion.title = newTitle;
      });
      await DatabaseApi.updateQuestion(_currentQuestion);
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã cập nhật tên câu hỏi thành công!')),
         );
      }
    }
    setState(() {
      _isEditingTitle = false;
    });
  }

  Future<void> _createSheet() async {
    if (widget.googleSheetUrl == null) return;

    setState(() => _isCreatingSheet = true);
    try {
      final url = Uri.parse('');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'spreadsheetUrl': widget.googleSheetUrl,
          'sheetName': _currentQuestion.title,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Đã tạo Sheet thành công!'), backgroundColor: Colors.green),
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
    } finally {
      if (mounted) setState(() => _isCreatingSheet = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isEditingTitle 
            ? TextField(
                controller: _titleController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 20),
                decoration: const InputDecoration(
                  border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                  hintText: ' tên câu hỏi mới',
                  hintStyle: TextStyle(color: Colors.white70),
                ),
                onSubmitted: (_) => _saveTitle(),
              )
            : Text(_currentQuestion.title),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isEditingTitle ? Icons.check : Icons.edit),
            tooltip: 'Đổi tên',
            onPressed: () {
              if (_isEditingTitle) {
                _saveTitle();
              } else {
                setState(() {
                  _titleController.text = _currentQuestion.title;
                  _isEditingTitle = true;
                });
              }
            },
          ),
          if (widget.googleSheetUrl != null)
            IconButton(
              icon: _isCreatingSheet 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.table_chart),
              tooltip: 'Tạo Sheet',
              onPressed: _isCreatingSheet ? null : _createSheet,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hiển thị nội dung đề bài (Nếu có)
            if (_currentQuestion.content != null && _currentQuestion.content!.isNotEmpty) ...[
              const Text(
                'NỘI DUNG ĐỀ BÀI:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueAccent),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _renderMixedText(_currentQuestion.content!),
              ),
              const SizedBox(height: 24),
            ],

            // Bảng hiện Barem
            const Text(
              'BAREM CHẤM ĐIỂM:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueAccent),
            ),
            const SizedBox(height: 8),
            if (_currentQuestion.steps.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Câu hỏi này chưa có barem nào.', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              Table(
                border: TableBorder.all(color: Colors.black87, width: 1.0),
                columnWidths: const {
                  0: FlexColumnWidth(6.5), // NỘI DUNG
                  1: FlexColumnWidth(2.0), // ĐIỂM
                },
                children: _buildTableRows(),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // Điều hướng sang màn hình Chỉnh sửa
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BaremCreateScreen(question: _currentQuestion),
            ),
          ).then((updatedQuestion) {
            // Khi quay lại, cập nhật State nếu người dùng đã lưu
            if (updatedQuestion != null && updatedQuestion is Question) {
              setState(() {
                _currentQuestion = updatedQuestion;
              });
            }
          });
        },
        icon: const Icon(Icons.edit),
        label: const Text('Chỉnh Sửa'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
    );
  }

  List<TableRow> _buildTableRows() {
    List<TableRow> rows = [];

    // Header Row
    rows.add(
      TableRow(
        decoration: BoxDecoration(color: Colors.grey.shade300),
        children: const [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('NỘI DUNG ĐÁP ÁN', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('ĐIỂM', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    // Data Rows
    for (int stepIndex = 0; stepIndex < _currentQuestion.steps.length; stepIndex++) {
      final step = _currentQuestion.steps[stepIndex];
      rows.add(
        TableRow(
          children: [
            _buildLatexCell(step.latexCode),
            _buildCell('${step.score.toStringAsFixed(2)} đ', align: TextAlign.right),
          ],
        ),
      );
    }

    // Total Row
    final totalScore = _currentQuestion.steps.fold(0.0, (sum, step) => sum + step.score);
    rows.add(
      TableRow(
        decoration: BoxDecoration(color: Colors.orange.shade50),
        children: [
          _buildCell('TỔNG ĐIỂM:', align: TextAlign.right, isBold: true),
          _buildCell('${totalScore.toStringAsFixed(2)} đ', align: TextAlign.right, isBold: true),
        ],
      ),
    );

    return rows;
  }

  Widget _buildCell(String text, {TextAlign align = TextAlign.center, bool isBold = false}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 16 : 14,
          ),
        ),
      ),
    );
  }

  Widget _buildLatexCell(String latexCode) {
    bool isLatex = latexCode.contains('\$');
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: isLatex
            ? _renderMixedText(latexCode)
            : Text(latexCode, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  Widget _renderMixedText(String input) {
    List<Widget> spans = [];
    final fragments = input.split('\$');
    for (int i = 0; i < fragments.length; i++) {
      if (i % 2 == 1) {
        spans.add(Math.tex(
          fragments[i],
          textStyle: const TextStyle(fontSize: 18),
          mathStyle: MathStyle.display,
        ));
      } else {
        if (fragments[i].isNotEmpty) {
          spans.add(Text(fragments[i], style: const TextStyle(fontSize: 16)));
        }
      }
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: spans,
    );
  }
}
