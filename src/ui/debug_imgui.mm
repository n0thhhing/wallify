#include "imgui.h"
#include "imgui_internal.h"
#include "backends/imgui_impl_metal.h"
#include "backends/imgui_impl_osx.h"

#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#include <stdarg.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>

extern "C" {

struct WallifyDebugSnapshot {
    int32_t glow, aurora, animations, dim, native_glass;
    int32_t hide_text, hide_progress, show_controls, timestamps;
    int32_t artwork_border, compact_gradient;
    int32_t frame, intensity, speed, source, mode, transition;
    int32_t font_scale, media_key_target, artwork_radius, progress_thickness;
    int32_t width, height, margin_left, margin_top, dragging;
    int64_t window_number, window_layer;
    double window_x, window_y, window_width, window_height;
    double outline_x, outline_y, outline_width, outline_height;
    uint32_t candidate_count;
    double snap_distance_sq;
    float mode_mix;
    uint32_t title_len, artist_len;
    char title[256], artist[256];
};

void wallify_debug_get_snapshot(WallifyDebugSnapshot* out);
void wallify_debug_set_bool(int32_t key, int32_t value);
void wallify_debug_set_int(int32_t key, int32_t value);

}

static NSPanel* gInspectorPanel = nil;
static MTKView* gInspectorView = nil;
static id<MTLCommandQueue> gInspectorQueue = nil;
static bool gInspectorInitialized = false;
static bool gInspectorVisible = false;
static bool gDockLayoutBuilt = false;

static void setInspectorFrame(NSPanel* panel) {
    NSScreen* screen = NSScreen.mainScreen;
    if (!screen) return;
    NSRect visible = screen.visibleFrame;
    const CGFloat width = 1040.0;
    const CGFloat height = 720.0;
    [panel setFrame:NSMakeRect(
        visible.origin.x + (visible.size.width - width) * 0.5,
        visible.origin.y + (visible.size.height - height) * 0.5,
        width, height) display:NO];
}

static void setupStyle() {
    ImGuiStyle& style = ImGui::GetStyle();
    ImGui::StyleColorsDark();
    style.WindowRounding = 8.0f;
    style.ChildRounding = 7.0f;
    style.FrameRounding = 5.0f;
    style.PopupRounding = 6.0f;
    style.ScrollbarRounding = 6.0f;
    style.GrabRounding = 5.0f;
    style.TabRounding = 5.0f;
    style.WindowBorderSize = 1.0f;
    style.ChildBorderSize = 1.0f;
    style.FramePadding = ImVec2(8.0f, 5.0f);
    style.WindowPadding = ImVec2(12.0f, 12.0f);
    style.ItemSpacing = ImVec2(8.0f, 7.0f);

    ImVec4* c = style.Colors;
    c[ImGuiCol_WindowBg] = ImVec4(0.075f, 0.078f, 0.09f, 0.98f);
    c[ImGuiCol_ChildBg] = ImVec4(0.06f, 0.063f, 0.074f, 0.96f);
    c[ImGuiCol_PopupBg] = ImVec4(0.08f, 0.082f, 0.095f, 0.99f);
    c[ImGuiCol_FrameBg] = ImVec4(0.13f, 0.135f, 0.155f, 1.0f);
    c[ImGuiCol_FrameBgHovered] = ImVec4(0.18f, 0.185f, 0.21f, 1.0f);
    c[ImGuiCol_FrameBgActive] = ImVec4(0.22f, 0.225f, 0.25f, 1.0f);
    c[ImGuiCol_Header] = ImVec4(0.15f, 0.155f, 0.18f, 1.0f);
    c[ImGuiCol_HeaderHovered] = ImVec4(0.21f, 0.215f, 0.25f, 1.0f);
    c[ImGuiCol_HeaderActive] = ImVec4(0.24f, 0.25f, 0.29f, 1.0f);
    c[ImGuiCol_Button] = ImVec4(0.145f, 0.15f, 0.175f, 1.0f);
    c[ImGuiCol_ButtonHovered] = ImVec4(0.21f, 0.22f, 0.255f, 1.0f);
    c[ImGuiCol_ButtonActive] = ImVec4(0.24f, 0.25f, 0.29f, 1.0f);
    c[ImGuiCol_Border] = ImVec4(0.24f, 0.25f, 0.29f, 0.55f);
    c[ImGuiCol_Separator] = ImVec4(0.22f, 0.23f, 0.27f, 0.5f);
    c[ImGuiCol_Text] = ImVec4(0.92f, 0.93f, 0.96f, 1.0f);
    c[ImGuiCol_TextDisabled] = ImVec4(0.5f, 0.52f, 0.58f, 1.0f);
}

static void propertyHeader(const char* label) {
    ImGui::TableNextRow();
    ImGui::TableSetColumnIndex(0);
    ImGui::TextDisabled("%s", label);
    ImGui::TableSetColumnIndex(1);
}

static bool beginProperties(const char* id) {
    return ImGui::BeginTable(
        id, 2,
        ImGuiTableFlags_SizingStretchProp |
        ImGuiTableFlags_RowBg |
        ImGuiTableFlags_BordersInnerH |
        ImGuiTableFlags_PadOuterX);
}

static void propertyText(const char* label, const char* value) {
    propertyHeader(label);
    ImGui::TextUnformatted(value ? value : "—");
}

static void propertyBool(const char* label, bool value, int key) {
    propertyHeader(label);
    ImGui::PushID(label);
    bool changed = value;
    if (ImGui::Checkbox("##value", &changed))
        wallify_debug_set_bool(key, changed ? 1 : 0);
    ImGui::PopID();
}

static void propertyInt(const char* label, int value, int key) {
    propertyHeader(label);
    ImGui::PushID(label);
    int changed = value;
    if (ImGui::InputInt("##value", &changed, 1, 10))
        wallify_debug_set_int(key, changed);
    ImGui::PopID();
}

static void propertyReadout(const char* label, const char* fmt, ...) {
    char buffer[256];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    propertyText(label, buffer);
}

static void drawRuntime(const WallifyDebugSnapshot& s) {
    if (beginProperties("runtime")) {
        static const char* modes[] = {"1 × 1", "2 × 1", "3 × 1", "1 × 2", "2 × 2"};
        int mode = s.mode;
        propertyHeader("Form Factor");
        if (ImGui::Combo("##mode", &mode, modes, IM_ARRAYSIZE(modes)))
            wallify_debug_set_int(14, mode);

        float mix = s.mode_mix * 100.0f;
        propertyHeader("Mode Mix");
        if (ImGui::SliderFloat("##mix", &mix, 0.0f, 100.0f, "%.0f%%"))
            wallify_debug_set_int(1000, (int)lroundf(mix));

        propertyInt("Width", s.width, 1001);
        propertyInt("Height", s.height, 1002);
        propertyText("Dragging", s.dragging ? "true" : "false");
        ImGui::EndTable();
    }

    ImGui::SeparatorText("Live State");
    if (beginProperties("runtime_live_state")) {
        propertyReadout("Window", "#%lld", (long long)s.window_number);
        propertyReadout("Layer", "%lld", (long long)s.window_layer);
        propertyReadout("Frame", "%.0f, %.0f  %.0f × %.0f",
                        s.window_x, s.window_y, s.window_width, s.window_height);
        ImGui::EndTable();
    }
}

static void drawAppearance(const WallifyDebugSnapshot& s) {
    if (beginProperties("appearance")) {
        propertyBool("Native Glass", s.native_glass != 0, 5);
        propertyBool("Glow", s.glow != 0, 0);
        propertyBool("Aurora", s.aurora != 0, 1);
        propertyBool("Animations", s.animations != 0, 2);

        static const char* speeds[] = {"Slow", "Normal", "Fast"};
        int speed = s.speed;
        propertyHeader("Animation Speed");
        if (ImGui::Combo("##speed", &speed, speeds, IM_ARRAYSIZE(speeds)))
            wallify_debug_set_int(12, speed);

        propertyBool("Hide Text", s.hide_text != 0, 6);
        propertyBool("Hide Progress", s.hide_progress != 0, 7);
        propertyBool("Show Controls", s.show_controls != 0, 8);
        propertyBool("Timestamps", s.timestamps != 0, 9);
        propertyBool("Artwork Border", s.artwork_border != 0, 19);
        propertyBool("Compact Gradient", s.compact_gradient != 0, 20);
        ImGui::EndTable();
    }
}

static void drawMedia(const WallifyDebugSnapshot& s) {
    if (beginProperties("media")) {
        static const char* sources[] = {"Now Playing", "Spotify", "Spotifast", "Auto"};
        int source = s.source;
        propertyHeader("Media Source");
        if (ImGui::Combo("##source", &source, sources, IM_ARRAYSIZE(sources)))
            wallify_debug_set_int(13, source);

        static const char* transitions[] = {"Default", "Cinematic", "Ripple", "Card Flip", "Vinyl", "Glitch"};
        int transition = s.transition;
        propertyHeader("Transition");
        if (ImGui::Combo("##transition", &transition, transitions, IM_ARRAYSIZE(transitions)))
            wallify_debug_set_int(16, transition);

        static const char* targets[] = {"Off", "Active", "Spotify", "Spotifast"};
        int target = s.media_key_target;
        propertyHeader("Media Keys");
        if (ImGui::Combo("##keys", &target, targets, IM_ARRAYSIZE(targets)))
            wallify_debug_set_int(18, target);

        propertyText("Title", s.title_len ? s.title : "—");
        propertyText("Artist", s.artist_len ? s.artist : "—");
        ImGui::EndTable();
    }
}

static void drawWindow(const WallifyDebugSnapshot& s) {
    if (beginProperties("window")) {
        propertyInt("Margin Left", s.margin_left, 1003);
        propertyInt("Margin Top", s.margin_top, 1004);
        propertyReadout("Window ID", "#%lld", (long long)s.window_number);
        propertyReadout("Layer", "%lld", (long long)s.window_layer);
        propertyReadout("Frame", "%.0f, %.0f  %.0f × %.0f",
                        s.window_x, s.window_y, s.window_width, s.window_height);
        ImGui::EndTable();
    }

    ImGui::SeparatorText("Widget");
    ImGui::Text("Size: %d × %d", s.width, s.height);
    ImGui::Text("Margins: %d, %d", s.margin_left, s.margin_top);
}

static void drawWindowServer(const WallifyDebugSnapshot& s) {
    if (beginProperties("windowserver")) {
        propertyReadout("Candidates", "%u", s.candidate_count);
        propertyReadout("Distance²", "%.0f", s.snap_distance_sq);
        propertyReadout("Window ID", "#%lld", (long long)s.window_number);
        propertyReadout("Layer", "%lld", (long long)s.window_layer);
        ImGui::EndTable();
    }

    ImGui::SeparatorText("Current Window");
    ImGui::Text("Frame: %.0f, %.0f  %.0f × %.0f",
                s.window_x, s.window_y, s.window_width, s.window_height);
}

static void drawSnap(const WallifyDebugSnapshot& s) {
    if (beginProperties("snap")) {
        propertyInt("Target X", (int)lround(s.outline_x), 1005);
        propertyInt("Target Y", (int)lround(s.outline_y), 1006);
        propertyInt("Target Width", (int)lround(s.outline_width), 1007);
        propertyInt("Target Height", (int)lround(s.outline_height), 1008);
        propertyReadout("Candidates", "%u", s.candidate_count);
        propertyReadout("Distance²", "%.0f", s.snap_distance_sq);
        ImGui::EndTable();
    }
}

static void drawTab(const char* label, void (*draw)(const WallifyDebugSnapshot&), const WallifyDebugSnapshot& snapshot) {
    if (ImGui::BeginTabItem(label)) {
        draw(snapshot);
        ImGui::EndTabItem();
    }
}

static void drawInspector() {
    WallifyDebugSnapshot s{};
    wallify_debug_get_snapshot(&s);

    ImGuiViewport* viewport = ImGui::GetMainViewport();
    ImGui::SetNextWindowPos(viewport->WorkPos);
    ImGui::SetNextWindowSize(viewport->WorkSize);
    ImGui::SetNextWindowCollapsed(false, ImGuiCond_Always);

    constexpr ImGuiWindowFlags rootFlags =
        ImGuiWindowFlags_NoDecoration |
        ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoResize |
        ImGuiWindowFlags_NoCollapse |
        ImGuiWindowFlags_NoSavedSettings |
        ImGuiWindowFlags_NoBringToFrontOnFocus |
        ImGuiWindowFlags_NoNavFocus |
        ImGuiWindowFlags_NoBackground;

    ImGui::Begin("##WallifyInspectorRoot", nullptr, rootFlags);

    if (ImGui::BeginTabBar("InspectorTabs", ImGuiTabBarFlags_Reorderable)) {
        drawTab("Runtime", drawRuntime, s);
        drawTab("Appearance", drawAppearance, s);
        drawTab("Media", drawMedia, s);
        drawTab("Window", drawWindow, s);
        drawTab("WindowServer", drawWindowServer, s);
        drawTab("Snap", drawSnap, s);
        ImGui::EndTabBar();
    }

    ImGui::End();
}

@interface WallifyImGuiView : MTKView <MTKViewDelegate>
@end

@implementation WallifyImGuiView

- (instancetype)initWithFrame:(NSRect)frame device:(id<MTLDevice>)device {
    self = [super initWithFrame:frame device:device];
    if (self) {
        self.delegate = self;
        self.paused = NO;
        self.enableSetNeedsDisplay = NO;
        self.preferredFramesPerSecond = 60;
        self.framebufferOnly = NO;
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        self.clearColor = MTLClearColorMake(0.065, 0.068, 0.08, 1.0);
    }
    return self;
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    (void)size;
}

- (void)drawInMTKView:(MTKView*)view {
    if (!gInspectorVisible || !gInspectorInitialized) return;

    MTLRenderPassDescriptor* pass = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!pass || !drawable) return;

    @autoreleasepool {
        ImGui_ImplMetal_NewFrame(pass);
        ImGui_ImplOSX_NewFrame(view);
        ImGui::NewFrame();

        drawInspector();

        ImGui::Render();

        id<MTLCommandBuffer> commandBuffer = [gInspectorQueue commandBuffer];
        commandBuffer.label = @"Wallify Inspector";
        id<MTLRenderCommandEncoder> encoder =
            [commandBuffer renderCommandEncoderWithDescriptor:pass];
        ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, encoder);
        [encoder endEncoding];
        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];
    }
}

@end

@interface WallifyInspectorWindowDelegate : NSObject <NSWindowDelegate>
@end

@implementation WallifyInspectorWindowDelegate
- (void)windowWillClose:(NSNotification*)notification {
    (void)notification;
    gInspectorVisible = false;
}
@end

static WallifyInspectorWindowDelegate* gInspectorDelegate = nil;

static void showInspectorOnMain(void) {
        NSLog(@"Wallify Inspector: showing");

        if (!gInspectorPanel) {
            id<MTLDevice> device = MTLCreateSystemDefaultDevice();
            if (!device) {
                NSLog(@"Wallify Inspector: no Metal device");
                return;
            }

            gInspectorQueue = [device newCommandQueue];
            if (!gInspectorQueue) {
                NSLog(@"Wallify Inspector: failed to create Metal command queue");
                return;
            }

            IMGUI_CHECKVERSION();
            ImGui::CreateContext();

            ImGuiIO& io = ImGui::GetIO();
            io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
            io.IniFilename = nullptr;

            setupStyle();

            gInspectorView = [[WallifyImGuiView alloc]
                initWithFrame:NSMakeRect(0, 0, 1040, 720)
                        device:device];

            gInspectorDelegate = [WallifyInspectorWindowDelegate new];
            gInspectorPanel = [[NSPanel alloc]
                initWithContentRect:NSMakeRect(0, 0, 1040, 720)
                           styleMask:(NSWindowStyleMaskTitled |
                                      NSWindowStyleMaskClosable |
                                      NSWindowStyleMaskResizable |
                                      NSWindowStyleMaskMiniaturizable)
                             backing:NSBackingStoreBuffered
                               defer:NO];

            gInspectorPanel.title = @"Wallify Inspector";
            gInspectorPanel.appearance =
                [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            gInspectorPanel.opaque = YES;
            gInspectorPanel.backgroundColor =
                [NSColor colorWithCalibratedWhite:0.06 alpha:1.0];
            gInspectorPanel.hasShadow = YES;
            gInspectorPanel.level = NSFloatingWindowLevel;
            gInspectorPanel.collectionBehavior =
                NSWindowCollectionBehaviorCanJoinAllSpaces |
                NSWindowCollectionBehaviorFullScreenAuxiliary;
            gInspectorPanel.releasedWhenClosed = NO;
            gInspectorPanel.delegate = gInspectorDelegate;
            gInspectorPanel.contentMinSize = NSMakeSize(720, 500);
            setInspectorFrame(gInspectorPanel);
            [gInspectorPanel setContentView:gInspectorView];

            if (!ImGui_ImplMetal_Init(device)) {
                NSLog(@"Wallify Inspector: ImGui Metal backend initialization failed");
                gInspectorPanel = nil;
                gInspectorDelegate = nil;
                gInspectorView = nil;
                ImGui::DestroyContext();
                gInspectorQueue = nil;
                return;
            }

            if (!ImGui_ImplOSX_Init(gInspectorView)) {
                NSLog(@"Wallify Inspector: ImGui OSX backend initialization failed");
                ImGui_ImplMetal_Shutdown();
                gInspectorPanel = nil;
                gInspectorDelegate = nil;
                gInspectorView = nil;
                ImGui::DestroyContext();
                gInspectorQueue = nil;
                return;
            }

            gInspectorInitialized = true;
        }

        gInspectorVisible = true;
        gInspectorPanel.hidesOnDeactivate = NO;
        gInspectorPanel.becomesKeyOnlyIfNeeded = NO;

        [NSApp activateIgnoringOtherApps:YES];
        [gInspectorPanel orderFrontRegardless];
        [gInspectorPanel makeKeyAndOrderFront:nil];
}

extern "C" void wallify_imgui_inspector_show(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        showInspectorOnMain();
    });
}

extern "C" void wallify_imgui_inspector_hide(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gInspectorVisible = false;
        if (gInspectorPanel)
            [gInspectorPanel orderOut:nil];
    });
}
