#import "settings_window.h"

extern const char *wallify_settings_path(void);

@interface WallifyFlippedView : NSVisualEffectView
@end

@implementation WallifyFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface WallifySettingsWindowController : NSObject <NSWindowDelegate>

@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) WallifyFlippedView *rootView;
@property (nonatomic, strong) WallifyFlippedView *sidebarView;
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) WallifyFlippedView *contentView;
@property (nonatomic, strong) NSArray<NSView *> *pages;
@property (nonatomic, strong) NSArray<NSButton *> *sidebarButtons;
@property (nonatomic, strong) NSTextField *pageTitleLabel;
@property (nonatomic, strong) NSTextField *pageSubtitleLabel;

// Appearance
@property (nonatomic, strong) NSButton *nativeGlassSwitch;
@property (nonatomic, strong) NSButton *glowSwitch;
@property (nonatomic, strong) NSButton *auroraSwitch;
@property (nonatomic, strong) NSSegmentedControl *intensitySegment;
@property (nonatomic, strong) NSButton *animationsSwitch;
@property (nonatomic, strong) NSButton *dimSwitch;
@property (nonatomic, strong) NSButton *artworkBorderSwitch;
@property (nonatomic, strong) NSButton *compactGradientSwitch;
@property (nonatomic, strong) NSSegmentedControl *artworkRadiusSegment;
@property (nonatomic, strong) NSSegmentedControl *progressThicknessSegment;
@property (nonatomic, strong) NSSegmentedControl *frameSegment;
@property (nonatomic, strong) NSSegmentedControl *speedSegment;

// Playback
@property (nonatomic, strong) NSSegmentedControl *modeSegment;
@property (nonatomic, strong) NSSegmentedControl *sourceSegment;
@property (nonatomic, strong) NSSegmentedControl *idleSegment;
@property (nonatomic, strong) NSPopUpButton *transitionPopup;
@property (nonatomic, strong) NSButton *hideTextSwitch;
@property (nonatomic, strong) NSButton *hideProgressSwitch;
@property (nonatomic, strong) NSButton *showControlsSwitch;
@property (nonatomic, strong) NSButton *showTimestampsSwitch;
@property (nonatomic, strong) NSSegmentedControl *fontScaleSegment;
@property (nonatomic, strong) NSSegmentedControl *mediaKeySegment;

// Desktop
@property (nonatomic, strong) NSTextField *gridStatusLabel;
@property (nonatomic, strong) NSButton *debugSwitch;

+ (instancetype)sharedController;
- (void)showSettingsWindow;
- (void)closeSettingsWindow;
- (void)refreshUIFromState;

@end

static WallifySettingsWindowController *sharedSettingsController = nil;

#pragma mark - Helpers

static NSTextField *makeTextLabel(
    NSString *text,
    CGFloat x,
    CGFloat y,
    CGFloat w,
    CGFloat fontSize,
    NSFontWeight weight,
    NSColor *color
) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, w, 20)];
    label.stringValue = text;
    label.font = [NSFont systemFontOfSize:fontSize weight:weight];
    label.textColor = color;
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.selectable = NO;
    return label;
}

static NSTextField *makePageTitle(NSString *text, CGFloat x, CGFloat y, CGFloat w) {
    return makeTextLabel(
        text,
        x,
        y,
        w,
        26,
        NSFontWeightBold,
        [NSColor labelColor]
    );
}

static NSTextField *makePageSubtitle(NSString *text, CGFloat x, CGFloat y, CGFloat w) {
    NSTextField *label = makeTextLabel(
        text,
        x,
        y,
        w,
        13,
        NSFontWeightRegular,
        [NSColor secondaryLabelColor]
    );
    label.lineBreakMode = NSLineBreakByWordWrapping;
    return label;
}

static NSTextField *makeSectionLabel(NSString *text, CGFloat x, CGFloat y, CGFloat w) {
    return makeTextLabel(
        text,
        x,
        y,
        w,
        11,
        NSFontWeightSemibold,
        [NSColor tertiaryLabelColor]
    );
}

static NSTextField *makeRowSubtitle(NSString *text, CGFloat x, CGFloat y, CGFloat w) {
    NSTextField *label = makeTextLabel(
        text,
        x,
        y,
        w,
        11,
        NSFontWeightRegular,
        [NSColor secondaryLabelColor]
    );
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

static NSBox *makeCard(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    NSBox *card = [[NSBox alloc] initWithFrame:NSMakeRect(x, y, w, h)];
    card.boxType = NSBoxCustom;
    card.transparent = YES;
    card.borderWidth = 0;
    card.cornerRadius = 14;
    card.fillColor = [NSColor colorWithWhite:0.5 alpha:0.10];
    return card;
}

static NSButton *makeToggle(
    NSString *title,
    int tag,
    id target,
    SEL action,
    CGFloat x,
    CGFloat y,
    CGFloat w
) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.frame = NSMakeRect(x, y, w, 22);
    button.tag = tag;
    button.buttonType = NSButtonTypeSwitch;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    button.controlSize = NSControlSizeRegular;
    return button;
}

static NSSegmentedControl *makeSegments(
    NSArray<NSString *> *items,
    int tag,
    id target,
    SEL action,
    CGFloat x,
    CGFloat y,
    CGFloat w
) {
    NSSegmentedControl *control =
        [NSSegmentedControl segmentedControlWithLabels:items
                                           trackingMode:NSSegmentSwitchTrackingSelectOne
                                                 target:target
                                                 action:action];
    control.frame = NSMakeRect(x, y, w, 26);
    control.tag = tag;
    control.segmentDistribution = NSSegmentDistributionFillEqually;
    control.controlSize = NSControlSizeRegular;
    return control;
}

static NSButton *makeActionButton(
    NSString *title,
    id target,
    SEL action,
    CGFloat x,
    CGFloat y,
    CGFloat w
) {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(x, y, w, 28)];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    button.target = target;
    button.action = action;
    return button;
}

#pragma mark - Controller

@implementation WallifySettingsWindowController

+ (instancetype)sharedController {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedSettingsController = [[WallifySettingsWindowController alloc] init];
    });
    return sharedSettingsController;
}

#pragma mark Window

- (void)createWindow {
    NSRect frame = NSMakeRect(0, 0, 820, 640);

    self.window = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled |
                            NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                      defer:NO];

    self.window.title = @"Wallify";
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    self.window.tabbingMode = NSWindowTabbingModeDisallowed;
    self.window.minSize = NSMakeSize(760, 560);
    self.window.collectionBehavior |= NSWindowCollectionBehaviorFullScreenAuxiliary;
    self.window.restorable = NO;

    self.rootView = [[WallifyFlippedView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
    self.rootView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.rootView.material = NSVisualEffectMaterialUnderWindowBackground;
    self.rootView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.rootView.state = NSVisualEffectStateActive;
    self.window.contentView = self.rootView;

    [self buildSidebar];
    [self buildMainContent];
    [self buildFooter];

    [self selectPage:0];
}

- (void)buildSidebar {
    self.sidebarView =
        [[WallifyFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 198, 640)];
    self.sidebarView.autoresizingMask = NSViewHeightSizable;

    self.sidebarView.material = NSVisualEffectMaterialSidebar;
    self.sidebarView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.sidebarView.state = NSVisualEffectStateActive;
    [self.rootView addSubview:self.sidebarView];

    NSTextField *brand =
        makeTextLabel(@"Wallify", 22, 24, 150, 20, NSFontWeightBold, [NSColor labelColor]);
    [self.sidebarView addSubview:brand];

    NSTextField *settings =
        makeTextLabel(@"SETTINGS", 22, 49, 150, 12, NSFontWeightSemibold, [NSColor secondaryLabelColor]);
    [self.sidebarView addSubview:settings];

    NSArray<NSDictionary *> *items = @[
        @{@"title": @"Appearance", @"symbol": @"paintpalette.fill"},
        @{@"title": @"Playback", @"symbol": @"play.circle.fill"},
        @{@"title": @"Desktop", @"symbol": @"macwindow.on.rectangle"},
    ];

    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];

    CGFloat y = 84;
    for (NSDictionary *item in items) {
        NSButton *button =
            [NSButton buttonWithTitle:item[@"title"]
                               target:self
                               action:@selector(sidebarButtonClicked:)];

        button.frame = NSMakeRect(12, y, 174, 38);
        button.bordered = NO;
        button.autoresizingMask = NSViewMaxXMargin;
        button.alignment = NSTextAlignmentLeft;
        button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        button.image = [NSImage imageWithSystemSymbolName:item[@"symbol"]
                                accessibilityDescription:nil];
        button.imagePosition = NSImageLeft;
        button.imageScaling = NSImageScaleProportionallyDown;
        button.contentTintColor = [NSColor secondaryLabelColor];
        button.tag = (NSInteger)buttons.count;
        button.wantsLayer = YES;
        button.layer.cornerRadius = 9;

        [self.sidebarView addSubview:button];
        [buttons addObject:button];
        y += 44;
    }

    self.sidebarButtons = buttons;

    NSBox *separator =
        [[NSBox alloc] initWithFrame:NSMakeRect(12, 500, 174, 1)];
    separator.boxType = NSBoxSeparator;
    [self.sidebarView addSubview:separator];

    NSTextField *version =
        makeTextLabel(@"Wallify 2.1", 22, 530, 150, 11, NSFontWeightMedium, [NSColor secondaryLabelColor]);
    [self.sidebarView addSubview:version];

    NSTextField *engine =
        makeTextLabel(@"Native Metal • macOS", 22, 548, 160, 10, NSFontWeightRegular, [NSColor tertiaryLabelColor]);
    [self.sidebarView addSubview:engine];
}

- (void)buildFooter {
    NSView *footer = [[NSView alloc] initWithFrame:NSMakeRect(198, 572, 622, 68)];
    footer.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self.rootView addSubview:footer];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 622, 1)];
    separator.boxType = NSBoxSeparator;
    [footer addSubview:separator];

    NSButton *defaults = [NSButton buttonWithTitle:@"Restore Defaults"
                                             target:self
                                             action:@selector(restoreDefaultsClicked:)];
    defaults.frame = NSMakeRect(36, 19, 132, 28);
    defaults.bezelStyle = NSBezelStyleRounded;
    defaults.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    [footer addSubview:defaults];

    NSTextField *hint = makeTextLabel(
        @"Changes are applied immediately",
        190,
        25,
        230,
        16,
        NSFontWeightRegular,
        [NSColor tertiaryLabelColor]
    );
    hint.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    [footer addSubview:hint];

    NSButton *done = [NSButton buttonWithTitle:@"Done"
                                         target:self
                                         action:@selector(doneClicked:)];
    done.frame = NSMakeRect(500, 18, 86, 30);
    done.keyEquivalent = @"\r";
    done.bezelStyle = NSBezelStyleRounded;
    done.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    [footer addSubview:done];
}

- (void)buildMainContent {
    CGFloat sidebarWidth = 198;

    self.contentView =
        [[WallifyFlippedView alloc] initWithFrame:NSMakeRect(sidebarWidth, 0, 622, 572)];
    self.contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.contentView.material = NSVisualEffectMaterialUnderPageBackground;
    self.contentView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.contentView.state = NSVisualEffectStateActive;
    [self.rootView addSubview:self.contentView];

    self.pageTitleLabel =
        makePageTitle(@"Appearance", 36, 28, 500);
    [self.contentView addSubview:self.pageTitleLabel];

    self.pageSubtitleLabel =
        makePageSubtitle(
            @"Control the glass, glow, colors, and animation behavior of your widget.",
            36,
            59,
            500
        );
    [self.contentView addSubview:self.pageSubtitleLabel];

    self.scrollView =
        [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 104, 582, 448)];
    self.scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.drawsBackground = NO;

    [self.contentView addSubview:self.scrollView];

    [self buildPages];
}

- (void)buildPages {
    WallifyFlippedView *appearance =
        [[WallifyFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 550, 760)];
    [self buildAppearancePage:appearance];

    WallifyFlippedView *playback =
        [[WallifyFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 550, 900)];
    [self buildPlaybackPage:playback];

    WallifyFlippedView *desktop =
        [[WallifyFlippedView alloc] initWithFrame:NSMakeRect(0, 0, 550, 760)];
    [self buildDesktopPage:desktop];

    self.pages = @[appearance, playback, desktop];
}

#pragma mark Pages

- (void)buildAppearancePage:(WallifyFlippedView *)view {
    NSBox *glassCard = makeCard(0, 0, 550, 315);
    [view addSubview:glassCard];

    [view addSubview:makeSectionLabel(@"GLASS & ATMOSPHERE", 18, 18, 500)];

    self.nativeGlassSwitch =
        makeToggle(@"Native Glass", 5, self, @selector(switchChanged:), 18, 43, 300);
    [view addSubview:self.nativeGlassSwitch];
    [view addSubview:makeRowSubtitle(
        @"Use the native macOS glass material for the widget.",
        43, 67, 470
    )];

    self.glowSwitch =
        makeToggle(@"Artwork Glow", 0, self, @selector(switchChanged:), 18, 91, 300);
    [view addSubview:self.glowSwitch];
    [view addSubview:makeRowSubtitle(
        @"Pull ambient color from the current album artwork.",
        43, 115, 470
    )];

    self.auroraSwitch =
        makeToggle(@"Aurora Background", 1, self, @selector(switchChanged:), 18, 139, 300);
    [view addSubview:self.auroraSwitch];
    [view addSubview:makeRowSubtitle(
        @"Animate a soft multi-stop gradient behind the widget.",
        43, 163, 470
    )];

    NSTextField *intensityLabel =
        makeTextLabel(@"Glow Intensity", 18, 194, 140, 12, NSFontWeightMedium, [NSColor labelColor]);
    [view addSubview:intensityLabel];

    self.intensitySegment =
        makeSegments(@[@"Low", @"Normal", @"High"], 11, self, @selector(segmentChanged:), 165, 188, 250);
    [view addSubview:self.intensitySegment];

    self.artworkBorderSwitch =
        makeToggle(@"Artwork Border", 19, self, @selector(switchChanged:), 18, 228, 220);
    [view addSubview:self.artworkBorderSwitch];
    [view addSubview:makeRowSubtitle(
        @"Draw a fine highlight around the album artwork.",
        43, 252, 470
    )];

    NSTextField *radiusLabel =
        makeTextLabel(@"Artwork Corners", 18, 284, 140, 12, NSFontWeightMedium, [NSColor labelColor]);
    [view addSubview:radiusLabel];

    self.artworkRadiusSegment =
        makeSegments(@[@"Soft", @"Rounded", @"Large"], 21, self, @selector(segmentChanged:), 165, 278, 250);
    [view addSubview:self.artworkRadiusSegment];

    NSBox *motionCard = makeCard(0, 330, 550, 330);
    [view addSubview:motionCard];

    [view addSubview:makeSectionLabel(@"MOTION", 18, 348, 500)];

    self.animationsSwitch =
        makeToggle(@"Fluid Animations", 2, self, @selector(switchChanged:), 18, 373, 300);
    [view addSubview:self.animationsSwitch];
    [view addSubview:makeRowSubtitle(
        @"Animate resizing, title movement, and mascot reactions.",
        43, 397, 470
    )];

    self.dimSwitch =
        makeToggle(@"Dim Artwork When Paused", 3, self, @selector(switchChanged:), 18, 421, 300);
    [view addSubview:self.dimSwitch];
    [view addSubview:makeRowSubtitle(
        @"Lower artwork brightness while playback is paused.",
        43, 445, 470
    )];

    NSTextField *frameLabel =
        makeTextLabel(@"Glass Border", 18, 477, 120, 12, NSFontWeightMedium, [NSColor labelColor]);
    [view addSubview:frameLabel];

    self.frameSegment =
        makeSegments(@[@"Off", @"Subtle", @"Strong"], 10, self, @selector(segmentChanged:), 165, 471, 250);
    [view addSubview:self.frameSegment];

    NSTextField *speedLabel =
        makeTextLabel(@"Animation Speed", 18, 519, 130, 12, NSFontWeightMedium, [NSColor labelColor]);
    [view addSubview:speedLabel];

    self.speedSegment =
        makeSegments(@[@"Slow", @"Normal", @"Fast"], 12, self, @selector(segmentChanged:), 165, 513, 250);
    [view addSubview:self.speedSegment];

    self.compactGradientSwitch =
        makeToggle(@"Compact Contrast Gradient", 20, self, @selector(switchChanged:), 18, 552, 290);
    [view addSubview:self.compactGradientSwitch];
    [view addSubview:makeRowSubtitle(
        @"Adds a dark fade under compact-mode track text.",
        43, 576, 470
    )];
}

- (void)buildPlaybackPage:(WallifyFlippedView *)view {
    NSBox *layoutCard = makeCard(0, 0, 550, 190);
    [view addSubview:layoutCard];

    [view addSubview:makeSectionLabel(@"WIDGET", 18, 18, 500)];

    NSTextField *modeLabel =
        makeTextLabel(@"Form Factor", 18, 45, 120, 12, NSFontWeightMedium, [NSColor labelColor]);
    [view addSubview:modeLabel];

    self.modeSegment =
        makeSegments(@[@"1 × 1", @"2 × 1", @"3 × 1", @"1 × 2", @"2 × 2"], 14, self, @selector(segmentChanged:), 148, 39, 365);
    [view addSubview:self.modeSegment];

    [view addSubview:makeRowSubtitle(
        @"Choose the desktop tile footprint used by Wallify.",
        18, 72, 500
    )];

    NSTextField *sourceLabel =
        makeTextLabel(@"Media Source", 18, 108, 120, 12, NSFontWeightMedium, [NSColor labelColor]);
    [view addSubview:sourceLabel];

    self.sourceSegment =
        makeSegments(@[@"Now Playing", @"Spotify", @"Spotifast", @"Auto"], 13, self, @selector(segmentChanged:), 148, 102, 365);
    [view addSubview:self.sourceSegment];

    NSBox *idleCard = makeCard(0, 204, 550, 195);
    [view addSubview:idleCard];

    [view addSubview:makeSectionLabel(@"IDLE & TRANSITIONS", 18, 222, 500)];

    NSTextField *idleLabel =
        makeTextLabel(@"Idle Companion", 18, 249, 120, 12, NSFontWeightMedium, [NSColor labelColor]);
    [view addSubview:idleLabel];

    self.idleSegment =
        makeSegments(@[@"Pixel Cat", @"Banana Cat", @"Spotify"], 15, self, @selector(segmentChanged:), 148, 243, 365);
    [view addSubview:self.idleSegment];

    [view addSubview:makeRowSubtitle(
        @"Shown when no track is playing. Click the cat to interact with it.",
        18, 275, 500
    )];

    NSTextField *transitionLabel =
        makeTextLabel(@"Track Transition", 18, 310, 120, 12, NSFontWeightMedium, [NSColor labelColor]);
    [view addSubview:transitionLabel];

    self.transitionPopup =
        [[NSPopUpButton alloc] initWithFrame:NSMakeRect(148, 304, 365, 28) pullsDown:NO];
    self.transitionPopup.target = self;
    self.transitionPopup.action = @selector(transitionChanged:);
    [self.transitionPopup addItemsWithTitles:@[
        @"Default • Smooth Crossfade",
        @"Cinematic • Zoom & Push",
        @"Liquid Ripple",
        @"3D Card Flip",
        @"Vinyl Spin",
        @"Cyber Glitch"
    ]];
    [view addSubview:self.transitionPopup];

    [view addSubview:makeRowSubtitle(
        @"GPU transition played when the artwork changes.",
        18, 339, 500
    )];

    NSBox *visibilityCard = makeCard(0, 413, 550, 310);
    [view addSubview:visibilityCard];

    [view addSubview:makeSectionLabel(@"VISIBILITY & TYPOGRAPHY", 18, 431, 500)];

    self.hideTextSwitch =
        makeToggle(@"Hide Track Text", 6, self, @selector(switchChanged:), 18, 459, 220);
    [view addSubview:self.hideTextSwitch];

    self.hideProgressSwitch =
        makeToggle(@"Hide Progress Bar", 7, self, @selector(switchChanged:), 280, 459, 220);
    [view addSubview:self.hideProgressSwitch];

    self.showControlsSwitch =
        makeToggle(@"Show Playback Controls", 8, self, @selector(switchChanged:), 18, 505, 230);
    [view addSubview:self.showControlsSwitch];

    self.showTimestampsSwitch =
        makeToggle(@"Show Time Labels", 9, self, @selector(switchChanged:), 280, 505, 220);
    [view addSubview:self.showTimestampsSwitch];

    [view addSubview:makeRowSubtitle(
        @"Choose which playback controls and time information remain visible.",
        43, 529, 470
    )];

    NSTextField *fontLabel =
        makeTextLabel(@"Font Size", 18, 565, 90, 12, NSFontWeightMedium, [NSColor labelColor]);
    [view addSubview:fontLabel];

    self.fontScaleSegment =
        makeSegments(@[@"Small", @"Normal", @"Large"], 17, self, @selector(segmentChanged:), 148, 559, 250);
    [view addSubview:self.fontScaleSegment];

    NSTextField *thicknessLabel =
        makeTextLabel(@"Progress Thickness", 18, 606, 130, 12, NSFontWeightMedium, [NSColor labelColor]);
    [view addSubview:thicknessLabel];

    self.progressThicknessSegment =
        makeSegments(@[@"Thin", @"Standard", @"Thick"], 22, self, @selector(segmentChanged:), 148, 600, 250);
    [view addSubview:self.progressThicknessSegment];

    NSBox *keysCard = makeCard(0, 738, 550, 150);
    [view addSubview:keysCard];

    [view addSubview:makeSectionLabel(@"MEDIA KEY REDIRECT", 18, 630, 500)];
    [view addSubview:makeRowSubtitle(
        @"Route F7 / F8 / F9 through Wallify instead of the system media handler.",
        18, 654, 500
    )];

    self.mediaKeySegment =
        makeSegments(@[@"Off", @"Active", @"Spotify", @"Spotifast"], 18, self, @selector(segmentChanged:), 18, 811, 430);
    [view addSubview:self.mediaKeySegment];

    [view addSubview:makeRowSubtitle(
        @"Accessibility permission is required to intercept hardware media keys.",
        18, 846, 500
    )];
}

- (void)buildDesktopPage:(WallifyFlippedView *)view {
    NSBox *positionCard = makeCard(0, 0, 550, 190);
    [view addSubview:positionCard];

    [view addSubview:makeSectionLabel(@"DESKTOP PLACEMENT", 18, 18, 500)];

    NSTextField *positionTitle =
        makeTextLabel(@"Current Position", 18, 46, 500, 13, NSFontWeightMedium, [NSColor labelColor]);
    [view addSubview:positionTitle];

    self.gridStatusLabel =
        makeTextLabel(@"Margin: checking…", 18, 72, 500, 12, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    [view addSubview:self.gridStatusLabel];

    [view addSubview:makeRowSubtitle(
        @"Drag the widget directly on the desktop, or reset it to the default slot.",
        18, 99, 500
    )];

    NSButton *resetPosition =
        makeActionButton(
            @"Reset Position",
            self,
            @selector(resetPositionClicked:),
            18,
            132,
            130
        );
    [view addSubview:resetPosition];

    NSBox *debugCard = makeCard(0, 204, 550, 140);
    [view addSubview:debugCard];

    [view addSubview:makeSectionLabel(@"DIAGNOSTICS", 18, 222, 500)];

    self.debugSwitch =
        makeToggle(@"Snapping Diagnostics HUD", 4, self, @selector(switchChanged:), 18, 248, 300);
    [view addSubview:self.debugSwitch];

    [view addSubview:makeRowSubtitle(
        @"Shows WindowServer coordinates, snap candidates, and live metrics.",
        43, 272, 470
    )];

    NSBox *fileCard = makeCard(0, 358, 550, 168);
    [view addSubview:fileCard];

    [view addSubview:makeSectionLabel(@"CONFIGURATION", 18, 376, 500)];

    NSString *confPath =
        [NSString stringWithUTF8String:wallify_settings_path()];

    NSTextField *pathLabel =
        makeTextLabel(
            confPath,
            18,
            402,
            500,
            10,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        );
    pathLabel.font = [NSFont monospacedSystemFontOfSize:10 weight:NSFontWeightRegular];
    pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [view addSubview:pathLabel];

    [view addSubview:makeActionButton(
        @"Reveal in Finder",
        self,
        @selector(revealConfigClicked:),
        18,
        445,
        130
    )];

    [view addSubview:makeActionButton(
        @"Open File",
        self,
        @selector(openConfigClicked:),
        158,
        445,
        110
    )];

    NSBox *aboutCard = makeCard(0, 540, 550, 170);
    [view addSubview:aboutCard];

    [view addSubview:makeSectionLabel(@"ABOUT", 18, 558, 500)];

    NSTextField *aboutTitle =
        makeTextLabel(@"Wallify", 18, 585, 500, 18, NSFontWeightBold, [NSColor labelColor]);
    [view addSubview:aboutTitle];

    [view addSubview:makeRowSubtitle(
        @"Native Metal 3 rendering with AppKit glass on macOS.",
        18, 614, 500
    )];

    [view addSubview:makeRowSubtitle(
        @"No runtime dependencies • Hardware accelerated.",
        18, 635, 500
    )];
}

#pragma mark Sidebar

- (void)sidebarButtonClicked:(NSButton *)sender {
    [self selectPage:sender.tag];
}

- (void)selectPage:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.pages.count) return;

    for (NSButton *button in self.sidebarButtons) {
        BOOL selected = button.tag == index;

        button.layer.backgroundColor =
            selected
                ? [NSColor selectedContentBackgroundColor].CGColor
                : NSColor.clearColor.CGColor;

        button.contentTintColor =
            selected
                ? [NSColor selectedControlTextColor]
                : [NSColor secondaryLabelColor];
    }

    NSArray<NSString *> *titles = @[@"Appearance", @"Playback", @"Desktop"];
    NSArray<NSString *> *subtitles = @[
        @"Control the glass, glow, colors, and animation behavior of your widget.",
        @"Choose playback sources, transitions, idle behavior, visibility, and media keys.",
        @"Manage desktop placement, diagnostics, and the Wallify configuration file."
    ];

    self.pageTitleLabel.stringValue = titles[index];
    self.pageSubtitleLabel.stringValue = subtitles[index];

    for (NSView *page in self.pages) {
        [page removeFromSuperview];
    }

    NSView *page = self.pages[index];

    CGFloat documentHeight = MAX(page.frame.size.height, self.scrollView.contentView.bounds.size.height);

    page.frame = NSMakeRect(
        16,
        0,
        self.scrollView.contentSize.width - 32,
        documentHeight
    );

    [self.scrollView.documentView removeFromSuperview];
    self.scrollView.documentView = page;
    [self.scrollView.contentView scrollToPoint:NSMakePoint(0, 0)];
}

#pragma mark Actions

- (void)switchChanged:(NSButton *)sender {
    BOOL value = sender.state == NSControlStateValueOn;
    wallify_settings_apply_bool((int)sender.tag, value);
}

- (void)segmentChanged:(NSSegmentedControl *)sender {
    wallify_settings_apply_int((int)sender.tag, (int)sender.selectedSegment);
}

- (void)transitionChanged:(NSPopUpButton *)sender {
    wallify_settings_apply_int(16, (int)sender.indexOfSelectedItem);
}

- (void)resetPositionClicked:(id)sender {
    wallify_settings_reset_position();
    [self updateGridStatusLabel];
}

- (void)restoreDefaultsClicked:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Restore Default Settings?";
    alert.informativeText =
        @"Appearance, playback, visibility, and animation preferences will be reset.";
    [alert addButtonWithTitle:@"Restore Defaults"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        wallify_settings_restore_defaults();
        [self refreshUIFromState];
    }
}

- (void)revealConfigClicked:(id)sender {
    NSString *path =
        [NSString stringWithUTF8String:wallify_settings_path()];
    [[NSWorkspace sharedWorkspace]
        selectFile:path
        inFileViewerRootedAtPath:@""];
}

- (void)openConfigClicked:(id)sender {
    NSString *path =
        [NSString stringWithUTF8String:wallify_settings_path()];
    [[NSWorkspace sharedWorkspace]
        openURL:[NSURL fileURLWithPath:path]];
}

- (void)doneClicked:(id)sender {
    [self closeSettingsWindow];
}

#pragma mark State

- (void)updateGridStatusLabel {
    WallifySettingsSnapshot snapshot;
    wallify_settings_get_snapshot(&snapshot);

    self.gridStatusLabel.stringValue =
        [NSString stringWithFormat:
            @"Left %d pt   •   Top %d pt   •   Grid %d, %d",
            snapshot.margin_left,
            snapshot.margin_top,
            snapshot.grid_x,
            snapshot.grid_y];
}

- (void)refreshUIFromState {
    WallifySettingsSnapshot s;
    wallify_settings_get_snapshot(&s);

    self.nativeGlassSwitch.state =
        s.native_glass ? NSControlStateValueOn : NSControlStateValueOff;

    // Native Glass supplies its own material/rim, so the GPU-only Aurora
    // layer and custom frame have no visual effect while it is enabled.
    self.auroraSwitch.enabled = !s.native_glass;
    self.frameSegment.enabled = !s.native_glass;
    self.glowSwitch.state =
        s.glow ? NSControlStateValueOn : NSControlStateValueOff;
    self.auroraSwitch.state =
        s.aurora ? NSControlStateValueOn : NSControlStateValueOff;
    self.animationsSwitch.state =
        s.animations ? NSControlStateValueOn : NSControlStateValueOff;
    self.dimSwitch.state =
        s.dim_paused ? NSControlStateValueOn : NSControlStateValueOff;
    self.debugSwitch.state =
        s.debug_hud ? NSControlStateValueOn : NSControlStateValueOff;

    self.hideTextSwitch.state =
        s.hide_text ? NSControlStateValueOn : NSControlStateValueOff;
    self.hideProgressSwitch.state =
        s.hide_progress ? NSControlStateValueOn : NSControlStateValueOff;
    self.showControlsSwitch.state =
        s.show_controls ? NSControlStateValueOn : NSControlStateValueOff;
    self.showTimestampsSwitch.state =
        s.show_timestamps ? NSControlStateValueOn : NSControlStateValueOff;
    self.artworkBorderSwitch.state =
        s.artwork_border ? NSControlStateValueOn : NSControlStateValueOff;
    self.compactGradientSwitch.state =
        s.compact_gradient ? NSControlStateValueOn : NSControlStateValueOff;

    self.artworkRadiusSegment.selectedSegment =
        (s.artwork_radius >= 0 && s.artwork_radius <= 2)
            ? s.artwork_radius
            : 1;

    self.progressThicknessSegment.selectedSegment =
        (s.progress_thickness >= 0 && s.progress_thickness <= 2)
            ? s.progress_thickness
            : 1;

    self.frameSegment.selectedSegment =
        (s.frame_strength >= 0 && s.frame_strength <= 2)
            ? s.frame_strength
            : 1;

    self.intensitySegment.selectedSegment =
        (s.glow_intensity >= 0 && s.glow_intensity <= 2)
            ? s.glow_intensity
            : 1;

    self.speedSegment.selectedSegment =
        (s.animation_speed >= 0 && s.animation_speed <= 2)
            ? s.animation_speed
            : 1;

    self.modeSegment.selectedSegment =
        (s.widget_mode >= 0 && s.widget_mode <= 4)
            ? s.widget_mode
            : 2;

    self.sourceSegment.selectedSegment =
        (s.media_source >= 0 && s.media_source <= 3)
            ? s.media_source
            : 0;

    self.idleSegment.selectedSegment =
        (s.idle_style >= 0 && s.idle_style <= 2)
            ? s.idle_style
            : 0;

    self.fontScaleSegment.selectedSegment =
        (s.font_scale >= 0 && s.font_scale <= 2)
            ? s.font_scale
            : 1;

    self.mediaKeySegment.selectedSegment =
        (s.media_key_target >= 0 && s.media_key_target <= 3)
            ? s.media_key_target
            : 0;

    if (s.track_transition >= 0 &&
        s.track_transition < self.transitionPopup.numberOfItems) {
        [self.transitionPopup
            selectItemAtIndex:s.track_transition];
    }

    [self updateGridStatusLabel];
}

#pragma mark Presentation

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
    (void)notification;
}

@end

void wallify_show_settings_window(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[WallifySettingsWindowController sharedController]
            showSettingsWindow];
    });
}

void wallify_close_settings_window(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[WallifySettingsWindowController sharedController]
            closeSettingsWindow];
    });
}

void wallify_settings_notify_position_changed(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[WallifySettingsWindowController sharedController]
            updateGridStatusLabel];
    });
}

bool wallify_has_settings_flag(void) {
    NSArray *args = [[NSProcessInfo processInfo] arguments];

    for (NSString *arg in args) {
        if ([arg isEqualToString:@"--settings"] ||
            [arg isEqualToString:@"-s"]) {
            return true;
        }
    }

    return false;
}

void wallify_refresh_settings_ui(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sharedSettingsController &&
            sharedSettingsController.window.isVisible) {
            [sharedSettingsController refreshUIFromState];
        }
    });
}
