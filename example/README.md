# Nosmai Camera SDK Flutter Example

Demonstrates comprehensive usage of the Nosmai Camera SDK Flutter plugin including camera functionality, filters, flash/torch control, and makeup effects.

## Features

### 🎥 Camera Functionality
- Live camera preview with real-time filters
- Photo capture and video recording
- Front/back camera switching
- Recording progress tracking

### ✨ Filter Categories
- **Beauty Filters**: Skin smoothing, whitening, face slimming, eye enlargement, nose size adjustment
- **Color Filters**: Brightness, contrast, RGB adjustment, white balance
- **HSB Filters**: Hue, saturation, brightness controls
- **Effect Filters**: Local and cloud-based visual effects
- **Cloud Filters**: Downloadable effects from Nosmai's cloud service

### 💄 Makeup Filters
- **Lipstick Filter**: Apply lipstick effect with adjustable intensity (0-10)
- **Blusher Filter**: Add blush/rouge effect with customizable level (0-50)

### 📸 Flash & Torch Control
- **Flash Detection**: Check if device has flash capability
- **Flash Modes**: Off, On, Auto modes for photo capture
- **Torch Control**: Continuous light for video recording
- **Torch Modes**: Off, On, Auto modes for sustained illumination

## Quick Start

### Basic Setup
```dart
// Initialize the SDK
final nosmai = NosmaiFlutter.instance;
await NosmaiFlutter.initialize('your_license_key');

// Configure camera
await nosmai.configureCamera(position: NosmaiCameraPosition.front);
await nosmai.startProcessing();
```

### Flash & Torch Usage
```dart
// Check flash availability
final hasFlash = await nosmai.hasFlash();
final hasTorch = await nosmai.hasTorch();

// Control flash
await nosmai.setFlashMode(NosmaiFlashMode.on);
await nosmai.setFlashMode(NosmaiFlashMode.off);

// Control torch
await nosmai.setTorchMode(NosmaiTorchMode.on);
await nosmai.setTorchMode(NosmaiTorchMode.off);
```

### Makeup Filters Usage
```dart
// Apply lipstick filter (0-10 intensity)
await nosmai.applyMakeupBlendLevel("LipstickFilter", 8.0);

// Apply blusher filter (0-50 intensity)
await nosmai.applyMakeupBlendLevel("BlusherFilter", 25.0);
```

### Beauty Filters Usage
```dart
// Apply beauty filters
await nosmai.applySkinSmoothing(5.0);     // 0-10
await nosmai.applySkinWhitening(3.0);     // 0-10
await nosmai.applyFaceSlimming(4.0);      // 0-10
await nosmai.applyEyeEnlargement(2.0);    // 0-10
await nosmai.applyNoseSize(45.0);         // 0-100 (50 is normal)
```

### Color & Effect Filters
```dart
// Color adjustments
await nosmai.applyBrightnessFilter(0.2);  // -1.0 to 1.0
await nosmai.applyContrastFilter(1.2);    // 0.0 to 4.0

// Apply effects
await nosmai.applyFilter('path/to/effect.nosmai');

// Reset all filters
await nosmai.removeAllFilters();
```

## Test Features

The example app includes a **Flash Test Button** (orange ⚡ icon) that demonstrates:
- Flash availability detection
- Flash on/off control
- Torch functionality testing
- Real-time status feedback

## Project Structure

- `lib/unified_camera_screen.dart` - Main camera interface with all features
- `lib/beauty_filter_screen.dart` - Beauty-focused camera screen
- `lib/filter_example.dart` - Filter demonstration screen

## Getting Started

1. **Clone the repository**
2. **Add your Nosmai license key** in the initialization code
3. **Run the app**: `flutter run`
4. **Test features** using the UI controls and test buttons

## Requirements

- Flutter SDK
- iOS 12.0+ / Android API 21+
- Valid Nosmai Camera SDK license
- Device with camera and (optionally) flash

## Resources

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)
- [Flutter Documentation](https://docs.flutter.dev/)

For Nosmai SDK specific documentation and support, contact Nosmai support team.
