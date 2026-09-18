#import <AppKit/AppKit.h>
NSImage *createRoundedRectMask(NSRect bounds, CGFloat radius) {
    NSImage *image = [[NSImage alloc] initWithSize:bounds.size];
    [image lockFocus];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius];
    [[NSColor blackColor] set];
    [path fill];
    [image unlockFocus];
    image.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    image.resizingMode = NSImageResizingModeStretch;
    return image;
}
