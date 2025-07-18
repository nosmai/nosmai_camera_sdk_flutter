/// Nosmai Flutter Plugin Core API
///
/// This file contains the main NosmaiFlutter class and core API methods.
library;

import 'dart:async';
import 'package:flutter/services.dart';

import '../types/enums.dart';
import '../types/models.dart';
import '../types/errors.dart';
import '../platform/platform_interface.dart';

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
  StreamController<NosmaiSdkStateInfo>? _stateController;

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

  /// Filter cache with TTL management
  static List<NosmaiFilter>? _cachedFilters;
  static DateTime? _lastCacheTime;
  static const Duration _defaultCacheValidityDuration = Duration(minutes: 5);

  /// Camera switch throttling
  static bool _isCameraSwitching = false;
  static DateTime? _lastSwitchTime;
  static const Duration _defaultThrottleDuration = Duration(milliseconds: 500);

  /// Stream of error events
  Stream<NosmaiError> get onError {
    _errorController ??= StreamController<NosmaiError>.broadcast();
    return _errorController!.stream;
  }

  /// Stream of download progress events
  Stream<NosmaiDownloadProgress> get onDownloadProgress {
    _downloadProgressController ??=
        StreamController<NosmaiDownloadProgress>.broadcast();
    return _downloadProgressController!.stream;
  }

  /// Stream of SDK state changes
  Stream<NosmaiSdkStateInfo> get onStateChanged {
    _stateController ??= StreamController<NosmaiSdkStateInfo>.broadcast();
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
  Future<bool> initWithLicense(String licenseKey) async {
    if (_isDisposed) {
      _isDisposed = false;
      _isInitialized = false;
      _isProcessing = false;
      _isRecording = false;
      _activeOperations.clear();
    }

    if (_isInitialized) {
      await cleanup();
    }

    try {
      final success = await _trackOperation(
          NosmaiFlutterPlatform.instance.initWithLicense(licenseKey));

      _isInitialized = success;
      // SDK initialization completed

      return success;
    } catch (e) {
      _errorController?.add(NosmaiError.general(
        type: NosmaiErrorType.platformError,
        message: 'Failed to initialize SDK',
        details: e.toString(),
        originalError: e,
      ));
      return false;
    }
  }

  /// Initialize the SDK
  /// 
  /// [licenseKey] - Your Nosmai SDK license key
  /// 
  /// Returns true if initialization was successful, false otherwise.
  static Future<bool> initialize(String licenseKey) async {
    final instance = NosmaiFlutter.instance;
    
    // Initialize the SDK
    final success = await instance.initWithLicense(licenseKey);
    
    if (success) {
      _preloadEssentialFilters();
    }
    
    return success;
  }

  static void _preloadEssentialFilters() {
    Future.microtask(() async {
      try {
        final instance = NosmaiFlutter.instance;
        await instance.getLocalFilters();
      } catch (e) {
        // Filter pre-loading failed
      }
    });
  }

  /// Configure camera with position and optional session preset
  Future<void> configureCamera({
    required NosmaiCameraPosition position,
    String? sessionPreset,
  }) async {
    _checkInitialized();
    
    try {
      await NosmaiFlutterPlatform.instance.configureCamera(
        position: position,
        sessionPreset: sessionPreset,
      );
    } on PlatformException catch (e) {
      throw NosmaiError.camera(
        type: _parseErrorType(e.code),
        message: e.message ?? 'Camera configuration failed',
        details: e.details?.toString(),
      );
    } catch (e, stackTrace) {
      throw NosmaiError.general(
        type: NosmaiErrorType.cameraConfigurationFailed,
        message: 'Failed to configure camera: ${e.toString()}',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Start video processing
  Future<void> startProcessing() async {
    _checkInitialized();

    if (_isProcessing) {
      return;
    }

    try {
      await _trackOperation(NosmaiFlutterPlatform.instance.startProcessing());
      _isProcessing = true;
    } catch (e) {
      rethrow;
    }
  }

  /// Stop video processing
  Future<void> stopProcessing() async {
    if (_isDisposed) {
      return;
    }

    if (!_isProcessing) {
      return;
    }

    try {
      await _trackOperation(NosmaiFlutterPlatform.instance.stopProcessing());
      _isProcessing = false;
    } catch (e) {
      _isProcessing = false;
      rethrow;
    }
  }

  /// Apply a .nosmai effect file
  Future<bool> applyEffect(String effectPath) async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.applyEffect(effectPath);
  }

  /// Get list of available cloud filters
  Future<List<NosmaiFilter>> getCloudFilters() async {
    _checkInitialized();
    try {
      final List<dynamic> filters =
          await NosmaiFlutterPlatform.instance.getCloudFilters();
      return filters
          .map((filter) =>
              NosmaiFilter.fromMap(Map<String, dynamic>.from(filter)))
          .toList();
    } catch (e) {
      _errorController?.add(NosmaiError.general(
        type: NosmaiErrorType.networkError,
        message: 'Failed to get cloud filters',
        details: e.toString(),
        originalError: e,
      ));
      // Return empty list instead of throwing to allow app to continue
      return [];
    }
  }

  /// Download a cloud filter
  Future<Map<String, dynamic>> downloadCloudFilter(String filterId) async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.downloadCloudFilter(filterId);
  }

  /// Get list of local .nosmai filters
  Future<List<NosmaiFilter>> getLocalFilters() async {
    _checkInitialized();
    final List<dynamic> filters =
        await NosmaiFlutterPlatform.instance.getLocalFilters();
    return filters
        .map((filter) =>
            NosmaiFilter.fromMap(Map<String, dynamic>.from(filter)))
        .toList();
  }

  /// Fetch filters and effects from all sources
  Future<List<NosmaiFilter>> fetchFiltersAndEffectsFromAllSources() async {
    _checkInitialized();
    final List<dynamic> filters =
        await NosmaiFlutterPlatform.instance.getFilters();

    return filters.map((filter) {
      final filterMap = Map<String, dynamic>.from(filter);
      return NosmaiFilter.fromMap(filterMap);
    }).toList();
  }

  /// Get filters
  /// 
  /// Returns cached filters when available, otherwise fetches fresh data.
  /// 
  /// [forceRefresh] - Whether to force refresh the cache
  Future<List<NosmaiFilter>> getFilters({
    bool forceRefresh = false,
  }) async {
    const cacheValidityDuration = _defaultCacheValidityDuration;
    _checkInitialized();
    
    // Check if cache is valid and not forcing refresh
    if (!forceRefresh && _isCacheValid(cacheValidityDuration)) {
      return _cachedFilters!;
    }
    
    // Fetch fresh filters
    final filters = await fetchFiltersAndEffectsFromAllSources();
    
    // Update cache
    _updateFilterCache(filters);
    
    return filters;
  }

  /// Clear filter cache
  Future<void> clearCache() async {
    _cachedFilters = null;
    _lastCacheTime = null;
  }

  /// Configure filter cache settings
  /// 
  /// This method allows customization of the filter cache behavior.
  /// Note: This is a placeholder for future cache configuration options.
  Future<void> setCacheConfig(Map<String, dynamic> config) async {
    // Future implementation for cache configuration
    // Could include: max cache size, custom TTL per filter type, etc.
  }

  /// Check if the filter cache is still valid
  static bool _isCacheValid(Duration validityDuration) {
    return _cachedFilters != null && 
           _lastCacheTime != null && 
           DateTime.now().difference(_lastCacheTime!) < validityDuration;
  }

  /// Update the filter cache with new data
  static void _updateFilterCache(List<NosmaiFilter> filters) {
    _cachedFilters = filters;
    _lastCacheTime = DateTime.now();
  }

  /// Switch camera immediately (advanced)
  /// 
  /// Direct camera switch without throttling protection.
  /// Use switchCamera() instead for most cases.
  Future<void> switchCameraImmediate() async {
    _checkInitialized();
    
    try {
      final success = await NosmaiFlutterPlatform.instance.switchCamera();
      if (!success) {
        throw NosmaiError.camera(
          type: NosmaiErrorType.cameraSwitchFailed,
          message: 'Camera switch operation failed',
          details: 'The camera switch operation was unsuccessful',
        );
      }
    } on PlatformException catch (e) {
      throw NosmaiError.camera(
        type: _parseErrorType(e.code),
        message: e.message ?? 'Camera switch failed',
        details: e.details?.toString(),
      );
    } catch (e, stackTrace) {
      if (e is NosmaiError) rethrow;
      throw NosmaiError.general(
        type: NosmaiErrorType.cameraSwitchFailed,
        message: 'Failed to switch camera: ${e.toString()}',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Switch camera position
  /// 
  /// Switches between front and back camera with built-in protection against
  /// rapid switching that could cause crashes.
  /// 
  /// Returns true if camera switch was performed, false if ignored.
  Future<bool> switchCamera() async {
    const throttleDuration = Duration(milliseconds: 500);
    _checkInitialized();
    
    // Check if camera switching is in progress - silently ignore
    if (_isCameraSwitching) {
      return false;
    }
    
    // Check throttle timing - silently ignore rapid taps
    final now = DateTime.now();
    if (_lastSwitchTime != null && 
        now.difference(_lastSwitchTime!) < throttleDuration) {
      return false;
    }
    
    // Set switching state
    _isCameraSwitching = true;
    _lastSwitchTime = now;
    
    try {
      // Perform the camera switch
      await switchCameraImmediate();
      return true;
    } catch (e) {
      // Re-throw the actual camera switch error
      rethrow;
    } finally {
      // Always reset switching state
      _isCameraSwitching = false;
    }
  }

  /// Whether a camera switch operation is currently in progress
  static bool get isCameraSwitching => _isCameraSwitching;

  /// Remove all applied filters
  Future<void> removeAllFilters() async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.removeAllFilters();
  }

  /// Clean up and release all resources
  Future<void> cleanup() async {
    if (_isDisposed) return;

    _isDisposed = true;

    try {
      if (_isRecording) {
        await stopRecording().catchError((e) {
          return NosmaiRecordingResult(
              success: false, videoPath: null, duration: 0.0, fileSize: 0);
        });
      }

      if (_isProcessing) {
        await stopProcessing().catchError((e) {
          // Processing stop failed during cleanup
        });
      }

      if (_isInitialized) {
        await NosmaiFlutterPlatform.instance.cleanup().catchError((e) {
          // Platform cleanup failed during cleanup - ignore error
        });
      }

      _isInitialized = false;
      _isProcessing = false;
      _isRecording = false;
      _activeOperations.clear();

    } catch (e) {
      // Cleanup error ignored
    }
  }

  /// Start video recording
  Future<bool> startRecording() async {
    _checkInitialized();

    if (_isRecording) {
      return true;
    }

    final success =
        await _trackOperation(NosmaiFlutterPlatform.instance.startRecording());

    if (success) {
      _isRecording = true;
    }

    return success;
  }

  /// Stop video recording
  Future<NosmaiRecordingResult> stopRecording() async {
    _checkInitialized();

    if (!_isRecording) {
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

      // Recording stopped

      return recordingResult;
    } catch (e) {
      _isRecording = false;
      return NosmaiRecordingResult(
        success: false,
        duration: 0,
        fileSize: 0,
        error: e.toString(),
      );
    }
  }

  /// Capture photo with applied filters
  Future<NosmaiPhotoResult> capturePhoto() async {
    _checkInitialized();
    try {
      final result = await NosmaiFlutterPlatform.instance.capturePhoto();
      return NosmaiPhotoResult.fromMap(result);
    } catch (e) {
      _errorController?.add(NosmaiError.general(
        type: NosmaiErrorType.platformError,
        message: 'Failed to capture photo',
        details: e.toString(),
        originalError: e,
      ));
      return NosmaiPhotoResult(
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Detach camera view (for navigation cleanup)
  Future<void> detachCameraView() async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.detachCameraView();
  }

  /// Save image data to device gallery
  Future<Map<String, dynamic>> saveImageToGallery(List<int> imageData, {String? name}) async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.saveImageToGallery(imageData, name: name);
  }

  /// Save video file to device gallery
  Future<Map<String, dynamic>> saveVideoToGallery(String videoPath, {String? name}) async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.saveVideoToGallery(videoPath, name: name);
  }

  // Built-in Filter Methods
  /// Apply brightness filter
  Future<void> applySkinSmoothing(double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applySkinSmoothing(level);
  }

  /// Apply skin whitening filter
  Future<void> applySkinWhitening(double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applySkinWhitening(level);
  }

  /// Apply face slimming filter
  Future<void> applyFaceSlimming(double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyFaceSlimming(level);
  }

  /// Apply eye enlargement filter
  Future<void> applyEyeEnlargement(double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyEyeEnlargement(level);
  }

  /// Apply nose size filter
  Future<void> applyNoseSize(double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyNoseSize(level);
  }

  /// Apply brightness filter
  Future<void> applyBrightnessFilter(double brightness) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyBrightnessFilter(brightness);
  }

  /// Apply contrast filter
  Future<void> applyContrastFilter(double contrast) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyContrastFilter(contrast);
  }

  /// Apply RGB filter
  Future<void> applyRGBFilter({required double red, required double green, required double blue}) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyRGBFilter(red: red, green: green, blue: blue);
  }

  /// Apply sharpening filter
  Future<void> applySharpening(double level) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applySharpening(level);
  }

  /// Apply hue filter
  Future<void> applyHue(double hueAngle) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyHue(hueAngle);
  }

  /// Apply white balance filter
  Future<void> applyWhiteBalance({required double temperature, required double tint}) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.applyWhiteBalance(temperature: temperature, tint: tint);
  }

  /// Adjust HSB (Hue, Saturation, Brightness)
  Future<void> adjustHSB({required double hue, required double saturation, required double brightness}) async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.adjustHSB(hue: hue, saturation: saturation, brightness: brightness);
  }

  /// Reset HSB filter
  Future<void> resetHSBFilter() async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.resetHSBFilter();
  }

  /// Remove all built-in filters
  Future<void> removeBuiltInFilters() async {
    _checkInitialized();
    await NosmaiFlutterPlatform.instance.removeBuiltInFilters();
  }

  /// Check if beauty effects are enabled
  Future<bool> isBeautyEffectEnabled() async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.isBeautyEffectEnabled();
  }

  /// Check if this is a beauty filter (placeholder - needs implementation)
  Future<bool> isBeautyFilter() async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.isBeautyEffectEnabled();
  }

  /// Check if cloud filters are enabled/available
  Future<bool> isCloudFilterEnabled() async {
    _checkInitialized();
    return await NosmaiFlutterPlatform.instance.isCloudFilterEnabled();
  }

  /// Dispose of stream controllers and clean up all resources
  void dispose() {
    if (_isDisposed) return;

    _isDisposed = true;

    _performAsyncCleanup();

    _errorController?.close();
    _downloadProgressController?.close();
    _stateController?.close();
    _recordingProgressController?.close();

    _errorController = null;
    _downloadProgressController = null;
    _stateController = null;
    _recordingProgressController = null;
  }

  /// Internal async cleanup
  void _performAsyncCleanup() async {
    try {
      if (_isRecording) {
        await stopRecording().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            return NosmaiRecordingResult(
                success: false, duration: 0, fileSize: 0);
          },
        );
      }

      if (_isProcessing) {
        await stopProcessing().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
      }

      if (_isInitialized) {
        await NosmaiFlutterPlatform.instance.cleanup().timeout(
          const Duration(seconds: 5),
          onTimeout: () {},
        );
      }

      _isInitialized = false;
      _isProcessing = false;
      _isRecording = false;
      _activeOperations.clear();
    } catch (e) {
      // Cleanup error ignored
    }
  }

  /// Check if SDK is initialized and not disposed
  void _checkInitialized() {
    if (_isDisposed) {
      throw NosmaiError.general(
        type: NosmaiErrorType.stateError,
        message: 'NosmaiFlutter instance has been disposed',
        details: 'Call initWithLicense() again to reinitialize the SDK',
      );
    }
    if (!_isInitialized) {
      throw NosmaiError.general(
        type: NosmaiErrorType.sdkNotInitialized,
        message: 'NosmaiFlutter must be initialized before use',
        details: 'Call initWithLicense() first to initialize the SDK',
      );
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

  /// Helper function to parse error type from platform error code
  NosmaiErrorType _parseErrorType(String code) {
    switch (code.toUpperCase()) {
      case 'INVALID_LICENSE':
      case 'LICENSE_INVALID':
        return NosmaiErrorType.invalidLicense;
      case 'LICENSE_EXPIRED':
        return NosmaiErrorType.licenseExpired;
      case 'CAMERA_PERMISSION_DENIED':
        return NosmaiErrorType.cameraPermissionDenied;
      case 'CAMERA_UNAVAILABLE':
        return NosmaiErrorType.cameraUnavailable;
      case 'CAMERA_CONFIG_ERROR':
      case 'CAMERA_CONFIGURATION_FAILED':
        return NosmaiErrorType.cameraConfigurationFailed;
      case 'CAMERA_SWITCH_ERROR':
      case 'CAMERA_SWITCH_FAILED':
        return NosmaiErrorType.cameraSwitchFailed;
      case 'FILTER_NOT_FOUND':
        return NosmaiErrorType.filterNotFound;
      case 'FILTER_LOAD_ERROR':
        return NosmaiErrorType.filterLoadFailed;
      case 'FILTER_DOWNLOAD_ERROR':
        return NosmaiErrorType.filterDownloadFailed;
      case 'RECORDING_PERMISSION_DENIED':
        return NosmaiErrorType.recordingPermissionDenied;
      case 'RECORDING_STORAGE_FULL':
        return NosmaiErrorType.recordingStorageFull;
      case 'RECORDING_FAILED':
        return NosmaiErrorType.recordingWriteFailed;
      case 'RECORDING_IN_PROGRESS':
        return NosmaiErrorType.recordingInProgress;
      case 'NOT_INITIALIZED':
        return NosmaiErrorType.sdkNotInitialized;
      case 'OPERATION_TIMEOUT':
        return NosmaiErrorType.operationTimeout;
      case 'PLATFORM_ERROR':
        return NosmaiErrorType.platformError;
      case 'NETWORK_ERROR':
        return NosmaiErrorType.networkError;
      case 'INVALID_PARAMETER':
        return NosmaiErrorType.invalidParameter;
      default:
        return NosmaiErrorType.unknown;
    }
  }
}