#import "gpu.h"
#import "debug_stats.h"
#import "settings_window.h"
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/CATransaction.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#include <simd/simd.h>
#include <stdatomic.h>
#include <unistd.h>

extern void wallify_pointer(double, double, int);

static NSPanel* panel;
static NSStatusItem* statusItem;
static id<MTLDevice> device;
static id<MTLCommandQueue> queue;
static id<MTLRenderPipelineState> pipelineState;
static CAMetalLayer* surface;
static atomic_int surfaceWidth, surfaceHeight;
static NSLock* frameLock;
static BOOL scheduled;
static DrawCommand latestCommands[WALLIFY_MAX_COMMANDS];
static size_t latestCount;
static simd_float2 latestSize;
static id<MTLTexture> loadedTextures[WALLIFY_MAX_TEXTURES];
static id<MTLTexture> latestTextures[WALLIFY_MAX_TEXTURES];
static dispatch_semaphore_t inFlight;
static BOOL profiling;
static BOOL lastGlassUpdateValid;
static BOOL lastGlassActive;
static double lastGlassX, lastGlassY, lastGlassW, lastGlassH, lastGlassRadius;
static atomic_ulong sceneNanos, gpuNanos, uploadedBytes, sceneFrames, renderedFrames, drawCalls;

void wallify_debug_renderer_stats(WallifyRendererStats* out) {
    *out = (WallifyRendererStats){0};
    snprintf(out->device_name, sizeof(out->device_name), "%s", device.name.UTF8String ?: "Unavailable");
    out->ready = device != nil && pipelineState != nil && surface != nil;
    out->profiling = profiling;
    out->scene_frames = atomic_load(&sceneFrames);
    out->rendered_frames = atomic_load(&renderedFrames);
    out->uploaded_bytes = atomic_load(&uploadedBytes);
    if (out->scene_frames)
        out->scene_ms = atomic_load(&sceneNanos) / (double)out->scene_frames / 1e6;
    if (out->rendered_frames)
        out->gpu_ms = atomic_load(&gpuNanos) / (double)out->rendered_frames / 1e6;
    [frameLock lock];
    out->pending = scheduled;
    out->command_count = (uint32_t)latestCount;
    out->logical_width = latestSize.x;
    out->logical_height = latestSize.y;
    for (size_t i = 0; i < WALLIFY_MAX_TEXTURES; ++i) {
        if (loadedTextures[i]) {
            ++out->texture_count;
            out->texture_bytes += loadedTextures[i].allocatedSize;
        }
    }
    [frameLock unlock];
    out->drawable_width = surface.drawableSize.width;
    out->drawable_height = surface.drawableSize.height;
    out->scale = surface.contentsScale;
}

void wallify_profile_scene(double seconds) {
    if (!profiling)
        return;

    atomic_fetch_add(&sceneNanos, (unsigned long)(seconds * 1e9));

    unsigned long frames = atomic_fetch_add(&sceneFrames, 1) + 1;

    if (frames % 300 == 0) {
        unsigned long rendered = atomic_load(&renderedFrames);

        fprintf(stderr,
                "Wallify profile: frames=%lu scene_cpu_ms=%.3f gpu_ms=%.3f commands_per_frame=%.1f "
                "asset_upload_bytes=%lu full_frame_upload_bytes=0\n",
                frames, atomic_load(&sceneNanos) / (double)frames / 1e6,
                rendered ? atomic_load(&gpuNanos) / (double)rendered / 1e6 : 0,
                rendered ? atomic_load(&drawCalls) / (double)rendered : 0,
                atomic_load(&uploadedBytes));
    }
}

@interface WallifyView : NSView
@end

@implementation WallifyView

- (BOOL)isFlipped {
    return YES;
}

- (NSView*)hitTest:(NSPoint)point {
    return self;
}

- (BOOL)acceptsFirstResponder {
    return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

- (void)updateTrackingAreas {
    for (NSTrackingArea* area in self.trackingAreas) {
        [self removeTrackingArea:area];
    }

    NSTrackingArea* area = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                     NSTrackingActiveAlways | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];

    [self addTrackingArea:area];
    [super updateTrackingAreas];
}

- (void)pointer:(NSEvent*)event kind:(int)kind {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];

    wallify_pointer(p.x, p.y, kind);
}

- (void)mouseDown:(NSEvent*)e {
    [self pointer:e kind:1];
}

- (void)mouseUp:(NSEvent*)e {
    [self pointer:e kind:2];
}

- (void)mouseMoved:(NSEvent*)e {
    [self pointer:e kind:0];
}

- (void)mouseDragged:(NSEvent*)e {
    [self pointer:e kind:0];
}

- (void)mouseExited:(NSEvent*)e {
    (void)e;
    wallify_pointer(-1, -1, 0);
}

- (void)rightMouseUp:(NSEvent*)e {
    [self pointer:e kind:3];
}

@end

@interface WallifyPanel : NSPanel
@end

@implementation WallifyPanel

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}

- (BOOL)_hasActiveAppearance {
    return YES;
}

- (BOOL)_hasActiveAppearanceIgnoringKeyFocus {
    return YES;
}

- (BOOL)_hasActiveControls {
    return YES;
}

- (BOOL)_hasKeyAppearance {
    return YES;
}

- (BOOL)_hasMainAppearance {
    return YES;
}

@end

// Let AppKit own the glass material, optical filters, and rim.
static NSGlassEffectView* globalGlassView = nil;
static NSView* globalGlassContentView = nil;
static WallifyView* globalMetalView = nil;

@interface WallifyDesktopGlassView : NSGlassEffectView
@end

@implementation WallifyDesktopGlassView
@end

@interface WallifyStatusMenuTarget : NSObject
+ (instancetype)sharedTarget;
- (void)statusOpenSettings:(id)sender;
- (void)statusOpenSpotify:(id)sender;
@end

@interface WallifyAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation WallifyAppDelegate

- (void)applicationWillTerminate:(NSNotification*)notification {
    (void)notification;

    unlink("/tmp/art.raw");
    unlink("/tmp/art.bmp");
    unlink("/tmp/art-next.bmp");
    unlink("/tmp/mrc_artwork");
    unlink("/tmp/mrc_artwork_tmp");
}

@end

@implementation WallifyStatusMenuTarget

+ (instancetype)sharedTarget {
    static WallifyStatusMenuTarget* target = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
      target = [[WallifyStatusMenuTarget alloc] init];
    });

    return target;
}

- (void)statusOpenSettings:(id)sender {
    (void)sender;
    wallify_show_settings_window();
}

- (void)statusOpenSpotify:(id)sender {
    (void)sender;

    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"spotify:"]];
}

@end

static void movePanel(int left, int top) {
    NSRect screen = (panel.screen ?: NSScreen.mainScreen).visibleFrame;

    [panel setFrameOrigin:NSMakePoint(screen.origin.x + left,
                                      NSMaxY(screen) - top - panel.frame.size.height)];
}

bool wallify_create(int width, int height, int left, int top) {
    profiling = getenv("WALLIFY_PROFILE") != NULL;
    NSLog(@"Wallify: create %dx%d at %d,%d profiling=%@",
          width, height, left, top, profiling ? @"on" : @"off");

    device = MTLCreateSystemDefaultDevice();

    queue = [device newCommandQueue];

    if (!device || !queue) {
        NSLog(@"Wallify: Metal device or command queue unavailable.");

        return false;
    }

    NSError* error = nil;
    id<MTLLibrary> defaultLibrary = nil;

    NSURL* libraryURL = [[NSBundle mainBundle] URLForResource:@"default" withExtension:@"metallib"];

    if (libraryURL) {
        defaultLibrary = [device newLibraryWithURL:libraryURL error:&error];
    } else {
        /*
         * Fallback for zig-out/bin/wallify.
         */
        NSString* execPath = [[NSBundle mainBundle] executablePath];

        NSString* execDir = [execPath stringByDeletingLastPathComponent];

        NSURL* fallbackURL =
            [NSURL fileURLWithPath:[execDir stringByAppendingPathComponent:@"default.metallib"]];

        defaultLibrary = [device newLibraryWithURL:fallbackURL error:&error];
    }

    if (!defaultLibrary) {
        NSLog(@"Wallify: Failed to load Metal shaders: %@", error);
    }

    if (defaultLibrary) {
        MTLRenderPipelineDescriptor* pipelineStateDescriptor =
            [[MTLRenderPipelineDescriptor alloc] init];

        pipelineStateDescriptor.label = @"Wallify GPU compositor";

        pipelineStateDescriptor.vertexFunction =
            [defaultLibrary newFunctionWithName:@"vertex_main"];

        pipelineStateDescriptor.fragmentFunction =
            [defaultLibrary newFunctionWithName:@"fragment_main"];

        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

        pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;

        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;

        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;

        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;

        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;

        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor =
            MTLBlendFactorOneMinusSourceAlpha;

        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor =
            MTLBlendFactorOneMinusSourceAlpha;

        pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                               error:&error];

        if (!pipelineState) {
            NSLog(@"Wallify: Failed to create pipeline state: %@", error);
        }
    }

    if (!pipelineState) {
        return false;
    }

    inFlight = dispatch_semaphore_create(2);

    frameLock = [NSLock new];

    atomic_store(&surfaceWidth, width);

    atomic_store(&surfaceHeight, height);

    NSRect bounds = NSMakeRect(0, 0, atomic_load(&surfaceWidth), atomic_load(&surfaceHeight));

    panel = [[WallifyPanel alloc] initWithContentRect:bounds
                                            styleMask:NSWindowStyleMaskBorderless
                                              backing:NSBackingStoreBuffered
                                                defer:NO];

    panel.title = @"Wallify";

    panel.opaque = NO;

    panel.backgroundColor = NSColor.clearColor;

    panel.hasShadow = NO;

    panel.hidesOnDeactivate = NO;

    panel.releasedWhenClosed = NO;

    /*
     * Keep Wallify attached to the desktop.
     */
    panel.level = NSNormalWindowLevel - 1;

    panel.collectionBehavior =
        NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary;

    WallifyView* view = [[WallifyView alloc] initWithFrame:bounds];

    globalMetalView = view;

    surface = [CAMetalLayer layer];

    surface.device = device;

    surface.pixelFormat = MTLPixelFormatBGRA8Unorm;

    surface.framebufferOnly = YES;

    surface.presentsWithTransaction = YES;

    surface.opaque = NO;

    surface.contentsScale = NSScreen.mainScreen.backingScaleFactor;

    view.wantsLayer = YES;

    view.layer = surface;

    NSView* container = [[NSView alloc] initWithFrame:bounds];

    container.wantsLayer = YES;

    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    [container addSubview:view];

    panel.contentView = container;

    movePanel(left, top);

    [panel makeKeyAndOrderFront:nil];

    statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];

    statusItem.button.title = @"\u266b";

    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"Wallify"];

    WallifyAppDelegate* delegate = [[WallifyAppDelegate alloc] init];

    [NSApp setDelegate:delegate];

    NSMenuItem* header = [[NSMenuItem alloc] initWithTitle:@"Wallify" action:nil keyEquivalent:@""];

    [header setEnabled:NO];

    [menu addItem:header];

    NSMenuItem* settings = [[NSMenuItem alloc] initWithTitle:@"Settings…"
                                                      action:@selector(statusOpenSettings:)
                                               keyEquivalent:@","];

    settings.target = [WallifyStatusMenuTarget sharedTarget];

    [menu addItem:settings];
    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* spotify = [[NSMenuItem alloc] initWithTitle:@"Open Spotify"
                                                     action:@selector(statusOpenSpotify:)
                                              keyEquivalent:@""];

    spotify.target = [WallifyStatusMenuTarget sharedTarget];

    [menu addItem:spotify];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* quit = [[NSMenuItem alloc] initWithTitle:@"Quit Wallify"
                                                  action:@selector(terminate:)
                                           keyEquivalent:@"q"];

    quit.target = NSApp;

    [menu addItem:quit];

    statusItem.menu = menu;

    return true;
}

/*
 * At most one pending scene and two submitted GPU frames.
 */
static void presentLatest(void) {
    @autoreleasepool {

        [frameLock lock];

        if (!scheduled || dispatch_semaphore_wait(inFlight, DISPATCH_TIME_NOW) != 0) {

            [frameLock unlock];
            return;
        }

        DrawCommand commands[WALLIFY_MAX_COMMANDS];

        size_t count = latestCount;

        if (count == 0) {
            scheduled = NO;

            [frameLock unlock];

            dispatch_semaphore_signal(inFlight);

            return;
        }

        memcpy(commands, latestCommands, count * sizeof(DrawCommand));

        simd_float2 size = latestSize;

        id<MTLTexture> textures[WALLIFY_MAX_TEXTURES];

        for (size_t i = 0; i < WALLIFY_MAX_TEXTURES; i++) {
            textures[i] = latestTextures[i];
        }

        scheduled = NO;

        [frameLock unlock];

        id<MTLTexture> defaultTex = textures[0];

        if (!defaultTex) {
            [frameLock lock];

            defaultTex = loadedTextures[0];

            [frameLock unlock];
        }

        for (size_t i = 0; i < WALLIFY_MAX_TEXTURES; i++) {
            if (!textures[i]) {
                textures[i] = defaultTex;
            }
        }

        surface.drawableSize =
            CGSizeMake(size.x * surface.contentsScale, size.y * surface.contentsScale);

        id<CAMetalDrawable> drawable = [surface nextDrawable];

        if (!drawable) {
            dispatch_semaphore_signal(inFlight);

            return;
        }

        id<MTLCommandBuffer> command = [queue commandBuffer];

        command.label = @"Wallify scene";

        MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];

        pass.colorAttachments[0].texture = drawable.texture;

        pass.colorAttachments[0].loadAction = MTLLoadActionClear;

        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);

        pass.colorAttachments[0].storeAction = MTLStoreActionStore;

        id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];

        [encoder setRenderPipelineState:pipelineState];

        [encoder setVertexBytes:commands length:count * sizeof(DrawCommand) atIndex:0];

        [encoder setVertexBytes:&size length:sizeof(size) atIndex:1];

        [encoder setFragmentBytes:commands length:count * sizeof(DrawCommand) atIndex:0];

        [encoder setFragmentTextures:textures withRange:NSMakeRange(0, WALLIFY_MAX_TEXTURES)];

        [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                    vertexStart:0
                    vertexCount:4
                  instanceCount:count];

        [encoder endEncoding];

        if (profiling) {
            atomic_fetch_add(&drawCalls, 1);
        }

        [command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
          if (completed.status == MTLCommandBufferStatusError) {
              NSLog(@"Wallify GPU error: %@", completed.error);
          }

          if (profiling) {
              atomic_fetch_add(&renderedFrames, 1);

              atomic_fetch_add(
                  &gpuNanos,
                  (unsigned long)(fmax(0, completed.GPUEndTime - completed.GPUStartTime) * 1e9));
          }

          dispatch_semaphore_signal(inFlight);

          dispatch_async(dispatch_get_main_queue(), ^{
            presentLatest();
          });
        }];

        [command commit];

        [command waitUntilScheduled];

        /*
         * Resize atomically with drawable presentation so an old frame
         * is not stretched while the native window changes size.
         */
        [CATransaction begin];

        [CATransaction setDisableActions:YES];

        NSRect frame = panel.frame;

        if (frame.size.width != size.x || frame.size.height != size.y) {
            CGFloat top = NSMaxY(frame);

            frame.size = NSMakeSize(size.x, size.y);

            frame.origin.y = top - frame.size.height;

            [panel setFrame:frame display:NO];
        }

        [drawable present];

        [CATransaction commit];
    }
}

void wallify_swap_textures(int src, int dest) {
    if (src < 0 || src >= WALLIFY_MAX_TEXTURES || dest < 0 || dest >= WALLIFY_MAX_TEXTURES) {
        return;
    }

    [frameLock lock];

    id<MTLTexture> tmp = loadedTextures[dest];

    loadedTextures[dest] = loadedTextures[src];

    loadedTextures[src] = tmp;

    [frameLock unlock];
}

void wallify_load_texture(int textureID, const unsigned int* pixels, size_t width, size_t height) {
    if (textureID < 0 || textureID >= WALLIFY_MAX_TEXTURES || !width || !height) {
        return;
    }

    @autoreleasepool {

        MTLTextureDescriptor* desc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                               width:width
                                                              height:height
                                                           mipmapped:NO];

        desc.storageMode = MTLStorageModeShared;

        desc.usage = MTLTextureUsageShaderRead;

        id<MTLTexture> texture = [device newTextureWithDescriptor:desc];

        if (!texture) {
            return;
        }

        [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
                   mipmapLevel:0
                     withBytes:pixels
                   bytesPerRow:width * 4];

        [frameLock lock];

        loadedTextures[textureID] = texture;

        if (profiling) {
            atomic_fetch_add(&uploadedBytes, width * height * 4);
        }

        [frameLock unlock];
    }
}

float wallify_glow_extent(float artSize) {
    return ceilf(artSize * fmaxf(WALLIFY_GLOW_SCALE_X, WALLIFY_GLOW_SCALE_Y) +
                 6 * WALLIFY_GLOW_BLUR);
}

void wallify_blur_texture(int source, int destination, float artSize) {
    if (source < 0 || source >= WALLIFY_MAX_TEXTURES || destination < 0 ||
        destination >= WALLIFY_MAX_TEXTURES) {
        return;
    }

    @autoreleasepool {

        [frameLock lock];

        id<MTLTexture> input = loadedTextures[source];

        [frameLock unlock];

        if (!input) {
            return;
        }

        NSUInteger extent = (NSUInteger)wallify_glow_extent(artSize);

        MTLTextureDescriptor* desc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                               width:extent
                                                              height:extent
                                                           mipmapped:NO];

        desc.usage =
            MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;

        desc.storageMode = MTLStorageModePrivate;

        id<MTLTexture> padded = [device newTextureWithDescriptor:desc];

        id<MTLTexture> output = [device newTextureWithDescriptor:desc];

        if (!padded || !output) {
            return;
        }

        id<MTLCommandBuffer> command = [queue commandBuffer];

        command.label = @"Artwork glow bake";

        MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];

        pass.colorAttachments[0].texture = padded;

        pass.colorAttachments[0].loadAction = MTLLoadActionClear;

        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);

        pass.colorAttachments[0].storeAction = MTLStoreActionStore;

        DrawCommand c = {0};

        c.kind = WALLIFY_GLOW_SOURCE;

        c.dw = artSize * WALLIFY_GLOW_SCALE_X;

        c.dh = artSize * WALLIFY_GLOW_SCALE_Y;

        c.dx = (extent - c.dw) * 0.5;

        c.dy = (extent - c.dh) * 0.5;

        c.sw = 1;

        c.sh = 1;

        c.r = 1;

        c.g = 1;

        c.b = 1;

        c.alpha = 1;

        c.radius = artSize * 0.1;

        simd_float2 size = {extent, extent};

        id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];

        [encoder setRenderPipelineState:pipelineState];

        [encoder setVertexBytes:&c length:sizeof(c) atIndex:0];

        [encoder setVertexBytes:&size length:sizeof(size) atIndex:1];

        [encoder setFragmentBytes:&c length:sizeof(c) atIndex:0];

        id<MTLTexture> blurTextures[WALLIFY_MAX_TEXTURES];

        for (size_t i = 0; i < WALLIFY_MAX_TEXTURES; i++) {
            blurTextures[i] = input;
        }

        [encoder setFragmentTextures:blurTextures withRange:NSMakeRange(0, WALLIFY_MAX_TEXTURES)];

        [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                    vertexStart:0
                    vertexCount:4
                  instanceCount:1];

        [encoder endEncoding];

        MPSImageGaussianBlur* blur =
            [[MPSImageGaussianBlur alloc] initWithDevice:device sigma:WALLIFY_GLOW_BLUR];

        blur.edgeMode = MPSImageEdgeModeZero;

        [blur encodeToCommandBuffer:command sourceTexture:padded destinationTexture:output];

        [command commit];

        [frameLock lock];

        loadedTextures[destination] = output;

        [frameLock unlock];
    }
}

void wallify_present(float width, float height, const DrawCommand* commands, size_t count) {
    if (count > WALLIFY_MAX_COMMANDS || width <= 0 || height <= 0) {
        return;
    }

    [frameLock lock];

    memcpy(latestCommands, commands, count * sizeof(DrawCommand));

    latestCount = count;

    latestSize = (simd_float2){width, height};

    for (size_t i = 0; i < WALLIFY_MAX_TEXTURES; i++) {
        latestTextures[i] = loadedTextures[i];
    }

    BOOL enqueue = !scheduled;

    scheduled = YES;

    [frameLock unlock];

    if (enqueue) {
        dispatch_async(dispatch_get_main_queue(), ^{
          presentLatest();
        });
    }
}

void wallify_resize(int width, int height) {
    atomic_store(&surfaceWidth, width);

    atomic_store(&surfaceHeight, height);
}

void wallify_move(int left, int top) {
    dispatch_async(dispatch_get_main_queue(), ^{
      movePanel(left, top);
    });
}

int wallify_width(void) { return atomic_load(&surfaceWidth); }

int wallify_height(void) { return atomic_load(&surfaceHeight); }

static NSString* settingsPath;

void wallify_prepare(void) {
    @autoreleasepool {
        NSLog(@"Wallify: preparing native platform");

        NSBundle* bundle = NSBundle.mainBundle;

        if ([bundle.bundlePath.pathExtension isEqualToString:@"app"]) {
            NSFileManager* fm = [NSFileManager defaultManager];

            NSString* home = NSHomeDirectory();
            NSString* xdgDir = [home stringByAppendingPathComponent:@".config/Wallify"];
            NSString* xdgPath = [xdgDir stringByAppendingPathComponent:@"widget-settings.conf"];
            NSString* support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                                     NSUserDomainMask, YES)
                                     .firstObject stringByAppendingPathComponent:@"Wallify"];

            NSString* supportPath =
                [support stringByAppendingPathComponent:@"widget-settings.conf"];

            if ([fm fileExistsAtPath:xdgPath]) {
                [fm createDirectoryAtPath:support
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:nil];

                settingsPath = xdgPath;

            } else {

                [fm createDirectoryAtPath:support
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:nil];

                if (![fm fileExistsAtPath:supportPath]) {
                    [fm copyItemAtPath:[bundle.resourcePath
                                           stringByAppendingPathComponent:@"widget-settings.conf"]
                                toPath:supportPath
                                 error:nil];
                }

                settingsPath = supportPath;
            }

            [[NSFileManager defaultManager] changeCurrentDirectoryPath:bundle.resourcePath];

        } else {

            settingsPath = @"widget-settings.conf";
        }
    }
}

const char* wallify_settings_path(void) {
    return (settingsPath ?: @"widget-settings.conf").fileSystemRepresentation;
}

NSInteger wallify_panel_window_number(void) { return panel ? [panel windowNumber] : 0; }

bool wallify_panel_offsets(double* out_x, double* out_y) {
    if (!panel) {
        return false;
    }

    NSScreen* primary = NSScreen.screens.firstObject ?: NSScreen.mainScreen;

    NSScreen* screen = panel.screen ?: (NSScreen.mainScreen ?: primary);

    if (!screen || !primary) {
        return false;
    }

    NSRect visible = screen.visibleFrame;

    NSRect primFrame = primary.frame;

    double primTop = primFrame.origin.y + primFrame.size.height;

    double screenVisibleTop = visible.origin.y + visible.size.height;

    if (out_x) {
        *out_x = visible.origin.x;
    }

    if (out_y) {
        *out_y = primTop - screenVisibleTop;
    }

    return true;
}

#import "settings_window.m"

void wallify_update_glass_rect(double x, double y, double w, double h, double radius, float tint_r,
                               float tint_g, float tint_b, bool active) {
    // Artwork colors belong to the controls, not the desktop glass material.
    (void)tint_r;
    (void)tint_g;
    (void)tint_b;

    // The renderer can call this once per scene. Avoid queueing identical AppKit work
    // on the main thread when the glass geometry/material has not changed.
    if (lastGlassUpdateValid &&
        lastGlassActive == active &&
        lastGlassX == x && lastGlassY == y &&
        lastGlassW == w && lastGlassH == h &&
        lastGlassRadius == radius) {
        return;
    }

    lastGlassUpdateValid = YES;
    lastGlassActive = active;
    lastGlassX = x;
    lastGlassY = y;
    lastGlassW = w;
    lastGlassH = h;
    lastGlassRadius = radius;

    dispatch_async(dispatch_get_main_queue(), ^{
      if (!panel || !globalMetalView)
          return;
      NSView* container = panel.contentView;
      if (!container)
          return;

      [CATransaction begin];
      [CATransaction setDisableActions:YES];
      if (@available(macOS 26.0, *)) {
          if (active) {
              if (!globalGlassView) {
                  globalGlassView = [[WallifyDesktopGlassView alloc] initWithFrame:NSZeroRect];
                  globalGlassView.style = NSGlassEffectViewStyleRegular;

                  // On this runtime style=4 resets to style=0 / _variant=0.
                  // Select the private variant explicitly, leaving its optical
                  // filters and rim under AppKit's control.
                  SEL widgetVariant = NSSelectorFromString(@"set_variant:");
                  if ([globalGlassView respondsToSelector:widgetVariant]) {
                      ((void (*)(id, SEL, NSInteger))objc_msgSend)(globalGlassView, widgetVariant,
                                                                   5);
                  }
                  // Keep the optical material neutral. tintColor changes the
                  // glass highlights as well as its fill; it is not a dimmer.
                  globalGlassView.appearance =
                      [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
                  globalGlassView.tintColor = nil;
                  globalGlassContentView = [[NSView alloc] initWithFrame:NSZeroRect];
                  globalGlassContentView.wantsLayer = YES;
                  // Let the widget material supply its own background shading.
                  globalGlassContentView.layer.backgroundColor = NSColor.clearColor.CGColor;
                  globalGlassContentView.layer.cornerCurve = kCACornerCurveContinuous;
                  globalGlassContentView.layer.masksToBounds = YES;
                  globalGlassContentView.clipsToBounds = YES;
                  globalGlassView.contentView = globalGlassContentView;
                  [container addSubview:globalGlassView];
              }
              globalGlassView.hidden = NO;
              if (globalMetalView.superview != globalGlassContentView) {
                  [globalMetalView removeFromSuperview];
                  globalMetalView.autoresizingMask = NSViewNotSizable;
                  [globalGlassContentView addSubview:globalMetalView];
              }
              double flippedY = atomic_load(&surfaceHeight) - y - h;
              NSRect frame = NSMakeRect(x, flippedY, w, h);
              if (!NSEqualRects(globalGlassView.frame, frame))
                  globalGlassView.frame = frame;
              globalGlassView.cornerRadius = radius;

              globalGlassContentView.frame = globalGlassView.bounds;
              globalGlassContentView.layer.cornerRadius = radius;
              // Metal keeps its full-window coordinates inside the clipped card.
              globalMetalView.frame = NSMakeRect(-x, -flippedY, atomic_load(&surfaceWidth),
                                                 atomic_load(&surfaceHeight));
              [CATransaction commit];
              return;
          }
      }
      globalGlassView.hidden = YES;
      if (globalMetalView.superview != container) {
          [globalMetalView removeFromSuperview];
          globalMetalView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
          [container addSubview:globalMetalView];
      }
      globalMetalView.frame = container.bounds;
      [CATransaction commit];
    });
}

extern void wallify_media_key_event(int keyCode);

static CFMachPortRef mediaKeyTap = NULL;

static CFRunLoopSourceRef mediaKeyTapSource = NULL;

static int mediaKeyTarget = 0;

/*
 * 0 = off
 * 1 = active source
 * 2 = Spotify
 * 3 = Spotifast
 */

static CGEventRef mediaKeyCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event,
                                   void* refcon) {
    (void)proxy;
    (void)refcon;

    /*
     * Re-enable tap after automatic timeout/user-input disable.
     */
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (mediaKeyTap) {
            CGEventTapEnable(mediaKeyTap, true);
        }

        return event;
    }

    NSEvent* nsEvent = [NSEvent eventWithCGEvent:event];

    if (!nsEvent || nsEvent.type != NSEventTypeSystemDefined || nsEvent.subtype != 8) {
        return event;
    }

    int keyCode = (int)((nsEvent.data1 & 0xFFFF0000) >> 16);

    int keyFlags = (int)(nsEvent.data1 & 0x0000FFFF);

    int keyState = (int)((keyFlags & 0xFF00) >> 8);

    /*
     * Only process key-down.
     *
     * Consume key-up as well.
     */
    if (keyState != 0x0A) {
        return NULL;
    }

    if (keyCode == 16 || keyCode == 19 || keyCode == 20) {
        wallify_media_key_event(keyCode);

        return NULL;
    }

    return event;
}

void wallify_update_media_key_tap(int target) {
    dispatch_async(dispatch_get_main_queue(), ^{
      NSLog(@"Wallify: media key target -> %d", target);
      mediaKeyTarget = target;

      if (target == 0) {
          NSLog(@"Wallify: disabling media key interception");

          if (mediaKeyTap) {

              CGEventTapEnable(mediaKeyTap, false);

              if (mediaKeyTapSource) {

                  CFRunLoopRemoveSource(CFRunLoopGetMain(), mediaKeyTapSource,
                                        kCFRunLoopCommonModes);

                  CFRelease(mediaKeyTapSource);

                  mediaKeyTapSource = NULL;
              }

              CFRelease(mediaKeyTap);

              mediaKeyTap = NULL;
          }

          return;
      }

      if (mediaKeyTap) {
          NSLog(@"Wallify: media key tap already installed");
          return;
      }

      /*
       * Session-level event taps require Accessibility.
       */
      if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)
                                             @{@"AXTrustedCheckOptionPrompt" : @YES})) {
          NSLog(@"Wallify: Accessibility permission required for media key interception.");

          return;
      }

      CGEventMask mask = CGEventMaskBit(NSEventTypeSystemDefined);

      mediaKeyTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                                     kCGEventTapOptionDefault, mask, mediaKeyCallback, NULL);

      if (!mediaKeyTap) {
          NSLog(@"Wallify: Failed to create CGEventTap (check Accessibility permission).");

          return;
      }

      mediaKeyTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, mediaKeyTap, 0);

      CFRunLoopAddSource(CFRunLoopGetMain(), mediaKeyTapSource, kCFRunLoopCommonModes);

      CGEventTapEnable(mediaKeyTap, true);

      NSLog(@"Wallify: Media key tap installed (target=%d).", target);
    });
}
