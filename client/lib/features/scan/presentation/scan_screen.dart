import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/services/device_fingerprint_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

/// Scan flow state machine
enum _ScanPhase {
  idle,        // Waiting for tap
  scanning,    // QR camera open
  capturing,   // Selfie being captured
  verifying,   // Sending to backend
  done,        // Result shown
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  _ScanPhase _phase = _ScanPhase.idle;
  Map<String, dynamic>? _verificationResult;
  String? _errorMessage;
  bool _enrollmentChecked = false;
  bool _faceEnrolled = false;
  bool _deviceRegistered = false;

  // Collected signals
  String? _qrToken;
  List<int>? _faceFrameBytes;
  Position? _position;

  @override
  void initState() {
    super.initState();
    _checkEnrollment();
  }

  Future<void> _checkEnrollment() async {
    try {
      final status = await ref.read(apiClientProvider).getEnrollmentStatus();
      setState(() {
        _faceEnrolled = status['faceEnrolled'] as bool? ?? false;
        _deviceRegistered = status['deviceRegistered'] as bool? ?? false;
        _enrollmentChecked = true;
      });
    } catch (_) {
      setState(() => _enrollmentChecked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            onPressed: () => _showAttendanceHistoryModal(context),
            tooltip: 'My Attendance',
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.go('/student/enrollment'),
            tooltip: 'Enrollment',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authStateProvider.notifier).logout();
              context.go('/login');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Welcome card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.school, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome, ${authState.fullName ?? 'Student'}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            authState.email ?? '',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Phase content
            Expanded(child: _buildPhaseContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseContent() {
    switch (_phase) {
      case _ScanPhase.idle:
        return _buildIdleView();
      case _ScanPhase.scanning:
        return _buildQrScannerView();
      case _ScanPhase.capturing:
        return _buildCapturingView();
      case _ScanPhase.verifying:
        return _buildVerifyingView();
      case _ScanPhase.done:
        return _buildResultCard();
    }
  }

  // ─────────────────────────────────────────────
  // PHASE 1: Idle — Big "Scan QR" button
  // ─────────────────────────────────────────────
  Widget _buildIdleView() {
    final needsEnrollment = _enrollmentChecked && (!_faceEnrolled || !_deviceRegistered);

    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Enrollment warning banner
            if (needsEnrollment)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.warningColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: AppTheme.warningColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Enrollment incomplete',
                            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.warningColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (!_faceEnrolled) 'Face not enrolled',
                              if (!_deviceRegistered) 'Device not registered',
                            ].join(' · '),
                            style: const TextStyle(fontSize: 12, color: AppTheme.warningColor),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go('/student/enrollment'),
                      child: const Text('Fix'),
                    ),
                  ],
                ),
              ),

            // Error banner
            if (_errorMessage != null)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.errorColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.errorColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.errorColor),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_errorMessage!, style: const TextStyle(color: AppTheme.errorColor))),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: AppTheme.errorColor),
                      onPressed: () => setState(() => _errorMessage = null),
                    ),
                  ],
                ),
              ),
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryColor, Color(0xFF8B7CF7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(40),
                onTap: _startScanFlow,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner, size: 56, color: Colors.white),
                    SizedBox(height: 8),
                    Text(
                      'Scan QR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Tap to scan the QR code\ndisplayed by your instructor',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),

          // Step indicators
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepChip(Icons.qr_code, 'QR'),
              const Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
              _stepChip(Icons.face, 'Face'),
              const Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
              _stepChip(Icons.location_on, 'GPS'),
              const Icon(Icons.arrow_forward, size: 14, color: Colors.grey),
              _stepChip(Icons.shield, 'Verify'),
            ],
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _showAttendanceHistoryModal(context),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('My Attendance History'),
          ),
        ],
      ),
    ),
  );
}


  Widget _stepChip(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppTheme.primaryColor),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PHASE 2: QR Camera Scanner
  // ─────────────────────────────────────────────
  Widget _buildQrScannerView() {
    // Web doesn't support mobile_scanner camera; fall back to text input
    if (kIsWeb) {
      return _buildWebQrInput();
    }

    final controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    return Column(
      children: [
        const Text(
          'Point camera at the QR code',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: MobileScanner(
              controller: controller,
              onDetect: (capture) {
                final barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final value = barcodes.first.rawValue;
                  if (value != null && value.isNotEmpty) {
                    controller.dispose();
                    _onQrScanned(value);
                  }
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _phase = _ScanPhase.idle;
            _errorMessage = null;
          }),
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildWebQrInput() {
    final controller = TextEditingController();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.qr_code, size: 64, color: AppTheme.primaryColor),
        const SizedBox(height: 16),
        const Text('Paste QR token (web mode)', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'QR Token',
            prefixIcon: Icon(Icons.vpn_key_outlined),
          ),
          maxLines: 3,
          minLines: 1,
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () {
            final val = controller.text.trim();
            if (val.isNotEmpty) _onQrScanned(val);
          },
          child: const Text('Continue'),
        ),
        TextButton(
          onPressed: () => setState(() => _phase = _ScanPhase.idle),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // PHASE 3: Capturing (selfie + GPS)
  // ─────────────────────────────────────────────
  Widget _buildCapturingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Capturing selfie & location…', style: TextStyle(fontSize: 16)),
          SizedBox(height: 8),
          Text(
            'Please look at the camera and allow location access',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PHASE 4: Verifying with backend
  // ─────────────────────────────────────────────
  Widget _buildVerifyingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 24),
          Text('Verifying attendance…', style: TextStyle(fontSize: 16)),
          SizedBox(height: 8),
          Text(
            'Running QR · Device · Geofence · Face checks',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PHASE 5: Result
  // ─────────────────────────────────────────────
  Widget _buildResultCard() {
    if (_verificationResult == null) {
      return const Center(child: Text('No result'));
    }

    final status = _verificationResult!['finalStatus'] as String? ?? 'REJECTED';
    final layers = (_verificationResult!['layerResults'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    final statusColor = switch (status) {
      'PRESENT' => AppTheme.successColor,
      'FLAGGED' => AppTheme.warningColor,
      _ => AppTheme.errorColor,
    };

    final statusIcon = switch (status) {
      'PRESENT' => Icons.check_circle,
      'FLAGGED' => Icons.warning_amber,
      _ => Icons.cancel,
    };

    final statusMessage = switch (status) {
      'PRESENT' => 'Attendance marked!',
      'FLAGGED' => 'Flagged for review',
      _ => 'Attendance rejected',
    };

    return Column(
      children: [
        // Status header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(statusIcon, size: 56, color: statusColor),
              const SizedBox(height: 12),
              Text(
                status,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: statusColor),
              ),
              const SizedBox(height: 4),
              Text(statusMessage, style: TextStyle(color: statusColor.withValues(alpha: 0.8))),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Layer breakdown
        if (layers.isNotEmpty) ...[
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Verification Layers', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: layers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final layer = layers[index];
                final passed = layer['passed'] as bool? ?? false;
                final score = layer['score'] as num?;
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      passed ? Icons.check_circle : Icons.cancel,
                      color: passed ? AppTheme.successColor : AppTheme.errorColor,
                      size: 20,
                    ),
                    title: Text(
                      (layer['layer'] as String? ?? '').replaceAll('_', ' '),
                      style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                    ),
                    subtitle: Text(layer['detail'] as String? ?? '', style: const TextStyle(fontSize: 12)),
                    trailing: score != null
                        ? Text(score.toStringAsFixed(2), style: const TextStyle(fontSize: 12))
                        : null,
                  ),
                );
              },
            ),
          ),
        ] else
          const Expanded(child: SizedBox()),

        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() {
              _phase = _ScanPhase.idle;
              _verificationResult = null;
              _errorMessage = null;
              _qrToken = null;
              _faceFrameBytes = null;
              _position = null;
            }),
            icon: const Icon(Icons.refresh),
            label: const Text('Scan Again'),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // FLOW LOGIC
  // ─────────────────────────────────────────────

  void _startScanFlow() {
    setState(() {
      _phase = _ScanPhase.scanning;
      _errorMessage = null;
    });
  }

  void _onQrScanned(String token) {
    _qrToken = token;
    setState(() => _phase = _ScanPhase.capturing);
    _captureSelfieAndLocation();
  }

  Future<void> _captureSelfieAndLocation() async {
    try {
      // Step A: Capture selfie via image_picker (front camera)
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
        maxWidth: 640,
        maxHeight: 640,
      );

      if (photo == null) {
        // User cancelled camera
        setState(() {
          _phase = _ScanPhase.idle;
          _errorMessage = 'Selfie capture cancelled. Please try again.';
        });
        return;
      }

      _faceFrameBytes = await photo.readAsBytes();

      // Step B: Get GPS location
      _position = await _getCurrentLocation();

      // Step C: Verify with backend
      setState(() => _phase = _ScanPhase.verifying);
      await _submitVerification();
    } catch (e) {
      setState(() {
        _phase = _ScanPhase.idle;
        _errorMessage = 'Error during capture: $e';
      });
    }
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied. Please enable in Settings.');
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  Future<void> _submitVerification() async {
    try {
      final fingerprint = await DeviceFingerprintService.getFingerprint();

      final result = await ref.read(apiClientProvider).verifyScan(
        qrToken: _qrToken!,
        deviceFingerprint: fingerprint,
        latitude: _position?.latitude ?? 0.0,
        longitude: _position?.longitude ?? 0.0,
        faceFrameBytes: _faceFrameBytes!,
      );

      setState(() {
        _verificationResult = result;
        _phase = _ScanPhase.done;
      });
    } catch (e) {
      String message = _parseDioError(e);
      setState(() {
        _phase = _ScanPhase.idle;
        _errorMessage = message;
      });
    }
  }

  /// Extracts a human-readable message from a DioException response body.
  String _parseDioError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      // Try to get 'message' or 'error' field from backend JSON response
      if (data is Map) {
        final msg = data['message'] as String? ??
            data['error'] as String? ??
            data['detail'] as String?;
        if (msg != null && msg.isNotEmpty) {
          return _friendlyBackendMessage(msg);
        }
      }
      // Fall back to HTTP status
      final status = e.response?.statusCode;
      if (status == 400) return 'Request rejected (400). Complete enrollment first, then try again.';
      if (status == 401) return 'Session expired. Please log in again.';
      if (status == 403) return 'Access denied. You are not enrolled in this course.';
      if (status == 404) return 'Session or resource not found.';
      if (status == 409) return 'Already marked present in this session.';
    }
    return _friendlyBackendMessage(e.toString());
  }

  String _friendlyBackendMessage(String raw) {
    if (raw.contains('NOT_ENROLLED') || raw.toLowerCase().contains('not enrolled')) {
      return 'You are not enrolled in this course.';
    }
    if (raw.contains('DEVICE_NOT_REGISTERED') || raw.contains('device') && raw.contains('register')) {
      return 'Device not registered. Go to Enrollment and register this device first.';
    }
    if (raw.contains('SESSION_CLOSED') || raw.contains('closed')) {
      return 'This session is closed. Ask your instructor to start a new one.';
    }
    if (raw.contains('QR') || raw.contains('token') || raw.contains('expired')) {
      return 'QR code expired or invalid. Wait for the next rotation and try again.';
    }
    if (raw.contains('GEOFENCE') || raw.contains('geofence') || raw.contains('distance')) {
      return 'You are outside the classroom geofence. Move closer and try again.';
    }
    if (raw.contains('FACE') || raw.contains('face') || raw.contains('similarity')) {
      return 'Face verification failed. Ensure good lighting and look directly at the camera.';
    }
    if (raw.contains('already') || raw.contains('ALREADY_PRESENT')) {
      return 'Attendance already recorded for this session.';
    }
    // Return raw if short enough, else generic
    if (raw.length < 120) return raw;
    return 'Verification failed. Please try again.';
  }

  void _showAttendanceHistoryModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _StudentAttendanceHistoryModal(),
    );
  }
}

class _StudentAttendanceHistoryModal extends ConsumerStatefulWidget {
  const _StudentAttendanceHistoryModal();

  @override
  ConsumerState<_StudentAttendanceHistoryModal> createState() =>
      _StudentAttendanceHistoryModalState();
}

class _StudentAttendanceHistoryModalState
    extends ConsumerState<_StudentAttendanceHistoryModal> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];
  String? _error;
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final records = await ref.read(apiClientProvider).getMyAttendanceHistory();
      if (mounted) {
        setState(() {
          _history = records;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load attendance records: $e';
          _isLoading = false;
        });
      }
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'PRESENT':
        return AppTheme.successColor;
      case 'FLAGGED':
        return AppTheme.warningColor;
      case 'REJECTED':
        return AppTheme.errorColor;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'PRESENT':
        return Icons.check_circle_outline;
      case 'FLAGGED':
        return Icons.warning_amber_outlined;
      case 'REJECTED':
        return Icons.cancel_outlined;
      default:
        return Icons.help_outline;
    }
  }

  List<Map<String, dynamic>> get _filteredHistory {
    if (_filter == 'ALL') return _history;
    return _history.where((s) => s['finalStatus'] == _filter).toList();
  }

  Widget _statBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final presentCount =
        _history.where((s) => s['finalStatus'] == 'PRESENT').length;
    final flaggedCount =
        _history.where((s) => s['finalStatus'] == 'FLAGGED').length;
    final rejectedCount =
        _history.where((s) => s['finalStatus'] == 'REJECTED').length;
    final attendanceRate = _history.isNotEmpty
        ? ((presentCount / _history.length) * 100).toStringAsFixed(0)
        : '0';

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.history_edu, color: AppTheme.primaryColor),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('My Attendance History',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Detailed multi-signal verification records',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                    onPressed: _loadHistory,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Stats summary row
            if (_history.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statBadge(
                        'Total Scans', '${_history.length}', AppTheme.primaryColor),
                    _statBadge('Present', '$presentCount', AppTheme.successColor),
                    _statBadge('Flagged', '$flaggedCount', AppTheme.warningColor),
                    _statBadge('Rejected', '$rejectedCount', AppTheme.errorColor),
                    _statBadge('Rate', '$attendanceRate%', const Color(0xFF6C5CE7)),
                  ],
                ),
              ),

            // Filter chips
            if (_history.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        ['ALL', 'PRESENT', 'FLAGGED', 'REJECTED'].map((f) {
                      final isSelected = _filter == f;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(f,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected ? Colors.white : null)),
                          selected: isSelected,
                          selectedColor: AppTheme.primaryColor,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

            const Divider(height: 1),

            // Body
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline,
                                    size: 48, color: AppTheme.errorColor),
                                const SizedBox(height: 12),
                                Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: AppTheme.errorColor)),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                    onPressed: _loadHistory,
                                    child: const Text('Retry')),
                              ],
                            ),
                          ),
                        )
                      : _filteredHistory.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.history_toggle_off,
                                      size: 56, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  const Text('No attendance records found',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 16)),
                                  const SizedBox(height: 6),
                                  Text(
                                    _filter == 'ALL'
                                        ? 'Scan a classroom QR code to record your first attendance!'
                                        : 'No records matching status "$_filter".',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              itemCount: _filteredHistory.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final item = _filteredHistory[index];
                                final status = item['finalStatus'] as String? ??
                                    'UNKNOWN';
                                final courseCode =
                                    item['courseCode'] ?? 'Course';
                                final courseName = item['courseName'] ?? '';
                                final submittedAt = item['submittedAt'] != null
                                    ? DateFormat('MMM dd, yyyy • h:mm a')
                                        .format(DateTime.parse(
                                                item['submittedAt'])
                                            .toLocal())
                                    : '';
                                final layers = List<Map<String, dynamic>>.from(
                                    item['layerResults'] ?? []);

                                return Card(
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: ExpansionTile(
                                    tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 4),
                                    leading: CircleAvatar(
                                      backgroundColor: _statusColor(status)
                                          .withValues(alpha: 0.15),
                                      child: Icon(_statusIcon(status),
                                          color: _statusColor(status),
                                          size: 22),
                                    ),
                                    title: Row(
                                      children: [
                                        Text(courseCode,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15)),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _statusColor(status)
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            status,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: _statusColor(status),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (courseName.isNotEmpty)
                                            Text(courseName,
                                                style: TextStyle(
                                                    color: Colors.grey.shade700,
                                                    fontSize: 13)),
                                          Text(submittedAt,
                                              style: TextStyle(
                                                  color: Colors.grey.shade500,
                                                  fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    children: [
                                      if (layers.isEmpty)
                                        const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Text(
                                              'No layer telemetry recorded for this scan.',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey)),
                                        )
                                      else
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              16, 0, 16, 12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Divider(height: 1),
                                              const SizedBox(height: 8),
                                              const Text(
                                                  'Multi-Factor Layer Telemetry',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              const SizedBox(height: 6),
                                              ...layers.map((l) {
                                                final passed = l['passed']
                                                        as bool? ??
                                                    false;
                                                final layerName =
                                                    (l['layer'] as String? ??
                                                            '')
                                                        .replaceAll('_', ' ');
                                                final detail =
                                                    l['detail'] as String? ??
                                                        '';
                                                final score =
                                                    l['score'] as num?;
                                                return Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 3),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Icon(
                                                        passed
                                                            ? Icons.check_circle
                                                            : Icons.cancel,
                                                        color: passed
                                                            ? AppTheme
                                                                .successColor
                                                            : AppTheme
                                                                .errorColor,
                                                        size: 16,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(layerName,
                                                                style: const TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    fontSize:
                                                                        12)),
                                                            if (detail
                                                                .isNotEmpty)
                                                              Text(detail,
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      color: Colors
                                                                          .grey
                                                                          .shade600)),
                                                          ],
                                                        ),
                                                      ),
                                                      if (score != null)
                                                        Text(
                                                            score
                                                                .toStringAsFixed(
                                                                    2),
                                                            style: const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold)),
                                                    ],
                                                  ),
                                                );
                                              }),
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
      ),
    );
  }
}

