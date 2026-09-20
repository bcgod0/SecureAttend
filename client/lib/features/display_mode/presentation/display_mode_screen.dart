import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// FR-6: Display Mode — full-screen rotating QR token for classroom projection.
/// Connects via STOMP WebSocket to /topic/session/{sessionId}/qr.
/// Falls back to REST polling if WebSocket cannot connect.
class DisplayModeScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const DisplayModeScreen({super.key, required this.sessionId});

  @override
  ConsumerState<DisplayModeScreen> createState() => _DisplayModeScreenState();
}

class _DisplayModeScreenState extends ConsumerState<DisplayModeScreen>
    with WidgetsBindingObserver {
  String _currentToken = '';
  int _sequenceNumber = 0;
  int _attendanceCount = 0;
  bool _isConnected = false;
  bool _isLoading = true;
  String? _sessionCourse;
  StompClient? _stompClient;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  int _rotationSeconds = 10;
  int _secondsLeft = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep screen on during Display Mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _bootstrapQrToken();
    _loadSessionInfo();
    _connectStomp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _stompClient?.deactivate();
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// Load the first QR token immediately via REST so there's no blank screen
  Future<void> _bootstrapQrToken() async {
    try {
      final data = await ref.read(apiClientProvider).getCurrentQrToken(widget.sessionId);
      if (mounted) {
        final rotationSeconds = (data['rotationSeconds'] as int?) ?? _rotationSeconds;
        setState(() {
          _rotationSeconds = rotationSeconds;
          _currentToken = data['token'] as String? ?? '';
          _secondsLeft = rotationSeconds;
          _isLoading = false;
        });
        _startCountdown(rotationSeconds);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSessionInfo() async {
    try {
      final session = await ref.read(apiClientProvider).getSession(widget.sessionId);
      if (mounted) {
        final rotationSeconds = (session['qrRotationSeconds'] as int?) ?? _rotationSeconds;
        setState(() {
          _rotationSeconds = rotationSeconds;
          _sessionCourse = '${session['courseCode']} — ${session['courseName']}';
          _attendanceCount = (session['attendanceSummary']?['present'] as int?) ?? 0;
        });
      }
    } catch (_) {}
  }

  void _connectStomp() {
    // Read token from secure storage for WebSocket Authorization header
    const storage = FlutterSecureStorage();

    Future.microtask(() async {
      final token = await storage.read(key: 'access_token');
      _stompClient = StompClient(
        config: StompConfig(
          url: 'ws://localhost:8080/ws',
          onConnect: _onStompConnected,
          onDisconnect: (_) {
            if (mounted) {
              setState(() => _isConnected = false);
              _startFallbackPolling();
            }
          },
          onStompError: (_) {
            if (mounted) {
              setState(() => _isConnected = false);
              _startFallbackPolling();
            }
          },
          onWebSocketError: (_) {
            if (mounted) {
              setState(() => _isConnected = false);
              _startFallbackPolling();
            }
          },
          connectionTimeout: const Duration(seconds: 5),
          reconnectDelay: const Duration(seconds: 10),
          stompConnectHeaders: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
          webSocketConnectHeaders: {
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
      _stompClient!.activate();
    });
  }

  void _onStompConnected(StompFrame frame) {
    if (!mounted) return;
    setState(() => _isConnected = true);
    _pollTimer?.cancel(); // Cancel fallback polling

    // Subscribe to QR token rotation updates
    _stompClient!.subscribe(
      destination: '/topic/session/${widget.sessionId}/qr',
      callback: (frame) {
        if (!mounted || frame.body == null) return;
        try {
          // Parse JSON: {"token": "...", "rotationSeconds": 30, "expiresAt": 1234, "sequenceNumber": 5}
          final body = frame.body!;
          final tokenMatch = RegExp(r'"token"\s*:\s*"([^"]+)"').firstMatch(body);
          final seqMatch = RegExp(r'"sequenceNumber"\s*:\s*(\d+)').firstMatch(body);
          final rotMatch = RegExp(r'"rotationSeconds"\s*:\s*(\d+)').firstMatch(body);

          if (tokenMatch != null) {
            final rotSeconds = rotMatch != null ? int.parse(rotMatch.group(1)!) : _rotationSeconds;
            setState(() {
              _rotationSeconds = rotSeconds;
              _currentToken = tokenMatch.group(1)!;
              _sequenceNumber = seqMatch != null ? int.parse(seqMatch.group(1)!) : _sequenceNumber + 1;
              _secondsLeft = rotSeconds;
            });
            _startCountdown(rotSeconds);
          }
        } catch (_) {}
      },
    );

    // Subscribe to attendance count updates
    _stompClient!.subscribe(
      destination: '/topic/session/${widget.sessionId}/attendance',
      callback: (frame) {
        if (!mounted || frame.body == null) return;
        try {
          final countMatch = RegExp(r'"present"\s*:\s*(\d+)').firstMatch(frame.body!);
          if (countMatch != null) {
            setState(() => _attendanceCount = int.parse(countMatch.group(1)!));
          }
        } catch (_) {}
      },
    );
  }

  void _startFallbackPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: _rotationSeconds), (_) async {
      try {
        final data = await ref.read(apiClientProvider).getCurrentQrToken(widget.sessionId);
        if (mounted) {
          final rotationSeconds = (data['rotationSeconds'] as int?) ?? _rotationSeconds;
          setState(() {
            _rotationSeconds = rotationSeconds;
            _currentToken = data['token'] as String? ?? _currentToken;
            _sequenceNumber++;
            _secondsLeft = rotationSeconds;
          });
          _startCountdown(rotationSeconds);
        }
      } catch (_) {}
    });
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    setState(() => _secondsLeft = seconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        if (_secondsLeft > 0) {
          _secondsLeft--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _closeSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Close Session'),
        content: const Text('Are you sure you want to close this attendance session?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Close Session'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ref.read(apiClientProvider).closeSession(widget.sessionId);
        if (mounted) context.pop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SafeArea(
              child: Column(
                children: [
                  // Header bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Row(
                      children: [
                        // Connection status
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isConnected ? AppTheme.successColor : Colors.orange,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isConnected ? 'Live' : 'Polling',
                              style: TextStyle(
                                color: _isConnected ? AppTheme.successColor : Colors.orange,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        // Course name
                        Expanded(
                          child: Text(
                            _sessionCourse ?? 'Loading...',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Attendance count
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.primaryColor.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.people, color: Colors.white70, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                '$_attendanceCount present',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Close session button
                        TextButton.icon(
                          onPressed: _closeSession,
                          icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                          label: const Text('End', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  ),

                  // QR Code — centered and large
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_currentToken.isEmpty)
                            const Text(
                              'Waiting for QR token...',
                              style: TextStyle(color: Colors.white54, fontSize: 18),
                            )
                          else
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.primaryColor.withOpacity(0.4),
                                        blurRadius: 60,
                                        spreadRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: QrImageView(
                                    data: _currentToken,
                                    size: 320,
                                    version: QrVersions.auto,
                                  ),
                                ),
                                const SizedBox(height: 32),
                                // Countdown ring
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.timer_outlined, color: Colors.white54, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Refreshes in $_secondsLeft seconds',
                                      style: const TextStyle(color: Colors.white54, fontSize: 16),
                                    ),
                                    if (_sequenceNumber > 0) ...[
                                      const SizedBox(width: 24),
                                      Text(
                                        '#$_sequenceNumber',
                                        style: const TextStyle(color: Colors.white24, fontSize: 14),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Footer branding
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.shield_outlined, color: Colors.white24, size: 16),
                        const SizedBox(width: 8),
                        const Text(
                          'SecureAttend — Anti-Proxy Verification',
                          style: TextStyle(color: Colors.white24, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
