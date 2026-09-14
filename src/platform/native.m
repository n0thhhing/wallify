#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <stdatomic.h>

extern void wallify_pointer(double, double, int);
static NSPanel *panel;
static NSStatusItem *statusItem;
static id<MTLDevice> device;
static id<MTLCommandQueue> queue;
static id<MTLRenderPipelineState> pipelineState;
static CAMetalLayer *surface;
static atomic_int surfaceWidth = 531, surfaceHeight = 199;
static NSLock *frameLock;
static NSData *latestFrame;
static NSUInteger frameWidth, frameHeight;
static BOOL scheduled;

@interface WallifyView : NSView
@end
@implementation WallifyView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return NO; }
- (void)updateTrackingAreas {
    for (NSTrackingArea *area in self.trackingAreas) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect owner:self userInfo:nil]];
    [super updateTrackingAreas];
}
- (void)pointer:(NSEvent *)event kind:(int)kind {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    wallify_pointer(p.x, p.y, kind);
}
- (void)mouseDown:(NSEvent *)e { [self pointer:e kind:1]; }
- (void)mouseUp:(NSEvent *)e { [self pointer:e kind:2]; }
- (void)mouseMoved:(NSEvent *)e { [self pointer:e kind:0]; }
- (void)mouseDragged:(NSEvent *)e { [self pointer:e kind:0]; }
- (void)mouseExited:(NSEvent *)e { wallify_pointer(-1, -1, 0); }
- (void)rightMouseUp:(NSEvent *)e { [self pointer:e kind:3]; }
@end
@interface WallifyPanel : NSPanel
@end
@implementation WallifyPanel
- (BOOL)canBecomeKeyWindow { return NO; }
@end

static void movePanel(int left, int top) {
    NSRect screen = (panel.screen ?: NSScreen.mainScreen).visibleFrame;
    [panel setFrameOrigin:NSMakePoint(screen.origin.x + left, NSMaxY(screen) - top - panel.frame.size.height)];
}
bool wallify_create(bool compact, int left, int top) {
    device = MTLCreateSystemDefaultDevice();
    queue = [device newCommandQueue];
    
    NSError *error = nil;
    id<MTLLibrary> defaultLibrary = [device newLibraryWithSource:metalShaderSource options:nil error:&error];
    if (!defaultLibrary) {
        NSString *resourcePath = [[NSBundle mainBundle] pathForResource:@"default" ofType:@"metallib"];
        if (resourcePath) {
            defaultLibrary = [device newLibraryWithFile:resourcePath error:&error];
        }
    }
    
    if (defaultLibrary) {
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Simple Pipeline";
        pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"vertex_main"];
        pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"fragment_main"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        
        pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        if (!pipelineState) NSLog(@"Failed to created pipeline state, error %@", error);
    }

    if (!device || !queue) return false;
    frameLock = [NSLock new];
    atomic_store(&surfaceWidth, compact ? 180 : 531);
    atomic_store(&surfaceHeight, compact ? 224 : 199);
    NSRect bounds = NSMakeRect(0, 0, atomic_load(&surfaceWidth), atomic_load(&surfaceHeight));
    panel = [[WallifyPanel alloc] initWithContentRect:bounds styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    panel.title = @"Wallify";
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = NO;
    panel.hidesOnDeactivate = NO;
    panel.releasedWhenClosed = NO;
    panel.level = NSNormalWindowLevel - 1;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary;
    WallifyView *view = [[WallifyView alloc] initWithFrame:bounds];
    surface = [CAMetalLayer layer];
    surface.device = device;
    surface.pixelFormat = MTLPixelFormatBGRA8Unorm;
    surface.framebufferOnly = NO;
    surface.opaque = NO;
    surface.contentsScale = 2;
    view.wantsLayer = YES;
    view.layer = surface;
    panel.contentView = view;
    [panel makeFirstResponder:view];
    movePanel(left, top);
    [panel orderFrontRegardless];
    statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    statusItem.button.title = @"♫";
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Wallify"];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Wallify" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    [menu addItem:quit];
    statusItem.menu = menu;
    return true;
}

// Coalesce frames: AppKit never accumulates a queue of stale pixel buffers.
static void presentLatest(void) {
    @autoreleasepool {
        [frameLock lock];
        NSData *pixels = latestFrame;
        NSUInteger width = frameWidth, height = frameHeight;
        latestFrame = nil;
        scheduled = NO;
        [frameLock unlock];
        if (!pixels) return;
        surface.drawableSize = CGSizeMake(width, height);
        id<CAMetalDrawable> drawable = [surface nextDrawable];
        if (!drawable) return;
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:width height:height mipmapped:NO];
        desc.storageMode = MTLStorageModeShared;
        id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
        if (!texture) return;
        [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:pixels.bytes bytesPerRow:width * 4];
        id<MTLCommandBuffer> command = [queue commandBuffer];
        id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
        [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(width,height,1) toTexture:drawable.texture destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
        [blit endEncoding];
        [command presentDrawable:drawable];
        [command commit];
    }
}
void wallify_present(const unsigned int *pixels, size_t width, size_t height) {
    @autoreleasepool {
        // The shared software canvas uses straight alpha; Core Animation expects premultiplied RGBA.
        NSMutableData *copy = [NSMutableData dataWithBytes:pixels length:width * height * 4];
        unsigned char *p = copy.mutableBytes;
        for (size_t i = 0; i < width * height; i++, p += 4) {
            for (int c = 0; c < 3; c++) p[c] = (p[c] * p[3] + 127) / 255;
            unsigned char r = p[0]; p[0] = p[2]; p[2] = r;
        }
        [frameLock lock];
        latestFrame = copy; frameWidth = width; frameHeight = height;
        BOOL enqueue = !scheduled;
        scheduled = YES;
        [frameLock unlock];
        if (enqueue) dispatch_async(dispatch_get_main_queue(), ^{ presentLatest(); });
    }
}
void wallify_resize(bool compact) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSRect frame = panel.frame;
        CGFloat top = NSMaxY(frame);
        frame.size = NSMakeSize(compact ? 180 : 531, compact ? 224 : 199);
        frame.origin.y = top - frame.size.height;
        [panel setFrame:frame display:YES];
        atomic_store(&surfaceWidth, (int)frame.size.width);
        atomic_store(&surfaceHeight, (int)frame.size.height);
    });
}
void wallify_move(int left, int top) { dispatch_async(dispatch_get_main_queue(), ^{ movePanel(left, top); }); }
int wallify_width(void) { return atomic_load(&surfaceWidth); }
int wallify_height(void) { return atomic_load(&surfaceHeight); }

static NSString *settingsPath;
void wallify_prepare(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        if ([bundle.bundlePath.pathExtension isEqualToString:@"app"]) {
            NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Wallify"];
            [[NSFileManager defaultManager] createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:nil];
            settingsPath = [support stringByAppendingPathComponent:@"widget-settings.conf"];
            if (![[NSFileManager defaultManager] fileExistsAtPath:settingsPath])
                [[NSFileManager defaultManager] copyItemAtPath:[bundle.resourcePath stringByAppendingPathComponent:@"widget-settings.conf"] toPath:settingsPath error:nil];
            [[NSFileManager defaultManager] changeCurrentDirectoryPath:bundle.resourcePath];
        } else settingsPath = @"widget-settings.conf";
    }
}
const char *wallify_settings_path(void) { return (settingsPath ?: @"widget-settings.conf").fileSystemRepresentation; }
