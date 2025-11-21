#import "NosmaiFlutterPlugin.h"
#import "NosmaiCameraPreviewView.h"
#import <nosmai/Nosmai.h>
#import <Photos/Photos.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <sys/socket.h>
#import <netinet/in.h>

// NosmaiExternalProcessor interface
@interface NosmaiExternalProcessor : NSObject
@property (nonatomic, assign) BOOL isInitialized;
@property (nonatomic, assign) CVPixelBufferRef lastProcessedBuffer;
@property (nonatomic, strong) dispatch_semaphore_t frameSemaphore;
- (BOOL)processPixelBuffer:(CVPixelBufferRef)pixelBuffer mirror:(BOOL)mirror;
@end

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
// Flash and Torch state tracking (NosmaiCamera doesn't provide getters)
@property(nonatomic, assign) AVCaptureFlashMode currentFlashMode;
@property(nonatomic, assign) AVCaptureTorchMode currentTorchMode;
@end

@implementation NosmaiFlutterPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"nosmai_camera_sdk"
            binaryMessenger:[registrar messenger]];
  NosmaiFlutterPlugin* instance = [[NosmaiFlutterPlugin alloc] init];
  instance.channel = channel;
  [registrar addMethodCallDelegate:instance channel:channel];
  
  NosmaiCameraPreviewViewFactory* factory =
      [[NosmaiCameraPreviewViewFactory alloc] initWithMessenger:[registrar messenger]];
  [registrar registerViewFactory:factory withId:@"nosmai_camera_preview"];
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _isInitialized = NO;
    _isCameraAttached = NO;

    _filterCache = [[NSCache alloc] init];
    _filterCache.countLimit = 100;
    _filterCache.totalCostLimit = 50 * 1024 * 1024;

    _cameraStateSemaphore = dispatch_semaphore_create(1);

    _cacheQueue = dispatch_queue_create("com.nosmai.cache", DISPATCH_QUEUE_CONCURRENT);

    _filterOperationSemaphore = dispatch_semaphore_create(1);

    // Initialize flash/torch state to off
    _currentFlashMode = AVCaptureFlashModeOff;
    _currentTorchMode = AVCaptureTorchModeOff;
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
  else if ([@"pauseCamera" isEqualToString:method]) {
    [self handlePauseCamera:call result:result];
  }
  else if ([@"resumeCamera" isEqualToString:method]) {
    [self handleResumeCamera:call result:result];
  }
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
  else if ([@"getEffectParameters" isEqualToString:method]) {
    [self handleGetEffectParameters:call result:result];
  }
  else if ([@"getEffectParameterValue" isEqualToString:method]) {
    [self handleGetEffectParameterValue:call result:result];
  }
  else if ([@"setEffectParameter" isEqualToString:method]) {
    [self handleSetEffectParameter:call result:result];
  }
  else if ([@"setEffectParameterString" isEqualToString:method]) {
    [self handleSetEffectParameterString:call result:result];
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
  
  [NosmaiCore shared].delegate = self;

  __weak typeof(self) weakSelf = self;
  [[NosmaiCore shared] initializeWithAPIKey:licenseKey completion:^(BOOL success, NSError *error) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;

    dispatch_async(dispatch_get_main_queue(), ^{
      strongSelf.isInitialized = success;

      if (success) {
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
  
  if (!position || (![position isEqualToString:@"front"] && ![position isEqualToString:@"back"])) {
    result([FlutterError errorWithCode:@"INVALID_PARAMETER"
                               message:@"Camera position must be 'front' or 'back'"
                               details:@{@"position": position ?: @"null"}]);
    return;
  }
  
  NosmaiCameraPosition cameraPosition = NosmaiCameraPositionFront;
  if ([@"back" isEqualToString:position]) {
    cameraPosition = NosmaiCameraPositionBack;
  }
  
  if (!sessionPreset) {
    sessionPreset = AVCaptureSessionPresetHigh;
  }
  
  NSDate *startTime = [NSDate date];
  
  @try {
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
    [[NosmaiSDK sharedInstance] stopProcessing];
    [[NosmaiCore shared].camera stopCapture];
    result(nil);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"STOP_PROCESSING_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handlePauseCamera:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before pausing camera"
                               details:nil]);
    return;
  }

  @try {
    // Only stop camera capture - SDK processing stays active
    [[NosmaiCore shared].camera stopCapture];
    NSLog(@"⏸️ Camera paused successfully");
    result(@YES);
  } @catch (NSException *exception) {
    NSLog(@"❌ pauseCamera error: %@", exception.reason);
    result([FlutterError errorWithCode:@"PAUSE_ERROR"
                               message:exception.reason
                               details:exception.userInfo]);
  }
}

- (void)handleResumeCamera:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK must be initialized before resuming camera"
                               details:nil]);
    return;
  }

  @try {
    // Only restart camera capture - SDK processing already active
    [[NosmaiCore shared].camera startCapture];
    NSLog(@"▶️ Camera resumed successfully");
    result(@YES);
  } @catch (NSException *exception) {
    NSLog(@"❌ resumeCamera error: %@", exception.reason);
    result([FlutterError errorWithCode:@"RESUME_ERROR"
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
  
  dispatch_async(dispatch_get_main_queue(), ^{
    @try {
      BOOL success = [[NosmaiCore shared].camera switchCamera];
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
      [[NosmaiCore shared] cleanup];
    }
    
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
    dispatch_semaphore_wait(self.cameraStateSemaphore, DISPATCH_TIME_FOREVER);

    NosmaiCore* core = [NosmaiCore shared];
    if (core && core.isInitialized && self.isCameraAttached) {
      [core.camera detachFromView];
      self.isCameraAttached = NO;

      // Ensure SDK releases the current preview surface so stale frames
      // are not reused when we reattach on the next navigation.
      [[NosmaiSDK sharedInstance] setPreviewView:nil];

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
    if (self.previewView) {
      
      [[NosmaiSDK sharedInstance] setPreviewView:nil];
      
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
  
  dispatch_semaphore_wait(self.filterOperationSemaphore, DISPATCH_TIME_FOREVER);
  
  [[NosmaiCore shared].effects applyEffect:effectPath completion:^(BOOL success, NSError *error) {
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
  
  if (![self isNetworkAvailable]) {
    result([FlutterError errorWithCode:@"NETWORK_UNAVAILABLE"
                               message:@"No internet connection available"
                               details:@"Filter download requires an active internet connection."]);
    return;
  }
  
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
  
  
  [[NosmaiSDK sharedInstance] downloadCloudFilter:filterId
                                          progress:^(float progress) {
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
  
  if (![self isNetworkAvailable]) {
    result([FlutterError errorWithCode:@"NETWORK_UNAVAILABLE"
                               message:@"No internet connection available"
                               details:@"Cloud filters require an active internet connection. Please check your network settings and try again."]);
    return;
  }
  
  NSArray<NSDictionary *> *cloudFilters = [[NosmaiSDK sharedInstance] getCloudFilters];
  
  if (cloudFilters && cloudFilters.count > 0) {
    NSMutableArray *enhancedFilters = [NSMutableArray array];
    
    for (NSDictionary *filter in cloudFilters) {
      NSMutableDictionary *enhancedFilter = [filter mutableCopy];
      
      id pathValue = filter[@"path"];
      id localPathValue = filter[@"localPath"];
      NSString *filterPath = nil;
      
      if ([pathValue isKindOfClass:[NSString class]]) {
        filterPath = pathValue;
      } else if ([localPathValue isKindOfClass:[NSString class]]) {
        filterPath = localPathValue;
      }
      
      if (!filterPath || filterPath.length == 0) {
        NSString *filterId = filter[@"id"] ?: filter[@"filterId"];
        NSString *filterName = filter[@"name"];
        NSString *category = filter[@"filterCategory"];
        
        if (filterId && filterName && category) {
          NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
          if (paths.count > 0) {
            NSString *cachesDir = paths[0];
            NSString *cloudFiltersDir = [cachesDir stringByAppendingPathComponent:@"NosmaiCloudFilters"];
            NSString *normalizedName = [[filterName lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@"_"];
            NSArray *possibleFilenames = @[
              [NSString stringWithFormat:@"%@_%@_%@.nosmai", category, normalizedName, filterId],
              [NSString stringWithFormat:@"%@_%@.nosmai", category, filterId],
              [NSString stringWithFormat:@"%@.nosmai", filterId],
              [NSString stringWithFormat:@"special-effects_%@_%@.nosmai", normalizedName, filterId], 
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
      
      if (filter[@"filterCategory"] && ![filter[@"filterCategory"] isKindOfClass:[NSNull class]]) {
        enhancedFilter[@"filterCategory"] = filter[@"filterCategory"];
      }
      
      if (enhancedFilter[@"type"]) {
        enhancedFilter[@"originalType"] = enhancedFilter[@"type"];
      }
      enhancedFilter[@"type"] = @"cloud";
      
      NSString *filterType = @"effect"; 
      NSString *filterCategory = filter[@"filterCategory"];
      if (filterCategory && [filterCategory isKindOfClass:[NSString class]]) {
        if ([filterCategory isEqualToString:@"cloud-filters"] || [filterCategory isEqualToString:@"fx-and-filters"]) {
          filterType = @"filter";
        } else if ([filterCategory isEqualToString:@"beauty-effects"] || [filterCategory isEqualToString:@"special-effects"]) {
          filterType = @"effect";
        }
      }
      enhancedFilter[@"filterType"] = filterType;
      
      BOOL isDownloaded = NO;
      
      if (filterPath && [[NSFileManager defaultManager] fileExistsAtPath:filterPath]) {
        isDownloaded = YES;
      }
      
      if (isDownloaded && filterPath && [[NSFileManager defaultManager] fileExistsAtPath:filterPath]) {
        UIImage *previewImage = [[NosmaiSDK sharedInstance] loadPreviewImageForFilter:filterPath];
        if (previewImage) {
          NSData *imageData = UIImageJPEGRepresentation(previewImage, 0.7);
          if (imageData) {
            NSString *base64String = [imageData base64EncodedStringWithOptions:0];
            enhancedFilter[@"previewImageBase64"] = base64String;
          }
        }
      }
      
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
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    
    NSDictionary<NSString*, NSArray<NSDictionary*>*> *organizedFilters = [[NosmaiSDK sharedInstance] getInitialFilters];
    
    NSMutableArray *allFilters = [NSMutableArray array];
    for (NSString *filterType in organizedFilters.allKeys) {
      NSArray<NSDictionary*> *filtersOfType = organizedFilters[filterType];
      
      for (NSDictionary *filter in filtersOfType) {
        NSMutableDictionary *enhancedFilter = [filter mutableCopy];
        
        if (!enhancedFilter[@"name"] || [enhancedFilter[@"name"] isKindOfClass:[NSNull class]]) {
          continue;
        }
        
        enhancedFilter[@"filterType"] = filterType;
        
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
    
    NSArray<NSDictionary *> *localFilters = [self getFlutterLocalFilters];
    if (localFilters.count > 0) {
      [allFilters addObjectsFromArray:localFilters];
    }

    NSArray *sanitizedFilters = [self sanitizeFiltersForFlutter:allFilters];

    

    dispatch_async(dispatch_get_main_queue(), ^{
      result(sanitizedFilters ?: @[]);
      
      if ([self isNetworkAvailable]) {
        [[NosmaiSDK sharedInstance] fetchCloudFilters];
      } else {
      }
    });
  });
}



- (NSArray<NSDictionary *> *)getFlutterLocalFilters {
  NSTimeInterval cacheValidDuration = 5 * 60; 
  NSDate *now = [NSDate date];
  
  NSArray *cachedFilters = [self getCachedLocalFilters];
  NSDate *lastCacheTime = [self getLastFilterCacheTime];

  if (cachedFilters && cachedFilters.count > 0 && lastCacheTime &&
      [now timeIntervalSinceDate:lastCacheTime] < cacheValidDuration) {
    return cachedFilters;
  }

  NSMutableArray *localFilters = [NSMutableArray array];

  NSArray *discoveredFilterNames = [self discoverNosmaiFiltersInAssets];
  
  
  for (NSString *filterName in discoveredFilterNames) {
    NSString *cacheKey = [NSString stringWithFormat:@"local_filter_%@", filterName];
    NSDictionary *cachedFilterInfo = [self.filterCache objectForKey:cacheKey];

    if (cachedFilterInfo) {
      [localFilters addObject:cachedFilterInfo];
      continue;
    }

    NSString *manifestAssetKey = [FlutterDartProject lookupKeyForAsset:[NSString stringWithFormat:@"assets/nosmai_filters/%@/%@_manifest.json", filterName, filterName]];
    NSString *manifestPath = [[NSBundle mainBundle] pathForResource:manifestAssetKey ofType:nil];

    NSString *nosmaiAssetKey = [FlutterDartProject lookupKeyForAsset:[NSString stringWithFormat:@"assets/nosmai_filters/%@/%@.nosmai", filterName, filterName]];
    NSString *nosmaiPath = [[NSBundle mainBundle] pathForResource:nosmaiAssetKey ofType:nil];

    NSString *previewAssetKey = [FlutterDartProject lookupKeyForAsset:[NSString stringWithFormat:@"assets/nosmai_filters/%@/%@_preview.png", filterName, filterName]];
    NSString *previewPath = [[NSBundle mainBundle] pathForResource:previewAssetKey ofType:nil];

    if (!nosmaiPath || ![[NSFileManager defaultManager] fileExistsAtPath:nosmaiPath]) {
      NSLog(@"Error: Missing .nosmai file for filter '%@'", filterName);
      continue;
    }

    NSMutableDictionary *filterInfo = [NSMutableDictionary dictionary];

    if (manifestPath && [[NSFileManager defaultManager] fileExistsAtPath:manifestPath]) {
      NSError *jsonError = nil;
      NSData *jsonData = [NSData dataWithContentsOfFile:manifestPath];
      NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];

      if (!jsonError && manifest) {
        filterInfo[@"id"] = manifest[@"id"] ?: filterName;
        filterInfo[@"name"] = manifest[@"id"] ?: filterName;
        filterInfo[@"displayName"] = manifest[@"displayName"] ?: [self createDisplayNameFromFilterName:filterName];
        filterInfo[@"description"] = manifest[@"description"] ?: @"";
        filterInfo[@"filterType"] = manifest[@"filterType"] ?: @"effect";
        filterInfo[@"version"] = manifest[@"version"] ?: @"1.0.0";
        filterInfo[@"author"] = manifest[@"author"] ?: @"";
        filterInfo[@"tags"] = manifest[@"tags"] ?: @[];
        filterInfo[@"minSDKVersion"] = manifest[@"minSDKVersion"] ?: @"1.0.0";
        filterInfo[@"created"] = manifest[@"created"] ?: @"";
      } else {
        NSLog(@"Warning: Failed to parse manifest.json for filter '%@': %@", filterName, jsonError.localizedDescription);
        filterInfo[@"id"] = filterName;
        filterInfo[@"name"] = filterName;
        filterInfo[@"displayName"] = [self createDisplayNameFromFilterName:filterName];
        filterInfo[@"filterType"] = @"effect";
      }
    } else {
      NSLog(@"Warning: Missing manifest.json for filter '%@', using defaults", filterName);
      filterInfo[@"id"] = filterName;
      filterInfo[@"name"] = filterName;
      filterInfo[@"displayName"] = [self createDisplayNameFromFilterName:filterName];
      filterInfo[@"filterType"] = @"effect";
    }

    filterInfo[@"path"] = nosmaiPath;
    filterInfo[@"effectPath"] = nosmaiPath;

    NSError *error = nil;
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:nosmaiPath error:&error];
    if (!error && fileAttributes) {
      filterInfo[@"fileSize"] = fileAttributes[NSFileSize];
    } else {
      filterInfo[@"fileSize"] = @0;
    }

    filterInfo[@"type"] = @"local";
    filterInfo[@"isDownloaded"] = @YES;

    BOOL previewLoaded = NO;

    if (previewPath && [[NSFileManager defaultManager] fileExistsAtPath:previewPath]) {
      UIImage *previewImage = [UIImage imageWithContentsOfFile:previewPath];
      if (previewImage) {
        NSData *imageData = UIImageJPEGRepresentation(previewImage, 0.7);
        if (imageData) {
          NSString *base64String = [imageData base64EncodedStringWithOptions:0];
          filterInfo[@"previewImageBase64"] = base64String;
          filterInfo[@"hasPreview"] = @YES;
          previewLoaded = YES;

          [self.filterCache setObject:[filterInfo copy] forKey:cacheKey cost:imageData.length];
        }
      }
    }

    if (!previewLoaded) {
      UIImage *previewImage = [[NosmaiSDK sharedInstance] loadPreviewImageForFilter:nosmaiPath];
      if (previewImage) {
        NSData *imageData = UIImageJPEGRepresentation(previewImage, 0.7);
        if (imageData) {
          NSString *base64String = [imageData base64EncodedStringWithOptions:0];
          filterInfo[@"previewImageBase64"] = base64String;
          filterInfo[@"hasPreview"] = @YES;

          [self.filterCache setObject:[filterInfo copy] forKey:cacheKey cost:imageData.length];
        }
      } else {
        NSLog(@"Warning: No preview image available for filter '%@'", filterName);
        filterInfo[@"hasPreview"] = @NO;
        [self.filterCache setObject:[filterInfo copy] forKey:cacheKey cost:1024];
      }
    }

    [localFilters addObject:[filterInfo copy]];
  }

  NSArray *finalFilters = [localFilters copy];
  if (finalFilters.count > 0) {
    [self setCachedLocalFilters:finalFilters withCacheTime:now];
  }

  return finalFilters;
}

- (NSDictionary *)mapFrameworkKeysToPluginKeys:(NSDictionary *)frameworkFilter {
  NSMutableDictionary *pluginFilter = [NSMutableDictionary dictionary];
  
  pluginFilter[@"id"] = frameworkFilter[@"id"] ?: frameworkFilter[@"name"] ?: @"";
  pluginFilter[@"name"] = frameworkFilter[@"name"] ?: @"";
  pluginFilter[@"description"] = frameworkFilter[@"description"] ?: @"";
  pluginFilter[@"displayName"] = frameworkFilter[@"displayName"] ?: frameworkFilter[@"name"] ?: @"";
  
  NSString *path = frameworkFilter[@"path"] ?: frameworkFilter[@"localPath"] ?: @"";
  if (path.length > 0) {
    pluginFilter[@"path"] = path;
  } else {
    pluginFilter[@"path"] = @"";
  }
  
  pluginFilter[@"fileSize"] = frameworkFilter[@"fileSize"] ?: @0;
  
  pluginFilter[@"type"] = frameworkFilter[@"type"] ?: @"local";
  
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
  
  NSString *filterType = frameworkFilter[@"filterType"] ?: @"effect"; 
  
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
  
  pluginFilter[@"isFree"] = frameworkFilter[@"isFree"] ?: @YES;
  pluginFilter[@"isDownloaded"] = frameworkFilter[@"isDownloaded"] ?: @YES;
  pluginFilter[@"previewUrl"] = frameworkFilter[@"previewUrl"] ?: frameworkFilter[@"thumbnailUrl"];
  pluginFilter[@"category"] = frameworkFilter[@"category"];
  pluginFilter[@"downloadCount"] = frameworkFilter[@"downloadCount"] ?: @0;
  pluginFilter[@"price"] = frameworkFilter[@"price"] ?: @0;
  
  if (frameworkFilter[@"previewImageBase64"]) {
    pluginFilter[@"previewImageBase64"] = frameworkFilter[@"previewImageBase64"];
  }
  
  return [pluginFilter copy];
}

- (NSArray<NSDictionary *> *)sanitizeFiltersForFlutter:(NSArray<NSDictionary *> *)filters {
  NSMutableArray *sanitizedFilters = [NSMutableArray array];
  
  for (NSDictionary *filter in filters) {
    NSDictionary *mappedFilter = [self mapFrameworkKeysToPluginKeys:filter];
    

    NSMutableDictionary *sanitizedFilter = [NSMutableDictionary dictionary];
    
    for (NSString *key in mappedFilter.allKeys) {
      id value = mappedFilter[key];
      
      if ([value isKindOfClass:[NSNull class]]) {
      } else if (value == nil) {
      } else if ([value isKindOfClass:[NSString class]]) {
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
      } else {
      }
    }
    
    [sanitizedFilters addObject:[sanitizedFilter copy]];
  }
  
  return [sanitizedFilters copy];
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
    
    if (self.recordingProgressTimer) {
      [self.recordingProgressTimer invalidate];
      self.recordingProgressTimer = nil;
    }
    
    if (videoURL && !error) {
      NSTimeInterval duration = [[NosmaiCore shared] currentRecordingDuration];
      
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

  [[NosmaiCore shared] capturePhoto:^(UIImage *image, NSError *error) {
    if (image) {
      NSData *imageData = UIImageJPEGRepresentation(image, 0.8);

      NSMutableDictionary *resultDict = [NSMutableDictionary dictionary];
      resultDict[@"success"] = @YES;
      resultDict[@"width"] = @(image.size.width);
      resultDict[@"height"] = @(image.size.height);

      if (imageData) {
        FlutterStandardTypedData *typedData = [FlutterStandardTypedData typedDataWithBytes:imageData];
        resultDict[@"imageData"] = typedData;

        @try {
          NSString *tempDir = NSTemporaryDirectory();
          NSString *fileName = [NSString stringWithFormat:@"nosmai_photo_%ld.jpg",
                                (long)[[NSDate date] timeIntervalSince1970] * 1000];
          NSString *filePath = [tempDir stringByAppendingPathComponent:fileName];

          if ([imageData writeToFile:filePath atomically:YES]) {
            resultDict[@"imagePath"] = filePath;
          } else {
            resultDict[@"imagePath"] = [NSNull null];
          }
        } @catch (NSException *exception) {
          resultDict[@"imagePath"] = [NSNull null];
        }
      } else {
        resultDict[@"imagePath"] = [NSNull null];
      }

      result(resultDict);
    } else {
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
  
  UIImage *image = [UIImage imageWithData:imageData.data];
  if (!image) {
    result([FlutterError errorWithCode:@"INVALID_IMAGE"
                               message:@"Could not create image from data"
                               details:nil]);
    return;
  }
  
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
  
  if (![[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
    result([FlutterError errorWithCode:@"FILE_NOT_FOUND"
                               message:@"Video file not found"
                               details:nil]);
    return;
  }
  
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

- (void)nosmaiDidChangeState:(NosmaiState)newState {
  [self.channel invokeMethod:@"onStateChanged" arguments:@{@"state": @(newState)}];
}

- (void)nosmaiDidFailWithError:(NSError *)error {
  [self.channel invokeMethod:@"onError" arguments:@{
    @"code": @(error.code),
    @"message": error.localizedDescription
  }];
}

- (void)nosmaiDidUpdateFilters:(NSDictionary<NSString*, NSArray<NSDictionary*>*>*)organizedFilters {
  

  NSMutableArray *allFilters = [NSMutableArray array];
  
  for (NSString *filterType in organizedFilters.allKeys) {
    NSArray<NSDictionary*> *filtersOfType = organizedFilters[filterType];
    for (NSDictionary *filter in filtersOfType) {
      NSMutableDictionary *enhancedFilter = [filter mutableCopy];
      [allFilters addObject:enhancedFilter];
    }
  }
  
  NSArray *sanitizedFilters = [self sanitizeFiltersForFlutter:allFilters];
  [self.channel invokeMethod:@"onFiltersUpdated" arguments:sanitizedFilters];
}

- (void)nosmaiCameraDidStartCapture {
  [self.channel invokeMethod:@"onCameraReady" arguments:nil];
}

- (void)nosmaiCameraDidStopCapture {
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

- (void)nosmaiCameraDidAttachToView:(UIView *)view {
  dispatch_semaphore_wait(self.cameraStateSemaphore, DISPATCH_TIME_FOREVER);
  self.isCameraAttached = YES;
  dispatch_semaphore_signal(self.cameraStateSemaphore);
  
  [self.channel invokeMethod:@"onCameraAttached" arguments:nil];
}

- (void)nosmaiCameraDidDetachFromView {
  dispatch_semaphore_wait(self.cameraStateSemaphore, DISPATCH_TIME_FOREVER);
  self.isCameraAttached = NO;
  dispatch_semaphore_signal(self.cameraStateSemaphore);
  
  [self.channel invokeMethod:@"onCameraDetached" arguments:nil];
}

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

- (void)nosmaiDidChangeLicenseStatus:(BOOL)isValid status:(NSString*)status {
  @try {
    NSString *statusString = nil;

    if (isValid && [status isEqualToString:@"VALID"]) {
      statusString = @"valid";
    } else if ([status rangeOfString:@"EXPIRED" options:NSCaseInsensitiveSearch].location != NSNotFound) {
      statusString = @"expired";
    } else if (!isValid) {
      statusString = @"invalid";
    }

    if (statusString) {
      [self.channel invokeMethod:@"onLicenseStatusChanged" arguments:@{@"status": statusString}];
    }
  } @catch (NSException *exception) {}
}

#pragma mark - Helper Methods

- (NSArray<NSString *> *)discoverNosmaiFiltersInAssets {
  NSMutableArray *filterNames = [NSMutableArray array];
  NSFileManager *fileManager = [NSFileManager defaultManager];

  NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
  NSArray *potentialPaths = @[
    @"flutter_assets/assets/nosmai_filters",
    @"Frameworks/App.framework/flutter_assets/assets/nosmai_filters",
    @"assets/nosmai_filters"
  ];

  for (NSString *relativePath in potentialPaths) {
    NSString *fullPath = [bundlePath stringByAppendingPathComponent:relativePath];

    if ([fileManager fileExistsAtPath:fullPath]) {
      NSError *error = nil;
      NSArray *contents = [fileManager contentsOfDirectoryAtPath:fullPath error:&error];

      if (!error && contents) {
        for (NSString *folderName in contents) {
          if ([folderName hasPrefix:@"."]) continue; 

          NSString *folderPath = [fullPath stringByAppendingPathComponent:folderName];

          BOOL isDirectory = NO;
          if ([fileManager fileExistsAtPath:folderPath isDirectory:&isDirectory] && isDirectory) {
            NSString *nosmaiFile = [folderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.nosmai", folderName]];
            NSString *manifestFile = [folderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_manifest.json", folderName]];

            if ([fileManager fileExistsAtPath:nosmaiFile] && [fileManager fileExistsAtPath:manifestFile]) {
              if (![filterNames containsObject:folderName]) {
                [filterNames addObject:folderName];
              }
            }
          }
        }
      }
    }
  }

  if (filterNames.count == 0) {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSArray *allPaths = [mainBundle pathsForResourcesOfType:@"json" inDirectory:nil];

    for (NSString *path in allPaths) {
      if ([path containsString:@"manifest.json"] && [path containsString:@"nosmai_filters"]) {
        NSArray *components = [path componentsSeparatedByString:@"/"];
        for (NSInteger i = 0; i < components.count - 1; i++) {
          if ([components[i] isEqualToString:@"nosmai_filters"] && i + 1 < components.count) {
            NSString *fileName = components.lastObject;

            if ([fileName hasSuffix:@"_manifest.json"]) {
              NSString *filterName = [fileName stringByReplacingOccurrencesOfString:@"_manifest.json" withString:@""];

              if (filterName.length > 0 && ![filterNames containsObject:filterName]) {
                [filterNames addObject:filterName];
              }
            }
          }
        }
      }
    }
  }

  [filterNames sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

  return [filterNames copy];
}

- (NSString *)createDisplayNameFromFilterName:(NSString *)filterName {
  if (!filterName || filterName.length == 0) {
    return @"Unknown Filter";
  }
  
  NSString *displayName = filterName;
  
  displayName = [displayName stringByReplacingOccurrencesOfString:@"_" withString:@" "];
  displayName = [displayName stringByReplacingOccurrencesOfString:@"-" withString:@" "];

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


- (void)sendRecordingProgress {
  if (self.isRecording) {
    NSTimeInterval duration = [[NosmaiCore shared] currentRecordingDuration];
    [self.channel invokeMethod:@"onRecordingProgress" arguments:@{
      @"duration": @(duration)
    }];
  }
}

- (BOOL)isNetworkAvailable {
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
    if (success) {
      // Update internal state tracking
      self.currentFlashMode = flashMode;
    }
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
    if (success) {
      // Update internal state tracking
      self.currentTorchMode = torchMode;
    }
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
    // Check if device has flash capability
    BOOL hasFlash = [[NosmaiCore shared].camera hasFlash];
    if (!hasFlash) {
      result(@"off");
      return;
    }

    // Return internally tracked flash mode (NosmaiCamera doesn't provide getter)
    NSString *modeString;
    switch (self.currentFlashMode) {
      case AVCaptureFlashModeOn:
        modeString = @"on";
        break;
      case AVCaptureFlashModeAuto:
        modeString = @"auto";
        break;
      case AVCaptureFlashModeOff:
      default:
        modeString = @"off";
        break;
    }

    result(modeString);
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
    // Check if device has torch capability
    BOOL hasTorch = [[NosmaiCore shared].camera hasTorch];
    if (!hasTorch) {
      result(@"off");
      return;
    }

    // Return internally tracked torch mode (NosmaiCamera doesn't provide getter)
    NSString *modeString;
    switch (self.currentTorchMode) {
      case AVCaptureTorchModeOn:
        modeString = @"on";
        break;
      case AVCaptureTorchModeAuto:
        modeString = @"auto";
        break;
      case AVCaptureTorchModeOff:
      default:
        modeString = @"off";
        break;
    }

    result(modeString);
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"TORCH_ERROR"
                               message:@"Failed to get torch mode"
                               details:exception.reason]);
  }
}

#pragma mark - Effect Parameter Control

- (void)handleGetEffectParameters:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK not initialized"
                               details:nil]);
    return;
  }

  @try {
    // Get parameters from active effect using NosmaiSDK
    NSArray<NSDictionary*>* parameters = [[NosmaiSDK sharedInstance] getEffectParameters];

    if (parameters == nil) {
      // No effect is currently active or no parameters available
      result(@[]);
      return;
    }

    // Convert NSArray to format expected by Flutter
    NSMutableArray* flutterParameters = [NSMutableArray arrayWithCapacity:parameters.count];

    for (NSDictionary* param in parameters) {
      NSMutableDictionary* flutterParam = [NSMutableDictionary dictionary];

      // Extract parameter information
      if (param[@"name"]) {
        flutterParam[@"name"] = param[@"name"];
      }

      if (param[@"type"]) {
        flutterParam[@"type"] = param[@"type"];
      }

      if (param[@"defaultValue"]) {
        flutterParam[@"defaultValue"] = param[@"defaultValue"];
      }

      if (param[@"passId"]) {
        flutterParam[@"passId"] = param[@"passId"];
      }

      [flutterParameters addObject:flutterParam];
    }

    result(flutterParameters);

  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"EFFECT_PARAMETER_ERROR"
                               message:@"Failed to get effect parameters"
                               details:exception.reason]);
  }
}

- (void)handleGetEffectParameterValue:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK not initialized"
                               details:nil]);
    return;
  }

  NSString* parameterName = call.arguments[@"parameterName"];
  if (parameterName == nil || [parameterName length] == 0) {
    result([FlutterError errorWithCode:@"INVALID_PARAMETER"
                               message:@"Parameter name is required"
                               details:nil]);
    return;
  }

  @try {
    // Get parameter value from active effect using NosmaiSDK
    float value = [[NosmaiSDK sharedInstance] getEffectParameterValue:parameterName];

    // Return the value as NSNumber
    result(@(value));

  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"EFFECT_PARAMETER_ERROR"
                               message:@"Failed to get effect parameter value"
                               details:exception.reason]);
  }
}

- (void)handleSetEffectParameter:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK not initialized"
                               details:nil]);
    return;
  }

  NSString* parameterName = call.arguments[@"parameterName"];
  NSNumber* valueNumber = call.arguments[@"value"];

  if (parameterName == nil || [parameterName length] == 0) {
    result([FlutterError errorWithCode:@"INVALID_PARAMETER"
                               message:@"Parameter name is required"
                               details:nil]);
    return;
  }

  if (valueNumber == nil) {
    result([FlutterError errorWithCode:@"INVALID_PARAMETER"
                               message:@"Parameter value is required"
                               details:nil]);
    return;
  }

  @try {
    // Convert NSNumber to float
    float value = [valueNumber floatValue];

    // Set parameter value using NosmaiSDK
    BOOL success = [[NosmaiSDK sharedInstance] setEffectParameter:parameterName value:value];

    // Return success status
    result(@(success));

  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"EFFECT_PARAMETER_ERROR"
                               message:@"Failed to set effect parameter"
                               details:exception.reason]);
  }
}

- (void)handleSetEffectParameterString:(FlutterMethodCall*)call result:(FlutterResult)result {
  if (!self.isInitialized) {
    result([FlutterError errorWithCode:@"NOT_INITIALIZED"
                               message:@"SDK not initialized"
                               details:nil]);
    return;
  }

  NSString* parameterName = call.arguments[@"parameterName"];
  NSString* value = call.arguments[@"value"];

  if (parameterName == nil || [parameterName length] == 0) {
    result([FlutterError errorWithCode:@"INVALID_PARAMETER"
                               message:@"Parameter name is required"
                               details:nil]);
    return;
  }

  if (value == nil) {
    result([FlutterError errorWithCode:@"INVALID_PARAMETER"
                               message:@"Parameter value is required"
                               details:nil]);
    return;
  }

  @try {
    // Set string parameter value using NosmaiSDK
    BOOL success = [[NosmaiSDK sharedInstance] setEffectParameter:parameterName stringValue:value];

    // Return success status
    result(@(success));

  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"EFFECT_PARAMETER_ERROR"
                               message:@"Failed to set effect parameter string"
                               details:exception.reason]);
  }
}

#pragma mark - Test Filter Method

#pragma mark - External Pixel Buffer Processing

// Static instance for external processing
static NosmaiExternalProcessor *_externalProcessor = nil;
static dispatch_once_t onceToken;
static BOOL isOffscreenInitialized = NO;

// Shared CIContext for GPU-accelerated manual flip (created once, reused for performance)
static CIContext *_sharedFlipCIContext = nil;
static dispatch_once_t _flipCIContextOnceToken;

#pragma mark - Manual Mirror Transform Helper

+ (CIContext *)sharedFlipCIContext {
    dispatch_once(&_flipCIContextOnceToken, ^{
        _sharedFlipCIContext = [CIContext contextWithOptions:@{
            kCIContextUseSoftwareRenderer: @NO,  // Use GPU
            kCIContextPriorityRequestLow: @NO    // High priority
        }];
        NSLog(@"✅ Created shared CIContext for manual flip (GPU-accelerated)");
    });
    return _sharedFlipCIContext;
}

+ (CVPixelBufferRef)flipPixelBufferHorizontally:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) {
        return NULL;
    }

    @autoreleasepool {
        CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
        if (!ciImage) {
            NSLog(@"⚠️ Failed to create CIImage from pixelBuffer");
            return NULL;
        }

        // Apply horizontal flip transform
        CGAffineTransform transform = CGAffineTransformMakeScale(-1.0, 1.0);
        transform = CGAffineTransformTranslate(transform, -ciImage.extent.size.width, 0);
        CIImage *flippedImage = [ciImage imageByApplyingTransform:transform];

        // Create new pixel buffer
        CVPixelBufferRef flippedBuffer = NULL;
        CVReturn status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            NULL,
            &flippedBuffer
        );

        if (status != kCVReturnSuccess || !flippedBuffer) {
            NSLog(@"⚠️ Failed to create flipped CVPixelBuffer: %d", (int)status);
            return NULL;
        }

        // GPU render
        [[self sharedFlipCIContext] render:flippedImage toCVPixelBuffer:flippedBuffer];
        return flippedBuffer;  // Caller must release
    }
}

#pragma mark - New External Processing Implementation

+ (BOOL)processExternalPixelBuffer:(CVPixelBufferRef)pixelBuffer shouldFlip:(BOOL)shouldFlip {
    if (!pixelBuffer) {
        return NO;
    }

    NosmaiSDK *sdk = [NosmaiSDK sharedInstance];
    if (!sdk) {
        return NO;
    }

    // Initialize offscreen mode on first frame
    if (!isOffscreenInitialized) {
        BOOL offscreenSuccess = [sdk initializeOffscreenWithWidth:720 height:1280];
        if (!offscreenSuccess) {
            return NO;
        }
        [sdk setProcessingMode:NosmaiProcessingModeOffscreen];
        [sdk setLiveFrameOutputEnabled:YES];
        isOffscreenInitialized = YES;
        NSLog(@"✅ Nosmai offscreen mode initialized");
    }

    // Lazy init external processor
    dispatch_once(&onceToken, ^{
        _externalProcessor = [[NosmaiExternalProcessor alloc] init];
    });

    @try {
        CVPixelBufferRef bufferToProcess = pixelBuffer;
        CVPixelBufferRef flippedBuffer = NULL;

        // STEP 1: Manual flip if needed (front camera un-mirror)
        if (shouldFlip) {
            flippedBuffer = [self flipPixelBufferHorizontally:pixelBuffer];
            if (flippedBuffer) {
                bufferToProcess = flippedBuffer;
            }
        }

        // STEP 2: Create CMSampleBuffer
        CMSampleBufferRef sampleBuffer = NULL;
        CMSampleTimingInfo timingInfo = {
            .duration = CMTimeMake(1, 30),
            .presentationTimeStamp = CMTimeMake(0, 1),
            .decodeTimeStamp = kCMTimeInvalid
        };

        CMVideoFormatDescriptionRef formatDescription = NULL;
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, bufferToProcess, &formatDescription);

        OSStatus status = CMSampleBufferCreateForImageBuffer(
            kCFAllocatorDefault,
            bufferToProcess,
            true,
            NULL,
            NULL,
            formatDescription,
            &timingInfo,
            &sampleBuffer
        );

        if (formatDescription) {
            CFRelease(formatDescription);
        }

        if (status != noErr || !sampleBuffer) {
            if (flippedBuffer) CVPixelBufferRelease(flippedBuffer);
            return NO;
        }

        // STEP 3: Process with Nosmai (ALWAYS mirror:NO since we manually flipped)
        BOOL processSuccess = [sdk processSampleBuffer:sampleBuffer mirror:NO];
        CFRelease(sampleBuffer);

        if (!processSuccess) {
            if (flippedBuffer) CVPixelBufferRelease(flippedBuffer);
            return NO;
        }

        // STEP 4: Wait for callback
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC);
        long result = dispatch_semaphore_wait(_externalProcessor.frameSemaphore, timeout);

        if (result != 0) {
            if (flippedBuffer) CVPixelBufferRelease(flippedBuffer);
            return NO;
        }

        // STEP 5: Copy back to original buffer
        if (_externalProcessor.lastProcessedBuffer) {
            CVPixelBufferLockBaseAddress(pixelBuffer, 0);
            CVPixelBufferLockBaseAddress(_externalProcessor.lastProcessedBuffer, 0);

            void *srcBaseAddress = CVPixelBufferGetBaseAddress(_externalProcessor.lastProcessedBuffer);
            void *dstBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
            size_t srcBytesPerRow = CVPixelBufferGetBytesPerRow(_externalProcessor.lastProcessedBuffer);
            size_t dstBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
            size_t height = CVPixelBufferGetHeight(pixelBuffer);

            for (size_t row = 0; row < height; row++) {
                memcpy(dstBaseAddress + row * dstBytesPerRow,
                       srcBaseAddress + row * srcBytesPerRow,
                       MIN(srcBytesPerRow, dstBytesPerRow));
            }

            CVPixelBufferUnlockBaseAddress(_externalProcessor.lastProcessedBuffer, 0);
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        }

        // Cleanup
        if (flippedBuffer) {
            CVPixelBufferRelease(flippedBuffer);
        }

        return YES;

    } @catch (NSException *exception) {
        return NO;
    }
}

#pragma mark - Backward Compatible Method

+ (BOOL)processExternalPixelBuffer:(CVPixelBufferRef)pixelBuffer mirror:(BOOL)mirror {
    // Redirect to new implementation
    return [self processExternalPixelBuffer:pixelBuffer shouldFlip:mirror];
}

#pragma mark - Reset External Frame Mode

+ (void)resetExternalFrameMode {
    NSLog(@"🔄 Resetting external frame mode...");

    // Reset offscreen initialization flag
    isOffscreenInitialized = NO;

    // Reset dispatch_once token to allow re-initialization
    onceToken = 0;

    // Clean up external processor
    if (_externalProcessor) {
        if (_externalProcessor.lastProcessedBuffer) {
            CVPixelBufferRelease(_externalProcessor.lastProcessedBuffer);
            _externalProcessor.lastProcessedBuffer = NULL;
        }
        _externalProcessor = nil;
    }

    // Reset SDK processing mode back to live camera mode
    NosmaiSDK *sdk = [NosmaiSDK sharedInstance];
    if (sdk) {
        [sdk setProcessingMode:NosmaiProcessingModeLive];
        [sdk setLiveFrameOutputEnabled:NO];
        [sdk setCVPixelBufferCallback:nil];
        NSLog(@"✅ SDK reset to live camera mode");
    }

    NSLog(@"✅ External frame mode reset complete");
}

@end

#pragma mark - NosmaiExternalProcessor Implementation

@implementation NosmaiExternalProcessor

- (instancetype)init {
    self = [super init];
    if (self) {
        _isInitialized = YES;
        _lastProcessedBuffer = NULL;
        _frameSemaphore = dispatch_semaphore_create(0);

        // Set callback to receive processed frames
        NosmaiSDK *sdk = [NosmaiSDK sharedInstance];
        __weak typeof(self) weakSelf = self;
        [sdk setCVPixelBufferCallback:^(CVPixelBufferRef processedBuffer, double timestamp) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;

            if (processedBuffer) {
                CVPixelBufferRetain(processedBuffer);
                if (strongSelf.lastProcessedBuffer) {
                    CVPixelBufferRelease(strongSelf.lastProcessedBuffer);
                }
                strongSelf.lastProcessedBuffer = processedBuffer;
                dispatch_semaphore_signal(strongSelf.frameSemaphore);
            }
        }];
    }
    return self;
}

- (BOOL)processPixelBuffer:(CVPixelBufferRef)pixelBuffer mirror:(BOOL)mirror {
    if (!_isInitialized) {
        return NO;
    }

    @try {
        // Create CMSampleBuffer from CVPixelBuffer
        CMSampleBufferRef sampleBuffer = NULL;
        CMSampleTimingInfo timingInfo = {
            .duration = CMTimeMake(1, 30),
            .presentationTimeStamp = CMTimeMake(0, 1),
            .decodeTimeStamp = kCMTimeInvalid
        };

        CMVideoFormatDescriptionRef formatDescription = NULL;
        CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDescription);

        OSStatus status = CMSampleBufferCreateForImageBuffer(
            kCFAllocatorDefault,
            pixelBuffer,
            true,
            NULL,
            NULL,
            formatDescription,
            &timingInfo,
            &sampleBuffer
        );

        if (formatDescription) {
            CFRelease(formatDescription);
        }

        if (status != noErr || !sampleBuffer) {
            return NO;
        }

        // Process through NosmaiSDK
        NosmaiSDK *sdk = [NosmaiSDK sharedInstance];
        BOOL processSuccess = [sdk processSampleBuffer:sampleBuffer mirror:mirror];
        CFRelease(sampleBuffer);

        if (!processSuccess) {
            return NO;
        }

        // Wait for processed frame from callback (50ms timeout)
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC);
        long result = dispatch_semaphore_wait(self.frameSemaphore, timeout);

        if (result != 0) {
            return NO;
        }

        // Copy processed frame back to original buffer (no flip needed)
        if (self.lastProcessedBuffer) {
            CVPixelBufferLockBaseAddress(pixelBuffer, 0);
            CVPixelBufferLockBaseAddress(self.lastProcessedBuffer, 0);

            void *srcBaseAddress = CVPixelBufferGetBaseAddress(self.lastProcessedBuffer);
            void *dstBaseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
            size_t srcBytesPerRow = CVPixelBufferGetBytesPerRow(self.lastProcessedBuffer);
            size_t dstBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
            size_t height = CVPixelBufferGetHeight(pixelBuffer);

            for (size_t row = 0; row < height; row++) {
                memcpy(dstBaseAddress + row * dstBytesPerRow,
                       srcBaseAddress + row * srcBytesPerRow,
                       MIN(srcBytesPerRow, dstBytesPerRow));
            }

            CVPixelBufferUnlockBaseAddress(self.lastProcessedBuffer, 0);
            CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

            return YES;
        }

        return NO;
    } @catch (NSException *exception) {
        return NO;
    }
}

- (void)dealloc {
    [[NosmaiSDK sharedInstance] setCVPixelBufferCallback:nil];
    if (_lastProcessedBuffer) {
        CVPixelBufferRelease(_lastProcessedBuffer);
        _lastProcessedBuffer = NULL;
    }
}

@end
