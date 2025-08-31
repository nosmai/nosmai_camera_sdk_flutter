import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../nosmai_camera_sdk.dart';

class NosmaiCameraPreview extends StatefulWidget {
  const NosmaiCameraPreview({
    super.key,
    this.width,
    this.height,
    this.onInitialized,
    this.onError,
    this.controller,
  });

  final double? width;
  final double? height;
  final VoidCallback? onInitialized;
  final Function(String error)? onError;
  final NosmaiCameraPreviewController? controller;

  @override
  State<NosmaiCameraPreview> createState() => _NosmaiCameraPreviewState();
}

class NosmaiCameraPreviewController {
  _NosmaiCameraPreviewState? _state;

  void _attach(_NosmaiCameraPreviewState state) {
    _state = state;
  }

  void _detach() {
    _state = null;
  }

  /// Manually reinitialize the camera preview
  Future<void> reinitialize() async {
    await _state?.reinitialize();
  }

  /// Check if camera is currently initializing
  bool get isInitializing => _state?._isInitializing ?? false;

  /// Check if camera is initialized
  bool get isInitialized => _state?._isInitialized ?? false;

  /// Get current error if any
  String? get currentError => _state?._initError;
}

class _NosmaiCameraPreviewState extends State<NosmaiCameraPreview>
    with WidgetsBindingObserver {
  bool _isInitializing = false;
  bool _isInitialized = false;
  String? _initError;
  late final NosmaiFlutter _nosmaiFlutter;
  static int _viewCounter = 0;
  late final String _viewKey;

  @override
  void initState() {
    super.initState();
    _nosmaiFlutter = NosmaiFlutter.instance;
    WidgetsBinding.instance.addObserver(this);

    // Create unique view key for this instance
    _viewKey = 'nosmai_camera_${++_viewCounter}';

    // Attach controller if provided
    widget.controller?._attach(this);

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Delay to ensure widget is fully mounted and context is ready
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initializeAndroidTexturePreview();
        }
      });
    } else {
      // Camera is pre-warmed, set as initialized immediately for iOS
      _isInitialized = true;
      _isInitializing = false;
      widget.onInitialized?.call();
    }
  }

  @override
  void dispose() {
    // Detach controller
    widget.controller?._detach();

    // Cleanup
    WidgetsBinding.instance.removeObserver(this);

    // Cleanup camera view
    _cleanupOnDispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isInitialized) return;

    switch (state) {
      case AppLifecycleState.paused:
        // App is going to background - stop processing but keep SDK initialized
        _pauseCamera();
        break;
      case AppLifecycleState.resumed:
        // App is back to foreground - resume processing
        _resumeCamera();
        break;
      case AppLifecycleState.detached:
        // App is being terminated - cleanup camera
        _cleanupOnDispose();
        break;
      default:
        break;
    }
  }

  Future<void> _pauseCamera() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Best-effort stop on Android (no-op if not implemented)
        if (_isInitialized && _nosmaiFlutter.isProcessing) {
          await _nosmaiFlutter.stopProcessing();
        }
      } else if (_isInitialized && _nosmaiFlutter.isProcessing) {
        await _nosmaiFlutter.stopProcessing();
      }
    } catch (e) {
      // Ignore camera pause errors
    }
  }

  Future<void> _resumeCamera() async {
    try {
      if (_isInitialized && !_nosmaiFlutter.isProcessing) {
        await _nosmaiFlutter.startProcessing();
      }
    } catch (e) {
      // If resume fails, camera is still pre-warmed, just reset state
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _cleanupCamera() async {
    try {
      // Stop processing if active
      if (_nosmaiFlutter.isProcessing) {
        await _nosmaiFlutter.stopProcessing();
      }

      // Detach camera view
      await _nosmaiFlutter.detachCameraView();

      // Brief delay for cleanup
      await Future.delayed(const Duration(milliseconds: 200));

      // Reset state if mounted
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _isInitializing = false;
        });
      }
    }
  }

  /// Cleanup camera view on dispose
  void _cleanupOnDispose() {
    try {
      // On Android: prefer soft-detach (stop camera feed) and keep GL/render surface intact
      if (defaultTargetPlatform == TargetPlatform.android) {
        _nosmaiFlutter.detachCameraView().catchError((_) {});
      } else {
        // iOS path unchanged
        _nosmaiFlutter.detachCameraView().catchError((_) {});
      }
    } catch (e) {
      // Ignore disposal errors
    }
  }

  /// Manually reinitialize the camera (useful for error recovery)
  Future<void> reinitialize() async {
    // Force cleanup
    await _cleanupCamera();

    // Longer delay to ensure everything is cleaned up
    await Future.delayed(const Duration(milliseconds: 1000));

    if (defaultTargetPlatform == TargetPlatform.android) {
      // AndroidView path: minimal delay and mark initialized
      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isInitializing = false;
          _initError = null;
        });
      }
      widget.onInitialized?.call();
    } else {
      // Force reset to initialized state (camera is pre-warmed) on iOS
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isInitializing = false;
          _initError = null;
        });
      }
      widget.onInitialized?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Use AndroidView-based preview to avoid EGL races with Flutter Texture
      final mediaQuery = MediaQuery.of(context);
      final screenSize = mediaQuery.size;
      final screenWidth = screenSize.width;
      final screenHeight = screenSize.height;

      return MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        removeLeft: true,
        removeRight: true,
        child: SizedBox(
          width: widget.width ?? screenWidth,
          height: widget.height ?? screenHeight,
          child: AndroidView(
            viewType: 'nosmai_camera_preview',
            layoutDirection: TextDirection.ltr,
            creationParams: <String, dynamic>{
              'width': screenWidth,
              'height': screenHeight,
            },
            creationParamsCodec: const StandardMessageCodec(),
          ),
        ),
      );
    }

    // Show error state
    if (_initError != null) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: const Color(0xFF000000),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Camera Error',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _initError!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: reinitialize,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Show camera preview - force full screen dimensions including notch and bottom
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final padding = mediaQuery.padding;

    // Use device screen bounds directly for full-screen coverage
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      removeLeft: true,
      removeRight: true,
      child: ClipRect(
        child: OverflowBox(
          minWidth: screenWidth,
          maxWidth: screenWidth,
          minHeight: screenHeight,
          maxHeight: screenHeight,
          child: SizedBox(
            width: screenWidth,
            height: screenHeight,
            child: UiKitView(
              key: ValueKey(_viewKey), // Unique key for this view instance
              viewType: 'nosmai_camera_preview',
              layoutDirection: TextDirection.ltr,
              creationParams: <String, dynamic>{
                'width': screenWidth,
                'height': screenHeight,
                'deviceType': _getDeviceType(),
                'safeAreaTop': padding.top,
                'safeAreaBottom': padding.bottom,
              },
              creationParamsCodec: const StandardMessageCodec(),
            ),
          ),
        ),
      ),
    );
  }

  /// Get device type information for native side
  String _getDeviceType() {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final padding = mediaQuery.padding;

    // Include safe area information
    final hasNotch =
        padding.top > 24; // Devices with notch typically have padding > 24
    final hasBottomSafeArea = padding.bottom > 0;

    // Determine device type based on screen dimensions
    String deviceType;
    if (screenWidth >= 1024 || screenHeight >= 1024) {
      deviceType = 'tablet';
    } else if (screenWidth >= 768 || screenHeight >= 768) {
      deviceType = 'large_phone';
    } else {
      deviceType = 'phone';
    }

    // Add safe area info for iOS layout
    if (hasNotch) {
      deviceType += '_notch';
    }
    if (hasBottomSafeArea) {
      deviceType += '_bottom';
    }

    return deviceType;
  }

  Future<void> _initializeAndroidTexturePreview() async {
    // Migrate to AndroidView path: just mark initialized after small delay
    setState(() {
      _isInitializing = true;
      _initError = null;
    });
    await Future.delayed(const Duration(milliseconds: 50));
    if (mounted) {
      setState(() {
        _isInitialized = true;
        _isInitializing = false;
      });
    }
    widget.onInitialized?.call();
  }
}
