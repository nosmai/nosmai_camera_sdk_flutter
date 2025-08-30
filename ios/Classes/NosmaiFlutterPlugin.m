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
@property(nonatomic, strong) dispatch_queue_t cacheQueue;
@property(nonatomic, strong) dispatch_semaphore_t filterOperationSemaphore;
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
    
    // Initialize concurrent queue for thread-safe cache operations
    _cacheQueue = dispatch_queue_create("com.nosmai.cache", DISPATCH_QUEUE_CONCURRENT);
    
    // Initialize filter operation semaphore to prevent concurrent filter operations
    _filterOperationSemaphore = dispatch_semaphore_create(1);
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
  else if ([@"applyLipstick" isEqualToString:method]) {
    [self handleApplyLipstick:call result:result];
  }
  else if ([@"applyBlusher" isEqualToString:method]) {
    [self handleApplyBlusher:call result:result];
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
  // Flash and Torch
  else if ([@"hasFlash" isEqualToString:method]) {
    [self handleHasFlash:call result:result];
  }
  else if ([@"hasTorch" isEqualToString:method]) {
    [self handleHasTorch:call result:result];
  }
  else if ([@"setFlashMode" isEqualToString:method]) {
    [self handleSetFlashMode:call result:result];
  }
  else if ([@"setTorchMode" isEqualToString:method]) {
    [self handleSetTorchMode:call result:result];
  }
  else if ([@"getFlashMode" isEqualToString:method]) {
    [self handleGetFlashMode:call result:result];
  }
  else if ([@"getTorchMode" isEqualToString:method]) {
    [self handleGetTorchMode:call result:result];
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
    // Stop SDK processing to prevent circular dependency
    [[NosmaiSDK sharedInstance] stopProcessing];
    // Stop camera capture after SDK processing
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

- (void)handleApplyLipstick:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* intensity = call.arguments[@"intensity"];
  
  if (!intensity) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Intensity is required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applyMakeupBlendLevel:@"lipstick" level:intensity.floatValue];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleApplyBlusher:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before applying filters"
                               details:nil]);
    return;
  }
  
  NSNumber* intensity = call.arguments[@"intensity"];
  
  if (!intensity) {
    result([FlutterError errorWithCode:@"INVALID_ARGUMENTS"
                               message:@"Intensity is required"
                               details:nil]);
    return;
  }
  
  @try {
    [[NosmaiCore shared].effects applyMakeupBlendLevel:@"blusher" level:intensity.floatValue];
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


- (void)handleRemoveAllFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before removing filters"
                               details:@"Please call initWithLicense() first"]);
    return;
  }
  
  // Use semaphore to ensure only one filter operation at a time
  dispatch_semaphore_wait(self.filterOperationSemaphore, DISPATCH_TIME_FOREVER);
  
  @try {
    [[NosmaiCore shared].effects removeAllEffects];
    dispatch_semaphore_signal(self.filterOperationSemaphore);
    result(nil);
  } @catch (NSException *exception) {
    dispatch_semaphore_signal(self.filterOperationSemaphore);
    result([FlutterError errorWithCode:@"REMOVE_FILTERS_ERROR"
                               message:[NSString stringWithFormat:@"Failed to remove filters: %@", exception.reason]
                               details:exception.userInfo.description]);
  }
}

- (void)handleCleanup:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    if (self.isInitialized) {
      // Clean up NosmaiCore while preserving SDK initialization state
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
  dispatch_barrier_async(self.cacheQueue, ^{
    self.cachedLocalFilters = nil;
    self.lastFilterCacheTime = nil;
  });
}

#pragma mark - Thread-Safe Cache Methods

- (NSArray *)getCachedLocalFilters {
  __block NSArray *filters;
  dispatch_sync(self.cacheQueue, ^{
    filters = self.cachedLocalFilters;
  });
  return filters;
}

- (NSDate *)getLastFilterCacheTime {
  __block NSDate *cacheTime;
  dispatch_sync(self.cacheQueue, ^{
    cacheTime = self.lastFilterCacheTime;
  });
  return cacheTime;
}

- (void)setCachedLocalFilters:(NSArray *)filters withCacheTime:(NSDate *)cacheTime {
  dispatch_barrier_async(self.cacheQueue, ^{
    self.cachedLocalFilters = filters;
    self.lastFilterCacheTime = cacheTime;
  });
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
    // Recreate preview view connection to ensure proper rendering
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
    // Configure preview view to establish proper SDK connection
    // Ensures camera view functionality after navigation
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
                               details:@"Please call initWithLicense() first"]);
    return;
  }
  
  NSString* effectPath = call.arguments[@"effectPath"];
  
  if (!effectPath || effectPath.length == 0) {
    result([FlutterError errorWithCode:@"INVALID_EFFECT_PATH"
                               message:@"Invalid or missing effect path"
                               details:@"A valid effect path is required to apply filters."]);
    return;
  }
  
  // Use semaphore to ensure only one filter operation at a time
  dispatch_semaphore_wait(self.filterOperationSemaphore, DISPATCH_TIME_FOREVER);
  
  [[NosmaiCore shared].effects applyEffect:effectPath completion:^(BOOL success, NSError *error) {
    // Always release semaphore when operation completes
    dispatch_semaphore_signal(self.filterOperationSemaphore);
    
    if (success) {
      result(@YES);
    } else {
      NSString *errorMessage = error ? error.localizedDescription : @"Failed to apply effect";
      NSString *errorDetails = [NSString stringWithFormat:@"Effect path: %@", effectPath];
      result([FlutterError errorWithCode:@"EFFECT_APPLY_FAILED"
                                 message:errorMessage
                                 details:errorDetails]);
    }
  }];
}

- (void)handleDownloadCloudFilter:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before downloading cloud filters"
                               details:@"Please call initWithLicense() first"]);
    return;
  }
  
  NSString* filterId = call.arguments[@"filterId"];
  
  if (!filterId || filterId.length == 0) {
    result([FlutterError errorWithCode:@"INVALID_FILTER_ID"
                               message:@"Invalid or missing filter ID"
                               details:@"A valid filter ID is required to download cloud filters."]);
    return;
  }
  
  // Check network availability
  if (![self isNetworkAvailable]) {
    result([FlutterError errorWithCode:@"NETWORK_UNAVAILABLE"
                               message:@"No internet connection available"
                               details:@"Filter download requires an active internet connection."]);
    return;
  }
  
  // Check if filter is already downloaded
  if ([[NosmaiSDK sharedInstance] isCloudFilterDownloaded:filterId]) {
    NSString* localPath = [[NosmaiSDK sharedInstance] getCloudFilterLocalPath:filterId];
    if (!localPath || localPath.length == 0) {
      result([FlutterError errorWithCode:@"DOWNLOAD_PATH_ERROR"
                                 message:@"Filter marked as downloaded but local path is unavailable"
                                 details:@"The filter appears to be downloaded but the file path cannot be found."]);
      return;
    }
    result(@{
      @"success": @YES,
      @"localPath": localPath,
      @"path": localPath
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
    if (success && localPath && localPath.length > 0) {
      result(@{
        @"success": @YES,
        @"localPath": localPath,
        @"path": localPath
      });
    } else {
      NSString *errorMessage;
      NSString *errorCode;
      NSString *errorDetails;
      
      if (error) {
        errorMessage = error.localizedDescription;
        errorCode = [NSString stringWithFormat:@"DOWNLOAD_ERROR_%ld", (long)error.code];
        errorDetails = [NSString stringWithFormat:@"Filter ID: %@, Error Code: %ld", filterId, (long)error.code];
      } else if (!localPath || localPath.length == 0) {
        errorMessage = @"Download completed but local path is missing";
        errorCode = @"DOWNLOAD_PATH_MISSING";
        errorDetails = [NSString stringWithFormat:@"Filter ID: %@, Download success but no file path returned", filterId];
      } else {
        errorMessage = @"Unknown download failure";
        errorCode = @"DOWNLOAD_UNKNOWN_ERROR";
        errorDetails = [NSString stringWithFormat:@"Filter ID: %@", filterId];
      }
      
      result([FlutterError errorWithCode:errorCode
                                 message:errorMessage
                                 details:errorDetails]);
    }
  }];
}

- (void)handleGetCloudFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before getting cloud filters"
                               details:@"Please call initWithLicense() first"]);
    return;
  }
  
  // Check network availability
  if (![self isNetworkAvailable]) {
    result([FlutterError errorWithCode:@"NETWORK_UNAVAILABLE"
                               message:@"No internet connection available"
                               details:@"Cloud filters require an active internet connection. Please check your network settings and try again."]);
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
      
      // If no path found, try to construct download path for cloud filters
      if (!filterPath || filterPath.length == 0) {
        NSString *filterId = filter[@"id"] ?: filter[@"filterId"];
        NSString *filterName = filter[@"name"];
        NSString *category = filter[@"filterCategory"];
        
        if (filterId && filterName && category) {
          // Try to construct the expected download path based on the pattern we see in downloads
          NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
          if (paths.count > 0) {
            NSString *cachesDir = paths[0];
            NSString *cloudFiltersDir = [cachesDir stringByAppendingPathComponent:@"NosmaiCloudFilters"];
            
            // Try different possible filename patterns based on observed download paths
            NSString *normalizedName = [[filterName lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@"_"];
            NSArray *possibleFilenames = @[
              [NSString stringWithFormat:@"%@_%@_%@.nosmai", category, normalizedName, filterId],
              [NSString stringWithFormat:@"%@_%@.nosmai", category, filterId],
              [NSString stringWithFormat:@"%@.nosmai", filterId],
              [NSString stringWithFormat:@"special-effects_%@_%@.nosmai", normalizedName, filterId], // Specific pattern we observed
            ];
            
            for (NSString *filename in possibleFilenames) {
              NSString *possiblePath = [cloudFiltersDir stringByAppendingPathComponent:filename];
              if ([[NSFileManager defaultManager] fileExistsAtPath:possiblePath]) {
                filterPath = possiblePath;
                break;
              }
            }
          }
        }
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
      
      // Map filterCategory to filterType
      NSString *filterType = @"effect"; // default to effect
      NSString *filterCategory = filter[@"filterCategory"];
      if (filterCategory && [filterCategory isKindOfClass:[NSString class]]) {
        if ([filterCategory isEqualToString:@"cloud-filters"] || [filterCategory isEqualToString:@"fx-and-filters"]) {
          filterType = @"filter";
        } else if ([filterCategory isEqualToString:@"beauty-effects"] || [filterCategory isEqualToString:@"special-effects"]) {
          filterType = @"effect";
        }
      }
      enhancedFilter[@"filterType"] = filterType;
      
      // Check if filter is downloaded - ONLY use file existence check for accuracy
      BOOL isDownloaded = NO;
      
      // Only rely on actual file existence to determine download status
      if (filterPath && [[NSFileManager defaultManager] fileExistsAtPath:filterPath]) {
        isDownloaded = YES;
      }
      
      // For downloaded filters, load preview image
      if (isDownloaded && filterPath && [[NSFileManager defaultManager] fileExistsAtPath:filterPath]) {
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
      
      // Set the final download status and update path if found
      enhancedFilter[@"isDownloaded"] = @(isDownloaded);
      if (isDownloaded && filterPath) {
        enhancedFilter[@"path"] = filterPath;
        enhancedFilter[@"localPath"] = filterPath;
      }
      
      [enhancedFilters addObject:enhancedFilter];
    }
    
    NSArray<NSDictionary *> *sanitizedFilters = [self sanitizeFiltersForFlutter:enhancedFilters];
    if (!sanitizedFilters || sanitizedFilters.count == 0) {
      result([FlutterError errorWithCode:@"CLOUD_FILTER_PROCESSING_FAILED"
                                 message:@"Failed to process cloud filters"
                                 details:@"Cloud filters received but could not be processed properly."]);
      return;
    }
    result(sanitizedFilters);
  } else {
    result([FlutterError errorWithCode:@"CLOUD_FILTERS_NOT_AVAILABLE"
                               message:@"Cloud filters are not available"
                               details:@"No cloud filters found. This could be due to server issues or your account may not have access to cloud filters."]);
  }
}

- (void)handleGetLocalFilters:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before getting local filters"
                               details:@"Please call initWithLicense() first"]);
    return;
  }
  
  @try {
    // Use our custom getFlutterLocalFilters method instead of SDK's getLocalFilters
    NSArray<NSDictionary *> *filters = [self getFlutterLocalFilters];
    
    if (!filters) {
      result([FlutterError errorWithCode:@"FILTER_DISCOVERY_FAILED"
                                 message:@"Failed to discover local filters"
                                 details:@"No local filters found in app bundle. Check if filters are properly included in assets folder."]);
      return;
    }
    
    NSArray<NSDictionary *> *sanitizedFilters = [self sanitizeFiltersForFlutter:filters];
    if (!sanitizedFilters || sanitizedFilters.count == 0) {
      result([FlutterError errorWithCode:@"FILTER_PROCESSING_FAILED"
                                 message:@"Failed to process local filters"
                                 details:@"Local filters found but could not be processed. Check filter file integrity."]);
      return;
    }
    
    result(sanitizedFilters);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FILTER_LOAD_ERROR"
                               message:[NSString stringWithFormat:@"Error loading local filters: %@", exception.reason]
                               details:exception.userInfo.description]);
  }
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
  
  NSArray *cachedFilters = [self getCachedLocalFilters];
  NSDate *lastCacheTime = [self getLastFilterCacheTime];
  
  if (cachedFilters && lastCacheTime && 
      [now timeIntervalSinceDate:lastCacheTime] < cacheValidDuration) {
    return cachedFilters;
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
      
      // Extract filterType using new SDK method
      NSDictionary *sdkFilterInfo = [[NosmaiSDK sharedInstance] getFilterInfoFromPath:filePath];
      
      if (sdkFilterInfo && sdkFilterInfo[@"filterType"]) {
        filterInfo[@"filterType"] = sdkFilterInfo[@"filterType"];
      } else {
        filterInfo[@"filterType"] = @"effect"; // default fallback
      }
      
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
  
  // Cache the result using thread-safe method
  NSArray *finalFilters = [localFilters copy];
  [self setCachedLocalFilters:finalFilters withCacheTime:now];
  
  return finalFilters;
}

- (NSDictionary *)mapFrameworkKeysToPluginKeys:(NSDictionary *)frameworkFilter {
  NSMutableDictionary *pluginFilter = [NSMutableDictionary dictionary];
  
  // Transform framework filter data to plugin-compatible format
  
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
    
    if ([category hasPrefix:@"fx-and-filters"]) {
      filterType = @"filter";
    } else if ([category hasPrefix:@"special-effects"]) {
      filterType = @"effect";
    } else {
    }
  } else {
   
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
    

    NSMutableDictionary *sanitizedFilter = [NSMutableDictionary dictionary];
    
    // Only include supported data types for Flutter StandardCodec
    for (NSString *key in mappedFilter.allKeys) {
      id value = mappedFilter[key];
      
      // Check if value is a supported type for Flutter StandardCodec
      if ([value isKindOfClass:[NSNull class]]) {
        // Convert NSNull to nil or appropriate default
        // Skip NSNull values as they cause issues in Flutter
      } else if (value == nil) {
        // Skip nil values
      } else if ([value isKindOfClass:[NSString class]]) {
        // Handle strings specially - don't skip empty strings for path
        NSString *stringValue = (NSString *)value;
        if ([key isEqualToString:@"path"] && stringValue.length > 0) {
        }
        sanitizedFilter[key] = value;
      } else if ([value isKindOfClass:[NSNumber class]] ||
                 [value isKindOfClass:[NSArray class]] ||
                 [value isKindOfClass:[NSDictionary class]] ||
                 [value isKindOfClass:[NSData class]]) {
        sanitizedFilter[key] = value;
      } else if ([value isKindOfClass:[UIImage class]]) {
        // Convert UIImage to base64 string or skip it
        // Could convert to base64 if needed:
        // UIImage *image = (UIImage *)value;
        // NSData *imageData = UIImagePNGRepresentation(image);
        // sanitizedFilter[key] = [imageData base64EncodedStringWithOptions:0];
      } else {
        // Skip unsupported types
      }
    }
    
    [sanitizedFilters addObject:[sanitizedFilter copy]];
  }
  
  return [sanitizedFilters copy];
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
      
      result(@YES);
    } else {
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
      
      result(@{
        @"success": @YES,
        @"videoPath": videoURL.path,
        @"duration": @(duration),
        @"fileSize": fileSize
      });
    } else {
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
  [self.channel invokeMethod:@"onStateChanged" arguments:@{@"state": @(newState)}];
}

- (void)nosmaiDidFailWithError:(NSError *)error {
  [self.channel invokeMethod:@"onError" arguments:@{
    @"code": @(error.code),
    @"message": error.localizedDescription
  }];
}

// - (void)nosmaiDidUpdateFilters:(NSDictionary<NSString*, NSArray<NSDictionary*>*>*)organizedFilters {
  
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
  // Notify Flutter that camera is ready for processing
  [self.channel invokeMethod:@"onCameraReady" arguments:nil];
}

- (void)nosmaiCameraDidStopCapture {
  // Notify Flutter that camera processing stopped
  [self.channel invokeMethod:@"onCameraProcessingStopped" arguments:nil];
}

- (void)nosmaiCameraDidSwitchToPosition:(NosmaiCameraPosition)position {
}

- (void)nosmaiCameraDidFailWithError:(NSError *)error {
  [self.channel invokeMethod:@"onError" arguments:@{
    @"code": @"CAMERA_ERROR",
    @"message": error.localizedDescription
  }];
}

// Add missing camera state delegate method
- (void)nosmaiCameraDidAttachToView:(UIView *)view {
  dispatch_semaphore_wait(self.cameraStateSemaphore, DISPATCH_TIME_FOREVER);
  self.isCameraAttached = YES;
  dispatch_semaphore_signal(self.cameraStateSemaphore);
  
  // Notify Flutter that camera is attached and ready
  [self.channel invokeMethod:@"onCameraAttached" arguments:nil];
}

- (void)nosmaiCameraDidDetachFromView {
  dispatch_semaphore_wait(self.cameraStateSemaphore, DISPATCH_TIME_FOREVER);
  self.isCameraAttached = NO;
  dispatch_semaphore_signal(self.cameraStateSemaphore);
  
  // Notify Flutter that camera has been detached
  [self.channel invokeMethod:@"onCameraDetached" arguments:nil];
}

// NosmaiEffectsDelegate Methods
- (void)nosmaiEffectsDidLoadEffect:(NSString *)effectPath {
}

- (void)nosmaiEffectsDidFailToLoadEffect:(NSString *)effectPath error:(NSError *)error {
  [self.channel invokeMethod:@"onError" arguments:@{
    @"code": @"EFFECT_ERROR",
    @"message": error.localizedDescription
  }];
}

- (void)nosmaiEffectsDidRemoveAllEffects {
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
      NSError *error = nil;
      NSArray *contents = [fileManager contentsOfDirectoryAtPath:fullPath error:&error];
      
      if (!error && contents) {
        for (NSString *fileName in contents) {
          if ([fileName hasSuffix:@".nosmai"]) {
            // Remove the .nosmai extension to get the filter name
            NSString *filterName = [fileName stringByDeletingPathExtension];
            if (![filterNames containsObject:filterName]) {
              [filterNames addObject:filterName];
            }
          }
        }
      } else {
      }
    }
  }
  
  // Also try using Flutter's asset lookup mechanism
  [self discoverFiltersUsingFlutterAssetLookup:filterNames];
  
  // Sort alphabetically for consistent ordering
  [filterNames sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
  
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
  
  // Clean up semaphores and queues
  if (self.cameraStateSemaphore) {
    self.cameraStateSemaphore = nil;
  }
  if (self.filterOperationSemaphore) {
    self.filterOperationSemaphore = nil;
  }
  if (self.cacheQueue) {
    self.cacheQueue = nil;
  }
  
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Flash and Torch

- (void)handleHasFlash:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK not initialized"
                               details:nil]);
    return;
  }
  
  @try {
    BOOL hasFlash = [[NosmaiCore shared].camera hasFlash];
    result(@(hasFlash));
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FLASH_ERROR"
                               message:@"Failed to check flash availability"
                               details:exception.reason]);
  }
}

- (void)handleHasTorch:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK not initialized"
                               details:nil]);
    return;
  }
  
  @try {
    BOOL hasTorch = [[NosmaiCore shared].camera hasTorch];
    result(@(hasTorch));
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"TORCH_ERROR"
                               message:@"Failed to check torch availability"
                               details:exception.reason]);
  }
}

- (void)handleSetFlashMode:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK not initialized"
                               details:nil]);
    return;
  }
  
  NSString *flashModeString = call.arguments[@"flashMode"];
  if (!flashModeString) {
    result([FlutterError errorWithCode:@"INVALID_PARAMETER"
                               message:@"Flash mode parameter is required"
                               details:nil]);
    return;
  }
  
  AVCaptureFlashMode flashMode;
  if ([flashModeString isEqualToString:@"on"]) {
    flashMode = AVCaptureFlashModeOn;
  } else if ([flashModeString isEqualToString:@"auto"]) {
    flashMode = AVCaptureFlashModeAuto;
  } else {
    flashMode = AVCaptureFlashModeOff;
  }
  
  @try {
    BOOL success = [[NosmaiCore shared].camera setFlashMode:flashMode];
    result(@(success));
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FLASH_ERROR"
                               message:@"Failed to set flash mode"
                               details:exception.reason]);
  }
}

- (void)handleSetTorchMode:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK not initialized"
                               details:nil]);
    return;
  }
  
  NSString *torchModeString = call.arguments[@"torchMode"];
  if (!torchModeString) {
    result([FlutterError errorWithCode:@"INVALID_PARAMETER"
                               message:@"Torch mode parameter is required"
                               details:nil]);
    return;
  }
  
  AVCaptureTorchMode torchMode;
  if ([torchModeString isEqualToString:@"on"]) {
    torchMode = AVCaptureTorchModeOn;
  } else if ([torchModeString isEqualToString:@"auto"]) {
    torchMode = AVCaptureTorchModeAuto;
  } else {
    torchMode = AVCaptureTorchModeOff;
  }
  
  @try {
    BOOL success = [[NosmaiCore shared].camera setTorchMode:torchMode];
    result(@(success));
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"TORCH_ERROR"
                               message:@"Failed to set torch mode"
                               details:exception.reason]);
  }
}

- (void)handleGetFlashMode:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK not initialized"
                               details:nil]);
    return;
  }
  
  @try {
    BOOL hasFlash = [[NosmaiCore shared].camera hasFlash];
    if (hasFlash) {
      result(@"off"); // Default state
    } else {
      result(@"off"); // No flash available
    }
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"FLASH_ERROR"
                               message:@"Failed to get flash mode"
                               details:exception.reason]);
  }
}

- (void)handleGetTorchMode:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK not initialized"
                               details:nil]);
    return;
  }
  
  @try {
    BOOL hasTorch = [[NosmaiCore shared].camera hasTorch];
    if (hasTorch) {
      result(@"off"); // Default state
    } else {
      result(@"off"); // No torch available
    }
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"TORCH_ERROR"
                               message:@"Failed to get torch mode"
                               details:exception.reason]);
  }
}

@end
