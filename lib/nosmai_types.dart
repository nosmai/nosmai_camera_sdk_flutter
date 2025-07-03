/// Nosmai Flutter Plugin Types
/// 
/// This file contains all the type definitions used by the Nosmai Flutter plugin.

import 'dart:typed_data';

/// Camera position enumeration
enum NosmaiCameraPosition {
  front,
  back,
}

/// Filter types supported by Nosmai SDK
enum NosmaiFilterType {
  nosmai,  // Custom .nosmai effect packages
  cloud,   // Cloud-based filters
}

/// Filter category types for metadata-based categorization
enum NosmaiFilterCategory {
  beauty,  // Beauty enhancement filters (lipstick, face slimming, etc.)
  effect,  // Creative/artistic effects (glitch, holographic, etc.)
  filter,  // Standard filters (color adjustments, basic effects, etc.)
  unknown, // Unknown or uncategorized filters
}







/// Cloud filter information
class NosmaiCloudFilter {
  final String id;
  final String name;
  final String displayName;
  final bool isFree;
  final bool isDownloaded;
  final String? localPath;
  final int? fileSize;
  final String? previewUrl;
  final String? category;
  final NosmaiFilterCategory filterCategory;

  const NosmaiCloudFilter({
    required this.id,
    required this.name,
    required this.displayName,
    required this.isFree,
    required this.isDownloaded,
    this.localPath,
    this.fileSize,
    this.previewUrl,
    this.category,
    this.filterCategory = NosmaiFilterCategory.unknown,
  });

  factory NosmaiCloudFilter.fromMap(Map<String, dynamic> map) {
    // Handle localPath - check for NSNull and convert properly, fallback to 'path' field
    String? localPath;
    final localPathValue = map['localPath'] ?? map['path']; // Fallback to 'path' field
    if (localPathValue != null && localPathValue.toString() != 'null') {
      localPath = localPathValue.toString();
    }
    
    // Handle filterId - use 'name' as fallback for cached filters  
    String filterId = map['filterId']?.toString() ?? 
                     map['id']?.toString() ?? 
                     map['name']?.toString() ?? '';
    
    // Parse filter category from metadata
    NosmaiFilterCategory filterCategory = NosmaiFilterCategory.unknown;
    final filterTypeString = map['filterType']?.toString().toLowerCase();
    if (filterTypeString != null) {
      switch (filterTypeString) {
        case 'beauty':
          filterCategory = NosmaiFilterCategory.beauty;
          break;
        case 'effect':
          filterCategory = NosmaiFilterCategory.effect;
          break;
        case 'filter':
          filterCategory = NosmaiFilterCategory.filter;
          break;
      }
    }
    
    return NosmaiCloudFilter(
      id: filterId,
      name: map['name']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? '',
      isFree: map['isFree'] as bool? ?? false,
      isDownloaded: map['isDownloaded'] as bool? ?? false,
      localPath: localPath,
      fileSize: map['fileSize'] as int?,
      previewUrl: map['previewUrl']?.toString(),
      category: map['category']?.toString(),
      filterCategory: filterCategory,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'displayName': displayName,
      'isFree': isFree,
      'isDownloaded': isDownloaded,
      if (localPath != null) 'localPath': localPath,
      if (fileSize != null) 'fileSize': fileSize,
      if (previewUrl != null) 'previewUrl': previewUrl,
      if (category != null) 'category': category,
      'filterCategory': filterCategory.name,
    };
  }
}

/// Local filter information
class NosmaiLocalFilter {
  final String name;
  final String path;
  final String displayName;
  final int fileSize;
  final String type;
  final NosmaiFilterCategory filterCategory;

  const NosmaiLocalFilter({
    required this.name,
    required this.path,
    required this.displayName,
    required this.fileSize,
    required this.type,
    this.filterCategory = NosmaiFilterCategory.unknown,
  });

  factory NosmaiLocalFilter.fromMap(Map<String, dynamic> map) {
    // Parse filter category from metadata
    NosmaiFilterCategory filterCategory = NosmaiFilterCategory.unknown;
    final filterTypeString = map['filterType']?.toString().toLowerCase();
    if (filterTypeString != null) {
      switch (filterTypeString) {
        case 'beauty':
          filterCategory = NosmaiFilterCategory.beauty;
          break;
        case 'effect':
          filterCategory = NosmaiFilterCategory.effect;
          break;
        case 'filter':
          filterCategory = NosmaiFilterCategory.filter;
          break;
      }
    }
    
    return NosmaiLocalFilter(
      name: map['name']?.toString() ?? '',
      path: map['path']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? '',
      fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
      type: map['type']?.toString() ?? 'local',
      filterCategory: filterCategory,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'path': path,
      'displayName': displayName,
      'fileSize': fileSize,
      'type': type,
      'filterCategory': filterCategory.name,
    };
  }
}

/// Effect parameter information
class NosmaiEffectParameter {
  final String name;
  final String type;
  final double defaultValue;
  final double currentValue;
  final double minValue;
  final double maxValue;
  final String? passId;

  const NosmaiEffectParameter({
    required this.name,
    required this.type,
    required this.defaultValue,
    required this.currentValue,
    required this.minValue,
    required this.maxValue,
    this.passId,
  });

  factory NosmaiEffectParameter.fromMap(Map<String, dynamic> map) {
    return NosmaiEffectParameter(
      name: map['name']?.toString() ?? '',
      type: map['type']?.toString() ?? 'float',
      defaultValue: (map['defaultValue'] as num?)?.toDouble() ?? 0.0,
      currentValue: (map['currentValue'] as num?)?.toDouble() ?? 0.0,
      minValue: (map['minValue'] as num?)?.toDouble() ?? 0.0,
      maxValue: (map['maxValue'] as num?)?.toDouble() ?? 1.0,
      passId: map['passId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'defaultValue': defaultValue,
      'currentValue': currentValue,
      'minValue': minValue,
      'maxValue': maxValue,
      if (passId != null) 'passId': passId,
    };
  }
}

/// Recording result information
class NosmaiRecordingResult {
  final bool success;
  final String? videoPath;
  final double duration;
  final int fileSize;
  final String? error;

  const NosmaiRecordingResult({
    required this.success,
    this.videoPath,
    required this.duration,
    required this.fileSize,
    this.error,
  });

  factory NosmaiRecordingResult.fromMap(Map<String, dynamic> map) {
    return NosmaiRecordingResult(
      success: map['success'] as bool? ?? false,
      videoPath: map['videoPath']?.toString(),
      duration: (map['duration'] as num?)?.toDouble() ?? 0.0,
      fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
      error: map['error']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      if (videoPath != null) 'videoPath': videoPath,
      'duration': duration,
      'fileSize': fileSize,
      if (error != null) 'error': error,
    };
  }
}

/// Download progress information
class NosmaiDownloadProgress {
  final String filterId;
  final double progress;
  final String? status;

  const NosmaiDownloadProgress({
    required this.filterId,
    required this.progress,
    this.status,
  });

  factory NosmaiDownloadProgress.fromMap(Map<String, dynamic> map) {
    return NosmaiDownloadProgress(
      filterId: map['filterId']?.toString() ?? '',
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      status: map['status']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'filterId': filterId,
      'progress': progress,
      if (status != null) 'status': status,
    };
  }
}

/// Recording progress information
class NosmaiRecordingProgress {
  final double duration;
  final String? status;

  const NosmaiRecordingProgress({
    required this.duration,
    this.status,
  });

  factory NosmaiRecordingProgress.fromMap(Map<String, dynamic> map) {
    return NosmaiRecordingProgress(
      duration: (map['duration'] as num?)?.toDouble() ?? 0.0,
      status: map['status']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'duration': duration,
      if (status != null) 'status': status,
    };
  }
}



/// SDK state enumeration
enum NosmaiSdkState {
  uninitialized,
  initializing,
  ready,
  error,
  paused,
}

/// Error types that can occur in the SDK
class NosmaiError {
  final String code;
  final String message;
  final String? details;

  const NosmaiError({
    required this.code,
    required this.message,
    this.details,
  });

  factory NosmaiError.fromMap(Map<String, dynamic> map) {
    return NosmaiError(
      code: map['code']?.toString() ?? 'unknown',
      message: map['message']?.toString() ?? 'Unknown error occurred',
      details: map['details']?.toString(),
    );
  }

  @override
  String toString() {
    return 'NosmaiError(code: $code, message: $message, details: $details)';
  }
}

/// Photo capture result
class NosmaiPhotoResult {
  final bool success;
  final String? imagePath;
  final List<int>? imageData;
  final String? error;
  final int? width;
  final int? height;

  const NosmaiPhotoResult({
    required this.success,
    this.imagePath,
    this.imageData,
    this.error,
    this.width,
    this.height,
  });

  factory NosmaiPhotoResult.fromMap(Map<String, dynamic> map) {
    try {
      final success = map['success'] as bool? ?? false;
      final imagePath = map['imagePath']?.toString();
      final error = map['error']?.toString();
      
      // Handle both int and double types from iOS
      int? width;
      int? height;
      
      if (map['width'] != null) {
        if (map['width'] is int) {
          width = map['width'] as int;
        } else if (map['width'] is double) {
          width = (map['width'] as double).round();
        } else {
          width = int.tryParse(map['width'].toString());
        }
      }
      
      if (map['height'] != null) {
        if (map['height'] is int) {
          height = map['height'] as int;
        } else if (map['height'] is double) {
          height = (map['height'] as double).round();
        } else {
          height = int.tryParse(map['height'].toString());
        }
      }
      
      List<int>? imageData;
      if (map['imageData'] != null) {
        try {
          // Handle different types of image data from native platforms
          final rawImageData = map['imageData'];
          
          if (rawImageData is List<int>) {
            imageData = rawImageData;
          } else if (rawImageData is Uint8List) {
            imageData = rawImageData.toList();
          } else if (rawImageData is List) {
            // This handles _UnmodifiableUint8ArrayView and other List types
            imageData = List<int>.from(rawImageData);
          }
        } catch (e) {
          imageData = null;
        }
      }
      
      return NosmaiPhotoResult(
        success: success,
        imagePath: imagePath,
        imageData: imageData,
        error: error,
        width: width,
        height: height,
      );
      
    } catch (e) {
      return NosmaiPhotoResult(
        success: false,
        error: 'Failed to parse photo result: $e',
      );
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      if (imagePath != null) 'imagePath': imagePath,
      if (imageData != null) 'imageData': imageData,
      if (error != null) 'error': error,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    };
  }

  @override
  String toString() {
    return 'NosmaiPhotoResult(success: $success, imagePath: $imagePath, error: $error, width: $width, height: $height)';
  }
}