import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import '../models/question.dart';

class ExamBaremPreviewScreen extends StatelessWidget {
  final String examTitle;
  final List<Question> questions;

  const ExamBaremPreviewScreen({
    super.key,
    required this.examTitle,
    required this.questions,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate total score
    double grandTotal = 0;
    for (var q in questions) {
      grandTotal += q.steps.fold(0.0, (sum, step) => sum + step.score);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Barem: $examTitle'),
        backgroundColor: Colors.deepPurpleAccent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Header Thông báo tổng điểm
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16.0),
            color: Colors.deepPurple.shade50,
            child: Text(
              'Số câu hỏi: ${questions.length}  |  Tổng Điểm Toàn Đề: ${grandTotal.toStringAsFixed(2)} đ',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.deepPurple),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Table(
                border: TableBorder.all(color: Colors.black87, width: 1.0),
                columnWidths: const {
                  0: FlexColumnWidth(1.5), // CÂU
                  1: FlexColumnWidth(6.5), // NỘI DUNG
                  2: FlexColumnWidth(2.0), // ĐIỂM
                },
                children: _buildTableRows(questions),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TableRow> _buildTableRows(List<Question> questions) {
    List<TableRow> rows = [];

    // Header Row
    rows.add(
      TableRow(
        decoration: BoxDecoration(color: Colors.grey.shade200),
        children: const [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('CÂU', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('NỘI DUNG', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('ĐIỂM', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    // Data Rows
    for (int qIndex = 0; qIndex < questions.length; qIndex++) {
      final q = questions[qIndex];
      final totalScore = q.steps.fold(0.0, (sum, step) => sum + step.score);

      bool hasContent = q.content != null && q.content!.trim().isNotEmpty;

      if (hasContent) {
        rows.add(
          TableRow(
            decoration: BoxDecoration(color: Colors.blue.shade50),
            children: [
              _buildQuestionHeaderCell(qIndex + 1, totalScore),
              _buildContentCell(q.content!),
              _buildCell('', align: TextAlign.center),
            ],
          ),
        );

        if (q.steps.isEmpty) {
          rows.add(
            TableRow(
              children: [
                const TableCell(child: SizedBox()),
                _buildCell('(Chưa có barem)', align: TextAlign.left),
                _buildCell('0.0 đ', align: TextAlign.right),
              ],
            ),
          );
        } else {
          for (int stepIndex = 0; stepIndex < q.steps.length; stepIndex++) {
            final step = q.steps[stepIndex];
            rows.add(
              TableRow(
                children: [
                  const TableCell(child: SizedBox()),
                  _buildLatexCell(step.latexCode),
                  _buildCell('${step.score.toStringAsFixed(2)} đ', align: TextAlign.right),
                ],
              ),
            );
          }
        }
      } else {
        if (q.steps.isEmpty) {
          rows.add(
            TableRow(
              children: [
                _buildQuestionHeaderCell(qIndex + 1, totalScore),
                _buildCell('(Chưa có barem)', align: TextAlign.left),
                _buildCell('0.0 đ', align: TextAlign.right),
              ],
            ),
          );
        } else {
          for (int stepIndex = 0; stepIndex < q.steps.length; stepIndex++) {
            final step = q.steps[stepIndex];
            rows.add(
              TableRow(
                children: [
                  stepIndex == 0
                      ? _buildQuestionHeaderCell(qIndex + 1, totalScore)
                      : const TableCell(child: SizedBox()),

                  _buildLatexCell(step.latexCode),
                  _buildCell('${step.score.toStringAsFixed(2)} đ', align: TextAlign.right),
                ],
              ),
            );
          }
        }
      }
    }

    return rows;
  }

  Widget _buildContentCell(String content) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Đề bài:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              const SizedBox(height: 4),
              content.contains(r'$')
                  ? _renderMixedText(content)
                  : Text(content, style: const TextStyle(fontSize: 16)),
            ]
        ),
      ),
    );
  }

  // A read-only cell for the first column that NO LONGER includes the delete button
  Widget _buildQuestionHeaderCell(int questionNumber, double totalScore) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Text(
          '$questionNumber\n(${totalScore.toStringAsFixed(2)}đ)',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildCell(String text, {bool isTitleRow = false, TextAlign align = TextAlign.center}) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(
            fontWeight: isTitleRow ? FontWeight.bold : FontWeight.normal,
            fontSize: isTitleRow ? 16 : 14,
          ),
        ),
      ),
    );
  }

  Widget _buildLatexCell(String latexCode) {
    // Basic text vs latex parsing
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
        // It's math
        spans.add(Math.tex(
          fragments[i],
          textStyle: const TextStyle(fontSize: 18),
          mathStyle: MathStyle.display,
        ));
      } else {
        // It's normal text
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
