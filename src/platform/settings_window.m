#import "settings_window.h"
#import "debug_stats.h"
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>
#import <ServiceManagement/ServiceManagement.h>

extern void wallify_imgui_inspector_show(void) __attribute__((weak_import));

extern const char *wallify_settings_path(void);

static const CGFloat WFTopInset = 54.0;
static const CGFloat WFSidebarInset = 18.0;
static const CGFloat WFContentInset = 12.0;
static const CGFloat WFContentMaxWidth = 600.0;

@interface WFFlippedView : NSView
@end

@implementation WFFlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

typedef NS_ENUM(NSInteger, WFSettingType) {
    WFSettingTypeToggle,
    WFSettingTypeSegments,
    WFSettingTypePopup,
};

typedef NS_ENUM(NSInteger, WFSectionType) {
    WFSectionTypeSettings,
    WFSectionTypePosition,
    WFSectionTypeConfiguration,
    WFSectionTypePerformance,
    WFSectionTypeSystem,
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
         * Keep the public Regular material. It reads as frosted glass rather
         * than the highly refractive widget/HUD treatment used by Wallify.
         */
        glass.style = NSGlassEffectViewStyleRegular;

        glass.cornerRadius = 0.0;
        glass.tintColor =
            [[NSColor controlBackgroundColor]
                colorWithAlphaComponent:0.42];
        glass.effectIsInteractive = NO;
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
);

@interface WFSidebarButton : NSButton
@property(nonatomic, strong) NSImageView *iconView;
@property(nonatomic, strong) NSTextField *textLabel;
@end

@implementation WFSidebarButton

- (instancetype)initWithTitle:(NSString *)title
                         symbol:(NSString *)symbol
                         target:(id)target
                         action:(SEL)action {
    self = [super initWithFrame:NSZeroRect];
    if (!self)
        return nil;

    self.target = target;
    self.action = action;
    self.title = @"";
    self.bordered = NO;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 8.0;
    self.layer.masksToBounds = YES;

    self.iconView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.iconView.image =
        [NSImage imageWithSystemSymbolName:symbol
                     accessibilityDescription:nil];
    self.iconView.symbolConfiguration =
        [NSImageSymbolConfiguration
            configurationWithPointSize:14.0
                                 weight:NSFontWeightMedium];
    self.iconView.contentTintColor = [NSColor secondaryLabelColor];

    self.textLabel =
        wfLabel(
            title,
            13.5,
            NSFontWeightMedium,
            [NSColor labelColor]
        );

    [self addSubview:self.iconView];
    [self addSubview:self.textLabel];

    return self;
}

- (void)layout {
    [super layout];

    const CGFloat horizontalInset = 12.0;
    const CGFloat gap = 10.0;
    const CGFloat iconSize = 18.0;
    const CGFloat textHeight = 20.0;
    const CGFloat contentWidth =
        MAX(
            0.0,
            self.bounds.size.width -
            (horizontalInset * 2.0) -
            iconSize -
            gap
        );

    CGFloat centerY = floor(self.bounds.size.height * 0.5);

    self.iconView.frame =
        NSMakeRect(
            horizontalInset,
            floor(centerY - iconSize * 0.5),
            iconSize,
            iconSize
        );

    self.textLabel.frame =
        NSMakeRect(
            horizontalInset + iconSize + gap,
            floor(centerY - textHeight * 0.5),
            contentWidth,
            textHeight
        );
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.iconView.alphaValue = enabled ? 1.0 : 0.5;
    self.textLabel.alphaValue = enabled ? 1.0 : 0.5;
}

@end

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
    field.lineBreakMode = NSLineBreakByWordWrapping;
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

@interface WFSettingRowView : WFFlippedView
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

    const CGFloat horizontalPadding = WFContentInset;
    const CGFloat controlGap = 24.0;

    CGFloat availableControlWidth = 72.0;

    if ([self.control isKindOfClass:[NSSegmentedControl class]]) {
        availableControlWidth = 320.0;
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
        MAX(140.0, controlX - controlGap - horizontalPadding);

    if (self.subtitleLabel.superview) {
        self.titleLabel.frame =
            NSMakeRect(
                horizontalPadding,
                14.0,
                textWidth,
                18.0
            );

        self.subtitleLabel.frame =
            NSMakeRect(
                horizontalPadding,
                35.0,
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

}

@end

#pragma mark - Section view

@interface WFSectionView : WFFlippedView
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
        WFFlippedView *content = [[WFFlippedView alloc] initWithFrame:NSZeroRect];

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

        pathLabel.lineBreakMode = NSLineBreakByClipping;

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
    } else if (definition.type == WFSectionTypePerformance) {
        NSView *content = [[NSView alloc] initWithFrame:NSZeroRect];
        NSTextField *status = wfLabel(@"Renderer status", 12.0, NSFontWeightMedium, [NSColor labelColor]);
        status.tag = 1101;
        NSTextField *detail = wfLabel(@"Static caching, tiered animation budgets, and occlusion sleeping are automatic.", 11.0, NSFontWeightRegular, [NSColor secondaryLabelColor]);
        detail.tag = 1102;
        NSButton *inspector = wfButton(@"Open Inspector", target, @selector(openInspectorClicked:));
        inspector.tag = 1103;
        inspector.enabled = wallify_imgui_inspector_show != NULL;
        [content addSubview:status];
        [content addSubview:detail];
        [content addSubview:inspector];
        self.specialContent = content;
        [self addSubview:content];

    } else if (definition.type == WFSectionTypeSystem) {
        NSView *content = [[NSView alloc] initWithFrame:NSZeroRect];
        NSButton *login = [NSButton buttonWithTitle:@"Launch at Login" target:target action:@selector(launchAtLoginChanged:)];
        login.buttonType = NSButtonTypeSwitch;
        login.controlSize = NSControlSizeRegular;
        login.tag = 1201;
        NSButton *loginSettings = wfButton(@"Open Login Items Settings", target, @selector(openLoginItemsSettingsClicked:));
        loginSettings.tag = 1202;
        [content addSubview:login];
        [content addSubview:loginSettings];
        self.specialContent = content;
        [self addSubview:content];
    }

    return self;
}

- (CGFloat)preferredHeight {
    if (self.type == WFSectionTypeSettings) {
        return 31.0 +
               MAX(0.0, self.rows.count * 58.0);
    }

    if (self.type == WFSectionTypePosition ||
        self.type == WFSectionTypeConfiguration) {
        return 31.0 + 112.0;
    }
    if (self.type == WFSectionTypePerformance) return 31.0 + 130.0;
    if (self.type == WFSectionTypeSystem) return 31.0 + 92.0;

    return 31.0;
}

- (void)layout {
    [super layout];

    const CGFloat headerHeight = 18.0;

    self.headerLabel.frame =
        NSMakeRect(
            WFContentInset,
            0,
            self.bounds.size.width - (WFContentInset * 2.0),
            headerHeight
        );

    if (self.type == WFSectionTypeSettings) {
        CGFloat y = headerHeight + 2.0;

        for (NSInteger i = 0; i < (NSInteger)self.rows.count; i++) {
            WFSettingRowView *row = self.rows[i];

            row.frame =
                NSMakeRect(
                    0,
                    y,
                    self.bounds.size.width,
                    57.0
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
                        WFContentInset,
                        56,
                        MAX(0.0, row.bounds.size.width - (WFContentInset * 2.0)),
                        1
                    );
            }

            y += 58.0;
        }

    } else if (self.specialContent) {
        CGFloat top = headerHeight + 3.0;

        CGFloat specialHeight = self.type == WFSectionTypePerformance
            ? 130.0
            : (self.type == WFSectionTypeSystem ? 92.0 : 109.0);
        self.specialContent.frame =
            NSMakeRect(
                0,
                top,
                self.bounds.size.width,
                specialHeight
            );

        NSArray<NSView *> *views = self.specialContent.subviews;

        if (self.type == WFSectionTypePosition && views.count >= 3) {
            NSTextField *status = (NSTextField *)views[0];
            NSTextField *hint = (NSTextField *)views[1];
            NSButton *reset = (NSButton *)views[2];

            status.frame =
                NSMakeRect(WFContentInset, 7,
                           self.bounds.size.width - (WFContentInset * 2.0), 18);
            hint.frame =
                NSMakeRect(WFContentInset, 31,
                           self.bounds.size.width - (WFContentInset * 2.0), 18);
            reset.frame =
                NSMakeRect(WFContentInset, 60, 120, 30);

        } else if (self.type == WFSectionTypePerformance &&
                   views.count >= 3) {
            NSTextField *status = (NSTextField *)views[0];
            NSTextField *detail = (NSTextField *)views[1];
            NSButton *inspector = (NSButton *)views[2];
            status.frame = NSMakeRect(WFContentInset, 7, self.bounds.size.width - WFContentInset * 2.0, 20);
            detail.frame = NSMakeRect(WFContentInset, 32, self.bounds.size.width - WFContentInset * 2.0, 34);
            inspector.frame = NSMakeRect(WFContentInset, 82, 122, 30);
        } else if (self.type == WFSectionTypeSystem &&
                   views.count >= 2) {
            NSButton *login = (NSButton *)views[0];
            NSButton *loginSettings = (NSButton *)views[1];
            login.frame = NSMakeRect(WFContentInset, 10, 180, 26);
            loginSettings.frame = NSMakeRect(WFContentInset, 48, 200, 30);
        } else if (self.type == WFSectionTypeConfiguration &&
                   views.count >= 3) {
            NSTextField *path = (NSTextField *)views[0];
            NSButton *reveal = (NSButton *)views[1];
            NSButton *open = (NSButton *)views[2];

            path.frame =
                NSMakeRect(WFContentInset, 8,
                           self.bounds.size.width - (WFContentInset * 2.0), 18);

            reveal.frame = NSMakeRect(WFContentInset, 44, 132, 30);
            open.frame = NSMakeRect(WFContentInset + 142, 44, 104, 30);
        }
    }
}

@end

#pragma mark - Page view

@interface WFPageView : WFFlippedView
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
    CGFloat height = 18.0;

    for (WFSectionView *section in self.sections)
        height += [section preferredHeight] + 20.0;

    return height + 18.0;
}

- (void)layout {
    [super layout];

    CGFloat y = 18.0;

    for (WFSectionView *section in self.sections) {
        CGFloat h = [section preferredHeight];

        CGFloat sectionWidth =
            MIN(
                WFContentMaxWidth,
                MAX(100.0, self.bounds.size.width - 52.0)
            );

        CGFloat sectionX =
            floor((self.bounds.size.width - sectionWidth) * 0.5);

        section.frame =
            NSMakeRect(
                sectionX,
                y,
                sectionWidth,
                h
            );

        y += h + 18.0;
    }
}

@end

#pragma mark - Content view

@class WallifySettingsWindowController;

@interface WFSettingsContentView : WFFlippedView
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
@property(nonatomic, strong) NSButton *restoreDefaultsButton;
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
            @[@"Pixel Cat", @"Banana Cat", @"Spotify", @"Raccoon"]
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
            @"Debug Console",
            @"Show live Wallify runtime and diagnostics."
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
            @"Performance",
            @"gauge.with.dots.needle.67percent",
            @[
                wfSpecialSection(WFSectionTypePerformance, @"Renderer"),
            ]
        ),

        wfPage(
            @"Desktop",
            @"rectangle.on.rectangle",
            @[
                wfSpecialSection(WFSectionTypePosition, @"Position"),
                wfSection(@"Diagnostics", @[debug]),
                wfSpecialSection(WFSectionTypeSystem, @"System"),
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

    const CGFloat width = 800.0;
    const CGFloat height = 560.0;

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
    self.window.minSize = NSMakeSize(720.0, 500.0);
    self.window.contentMinSize = NSMakeSize(720.0, 500.0);
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
        [[WFFlippedView alloc]
            initWithFrame:self.glassView.bounds];

    self.glassContentView.autoresizingMask =
        NSViewWidthSizable |
        NSViewHeightSizable;

    self.glassContentView.wantsLayer = YES;
    self.glassContentView.layer.backgroundColor =
        [[NSColor windowBackgroundColor]
            colorWithAlphaComponent:0.34].CGColor;

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
        [[WFFlippedView alloc]
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
        @"Performance",
        @"Desktop"
    ];

    NSArray<NSString *> *symbols = @[
        @"slider.horizontal.3",
        @"paintbrush",
        @"play.circle",
        @"gauge.with.dots.needle.67percent",
        @"rectangle.on.rectangle"
    ];

    NSMutableArray<NSButton *> *buttons =
        [NSMutableArray arrayWithCapacity:titles.count];

    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        WFSidebarButton *button =
            [[WFSidebarButton alloc]
                initWithTitle:titles[i]
                symbol:symbols[i]
                target:self
                action:@selector(sidebarButtonClicked:)];

        button.tag = i;

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
    self.restoreDefaultsButton = restore;
}

#pragma mark Main

- (void)buildMainView {
    self.mainView =
        [[WFFlippedView alloc]
            initWithFrame:NSZeroRect];

    self.mainView.autoresizingMask =
        NSViewWidthSizable |
        NSViewHeightSizable;

    [self.contentRoot addSubview:self.mainView];

    NSBox *mainDivider =
        [[NSBox alloc] initWithFrame:NSZeroRect];
    mainDivider.boxType = NSBoxSeparator;
    [self.contentRoot addSubview:mainDivider];

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

    const CGFloat sidebarWidth = 178.0;
    const CGFloat headerHeight = 92.0;

    self.sidebarView.frame =
        NSMakeRect(
            0,
            0,
            sidebarWidth,
            bounds.size.height
        );

    CGFloat dividerY = WFTopInset + 44.0;

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
        appIcon.frame = NSMakeRect(22, WFTopInset + 2.0, 24, 24);

    if (appName)
        appName.frame = NSMakeRect(56, WFTopInset, 108, 24);

    if (caption)
        caption.frame = NSMakeRect(57, WFTopInset + 23.0, 108, 18);

    for (NSButton *button in self.sidebarButtons) {
        NSInteger index = button.tag;

        button.frame =
            NSMakeRect(
                WFSidebarInset,
                WFTopInset + 70.0 + index * 38.0,
                sidebarWidth - (WFSidebarInset * 2.0),
                36
            );
    }

    self.restoreDefaultsButton.frame =
        NSMakeRect(
            WFSidebarInset,
            bounds.size.height - 40,
            sidebarWidth - (WFSidebarInset * 2.0),
            28
        );

    NSBox *mainDivider = nil;
    for (NSView *view in self.contentRoot.subviews) {
        if ([view isKindOfClass:[NSBox class]]) {
            mainDivider = (NSBox *)view;
            break;
        }
    }

    if (mainDivider) {
        mainDivider.frame =
            NSMakeRect(
                sidebarWidth,
                0,
                1,
                bounds.size.height
            );
    }

    self.mainView.frame =
        NSMakeRect(
            sidebarWidth + 1,
            0,
            MAX(0.0, bounds.size.width - sidebarWidth),
            bounds.size.height
        );

    self.pageIconView.frame =
        NSMakeRect(30, WFTopInset - 2.0, 22, 22);

    self.pageTitleLabel.frame =
        NSMakeRect(
            62,
            WFTopInset - 8.0,
            MAX(120.0, self.mainView.bounds.size.width - 88),
            32
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
    WFPageView *oldPage = self.currentPage;

    if (oldPage) {
        [oldPage removeFromSuperview];
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

    WFPageView *newPage =
        [[WFPageView alloc]
            initWithSections:sections];

    self.currentPage = newPage;
    self.scrollView.documentView = newPage;

    self.pageTitleLabel.stringValue = page.title;
    self.pageIconView.image =
        [NSImage imageWithSystemSymbolName:
            page.symbol
                     accessibilityDescription:nil];

    [self layoutContent];

    NSRect frame = newPage.frame;
    frame.origin.x += 12.0;
    newPage.frame = frame;
    newPage.alphaValue = 0.0;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.18;
        context.timingFunction =
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];

        NSRect targetFrame = newPage.frame;
        targetFrame.origin.x -= 12.0;

        [[newPage animator] setFrame:targetFrame];
        [[newPage animator] setAlphaValue:1.0];
    } completionHandler:^{
        [newPage setAlphaValue:1.0];
    }];
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

- (void)openInspectorClicked:(id)sender {
    (void)sender;
    if (wallify_imgui_inspector_show)
        wallify_imgui_inspector_show();
}

- (void)launchAtLoginChanged:(NSButton *)sender {
    const BOOL enabled = sender.state == NSControlStateValueOn;
    if (!wallify_launch_at_login_set(enabled)) {
        sender.state = wallify_launch_at_login_enabled()
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    }
}

- (void)openLoginItemsSettingsClicked:(id)sender {
    (void)sender;
    if (@available(macOS 13.0, *))
        [SMAppService openSystemSettingsLoginItems];
}

#pragma mark State

- (WFSettingDefinition *)definitionForKey:(NSInteger)key {
    return self.definitionsByKey[@(key)];
}

- (void)updatePositionStatus {
    if (!self.currentPage)
        return;

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

    for (WFSectionView *section in self.currentPage.sections) {
        if (section.type == WFSectionTypePerformance && section.specialContent.subviews.count >= 3) {
            WallifyRendererStats stats = {0};
            wallify_debug_renderer_stats(&stats);
            NSTextField *status = (NSTextField *)section.specialContent.subviews[0];
            NSTextField *detail = (NSTextField *)section.specialContent.subviews[1];
            NSButton *inspector = (NSButton *)section.specialContent.subviews[2];

            status.stringValue = stats.ready
                ? [NSString stringWithFormat:@"Metal ready • %s", stats.device_name]
                : @"Metal renderer unavailable";
            detail.stringValue = stats.profiling
                ? [NSString stringWithFormat:@"Scene %.3f ms • GPU %.3f ms • %.2f MiB textures",
                    stats.scene_ms, stats.gpu_ms, stats.texture_bytes / 1048576.0]
                : @"Timing disabled • run WALLIFY_PROFILE=1 ./run -d -f for CPU/GPU measurements";
            inspector.enabled = wallify_imgui_inspector_show != NULL;
        } else if (section.type == WFSectionTypeSystem && section.specialContent.subviews.count >= 2) {
            NSButton *login = (NSButton *)section.specialContent.subviews[0];
            login.state = wallify_launch_at_login_enabled()
                ? NSControlStateValueOn
                : NSControlStateValueOff;
        }
    }
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

bool wallify_launch_at_login_enabled(void) {
    if (@available(macOS 13.0, *)) {
        return [[SMAppService mainAppService] status] == SMAppServiceStatusEnabled;
    }
    return false;
}

bool wallify_launch_at_login_set(bool enabled) {
    if (@available(macOS 13.0, *)) {
        SMAppService *service = [SMAppService mainAppService];
        NSError *error = nil;
        BOOL success = enabled
            ? [service registerAndReturnError:&error]
            : [service unregisterAndReturnError:&error];

        if (success) {
            NSLog(@"Wallify: launch at login -> %@", enabled ? @"enabled" : @"disabled");
        } else {
            NSLog(@"Wallify: launch at login %@ failed: %@", enabled ? @"enable" : @"disable", error);
        }
        return success;
    }
    return false;
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
