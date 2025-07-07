import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'nosmai_flutter_platform_interface.dart';
import 'nosmai_types.dart';

/// Camera state notifier for communication between platform and widgets
class CameraStateNotifier {
  static final CameraStateNotifier _instance = CameraStateNotifier._internal();
  static CameraStateNotifier get instance => _instance;
  CameraStateNotifier._internal();
  
  final List<Function()> _attachedCallbacks = [];
  final List<Function()> _detachedCallbacks = [];
  final List<Function()> _readyCallbacks = [];
  final List<Function()> _processingStoppedCallbacks = [];
  
  void addAttachedCallback(Function() callback) {
    _attachedCallbacks.add(callback);
  }
  
  void removeAttachedCallback(Function() callback) {
    _attachedCallbacks.remove(callback);
  }
  
  void addDetachedCallback(Function() callback) {
    _detachedCallbacks.add(callback);
  }
  
  void removeDetachedCallback(Function() callback) {
    _detachedCallbacks.remove(callback);
  }
  
  void addReadyCallback(Function() callback) {
    _readyCallbacks.add(callback);
  }
  
  void removeReadyCallback(Function() callback) {
    _readyCallbacks.remove(callback);
  }
  
  void addProcessingStoppedCallback(Function() callback) {
    _processingStoppedCallbacks.add(callback);
  }
  
  void removeProcessingStoppedCallback(Function() callback) {
    _processingStoppedCallbacks.remove(callback);
  }
  
  void notifyCameraAttached() {
    debugPrint('📷 Camera attached notification received');
    for (final callback in _attachedCallbacks) {
      try {
        callback();
      } catch (e) {
        debugPrint('Error in camera attached callback: $e');
      }
    }
  }
  
  void notifyCameraDetached() {
    debugPrint('📷 Camera detached notification received');
    for (final callback in _detachedCallbacks) {
      try {
        callback();
      } catch (e) {
        debugPrint('Error in camera detached callback: $e');
      }
    }
  }
  
  void notifyCameraReady() {
    debugPrint('📷 Camera ready notification received');
    for (final callback in _readyCallbacks) {
      try {
        callback();
      } catch (e) {
        debugPrint('Error in camera ready callback: $e');
      }
    }
  }
  
  void notifyCameraProcessingStopped() {
    debugPrint('📷 Camera processing stopped notification received');
    for (final callback in _processingStoppedCallbacks) {
      try {
        callback();
      } catch (e) {
        debugPrint('Error in camera processing stopped callback: $e');
      }
    }
  }
}


/// An implementation of [NosmaiFlutterPlatform] that uses method channels.
class MethodChannelNosmaiFlutter extends NosmaiFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('nosmai_flutter');

  /// Constructor that sets up method call handler for callbacks
  MethodChannelNosmaiFlutter() {
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  /// Handle method calls from native platform (callbacks)
  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onError':
        final Map<String, dynamic> args = Map<String, dynamic>.from(call.arguments);
        NosmaiError.fromMap(args);
        // This will be handled by the main NosmaiFlutter class
        break;
      case 'onDownloadProgress':
        final Map<String, dynamic> args = Map<String, dynamic>.from(call.arguments);
        NosmaiDownloadProgress.fromMap(args);
        // This will be handled by the main NosmaiFlutter class
        break;
      case 'onRecordingProgress':
        // This will be handled by the main NosmaiFlutter class
        break;
      case 'onStateChanged':
        // Handle SDK state changes
        break;
      case 'onCameraAttached':
        // Camera successfully attached - notify camera preview widgets
        CameraStateNotifier.instance.notifyCameraAttached();
        break;
      case 'onCameraDetached':
        // Camera detached - notify camera preview widgets
        CameraStateNotifier.instance.notifyCameraDetached();
        break;
      case 'onCameraReady':
        // Camera is ready for processing
        CameraStateNotifier.instance.notifyCameraReady();
        break;
      case 'onCameraProcessingStopped':
        // Camera processing stopped
        CameraStateNotifier.instance.notifyCameraProcessingStopped();
        break;
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<bool> initWithLicense(String licenseKey) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('initWithLicense', {
        'licenseKey': licenseKey,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error initializing Nosmai SDK: $e');
      return false;
    }
  }

  @override
  Future<void> configureCamera({
    required NosmaiCameraPosition position,
    String? sessionPreset,
  }) async {
    try {
      await methodChannel.invokeMethod('configureCamera', {
        'position': position.name,
        'sessionPreset': sessionPreset ?? 'AVCaptureSessionPresetHigh',
      });
    } catch (e) {
      debugPrint('Error configuring camera: $e');
      rethrow;
    }
  }

  @override
  Future<void> startProcessing() async {
    try {
      await methodChannel.invokeMethod('startProcessing');
    } catch (e) {
      debugPrint('Error starting processing: $e');
      rethrow;
    }
  }

  @override
  Future<void> stopProcessing() async {
    try {
      await methodChannel.invokeMethod('stopProcessing');
    } catch (e) {
      debugPrint('Error stopping processing: $e');
      rethrow;
    }
  }








  @override
  Future<bool> loadNosmaiFilter(String filePath) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('loadNosmaiFilter', {
        'filePath': filePath,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error loading Nosmai filter: $e');
      return false;
    }
  }

  @override
  Future<bool> switchCamera() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('switchCamera');
      return result ?? false;
    } catch (e) {
      debugPrint('Error switching camera: $e');
      return false;
    }
  }

  @override
  Future<void> setFaceDetectionEnabled(bool enable) async {
    try {
      await methodChannel.invokeMethod('setFaceDetectionEnabled', {
        'enable': enable,
      });
    } catch (e) {
      debugPrint('Error setting face detection: $e');
      rethrow;
    }
  }

  @override
  Future<void> removeAllFilters() async {
    try {
      await methodChannel.invokeMethod('removeAllFilters');
    } catch (e) {
      debugPrint('Error removing all filters: $e');
      rethrow;
    }
  }

  @override
  Future<void> setPreviewView() async {
    try {
      await methodChannel.invokeMethod('setPreviewView');
    } catch (e) {
      debugPrint('Error setting preview view: $e');
      rethrow;
    }
  }

  @override
  Future<void> cleanup() async {
    try {
      await methodChannel.invokeMethod('cleanup');
    } catch (e) {
      debugPrint('Error cleaning up: $e');
      rethrow;
    }
  }

  // New Advanced Features Implementation
  @override
  Future<bool> applyEffect(String effectPath) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('applyEffect', {
        'effectPath': effectPath,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error applying effect: $e');
      return false;
    }
  }

  @override
  Future<List<dynamic>> getCloudFilters() async {
    try {
      final result = await methodChannel.invokeMethod<List<dynamic>>('getCloudFilters');
      return result ?? [];
    } catch (e) {
      debugPrint('Error getting cloud filters: $e');
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>> downloadCloudFilter(String filterId) async {
    try {
      final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('downloadCloudFilter', {
        'filterId': filterId,
      });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Error downloading cloud filter: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  @override
  Future<List<dynamic>> getLocalFilters() async {
    try {
      final result = await methodChannel.invokeMethod<List<dynamic>>('getLocalFilters');
      return result ?? [];
    } catch (e) {
      debugPrint('Error getting local filters: $e');
      return [];
    }
  }

  @override
  Future<List<dynamic>> getFilters() async {
    try {
      final result = await methodChannel.invokeMethod<List<dynamic>>('getFilters');
      return result ?? [];
    } catch (e) {
      debugPrint('Error getting filters: $e');
      return [];
    }
  }

  @override
  Future<List<dynamic>> getEffectParameters() async {
    try {
      final result = await methodChannel.invokeMethod<List<dynamic>>('getEffectParameters');
      return result ?? [];
    } catch (e) {
      debugPrint('Error getting effect parameters: $e');
      return [];
    }
  }

  @override
  Future<bool> setEffectParameter(String parameterName, double value) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('setEffectParameter', {
        'parameterName': parameterName,
        'value': value,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('Error setting effect parameter: $e');
      return false;
    }
  }

  // Recording Features Implementation
  @override
  Future<bool> startRecording() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('startRecording');
      return result ?? false;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> stopRecording() async {
    try {
      final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('stopRecording');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  @override
  Future<bool> isRecording() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('isRecording');
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking recording status: $e');
      return false;
    }
  }

  @override
  Future<double> getCurrentRecordingDuration() async {
    try {
      final result = await methodChannel.invokeMethod<double>('getCurrentRecordingDuration');
      return result ?? 0.0;
    } catch (e) {
      debugPrint('Error getting recording duration: $e');
      return 0.0;
    }
  }


  @override
  Future<Map<String, dynamic>> capturePhoto() async {
    try {
      final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('capturePhoto');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Error capturing photo: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  @override
  Future<Map<String, dynamic>> saveImageToGallery(List<int> imageData, {String? name}) async {
    try {
      final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('saveImageToGallery', {
        'imageData': Uint8List.fromList(imageData),
        'name': name ?? 'nosmai_photo_${DateTime.now().millisecondsSinceEpoch}',
      });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Error saving image to gallery: $e');
      return {'isSuccess': false, 'error': e.toString()};
    }
  }

  @override
  Future<Map<String, dynamic>> saveVideoToGallery(String videoPath, {String? name}) async {
    try {
      final result = await methodChannel.invokeMethod<Map<dynamic, dynamic>>('saveVideoToGallery', {
        'videoPath': videoPath,
        'name': name ?? 'nosmai_video_${DateTime.now().millisecondsSinceEpoch}',
      });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      debugPrint('Error saving video to gallery: $e');
      return {'isSuccess': false, 'error': e.toString()};
    }
  }

  @override
  Future<void> clearFilterCache() async {
    try {
      await methodChannel.invokeMethod('clearFilterCache');
    } catch (e) {
      debugPrint('Error clearing filter cache: $e');
      rethrow;
    }
  }

  @override
  Future<void> detachCameraView() async {
    try {
      await methodChannel.invokeMethod('detachCameraView');
    } catch (e) {
      debugPrint('Error detaching camera view: $e');
      rethrow;
    }
  }

  // Built-in Filter Methods Implementation
  @override
  Future<void> applyBrightnessFilter(double brightness) async {
    try {
      await methodChannel.invokeMethod('applyBrightnessFilter', {
        'brightness': brightness,
      });
    } catch (e) {
      debugPrint('Error applying brightness filter: $e');
      rethrow;
    }
  }

  @override
  Future<void> applyContrastFilter(double contrast) async {
    try {
      await methodChannel.invokeMethod('applyContrastFilter', {
        'contrast': contrast,
      });
    } catch (e) {
      debugPrint('Error applying contrast filter: $e');
      rethrow;
    }
  }

  @override
  Future<void> applyRGBFilter({required double red, required double green, required double blue}) async {
    try {
      await methodChannel.invokeMethod('applyRGBFilter', {
        'red': red,
        'green': green,
        'blue': blue,
      });
    } catch (e) {
      debugPrint('Error applying RGB filter: $e');
      rethrow;
    }
  }

  @override
  Future<void> applySkinSmoothing(double level) async {
    try {
      await methodChannel.invokeMethod('applySkinSmoothing', {
        'level': level,
      });
    } catch (e) {
      debugPrint('Error applying skin smoothing: $e');
      rethrow;
    }
  }

  @override
  Future<void> applySkinWhitening(double level) async {
    try {
      await methodChannel.invokeMethod('applySkinWhitening', {
        'level': level,
      });
    } catch (e) {
      debugPrint('Error applying skin whitening: $e');
      rethrow;
    }
  }

  @override
  Future<void> applyFaceSlimming(double level) async {
    try {
      await methodChannel.invokeMethod('applyFaceSlimming', {
        'level': level,
      });
    } catch (e) {
      debugPrint('Error applying face slimming: $e');
      rethrow;
    }
  }

  @override
  Future<void> applyEyeEnlargement(double level) async {
    try {
      await methodChannel.invokeMethod('applyEyeEnlargement', {
        'level': level,
      });
    } catch (e) {
      debugPrint('Error applying eye enlargement: $e');
      rethrow;
    }
  }

  @override
  Future<void> applyNoseSize(double level) async {
    try {
      await methodChannel.invokeMethod('applyNoseSize', {
        'level': level,
      });
    } catch (e) {
      debugPrint('Error applying nose size: $e');
      rethrow;
    }
  }

  @override
  Future<void> applySharpening(double level) async {
    try {
      await methodChannel.invokeMethod('applySharpening', {
        'level': level,
      });
    } catch (e) {
      debugPrint('Error applying sharpening: $e');
      rethrow;
    }
  }

  @override
  Future<void> applyMakeupBlendLevel(String filterName, double level) async {
    try {
      await methodChannel.invokeMethod('applyMakeupBlendLevel', {
        'filterName': filterName,
        'level': level,
      });
    } catch (e) {
      debugPrint('Error applying makeup blend level: $e');
      rethrow;
    }
  }

  @override
  Future<void> applyGrayscaleFilter() async {
    try {
      await methodChannel.invokeMethod('applyGrayscaleFilter');
    } catch (e) {
      debugPrint('Error applying grayscale filter: $e');
      rethrow;
    }
  }

  @override
  Future<void> applyHue(double hueAngle) async {
    try {
      await methodChannel.invokeMethod('applyHue', {
        'hueAngle': hueAngle,
      });
    } catch (e) {
      debugPrint('Error applying hue: $e');
      rethrow;
    }
  }


  @override
  Future<void> applyWhiteBalance({required double temperature, required double tint}) async {
    try {
      await methodChannel.invokeMethod('applyWhiteBalance', {
        'temperature': temperature,
        'tint': tint,
      });
    } catch (e) {
      debugPrint('Error applying white balance: $e');
      rethrow;
    }
  }


  @override
  Future<void> adjustHSB({required double hue, required double saturation, required double brightness}) async {
    try {
      await methodChannel.invokeMethod('adjustHSB', {
        'hue': hue,
        'saturation': saturation,
        'brightness': brightness,
      });
    } catch (e) {
      debugPrint('Error adjusting HSB: $e');
      rethrow;
    }
  }

  @override
  Future<void> resetHSBFilter() async {
    try {
      await methodChannel.invokeMethod('resetHSBFilter');
    } catch (e) {
      debugPrint('Error resetting HSB filter: $e');
      rethrow;
    }
  }

  @override
  Future<void> removeBuiltInFilters() async {
    try {
      await methodChannel.invokeMethod('removeBuiltInFilters');
    } catch (e) {
      debugPrint('Error removing built-in filters: $e');
      rethrow;
    }
  }

  @override
  Future<void> removeBuiltInFilterByName(String filterName) async {
    try {
      await methodChannel.invokeMethod('removeBuiltInFilterByName', {
        'filterName': filterName,
      });
    } catch (e) {
      debugPrint('Error removing built-in filter by name: $e');
      rethrow;
    }
  }

  @override
  Future<List<dynamic>> getInitialFilters() async {
    try {
      final result = await methodChannel.invokeMethod<List<dynamic>>('getInitialFilters');
      return result ?? [];
    } catch (e) {
      debugPrint('Error getting initial filters: $e');
      return [];
    }
  }

  @override
  Future<void> fetchCloudFilters() async {
    try {
      await methodChannel.invokeMethod('fetchCloudFilters');
    } catch (e) {
      debugPrint('Error fetching cloud filters: $e');
      rethrow;
    }
  }

  @override
  Future<bool> isBeautyEffectEnabled() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('isBeautyEffectEnabled');
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking beauty effect availability: $e');
      return false;
    }
  }

  @override
  Future<bool> isCloudFilterEnabled() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('isCloudFilterEnabled');
      return result ?? false;
    } catch (e) {
      debugPrint('Error checking cloud filter availability: $e');
      return false;
    }
  }
}