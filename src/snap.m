#import <AppKit/AppKit.h>
#import <stdio.h>

static NSPanel *snap_panel = nil;

void show_snap_outline_objc(double x, double y, double w, double h) {
    dispatch_async(dispatch_get_main_queue(), ^{
        FILE *f = fopen("/tmp/wallify.log", "a");
        if (f) {
            fprintf(f, "DISPATCH BLOCK EXECUTED! x=%f, y=%f\n", x, y);
            fclose(f);
        }
        NSRect screen_frame = [[[NSScreen screens] firstObject] frame];
        NSRect rect = NSMakeRect(x, screen_frame.size.height - y - h, w, h);
        
        if (snap_panel == nil) {
            snap_panel = [[NSPanel alloc] initWithContentRect:rect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
            [snap_panel setOpaque:NO];
            [snap_panel setHasShadow:NO];
            [snap_panel setBackgroundColor:[NSColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.3]];
            [snap_panel setIgnoresMouseEvents:YES];
            [snap_panel setLevel:NSFloatingWindowLevel];
            
            NSView *contentView = [snap_panel contentView];
            [contentView setWantsLayer:YES];
            [[contentView layer] setCornerRadius:26.0];
        }
        
        [snap_panel setFrame:rect display:YES];
        [snap_panel orderFrontRegardless];
    });
}

void hide_snap_outline_objc() {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (snap_panel != nil) {
            [snap_panel orderOut:nil];
        }
    });
}
