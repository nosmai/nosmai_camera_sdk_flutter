import 'package:flutter/widgets.dart';
import 'nosmai_flutter.dart';

/// Simple mixin for managing Nosmai camera lifecycle in Flutter screens
///
/// This mixin handles proper camera initialization and cleanup.
/// Use this mixin in your camera screen's State class to ensure smooth camera operations.
///
/// Example usage:
/// ```dart
/// class CameraScreenState extends State<CameraScreen>
///     with NosmaiCameraLifecycleMixin {
///
///   @override
///   Widget build(BuildContext context) {
///     return Scaffold(
///       appBar: AppBar(
///         leading: IconButton(
///           icon: Icon(Icons.arrow_back),
///           onPressed: () async {
///             await cleanupBeforeNavigation();
///             Navigator.pop(context);
///           },
///         ),
///       ),
///       body: NosmaiCameraPreview(
///         onInitialized: onCameraInitialized,
///         onError: onCameraError,
///       ),
///     );
///   }
/// }
/// ```
mixin NosmaiCameraLifecycleMixin<T extends StatefulWidget> on State<T> {
  late final NosmaiFlutter _nosmaiFlutter;
  bool _isScreenActive = true;

  @override
  void initState() {
    super.initState();
    _nosmaiFlutter = NosmaiFlutter.instance;
    _isScreenActive = true;

    debugPrint('📱 Camera screen initialized');
  }

  @override
  void dispose() {
    _cleanupOnDispose();
    super.dispose();
  }

  /// Called when the camera is successfully initialized
  void onCameraInitialized() {
    debugPrint('✅ Camera initialized callback');
  }

  /// Called when the camera encounters an error
  void onCameraError(String error) {
    debugPrint('❌ Camera error callback: $error');
  }

  /// Call this method before navigating away from the camera screen
  Future<void> cleanupBeforeNavigation() async {
    if (!_isScreenActive) return;

    _isScreenActive = false;

    debugPrint('🔄 Cleanup before navigation');

    try {
      // Detach camera view gracefully
      if (_nosmaiFlutter.isInitialized) {
        await _nosmaiFlutter.detachCameraView();

        // Stop processing if still active
        if (_nosmaiFlutter.isProcessing) {
          await _nosmaiFlutter.stopProcessing();
        }
      }

      debugPrint('✅ Navigation cleanup completed');
    } catch (e) {
      debugPrint('⚠️ Error during navigation cleanup: $e');
    }
  }

  /// Cleanup when screen is disposed
  void _cleanupOnDispose() async {
    if (!_isScreenActive) return;

    _isScreenActive = false;

    debugPrint('🗑️ Cleaning up camera screen resources');

    try {
      // Detach camera view gracefully
      if (_nosmaiFlutter.isInitialized) {
        await _nosmaiFlutter.detachCameraView();

        // Stop processing if still active
        if (_nosmaiFlutter.isProcessing) {
          await _nosmaiFlutter.stopProcessing();
        }
      }

      debugPrint('✅ Camera screen cleanup completed');
    } catch (e) {
      debugPrint('⚠️ Error during camera screen cleanup: $e');
    }
  }

  /// Get current camera state
  bool get isScreenActive => _isScreenActive;
}
