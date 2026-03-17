class BaremStep {
  String latexCode;
  double score;

  BaremStep({
    this.latexCode = '',
    this.score = 0.0,
  });

  factory BaremStep.fromJson(Map<String, dynamic> json) {
    return BaremStep(
      latexCode: json['latexCode'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latexCode': latexCode,
      'score': score,
    };
  }
}
