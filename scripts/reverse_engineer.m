#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

void printLayerHierarchy(CALayer *layer, int level) {
    if (!layer) return;
    for (int i = 0; i < level; i++) printf("  ");
    printf("- %s\n", class_getName([layer class]));
    if (layer.filters) {
        for (int i = 0; i < level; i++) printf("  ");
        printf("  Filters:\n");
        for (id filter in layer.filters) {
            for (int i = 0; i < level; i++) printf("  ");
            printf("   - %s\n", [[filter description] UTF8String]);
        }
    }
    for (CALayer *sub in layer.sublayers) {
        printLayerHierarchy(sub, level + 1);
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        printf("========================================\n");
        printf("  APPLE WIDGET REVERSE ENGINEERING TOOL \n");
        printf("========================================\n\n");
        
        Class ConcentricClass = NSClassFromString(@"NSContainerConcentricGlassEffectView");
        if (!ConcentricClass) {
            printf("Failed to find NSContainerConcentricGlassEffectView in AppKit.\n");
            return 1;
        }
        
        printf("[+] Found class: %s\n", class_getName(ConcentricClass));
        printf("[+] Dumping properties:\n");
        
        unsigned int propCount;
        objc_property_t *props = class_copyPropertyList(ConcentricClass, &propCount);
        for (unsigned int i = 0; i < propCount; i++) {
            printf("    - %s (%s)\n", property_getName(props[i]), property_getAttributes(props[i]));
        }
        free(props);
        
        printf("\n[+] Initializing headless Widget view...\n");
        
        // We must attach it to a window to force CoreAnimation to build the full render tree
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,400,400) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        NSView *view = [[ConcentricClass alloc] initWithFrame:NSMakeRect(0,0,200,200)];
        view.wantsLayer = YES;
        [window.contentView addSubview:view];
        
        // We test variant 0 (default WidgetKit) and variant 4 (Context Menu fallback)
        NSArray *variants = @[@0, @4];
        
        for (NSNumber *variant in variants) {
            printf("\n----------------------------------------\n");
            printf("[+] Forcing _variant = %d\n", [variant intValue]);
            @try {
                [view setValue:variant forKey:@"_variant"];
                [view layout];
                [view display];
                [window display];
                
                printf("[+] Layer Tree:\n");
                printLayerHierarchy(view.layer, 1);
            } @catch (NSException *e) {
                printf("Error setting variant: %s\n", [[e reason] UTF8String]);
            }
        }
        
        printf("\n========================================\n");
        printf("  REVERSE ENGINEERING COMPLETE \n");
        printf("========================================\n");
    }
    return 0;
}
