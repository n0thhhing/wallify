#include "imgui.h"
#include "imgui_internal.h"
#include "backends/imgui_impl_metal.h"
#include "backends/imgui_impl_osx.h"
#include "../platform/debug_stats.h"
#include "../platform/gpu.h"

#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#include <stdarg.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string>
#include <mutex>
#include <thread>
#include <unistd.h>

extern "C" {



void wallify_debug_get_snapshot(WallifyDebugSnapshot* out);
void wallify_debug_set_bool(int32_t key, int32_t value);
void wallify_debug_set_int(int32_t key, int32_t value);

}

static NSPanel* gInspectorPanel = nil;
static MTKView* gInspectorView = nil;
static id<MTLCommandQueue> gInspectorQueue = nil;
static bool gInspectorInitialized = false;
static bool gInspectorVisible = false;
static bool gInspectorCollapsed = false;
static NSPoint gInspectorDragStartMouse = NSZeroPoint;
static NSPoint gInspectorDragStartOrigin = NSZeroPoint;

static const CGFloat kInspectorWidth = 1040.0;
static const CGFloat kInspectorExpandedHeight = 720.0;
static const CGFloat kInspectorCollapsedWidth = 240.0;

static CGFloat gInspectorExpandedWidth = kInspectorWidth;
static CGFloat gInspectorExpandedHeight = kInspectorExpandedHeight;
static bool gInspectorDrawableResizing = false;
static float gFrameTimes[180] = {};
static int gFrameTimeOffset = 0;
static int gFrameTimeCount = 0;

static std::mutex gInspectorConsoleMutex;
static std::string gInspectorConsole;
static int gInspectorConsoleOriginalStdout = -1;
static std::thread gInspectorConsoleThread;
static bool gInspectorConsoleInstalled = false;
static bool gInspectorConsoleAutoScroll = true;

static void appendInspectorConsole(const char* data, size_t length) {
    if (!data || !length) return;
    std::lock_guard<std::mutex> lock(gInspectorConsoleMutex);
    constexpr size_t kMaxConsoleBytes = 512 * 1024;
    gInspectorConsole.append(data, length);
    if (gInspectorConsole.size() > kMaxConsoleBytes)
        gInspectorConsole.erase(0, gInspectorConsole.size() - kMaxConsoleBytes);
}

static void startInspectorConsoleCapture() {
    if (gInspectorConsoleInstalled) return;

    int pipefd[2] = {-1, -1};
    if (pipe(pipefd) != 0) return;

    gInspectorConsoleOriginalStdout = dup(STDOUT_FILENO);
    if (gInspectorConsoleOriginalStdout < 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        return;
    }

    if (dup2(pipefd[1], STDOUT_FILENO) < 0 || dup2(pipefd[1], STDERR_FILENO) < 0) {
        dup2(gInspectorConsoleOriginalStdout, STDOUT_FILENO);
        close(pipefd[0]);
        close(pipefd[1]);
        close(gInspectorConsoleOriginalStdout);
        gInspectorConsoleOriginalStdout = -1;
        return;
    }
    close(pipefd[1]);

    gInspectorConsoleInstalled = true;
    gInspectorConsoleThread = std::thread([read_fd = pipefd[0]] {
        char buffer[4096];
        for (;;) {
            const ssize_t count = read(read_fd, buffer, sizeof(buffer));
            if (count <= 0) break;

            appendInspectorConsole(buffer, (size_t)count);

            if (gInspectorConsoleOriginalStdout >= 0) {
                ssize_t written = 0;
                while (written < count) {
                    const ssize_t n = write(gInspectorConsoleOriginalStdout,
                                            buffer + written,
                                            (size_t)(count - written));
                    if (n <= 0) break;
                    written += n;
                }
            }
        }
        close(read_fd);
    });
    gInspectorConsoleThread.detach();
}

extern "C" void wallify_debug_console_install(void) {
    if ([NSThread isMainThread]) {
        startInspectorConsoleCapture();
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            startInspectorConsoleCapture();
        });
    }
}

static void setInspectorFrame(NSPanel* panel) {
    NSScreen* screen = NSScreen.mainScreen;
    if (!screen) return;
    NSRect visible = screen.visibleFrame;
    const CGFloat width = gInspectorExpandedWidth;
    const CGFloat height = gInspectorExpandedHeight;
    [panel setFrame:NSMakeRect(
        visible.origin.x + (visible.size.width - width) * 0.5,
        visible.origin.y + (visible.size.height - height) * 0.5,
        width, height) display:NO];
}

static void setupStyle() {
    ImGuiStyle& style = ImGui::GetStyle();
    ImGui::StyleColorsDark();

    style.WindowRounding = 10.0f;
    style.ChildRounding = 8.0f;
    style.FrameRounding = 6.0f;
    style.PopupRounding = 7.0f;
    style.ScrollbarRounding = 8.0f;
    style.GrabRounding = 6.0f;
    style.TabRounding = 6.0f;

    style.WindowBorderSize = 1.0f;
    style.ChildBorderSize = 1.0f;
    style.FrameBorderSize = 1.0f;

    style.WindowPadding = ImVec2(16.0f, 14.0f);
    style.FramePadding = ImVec2(9.0f, 6.0f);
    style.ItemSpacing = ImVec2(9.0f, 8.0f);
    style.ItemInnerSpacing = ImVec2(7.0f, 5.0f);
    style.CellPadding = ImVec2(9.0f, 7.0f);
    style.IndentSpacing = 20.0f;

    ImVec4* c = style.Colors;
    c[ImGuiCol_WindowBg] = ImVec4(0.055f, 0.058f, 0.068f, 1.0f);
    c[ImGuiCol_ChildBg] = ImVec4(0.072f, 0.075f, 0.088f, 1.0f);
    c[ImGuiCol_PopupBg] = ImVec4(0.085f, 0.089f, 0.103f, 1.0f);

    c[ImGuiCol_FrameBg] = ImVec4(0.115f, 0.121f, 0.142f, 1.0f);
    c[ImGuiCol_FrameBgHovered] = ImVec4(0.155f, 0.163f, 0.19f, 1.0f);
    c[ImGuiCol_FrameBgActive] = ImVec4(0.19f, 0.20f, 0.235f, 1.0f);

    c[ImGuiCol_Header] = ImVec4(0.12f, 0.126f, 0.148f, 1.0f);
    c[ImGuiCol_HeaderHovered] = ImVec4(0.17f, 0.18f, 0.21f, 1.0f);
    c[ImGuiCol_HeaderActive] = ImVec4(0.21f, 0.22f, 0.26f, 1.0f);

    c[ImGuiCol_Button] = ImVec4(0.12f, 0.126f, 0.148f, 1.0f);
    c[ImGuiCol_ButtonHovered] = ImVec4(0.17f, 0.18f, 0.21f, 1.0f);
    c[ImGuiCol_ButtonActive] = ImVec4(0.21f, 0.22f, 0.26f, 1.0f);

    c[ImGuiCol_Tab] = ImVec4(0.10f, 0.105f, 0.122f, 1.0f);
    c[ImGuiCol_TabHovered] = ImVec4(0.17f, 0.18f, 0.21f, 1.0f);
    c[ImGuiCol_TabSelected] = ImVec4(0.18f, 0.19f, 0.225f, 1.0f);
    c[ImGuiCol_TabSelectedOverline] = ImVec4(0.28f, 0.55f, 0.95f, 1.0f);

    c[ImGuiCol_Border] = ImVec4(0.22f, 0.235f, 0.27f, 0.48f);
    c[ImGuiCol_Separator] = ImVec4(0.19f, 0.20f, 0.235f, 0.7f);

    c[ImGuiCol_Text] = ImVec4(0.93f, 0.94f, 0.97f, 1.0f);
    c[ImGuiCol_TextDisabled] = ImVec4(0.50f, 0.53f, 0.60f, 1.0f);

    c[ImGuiCol_CheckMark] = ImVec4(0.42f, 0.68f, 1.0f, 1.0f);
    c[ImGuiCol_SliderGrab] = ImVec4(0.40f, 0.64f, 0.96f, 1.0f);
    c[ImGuiCol_SliderGrabActive] = ImVec4(0.52f, 0.74f, 1.0f, 1.0f);
}

static void propertyHeader(const char* label) {
    ImGui::TableNextRow();
    ImGui::TableSetColumnIndex(0);
    ImGui::TextDisabled("%s", label);
    ImGui::TableSetColumnIndex(1);
}

static bool beginProperties(const char* id) {
    const bool open = ImGui::BeginTable(
        id, 2,
        ImGuiTableFlags_SizingStretchProp |
        ImGuiTableFlags_RowBg |
        ImGuiTableFlags_BordersInnerH |
        ImGuiTableFlags_PadOuterX |
        ImGuiTableFlags_NoBordersInBodyUntilResize);

    if (open) {
        const float width = ImGui::GetContentRegionAvail().x;
        const float labelWidth = ImClamp(width * 0.34f, 125.0f, 180.0f);
        ImGui::TableSetupColumn("Property", ImGuiTableColumnFlags_WidthFixed, labelWidth);
        ImGui::TableSetupColumn("Value", ImGuiTableColumnFlags_WidthStretch);
    }

    return open;
}

static void propertyText(const char* label, const char* value) {
    propertyHeader(label);
    ImGui::TextWrapped("%s", value ? value : "—");
}

static void propertyBool(const char* label, bool value, int key) {
    propertyHeader(label);
    ImGui::PushID(label);
    ImGui::SetNextItemWidth(-1.0f);
    bool changed = value;
    if (ImGui::Checkbox("##value", &changed))
        wallify_debug_set_bool(key, changed ? 1 : 0);
    ImGui::PopID();
}

static void propertyInt(const char* label, int value, int key) {
    propertyHeader(label);
    ImGui::PushID(label);
    ImGui::SetNextItemWidth(-1.0f);
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

static void drawRenderer(const WallifyDebugSnapshot& s) {
    WallifyRendererStats renderer{};
    wallify_debug_renderer_stats(&renderer);
    ImGui::SeparatorText("Widget renderer / Metal");
    if (beginProperties("widget_renderer")) {
        propertyText("Device", renderer.device_name);
        propertyText("Pipeline", renderer.ready ? "Ready" : "Unavailable");
        propertyText("Pending scene", renderer.pending ? "Yes" : "No");
        propertyText("Frame requested", s.frame_requested ? "Yes" : "No");
        propertyReadout("Latest scene commands", "%u / %d", renderer.command_count, WALLIFY_MAX_COMMANDS);
        propertyReadout("Loaded textures", "%u / %d", renderer.texture_count, WALLIFY_MAX_TEXTURES);
        propertyReadout("Texture allocation", "%.2f MiB", renderer.texture_bytes / 1048576.0);
        propertyReadout("Scene size", "%.0f x %.0f pt", renderer.logical_width, renderer.logical_height);
        propertyReadout("Drawable", "%.0f x %.0f px", renderer.drawable_width, renderer.drawable_height);
        propertyReadout("Render scale", "%.2fx", renderer.scale);
        ImGui::EndTable();
    }
    if (renderer.profiling) {
        ImGui::SeparatorText("Widget profiling / averages since launch");
        if (beginProperties("widget_profile")) {
            propertyReadout("Scene / completed GPU frames", "%llu / %llu",
                            (unsigned long long)renderer.scene_frames, (unsigned long long)renderer.rendered_frames);
            propertyReadout("Scene CPU", "%.3f ms", renderer.scene_ms);
            propertyReadout("GPU", "%.3f ms", renderer.gpu_ms);
            propertyReadout("Asset uploads", "%.2f MiB", renderer.uploaded_bytes / 1048576.0);
            ImGui::EndTable();
        }
    } else {
        ImGui::TextWrapped("Widget CPU/GPU timing is disabled. Launch with WALLIFY_PROFILE=1 ./run -d -f to collect it.");
    }
    ImGui::SeparatorText("Inspector rendering / separate from widget");
    const ImGuiIO& io = ImGui::GetIO();
    if (beginProperties("inspector_renderer")) {
        propertyReadout("Frame rate", "%.1f FPS", io.Framerate);
        propertyReadout("Last frame interval", "%.3f ms", io.DeltaTime * 1000.0f);
        propertyReadout("Vertices / indices", "%d / %d", io.MetricsRenderVertices, io.MetricsRenderIndices);
        propertyReadout("Visible / active ImGui windows", "%d / %d", io.MetricsRenderWindows, io.MetricsActiveWindows);
        propertyText("Platform backend", io.BackendPlatformName);
        propertyText("Renderer backend", io.BackendRendererName);
        ImGui::EndTable();
    }
    if (gFrameTimeCount) {
        ImGui::PlotLines("##frame_intervals", gFrameTimes, gFrameTimeCount,
                         gFrameTimeCount == IM_ARRAYSIZE(gFrameTimes) ? gFrameTimeOffset : 0,
                         "Inspector frame interval (ms)", 0.0f, FLT_MAX, ImVec2(-1, 90));
    }
}

static const char* hitTargetName(int target) {
    static const char* names[] = {"None", "Grid background", "Card", "Artwork", "Seek bar", "Previous", "Play / pause", "Next"};
    return target >= 0 && target < IM_ARRAYSIZE(names) ? names[target] : "Unknown";
}

static void drawMouse(const WallifyDebugSnapshot& s) {
    const ImGuiIO& io = ImGui::GetIO();
    NSPoint screen = NSEvent.mouseLocation;
    ImGui::SeparatorText("Widget input / local points, origin at top left");
    if (beginProperties("widget_mouse")) {
        propertyReadout("Last pointer event", "%.1f, %.1f", s.pointer_x, s.pointer_y);
        propertyText("Hovered target", hitTargetName(s.hover_target));
        propertyText("Last clicked target", hitTargetName(s.click_target));
        propertyText("Seeking", s.seeking ? "Yes" : "No");
        propertyText("Dragging panel", s.panel_dragging ? "Yes" : "No");
        propertyText("Snap animation", s.snap_active ? "Active" : "Idle");
        ImGui::EndTable();
    }
    ImGui::SeparatorText("Inspector input / local points, origin at top left");
    if (beginProperties("inspector_mouse")) {
        if (ImGui::IsMousePosValid()) propertyReadout("Pointer", "%.1f, %.1f", io.MousePos.x, io.MousePos.y);
        else propertyText("Pointer", "Unavailable");
        propertyReadout("Delta", "%.1f, %.1f", io.MouseDelta.x, io.MouseDelta.y);
        propertyReadout("Wheel X / Y", "%.2f / %.2f", io.MouseWheelH, io.MouseWheel);
        propertyText("Captures mouse", io.WantCaptureMouse ? "Yes" : "No");
        propertyText("Captures keyboard", io.WantCaptureKeyboard ? "Yes" : "No");
        propertyText("Wants text input", io.WantTextInput ? "Yes" : "No");
        propertyReadout("Modifiers", "Shift %d  Ctrl %d  Alt %d  Super %d", io.KeyShift, io.KeyCtrl, io.KeyAlt, io.KeySuper);
        propertyReadout("Hovered / active ImGui IDs", "%08X / %08X", GImGui->HoveredIdPreviousFrame, ImGui::GetActiveID());
        propertyReadout("Queued input events", "%d", GImGui->InputEventsQueue.Size);
        propertyReadout("AppKit screen pointer (bottom left)", "%.1f, %.1f pt", screen.x, screen.y);
        ImGui::EndTable();
    }
    if (ImGui::BeginTable("mouse_buttons", 4, ImGuiTableFlags_RowBg | ImGuiTableFlags_BordersInnerH)) {
        ImGui::TableSetupColumn("Button"); ImGui::TableSetupColumn("Down");
        ImGui::TableSetupColumn("Held (seconds)"); ImGui::TableSetupColumn("Click count");
        ImGui::TableHeadersRow();
        const char* names[] = {"Left", "Right", "Middle"};
        for (int i = 0; i < 3; ++i) {
            ImGui::TableNextRow();
            ImGui::TableNextColumn(); ImGui::TextUnformatted(names[i]);
            ImGui::TableNextColumn(); ImGui::TextUnformatted(io.MouseDown[i] ? "Yes" : "No");
            ImGui::TableNextColumn(); ImGui::Text("%.3f", ImMax(0.0f, io.MouseDownDuration[i]));
            ImGui::TableNextColumn(); ImGui::Text("%d", io.MouseClickedCount[i]);
        }
        ImGui::EndTable();
    }
}

static void drawLayout(const WallifyDebugSnapshot& s) {
    static const char* names[] = {"Card", "Artwork", "Progress", "Seek hitbox", "Previous hitbox", "Play / pause hitbox", "Next hitbox"};
    static const ImU32 colors[] = {IM_COL32(200,200,215,255), IM_COL32(120,180,255,255), IM_COL32(100,230,170,255), IM_COL32(255,210,100,255), IM_COL32(225,130,230,255), IM_COL32(255,150,130,255), IM_COL32(140,220,240,255)};
    ImGui::TextWrapped("Live widget geometry in points. Outlines show visible elements and active input hitboxes; the dot is the last widget pointer event. Hidden elements remain listed below.");
    const float scale = ImMin((ImGui::GetContentRegionAvail().x - 16.0f) / (float)ImMax(1.0, s.layout_width),
                             260.0f / (float)ImMax(1.0, s.layout_height));
    const ImVec2 origin = ImGui::GetCursorScreenPos();
    const ImVec2 size((float)s.layout_width * scale, (float)s.layout_height * scale);
    ImDrawList* draw = ImGui::GetWindowDrawList();
    draw->AddRectFilled(origin, ImVec2(origin.x + size.x, origin.y + size.y), IM_COL32(12,14,18,255));
    draw->PushClipRect(origin, ImVec2(origin.x + size.x, origin.y + size.y), true);
    for (int i = 0; i < 7; ++i) {
        if (!s.geometry_visible[i]) continue;
        const double* r = s.geometry[i];
        ImVec2 a(origin.x + r[0] * scale, origin.y + r[1] * scale);
        ImVec2 b(a.x + r[2] * scale, a.y + r[3] * scale);
        draw->AddRect(a, b, colors[i], r[4] * scale, 0, 1.5f);
    }
    if (s.pointer_x >= 0 && s.pointer_y >= 0)
        draw->AddCircleFilled(ImVec2(origin.x + s.pointer_x * scale, origin.y + s.pointer_y * scale), 3.5f, IM_COL32_WHITE);
    draw->PopClipRect();
    ImGui::Dummy(size);
    ImGui::Text("Layout: %.0f x %.0f pt    Compact blend: %.3f", s.layout_width, s.layout_height, s.compact_mix);
    if (ImGui::BeginTable("geometry", 6, ImGuiTableFlags_RowBg | ImGuiTableFlags_BordersInnerH)) {
        for (const char* name : {"Element", "X", "Y", "Width", "Height", "Radius"}) ImGui::TableSetupColumn(name);
        ImGui::TableHeadersRow();
        for (int i = 0; i < 7; ++i) {
            ImGui::TableNextRow();
            ImGui::TableNextColumn(); ImGui::TextColored(ImGui::ColorConvertU32ToFloat4(colors[i]), "%s%s", names[i], s.geometry_visible[i] ? "" : " (hidden)");
            for (double v : s.geometry[i]) { ImGui::TableNextColumn(); ImGui::Text("%.1f", v); }
        }
        ImGui::EndTable();
    }
}

static void viewportProperties(const char* id, NSWindow* window) {
    if (!window) { ImGui::TextDisabled("Window unavailable"); return; }
    if (beginProperties(id)) {
        NSRect frame = window.frame;
        NSRect bounds = window.contentView.bounds;
        propertyReadout("AppKit frame (bottom left)", "%.0f, %.0f  %.0f x %.0f pt", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
        propertyReadout("Content bounds", "%.0f, %.0f  %.0f x %.0f pt", bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height);
        propertyReadout("Backing scale", "%.2fx", window.backingScaleFactor);
        propertyText("Visible", window.visible ? "Yes" : "No");
        propertyText("Key window", window.keyWindow ? "Yes" : "No");
        propertyText("Occluded", (window.occlusionState & NSWindowOcclusionStateVisible) ? "No" : "Yes");
        propertyText("Display", window.screen.localizedName.UTF8String);
        ImGui::EndTable();
    }
}

static void drawViewport(const WallifyDebugSnapshot& s) {
    ImGui::SeparatorText("Widget window");
    viewportProperties("widget_viewport", [NSApp windowWithWindowNumber:(NSInteger)s.window_number]);
    ImGui::SeparatorText("Inspector window");
    viewportProperties("inspector_viewport", gInspectorPanel);
    const ImGuiIO& io = ImGui::GetIO();
    if (beginProperties("imgui_viewport")) {
        propertyReadout("ImGui display", "%.0f x %.0f pt", io.DisplaySize.x, io.DisplaySize.y);
        propertyReadout("Framebuffer scale", "%.2f x %.2f", io.DisplayFramebufferScale.x, io.DisplayFramebufferScale.y);
        propertyReadout("Metal drawable", "%.0f x %.0f px", gInspectorView.drawableSize.width, gInspectorView.drawableSize.height);
        ImGui::EndTable();
    }
    ImGui::SeparatorText("Connected displays / AppKit coordinates");
    int index = 0;
    for (NSScreen* screen in NSScreen.screens) {
        ImGui::PushID(index++);
        ImGui::TextUnformatted(screen.localizedName.UTF8String);
        if (beginProperties("screen")) {
            NSRect frame = screen.frame, work = screen.visibleFrame;
            propertyReadout("Frame", "%.0f, %.0f  %.0f x %.0f pt", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
            propertyReadout("Work area", "%.0f, %.0f  %.0f x %.0f pt", work.origin.x, work.origin.y, work.size.width, work.size.height);
            propertyReadout("Scale / maximum refresh", "%.2fx / %ld Hz", screen.backingScaleFactor, (long)screen.maximumFramesPerSecond);
            ImGui::EndTable();
        }
        ImGui::PopID();
    }
}

static void drawAnimation(const WallifyDebugSnapshot& s) {
    if (beginProperties("animation_state")) {
        propertyText("Mode transition", s.transition_active ? "Active" : "Idle");
        propertyReadout("Mode transition blend", "%.4f", s.transition_mix);
        propertyReadout("Compact blend", "%.4f", s.compact_mix);
        propertyReadout("Idle blend", "%.4f", s.idle_mix);
        propertyReadout("Aurora blend", "%.4f", s.aurora_mix);
        propertyReadout("Artwork crossfade", "%.4f", s.artwork_mix);
        propertyReadout("Play / pause blend", "%.4f", s.play_pause_mix);
        propertyText("Artwork available", s.has_artwork ? "Yes" : "No");
        propertyReadout("Playback position / duration", "%.2f / %.2f seconds", s.position, s.duration);
        propertyReadout("Playback rate", "%.2f", s.rate);
        ImGui::EndTable();
    }
}

static void drawSection(const char* label, void (*draw)(const WallifyDebugSnapshot&),
                        const WallifyDebugSnapshot& snapshot, bool defaultOpen = false) {
    const ImGuiTreeNodeFlags flags =
        ImGuiTreeNodeFlags_Framed |
        ImGuiTreeNodeFlags_SpanAvailWidth |
        ImGuiTreeNodeFlags_AllowOverlap |
        (defaultOpen ? ImGuiTreeNodeFlags_DefaultOpen : ImGuiTreeNodeFlags_None);

    if (ImGui::CollapsingHeader(label, flags)) {
        ImGui::PushID(label);
        ImGui::Spacing();
        draw(snapshot);
        ImGui::PopID();
        ImGui::Spacing();
    }
}

static void drawWidget(const WallifyDebugSnapshot& s) {
    drawSection("Runtime", drawRuntime, s, true);
    drawSection("Appearance", drawAppearance, s, true);
    drawSection("Media", drawMedia, s);
    drawSection("Animation", drawAnimation, s);
}

static void drawGeometry(const WallifyDebugSnapshot& s) {
    ImGui::TextDisabled("Live geometry, display coordinates, and snapping state");
    ImGui::Spacing();

    drawSection("Layout & hitboxes", drawLayout, s, true);
    drawSection("Window", drawWindow, s, true);
    drawSection("Viewports & displays", drawViewport, s);
    drawSection("Snapping", drawSnap, s);
    drawSection("WindowServer", drawWindowServer, s);
}

static const char* modeName(int mode) {
    static const char* names[] = {"1 × 1", "2 × 1", "3 × 1", "1 × 2", "2 × 2"};
    return mode >= 0 && mode < IM_ARRAYSIZE(names) ? names[mode] : "Unknown";
}

static const char* mediaSourceName(int source) {
    static const char* names[] = {"Now Playing", "Spotify", "Spotifast", "Auto"};
    return source >= 0 && source < IM_ARRAYSIZE(names) ? names[source] : "Unknown";
}

static void drawStatusMetric(const char* label, const char* value, bool accent = false) {
    ImGui::TableNextColumn();
    ImGui::TextDisabled("%s", label);
    ImGui::PushTextWrapPos(ImGui::GetCursorPosX() + ImGui::GetColumnWidth() - 12.0f);
    if (accent) {
        ImVec4 color = ImGui::GetStyle().Colors[ImGuiCol_CheckMark];
        ImGui::TextColored(color, "%s", value);
    } else {
        ImGui::Text("%s", value);
    }
    ImGui::PopTextWrapPos();
}

static void drawInspectorStatusBar(const WallifyDebugSnapshot& s) {
    const ImGuiIO& io = ImGui::GetIO();

    char modeText[32];
    snprintf(modeText, sizeof(modeText), "%s  ·  %d × %d", modeName(s.mode), s.width, s.height);

    const char* status =
        s.transition_active ? "Transitioning" :
        (s.frame_requested ? "Live" : "Idle");

    char titleText[48];
    if (s.title_len) {
        snprintf(titleText, sizeof(titleText), "%.28s%s",
                 s.title, s.title_len > 28 ? "…" : "");
    } else {
        snprintf(titleText, sizeof(titleText), "Nothing playing");
    }

    char mediaText[96];
    snprintf(mediaText, sizeof(mediaText), "%s  ·  %s",
             titleText, mediaSourceName(s.source));

    char frameText[32];
    snprintf(frameText, sizeof(frameText), "%.0f FPS  ·  %.2f ms",
             io.Framerate, io.DeltaTime * 1000.0f);

    ImGui::PushStyleVar(ImGuiStyleVar_CellPadding, ImVec2(12.0f, 4.0f));
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(6.0f, 2.0f));

    if (ImGui::BeginTable("InspectorStatusTable", 4,
                          ImGuiTableFlags_SizingStretchProp |
                          ImGuiTableFlags_BordersInnerV |
                          ImGuiTableFlags_NoPadOuterX)) {
        ImGui::TableSetupColumn("Status", ImGuiTableColumnFlags_WidthFixed, 160.0f);
        ImGui::TableSetupColumn("Mode", ImGuiTableColumnFlags_WidthFixed, 190.0f);
        ImGui::TableSetupColumn("Media", ImGuiTableColumnFlags_WidthStretch);
        ImGui::TableSetupColumn("Frame", ImGuiTableColumnFlags_WidthFixed, 160.0f);

        drawStatusMetric("STATUS", status, true);
        drawStatusMetric("MODE", modeText);
        drawStatusMetric("MEDIA", mediaText);
        drawStatusMetric("FRAME", frameText);
        ImGui::EndTable();
    }

    ImGui::PopStyleVar(2);
    ImGui::Spacing();
}

static void drawConsole(const WallifyDebugSnapshot&) {
    ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(8.0f, 5.0f));
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(8.0f, 6.0f));

    if (ImGui::Button("Clear")) {
        std::lock_guard<std::mutex> lock(gInspectorConsoleMutex);
        gInspectorConsole.clear();
    }
    ImGui::SameLine();
    ImGui::Checkbox("Auto-scroll", &gInspectorConsoleAutoScroll);
    ImGui::SameLine();
    size_t bytes = 0;
    {
        std::lock_guard<std::mutex> lock(gInspectorConsoleMutex);
        bytes = gInspectorConsole.size();
    }
    ImGui::TextDisabled("%zu KiB captured", bytes / 1024);

    const ImVec2 avail = ImGui::GetContentRegionAvail();
    if (ImGui::BeginChild("ConsoleOutput", avail, ImGuiChildFlags_Borders,
                          ImGuiWindowFlags_HorizontalScrollbar)) {
        ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(0.0f, 2.0f));
        std::string output;
        {
            std::lock_guard<std::mutex> lock(gInspectorConsoleMutex);
            output = gInspectorConsole;
        }
        ImGui::TextUnformatted(output.empty() ? "Console is waiting for output…" : output.c_str());
        if (gInspectorConsoleAutoScroll && ImGui::GetScrollY() >= ImGui::GetScrollMaxY() - 8.0f)
            ImGui::SetScrollHereY(1.0f);
        ImGui::PopStyleVar();
    }
    ImGui::EndChild();

    ImGui::PopStyleVar(2);
}

static void drawTab(const char* label, void (*draw)(const WallifyDebugSnapshot&), const WallifyDebugSnapshot& snapshot) {
    if (ImGui::BeginTabItem(label)) {
        ImGui::PushID(label);

        const ImVec2 avail = ImGui::GetContentRegionAvail();
        if (ImGui::BeginChild("InspectorContent", avail, ImGuiChildFlags_Borders)) {
            draw(snapshot);
        }
        ImGui::EndChild();

        ImGui::PopID();
        ImGui::EndTabItem();
    }
}

static void resizeInspector(CGFloat width, CGFloat height, bool saveExpandedSize) {
    if (!gInspectorPanel) return;

    if (saveExpandedSize && !gInspectorCollapsed) {
        gInspectorExpandedWidth = width;
        gInspectorExpandedHeight = height;
    }

    NSRect frame = gInspectorPanel.frame;
    // Keep the title bar anchored at the same screen position.
    frame.origin.y += frame.size.height - height;
    frame.size = NSMakeSize(width, height);
    gInspectorDrawableResizing = true;
    [gInspectorPanel setFrame:frame display:YES animate:NO];
    [gInspectorView setNeedsLayout:YES];
}

static void dragInspectorTitleBar() {
    ImGuiWindow* window = ImGui::GetCurrentWindow();
    static bool dragging = false;
    const bool active = ImGui::GetActiveID() == window->MoveId &&
        ImGui::IsMouseDown(ImGuiMouseButton_Left) &&
        (dragging || window->TitleBarRect().Contains(ImGui::GetIO().MouseClickedPos[0]));
    if (active && !dragging) {
        gInspectorDragStartMouse = [NSEvent mouseLocation];
        gInspectorDragStartOrigin = gInspectorPanel.frame.origin;
    }
    if (active) {
        NSPoint mouse = [NSEvent mouseLocation];
        [gInspectorPanel setFrameOrigin:NSMakePoint(
            gInspectorDragStartOrigin.x + mouse.x - gInspectorDragStartMouse.x,
            gInspectorDragStartOrigin.y + mouse.y - gInspectorDragStartMouse.y)];
    }
    dragging = active;
}

static void drawInspector() {
    WallifyDebugSnapshot s{};
    wallify_debug_get_snapshot(&s);
    gFrameTimes[gFrameTimeOffset] = ImGui::GetIO().DeltaTime * 1000.0f;
    gFrameTimeOffset = (gFrameTimeOffset + 1) % IM_ARRAYSIZE(gFrameTimes);
    gFrameTimeCount = ImMin(gFrameTimeCount + 1, IM_ARRAYSIZE(gFrameTimes));

    ImGui::SetNextWindowPos(ImVec2(0, 0), ImGuiCond_Always);
    ImGui::SetNextWindowSize(ImVec2(gInspectorCollapsed ? kInspectorCollapsedWidth : gInspectorExpandedWidth,
                                  gInspectorExpandedHeight),
                             ImGuiCond_Always);

    constexpr ImGuiWindowFlags rootFlags =
        ImGuiWindowFlags_NoScrollbar |
        ImGuiWindowFlags_NoMove |
        ImGuiWindowFlags_NoResize |
        ImGuiWindowFlags_NoSavedSettings |
        ImGuiWindowFlags_NoBringToFrontOnFocus |
        ImGuiWindowFlags_NoNavFocus;

    const bool expanded = ImGui::Begin("Wallify Inspector", nullptr, rootFlags);
    const bool collapsed = ImGui::IsWindowCollapsed();
    if (collapsed != gInspectorCollapsed) {
        gInspectorCollapsed = collapsed;
        resizeInspector(collapsed ? kInspectorCollapsedWidth : gInspectorExpandedWidth,
                        collapsed ? ImGui::GetWindowHeight() : gInspectorExpandedHeight,
                        false);
    }
    dragInspectorTitleBar();

    if (expanded) {
        drawInspectorStatusBar(s);

        if (ImGui::BeginTabBar(
                "InspectorTabs",
                ImGuiTabBarFlags_Reorderable |
                ImGuiTabBarFlags_FittingPolicyScroll)) {
            drawTab("Widget", drawWidget, s);
            drawTab("Renderer", drawRenderer, s);
            drawTab("Input", drawMouse, s);
            drawTab("Layout", drawGeometry, s);
            drawTab("Console", drawConsole, s);
            ImGui::EndTabBar();
        }
    }

    ImGui::End();
}

@interface WallifyImGuiView : MTKView <MTKViewDelegate>
@end

@implementation WallifyImGuiView

- (BOOL)acceptsFirstMouse:(NSEvent*)event {
    (void)event;
    return YES;
}

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
    gInspectorDrawableResizing = true;
}

- (void)drawInMTKView:(MTKView*)view {
    if (!gInspectorVisible || !gInspectorInitialized) return;

    MTLRenderPassDescriptor* pass = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!pass || !drawable) return;

    const CGFloat scale = MAX(view.window.backingScaleFactor, 1.0);
    const CGSize expectedDrawableSize = CGSizeMake(
        view.bounds.size.width * scale,
        view.bounds.size.height * scale);

    const NSUInteger drawableWidth = drawable.texture.width;
    const NSUInteger drawableHeight = drawable.texture.height;
    const bool drawableMatchesView =
        fabs((CGFloat)drawableWidth - expectedDrawableSize.width) <= 1.0 &&
        fabs((CGFloat)drawableHeight - expectedDrawableSize.height) <= 1.0;

    if (gInspectorDrawableResizing && !drawableMatchesView) {
        return;
    }

    if (drawableMatchesView) {
        gInspectorDrawableResizing = false;
    }

    @autoreleasepool {
        ImGui_ImplMetal_NewFrame(pass);
        ImGui_ImplOSX_NewFrame(view);
        // AppKit need not emit a mouse-moved event when we resize or move the
        // panel beneath the pointer. Refresh the local position for hit tests.
        NSPoint mouse = [view convertPoint:view.window.mouseLocationOutsideOfEventStream
                                 fromView:nil];
        ImGui::GetIO().AddMousePosEvent(mouse.x,
            view.isFlipped ? mouse.y : view.bounds.size.height - mouse.y);
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

@interface WallifyInspectorPanel : NSPanel
@end

@implementation WallifyInspectorPanel

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return NO;
}

@end

@interface WallifyInspectorWindowDelegate : NSObject <NSWindowDelegate>
@end

@implementation WallifyInspectorWindowDelegate
- (void)windowDidResize:(NSNotification*)notification {
    (void)notification;
    if (!gInspectorPanel || gInspectorCollapsed) return;

    const NSSize size = gInspectorPanel.contentView.bounds.size;
    if (size.width < 1.0 || size.height < 1.0) return;

    gInspectorExpandedWidth = size.width;
    gInspectorExpandedHeight = size.height;
    gInspectorDrawableResizing = true;
}

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
                initWithFrame:NSMakeRect(0, 0, kInspectorWidth, kInspectorExpandedHeight)
                        device:device];
            gInspectorView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

            gInspectorDelegate = [WallifyInspectorWindowDelegate new];
            gInspectorPanel = [[WallifyInspectorPanel alloc]
                initWithContentRect:NSMakeRect(0, 0, kInspectorWidth, kInspectorExpandedHeight)
                           styleMask:(NSWindowStyleMaskBorderless |
                                      NSWindowStyleMaskResizable)
                             backing:NSBackingStoreBuffered
                               defer:NO];

            gInspectorPanel.title = @"";
            gInspectorPanel.movableByWindowBackground = NO;
            gInspectorPanel.acceptsMouseMovedEvents = YES;
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
            gInspectorPanel.contentMinSize = NSMakeSize(640.0, 420.0);
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

        ImGui::SetWindowCollapsed("Wallify Inspector", false);
        gInspectorCollapsed = false;
        gInspectorExpandedWidth = kInspectorWidth;
        gInspectorExpandedHeight = kInspectorExpandedHeight;
        gInspectorVisible = true;
        resizeInspector(gInspectorExpandedWidth, gInspectorExpandedHeight, false);
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
