#import "settings_window.h"

extern const char *wallify_settings_path(void);

@interface WallifyFlippedView : NSVisualEffectView
@end

@implementation WallifyFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface WallifySettingsWindowController : NSObject <NSWindowDelegate>

@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WallifyFlippedView *rootView;
@property(nonatomic, strong) WallifyFlippedView *sidebarView;
@property(nonatomic, strong) WallifyFlippedView *contentView;
@property(nonatomic, strong) NSScrollView *scrollView;
@property(nonatomic, strong) NSArray<NSView *> *pages;
@property(nonatomic, strong) NSArray<NSButton *> *sidebarButtons;

@property(nonatomic, strong) NSTextField *pageTitleLabel;
@property(nonatomic, strong) NSImageView *pageIconView;

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

// Desktop
@property(nonatomic, strong) NSTextField *gridStatusLabel;
@property(nonatomic, strong) NSButton *debugSwitch;

+ (instancetype)sharedController;
- (void)showSettingsWindow;
- (void)closeSettingsWindow;
- (void)refreshUIFromState;

@end

static WallifySettingsWindowController *sharedSettingsController = nil;

#pragma mark - Small UI helpers

static NSTextField *label(
    NSString *text,
    NSRect frame,
    CGFloat size,
    NSFontWeight weight,
    NSColor *color
) {
    NSTextField *view =
        [[NSTextField alloc] initWithFrame:frame];

    view.stringValue = text;
    view.font = [NSFont systemFontOfSize:size weight:weight];
    view.textColor = color;
    view.editable = NO;
    view.bezeled = NO;
    view.drawsBackground = NO;
    view.selectable = NO;
    view.lineBreakMode = NSLineBreakByTruncatingTail;

    return view;
}

static NSBox *groupBox(NSRect frame) {
    NSBox *box =
        [[NSBox alloc] initWithFrame:frame];

    box.boxType = NSBoxCustom;
    box.transparent = NO;
    box.borderWidth = 0;
    box.cornerRadius = 12;
    box.fillColor =
        [[NSColor controlBackgroundColor]
            colorWithAlphaComponent:0.52];

    return box;
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
    control.segmentDistribution =
        NSSegmentDistributionFillEqually;
    control.controlSize = NSControlSizeRegular;

    return control;
}

static NSButton *actionButton(
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

static void separator(NSView *parent, CGFloat y, CGFloat width) {
    NSBox *line =
        [[NSBox alloc]
            initWithFrame:NSMakeRect(18, y, width - 36, 1)];

    line.boxType = NSBoxSeparator;
    [parent addSubview:line];
}

static void addToggleRow(
    NSView *parent,
    NSString *title,
    NSString *subtitle,
    NSButton *control,
    CGFloat y,
    CGFloat width,
    BOOL showSeparator
) {
    [parent addSubview:
        label(
            title,
            NSMakeRect(18, y + 9, 280, 20),
            13,
            NSFontWeightMedium,
            [NSColor labelColor]
        )];

    if (subtitle.length > 0) {
        [parent addSubview:
            label(
                subtitle,
                NSMakeRect(18, y + 30, 390, 18),
                11,
                NSFontWeightRegular,
                [NSColor secondaryLabelColor]
            )];
    }

    control.frame =
        NSMakeRect(
            width - 76,
            y + 13,
            58,
            24
        );

    [parent addSubview:control];

    if (showSeparator)
        separator(parent, y + 69, width);
}

static void addControlRow(
    NSView *parent,
    NSString *title,
    NSString *subtitle,
    NSControl *control,
    CGFloat y,
    CGFloat width,
    CGFloat controlWidth,
    BOOL showSeparator
) {
    [parent addSubview:
        label(
            title,
            NSMakeRect(18, y + 9, 160, 20),
            13,
            NSFontWeightMedium,
            [NSColor labelColor]
        )];

    if (subtitle.length > 0) {
        [parent addSubview:
            label(
                subtitle,
                NSMakeRect(18, y + 31, 200, 18),
                11,
                NSFontWeightRegular,
                [NSColor secondaryLabelColor]
            )];
    }

    control.frame =
        NSMakeRect(
            width - controlWidth - 18,
            y + 15,
            controlWidth,
            28
        );

    [parent addSubview:control];

    if (showSeparator)
        separator(parent, y + 69, width);
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

#pragma mark Window

- (void)createWindow {
    const CGFloat width = 760.0;
    const CGFloat height = 580.0;
    const CGFloat sidebarWidth = 180.0;

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
    self.window.minSize = NSMakeSize(700, 540);
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

    self.window.contentView =
        self.rootView;

    /*
     * Sidebar.
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
     * Main content.
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
    [self buildFooter];

    [self selectPage:0];
}

#pragma mark Sidebar

- (void)buildSidebar {
    NSImageView *icon =
        [[NSImageView alloc]
            initWithFrame:NSMakeRect(22, 20, 28, 28)];

    icon.image =
        [NSImage imageWithSystemSymbolName:
            @"music.note"
            accessibilityDescription:@"Wallify"];

    icon.symbolConfiguration =
        [NSImageSymbolConfiguration
            configurationWithPointSize:17
            weight:NSFontWeightSemibold];

    icon.contentTintColor =
        [NSColor controlAccentColor];

    [self.sidebarView addSubview:icon];

    [self.sidebarView addSubview:
        label(
            @"Wallify",
            NSMakeRect(58, 16, 105, 22),
            15,
            NSFontWeightSemibold,
            [NSColor labelColor]
        )];

    [self.sidebarView addSubview:
        label(
            @"Settings",
            NSMakeRect(58, 39, 105, 18),
            10,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        )];

    separator(self.sidebarView, 70, 180);

    NSArray<NSDictionary *> *items = @[
        @{
            @"title": @"General",
            @"symbol": @"gearshape"
        },
        @{
            @"title": @"Appearance",
            @"symbol": @"paintpalette"
        },
        @{
            @"title": @"Playback",
            @"symbol": @"play.circle"
        },
        @{
            @"title": @"Desktop",
            @"symbol": @"rectangle.on.rectangle"
        }
    ];

    NSMutableArray<NSButton *> *buttons =
        [NSMutableArray arrayWithCapacity:items.count];

    CGFloat y = 88.0;

    for (NSDictionary *item in items) {
        NSButton *button =
            [NSButton buttonWithTitle:item[@"title"]
                               target:self
                               action:@selector(sidebarButtonClicked:)];

        button.tag = (NSInteger)buttons.count;
        button.bordered = NO;
        button.alignment = NSTextAlignmentLeft;
        button.font =
            [NSFont systemFontOfSize:13
                              weight:NSFontWeightMedium];

        button.image =
            [NSImage imageWithSystemSymbolName:
                item[@"symbol"]
                accessibilityDescription:nil];

        button.imagePosition = NSImageLeft;
        button.imageScaling =
            NSImageScaleProportionallyDown;

        button.contentTintColor =
            [NSColor secondaryLabelColor];

        button.frame =
            NSMakeRect(
                10,
                y,
                160,
                36
            );

        button.wantsLayer = YES;
        button.layer.cornerRadius = 8;

        [self.sidebarView addSubview:button];
        [buttons addObject:button];

        y += 42;
    }

    self.sidebarButtons = buttons;

    separator(self.sidebarView, 512, 180);

    [self.sidebarView addSubview:
        label(
            @"Native Metal",
            NSMakeRect(18, 530, 140, 18),
            10,
            NSFontWeightMedium,
            [NSColor tertiaryLabelColor]
        )];

    [self.sidebarView addSubview:
        label(
            @"AppKit • macOS",
            NSMakeRect(18, 549, 140, 18),
            10,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        )];
}

#pragma mark Header

- (void)buildHeader {
    self.pageIconView =
        [[NSImageView alloc]
            initWithFrame:NSMakeRect(27, 20, 26, 26)];

    self.pageIconView.symbolConfiguration =
        [NSImageSymbolConfiguration
            configurationWithPointSize:18
            weight:NSFontWeightMedium];

    self.pageIconView.contentTintColor =
        [NSColor controlAccentColor];

    [self.contentView addSubview:self.pageIconView];

    self.pageTitleLabel =
        label(
            @"General",
            NSMakeRect(63, 16, 350, 32),
            23,
            NSFontWeightBold,
            [NSColor labelColor]
        );

    [self.contentView addSubview:self.pageTitleLabel];

    separator(self.contentView, 64, self.contentView.bounds.size.width);
}

#pragma mark Scroll

- (void)buildScrollView {
    self.scrollView =
        [[NSScrollView alloc]
            initWithFrame:
                NSMakeRect(
                    16,
                    76,
                    self.contentView.bounds.size.width - 32,
                    450
                )];

    self.scrollView.autoresizingMask =
        NSViewWidthSizable |
        NSViewHeightSizable;

    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.scrollerStyle = NSScrollerStyleOverlay;
    self.scrollView.drawsBackground = NO;
    self.scrollView.borderType = NSNoBorder;

    [self.contentView addSubview:self.scrollView];
}

#pragma mark Footer

- (void)buildFooter {
    NSView *footer =
        [[NSView alloc]
            initWithFrame:
                NSMakeRect(
                    180,
                    526,
                    self.window.frame.size.width - 180,
                    54
                )];

    footer.autoresizingMask =
        NSViewWidthSizable |
        NSViewMinYMargin;

    [self.rootView addSubview:footer];

    separator(
        footer,
        0,
        footer.bounds.size.width
    );

    NSButton *defaults =
        actionButton(
            @"Restore Defaults",
            self,
            @selector(restoreDefaultsClicked:)
        );

    defaults.frame =
        NSMakeRect(
            18,
            11,
            128,
            29
        );

    [footer addSubview:defaults];

    NSButton *done =
        [NSButton buttonWithTitle:@"Done"
                           target:self
                           action:@selector(doneClicked:)];

    done.bezelStyle =
        NSBezelStyleRounded;

    done.font =
        [NSFont systemFontOfSize:12
                          weight:NSFontWeightSemibold];

    done.keyEquivalent = @"\r";

    done.frame =
        NSMakeRect(
            footer.bounds.size.width - 92,
            10,
            74,
            30
        );

    [footer addSubview:done];
}

#pragma mark Pages

- (void)buildPages {
    const CGFloat pageWidth = 500.0;

    WallifyFlippedView *general =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(0, 0, pageWidth, 600)];

    [self buildGeneralPage:general];

    WallifyFlippedView *appearance =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(0, 0, pageWidth, 760)];

    [self buildAppearancePage:appearance];

    WallifyFlippedView *playback =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(0, 0, pageWidth, 840)];

    [self buildPlaybackPage:playback];

    WallifyFlippedView *desktop =
        [[WallifyFlippedView alloc]
            initWithFrame:
                NSMakeRect(0, 0, pageWidth, 620)];

    [self buildDesktopPage:desktop];

    self.pages = @[
        general,
        appearance,
        playback,
        desktop
    ];
}

#pragma mark General page

- (void)buildGeneralPage:(WallifyFlippedView *)view {
    const CGFloat width = 500.0;

    [view addSubview:
        label(
            @"Widget",
            NSMakeRect(4, 2, width - 8, 18),
            11,
            NSFontWeightSemibold,
            [NSColor secondaryLabelColor]
        )];

    NSBox *widget =
        groupBox(NSMakeRect(0, 24, width, 150));

    [view addSubview:widget];

    addControlRow(
        widget,
        @"Form Factor",
        @"Desktop footprint.",
        self.modeSegment =
            makeSegments(
                @[@"1 × 1", @"2 × 1", @"3 × 1", @"1 × 2", @"2 × 2"],
                14,
                self,
                @selector(segmentChanged:)
            ),
        0,
        width,
        300,
        YES
    );

    addControlRow(
        widget,
        @"Media Source",
        @"Playback source.",
        self.sourceSegment =
            makeSegments(
                @[@"Now Playing", @"Spotify", @"Spotifast", @"Auto"],
                70,
                self,
                @selector(segmentChanged:)
            ),
        0,
        width,
        300,
        NO
    );

    [view addSubview:
        label(
            @"Idle",
            NSMakeRect(4, 194, width - 8, 18),
            11,
            NSFontWeightSemibold,
            [NSColor secondaryLabelColor]
        )];

    NSBox *idle =
        groupBox(NSMakeRect(0, 216, width, 150));

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
        300,
        YES
    );

    self.transitionPopup =
        [[NSPopUpButton alloc]
            initWithFrame:NSZeroRect
            pullsDown:NO];

    [self.transitionPopup
        addItemsWithTitles:@[
            @"Default",
            @"Cinematic",
            @"Ripple",
            @"Card Flip",
            @"Vinyl",
            @"Glitch"
        ]];

    self.transitionPopup.target = self;
    self.transitionPopup.action =
        @selector(transitionChanged:);

    addControlRow(
        idle,
        @"Track Transition",
        @"Effect used when artwork changes.",
        self.transitionPopup,
        70,
        width,
        300,
        NO
    );

    [view addSubview:
        label(
            @"Media Keys",
            NSMakeRect(4, 388, width - 8, 18),
            11,
            NSFontWeightSemibold,
            [NSColor secondaryLabelColor]
        )];

    NSBox *keys =
        groupBox(NSMakeRect(0, 410, width, 150));

    [view addSubview:keys];

    addControlRow(
        keys,
        @"Target",
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
        300,
        NO
    );

    [keys addSubview:
        label(
            @"Accessibility permission is required.",
            NSMakeRect(18, 88, 440, 18),
            10,
            NSFontWeightRegular,
            [NSColor tertiaryLabelColor]
        )];
}

#pragma mark Appearance page

- (void)buildAppearancePage:(WallifyFlippedView *)view {
    const CGFloat width = 500.0;

    [view addSubview:
        label(
            @"Material",
            NSMakeRect(4, 2, width - 8, 18),
            11,
            NSFontWeightSemibold,
            [NSColor secondaryLabelColor]
        )];

    NSBox *material =
        groupBox(NSMakeRect(0, 24, width, 290));

    [view addSubview:material];

    addToggleRow(
        material,
        @"Native Glass",
        @"Use the macOS Liquid Glass material.",
        self.nativeGlassSwitch =
            makeToggle(5, self, @selector(switchChanged:)),
        0,
        width,
        YES
    );

    addToggleRow(
        material,
        @"Artwork Glow",
        @"Ambient color from album artwork.",
        self.glowSwitch =
            makeToggle(0, self, @selector(switchChanged:)),
        70,
        width,
        YES
    );

    addControlRow(
        material,
        @"Glow Intensity",
        @"Glow strength.",
        self.intensitySegment =
            makeSegments(
                @[@"Low", @"Normal", @"High"],
                11,
                self,
                @selector(segmentChanged:)
            ),
        140,
        width,
        230,
        YES
    );

    addToggleRow(
        material,
        @"Aurora",
        @"Animated background gradient.",
        self.auroraSwitch =
            makeToggle(1, self, @selector(switchChanged:)),
        210,
        width,
        NO
    );

    [view addSubview:
        label(
            @"Artwork",
            NSMakeRect(4, 338, width - 8, 18),
            11,
            NSFontWeightSemibold,
            [NSColor secondaryLabelColor]
        )];

    NSBox *artwork =
        groupBox(NSMakeRect(0, 360, width, 220));

    [view addSubview:artwork];

    addToggleRow(
        artwork,
        @"Artwork Border",
        @"Fine edge around album artwork.",
        self.artworkBorderSwitch =
            makeToggle(19, self, @selector(switchChanged:)),
        0,
        width,
        YES
    );

    addControlRow(
        artwork,
        @"Corners",
        @"Artwork radius.",
        self.artworkRadiusSegment =
            makeSegments(
                @[@"Soft", @"Rounded", @"Large"],
                21,
                self,
                @selector(segmentChanged:)
            ),
        70,
        width,
        230,
        YES
    );

    addToggleRow(
        artwork,
        @"Compact Contrast",
        @"Fade behind text in 1 × 1.",
        self.compactGradientSwitch =
            makeToggle(20, self, @selector(switchChanged:)),
        140,
        width,
        NO
    );

    [view addSubview:
        label(
            @"Motion",
            NSMakeRect(4, 604, width - 8, 18),
            11,
            NSFontWeightSemibold,
            [NSColor secondaryLabelColor]
        )];

    NSBox *motion =
        groupBox(NSMakeRect(0, 626, width, 220));

    [view addSubview:motion];

    addToggleRow(
        motion,
        @"Animations",
        @"Animate resizing and state changes.",
        self.animationsSwitch =
            makeToggle(2, self, @selector(switchChanged:)),
        0,
        width,
        YES
    );

    addControlRow(
        motion,
        @"Speed",
        @"Animation speed.",
        self.speedSegment =
            makeSegments(
                @[@"Slow", @"Normal", @"Fast"],
                12,
                self,
                @selector(segmentChanged:)
            ),
        70,
        width,
        230,
        YES
    );

    addControlRow(
        motion,
        @"Custom Border",
        @"Border for the custom material.",
        self.frameSegment =
            makeSegments(
                @[@"Off", @"Subtle", @"Strong"],
                10,
                self,
                @selector(segmentChanged:)
            ),
        140,
        width,
        230,
        NO
    );

    addToggleRow(
        motion,
        @"Dim When Paused",
        @"Lower artwork brightness while paused.",
        self.dimSwitch =
            makeToggle(3, self, @selector(switchChanged:)),
        210,
        width,
        NO
    );
}

#pragma mark Playback page

- (void)buildPlaybackPage:(WallifyFlippedView *)view {
    const CGFloat width = 500.0;

    [view addSubview:
        label(
            @"Visibility",
            NSMakeRect(4, 2, width - 8, 18),
            11,
            NSFontWeightSemibold,
            [NSColor secondaryLabelColor]
        )];

    NSBox *visibility =
        groupBox(NSMakeRect(0, 24, width, 360));

    [view addSubview:visibility];

    addToggleRow(
        visibility,
        @"Track Text",
        @"Show title and artist.",
        self.hideTextSwitch =
            makeToggle(6, self, @selector(switchChanged:)),
        0,
        width,
        YES
    );

    addToggleRow(
        visibility,
        @"Progress Bar",
        @"Show playback progress.",
        self.hideProgressSwitch =
            makeToggle(7, self, @selector(switchChanged:)),
        70,
        width,
        YES
    );

    addToggleRow(
        visibility,
        @"Playback Controls",
        @"Show previous, play/pause, and next.",
        self.showControlsSwitch =
            makeToggle(8, self, @selector(switchChanged:)),
        140,
        width,
        YES
    );

    addToggleRow(
        visibility,
        @"Time Labels",
        @"Show elapsed and remaining time.",
        self.showTimestampsSwitch =
            makeToggle(9, self, @selector(switchChanged:)),
        210,
        width,
        YES
    );

    addControlRow(
        visibility,
        @"Progress Thickness",
        @"Visual weight of the progress bar.",
        self.progressThicknessSegment =
            makeSegments(
                @[@"Thin", @"Standard", @"Thick"],
                22,
                self,
                @selector(segmentChanged:)
            ),
        280,
        width,
        230,
        NO
    );

    [view addSubview:
        label(
            @"Typography",
            NSMakeRect(4, 408, width - 8, 18),
            11,
            NSFontWeightSemibold,
            [NSColor secondaryLabelColor]
        )];

    NSBox *typography =
        groupBox(NSMakeRect(0, 430, width, 80));

    [view addSubview:typography];

    addControlRow(
        typography,
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
        230,
        NO
    );
}

#pragma mark Desktop page

- (void)buildDesktopPage:(WallifyFlippedView *)view {
    const CGFloat width = 500.0;

    [view addSubview:
        label(
            @"Position",
            NSMakeRect(4, 2, width - 8, 18),
            11,
            NSFontWeightSemibold,
            [NSColor secondaryLabelColor]
        )];

    NSBox *position =
        groupBox(NSMakeRect(0, 24, width, 184));

    [view addSubview:position];

    [position addSubview:
        label(
            @"Current Position",
            NSMakeRect(18, 16, 240, 20),
            13,
            NSFontWeightMedium,
            [NSColor labelColor]
        )];

    self.gridStatusLabel =
        label(
            @"Checking…",
            NSMakeRect(18, 45, 450, 20),
            12,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        );

    self.gridStatusLabel.font =
        [NSFont monospacedSystemFontOfSize:12
                                    weight:NSFontWeightRegular];

    [position addSubview:self.gridStatusLabel];

    [position addSubview:
        label(
            @"Drag the widget on the desktop to reposition it.",
            NSMakeRect(18, 73, 450, 20),
            11,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        )];

    NSButton *reset =
        actionButton(
            @"Reset Position",
            self,
            @selector(resetPositionClicked:)
        );

    reset.frame =
        NSMakeRect(18, 116, 120, 30);

    [position addSubview:reset];

    [view addSubview:
        label(
            @"Diagnostics",
            NSMakeRect(4, 232, width - 8, 18),
            11,
            NSFontWeightSemibold,
            [NSColor secondaryLabelColor]
        )];

    NSBox *diagnostics =
        groupBox(NSMakeRect(0, 254, width, 80));

    [view addSubview:diagnostics];

    addToggleRow(
        diagnostics,
        @"Snapping Diagnostics",
        @"Show snap candidates and coordinates.",
        self.debugSwitch =
            makeToggle(4, self, @selector(switchChanged:)),
        0,
        width,
        NO
    );

    [view addSubview:
        label(
            @"Configuration",
            NSMakeRect(4, 358, width - 8, 18),
            11,
            NSFontWeightSemibold,
            [NSColor secondaryLabelColor]
        )];

    NSBox *config =
        groupBox(NSMakeRect(0, 380, width, 150));

    [view addSubview:config];

    [config addSubview:
        label(
            @"Settings File",
            NSMakeRect(18, 16, 200, 20),
            13,
            NSFontWeightMedium,
            [NSColor labelColor]
        )];

    NSString *path =
        [NSString stringWithUTF8String:
            wallify_settings_path()];

    NSTextField *pathLabel =
        label(
            path,
            NSMakeRect(18, 44, 450, 20),
            10,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        );

    pathLabel.font =
        [NSFont monospacedSystemFontOfSize:10
                                    weight:NSFontWeightRegular];

    pathLabel.lineBreakMode =
        NSLineBreakByTruncatingMiddle;

    [config addSubview:pathLabel];

    NSButton *reveal =
        actionButton(
            @"Reveal in Finder",
            self,
            @selector(revealConfigClicked:)
        );

    reveal.frame =
        NSMakeRect(18, 84, 130, 30);

    [config addSubview:reveal];

    NSButton *open =
        actionButton(
            @"Open File",
            self,
            @selector(openConfigClicked:)
        );

    open.frame =
        NSMakeRect(158, 84, 104, 30);

    [config addSubview:open];
}

#pragma mark Navigation

- (void)sidebarButtonClicked:(NSButton *)sender {
    [self selectPage:sender.tag];
}

- (void)selectPage:(NSInteger)index {
    if (index < 0 ||
        index >= (NSInteger)self.pages.count)
        return;

    NSArray<NSString *> *titles = @[
        @"General",
        @"Appearance",
        @"Playback",
        @"Desktop"
    ];

    NSArray<NSString *> *symbols = @[
        @"gearshape",
        @"paintpalette",
        @"play.circle",
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

    self.pageIconView.image =
        [NSImage imageWithSystemSymbolName:
            symbols[index]
            accessibilityDescription:nil];

    for (NSView *page in self.pages)
        [page removeFromSuperview];

    NSView *page = self.pages[index];

    CGFloat width =
        self.scrollView.contentView.bounds.size.width;

    page.frame =
        NSMakeRect(
            0,
            0,
            MAX(500.0, width - 8.0),
            page.frame.size.height
        );

    self.scrollView.documentView = page;

    [self.scrollView.contentView
        scrollToPoint:NSMakePoint(0, 0)];
}

#pragma mark Actions

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
        @"All Wallify preferences will be reset.";

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

#pragma mark State

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

    wallify_settings_get_snapshot(&s);

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
     * Native Glass owns its material/rim.
     */
    self.auroraSwitch.enabled =
        !s.native_glass;

    self.frameSegment.enabled =
        !s.native_glass;

    [self updateGridStatusLabel];
}

#pragma mark Presentation

- (void)showSettingsWindow {
    if (!self.window)
        [self createWindow];

    [self refreshUIFromState];

    [self.window center];
    [self.window makeKeyAndOrderFront:nil];

    [NSApp activateIgnoringOtherApps:YES];
}

- (void)closeSettingsWindow {
    if (self.window)
        [self.window orderOut:nil];
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
