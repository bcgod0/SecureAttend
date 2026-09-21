import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

/// FR-6: Display Mode — rotating QR token with live real-time attendance panel.
/// Connects via STOMP WebSocket to:
/// - /topic/session/{sessionId}/qr for rotating tokens
/// - /topic/session/{sessionId}/attendance for real-time student attendance
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
  List<Map<String, dynamic>> _attendees = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep screen on during Display Mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _bootstrapQrToken();
    _loadSessionInfo();
    _loadAttendanceList();
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

  Future<void> _loadAttendanceList() async {
    try {
      final data = await ref.read(apiClientProvider).getAttendance(widget.sessionId);
      final content = data['content'] as List<dynamic>?;
      if (content != null && mounted) {
        setState(() {
          _attendees = content.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _attendanceCount = _attendees
              .where((a) => a['finalStatus'] == 'PRESENT' || a['finalStatus'] == 'VERIFIED' || a['finalStatus'] == 'FLAGGED')
              .length;
        });
      }
    } catch (_) {}
  }

  void _connectStomp() {
    const storage = FlutterSecureStorage();

    Future.microtask(() async {
      final token = await storage.read(key: 'access_token');
      _stompClient = StompClient(
        config: StompConfig(
          url: defaultWsUrl,
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

    // Subscribe to live attendance updates (students marking attendance)
    _stompClient!.subscribe(
      destination: '/topic/session/${widget.sessionId}/attendance',
      callback: (frame) {
        if (!mounted || frame.body == null) return;
        try {
          final bodyStr = frame.body!;
          Map<String, dynamic>? data;
          try {
            data = jsonDecode(bodyStr) as Map<String, dynamic>?;
          } catch (_) {}

          final studentName = data?['studentName']?.toString() ??
              RegExp(r'"studentName"\s*:\s*"([^"]+)"').firstMatch(bodyStr)?.group(1);
          final finalStatus = data?['finalStatus']?.toString() ??
              RegExp(r'"finalStatus"\s*:\s*"([^"]+)"').firstMatch(bodyStr)?.group(1) ??
              'PRESENT';
          final scanId = data?['scanId']?.toString() ??
              RegExp(r'"scanId"\s*:\s*"([^"]+)"').firstMatch(bodyStr)?.group(1);
          final submittedAt = data?['submittedAt']?.toString() ??
              RegExp(r'"submittedAt"\s*:\s*"([^"]+)"').firstMatch(bodyStr)?.group(1) ??
              DateTime.now().toIso8601String();

          if (studentName != null && studentName.isNotEmpty) {
            setState(() {
              _attendees.removeWhere((a) =>
                  (scanId != null && scanId.isNotEmpty && a['scanId']?.toString() == scanId) ||
                  (a['studentName'] == studentName && a['submittedAt'] == submittedAt));

              _attendees.insert(0, {
                'scanId': scanId ?? '',
                'studentName': studentName,
                'finalStatus': finalStatus,
                'submittedAt': submittedAt,
              });
              _attendanceCount = _attendees
                  .where((a) => a['finalStatus'] == 'PRESENT' || a['finalStatus'] == 'VERIFIED' || a['finalStatus'] == 'FLAGGED')
                  .length;
            });
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

      _loadAttendanceList();
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
        if (mounted) context.go('/faculty/sessions');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  String _formatTime(dynamic timeValue) {
    if (timeValue == null) return '';
    try {
      final dt = DateTime.parse(timeValue.toString()).toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m:$s $ampm';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SafeArea(
              child: Column(
                children: [
                  // Top Header bar with Back button
                  _buildHeaderBar(context),
                  const Divider(color: Colors.white12, height: 1),

                  // Main Content: Left side QR, Right side Live Attendance
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 750;
                        if (isWide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Left: QR Code panel
                              Expanded(
                                flex: 6,
                                child: _buildQrPanel(),
                              ),
                              // Vertical Divider
                              const VerticalDivider(color: Colors.white12, width: 1),
                              // Right: Live Attendees panel
                              Expanded(
                                flex: 4,
                                child: _buildAttendancePanel(),
                              ),
                            ],
                          );
                        } else {
                          // Narrow Screen: Stack vertically
                          return Column(
                            children: [
                              Expanded(
                                flex: 5,
                                child: _buildQrPanel(),
                              ),
                              const Divider(color: Colors.white12, height: 1),
                              Expanded(
                                flex: 5,
                                child: _buildAttendancePanel(),
                              ),
                            ],
                          );
                        }
                      },
                    ),
                  ),

                  // Footer branding
                  _buildFooter(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: 'Back to Dashboard',
            onPressed: () => context.go('/faculty/sessions'),
          ),
          const SizedBox(width: 8),

          // Connection status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (_isConnected ? AppTheme.successColor : Colors.orange).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_isConnected ? AppTheme.successColor : Colors.orange).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected ? AppTheme.successColor : Colors.orange,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _isConnected ? 'Live' : 'Polling',
                  style: TextStyle(
                    color: _isConnected ? AppTheme.successColor : Colors.orange,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Course name
          Expanded(
            child: Text(
              _sessionCourse ?? 'Loading Session...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Attendance count pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primaryColor.withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  '$_attendanceCount present',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Close session button
          ElevatedButton.icon(
            onPressed: _closeSession,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.85),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('End Session'),
          ),
        ],
      ),
    );
  }

  Widget _buildQrPanel() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_currentToken.isEmpty)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Generating dynamic QR token...',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                ],
              )
            else
              Column(
                children: [
                  // QR card with radiant glow
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withOpacity(0.35),
                          blurRadius: 50,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: _currentToken,
                      size: 280,
                      version: QrVersions.auto,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Countdown ring & sequence
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, color: Colors.white70, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Refreshes in $_secondsLeft seconds',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_sequenceNumber > 0) ...[
                          const SizedBox(width: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '#$_sequenceNumber',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Point your phone camera at this QR code with the SecureAttend app',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendancePanel() {
    final presentCount = _attendees
        .where((a) => a['finalStatus'] == 'PRESENT' || a['finalStatus'] == 'VERIFIED')
        .length;
    final flaggedCount = _attendees.where((a) => a['finalStatus'] == 'FLAGGED').length;

    return Container(
      color: const Color(0xFF111827),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header of the attendance list
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                const Icon(Icons.how_to_reg_rounded, color: AppTheme.successColor, size: 22),
                const SizedBox(width: 10),
                const Text(
                  'Live Attendance',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (presentCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$presentCount present',
                      style: const TextStyle(
                        color: AppTheme.successColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (flaggedCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$flaggedCount flagged',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Student List
          Expanded(
            child: _attendees.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_scanner,
                          size: 48,
                          color: Colors.white.withOpacity(0.2),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No scans yet',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Students will appear here immediately upon scanning the QR code.',
                            style: TextStyle(color: Colors.white38, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: _attendees.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _attendees[index];
                      final name = item['studentName'] as String? ?? 'Unknown';
                      final status = (item['finalStatus'] as String? ?? 'PRESENT').toUpperCase();
                      final timeStr = _formatTime(item['submittedAt']);
                      final isPresent = status == 'PRESENT' || status == 'VERIFIED';
                      final isFlagged = status == 'FLAGGED';

                      final statusColor = isPresent
                          ? AppTheme.successColor
                          : isFlagged
                              ? Colors.orange
                              : Colors.red;
                      final statusText = isPresent
                          ? 'Present'
                          : isFlagged
                              ? 'Flagged'
                              : 'Rejected';
                      final statusIcon = isPresent
                          ? Icons.check_circle
                          : isFlagged
                              ? Icons.warning_amber_rounded
                              : Icons.cancel;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Avatar with initial
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: statusColor.withValues(alpha: 0.2),
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Student Name & Time
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (timeStr.isNotEmpty)
                                    Text(
                                      timeStr,
                                      style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Status Pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    statusIcon,
                                    size: 12,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.shield_outlined, color: Colors.white24, size: 15),
          SizedBox(width: 8),
          Text(
            'SecureAttend — Multi-Layer Biometric & Anti-Proxy Verification',
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
