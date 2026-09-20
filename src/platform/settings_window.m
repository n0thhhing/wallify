#import "settings_window.h"

extern const char *wallify_settings_path(void);

typedef NS_ENUM(NSInteger, WFSettingType) {
    WFSettingTypeToggle,
    WFSettingTypeSegments,
    WFSettingTypePopup,
};

typedef NS_ENUM(NSInteger, WFSectionType) {
    WFSectionTypeSettings,
    WFSectionTypePosition,
    WFSectionTypeConfiguration,
};

@interface WFSettingDefinition : NSObject
@property(nonatomic) WFSettingType type;
@property(nonatomic) NSInteger key;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *subtitle;
@property(nonatomic, copy) NSArray<NSString *> *options;
@property(nonatomic) NSInteger enabledByBoolKey;
@property(nonatomic) BOOL enabledByBoolValue;
@end

@implementation WFSettingDefinition
@end

@interface WFSectionDefinition : NSObject
@property(nonatomic) WFSectionType type;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSArray<WFSettingDefinition *> *settings;
@end

@implementation WFSectionDefinition
@end

@interface WFPageDefinition : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *symbol;
@property(nonatomic, copy) NSArray<WFSectionDefinition *> *sections;
@end

@implementation WFPageDefinition
@end

@interface WallifyFlippedVisualView : NSVisualEffectView
@end

@implementation WallifyFlippedVisualView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface WallifySettingsWindowController : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) WallifyFlippedVisualView *rootView;
@property(nonatomic, strong) WallifyFlippedVisualView *sidebarView;
@property(nonatomic, strong) NSView *contentView;
@property(nonatomic, strong) NSStackView *pageStack;
@property(nonatomic, strong) NSScrollView *scrollView;
@property(nonatomic, strong) NSImageView *pageIconView;
@property(nonatomic, strong) NSTextField *pageTitleLabel;
@property(nonatomic, strong) NSTextField *positionStatusLabel;
@property(nonatomic, strong) NSArray<NSButton *> *sidebarButtons;
@property(nonatomic, strong) NSArray<WFPageDefinition *> *pageDefinitions;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSControl *> *controlsByKey;
@property(nonatomic) NSInteger selectedPageIndex;
+ (instancetype)sharedController;
- (void)showSettingsWindow;
- (void)closeSettingsWindow;
- (void)refreshUIFromState;
@end

static WallifySettingsWindowController *sharedSettingsController = nil;

#pragma mark - Definition helpers

static WFSettingDefinition *wfSetting(
    WFSettingType type,
    NSInteger key,
    NSString *title,
    NSString *subtitle,
    NSArray<NSString *> *options
) {
    WFSettingDefinition *setting = [WFSettingDefinition new];
    setting.type = type;
    setting.key = key;
    setting.title = title;
    setting.subtitle = subtitle ?: @"";
    setting.options = options ?: @[];
    setting.enabledByBoolKey = -1;
    setting.enabledByBoolValue = YES;
    return setting;
}

static WFSettingDefinition *wfToggle(
    NSInteger key,
    NSString *title,
    NSString *subtitle
) {
    return wfSetting(WFSettingTypeToggle, key, title, subtitle, nil);
}

static WFSettingDefinition *wfSegments(
    NSInteger key,
    NSString *title,
    NSString *subtitle,
    NSArray<NSString *> *options
) {
    return wfSetting(WFSettingTypeSegments, key, title, subtitle, options);
}

static WFSettingDefinition *wfPopup(
    NSInteger key,
    NSString *title,
    NSString *subtitle,
    NSArray<NSString *> *options
) {
    return wfSetting(WFSettingTypePopup, key, title, subtitle, options);
}

static WFSectionDefinition *wfSection(
    NSString *title,
    NSArray<WFSettingDefinition *> *settings
) {
    WFSectionDefinition *section = [WFSectionDefinition new];
    section.type = WFSectionTypeSettings;
    section.title = title;
    section.settings = settings ?: @[];
    return section;
}

static WFSectionDefinition *wfSpecialSection(
    WFSectionType type,
    NSString *title
) {
    WFSectionDefinition *section = [WFSectionDefinition new];
    section.type = type;
    section.title = title;
    section.settings = @[];
    return section;
}

static WFPageDefinition *wfPage(
    NSString *title,
    NSString *symbol,
    NSArray<WFSectionDefinition *> *sections
) {
    WFPageDefinition *page = [WFPageDefinition new];
    page.title = title;
    page.symbol = symbol;
    page.sections = sections;
    return page;
}

#pragma mark - UI primitives

static NSTextField *wfLabel(
    NSString *text,
    CGFloat size,
    NSFontWeight weight,
    NSColor *color
) {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSZeroRect];

    field.stringValue = text ?: @"";
    field.font = [NSFont systemFontOfSize:size weight:weight];
    field.textColor = color;
    field.editable = NO;
    field.bezeled = NO;
    field.drawsBackground = NO;
    field.selectable = NO;
    field.usesSingleLineMode = YES;
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.translatesAutoresizingMaskIntoConstraints = NO;

    return field;
}

static NSImageView *wfSymbolView(
    NSString *symbol,
    CGFloat pointSize,
    NSFontWeight weight
) {
    NSImageView *view = [[NSImageView alloc] initWithFrame:NSZeroRect];

    view.image = [NSImage imageWithSystemSymbolName:symbol
                              accessibilityDescription:nil];
    view.symbolConfiguration =
        [NSImageSymbolConfiguration configurationWithPointSize:pointSize
                                                        weight:weight];
    view.contentTintColor = [NSColor controlAccentColor];
    view.imageScaling = NSImageScaleProportionallyUpOrDown;
    view.translatesAutoresizingMaskIntoConstraints = NO;

    return view;
}

static void wfPin(
    NSView *view,
    NSView *parent,
    CGFloat top,
    CGFloat leading,
    CGFloat bottom,
    CGFloat trailing
) {
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:parent.topAnchor constant:top],
        [view.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor constant:leading],
        [view.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor constant:-bottom],
        [view.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor constant:-trailing],
    ]];
}

static NSButton *wfButton(
    NSString *title,
    id target,
    SEL action
) {
    NSButton *button =
        [NSButton buttonWithTitle:title target:target action:action];

    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeRegular;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    return button;
}

#pragma mark - Controller

@implementation WallifySettingsWindowController

+ (instancetype)sharedController {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedSettingsController = [WallifySettingsWindowController new];
    });
    return sharedSettingsController;
}

#pragma mark Definitions

- (void)buildDefinitions {
    WFSettingDefinition *nativeGlass =
        wfToggle(5, @"Native Glass", @"Use the macOS Liquid Glass material.");

    WFSettingDefinition *glow =
        wfToggle(0, @"Artwork Glow", @"Use album artwork to create ambient color.");

    WFSettingDefinition *glowIntensity =
        wfSegments(
            11,
            @"Glow Intensity",
            @"Controls the strength of the ambient glow.",
            @[@"Low", @"Normal", @"High"]
        );
    glowIntensity.enabledByBoolKey = 0;

    WFSettingDefinition *aurora =
        wfToggle(1, @"Aurora", @"Animated background gradient.");

    WFSettingDefinition *frame =
        wfSegments(
            10,
            @"Custom Border",
            @"Border strength for the custom material.",
            @[@"Off", @"Subtle", @"Strong"]
        );
    frame.enabledByBoolKey = 5;
    frame.enabledByBoolValue = NO;

    WFSettingDefinition *animations =
        wfToggle(2, @"Animations", @"Animate widget resizing and state changes.");

    WFSettingDefinition *speed =
        wfSegments(
            12,
            @"Animation Speed",
            @"How quickly UI transitions are animated.",
            @[@"Slow", @"Normal", @"Fast"]
        );
    speed.enabledByBoolKey = 2;

    WFSettingDefinition *generalMode =
        wfSegments(
            14,
            @"Form Factor",
            @"Choose the widget footprint.",
            @[@"1 × 1", @"2 × 1", @"3 × 1", @"1 × 2", @"2 × 2"]
        );

    WFSettingDefinition *source =
        wfSegments(
            13,
            @"Media Source",
            @"Choose where Wallify reads playback information.",
            @[@"Now Playing", @"Spotify", @"Spotifast", @"Auto"]
        );

    WFSettingDefinition *idle =
        wfSegments(
            15,
            @"Idle Companion",
            @"Shown when nothing is currently playing.",
            @[@"Pixel Cat", @"Banana Cat", @"Spotify"]
        );

    WFSettingDefinition *transition =
        wfPopup(
            16,
            @"Track Transition",
            @"Effect used when artwork changes.",
            @[@"Default", @"Cinematic", @"Ripple", @"Card Flip", @"Vinyl", @"Glitch"]
        );

    WFSettingDefinition *mediaKeys =
        wfSegments(
            18,
            @"Media Key Target",
            @"Route F7, F8 and F9 through Wallify.",
            @[@"Off", @"Active", @"Spotify", @"Spotifast"]
        );

    WFSettingDefinition *artworkBorder =
        wfToggle(19, @"Artwork Border", @"Add a fine edge around album artwork.");

    WFSettingDefinition *compactGradient =
        wfToggle(20, @"Compact Contrast", @"Add a subtle fade behind text in 1 × 1 mode.");

    WFSettingDefinition *artworkRadius =
        wfSegments(
            21,
            @"Artwork Corners",
            @"Choose the album artwork corner radius.",
            @[@"Soft", @"Rounded", @"Large"]
        );

    WFSettingDefinition *dimPaused =
        wfToggle(3, @"Dim When Paused", @"Lower artwork brightness while paused.");

    WFSettingDefinition *progressThickness =
        wfSegments(
            22,
            @"Progress Thickness",
            @"Choose the visual weight of the progress bar.",
            @[@"Thin", @"Standard", @"Thick"]
        );

    WFSettingDefinition *fontScale =
        wfSegments(
            17,
            @"Font Size",
            @"Scale title, artist and playback labels.",
            @[@"Small", @"Normal", @"Large"]
        );

    WFSettingDefinition *hideText =
        wfToggle(6, @"Hide Track Text", @"Hide the title and artist labels.");

    WFSettingDefinition *hideProgress =
        wfToggle(7, @"Hide Progress Bar", @"Hide the playback progress bar.");

    WFSettingDefinition *showControls =
        wfToggle(8, @"Playback Controls", @"Show previous, play/pause and next.");

    WFSettingDefinition *showTimestamps =
        wfToggle(9, @"Time Labels", @"Show elapsed and remaining time.");

    WFSettingDefinition *debug =
        wfToggle(4, @"Snapping Diagnostics", @"Show snap candidates and coordinates.");

    self.pageDefinitions = @[
        wfPage(
            @"General",
            @"slider.horizontal.3",
            @[
                wfSection(@"Widget", @[generalMode, source]),
                wfSection(@"Idle", @[idle, transition]),
                wfSection(@"Media Keys", @[mediaKeys]),
            ]
        ),

        wfPage(
            @"Appearance",
            @"paintbrush",
            @[
                wfSection(@"Material", @[nativeGlass, glow, glowIntensity, aurora, frame]),
                wfSection(@"Artwork", @[artworkBorder, compactGradient, artworkRadius]),
                wfSection(@"Motion", @[animations, speed, dimPaused]),
            ]
        ),

        wfPage(
            @"Playback",
            @"play.circle",
            @[
                wfSection(@"Visibility", @[hideText, hideProgress, showControls, showTimestamps]),
                wfSection(@"Progress", @[progressThickness]),
                wfSection(@"Typography", @[fontScale]),
            ]
        ),

        wfPage(
            @"Desktop",
            @"rectangle.on.rectangle",
            @[
                wfSpecialSection(WFSectionTypePosition, @"Position"),
                wfSection(@"Diagnostics", @[debug]),
                wfSpecialSection(WFSectionTypeConfiguration, @"Configuration"),
            ]
        ),
    ];
}

#pragma mark Window

- (void)createWindow {
    const CGFloat width = 820.0;
    const CGFloat height = 620.0;
    const CGFloat sidebarWidth = 190.0;

    self.controlsByKey = [NSMutableDictionary dictionary];
    self.selectedPageIndex = 0;
    [self buildDefinitions];

    self.window =
        [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, width, height)
                      styleMask:
                          NSWindowStyleMaskTitled |
                          NSWindowStyleMaskClosable |
                          NSWindowStyleMaskMiniaturizable
                        backing:NSBackingStoreBuffered
                          defer:NO];

    self.window.title = @"Wallify";
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    self.window.restorable = NO;
    self.window.tabbingMode = NSWindowTabbingModeDisallowed;
    self.window.minSize = NSMakeSize(760, 560);
    self.window.collectionBehavior |= NSWindowCollectionBehaviorFullScreenAuxiliary;

    self.rootView =
        [[WallifyFlippedVisualView alloc] initWithFrame:NSZeroRect];

    self.rootView.material = NSVisualEffectMaterialUnderWindowBackground;
    self.rootView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.rootView.state = NSVisualEffectStateActive;
    self.rootView.translatesAutoresizingMaskIntoConstraints = NO;
    self.window.contentView = self.rootView;

    self.sidebarView =
        [[WallifyFlippedVisualView alloc] initWithFrame:NSZeroRect];

    self.sidebarView.material = NSVisualEffectMaterialSidebar;
    self.sidebarView.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    self.sidebarView.state = NSVisualEffectStateActive;
    self.sidebarView.translatesAutoresizingMaskIntoConstraints = NO;

    [self.rootView addSubview:self.sidebarView];

    self.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.rootView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.sidebarView.leadingAnchor constraintEqualToAnchor:self.rootView.leadingAnchor],
        [self.sidebarView.topAnchor constraintEqualToAnchor:self.rootView.topAnchor],
        [self.sidebarView.bottomAnchor constraintEqualToAnchor:self.rootView.bottomAnchor],
        [self.sidebarView.widthAnchor constraintEqualToConstant:sidebarWidth],

        [self.contentView.leadingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor],
        [self.contentView.topAnchor constraintEqualToAnchor:self.rootView.topAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.rootView.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.rootView.bottomAnchor],
    ]];

    [self buildSidebar];
    [self buildContent];
    [self selectPage:0];
}

#pragma mark Sidebar

- (void)buildSidebar {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 7.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    [self.sidebarView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.sidebarView.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:self.sidebarView.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:self.sidebarView.topAnchor constant:18],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.sidebarView.bottomAnchor constant:-18],
    ]];

    NSStackView *brand = [[NSStackView alloc] initWithFrame:NSZeroRect];
    brand.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    brand.alignment = NSLayoutAttributeCenterY;
    brand.spacing = 10.0;
    brand.edgeInsets = NSEdgeInsetsMake(0, 3, 0, 0);

    NSImageView *icon = wfSymbolView(@"music.note", 19.0, NSFontWeightSemibold);
    NSTextField *title = wfLabel(@"Wallify", 17.0, NSFontWeightSemibold, [NSColor labelColor]);

    [brand addArrangedSubview:icon];
    [brand addArrangedSubview:title];

    [stack addArrangedSubview:brand];

    NSTextField *caption =
        wfLabel(@"Preferences", 11.0, NSFontWeightMedium, [NSColor secondaryLabelColor]);
    [stack addArrangedSubview:caption];

    NSBox *divider = [[NSBox alloc] initWithFrame:NSZeroRect];
    divider.boxType = NSBoxSeparator;
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:divider];

    [divider.heightAnchor constraintEqualToConstant:1].active = YES;

    NSMutableArray<NSButton *> *buttons =
        [NSMutableArray arrayWithCapacity:self.pageDefinitions.count];

    for (NSInteger i = 0; i < (NSInteger)self.pageDefinitions.count; i++) {
        WFPageDefinition *page = self.pageDefinitions[i];

        NSButton *button =
            [NSButton buttonWithTitle:page.title
                               target:self
                               action:@selector(sidebarButtonClicked:)];

        button.tag = i;
        button.bordered = NO;
        button.alignment = NSTextAlignmentLeft;
        button.font = [NSFont systemFontOfSize:13.5 weight:NSFontWeightMedium];
        button.image =
            [NSImage imageWithSystemSymbolName:page.symbol
                         accessibilityDescription:nil];
        button.symbolConfiguration =
            [NSImageSymbolConfiguration configurationWithPointSize:14
                                                            weight:NSFontWeightMedium];
        button.imagePosition = NSImageLeft;
        button.contentTintColor = [NSColor secondaryLabelColor];
        [button setContentHuggingPriority:250.0
                   forOrientation:NSLayoutConstraintOrientationHorizontal];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.wantsLayer = YES;
        button.layer.cornerRadius = 8.0;
        button.toolTip = page.title;

        [stack addArrangedSubview:button];
        [button.heightAnchor constraintEqualToConstant:34].active = YES;
        [buttons addObject:button];
    }

    self.sidebarButtons = buttons;

    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:spacer];
    [spacer setContentHuggingPriority:1.0 forOrientation:NSLayoutConstraintOrientationVertical];
    [spacer setContentCompressionResistancePriority:1.0
                                   forOrientation:NSLayoutConstraintOrientationVertical];

    NSBox *bottomDivider = [[NSBox alloc] initWithFrame:NSZeroRect];
    bottomDivider.boxType = NSBoxSeparator;
    bottomDivider.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:bottomDivider];
    [bottomDivider.heightAnchor constraintEqualToConstant:1].active = YES;

    NSTextField *status =
        wfLabel(@"Native Metal  •  macOS", 10.5, NSFontWeightRegular,
                [NSColor tertiaryLabelColor]);
    status.maximumNumberOfLines = 1;
    [stack addArrangedSubview:status];
}

#pragma mark Content

- (void)buildContent {
    NSStackView *layout = [[NSStackView alloc] initWithFrame:NSZeroRect];
    layout.orientation = NSUserInterfaceLayoutOrientationVertical;
    layout.alignment = NSLayoutAttributeWidth;
    layout.spacing = 0.0;
    layout.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:layout];

    [NSLayoutConstraint activateConstraints:@[
        [layout.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [layout.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [layout.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [layout.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    ]];

    NSView *header = [[NSView alloc] initWithFrame:NSZeroRect];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [layout addArrangedSubview:header];
    [header.heightAnchor constraintEqualToConstant:76].active = YES;

    self.pageIconView = wfSymbolView(@"slider.horizontal.3", 20.0, NSFontWeightMedium);
    self.pageTitleLabel =
        wfLabel(@"General", 23.0, NSFontWeightBold, [NSColor labelColor]);

    [header addSubview:self.pageIconView];
    [header addSubview:self.pageTitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.pageIconView.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:28],
        [self.pageIconView.centerYAnchor constraintEqualToAnchor:header.centerYAnchor constant:-2],
        [self.pageIconView.widthAnchor constraintEqualToConstant:25],
        [self.pageIconView.heightAnchor constraintEqualToConstant:25],

        [self.pageTitleLabel.leadingAnchor constraintEqualToAnchor:self.pageIconView.trailingAnchor constant:10],
        [self.pageTitleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor constant:-2],
        [self.pageTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:header.trailingAnchor constant:-24],
    ]];

    NSBox *headerDivider = [[NSBox alloc] initWithFrame:NSZeroRect];
    headerDivider.boxType = NSBoxSeparator;
    headerDivider.translatesAutoresizingMaskIntoConstraints = NO;
    [layout addArrangedSubview:headerDivider];
    [headerDivider.heightAnchor constraintEqualToConstant:1].active = YES;

    self.scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.scrollerStyle = NSScrollerStyleOverlay;
    self.scrollView.drawsBackground = NO;
    self.scrollView.borderType = NSNoBorder;
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [layout addArrangedSubview:self.scrollView];

    [self.scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:1].active = YES;

    self.pageStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    self.pageStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.pageStack.alignment = NSLayoutAttributeWidth;
    self.pageStack.spacing = 0.0;
    self.pageStack.edgeInsets = NSEdgeInsetsMake(26, 28, 34, 28);
    self.pageStack.translatesAutoresizingMaskIntoConstraints = NO;

    [self.scrollView setDocumentView:self.pageStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.pageStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentView.leadingAnchor],
        [self.pageStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentView.trailingAnchor],
        [self.pageStack.topAnchor constraintEqualToAnchor:self.scrollView.contentView.topAnchor],
        [self.pageStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentView.bottomAnchor],
        [self.pageStack.widthAnchor constraintEqualToAnchor:self.scrollView.contentView.widthAnchor],
    ]];

    NSView *footer = [[NSView alloc] initWithFrame:NSZeroRect];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [layout addArrangedSubview:footer];
    [footer.heightAnchor constraintEqualToConstant:58].active = YES;

    NSBox *footerDivider = [[NSBox alloc] initWithFrame:NSZeroRect];
    footerDivider.boxType = NSBoxSeparator;
    footerDivider.translatesAutoresizingMaskIntoConstraints = NO;
    [footer addSubview:footerDivider];

    [footerDivider.topAnchor constraintEqualToAnchor:footer.topAnchor].active = YES;
    [footerDivider.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor].active = YES;
    [footerDivider.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor].active = YES;
    [footerDivider.heightAnchor constraintEqualToConstant:1].active = YES;

    NSButton *restore =
        wfButton(@"Restore Defaults", self, @selector(restoreDefaultsClicked:));
    restore.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *done =
        wfButton(@"Done", self, @selector(doneClicked:));
    done.keyEquivalent = @"\r";
    done.translatesAutoresizingMaskIntoConstraints = NO;

    [footer addSubview:restore];
    [footer addSubview:done];

    [NSLayoutConstraint activateConstraints:@[
        [restore.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:24],
        [restore.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor constant:1],
        [done.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-24],
        [done.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor constant:1],
        [done.widthAnchor constraintGreaterThanOrEqualToConstant:76],
    ]];
}

#pragma mark Page rendering

- (NSControl *)makeControlForDefinition:(WFSettingDefinition *)definition {
    switch (definition.type) {
        case WFSettingTypeToggle: {
            NSButton *button =
                [NSButton buttonWithTitle:@""
                                   target:self
                                   action:@selector(toggleChanged:)];
            button.buttonType = NSButtonTypeSwitch;
            button.controlSize = NSControlSizeRegular;
            button.tag = definition.key;
            return button;
        }

        case WFSettingTypeSegments: {
            NSSegmentedControl *control =
                [NSSegmentedControl segmentedControlWithLabels:
                    definition.options
                    trackingMode:NSSegmentSwitchTrackingSelectOne
                    target:self
                    action:@selector(segmentChanged:)];

            control.segmentDistribution = NSSegmentDistributionFillEqually;
            control.controlSize = NSControlSizeRegular;
            control.tag = definition.key;
            return control;
        }

        case WFSettingTypePopup: {
            NSPopUpButton *control =
                [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];

            [control addItemsWithTitles:definition.options];
            control.target = self;
            control.action = @selector(popupChanged:);
            control.tag = definition.key;
            return control;
        }
    }

    return nil;
}

- (NSView *)makeSettingRow:(WFSettingDefinition *)definition last:(BOOL)last {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *labels = [[NSStackView alloc] initWithFrame:NSZeroRect];
    labels.orientation = NSUserInterfaceLayoutOrientationVertical;
    labels.alignment = NSLayoutAttributeLeading;
    labels.spacing = 3.0;
    labels.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *title =
        wfLabel(definition.title, 13.0, NSFontWeightMedium, [NSColor labelColor]);
    title.usesSingleLineMode = NO;
    title.maximumNumberOfLines = 2;

    [labels addArrangedSubview:title];

    if (definition.subtitle.length > 0) {
        NSTextField *subtitle =
            wfLabel(definition.subtitle, 11.0, NSFontWeightRegular,
                    [NSColor secondaryLabelColor]);
        subtitle.usesSingleLineMode = NO;
        subtitle.maximumNumberOfLines = 2;
        [labels addArrangedSubview:subtitle];
    }

    NSControl *control = [self makeControlForDefinition:definition];
    control.translatesAutoresizingMaskIntoConstraints = NO;

    [row addSubview:labels];
    [row addSubview:control];

    CGFloat minimumControlWidth = 72.0;
    CGFloat maximumControlWidth = 320.0;

    if ([control isKindOfClass:[NSSegmentedControl class]]) {
        NSInteger count = definition.options.count;
        minimumControlWidth = MIN(320.0, MAX(120.0, count * 72.0));
        maximumControlWidth = MAX(minimumControlWidth, 320.0);
    } else if ([control isKindOfClass:[NSPopUpButton class]]) {
        minimumControlWidth = 150.0;
        maximumControlWidth = 230.0;
    }

    [NSLayoutConstraint activateConstraints:@[
        [labels.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:2],
        [labels.topAnchor constraintEqualToAnchor:row.topAnchor constant:11],
        [labels.bottomAnchor constraintEqualToAnchor:row.bottomAnchor constant:-11],

        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-2],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [control.widthAnchor constraintGreaterThanOrEqualToConstant:minimumControlWidth],
        [control.widthAnchor constraintLessThanOrEqualToConstant:maximumControlWidth],

        [labels.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-18],

        [row.heightAnchor constraintGreaterThanOrEqualToConstant:59],
    ]];

    [control setContentHuggingPriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [control setContentCompressionResistancePriority:750 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [labels setContentCompressionResistancePriority:250
                                  forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.controlsByKey[@(definition.key)] = control;

    if (!last) {
        NSBox *line = [[NSBox alloc] initWithFrame:NSZeroRect];
        line.boxType = NSBoxSeparator;
        line.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:line];

        [NSLayoutConstraint activateConstraints:@[
            [line.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [line.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [line.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
            [line.heightAnchor constraintEqualToConstant:1],
        ]];
    }

    return row;
}

- (NSView *)makeSection:(WFSectionDefinition *)section {
    NSStackView *sectionStack =
        [[NSStackView alloc] initWithFrame:NSZeroRect];

    sectionStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    sectionStack.alignment = NSLayoutAttributeWidth;
    sectionStack.spacing = 0.0;
    sectionStack.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *header =
        wfLabel(section.title, 11.0, NSFontWeightSemibold, [NSColor secondaryLabelColor]);
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [sectionStack addArrangedSubview:header];

    [header.topAnchor constraintEqualToAnchor:sectionStack.topAnchor].active = YES;

    NSView *card = [[NSView alloc] initWithFrame:NSZeroRect];
    card.wantsLayer = YES;
    card.layer.cornerRadius = 11.0;
    card.layer.masksToBounds = YES;
    card.layer.backgroundColor =
        [[NSColor controlBackgroundColor] colorWithAlphaComponent:0.48].CGColor;
    card.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *rows =
        [[NSStackView alloc] initWithFrame:NSZeroRect];

    rows.orientation = NSUserInterfaceLayoutOrientationVertical;
    rows.alignment = NSLayoutAttributeFill;
    rows.spacing = 0.0;
    rows.translatesAutoresizingMaskIntoConstraints = NO;

    [card addSubview:rows];
    wfPin(rows, card, 0, 0, 0, 0);

    [sectionStack addArrangedSubview:card];

    if (section.type == WFSectionTypeSettings) {
        for (NSInteger i = 0; i < (NSInteger)section.settings.count; i++) {
            [rows addArrangedSubview:
                [self makeSettingRow:section.settings[i]
                                last:i == (NSInteger)section.settings.count - 1]];
        }
    } else if (section.type == WFSectionTypePosition) {
        [rows addArrangedSubview:[self makePositionContent]];
    } else if (section.type == WFSectionTypeConfiguration) {
        [rows addArrangedSubview:[self makeConfigurationContent]];
    }

    return sectionStack;
}

#pragma mark Section-specific content

- (NSView *)makePositionContent {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 7.0;
    stack.edgeInsets = NSEdgeInsetsMake(14, 14, 14, 14);
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *value =
        wfLabel(@"Checking…", 12.0, NSFontWeightRegular, [NSColor labelColor]);
    value.font = [NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular];
    self.positionStatusLabel = value;

    NSTextField *hint =
        wfLabel(
            @"Drag the widget on the desktop to reposition it.",
            11.0,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        );
    hint.usesSingleLineMode = NO;
    hint.maximumNumberOfLines = 2;

    NSButton *reset =
        wfButton(@"Reset Position", self, @selector(resetPositionClicked:));

    [stack addArrangedSubview:value];
    [stack addArrangedSubview:hint];
    [stack addArrangedSubview:reset];

    return stack;
}

- (NSView *)makeConfigurationContent {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 9.0;
    stack.edgeInsets = NSEdgeInsetsMake(14, 14, 14, 14);
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    NSString *path =
        [NSString stringWithUTF8String:wallify_settings_path()];

    NSTextField *pathLabel =
        wfLabel(path, 10.5, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    pathLabel.font = [NSFont monospacedSystemFontOfSize:10.5 weight:NSFontWeightRegular];
    pathLabel.maximumNumberOfLines = 2;
    pathLabel.usesSingleLineMode = NO;
    pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    NSStackView *buttons = [[NSStackView alloc] initWithFrame:NSZeroRect];
    buttons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    buttons.alignment = NSLayoutAttributeCenterY;
    buttons.spacing = 8.0;

    [buttons addArrangedSubview:
        wfButton(@"Reveal in Finder", self, @selector(revealConfigClicked:))];

    [buttons addArrangedSubview:
        wfButton(@"Open File", self, @selector(openConfigClicked:))];

    [stack addArrangedSubview:pathLabel];
    [stack addArrangedSubview:buttons];

    return stack;
}

- (void)renderSelectedPage {
    [self.pageStack.arrangedSubviews
        enumerateObjectsUsingBlock:^(NSView *view, NSUInteger idx, BOOL *stop) {
            (void)idx;
            (void)stop;
            [self.pageStack removeArrangedSubview:view];
            [view removeFromSuperview];
        }];

    self.controlsByKey = [NSMutableDictionary dictionary];

    WFPageDefinition *page = self.pageDefinitions[self.selectedPageIndex];

    for (WFSectionDefinition *section in page.sections) {
        [self.pageStack addArrangedSubview:[self makeSection:section]];
    }

    self.pageTitleLabel.stringValue = page.title;
    self.pageIconView.image =
        [NSImage imageWithSystemSymbolName:page.symbol
                     accessibilityDescription:nil];

    [self.scrollView.documentView
        scrollPoint:NSMakePoint(0, CGFLOAT_MAX)];

    [self refreshUIFromState];
}

#pragma mark Navigation

- (void)sidebarButtonClicked:(NSButton *)sender {
    [self selectPage:sender.tag];
}

- (void)selectPage:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.pageDefinitions.count)
        return;

    self.selectedPageIndex = index;

    for (NSButton *button in self.sidebarButtons) {
        BOOL selected = button.tag == index;

        button.layer.backgroundColor =
            selected
                ? [NSColor selectedControlColor].CGColor
                : NSColor.clearColor.CGColor;

        button.contentTintColor =
            selected
                ? [NSColor selectedControlTextColor]
                : [NSColor secondaryLabelColor];
    }

    [self renderSelectedPage];
}

#pragma mark Actions

- (void)toggleChanged:(NSButton *)sender {
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

- (void)popupChanged:(NSPopUpButton *)sender {
    wallify_settings_apply_int(
        (int)sender.tag,
        (int)sender.indexOfSelectedItem
    );

    [self refreshUIFromState];
}

- (void)resetPositionClicked:(id)sender {
    (void)sender;

    wallify_settings_reset_position();
    [self updatePositionStatus];
}

- (void)restoreDefaultsClicked:(id)sender {
    (void)sender;

    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Restore Default Settings?";
    alert.informativeText = @"All Wallify preferences will be reset.";
    alert.alertStyle = NSAlertStyleWarning;

    [alert addButtonWithTitle:@"Restore Defaults"];
    [alert addButtonWithTitle:@"Cancel"];

    if ([alert runModal] == NSAlertFirstButtonReturn) {
        wallify_settings_restore_defaults();
        [self refreshUIFromState];
    }
}

- (void)revealConfigClicked:(id)sender {
    (void)sender;

    NSString *path =
        [NSString stringWithUTF8String:wallify_settings_path()];

    [[NSWorkspace sharedWorkspace]
        selectFile:path
        inFileViewerRootedAtPath:@""];
}

- (void)openConfigClicked:(id)sender {
    (void)sender;

    NSString *path =
        [NSString stringWithUTF8String:wallify_settings_path()];

    [[NSWorkspace sharedWorkspace]
        openURL:[NSURL fileURLWithPath:path]];
}

- (void)doneClicked:(id)sender {
    (void)sender;
    [self closeSettingsWindow];
}

#pragma mark State

- (void)updatePositionStatus {
    if (!self.positionStatusLabel)
        return;

    WallifySettingsSnapshot snapshot;
    wallify_settings_get_snapshot(&snapshot);

    self.positionStatusLabel.stringValue =
        [NSString stringWithFormat:
            @"Left %d pt   •   Top %d pt   •   Grid %d, %d",
            snapshot.margin_left,
            snapshot.margin_top,
            snapshot.grid_x,
            snapshot.grid_y];
}

- (void)applyControlStateFromSnapshot:(WallifySettingsSnapshot)snapshot
                            definition:(WFSettingDefinition *)definition
                              control:(NSControl *)control {
    NSInteger index = -1;

    switch (definition.key) {
        case 0: index = snapshot.glow; break;
        case 1: index = snapshot.aurora; break;
        case 2: index = snapshot.animations; break;
        case 3: index = snapshot.dim_paused; break;
        case 4: index = snapshot.debug_hud; break;
        case 5: index = snapshot.native_glass; break;
        case 6: index = snapshot.hide_text; break;
        case 7: index = snapshot.hide_progress; break;
        case 8: index = snapshot.show_controls; break;
        case 9: index = snapshot.show_timestamps; break;
        case 10: index = snapshot.frame_strength; break;
        case 11: index = snapshot.glow_intensity; break;
        case 12: index = snapshot.animation_speed; break;
        case 13: index = snapshot.media_source; break;
        case 14: index = snapshot.widget_mode; break;
        case 15: index = snapshot.idle_style; break;
        case 16: index = snapshot.track_transition; break;
        case 17: index = snapshot.font_scale; break;
        case 18: index = snapshot.media_key_target; break;
        case 19: index = snapshot.artwork_border; break;
        case 20: index = snapshot.compact_gradient; break;
        case 21: index = snapshot.artwork_radius; break;
        case 22: index = snapshot.progress_thickness; break;
        default: break;
    }

    if ([control isKindOfClass:[NSButton class]] &&
        definition.type == WFSettingTypeToggle) {
        [(NSButton *)control setState:
            index != 0
                ? NSControlStateValueOn
                : NSControlStateValueOff];
    } else if ([control isKindOfClass:[NSSegmentedControl class]]) {
        NSSegmentedControl *segments = (NSSegmentedControl *)control;
        if (index >= 0 && index < segments.segmentCount)
            segments.selectedSegment = index;
    } else if ([control isKindOfClass:[NSPopUpButton class]]) {
        NSPopUpButton *popup = (NSPopUpButton *)control;
        if (index >= 0 && index < popup.numberOfItems)
            [popup selectItemAtIndex:index];
    }

    if (definition.enabledByBoolKey >= 0) {
        BOOL enabled = YES;

        NSNumber *dependencyValue =
            @{
                @0: @(snapshot.glow),
                @2: @(snapshot.animations),
                @5: @(snapshot.native_glass),
            }[@(definition.enabledByBoolKey)];

        if (dependencyValue)
            enabled = dependencyValue.boolValue == definition.enabledByBoolValue;

        /*
         * A disabled dependent control is allowed to remain stored in the
         * configuration. This only changes whether it can be edited.
         */
        control.enabled = enabled;
    }
}

- (void)refreshUIFromState {
    if (!self.window)
        return;

    WallifySettingsSnapshot snapshot;
    wallify_settings_get_snapshot(&snapshot);

    for (NSNumber *key in self.controlsByKey) {
        NSControl *control = self.controlsByKey[key];

        WFSettingDefinition *definition = nil;

        for (WFPageDefinition *page in self.pageDefinitions) {
            for (WFSectionDefinition *section in page.sections) {
                for (WFSettingDefinition *candidate in section.settings) {
                    if (candidate.key == key.integerValue) {
                        definition = candidate;
                        break;
                    }
                }
                if (definition)
                    break;
            }
            if (definition)
                break;
        }

        if (definition) {
            [self applyControlStateFromSnapshot:snapshot
                                       definition:definition
                                         control:control];
        }
    }

    [self updatePositionStatus];
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
                updatePositionStatus];
        }
    );
}

bool wallify_has_settings_flag(void) {
    NSArray *args = [NSProcessInfo processInfo].arguments;

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
                [sharedSettingsController refreshUIFromState];
            }
        }
    );
}
