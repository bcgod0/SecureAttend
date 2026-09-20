import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

class CreateSessionScreen extends ConsumerStatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  ConsumerState<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends ConsumerState<CreateSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedCourseId;
  final _latController = TextEditingController(text: '28.6139');
  final _lonController = TextEditingController(text: '77.2090');
  final _radiusController = TextEditingController(text: '100');
  final _rotationController = TextEditingController(text: '10');
  bool _isLoading = false;
  bool _isLoadingCourses = false;
  String? _courseError;
  List<Map<String, dynamic>> _courses = [];

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() {
      _isLoadingCourses = true;
      _courseError = null;
    });
    try {
      final data = await ref.read(apiClientProvider).listCourses();
      final list = List<Map<String, dynamic>>.from(data['content'] ?? []);
      setState(() {
        _courses = list;
        if (list.length == 1) {
          _selectedCourseId = list.first['id'] as String?;
        }
      });
    } catch (e) {
      setState(() {
        _courseError = e.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load courses: $e'),
            backgroundColor: AppTheme.errorColor,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadCourses,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingCourses = false);
      }
    }
  }

  Future<void> _useMyLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied. Enable in device settings.')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _latController.text = pos.latitude.toStringAsFixed(6);
      _lonController.text = pos.longitude.toStringAsFixed(6);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location captured!'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _radiusController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  Future<void> _createSession() async {
    if (!_formKey.currentState!.validate() || _selectedCourseId == null) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(apiClientProvider).createSession(
        courseId: _selectedCourseId!,
        geofenceLat: double.parse(_latController.text),
        geofenceLon: double.parse(_lonController.text),
        geofenceRadiusMeters: int.parse(_radiusController.text),
        qrRotationSeconds: int.parse(_rotationController.text),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session created!'), backgroundColor: AppTheme.successColor),
        );
        context.go('/faculty/sessions');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.errorColor),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Session')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Session Details', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 24),

                // Course dropdown
                DropdownButtonFormField<String>(
                  value: _selectedCourseId,
                  decoration: InputDecoration(
                    labelText: 'Course',
                    hintText: _isLoadingCourses
                        ? 'Loading courses...'
                        : (_courses.isEmpty ? 'No courses available' : 'Select a course'),
                    prefixIcon: const Icon(Icons.book_outlined),
                    suffixIcon: _isLoadingCourses
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Refresh courses',
                            onPressed: _loadCourses,
                          ),
                    helperText: _courses.isEmpty && !_isLoadingCourses
                        ? (_courseError != null ? 'Error loading courses' : 'No courses found. Create one in Admin dashboard.')
                        : null,
                    helperMaxLines: 2,
                  ),
                  items: _courses.map((c) => DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text('${c['code']} — ${c['name']}'),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedCourseId = v),
                  validator: (v) => v == null ? 'Select a course' : null,
                ),
                const SizedBox(height: 16),

                Text('Geofence', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _latController,
                        decoration: const InputDecoration(labelText: 'Latitude'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        validator: (v) => v?.isEmpty == true ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _lonController,
                        decoration: const InputDecoration(labelText: 'Longitude'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        validator: (v) => v?.isEmpty == true ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Tooltip(
                      message: 'Use my location',
                      child: IconButton.filled(
                        icon: const Icon(Icons.my_location),
                        onPressed: _useMyLocation,
                        style: IconButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _radiusController,
                  decoration: const InputDecoration(
                    labelText: 'Radius (meters)',
                    prefixIcon: Icon(Icons.radar),
                    suffixText: 'm',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 10 || n > 1000) return '10–1000m';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _rotationController,
                  decoration: const InputDecoration(
                    labelText: 'QR Rotation Interval',
                    prefixIcon: Icon(Icons.timer),
                    suffixText: 'seconds',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 5 || n > 60) return '5–60s';
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createSession,
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Create Session'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
