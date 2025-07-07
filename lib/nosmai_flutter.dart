
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'nosmai_flutter_platform_interface.dart';
import 'nosmai_types.dart';

// Export types and widgets for easy access
export 'nosmai_types.dart';
export 'nosmai_camera_preview.dart';
export 'nosmai_camera_lifecycle_mixin.dart';

/// Main NosmaiFlutter class that provides the public API
class NosmaiFlutter {
  /// Private constructor to prevent direct instantiation
  NosmaiFlutter._();

  /// Singleton instance
  static final NosmaiFlutter _instance = NosmaiFlutter._();

  /// Get the shared instance
  static NosmaiFlutter get instance => _instance;

  /// Stream controller for error events (lazy initialization)
  StreamController<NosmaiError>? _errorController;

  /// Stream controller for download progress events (lazy initialization)
  StreamController<NosmaiDownloadProgress>? _downloadProgressController;

  /// Stream controller for SDK state changes (lazy initialization)
  StreamController<NosmaiSdkState>? _stateController;

  /// Stream controller for recording progress events (lazy initialization)
  StreamController<double>? _recordingProgressController;

  /// Whether the SDK has been initialized
  bool _isInitialized = false;

  /// Whether processing is currently active
  bool _isProcessing = false;

  /// Whether recording is currently active
  bool _isRecording = false;

  /// Whether the instance has been disposed
  bool _isDisposed = false;

  /// List of active async operations to cancel on dispose
  final List<Future> _activeOperations = [];

  /// Stream of error events
  Stream<NosmaiError> get onError {
    _errorController ??= StreamController<NosmaiError>.broadcast();
    return _errorController!.stream;
  }

  /// Stream of download progress events
  Stream<NosmaiDownloadProgress> get onDownloadProgress {
    _downloadProgressController ??= StreamController<NosmaiDownloadProgress>.broadcast();
    return _downloadProgressController!.stream;
  }

  /// Stream of SDK state changes
  Stream<NosmaiSdkState> get onStateChanged {
    _stateController ??= StreamController<NosmaiSdkState>.broadcast();
    return _stateController!.stream;
  }

  /// Stream of recording progress events (duration in seconds)
  Stream<double> get onRecordingProgress {
    _recordingProgressController ??= StreamController<double>.broadcast();
    return _recordingProgressController!.stream;
  }

  /// Whether the SDK is initialized
  bool get isInitialized => _isInitialized;

  /// Whether processing is active
  bool get isProcessing => _isProcessing;

  /// Whether recording is active
  bool get isRecording => _isRecording;

  /// Initialize the SDK with a license key
  ///
  /// Returns true if initialization was successful, false otherwise.
  /// Must be called before any other SDK methods.
  /// Automatically handles cleanup of previous instances if needed.
  Future<bool> initWithLicense(String licenseKey) async {
    // Allow re-initialization after dispose for testing
    if (_isDisposed) {
      _isDisposed = false;
      _isInitialized = false;
      _isProcessing = false;
      _isRecording = false;
      _activeOperations.clear();
      debugPrint('🔄 Resetting disposed instance for re-initialization');
    }

    // If already initialized, clean up first
    if (_isInitialized) {
      debugPrint('⚠️ SDK already initialized, cleaning up first...');
      await _internalCleanup();
    }

    try {
      final success = await _trackOperation(
          NosmaiFlutterPlatform.instance.initWithLicense(licenseKey));

      _isInitialized = success;

      if (success) {
        debugPrint('✅ Nosmai SDK initialized successfully');
      } else {
        debugPrint('❌ Nosmai SDK initialization failed');
      }

      return success;
    } catch (e) {
      _errorController?.add(NosmaiError(
        code: 'INIT_ERROR',
        message: 'Failed to initialize SDK',
        details: e.toString(),
      ));
      debugPrint('❌ SDK initialization error: $e');
      return false;
    }
  }

  /// Configure camera with position and optional session preset
  ///
  /// Must be called after initialization and before starting processing.
  /// If [sessionPreset] is not provided, defaults to AVCaptureSessionPresetHigh.
  Future<void> configureCamera({
    required NosmaiCameraPosition position,
    String? sessionPreset,
  }) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.configureCamera(
      position: position,
      sessionPreset: sessionPreset,
    );
  }

  /// Start video processing
  ///
  /// Begins capturing and processing video from the camera.
  Future<void> startProcessing() async {
    _checkInitialized();

    if (_isProcessing) {
      debugPrint('⚠️ Already processing, ignoring start request');
      return;
    }

    try {
      await _trackOperation(NosmaiFlutterPlatform.instance.startProcessing());
      _isProcessing = true;
      debugPrint('▶️ Video processing started');
    } catch (e) {
      debugPrint('❌ Failed to start processing: $e');
      rethrow;
    }
  }

  /// Stop video processing
  ///
  /// Stops capturing and processing video from the camera.
  Future<void> stopProcessing() async {
    if (_isDisposed) {
      debugPrint('⚠️ Instance disposed, skipping stop processing');
      return;
    }

    if (!_isProcessing) {
      debugPrint('⚠️ Not currently processing, ignoring stop request');
      return;
    }

    try {
      await _trackOperation(NosmaiFlutterPlatform.instance.stopProcessing());
      _isProcessing = false;
      debugPrint('⏹️ Video processing stopped');
    } catch (e) {
      _isProcessing = false; // Ensure state is consistent
      debugPrint('❌ Error stopping processing: $e');
      rethrow;
    }
  }








  /// Load a Nosmai filter file
  ///
  /// [filePath] - Path to the .nosmai file
  /// Returns true if successful, false otherwise
  Future<bool> loadNosmaiFilter(String filePath) async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.loadNosmaiFilter(filePath);
  }

  /// Switch between front and back camera
  ///
  /// Returns true if successful, false otherwise
  Future<bool> switchCamera() async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.switchCamera();
  }

  /// Enable or disable automatic face detection
  ///
  /// Face detection is required for beauty and face reshape filters.
  /// [enable] - true to enable, false to disable
  Future<void> setFaceDetectionEnabled(bool enable) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.setFaceDetectionEnabled(enable);
  }

  /// Remove all applied filters
  ///
  /// Clears all currently applied filters and returns to original video feed.
  Future<void> removeAllFilters() async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.removeAllFilters();
  }

  /// Set preview view (iOS only)
  ///
  /// Sets up the native view for camera preview display.
  Future<void> setPreviewView() async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.setPreviewView();
  }

  /// Clean up and release all resources
  ///
  /// Should be called when done using the SDK to free up memory and resources.
  /// This method handles all internal cleanup automatically.
  Future<void> cleanup() async {
    if (_isDisposed) return; // Already disposed

    _isDisposed = true;

    try {
      // Stop any ongoing recording
      if (_isRecording) {
        await stopRecording().catchError((e) {
          debugPrint('Error stopping recording during cleanup: $e');
          return const NosmaiRecordingResult(success: false, duration: 0, fileSize: 0);
        });
      }

      // Stop processing
      if (_isProcessing) {
        await stopProcessing().catchError((e) {
          debugPrint('Error stopping processing during cleanup: $e');
          return;
        });
      }

      // Clean up SDK resources
      if (_isInitialized) {
        await NosmaiFlutterPlatform.instance.cleanup().catchError((e) {
          debugPrint('Error cleaning up platform: $e');
        });
      }

      // Reset all state
      _isInitialized = false;
      _isProcessing = false;
      _isRecording = false;

      // Clear active operations
      _activeOperations.clear();

      debugPrint('✅ Nosmai SDK cleanup completed successfully');
    } catch (e) {
      debugPrint('❌ Error during cleanup: $e');
    }
  }

  /// Internal cleanup for double initialization - doesn't mark as disposed
  Future<void> _internalCleanup() async {
    try {
      // Stop any ongoing recording
      if (_isRecording) {
        await stopRecording().catchError((e) {
          debugPrint('Error stopping recording during cleanup: $e');
          return const NosmaiRecordingResult(success: false, duration: 0, fileSize: 0);
        });
      }

      // Stop processing
      if (_isProcessing) {
        await stopProcessing().catchError((e) {
          debugPrint('Error stopping processing during cleanup: $e');
          return;
        });
      }

      // Clean up SDK resources
      if (_isInitialized) {
        await NosmaiFlutterPlatform.instance.cleanup().catchError((e) {
          debugPrint('Error cleaning up platform: $e');
        });
      }

      // Reset state but don't mark as disposed
      _isInitialized = false;
      _isProcessing = false;
      _isRecording = false;

      // Clear active operations
      _activeOperations.clear();

      debugPrint('✅ Nosmai SDK cleanup completed successfully');
    } catch (e) {
      debugPrint('❌ Error during internal cleanup: $e');
    }
  }

  // New Advanced Features

  /// Apply a .nosmai effect file
  ///
  /// [effectPath] - Path to the .nosmai effect file
  /// Returns true if successful, false otherwise
  Future<bool> applyEffect(String effectPath) async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.applyEffect(effectPath);
  }

  /// Get list of available cloud filters
  ///
  /// Returns a list of cloud filter information
  Future<List<NosmaiCloudFilter>> getCloudFilters() async {
    _checkInitialized();
    final List<dynamic> filters =
        await NosmaiFlutterPlatform.instance.getCloudFilters();
    return filters
        .map((filter) =>
            NosmaiCloudFilter.fromMap(Map<String, dynamic>.from(filter)))
        .toList();
  }

  /// Download a cloud filter
  ///
  /// [filterId] - The ID of the filter to download
  /// Returns download result with success status and local path
  Future<Map<String, dynamic>> downloadCloudFilter(String filterId) async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.downloadCloudFilter(filterId);
  }

  /// Get list of local .nosmai filters
  ///
  /// Returns a list of local filter information
  Future<List<NosmaiLocalFilter>> getLocalFilters() async {
    _checkInitialized();
    final List<dynamic> filters =
        await NosmaiFlutterPlatform.instance.getLocalFilters();
    return filters
        .map((filter) =>
            NosmaiLocalFilter.fromMap(Map<String, dynamic>.from(filter)))
        .toList();
  }

  /// Get combined list of local and cloud filters
  ///
  /// Returns a list of all available filters (local from assets + cloud filters)
  /// Local filters are loaded automatically from assets/filters directory
  /// Cloud filters require download before use
  Future<List<dynamic>> getFilters() async {
    _checkInitialized();
    final List<dynamic> filters =
        await NosmaiFlutterPlatform.instance.getFilters();

    return filters.map((filter) {
      final filterMap = Map<String, dynamic>.from(filter);
      final type = filterMap['type'] as String?;

      if (type == 'cloud') {
        final cloudFilter = NosmaiCloudFilter.fromMap(filterMap);
        return cloudFilter;
      } else {
        return NosmaiLocalFilter.fromMap(filterMap);
      }
    }).toList();
  }

  /// Check if a filter is a beauty filter based on metadata
  ///
  /// This uses the filterCategory metadata instead of name-based detection
  bool isBeautyFilter(dynamic filter) {
    if (filter is NosmaiLocalFilter) {
      return filter.filterCategory == NosmaiFilterCategory.beauty;
    } else if (filter is NosmaiCloudFilter) {
      return filter.filterCategory == NosmaiFilterCategory.beauty;
    }
    return false;
  }

  /// Get all filters of a specific category
  ///
  /// Returns filters that match the given category type
  Future<List<dynamic>> getFiltersByCategory(NosmaiFilterCategory category) async {
    final allFilters = await getFilters();
    return allFilters.where((filter) {
      if (filter is NosmaiLocalFilter) {
        return filter.filterCategory == category;
      } else if (filter is NosmaiCloudFilter) {
        return filter.filterCategory == category;
      }
      return false;
    }).toList();
  }

  /// Organize all filters by their category
  ///
  /// Returns a map with categories as keys and lists of filters as values
  Future<Map<NosmaiFilterCategory, List<dynamic>>> organizeFiltersByCategory() async {
    final allFilters = await getFilters();
    final Map<NosmaiFilterCategory, List<dynamic>> organized = {};
    
    // Initialize categories
    for (final category in NosmaiFilterCategory.values) {
      organized[category] = [];
    }
    
    // Organize filters
    for (final filter in allFilters) {
      NosmaiFilterCategory category = NosmaiFilterCategory.unknown;
      
      if (filter is NosmaiLocalFilter) {
        category = filter.filterCategory;
      } else if (filter is NosmaiCloudFilter) {
        category = filter.filterCategory;
      }
      
      organized[category]!.add(filter);
    }
    
    return organized;
  }

  /// Get parameters for the currently loaded effect
  ///
  /// Returns a list of effect parameters that can be adjusted
  Future<List<NosmaiEffectParameter>> getEffectParameters() async {
    _checkInitialized();
    final List<dynamic> parameters =
        await NosmaiFlutterPlatform.instance.getEffectParameters();
    return parameters
        .map((param) =>
            NosmaiEffectParameter.fromMap(Map<String, dynamic>.from(param)))
        .toList();
  }

  /// Set a parameter value for the current effect
  ///
  /// [parameterName] - Name of the parameter to set
  /// [value] - Value to set (typically 0.0 to 1.0)
  /// Returns true if successful, false otherwise
  Future<bool> setEffectParameter(String parameterName, double value) async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance
        .setEffectParameter(parameterName, value);
  }

  // Recording Features

  /// Start video recording
  ///
  /// Returns true if recording started successfully
  Future<bool> startRecording() async {
    _checkInitialized();

    if (_isRecording) {
      debugPrint('⚠️ Already recording, ignoring start request');
      return true;
    }

    final success =
        await _trackOperation(NosmaiFlutterPlatform.instance.startRecording());

    if (success) {
      _isRecording = true;
      debugPrint('▶️ Recording started');
    } else {
      debugPrint('❌ Failed to start recording');
    }

    return success;
  }

  /// Stop video recording
  ///
  /// Returns recording result with video path
  Future<NosmaiRecordingResult> stopRecording() async {
    _checkInitialized();

    if (!_isRecording) {
      debugPrint('⚠️ Not currently recording, ignoring stop request');
      return const NosmaiRecordingResult(
        success: false,
        duration: 0,
        fileSize: 0,
        error: 'Not currently recording',
      );
    }

    try {
      final result =
          await _trackOperation(NosmaiFlutterPlatform.instance.stopRecording());

      _isRecording = false;

      final recordingResult =
          NosmaiRecordingResult.fromMap(Map<String, dynamic>.from(result));

      if (recordingResult.success) {
        debugPrint('⏹️ Recording stopped successfully');
      } else {
        debugPrint('❌ Failed to stop recording: ${recordingResult.error}');
      }

      return recordingResult;
    } catch (e) {
      _isRecording = false; // Ensure state is consistent
      debugPrint('❌ Error stopping recording: $e');
      return NosmaiRecordingResult(
        success: false,
        duration: 0,
        fileSize: 0,
        error: e.toString(),
      );
    }
  }

  /// Check if currently recording
  ///
  /// Returns true if recording is in progress
  Future<bool> isCurrentlyRecording() async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.isRecording();
  }

  /// Get current recording duration
  ///
  /// Returns the current recording duration in seconds, 0 if not recording
  Future<double> getCurrentRecordingDuration() async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.getCurrentRecordingDuration();
  }


  /// Get platform version (for debugging)
  Future<String?> getPlatformVersion() async {
    return await NosmaiFlutterPlatform.instance.getPlatformVersion();
  }

  /// Capture photo with applied filters
  ///
  /// Returns a map containing success status and photo data
  /// On success: {'success': true, 'imagePath': String?, 'imageData': Uint8List?}
  /// On failure: {'success': false, 'error': String}
  Future<NosmaiPhotoResult> capturePhoto() async {
    _checkInitialized();
    try {
      final result = await NosmaiFlutterPlatform.instance.capturePhoto();
      return NosmaiPhotoResult.fromMap(result);
    } catch (e) {
      _errorController?.add(NosmaiError(
        code: 'PHOTO_CAPTURE_ERROR',
        message: 'Failed to capture photo',
        details: e.toString(),
      ));
      return NosmaiPhotoResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Save image data to device gallery (iOS Photos app)
  ///
  /// [imageData] - Raw image data as List&lt;int&gt;
  /// [name] - Optional name for the saved image
  /// Returns a map with success status and file path
  Future<Map<String, dynamic>> saveImageToGallery(List<int> imageData,
      {String? name}) async {
    _checkInitialized();
    try {
      return await NosmaiFlutterPlatform.instance
          .saveImageToGallery(imageData, name: name);
    } catch (e) {
      _errorController?.add(NosmaiError(
        code: 'SAVE_IMAGE_ERROR',
        message: 'Failed to save image to gallery',
        details: e.toString(),
      ));
      return {'isSuccess': false, 'error': e.toString()};
    }
  }

  /// Save video file to device gallery (iOS Photos app)
  ///
  /// [videoPath] - Path to the video file
  /// [name] - Optional name for the saved video
  /// Returns a map with success status and file path
  Future<Map<String, dynamic>> saveVideoToGallery(String videoPath,
      {String? name}) async {
    _checkInitialized();
    try {
      return await NosmaiFlutterPlatform.instance
          .saveVideoToGallery(videoPath, name: name);
    } catch (e) {
      _errorController?.add(NosmaiError(
        code: 'SAVE_VIDEO_ERROR',
        message: 'Failed to save video to gallery',
        details: e.toString(),
      ));
      return {'isSuccess': false, 'error': e.toString()};
    }
  }

  /// Clear filter cache to force refresh
  ///
  /// This method clears the internal filter cache, forcing a fresh discovery
  /// of filters on the next getFilters() call. Useful after downloading new
  /// cloud filters or when troubleshooting filter issues.
  Future<void> clearFilterCache() async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.clearFilterCache();
  }

  /// Detach camera from current view
  ///
  /// This method gracefully detaches the camera from any currently attached view.
  /// Useful when navigating away from camera screens to ensure clean resource management.
  Future<void> detachCameraView() async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.detachCameraView();
  }

  /// Dispose of stream controllers and clean up all resources
  ///
  /// This is the ONLY method users need to call for complete cleanup.
  /// It handles all internal state management automatically.
  void dispose() {
    if (_isDisposed) return; // Already disposed

    // Mark as disposed first to prevent new operations
    _isDisposed = true;

    // Perform cleanup asynchronously but don't wait
    _performAsyncCleanup();

    // Close stream controllers immediately
    _errorController?.close();
    _downloadProgressController?.close();
    _stateController?.close();
    _recordingProgressController?.close();
    
    // Clear references
    _errorController = null;
    _downloadProgressController = null;
    _stateController = null;
    _recordingProgressController = null;

    debugPrint('✅ Nosmai Flutter instance disposed successfully');
  }

  /// Internal async cleanup that doesn't block dispose()
  void _performAsyncCleanup() async {
    try {
      // Stop any ongoing recording
      if (_isRecording) {
        await stopRecording().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('⚠️ Recording stop timed out during dispose');
            return const NosmaiRecordingResult(
                success: false, duration: 0, fileSize: 0);
          },
        );
      }

      // Stop processing
      if (_isProcessing) {
        await stopProcessing().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('⚠️ Processing stop timed out during dispose');
          },
        );
      }

      // Clean up SDK resources
      if (_isInitialized) {
        await NosmaiFlutterPlatform.instance.cleanup().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('⚠️ Platform cleanup timed out during dispose');
          },
        );
      }

      // Reset all state
      _isInitialized = false;
      _isProcessing = false;
      _isRecording = false;
      _activeOperations.clear();
    } catch (e) {
      debugPrint('⚠️ Error during async cleanup: $e');
    }
  }

  /// Check if SDK is initialized and not disposed
  void _checkInitialized() {
    if (_isDisposed) {
      throw StateError(
          'NosmaiFlutter instance has been disposed. Call initWithLicense() again to reinitialize.');
    }
    if (!_isInitialized) {
      throw StateError(
          'NosmaiFlutter must be initialized with initWithLicense() before use');
    }
  }

  /// Internal helper to track async operations
  Future<T> _trackOperation<T>(Future<T> operation) {
    if (_isDisposed) {
      return Future.error(
          StateError('Cannot perform operation on disposed instance'));
    }

    _activeOperations.add(operation);

    return operation.whenComplete(() {
      _activeOperations.remove(operation);
    });
  }

  // Built-in Filter Methods

  /// Apply brightness filter
  ///
  /// [brightness] - Brightness value (typically -1.0 to 1.0)
  Future<void> applyBrightnessFilter(double brightness) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyBrightnessFilter(brightness);
  }

  /// Apply contrast filter
  ///
  /// [contrast] - Contrast value (typically 0.0 to 2.0)
  Future<void> applyContrastFilter(double contrast) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyContrastFilter(contrast);
  }

  /// Apply RGB filter
  ///
  /// [red] - Red channel adjustment (typically 0.0 to 2.0)
  /// [green] - Green channel adjustment (typically 0.0 to 2.0)
  /// [blue] - Blue channel adjustment (typically 0.0 to 2.0)
  Future<void> applyRGBFilter({required double red, required double green, required double blue}) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyRGBFilter(red: red, green: green, blue: blue);
  }

  /// Apply skin smoothing filter
  ///
  /// [level] - Smoothing level (0.0 to 10.0)
  /// Note: Face detection must be enabled for this filter to work
  Future<void> applySkinSmoothing(double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applySkinSmoothing(level);
  }

  /// Apply skin whitening filter
  ///
  /// [level] - Whitening level (0.0 to 10.0)
  /// Note: Face detection must be enabled for this filter to work
  Future<void> applySkinWhitening(double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applySkinWhitening(level);
  }

  /// Apply face slimming filter
  ///
  /// [level] - Slimming level (0.0 to 10.0)
  /// Note: Face detection must be enabled for this filter to work
  Future<void> applyFaceSlimming(double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyFaceSlimming(level);
  }

  /// Apply eye enlargement filter
  ///
  /// [level] - Enlargement level (0.0 to 10.0)
  /// Note: Face detection must be enabled for this filter to work
  Future<void> applyEyeEnlargement(double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyEyeEnlargement(level);
  }

  /// Apply nose size filter
  ///
  /// [level] - Nose size level (0.0 to 100.0, with 50.0 being normal)
  /// Note: Face detection must be enabled for this filter to work
  Future<void> applyNoseSize(double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyNoseSize(level);
  }

  /// Apply sharpening filter
  ///
  /// [level] - Sharpening level (0.0 to 10.0)
  Future<void> applySharpening(double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applySharpening(level);
  }

  /// Apply makeup blend level
  ///
  /// [filterName] - Name of the makeup filter
  /// [level] - Blend level (0.0 to 1.0)
  Future<void> applyMakeupBlendLevel(String filterName, double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyMakeupBlendLevel(filterName, level);
  }

  /// Apply grayscale filter
  Future<void> applyGrayscaleFilter() async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyGrayscaleFilter();
  }

  /// Apply hue adjustment
  ///
  /// [hueAngle] - Hue angle adjustment (0.0 to 360.0)
  Future<void> applyHue(double hueAngle) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyHue(hueAngle);
  }


  /// Apply white balance filter
  ///
  /// [temperature] - Color temperature (2000-8000, where 5000 is normal)
  /// [tint] - Tint adjustment (typically -100 to 100)
  Future<void> applyWhiteBalance({required double temperature, required double tint}) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyWhiteBalance(temperature: temperature, tint: tint);
  }


  /// Adjust HSB (Hue, Saturation, Brightness)
  ///
  /// [hue] - Hue rotation in degrees (-360 to 360)
  /// [saturation] - Saturation level (0.0 to 2.0, where 1.0 is normal)
  /// [brightness] - Brightness level (0.0 to 2.0, where 1.0 is normal)
  /// Note: These adjustments are additive. Use resetHSBFilter() to start fresh.
  Future<void> adjustHSB({required double hue, required double saturation, required double brightness}) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.adjustHSB(hue: hue, saturation: saturation, brightness: brightness);
  }

  /// Reset HSB filter to default values
  Future<void> resetHSBFilter() async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.resetHSBFilter();
  }

  /// Remove all built-in filters
  Future<void> removeBuiltInFilters() async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.removeBuiltInFilters();
  }

  /// Remove a specific built-in filter by name
  ///
  /// [filterName] - Name of the filter to remove
  Future<void> removeBuiltInFilterByName(String filterName) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.removeBuiltInFilterByName(filterName);
  }

  /// Get initial filters available from the SDK
  ///
  /// Returns a list of filters that are available immediately
  Future<List<dynamic>> getInitialFilters() async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.getInitialFilters();
  }

  /// Fetch cloud filters from the server
  ///
  /// This triggers an async fetch of cloud filters.
  /// Listen to filter updates via delegate callbacks.
  Future<void> fetchCloudFilters() async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.fetchCloudFilters();
  }

  // License Feature Methods

  /// Check if beauty effects are enabled for the current license
  ///
  /// Returns true if beauty effects are available, false otherwise
  Future<bool> isBeautyEffectEnabled() async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.isBeautyEffectEnabled();
  }

  /// Check if cloud filters are enabled for the current license
  ///
  /// Returns true if cloud filters are available, false otherwise
  Future<bool> isCloudFilterEnabled() async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.isCloudFilterEnabled();
  }
}
