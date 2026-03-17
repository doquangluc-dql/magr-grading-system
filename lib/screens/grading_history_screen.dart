import 'package:flutter/material.dart';
import '../models/grading_batch.dart';
import '../models/grading_session.dart';
import '../services/database_api.dart';
import 'dart:convert';
import 'dart:async';

class GradingHistoryScreen extends StatefulWidget {
  const GradingHistoryScreen({super.key});

  @override
  State<GradingHistoryScreen> createState() => _GradingHistoryScreenState();
}

class _GradingHistoryScreenState extends State<GradingHistoryScreen> with SingleTickerProviderStateMixin {
  late Future<List<GradingBatch>> _batchesFuture;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _loadBatches();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _loadBatches() {
    setState(() {
      _batchesFuture = DatabaseApi.getGradingBatches();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GradingBatch>>(
      future: _batchesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Lỗi: ${snapshot.error}'));
        }
        final batches = snapshot.data ?? [];
        if (batches.isEmpty) {
          return const Center(child: Text('Chưa có lịch sử chấm nào.'));
        }

        return RefreshIndicator(
          onRefresh: () async => _loadBatches(),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: batches.length,
            itemBuilder: (context, index) {
              final batch = batches[index];
              final successRate = batch.totalItems > 0 ? batch.completedItems / batch.totalItems : 0.0;
              final failRate = batch.totalItems > 0 ? batch.failedItems / batch.totalItems : 0.0;
              final isProcessing = batch.status == 'Processing';
              
              return AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: isProcessing 
                        ? [
                            BoxShadow(
                              color: Colors.indigo.withOpacity(0.3 * _pulseController.value),
                              blurRadius: 8 * _pulseController.value,
                              spreadRadius: 2 * _pulseController.value,
                            )
                          ] 
                        : null,
                    ),
                    child: Card(
                      elevation: isProcessing ? 0 : 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isProcessing 
                            ? Colors.indigo.withOpacity(0.5) 
                            : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => _openBatchDetail(batch),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      batch.batchName, 
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      maxLines: 1, overflow: TextOverflow.ellipsis
                                    ),
                                  ),
                                  if (batch.sheetUrl != null && batch.sheetUrl!.isNotEmpty)
                                    IconButton(
                                      icon: const Icon(Icons.table_chart_outlined, color: Colors.green, size: 24),
                                      onPressed: () {
                                        // TODO: Open URL 
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Mở Sheet: ${batch.sheetUrl}')),
                                        );
                                      },
                                      constraints: const BoxConstraints(),
                                      padding: EdgeInsets.zero,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('${batch.examTitle} • ${batch.questionTitle}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              const SizedBox(height: 12),
                              // Multi-color Progress Bar with Stripes
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: StripedProgressBar(
                                  successRate: successRate,
                                  failRate: failRate,
                                  isProcessing: isProcessing,
                                  pulseAnimation: _pulseController,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _buildStatIcon(Icons.check_circle, Colors.green, '${batch.completedItems}'),
                                  const SizedBox(width: 12),
                                  _buildStatIcon(Icons.error, Colors.red, '${batch.failedItems}'),
                                  const SizedBox(width: 12),
                                  _buildStatIcon(Icons.inventory_2, Colors.grey, '${batch.totalItems}'),
                                  const Spacer(),
                                  if (isProcessing)
                                    const SizedBox(
                                      width: 12, height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.indigo),
                                    )
                                  else
                                    Text(
                                      batch.status == 'Completed' ? 'Hoàn tất' : batch.status,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  void _openBatchDetail(GradingBatch batch) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (ctx) => GradingBatchDetailScreen(batchId: batch.id, batchTitle: batch.batchName)),
    );
  }

  Widget _buildStatIcon(IconData icon, Color color, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
      ],
    );
  }
}

class StripedProgressBar extends StatelessWidget {
  final double successRate;
  final double failRate;
  final bool isProcessing;
  final Animation<double> pulseAnimation;

  const StripedProgressBar({
    super.key,
    required this.successRate,
    required this.failRate,
    required this.isProcessing,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 10,
      width: double.infinity,
      color: Colors.grey.shade200,
      child: Stack(
        children: [
          Row(
            children: [
              if (successRate > 0)
                Expanded(
                  flex: (successRate * 1000).toInt(),
                  child: Container(color: Colors.green),
                ),
              if (failRate > 0)
                Expanded(
                  flex: (failRate * 1000).toInt(),
                  child: Container(color: Colors.red),
                ),
              if (1 - (successRate + failRate) > 0)
                Expanded(
                  flex: ((1 - (successRate + failRate)) * 1000).toInt(),
                  child: Container(color: Colors.transparent),
                ),
            ],
          ),
          if (isProcessing)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: pulseAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    painter: StripePainter(offset: pulseAnimation.value * 20),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class StripePainter extends CustomPainter {
  final double offset;
  StripePainter({required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    for (double i = -20; i < size.width + 20; i += 12) {
      canvas.drawLine(
        Offset(i + offset, 0),
        Offset(i + offset - 6, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(StripePainter oldDelegate) => oldDelegate.offset != offset;
}

class GradingBatchDetailScreen extends StatefulWidget {
  final String batchId;
  final String batchTitle;
  const GradingBatchDetailScreen({super.key, required this.batchId, required this.batchTitle});

  @override
  State<GradingBatchDetailScreen> createState() => _GradingBatchDetailScreenState();
}

class _GradingBatchDetailScreenState extends State<GradingBatchDetailScreen> {
  List<GradingSession>? _sessions;
  Timer? _refreshTimer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchSessions();
    // Poll every 4 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      _fetchSessions();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchSessions() async {
    try {
      final sessions = await DatabaseApi.getSessionsForBatch(widget.batchId);
      if (mounted) {
        setState(() {
          _sessions = sessions..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error polling sessions: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.batchTitle),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _fetchSessions, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : (_sessions == null || _sessions!.isEmpty)
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.hourglass_empty, size: 48, color: Colors.grey),
                   SizedBox(height: 16),
                   Text('Đang khởi tạo danh sách...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _sessions!.length,
              separatorBuilder: (ctx, i) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final s = _sessions![index];
                final isPending = s.n8nStatus == 'Pending';
                
                return ListTile(
                  leading: s.studentImageBase64 != null 
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.memory(
                          base64Decode(s.studentImageBase64!.split(',').last), 
                          width: 44, height: 44, fit: BoxFit.cover,
                          gaplessPlayback: true, // GIÚP HẾT NHÁY ẢNH
                        ),
                      )
                    : const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(s.studentName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.n8nStatus == 'Success')
                        Text('Điểm: ${s.score ?? 0} đ', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                      else if (s.n8nStatus == 'Failed')
                        Text('Lỗi: ${s.errorDetails ?? "Xử lý thất bại"}', style: const TextStyle(color: Colors.red, fontSize: 11))
                      else
                        Row(
                          children: [
                            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text(isPending ? 'Đang chờ...' : 'Đang chấm...', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                    ],
                  ),
                  trailing: Icon(
                    s.n8nStatus == 'Success' ? Icons.check_circle : (s.n8nStatus == 'Failed' ? Icons.error : Icons.hourglass_empty),
                    color: s.n8nStatus == 'Success' ? Colors.green : (s.n8nStatus == 'Failed' ? Colors.red : Colors.grey),
                  ),
                );
              },
            ),
    );
  }
}
