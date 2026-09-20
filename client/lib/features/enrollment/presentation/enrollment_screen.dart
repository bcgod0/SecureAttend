import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/api/api_client.dart';
import '../../../core/services/device_fingerprint_service.dart';
import '../../../core/theme/app_theme.dart';

class EnrollmentScreen extends ConsumerStatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  ConsumerState<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends ConsumerState<EnrollmentScreen> {
  bool _faceEnrolled = false;
  bool _deviceRegistered = false;
  bool _isLoading = true;
  bool _faceUploading = false;
  bool _deviceRegistering = false;
  Uint8List? _capturedFacePreview;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await ref.read(apiClientProvider).getEnrollmentStatus();
      setState(() {
        _faceEnrolled = status['faceEnrolled'] ?? false;
        _deviceRegistered = status['deviceRegistered'] ?? false;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enrollment'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/student/scan'),
          tooltip: 'Back',
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Complete Your Setup',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Both steps must be completed before you can scan attendance.'),
                  const SizedBox(height: 32),

                  // ── Step 1: Face Enrollment ──
                  _EnrollmentStep(
                    title: 'Face Enrollment',
                    subtitle: _faceEnrolled
                        ? 'Your face is registered ✓'
                        : 'Capture your face for identity verification',
                    icon: Icons.face,
                    completed: _faceEnrolled,
                    isLoading: _faceUploading,
                    preview: _capturedFacePreview,
                    onTap: _faceEnrolled ? null : () => _startFaceEnrollment(),
                  ),
                  const SizedBox(height: 16),

                  // ── Step 2: Device Registration ──
                  _EnrollmentStep(
                    title: 'Device Registration',
                    subtitle: _deviceRegistered
                        ? 'This device is bound to your account ✓'
                        : 'Register this device for attendance',
                    icon: Icons.phone_android,
                    completed: _deviceRegistered,
                    isLoading: _deviceRegistering,
                    onTap: _deviceRegistered ? null : _registerDevice,
                  ),
                  const Spacer(),

                  if (_faceEnrolled && _deviceRegistered)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.successColor.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: AppTheme.successColor),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Enrollment complete! You can now scan attendance.',
                              style: TextStyle(color: AppTheme.successColor, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _startFaceEnrollment() async {
    // Confirm dialog with instructions
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Face Enrollment'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.face_retouching_natural, size: 48, color: AppTheme.primaryColor),
            SizedBox(height: 16),
            Text(
              'Please:\n'
              '• Ensure good, even lighting\n'
              '• Look directly at the front camera\n'
              '• Remove glasses if possible\n'
              '• Keep a neutral expression',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open Camera')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Open front camera via image_picker
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 90,
      maxWidth: 800,
      maxHeight: 800,
    );

    if (photo == null || !mounted) return;

    setState(() => _faceUploading = true);

    try {
      final bytes = await photo.readAsBytes();
      _capturedFacePreview = bytes;

      await ref.read(apiClientProvider).enrollFace(
        bytes,
        'face_enrollment.jpg',
      );

      if (mounted) {
        setState(() {
          _faceEnrolled = true;
          _faceUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Face enrolled successfully!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _faceUploading = false;
          _capturedFacePreview = null;
        });
        String msg = e.toString();
        if (msg.contains('no face') || msg.contains('face_not_detected')) {
          msg = 'No face detected. Please ensure your face is clearly visible.';
        } else if (msg.contains('multiple')) {
          msg = 'Multiple faces detected. Please ensure only your face is in frame.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  Future<void> _registerDevice() async {
    setState(() => _deviceRegistering = true);
    try {
      final fingerprint = await DeviceFingerprintService.getFingerprint();
      final deviceInfo = await DeviceFingerprintService.getDeviceInfo();

      await ref.read(apiClientProvider).registerDevice(
        fingerprintHash: fingerprint,
        deviceInfo: deviceInfo,
      );

      if (mounted) {
        setState(() {
          _deviceRegistered = true;
          _deviceRegistering = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device registered successfully!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deviceRegistering = false);
        String msg = e.toString();
        if (msg.contains('already registered') || msg.contains('CONFLICT')) {
          msg = 'A device is already registered for your account. Contact admin to replace it.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────
// _EnrollmentStep — reusable card widget for each step
// ─────────────────────────────────────────────────────────────

class _EnrollmentStep extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool completed;
  final bool isLoading;
  final Uint8List? preview;
  final VoidCallback? onTap;

  const _EnrollmentStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.completed,
    this.isLoading = false,
    this.preview,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(20),
        leading: _buildLeading(),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: _buildTrailing(),
        onTap: isLoading ? null : onTap,
      ),
    );
  }

  Widget _buildLeading() {
    if (isLoading) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (preview != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(preview!, width: 44, height: 44, fit: BoxFit.cover),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: completed
            ? AppTheme.successColor.withValues(alpha: 0.1)
            : AppTheme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        completed ? Icons.check : icon,
        color: completed ? AppTheme.successColor : AppTheme.primaryColor,
      ),
    );
  }

  Widget? _buildTrailing() {
    if (isLoading) return null;
    if (completed) return const Icon(Icons.check_circle, color: AppTheme.successColor);
    return const Icon(Icons.arrow_forward_ios, size: 16);
  }
}
