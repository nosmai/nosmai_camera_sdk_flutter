#import "NosmaiFlutterPlugin.h"
#import "NosmaiCameraPreviewView.h"
#import <nosmai/Nosmai.h>
#import <Photos/Photos.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <sys/socket.h>
#import <netinet/in.h>

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
      methodChannelWithName:@"nosmai_camera_sdk"
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
  else if ([@"startLiveFrameStream" isEqualToString:method]) {
    [self handleStartLiveFrameStream:call result:result];
  }
  else if ([@"stopLiveFrameStream" isEqualToString:method]) {
    [self handleStopLiveFrameStream:call result:result];
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
        // Only set delegates during initialization, don't configure camera yet
        // Camera will be configured when user explicitly opens camera
        [[NosmaiCore shared].camera setDelegate:strongSelf];
        [[NosmaiCore shared].effects setDelegate:strongSelf];
        
        result(@YES);
      } else {
        result([FlutterError errorWithCode:@"INIT_FAILED"
                                   message:error ? error.localizedDescription : @"Failed to initialize SDK with provided license"
                                   details:nil]);
      }
    });
  }];
}

#pragma mark - Live Frame Streaming
- (void)handleStartLiveFrameStream:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before starting the frame stream"
                               details:nil]);
    return;
  }
  
  // Live frame streaming not implemented in this version
  result([FlutterError errorWithCode:@"NOT_IMPLEMENTED"
                             message:@"Live frame streaming is not implemented"
                             details:nil]);
  
}

- (void)handleStopLiveFrameStream:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before stopping the frame stream"
                               details:nil]);
    return;
  }
  
  result([FlutterError errorWithCode:@"NOT_IMPLEMENTED"
                             message:@"Live frame streaming is not implemented"
                             details:nil]);
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
  
  // Validate input parameters
  if (!position || (![position isEqualToString:@"front"] && ![position isEqualToString:@"back"])) {
    result([FlutterError errorWithCode:@"INVALID_PARAMETER"
                               message:@"Camera position must be 'front' or 'back'"
                               details:@{@"position": position ?: @"null"}]);
    return;
  }
  
  // Convert string position to enum
  NosmaiCameraPosition cameraPosition = NosmaiCameraPositionFront;
  if ([@"back" isEqualToString:position]) {
    cameraPosition = NosmaiCameraPositionBack;
  }
  
  // Use default preset if none provided
  if (!sessionPreset) {
    sessionPreset = AVCaptureSessionPresetHigh;
  }
  
  NSDate *startTime = [NSDate date];
  
  // Configure camera synchronously for immediate availability
  @try {
    // Configure camera using the new modular API
    NosmaiCameraConfig *config = [[NosmaiCameraConfig alloc] init];
    config.position = cameraPosition;
    config.sessionPreset = sessionPreset;
    config.frameRate = 30;
    
    [[NosmaiCore shared].camera updateConfiguration:config];
    [[NosmaiCore shared].camera setDelegate:self];
    
    NSTimeInterval configTime = [[NSDate date] timeIntervalSinceDate:startTime];
    
    result(nil);
    
  } @catch (NSException *exception) {
    NSTimeInterval configTime = [[NSDate date] timeIntervalSinceDate:startTime];
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
  
  NSDate *startTime = [NSDate date];
  
  @try {
    // Start camera capture first
    BOOL success = [[NosmaiCore shared].camera startCapture];
    if (success) {
      [[NosmaiSDK sharedInstance] startProcessing];
      NSTimeInterval processingTime = [[NSDate date] timeIntervalSinceDate:startTime];
      result(nil);
    } else {
      NSTimeInterval processingTime = [[NSDate date] timeIntervalSinceDate:startTime];
      result([FlutterError errorWithCode:@"CAMERA_START_ERROR"
                                 message:@"Failed to start camera capture"
                                 details:nil]);
    }
  } @catch (NSException *exception) {
    NSTimeInterval processingTime = [[NSDate date] timeIntervalSinceDate:startTime];
    result([FlutterError errorWithCode:@"PROCESSING_START_ERROR"
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
  
  if (!filePath || filePath.length == 0) {
    result([FlutterError errorWithCode:@"INVALID_PARAMETER"
                               message:@"Filter file path cannot be empty"
                               details:@{@"filePath": filePath ?: @"null"}]);
    return;
  }
  
  // Check if file exists
  if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
    result([FlutterError errorWithCode:@"FILTER_NOT_FOUND"
                               message:@"Filter file not found at specified path"
                               details:@{@"filePath": filePath}]);
    return;
  }
  
  @try {
    // Use the new Effects Engine for loading filters
    [[NosmaiCore shared].effects applyEffect:filePath completion:^(BOOL success, NSError *error) {
      if (success) {
        result(@(YES));
      } else {
        
        // Determine specific error type
        NSString *errorCode = @"FILTER_LOAD_ERROR";
        NSString *errorMessage = @"Failed to load filter";
        
        if (error) {
          if ([error.localizedDescription containsString:@"format"] || [error.localizedDescription containsString:@"invalid"]) {
            errorCode = @"FILTER_INVALID_FORMAT";
            errorMessage = @"Filter file format is invalid or corrupted";
          } else if ([error.localizedDescription containsString:@"version"]) {
            errorCode = @"FILTER_UNSUPPORTED_VERSION";
            errorMessage = @"Filter file version is not supported";
          } else if ([error.localizedDescription containsString:@"not found"]) {
            errorCode = @"FILTER_NOT_FOUND";
            errorMessage = @"Filter file not found";
          }
        }
        
        result([FlutterError errorWithCode:errorCode
                                   message:errorMessage
                                   details:@{
                                     @"filePath": filePath,
                                     @"originalError": error.localizedDescription ?: @"Unknown error"
                                   }]);
      }
    }];
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_LOAD_ERROR"
                               message:exception.reason ?: @"Failed to load filter"
                               details:@{
                                 @"filePath": filePath,
                                 @"originalError": exception.reason ?: @"Unknown error"
                               }]);
  }
}

- (void)handleSwitchCamera:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before switching camera"
                               details:nil]);
    return;
  }
  
  // Perform camera switch on main thread to avoid UI issues
  dispatch_async(dispatch_get_main_queue(), ^{
    @try {
      BOOL success = [[NosmaiCore shared].camera switchCamera];
      
      // Send result back on main thread
      dispatch_async(dispatch_get_main_queue(), ^{
        if (success) {
          result(@(success));
        } else {
          result([FlutterError errorWithCode:@"CAMERA_SWITCH_FAILED"
                                     message:@"Camera switch operation failed"
                                     details:@{@"reason": @"Switch operation returned false"}]);
        }
      });
    } @catch (NSException *exception) {
      dispatch_async(dispatch_get_main_queue(), ^{
        NSString *errorCode = @"CAMERA_SWITCH_FAILED";
        NSString *errorMessage = exception.reason ?: @"Camera switch failed";
        
        // Check for specific error conditions
        if ([exception.reason containsString:@"unavailable"] || [exception.reason containsString:@"not found"]) {
          errorCode = @"CAMERA_UNAVAILABLE";
          errorMessage = @"Camera is not available";
        } else if ([exception.reason containsString:@"permission"]) {
          errorCode = @"CAMERA_PERMISSION_DENIED";
          errorMessage = @"Camera permission is required";
        }
        
        result([FlutterError errorWithCode:errorCode
                                   message:errorMessage
                                   details:@{@"originalError": exception.reason ?: @"Unknown error"}]);
      });
    }
  });
}

- (void)handleSetFaceDetectionEnabled:(FlutterMethodCall*)call result:(FlutterResult)result {
  // Face detection is automatically handled by the SDK for face-based filters
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
      
      // First set to nil to force cleanup
      [[NosmaiSDK sharedInstance] setPreviewView:nil];
      
      // Small delay to ensure cleanup
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Set the preview view again
        [[NosmaiSDK sharedInstance] setPreviewView:self.previewView];
        result(nil);
      });
    } else {
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
    } else {
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
      result(@YES);
    } else {
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
  
  // Check if filter is already downloaded
  if ([[NosmaiSDK sharedInstance] isCloudFilterDownloaded:filterId]) {
    NSString* localPath = [[NosmaiSDK sharedInstance] getCloudFilterLocalPath:filterId];
    result(@{
      @"success": @YES,
      @"localPath": localPath ?: @"",
      @"path": localPath ?: @""
    });
    return;
  }
  
  
  // Use the same approach as VideoFilterController.mm - use NosmaiSDK directly
  [[NosmaiSDK sharedInstance] downloadCloudFilter:filterId
                                          progress:^(float progress) {
    // Send progress updates to Flutter
    [self.channel invokeMethod:@"onDownloadProgress" arguments:@{
      @"filterId": filterId,
      @"progress": @(progress)
    }];
  }
                                        completion:^(BOOL success, NSString *localPath, NSError *error) {
    if (success) {
      result(@{
        @"success": @YES,
        @"localPath": localPath ?: @"",
        @"path": localPath ?: @""
      });
    } else {
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
  
  if (cloudFilters && cloudFilters.count > 0) {
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
      
      // Add type field for cloud filters - this is required by NosmaiCloudFilter.fromMap
      // Store the original type (free/paid) in a separate field and set type to "cloud"
      if (enhancedFilter[@"type"]) {
        enhancedFilter[@"originalType"] = enhancedFilter[@"type"];
      }
      enhancedFilter[@"type"] = @"cloud";
      
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
    result(sanitizedFilters ?: @[]);
  } else {
    // Return empty array instead of error - cloud filters might not be available
    // due to network issues, license restrictions, or no filters configured
    NSLog(@"Cloud filters not available - returning empty array");
    result(@[]);
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
      // Don't override filterType here - let mapFrameworkKeysToPluginKeys determine it correctly
      // enhancedFilter[@"filterType"] = filterType; // Add filter type for organization
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
  
  // Check network connectivity before attempting cloud filter fetch
  if (![self isNetworkAvailable]) {
    result(nil);
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

  // Perform all data fetching and processing on a background thread
  // to keep the UI responsive.
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    
    // 1. Get initial filters from the Nosmai SDK
    NSDictionary<NSString*, NSArray<NSDictionary*>*> *organizedFilters = [[NosmaiSDK sharedInstance] getInitialFilters];
    
    NSMutableArray *allFilters = [NSMutableArray array];
    
    // Process the organized filters from the SDK
    for (NSString *filterType in organizedFilters.allKeys) {
      NSArray<NSDictionary*> *filtersOfType = organizedFilters[filterType];
      
      for (NSDictionary *filter in filtersOfType) {
        NSMutableDictionary *enhancedFilter = [filter mutableCopy];
        
        // Basic validation to prevent crashes from null names
        if (!enhancedFilter[@"name"] || [enhancedFilter[@"name"] isKindOfClass:[NSNull class]]) {
          continue;
        }
        
        // Set filterType from SDK's organization
        enhancedFilter[@"filterType"] = filterType;
        
        // Safely get the filter path for preview loading
        id pathValue = filter[@"localPath"] ?: filter[@"path"];
        if ([pathValue isKindOfClass:[NSString class]] && [[NSFileManager defaultManager] fileExistsAtPath:pathValue]) {
          UIImage *previewImage = [[NosmaiSDK sharedInstance] loadPreviewImageForFilter:pathValue];
          if (previewImage) {
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
    
    // 2. Add local filters defined in the Flutter project's assets
    NSArray<NSDictionary *> *localFilters = [self getFlutterLocalFilters];
    if (localFilters.count > 0) {
      [allFilters addObjectsFromArray:localFilters];
    }

    // 3. Sanitize the final combined list for safe transport to Flutter
    NSArray *sanitizedFilters = [self sanitizeFiltersForFlutter:allFilters];

    // ================== LOGGING CALL ==================
    // Log the final data right before sending it to Flutter.
    [self printAllFilterData:sanitizedFilters ofType:@"All Combined Filters (Final)"];
    // ==================================================

    // 4. Return the final result to Flutter on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      // This is the ONLY place 'result' should be called for this method.
      result(sanitizedFilters ?: @[]);
      
      // 5. After providing the initial list, trigger a background fetch for any new cloud filters.
      // This gives the user an immediate list to work with while updates happen in the background.
      if ([self isNetworkAvailable]) {
        [[NosmaiSDK sharedInstance] fetchCloudFilters];
      } else {
      }
    });
  });
}
- (NSArray<NSDictionary *> *)getFlutterLocalFilters {
  // Check cache first - only refresh every 5 minutes
  NSTimeInterval cacheValidDuration = 5 * 60; // 5 minutes
  NSDate *now = [NSDate date];
  
  if (self.cachedLocalFilters && self.lastFilterCacheTime && 
      [now timeIntervalSinceDate:self.lastFilterCacheTime] < cacheValidDuration) {
    return self.cachedLocalFilters;
  }
  
  NSMutableArray *localFilters = [NSMutableArray array];
  
  // Dynamically discover all .nosmai files in assets/filters/ directory
  NSArray *discoveredFilterNames = [self discoverNosmaiFiltersInAssets];
  
  
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
    } else {
    }
  }
  
  // Cache the result
  self.cachedLocalFilters = [localFilters copy];
  self.lastFilterCacheTime = now;
  
  return [localFilters copy];
}

- (NSDictionary *)mapFrameworkKeysToPluginKeys:(NSDictionary *)frameworkFilter {
  NSMutableDictionary *pluginFilter = [NSMutableDictionary dictionary];
  
  // Debug: Log the original framework filter data
  // Debug logging removed for production
  
  // Map basic required fields
  pluginFilter[@"id"] = frameworkFilter[@"id"] ?: frameworkFilter[@"name"] ?: @"";
  pluginFilter[@"name"] = frameworkFilter[@"name"] ?: @"";
  pluginFilter[@"description"] = frameworkFilter[@"description"] ?: @"";
  pluginFilter[@"displayName"] = frameworkFilter[@"displayName"] ?: frameworkFilter[@"name"] ?: @"";
  
  // Map path (framework can use both localPath and path)
  NSString *path = frameworkFilter[@"path"] ?: frameworkFilter[@"localPath"] ?: @"";
  // Don't set empty paths - let Flutter handle missing paths
  if (path.length > 0) {
    pluginFilter[@"path"] = path;
  } else {
    pluginFilter[@"path"] = @"";
  }
  
  // Debug logging for path mapping
  NSLog(@"🔍 Path mapping debug for %@:", frameworkFilter[@"name"] ?: @"Unknown");
  NSLog(@"   - Framework localPath: %@", frameworkFilter[@"localPath"] ?: @"null");
  NSLog(@"   - Framework path: %@", frameworkFilter[@"path"] ?: @"null");
  NSLog(@"   - Final mapped path: %@", path);
  
  // Map file size
  pluginFilter[@"fileSize"] = frameworkFilter[@"fileSize"] ?: @0;
  
  // Map type (framework and plugin both use same values)
  pluginFilter[@"type"] = frameworkFilter[@"type"] ?: @"local";
  
  // Map filterCategory (framework uses specific categories, plugin uses generic ones)
  NSString *frameworkCategory = frameworkFilter[@"filterCategory"];
  if (frameworkCategory) {
    if ([frameworkCategory isEqualToString:@"beauty-effects"]) {
      pluginFilter[@"filterCategory"] = @"beauty";
    } else if ([frameworkCategory isEqualToString:@"special-effects"]) {
      pluginFilter[@"filterCategory"] = @"effect";
    } else if ([frameworkCategory isEqualToString:@"cloud-filters"] || 
               [frameworkCategory isEqualToString:@"fx-and-filters"]) {
      pluginFilter[@"filterCategory"] = @"filter";
    } else {
      pluginFilter[@"filterCategory"] = @"unknown";
    }
  } else {
    pluginFilter[@"filterCategory"] = @"unknown";
  }
  
  // Map filterType - for cloud filters use filterCategory, for local filters preserve SDK's filterType
  NSString *filterType = frameworkFilter[@"filterType"] ?: @"effect"; // Use SDK's filterType or default
  
  // For cloud filters, determine type from filterCategory (override SDK's filterType)
  if ([frameworkFilter[@"type"] isEqualToString:@"cloud"]) {
    NSString *category = frameworkFilter[@"filterCategory"];
    NSLog(@"🔍 FilterType determination for %@: type=%@, category=%@", 
          frameworkFilter[@"name"] ?: @"Unknown", 
          frameworkFilter[@"type"] ?: @"null", 
          category ?: @"null");
    
    if ([category hasPrefix:@"fx-and-filters"]) {
      filterType = @"filter";
      NSLog(@"   -> Setting filterType to 'filter' (fx-and-filters)");
    } else if ([category hasPrefix:@"special-effects"]) {
      filterType = @"effect";
      NSLog(@"   -> Setting filterType to 'effect' (special-effects)");
    } else {
      NSLog(@"   -> Using default filterType 'effect' (unknown category)");
    }
  } else {
    // For local filters and others, use SDK's filterType
    NSLog(@"🔍 FilterType determination for %@: type=%@, using SDK filterType: %@", 
          frameworkFilter[@"name"] ?: @"Unknown", 
          frameworkFilter[@"type"] ?: @"null",
          filterType);
  }
  
  pluginFilter[@"filterType"] = filterType;
  
  // Map cloud-specific properties
  pluginFilter[@"isFree"] = frameworkFilter[@"isFree"] ?: @YES;
  pluginFilter[@"isDownloaded"] = frameworkFilter[@"isDownloaded"] ?: @YES;
  pluginFilter[@"previewUrl"] = frameworkFilter[@"previewUrl"] ?: frameworkFilter[@"thumbnailUrl"];
  pluginFilter[@"category"] = frameworkFilter[@"category"];
  pluginFilter[@"downloadCount"] = frameworkFilter[@"downloadCount"] ?: @0;
  pluginFilter[@"price"] = frameworkFilter[@"price"] ?: @0;
  
  // Pass through other fields that might be useful
  if (frameworkFilter[@"previewImageBase64"]) {
    pluginFilter[@"previewImageBase64"] = frameworkFilter[@"previewImageBase64"];
  }
  
  return [pluginFilter copy];
}

- (NSArray<NSDictionary *> *)sanitizeFiltersForFlutter:(NSArray<NSDictionary *> *)filters {
  NSMutableArray *sanitizedFilters = [NSMutableArray array];
  
  for (NSDictionary *filter in filters) {
    // First map framework keys to plugin keys
    NSDictionary *mappedFilter = [self mapFrameworkKeysToPluginKeys:filter];
    
    // Debug the mapping result
    NSLog(@"🔍 Mapped filter result for %@:", mappedFilter[@"name"] ?: @"Unknown");
    NSLog(@"   - Mapped path: %@", mappedFilter[@"path"] ?: @"null");
    NSLog(@"   - Mapped filterType: %@", mappedFilter[@"filterType"] ?: @"null");
    
    NSMutableDictionary *sanitizedFilter = [NSMutableDictionary dictionary];
    
    // Only include supported data types for Flutter StandardCodec
    for (NSString *key in mappedFilter.allKeys) {
      id value = mappedFilter[key];
      
      // Check if value is a supported type for Flutter StandardCodec
      if ([value isKindOfClass:[NSNull class]]) {
        // Convert NSNull to nil or appropriate default
        // Skip NSNull values as they cause issues in Flutter
        NSLog(@"⚠️ Skipping NSNull value for key: %@", key);
      } else if (value == nil) {
        // Skip nil values
        NSLog(@"⚠️ Skipping nil value for key: %@", key);
      } else if ([value isKindOfClass:[NSString class]]) {
        // Handle strings specially - don't skip empty strings for path
        NSString *stringValue = (NSString *)value;
        if ([key isEqualToString:@"path"] && stringValue.length > 0) {
          NSLog(@"✅ Including path: %@", stringValue);
        }
        sanitizedFilter[key] = value;
      } else if ([value isKindOfClass:[NSNumber class]] ||
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

// - (void)printAllFilterData:(NSArray<NSDictionary *> *)filters {
//   NSLog(@"\n=================== FLUTTER FILTER DATA ANALYSIS ===================");
//   NSLog(@"📊 Total Filters Found: %lu", (unsigned long)filters.count);
  
//   if (!filters || filters.count == 0) {
//     NSLog(@"❌ No filters found!");
//     return;
//   }
  
//   for (int i = 0; i < filters.count; i++) {
//     NSDictionary *filter = filters[i];
    
//     NSLog(@"\n[%d] Filter Details:", i+1);
//     NSLog(@"Filter Name: %@", filter[@"name"] ?: @"null");
//     NSLog(@"Display Name: %@", filter[@"displayName"] ?: @"null");
//     NSLog(@"Type: %@", filter[@"type"] ?: @"null");
//     NSLog(@"Is Downloaded: %@", filter[@"isDownloaded"] ?: @"null");
//     NSLog(@"File Size: %@", filter[@"fileSize"] ?: @"null");
//     NSLog(@"Path: %@", filter[@"path"] ?: @"null");
    
//     // Only show cloud-specific fields if they exist
//     if (filter[@"filterId"]) {
//       NSLog(@"Filter ID: %@", filter[@"filterId"]);
//     } else {
//       NSLog(@"Filter ID: null (MISSING!)");
//     }
//     if (filter[@"isFree"]) {
//       NSLog(@"Is Free: %@", filter[@"isFree"]);
//     }
//     if (filter[@"localPath"]) {
//       NSLog(@"Local Path: %@", filter[@"localPath"]);
//     }
//   }
  
//   NSLog(@"=================== END FLUTTER FILTER ANALYSIS ===================\n");
// }


- (void)printAllFilterData:(NSArray<NSDictionary *> *)filters ofType:(NSString *)filterCategoryName {
    NSLog(@"\n=================== NOSMAI FILTER DATA ANALYSIS (%@) ===================", [filterCategoryName uppercaseString]);
    NSLog(@"📊 Total '%@' Filters Found: %lu", filterCategoryName, (unsigned long)filters.count);

    if (!filters || filters.count == 0) {
        NSLog(@"❌ No filters found for this category!");
        NSLog(@"========================================================================\n");
        return;
    }

    for (int i = 0; i < filters.count; i++) {
        NSDictionary *filter = filters[i];

        // Use a more descriptive name if available (displayName > name)
        NSString *logName = filter[@"displayName"] ?: filter[@"name"];
        NSLog(@"\n[%d] Filter: '%@'", i + 1, logName ?: @"Unnamed Filter");
        NSLog(@"--------------------------------------------------");

        // --- Core Identification ---
        NSLog(@"  Name         : %@", filter[@"name"] ?: @"null");
        NSLog(@"  Display Name : %@", filter[@"displayName"] ?: @"null");

        // --- Type & Category Information ---
        NSLog(@"  Type         : %@", filter[@"type"] ?: @"null"); // e.g., "cloud", "nosmai", "special"
        NSLog(@"  Filter Type  : %@", filter[@"filterType"] ?: @"null"); // Custom type from Flutter
        NSLog(@"  Category     : %@", filter[@"category"] ?: filter[@"filterCategory"] ?: @"null"); // e.g., "Beauty", "Effect"

        // --- Download & Path Status ---
        NSLog(@"  Is Downloaded: %@", [filter[@"isDownloaded"] boolValue] ? @"YES" : @"NO");
        NSLog(@"  Path         : %@", filter[@"path"] ?: @"null");
        NSLog(@"  Local Path   : %@", filter[@"localPath"] ?: @"null"); // Often same as path after download

        // --- Cloud-Specific Fields ---
        if ([filter[@"type"] isEqualToString:@"cloud"]) {
            NSLog(@"  Filter ID    : %@", filter[@"filterId"] ?: @"null (MISSING!)");
            NSLog(@"  Is Free      : %@", [filter[@"isFree"] boolValue] ? @"YES" : @"NO");
            NSLog(@"  File Size    : %@", filter[@"fileSize"] ? [NSString stringWithFormat:@"%@ bytes", filter[@"fileSize"]] : @"null");
            NSLog(@"  Preview URL  : %@", filter[@"previewUrl"] ?: filter[@"thumbnailUrl"] ?: @"null");
        }
    }
    NSLog(@"\n=================== END OF ANALYSIS (%@) ===================\n", [filterCategoryName uppercaseString]);
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

// - (void)nosmaiDidUpdateFilters:(NSDictionary<NSString*, NSArray<NSDictionary*>*>*)organizedFilters {
//   NSLog(@"🔄 Filters updated from SDK");
  
//   // Convert organized filters to array format for Flutter
//   NSMutableArray *allFilters = [NSMutableArray array];
  
//   for (NSString *filterType in organizedFilters.allKeys) {
//     NSArray<NSDictionary*> *filtersOfType = organizedFilters[filterType];
//     for (NSDictionary *filter in filtersOfType) {
//       NSMutableDictionary *enhancedFilter = [filter mutableCopy];
//       enhancedFilter[@"filterType"] = filterType;
//       [allFilters addObject:enhancedFilter];
//     }
//   }
  
//   // Sanitize and send to Flutter
//   NSArray *sanitizedFilters = [self sanitizeFiltersForFlutter:allFilters];
//   [self.channel invokeMethod:@"onFiltersUpdated" arguments:sanitizedFilters];
// }

- (void)nosmaiDidUpdateFilters:(NSDictionary<NSString*, NSArray<NSDictionary*>*>*)organizedFilters {
  NSLog(@"🔄 Filters updated from SDK delegate");
  
  // ================== ADD THIS LOGGING LOGIC ==================
  // Iterate through each category ("filter", "effect", etc.) and log its contents.
  for (NSString *filterCategoryName in organizedFilters.allKeys) {
      NSArray<NSDictionary*> *filtersInCategory = organizedFilters[filterCategoryName];
      [self printAllFilterData:filtersInCategory ofType:filterCategoryName];
  }
  // ============================================================

  // Convert organized filters to array format for Flutter
  NSMutableArray *allFilters = [NSMutableArray array];
  
  for (NSString *filterType in organizedFilters.allKeys) {
    NSArray<NSDictionary*> *filtersOfType = organizedFilters[filterType];
    for (NSDictionary *filter in filtersOfType) {
      NSMutableDictionary *enhancedFilter = [filter mutableCopy];
      // Don't override filterType here - let mapFrameworkKeysToPluginKeys determine it correctly
      // enhancedFilter[@"filterType"] = filterType;
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

- (BOOL)isNetworkAvailable {
    // Simple network availability check using SystemConfiguration
    // This is fast and doesn't require actual network requests
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
    
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr*)&zeroAddress);
    
    if (reachability != NULL) {
        SCNetworkReachabilityFlags flags;
        if (SCNetworkReachabilityGetFlags(reachability, &flags)) {
            CFRelease(reachability);
            return (flags & kSCNetworkReachabilityFlagsReachable) && !(flags & kSCNetworkReachabilityFlagsConnectionRequired);
        }
        CFRelease(reachability);
    }
    
    return NO;
}

- (void)dealloc {
  if (self.recordingProgressTimer) {
    [self.recordingProgressTimer invalidate];
    self.recordingProgressTimer = nil;
  }
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end