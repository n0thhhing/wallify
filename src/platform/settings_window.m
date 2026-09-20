#import "settings_window.h"

extern const char *wallify_settings_path(void);

@interface WallifyFlippedView : NSVisualEffectView
@end

@implementation WallifyFlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface WallifySettingsWindowController : NSObject <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate>

@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WallifyFlippedView *rootView;
@property(nonatomic, strong) WallifyFlippedView *sidebarView;
@property(nonatomic, strong) NSScrollView *scrollView;
@property(nonatomic, strong) WallifyFlippedView *contentView;
@property(nonatomic, strong) NSArray<NSView *> *pages;

@property(nonatomic, strong) NSTableView *sidebarTable;
@property(nonatomic, strong) NSArray<NSDictionary *> *sidebarItems;

@property(nonatomic, strong) NSTextField *pageTitleLabel;
@property(nonatomic, strong) NSTextField *pageSubtitleLabel;
@property(nonatomic, strong) NSImageView *pageIconView;
@property(nonatomic, strong) NSTextField *applyLabel;

// Appearance
@property(nonatomic, strong) NSButton *nativeGlassSwitch;
@property(nonatomic, strong) NSButton *glowSwitch;
@property(nonatomic, strong) NSButton *auroraSwitch;
@property(nonatomic, strong) NSSegmentedControl *intensitySegment;
@property(nonatomic, strong) NSButton *animationsSwitch;
@property(nonatomic, strong) NSButton *dimSwitch;
@property(nonatomic, strong) NSButton *artworkBorderSwitch;
@property(nonatomic, strong) NSButton *compactGradientSwitch;
@property(nonatomic, strong) NSSegmentedControl *artworkRadiusSegment;
@property(nonatomic, strong) NSSegmentedControl *progressThicknessSegment;
@property(nonatomic, strong) NSSegmentedControl *frameSegment;
@property(nonatomic, strong) NSSegmentedControl *speedSegment;

// Playback
@property(nonatomic, strong) NSSegmentedControl *modeSegment;
@property(nonatomic, strong) NSSegmentedControl *sourceSegment;
@property(nonatomic, strong) NSSegmentedControl *idleSegment;
@property(nonatomic, strong) NSPopUpButton *transitionPopup;
@property(nonatomic, strong) NSButton *hideTextSwitch;
@property(nonatomic, strong) NSButton *hideProgressSwitch;
@property(nonatomic, strong) NSButton *showControlsSwitch;
@property(nonatomic, strong) NSButton *showTimestampsSwitch;
@property(nonatomic, strong) NSSegmentedControl *fontScaleSegment;
@property(nonatomic, strong) NSSegmentedControl *mediaKeySegment;

// General / desktop
@property(nonatomic, strong) NSTextField *gridStatusLabel;
@property(nonatomic, strong) NSButton *debugSwitch;

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
    CGFloat size,
    NSFontWeight weight,
    NSColor *color
) {
    NSTextField *label =
        [[NSTextField alloc] initWithFrame:NSMakeRect(x, y, w, h)];

    label.stringValue = text;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.editable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.selectable = NO;

    return label;
}

static NSTextField *makeCaption(
    NSString *text,
    CGFloat x,
    CGFloat y,
    CGFloat w
) {
    NSTextField *label =
        makeLabel(
            text,
            x,
            y,
            w,
            20,
            11,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        );

    label.lineBreakMode = NSLineBreakByTruncatingTail;

    return label;
}

static NSTextField *makeGroupHeader(
    NSString *text,
    CGFloat x,
    CGFloat y,
    CGFloat w
) {
    return makeLabel(
        text.uppercaseString,
        x,
        y,
        w,
        18,
        11,
        NSFontWeightSemibold,
        [NSColor secondaryLabelColor]
    );
}

static NSBox *makeGroup(
    CGFloat x,
    CGFloat y,
    CGFloat w,
    CGFloat h
) {
    NSBox *group =
        [[NSBox alloc]
            initWithFrame:NSMakeRect(x, y, w, h)];

    group.boxType = NSBoxCustom;
    group.transparent = NO;
    group.borderWidth = 0;
    group.cornerRadius = 12;

    group.fillColor =
        [[NSColor controlBackgroundColor]
            colorWithAlphaComponent:0.72];

    return group;
}

static void addSeparator(
    NSView *parent,
    CGFloat x,
    CGFloat y,
    CGFloat w
) {
    NSBox *separator =
        [[NSBox alloc]
            initWithFrame:NSMakeRect(x, y, w, 1)];

    separator.boxType = NSBoxSeparator;

    [parent addSubview:separator];
}

static NSButton *makeToggle(
    int tag,
    id target,
    SEL action
) {
    NSButton *button =
        [NSButton buttonWithTitle:@""
                           target:target
                           action:action];

    button.buttonType = NSButtonTypeSwitch;
    button.tag = tag;
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
    button.font =
        [NSFont systemFontOfSize:12
                          weight:NSFontWeightMedium];

    return button;
}

static void addToggleRow(
    NSView *parent,
    NSString *title,
    NSString *subtitle,
    NSButton *control,
    CGFloat y,
    CGFloat width,
    BOOL separator
) {
    const CGFloat left = 18.0;
    const CGFloat right = width - 18.0;

    NSTextField *titleLabel =
        makeLabel(
            title,
            left,
            y + 11,
            280,
            20,
            13,
            NSFontWeightMedium,
            [NSColor labelColor]
        );

    [parent addSubview:titleLabel];

    if (subtitle.length > 0) {
        [parent addSubview:
            makeCaption(
                subtitle,
                left,
                y + 33,
                420
            )];
    }

    control.frame =
        NSMakeRect(
            right - 54.0,
            y + 17,
            54.0,
            24.0
        );

    [parent addSubview:control];

    if (separator) {
        addSeparator(
            parent,
            left,
            y + 69,
            width - 36.0
        );
    }
}

static void addControlRow(
    NSView *parent,
    NSString *title,
    NSString *subtitle,
    NSControl *control,
    CGFloat y,
    CGFloat width,
    CGFloat controlWidth,
    BOOL separator
) {
    const CGFloat left = 18.0;
    const CGFloat right = width - 18.0;

    [parent addSubview:
        makeLabel(
            title,
            left,
            y + 10,
            175,
            20,
            13,
            NSFontWeightMedium,
            [NSColor labelColor]
        )];

    if (subtitle.length > 0) {
        [parent addSubview:
            makeCaption(
                subtitle,
                left,
                y + 33,
                240
            )];
    }

    NSRect frame =
        NSMakeRect(
            right - controlWidth,
            y + 15,
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
            width - 36.0
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
    const CGFloat width = 760.0;
    const CGFloat height = 620.0;
    const CGFloat sidebarWidth = 190.0;

    self.window =
        [[NSWindow alloc]
            initWithContentRect:
                NSMakeRect(0, 0, width, height)
                      styleMask:
                          NSWindowStyleMaskTitled |
                          NSWindowStyleMaskClosable |
                          NSWindowStyleMaskMiniaturizable
                        backing:NSBackingStoreBuffered
                          defer:NO];

    self.window.title = @"Wallify";
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    self.window.tabbingMode = NSWindowTabbingModeDisallowed;
    self.window.restorable = NO;
    self.window.minSize = NSMakeSize(700, 560);
    self.window.collectionBehavior |=
        NSWindowCollectionBehaviorFullScreenAuxiliary;

    self.rootView =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(0, 0, width, height)];

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

    /*
     * Sidebar
     */
    self.sidebarView =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(
                    0,
                    0,
                    sidebarWidth,
                    height
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

    /*
     * Main content
     */
    self.contentView =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(
                    sidebarWidth,
                    0,
                    width - sidebarWidth,
                    height
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

    [self buildSidebar];
    [self buildHeader];
    [self buildScrollView];
    [self buildPages];

    [self selectPage:0];
}

#pragma mark - Sidebar

- (void)buildSidebar {
    NSImageView *logo =
        [[NSImageView alloc]
            initWithFrame:
                NSMakeRect(18, 19, 28, 28)];

    logo.image =
        [NSImage imageWithSystemSymbolName:
            @"music.note"
            accessibilityDescription:@"Wallify"];

    logo.symbolConfiguration =
        [NSImageSymbolConfiguration
            configurationWithPointSize:17
            weight:NSFontWeightSemibold];

    logo.contentTintColor =
        [NSColor controlAccentColor];

    [self.sidebarView addSubview:logo];

    [self.sidebarView addSubview:
        makeLabel(
            @"Wallify",
            54,
            15,
            120,
            24,
            15,
            NSFontWeightSemibold,
            [NSColor labelColor]
        )];

    [self.sidebarView addSubview:
        makeLabel(
            @"Preferences",
            54,
            37,
            120,
            18,
            10,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        )];

    addSeparator(
        self.sidebarView,
        14,
        68,
        162
    );

    self.sidebarItems = @[
        @{
            @"title": @"General",
            @"symbol": @"gear"
        },
        @{
            @"title": @"Appearance",
            @"symbol": @"eye"
        },
        @{
            @"title": @"Playback",
            @"symbol": @"play.laptopcomputer"
        },
        @{
            @"title": @"Advanced",
            @"symbol": @"gearshape.2"
        }
    ];

    self.sidebarTable =
        [[NSTableView alloc]
            initWithFrame:
                NSMakeRect(8, 82, 174, 190)];

    self.sidebarTable.headerView = nil;
    self.sidebarTable.rowHeight = 38;
    self.sidebarTable.intercellSpacing = NSMakeSize(0, 3);
    self.sidebarTable.selectionHighlightStyle =
        NSTableViewSelectionHighlightStyleNone;
    self.sidebarTable.focusRingType = NSFocusRingTypeNone;
    self.sidebarTable.backgroundColor = NSColor.clearColor;
    self.sidebarTable.dataSource = self;
    self.sidebarTable.delegate = self;

    NSTableColumn *column =
        [[NSTableColumn alloc] initWithIdentifier:@"sidebar"];

    column.width = 174;

    [self.sidebarTable addTableColumn:column];

    NSScrollView *sidebarScroll =
        [[NSScrollView alloc]
            initWithFrame:
                NSMakeRect(8, 82, 174, 190)];

    sidebarScroll.documentView =
        self.sidebarTable;

    sidebarScroll.hasVerticalScroller = NO;
    sidebarScroll.hasHorizontalScroller = NO;
    sidebarScroll.drawsBackground = NO;
    sidebarScroll.borderType = NSNoBorder;

    [self.sidebarView addSubview:sidebarScroll];

    addSeparator(
        self.sidebarView,
        14,
        540,
        162
    );

    [self.sidebarView addSubview:
        makeLabel(
            @"WALLIFY",
            18,
            560,
            150,
            18,
            9,
            NSFontWeightSemibold,
            [NSColor tertiaryLabelColor]
        )];

    [self.sidebarView addSubview:
        makeLabel(
            @"Native Metal • macOS",
            18,
            580,
            150,
            18,
            10,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        )];
}

#pragma mark - Header

- (void)buildHeader {
    const CGFloat headerHeight = 92.0;

    self.pageIconView =
        [[NSImageView alloc]
            initWithFrame:
                NSMakeRect(28, 24, 28, 28)];

    self.pageIconView.symbolConfiguration =
        [NSImageSymbolConfiguration
            configurationWithPointSize:19
            weight:NSFontWeightMedium];

    self.pageIconView.contentTintColor =
        [NSColor controlAccentColor];

    [self.contentView addSubview:self.pageIconView];

    self.pageTitleLabel =
        makeLabel(
            @"General",
            66,
            19,
            300,
            32,
            24,
            NSFontWeightBold,
            [NSColor labelColor]
        );

    [self.contentView addSubview:self.pageTitleLabel];

    self.pageSubtitleLabel =
        makeLabel(
            @"Configure the basics of your Wallify widget.",
            66,
            49,
            430,
            20,
            12,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        );

    [self.contentView addSubview:self.pageSubtitleLabel];

    self.applyLabel =
        makeLabel(
            @"",
            260,
            25,
            250,
            18,
            10,
            NSFontWeightMedium,
            [NSColor tertiaryLabelColor]
        );

    self.applyLabel.alignment =
        NSTextAlignmentRight;

    [self.contentView addSubview:self.applyLabel];

    addSeparator(
        self.contentView,
        24,
        headerHeight - 1,
        522
    );
}

#pragma mark - Scroll view

- (void)buildScrollView {
    self.scrollView =
        [[NSScrollView alloc]
            initWithFrame:
                NSMakeRect(
                    20,
                    18,
                    530,
                    488
                )];

    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.scrollerStyle = NSScrollerStyleOverlay;
    self.scrollView.drawsBackground = NO;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.autoresizingMask =
        NSViewWidthSizable |
        NSViewHeightSizable;

    [self.contentView addSubview:self.scrollView];
}

#pragma mark - Pages

- (void)buildPages {
    const CGFloat pageWidth = 510.0;

    WallifyFlippedView *general =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(0, 0, pageWidth, 760)];

    [self buildGeneralPage:general];

    WallifyFlippedView *appearance =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(0, 0, pageWidth, 900)];

    [self buildAppearancePage:appearance];

    WallifyFlippedView *playback =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(0, 0, pageWidth, 1060)];

    [self buildPlaybackPage:playback];

    WallifyFlippedView *advanced =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(0, 0, pageWidth, 860)];

    [self buildAdvancedPage:advanced];

    self.pages = @[
        general,
        appearance,
        playback,
        advanced
    ];
}

#pragma mark General

- (void)buildGeneralPage:(WallifyFlippedView *)view {
    const CGFloat width = 510.0;

    [view addSubview:
        makeGroupHeader(
            @"Widget",
            6,
            0,
            width
        )];

    NSBox *widget =
        makeGroup(
            0,
            22,
            width,
            150
        );

    [view addSubview:widget];

    addControlRow(
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
        0,
        width,
        296,
        YES
    );

    addControlRow(
        widget,
        @"Media Source",
        @"Where playback state comes from.",
        self.sourceSegment =
            makeSegments(
                @[@"Now Playing", @"Spotify", @"Spotifast", @"Auto"],
                13,
                self,
                @selector(segmentChanged:)
            ),
        70,
        width,
        296,
        NO
    );

    [view addSubview:
        makeGroupHeader(
            @"Idle Behavior",
            6,
            200,
            width
        )];

    NSBox *idle =
        makeGroup(
            0,
            222,
            width,
            150
        );

    [view addSubview:idle];

    addControlRow(
        idle,
        @"Idle Companion",
        @"Shown when nothing is playing.",
        self.idleSegment =
            makeSegments(
                @[@"Pixel Cat", @"Banana Cat", @"Spotify"],
                15,
                self,
                @selector(segmentChanged:)
            ),
        0,
        width,
        296,
        YES
    );

    addControlRow(
        idle,
        @"Track Transition",
        @"Effect used when artwork changes.",
        self.transitionPopup =
            [[NSPopUpButton alloc]
                initWithFrame:NSZeroRect
                pullsDown:NO],
        70,
        width,
        296,
        NO
    );

    [self.transitionPopup
        addItemsWithTitles:@[
            @"Default • Smooth Crossfade",
            @"Cinematic • Zoom & Push",
            @"Liquid Ripple",
            @"3D Card Flip",
            @"Vinyl Spin",
            @"Cyber Glitch"
        ]];

    [view addSubview:
        makeGroupHeader(
            @"Playback",
            6,
            400,
            width
        )];

    NSBox *playback =
        makeGroup(
            0,
            422,
            width,
            150
        );

    [view addSubview:playback];

    addControlRow(
        playback,
        @"Media Keys",
        @"Route F7 / F8 / F9 through Wallify.",
        self.mediaKeySegment =
            makeSegments(
                @[@"Off", @"Active", @"Spotify", @"Spotifast"],
                18,
                self,
                @selector(segmentChanged:)
            ),
        0,
        width,
        296,
        NO
    );

    [view addSubview:
        makeCaption(
            @"Accessibility permission is required to intercept hardware media keys.",
            18,
            585,
            470
        )];

    NSButton *quit =
        makeActionButton(
            @"Quit Wallify",
            self,
            @selector(quitClicked:)
        );

    quit.frame =
        NSMakeRect(
            18,
            622,
            105,
            30
        );

    [view addSubview:quit];
}

#pragma mark Appearance

- (void)buildAppearancePage:(WallifyFlippedView *)view {
    const CGFloat width = 510.0;

    [view addSubview:
        makeGroupHeader(
            @"Material",
            6,
            0,
            width
        )];

    NSBox *material =
        makeGroup(
            0,
            22,
            width,
            295
        );

    [view addSubview:material];

    addToggleRow(
        material,
        @"Native Glass",
        @"Use the native macOS Liquid Glass material.",
        self.nativeGlassSwitch =
            makeToggle(
                5,
                self,
                @selector(switchChanged:)
            ),
        0,
        width,
        YES
    );

    addToggleRow(
        material,
        @"Artwork Glow",
        @"Ambient color pulled from the current artwork.",
        self.glowSwitch =
            makeToggle(
                0,
                self,
                @selector(switchChanged:)
            ),
        70,
        width,
        YES
    );

    addControlRow(
        material,
        @"Glow Intensity",
        @"Strength of the artwork glow.",
        self.intensitySegment =
            makeSegments(
                @[@"Low", @"Normal", @"High"],
                11,
                self,
                @selector(segmentChanged:)
            ),
        140,
        width,
        240,
        YES
    );

    addToggleRow(
        material,
        @"Aurora",
        @"Animated gradient behind the widget.",
        self.auroraSwitch =
            makeToggle(
                1,
                self,
                @selector(switchChanged:)
            ),
        210,
        width,
        NO
    );

    [view addSubview:
        makeGroupHeader(
            @"Artwork",
            6,
            340,
            width
        )];

    NSBox *artwork =
        makeGroup(
            0,
            362,
            width,
            220
        );

    [view addSubview:artwork];

    addToggleRow(
        artwork,
        @"Artwork Border",
        @"Fine highlight around album artwork.",
        self.artworkBorderSwitch =
            makeToggle(
                19,
                self,
                @selector(switchChanged:)
            ),
        0,
        width,
        YES
    );

    addControlRow(
        artwork,
        @"Artwork Corners",
        @"Choose the artwork radius.",
        self.artworkRadiusSegment =
            makeSegments(
                @[@"Soft", @"Rounded", @"Large"],
                21,
                self,
                @selector(segmentChanged:)
            ),
        70,
        width,
        240,
        YES
    );

    addToggleRow(
        artwork,
        @"Compact Contrast",
        @"Fade behind text in 1 × 1 mode.",
        self.compactGradientSwitch =
            makeToggle(
                20,
                self,
                @selector(switchChanged:)
            ),
        140,
        width,
        NO
    );

    [view addSubview:
        makeGroupHeader(
            @"Motion",
            6,
            627,
            width
        )];

    NSBox *motion =
        makeGroup(
            0,
            649,
            width,
            220
        );

    [view addSubview:motion];

    addToggleRow(
        motion,
        @"Animations",
        @"Animate resizing and state changes.",
        self.animationsSwitch =
            makeToggle(
                2,
                self,
                @selector(switchChanged:)
            ),
        0,
        width,
        YES
    );

    addControlRow(
        motion,
        @"Animation Speed",
        @"Control transition speed.",
        self.speedSegment =
            makeSegments(
                @[@"Slow", @"Normal", @"Fast"],
                12,
                self,
                @selector(segmentChanged:)
            ),
        70,
        width,
        240,
        YES
    );

    addControlRow(
        motion,
        @"Glass Border",
        @"Border used by the custom material.",
        self.frameSegment =
            makeSegments(
                @[@"Off", @"Subtle", @"Strong"],
                10,
                self,
                @selector(segmentChanged:)
            ),
        140,
        width,
        240,
        NO
    );
}

#pragma mark Playback

- (void)buildPlaybackPage:(WallifyFlippedView *)view {
    const CGFloat width = 510.0;

    [view addSubview:
        makeGroupHeader(
            @"Visibility",
            6,
            0,
            width
        )];

    NSBox *visibility =
        makeGroup(
            0,
            22,
            width,
            360
        );

    [view addSubview:visibility];

    addToggleRow(
        visibility,
        @"Track Text",
        @"Show title and artist information.",
        self.hideTextSwitch =
            makeToggle(
                6,
                self,
                @selector(switchChanged:)
            ),
        0,
        width,
        YES
    );

    addToggleRow(
        visibility,
        @"Progress Bar",
        @"Show the current playback position.",
        self.hideProgressSwitch =
            makeToggle(
                7,
                self,
                @selector(switchChanged:)
            ),
        70,
        width,
        YES
    );

    addToggleRow(
        visibility,
        @"Playback Controls",
        @"Show previous, play/pause, and next.",
        self.showControlsSwitch =
            makeToggle(
                8,
                self,
                @selector(switchChanged:)
            ),
        140,
        width,
        YES
    );

    addToggleRow(
        visibility,
        @"Time Labels",
        @"Show elapsed and remaining time.",
        self.showTimestampsSwitch =
            makeToggle(
                9,
                self,
                @selector(switchChanged:)
            ),
        210,
        width,
        YES
    );

    addControlRow(
        visibility,
        @"Progress Thickness",
        @"Weight of the playback progress bar.",
        self.progressThicknessSegment =
            makeSegments(
                @[@"Thin", @"Standard", @"Thick"],
                22,
                self,
                @selector(segmentChanged:)
            ),
        280,
        width,
        240,
        NO
    );

    [view addSubview:
        makeGroupHeader(
            @"Typography",
            6,
            405,
            width
        )];

    NSBox *type =
        makeGroup(
            0,
            427,
            width,
            80
        );

    [view addSubview:type];

    addControlRow(
        type,
        @"Font Size",
        @"Scale track information.",
        self.fontScaleSegment =
            makeSegments(
                @[@"Small", @"Normal", @"Large"],
                17,
                self,
                @selector(segmentChanged:)
            ),
        0,
        width,
        240,
        NO
    );

    [view addSubview:
        makeGroupHeader(
            @"Paused State",
            6,
            542,
            width
        )];

    NSBox *paused =
        makeGroup(
            0,
            564,
            width,
            80
        );

    [view addSubview:paused];

    addToggleRow(
        paused,
        @"Dim Artwork",
        @"Lower artwork brightness when paused.",
        self.dimSwitch =
            makeToggle(
                3,
                self,
                @selector(switchChanged:)
            ),
        0,
        width,
        NO
    );
}

#pragma mark Advanced

- (void)buildAdvancedPage:(WallifyFlippedView *)view {
    const CGFloat width = 510.0;

    [view addSubview:
        makeGroupHeader(
            @"Desktop",
            6,
            0,
            width
        )];

    NSBox *desktop =
        makeGroup(
            0,
            22,
            width,
            178
        );

    [view addSubview:desktop];

    [desktop addSubview:
        makeLabel(
            @"Current Position",
            18,
            18,
            220,
            20,
            13,
            NSFontWeightMedium,
            [NSColor labelColor]
        )];

    self.gridStatusLabel =
        makeLabel(
            @"Checking position…",
            18,
            46,
            460,
            22,
            12,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        );

    self.gridStatusLabel.font =
        [NSFont monospacedSystemFontOfSize:12
                                    weight:NSFontWeightRegular];

    [desktop addSubview:self.gridStatusLabel];

    [desktop addSubview:
        makeCaption(
            @"Drag the widget on the desktop or restore its default position.",
            18,
            72,
            460
        )];

    NSButton *reset =
        makeActionButton(
            @"Reset Position",
            self,
            @selector(resetPositionClicked:)
        );

    reset.frame =
        NSMakeRect(
            18,
            116,
            122,
            30
        );

    [desktop addSubview:reset];

    [view addSubview:
        makeGroupHeader(
            @"Diagnostics",
            6,
            228,
            width
        )];

    NSBox *diagnostics =
        makeGroup(
            0,
            250,
            width,
            80
        );

    [view addSubview:diagnostics];

    addToggleRow(
        diagnostics,
        @"Snapping Diagnostics",
        @"Show snap candidates and live coordinates.",
        self.debugSwitch =
            makeToggle(
                4,
                self,
                @selector(switchChanged:)
            ),
        0,
        width,
        NO
    );

    [view addSubview:
        makeGroupHeader(
            @"Configuration",
            6,
            358,
            width
        )];

    NSBox *configuration =
        makeGroup(
            0,
            380,
            width,
            170
        );

    [view addSubview:configuration];

    [configuration addSubview:
        makeLabel(
            @"Settings File",
            18,
            17,
            200,
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
            18,
            45,
            460,
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
            18,
            88,
            128,
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
            154,
            88,
            102,
            30
        );

    [configuration addSubview:open];

    [configuration addSubview:
        makeCaption(
            @"Changes are saved automatically.",
            18,
            130,
            460
        )];

    [view addSubview:
        makeGroupHeader(
            @"About",
            6,
            575,
            width
        )];

    NSBox *about =
        makeGroup(
            0,
            597,
            width,
            140
        );

    [view addSubview:about];

    [about addSubview:
        makeLabel(
            @"Wallify",
            18,
            16,
            300,
            24,
            17,
            NSFontWeightSemibold,
            [NSColor labelColor]
        )];

    [about addSubview:
        makeCaption(
            @"Native Metal rendering • AppKit Liquid Glass",
            18,
            48,
            460
        )];

    [about addSubview:
        makeCaption(
            @"Hardware accelerated and built for the macOS desktop.",
            18,
            72,
            460
        )];
}

#pragma mark - Sidebar table

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return self.sidebarItems.count;
}

- (NSView *)tableView:(NSTableView *)tableView
   viewForTableColumn:(NSTableColumn *)tableColumn
                  row:(NSInteger)row {
    (void)tableColumn;

    if (row < 0 || row >= (NSInteger)self.sidebarItems.count)
        return nil;

    NSDictionary *item =
        self.sidebarItems[row];

    NSTableCellView *cell =
        [tableView makeViewWithIdentifier:@"SidebarCell"
                                    owner:self];

    if (!cell) {
        cell =
            [[NSTableCellView alloc]
                initWithFrame:
                    NSMakeRect(0, 0, 174, 38)];

        cell.identifier = @"SidebarCell";

        NSImageView *icon =
            [[NSImageView alloc]
                initWithFrame:
                    NSMakeRect(10, 7, 22, 22)];

        icon.tag = 100;
        icon.imageScaling =
            NSImageScaleProportionallyDown;

        [cell addSubview:icon];

        NSTextField *label =
            makeLabel(
                @"",
                42,
                8,
                120,
                22,
                13,
                NSFontWeightMedium,
                [NSColor labelColor]
            );

        label.tag = 101;

        [cell addSubview:label];

        cell.wantsLayer = YES;
        cell.layer.cornerRadius = 8;
    }

    NSImageView *icon =
        [cell viewWithTag:100];

    NSTextField *label =
        [cell viewWithTag:101];

    icon.image =
        [NSImage imageWithSystemSymbolName:
            item[@"symbol"]
            accessibilityDescription:nil];

    icon.symbolConfiguration =
        [NSImageSymbolConfiguration
            configurationWithPointSize:14
            weight:NSFontWeightMedium];

    label.stringValue =
        item[@"title"];

    NSInteger selected =
        self.sidebarTable.selectedRow;

    BOOL active =
        row == selected;

    cell.layer.backgroundColor =
        active
            ? [NSColor selectedControlColor].CGColor
            : NSColor.clearColor.CGColor;

    icon.contentTintColor =
        active
            ? [NSColor selectedControlTextColor]
            : [NSColor secondaryLabelColor];

    label.textColor =
        active
            ? [NSColor selectedControlTextColor]
            : [NSColor labelColor];

    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;

    [self selectPage:self.sidebarTable.selectedRow];
}

#pragma mark - Navigation

- (void)selectPage:(NSInteger)index {
    if (index < 0 ||
        index >= (NSInteger)self.pages.count)
        return;

    if (self.sidebarTable.selectedRow != index) {
        [self.sidebarTable
            selectRowIndexes:
                [NSIndexSet indexSetWithIndex:index]
                  byExtendingSelection:NO];
    }

    NSArray<NSString *> *titles = @[
        @"General",
        @"Appearance",
        @"Playback",
        @"Advanced"
    ];

    NSArray<NSString *> *subtitles = @[
        @"Configure the basics of your Wallify widget.",
        @"Customize the material, artwork, and motion.",
        @"Control visibility, typography, and playback presentation.",
        @"Manage desktop placement, diagnostics, and configuration."
    ];

    NSArray<NSString *> *symbols = @[
        @"gear",
        @"eye",
        @"play.laptopcomputer",
        @"gearshape.2"
    ];

    self.pageTitleLabel.stringValue =
        titles[index];

    self.pageSubtitleLabel.stringValue =
        subtitles[index];

    self.pageIconView.image =
        [NSImage imageWithSystemSymbolName:
            symbols[index]
            accessibilityDescription:nil];

    for (NSView *page in self.pages) {
        [page removeFromSuperview];
    }

    NSView *page =
        self.pages[index];

    CGFloat documentWidth =
        self.scrollView.contentView.bounds.size.width;

    page.frame =
        NSMakeRect(
            0,
            0,
            MAX(500.0, documentWidth - 8.0),
            page.frame.size.height
        );

    self.scrollView.documentView = page;

    [self.scrollView.contentView
        scrollToPoint:
            NSMakePoint(0, 0)];

    [self.scrollView
        reflectScrolledClipView:
            self.scrollView.contentView];

    [self refreshUIFromState];
}

#pragma mark - Settings actions

- (void)switchChanged:(NSButton *)sender {
    wallify_settings_apply_bool(
        (int)sender.tag,
        sender.state == NSControlStateValueOn
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
        @"Wallify's appearance, playback, and desktop preferences will be reset.";

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

- (void)quitClicked:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
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
            selectItemAtIndex:s.track_transition];
    }

    /*
     * Native Glass supplies its own material/rim.
     */
    self.auroraSwitch.enabled =
        !s.native_glass;

    self.frameSegment.enabled =
        !s.native_glass;

    self.applyLabel.stringValue =
        @"APPLIES IMMEDIATELY";

    [self updateGridStatusLabel];

    [self.sidebarTable reloadData];
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
