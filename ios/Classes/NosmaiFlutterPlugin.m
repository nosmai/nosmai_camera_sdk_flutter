#import "NosmaiFlutterPlugin.h"
#import "NosmaiCameraPreviewView.h"
#import <nosmai/Nosmai.h>
#import <Photos/Photos.h>

@interface NosmaiFlutterPlugin() <NosmaiDelegate, NosmaiCameraDelegate, NosmaiEffectsDelegate>
@property(nonatomic, strong) FlutterMethodChannel* channel;
@property(nonatomic, strong) UIView* previewView;
@property(nonatomic, assign) BOOL isInitialized;
@property(nonatomic, assign) BOOL isRecording;
@property(nonatomic, strong) NSTimer* recordingProgressTimer;
@property(nonatomic, strong) NSCache* filterCache;
@property(nonatomic, strong) NSArray* cachedLocalFilters;
@property(nonatomic, strong) NSDate* lastFilterCacheTime;
@property(nonatomic, assign) BOOL isCameraAttached;
@property(nonatomic, strong) dispatch_semaphore_t cameraStateSemaphore;
@end

@implementation NosmaiFlutterPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"nosmai_flutter"
            binaryMessenger:[registrar messenger]];
  NosmaiFlutterPlugin* instance = [[NosmaiFlutterPlugin alloc] init];
  instance.channel = channel;
  [registrar addMethodCallDelegate:instance channel:channel];
  
  // Register platform view factory for camera preview
  NosmaiCameraPreviewViewFactory* factory =
      [[NosmaiCameraPreviewViewFactory alloc] initWithMessenger:[registrar messenger]];
  [registrar registerViewFactory:factory withId:@"nosmai_camera_preview"];
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _isInitialized = NO;
    _isCameraAttached = NO;
    
    // Initialize filter cache for performance
    _filterCache = [[NSCache alloc] init];
    _filterCache.countLimit = 100; // Cache up to 100 filters
    _filterCache.totalCostLimit = 50 * 1024 * 1024; // 50MB limit for preview images
    
    // Initialize camera state semaphore for synchronization
    _cameraStateSemaphore = dispatch_semaphore_create(1);
  }
  return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString* method = call.method;
  
  if ([@"getPlatformVersion" isEqualToString:method]) {
    result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
  }
  else if ([@"initWithLicense" isEqualToString:method]) {
    [self handleInitWithLicense:call result:result];
  }
  else if ([@"configureCamera" isEqualToString:method]) {
    [self handleConfigureCamera:call result:result];
  }
  else if ([@"startProcessing" isEqualToString:method]) {
    [self handleStartProcessing:call result:result];
  }
  else if ([@"stopProcessing" isEqualToString:method]) {
    [self handleStopProcessing:call result:result];
  }
  // Built-in filter methods
  else if ([@"applyBrightnessFilter" isEqualToString:method]) {
    [self handleApplyBrightnessFilter:call result:result];
  }
  else if ([@"applyContrastFilter" isEqualToString:method]) {
    [self handleApplyContrastFilter:call result:result];
  }
  else if ([@"applyRGBFilter" isEqualToString:method]) {
    [self handleApplyRGBFilter:call result:result];
  }
  else if ([@"applySkinSmoothing" isEqualToString:method]) {
    [self handleApplySkinSmoothing:call result:result];
  }
  else if ([@"applySkinWhitening" isEqualToString:method]) {
    [self handleApplySkinWhitening:call result:result];
  }
  else if ([@"applyFaceSlimming" isEqualToString:method]) {
    [self handleApplyFaceSlimming:call result:result];
  }
  else if ([@"applyEyeEnlargement" isEqualToString:method]) {
    [self handleApplyEyeEnlargement:call result:result];
  }
  else if ([@"applyNoseSize" isEqualToString:method]) {
    [self handleApplyNoseSize:call result:result];
  }
  else if ([@"applySharpening" isEqualToString:method]) {
    [self handleApplySharpening:call result:result];
  }
  else if ([@"applyMakeupBlendLevel" isEqualToString:method]) {
    [self handleApplyMakeupBlendLevel:call result:result];
  }
  else if ([@"applyGrayscaleFilter" isEqualToString:method]) {
    [self handleApplyGrayscaleFilter:call result:result];
  }
  else if ([@"applyHue" isEqualToString:method]) {
    [self handleApplyHue:call result:result];
  }
  else if ([@"applyWhiteBalance" isEqualToString:method]) {
    [self handleApplyWhiteBalance:call result:result];
  }
  else if ([@"adjustHSB" isEqualToString:method]) {
    [self handleAdjustHSB:call result:result];
  }
  else if ([@"resetHSBFilter" isEqualToString:method]) {
    [self handleResetHSBFilter:call result:result];
  }
  else if ([@"removeBuiltInFilters" isEqualToString:method]) {
    [self handleRemoveBuiltInFilters:call result:result];
  }
  else if ([@"removeBuiltInFilterByName" isEqualToString:method]) {
    [self handleRemoveBuiltInFilterByName:call result:result];
  }
  else if ([@"getInitialFilters" isEqualToString:method]) {
    [self handleGetInitialFilters:call result:result];
  }
  else if ([@"fetchCloudFilters" isEqualToString:method]) {
    [self handleFetchCloudFilters:call result:result];
  }
  else if ([@"loadNosmaiFilter" isEqualToString:method]) {
    [self handleLoadNosmaiFilter:call result:result];
  }
  else if ([@"applyEffect" isEqualToString:method]) {
    [self handleApplyEffect:call result:result];
  }
  else if ([@"downloadCloudFilter" isEqualToString:method]) {
    [self handleDownloadCloudFilter:call result:result];
  }
  else if ([@"getCloudFilters" isEqualToString:method]) {
    [self handleGetCloudFilters:call result:result];
  }
  else if ([@"getLocalFilters" isEqualToString:method]) {
    [self handleGetLocalFilters:call result:result];
  }
  else if ([@"getFilters" isEqualToString:method]) {
    [self handleGetFilters:call result:result];
  }
  else if ([@"getEffectParameters" isEqualToString:method]) {
    [self handleGetEffectParameters:call result:result];
  }
  else if ([@"setEffectParameter" isEqualToString:method]) {
    [self handleSetEffectParameter:call result:result];
  }
  else if ([@"startRecording" isEqualToString:method]) {
    [self handleStartRecording:call result:result];
  }
  else if ([@"stopRecording" isEqualToString:method]) {
    [self handleStopRecording:call result:result];
  }
  else if ([@"isRecording" isEqualToString:method]) {
    [self handleIsRecording:call result:result];
  }
  else if ([@"getCurrentRecordingDuration" isEqualToString:method]) {
    [self handleGetCurrentRecordingDuration:call result:result];
  }
  else if ([@"switchCamera" isEqualToString:method]) {
    [self handleSwitchCamera:call result:result];
  }
  else if ([@"setFaceDetectionEnabled" isEqualToString:method]) {
    [self handleSetFaceDetectionEnabled:call result:result];
  }
  else if ([@"removeAllFilters" isEqualToString:method]) {
    [self handleRemoveAllFilters:call result:result];
  }
  else if ([@"cleanup" isEqualToString:method]) {
    [self handleCleanup:call result:result];
  }
  else if ([@"setPreviewView" isEqualToString:method]) {
    [self handleSetPreviewView:call result:result];
  }
  else if ([@"capturePhoto" isEqualToString:method]) {
    [self handleCapturePhoto:call result:result];
  }
  else if ([@"saveImageToGallery" isEqualToString:method]) {
    [self handleSaveImageToGallery:call result:result];
  }
  else if ([@"saveVideoToGallery" isEqualToString:method]) {
    [self handleSaveVideoToGallery:call result:result];
  }
  else if ([@"clearFilterCache" isEqualToString:method]) {
    [self handleClearFilterCache:call result:result];
  }
  else if ([@"detachCameraView" isEqualToString:method]) {
    [self handleDetachCameraView:call result:result];
  }
  else if ([@"reinitializePreview" isEqualToString:method]) {
    [self handleReinitializePreview:call result:result];
  }
  else if ([@"isBeautyEffectEnabled" isEqualToString:method]) {
    [self handleIsBeautyEffectEnabled:call result:result];
  }
  else if ([@"isCloudFilterEnabled" isEqualToString:method]) {
    [self handleIsCloudFilterEnabled:call result:result];
  }
  else {
    result(FlutterMethodNotImplemented);
  }
}

#pragma mark - SDK Initialization

- (void)handleInitWithLicense:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString* licenseKey = call.arguments[@"licenseKey"];
  
  if (!licenseKey || licenseKey.length == 0) {
    result([FlutterError errorWithCode:@"INVALID_LICENSE"
                               message:@"License key is required"
                               details:nil]);
    return;
  }
  
  // Set delegate first
  [NosmaiCore shared].delegate = self;
  
  // Initialize using the new modular SDK
  __weak typeof(self) weakSelf = self;
  [[NosmaiCore shared] initializeWithAPIKey:licenseKey completion:^(BOOL success, NSError *error) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    
    dispatch_async(dispatch_get_main_queue(), ^{
      strongSelf.isInitialized = success;
      
      if (success) {
        NSLog(@"✅ Nosmai Core initialized successfully");
        
        // Configure camera with default settings
        NosmaiCameraConfig *config = [[NosmaiCameraConfig alloc] init];
        config.position = NosmaiCameraPositionFront;
        config.sessionPreset = AVCaptureSessionPresetHigh;
        config.frameRate = 30;
        
        [[NosmaiCore shared].camera updateConfiguration:config];
        [[NosmaiCore shared].camera setDelegate:strongSelf];
        [[NosmaiCore shared].effects setDelegate:strongSelf];
        
        result(@YES);
      } else {
        NSLog(@"❌ Failed to initialize Nosmai Core: %@", error.localizedDescription);
        result([FlutterError errorWithCode:@"INIT_FAILED"
                                   message:error ? error.localizedDescription : @"Failed to initialize SDK with provided license"
                                   details:nil]);
      }
    });
  }];
}

#pragma mark - Camera Configuration

- (void)handleConfigureCamera:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before configuring camera"
                               details:nil]);
    return;
  }
  
  NSString* position = call.arguments[@"position"];
  NSString* sessionPreset = call.arguments[@"sessionPreset"];
  
  // Convert string position to enum
  NosmaiCameraPosition cameraPosition = NosmaiCameraPositionFront;
  if ([@"back" isEqualToString:position]) {
    cameraPosition = NosmaiCameraPositionBack;
  }
  
  // Use default preset if none provided
  if (!sessionPreset) {
    sessionPreset = AVCaptureSessionPresetHigh;
    NSLog(@"📱 Using default session preset: %@", sessionPreset);
  }
  
  @try {
    // Configure camera using the new modular API
    NosmaiCameraConfig *config = [[NosmaiCameraConfig alloc] init];
    config.position = cameraPosition;
    config.sessionPreset = sessionPreset;
    config.frameRate = 30;
    
    [[NosmaiCore shared].camera updateConfiguration:config];
    [[NosmaiCore shared].camera setDelegate:self];
    
    NSLog(@"📱 Camera configured: %@ with preset: %@", position, sessionPreset);
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"CAMERA_CONFIG_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

#pragma mark - Processing Control

- (void)handleStartProcessing:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before starting processing"
                               details:nil]);
    return;
  }
  
  @try {
    // 🔧 FIX: Start camera capture first
    BOOL success = [[NosmaiCore shared].camera startCapture];
    if (success) {
      [[NosmaiSDK sharedInstance] startProcessing];
      result(nil);
    } else {
      result([FlutterError errorWithCode:@"START_PROCESSING_ERROR"
                                 message:@"Failed to start camera capture"
                                 details:nil]);
    }
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"START_PROCESSING_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleStopProcessing:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before stopping processing"
                               details:nil]);
    return;
  }
  
  @try {
    // 🔧 FIX: Stop SDK processing first to avoid circular dependency
    [[NosmaiSDK sharedInstance] stopProcessing];
    // 🔧 FIX: Then stop camera capture
    [[NosmaiCore shared].camera stopCapture];
    NSLog(@"⏸️ SDK processing and camera capture stopped");
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"STOP_PROCESSING_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

#pragma mark - Built-in Filter Applications

- (void)handleApplyBrightnessFilter:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* brightness = call.arguments[@"brightness"];
  if (!brightness) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Brightness value is required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applyBrightnessFilter:brightness.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleApplyContrastFilter:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* contrast = call.arguments[@"contrast"];
  if (!contrast) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Contrast value is required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applyContrastFilter:contrast.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleApplyRGBFilter:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* red = call.arguments[@"red"];
  NSNumber* green = call.arguments[@"green"];
  NSNumber* blue = call.arguments[@"blue"];
  
  if (!red || !green || !blue) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"RGB values are required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applyRGBFilterWithRed:red.floatValue
                                                  green:green.floatValue
                                                   blue:blue.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleApplySkinSmoothing:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* level = call.arguments[@"level"];
  if (!level) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Level value is required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applySkinSmoothing:level.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleApplySkinWhitening:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* level = call.arguments[@"level"];
  if (!level) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Level value is required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applySkinWhitening:level.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleApplyFaceSlimming:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* level = call.arguments[@"level"];
  if (!level) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Level value is required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applyFaceSlimming:level.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleApplyEyeEnlargement:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* level = call.arguments[@"level"];
  if (!level) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Level value is required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applyEyeEnlargement:level.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleApplyNoseSize:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* level = call.arguments[@"level"];
  if (!level) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Level value is required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applyNoseSize:level.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleApplySharpening:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* level = call.arguments[@"level"];
  if (!level) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Level value is required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applySharpening:level.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleApplyMakeupBlendLevel:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSString* filterName = call.arguments[@"filterName"];
  NSNumber* level = call.arguments[@"level"];
  
  if (!filterName || !level) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Filter name and level are required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applyMakeupBlendLevel:filterName level:level.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleApplyGrayscaleFilter:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applyGrayscaleFilter];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleApplyHue:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* hueAngle = call.arguments[@"hueAngle"];
  if (!hueAngle) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Hue angle is required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applyHue:hueAngle.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}


- (void)handleApplyWhiteBalance:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* temperature = call.arguments[@"temperature"];
  NSNumber* tint = call.arguments[@"tint"];
  
  if (!temperature || !tint) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Temperature and tint are required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applyWhiteBalanceWithTemperature:temperature.floatValue
                                                              tint:tint.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}


- (void)handleAdjustHSB:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* hue = call.arguments[@"hue"];
  NSNumber* saturation = call.arguments[@"saturation"];
  NSNumber* brightness = call.arguments[@"brightness"];
  
  if (!hue || !saturation || !brightness) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Hue, saturation and brightness are required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects adjustHSBWithHue:hue.floatValue
                                        saturation:saturation.floatValue
                                        brightness:brightness.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleResetHSBFilter:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects resetHSBFilter];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleRemoveBuiltInFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before removing filters"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects removeBuiltInFilters];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleRemoveBuiltInFilterByName:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before removing filters"
                               details:nil]);
    return;
  }
  
  NSString* filterName = call.arguments[@"filterName"];
  if (!filterName) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Filter name is required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects removeBuiltInFilterByName:filterName];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

#pragma mark - File Loading and Camera Control

- (void)handleLoadNosmaiFilter:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before loading filters"
                               details:nil]);
    return;
  }
  
  NSString* filePath = call.arguments[@"filePath"];
  
  if (!filePath) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"File path is required"
                               details:nil]);
    return;
  }
  
  @try {
    // Use the new Effects Engine for loading filters
    [[NosmaiCore shared].effects applyEffect:filePath completion:^(BOOL success, NSError *error) {
      if (success) {
        NSLog(@"📁 Load Nosmai filter %@: SUCCESS", filePath);
        result(@(YES));
      } else {
        NSLog(@"📁 Load Nosmai filter %@: FAILED - %@", filePath, error.localizedDescription);
        result(@(NO));
      }
    }];
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"LOAD_FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleSwitchCamera:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before switching camera"
                               details:nil]);
    return;
  }
  
  @try {
    BOOL success = [[NosmaiCore shared].camera switchCamera];
    NSLog(@"📷 Camera switch: %@", success ? @"SUCCESS" : @"FAILED");
    result(@(success));
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"CAMERA_SWITCH_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleSetFaceDetectionEnabled:(FlutterMethodCall*)call result:(FlutterResult)result {
  // Face detection is automatically handled by the SDK for face-based filters
  NSLog(@"👤 Face detection is automatically managed by SDK");
  result(nil);
}

- (void)handleRemoveAllFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before removing filters"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects removeAllEffects];
    NSLog(@"🚫 All filters removed");
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"REMOVE_FILTERS_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleCleanup:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    if (self.isInitialized) {
      // 🔧 FIX: Call cleanup on NosmaiCore but keep SDK initialized for reuse
      [[NosmaiCore shared] cleanup];
      // Don't set isInitialized to NO - SDK remains ready for next use
      NSLog(@"🧹 SDK cleanup completed - ready for reuse");
    }
    
    // Clear filter cache during cleanup
    [self clearFilterCache];
    
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"CLEANUP_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleClearFilterCache:(FlutterMethodCall*)call result:(FlutterResult)result {
  [self clearFilterCache];
  NSLog(@"🧹 Filter cache cleared");
  result(nil);
}

- (void)clearFilterCache {
  [self.filterCache removeAllObjects];
  self.cachedLocalFilters = nil;
  self.lastFilterCacheTime = nil;
}

- (void)handleDetachCameraView:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    if (self.isInitialized) {
      // Use semaphore to ensure thread-safe camera detachment
      dispatch_semaphore_wait(self.cameraStateSemaphore, DISPATCH_TIME_FOREVER);
      
      NosmaiCore* core = [NosmaiCore shared];
      if (core && core.isInitialized && self.isCameraAttached) {
        [core.camera detachFromView];
        self.isCameraAttached = NO;
        NSLog(@"📺 Camera detached gracefully via Flutter method");
        
        // Notify Flutter that camera has been detached
        [self.channel invokeMethod:@"onCameraDetached" arguments:nil];
      }
      
      dispatch_semaphore_signal(self.cameraStateSemaphore);
    }
    result(nil);
  } @catch (NSException *exception) {
    dispatch_semaphore_signal(self.cameraStateSemaphore);
    result([FlutterError errorWithCode:@"DETACH_CAMERA_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleReinitializePreview:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before reinitializing preview"
                               details:nil]);
    return;
  }
  
  @try {
    // 🔧 FIX: Force preview view recreation by calling setPreviewView with nil then with the actual view
    if (self.previewView) {
      NSLog(@"🔄 Reinitializing preview view");
      
      // First set to nil to force cleanup
      [[NosmaiSDK sharedInstance] setPreviewView:nil];
      
      // Small delay to ensure cleanup
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Set the preview view again
        [[NosmaiSDK sharedInstance] setPreviewView:self.previewView];
        NSLog(@"✅ Preview view reinitialized");
        result(nil);
      });
    } else {
      NSLog(@"⚠️ No preview view to reinitialize");
      result(nil);
    }
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"REINIT_PREVIEW_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}




- (void)handleSetPreviewView:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before setting preview view"
                               details:nil]);
    return;
  }
  
  @try {
    // 🔧 FIX: Set preview view on SDK to ensure proper connection
    // This helps when navigating back to the camera view
    if (self.previewView) {
      [[NosmaiSDK sharedInstance] setPreviewView:self.previewView];
      NSLog(@"📺 Preview view set on NosmaiSDK");
    } else {
      NSLog(@"📺 Preview view setup will be handled by platform view");
    }
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"SET_PREVIEW_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

#pragma mark - New SDK Features

- (void)handleApplyEffect:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying effects"
                               details:nil]);
    return;
  }
  
  NSString* effectPath = call.arguments[@"effectPath"];
  
  if (!effectPath) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Effect path is required"
                               details:nil]);
    return;
  }
  
  [[NosmaiCore shared].effects applyEffect:effectPath completion:^(BOOL success, NSError *error) {
    if (success) {
      NSLog(@"✅ Effect applied successfully: %@", effectPath);
      result(@YES);
    } else {
      NSLog(@"❌ Failed to apply effect: %@", error.localizedDescription);
      result([FlutterError errorWithCode:@"EFFECT_ERROR"
                                 message:error ? error.localizedDescription : @"Failed to apply effect"
                                 details:nil]);
    }
  }];
}

- (void)handleDownloadCloudFilter:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before downloading cloud filters"
                               details:nil]);
    return;
  }
  
  NSString* filterId = call.arguments[@"filterId"];
  
  if (!filterId) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Filter ID is required"
                               details:nil]);
    return;
  }
  
  NSLog(@"🔄 Starting download for cloud filter: %@", filterId);
  
  // Use the same approach as VideoFilterController.mm - use NosmaiSDK directly
  [[NosmaiSDK sharedInstance] downloadCloudFilter:filterId
                                          progress:^(float progress) {
    NSLog(@"📥 Download progress for %@: %.1f%%", filterId, progress * 100);
    // Send progress updates to Flutter
    [self.channel invokeMethod:@"onDownloadProgress" arguments:@{
      @"filterId": filterId,
      @"progress": @(progress)
    }];
  }
                                        completion:^(BOOL success, NSString *localPath, NSError *error) {
    if (success) {
      NSLog(@"✅ Cloud filter downloaded successfully: %@ -> %@", filterId, localPath);
      result(@{
        @"success": @YES,
        @"localPath": localPath ?: @""
      });
    } else {
      NSLog(@"❌ Failed to download cloud filter %@: %@", filterId, error.localizedDescription ?: @"Unknown error");
      result([FlutterError errorWithCode:@"DOWNLOAD_ERROR"
                                 message:error ? error.localizedDescription : @"Failed to download cloud filter"
                                 details:@{@"filterId": filterId}]);
    }
  }];
}

- (void)handleGetCloudFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before getting cloud filters"
                               details:nil]);
    return;
  }
  
  // Use NosmaiSDK getCloudFilters with preview images like in native implementation
  NSArray<NSDictionary *> *cloudFilters = [[NosmaiSDK sharedInstance] getCloudFilters];
  
  if (cloudFilters) {
    // Process each cloud filter to add preview images
    NSMutableArray *enhancedFilters = [NSMutableArray array];
    
    for (NSDictionary *filter in cloudFilters) {
      NSMutableDictionary *enhancedFilter = [filter mutableCopy];
      
      // Safely get filter path, handling NSNull
      id pathValue = filter[@"path"];
      id localPathValue = filter[@"localPath"];
      NSString *filterPath = nil;
      
      if ([pathValue isKindOfClass:[NSString class]]) {
        filterPath = pathValue;
      } else if ([localPathValue isKindOfClass:[NSString class]]) {
        filterPath = localPathValue;
      }
      
      // Add filterCategory field if available from C++ CloudFilterInfo
      if (filter[@"filterCategory"] && ![filter[@"filterCategory"] isKindOfClass:[NSNull class]]) {
        enhancedFilter[@"filterCategory"] = filter[@"filterCategory"];
      }
      
      if (filterPath && [[NSFileManager defaultManager] fileExistsAtPath:filterPath]) {
        UIImage *previewImage = [[NosmaiSDK sharedInstance] loadPreviewImageForFilter:filterPath];
        if (previewImage) {
          // Convert UIImage to base64 string for Flutter
          NSData *imageData = UIImageJPEGRepresentation(previewImage, 0.7);
          if (imageData) {
            NSString *base64String = [imageData base64EncodedStringWithOptions:0];
            enhancedFilter[@"previewImageBase64"] = base64String;
          }
        }
      }
      
      [enhancedFilters addObject:enhancedFilter];
    }
    
    NSArray<NSDictionary *> *sanitizedFilters = [self sanitizeFiltersForFlutter:enhancedFilters];
    NSLog(@"✅ Retrieved %lu cloud filters with previews", (unsigned long)sanitizedFilters.count);
    result(sanitizedFilters ?: @[]);
  } else {
    NSLog(@"❌ Failed to get cloud filters from SDK");
    result([FlutterError errorWithCode:@"CLOUD_FILTERS_ERROR"
                               message:@"Failed to retrieve cloud filters"
                               details:nil]);
  }
}

- (void)handleGetLocalFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before getting local filters"
                               details:nil]);
    return;
  }
  
  NSArray<NSDictionary *> *filters = [[NosmaiSDK sharedInstance] getLocalFilters];
  NSArray<NSDictionary *> *sanitizedFilters = [self sanitizeFiltersForFlutter:filters];
  NSLog(@"✅ Retrieved %lu local filters", (unsigned long)sanitizedFilters.count);
  result(sanitizedFilters ?: @[]);
}

- (void)handleGetInitialFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before getting filters"
                               details:nil]);
    return;
  }
  
  // Get initial filters synchronously using the new SDK method
  NSDictionary<NSString*, NSArray<NSDictionary*>*> *organizedFilters = [[NosmaiSDK sharedInstance] getInitialFilters];
  
  // Convert to array format for Flutter
  NSMutableArray *allFilters = [NSMutableArray array];
  
  for (NSString *filterType in organizedFilters.allKeys) {
    NSArray<NSDictionary*> *filtersOfType = organizedFilters[filterType];
    for (NSDictionary *filter in filtersOfType) {
      NSMutableDictionary *enhancedFilter = [filter mutableCopy];
      enhancedFilter[@"filterType"] = filterType; // Add filter type for organization
      [allFilters addObject:enhancedFilter];
    }
  }
  
  NSArray *sanitizedFilters = [self sanitizeFiltersForFlutter:allFilters];
  result(sanitizedFilters ?: @[]);
}

- (void)handleFetchCloudFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before fetching cloud filters"
                               details:nil]);
    return;
  }
  
  // Set delegate to receive filter updates
  [[NosmaiSDK sharedInstance] setDelegate:self];
  
  // Trigger background cloud filter fetch
  [[NosmaiSDK sharedInstance] fetchCloudFilters];
  
  // Return immediately - updates will come through delegate
  result(nil);
}

- (void)handleGetFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before getting filters"
                               details:nil]);
    return;
  }
  
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    // First get initial filters for immediate display
    NSDictionary<NSString*, NSArray<NSDictionary*>*> *organizedFilters = [[NosmaiSDK sharedInstance] getInitialFilters];
    
    NSMutableArray *allFilters = [NSMutableArray array];
    
    // Process organized filters
    for (NSString *filterType in organizedFilters.allKeys) {
      NSArray<NSDictionary*> *filtersOfType = organizedFilters[filterType];
      
      for (NSDictionary *filter in filtersOfType) {
        NSMutableDictionary *enhancedFilter = [filter mutableCopy];
        
        // Ensure required fields have values (not NSNull)
        if (!enhancedFilter[@"name"] || [enhancedFilter[@"name"] isKindOfClass:[NSNull class]]) {
          NSLog(@"⚠️ Skipping filter with invalid name");
          continue;
        }
        
        // Add filter type for organization
        enhancedFilter[@"filterType"] = filterType;
        
        // Safely get filter path, handling NSNull
        id pathValue = filter[@"path"];
        id localPathValue = filter[@"localPath"];
        NSString *filterPath = nil;
        
        if ([pathValue isKindOfClass:[NSString class]]) {
          filterPath = pathValue;
        } else if ([localPathValue isKindOfClass:[NSString class]]) {
          filterPath = localPathValue;
        }
        
        if (filterPath && [[NSFileManager defaultManager] fileExistsAtPath:filterPath]) {
          UIImage *previewImage = [[NosmaiSDK sharedInstance] loadPreviewImageForFilter:filterPath];
          if (previewImage) {
            // Convert UIImage to base64 string for Flutter
            NSData *imageData = UIImageJPEGRepresentation(previewImage, 0.7);
            if (imageData) {
              NSString *base64String = [imageData base64EncodedStringWithOptions:0];
              enhancedFilter[@"previewImageBase64"] = base64String;
            }
          }
        }
        
        [allFilters addObject:enhancedFilter];
      }
    }
    
    NSLog(@"✅ Found %lu filters from SDK with previews", (unsigned long)allFilters.count);
    
    // Now add Flutter local filters on top
    NSArray<NSDictionary *> *localFilters = [self getFlutterLocalFilters];
    if (localFilters.count > 0) {
      NSLog(@"✅ Adding %lu Flutter local filters", (unsigned long)localFilters.count);
      [allFilters addObjectsFromArray:localFilters];
    }
    
    NSLog(@"✅ Retrieved %lu total filters", (unsigned long)allFilters.count);
    
    // Sanitize filters to ensure they only contain serializable data
    NSArray *sanitizedFilters = [self sanitizeFiltersForFlutter:allFilters];
    
    // Return result on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      result(sanitizedFilters ?: @[]);
      
      // Also trigger cloud filter fetch for updates
      [[NosmaiSDK sharedInstance] fetchCloudFilters];
    });
  });
}

- (NSArray<NSDictionary *> *)getFlutterLocalFilters {
  // Check cache first - only refresh every 5 minutes
  NSTimeInterval cacheValidDuration = 5 * 60; // 5 minutes
  NSDate *now = [NSDate date];
  
  if (self.cachedLocalFilters && self.lastFilterCacheTime && 
      [now timeIntervalSinceDate:self.lastFilterCacheTime] < cacheValidDuration) {
    NSLog(@"💾 Using cached local filters (%lu items)", (unsigned long)self.cachedLocalFilters.count);
    return self.cachedLocalFilters;
  }
  
  NSMutableArray *localFilters = [NSMutableArray array];
  
  // Dynamically discover all .nosmai files in assets/filters/ directory
  NSArray *discoveredFilterNames = [self discoverNosmaiFiltersInAssets];
  
  NSLog(@"🔍 Discovered %lu .nosmai files in assets/filters/", (unsigned long)discoveredFilterNames.count);
  
  for (NSString *filterName in discoveredFilterNames) {
    // Check if filter info is cached
    NSString *cacheKey = [NSString stringWithFormat:@"local_filter_%@", filterName];
    NSDictionary *cachedFilterInfo = [self.filterCache objectForKey:cacheKey];
    
    if (cachedFilterInfo) {
      [localFilters addObject:cachedFilterInfo];
      continue;
    }
    
    // Try to get Flutter asset path
    NSString *assetKey = [FlutterDartProject lookupKeyForAsset:[NSString stringWithFormat:@"assets/filters/%@.nosmai", filterName]];
    NSString *filePath = [[NSBundle mainBundle] pathForResource:assetKey ofType:nil];
    
    if (filePath && [[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
      NSMutableDictionary *filterInfo = [NSMutableDictionary dictionary];
      
      filterInfo[@"name"] = filterName;
      filterInfo[@"path"] = filePath;
      
      // Create display name by converting snake_case to Title Case
      NSString *displayName = [self createDisplayNameFromFilterName:filterName];
      filterInfo[@"displayName"] = displayName;
      
      // Get file size
      NSError *error = nil;
      NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
      if (!error && fileAttributes) {
        filterInfo[@"fileSize"] = fileAttributes[NSFileSize];
      } else {
        filterInfo[@"fileSize"] = @0;
      }
      
      filterInfo[@"type"] = @"local";
      filterInfo[@"isDownloaded"] = @YES;
      
      // Load preview image for local filters too
      UIImage *previewImage = [[NosmaiSDK sharedInstance] loadPreviewImageForFilter:filePath];
      if (previewImage) {
        // Convert UIImage to base64 string for Flutter
        NSData *imageData = UIImageJPEGRepresentation(previewImage, 0.7);
        if (imageData) {
          NSString *base64String = [imageData base64EncodedStringWithOptions:0];
          filterInfo[@"previewImageBase64"] = base64String;
          
          // Cache with image data size as cost
          [self.filterCache setObject:[filterInfo copy] forKey:cacheKey cost:imageData.length];
        }
      } else {
        // Cache without preview image
        [self.filterCache setObject:[filterInfo copy] forKey:cacheKey cost:1024];
      }
      
      [localFilters addObject:[filterInfo copy]];
      NSLog(@"✅ Found Flutter local filter: %@ at %@", filterName, filePath);
    } else {
      NSLog(@"❌ Could not find Flutter asset: assets/filters/%@.nosmai", filterName);
    }
  }
  
  // Cache the result
  self.cachedLocalFilters = [localFilters copy];
  self.lastFilterCacheTime = now;
  
  return [localFilters copy];
}

- (NSArray<NSDictionary *> *)sanitizeFiltersForFlutter:(NSArray<NSDictionary *> *)filters {
  NSMutableArray *sanitizedFilters = [NSMutableArray array];
  
  for (NSDictionary *filter in filters) {
    NSMutableDictionary *sanitizedFilter = [NSMutableDictionary dictionary];
    
    // Only include supported data types for Flutter StandardCodec
    for (NSString *key in filter.allKeys) {
      id value = filter[key];
      
      // Check if value is a supported type for Flutter StandardCodec
      if ([value isKindOfClass:[NSNull class]]) {
        // Convert NSNull to nil or appropriate default
        // Skip NSNull values as they cause issues in Flutter
        NSLog(@"⚠️ Skipping NSNull value for key: %@", key);
      } else if (value == nil) {
        // Skip nil values
        NSLog(@"⚠️ Skipping nil value for key: %@", key);
      } else if ([value isKindOfClass:[NSString class]] ||
                 [value isKindOfClass:[NSNumber class]] ||
                 [value isKindOfClass:[NSArray class]] ||
                 [value isKindOfClass:[NSDictionary class]] ||
                 [value isKindOfClass:[NSData class]]) {
        sanitizedFilter[key] = value;
      } else if ([value isKindOfClass:[UIImage class]]) {
        // Convert UIImage to base64 string or skip it
        NSLog(@"⚠️ Skipping UIImage value for key: %@", key);
        // Could convert to base64 if needed:
        // UIImage *image = (UIImage *)value;
        // NSData *imageData = UIImagePNGRepresentation(image);
        // sanitizedFilter[key] = [imageData base64EncodedStringWithOptions:0];
      } else {
        // Skip unsupported types
        NSLog(@"⚠️ Skipping unsupported value type %@ for key: %@", NSStringFromClass([value class]), key);
      }
    }
    
    [sanitizedFilters addObject:[sanitizedFilter copy]];
  }
  
  return [sanitizedFilters copy];
}

- (void)printAllFilterData:(NSArray<NSDictionary *> *)filters {
  NSLog(@"\n=================== FLUTTER FILTER DATA ANALYSIS ===================");
  NSLog(@"📊 Total Filters Found: %lu", (unsigned long)filters.count);
  
  if (!filters || filters.count == 0) {
    NSLog(@"❌ No filters found!");
    return;
  }
  
  for (int i = 0; i < filters.count; i++) {
    NSDictionary *filter = filters[i];
    
    NSLog(@"\n[%d] Filter Details:", i+1);
    NSLog(@"Filter Name: %@", filter[@"name"] ?: @"null");
    NSLog(@"Display Name: %@", filter[@"displayName"] ?: @"null");
    NSLog(@"Type: %@", filter[@"type"] ?: @"null");
    NSLog(@"Is Downloaded: %@", filter[@"isDownloaded"] ?: @"null");
    NSLog(@"File Size: %@", filter[@"fileSize"] ?: @"null");
    NSLog(@"Path: %@", filter[@"path"] ?: @"null");
    
    // Only show cloud-specific fields if they exist
    if (filter[@"filterId"]) {
      NSLog(@"Filter ID: %@", filter[@"filterId"]);
    } else {
      NSLog(@"Filter ID: null (MISSING!)");
    }
    if (filter[@"isFree"]) {
      NSLog(@"Is Free: %@", filter[@"isFree"]);
    }
    if (filter[@"localPath"]) {
      NSLog(@"Local Path: %@", filter[@"localPath"]);
    }
  }
  
  NSLog(@"=================== END FLUTTER FILTER ANALYSIS ===================\n");
}

- (void)handleGetEffectParameters:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before getting effect parameters"
                               details:nil]);
    return;
  }
  
  NSArray<NSDictionary *> *parameters = [[NosmaiCore shared].effects getEffectParameters];
  NSArray<NSDictionary *> *sanitizedParameters = [self sanitizeFiltersForFlutter:parameters];
  result(sanitizedParameters ?: @[]);
}

- (void)handleSetEffectParameter:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before setting effect parameters"
                               details:nil]);
    return;
  }
  
  NSString* parameterName = call.arguments[@"parameterName"];
  NSNumber* value = call.arguments[@"value"];
  
  if (!parameterName || !value) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Parameter name and value are required"
                               details:nil]);
    return;
  }
  
  BOOL success = [[NosmaiCore shared].effects setEffectParameter:parameterName value:value.floatValue];
  result(@(success));
}

- (void)handleStartRecording:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before starting recording"
                               details:nil]);
    return;
  }
  
  if (self.isRecording) {
    result([FlutterError errorWithCode:@"ALREADY_RECORDING"
                               message:@"Recording is already in progress"
                               details:nil]);
    return;
  }
  
  [[NosmaiCore shared] startRecordingWithCompletion:^(BOOL success, NSError *error) {
    if (success) {
      self.isRecording = YES;
      
      // Start recording progress timer
      self.recordingProgressTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                                      target:self
                                                                    selector:@selector(sendRecordingProgress)
                                                                    userInfo:nil
                                                                     repeats:YES];
      
      NSLog(@"✅ Recording started");
      result(@YES);
    } else {
      NSLog(@"❌ Failed to start recording: %@", error.localizedDescription);
      result([FlutterError errorWithCode:@"RECORDING_ERROR"
                                 message:error ? error.localizedDescription : @"Failed to start recording"
                                 details:nil]);
    }
  }];
}

- (void)handleStopRecording:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before stopping recording"
                               details:nil]);
    return;
  }
  
  if (!self.isRecording) {
    result([FlutterError errorWithCode:@"NOT_RECORDING"
                               message:@"No recording in progress"
                               details:nil]);
    return;
  }
  
  [[NosmaiCore shared] stopRecordingWithCompletion:^(NSURL *videoURL, NSError *error) {
    self.isRecording = NO;
    
    // Stop recording progress timer
    if (self.recordingProgressTimer) {
      [self.recordingProgressTimer invalidate];
      self.recordingProgressTimer = nil;
    }
    
    if (videoURL && !error) {
      NSTimeInterval duration = [[NosmaiCore shared] currentRecordingDuration];
      
      // Get file size
      NSError *fileError = nil;
      NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:videoURL.path error:&fileError];
      NSNumber *fileSize = fileError ? @0 : fileAttributes[NSFileSize];
      
      NSLog(@"✅ Recording stopped, saved to: %@", videoURL.path);
      result(@{
        @"success": @YES,
        @"videoPath": videoURL.path,
        @"duration": @(duration),
        @"fileSize": fileSize
      });
    } else {
      NSLog(@"❌ Failed to stop recording: %@", error.localizedDescription);
      result([FlutterError errorWithCode:@"RECORDING_ERROR"
                                 message:error ? error.localizedDescription : @"Failed to stop recording"
                                 details:nil]);
    }
  }];
}

- (void)handleIsRecording:(FlutterMethodCall*)call result:(FlutterResult)result {
  result(@(self.isRecording));
}

- (void)handleGetCurrentRecordingDuration:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized"
                               details:nil]);
    return;
  }
  
  NSTimeInterval duration = [[NosmaiCore shared] currentRecordingDuration];
  result(@(duration));
}


- (void)handleCapturePhoto:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized"
                               details:nil]);
    return;
  }
  
  // Use NosmaiCore's capturePhoto method like in the native iOS code
  [[NosmaiCore shared] capturePhoto:^(UIImage *image, NSError *error) {
    if (image) {
      // Convert UIImage to data
      NSData *imageData = UIImageJPEGRepresentation(image, 0.8);
      
      // Create result dictionary
      NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
      resultDict[@"success"] = @YES;
      resultDict[@"width"] = @(image.size.width);
      resultDict[@"height"] = @(image.size.height);
      
      if (imageData) {
        // Convert NSData to FlutterStandardTypedData
        FlutterStandardTypedData *typedData = [FlutterStandardTypedData typedDataWithBytes:imageData];
        resultDict[@"imageData"] = typedData;
      }
      
      result(resultDict);
    } else {
      // Handle error case
      NSString *errorMessage = error ? error.localizedDescription : @"Unknown error occurred while capturing photo";
      result(@{
        @"success": @NO,
        @"error": errorMessage
      });
    }
  }];
}

- (void)handleSaveImageToGallery:(FlutterMethodCall*)call result:(FlutterResult)result {
  FlutterStandardTypedData *imageData = call.arguments[@"imageData"];
  NSString *imageName = call.arguments[@"name"];
  
  if (!imageData || !imageData.data) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Image data is required"
                               details:nil]);
    return;
  }
  
  // Convert data to UIImage
  UIImage *image = [UIImage imageWithData:imageData.data];
  if (!image) {
    result([FlutterError errorWithCode:@"INVALID_IMAGE"
                               message:@"Could not create image from data"
                               details:nil]);
    return;
  }
  
  // Check authorization status
  PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
  if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
    result([FlutterError errorWithCode:@"PERMISSION_DENIED"
                               message:@"Photo library access denied"
                               details:nil]);
    return;
  }
  
  if (status == PHAuthorizationStatusNotDetermined) {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus authStatus) {
      if (authStatus == PHAuthorizationStatusAuthorized) {
        [self saveImageToPhotosApp:image withName:imageName result:result];
      } else {
        result([FlutterError errorWithCode:@"PERMISSION_DENIED"
                                   message:@"Photo library access denied"
                                   details:nil]);
      }
    }];
    return;
  }
  
  [self saveImageToPhotosApp:image withName:imageName result:result];
}

- (void)saveImageToPhotosApp:(UIImage *)image withName:(NSString *)name result:(FlutterResult)result {
  [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
    PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromImage:image];
    if (name) {
      request.creationDate = [NSDate date];
    }
  } completionHandler:^(BOOL success, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (success) {
        result(@{
          @"isSuccess": @YES,
          @"filePath": @"Photos App"
        });
      } else {
        result([FlutterError errorWithCode:@"SAVE_FAILED"
                                   message:error ? error.localizedDescription : @"Failed to save image"
                                   details:nil]);
      }
    });
  }];
}

- (void)handleSaveVideoToGallery:(FlutterMethodCall*)call result:(FlutterResult)result {
  NSString *videoPath = call.arguments[@"videoPath"];
  NSString *videoName = call.arguments[@"name"];
  
  if (!videoPath) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Video path is required"
                               details:nil]);
    return;
  }
  
  // Check if file exists
  if (![[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
    result([FlutterError errorWithCode:@"FILE_NOT_FOUND"
                               message:@"Video file not found"
                               details:nil]);
    return;
  }
  
  // Check authorization status
  PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
  if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
    result([FlutterError errorWithCode:@"PERMISSION_DENIED"
                               message:@"Photo library access denied"
                               details:nil]);
    return;
  }
  
  if (status == PHAuthorizationStatusNotDetermined) {
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus authStatus) {
      if (authStatus == PHAuthorizationStatusAuthorized) {
        [self saveVideoToPhotosApp:videoPath withName:videoName result:result];
      } else {
        result([FlutterError errorWithCode:@"PERMISSION_DENIED"
                                   message:@"Photo library access denied"
                                   details:nil]);
      }
    }];
    return;
  }
  
  [self saveVideoToPhotosApp:videoPath withName:videoName result:result];
}

- (void)saveVideoToPhotosApp:(NSString *)videoPath withName:(NSString *)name result:(FlutterResult)result {
  NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
  
  [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
    PHAssetChangeRequest *request = [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:videoURL];
    if (name) {
      request.creationDate = [NSDate date];
    }
  } completionHandler:^(BOOL success, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (success) {
        result(@{
          @"isSuccess": @YES,
          @"filePath": @"Photos App"
        });
      } else {
        result([FlutterError errorWithCode:@"SAVE_FAILED"
                                   message:error ? error.localizedDescription : @"Failed to save video"
                                   details:nil]);
      }
    });
  }];
}

#pragma mark - Delegate Methods

// NosmaiDelegate Methods
- (void)nosmaiDidChangeState:(NosmaiState)newState {
  NSLog(@"🔄 SDK state changed: %ld", (long)newState);
  [self.channel invokeMethod:@"onStateChanged" arguments:@{@"state": @(newState)}];
}

- (void)nosmaiDidFailWithError:(NSError *)error {
  NSLog(@"❌ SDK Error: %@", error.localizedDescription);
  [self.channel invokeMethod:@"onError" arguments:@{
    @"code": @(error.code),
    @"message": error.localizedDescription
  }];
}

- (void)nosmaiDidUpdateFilters:(NSDictionary<NSString*, NSArray<NSDictionary*>*>*)organizedFilters {
  NSLog(@"🔄 Filters updated from SDK");
  
  // Convert organized filters to array format for Flutter
  NSMutableArray *allFilters = [NSMutableArray array];
  
  for (NSString *filterType in organizedFilters.allKeys) {
    NSArray<NSDictionary*> *filtersOfType = organizedFilters[filterType];
    for (NSDictionary *filter in filtersOfType) {
      NSMutableDictionary *enhancedFilter = [filter mutableCopy];
      enhancedFilter[@"filterType"] = filterType;
      [allFilters addObject:enhancedFilter];
    }
  }
  
  // Sanitize and send to Flutter
  NSArray *sanitizedFilters = [self sanitizeFiltersForFlutter:allFilters];
  [self.channel invokeMethod:@"onFiltersUpdated" arguments:sanitizedFilters];
}

// NosmaiCameraDelegate Methods
- (void)nosmaiCameraDidStartCapture {
  NSLog(@"📹 Camera capture started");
  // Notify Flutter that camera is ready for processing
  [self.channel invokeMethod:@"onCameraReady" arguments:nil];
}

- (void)nosmaiCameraDidStopCapture {
  NSLog(@"📹 Camera capture stopped");
  // Notify Flutter that camera processing stopped
  [self.channel invokeMethod:@"onCameraProcessingStopped" arguments:nil];
}

- (void)nosmaiCameraDidSwitchToPosition:(NosmaiCameraPosition)position {
  NSLog(@"📷 Camera switched to position: %ld", (long)position);
}

- (void)nosmaiCameraDidFailWithError:(NSError *)error {
  NSLog(@"❌ Camera Error: %@", error.localizedDescription);
  [self.channel invokeMethod:@"onError" arguments:@{
    @"code": @"CAMERA_ERROR",
    @"message": error.localizedDescription
  }];
}

// Add missing camera state delegate method
- (void)nosmaiCameraDidAttachToView:(UIView *)view {
  NSLog(@"📺 Camera attached to view successfully");
  dispatch_semaphore_wait(self.cameraStateSemaphore, DISPATCH_TIME_FOREVER);
  self.isCameraAttached = YES;
  dispatch_semaphore_signal(self.cameraStateSemaphore);
  
  // Notify Flutter that camera is attached and ready
  [self.channel invokeMethod:@"onCameraAttached" arguments:nil];
}

- (void)nosmaiCameraDidDetachFromView {
  NSLog(@"📺 Camera detached from view");
  dispatch_semaphore_wait(self.cameraStateSemaphore, DISPATCH_TIME_FOREVER);
  self.isCameraAttached = NO;
  dispatch_semaphore_signal(self.cameraStateSemaphore);
  
  // Notify Flutter that camera has been detached
  [self.channel invokeMethod:@"onCameraDetached" arguments:nil];
}

// NosmaiEffectsDelegate Methods
- (void)nosmaiEffectsDidLoadEffect:(NSString *)effectPath {
  NSLog(@"✅ Effect loaded: %@", effectPath);
}

- (void)nosmaiEffectsDidFailToLoadEffect:(NSString *)effectPath error:(NSError *)error {
  NSLog(@"❌ Failed to load effect %@: %@", effectPath, error.localizedDescription);
  [self.channel invokeMethod:@"onError" arguments:@{
    @"code": @"EFFECT_ERROR",
    @"message": error.localizedDescription
  }];
}

- (void)nosmaiEffectsDidRemoveAllEffects {
  NSLog(@"🚫 All effects removed");
}

#pragma mark - Helper Methods

- (NSArray<NSString *> *)discoverNosmaiFiltersInAssets {
  NSMutableArray *filterNames = [NSMutableArray array];
  
  // Get the main bundle path
  NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
  NSFileManager *fileManager = [NSFileManager defaultManager];
  
  // Try multiple potential paths where Flutter assets might be stored
  NSArray *potentialPaths = @[
    @"flutter_assets/assets/filters",
    @"Frameworks/App.framework/flutter_assets/assets/filters",
    @"assets/filters"
  ];
  
  for (NSString *relativePath in potentialPaths) {
    NSString *fullPath = [bundlePath stringByAppendingPathComponent:relativePath];
    
    if ([fileManager fileExistsAtPath:fullPath]) {
      NSLog(@"📁 Found filters directory at: %@", fullPath);
      
      NSError *error = nil;
      NSArray *contents = [fileManager contentsOfDirectoryAtPath:fullPath error:&error];
      
      if (!error && contents) {
        for (NSString *fileName in contents) {
          if ([fileName hasSuffix:@".nosmai"]) {
            // Remove the .nosmai extension to get the filter name
            NSString *filterName = [fileName stringByDeletingPathExtension];
            if (![filterNames containsObject:filterName]) {
              [filterNames addObject:filterName];
              NSLog(@"🎨 Discovered filter: %@", filterName);
            }
          }
        }
      } else {
        NSLog(@"⚠️ Error reading directory %@: %@", fullPath, error.localizedDescription);
      }
    }
  }
  
  // Also try using Flutter's asset lookup mechanism
  [self discoverFiltersUsingFlutterAssetLookup:filterNames];
  
  // Sort alphabetically for consistent ordering
  [filterNames sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
  
  NSLog(@"🏁 Final discovered filter count: %lu", (unsigned long)filterNames.count);
  return [filterNames copy];
}

- (void)discoverFiltersUsingFlutterAssetLookup:(NSMutableArray *)filterNames {
  // Try to discover filters by attempting to look up common filter names
  // This is a fallback method when directory scanning doesn't work
  NSArray *commonFilterNames = @[
    @"ascii_art", @"halloween_animation", @"before_after_split",
    @"passingby_cube", @"prism_light_leak", @"serenity_cube",
    @"vintage", @"black_white", @"sepia", @"blur", @"sharpen",
    @"warm", @"cool", @"retro", @"film", @"neon", @"cyberpunk"
  ];
  
  for (NSString *filterName in commonFilterNames) {
    NSString *assetKey = [FlutterDartProject lookupKeyForAsset:[NSString stringWithFormat:@"assets/filters/%@.nosmai", filterName]];
    NSString *filePath = [[NSBundle mainBundle] pathForResource:assetKey ofType:nil];
    
    if (filePath && [[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
      if (![filterNames containsObject:filterName]) {
        [filterNames addObject:filterName];
        NSLog(@"🔍 Found filter via asset lookup: %@", filterName);
      }
    }
  }
}

- (NSString *)createDisplayNameFromFilterName:(NSString *)filterName {
  if (!filterName || filterName.length == 0) {
    return @"Unknown Filter";
  }
  
  // Convert snake_case or kebab-case to Title Case
  NSString *displayName = filterName;
  
  // Replace underscores and hyphens with spaces
  displayName = [displayName stringByReplacingOccurrencesOfString:@"_" withString:@" "];
  displayName = [displayName stringByReplacingOccurrencesOfString:@"-" withString:@" "];
  
  // Handle special cases for better naming
  NSDictionary *specialCases = @{
    @"ascii art": @"ASCII Art",
    @"halloween animation": @"Halloween Animation",
    @"before after split": @"Before After Split",
    @"passingby cube": @"Passing Cube",
    @"prism light leak": @"Prism Light Leak",
    @"serenity cube": @"Serenity Cube",
    @"black white": @"Black & White",
    @"light leak": @"Light Leak",
    @"film grain": @"Film Grain"
  };
  
  NSString *lowerDisplayName = [displayName lowercaseString];
  if (specialCases[lowerDisplayName]) {
    return specialCases[lowerDisplayName];
  }
  
  // Capitalize each word
  NSArray *words = [displayName componentsSeparatedByString:@" "];
  NSMutableArray *capitalizedWords = [NSMutableArray array];
  
  for (NSString *word in words) {
    if (word.length > 0) {
      NSString *capitalizedWord = [word stringByReplacingCharactersInRange:NSMakeRange(0,1)
                                                                withString:[[word substringToIndex:1] uppercaseString]];
      [capitalizedWords addObject:capitalizedWord];
    }
  }
  
  return [capitalizedWords componentsJoinedByString:@" "];
}

#pragma mark - License Feature Methods

- (void)handleIsBeautyEffectEnabled:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before checking license features"
                               details:nil]);
    return;
  }
  
  @try {
    BOOL isEnabled = [[NosmaiCore shared].effects isBeautyEffectEnabled];
    result(@(isEnabled));
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"LICENSE_CHECK_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleIsCloudFilterEnabled:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before checking license features"
                               details:nil]);
    return;
  }
  
  @try {
    BOOL isEnabled = [[NosmaiCore shared].effects isCloudFilterEnabled];
    result(@(isEnabled));
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"LICENSE_CHECK_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

// SDK callbacks are handled internally

- (void)sendRecordingProgress {
  if (self.isRecording) {
    NSTimeInterval duration = [[NosmaiCore shared] currentRecordingDuration];
    [self.channel invokeMethod:@"onRecordingProgress" arguments:@{
      @"duration": @(duration)
    }];
  }
}

- (void)dealloc {
  if (self.recordingProgressTimer) {
    [self.recordingProgressTimer invalidate];
    self.recordingProgressTimer = nil;
  }
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end