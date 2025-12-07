## 3.0.5
- **IMPROVED**: Enhanced rendering engine for better performance and smoother visual output

## 3.0.4
- **FIXED**: iOS camera dispose issue resolved to prevent crashes and ensure proper resource release

## 3.0.3
- **FIXED**: Resolve AAR library issue  

## 3.0.2
- **FIXED**: Resolved native library bugs to improve overall SDK stability and performance  
- **FIXED**: Flashlight issue resolved in plugin for both iOS and Android platforms  


## 3.0.1
- **CHANGE**: Filter directory path updated for better consistency
  - Changed filter path from `assets/Nosmai_Filters/` to `assets/nosmai_filters/` (lowercase)
  - Updated native code paths on both iOS and Android platforms
  - Updated documentation and examples to reflect new path structure
  - **Migration**: Rename your filter directory from `Nosmai_Filters` to `nosmai_filters` and update `pubspec.yaml` asset paths

## 3.0.0
- **⚠️ BREAKING CHANGE**: Filter structure updated for better performance
  - Old `assets/filters/` structure is now DEPRECATED
  - New structure: `assets/Nosmai_Filters/{filter_name}/` with manifest files
  - Each filter must include: `{filter_name}_manifest.json`, `{filter_name}_preview.png`, `{filter_name}.nosmai`
  - **Migration required**: Update pubspec.yaml to declare each filter path individually
  - See [example/pubspec.yaml](example/pubspec.yaml) for reference
  - Download new filters from: https://effects.nosmai.com/assets-store/filters
- **NEW FEATURES**:
  - Added metadata support: version, author, tags, creation date
  - Updated `NosmaiFilter` model with new optional fields
- **IMPROVEMENTS**:
  - **Native SDK Updates**: Updated native iOS and Android code for better performance and stability
  - Enhanced camera processing pipeline for smoother real-time effects
  - Improved memory management and resource handling
  - Optimized filter loading and application mechanism
  - Better error handling and recovery across all SDK operations
  - Updated `getLocalFilters()` to use new structure on iOS and Android
  - Enhanced README and documentation with comprehensive filter guides

## 2.0.1+8
- Fixed camera aspect ratio issue on Android (improves reliability across devices).

## 2.0.1+7
- Fix aspect ratio issue on Android.

## 2.0.1+6
- Fix no-audio issue in recorded video on Android.

## 2.0.1+5
- Resolve camera foreground issue on Android.

## 2.0.1+4
- Fixed mirror issue when switching camera on Android.

## 2.0.1+3
- Fixed Android camera crashing issue in release mode.

## 2.0.1+2
- improve app structure.

## 2.0.1+1
- update README.md.

## 2.0.1
- Fixed back camera mirror issue on Android.

## 2.0.0
- Fixed Android crashing issue
- Resolved iOS video recording issue

## 1.0.4+2
- Fix android camera issue

## 1.0.4+1
- resolve .AAR build issue

## 1.0.4
- Added Android .aar integration inside the plugin
- Fixed build.gradle configurations for Android
- Minor bug fixes and improvements

## 1.0.3
- Initial release of Nosmai Camera SDK Flutter plugin
- Real-time video filtering and beauty effects
- Comprehensive filter system with cloud and local filters
- Built-in beauty filters (skin smoothing, whitening, face slimming)
- Color adjustment filters (brightness, contrast, RGB)
- Effect filters (sharpening, hue, white balance)
- HSB (Hue, Saturation, Brightness) controls
- Video recording capabilities with filter effects
- Camera switching and position configuration
- Error handling and lifecycle management
- iOS platform support with comprehensive API
