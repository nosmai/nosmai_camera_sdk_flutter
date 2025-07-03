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

  /// Call this only when the app is terminating
  Future<void> cleanup() async {
    if (_isInitialized) {
      await _nosmai.cleanup();
      _isInitialized = false;
      debugPrint('🧹 Nosmai SDK cleaned up');
    }
  }
}
