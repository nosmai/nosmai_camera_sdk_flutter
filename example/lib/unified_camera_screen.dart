// ignore_for_file: avoid_print, use_build_context_synchronously
import 'dart:convert' show json;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nosmai_camera_sdk/nosmai_camera_sdk.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

/// Unified camera screen that demonstrates comprehensive Nosmai SDK functionality
///
/// This screen showcases:
/// - Live camera preview with filters
/// - Photo capture and video recording
/// - Filter categories (Effects, Beauty, Color, HSB, Cloud)
/// - Real-time filter application
/// - Cloud filter downloading
/// - Camera switching
/// - Responsive UI design
///
/// The implementation follows Flutter best practices with proper error handling,
/// performance optimizations, and a clean, maintainable code structure.
class UnifiedCameraScreen extends StatefulWidget {
  const UnifiedCameraScreen({super.key});

  @override
  State<UnifiedCameraScreen> createState() => _UnifiedCameraScreenState();
}

class _UnifiedCameraScreenState extends State<UnifiedCameraScreen>
    with
        TickerProviderStateMixin,
        NosmaiCameraLifecycleMixin,
        WidgetsBindingObserver {
  // SDK instance
  final NosmaiFlutter _nosmai = NosmaiFlutter.instance;

  // Camera state
  bool _isRecording = false;
  bool _isFrontCamera = true;

  // Filter state
  bool _isCloudFiltersLoading = false;
  int _selectedCategoryIndex = 0;
  FilterItem? _activeFilter;

  // Filter categories with pre-defined filters
  late final List<FilterCategory> _categories;

  // UI Controllers
  late AnimationController _recordButtonController;
  late AnimationController _filterPanelController;
  bool _isFilterPanelVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCategories();
    _setupAnimationControllers();
    _configureCameraForFirstUse();
    // _loadFiltersInBackground();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureCameraReady();
  }

  /// Ensure camera is ready when returning to screen
  Future<void> _ensureCameraReady() async {
    try {
      // Small delay to ensure previous cleanup completed
      await Future.delayed(const Duration(milliseconds: 100));
      // Reinitialize preview for proper navigation recovery
      await _nosmai.reinitializePreview();
      // Start processing to ensure camera is ready
      if (!_nosmai.isProcessing) {
        await _nosmai.startProcessing();
      }
    } catch (e) {
      debugPrint('Error ensuring camera ready: $e');
    }
  }

  /// Configure camera when user first opens camera screen
  Future<void> _configureCameraForFirstUse() async {
    try {
      // Configure camera for front-facing position (typical for beauty filters)
      await _nosmai.configureCamera(position: NosmaiCameraPosition.front);
      // Start processing for immediate camera availability
      await _nosmai.startProcessing();
    } catch (e) {
      debugPrint('Error configuring camera: $e');
    }
  }

  /// Initialize filter categories with default values
  void _initializeCategories() {
    _categories = [
      FilterCategory(name: 'Effects', icon: Icons.auto_awesome, filters: []),
      FilterCategory(
        name: 'Beauty',
        icon: Icons.face_retouching_natural,
        filters: _createBeautyFilters(),
      ),
      FilterCategory(
        name: 'Color',
        icon: Icons.palette,
        filters: _createColorFilters(),
      ),
      FilterCategory(
        name: 'HSB',
        icon: Icons.tune,
        filters: _createHSBFilters(),
      ),
      FilterCategory(name: 'Cloud', icon: Icons.cloud_queue, filters: []),
    ];
  }

  /// Create beauty filter items
  List<FilterItem> _createBeautyFilters() {
    return [
      FilterItem(
        id: 'skin_smoothing',
        name: 'Smooth',
        type: FilterType.slider,
        value: 0.0,
        min: 0.0,
        max: 10.0,
      ),
      FilterItem(
        id: 'skin_whitening',
        name: 'Brighten',
        type: FilterType.slider,
        value: 0.0,
        min: 0.0,
        max: 10.0,
      ),
      FilterItem(
        id: 'face_slimming',
        name: 'Slim Face',
        type: FilterType.slider,
        value: 0.0,
        min: 0.0,
        max: 10.0,
      ),
      FilterItem(
        id: 'eye_enlargement',
        name: 'Big Eyes',
        type: FilterType.slider,
        value: 0.0,
        min: 0.0,
        max: 10.0,
      ),
      FilterItem(
        id: 'nose_size',
        name: 'Nose Size',
        type: FilterType.slider,
        value: 50.0,
        min: 0.0,
        max: 100.0,
      ),
    ];
  }

  /// Create color filter items
  List<FilterItem> _createColorFilters() {
    return [
      FilterItem(
        id: 'brightness',
        name: 'Brightness',
        type: FilterType.slider,
        value: 0.0,
        min: -1.0,
        max: 1.0,
      ),
      FilterItem(
        id: 'contrast',
        name: 'Contrast',
        type: FilterType.slider,
        value: 1.0,
        min: 0.0,
        max: 2.0,
      ),
      FilterItem(
        id: 'temperature',
        name: 'Warmth',
        type: FilterType.slider,
        value: 5000.0,
        min: 2000.0,
        max: 8000.0,
      ),
    ];
  }

  /// Create HSB filter items
  List<FilterItem> _createHSBFilters() {
    return [
      FilterItem(
        id: 'hsb_hue',
        name: 'Hue',
        type: FilterType.slider,
        value: 0.0,
        min: -360.0,
        max: 360.0,
      ),
      FilterItem(
        id: 'hsb_saturation',
        name: 'Saturation',
        type: FilterType.slider,
        value: 1.0,
        min: 0.0,
        max: 2.0,
      ),
      FilterItem(
        id: 'hsb_brightness',
        name: 'Brightness',
        type: FilterType.slider,
        value: 1.0,
        min: 0.0,
        max: 2.0,
      ),
    ];
  }

  /// Setup animation controllers
  void _setupAnimationControllers() {
    _recordButtonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _filterPanelController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  Future<void> _loadEffectFilters() async {
    try {
      final filters = await _nosmai.getFilters();

      final effectFilters = <FilterItem>[];

      for (final filter in filters) {
        if (filter.isLocalFilter) {
          effectFilters.add(
            FilterItem(
              id: filter.path,
              name: filter.displayName,
              type: FilterType.effect,
              path: filter.path,
            ),
          );
        }
      }

      setState(() {
        _categories[0].filters = effectFilters;
      });
    } catch (e) {
      debugPrint('Error loading effect filters: $e');
    }
  }

  /// Load cloud filters from the SDK
  ///
  /// This method fetches available cloud filters and logs the response for debugging.
  /// Empty results are normal and don't indicate an error.
  Future<void> _loadCloudFilters() async {
    if (_isCloudFiltersLoading) return;

    setState(() {
      _isCloudFiltersLoading = true;
    });

    try {
      final filters = await _nosmai.getCloudFilters();

      final cloudEffectFilters = _createCloudFilterItems(filters);
      _updateCloudFiltersInUI(cloudEffectFilters);
    } catch (e) {
      debugPrint('⚠️ Cloud filters error: $e');
      _handleCloudFiltersError(e);
    } finally {
      if (mounted) {
        setState(() {
          _isCloudFiltersLoading = false;
        });
      }
    }
  }

  /// Create FilterItem objects from cloud filters
  List<FilterItem> _createCloudFilterItems(List<dynamic> filters) {
    return filters
        .map(
          (filter) => FilterItem(
            id: filter.id,
            name: filter.displayName,
            type: FilterType.effect,
            path: filter.path, // Path is null if not downloaded
            isDownloaded: filter.isDownloaded, // Check if already downloaded
          ),
        )
        .toList();
  }

  /// Update cloud filters in the UI
  void _updateCloudFiltersInUI(List<FilterItem> cloudFilters) {
    setState(() {
      final cloudCategoryIndex = _categories.indexWhere(
        (cat) => cat.name == 'Cloud',
      );
      if (cloudCategoryIndex != -1) {
        _categories[cloudCategoryIndex].filters = cloudFilters;
      }
    });
  }

  /// Handle cloud filters loading errors
  void _handleCloudFiltersError(dynamic error) {
    // Only show user-facing error for actual exceptions, not empty results
    if (mounted && error.toString().contains('PlatformException')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud filters temporarily unavailable'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Load filters in background without blocking the UI
  ///
  /// This method loads both effect and cloud filters asynchronously to avoid
  /// blocking the camera interface during startup.
  Future<void> _loadFiltersInBackground() async {
    // Load effect filters in background
    Future.microtask(() async {
      await _loadEffectFilters();
    });

    // Load cloud filters asynchronously
    Future.microtask(() async {
      await _loadCloudFilters();
    });
  }

  void _toggleFilterPanel() {
    setState(() {
      _isFilterPanelVisible = !_isFilterPanelVisible;
    });
    if (_isFilterPanelVisible) {
      _filterPanelController.forward();
    } else {
      _filterPanelController.reverse();
    }
  }

  Future<void> _applyFilter(FilterItem filter) async {
    setState(() {
      _activeFilter = filter;
    });

    try {
      switch (filter.id) {
        // Beauty filters
        case 'skin_smoothing':
          await _nosmai.applySkinSmoothing(filter.value);
          break;
        case 'skin_whitening':
          await _nosmai.applySkinWhitening(filter.value);
          break;
        case 'face_slimming':
          await _nosmai.applyFaceSlimming(filter.value);
          break;
        case 'eye_enlargement':
          await _nosmai.applyEyeEnlargement(filter.value);
          break;
        case 'nose_size':
          await _nosmai.applyNoseSize(filter.value);
          break;

        // Color filters
        case 'brightness':
          await _nosmai.applyBrightnessFilter(filter.value);
          break;
        case 'contrast':
          await _nosmai.applyContrastFilter(filter.value);
          break;
        case 'temperature':
          await _nosmai.applyWhiteBalance(temperature: filter.value, tint: 0.0);
          break;

        // HSB filters
        case 'hsb_hue':
          await _applyHSBFilters();
          break;
        case 'hsb_saturation':
          await _applyHSBFilters();
          break;
        case 'hsb_brightness':
          await _applyHSBFilters();
          break;

        // Effect filters
        default:
          if (filter.type == FilterType.effect) {
            await _applyEffectFilter(filter);
          }
      }
    } catch (e) {
      debugPrint('Error applying filter: $e');
    }
  }

  Future<void> _applyEffectFilter(FilterItem filter) async {
    try {
      // Check if this is a cloud filter that needs to be downloaded
      if ((filter.path == null || filter.path!.isEmpty) &&
          !filter.isDownloaded) {
        // This is a cloud filter that needs to be downloaded

        // Show loading indicator
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text('Downloading ${filter.name}...'),
                ],
              ),
              backgroundColor: const Color(0xFF6C5CE7),
              duration: const Duration(seconds: 3),
            ),
          );
        }

        // Download the cloud filter
        final downloadResult = await _nosmai.downloadCloudFilter(filter.id);

        if (downloadResult['success'] == true) {
          // Update filter path with downloaded path
          final downloadedPath = downloadResult['path'] as String?;
          if (downloadedPath != null) {
            filter.path = downloadedPath;

            // Apply the downloaded filter
            await _nosmai.applyFilter(downloadedPath);

            // Show success message
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${filter.name} downloaded and applied!'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          } else {
            throw Exception('Download succeeded but no path returned');
          }
        } else {
          throw Exception(downloadResult['error'] ?? 'Download failed');
        }
      } else {
        // This is a local filter or already downloaded cloud filter
        await _nosmai.applyFilter(filter.path!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to apply ${filter.name}: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _applyHSBFilters() async {
    final hueFilter = _categories[3].filters.firstWhere(
          (f) => f.id == 'hsb_hue',
        );
    final satFilter = _categories[3].filters.firstWhere(
          (f) => f.id == 'hsb_saturation',
        );
    final brightnessFilter = _categories[3].filters.firstWhere(
          (f) => f.id == 'hsb_brightness',
        );

    try {
      await _nosmai.resetHSBFilter();

      // Apply hue using standalone filter (HSB hue not implemented)
      if (hueFilter.value != 0.0) {
        double hueValue =
            hueFilter.value < 0 ? hueFilter.value + 360 : hueFilter.value;
        await _nosmai.applyHue(hueValue);
      }

      // Apply saturation and brightness
      await _nosmai.adjustHSB(
        hue: 0.0,
        saturation: satFilter.value,
        brightness: brightnessFilter.value,
      );
    } catch (e) {
      debugPrint('Error applying HSB filters: $e');
    }
  }

  Future<void> _resetAllFilters() async {
    try {
      await _nosmai.removeBuiltInFilters();
      await _nosmai.resetHSBFilter();
      await _nosmai.removeAllFilters();

      // Reset all filter values
      for (final category in _categories) {
        for (final filter in category.filters) {
          if (filter.type == FilterType.slider) {
            setState(() {
              filter.value = filter.defaultValue;
            });
          }
        }
      }

      setState(() {
        _activeFilter = null;
      });
    } catch (e) {
      debugPrint('Error resetting filters: $e');
    }
  }

  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        _recordButtonController.reverse();
        final result = await _nosmai.stopRecording();

        if (!mounted) return;

        setState(() => _isRecording = false);

        if (result.success && result.videoPath != null) {
          _showVideoSuccessDialog(result.videoPath!);
        }
      } else {
        final success = await _nosmai.startRecording();

        if (!mounted) return;

        if (success) {
          setState(() => _isRecording = true);
          _recordButtonController.forward();
        }
      }
    } catch (e) {
      debugPrint('Recording error: $e');
    }
  }

  Future<void> _capturePhoto() async {
    // Add haptic feedback
    HapticFeedback.mediumImpact();

    try {
      final result = await _nosmai.capturePhoto();

      if (result.success) {
        _showPhotoSuccessDialog(result);
      }
    } catch (e) {
      debugPrint('Photo capture error: $e');
    }
  }

  Future<void> _switchCamera() async {
    try {
      // Check if SDK is still initialized
      if (!_nosmai.isInitialized) {
        debugPrint('❌ SDK not initialized, cannot switch camera');
        return;
      }

      final switched = await _nosmai.switchCamera();

      if (switched) {
        setState(() {
          _isFrontCamera = !_isFrontCamera;
        });
        debugPrint(
          '✅ Camera switched successfully to ${_isFrontCamera ? 'front' : 'back'}',
        );
      } else {
        debugPrint('🔄 Camera switch throttled - ignored rapid tap');
      }
    } catch (e) {
      debugPrint('❌ Camera switch failed: $e');

      // Handle specific error types
      if (e is NosmaiError) {
        _handleCameraError(e);
      } else {
        _showErrorMessage('Camera switch failed: ${e.toString()}');
      }
    }
  }

  /// Handle camera-specific errors with user-friendly messages
  void _handleCameraError(NosmaiError error) {
    switch (error.type) {
      case NosmaiErrorType.cameraPermissionDenied:
        _showErrorDialog(
          'Camera Permission Required',
          error.userMessage,
          actions: error.recoveryActions,
        );
        break;
      case NosmaiErrorType.cameraUnavailable:
        _showErrorMessage('Camera is not available on this device');
        break;
      case NosmaiErrorType.cameraSwitchFailed:
        _showErrorMessage('Failed to switch camera. Please try again.');
        break;
      default:
        _showErrorMessage(error.userMessage);
    }
  }

  /// Show error dialog with recovery actions
  void _showErrorDialog(String title, String message, {List<String>? actions}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (actions != null && actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Suggested actions:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...actions.map((action) => Text('• $action')),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show simple error message
  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showPhotoSuccessDialog(NosmaiPhotoResult result) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      isDismissible: true,
      enableDrag: false,
      builder: (context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Icon(
              Icons.check_circle,
              color: Color(0xFF4ECDC4),
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              'Photo Captured!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withOpacity(0.3),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Done'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      if (result.imageData != null) {
                        await _savePhotoToGallery(result);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Save to Gallery'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _savePhotoToGallery(NosmaiPhotoResult result) async {
    try {
      final permission = await Permission.photos.request();
      if (permission != PermissionStatus.granted) return;

      final imageResult = await _nosmai.saveImageToGallery(
        result.imageData!,
        name: "nosmai_photo_${DateTime.now().millisecondsSinceEpoch}",
      );

      if (imageResult['isSuccess'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Photo saved to gallery'),
            backgroundColor: const Color(0xFF4ECDC4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to save photo: $e');
    }
  }

  void _showVideoSuccessDialog(String videoPath) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: false,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Icon(Icons.videocam, color: Color(0xFF4ECDC4), size: 48),
            const SizedBox(height: 16),
            const Text(
              'Video Recorded!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _saveVideoToGallery(videoPath);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Save to Gallery'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _saveVideoToGallery(String videoPath) async {
    try {
      final permission = await Permission.photos.request();
      if (permission != PermissionStatus.granted) return;

      final result = await _nosmai.saveVideoToGallery(
        videoPath,
        name: "nosmai_video_${DateTime.now().millisecondsSinceEpoch}",
      );

      if (result['isSuccess'] == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Video saved to gallery'),
            backgroundColor: const Color(0xFF4ECDC4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to save video: $e');
    }
  }

  Future<bool> hasOldFilterStructure() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);

      // Check if any asset starts with 'assets/filters/' and ends with '.nosmai'
      final hasOldFilters = manifestMap.keys.any((String key) =>
          key.startsWith('assets/filters/') && key.endsWith('.nosmai'));

      return hasOldFilters;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          print("================= ${await hasOldFilterStructure()}");
          print('🔘 FloatingActionButton pressed!');
          try {
            // Get local filters from nosmai_filters structure
            final localFilters = await _nosmai.getLocalFilters();

            print('📊 Local Filters (nosmai_filters): ${localFilters.length}');

            if (localFilters.isNotEmpty) {
              print('✅ Success!');
              print('   Filter Count: ${localFilters.length}');

              // Print all filters with their metadata
              for (var i = 0; i < localFilters.length; i++) {
                final filter = localFilters[i];
                print('\n📋 Filter ${i + 1}:');
                print('   - ID: ${filter.id}');
                print('   - Name: ${filter.name}');
                print('   - Display Name: ${filter.displayName}');
                print('   - Description: ${filter.description}');
                print('   - Filter Type: ${filter.sourceType.name}');
                print('   - Version: ${filter.version}');
                print('   - Author: ${filter.author}');
                print('   - Tags: ${filter.tags}');
                print('   - Path: ${filter.path}');
              }

              // Show snackbar
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Found ${localFilters.length} local filters',
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );

                // Apply first filter
                _nosmai.applyFilter(localFilters[0].path);
              }
            } else {
              print('❌ No filters found');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No local filters found'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          } catch (e) {
            print('❌ Error calling getLocalFilters: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        child: const Icon(Icons.filter_vintage),
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: RepaintBoundary(child: NosmaiCameraPreview()),
          ),

          // Top Controls
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Back button
                      _buildIconButton(
                        icon: Icons.arrow_back_ios_rounded,
                        onTap: () async {
                          await cleanupBeforeNavigation();
                          if (mounted) {
                            Navigator.pop(context);
                          }
                        },
                      ),

                      // Center controls
                      Row(
                        children: [
                          if (_activeFilter != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _activeFilter!.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),

                      // Right controls
                      Row(
                        children: [
                          _buildIconButton(
                            icon: NosmaiFlutter.isCameraSwitching
                                ? Icons.hourglass_empty_rounded
                                : Icons.flip_camera_ios_rounded,
                            onTap: NosmaiFlutter.isCameraSwitching
                                ? null
                                : _switchCamera,
                          ),
                          const SizedBox(width: 12),
                          _buildIconButton(
                            icon: Icons.refresh_rounded,
                            onTap: _resetAllFilters,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Filter Panel Backdrop
          if (_isFilterPanelVisible)
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleFilterPanel,
                child: Container(color: Colors.transparent),
              ),
            ),

          // Filter Panel
          if (_isFilterPanelVisible)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _filterPanelController,
                builder: (context, child) {
                  final screenHeight = MediaQuery.of(context).size.height;
                  final panelHeight =
                      screenHeight < 700 ? screenHeight * 0.4 : 300.0;
                  return Transform.translate(
                    offset: Offset(
                      0,
                      panelHeight * (1 - _filterPanelController.value),
                    ),
                    child: Opacity(
                      opacity: _filterPanelController.value,
                      child: _buildFilterPanel(),
                    ),
                  );
                },
              ),
            ),

          // Bottom Controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Main Controls
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.9),
                        Colors.black.withOpacity(0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        // Action Buttons
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Gallery
                              _buildActionButton(
                                icon: Icons.photo_library_rounded,
                                onTap: () {},
                                size: 20,
                              ),

                              // Capture Photo
                              _buildActionButton(
                                icon: Icons.camera_alt_rounded,
                                onTap: _capturePhoto,
                                size: 24,
                              ),

                              // Record Video
                              GestureDetector(
                                onTap: _toggleRecording,
                                child: AnimatedBuilder(
                                  animation: _recordButtonController,
                                  builder: (context, child) {
                                    return Container(
                                      width: 60,
                                      height: 60,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _isRecording
                                              ? Colors.red
                                              : Colors.white,
                                          width: 3,
                                        ),
                                      ),
                                      child: Center(
                                        child: Container(
                                          width: 46,
                                          height: 46,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _isRecording
                                                ? Colors.red
                                                : Colors.white.withOpacity(
                                                    0.3,
                                                  ),
                                          ),
                                          child: Icon(
                                            _isRecording
                                                ? Icons.stop
                                                : Icons.videocam,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),

                              // Filters
                              _buildActionButton(
                                icon: Icons.auto_awesome,
                                onTap: _toggleFilterPanel,
                                isActive: _isFilterPanelVisible,
                                size: 20,
                              ),

                              // Effects
                              _buildActionButton(
                                icon: Icons.blur_on_rounded,
                                onTap: () {
                                  setState(() => _selectedCategoryIndex = 0);
                                  if (!_isFilterPanelVisible) {
                                    _toggleFilterPanel();
                                  }
                                },
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Recording Indicator
          if (_isRecording)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.only(top: 16),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Recording',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Filter Loading Indicator (non-blocking)
          if (_isCloudFiltersLoading)
            Positioned(
              bottom: 320,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF6C5CE7),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Loading filters...',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback? onTap,
    double size = 24,
  }) {
    final isDisabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(isDisabled ? 0.1 : 0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: Colors.white.withOpacity(isDisabled ? 0.5 : 1.0),
          size: size,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    double size = 24,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF6C5CE7)
              : Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }

  Widget _buildFilterPanel() {
    final screenHeight = MediaQuery.of(context).size.height;
    final panelHeight = screenHeight < 700 ? screenHeight * 0.4 : 300.0;

    return Container(
      height: panelHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Category Tabs
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategoryIndex == index;

                return GestureDetector(
                  onTap: () => setState(() => _selectedCategoryIndex = index),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF6C5CE7)
                          : Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(category.icon, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          category.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          // Filter Content
          Expanded(child: _buildFilterContent()),
        ],
      ),
    );
  }

  /// Since cloud filters now load automatically, the button is no longer needed.
  Widget _buildFilterContent() {
    final category = _categories[_selectedCategoryIndex];

    // Show loading indicator for cloud filters while they are being fetched.
    if (category.name == 'Cloud' && _isCloudFiltersLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
      );
    }

    if (category.filters.isEmpty) {
      return Center(
        child: Text(
          'No filters available',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
        ),
      );
    }

    // For effect or cloud filters, show horizontal scrollable list
    if (category.name == 'Effects' || category.name == 'Cloud') {
      return SizedBox(
        height: 80,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: category.filters.length,
          itemBuilder: (context, index) {
            final filter = category.filters[index];
            final isActive = _activeFilter?.id == filter.id;

            return GestureDetector(
              onTap: () => _applyFilter(filter),
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive
                            ? const Color(0xFF6C5CE7)
                            : Colors.white.withOpacity(0.1),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFF6C5CE7)
                              : Colors.white.withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      width: 60,
                      child: Text(
                        filter.name,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    // For slider filters, show horizontal scrollable list
    return SizedBox(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: category.filters.length,
        itemBuilder: (context, index) {
          final filter = category.filters[index];

          return Container(
            width: 120,
            margin: const EdgeInsets.only(right: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  filter.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  filter.max > 100
                      ? filter.value.toStringAsFixed(0)
                      : filter.value.toStringAsFixed(filter.max > 10 ? 0 : 2),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF6C5CE7),
                    inactiveTrackColor: Colors.white.withOpacity(0.2),
                    thumbColor: const Color(0xFF6C5CE7),
                    overlayColor: const Color(0xFF6C5CE7).withOpacity(0.3),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: filter.value.clamp(filter.min, filter.max),
                    min: filter.min,
                    max: filter.max,
                    onChanged: (value) {
                      setState(() {
                        filter.value = value;
                      });
                    },
                    onChangeEnd: (_) => _applyFilter(filter),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _ensureCameraReady();
        break;
      case AppLifecycleState.paused:
        _pauseCamera();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordButtonController.dispose();
    _filterPanelController.dispose();
    // Stop camera when leaving screen
    _pauseCamera();
    super.dispose();
  }

  /// Pause camera when leaving screen
  Future<void> _pauseCamera() async {
    try {
      // Just stop processing, don't dispose anything
      if (_nosmai.isProcessing) {
        await _nosmai.stopProcessing();
      }
    } catch (e) {
      debugPrint('Error pausing camera: $e');
    }
  }
}

// Data Models
enum FilterType { slider, toggle, effect }

class FilterCategory {
  final String name;
  final IconData icon;
  List<FilterItem> filters;

  FilterCategory({
    required this.name,
    required this.icon,
    required this.filters,
  });
}

class FilterItem {
  final String id;
  final String name;
  final FilterType type;
  double value;
  final double min;
  final double max;
  String? path;
  final bool isDownloaded;

  FilterItem({
    required this.id,
    required this.name,
    required this.type,
    this.value = 0.0,
    this.min = 0.0,
    this.max = 1.0,
    this.path,
    this.isDownloaded = true, // Default to true for local filters
  });

  double get defaultValue {
    switch (id) {
      case 'contrast':
      case 'hsb_saturation':
      case 'hsb_brightness':
        return 1.0;
      case 'temperature':
        return 5000.0;
      case 'nose_size':
        return 50.0;
      default:
        return 0.0;
    }
  }
}
