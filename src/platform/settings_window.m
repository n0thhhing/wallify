#import "settings_window.h"
#import <objc/message.h>

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

#pragma mark - Glass

@interface WFGlassFallbackView : NSVisualEffectView
@end

@implementation WFGlassFallbackView
@end

static NSView *wfMakeGlassView(NSRect frame) {
    if (@available(macOS 26.0, *)) {
        NSGlassEffectView *glass =
            [[NSGlassEffectView alloc] initWithFrame:frame];

        /*
         * Private variant 2 is the HUD/dock-style Liquid Glass material
         * on current macOS 26+ runtimes. The public API only exposes the
         * Regular and Clear styles; keep the runtime check so older/newer
         * runtimes can safely fall back to the public style.
         */
        glass.style = NSGlassEffectViewStyleRegular;

        SEL setVariant = NSSelectorFromString(@"set_variant:");
        if ([glass respondsToSelector:setVariant]) {
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(
                glass,
                setVariant,
                2
            );
        }

        glass.cornerRadius = 0.0;
        glass.tintColor = nil;
        glass.effectIsInteractive = YES;
        return glass;
    }

    WFGlassFallbackView *fallback =
        [[WFGlassFallbackView alloc] initWithFrame:frame];

    fallback.material = NSVisualEffectMaterialHUDWindow;
    fallback.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    fallback.state = NSVisualEffectStateActive;
    fallback.emphasized = YES;
    return fallback;
}

#pragma mark - Generic controls

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
    field.lineBreakMode = NSLineBreakByTruncatingTail;
    field.usesSingleLineMode = YES;
    field.maximumNumberOfLines = 1;

    return field;
}

static NSButton *wfButton(
    NSString *title,
    id target,
    SEL action
) {
    NSButton *button =
        [NSButton buttonWithTitle:title
                           target:target
                           action:action];

    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeRegular;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    return button;
}

static NSImageView *wfSymbol(
    NSString *name,
    CGFloat size,
    NSFontWeight weight
) {
    NSImageView *view = [[NSImageView alloc] initWithFrame:NSZeroRect];

    view.image =
        [NSImage imageWithSystemSymbolName:name
                     accessibilityDescription:nil];

    view.symbolConfiguration =
        [NSImageSymbolConfiguration
            configurationWithPointSize:size
                                 weight:weight];

    view.contentTintColor = [NSColor controlAccentColor];
    view.imageScaling = NSImageScaleProportionallyUpOrDown;
    return view;
}

#pragma mark - Setting row

@interface WFSettingRowView : NSView
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *subtitleLabel;
@property(nonatomic, strong) NSControl *control;
@end

@implementation WFSettingRowView

- (instancetype)initWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                       control:(NSControl *)control {
    self = [super initWithFrame:NSZeroRect];
    if (!self)
        return nil;

    self.titleLabel =
        wfLabel(title, 13.0, NSFontWeightMedium, [NSColor labelColor]);

    self.subtitleLabel =
        wfLabel(subtitle, 11.0, NSFontWeightRegular,
                [NSColor secondaryLabelColor]);

    self.subtitleLabel.maximumNumberOfLines = 1;

    self.control = control;
    [self addSubview:self.titleLabel];

    if (subtitle.length > 0)
        [self addSubview:self.subtitleLabel];

    [self addSubview:self.control];

    return self;
}

- (void)layout {
    [super layout];

    const CGFloat horizontalPadding = 2.0;
    const CGFloat controlGap = 18.0;
    const CGFloat textGap = 3.0;

    CGFloat availableControlWidth = 72.0;

    if ([self.control isKindOfClass:[NSSegmentedControl class]]) {
        availableControlWidth =
            MIN(
                320.0,
                MAX(190.0, self.bounds.size.width * 0.52)
            );
    } else if ([self.control isKindOfClass:[NSPopUpButton class]]) {
        availableControlWidth = 190.0;
    }

    CGFloat controlX =
        self.bounds.size.width -
        horizontalPadding -
        availableControlWidth;

    CGFloat controlY =
        floor((self.bounds.size.height - self.control.frame.size.height) * 0.5);

    self.control.frame =
        NSMakeRect(
            controlX,
            controlY,
            availableControlWidth,
            self.control.frame.size.height > 0
                ? self.control.frame.size.height
                : 24.0
        );

    CGFloat textWidth =
        MAX(80.0, controlX - controlGap - horizontalPadding);

    if (self.subtitleLabel.superview) {
        self.titleLabel.frame =
            NSMakeRect(
                horizontalPadding,
                15.0,
                textWidth,
                18.0
            );

        self.subtitleLabel.frame =
            NSMakeRect(
                horizontalPadding,
                36.0,
                textWidth,
                16.0
            );
    } else {
        self.titleLabel.frame =
            NSMakeRect(
                horizontalPadding,
                floor((self.bounds.size.height - 18.0) * 0.5),
                textWidth,
                18.0
            );
    }

    (void)textGap;
}

@end

#pragma mark - Section view

@interface WFSectionView : NSView
@property(nonatomic, strong) NSTextField *headerLabel;
@property(nonatomic, strong) NSArray<WFSettingRowView *> *rows;
@property(nonatomic, copy) NSString *sectionTitle;
@property(nonatomic) WFSectionType type;
@property(nonatomic, strong) NSView *specialContent;
@end

@implementation WFSectionView

- (instancetype)initWithDefinition:(WFSectionDefinition *)definition
                             target:(id)target
                           controls:(NSMutableDictionary<NSNumber *, NSControl *> *)controls {
    self = [super initWithFrame:NSZeroRect];
    if (!self)
        return nil;

    self.type = definition.type;
    self.sectionTitle = definition.title;

    self.headerLabel =
        wfLabel(
            definition.title,
            11.0,
            NSFontWeightSemibold,
            [NSColor secondaryLabelColor]
        );

    [self addSubview:self.headerLabel];

    if (definition.type == WFSectionTypeSettings) {
        NSMutableArray<WFSettingRowView *> *rows =
            [NSMutableArray arrayWithCapacity:definition.settings.count];

        for (WFSettingDefinition *setting in definition.settings) {
            NSControl *control = nil;

            if (setting.type == WFSettingTypeToggle) {
                NSButton *toggle =
                    [NSButton buttonWithTitle:@""
                                       target:target
                                       action:@selector(toggleChanged:)];

                toggle.buttonType = NSButtonTypeSwitch;
                toggle.controlSize = NSControlSizeRegular;
                toggle.tag = setting.key;
                toggle.frame = NSMakeRect(0, 0, 58, 24);
                control = toggle;

            } else if (setting.type == WFSettingTypeSegments) {
                NSSegmentedControl *segments =
                    [NSSegmentedControl
                        segmentedControlWithLabels:setting.options
                        trackingMode:NSSegmentSwitchTrackingSelectOne
                        target:target
                        action:@selector(segmentChanged:)];

                segments.segmentDistribution =
                    NSSegmentDistributionFillEqually;
                segments.controlSize = NSControlSizeRegular;
                segments.tag = setting.key;
                segments.frame = NSMakeRect(0, 0, 250, 24);
                control = segments;

            } else if (setting.type == WFSettingTypePopup) {
                NSPopUpButton *popup =
                    [[NSPopUpButton alloc]
                        initWithFrame:NSMakeRect(0, 0, 190, 24)
                        pullsDown:NO];

                [popup addItemsWithTitles:setting.options];
                popup.target = target;
                popup.action = @selector(popupChanged:);
                popup.tag = setting.key;
                control = popup;
            }

            if (!control)
                continue;

            controls[@(setting.key)] = control;

            [rows addObject:
                [[WFSettingRowView alloc]
                    initWithTitle:setting.title
                    subtitle:setting.subtitle
                    control:control]];
        }

        self.rows = rows;

        for (WFSettingRowView *row in rows)
            [self addSubview:row];

    } else if (definition.type == WFSectionTypePosition) {
        NSView *content = [[NSView alloc] initWithFrame:NSZeroRect];

        NSTextField *status =
            wfLabel(
                @"Checking…",
                12.0,
                NSFontWeightRegular,
                [NSColor labelColor]
            );

        status.font =
            [NSFont monospacedSystemFontOfSize:12
                                        weight:NSFontWeightRegular];

        status.tag = 1001;

        NSTextField *hint =
            wfLabel(
                @"Drag the widget on the desktop to reposition it.",
                11.0,
                NSFontWeightRegular,
                [NSColor secondaryLabelColor]
            );

        NSButton *reset =
            wfButton(
                @"Reset Position",
                target,
                @selector(resetPositionClicked:)
            );

        [content addSubview:status];
        [content addSubview:hint];
        [content addSubview:reset];

        self.specialContent = content;
        [self addSubview:content];

    } else if (definition.type == WFSectionTypeConfiguration) {
        NSView *content = [[NSView alloc] initWithFrame:NSZeroRect];

        NSString *path =
            [NSString stringWithUTF8String:wallify_settings_path()];

        NSTextField *pathLabel =
            wfLabel(
                path,
                10.5,
                NSFontWeightRegular,
                [NSColor secondaryLabelColor]
            );

        pathLabel.font =
            [NSFont monospacedSystemFontOfSize:10.5
                                        weight:NSFontWeightRegular];

        pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

        NSButton *reveal =
            wfButton(
                @"Reveal in Finder",
                target,
                @selector(revealConfigClicked:)
            );

        NSButton *open =
            wfButton(
                @"Open File",
                target,
                @selector(openConfigClicked:)
            );

        [content addSubview:pathLabel];
        [content addSubview:reveal];
        [content addSubview:open];

        self.specialContent = content;
        [self addSubview:content];
    }

    return self;
}

- (CGFloat)preferredHeight {
    if (self.type == WFSectionTypeSettings) {
        return 31.0 +
               MAX(0.0, self.rows.count * 66.0);
    }

    if (self.type == WFSectionTypePosition ||
        self.type == WFSectionTypeConfiguration) {
        return 31.0 + 112.0;
    }

    return 31.0;
}

- (void)layout {
    [super layout];

    const CGFloat headerHeight = 20.0;

    self.headerLabel.frame =
        NSMakeRect(
            2,
            0,
            self.bounds.size.width - 4,
            headerHeight
        );

    if (self.type == WFSectionTypeSettings) {
        CGFloat y = headerHeight + 3.0;

        for (NSInteger i = 0; i < (NSInteger)self.rows.count; i++) {
            WFSettingRowView *row = self.rows[i];

            row.frame =
                NSMakeRect(
                    0,
                    y,
                    self.bounds.size.width,
                    65.0
                );

            if (i < (NSInteger)self.rows.count - 1) {
                NSBox *separator = nil;

                for (NSView *subview in row.subviews) {
                    if ([subview.identifier isEqualToString:@"separator"]) {
                        separator = (NSBox *)subview;
                        break;
                    }
                }

                if (!separator) {
                    separator =
                        [[NSBox alloc]
                            initWithFrame:NSMakeRect(0, 64, self.bounds.size.width, 1)];

                    separator.boxType = NSBoxSeparator;
                    separator.identifier = @"separator";
                    [row addSubview:separator];
                }

                separator.frame =
                    NSMakeRect(
                        2,
                        64,
                        MAX(0.0, row.bounds.size.width - 2),
                        1
                    );
            }

            y += 66.0;
        }

    } else if (self.specialContent) {
        CGFloat top = headerHeight + 3.0;

        self.specialContent.frame =
            NSMakeRect(
                0,
                top,
                self.bounds.size.width,
                109.0
            );

        NSArray<NSView *> *views = self.specialContent.subviews;

        if (self.type == WFSectionTypePosition && views.count >= 3) {
            NSTextField *status = (NSTextField *)views[0];
            NSTextField *hint = (NSTextField *)views[1];
            NSButton *reset = (NSButton *)views[2];

            status.frame =
                NSMakeRect(2, 7, self.bounds.size.width - 4, 18);
            hint.frame =
                NSMakeRect(2, 31, self.bounds.size.width - 4, 18);
            reset.frame =
                NSMakeRect(2, 60, 120, 30);

        } else if (self.type == WFSectionTypeConfiguration &&
                   views.count >= 3) {
            NSTextField *path = (NSTextField *)views[0];
            NSButton *reveal = (NSButton *)views[1];
            NSButton *open = (NSButton *)views[2];

            path.frame =
                NSMakeRect(2, 8, self.bounds.size.width - 4, 18);

            reveal.frame = NSMakeRect(2, 44, 132, 30);
            open.frame = NSMakeRect(142, 44, 104, 30);
        }
    }
}

@end

#pragma mark - Page view

@interface WFPageView : NSView
@property(nonatomic, strong) NSArray<WFSectionView *> *sections;
- (CGFloat)preferredHeight;
@end

@implementation WFPageView

- (instancetype)initWithSections:(NSArray<WFSectionView *> *)sections {
    self = [super initWithFrame:NSZeroRect];
    if (!self)
        return nil;

    self.sections = sections;

    for (WFSectionView *section in sections)
        [self addSubview:section];

    return self;
}

- (CGFloat)preferredHeight {
    CGFloat height = 26.0;

    for (WFSectionView *section in self.sections)
        height += [section preferredHeight] + 24.0;

    return height + 26.0;
}

- (void)layout {
    [super layout];

    CGFloat y = 26.0;

    for (WFSectionView *section in self.sections) {
        CGFloat h = [section preferredHeight];

        section.frame =
            NSMakeRect(
                26.0,
                y,
                MAX(100.0, self.bounds.size.width - 52.0),
                h
            );

        y += h + 24.0;
    }
}

@end

#pragma mark - Content view

@class WallifySettingsWindowController;

@interface WFSettingsContentView : NSView
@property(nonatomic, weak) WallifySettingsWindowController *controller;
@end

#pragma mark - Controller

@interface WallifySettingsWindowController : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSView *glassView;
@property(nonatomic, strong) NSView *glassContentView;
@property(nonatomic, strong) WFSettingsContentView *contentRoot;
@property(nonatomic, strong) NSView *sidebarView;
@property(nonatomic, strong) NSView *mainView;
@property(nonatomic, strong) NSScrollView *scrollView;
@property(nonatomic, strong) WFPageView *currentPage;
@property(nonatomic, strong) NSImageView *pageIconView;
@property(nonatomic, strong) NSTextField *pageTitleLabel;
@property(nonatomic, strong) NSTextField *positionStatusLabel;
@property(nonatomic, strong) NSArray<NSButton *> *sidebarButtons;
@property(nonatomic, strong) NSArray<WFPageDefinition *> *pageDefinitions;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, NSControl *> *controlsByKey;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, WFSettingDefinition *> *definitionsByKey;
@property(nonatomic) NSInteger selectedPageIndex;
+ (instancetype)sharedController;
- (void)showSettingsWindow;
- (void)closeSettingsWindow;
- (void)refreshUIFromState;
- (void)layoutContent;
- (void)selectPage:(NSInteger)index;
@end

@implementation WFSettingsContentView

- (BOOL)isFlipped {
    return YES;
}

- (void)layout {
    [super layout];

    [self.controller layoutContent];
}

@end

#pragma mark - Controller implementation

static WallifySettingsWindowController *sharedSettingsController = nil;

@implementation WallifySettingsWindowController

+ (instancetype)sharedController {
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        sharedSettingsController =
            [[WallifySettingsWindowController alloc] init];
    });

    return sharedSettingsController;
}

#pragma mark Definitions

- (void)buildDefinitions {
    self.controlsByKey = [NSMutableDictionary dictionary];
    self.definitionsByKey = [NSMutableDictionary dictionary];

    WFSettingDefinition *formFactor =
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
            @"Shown when nothing is playing.",
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

    WFSettingDefinition *nativeGlass =
        wfToggle(
            5,
            @"Native Glass",
            @"Use the macOS Liquid Glass material."
        );

    WFSettingDefinition *glow =
        wfToggle(
            0,
            @"Artwork Glow",
            @"Use album artwork to create ambient color."
        );

    WFSettingDefinition *glowIntensity =
        wfSegments(
            11,
            @"Glow Intensity",
            @"Control the strength of the ambient glow.",
            @[@"Low", @"Normal", @"High"]
        );
    glowIntensity.enabledByBoolKey = 0;

    WFSettingDefinition *aurora =
        wfToggle(
            1,
            @"Aurora",
            @"Animated background gradient."
        );
    aurora.enabledByBoolKey = 5;
    aurora.enabledByBoolValue = NO;

    WFSettingDefinition *frame =
        wfSegments(
            10,
            @"Custom Border",
            @"Border strength for the custom material.",
            @[@"Off", @"Subtle", @"Strong"]
        );
    frame.enabledByBoolKey = 5;
    frame.enabledByBoolValue = NO;

    WFSettingDefinition *artworkBorder =
        wfToggle(
            19,
            @"Artwork Border",
            @"Add a fine edge around album artwork."
        );

    WFSettingDefinition *compactGradient =
        wfToggle(
            20,
            @"Compact Contrast",
            @"Add a subtle fade behind text in 1 × 1 mode."
        );

    WFSettingDefinition *artworkRadius =
        wfSegments(
            21,
            @"Artwork Corners",
            @"Choose the album artwork corner radius.",
            @[@"Soft", @"Rounded", @"Large"]
        );

    WFSettingDefinition *animations =
        wfToggle(
            2,
            @"Animations",
            @"Animate resizing and state changes."
        );

    WFSettingDefinition *speed =
        wfSegments(
            12,
            @"Animation Speed",
            @"Control the speed of transitions.",
            @[@"Slow", @"Normal", @"Fast"]
        );
    speed.enabledByBoolKey = 2;

    WFSettingDefinition *dimPaused =
        wfToggle(
            3,
            @"Dim When Paused",
            @"Lower artwork brightness while paused."
        );

    WFSettingDefinition *hideText =
        wfToggle(
            6,
            @"Hide Track Text",
            @"Hide the title and artist labels."
        );

    WFSettingDefinition *hideProgress =
        wfToggle(
            7,
            @"Hide Progress Bar",
            @"Hide the playback progress bar."
        );

    WFSettingDefinition *showControls =
        wfToggle(
            8,
            @"Playback Controls",
            @"Show previous, play/pause and next."
        );

    WFSettingDefinition *showTimestamps =
        wfToggle(
            9,
            @"Time Labels",
            @"Show elapsed and remaining time."
        );

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

    WFSettingDefinition *debug =
        wfToggle(
            4,
            @"Snapping Diagnostics",
            @"Show snap candidates and coordinates."
        );

    self.pageDefinitions = @[
        wfPage(
            @"General",
            @"slider.horizontal.3",
            @[
                wfSection(@"Widget", @[formFactor, source]),
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

    for (WFPageDefinition *page in self.pageDefinitions) {
        for (WFSectionDefinition *section in page.sections) {
            for (WFSettingDefinition *setting in section.settings) {
                self.definitionsByKey[@(setting.key)] = setting;
            }
        }
    }
}

#pragma mark Window

- (void)createWindow {
    [self buildDefinitions];

    const CGFloat width = 860.0;
    const CGFloat height = 620.0;

    self.window =
        [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, width, height)
                      styleMask:
                          NSWindowStyleMaskTitled |
                          NSWindowStyleMaskClosable |
                          NSWindowStyleMaskMiniaturizable |
                          NSWindowStyleMaskResizable |
                          NSWindowStyleMaskFullSizeContentView
                        backing:NSBackingStoreBuffered
                          defer:NO];

    self.window.title = @"Wallify Settings";
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    self.window.restorable = NO;
    self.window.tabbingMode = NSWindowTabbingModeDisallowed;
    self.window.minSize = NSMakeSize(760.0, 560.0);
    self.window.contentMinSize = NSMakeSize(760.0, 560.0);
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.opaque = NO;
    self.window.backgroundColor = NSColor.clearColor;
    self.window.hasShadow = YES;
    self.window.movableByWindowBackground = YES;
    self.window.collectionBehavior =
        NSWindowCollectionBehaviorFullScreenAuxiliary;

    [self.window setFrameAutosaveName:@"Wallify.SettingsWindow"];

    self.glassView =
        wfMakeGlassView(
            NSMakeRect(0, 0, width, height)
        );

    self.glassView.autoresizingMask =
        NSViewWidthSizable |
        NSViewHeightSizable;

    self.window.contentView =
        self.glassView;

    self.glassContentView =
        [[NSView alloc]
            initWithFrame:self.glassView.bounds];

    self.glassContentView.autoresizingMask =
        NSViewWidthSizable |
        NSViewHeightSizable;

    self.glassContentView.wantsLayer = YES;
    self.glassContentView.layer.backgroundColor =
        NSColor.clearColor.CGColor;

    if ([self.glassView respondsToSelector:@selector(setContentView:)]) {
        [(NSGlassEffectView *)self.glassView
            setContentView:self.glassContentView];
    } else {
        [self.glassView addSubview:self.glassContentView];
    }

    self.contentRoot =
        [[WFSettingsContentView alloc]
            initWithFrame:self.glassContentView.bounds];

    self.contentRoot.controller = self;
    self.contentRoot.autoresizingMask =
        NSViewWidthSizable |
        NSViewHeightSizable;

    [self.glassContentView addSubview:self.contentRoot];

    [self buildSidebar];
    [self buildMainView];
    [self selectPage:0];
}

#pragma mark Sidebar

- (void)buildSidebar {
    self.sidebarView =
        [[NSView alloc]
            initWithFrame:NSZeroRect];

    self.sidebarView.wantsLayer = YES;
    self.sidebarView.layer.backgroundColor =
        [[NSColor controlBackgroundColor]
            colorWithAlphaComponent:0.12].CGColor;

    [self.contentRoot addSubview:self.sidebarView];

    NSImageView *appIcon =
        wfSymbol(@"music.note", 21.0, NSFontWeightSemibold);

    NSTextField *appName =
        wfLabel(
            @"Wallify",
            17.0,
            NSFontWeightSemibold,
            [NSColor labelColor]
        );

    [self.sidebarView addSubview:appIcon];
    [self.sidebarView addSubview:appName];

    NSTextField *caption =
        wfLabel(
            @"Preferences",
            11.0,
            NSFontWeightRegular,
            [NSColor secondaryLabelColor]
        );

    [self.sidebarView addSubview:caption];

    NSArray<NSString *> *titles = @[
        @"General",
        @"Appearance",
        @"Playback",
        @"Desktop"
    ];

    NSArray<NSString *> *symbols = @[
        @"slider.horizontal.3",
        @"paintbrush",
        @"play.circle",
        @"rectangle.on.rectangle"
    ];

    NSMutableArray<NSButton *> *buttons =
        [NSMutableArray arrayWithCapacity:titles.count];

    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        NSButton *button =
            [NSButton buttonWithTitle:titles[i]
                               target:self
                               action:@selector(sidebarButtonClicked:)];

        button.tag = i;
        button.bordered = NO;
        button.alignment = NSTextAlignmentLeft;
        button.font =
            [NSFont systemFontOfSize:13.5
                              weight:NSFontWeightMedium];

        button.image =
            [NSImage imageWithSystemSymbolName:
                symbols[i]
                accessibilityDescription:nil];

        button.symbolConfiguration =
            [NSImageSymbolConfiguration
                configurationWithPointSize:14
                                     weight:NSFontWeightMedium];

        button.imagePosition = NSImageLeft;
        button.contentTintColor = [NSColor secondaryLabelColor];
        button.wantsLayer = YES;
        button.layer.cornerRadius = 8.0;

        [self.sidebarView addSubview:button];
        [buttons addObject:button];
    }

    self.sidebarButtons = buttons;

    NSBox *divider =
        [[NSBox alloc] initWithFrame:NSZeroRect];
    divider.boxType = NSBoxSeparator;
    [self.sidebarView addSubview:divider];

    NSButton *restore =
        wfButton(
            @"Restore Defaults",
            self,
            @selector(restoreDefaultsClicked:)
        );

    restore.bordered = NO;
    restore.alignment = NSTextAlignmentLeft;
    restore.font =
        [NSFont systemFontOfSize:11.5
                          weight:NSFontWeightMedium];
    restore.contentTintColor = [NSColor secondaryLabelColor];
    [self.sidebarView addSubview:restore];

    self.sidebarView.subviews[0].tag = 0;
}

#pragma mark Main

- (void)buildMainView {
    self.mainView =
        [[NSView alloc]
            initWithFrame:NSZeroRect];

    self.mainView.autoresizingMask =
        NSViewWidthSizable |
        NSViewHeightSizable;

    [self.contentRoot addSubview:self.mainView];

    self.pageIconView =
        wfSymbol(@"slider.horizontal.3", 20.0, NSFontWeightMedium);

    self.pageTitleLabel =
        wfLabel(
            @"General",
            24.0,
            NSFontWeightBold,
            [NSColor labelColor]
        );

    [self.mainView addSubview:self.pageIconView];
    [self.mainView addSubview:self.pageTitleLabel];

    self.scrollView =
        [[NSScrollView alloc]
            initWithFrame:NSZeroRect];

    self.scrollView.hasVerticalScroller = YES;
    self.scrollView.autohidesScrollers = YES;
    self.scrollView.scrollerStyle = NSScrollerStyleOverlay;
    self.scrollView.drawsBackground = NO;
    self.scrollView.borderType = NSNoBorder;

    [self.mainView addSubview:self.scrollView];
}

#pragma mark Layout

- (void)layoutContent {
    if (!self.contentRoot)
        return;

    NSRect bounds = self.contentRoot.bounds;

    const CGFloat sidebarWidth = 190.0;
    const CGFloat headerHeight = 84.0;

    self.sidebarView.frame =
        NSMakeRect(
            0,
            0,
            sidebarWidth,
            bounds.size.height
        );

    CGFloat dividerY = 92.0;

    for (NSView *view in self.sidebarView.subviews) {
        if ([view isKindOfClass:[NSBox class]]) {
            NSBox *box = (NSBox *)view;
            box.frame =
                NSMakeRect(
                    18,
                    dividerY,
                    sidebarWidth - 36,
                    1
                );
            dividerY += 1.0;
            continue;
        }
    }

    NSImageView *appIcon = nil;
    NSTextField *appName = nil;
    NSTextField *caption = nil;

    for (NSView *view in self.sidebarView.subviews) {
        if ([view isKindOfClass:[NSImageView class]])
            appIcon = (NSImageView *)view;
        else if ([view isKindOfClass:[NSTextField class]]) {
            if (!appName)
                appName = (NSTextField *)view;
            else
                caption = (NSTextField *)view;
        }
    }

    if (appIcon)
        appIcon.frame = NSMakeRect(22, 26, 24, 24);

    if (appName)
        appName.frame = NSMakeRect(56, 24, 110, 24);

    if (caption)
        caption.frame = NSMakeRect(57, 47, 110, 18);

    for (NSButton *button in self.sidebarButtons) {
        NSInteger index = button.tag;

        button.frame =
            NSMakeRect(
                14,
                116 + index * 42,
                sidebarWidth - 28,
                36
            );
    }

    NSButton *restore = nil;
    for (NSView *view in self.sidebarView.subviews) {
        if ([view isKindOfClass:[NSButton class]] &&
            view != self.sidebarButtons.firstObject &&
            ![self.sidebarButtons containsObject:(NSButton *)view]) {
            restore = (NSButton *)view;
        }
    }

    if (restore) {
        restore.frame =
            NSMakeRect(
                14,
                bounds.size.height - 50,
                sidebarWidth - 28,
                30
            );
    }

    self.mainView.frame =
        NSMakeRect(
            sidebarWidth,
            0,
            MAX(0.0, bounds.size.width - sidebarWidth),
            bounds.size.height
        );

    self.pageIconView.frame =
        NSMakeRect(28, 31, 24, 24);

    self.pageTitleLabel.frame =
        NSMakeRect(
            63,
            24,
            MAX(120.0, self.mainView.bounds.size.width - 90),
            34
        );

    self.scrollView.frame =
        NSMakeRect(
            0,
            headerHeight,
            self.mainView.bounds.size.width,
            MAX(0.0, self.mainView.bounds.size.height - headerHeight)
        );

    if (self.currentPage) {
        CGFloat width = self.scrollView.contentView.bounds.size.width;

        if (width > 0) {
            CGFloat height = [self.currentPage preferredHeight];

            self.currentPage.frame =
                NSMakeRect(
                    0,
                    0,
                    width,
                    MAX(height, self.scrollView.contentView.bounds.size.height)
                );

            [self.currentPage setNeedsLayout:YES];
            [self.currentPage layoutSubtreeIfNeeded];
        }
    }
}

#pragma mark Page rendering

- (void)renderSelectedPage {
    if (self.currentPage) {
        [self.currentPage removeFromSuperview];
        self.currentPage = nil;
    }

    WFPageDefinition *page =
        self.pageDefinitions[self.selectedPageIndex];

    NSMutableArray<WFSectionView *> *sections =
        [NSMutableArray arrayWithCapacity:page.sections.count];

    for (WFSectionDefinition *definition in page.sections) {
        WFSectionView *section =
            [[WFSectionView alloc]
                initWithDefinition:definition
                             target:self
                           controls:self.controlsByKey];

        [sections addObject:section];
    }

    self.currentPage =
        [[WFPageView alloc]
            initWithSections:sections];

    self.scrollView.documentView = self.currentPage;

    self.pageTitleLabel.stringValue = page.title;
    self.pageIconView.image =
        [NSImage imageWithSystemSymbolName:
            page.symbol
            accessibilityDescription:nil];

    [self layoutContent];
}

#pragma mark Navigation

- (void)sidebarButtonClicked:(NSButton *)sender {
    [self selectPage:sender.tag];
}

- (void)selectPage:(NSInteger)index {
    if (index < 0 ||
        index >= (NSInteger)self.pageDefinitions.count)
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
    [self refreshUIFromState];
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
    [self refreshUIFromState];
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

#pragma mark State

- (WFSettingDefinition *)definitionForKey:(NSInteger)key {
    return self.definitionsByKey[@(key)];
}

- (void)updatePositionStatus {
    if (!self.currentPage)
        return;

    for (WFView *view in @[]) {
        (void)view;
    }

    for (NSView *sectionView in self.currentPage.sections) {
        if (![sectionView isKindOfClass:[WFSectionView class]])
            continue;

        WFSectionView *section = (WFSectionView *)sectionView;

        if (section.type != WFSectionTypePosition ||
            !section.specialContent)
            continue;

        for (NSView *view in section.specialContent.subviews) {
            if (view.tag == 1001 &&
                [view isKindOfClass:[NSTextField class]]) {

                WallifySettingsSnapshot snapshot;
                wallify_settings_get_snapshot(&snapshot);

                ((NSTextField *)view).stringValue =
                    [NSString stringWithFormat:
                        @"Left %d pt   •   Top %d pt   •   Grid %d, %d",
                        snapshot.margin_left,
                        snapshot.margin_top,
                        snapshot.grid_x,
                        snapshot.grid_y];

                return;
            }
        }
    }
}

- (void)applySnapshot:(WallifySettingsSnapshot)snapshot
        toDefinition:(WFSettingDefinition *)definition
             control:(NSControl *)control {
    NSInteger value = -1;

    switch (definition.key) {
        case 0: value = snapshot.glow; break;
        case 1: value = snapshot.aurora; break;
        case 2: value = snapshot.animations; break;
        case 3: value = snapshot.dim_paused; break;
        case 4: value = snapshot.debug_hud; break;
        case 5: value = snapshot.native_glass; break;
        case 6: value = snapshot.hide_text; break;
        case 7: value = snapshot.hide_progress; break;
        case 8: value = snapshot.show_controls; break;
        case 9: value = snapshot.show_timestamps; break;
        case 10: value = snapshot.frame_strength; break;
        case 11: value = snapshot.glow_intensity; break;
        case 12: value = snapshot.animation_speed; break;
        case 13: value = snapshot.media_source; break;
        case 14: value = snapshot.widget_mode; break;
        case 15: value = snapshot.idle_style; break;
        case 16: value = snapshot.track_transition; break;
        case 17: value = snapshot.font_scale; break;
        case 18: value = snapshot.media_key_target; break;
        case 19: value = snapshot.artwork_border; break;
        case 20: value = snapshot.compact_gradient; break;
        case 21: value = snapshot.artwork_radius; break;
        case 22: value = snapshot.progress_thickness; break;
        default: break;
    }

    if ([control isKindOfClass:[NSButton class]] &&
        definition.type == WFSettingTypeToggle) {

        ((NSButton *)control).state =
            value != 0
                ? NSControlStateValueOn
                : NSControlStateValueOff;

    } else if ([control isKindOfClass:[NSSegmentedControl class]]) {
        NSSegmentedControl *segments =
            (NSSegmentedControl *)control;

        if (value >= 0 && value < segments.segmentCount)
            segments.selectedSegment = value;

    } else if ([control isKindOfClass:[NSPopUpButton class]]) {
        NSPopUpButton *popup =
            (NSPopUpButton *)control;

        if (value >= 0 && value < popup.numberOfItems)
            [popup selectItemAtIndex:value];
    }

    if (definition.enabledByBoolKey >= 0) {
        NSInteger dependency = definition.enabledByBoolKey;
        BOOL dependencyValue = NO;

        switch (dependency) {
            case 0: dependencyValue = snapshot.glow; break;
            case 2: dependencyValue = snapshot.animations; break;
            case 5: dependencyValue = snapshot.native_glass; break;
            default: dependencyValue = YES; break;
        }

        control.enabled =
            dependencyValue == definition.enabledByBoolValue;
    } else {
        control.enabled = YES;
    }
}

- (void)refreshUIFromState {
    if (!self.window)
        return;

    WallifySettingsSnapshot snapshot;
    wallify_settings_get_snapshot(&snapshot);

    for (NSNumber *key in self.controlsByKey) {
        WFSettingDefinition *definition =
            [self definitionForKey:key.integerValue];

        if (!definition)
            continue;

        [self applySnapshot:snapshot
               toDefinition:definition
                    control:self.controlsByKey[key]];
    }

    [self updatePositionStatus];
}

#pragma mark Presentation

- (void)showSettingsWindow {
    if (!self.window)
        [self createWindow];

    [self refreshUIFromState];

    if (!self.window.isVisible)
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
    NSArray *args =
        [NSProcessInfo processInfo].arguments;

    for (NSString *arg in args) {
        if ([arg isEqualToString:@"--settings"] ||
            [arg isEqualToString:@"-s"])
            return true;
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
