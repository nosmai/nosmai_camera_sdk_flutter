import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../types/enums.dart';
import '../types/models.dart';
import '../types/errors.dart';
import 'platform_interface.dart';

/// Internal camera state notifier for communication between platform and widgets
class CameraStateNotifierImpl {
  static final CameraStateNotifierImpl _instance =
      CameraStateNotifierImpl._internal();
  static CameraStateNotifierImpl get instance => _instance;
  CameraStateNotifierImpl._internal();

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
    for (final callback in _attachedCallbacks) {
      try {
        callback();
      } catch (e) {
        // Error in camera attached callback - continue with other callbacks
      }
    }
  }

  void notifyCameraDetached() {
    for (final callback in _detachedCallbacks) {
      try {
        callback();
      } catch (e) {
        // Error in camera detached callback - continue with other callbacks
      }
    }
  }

  void notifyCameraReady() {
    for (final callback in _readyCallbacks) {
      try {
        callback();
      } catch (e) {
        // Error in camera ready callback - continue with other callbacks
      }
    }
  }

  void notifyCameraProcessingStopped() {
    for (final callback in _processingStoppedCallbacks) {
      try {
        callback();
      } catch (e) {
        // Error in camera processing stopped callback - continue with other callbacks
      }
    }
  }
}

/// Expose camera state notifier for use in other files
class CameraStateNotifier {
  static CameraStateNotifierImpl get instance =>
      CameraStateNotifierImpl.instance;
}

/// An implementation of [NosmaiFlutterPlatform] that uses method channels.
class MethodChannelNosmaiFlutter extends NosmaiFlutterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('nosmai_camera_sdk');

  /// Constructor that sets up method call handler for callbacks
  MethodChannelNosmaiFlutter() {
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  /// Handle method calls from native platform (callbacks)
  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onError':
        final Map<String, dynamic> args =
            Map<String, dynamic>.from(call.arguments);
        NosmaiError.fromMap(args);
        // This will be handled by the main NosmaiFlutter class
        break;
      case 'onDownloadProgress':
        final Map<String, dynamic> args =
            Map<String, dynamic>.from(call.arguments);
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
        CameraStateNotifierImpl.instance.notifyCameraAttached();
        break;
      case 'onCameraDetached':
        // Camera detached - notify camera preview widgets
        CameraStateNotifierImpl.instance.notifyCameraDetached();
        break;
      case 'onCameraReady':
        // Camera is ready for processing
        CameraStateNotifierImpl.instance.notifyCameraReady();
        break;
      case 'onCameraProcessingStopped':
        // Camera processing stopped
        CameraStateNotifierImpl.instance.notifyCameraProcessingStopped();
        break;
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version =
        await methodChannel.invokeMethod<String>('getPlatformVersion');
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
      rethrow;
    }
  }

  @override
  Future<void> startProcessing() async {
    try {
      await methodChannel.invokeMethod('startProcessing');
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> stopProcessing() async {
    try {
      await methodChannel.invokeMethod('stopProcessing');
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<bool> switchCamera() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('switchCamera');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> removeAllFilters() async {
    try {
      await methodChannel.invokeMethod('removeAllFilters');
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> setPreviewView() async {
    try {
      await methodChannel.invokeMethod('setPreviewView');
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> cleanup() async {
    try {
      await methodChannel.invokeMethod('cleanup');
    } catch (e) {
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
      return false;
    }
  }

  @override
  Future<List<dynamic>> getCloudFilters() async {
    try {
      final result =
          await methodChannel.invokeMethod<List<dynamic>>('getCloudFilters');
      return result ?? [];
    } catch (e) {
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>> downloadCloudFilter(String filterId) async {
    try {
      final result = await methodChannel
          .invokeMethod<Map<dynamic, dynamic>>('downloadCloudFilter', {
        'filterId': filterId,
      });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  @override
  Future<List<dynamic>> getLocalFilters() async {
    try {
      final result =
          await methodChannel.invokeMethod<List<dynamic>>('getLocalFilters');
      return result ?? [];
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<dynamic>> getFilters() async {
    try {
      final result =
          await methodChannel.invokeMethod<List<dynamic>>('getFilters');
      return result ?? [];
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<dynamic>> getEffectParameters() async {
    try {
      final result = await methodChannel
          .invokeMethod<List<dynamic>>('getEffectParameters');
      return result ?? [];
    } catch (e) {
      return [];
    }
  }

  @override
  Future<bool> setEffectParameter(String parameterName, double value) async {
    try {
      final result =
          await methodChannel.invokeMethod<bool>('setEffectParameter', {
        'parameterName': parameterName,
        'value': value,
      });
      return result ?? false;
    } catch (e) {
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
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> stopRecording() async {
    try {
      final result = await methodChannel
          .invokeMethod<Map<dynamic, dynamic>>('stopRecording');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  @override
  Future<bool> isRecording() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('isRecording');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<double> getCurrentRecordingDuration() async {
    try {
      final result = await methodChannel
          .invokeMethod<double>('getCurrentRecordingDuration');
      return result ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  @override
  Future<Map<String, dynamic>> capturePhoto() async {
    try {
      final result = await methodChannel
          .invokeMethod<Map<dynamic, dynamic>>('capturePhoto');
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  @override
  Future<Map<String, dynamic>> saveImageToGallery(List<int> imageData,
      {String? name}) async {
    try {
      final result = await methodChannel
          .invokeMethod<Map<dynamic, dynamic>>('saveImageToGallery', {
        'imageData': Uint8List.fromList(imageData),
        'name': name ?? 'nosmai_photo_${DateTime.now().millisecondsSinceEpoch}',
      });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      return {'isSuccess': false, 'error': e.toString()};
    }
  }

  @override
  Future<Map<String, dynamic>> saveVideoToGallery(String videoPath,
      {String? name}) async {
    try {
      final result = await methodChannel
          .invokeMethod<Map<dynamic, dynamic>>('saveVideoToGallery', {
        'videoPath': videoPath,
        'name': name ?? 'nosmai_video_${DateTime.now().millisecondsSinceEpoch}',
      });
      return Map<String, dynamic>.from(result ?? {});
    } catch (e) {
      return {'isSuccess': false, 'error': e.toString()};
    }
  }

  @override
  Future<void> clearFilterCache() async {
    try {
      await methodChannel.invokeMethod('clearFilterCache');
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> detachCameraView() async {
    try {
      await methodChannel.invokeMethod('detachCameraView');
    } catch (e) {
      rethrow;
    }
  }
  
  @override
  Future<void> reinitializePreview() async {
    try {
      await methodChannel.invokeMethod('reinitializePreview');
    } catch (e) {
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
      rethrow;
    }
  }

  @override
  Future<void> applyRGBFilter(
      {required double red,
      required double green,
      required double blue}) async {
    try {
      await methodChannel.invokeMethod('applyRGBFilter', {
        'red': red,
        'green': green,
        'blue': blue,
      });
    } catch (e) {
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
      rethrow;
    }
  }

  @override
  Future<void> applyGrayscaleFilter() async {
    try {
      await methodChannel.invokeMethod('applyGrayscaleFilter');
    } catch (e) {
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
      rethrow;
    }
  }

  @override
  Future<void> applyWhiteBalance(
      {required double temperature, required double tint}) async {
    try {
      await methodChannel.invokeMethod('applyWhiteBalance', {
        'temperature': temperature,
        'tint': tint,
      });
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> adjustHSB(
      {required double hue,
      required double saturation,
      required double brightness}) async {
    try {
      await methodChannel.invokeMethod('adjustHSB', {
        'hue': hue,
        'saturation': saturation,
        'brightness': brightness,
      });
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> resetHSBFilter() async {
    try {
      await methodChannel.invokeMethod('resetHSBFilter');
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> removeBuiltInFilters() async {
    try {
      await methodChannel.invokeMethod('removeBuiltInFilters');
    } catch (e) {
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
      rethrow;
    }
  }

  @override
  Future<bool> isBeautyEffectEnabled() async {
    try {
      final result =
          await methodChannel.invokeMethod<bool>('isBeautyEffectEnabled');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> isCloudFilterEnabled() async {
    try {
      final result =
          await methodChannel.invokeMethod<bool>('isCloudFilterEnabled');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // Flash and Torch Methods
  @override
  Future<bool> hasFlash() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('hasFlash');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> hasTorch() async {
    try {
      final result = await methodChannel.invokeMethod<bool>('hasTorch');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> setFlashMode(NosmaiFlashMode flashMode) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('setFlashMode', {
        'flashMode': flashMode.name,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> setTorchMode(NosmaiTorchMode torchMode) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('setTorchMode', {
        'torchMode': torchMode.name,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<NosmaiFlashMode> getFlashMode() async {
    try {
      final result = await methodChannel.invokeMethod<String>('getFlashMode');
      switch (result) {
        case 'on':
          return NosmaiFlashMode.on;
        case 'auto':
          return NosmaiFlashMode.auto;
        case 'off':
        default:
          return NosmaiFlashMode.off;
      }
    } catch (e) {
      return NosmaiFlashMode.off;
    }
  }

  @override
  Future<NosmaiTorchMode> getTorchMode() async {
    try {
      final result = await methodChannel.invokeMethod<String>('getTorchMode');
      switch (result) {
        case 'on':
          return NosmaiTorchMode.on;
        case 'auto':
          return NosmaiTorchMode.auto;
        case 'off':
        default:
          return NosmaiTorchMode.off;
      }
    } catch (e) {
      return NosmaiTorchMode.off;
    }
  }

  // Android Texture-based preview helpers
  @override
  Future<int?> createPreviewTexture({double? width, double? height}) async {
    try {
      final result = await methodChannel.invokeMethod<int>('createTexture', {
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      });
      return result;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<bool> setRenderSurface(int textureId,
      {required double width, required double height}) async {
    try {
      final result = await methodChannel.invokeMethod<bool>('setRenderSurface', {
        'textureId': textureId,
        'width': width,
        'height': height,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> clearRenderSurface(int textureId) async {
    try {
      await methodChannel.invokeMethod('clearRenderSurface', {
        'textureId': textureId,
      });
    } catch (_) {}
  }
}
