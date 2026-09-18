import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// FR-6: Display Mode — full-screen rotating QR token for classroom projection.
/// Synced via WebSocket (STOMP), not polling.
class DisplayModeScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const DisplayModeScreen({super.key, required this.sessionId});

  @override
  ConsumerState<DisplayModeScreen> createState() => _DisplayModeScreenState();
}

class _DisplayModeScreenState extends ConsumerState<DisplayModeScreen> {
  String _currentToken = '';
  int _sequenceNumber = 0;
  int _attendanceCount = 0;
  bool _isConnected = false;
  Timer? _mockTimer; // Placeholder for WebSocket — will use STOMP in production

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    _loadSessionInfo();
  }

  @override
  void dispose() {
    _mockTimer?.cancel();
    super.dispose();
  }

  void _connectWebSocket() {
    // In production, this connects via STOMP:
    //   stomp_dart_client → ws://host:8080/ws
    //   subscribe to /topic/session/{sessionId}/qr
    //   subscribe to /topic/session/{sessionId}/attendance
    //
    // For now, simulate with a timer that would be replaced by actual WebSocket messages
    setState(() => _isConnected = true);

    _mockTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      setState(() {
        _sequenceNumber++;
        // In production, _currentToken comes from WebSocket message
        _currentToken = 'secureattend://${widget.sessionId}/seq=$_sequenceNumber/t=${DateTime.now().millisecondsSinceEpoch}';
      });
    });

    // Generate initial token
    setState(() {
      _sequenceNumber = 1;
      _currentToken = 'secureattend://${widget.sessionId}/seq=1/t=${DateTime.now().millisecondsSinceEpoch}';
    });
  }

  Future<void> _loadSessionInfo() async {
    try {
      final data = await ref.read(apiClientProvider).getSession(widget.sessionId);
      setState(() {
        _attendanceCount = data['attendanceSummary']?['total'] ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _closeSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Close Session?'),
        content: const Text('No more scans will be accepted after closing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Close Session'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(apiClientProvider).closeSession(widget.sessionId);
        if (mounted) context.go('/faculty/sessions');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorColor),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.go('/faculty/sessions'),
                  ),
                  const Spacer(),
                  // Connection indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isConnected
                          ? AppTheme.successColor.withOpacity(0.2)
                          : AppTheme.errorColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isConnected ? Icons.wifi : Icons.wifi_off,
                          size: 16,
                          color: _isConnected ? AppTheme.successColor : AppTheme.errorColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isConnected ? 'Live' : 'Disconnected',
                          style: TextStyle(
                            color: _isConnected ? AppTheme.successColor : AppTheme.errorColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Attendance count
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_attendanceCount scans',
                      style: const TextStyle(color: AppTheme.primaryColor, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.stop_circle, color: AppTheme.errorColor),
                    onPressed: _closeSession,
                    tooltip: 'Close Session',
                  ),
                ],
              ),
            ),

            // QR Code — full screen
            Expanded(
              child: Center(
                child: _currentToken.isEmpty
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: QrImageView(
                              data: _currentToken,
                              version: QrVersions.auto,
                              size: MediaQuery.of(context).size.shortestSide * 0.6,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Scan this QR code to mark attendance',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'QR #$_sequenceNumber',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
