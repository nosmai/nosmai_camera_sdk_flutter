#import "NosmaiCameraPreviewView.h"
#import "NosmaiFlutterPlugin.h"
#import <nosmai/Nosmai.h>
#import <nosmai/NosmaiSDK.h>

// Custom UIView subclass that handles layout updates
@interface NosmaiNativePreviewView : UIView
@end

@implementation NosmaiNativePreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // Ensure the view can handle device rotations and size changes
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        // Set up notifications for orientation changes
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(orientationDidChange:)
                                                     name:UIDeviceOrientationDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // Ensure we're on the main thread for UI updates
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self layoutSubviews];
        });
        return;
    }
    
    // Force the camera preview to fill the entire view bounds
    // This ensures proper scaling on all device sizes
    NosmaiCore* core = [NosmaiCore shared];
    if (core && core.isInitialized && core.camera) {
        // Update all sublayers to fill the bounds
        for (CALayer* layer in self.layer.sublayers) {
            // Set the layer frame to match the view bounds exactly
            layer.frame = self.bounds;
            
            // Use aspect fill to ensure full coverage without letterboxing
            layer.contentsGravity = kCAGravityResizeAspectFill;
            
            // Ensure the layer is properly positioned
            layer.position = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
            
            // Enable bounds clipping to prevent overflow
            layer.masksToBounds = YES;
            
            // Force the layer to update its display
            [layer setNeedsDisplay];
        }
        
        // Force resize of all NosmaiView subviews
        for (UIView* subview in self.subviews) {
            if ([subview isKindOfClass:NSClassFromString(@"NosmaiView")]) {
                subview.frame = self.bounds;
                subview.layer.contentsGravity = kCAGravityResizeAspectFill;
                subview.layer.masksToBounds = YES;
                subview.contentMode = UIViewContentModeScaleAspectFill;
                
                // Force all sublayers to also scale to fill
                for (CALayer* layer in subview.layer.sublayers) {
                    layer.frame = subview.bounds;
                    layer.contentsGravity = kCAGravityResizeAspectFill;
                    layer.masksToBounds = YES;
                    [layer setNeedsDisplay];
                }
                
                [subview setNeedsLayout];
                [subview layoutIfNeeded];
                
            }
        }
    }
    
}

- (void)orientationDidChange:(NSNotification*)notification {
    // Force layout update when device orientation changes
    dispatch_async(dispatch_get_main_queue(), ^{
        [self setNeedsLayout];
        [self layoutIfNeeded];
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
        
        // Parse creation parameters from Flutter
        NSDictionary* creationParams = (NSDictionary*)args;
        CGFloat requestedWidth = 0;
        CGFloat requestedHeight = 0;
        NSString* deviceType = @"phone";
        BOOL hasNotch = NO;
        BOOL hasBottomSafeArea = NO;
        CGFloat safeAreaTop = 0;
        CGFloat safeAreaBottom = 0;
        
        if (creationParams) {
            if (creationParams[@"width"]) {
                requestedWidth = [creationParams[@"width"] doubleValue];
            }
            if (creationParams[@"height"]) {
                requestedHeight = [creationParams[@"height"] doubleValue];
            }
            if (creationParams[@"deviceType"]) {
                deviceType = creationParams[@"deviceType"];
                hasNotch = [deviceType containsString:@"_notch"];
                hasBottomSafeArea = [deviceType containsString:@"_bottom"];
            }
            if (creationParams[@"safeAreaTop"]) {
                safeAreaTop = [creationParams[@"safeAreaTop"] doubleValue];
            }
            if (creationParams[@"safeAreaBottom"]) {
                safeAreaBottom = [creationParams[@"safeAreaBottom"] doubleValue];
            }
        }
        
        // Use provided frame as-is (original approach)
        adjustedFrame = frame;
        
        _nativeView = [[NosmaiNativePreviewView alloc] initWithFrame:adjustedFrame];
        _nativeView.backgroundColor = [UIColor blackColor];
        _nativeView.layer.masksToBounds = YES;
        _nativeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        // Use ScaleAspectFill to ensure full coverage without letterboxing
        _nativeView.contentMode = UIViewContentModeScaleAspectFill;
        
        // Set content scaling mode for full-screen display (no letterboxing)
        _nativeView.layer.contentsGravity = kCAGravityResizeAspectFill;
        
        // Ensure the view is properly configured for OpenGL rendering
        _nativeView.opaque = YES;
        _nativeView.clearsContextBeforeDrawing = NO;
        
        // Set up proper layer configuration for high-performance rendering
        _nativeView.layer.opaque = YES;
        _nativeView.layer.drawsAsynchronously = NO; // Disable async drawing to reduce thread issues
        
        // Ensure the view extends to all edges (including safe areas)
        _nativeView.clipsToBounds = YES;
        _nativeView.insetsLayoutMarginsFromSafeArea = NO;
        
        // Log device screen information for comparison
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGSize screenSize = screenBounds.size;
        UIEdgeInsets safeAreaInsets = UIEdgeInsetsZero;
        
        if (@available(iOS 11.0, *)) {
            UIWindow* keyWindow = [UIApplication sharedApplication].keyWindow;
            if (keyWindow) {
                safeAreaInsets = keyWindow.safeAreaInsets;
            }
        }
        
        // Setup camera preview immediately since SDK is pre-warmed
        [self performCameraAttachment];
    }
    return self;
}

- (void)setupCameraPreviewWithStateCheck {
    dispatch_async(_setupQueue, ^{
        // Use semaphore to ensure only one setup operation at a time
        dispatch_semaphore_wait(self.setupSemaphore, DISPATCH_TIME_FOREVER);
        
        if (self.isSetupInProgress) {
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
            dispatch_semaphore_wait(self.setupSemaphore, DISPATCH_TIME_FOREVER);
            self.isSetupInProgress = NO;
            self.setupRetryCount = 0;
            dispatch_semaphore_signal(self.setupSemaphore);
            return;
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self waitForSDKReadyThenSetup];
        });
    }
}

- (void)performCameraAttachment {
    dispatch_async(dispatch_get_main_queue(), ^{
        NosmaiCore* core = [NosmaiCore shared];
        
        if (!core || !core.isInitialized) {
            dispatch_semaphore_wait(self.setupSemaphore, DISPATCH_TIME_FOREVER);
            self.isSetupInProgress = NO;
            dispatch_semaphore_signal(self.setupSemaphore);
            return;
        }
        
        // Don't setup during recording to prevent black screen
        if (core.isRecording) {
            dispatch_semaphore_wait(self.setupSemaphore, DISPATCH_TIME_FOREVER);
            self.isSetupInProgress = NO;
            dispatch_semaphore_signal(self.setupSemaphore);
            return;
        }
        
        
        // Detach from previous view if needed
        if (self.isAttached && !self.wasDetachedGracefully) {
            [core.camera detachFromView];
            self.isAttached = NO;
        }
        
        // Attach immediately without delay
        [self attachCameraToView];
    });
}

- (void)attachCameraToView {
    // Ensure camera attachment happens on main thread
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self attachCameraToView];
        });
        return;
    }
    
    NosmaiCore* core = [NosmaiCore shared];
    
    // Reset graceful detach flag
    self.wasDetachedGracefully = NO;
    
    // Always proceed with attachment - NosmaiSDK handles processing state internally
    [self completeAttachment];
}

- (void)completeAttachment {
    NosmaiCore* core = [NosmaiCore shared];
    
    // Essential dual attachment (the actual fix)
    [core.camera attachToView:self->_nativeView];
    [[NosmaiSDK sharedInstance] setPreviewView:self->_nativeView];
    self.isAttached = YES;
    
    // Configure the native view for full-screen display
    self->_nativeView.layer.contentsGravity = kCAGravityResizeAspectFill;
    self->_nativeView.layer.masksToBounds = YES;
    
    // Single layout update - let the system handle proper sizing
    [self->_nativeView setNeedsLayout];
    [self->_nativeView layoutIfNeeded];
    
    // Essential fillMode configuration (the key fix)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self configureNosmaiViewFillMode];
    });
    
    
    // Reset setup state
    dispatch_semaphore_wait(self.setupSemaphore, DISPATCH_TIME_FOREVER);
    self.isSetupInProgress = NO;
    self.setupRetryCount = 0;
    dispatch_semaphore_signal(self.setupSemaphore);
    
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

- (void)updateViewBounds:(CGRect)bounds {
    // Update the native view bounds for dynamic resizing on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_nativeView.frame = bounds;
        
        // Force full layout update for new bounds
        [self->_nativeView setNeedsLayout];
        [self->_nativeView layoutIfNeeded];
        
        // Update layer properties for new frame
        self->_nativeView.layer.contentsGravity = kCAGravityResizeAspectFill;
        self->_nativeView.layer.masksToBounds = YES;
        
        
        // Force resize of all NosmaiView subviews
        [self forceNosmaiViewResize];
        
        // Additional delayed update for complex layout changes
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self->_nativeView setNeedsLayout];
            [self->_nativeView layoutIfNeeded];
            [self forceNosmaiViewResize];
        });
    });
}

- (void)forceNosmaiViewResize {
    // Force resize of all NosmaiView instances to fill the entire bounds
    for (UIView* subview in self->_nativeView.subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"NosmaiView")]) {
            subview.frame = self->_nativeView.bounds;
            subview.layer.contentsGravity = kCAGravityResizeAspectFill;
            subview.layer.masksToBounds = YES;
            subview.contentMode = UIViewContentModeScaleAspectFill;
            
            // Force all sublayers to also scale to fill
            for (CALayer* layer in subview.layer.sublayers) {
                layer.frame = subview.bounds;
                layer.contentsGravity = kCAGravityResizeAspectFill;
                layer.masksToBounds = YES;
                [layer setNeedsDisplay];
            }
            
            [subview setNeedsLayout];
            [subview layoutIfNeeded];
        }
    }
}

- (void)configureNosmaiViewFillMode {
    // Essential fillMode fix from working iOS app
    for (UIView *subview in self->_nativeView.subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"NosmaiView")]) {
            subview.frame = self->_nativeView.bounds;
            if ([subview respondsToSelector:@selector(setFillMode:)]) {
                [subview setValue:@(2) forKey:@"fillMode"]; // Aspect fill
            }
            break;
        }
    }
}

- (void)detachCameraGracefully {
    
    // Use semaphore to ensure thread-safe detachment
    dispatch_semaphore_wait(self.setupSemaphore, DISPATCH_TIME_FOREVER);
    
    NosmaiCore* core = [NosmaiCore shared];
    if (core && core.isInitialized && self.isAttached) {
        [core.camera detachFromView];
        self.isAttached = NO;
        self.wasDetachedGracefully = YES;
    }
    
    dispatch_semaphore_signal(self.setupSemaphore);
}

- (void)dealloc {
    
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
    
    return newView;
}

- (NSObject<FlutterMessageCodec>*)createArgsCodec {
    return [FlutterStandardMessageCodec sharedInstance];
}

@end
