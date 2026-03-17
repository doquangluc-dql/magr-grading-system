import 'package:flutter/material.dart';
import '../models/barem_step.dart';
import '../models/question.dart';
import '../services/database_api.dart';
import '../widgets/latex_text_preview.dart';

class BaremCreateScreen extends StatefulWidget {
  final Question question;
  const BaremCreateScreen({super.key, required this.question});

  @override
  State<BaremCreateScreen> createState() => _BaremCreateScreenState();
}

class _BaremCreateScreenState extends State<BaremCreateScreen> {
  // Kho chứa danh sách các bước ban đầu (Lấy từ question, nếu rỗng thì tạo 1 bước)
  late List<BaremStep> steps;
  late TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    // Khởi tạo clone từ steps của question để cho phép chỉnh sửa
    if (widget.question.steps.isNotEmpty) {
      steps = widget.question.steps.map((e) => BaremStep(latexCode: e.latexCode, score: e.score)).toList();
    } else {
      steps = [BaremStep()];
    }
    // Gán giá trị nội dung ban đầu
    _contentController = TextEditingController(text: widget.question.content);
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  // Hàm thêm bước mới
  void addStep() {
    setState(() {
      steps.add(BaremStep());
    });
  }

  // Hàm để Lưu Barem đẩy lên Server
  void _saveBaremData() async {
    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đang lưu Barem lên MongoDB...'))
    );

    // Allow update content before firing API update (this won't update the 'content' field on DB yet
    // because API only updates steps. Let's fix that below by updating the DB API method later if needed.
    // However, the object is local so updating widget.question.content works for UI.
    // For full architecture, we should update the entire question Document, or explicitly set the 'content' column)
    
    // We will update local object
    widget.question.content = _contentController.text;
    widget.question.steps = steps.map((e) => BaremStep(latexCode: e.latexCode, score: e.score)).toList();

    // Call API: now we update BOTH steps and content
    await DatabaseApi.updateQuestion(widget.question);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Lưu Barem lên Cloud thành công!'),
          backgroundColor: Colors.green,
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhập Barem Đáp Án'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _saveBaremData,
            icon: const Icon(Icons.save, color: Colors.white),
            label: const Text('Lưu Barem', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 1. Khung Nhập Nội Dung Bài Toán
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _contentController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Nội dung đề bài (Không bắt buộc)',
                      hintText: r'VD: Giải phương trình bậc 2: $x^2 - 4x + 4 = 0$',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.blue.shade50,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 110, 
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blue.shade200, width: 2),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                    ),
                    alignment: Alignment.topLeft,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _contentController,
                      builder: (context, value, child) {
                        return LatexTextPreview(text: value.text);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(thickness: 2),
          // 2. Danh sách các bước giải (Barem)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: steps.length,
              itemBuilder: (context, index) {
                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Bước ${index + 1}', 
                           style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          // Ô nhập Điểm MỚI
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              initialValue: steps[index].score.toString(),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Điểm',
                                border: OutlineInputBorder(),
                                isDense: true,
                                suffixText: 'đ',
                              ),
                              onChanged: (value) {
                                steps[index].score = double.tryParse(value) ?? 0.0;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.camera_alt, color: Colors.blue),
                            tooltip: 'Chụp/Tải ảnh gọi Gemini OCR',
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Tính năng OCR Gemini sẽ nằm ở đây!'))
                              );
                            },
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Ô Input để giáo viên gõ cú pháp
                      Expanded(
                        child: TextFormField(
                          initialValue: steps[index].latexCode,
                          maxLines: 4,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            hintText: r'Nhập nội dung (VD: Học sinh viết đúng $x+1=2$)',
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                          onChanged: (value) {
                            setState(() {
                              steps[index].latexCode = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      
                      // 2. Ô Output Preview Render Toán Học
                      Expanded(
                        child: Container(
                          height: 110, // Giữ chiều cao tương đương ô text
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue.shade200, width: 2),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.white,
                          ),
                          alignment: Alignment.topLeft,
                          child: LatexTextPreview(text: steps[index].latexCode),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
          );
        },
      ),
    ),
  ],
),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addStep,
        icon: const Icon(Icons.add),
        label: const Text('Thêm Bước Giải'),
      ),
    );
  }
}
