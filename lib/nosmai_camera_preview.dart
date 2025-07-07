import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'nosmai_flutter.dart';

/// A widget that displays the Nosmai camera preview with proper lifecycle management
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

/// Camera preview controller for programmatic control
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

  @override
  void initState() {
    super.initState();
    _nosmaiFlutter = NosmaiFlutter.instance;
    WidgetsBinding.instance.addObserver(this);
    
    // Attach controller if provided
    widget.controller?._attach(this);
    
    // Note: Using simplified state management without complex callbacks
    
    _initializeCamera();
  }

  @override
  void dispose() {
    // Detach controller
    widget.controller?._detach();
    
    // Cleanup - using simplified approach
    
    WidgetsBinding.instance.removeObserver(this);
    _cleanupCameraOnDispose();
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
        // App is being terminated - cleanup everything
        _cleanupCameraOnDispose();
        break;
      default:
        break;
    }
  }

  Future<void> _initializeCamera() async {
    if (_isInitializing || _isInitialized) return;

    setState(() {
      _isInitializing = true;
      _initError = null;
    });

    try {
      // Ensure SDK is initialized first
      if (!_nosmaiFlutter.isInitialized) {
        setState(() {
          _initError = 'SDK not initialized. Please initialize the SDK first.';
          _isInitializing = false;
        });
        widget.onError?.call(_initError!);
        return;
      }

      // Configure camera
      await _nosmaiFlutter.configureCamera(
        position: NosmaiCameraPosition.front,
      );
      

      // Start processing
      await _nosmaiFlutter.startProcessing();
      

      // Add a small delay to allow the platform view to attach
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _isInitialized = true;
        _isInitializing = false;
      });

      widget.onInitialized?.call();
      debugPrint('✅ Camera preview initialized successfully');
    } catch (e) {
      final errorMessage = 'Failed to initialize camera: $e';
      setState(() {
        _initError = errorMessage;
        _isInitializing = false;
        _isInitialized = false;
      });
      widget.onError?.call(errorMessage);
      debugPrint('❌ Camera initialization error: $e');
    }
  }

  Future<void> _pauseCamera() async {
    try {
      if (_isInitialized && _nosmaiFlutter.isProcessing) {
        await _nosmaiFlutter.stopProcessing();
        debugPrint('⏸️ Camera processing paused');
      }
    } catch (e) {
      debugPrint('⚠️ Error pausing camera: $e');
    }
  }

  Future<void> _resumeCamera() async {
    try {
      if (_isInitialized && !_nosmaiFlutter.isProcessing) {
        await _nosmaiFlutter.startProcessing();
        debugPrint('▶️ Camera processing resumed');
      }
    } catch (e) {
      debugPrint('⚠️ Error resuming camera: $e');
      // If resume fails, try to reinitialize
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _isInitializing = false;
        });
        _initializeCamera();
      }
    }
  }

  Future<void> _cleanupCamera() async {
    try {
      debugPrint('🧹 Starting camera cleanup...');
      
      // Only stop processing and detach view - DO NOT cleanup SDK
      // The SDK should remain initialized for next use
      
      // Try to stop processing if active
      if (_nosmaiFlutter.isProcessing) {
        try {
          await _nosmaiFlutter.stopProcessing();
          debugPrint('⏹️ Camera processing stopped');
        } catch (e) {
          debugPrint('⚠️ Stop processing warning: $e');
        }
      }
      
      // Try to detach camera view
      try {
        await _nosmaiFlutter.detachCameraView();
        debugPrint('🔌 Camera view detached');
      } catch (e) {
        debugPrint('⚠️ Detach view warning: $e');
      }
      
      // Add delay to ensure cleanup completes
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Only update state if widget is still mounted
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _isInitializing = false;
        });
      }
      
      debugPrint('✅ Camera cleanup completed - SDK remains initialized');
    } catch (e) {
      debugPrint('⚠️ Error during camera cleanup: $e');
      // Force reset state even if cleanup fails
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _isInitializing = false;
        });
      }
    }
  }

  /// Special cleanup method for dispose that doesn't call setState
  Future<void> _cleanupCameraOnDispose() async {
    try {
      debugPrint('🧹 Starting camera cleanup on dispose...');
      
      // Only stop processing and detach view - DO NOT cleanup SDK
      // The SDK should remain initialized for next use
      
      // Try to stop processing if active
      if (_nosmaiFlutter.isProcessing) {
        try {
          await _nosmaiFlutter.stopProcessing();
          debugPrint('⏹️ Camera processing stopped on dispose');
        } catch (e) {
          debugPrint('⚠️ Stop processing warning on dispose: $e');
        }
      }
      
      // Try to detach camera view
      try {
        await _nosmaiFlutter.detachCameraView();
        debugPrint('🔌 Camera view detached on dispose');
      } catch (e) {
        debugPrint('⚠️ Detach view warning on dispose: $e');
      }
      
      debugPrint('✅ Camera cleanup on dispose completed - SDK remains initialized');
    } catch (e) {
      debugPrint('⚠️ Error during camera cleanup on dispose: $e');
    }
  }

  /// Manually reinitialize the camera (useful for error recovery)
  Future<void> reinitialize() async {
    debugPrint('🔄 Manual camera reinitialize requested');
    
    // Force cleanup
    await _cleanupCamera();
    
    // Longer delay to ensure everything is cleaned up
    await Future.delayed(const Duration(milliseconds: 1000));
    
    // Force reset all state
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _isInitializing = false;
        _initError = null;
      });
    }
    
    // Re-initialize
    await _initializeCamera();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: const Color(0xFF000000),
        child: const Center(
          child: Text(
            'Camera preview only supported on iOS',
            style: TextStyle(color: Colors.white),
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
              const Text(
                'Camera Error',
                style: TextStyle(
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

    // Show loading state
    if (_isInitializing || !_isInitialized) {
      String statusText = _isInitializing ? 'Initializing camera...' : 'Camera loading...';
      
      return Container(
        width: widget.width,
        height: widget.height,
        color: const Color(0xFF000000),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 16),
              Text(
                statusText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show camera preview
    return SizedBox(
      width: widget.width ?? double.infinity,
      height: widget.height ?? double.infinity,
      child: const UiKitView(
        viewType: 'nosmai_camera_preview',
        layoutDirection: TextDirection.ltr,
        creationParams: null,
        creationParamsCodec: null,
      ),
    );
  }
}