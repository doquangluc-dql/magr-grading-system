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
        // Văn bản thường
        spans.add(TextSpan(
          text: parts[i],
          style: const TextStyle(fontSize: 18, color: Colors.black87),
        ));
      } else {
        // Công thức Toánhọc
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Math.tex(
            parts[i],
            textStyle: const TextStyle(fontSize: 18),
            onErrorFallback: (err) => Text(
              '\$${parts[i]}\$',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ));
      }
    }

    return SingleChildScrollView(
      child: SelectableText.rich(
        TextSpan(children: spans),
      ),
    );
  }
}
