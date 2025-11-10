/// Nosmai Flutter Plugin Enums
///
/// This file contains all the enumeration types used by the Nosmai Flutter plugin.

/// Camera position enumeration
enum NosmaiCameraPosition {
  front,
  back,
}

/// Filter types supported by Nosmai SDK
enum NosmaiFilterType {
  local, // Custom .nosmai effect packages
  cloud, // Cloud-based filters
}

/// Filter category types for metadata-based categorization
enum NosmaiFilterCategory {
  beauty, // Beauty enhancement filters (lipstick, face slimming, etc.)
  effect, // Creative/artistic effects (glitch, holographic, etc.)
  filter, // Standard filters (color adjustments, basic effects, etc.)
  unknown, // Unknown or uncategorized filters
}

/// Filter source type enumeration
enum NosmaiFilterSourceType {
  filter,
  effect,
}

/// Error types that can occur in the Nosmai SDK
enum NosmaiErrorType {
  // General errors
  unknown,
  stateError,
  operationTimeout,
  platformError,
  networkError,
  invalidParameter,

  // SDK initialization errors
  sdkNotInitialized,
  invalidLicense,
  licenseExpired,

  // Camera errors
  cameraPermissionDenied,
  cameraUnavailable,
  cameraConfigurationFailed,
  cameraSwitchFailed,

  // Filter errors
  filterNotFound,
  filterInvalidFormat,
  filterLoadFailed,
  filterDownloadFailed,

  // Recording errors
  recordingPermissionDenied,
  recordingStorageFull,
  recordingWriteFailed,
  recordingInProgress,
}

/// SDK state enumeration
enum NosmaiSdkState {
  uninitialized,
  initializing,
  ready,
  error,
}

/// Flash mode enumeration
enum NosmaiFlashMode {
  off,
  on,
  auto,
}

/// Torch mode enumeration
enum NosmaiTorchMode {
  off,
  on,
  auto,
}

/// License status enumeration
enum NosmaiLicenseStatus {
  valid,
  expired,
  invalid,
}
