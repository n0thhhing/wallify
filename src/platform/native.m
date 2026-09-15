#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <stdatomic.h>
#include <simd/simd.h>
#import <MetalPerformanceShaders/MetalPerformanceShaders.h>
#include "gpu.h"

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
    panel.level = NSNormalWindowLevel - 1;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary;
    WallifyView *view = [[WallifyView alloc] initWithFrame:bounds];
    surface = [CAMetalLayer layer];
    surface.device = device;
    surface.pixelFormat = MTLPixelFormatBGRA8Unorm;
    surface.framebufferOnly = YES;
    surface.opaque = NO;
    surface.contentsScale = NSScreen.mainScreen.backingScaleFactor;
    view.wantsLayer = YES;
    view.layer = surface;
    panel.contentView = view;
    movePanel(left, top);
    [panel orderFrontRegardless];
    statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    statusItem.button.title = @"\u266b";
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Wallify"];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Wallify" action:@selector(terminate:) keyEquivalent:@""];
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
        [command presentDrawable:drawable];
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

// Bake transformed artwork into transparent padding before blurring. This
// keeps the glow localized to the cover instead of smearing opaque edge colors
// across the player. All work happens once per artwork update on the GPU.
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
    dispatch_async(dispatch_get_main_queue(), ^{
        NSRect frame = panel.frame;
        CGFloat top = NSMaxY(frame);
        frame.size = NSMakeSize(width, height);
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
