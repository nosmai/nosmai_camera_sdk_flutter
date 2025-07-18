import 'package:flutter/material.dart';
import 'package:nosmai_camera_sdk/nosmai_flutter.dart';

/// Singleton manager for Nosmai SDK to ensure it's initialized only once
class NosmaiAppManager {
  static final NosmaiAppManager _instance = NosmaiAppManager._internal();
  static NosmaiAppManager get instance => _instance;

  NosmaiAppManager._internal();

  final NosmaiFlutter _nosmai = NosmaiFlutter.instance;
  bool _isInitialized = false;
  String? _initError;

  NosmaiFlutter get nosmai => _nosmai;
  bool get isInitialized => _isInitialized;
  String? get initError => _initError;

  /// Initialize the SDK once for the entire app
  Future<bool> initialize(String licenseKey) async {
    if (_isInitialized) {
      debugPrint('✅ Nosmai SDK already initialized');
      return true;
    }

    try {
      debugPrint('🚀 Initializing Nosmai SDK...');
      final success = await _nosmai.initWithLicense(licenseKey);

      if (success) {
        _isInitialized = true;
        _initError = null;
        debugPrint('✅ Nosmai SDK initialized successfully');
        
        // Pre-warm camera for faster startup
        _prewarmCamera();
      } else {
        _isInitialized = false;
        _initError = 'Failed to initialize SDK with license';
        debugPrint('❌ Nosmai SDK initialization failed');
      }

      return success;
    } catch (e) {
      _isInitialized = false;
      _initError = e.toString();
      debugPrint('❌ Nosmai SDK initialization error: $e');
      return false;
    }
  }

  /// Pre-warm the camera for faster startup (similar to TikTok)
  void _prewarmCamera() {
    // Pre-configure camera immediately after SDK initialization
    Future.microtask(() async {
      try {
        final stopwatch = Stopwatch()..start();
        debugPrint('⏱️ Starting camera pre-warming...');
        
        // Pre-configure front camera (most commonly used first)
        final configStart = Stopwatch()..start();
        await _nosmai.configureCamera(
          position: NosmaiCameraPosition.front,
        );
        configStart.stop();
        debugPrint('⏱️ Pre-warming: Camera config took ${configStart.elapsedMilliseconds}ms');
        
        // Pre-start processing for instant camera
        final processingStart = Stopwatch()..start();
        await _nosmai.startProcessing();
        processingStart.stop();
        debugPrint('⏱️ Pre-warming: Processing start took ${processingStart.elapsedMilliseconds}ms');
        
        // Pre-load essential filters in background
        _preloadEssentialFilters();
        
        stopwatch.stop();
        debugPrint('📷 Camera pre-warmed and ready in ${stopwatch.elapsedMilliseconds}ms');
      } catch (e) {
        debugPrint('⚠️ Camera pre-warming failed: $e');
      }
    });
  }

  /// Pre-load essential filters for faster access
  void _preloadEssentialFilters() {
    Future.microtask(() async {
      try {
        // Pre-load only local filters (fast)
        await _nosmai.getLocalFilters();
        debugPrint('🎭 Essential filters pre-loaded');
      } catch (e) {
        debugPrint('⚠️ Filter pre-loading failed: $e');
      }
    });
  }

  /// Call this only when the app is terminating
  Future<void> cleanup() async {
    if (_isInitialized) {
      await _nosmai.cleanup();
      _isInitialized = false;
      debugPrint('🧹 Nosmai SDK cleaned up');
    }
  }
}
