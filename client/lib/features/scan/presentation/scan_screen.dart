import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  String? _scanResult;
  bool _isScanning = false;
  Map<String, dynamic>? _verificationResult;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
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
            const SizedBox(height: 32),

            // Scan button
            if (_verificationResult == null) ...[
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                              color: AppTheme.primaryColor.withOpacity(0.3),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(40),
                            onTap: _isScanning ? null : _startScan,
                            child: _isScanning
                                ? const Center(
                                    child: CircularProgressIndicator(color: Colors.white),
                                  )
                                : const Column(
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
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Verification result
              _buildResultCard(),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);

    // In production, this opens mobile_scanner for QR scanning,
    // then camera for face capture, then geolocator for GPS,
    // then submits all to the verify endpoint.

    // Placeholder: simulate scan for now
    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      _isScanning = false;
      _verificationResult = {
        'finalStatus': 'PRESENT',
        'layerResults': [
          {'layer': 'QR_VALIDATION', 'passed': true, 'detail': 'Token valid'},
          {'layer': 'DEVICE_MATCH', 'passed': true, 'detail': 'Device matched'},
          {'layer': 'GEOFENCE', 'passed': true, 'score': 45.2, 'detail': 'Within 45m (limit: 100m)'},
          {'layer': 'FACE_VERIFICATION', 'passed': true, 'score': 0.82, 'detail': 'Match confirmed'},
          {'layer': 'ANOMALY', 'passed': true, 'score': 0.12, 'detail': 'Normal pattern'},
        ],
      };
    });
  }

  Widget _buildResultCard() {
    final status = _verificationResult!['finalStatus'] as String;
    final layers = _verificationResult!['layerResults'] as List;

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

    return Expanded(
      child: Column(
        children: [
          // Status header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Icon(statusIcon, size: 56, color: statusColor),
                const SizedBox(height: 12),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Layer results
          Expanded(
            child: ListView.builder(
              itemCount: layers.length,
              itemBuilder: (context, index) {
                final layer = layers[index] as Map<String, dynamic>;
                final passed = layer['passed'] as bool;
                return Card(
                  child: ListTile(
                    leading: Icon(
                      passed ? Icons.check_circle : Icons.cancel,
                      color: passed ? AppTheme.successColor : AppTheme.errorColor,
                    ),
                    title: Text(layer['layer'] as String),
                    subtitle: Text(layer['detail'] as String),
                    trailing: layer['score'] != null
                        ? Text('${(layer['score'] as num).toStringAsFixed(2)}')
                        : null,
                  ),
                );
              },
            ),
          ),

          // Scan again button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => setState(() => _verificationResult = null),
              child: const Text('Scan Again'),
            ),
          ),
        ],
      ),
    );
  }
}
