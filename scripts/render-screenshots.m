// Render the production AppKit views with example profiles, without network connections.
#import "../Sources/QDApp.m"

static void SaveView(NSView *view, NSString *path) {
    [view layoutSubtreeIfNeeded];
    [view displayIfNeeded];
    [CATransaction flush];
    NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (![png writeToFile:path atomically:YES]) { fprintf(stderr, "Could not write screenshot\n"); exit(1); }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1440,900)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        window.backgroundColor = [NSColor colorWithWhite:0.07 alpha:1];
        QDRootView *root = [[QDRootView alloc] initWithFrame:NSMakeRect(0,0,1440,900)];
        root.wantsLayer = YES;
        root.layer.backgroundColor = window.backgroundColor.CGColor;
        window.contentView = root;
        root.expanded = -1;
        root.titleLabel = Label(@"QuadRDP",24,NSFontWeightBold);
        root.subtitleLabel = Label(@"YOUR REMOTE WORKSPACE",10,NSFontWeightSemibold);
        root.subtitleLabel.textColor = NSColor.secondaryLabelColor;
        root.footerLabel = Label(@"⌘1–4  Focus computer     ⌘Return  Expand tile     ⌘0  Show grid     Control + Option = Windows Ctrl + Alt",11,NSFontWeightRegular);
        root.footerLabel.textColor = NSColor.secondaryLabelColor;
        root.allButton = Button(@"Connect all",nil,NULL);
        root.allButton.bezelColor = [NSColor colorWithSRGBRed:0.18 green:0.50 blue:0.40 alpha:1];
        root.stopButton = Button(@"Disconnect all",nil,NULL);
        root.gridButton = Button(@"2 × 2 grid",nil,NULL);
        for (NSView *view in @[root.titleLabel,root.subtitleLabel,root.footerLabel,root.allButton,root.stopButton,root.gridButton]) [root addSubview:view];
        NSMutableArray *tiles = [NSMutableArray array];
        NSArray *names = @[@"Inference · 01",@"Inference · 02",@"Inference · 03",@"Inference · 04"];
        for (NSInteger i=0;i<4;i++) {
            QDTile *tile = [[QDTile alloc] initWithFrame:NSZeroRect];
            QDProfile *profile = [QDProfile emptyProfile:i];
            profile.name = names[i];
            profile.host = [NSString stringWithFormat:@"inference-%02ld.example.com",(long)i+1];
            profile.username = @"operator";
            tile.profile = profile;
            tile.session = [QDSession new];
            tile.desktop.session = tile.session;
            tile.indexLabel.stringValue = [NSString stringWithFormat:@"%02ld",(long)i+1];
            tile.selected = i==0;
            [root addSubview:tile]; [tiles addObject:tile];
        }
        root.tiles = tiles;
        [window.appearance performAsCurrentDrawingAppearance:^{
            SaveView(root,@"docs/images/quad-grid.png");
            root.expanded = 0; root.needsLayout = YES;
            SaveView(root,@"docs/images/focus-view.png");
        }];
        puts("Rendered grid and focus views with example profiles; no servers contacted.");
    }
    return 0;
}
