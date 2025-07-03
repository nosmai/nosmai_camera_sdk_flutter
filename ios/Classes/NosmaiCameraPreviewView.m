#import "NosmaiCameraPreviewView.h"
#import "NosmaiFlutterPlugin.h"
#import <nosmai/Nosmai.h>
#import <nosmai/NosmaiSDK.h>

// Custom UIView subclass that handles layout updates
@interface NosmaiNativePreviewView : UIView
@end

@implementation NosmaiNativePreviewView

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // The camera preview layer frame should be automatically updated by the SDK
    // when attachToView is called, which happens during initial setup.
    // We don't need to manually update it here since the SDK handles frame management.
    NSLog(@"📐 NosmaiNativePreviewView layout updated with bounds: %@", NSStringFromCGRect(self.bounds));
}

@end

@interface NosmaiCameraPreviewView()
@property(nonatomic, strong) NosmaiNativePreviewView* nativeView;
@property(nonatomic, assign) BOOL isSetupInProgress;
@property(nonatomic, strong) dispatch_queue_t setupQueue;
@property(nonatomic, assign) BOOL isAttached;
@property(nonatomic, assign) BOOL wasDetachedGracefully;
@property(nonatomic, strong) dispatch_semaphore_t setupSemaphore;
@property(nonatomic, assign) NSInteger setupRetryCount;
@end

@implementation NosmaiCameraPreviewView

- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
              binaryMessenger:(NSObject<FlutterBinaryMessenger>*)messenger {
    if (self = [super init]) {
        // Initialize thread-safe setup queue
        _setupQueue = dispatch_queue_create("com.nosmai.preview.setup", DISPATCH_QUEUE_SERIAL);
        _isSetupInProgress = NO;
        _isAttached = NO;
        _wasDetachedGracefully = NO;
        _setupSemaphore = dispatch_semaphore_create(1);
        _setupRetryCount = 0;
        
        // Create the native view that will host the camera preview
        CGRect adjustedFrame = frame;
        
        // Use screen bounds for full-screen when frame is zero or very small
        if (CGRectEqualToRect(frame, CGRectZero) || frame.size.width < 100 || frame.size.height < 100) {
            adjustedFrame = [UIScreen mainScreen].bounds;
        }
        
        _nativeView = [[NosmaiNativePreviewView alloc] initWithFrame:adjustedFrame];
        _nativeView.backgroundColor = [UIColor blackColor];
        _nativeView.layer.masksToBounds = YES;
        _nativeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _nativeView.contentMode = UIViewContentModeScaleAspectFill;
        
        // Set content scaling mode for better full-screen display
        _nativeView.layer.contentsGravity = kCAGravityResizeAspectFill;
        
        NSLog(@"📱 NosmaiCameraPreviewView created with frame: %@ (viewId: %lld)", NSStringFromCGRect(adjustedFrame), viewId);
        
        // Setup camera preview safely with state-based waiting
        [self setupCameraPreviewWithStateCheck];
    }
    return self;
}

- (void)setupCameraPreviewWithStateCheck {
    dispatch_async(_setupQueue, ^{
        // Use semaphore to ensure only one setup operation at a time
        dispatch_semaphore_wait(self.setupSemaphore, DISPATCH_TIME_FOREVER);
        
        if (self.isSetupInProgress) {
            NSLog(@"⚠️ Camera setup already in progress, skipping...");
            dispatch_semaphore_signal(self.setupSemaphore);
            return;
        }
        
        self.isSetupInProgress = YES;
        dispatch_semaphore_signal(self.setupSemaphore);
        
        [self waitForSDKReadyThenSetup];
    });
}

- (void)waitForSDKReadyThenSetup {
    NosmaiCore* core = [NosmaiCore shared];
    
    if (core && core.isInitialized) {
        [self performCameraAttachment];
    } else {
        self.setupRetryCount++;
        if (self.setupRetryCount > 10) {
            NSLog(@"❌ Failed to setup camera after 10 retries - SDK not ready");
            dispatch_semaphore_wait(self.setupSemaphore, DISPATCH_TIME_FOREVER);
            self.isSetupInProgress = NO;
            self.setupRetryCount = 0;
            dispatch_semaphore_signal(self.setupSemaphore);
            return;
        }
        
        NSLog(@"⏳ SDK not ready (attempt %ld), waiting...", (long)self.setupRetryCount);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self waitForSDKReadyThenSetup];
        });
    }
}

- (void)performCameraAttachment {
    dispatch_async(dispatch_get_main_queue(), ^{
        NosmaiCore* core = [NosmaiCore shared];
        
        if (!core || !core.isInitialized) {
            NSLog(@"❌ Core became unavailable during setup");
            dispatch_semaphore_wait(self.setupSemaphore, DISPATCH_TIME_FOREVER);
            self.isSetupInProgress = NO;
            dispatch_semaphore_signal(self.setupSemaphore);
            return;
        }
        
        // Don't setup during recording to prevent black screen
        if (core.isRecording) {
            NSLog(@"⚠️ Skipping camera setup during recording");
            dispatch_semaphore_wait(self.setupSemaphore, DISPATCH_TIME_FOREVER);
            self.isSetupInProgress = NO;
            dispatch_semaphore_signal(self.setupSemaphore);
            return;
        }
        
        NSLog(@"🔧 Setting up camera attachment (attached: %@, graceful: %@)", 
              self.isAttached ? @"YES" : @"NO",
              self.wasDetachedGracefully ? @"YES" : @"NO");
        
        // Detach from previous view if needed
        if (self.isAttached && !self.wasDetachedGracefully) {
            NSLog(@"🔄 Detaching from previous view before reattaching");
            [core.camera detachFromView];
            self.isAttached = NO;
            
            // Wait a moment for detachment to complete
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self attachCameraToView];
            });
        } else {
            [self attachCameraToView];
        }
    });
}

- (void)attachCameraToView {
    NosmaiCore* core = [NosmaiCore shared];
    
    // Reset graceful detach flag
    self.wasDetachedGracefully = NO;
    
    // 🔧 FIX: Set preview view on NosmaiSDK to ensure proper connection
    [[NosmaiSDK sharedInstance] setPreviewView:self->_nativeView];
    
    // Attach camera to this view
    [core.camera attachToView:self->_nativeView];
    self.isAttached = YES;
    
    NSLog(@"📺 Camera attached to preview view (frame: %@)", NSStringFromCGRect(self->_nativeView.frame));
    
    // Force layout update
    [self->_nativeView setNeedsLayout];
    [self->_nativeView layoutIfNeeded];
    
    // Reset setup state
    dispatch_semaphore_wait(self.setupSemaphore, DISPATCH_TIME_FOREVER);
    self.isSetupInProgress = NO;
    self.setupRetryCount = 0;
    dispatch_semaphore_signal(self.setupSemaphore);
    
    NSLog(@"✅ Camera setup completed successfully");
}

- (void)setupCameraPreviewSafely {
    // Redirect to new state-based method
    [self setupCameraPreviewWithStateCheck];
}

- (void)setupCameraPreview {
    // Deprecated method - redirect to safe version
    [self setupCameraPreviewSafely];
}

- (UIView*)view {
    return _nativeView;
}

- (void)detachCameraGracefully {
    NSLog(@"🔄 Gracefully detaching camera from view");
    
    // Use semaphore to ensure thread-safe detachment
    dispatch_semaphore_wait(self.setupSemaphore, DISPATCH_TIME_FOREVER);
    
    NosmaiCore* core = [NosmaiCore shared];
    if (core && core.isInitialized && self.isAttached) {
        [core.camera detachFromView];
        self.isAttached = NO;
        self.wasDetachedGracefully = YES;
        NSLog(@"📺 Camera gracefully detached from view");
    }
    
    dispatch_semaphore_signal(self.setupSemaphore);
}

- (void)dealloc {
    NSLog(@"🗑️ NosmaiCameraPreviewView deallocating (attached: %@)", self.isAttached ? @"YES" : @"NO");
    
    // Clean detachment when view is deallocated
    if (self.isAttached) {
        [self detachCameraGracefully];
    }
    
    // Clean up dispatch queue and semaphore
    if (_setupQueue) {
        _setupQueue = nil;
    }
    if (_setupSemaphore) {
        _setupSemaphore = nil;
    }
}

@end

@implementation NosmaiCameraPreviewViewFactory {
    NSObject<FlutterBinaryMessenger>* _messenger;
    NSMutableDictionary<NSNumber*, NosmaiCameraPreviewView*>* _activeViews;
}

- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger>*)messenger {
    self = [super init];
    if (self) {
        _messenger = messenger;
        _activeViews = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSObject<FlutterPlatformView>*)createWithFrame:(CGRect)frame
                                   viewIdentifier:(int64_t)viewId
                                        arguments:(id _Nullable)args {
    
    // Clean up any existing view with the same ID
    NSNumber* viewIdKey = @(viewId);
    NosmaiCameraPreviewView* existingView = _activeViews[viewIdKey];
    if (existingView) {
        NSLog(@"🔄 Cleaning up existing view with ID: %lld", viewId);
        [existingView detachCameraGracefully];
        [_activeViews removeObjectForKey:viewIdKey];
    }
    
    // Create new view
    NosmaiCameraPreviewView* newView = [[NosmaiCameraPreviewView alloc] initWithFrame:frame
                                                                       viewIdentifier:viewId
                                                                            arguments:args
                                                                      binaryMessenger:_messenger];
    
    // Track the new view
    _activeViews[viewIdKey] = newView;
    
    NSLog(@"📱 Created new camera preview view with ID: %lld (total active: %lu)", viewId, (unsigned long)_activeViews.count);
    
    return newView;
}

- (NSObject<FlutterMessageCodec>*)createArgsCodec {
    return [FlutterStandardMessageCodec sharedInstance];
}

@end