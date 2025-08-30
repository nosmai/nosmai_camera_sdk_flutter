/// Nosmai Flutter Plugin Data Models
///
/// This file contains all the data model classes used by the Nosmai Flutter plugin.

import 'dart:typed_data';
import 'enums.dart';

/// Helper function to safely parse integers from various types
int? _parseIntSafely(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
    final doubleValue = double.tryParse(value);
    return doubleValue?.toInt();
  }
  return null;
}

/// Filter information for both local and cloud filters
class NosmaiFilter {
  final String id;
  final String name;
  final String description;
  final String displayName;
  final String path;
  final int fileSize;
  final String type; // "cloud" or "local" - indicates source location
  final NosmaiFilterCategory filterCategory; // beauty, effect, filter
  final NosmaiFilterSourceType sourceType; // filter, effect

  // Cloud-specific properties (optional for local filters)
  final bool isFree;
  final bool isDownloaded;
  final String? previewUrl;
  final String? category;
  final int downloadCount;
  final int price;

  const NosmaiFilter({
    required this.id,
    required this.name,
    required this.description,
    required this.displayName,
    required this.path,
    required this.fileSize,
    required this.type,
    this.filterCategory = NosmaiFilterCategory.unknown,
    this.sourceType = NosmaiFilterSourceType.effect,
    this.isFree = true,
    this.isDownloaded = true,
    this.previewUrl,
    this.category,
    this.downloadCount = 0,
    this.price = 0,
  });

  /// Check if this is a cloud filter
  bool get isCloudFilter => type == 'cloud';

  /// Check if this is a local filter
  bool get isLocalFilter => type == 'local';

  /// Check if this is a filter (vs effect)
  bool get isFilter => sourceType == NosmaiFilterSourceType.filter;

  /// Check if this is an effect (vs filter)
  bool get isEffect => sourceType == NosmaiFilterSourceType.effect;

  factory NosmaiFilter.fromMap(Map<String, dynamic> map) {
    final String typeString = map['type']?.toString() ?? 'local';
    NosmaiFilterSourceType parsedSourceType;
    final filterTypeString = map['filterType']?.toString().toLowerCase();
    switch (filterTypeString) {
      case 'filter':
        parsedSourceType = NosmaiFilterSourceType.filter;
        break;
      case 'effect':
        parsedSourceType = NosmaiFilterSourceType.effect;
        break;
      default:
        // Default to effect for backward compatibility
        parsedSourceType = NosmaiFilterSourceType.effect;
        break;
    }

    NosmaiFilterCategory parsedFilterCategory = NosmaiFilterCategory.unknown;
    final categoryString =
        (map['category'] ?? map['filterCategory'])?.toString().toLowerCase();
    if (categoryString != null) {
      switch (categoryString) {
        case 'beauty':
          parsedFilterCategory = NosmaiFilterCategory.beauty;
          break;
        case 'effect':
          parsedFilterCategory = NosmaiFilterCategory.effect;
          break;
        case 'filter':
          parsedFilterCategory = NosmaiFilterCategory.filter;
          break;
      }
    }

    String finalPath;
    final pathValue = map['path'];
    if (pathValue != null && pathValue.toString() != 'null') {
      finalPath = pathValue.toString();
    } else {
      finalPath = '';
    }

    return NosmaiFilter(
      id: map['id']?.toString() ??
          map['filterId']?.toString() ??
          map['name']?.toString() ??
          '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      displayName:
          map['displayName']?.toString() ?? map['name']?.toString() ?? '',
      path: finalPath,
      fileSize: _parseIntSafely(map['fileSize']) ?? 0,
      type: typeString,
      filterCategory: parsedFilterCategory,
      sourceType: parsedSourceType,
      isFree: map['isFree'] as bool? ?? true,
      isDownloaded: map['isDownloaded'] as bool? ?? false,
      previewUrl: map['previewImageBase64']?.toString() ??
          map['previewUrl']?.toString() ??
          map['thumbnailUrl']?.toString(),
      category: map['category']?.toString(),
      downloadCount: _parseIntSafely(map['downloadCount']) ?? 0,
      price: _parseIntSafely(map['price']) ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'displayName': displayName,
      'path': path,
      'fileSize': fileSize,
      'type': type,
      'filterCategory': filterCategory.name,
      'sourceType': sourceType.name,
      'isFree': isFree,
      'isDownloaded': isDownloaded,
      'previewUrl': previewUrl,
      'category': category,
      'downloadCount': downloadCount,
      'price': price,
    };
  }

  @override
  String toString() {
    return 'NosmaiFilter(id: $id, name: $name, type: $type, filterCategory: $filterCategory, sourceType: $sourceType)';
  }
}

/// Download progress information
class NosmaiDownloadProgress {
  final String filterId;
  final double progress; // 0.0 to 1.0
  final int? bytesDownloaded;
  final int? totalBytes;

  const NosmaiDownloadProgress({
    required this.filterId,
    required this.progress,
    this.bytesDownloaded,
    this.totalBytes,
  });

  factory NosmaiDownloadProgress.fromMap(Map<String, dynamic> map) {
    return NosmaiDownloadProgress(
      filterId: map['filterId']?.toString() ?? '',
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      bytesDownloaded: _parseIntSafely(map['bytesDownloaded']),
      totalBytes: _parseIntSafely(map['totalBytes']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'filterId': filterId,
      'progress': progress,
      'bytesDownloaded': bytesDownloaded,
      'totalBytes': totalBytes,
    };
  }
}

/// Effect parameter information
class NosmaiEffectParameter {
  final String name;
  final String type;
  final double defaultValue;
  final String passId;
  final double? minValue;
  final double? maxValue;

  const NosmaiEffectParameter({
    required this.name,
    required this.type,
    required this.defaultValue,
    required this.passId,
    this.minValue,
    this.maxValue,
  });

  factory NosmaiEffectParameter.fromMap(Map<String, dynamic> map) {
    return NosmaiEffectParameter(
      name: map['name']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      defaultValue: (map['defaultValue'] as num?)?.toDouble() ?? 0.0,
      passId: map['passId']?.toString() ?? '',
      minValue: (map['minValue'] as num?)?.toDouble(),
      maxValue: (map['maxValue'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'type': type,
      'defaultValue': defaultValue,
      'passId': passId,
      'minValue': minValue,
      'maxValue': maxValue,
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
      fileSize: _parseIntSafely(map['fileSize']) ?? 0,
      error: map['error']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'videoPath': videoPath,
      'duration': duration,
      'fileSize': fileSize,
      'error': error,
    };
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
            // Try to convert list elements to int
            imageData = rawImageData.map((e) => e as int).toList();
          }
        } catch (e) {
          // If image data conversion fails, continue without it
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
        error: 'Failed to parse photo result: ${e.toString()}',
      );
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'imagePath': imagePath,
      'imageData': imageData,
      'error': error,
      'width': width,
      'height': height,
    };
  }
}
