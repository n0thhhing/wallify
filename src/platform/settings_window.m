#import "settings_window.h"

extern const char *wallify_settings_path(void);

@interface WallifyFlippedView : NSVisualEffectView
@end

@implementation WallifyFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface WallifySettingsWindowController : NSObject <NSWindowDelegate, NSToolbarDelegate>

@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) NSTabView *tabView;

// Appearance controls
@property (nonatomic, strong) NSButton *glowSwitch;
@property (nonatomic, strong) NSButton *auroraSwitch;
@property (nonatomic, strong) NSSegmentedControl *intensitySegment;
@property (nonatomic, strong) NSButton *animationsSwitch;
@property (nonatomic, strong) NSButton *dimSwitch;
@property (nonatomic, strong) NSSegmentedControl *frameSegment;
@property (nonatomic, strong) NSSegmentedControl *speedSegment;

// Behavior controls
@property (nonatomic, strong) NSSegmentedControl *modeSegment;
@property (nonatomic, strong) NSSegmentedControl *sourceSegment;
@property (nonatomic, strong) NSSegmentedControl *idleSegment;
@property (nonatomic, strong) NSPopUpButton *transitionPopup;

// Desktop & Advanced controls
@property (nonatomic, strong) NSTextField *gridStatusLabel;
@property (nonatomic, strong) NSButton *debugSwitch;

+ (instancetype)sharedController;
- (void)showSettingsWindow;
- (void)closeSettingsWindow;
- (void)refreshUIFromState;

@end

static WallifySettingsWindowController *sharedSettingsController = nil;

@implementation WallifySettingsWindowController

+ (instancetype)sharedController {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedSettingsController = [[WallifySettingsWindowController alloc] init];
    });
    return sharedSettingsController;
}

static NSTextField *makeHeaderLabel(NSString *text, CGFloat x, CGFloat y) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 480, 18)];
    label.stringValue = text;
    label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    label.textColor = [NSColor secondaryLabelColor];
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.selectable = NO;
    return label;
}

static NSTextField *makeItemLabel(NSString *text, CGFloat x, CGFloat y) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, 480, 18)];
    label.stringValue = text;
    label.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    label.textColor = [NSColor labelColor];
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.selectable = NO;
    return label;
}

static NSTextField *makeSubtext(NSString *text, CGFloat x, CGFloat y, CGFloat w) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, w, 16)];
    label.stringValue = text;
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = [NSColor secondaryLabelColor];
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.selectable = NO;
    return label;
}

static NSButton *makeSwitch(NSString *title, int tag, id target, SEL action, CGFloat x, CGFloat y) {
    NSButton *btn = [NSButton checkboxWithTitle:title target:target action:action];
    btn.frame = NSMakeRect(x, y, 320, 20);
    btn.tag = tag;
    btn.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    return btn;
}

static NSSegmentedControl *makeSegments(NSArray<NSString *> *items, int tag, id target, SEL action, CGFloat x, CGFloat y, CGFloat w) {
    NSSegmentedControl *sc = [NSSegmentedControl segmentedControlWithLabels:items trackingMode:NSSegmentSwitchTrackingSelectOne target:target action:action];
    sc.frame = NSMakeRect(x, y, w, 24);
    sc.tag = tag;
    sc.segmentDistribution = NSSegmentDistributionFillEqually;
    return sc;
}

static NSBox *makeDivider(CGFloat x, CGFloat y, CGFloat w) {
    NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(x, y, w, 1)];
    box.boxType = NSBoxSeparator;
    return box;
}

- (void)createWindow {
    NSRect frame = NSMakeRect(0, 0, 520, 580);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
    self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Wallify Settings";
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    self.window.tabbingMode = NSWindowTabbingModeDisallowed;

    WallifyFlippedView *root = [[WallifyFlippedView alloc] initWithFrame:frame];
    root.material = NSVisualEffectMaterialWindowBackground;
    root.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    root.state = NSVisualEffectStateActive;
    self.window.contentView = root;

    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"SettingsToolbar"];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    toolbar.allowsUserCustomization = NO;
    toolbar.autosavesConfiguration = NO;
    self.window.toolbar = toolbar;

    // Tab view container
    self.tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(0, 0, 520, 500)];
    self.tabView.tabViewType = NSNoTabsNoBorder;
    [root addSubview:self.tabView];

    // Build Tab 1: Appearance
    NSTabViewItem *itemAppearance = [[NSTabViewItem alloc] initWithIdentifier:@"appearance"];
    WallifyFlippedView *viewAppearance = [[WallifyFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 520, 480)];
    [self buildAppearanceTab:viewAppearance];
    itemAppearance.view = viewAppearance;
    [self.tabView addTabViewItem:itemAppearance];

    // Build Tab 2: Behavior
    NSTabViewItem *itemBehavior = [[NSTabViewItem alloc] initWithIdentifier:@"behavior"];
    WallifyFlippedView *viewBehavior = [[WallifyFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 520, 480)];
    [self buildBehaviorTab:viewBehavior];
    itemBehavior.view = viewBehavior;
    [self.tabView addTabViewItem:itemBehavior];

    // Build Tab 3: Desktop & About
    NSTabViewItem *itemDesktop = [[NSTabViewItem alloc] initWithIdentifier:@"desktop"];
    WallifyFlippedView *viewDesktop = [[WallifyFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 520, 480)];
    [self buildDesktopTab:viewDesktop];
    itemDesktop.view = viewDesktop;
    [self.tabView addTabViewItem:itemDesktop];

    // Divider above bottom bar
    [root addSubview:makeDivider(0, 532, 520)];

    // Bottom bar
    NSTextField *versionLabel = makeSubtext(@"Wallify v2.1 • Metal 3 Desktop Widget", 20, 545, 220);
    [root addSubview:versionLabel];

    NSButton *restoreBtn = [[NSButton alloc] initWithFrame:NSMakeRect(240, 542, 160, 26)];
    restoreBtn.title = @"Restore Defaults…";
    restoreBtn.bezelStyle = NSBezelStyleRounded;
    restoreBtn.target = self;
    restoreBtn.action = @selector(restoreDefaultsClicked:);
    [root addSubview:restoreBtn];

    NSButton *doneBtn = [[NSButton alloc] initWithFrame:NSMakeRect(410, 542, 90, 26)];
    doneBtn.title = @"Done";
    doneBtn.bezelStyle = NSBezelStyleRounded;
    doneBtn.keyEquivalent = @"\r";
    doneBtn.target = self;
    doneBtn.action = @selector(doneClicked:);
    [root addSubview:doneBtn];
}

- (void)buildAppearanceTab:(WallifyFlippedView *)view {
    // Section 1: Lighting & Glow
    [view addSubview:makeHeaderLabel(@"LIGHTING & ATMOSPHERE", 20, 16)];

    self.glowSwitch = makeSwitch(@"Radiant Artwork Glow", 0, self, @selector(switchChanged:), 20, 38);
    [view addSubview:self.glowSwitch];
    [view addSubview:makeSubtext(@"Casts an ambient atmospheric glow matching current album art colors.", 44, 62, 450)];

    self.auroraSwitch = makeSwitch(@"Dynamic Aurora Background", 1, self, @selector(switchChanged:), 20, 84);
    [view addSubview:self.auroraSwitch];
    [view addSubview:makeSubtext(@"Multi-stop animated color gradient shifting smoothly behind the widget.", 44, 108, 450)];

    [view addSubview:makeItemLabel(@"Glow Intensity", 20, 132)];
    self.intensitySegment = makeSegments(@[@"Low", @"Normal", @"High"], 11, self, @selector(segmentChanged:), 20, 154, 320);
    [view addSubview:self.intensitySegment];

    [view addSubview:makeDivider(20, 192, 480)];

    // Section 2: Motion & Glass Frame
    [view addSubview:makeHeaderLabel(@"MOTION & GLASS BORDER", 20, 204)];

    self.animationsSwitch = makeSwitch(@"Fluid UI Animations", 2, self, @selector(switchChanged:), 20, 226);
    [view addSubview:self.animationsSwitch];
    [view addSubview:makeSubtext(@"Spring physics for resizing, marquee titles, and pet reactions.", 44, 250, 450)];

    self.dimSwitch = makeSwitch(@"Dim Artwork When Paused", 3, self, @selector(switchChanged:), 20, 272);
    [view addSubview:self.dimSwitch];
    [view addSubview:makeSubtext(@"Subtly reduces artwork brightness when playback is paused.", 44, 296, 450)];

    [view addSubview:makeItemLabel(@"Glass Border Accent", 20, 320)];
    self.frameSegment = makeSegments(@[@"Off", @"Subtle", @"Strong"], 10, self, @selector(segmentChanged:), 20, 342, 320);
    [view addSubview:self.frameSegment];

    [view addSubview:makeItemLabel(@"Animation Pacing", 20, 376)];
    self.speedSegment = makeSegments(@[@"Slow", @"Normal", @"Fast"], 12, self, @selector(segmentChanged:), 20, 398, 320);
    [view addSubview:self.speedSegment];
}

- (void)buildBehaviorTab:(WallifyFlippedView *)view {
    // Section 1: Form Factor
    [view addSubview:makeHeaderLabel(@"WIDGET SIZE & LAYOUT", 20, 16)];

    [view addSubview:makeItemLabel(@"Form Factor", 20, 36)];
    self.modeSegment = makeSegments(@[@"Compact (1×1 Mini Tile)", @"Expanded Player (3×1)"], 14, self, @selector(segmentChanged:), 20, 58, 440);
    [view addSubview:self.modeSegment];
    [view addSubview:makeSubtext(@"Compact displays 180×180pt artwork or pet; Expanded shows player info & controls.", 20, 88, 480)];

    [view addSubview:makeDivider(20, 118, 480)];

    // Section 2: Audio Source
    [view addSubview:makeHeaderLabel(@"AUDIO TELEMETRY", 20, 130)];

    [view addSubview:makeItemLabel(@"Media Source", 20, 150)];
    self.sourceSegment = makeSegments(@[@"System Now Playing", @"Spotify Direct", @"Spotifast"], 13, self, @selector(segmentChanged:), 20, 172, 440);
    [view addSubview:self.sourceSegment];
    [view addSubview:makeSubtext(@"Now Playing supports all media; Spotify uses AppleScript; Spotifast connects via fast local IPC.", 20, 202, 480)];

    [view addSubview:makeDivider(20, 230, 480)];

    // Section 3: Idle Character & Transition
    [view addSubview:makeHeaderLabel(@"IDLE COMPANION & ARTWORK", 20, 242)];

    [view addSubview:makeItemLabel(@"Idle Mascot", 20, 262)];
    self.idleSegment = makeSegments(@[@"🐱 Pixel Cat", @"🍌 Banana Cat", @"♫ Spotify Button"], 15, self, @selector(segmentChanged:), 20, 284, 440);
    [view addSubview:self.idleSegment];
    [view addSubview:makeSubtext(@"Interactive companion shown when no media is playing. Click the cat to pet it!", 20, 314, 480)];

    [view addSubview:makeItemLabel(@"Track Artwork Transition", 20, 344)];
    self.transitionPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(20, 366, 320, 26) pullsDown:NO];
    [self.transitionPopup addItemsWithTitles:@[
        @"Default (Smooth Crossfade)",
        @"Cinematic (Zoom & Push)",
        @"Liquid Ripple (Metal Wave)",
        @"3D Card Flip (Spatial Rotation)",
        @"Vinyl Spin (Turntable Rotation)",
        @"Cyber Glitch (CRT Slice)"
    ]];
    self.transitionPopup.target = self;
    self.transitionPopup.action = @selector(transitionChanged:);
    [view addSubview:self.transitionPopup];
    [view addSubview:makeSubtext(@"GPU Metal shader animation played when switching songs.", 20, 398, 480)];
}

- (void)buildDesktopTab:(WallifyFlippedView *)view {
    // Section 1: Desktop Grid Placement
    [view addSubview:makeHeaderLabel(@"MACOS DESKTOP GRID PLACEMENT", 20, 16)];

    NSBox *gridBox = [[NSBox alloc] initWithFrame:NSMakeRect(20, 38, 480, 105)];
    gridBox.titlePosition = NSNoTitle;
    WallifyFlippedView *boxContent = [[WallifyFlippedView alloc] initWithFrame:gridBox.contentView.bounds];

    NSTextField *boxTitle = makeItemLabel(@"Current Desktop Position", 16, 12);
    [boxContent addSubview:boxTitle];

    self.gridStatusLabel = makeSubtext(@"Position: checking...", 16, 34, 440);
    self.gridStatusLabel.textColor = [NSColor labelColor];
    [boxContent addSubview:self.gridStatusLabel];

    NSButton *snapResetBtn = [[NSButton alloc] initWithFrame:NSMakeRect(16, 64, 250, 26)];
    snapResetBtn.title = @"Snap to Default Grid Slot (8, 8)";
    snapResetBtn.bezelStyle = NSBezelStyleRounded;
    snapResetBtn.target = self;
    snapResetBtn.action = @selector(resetPositionClicked:);
    [boxContent addSubview:snapResetBtn];

    gridBox.contentView = boxContent;
    [view addSubview:gridBox];

    [view addSubview:makeDivider(20, 158, 480)];

    // Section 2: Diagnostics
    [view addSubview:makeHeaderLabel(@"DIAGNOSTICS & DEBUGGING", 20, 170)];

    self.debugSwitch = makeSwitch(@"Show Snapping Diagnostics HUD", 4, self, @selector(switchChanged:), 20, 192);
    [view addSubview:self.debugSwitch];
    [view addSubview:makeSubtext(@"Displays live floating window with WindowServer coordinates, candidates, and snap metrics.", 44, 216, 450)];

    [view addSubview:makeDivider(20, 246, 480)];

    // Section 3: Settings File
    [view addSubview:makeHeaderLabel(@"CONFIGURATION FILE", 20, 258)];

    NSString *confPath = [NSString stringWithUTF8String:wallify_settings_path()];
    NSTextField *pathLabel = makeSubtext(confPath, 20, 280, 480);
    pathLabel.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
    [view addSubview:pathLabel];

    NSButton *revealBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, 306, 150, 26)];
    revealBtn.title = @"Reveal in Finder";
    revealBtn.bezelStyle = NSBezelStyleRounded;
    revealBtn.target = self;
    revealBtn.action = @selector(revealConfigClicked:);
    [view addSubview:revealBtn];

    NSButton *openEditorBtn = [[NSButton alloc] initWithFrame:NSMakeRect(180, 306, 160, 26)];
    openEditorBtn.title = @"Open in Text Editor";
    openEditorBtn.bezelStyle = NSBezelStyleRounded;
    openEditorBtn.target = self;
    openEditorBtn.action = @selector(openConfigClicked:);
    [view addSubview:openEditorBtn];

    [view addSubview:makeDivider(20, 348, 480)];

    // Section 4: About
    [view addSubview:makeHeaderLabel(@"ABOUT WALLIFY", 20, 360)];

    NSTextField *aboutTitle = makeItemLabel(@"Wallify 2.1", 20, 380);
    aboutTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightBold];
    [view addSubview:aboutTitle];

    [view addSubview:makeSubtext(@"Engineered with native Metal 3 shaders and AppKit for macOS Sequoia.", 20, 402, 480)];
    [view addSubview:makeSubtext(@"Zero runtime dependencies • Pure native performance", 20, 420, 480)];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"appearance", @"behavior", @"desktop"];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"appearance", @"behavior", @"desktop"];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"appearance", @"behavior", @"desktop"];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    if ([itemIdentifier isEqualToString:@"appearance"]) {
        item.label = @"Appearance";
        item.image = [NSImage imageWithSystemSymbolName:@"paintpalette" accessibilityDescription:nil];
        item.target = self;
        item.action = @selector(toolbarAction:);
    } else if ([itemIdentifier isEqualToString:@"behavior"]) {
        item.label = @"Behavior";
        item.image = [NSImage imageWithSystemSymbolName:@"switch.2" accessibilityDescription:nil];
        item.target = self;
        item.action = @selector(toolbarAction:);
    } else if ([itemIdentifier isEqualToString:@"desktop"]) {
        item.label = @"Desktop & About";
        item.image = [NSImage imageWithSystemSymbolName:@"macwindow" accessibilityDescription:nil];
        item.target = self;
        item.action = @selector(toolbarAction:);
    }
    return item;
}

- (void)toolbarAction:(NSToolbarItem *)sender {
    if ([sender.itemIdentifier isEqualToString:@"appearance"]) [self.tabView selectTabViewItemAtIndex:0];
    else if ([sender.itemIdentifier isEqualToString:@"behavior"]) [self.tabView selectTabViewItemAtIndex:1];
    else if ([sender.itemIdentifier isEqualToString:@"desktop"]) [self.tabView selectTabViewItemAtIndex:2];
}

- (void)switchChanged:(NSButton *)sender {
    BOOL val = (sender.state == NSControlStateValueOn);
    wallify_settings_apply_bool((int)sender.tag, val);
}

- (void)segmentChanged:(NSSegmentedControl *)sender {
    int val = (int)sender.selectedSegment;
    wallify_settings_apply_int((int)sender.tag, val);
}

- (void)transitionChanged:(NSPopUpButton *)sender {
    int val = (int)sender.indexOfSelectedItem;
    wallify_settings_apply_int(16, val);
}

- (void)resetPositionClicked:(id)sender {
    wallify_settings_reset_position();
    [self updateGridStatusLabel];
}

- (void)restoreDefaultsClicked:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Restore Default Settings?";
    alert.informativeText = @"All appearance, behavior, and animation preferences will be reset to their factory defaults.";
    [alert addButtonWithTitle:@"Restore Defaults"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        wallify_settings_restore_defaults();
        [self refreshUIFromState];
    }
}

- (void)revealConfigClicked:(id)sender {
    NSString *path = [NSString stringWithUTF8String:wallify_settings_path()];
    [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:@""];
}

- (void)openConfigClicked:(id)sender {
    NSString *path = [NSString stringWithUTF8String:wallify_settings_path()];
    [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:path]];
}

- (void)doneClicked:(id)sender {
    [self closeSettingsWindow];
}

- (void)updateGridStatusLabel {
    WallifySettingsSnapshot s;
    wallify_settings_get_snapshot(&s);
    self.gridStatusLabel.stringValue = [NSString stringWithFormat:@"Margin: Left %d pt, Top %d pt  •  Grid Slot: Col %d, Row %d", s.margin_left, s.margin_top, s.grid_x, s.grid_y];
}

- (void)refreshUIFromState {
    WallifySettingsSnapshot s;
    wallify_settings_get_snapshot(&s);

    self.glowSwitch.state = s.glow ? NSControlStateValueOn : NSControlStateValueOff;
    self.auroraSwitch.state = s.aurora ? NSControlStateValueOn : NSControlStateValueOff;
    self.animationsSwitch.state = s.animations ? NSControlStateValueOn : NSControlStateValueOff;
    self.dimSwitch.state = s.dim_paused ? NSControlStateValueOn : NSControlStateValueOff;
    self.debugSwitch.state = s.debug_hud ? NSControlStateValueOn : NSControlStateValueOff;

    self.frameSegment.selectedSegment = (s.frame_strength >= 0 && s.frame_strength <= 2) ? s.frame_strength : 1;
    self.intensitySegment.selectedSegment = (s.glow_intensity >= 0 && s.glow_intensity <= 2) ? s.glow_intensity : 1;
    self.speedSegment.selectedSegment = (s.animation_speed >= 0 && s.animation_speed <= 2) ? s.animation_speed : 1;

    self.modeSegment.selectedSegment = (s.widget_mode >= 0 && s.widget_mode <= 1) ? s.widget_mode : 0;
    self.sourceSegment.selectedSegment = (s.media_source >= 0 && s.media_source <= 2) ? s.media_source : 0;
    self.idleSegment.selectedSegment = (s.idle_style >= 0 && s.idle_style <= 2) ? s.idle_style : 0;

    if (s.track_transition >= 0 && s.track_transition < self.transitionPopup.numberOfItems) {
        [self.transitionPopup selectItemAtIndex:s.track_transition];
    }

    [self updateGridStatusLabel];
}

- (void)showSettingsWindow {
    if (!self.window) {
        [self createWindow];
    }
    [self refreshUIFromState];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)closeSettingsWindow {
    if (self.window) {
        [self.window orderOut:nil];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    // Window hidden, controller stays ready for next open
}

@end

void wallify_show_settings_window(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[WallifySettingsWindowController sharedController] showSettingsWindow];
    });
}

void wallify_close_settings_window(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[WallifySettingsWindowController sharedController] closeSettingsWindow];
    });
}

void wallify_settings_notify_position_changed(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[WallifySettingsWindowController sharedController] updateGridStatusLabel];
    });
}

bool wallify_has_settings_flag(void) {
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    for (NSString *arg in args) {
        if ([arg isEqualToString:@"--settings"] || [arg isEqualToString:@"-s"]) {
            return true;
        }
    }
    return false;
}
