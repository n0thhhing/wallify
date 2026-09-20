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
@property (nonatomic, strong) NSImageView *pageIconView;
@property (nonatomic, strong) NSTextField *applyLabel;

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

static NSTextField *makeLabel(
    NSString *text,
    CGFloat x,
    CGFloat y,
    CGFloat w,
    CGFloat h,
    CGFloat fontSize,
    NSFontWeight weight,
    NSColor *color
) {
    NSTextField *label =
        [[NSTextField alloc]
            initWithFrame:NSMakeRect(x, y, w, h)];

    label.stringValue = text;
    label.font = [NSFont systemFontOfSize:fontSize weight:weight];
    label.textColor = color;
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.selectable = NO;
    label.usesSingleLineMode = NO;
    label.lineBreakMode = NSLineBreakByTruncatingTail;

    return label;
}

static NSTextField *makeTitleLabel(NSString *text, CGFloat x, CGFloat y, CGFloat w) {
    return makeLabel(
        text,
        x,
        y,
        w,
        34,
        27,
        NSFontWeightBold,
        [NSColor labelColor]
    );
}

static NSTextField *makeSubtitleLabel(NSString *text, CGFloat x, CGFloat y, CGFloat w) {
    NSTextField *label =
        makeLabel(
            text,
            x,
            y,
            w,
            40,
            13,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        );

    label.lineBreakMode = NSLineBreakByWordWrapping;
    return label;
}

static NSTextField *makeGroupTitle(NSString *text, CGFloat x, CGFloat y, CGFloat w) {
    return makeLabel(
        text.uppercaseString,
        x,
        y,
        w,
        20,
        11,
        NSFontWeightSemibold,
        [NSColor tertiaryLabelColor]
    );
}

static NSBox *makeGroup(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    NSBox *group =
        [[NSBox alloc]
            initWithFrame:NSMakeRect(x, y, w, h)];

    group.boxType = NSBoxCustom;
    group.transparent = NO;
    group.borderWidth = 0;
    group.cornerRadius = 14;
    group.fillColor =
        [[NSColor controlBackgroundColor]
            colorWithAlphaComponent:0.48];

    return group;
}

static void addSeparator(NSView *parent, CGFloat x, CGFloat y, CGFloat w) {
    NSBox *separator =
        [[NSBox alloc]
            initWithFrame:NSMakeRect(x, y, w, 1)];

    separator.boxType = NSBoxSeparator;
    [parent addSubview:separator];
}

static NSButton *makeToggle(
    NSString *title,
    int tag,
    id target,
    SEL action
) {
    NSButton *button =
        [NSButton buttonWithTitle:title
                           target:target
                           action:action];

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
    SEL action
) {
    NSSegmentedControl *control =
        [NSSegmentedControl segmentedControlWithLabels:items
                                           trackingMode:NSSegmentSwitchTrackingSelectOne
                                                 target:target
                                                 action:action];

    control.tag = tag;
    control.segmentDistribution = NSSegmentDistributionFillEqually;
    control.controlSize = NSControlSizeRegular;

    return control;
}

static NSSegmentedControl *makeCompactSegments(
    NSArray<NSString *> *items,
    int tag,
    id target,
    SEL action
) {
    NSSegmentedControl *control =
        makeSegments(items, tag, target, action);

    control.controlSize = NSControlSizeSmall;
    return control;
}

static NSButton *makeActionButton(
    NSString *title,
    id target,
    SEL action
) {
    NSButton *button =
        [NSButton buttonWithTitle:title
                           target:target
                           action:action];

    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];

    return button;
}

static void addSettingRow(
    NSView *parent,
    NSString *title,
    NSString *subtitle,
    NSControl *control,
    CGFloat y,
    CGFloat width,
    BOOL separator
) {
    const CGFloat left = 20.0;
    const CGFloat controlWidth = 290.0;
    const CGFloat right = width - 20.0;

    NSTextField *titleLabel =
        makeLabel(
            title,
            left,
            y + 10,
            right - controlWidth - 18.0,
            20,
            13,
            NSFontWeightMedium,
            [NSColor labelColor]
        );

    [parent addSubview:titleLabel];

    if (subtitle.length > 0) {
        NSTextField *subtitleLabel =
            makeLabel(
                subtitle,
                left,
                y + 31,
                right - controlWidth - 18.0,
                24,
                11,
                NSFontWeightRegular,
                [NSColor secondaryLabelColor]
            );

        subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [parent addSubview:subtitleLabel];
    }

    NSRect frame = control.frame;
    frame.origin.x = right - controlWidth;
    frame.origin.y = y + 15;
    frame.size.width = controlWidth;
    frame.size.height = 26;

    if ([control isKindOfClass:[NSButton class]]) {
        frame.size.width = 300.0;
        frame.origin.x = right - 300.0;
        frame.size.height = 24;
        frame.origin.y = y + 11;
    }

    control.frame = frame;
    [parent addSubview:control];

    if (separator) {
        addSeparator(parent, left, y + 69, width - 40.0);
    }
}

static void addCenteredControlRow(
    NSView *parent,
    NSString *title,
    NSString *subtitle,
    NSControl *control,
    CGFloat y,
    CGFloat width,
    BOOL separator
) {
    const CGFloat left = 20.0;
    const CGFloat right = width - 20.0;
    const CGFloat controlWidth = 340.0;

    [parent addSubview:
        makeLabel(
            title,
            left,
            y + 9,
            180,
            20,
            13,
            NSFontWeightMedium,
            [NSColor labelColor]
        )];

    [parent addSubview:
        makeLabel(
            subtitle,
            left,
            y + 31,
            300,
            24,
            11,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        )];

    NSRect frame = NSMakeRect(
        right - controlWidth,
        y + 14,
        controlWidth,
        28
    );

    control.frame = frame;
    [parent addSubview:control];

    if (separator) {
        addSeparator(
            parent,
            left,
            y + 69,
            width - 40.0
        );
    }
}

#pragma mark - Controller

@implementation WallifySettingsWindowController

+ (instancetype)sharedController {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedSettingsController =
            [[WallifySettingsWindowController alloc] init];
    });

    return sharedSettingsController;
}

#pragma mark - Window

- (void)createWindow {
    const CGFloat windowWidth = 920.0;
    const CGFloat windowHeight = 680.0;
    const CGFloat sidebarWidth = 220.0;
    const CGFloat footerHeight = 64.0;

    NSRect frame =
        NSMakeRect(
            0,
            0,
            windowWidth,
            windowHeight
        );

    self.window =
        [[NSWindow alloc]
            initWithContentRect:frame
                      styleMask:
                          NSWindowStyleMaskTitled |
                          NSWindowStyleMaskClosable |
                          NSWindowStyleMaskMiniaturizable
                        backing:NSBackingStoreBuffered
                          defer:NO];

    self.window.title = @"Wallify Settings";
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    self.window.tabbingMode = NSWindowTabbingModeDisallowed;
    self.window.restorable = NO;
    self.window.minSize = NSMakeSize(820.0, 600.0);
    self.window.collectionBehavior |=
        NSWindowCollectionBehaviorFullScreenAuxiliary;

    self.rootView =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(
                    0,
                    0,
                    windowWidth,
                    windowHeight
                )];

    self.rootView.autoresizingMask =
        NSViewWidthSizable |
        NSViewHeightSizable;

    self.rootView.material =
        NSVisualEffectMaterialUnderWindowBackground;

    self.rootView.blendingMode =
        NSVisualEffectBlendingModeWithinWindow;

    self.rootView.state =
        NSVisualEffectStateActive;

    self.window.contentView = self.rootView;

    [self buildSidebar:sidebarWidth];
    [self buildMainContent:sidebarWidth footerHeight:footerHeight];

    [self buildFooter:
        sidebarWidth
        footerHeight:footerHeight
        windowHeight:windowHeight
        windowWidth:windowWidth];

    [self buildPages];

    [self selectPage:0];
}

#pragma mark - Sidebar

- (void)buildSidebar:(CGFloat)sidebarWidth {
    self.sidebarView =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(
                    0,
                    0,
                    sidebarWidth,
                    680
                )];

    self.sidebarView.autoresizingMask =
        NSViewHeightSizable;

    self.sidebarView.material =
        NSVisualEffectMaterialSidebar;

    self.sidebarView.blendingMode =
        NSVisualEffectBlendingModeWithinWindow;

    self.sidebarView.state =
        NSVisualEffectStateActive;

    [self.rootView addSubview:self.sidebarView];

    NSImageView *logo =
        [[NSImageView alloc]
            initWithFrame:
                NSMakeRect(
                    22,
                    22,
                    34,
                    34
                )];

    logo.image =
        [NSImage imageWithSystemSymbolName:
            @"music.note"
            accessibilityDescription:@"Wallify"];

    logo.symbolConfiguration =
        [NSImageSymbolConfiguration
            configurationWithPointSize:20
            weight:NSFontWeightSemibold];

    logo.contentTintColor =
        [NSColor controlAccentColor];

    [self.sidebarView addSubview:logo];

    [self.sidebarView addSubview:
        makeLabel(
            @"Wallify",
            68,
            18,
            130,
            26,
            16,
            NSFontWeightSemibold,
            [NSColor labelColor]
        )];

    [self.sidebarView addSubview:
        makeLabel(
            @"Settings",
            68,
            41,
            130,
            18,
            11,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        )];

    addSeparator(
        self.sidebarView,
        18,
        79,
        sidebarWidth - 36
    );

    NSArray<NSDictionary *> *items = @[
        @{
            @"title": @"Appearance",
            @"subtitle": @"Material & visuals",
            @"symbol": @"paintpalette.fill"
        },
        @{
            @"title": @"Playback",
            @"subtitle": @"Sources & controls",
            @"symbol": @"play.circle.fill"
        },
        @{
            @"title": @"Desktop",
            @"subtitle": @"Placement & diagnostics",
            @"symbol": @"rectangle.on.rectangle"
        }
    ];

    NSMutableArray<NSButton *> *buttons =
        [NSMutableArray arrayWithCapacity:items.count];

    CGFloat y = 98.0;

    for (NSDictionary *item in items) {
        NSButton *button =
            [NSButton buttonWithTitle:item[@"title"]
                               target:self
                               action:@selector(sidebarButtonClicked:)];

        button.tag = (NSInteger)buttons.count;
        button.bordered = NO;
        button.alignment = NSTextAlignmentLeft;
        button.image =
            [NSImage imageWithSystemSymbolName:
                item[@"symbol"]
                accessibilityDescription:nil];

        button.imagePosition = NSImageLeft;
        button.imageScaling = NSImageScaleProportionallyDown;
        button.font =
            [NSFont systemFontOfSize:13
                              weight:NSFontWeightMedium];

        button.contentTintColor =
            [NSColor secondaryLabelColor];

        button.frame =
            NSMakeRect(
                12,
                y,
                sidebarWidth - 24,
                46
            );

        button.wantsLayer = YES;
        button.layer.cornerRadius = 10.0;

        /*
         * Give the selected state a clean macOS-style pill.
         */
        button.layer.masksToBounds = YES;

        [self.sidebarView addSubview:button];
        [buttons addObject:button];

        y += 54.0;
    }

    self.sidebarButtons = buttons;

    addSeparator(
        self.sidebarView,
        18,
        520,
        sidebarWidth - 36
    );

    [self.sidebarView addSubview:
        makeLabel(
            @"WALLIFY",
            22,
            545,
            170,
            16,
            10,
            NSFontWeightSemibold,
            [NSColor tertiaryLabelColor]
        )];

    [self.sidebarView addSubview:
        makeLabel(
            @"Native Metal • AppKit Glass",
            22,
            566,
            175,
            18,
            11,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        )];

    [self.sidebarView addSubview:
        makeLabel(
            @"Changes apply immediately",
            22,
            594,
            175,
            18,
            10,
            NSFontWeightRegular,
            [NSColor tertiaryLabelColor]
        )];
}

#pragma mark - Main

- (void)buildMainContent:(CGFloat)sidebarWidth
           footerHeight:(CGFloat)footerHeight {
    CGFloat width = 920.0 - sidebarWidth;

    self.contentView =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(
                    sidebarWidth,
                    0,
                    width,
                    680.0 - footerHeight
                )];

    self.contentView.autoresizingMask =
        NSViewWidthSizable |
        NSViewHeightSizable;

    self.contentView.material =
        NSVisualEffectMaterialUnderPageBackground;

    self.contentView.blendingMode =
        NSVisualEffectBlendingModeWithinWindow;

    self.contentView.state =
        NSVisualEffectStateActive;

    [self.rootView addSubview:self.contentView];

    self.pageIconView =
        [[NSImageView alloc]
            initWithFrame:
                NSMakeRect(
                    30,
                    25,
                    30,
                    30
                )];

    self.pageIconView.symbolConfiguration =
        [NSImageSymbolConfiguration
            configurationWithPointSize:18
            weight:NSFontWeightMedium];

    self.pageIconView.contentTintColor =
        [NSColor controlAccentColor];

    [self.contentView addSubview:self.pageIconView];

    self.pageTitleLabel =
        makeTitleLabel(
            @"Appearance",
            70,
            20,
            width - 110
        );

    [self.contentView addSubview:self.pageTitleLabel];

    self.pageSubtitleLabel =
        makeSubtitleLabel(
            @"Control the look and behavior of the widget.",
            70,
            55,
            width - 110
        );

    [self.contentView addSubview:self.pageSubtitleLabel];

    self.applyLabel =
        makeLabel(
            @"",
            width - 215,
            27,
            175,
            20,
            10,
            NSFontWeightMedium,
            [NSColor tertiaryLabelColor]
        );

    self.applyLabel.alignment = NSTextAlignmentRight;
    [self.contentView addSubview:self.applyLabel];

    self.scrollView =
        [[NSScrollView alloc]
            initWithFrame:
                NSMakeRect(
                    18,
                    104,
                    width - 36,
                    492
                )];

    self.scrollView.autoresizingMask =
        NSViewWidthSizable |
        NSViewHeightSizable;

    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.drawsBackground = NO;
    self.scrollView.scrollerStyle = NSScrollerStyleOverlay;

    [self.contentView addSubview:self.scrollView];
}

- (void)buildFooter:
    (CGFloat)sidebarWidth
    footerHeight:(CGFloat)footerHeight
    windowHeight:(CGFloat)windowHeight
    windowWidth:(CGFloat)windowWidth {

    CGFloat contentWidth = windowWidth - sidebarWidth;

    NSView *footer =
        [[NSView alloc]
            initWithFrame:
                NSMakeRect(
                    sidebarWidth,
                    680.0 - footerHeight,
                    contentWidth,
                    footerHeight
                )];

    footer.autoresizingMask =
        NSViewWidthSizable |
        NSViewMinYMargin;

    [self.rootView addSubview:footer];

    addSeparator(
        footer,
        0,
        0,
        contentWidth
    );

    NSButton *defaults =
        makeActionButton(
            @"Restore Defaults",
            self,
            @selector(restoreDefaultsClicked:)
        );

    defaults.frame =
        NSMakeRect(
            24,
            18,
            126,
            28
        );

    [footer addSubview:defaults];

    NSButton *done =
        [NSButton buttonWithTitle:@"Done"
                           target:self
                           action:@selector(doneClicked:)];

    done.frame =
        NSMakeRect(
            contentWidth - 104,
            17,
            80,
            30
        );

    done.bezelStyle =
        NSBezelStyleRounded;

    done.font =
        [NSFont systemFontOfSize:12
                          weight:NSFontWeightSemibold];

    done.keyEquivalent = @"\r";

    [footer addSubview:done];
}

#pragma mark - Pages

- (void)buildPages {
    CGFloat pageWidth = 650.0;

    WallifyFlippedView *appearance =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(
                    0,
                    0,
                    pageWidth,
                    930
                )];

    [self buildAppearancePage:appearance];

    WallifyFlippedView *playback =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(
                    0,
                    0,
                    pageWidth,
                    1160
                )];

    [self buildPlaybackPage:playback];

    WallifyFlippedView *desktop =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(
                    0,
                    0,
                    pageWidth,
                    820
                )];

    [self buildDesktopPage:desktop];

    self.pages = @[
        appearance,
        playback,
        desktop
    ];
}

#pragma mark Appearance page

- (void)buildAppearancePage:(WallifyFlippedView *)view {
    const CGFloat width = 650.0;

    [view addSubview:
        makeGroupTitle(
            @"Material",
            6,
            0,
            width - 12
        )];

    NSBox *material =
        makeGroup(
            0,
            24,
            width,
            309
        );

    [view addSubview:material];

    addSettingRow(
        material,
        @"Native Glass",
        @"Use the macOS Liquid Glass material.",
        self.nativeGlassSwitch =
            makeToggle(
                @"",
                5,
                self,
                @selector(switchChanged:)
            ),
        0,
        width,
        YES
    );

    addSettingRow(
        material,
        @"Artwork Glow",
        @"Ambient color pulled from the current artwork.",
        self.glowSwitch =
            makeToggle(
                @"",
                0,
                self,
                @selector(switchChanged:)
            ),
        70,
        width,
        YES
    );

    addCenteredControlRow(
        material,
        @"Glow Intensity",
        @"Controls the strength of the artwork glow.",
        self.intensitySegment =
            makeCompactSegments(
                @[@"Low", @"Normal", @"High"],
                11,
                self,
                @selector(segmentChanged:)
            ),
        140,
        width,
        YES
    );

    addSettingRow(
        material,
        @"Aurora Background",
        @"Animated color field behind the custom material.",
        self.auroraSwitch =
            makeToggle(
                @"",
                1,
                self,
                @selector(switchChanged:)
            ),
        210,
        width,
        YES
    );

    addCenteredControlRow(
        material,
        @"Glass Border",
        @"Custom border used by the non-native material.",
        self.frameSegment =
            makeCompactSegments(
                @[@"Off", @"Subtle", @"Strong"],
                10,
                self,
                @selector(segmentChanged:)
            ),
        280 - 12,
        width,
        NO
    );

    [view addSubview:
        makeGroupTitle(
            @"Artwork",
            6,
            347,
            width - 12
        )];

    NSBox *artwork =
        makeGroup(
            0,
            371,
            width,
            239
        );

    [view addSubview:artwork];

    addSettingRow(
        artwork,
        @"Artwork Border",
        @"Add a fine highlight around the album art.",
        self.artworkBorderSwitch =
            makeToggle(
                @"",
                19,
                self,
                @selector(switchChanged:)
            ),
        0,
        width,
        YES
    );

    addCenteredControlRow(
        artwork,
        @"Artwork Corners",
        @"Choose how strongly the artwork is rounded.",
        self.artworkRadiusSegment =
            makeCompactSegments(
                @[@"Soft", @"Rounded", @"Large"],
                21,
                self,
                @selector(segmentChanged:)
            ),
        70,
        width,
        YES
    );

    addSettingRow(
        artwork,
        @"Compact Contrast",
        @"Adds a dark fade behind text in 1 × 1 mode.",
        self.compactGradientSwitch =
            makeToggle(
                @"",
                20,
                self,
                @selector(switchChanged:)
            ),
        140,
        width,
        NO
    );

    [view addSubview:
        makeGroupTitle(
            @"Motion",
            6,
            622,
            width - 12
        )];

    NSBox *motion =
        makeGroup(
            0,
            646,
            width,
            239
        );

    [view addSubview:motion];

    addSettingRow(
        motion,
        @"Animations",
        @"Animate artwork, resizing, and state changes.",
        self.animationsSwitch =
            makeToggle(
                @"",
                2,
                self,
                @selector(switchChanged:)
            ),
        0,
        width,
        YES
    );

    addCenteredControlRow(
        motion,
        @"Animation Speed",
        @"Control how quickly transitions play.",
        self.speedSegment =
            makeCompactSegments(
                @[@"Slow", @"Normal", @"Fast"],
                12,
                self,
                @selector(segmentChanged:)
            ),
        70,
        width,
        YES
    );

    addSettingRow(
        motion,
        @"Dim When Paused",
        @"Lower artwork brightness while playback is paused.",
        self.dimSwitch =
            makeToggle(
                @"",
                3,
                self,
                @selector(switchChanged:)
            ),
        140,
        width,
        NO
    );
}

#pragma mark Playback page

- (void)buildPlaybackPage:(WallifyFlippedView *)view {
    const CGFloat width = 650.0;

    [view addSubview:
        makeGroupTitle(
            @"Widget",
            6,
            0,
            width - 12
        )];

    NSBox *widget =
        makeGroup(
            0,
            24,
            width,
            179
        );

    [view addSubview:widget];

    addCenteredControlRow(
        widget,
        @"Form Factor",
        @"Choose the desktop footprint.",
        self.modeSegment =
            makeSegments(
                @[@"1 × 1", @"2 × 1", @"3 × 1", @"1 × 2", @"2 × 2"],
                14,
                self,
                @selector(segmentChanged:)
            ),
        5,
        width,
        YES
    );

    addCenteredControlRow(
        widget,
        @"Media Source",
        @"Choose where playback state comes from.",
        self.sourceSegment =
            makeCompactSegments(
                @[@"Now Playing", @"Spotify", @"Spotifast", @"Auto"],
                13,
                self,
                @selector(segmentChanged:)
            ),
        75,
        width,
        NO
    );

    [view addSubview:
        makeGroupTitle(
            @"Idle & Transitions",
            6,
            226,
            width - 12
        )];

    NSBox *transitions =
        makeGroup(
            0,
            250,
            width,
            249
        );

    [view addSubview:transitions];

    addCenteredControlRow(
        transitions,
        @"Idle Companion",
        @"What appears when nothing is playing.",
        self.idleSegment =
            makeCompactSegments(
                @[@"Pixel Cat", @"Banana Cat", @"Spotify"],
                15,
                self,
                @selector(segmentChanged:)
            ),
        0,
        width,
        YES
    );

    self.transitionPopup =
        [[NSPopUpButton alloc]
            initWithFrame:NSZeroRect
                      pullsDown:NO];

    self.transitionPopup.target = self;
    self.transitionPopup.action =
        @selector(transitionChanged:);

    [self.transitionPopup
        addItemsWithTitles:@[
            @"Default • Smooth Crossfade",
            @"Cinematic • Zoom & Push",
            @"Liquid Ripple",
            @"3D Card Flip",
            @"Vinyl Spin",
            @"Cyber Glitch"
        ]];

    addCenteredControlRow(
        transitions,
        @"Track Transition",
        @"Animation used when the artwork changes.",
        self.transitionPopup,
        70,
        width,
        YES
    );

    addCenteredControlRow(
        transitions,
        @"Media Key Target",
        @"Route F7 / F8 / F9 through Wallify.",
        self.mediaKeySegment =
            makeCompactSegments(
                @[@"Off", @"Active", @"Spotify", @"Spotifast"],
                18,
                self,
                @selector(segmentChanged:)
            ),
        140,
        width,
        NO
    );

    [view addSubview:
        makeLabel(
            @"Accessibility permission is required to intercept hardware media keys.",
            22,
            473,
            590,
            18,
            10,
            NSFontWeightRegular,
            [NSColor tertiaryLabelColor]
        )];

    [view addSubview:
        makeGroupTitle(
            @"Visibility",
            6,
            515,
            width - 12
        )];

    NSBox *visibility =
        makeGroup(
            0,
            539,
            width,
            319
        );

    [view addSubview:visibility];

    addSettingRow(
        visibility,
        @"Track Text",
        @"Show title and artist information.",
        self.hideTextSwitch =
            makeToggle(
                @"",
                6,
                self,
                @selector(switchChanged:)
            ),
        0,
        width,
        YES
    );

    addSettingRow(
        visibility,
        @"Progress Bar",
        @"Show the current playback position.",
        self.hideProgressSwitch =
            makeToggle(
                @"",
                7,
                self,
                @selector(switchChanged:)
            ),
        70,
        width,
        YES
    );

    addSettingRow(
        visibility,
        @"Playback Controls",
        @"Show previous, play/pause, and next buttons.",
        self.showControlsSwitch =
            makeToggle(
                @"",
                8,
                self,
                @selector(switchChanged:)
            ),
        140,
        width,
        YES
    );

    addSettingRow(
        visibility,
        @"Time Labels",
        @"Show elapsed and remaining track time.",
        self.showTimestampsSwitch =
            makeToggle(
                @"",
                9,
                self,
                @selector(switchChanged:)
            ),
        210,
        width,
        YES
    );

    addCenteredControlRow(
        visibility,
        @"Progress Thickness",
        @"Choose the visual weight of the progress bar.",
        self.progressThicknessSegment =
            makeCompactSegments(
                @[@"Thin", @"Standard", @"Thick"],
                22,
                self,
                @selector(segmentChanged:)
            ),
        280 - 12,
        width,
        NO
    );

    [view addSubview:
        makeGroupTitle(
            @"Typography",
            6,
            876,
            width - 12
        )];

    NSBox *type =
        makeGroup(
            0,
            900,
            width,
            86
        );

    [view addSubview:type];

    addCenteredControlRow(
        type,
        @"Font Size",
        @"Scale track text across all form factors.",
        self.fontScaleSegment =
            makeCompactSegments(
                @[@"Small", @"Normal", @"Large"],
                17,
                self,
                @selector(segmentChanged:)
            ),
        0,
        width,
        NO
    );
}

#pragma mark Desktop page

- (void)buildDesktopPage:(WallifyFlippedView *)view {
    const CGFloat width = 650.0;

    [view addSubview:
        makeGroupTitle(
            @"Placement",
            6,
            0,
            width - 12
        )];

    NSBox *placement =
        makeGroup(
            0,
            24,
            width,
            185
        );

    [view addSubview:placement];

    [placement addSubview:
        makeLabel(
            @"Current Position",
            20,
            17,
            250,
            20,
            13,
            NSFontWeightMedium,
            [NSColor labelColor]
        )];

    self.gridStatusLabel =
        makeLabel(
            @"Checking position…",
            20,
            45,
            585,
            22,
            13,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        );

    self.gridStatusLabel.font =
        [NSFont monospacedSystemFontOfSize:12
                                    weight:NSFontWeightRegular];

    [placement addSubview:self.gridStatusLabel];

    [placement addSubview:
        makeLabel(
            @"Drag the widget directly on the desktop or reset it to its default slot.",
            20,
            76,
            585,
            22,
            11,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        )];

    NSButton *reset =
        makeActionButton(
            @"Reset Position",
            self,
            @selector(resetPositionClicked:)
        );

    reset.frame =
        NSMakeRect(
            20,
            120,
            126,
            30
        );

    [placement addSubview:reset];

    [view addSubview:
        makeGroupTitle(
            @"Diagnostics",
            6,
            228,
            width - 12
        )];

    NSBox *diagnostics =
        makeGroup(
            0,
            252,
            width,
            120
        );

    [view addSubview:diagnostics];

    addSettingRow(
        diagnostics,
        @"Snapping Diagnostics",
        @"Show snap candidates, coordinates, and live metrics.",
        self.debugSwitch =
            makeToggle(
                @"",
                4,
                self,
                @selector(switchChanged:)
            ),
        15,
        width,
        NO
    );

    [view addSubview:
        makeGroupTitle(
            @"Configuration",
            6,
            390,
            width - 12
        )];

    NSBox *configuration =
        makeGroup(
            0,
            414,
            width,
            178
        );

    [view addSubview:configuration];

    [configuration addSubview:
        makeLabel(
            @"Settings file",
            20,
            17,
            150,
            20,
            13,
            NSFontWeightMedium,
            [NSColor labelColor]
        )];

    NSString *confPath =
        [NSString stringWithUTF8String:
            wallify_settings_path()];

    NSTextField *path =
        makeLabel(
            confPath,
            20,
            44,
            585,
            20,
            10,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        );

    path.font =
        [NSFont monospacedSystemFontOfSize:10
                                    weight:NSFontWeightRegular];

    path.lineBreakMode =
        NSLineBreakByTruncatingMiddle;

    [configuration addSubview:path];

    NSButton *reveal =
        makeActionButton(
            @"Reveal in Finder",
            self,
            @selector(revealConfigClicked:)
        );

    reveal.frame =
        NSMakeRect(
            20,
            91,
            132,
            30
        );

    [configuration addSubview:reveal];

    NSButton *open =
        makeActionButton(
            @"Open File",
            self,
            @selector(openConfigClicked:)
        );

    open.frame =
        NSMakeRect(
            162,
            91,
            105,
            30
        );

    [configuration addSubview:open];

    [view addSubview:
        makeGroupTitle(
            @"About",
            6,
            614,
            width - 12
        )];

    NSBox *about =
        makeGroup(
            0,
            638,
            width,
            143
        );

    [view addSubview:about];

    [about addSubview:
        makeLabel(
            @"Wallify",
            20,
            17,
            250,
            24,
            17,
            NSFontWeightSemibold,
            [NSColor labelColor]
        )];

    [about addSubview:
        makeLabel(
            @"Native Metal rendering • AppKit Liquid Glass",
            20,
            48,
            585,
            20,
            11,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        )];

    [about addSubview:
        makeLabel(
            @"Hardware accelerated and designed for the macOS desktop.",
            20,
            72,
            585,
            20,
            11,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        )];

    [about addSubview:
        makeLabel(
            @"Changes are saved automatically.",
            20,
            101,
            585,
            18,
            10,
            NSFontWeightRegular,
            [NSColor tertiaryLabelColor]
        )];
}

#pragma mark - Navigation

- (void)sidebarButtonClicked:(NSButton *)sender {
    [self selectPage:sender.tag];
}

- (void)selectPage:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.pages.count)
        return;

    NSArray<NSString *> *titles = @[
        @"Appearance",
        @"Playback",
        @"Desktop"
    ];

    NSArray<NSString *> *subtitles = @[
        @"Shape the material, artwork, and motion of your widget.",
        @"Choose the player source, controls, transitions, and typography.",
        @"Manage placement, diagnostics, and your configuration file."
    ];

    NSArray<NSString *> *symbols = @[
        @"paintpalette.fill",
        @"play.circle.fill",
        @"rectangle.on.rectangle"
    ];

    for (NSButton *button in self.sidebarButtons) {
        BOOL selected =
            button.tag == index;

        button.layer.backgroundColor =
            selected
                ? [NSColor selectedControlColor].CGColor
                : NSColor.clearColor.CGColor;

        button.contentTintColor =
            selected
                ? [NSColor selectedControlTextColor]
                : [NSColor secondaryLabelColor];
    }

    self.pageTitleLabel.stringValue =
        titles[index];

    self.pageSubtitleLabel.stringValue =
        subtitles[index];

    self.pageIconView.image =
        [NSImage imageWithSystemSymbolName:
            symbols[index]
            accessibilityDescription:nil];

    self.applyLabel.stringValue =
        @"APPLIES IMMEDIATELY";

    for (NSView *page in self.pages) {
        [page removeFromSuperview];
    }

    NSView *page =
        self.pages[index];

    CGFloat viewportWidth =
        self.scrollView.contentView.bounds.size.width;

    CGFloat pageWidth =
        MAX(
            620.0,
            viewportWidth - 4.0
        );

    CGFloat documentHeight =
        MAX(
            page.frame.size.height,
            self.scrollView.contentView.bounds.size.height
        );

    page.frame =
        NSMakeRect(
            0,
            0,
            pageWidth,
            documentHeight
        );

    self.scrollView.documentView =
        page;

    [self.scrollView.contentView
        scrollToPoint:
            NSMakePoint(
                0,
                0
            )];

    [self.scrollView reflectScrolledClipView:
        self.scrollView.contentView];

    [self refreshUIFromState];
}

#pragma mark - Actions

- (void)switchChanged:(NSButton *)sender {
    BOOL value =
        sender.state == NSControlStateValueOn;

    wallify_settings_apply_bool(
        (int)sender.tag,
        value
    );

    [self refreshUIFromState];
}

- (void)segmentChanged:(NSSegmentedControl *)sender {
    wallify_settings_apply_int(
        (int)sender.tag,
        (int)sender.selectedSegment
    );

    [self refreshUIFromState];
}

- (void)transitionChanged:(NSPopUpButton *)sender {
    wallify_settings_apply_int(
        16,
        (int)sender.indexOfSelectedItem
    );

    [self refreshUIFromState];
}

- (void)resetPositionClicked:(id)sender {
    (void)sender;

    wallify_settings_reset_position();

    [self updateGridStatusLabel];
}

- (void)restoreDefaultsClicked:(id)sender {
    (void)sender;

    NSAlert *alert =
        [[NSAlert alloc] init];

    alert.messageText =
        @"Restore Default Settings?";

    alert.informativeText =
        @"All Wallify appearance, playback, and desktop preferences will return to their defaults.";

    [alert addButtonWithTitle:@"Restore Defaults"];
    [alert addButtonWithTitle:@"Cancel"];

    alert.alertStyle =
        NSAlertStyleWarning;

    if ([alert runModal] ==
        NSAlertFirstButtonReturn) {

        wallify_settings_restore_defaults();

        [self refreshUIFromState];
    }
}

- (void)revealConfigClicked:(id)sender {
    (void)sender;

    NSString *path =
        [NSString stringWithUTF8String:
            wallify_settings_path()];

    [[NSWorkspace sharedWorkspace]
        selectFile:path
        inFileViewerRootedAtPath:@""];
}

- (void)openConfigClicked:(id)sender {
    (void)sender;

    NSString *path =
        [NSString stringWithUTF8String:
            wallify_settings_path()];

    [[NSWorkspace sharedWorkspace]
        openURL:
            [NSURL fileURLWithPath:path]];
}

- (void)doneClicked:(id)sender {
    (void)sender;

    [self closeSettingsWindow];
}

#pragma mark - State

- (void)updateGridStatusLabel {
    WallifySettingsSnapshot snapshot;

    wallify_settings_get_snapshot(
        &snapshot
    );

    self.gridStatusLabel.stringValue =
        [NSString stringWithFormat:
            @"Left %d pt   •   Top %d pt   •   Grid %d, %d",
            snapshot.margin_left,
            snapshot.margin_top,
            snapshot.grid_x,
            snapshot.grid_y];
}

- (void)refreshUIFromState {
    if (!self.window)
        return;

    WallifySettingsSnapshot s;

    wallify_settings_get_snapshot(
        &s
    );

    self.nativeGlassSwitch.state =
        s.native_glass
            ? NSControlStateValueOn
            : NSControlStateValueOff;

    self.glowSwitch.state =
        s.glow
            ? NSControlStateValueOn
            : NSControlStateValueOff;

    self.auroraSwitch.state =
        s.aurora
            ? NSControlStateValueOn
            : NSControlStateValueOff;

    self.animationsSwitch.state =
        s.animations
            ? NSControlStateValueOn
            : NSControlStateValueOff;

    self.dimSwitch.state =
        s.dim_paused
            ? NSControlStateValueOn
            : NSControlStateValueOff;

    self.artworkBorderSwitch.state =
        s.artwork_border
            ? NSControlStateValueOn
            : NSControlStateValueOff;

    self.compactGradientSwitch.state =
        s.compact_gradient
            ? NSControlStateValueOn
            : NSControlStateValueOff;

    self.hideTextSwitch.state =
        s.hide_text
            ? NSControlStateValueOn
            : NSControlStateValueOff;

    self.hideProgressSwitch.state =
        s.hide_progress
            ? NSControlStateValueOn
            : NSControlStateValueOff;

    self.showControlsSwitch.state =
        s.show_controls
            ? NSControlStateValueOn
            : NSControlStateValueOff;

    self.showTimestampsSwitch.state =
        s.show_timestamps
            ? NSControlStateValueOn
            : NSControlStateValueOff;

    self.debugSwitch.state =
        s.debug_hud
            ? NSControlStateValueOn
            : NSControlStateValueOff;

    self.intensitySegment.selectedSegment =
        (s.glow_intensity >= 0 &&
         s.glow_intensity <= 2)
            ? s.glow_intensity
            : 1;

    self.speedSegment.selectedSegment =
        (s.animation_speed >= 0 &&
         s.animation_speed <= 2)
            ? s.animation_speed
            : 1;

    self.frameSegment.selectedSegment =
        (s.frame_strength >= 0 &&
         s.frame_strength <= 2)
            ? s.frame_strength
            : 1;

    self.artworkRadiusSegment.selectedSegment =
        (s.artwork_radius >= 0 &&
         s.artwork_radius <= 2)
            ? s.artwork_radius
            : 1;

    self.progressThicknessSegment.selectedSegment =
        (s.progress_thickness >= 0 &&
         s.progress_thickness <= 2)
            ? s.progress_thickness
            : 1;

    self.fontScaleSegment.selectedSegment =
        (s.font_scale >= 0 &&
         s.font_scale <= 2)
            ? s.font_scale
            : 1;

    self.modeSegment.selectedSegment =
        (s.widget_mode >= 0 &&
         s.widget_mode <= 4)
            ? s.widget_mode
            : 2;

    self.sourceSegment.selectedSegment =
        (s.media_source >= 0 &&
         s.media_source <= 3)
            ? s.media_source
            : 0;

    self.idleSegment.selectedSegment =
        (s.idle_style >= 0 &&
         s.idle_style <= 2)
            ? s.idle_style
            : 0;

    self.mediaKeySegment.selectedSegment =
        (s.media_key_target >= 0 &&
         s.media_key_target <= 3)
            ? s.media_key_target
            : 0;

    if (s.track_transition >= 0 &&
        s.track_transition <
            self.transitionPopup.numberOfItems) {

        [self.transitionPopup
            selectItemAtIndex:
                s.track_transition];
    }

    /*
     * Native Glass owns the material and its rim.
     * These controls remain visible but are disabled
     * when they cannot affect the native material.
     */
    self.auroraSwitch.enabled =
        !s.native_glass;

    self.frameSegment.enabled =
        !s.native_glass;

    self.applyLabel.stringValue =
        @"APPLIES IMMEDIATELY";

    [self updateGridStatusLabel];
}

#pragma mark - Presentation

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

#pragma mark - C bridge

void wallify_show_settings_window(void) {
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            [[WallifySettingsWindowController sharedController]
                showSettingsWindow];
        }
    );
}

void wallify_close_settings_window(void) {
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            [[WallifySettingsWindowController sharedController]
                closeSettingsWindow];
        }
    );
}

void wallify_settings_notify_position_changed(void) {
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            [[WallifySettingsWindowController sharedController]
                updateGridStatusLabel];
        }
    );
}

bool wallify_has_settings_flag(void) {
    NSArray *args =
        [[NSProcessInfo processInfo] arguments];

    for (NSString *arg in args) {
        if ([arg isEqualToString:@"--settings"] ||
            [arg isEqualToString:@"-s"]) {
            return true;
        }
    }

    return false;
}

void wallify_refresh_settings_ui(void) {
    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            if (sharedSettingsController &&
                sharedSettingsController.window.isVisible) {

                [sharedSettingsController
                    refreshUIFromState];
            }
        }
    );
}
