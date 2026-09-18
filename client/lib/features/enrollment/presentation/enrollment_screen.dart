import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
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
      appBar: AppBar(title: const Text('Enrollment')),
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

                  _EnrollmentStep(
                    title: 'Face Enrollment',
                    subtitle: 'Capture your face for identity verification',
                    icon: Icons.face,
                    completed: _faceEnrolled,
                    onTap: _faceEnrolled ? null : () => _showFaceCapture(context),
                  ),
                  const SizedBox(height: 16),

                  _EnrollmentStep(
                    title: 'Device Registration',
                    subtitle: 'Register this device for attendance',
                    icon: Icons.phone_android,
                    completed: _deviceRegistered,
                    onTap: _deviceRegistered ? null : () => _registerDevice(),
                  ),
                  const Spacer(),

                  if (_faceEnrolled && _deviceRegistered)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
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

  void _showFaceCapture(BuildContext context) {
    // In a full implementation, this would open the camera for face capture
    // and send the image to the enrollment API
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Face Enrollment'),
        content: const Text(
          'This will open the camera to capture your face. '
          'Ensure good lighting and look directly at the camera.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: Implement camera capture and API call
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Camera integration pending — use mobile app')),
              );
            },
            child: const Text('Open Camera'),
          ),
        ],
      ),
    );
  }

  Future<void> _registerDevice() async {
    // Generate device fingerprint
    // In production: platform-specific device ID + model + hash
    final fingerprint = 'web-${DateTime.now().millisecondsSinceEpoch}';

    try {
      await ref.read(apiClientProvider).registerDevice(
        fingerprintHash: fingerprint,
        deviceInfo: {'platform': 'web', 'model': 'browser'},
      );
      setState(() => _deviceRegistered = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device registered successfully!'), backgroundColor: AppTheme.successColor),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Device registration failed: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }
}

class _EnrollmentStep extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool completed;
  final VoidCallback? onTap;

  const _EnrollmentStep({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.completed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(20),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: completed
                ? AppTheme.successColor.withOpacity(0.1)
                : AppTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            completed ? Icons.check : icon,
            color: completed ? AppTheme.successColor : AppTheme.primaryColor,
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: completed
            ? const Icon(Icons.check_circle, color: AppTheme.successColor)
            : const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
