// Included by native.m: repeating idle scenes are owned by Core Animation,
// leaving the application asleep between input and metadata changes.
// The active root is owned by the Metal surface. Replacing it removes the old animation tree from the layer hierarchy.
static CALayer* idleAnimationLayer;
static id idleSpriteImages[WALLIFY_MAX_TEXTURES];

static id idleSpriteImage(int textureID) {
    if (textureID < 0 || textureID >= WALLIFY_MAX_TEXTURES)
        return nil;
    if (idleSpriteImages[textureID])
        return idleSpriteImages[textureID];
    [frameLock lock];
    id<MTLTexture> texture = loadedTextures[textureID];
    [frameLock unlock];
    if (!texture)
        return nil;
    NSMutableData* pixels = [NSMutableData dataWithLength:texture.width * texture.height * 4];
    [texture getBytes:pixels.mutableBytes
         bytesPerRow:texture.width * 4
          fromRegion:MTLRegionMake2D(0, 0, texture.width, texture.height)
         mipmapLevel:0];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(texture.width, texture.height, 8, 32, texture.width * 4,
                                    space, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast,
                                    provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);
    idleSpriteImages[textureID] = CFBridgingRelease(image);
    return idleSpriteImages[textureID];
}

static void idleKeyframes(CALayer* layer, NSString* property, NSArray* values,
                          double period, double phase, double speed, double started) {
    [layer setValue:values.firstObject forKeyPath:property];
    BOOL constant = YES;
    for (id value in values) {
        if (![value isEqual:values.firstObject]) {
            constant = NO;
            break;
        }
    }
    if (constant)
        return;
    // One key time per value. Keeping the last keyframe below 1.0 gives
    // every discrete frame an equal slice of the loop before it repeats.
    NSMutableArray* times = [NSMutableArray arrayWithCapacity:values.count];
    for (NSUInteger i = 0; i < values.count; ++i)
        [times addObject:@((double)i / values.count)];
    CAKeyframeAnimation* animation = [CAKeyframeAnimation animationWithKeyPath:property];
    animation.values = values;
    animation.keyTimes = times;
    animation.calculationMode = kCAAnimationDiscrete;
    animation.duration = period / speed;
    animation.beginTime = started;
    animation.timeOffset = fmod(phase, period) / speed;
    animation.repeatCount = HUGE_VALF;
    [layer addAnimation:animation forKey:property];
}

static void idleCommandLayers(CALayer* root, const DrawCommand* frames, size_t frameCount,
                              size_t commandCount, id image, double period, double phase,
                              double speed, double started) {
    for (size_t index = 0; index < commandCount; ++index) {
        DrawCommand first = frames[index];
        CALayer* layer = [CALayer layer];
        layer.anchorPoint = CGPointZero;
        layer.contents = image;
        layer.minificationFilter = kCAFilterNearest;
        layer.magnificationFilter = kCAFilterNearest;
        if (!image) {
            layer.backgroundColor = [NSColor colorWithSRGBRed:first.r green:first.g
                                                        blue:first.b alpha:1].CGColor;
        }
        NSMutableArray* positions = [NSMutableArray arrayWithCapacity:frameCount];
        NSMutableArray* bounds = [NSMutableArray arrayWithCapacity:frameCount];
        NSMutableArray* rects = [NSMutableArray arrayWithCapacity:frameCount];
        NSMutableArray* opacities = [NSMutableArray arrayWithCapacity:frameCount];
        for (size_t frame = 0; frame < frameCount; ++frame) {
            DrawCommand c = frames[frame * commandCount + index];
            [positions addObject:[NSValue valueWithPoint:NSMakePoint(c.dx - c.clip_x, c.dy - c.clip_y)]];
            [bounds addObject:[NSValue valueWithRect:NSMakeRect(0, 0, c.dw, c.dh)]];
            [rects addObject:[NSValue valueWithRect:NSMakeRect(c.sx, c.sy, c.sw, c.sh)]];
            [opacities addObject:@(c.alpha)];
        }
        [root addSublayer:layer];
        idleKeyframes(layer, @"position", positions, period, phase, speed, started);
        idleKeyframes(layer, @"bounds", bounds, period, phase, speed, started);
        idleKeyframes(layer, @"contentsRect", rects, period, phase, speed, started);
        idleKeyframes(layer, @"opacity", opacities, period, phase, speed, started);
    }
}

bool wallify_idle_animation(const DrawCommand* sprites, size_t spriteCount, double spritePeriod,
                            const DrawCommand* effects, size_t effectFrames, size_t effectCount,
                            double effectPeriod, double phase, double speed) {
    @autoreleasepool {
        if (!spriteCount || speed <= 0)
            return false;
        id image = idleSpriteImage(sprites[0].texture_id);
        if (!image)
            return false;
        // The Zig samples live on its stack; retain copies across the main-queue hop.
        // The queued main-thread block captures these immutable byte copies; the caller's Zig stack can return immediately.
        NSData* spriteData = [NSData dataWithBytes:sprites length:spriteCount * sizeof(DrawCommand)];
        NSData* effectData = [NSData dataWithBytes:effects length:effectFrames * effectCount * sizeof(DrawCommand)];
        // Block capture retains spriteData/effectData until the layer tree has been built.
        dispatch_async(dispatch_get_main_queue(), ^{
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            [idleAnimationLayer removeFromSuperlayer];
            CALayer* root = [CALayer layer];
            DrawCommand first = ((const DrawCommand*)spriteData.bytes)[0];
            CGFloat y = surface.geometryFlipped ? first.clip_y :
                surface.bounds.size.height - first.clip_y - first.clip_h;
            root.frame = CGRectMake(first.clip_x, y, first.clip_w, first.clip_h);
            root.geometryFlipped = YES;
            root.masksToBounds = YES;
            root.cornerRadius = first.clip_radius;
            [surface addSublayer:root];
            double started = [root convertTime:CACurrentMediaTime() fromLayer:nil];
            idleCommandLayers(root, spriteData.bytes, spriteCount, 1, image,
                              spritePeriod, phase, speed, started);
            if (effectFrames)
                idleCommandLayers(root, effectData.bytes, effectFrames, effectCount, nil,
                                  effectPeriod, phase, speed, started);
            idleAnimationLayer = root;
            [CATransaction commit];
        });
        return true;
    }
}

void wallify_idle_animation_stop(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [idleAnimationLayer removeFromSuperlayer];
        idleAnimationLayer = nil;
    });
}
