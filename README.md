# Nosmai Camera SDK Flutter Plugin

A Flutter plugin for integrating the Nosmai SDK - Real-time video filtering and beauty effects for iOS applications.

## Features

- 🎥 **Real-time video processing** with GPU acceleration and camera preview
- ⚡ **Performance optimizations** with automatic pre-warming and intelligent caching
- ✨ **Beauty filters** (skin smoothing, whitening, face slimming, eye enlargement, nose size)
- 🎨 **Color adjustments** (brightness, contrast, HSB, white balance, RGB)
- 🎭 **Effects and filters** with .nosmai file support and cloud filters
- 📱 **Camera controls** with crash prevention and throttling protection
- 💾 **Media management** (save photos and videos to gallery)
- 📡 **Stream-based events** for real-time callbacks
- 🏷️ **Metadata-based filter categorization** (beauty, effect, filter)
- 🧠 **Smart filter caching** with TTL management
- ♻️ **Automatic lifecycle management** with proper cleanup

## Platform Support

| Platform | Status |
|----------|--------|
| iOS      | ✅ Supported (iOS 14.0+) |
| Android  | 🚧 Planned |

## Requirements

- **iOS**: 14.0+
- **Flutter**: 3.22.0+
- **Dart**: 3.0.0+

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  nosmai_camera_sdk: ^1.0.2+1
```

## Setup

### iOS Setup

1. **Update your `ios/Podfile`** to set minimum iOS version and enable required permissions:

```ruby
platform :ios, '14.0'

ENV['COCOAPODS_DISABLE_STATS'] = 'true'

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist. Run 'flutter pub get' first."
  end
  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings_path}"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)

flutter_ios_podfile_setup

target 'Runner' do
  use_frameworks! :linkage => :static
  use_modular_headers!

  flutter_install_all_ios_pods(File.dirname(File.realpath(__FILE__)))
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        
        ## dart: PermissionGroup.camera
        'PERMISSION_CAMERA=1',
        
        ## dart: PermissionGroup.microphone
        'PERMISSION_MICROPHONE=1',
        
        ## dart: PermissionGroup.photos
        'PERMISSION_PHOTOS=1',
      ]
    end
  end
end
```

2. **Add camera permissions** to your `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera to apply real-time filters and beauty effects.</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app may use the microphone for video recording with filters.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>This app saves photos and videos to your photo library.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>This app saves photos and videos to your photo library.</string>
```

3. **Run pod install** to update dependencies:

```bash
cd ios && pod install
```

> **Important**: The camera, microphone, and photo library permissions are required for the plugin to function properly. Without these permissions, the app will crash when trying to access the camera or save media to the gallery.

### Local Filters Setup

To use local .nosmai filters in your app, you need to add them to your project assets:

1. **Create the filters directory** in your Flutter project:
   ```
   your_app/
     assets/
       filters/
         your_filter.nosmai
         another_filter.nosmai
   ```

2. **Update your `pubspec.yaml`** to include the filters as assets:
   ```yaml
   flutter:
     assets:
       - assets/filters/
   ```

3. **Access filters in your code**:
   ```dart
   // Get all local filters (including those in assets/filters/)
   final localFilters = await NosmaiFlutter.instance.getLocalFilters();
   
   // Apply a specific local filter
   await NosmaiFlutter.instance.applyEffect('assets/filters/your_filter.nosmai');
   ```

> **Note**: Place your .nosmai filter files in the `assets/filters/` directory and ensure they are properly declared in `pubspec.yaml`. The plugin will automatically discover and include these filters when calling `getLocalFilters()`.

## Usage

### App Initialization

For production apps, initialize the SDK once at app startup with optimizations:

```dart
// main.dart
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nosmai_camera_sdk/nosmai_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Pre-request permissions for instant camera access
    await Permission.camera.request();
    await Permission.microphone.request();
    
    // Initialize SDK
    await NosmaiFlutter.initialize('YOUR_LICENSE_KEY');
  } catch (e) {
    // Handle initialization error
  }
  
  runApp(const MyApp());
}
```

### Basic Setup with Camera Preview

```dart
import 'package:nosmai_camera_sdk/nosmai_camera_sdk.dart';

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _checkInitialization();
  }

  void _checkInitialization() {
    // Check if SDK is already initialized
    setState(() {
      _isInitialized = NosmaiFlutter.instance.isInitialized;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview with automatic lifecycle management
          if (_isInitialized)
            const Positioned.fill(
              child: NosmaiCameraPreview(),
            )
          else
            const Center(
              child: CircularProgressIndicator(),
            ),
          
          // Your UI controls here
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: () async {
                    final result = await NosmaiFlutter.instance.capturePhoto();
                    if (result.success && result.imageData != null) {
                      // Handle captured photo
                      await NosmaiFlutter.instance.saveImageToGallery(
                        result.imageData!,
                        name: 'photo_${DateTime.now().millisecondsSinceEpoch}',
                      );
                    }
                  },
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                ),
                IconButton(
                  onPressed: () async {
                    await NosmaiFlutter.instance.switchCamera();
                  },
                  icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // NosmaiCameraPreview handles cleanup automatically
    super.dispose();
  }
}
```

### Applying Filters

#### Basic Color Adjustments

```dart
final nosmai = NosmaiFlutter.instance;

// Brightness adjustment
await nosmai.applyBrightnessFilter(0.3); // -1.0 to 1.0

// Contrast adjustment  
await nosmai.applyContrastFilter(1.5); // 0.0 to 2.0

// RGB color adjustments
await nosmai.applyRGBFilter(
  red: 1.2,   // 0.0 to 2.0
  green: 0.8, // 0.0 to 2.0
  blue: 1.1,  // 0.0 to 2.0
);

// HSB adjustments
await nosmai.adjustHSB(
  hue: 0.0,        // -360 to 360
  saturation: 1.2,  // 0.0 to 2.0
  brightness: 1.1,  // 0.0 to 2.0
);

// White balance
await nosmai.applyWhiteBalance(
  temperature: 5500.0, // 2000-8000
  tint: 0.0,          // -100 to 100
);
```

#### Beauty Filters

```dart
final nosmai = NosmaiFlutter.instance;

// Enable face detection for beauty filters
await nosmai.setFaceDetectionEnabled(true);

// Skin smoothing (requires face detection)
await nosmai.applySkinSmoothing(0.7); // 0.0 to 10.0

// Skin whitening
await nosmai.applySkinWhitening(0.5); // 0.0 to 10.0

// Face slimming
await nosmai.applyFaceSlimming(0.3); // 0.0 to 10.0

// Eye enlargement
await nosmai.applyEyeEnlargement(0.2); // 0.0 to 10.0

// Nose size adjustment
await nosmai.applyNoseSize(50.0); // 0.0 to 100.0
```

#### Effect Filters

```dart
final nosmai = NosmaiFlutter.instance;

// Apply .nosmai effect files
await nosmai.applyEffect('/path/to/filter.nosmai');

// Load and apply custom filters
final success = await nosmai.loadNosmaiFilter('/path/to/filter.nosmai');
if (success) {
  // Filter is now loaded and applied
}

// Get cached filters with automatic performance optimization
final filters = await nosmai.getCachedFilters();
for (final filter in filters) {
  if (filter is NosmaiLocalFilter) {
    await nosmai.applyEffect(filter.path);
  }
}

// Clear cache if needed
await nosmai.clearFilterCache();
```

### Camera Controls and Media Capture

```dart
final nosmai = NosmaiFlutter.instance;

// Switch between front and back camera
final switched = await nosmai.switchCamera();
if (switched) {
  // Camera switch was performed
} else {
  // Switch was ignored due to throttling (no error thrown)
}

// Or use immediate switch (advanced)
// await nosmai.switchCameraImmediate();

// Capture photo with applied filters
final result = await nosmai.capturePhoto();
if (result.success && result.imageData != null) {
  // Save to gallery
  final saveResult = await nosmai.saveImageToGallery(
    result.imageData!,
    name: 'my_photo_${DateTime.now().millisecondsSinceEpoch}',
  );
}

// Video recording
final recordingStarted = await nosmai.startRecording();
if (recordingStarted) {
  // Stop recording after some time
  final result = await nosmai.stopRecording();
  if (result.success && result.videoPath != null) {
    // Save to gallery
    await nosmai.saveVideoToGallery(
      result.videoPath!,
      name: 'my_video_${DateTime.now().millisecondsSinceEpoch}',
    );
  }
}

// Remove all applied filters
await nosmai.removeAllFilters();
await nosmai.removeBuiltInFilters();
await nosmai.resetHSBFilter();
```

### Event Handling

```dart
final nosmai = NosmaiFlutter.instance;

// Listen for errors
nosmai.onError.listen((error) {
  debugPrint('Nosmai Error: ${error.message}');
  // Handle error appropriately
});

// Listen for download progress (for cloud filters)
nosmai.onDownloadProgress.listen((progress) {
  debugPrint('Download: ${progress.progress}%');
});

// Listen for SDK state changes
nosmai.onStateChanged.listen((state) {
  debugPrint('SDK State: ${state.toString()}');
});

// Listen for recording progress
nosmai.onRecordingProgress.listen((duration) {
  debugPrint('Recording duration: ${duration}s');
});
```

### Filter Management and Organization

The SDK provides metadata-based filter categorization:

```dart
final nosmai = NosmaiFlutter.instance;

// Get filters with built-in caching
final allFilters = await nosmai.getFilters();

// Apply filters based on type
for (final filter in allFilters) {
  if (filter is NosmaiLocalFilter) {
    await nosmai.applyEffect(filter.path);
  }
}

// Clear cache when needed
await nosmai.clearCache();
```

## API Reference

### NosmaiFlutter

Main class for interacting with the Nosmai SDK.

#### Properties

- `bool isInitialized` - Whether the SDK has been initialized
- `bool isProcessing` - Whether video processing is active
- `bool isRecording` - Whether video recording is active
- `Stream<NosmaiError> onError` - Stream of error events
- `Stream<NosmaiDownloadProgress> onDownloadProgress` - Stream of download progress
- `Stream<NosmaiSdkStateInfo> onStateChanged` - Stream of SDK state changes
- `Stream<double> onRecordingProgress` - Stream of recording progress (duration in seconds)

#### Methods

##### Initialization & Lifecycle
- `static Future<bool> initialize(String licenseKey)` - Initialize SDK (recommended)
- `Future<bool> initWithLicense(String licenseKey)` - Initialize SDK with license (basic)
- `Future<void> configureCamera({required NosmaiCameraPosition position, String? sessionPreset})` - Configure camera
- `Future<void> startProcessing()` - Start video processing
- `Future<void> stopProcessing()` - Stop video processing
- `Future<void> cleanup()` - Clean up SDK resources
- `void dispose()` - Dispose instance and stream controllers

##### Camera Controls
- `Future<bool> switchCamera()` - Switch camera with built-in protection (recommended)
- `Future<void> switchCameraImmediate()` - Switch camera immediately (advanced)
- `static bool get isCameraSwitching` - Whether camera switch is in progress
- `Future<void> setPreviewView()` - Set preview view (iOS only)
- `Future<void> detachCameraView()` - Detach camera view
- `Future<void> setFaceDetectionEnabled(bool enable)` - Enable/disable face detection

##### Media Capture
- `Future<NosmaiPhotoResult> capturePhoto()` - Capture photo with applied filters
- `Future<bool> startRecording()` - Start video recording
- `Future<NosmaiRecordingResult> stopRecording()` - Stop video recording
- `Future<bool> isCurrentlyRecording()` - Check if currently recording
- `Future<double> getCurrentRecordingDuration()` - Get current recording duration
- `Future<Map<String, dynamic>> saveImageToGallery(List<int> imageData, {String? name})` - Save image to gallery
- `Future<Map<String, dynamic>> saveVideoToGallery(String videoPath, {String? name})` - Save video to gallery

##### Color & Basic Filters
- `Future<void> applyBrightnessFilter(double brightness)` - Apply brightness (-1.0 to 1.0)
- `Future<void> applyContrastFilter(double contrast)` - Apply contrast (0.0 to 2.0)
- `Future<void> applyRGBFilter({required double red, required double green, required double blue})` - Apply RGB adjustments
- `Future<void> adjustHSB({required double hue, required double saturation, required double brightness})` - Adjust HSB
- `Future<void> resetHSBFilter()` - Reset HSB to defaults
- `Future<void> applyWhiteBalance({required double temperature, required double tint})` - Apply white balance
- `Future<void> applyHue(double hueAngle)` - Apply hue rotation

##### Beauty Filters (require face detection)
- `Future<void> applySkinSmoothing(double level)` - Apply skin smoothing (0.0 to 10.0)
- `Future<void> applySkinWhitening(double level)` - Apply skin whitening (0.0 to 10.0)
- `Future<void> applyFaceSlimming(double level)` - Apply face slimming (0.0 to 10.0)
- `Future<void> applyEyeEnlargement(double level)` - Apply eye enlargement (0.0 to 10.0)
- `Future<void> applyNoseSize(double size)` - Apply nose size adjustment (0.0 to 100.0)

##### Effect Filters
- `Future<bool> applyEffect(String effectPath)` - Apply .nosmai effect file
- `Future<bool> loadNosmaiFilter(String filePath)` - Load custom filter
- `Future<List<NosmaiEffectParameter>> getEffectParameters()` - Get current effect parameters
- `Future<bool> setEffectParameter(String parameterName, double value)` - Set effect parameter

##### Filter Management
- `Future<List<NosmaiFilter>> getFilters({bool forceRefresh})` - Get filters with built-in caching (recommended)
- `Future<void> clearCache()` - Clear filter cache
- `Future<void> setCacheConfig(Map<String, dynamic> config)` - Configure cache settings
- `Future<List<NosmaiFilter>> fetchFiltersAndEffectsFromAllSources()` - Get all filters (basic)
- `Future<List<NosmaiFilter>> getLocalFilters()` - Get local filters only
- `Future<List<NosmaiFilter>> getCloudFilters()` - Get cloud filters only
- `Future<Map<String, dynamic>> downloadCloudFilter(String filterId)` - Download cloud filter

##### Filter Removal
- `Future<void> removeAllFilters()` - Remove all applied filters
- `Future<void> removeBuiltInFilters()` - Remove built-in filters
- `Future<void> removeBuiltInFilterByName(String filterName)` - Remove specific built-in filter

##### Additional Beauty and Color Methods
- `Future<void> applySharpening(double level)` - Apply sharpening (0.0 to 10.0)
- `Future<void> applyMakeupBlendLevel(String filterName, double level)` - Apply makeup blend level
- `Future<void> applyGrayscaleFilter()` - Apply grayscale filter

##### License Feature Methods
- `Future<bool> isBeautyEffectEnabled()` - Check if beauty effects are enabled for license
- `Future<bool> isCloudFilterEnabled()` - Check if cloud filters are enabled for license

##### Utility Methods
- `Future<String?> getPlatformVersion()` - Get platform version for debugging

### Core Types

#### NosmaiCameraPosition
- `front` - Front-facing camera
- `back` - Back-facing camera

#### NosmaiFilterCategory
- `beauty` - Beauty enhancement filters (face slimming, skin smoothing, etc.)
- `effect` - Creative/artistic effects (glitch, holographic, etc.)
- `filter` - Standard filters (color adjustments, basic effects, etc.)
- `unknown` - Unknown or uncategorized filters

#### NosmaiError
- `String code` - Error code
- `String message` - Error message
- `String? details` - Additional error details

#### NosmaiDownloadProgress
- `String filterId` - Filter being downloaded
- `double progress` - Download progress (0.0-1.0)
- `String? status` - Download status

#### NosmaiSdkState
- Various SDK state values for monitoring

#### NosmaiRecordingResult
- `bool success` - Whether recording was successful
- `String? videoPath` - Path to recorded video file
- `double duration` - Recording duration in seconds
- `int fileSize` - Video file size in bytes
- `String? error` - Error message if recording failed

#### NosmaiPhotoResult
- `bool success` - Whether photo capture was successful
- `String? imagePath` - Path to captured image file
- `List<int>? imageData` - Raw image data as bytes
- `String? error` - Error message if capture failed
- `int? width` - Image width in pixels
- `int? height` - Image height in pixels

### Filter Types

#### NosmaiLocalFilter
- `String name` - Filter name
- `String path` - Local file path
- `String displayName` - Human-readable name
- `int fileSize` - File size in bytes
- `String type` - Filter type ('local')
- `NosmaiFilterCategory filterCategory` - Filter category

#### NosmaiCloudFilter
- `String id` - Unique cloud filter ID
- `String name` - Filter name
- `String displayName` - Human-readable name
- `bool isFree` - Whether filter is free
- `bool isDownloaded` - Whether filter is downloaded
- `String? localPath` - Local path if downloaded
- `int? fileSize` - File size in bytes
- `String? previewUrl` - Preview image URL
- `String? category` - Category string
- `NosmaiFilterCategory filterCategory` - Filter category

#### NosmaiEffectParameter
- `String name` - Parameter name
- `String type` - Parameter type (e.g., 'float')
- `double defaultValue` - Default parameter value
- `double currentValue` - Current parameter value
- `double minValue` - Minimum allowed value
- `double maxValue` - Maximum allowed value
- `String? passId` - Pass ID for multi-pass effects

## Example

The `example` folder contains a comprehensive demo app showcasing all plugin features:

- **UnifiedCameraScreen**: Complete camera interface with filters, recording, and photo capture
- **Real-time filter switching** with horizontal scrollable filter panels
- **Interactive parameter adjustment** with sliders for beauty and color filters
- **Camera controls**: front/back switching, photo capture, video recording
- **Media management**: Save photos and videos to gallery
- **Filter organization**: Categorized by Effects, Beauty, Color, and HSB
- **Error handling and status monitoring**
- **Automatic lifecycle management**

### Running the Example

```bash
cd example
flutter pub get
cd ios && pod install
cd .. && flutter run
```

### Key Example Files

- `lib/main.dart` - App initialization with optimized SDK setup
- `lib/unified_camera_screen.dart` - Main camera interface with professional naming conventions and all features
- `lib/filter_example.dart` - Individual filter testing interface
- `lib/beauty_filter_screen.dart` - Dedicated beauty filter demonstration

## Integration with Existing Project

If you're integrating this plugin into an existing project that already uses the Nosmai SDK:

1. The plugin expects to find your SDK headers at the relative path shown in the podspec
2. Update the header search paths in `ios/nosmai_camera_sdk.podspec` if needed
3. Ensure your license key is valid and matches the one used in your existing app
4. The plugin will work alongside your existing Nosmai implementation

## Troubleshooting

### Common Issues

1. **SDK initialization fails**
   - Verify your license key is correct and active
   - Check that the Nosmai SDK headers are found at the expected path
   - Ensure iOS deployment target is 13.0+

2. **Camera permission denied**
   - Add camera usage description to Info.plist
   - Request permissions before initializing SDK

3. **Build errors on iOS**
   - Clean build folder: `flutter clean`
   - Update CocoaPods: `cd ios && pod update`
   - Check header search paths in nosmai_camera_sdk.podspec

4. **Framework not found**
   - Verify the relative path to your Nosmai SDK
   - Check that all required frameworks are linked
   - Ensure the SDK is built for the correct architecture

### Performance Tips

- **Initialize**: Use `NosmaiFlutter.initialize()` for setup
- **Use built-in caching**: Call `getFilters()` instead of fetching filters repeatedly
- **Camera switching**: Use `switchCamera()` for safe switching
- **Check switching state**: Use `NosmaiFlutter.isCameraSwitching` to disable UI during switches
- Use `NosmaiFlutter.instance` singleton for all SDK operations
- Use `NosmaiCameraPreview` widget for automatic lifecycle management
- Stop processing when app goes to background to save battery with `stopProcessing()`
- Remove filters when switching between different effect types using `removeAllFilters()`
- Beauty filters automatically enable face detection - disable when not needed with `setFaceDetectionEnabled(false)`
- Use horizontal scrollable filter panels for better UX as shown in the example
- Call `cleanup()` instead of `dispose()` for SDK resource cleanup
- Use `dispose()` only when completely done with the SDK instance

## License

This plugin is provided under the MIT License. However, the use of the underlying Nosmai SDK is subject to separate licensing terms and conditions.

To use this plugin, you must:
1. Obtain a valid license for the Nosmai SDK
2. Comply with all Nosmai SDK licensing terms
3. Include the Nosmai SDK framework in your application

## Support

For issues related to:
- **Plugin functionality**: Create an issue in this repository
- **Nosmai SDK**: Contact Nosmai support
- **Flutter integration**: Check Flutter documentation

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## Version History

### 1.0.0
- Initial release
- iOS platform support
- Complete filter API implementation
- Example app with comprehensive demos
- Real Nosmai SDK integration
- Stream-based event handling
- Comprehensive documentation