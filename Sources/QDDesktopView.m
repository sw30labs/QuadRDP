#import "QDDesktopView.h"

// Apple virtual key codes -> RDP set-1 scancodes (0x100 marks E0 extended keys).
uint32_t QDScanCode(unsigned short key) {
    static const uint16_t codes[128] = {
        [0]=0x1e,[1]=0x1f,[2]=0x20,[3]=0x21,[4]=0x23,[5]=0x22,[6]=0x2c,[7]=0x2d,
        [8]=0x2e,[9]=0x2f,[11]=0x30,[12]=0x10,[13]=0x11,[14]=0x12,[15]=0x13,[16]=0x15,
        [17]=0x14,[18]=0x02,[19]=0x03,[20]=0x04,[21]=0x05,[22]=0x07,[23]=0x06,[24]=0x0d,
        [25]=0x0a,[26]=0x08,[27]=0x0c,[28]=0x09,[29]=0x0b,[30]=0x1b,[31]=0x18,[32]=0x16,
        [33]=0x1a,[34]=0x17,[35]=0x19,[36]=0x1c,[37]=0x26,[38]=0x24,[39]=0x28,[40]=0x25,
        [41]=0x27,[42]=0x2b,[43]=0x33,[44]=0x35,[45]=0x31,[46]=0x32,[47]=0x34,[48]=0x0f,
        [49]=0x39,[50]=0x29,[51]=0x0e,[53]=0x01,[54]=0x15c,[55]=0x15b,[56]=0x2a,
        [57]=0x3a,[58]=0x38,[59]=0x1d,[60]=0x36,[61]=0x138,[62]=0x11d,[65]=0x53,
        [67]=0x37,[69]=0x4e,[71]=0x45,[75]=0x135,[76]=0x11c,[78]=0x4a,[81]=0x59,
        [82]=0x52,[83]=0x4f,[84]=0x50,[85]=0x51,[86]=0x4b,[87]=0x4c,[88]=0x4d,
        [89]=0x47,[91]=0x48,[92]=0x49,[96]=0x3f,[97]=0x40,[98]=0x41,[99]=0x3d,
        [100]=0x42,[101]=0x43,[103]=0x57,[105]=0x64,[106]=0x67,[107]=0x65,[109]=0x44,
        [111]=0x58,[113]=0x66,[114]=0x152,[115]=0x147,[116]=0x149,[117]=0x153,
        [118]=0x3e,[119]=0x14f,[120]=0x3c,[121]=0x151,[122]=0x3b,[123]=0x14b,
        [124]=0x14d,[125]=0x150,[126]=0x148
    };
    return key < 128 ? codes[key] : 0;
}
NSRect QDAspectFit(NSSize size, NSRect bounds) {
    if (size.width <= 0 || size.height <= 0) return bounds;
    CGFloat scale = MIN(bounds.size.width / size.width, bounds.size.height / size.height);
    NSSize result = NSMakeSize(size.width * scale, size.height * scale);
    return NSMakeRect(NSMidX(bounds) - result.width / 2, NSMidY(bounds) - result.height / 2, result.width, result.height);
}
NSPoint QDRemotePoint(NSPoint p, NSRect r, NSSize size) {
    if (r.size.width <= 0 || r.size.height <= 0) return NSZeroPoint;
    return NSMakePoint(MAX(0, MIN(size.width - 1, floor((p.x - r.origin.x) * size.width / r.size.width))),
                       MAX(0, MIN(size.height - 1, floor((p.y - r.origin.y) * size.height / r.size.height))));
}

@implementation QDDesktopView {
    NSImage *_image;
    NSSize _remoteSize;
    uint64_t _sequence;
    NSTrackingArea *_tracking;
    NSMutableSet<NSNumber *> *_keys;
    NSMutableSet<NSNumber *> *_buttons;
    NSPoint _lastPoint;
    BOOL _mouseInside;
    NSCursor *_lastCursor;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _keys = [NSMutableSet set]; _buttons = [NSMutableSet set];
        self.wantsLayer = YES; self.layer.backgroundColor = [NSColor colorWithWhite:0.045 alpha:1].CGColor;
        self.accessibilityElement = YES; self.accessibilityRole = NSAccessibilityImageRole;
    }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)becomeFirstResponder {
    if (self.focused) self.focused();
    [self.session synchronizeCapsLock:(NSEvent.modifierFlags & NSEventModifierFlagCapsLock) != 0];
    return YES;
}
- (BOOL)resignFirstResponder { [self releaseInputs]; return YES; }
- (void)updateTrackingAreas {
    if (_tracking) [self removeTrackingArea:_tracking];
    _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingMouseEnteredAndExited |
        NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil];
    [self addTrackingArea:_tracking]; [super updateTrackingAreas];
}
- (void)refresh {
    QDFrame *frame = self.session.frame;
    if (frame && frame.sequence != _sequence) {
        _sequence = frame.sequence; _remoteSize = NSMakeSize(frame.width, frame.height);
        CGImageRef image = [frame createImage];
        _image = [[NSImage alloc] initWithCGImage:image size:_remoteSize];
        CGImageRelease(image); self.needsDisplay = YES;
    } else if (!frame && _image) { _image = nil; _sequence = 0; self.needsDisplay = YES; }
    if (_mouseInside && self.window.isKeyWindow && _lastCursor != self.session.remoteCursor) {
        _lastCursor = self.session.remoteCursor; [_lastCursor set];
    }
}
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor colorWithWhite:0.045 alpha:1] setFill]; NSRectFill(self.bounds);
    if (_image) {
        [_image drawInRect:QDAspectFit(_remoteSize, self.bounds) fromRect:NSZeroRect
                operation:NSCompositingOperationCopy fraction:1 respectFlipped:YES
                    hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
        return;
    }
    NSImage *symbol = [NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:nil];
    symbol = [symbol imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:38 weight:NSFontWeightLight]];
    symbol = [symbol imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:NSColor.lightGrayColor]];
    [symbol drawInRect:NSMakeRect(NSMidX(self.bounds)-24, NSMidY(self.bounds)-66, 48, 40)
             fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.30 respectFlipped:YES hints:nil];
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new]; paragraph.alignment = NSTextAlignmentCenter;
    NSDictionary *title = @{NSFontAttributeName:[NSFont systemFontOfSize:17 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName:[NSColor colorWithWhite:0.8 alpha:1], NSParagraphStyleAttributeName:paragraph};
    NSDictionary *detail = @{NSFontAttributeName:[NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName:[NSColor colorWithWhite:0.45 alpha:1], NSParagraphStyleAttributeName:paragraph};
    [(self.placeholderTitle ?: @"Add a computer") drawInRect:NSMakeRect(28, NSMidY(self.bounds)-5, self.bounds.size.width-56, 28) withAttributes:title];
    [(self.placeholderDetail ?: @"Configure this tile to get started.") drawInRect:NSMakeRect(28, NSMidY(self.bounds)+27, self.bounds.size.width-56, 64) withAttributes:detail];
}
- (void)mouseEntered:(NSEvent *)event { _mouseInside = YES; _lastCursor = nil; [self refresh]; }
- (void)mouseExited:(NSEvent *)event { _mouseInside = NO; [NSCursor.arrowCursor set]; }
- (BOOL)sendMouse:(NSEvent *)event flags:(uint16_t)flags allowOutside:(BOOL)outside {
    if (!_image || self.session.state != QDConnected) return NO;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect rect = QDAspectFit(_remoteSize, self.bounds);
    if (!outside && !NSPointInRect(p, rect)) return NO;
    _lastPoint = QDRemotePoint(p, rect, _remoteSize);
    [self.session mouseFlags:flags x:_lastPoint.x y:_lastPoint.y]; return YES;
}
- (void)mouseMoved:(NSEvent *)event { [self sendMouse:event flags:0x0800 allowOutside:NO]; }
- (void)mouseDragged:(NSEvent *)event { [self sendMouse:event flags:0x0800 allowOutside:YES]; }
- (void)rightMouseDragged:(NSEvent *)event { [self mouseDragged:event]; }
- (void)otherMouseDragged:(NSEvent *)event { [self mouseDragged:event]; }
- (void)button:(NSEvent *)event flag:(uint16_t)flag down:(BOOL)down {
    if (down) [self.window makeFirstResponder:self];
    if ([self sendMouse:event flags:flag | (down ? 0x8000 : 0) allowOutside:!down]) {
        if (down) [_buttons addObject:@(flag)]; else [_buttons removeObject:@(flag)];
    }
}
- (void)mouseDown:(NSEvent *)e { [self button:e flag:0x1000 down:YES]; }
- (void)mouseUp:(NSEvent *)e { [self button:e flag:0x1000 down:NO]; }
- (void)rightMouseDown:(NSEvent *)e { [self button:e flag:0x2000 down:YES]; }
- (void)rightMouseUp:(NSEvent *)e { [self button:e flag:0x2000 down:NO]; }
- (void)otherMouseDown:(NSEvent *)e { [self button:e flag:0x4000 down:YES]; }
- (void)otherMouseUp:(NSEvent *)e { [self button:e flag:0x4000 down:NO]; }
- (void)scrollWheel:(NSEvent *)event {
    if (self.window.firstResponder != self) [self.window makeFirstResponder:self];
    CGFloat deltas[2] = {event.scrollingDeltaY, event.scrollingDeltaX};
    for (int axis = 0; axis < 2; axis++) if (deltas[axis] != 0) {
        int amount = (int)round(deltas[axis] * (event.hasPreciseScrollingDeltas ? 3 : 120));
        amount = MAX(-255, MIN(255, amount));
        if (amount) [self sendMouse:event flags:(axis ? 0x0400 : 0x0200) | (amount & 0x1ff) allowOutside:NO];
    }
}
- (void)keyDown:(NSEvent *)event {
    uint32_t code = QDScanCode(event.keyCode);
    if (!code || self.session.state != QDConnected) return;
    [_keys addObject:@(code)]; [self.session keyScanCode:code down:YES repeat:event.isARepeat];
}
- (void)keyUp:(NSEvent *)event {
    uint32_t code = QDScanCode(event.keyCode);
    if (![_keys containsObject:@(code)]) return;
    [_keys removeObject:@(code)]; [self.session keyScanCode:code down:NO repeat:NO];
}
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (self.window.firstResponder != self || self.session.state != QDConnected) return NO;
    NSString *key = event.charactersIgnoringModifiers.lowercaseString;
    if ((event.modifierFlags & NSEventModifierFlagCommand) &&
        ([@[@"0",@"1",@"2",@"3",@"4",@"\r",@"q",@","] containsObject:key])) {
        [self releaseInputs]; return NO;
    }
    if (event.modifierFlags & NSEventModifierFlagCommand) { [self keyDown:event]; return YES; }
    return NO;
}
- (void)flagsChanged:(NSEvent *)event {
    if (self.session.state != QDConnected) return;
    if (event.keyCode == 57) { [self.session synchronizeCapsLock:(event.modifierFlags & NSEventModifierFlagCapsLock) != 0]; return; }
    uint32_t code = QDScanCode(event.keyCode);
    if (!code) return;
    // Device-specific masks distinguish left/right even when both modifiers are held.
    uint64_t deviceMask = 0;
    switch (event.keyCode) {
        case 54: deviceMask=0x10; break; case 55: deviceMask=0x08; break;
        case 56: deviceMask=0x02; break; case 60: deviceMask=0x04; break;
        case 58: deviceMask=0x20; break; case 61: deviceMask=0x40; break;
        case 59: deviceMask=0x01; break; case 62: deviceMask=0x2000; break;
        default: return;
    }
    BOOL down = (event.modifierFlags & deviceMask) != 0;
    if (down) [_keys addObject:@(code)]; else [_keys removeObject:@(code)];
    [self.session keyScanCode:code down:down repeat:NO];
}
- (void)releaseInputs {
    for (NSNumber *code in _keys) [self.session keyScanCode:code.unsignedIntValue down:NO repeat:NO];
    for (NSNumber *button in _buttons) [self.session mouseFlags:button.unsignedShortValue x:_lastPoint.x y:_lastPoint.y];
    [_keys removeAllObjects]; [_buttons removeAllObjects];
}
@end
