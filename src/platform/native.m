#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/CATransaction.h>
#include <stdatomic.h>
#include <simd/simd.h>
#include <unistd.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#include "gpu.h"
#import "settings_window.h"

extern void wallify_pointer(double, double, int);
static NSPanel *panel;
static NSStatusItem *statusItem;
static id<MTLDevice> device;
static id<MTLCommandQueue> queue;
static id<MTLRenderPipelineState> pipelineState;
static CAMetalLayer *surface;
static atomic_int surfaceWidth, surfaceHeight;
static NSLock *frameLock;
static BOOL scheduled;
static DrawCommand latestCommands[WALLIFY_MAX_COMMANDS];
static size_t latestCount;
static simd_float2 latestSize;
static id<MTLTexture> loadedTextures[WALLIFY_MAX_TEXTURES];
static id<MTLTexture> latestTextures[WALLIFY_MAX_TEXTURES];
static dispatch_semaphore_t inFlight;
static BOOL profiling;
static atomic_ulong sceneNanos, gpuNanos, uploadedBytes, sceneFrames, renderedFrames, drawCalls;
void wallify_profile_scene(double seconds) {
    if (!profiling) return;
    atomic_fetch_add(&sceneNanos, (unsigned long)(seconds * 1e9));
    unsigned long frames = atomic_fetch_add(&sceneFrames, 1) + 1;
    if (frames % 300 == 0) {
        unsigned long rendered = atomic_load(&renderedFrames);
        fprintf(stderr, "Wallify profile: frames=%lu scene_cpu_ms=%.3f gpu_ms=%.3f commands_per_frame=%.1f asset_upload_bytes=%lu full_frame_upload_bytes=0\n", frames,
            atomic_load(&sceneNanos) / (double)frames / 1e6,
            rendered ? atomic_load(&gpuNanos) / (double)rendered / 1e6 : 0,
            rendered ? atomic_load(&drawCalls) / (double)rendered : 0,
            atomic_load(&uploadedBytes));
    }
}

@interface WallifyView : NSView
@end
@implementation WallifyView
- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)point { return self; }
- (BOOL)acceptsFirstResponder { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
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

@interface WallifyStatusMenuTarget : NSObject
+ (instancetype)sharedTarget;
- (void)statusOpenSettings:(id)sender;
- (void)statusOpenSpotify:(id)sender;
@end

@interface WallifyAppDelegate : NSObject <NSApplicationDelegate>
@end
@implementation WallifyAppDelegate
- (void)applicationWillTerminate:(NSNotification *)notification {
    unlink("/tmp/art.raw");
    unlink("/tmp/art.bmp");
    unlink("/tmp/art-next.bmp");
    unlink("/tmp/mrc_artwork");
    unlink("/tmp/mrc_artwork_tmp");
}
@end

@implementation WallifyStatusMenuTarget
+ (instancetype)sharedTarget {
    static WallifyStatusMenuTarget *target = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [[WallifyStatusMenuTarget alloc] init];
    });
    return target;
}
- (void)statusOpenSettings:(id)sender {
    wallify_show_settings_window();
}
- (void)statusOpenSpotify:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"spotify:"]];
}
@end

static void movePanel(int left, int top) {
    NSRect screen = (panel.screen ?: NSScreen.mainScreen).visibleFrame;
    [panel setFrameOrigin:NSMakePoint(screen.origin.x + left, NSMaxY(screen) - top - panel.frame.size.height)];
}

static NSGlassEffectView *globalGlassView = nil;
static NSView *globalGlassContentView = nil;
static WallifyView *globalMetalView = nil;

bool wallify_create(int width, int height, int left, int top) {
    profiling = getenv("WALLIFY_PROFILE") != NULL;
    device = MTLCreateSystemDefaultDevice();
    queue = [device newCommandQueue];
    
    NSError *error = nil;
    id<MTLLibrary> defaultLibrary = nil;
    NSURL *libraryURL = [[NSBundle mainBundle] URLForResource:@"default" withExtension:@"metallib"];
    if (libraryURL) {
        defaultLibrary = [device newLibraryWithURL:libraryURL error:&error];
    } else {
        // Fallback for running purely from zig-out/bin/wallify during tests
        NSString *execPath = [[NSBundle mainBundle] executablePath];
        NSString *execDir = [execPath stringByDeletingLastPathComponent];
        NSURL *fallbackURL = [NSURL fileURLWithPath:[execDir stringByAppendingPathComponent:@"default.metallib"]];
        defaultLibrary = [device newLibraryWithURL:fallbackURL error:&error];
    }
    
    if (!defaultLibrary) {
        NSLog(@"Failed to compile Metal shaders: %@", error);
    }
    
    if (defaultLibrary) {
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Wallify GPU compositor";
        pipelineStateDescriptor.vertexFunction = [defaultLibrary newFunctionWithName:@"vertex_main"];
        pipelineStateDescriptor.fragmentFunction = [defaultLibrary newFunctionWithName:@"fragment_main"];
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        pipelineStateDescriptor.colorAttachments[0].blendingEnabled = YES;
        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        
        pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
        if (!pipelineState) NSLog(@"Failed to created pipeline state, error %@", error);
    }

    if (!device || !queue || !pipelineState) return false;
    inFlight = dispatch_semaphore_create(2);
    frameLock = [NSLock new];
    atomic_store(&surfaceWidth, width);
    atomic_store(&surfaceHeight, height);
    NSRect bounds = NSMakeRect(0, 0, atomic_load(&surfaceWidth), atomic_load(&surfaceHeight));
    panel = [[WallifyPanel alloc] initWithContentRect:bounds styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    panel.title = @"Wallify";
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = NO;
    panel.hidesOnDeactivate = NO;
    panel.releasedWhenClosed = NO;
    // Push the window behind normal apps but above the wallpaper.
    // Joining all spaces + stationary makes it stick to the desktop like a native widget,
    // ignoring Mission Control swipes and the Alt-Tab switcher.
    panel.level = NSNormalWindowLevel - 1;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary;
    WallifyView *view = [[WallifyView alloc] initWithFrame:bounds];
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
    
    NSView *container = [[NSView alloc] initWithFrame:bounds];
    container.wantsLayer = YES;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [container addSubview:view];
    panel.contentView = container;
    movePanel(left, top);
    [panel orderFrontRegardless];

    statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    statusItem.button.title = @"\u266b";
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Wallify"];

    WallifyAppDelegate *delegate = [[WallifyAppDelegate alloc] init];
    [NSApp setDelegate:delegate];

    NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"Wallify" action:nil keyEquivalent:@""];
    [header setEnabled:NO];
    [menu addItem:header];

    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Settings…" action:@selector(statusOpenSettings:) keyEquivalent:@","];
    settings.target = [WallifyStatusMenuTarget sharedTarget];
    [menu addItem:settings];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *spotify = [[NSMenuItem alloc] initWithTitle:@"Open Spotify" action:@selector(statusOpenSpotify:) keyEquivalent:@""];
    spotify.target = [WallifyStatusMenuTarget sharedTarget];
    [menu addItem:spotify];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Wallify" action:@selector(terminate:) keyEquivalent:@"q"];
    quit.target = NSApp;
    [menu addItem:quit];
    statusItem.menu = menu;
    return true;
}

// At most one pending scene and two submitted GPU frames. Texture references
// are snapshotted with each scene, so cache eviction cannot change queued draws.
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
        for (size_t i = 0; i < WALLIFY_MAX_TEXTURES; i++) textures[i] = latestTextures[i];
        scheduled = NO;
        [frameLock unlock];

        // Ensure all texture bindings in the array are populated with valid textures (fallback to textures[0])
        id<MTLTexture> defaultTex = textures[0];
        if (!defaultTex) {
            [frameLock lock];
            defaultTex = loadedTextures[0];
            [frameLock unlock];
        }
        for (size_t i = 0; i < WALLIFY_MAX_TEXTURES; i++) {
            if (!textures[i]) textures[i] = defaultTex;
        }

        surface.drawableSize = CGSizeMake(size.x * surface.contentsScale, size.y * surface.contentsScale);
        id<CAMetalDrawable> drawable = [surface nextDrawable];
        if (!drawable) { dispatch_semaphore_signal(inFlight); return; }
        id<MTLCommandBuffer> command = [queue commandBuffer];
        command.label = @"Wallify scene";
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
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
        [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4 instanceCount:count];
        [encoder endEncoding];

        if (profiling) atomic_fetch_add(&drawCalls, 1);
        [command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
            if (completed.status == MTLCommandBufferStatusError) NSLog(@"Wallify GPU error: %@", completed.error);
            if (profiling) {
                atomic_fetch_add(&renderedFrames, 1);
                atomic_fetch_add(&gpuNanos, (unsigned long)(fmax(0, completed.GPUEndTime - completed.GPUStartTime) * 1e9));
            }
            dispatch_semaphore_signal(inFlight);
            dispatch_async(dispatch_get_main_queue(), ^{ presentLatest(); });
        }];
        [command commit];
        [command waitUntilScheduled];

        // Disable implicit animations and commit the window geometry and drawable together.
        // If we don't do this, CoreAnimation will stretch the old frame's pixels while resizing,
        // causing a nasty visual flash.
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
    if (src < 0 || src >= WALLIFY_MAX_TEXTURES || dest < 0 || dest >= WALLIFY_MAX_TEXTURES) return;
    [frameLock lock];
    id<MTLTexture> tmp = loadedTextures[dest];
    loadedTextures[dest] = loadedTextures[src];
    loadedTextures[src] = tmp;
    [frameLock unlock];
}

// Assets are uploaded only when they change; no full-frame texture exists.
void wallify_load_texture(int textureID, const unsigned int *pixels, size_t width, size_t height) {
    if (textureID < 0 || textureID >= WALLIFY_MAX_TEXTURES || !width || !height) return;
    @autoreleasepool {
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
        desc.storageMode = MTLStorageModeShared;
        desc.usage = MTLTextureUsageShaderRead;
        id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
        if (!texture) return;
        [texture replaceRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0 withBytes:pixels bytesPerRow:width * 4];
        [frameLock lock];
        loadedTextures[textureID] = texture;
        if (profiling) atomic_fetch_add(&uploadedBytes, width * height * 4);
        [frameLock unlock];
    }
}

// Pad the artwork with transparent pixels before blurring.
// If we blur the raw image directly, the hard edges smear strong colors everywhere.
// Padding it first gives us a nice, soft falloff. Handled on the GPU via MPS.
float wallify_glow_extent(float artSize) {
    return ceilf(artSize * fmaxf(WALLIFY_GLOW_SCALE_X, WALLIFY_GLOW_SCALE_Y) + 6 * WALLIFY_GLOW_BLUR);
}

void wallify_blur_texture(int source, int destination, float artSize) {
    if (source < 0 || source >= WALLIFY_MAX_TEXTURES || destination < 0 || destination >= WALLIFY_MAX_TEXTURES) return;
    @autoreleasepool {
        [frameLock lock];
        id<MTLTexture> input = loadedTextures[source];
        [frameLock unlock];
        if (!input) return;
        NSUInteger extent = (NSUInteger)wallify_glow_extent(artSize);
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:extent height:extent mipmapped:NO];
        desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;
        desc.storageMode = MTLStorageModePrivate;
        id<MTLTexture> padded = [device newTextureWithDescriptor:desc];
        id<MTLTexture> output = [device newTextureWithDescriptor:desc];
        if (!padded || !output) return;
        id<MTLCommandBuffer> command = [queue commandBuffer];
        command.label = @"Artwork glow bake";
        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = padded;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0);
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        DrawCommand c = {0};
        c.kind = WALLIFY_GLOW_SOURCE;
        c.dw = artSize * WALLIFY_GLOW_SCALE_X;
        c.dh = artSize * WALLIFY_GLOW_SCALE_Y;
        c.dx = (extent - c.dw) * .5;
        c.dy = (extent - c.dh) * .5;
        c.sw = c.sh = c.r = c.g = c.b = c.alpha = 1;
        c.radius = artSize * .1;
        simd_float2 size = {extent, extent};
        id<MTLRenderCommandEncoder> encoder = [command renderCommandEncoderWithDescriptor:pass];
        [encoder setRenderPipelineState:pipelineState];
        [encoder setVertexBytes:&c length:sizeof(c) atIndex:0];
        [encoder setVertexBytes:&size length:sizeof(size) atIndex:1];
        [encoder setFragmentBytes:&c length:sizeof(c) atIndex:0];
        id<MTLTexture> blurTextures[WALLIFY_MAX_TEXTURES];
        for (size_t i = 0; i < WALLIFY_MAX_TEXTURES; i++) blurTextures[i] = input;
        [encoder setFragmentTextures:blurTextures withRange:NSMakeRange(0, WALLIFY_MAX_TEXTURES)];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4 instanceCount:1];
        [encoder endEncoding];
        MPSImageGaussianBlur *blur = [[MPSImageGaussianBlur alloc] initWithDevice:device sigma:WALLIFY_GLOW_BLUR];
        blur.edgeMode = MPSImageEdgeModeZero;
        [blur encodeToCommandBuffer:command sourceTexture:padded destinationTexture:output];
        [command commit];
        [frameLock lock];
        loadedTextures[destination] = output;
        [frameLock unlock];
    }
}

void wallify_present(float width, float height, const DrawCommand *commands, size_t count) {
    if (count > WALLIFY_MAX_COMMANDS || width <= 0 || height <= 0) return;
    [frameLock lock];
    memcpy(latestCommands, commands, count * sizeof(DrawCommand));
    latestCount = count;
    latestSize = (simd_float2){width, height};
    for (size_t i = 0; i < WALLIFY_MAX_TEXTURES; i++) latestTextures[i] = loadedTextures[i];
    BOOL enqueue = !scheduled;
    scheduled = YES;
    [frameLock unlock];
    if (enqueue) dispatch_async(dispatch_get_main_queue(), ^{ presentLatest(); });
}

void wallify_resize(int width, int height) {
    // Publish the requested scene size immediately; presentLatest applies the
    // native resize only once a frame with these dimensions is ready.
    atomic_store(&surfaceWidth, width);
    atomic_store(&surfaceHeight, height);
}
void wallify_move(int left, int top) { dispatch_async(dispatch_get_main_queue(), ^{ movePanel(left, top); }); }
int wallify_width(void) { return atomic_load(&surfaceWidth); }
int wallify_height(void) { return atomic_load(&surfaceHeight); }

static NSString *settingsPath;
void wallify_prepare(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        if ([bundle.bundlePath.pathExtension isEqualToString:@"app"]) {
            NSFileManager *fm = [NSFileManager defaultManager];

            // XDG path: ~/.config/Wallify/widget-settings.conf
            NSString *home = NSHomeDirectory();
            NSString *xdgDir  = [home stringByAppendingPathComponent:@".config/Wallify"];
            NSString *xdgPath = [xdgDir stringByAppendingPathComponent:@"widget-settings.conf"];

            // AppSupport path: ~/Library/Application Support/Wallify/widget-settings.conf
            NSString *support     = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Wallify"];
            NSString *supportPath = [support stringByAppendingPathComponent:@"widget-settings.conf"];

            if ([fm fileExistsAtPath:xdgPath]) {
                // XDG config exists — use it as the canonical path.
                // We still ensure Application Support dir exists so other
                // runtime artifacts (textures, logs) have somewhere to land.
                [fm createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:nil];
                settingsPath = xdgPath;
            } else {
                // Fall back to Application Support, seeding from bundle if fresh install.
                [fm createDirectoryAtPath:support withIntermediateDirectories:YES attributes:nil error:nil];
                if (![fm fileExistsAtPath:supportPath])
                    [fm copyItemAtPath:[bundle.resourcePath stringByAppendingPathComponent:@"widget-settings.conf"] toPath:supportPath error:nil];
                settingsPath = supportPath;
            }

            [[NSFileManager defaultManager] changeCurrentDirectoryPath:bundle.resourcePath];
        } else settingsPath = @"widget-settings.conf";
    }
}
const char *wallify_settings_path(void) { return (settingsPath ?: @"widget-settings.conf").fileSystemRepresentation; }

NSInteger wallify_panel_window_number(void) {
    return panel ? [panel windowNumber] : 0;
}

bool wallify_panel_offsets(double *out_x, double *out_y) {
    if (!panel) return false;
    NSScreen *primary = NSScreen.screens.firstObject ?: NSScreen.mainScreen;
    NSScreen *screen = panel.screen ?: (NSScreen.mainScreen ?: primary);
    if (!screen || !primary) return false;
    NSRect visible = screen.visibleFrame;
    NSRect primFrame = primary.frame;
    double primTop = primFrame.origin.y + primFrame.size.height;
    double screenVisibleTop = visible.origin.y + visible.size.height;
    if (out_x) *out_x = visible.origin.x;
    if (out_y) *out_y = primTop - screenVisibleTop;
    return true;
}

#import "settings_window.m"


void wallify_update_glass_rect(
    double x, double y, double w, double h, double radius,
    float tint_r, float tint_g, float tint_b, bool active
) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!panel || !globalMetalView) return;
        NSView *container = panel.contentView;
        if (!container) return;

        if (@available(macOS 26.0, *)) {
            if (active) {
                if (!globalGlassView) {
                    /*
                     * Real macOS 26 Liquid Glass.
                     *
                     * IMPORTANT:
                     * The Metal view is CONTENT of the glass view.
                     * Do not put NSGlassEffectView behind it as a sibling.
                     */
                    globalGlassView = [[NSGlassEffectView alloc] initWithFrame:NSZeroRect];
                    globalGlassView.style = NSGlassEffectViewStyleRegular;
                    if (@available(macOS 27.0, *)) {
                        globalGlassView.effectIsInteractive = YES;
                    }

                    /*
                     * Wrapper lets us keep Wallify's existing
                     * panel-space Metal coordinates while the actual
                     * glass remains inset from the 180pt widget tile.
                     */
                    globalGlassContentView = [[NSView alloc] initWithFrame:NSZeroRect];
                    globalGlassContentView.clipsToBounds = YES;
                    globalGlassView.contentView = globalGlassContentView;

                    [container addSubview:globalGlassView];

                    /*
                     * Moving the Metal view here makes it actual
                     * glass content instead of a sibling underneath it.
                     */
                    [globalMetalView removeFromSuperview];
                    [globalGlassContentView addSubview:globalMetalView];
                }
                globalGlassView.hidden = NO;

                /*
                 * AppKit uses bottom-left coordinates.
                 * Wallify's renderer uses top-left coordinates.
                 */
                double flippedY = atomic_load(&surfaceHeight) - y - h;
                NSRect glassFrame = NSMakeRect(x, flippedY, w, h);
                globalGlassView.frame = glassFrame;
                globalGlassView.cornerRadius = radius;

                /*
                 * Keep the tint extremely subtle.
                 * The underlying artwork should provide most of the color.
                 */
                globalGlassView.tintColor = [NSColor colorWithSRGBRed:tint_r green:tint_g blue:tint_b alpha:0.055];

                /*
                 * Content view occupies the glass bounds.
                 */
                globalGlassContentView.frame = globalGlassView.bounds;

                /*
                 * Keep Metal in panel coordinates.
                 *
                 * The wrapper clips it to the glass shape, while
                 * the Metal viewport remains the original 180/540pt
                 * panel size. This means we don't have to rewrite
                 * every renderer coordinate.
                 */
                globalMetalView.frame = NSMakeRect(
                    -x,
                    -flippedY,
                    atomic_load(&surfaceWidth),
                    atomic_load(&surfaceHeight)
                );

                /*
                 * No hand-drawn CALayer border.
                 * NSGlassEffectView supplies the optical edge,
                 * highlight and depth treatment itself.
                 */
                globalGlassView.wantsLayer = YES;
                globalGlassView.layer.cornerCurve = kCACornerCurveContinuous;

            } else {
                if (globalGlassView) {
                    globalGlassView.hidden = YES;
                }
                /*
                 * Restore Metal to the normal hierarchy when
                 * native glass is disabled.
                 */
                [globalMetalView removeFromSuperview];
                [container addSubview:globalMetalView];
                globalMetalView.frame = container.bounds;
            }
            return;
        }

        /*
         * macOS < 26 fallback.
         *
         * Keep the old renderer-based glass path alive, but don't
         * try to emulate Liquid Glass on systems that don't provide
         * NSGlassEffectView.
         */
        if (globalGlassView) {
            globalGlassView.hidden = YES;
        }
        [globalMetalView removeFromSuperview];
        [container addSubview:globalMetalView];
        globalMetalView.frame = container.bounds;
    });
}

// ─── Hardware Media Key Interception ──────────────────────────────────────────
// macOS routes F7/F8/F9 (and Touch Bar equivalents) as NSSystemDefined events
// with subtype 8 (NX_SUBTYPE_AUX_CONTROL_BUTTONS). Key codes map to:
//   NX_KEYTYPE_PLAY  = 16  (F8 / play-pause)
//   NX_KEYTYPE_FAST  = 19  (F9 / next track)
//   NX_KEYTYPE_REWIND = 20 (F7 / previous track)
//
// By installing a CGEventTap at kCGSessionEventTap we intercept these before
// they reach the system media remote daemon (rpcd), which would otherwise wake
// Apple Music. We consume the event and dispatch to Wallify's own pipeline.

extern void wallify_media_key_event(int keyCode); // exported from Zig

static CFMachPortRef mediaKeyTap = NULL;
static CFRunLoopSourceRef mediaKeyTapSource = NULL;
static int mediaKeyTarget = 0; // 0=off, 1=active, 2=spotify, 3=spotifast

static CGEventRef mediaKeyCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
    // Re-enable the tap if it was auto-disabled after a timeout
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        CGEventTapEnable(mediaKeyTap, true);
        return event;
    }

    NSEvent *nsEvent = [NSEvent eventWithCGEvent:event];
    if (!nsEvent || nsEvent.type != NSEventTypeSystemDefined || nsEvent.subtype != 8) return event;

    // Decode the key from the data1 field — same format as IOKit NXEventData
    int keyCode  = (int)((nsEvent.data1 & 0xFFFF0000) >> 16);
    int keyFlags = (int)(nsEvent.data1 & 0x0000FFFF);
    int keyState = (int)((keyFlags & 0xFF00) >> 8); // 0x0A = down, 0x0B = up

    // Only act on key-down, not key-up (to avoid double-fire)
    if (keyState != 0x0A) return NULL; // consume both, act only on down

    if (keyCode == 16 || keyCode == 19 || keyCode == 20) {
        // Dispatch to Zig — it knows the active source and routes accordingly
        wallify_media_key_event(keyCode);
        return NULL; // consume — prevent Apple Music from being woken
    }
    return event;
}

void wallify_update_media_key_tap(int target) {
    dispatch_async(dispatch_get_main_queue(), ^{
        mediaKeyTarget = target;

        if (target == 0) {
            // Remove the tap entirely
            if (mediaKeyTap) {
                CGEventTapEnable(mediaKeyTap, false);
                CFRunLoopRemoveSource(CFRunLoopGetMain(), mediaKeyTapSource, kCFRunLoopCommonModes);
                CFRelease(mediaKeyTapSource);
                CFRelease(mediaKeyTap);
                mediaKeyTapSource = NULL;
                mediaKeyTap = NULL;
            }
            return;
        }

        // Already installed — just update target, no need to reinstall
        if (mediaKeyTap) return;

        // Check for Accessibility permission — required for a session-level tap
        if (!AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{
            @"AXTrustedCheckOptionPrompt": @YES
        })) {
            NSLog(@"Wallify: Accessibility permission required for media key interception.");
            return;
        }

        CGEventMask mask = CGEventMaskBit(NSEventTypeSystemDefined);
        mediaKeyTap = CGEventTapCreate(
            kCGSessionEventTap,
            kCGHeadInsertEventTap,
            kCGEventTapOptionDefault,
            mask,
            mediaKeyCallback,
            NULL
        );

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
