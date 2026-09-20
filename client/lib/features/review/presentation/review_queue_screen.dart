import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

class ReviewQueueScreen extends ConsumerStatefulWidget {
  const ReviewQueueScreen({super.key});

  @override
  ConsumerState<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends ConsumerState<ReviewQueueScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    try {
      final data = await ref.read(apiClientProvider).getReviewQueue();
      setState(() {
        _items = List<Map<String, dynamic>>.from(data['content'] ?? []);
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _review(String scanId, String decision) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).reviewScan(scanId, decision: decision);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Scan ${decision.toLowerCase()}'),
          backgroundColor: decision == 'APPROVED' ? AppTheme.successColor : AppTheme.errorColor,
        ),
      );
      _loadQueue(); // Refresh
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review Queue')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text('No flagged scans', style: TextStyle(color: Colors.grey.shade600, fontSize: 18)),
                      const SizedBox(height: 8),
                      const Text('All clear! No scans require review.'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadQueue,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.warning_amber, color: AppTheme.warningColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item['studentName'] ?? 'Unknown Student',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                    ),
                                  ),
                                  Text(
                                    item['courseCode'] ?? '',
                                    style: TextStyle(color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.warningColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  item['flaggedReason'] ?? 'Unknown reason',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Layer results
                              if (item['layerResults'] != null)
                                ...List<Map<String, dynamic>>.from(item['layerResults']).map((layer) {
                                  final passed = layer['passed'] as bool;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          passed ? Icons.check_circle : Icons.cancel,
                                          size: 16,
                                          color: passed ? AppTheme.successColor : AppTheme.errorColor,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(layer['layer'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            layer['detail'] as String,
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),

                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.close, size: 18),
                                    label: const Text('Reject'),
                                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.errorColor),
                                    onPressed: () => _review(item['scanId'], 'REJECTED'),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.check, size: 18),
                                    label: const Text('Approve'),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successColor),
                                    onPressed: () => _review(item['scanId'], 'APPROVED'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
