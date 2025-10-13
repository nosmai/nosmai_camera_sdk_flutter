import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import '../types/enums.dart';
import 'method_channel.dart';

/// The interface that implementations of nosmai_camera_sdk must implement.
abstract class NosmaiFlutterPlatform extends PlatformInterface {
  /// Constructs a NosmaiFlutterPlatform.
  NosmaiFlutterPlatform() : super(token: _token);

  static final Object _token = Object();

  static NosmaiFlutterPlatform _instance = MethodChannelNosmaiFlutter();

  /// The default instance of [NosmaiFlutterPlatform] to use.
  static NosmaiFlutterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [NosmaiFlutterPlatform] when
  /// they register themselves.
  static set instance(NosmaiFlutterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Initialize the SDK with a license key
  Future<bool> initWithLicense(String licenseKey) {
    throw UnimplementedError('initWithLicense() has not been implemented.');
  }

  /// Configure camera with position and session preset
  Future<void> configureCamera({
    required NosmaiCameraPosition position,
    String? sessionPreset,
  }) {
    throw UnimplementedError('configureCamera() has not been implemented.');
  }

  /// Start video processing
  Future<void> startProcessing() {
    throw UnimplementedError('startProcessing() has not been implemented.');
  }

  /// Stop video processing
  Future<void> stopProcessing() {
    throw UnimplementedError('stopProcessing() has not been implemented.');
  }

  /// Switch camera between front and back
  Future<bool> switchCamera() {
    throw UnimplementedError('switchCamera() has not been implemented.');
  }

  /// Remove all applied filters
  Future<void> removeAllFilters() {
    throw UnimplementedError('removeAllFilters() has not been implemented.');
  }

  /// Set preview view (iOS only)
  Future<void> setPreviewView() {
    throw UnimplementedError('setPreviewView() has not been implemented.');
  }

  /// Cleanup resources
  Future<void> cleanup() {
    throw UnimplementedError('cleanup() has not been implemented.');
  }

  /// Get platform version
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  // New Advanced Features
  Future<bool> applyEffect(String effectPath) {
    throw UnimplementedError('applyEffect() has not been implemented.');
  }

  Future<List<dynamic>> getCloudFilters() {
    throw UnimplementedError('getCloudFilters() has not been implemented.');
  }

  Future<Map<String, dynamic>> downloadCloudFilter(String filterId) {
    throw UnimplementedError('downloadCloudFilter() has not been implemented.');
  }

  Future<List<dynamic>> getLocalFilters() {
    throw UnimplementedError('getLocalFilters() has not been implemented.');
  }

  Future<List<dynamic>> getFilters() {
    throw UnimplementedError('getFilters() has not been implemented.');
  }

  // Recording Features
  Future<bool> startRecording() {
    throw UnimplementedError('startRecording() has not been implemented.');
  }

  Future<Map<String, dynamic>> stopRecording() {
    throw UnimplementedError('stopRecording() has not been implemented.');
  }

  Future<bool> isRecording() {
    throw UnimplementedError('isRecording() has not been implemented.');
  }

  Future<double> getCurrentRecordingDuration() {
    throw UnimplementedError(
        'getCurrentRecordingDuration() has not been implemented.');
  }

  /// Capture photo with applied filters
  Future<Map<String, dynamic>> capturePhoto() {
    throw UnimplementedError('capturePhoto() has not been implemented.');
  }

  /// Save image data to device gallery
  Future<Map<String, dynamic>> saveImageToGallery(List<int> imageData,
      {String? name}) {
    throw UnimplementedError('saveImageToGallery() has not been implemented.');
  }

  /// Save video file to device gallery
  Future<Map<String, dynamic>> saveVideoToGallery(String videoPath,
      {String? name}) {
    throw UnimplementedError('saveVideoToGallery() has not been implemented.');
  }

  /// Clear native filter cache
  Future<void> clearFilterCache() {
    throw UnimplementedError('clearFilterCache() has not been implemented.');
  }

  /// Detach camera from current view (for navigation cleanup)
  Future<void> detachCameraView() {
    throw UnimplementedError('detachCameraView() has not been implemented.');
  }

  /// Reinitialize the preview (useful for navigation recovery)
  Future<void> reinitializePreview() {
    throw UnimplementedError('reinitializePreview() has not been implemented.');
  }

  // Built-in Filter Methods
  Future<void> applyBrightnessFilter(double brightness) {
    throw UnimplementedError(
        'applyBrightnessFilter() has not been implemented.');
  }

  Future<void> applyContrastFilter(double contrast) {
    throw UnimplementedError('applyContrastFilter() has not been implemented.');
  }

  Future<void> applyRGBFilter(
      {required double red, required double green, required double blue}) {
    throw UnimplementedError('applyRGBFilter() has not been implemented.');
  }

  Future<void> applyLipstick(double intensity) {
    throw UnimplementedError('applyLipstick() has not been implemented.');
  }

  Future<void> applyBlusher(double intensity) {
    throw UnimplementedError('applyBlusher() has not been implemented.');
  }

  Future<void> applySkinSmoothing(double level) {
    throw UnimplementedError('applySkinSmoothing() has not been implemented.');
  }

  Future<void> applySkinWhitening(double level) {
    throw UnimplementedError('applySkinWhitening() has not been implemented.');
  }

  Future<void> applyFaceSlimming(double level) {
    throw UnimplementedError('applyFaceSlimming() has not been implemented.');
  }

  Future<void> applyEyeEnlargement(double level) {
    throw UnimplementedError('applyEyeEnlargement() has not been implemented.');
  }

  Future<void> applyNoseSize(double level) {
    throw UnimplementedError('applyNoseSize() has not been implemented.');
  }

  Future<void> applySharpening(double level) {
    throw UnimplementedError('applySharpening() has not been implemented.');
  }

  Future<void> applyMakeupBlendLevel(String filterName, double level) {
    throw UnimplementedError(
        'applyMakeupBlendLevel() has not been implemented.');
  }

  Future<void> applyGrayscaleFilter() {
    throw UnimplementedError(
        'applyGrayscaleFilter() has not been implemented.');
  }

  Future<void> applyHue(double hueAngle) {
    throw UnimplementedError('applyHue() has not been implemented.');
  }

  Future<void> applyWhiteBalance(
      {required double temperature, required double tint}) {
    throw UnimplementedError('applyWhiteBalance() has not been implemented.');
  }

  Future<void> adjustHSB(
      {required double hue,
      required double saturation,
      required double brightness}) {
    throw UnimplementedError('adjustHSB() has not been implemented.');
  }

  Future<void> resetHSBFilter() {
    throw UnimplementedError('resetHSBFilter() has not been implemented.');
  }

  Future<void> removeBuiltInFilters() {
    throw UnimplementedError(
        'removeBuiltInFilters() has not been implemented.');
  }

  Future<void> removeBuiltInFilterByName(String filterName) {
    throw UnimplementedError(
        'removeBuiltInFilterByName() has not been implemented.');
  }

  // License feature availability methods
  Future<bool> isBeautyEffectEnabled() {
    throw UnimplementedError(
        'isBeautyEffectEnabled() has not been implemented.');
  }

  Future<bool> isCloudFilterEnabled() {
    throw UnimplementedError(
        'isCloudFilterEnabled() has not been implemented.');
  }

  // Flash and Torch Methods
  Future<bool> hasFlash() {
    throw UnimplementedError('hasFlash() has not been implemented.');
  }

  Future<bool> hasTorch() {
    throw UnimplementedError('hasTorch() has not been implemented.');
  }

  Future<bool> setFlashMode(NosmaiFlashMode flashMode) {
    throw UnimplementedError('setFlashMode() has not been implemented.');
  }

  Future<bool> setTorchMode(NosmaiTorchMode torchMode) {
    throw UnimplementedError('setTorchMode() has not been implemented.');
  }

  Future<NosmaiFlashMode> getFlashMode() {
    throw UnimplementedError('getFlashMode() has not been implemented.');
  }

  Future<NosmaiTorchMode> getTorchMode() {
    throw UnimplementedError('getTorchMode() has not been implemented.');
  }

  // Effect Parameter Control Methods
  /// Get all available parameters for the currently loaded effect
  Future<List<dynamic>> getEffectParameters() {
    throw UnimplementedError('getEffectParameters() has not been implemented.');
  }

  /// Get the current value of a specific parameter
  Future<double> getEffectParameterValue(String parameterName) {
    throw UnimplementedError(
        'getEffectParameterValue() has not been implemented.');
  }

  /// Set a float parameter value for the currently loaded effect
  Future<bool> setEffectParameter(String parameterName, double value) {
    throw UnimplementedError('setEffectParameter() has not been implemented.');
  }

  /// Set a string parameter value for the currently loaded effect
  Future<bool> setEffectParameterString(String parameterName, String value) {
    throw UnimplementedError(
        'setEffectParameterString() has not been implemented.');
  }

  // Android Texture-based preview helpers (no-ops on iOS)
  /// Create a native SurfaceTexture and return its textureId (Android only)
  Future<int?> createPreviewTexture({double? width, double? height}) {
    throw UnimplementedError(
        'createPreviewTexture() has not been implemented.');
  }

  /// Bind the Surface from the given textureId to the SDK renderer (Android only)
  Future<bool> setRenderSurface(int textureId,
      {required double width, required double height}) {
    throw UnimplementedError('setRenderSurface() has not been implemented.');
  }

  /// Clear the current render surface and release the texture (Android only)
  Future<void> clearRenderSurface(int textureId) {
    throw UnimplementedError('clearRenderSurface() has not been implemented.');
  }
}
