import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class LatexTextPreview extends StatelessWidget {
  final String text;

  const LatexTextPreview({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const Text(
        'Kết quả sẽ hiển thị ở đây',
        style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
      );
    }

    final spans = <InlineSpan>[];
    final parts = text.split('\$');

    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;

      if (i % 2 == 0) {
        // Văn bản thường: Để TextSpan bọc trong SelectableText tự xuống dòng
        spans.add(TextSpan(
          text: parts[i],
          style: const TextStyle(fontSize: 18, color: Colors.black87, height: 1.5),
        ));
      } else {
        // Công thức Toán học: Bọc trong cuộn ngang để không làm vỡ giao diện
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Math.tex(
                parts[i],
                textStyle: const TextStyle(fontSize: 18),
                mathStyle: MathStyle.text,
                onErrorFallback: (err) => Text(
                  '\$${parts[i]}\$',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        ));
      }
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.left,
    );
  }
}
