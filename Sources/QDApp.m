#import "QDApp.h"
#import "QDDesktopView.h"
#import "QDProfile.h"
#import <QuartzCore/QuartzCore.h>

static NSColor *Accent(void) { return [NSColor colorWithSRGBRed:0.35 green:0.84 blue:0.70 alpha:1]; }
static NSTextField *Label(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}
static NSButton *Button(NSString *title, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    return button;
}
@interface QDFlippedView : NSView
@property id retainedController;
@end
@implementation QDFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface QDFormValidation : NSObject <NSTextFieldDelegate>
@property NSArray<NSTextField *> *fields;
@property NSButton *save;
@property NSTextField *message;
@property QDProfile *profile;
- (void)validate;
@end
@implementation QDFormValidation
- (void)controlTextDidChange:(NSNotification *)note { [self validate]; }
- (void)validate {
    QDProfile *p=[self.profile copy];
    p.host=[self.fields[1].stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *port=self.fields[2].stringValue;
    p.port=[port rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location==NSNotFound ? port.integerValue : 0;
    p.username=[self.fields[3].stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *error=p.validationError;
    self.save.enabled=error==nil;
    self.message.stringValue=error ?: @"";
}
@end

@interface QDTile : QDFlippedView
@property QDDesktopView *desktop;
@property NSTextField *nameLabel, *statusLabel, *indexLabel;
@property NSButton *connectButton, *editButton, *zoomButton, *secureButton;
@property QDProfile *profile;
@property QDSession *session;
@property (nonatomic) BOOL selected;
- (void)refresh;
@end
@implementation QDTile
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.cornerRadius = 12; self.layer.masksToBounds = YES;
        self.layer.backgroundColor = [NSColor colorWithWhite:0.105 alpha:1].CGColor;
        self.layer.borderWidth = 1;
        _desktop = [[QDDesktopView alloc] initWithFrame:NSZeroRect];
        _nameLabel = Label(@"Computer", 13, NSFontWeightSemibold);
        _statusLabel = Label(@"Not configured", 11, NSFontWeightRegular);
        _indexLabel = Label(@"01", 12, NSFontWeightMedium);
        _indexLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightMedium];
        _indexLabel.textColor = Accent();
        _connectButton = Button(@"Connect", nil, NULL);
        _editButton = Button(@"", nil, NULL);
        _editButton.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"Configure computer"];
        _editButton.toolTip = @"Configure this computer";
        _zoomButton = Button(@"", nil, NULL);
        _zoomButton.image = [NSImage imageWithSystemSymbolName:@"arrow.up.left.and.arrow.down.right" accessibilityDescription:@"Expand tile"];
        _zoomButton.toolTip = @"Expand / return to grid (⌘Return)";
        _secureButton = Button(@"", nil, NULL);
        _secureButton.image = [NSImage imageWithSystemSymbolName:@"keyboard" accessibilityDescription:@"Send Control Alt Delete"];
        _secureButton.toolTip = @"Send Ctrl+Alt+Delete to this computer";
        for (NSView *v in @[_desktop,_indexLabel,_nameLabel,_statusLabel,_connectButton,_editButton,_zoomButton,_secureButton]) [self addSubview:v];
    }
    return self;
}
- (void)layout {
    [super layout]; CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    _indexLabel.frame = NSMakeRect(16, 17, 25, 20);
    _nameLabel.frame = NSMakeRect(50, 11, MAX(40,w-278), 20);
    _statusLabel.frame = NSMakeRect(50, 32, MAX(40,w-278), 17);
    _secureButton.frame = NSMakeRect(w-222, 17, 34, 28);
    _editButton.frame = NSMakeRect(w-184, 17, 34, 28);
    _connectButton.frame = NSMakeRect(w-147, 17, 94, 28);
    _zoomButton.frame = NSMakeRect(w-48, 17, 34, 28);
    _desktop.frame = NSMakeRect(1, 61, w-2, MAX(1,h-62));
}
- (void)setSelected:(BOOL)selected { _selected = selected; [self refresh]; }
- (void)refresh {
    QDSessionState state = self.session.state;
    BOOL busy = state == QDConnecting || state == QDConnected || state == QDStopping;
    _nameLabel.stringValue = self.profile.name.length ? self.profile.name : self.profile.host;
    _statusLabel.stringValue = self.profile.host.length ? self.session.status : @"Not configured";
    _statusLabel.textColor = state == QDConnected ? Accent() : state == QDFailed ? NSColor.systemOrangeColor : NSColor.secondaryLabelColor;
    _statusLabel.toolTip = self.session.status;
    _connectButton.title = state == QDConnected ? @"Disconnect" : state == QDConnecting ? @"Cancel" : state == QDStopping ? @"Stopping…" : @"Connect";
    _connectButton.enabled = state != QDStopping;
    _editButton.enabled = !busy;
    _secureButton.enabled = state == QDConnected;
    self.layer.borderColor = self.selected ? Accent().CGColor : [NSColor colorWithWhite:0.21 alpha:1].CGColor;
    self.layer.borderWidth = self.selected ? 2 : 1;
    _desktop.placeholderTitle = state == QDConnecting ? @"Connecting…" : state == QDFailed ? @"Couldn’t connect" : self.profile.host.length ? self.profile.name : @"Add a computer";
    _desktop.placeholderDetail = state == QDFailed ? self.session.status : self.profile.host.length ?
        [NSString stringWithFormat:@"%@:%ld  ·  %@\nClick Connect when you’re ready.", self.profile.host, (long)self.profile.port, self.profile.username] :
        @"Click the gear to add a hostname and account.";
    _desktop.accessibilityLabel = [NSString stringWithFormat:@"%@ remote desktop. %@", self.profile.name, self.session.status];
    _desktop.needsDisplay = YES;
}
@end

@interface QDRootView : QDFlippedView
@property NSArray<QDTile *> *tiles;
@property NSTextField *titleLabel, *subtitleLabel, *footerLabel;
@property NSButton *allButton, *stopButton, *gridButton;
@property NSInteger expanded;
@end
@implementation QDRootView
- (void)layout {
    [super layout]; CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    self.titleLabel.frame = NSMakeRect(22, 16, 230, 28);
    self.subtitleLabel.frame = NSMakeRect(23, 47, 470, 20);
    self.allButton.frame = NSMakeRect(w-136, 26, 116, 32);
    self.stopButton.frame = NSMakeRect(w-266, 26, 124, 32);
    self.gridButton.frame = NSMakeRect(w-356, 26, 84, 32);
    self.footerLabel.frame = NSMakeRect(24, h-28, w-48, 18);
    NSRect area = NSMakeRect(20, 85, w-40, h-127);
    for (NSInteger i=0; i<4; i++) {
        QDTile *tile = self.tiles[i];
        tile.hidden = self.expanded >= 0 && i != self.expanded;
        if (self.expanded >= 0) tile.frame = area;
        else {
            CGFloat tw = (area.size.width-14)/2, th = (area.size.height-14)/2;
            tile.frame = NSMakeRect(area.origin.x+(i%2)*(tw+14), area.origin.y+(i/2)*(th+14), tw, th);
        }
        tile.needsLayout = YES;
    }
}
@end

@interface QDApp ()
@property NSWindow *window;
@property QDRootView *root;
@property NSMutableArray<QDProfile *> *profiles;
@property NSMutableArray<QDTile *> *tiles;
@property NSTimer *timer;
@property NSInteger selected;
@property NSMutableArray<void (^)(void)> *prompts;
@property NSAlert *activeAlert;
@property QDSession *activeAlertSession;
@property BOOL quitting, profileLoadFailed;
@end

@implementation QDApp
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    // Refresh the running Dock tile even if macOS cached the pre-icon bundle.
    NSURL *iconURL = [NSBundle.mainBundle URLForResource:@"QuadRDP" withExtension:@"icns"];
    NSImage *icon = iconURL ? [[NSImage alloc] initWithContentsOfURL:iconURL] : nil;
    if (icon.isValid) NSApp.applicationIconImage = icon;
    self.prompts = [NSMutableArray array]; self.tiles = [NSMutableArray array];
    NSError *loadError = nil; self.profiles = [QDLoadProfiles(&loadError) mutableCopy];
    self.profileLoadFailed = loadError != nil;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1360, 900)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"QuadRDP"; self.window.subtitle = @"Four computers. One workspace.";
    self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.window.backgroundColor = [NSColor colorWithWhite:0.07 alpha:1];
    self.window.minSize = NSMakeSize(1060, 680); self.window.delegate = self;
    self.window.releasedWhenClosed = NO; self.window.acceptsMouseMovedEvents = YES;
    [self.window setFrameAutosaveName:@"QuadRDP.MainWindow"];
    self.root = [[QDRootView alloc] initWithFrame:self.window.contentView.bounds]; self.root.expanded = -1;
    self.root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.window.contentView = self.root;
    self.root.titleLabel = Label(@"QuadRDP", 24, NSFontWeightBold);
    self.root.subtitleLabel = Label(@"YOUR REMOTE WORKSPACE", 10, NSFontWeightSemibold);
    self.root.subtitleLabel.textColor = NSColor.secondaryLabelColor;
    self.root.footerLabel = Label(@"⌘1–4  Focus computer     ⌘Return  Expand tile     ⌘0  Show grid     Control + Option = Windows Ctrl + Alt", 11, NSFontWeightRegular);
    self.root.footerLabel.textColor = NSColor.secondaryLabelColor;
    self.root.allButton = Button(@"Connect all", self, @selector(connectAll:));
    self.root.allButton.bezelColor = [NSColor colorWithSRGBRed:0.18 green:0.50 blue:0.40 alpha:1];
    self.root.stopButton = Button(@"Disconnect all", self, @selector(disconnectAll:));
    self.root.gridButton = Button(@"2 × 2 grid", self, @selector(showGrid:));
    for (NSView *v in @[self.root.titleLabel,self.root.subtitleLabel,self.root.footerLabel,self.root.allButton,self.root.stopButton,self.root.gridButton]) [self.root addSubview:v];
    __weak QDApp *weakSelf = self;
    for (NSInteger i=0; i<4; i++) {
        QDTile *tile = [[QDTile alloc] initWithFrame:NSZeroRect];
        tile.profile = self.profiles[i]; tile.session = [QDSession new]; tile.desktop.session = tile.session;
        tile.desktop.slot = i; tile.indexLabel.stringValue = [NSString stringWithFormat:@"%02ld", (long)i+1];
        tile.desktop.focused = ^{ [weakSelf selectTile:i]; };
        tile.session.stateChanged = ^{ [weakSelf refresh]; };
        __weak QDSession *weakSession = tile.session;
        tile.session.certificateRequest = ^(NSString *details, BOOL changed, void (^complete)(uint32_t)) {
            QDSession *session = weakSession;
            NSAlert *alert = [NSAlert new];
            alert.messageText = changed ? @"The computer’s certificate has changed" : @"Verify this computer’s certificate";
            alert.informativeText = [@"Continue only if you recognize this computer and its certificate.\n\n" stringByAppendingString:details];
            alert.alertStyle = changed ? NSAlertStyleCritical : NSAlertStyleWarning;
            [alert addButtonWithTitle:@"Cancel"]; [alert addButtonWithTitle:@"Connect Once"]; [alert addButtonWithTitle:@"Trust Certificate"];
            [weakSelf present:alert session:session completion:^(NSModalResponse response) {
                complete(response == NSAlertThirdButtonReturn ? 1 : response == NSAlertSecondButtonReturn ? 2 : 0);
            }];
        };
        for (NSButton *button in @[tile.connectButton,tile.editButton,tile.zoomButton,tile.secureButton]) { button.target = self; button.tag = i; }
        tile.connectButton.action = @selector(toggleConnection:); tile.editButton.action = @selector(editProfile:);
        tile.zoomButton.action = @selector(zoomTile:); tile.secureButton.action = @selector(secureAttention:);
        [self.tiles addObject:tile]; [self.root addSubview:tile];
    }
    self.root.tiles = self.tiles; [self installMenu]; [self selectTile:0];
    self.root.needsLayout = YES;
    [self.window center]; [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.tiles.firstObject.desktop];
    [NSApp activateIgnoringOtherApps:YES];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0/30 repeats:YES block:^(NSTimer *timer) {
        QDApp *app = weakSelf;
        for (QDTile *tile in app.tiles) if (!tile.hidden) [tile.desktop refresh];
        if (app.activeAlertSession && (app.activeAlertSession.stopping || app.activeAlertSession.state != QDConnecting))
            [app.window endSheet:app.activeAlert.window returnCode:NSModalResponseCancel];
        [app processPrompt];
        if (app.quitting) {
            BOOL busy = NO;
            for (QDTile *tile in app.tiles) if (tile.session.state == QDConnecting || tile.session.state == QDConnected || tile.session.state == QDStopping) busy = YES;
            if (!busy) { [app.timer invalidate]; [NSApp replyToApplicationShouldTerminate:YES]; }
        }
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    if (loadError) [self showError:loadError.localizedDescription];
}
- (void)installMenu {
    NSMenu *main = [NSMenu new]; NSMenuItem *appItem = [NSMenuItem new]; [main addItem:appItem];
    NSMenu *app = [NSMenu new]; appItem.submenu = app;
    NSMenuItem *about = [[NSMenuItem alloc] initWithTitle:@"About QuadRDP" action:@selector(about:) keyEquivalent:@""]; about.target = self; [app addItem:about];
    [app addItem:NSMenuItem.separatorItem];
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Configure Selected Computer…" action:@selector(editSelected:) keyEquivalent:@","]; settings.target=self; [app addItem:settings];
    [app addItem:NSMenuItem.separatorItem];
    [app addItemWithTitle:@"Quit QuadRDP" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenuItem *editItem=[NSMenuItem new]; editItem.title=@"Edit"; [main addItem:editItem];
    NSMenu *edit=[[NSMenu alloc] initWithTitle:@"Edit"]; editItem.submenu=edit;
    [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    NSMenuItem *viewItem = [NSMenuItem new]; viewItem.title = @"View"; [main addItem:viewItem];
    NSMenu *view = [[NSMenu alloc] initWithTitle:@"View"]; viewItem.submenu = view;
    for (NSInteger i=0; i<4; i++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Focus Computer %ld", (long)i+1]
            action:@selector(focusMenu:) keyEquivalent:[NSString stringWithFormat:@"%ld", (long)i+1]];
        item.target=self; item.tag=i; [view addItem:item];
    }
    [view addItem:NSMenuItem.separatorItem];
    NSMenuItem *expand = [[NSMenuItem alloc] initWithTitle:@"Expand / Restore Selected Tile" action:@selector(zoomSelected:) keyEquivalent:@"\r"]; expand.target=self; [view addItem:expand];
    NSMenuItem *grid = [[NSMenuItem alloc] initWithTitle:@"Show 2 × 2 Grid" action:@selector(showGrid:) keyEquivalent:@"0"]; grid.target=self; [view addItem:grid];
    [view addItemWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"].keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagCommand;
    NSApp.mainMenu = main;
}
- (void)about:(id)sender {
    NSAlert *alert=[NSAlert new]; alert.messageText=@"QuadRDP 0.1";
    alert.informativeText=@"Four independent RDP connections in one native Mac window.\n\nBuilt with AppKit and FreeRDP 3.\nCommand maps to the Windows key; Control and Option map to Ctrl and Alt.\n\nThis version supports desktop display, keyboard, mouse, and remote cursors. Clipboard, audio, drive redirection, and RD Gateway are not included.";
    [alert addButtonWithTitle:@"OK"]; [self present:alert session:nil completion:nil];
}
- (void)present:(NSAlert *)alert session:(QDSession *)session completion:(void (^)(NSModalResponse))completion {
    __weak QDApp *weakSelf=self;
    [self.prompts addObject:^{
        QDApp *app=weakSelf;
        if (app.quitting || (session && (session.stopping || session.state != QDConnecting))) {
            if (completion) completion(NSModalResponseCancel); return;
        }
        app.activeAlert=alert; app.activeAlertSession=session;
        [alert beginSheetModalForWindow:app.window completionHandler:^(NSModalResponse response) {
            app.activeAlert=nil; app.activeAlertSession=nil;
            if (completion) completion(response);
        }];
    }];
    [self processPrompt];
}
- (void)processPrompt {
    if (self.activeAlert || self.window.attachedSheet || !self.prompts.count || self.quitting) return;
    void (^show)(void)=self.prompts.firstObject; [self.prompts removeObjectAtIndex:0]; show();
}
- (void)showError:(NSString *)message {
    NSAlert *alert=[NSAlert new]; alert.messageText=@"QuadRDP"; alert.informativeText=message;
    [alert addButtonWithTitle:@"OK"]; [self present:alert session:nil completion:nil];
}
- (void)refresh {
    NSInteger connected=0;
    for (QDTile *tile in self.tiles) { [tile refresh]; if (tile.session.state==QDConnected) connected++; }
    self.root.subtitleLabel.stringValue=[NSString stringWithFormat:@"YOUR REMOTE WORKSPACE   ·   %ld / 4 CONNECTED", (long)connected];
}
- (void)selectTile:(NSInteger)index {
    self.selected=index;
    for (NSInteger i=0;i<4;i++) self.tiles[i].selected=i==index;
}
- (void)focusMenu:(NSMenuItem *)sender {
    [self selectTile:sender.tag];
    if (self.root.expanded>=0) { self.root.expanded=sender.tag; self.root.needsLayout=YES; }
    [self.window makeFirstResponder:self.tiles[sender.tag].desktop];
}
- (void)showGrid:(id)sender { self.root.expanded=-1; self.root.needsLayout=YES; }
- (void)zoomSelected:(id)sender { [self zoomTile:self.tiles[self.selected].zoomButton]; }
- (void)zoomTile:(NSButton *)sender {
    [self selectTile:sender.tag]; self.root.expanded=self.root.expanded==sender.tag ? -1 : sender.tag;
    self.root.needsLayout=YES; [self.window makeFirstResponder:self.tiles[sender.tag].desktop];
}
- (void)secureAttention:(NSButton *)sender {
    [self.tiles[sender.tag].desktop releaseInputs];
    [self.tiles[sender.tag].session sendControlAltDelete];
    [self.window makeFirstResponder:self.tiles[sender.tag].desktop];
}
- (void)connectAll:(id)sender {
    BOOL configured=NO;
    for (NSInteger i=0;i<4;i++) if (self.profiles[i].host.length) { configured=YES; [self connectTile:i]; }
    if (!configured) [self editSelected:nil];
}
- (void)disconnectAll:(id)sender {
    for (QDTile *tile in self.tiles) { [tile.desktop releaseInputs]; [tile.session disconnect]; }
}
- (void)toggleConnection:(NSButton *)sender {
    QDTile *tile=self.tiles[sender.tag];
    if (tile.session.state==QDConnecting || tile.session.state==QDConnected) { [tile.desktop releaseInputs]; [tile.session disconnect]; }
    else [self connectTile:sender.tag];
}
- (void)connectTile:(NSInteger)index {
    QDTile *tile=self.tiles[index];
    if (tile.session.state==QDConnecting || tile.session.state==QDConnected || tile.session.state==QDStopping) return;
    if (!tile.profile.host.length) { [self editProfile:tile.editButton]; return; }
    NSError *error=nil; NSString *password=[tile.profile password:&error];
    if (error) { [self showError:error.localizedDescription]; return; }
    if (password.length) { [tile.session connectProfile:tile.profile password:password]; return; }
    NSAlert *alert=[NSAlert new]; alert.messageText=[@"Connect to " stringByAppendingString:tile.profile.name];
    alert.informativeText=[NSString stringWithFormat:@"%@ · %@\nEnter the Windows account password (not a Windows Hello PIN).",tile.profile.host,tile.profile.username];
    [alert addButtonWithTitle:@"Connect"]; [alert addButtonWithTitle:@"Cancel"];
    QDFlippedView *accessory=[[QDFlippedView alloc] initWithFrame:NSMakeRect(0,0,380,65)];
    NSSecureTextField *field=[[NSSecureTextField alloc] initWithFrame:NSMakeRect(0,0,380,26)];
    field.placeholderString=@"Password";
    NSButton *remember=[NSButton checkboxWithTitle:@"Save password in macOS Keychain" target:nil action:NULL]; remember.frame=NSMakeRect(0,36,380,22);
    [accessory addSubview:field]; [accessory addSubview:remember]; alert.accessoryView=accessory;
    [self present:alert session:nil completion:^(NSModalResponse response) {
        if (response!=NSAlertFirstButtonReturn || self.quitting) return;
        NSString *secret=field.stringValue; field.stringValue=@"";
        if (remember.state==NSControlStateValueOn) {
            NSError *writeError=nil;
            if (![tile.profile savePassword:secret error:&writeError]) { [self showError:writeError.localizedDescription]; return; }
        }
        [tile.session connectProfile:tile.profile password:secret];
    }];
}
- (void)editSelected:(id)sender { [self editProfile:self.tiles[self.selected].editButton]; }
- (void)editProfile:(NSButton *)sender {
    if (self.profileLoadFailed) { [self showError:@"Fix the existing profiles.json file and relaunch before saving changes. Your original file has been preserved."]; return; }
    NSInteger index=sender.tag; QDTile *tile=self.tiles[index];
    if (tile.session.state==QDConnected || tile.session.state==QDConnecting || tile.session.state==QDStopping) return;
    QDProfile *draft=[tile.profile copy];
    NSAlert *alert=[NSAlert new]; alert.messageText=[NSString stringWithFormat:@"Configure computer %ld", (long)index+1];
    alert.informativeText=@"Set up the Windows computer for this tile. Enable Remote Desktop on that computer first.";
    [alert addButtonWithTitle:@"Save"]; [alert addButtonWithTitle:@"Cancel"];
    QDFlippedView *form=[[QDFlippedView alloc] initWithFrame:NSMakeRect(0,0,490,396)];
    NSArray *labels=@[@"Name",@"Host",@"Port",@"Username",@"Domain",@"Password"];
    NSArray *values=@[draft.name,draft.host,@(draft.port).stringValue,draft.username,draft.domain,@""];
    NSMutableArray<NSTextField *> *fields=[NSMutableArray array];
    for (NSInteger i=0;i<6;i++) {
        NSTextField *label=Label(labels[i],12,NSFontWeightMedium); label.frame=NSMakeRect(0,7+i*36,95,22); [form addSubview:label];
        NSTextField *field=i==5 ? [NSSecureTextField new] : [NSTextField new];
        field.frame=NSMakeRect(104,i*36,386,26); field.stringValue=values[i];
        field.placeholderString=i==1 ? @"192.168.1.10 or computer.example.com" : i==3 ? @"user or DOMAIN\\user" : i==4 ? @"Optional" : i==5 ? @"Leave empty to keep the existing password" : @"";
        [form addSubview:field]; [fields addObject:field];
    }
    NSButton *forget=[NSButton checkboxWithTitle:@"Remove saved password for this account" target:nil action:NULL];
    forget.frame=NSMakeRect(104,216,386,24); [form addSubview:forget];
    NSTextField *resolutionLabel=Label(@"Resolution",12,NSFontWeightMedium); resolutionLabel.frame=NSMakeRect(0,252,98,22); [form addSubview:resolutionLabel];
    NSPopUpButton *resolution=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(104,245,386,28) pullsDown:NO];
    NSArray *sizes=@[@[@1280,@720],@[@1600,@900],@[@1920,@1080],@[@2560,@1440],@[@3840,@2160]];
    for (NSArray *size in sizes) {
        [resolution addItemWithTitle:[NSString stringWithFormat:@"%@ × %@",size[0],size[1]]];
        if ([size[0] integerValue]==draft.width && [size[1] integerValue]==draft.height) [resolution selectItemAtIndex:resolution.numberOfItems-1];
    }
    [form addSubview:resolution];
    NSTextField *securityLabel=Label(@"Security",12,NSFontWeightMedium); securityLabel.frame=NSMakeRect(0,287,98,22); [form addSubview:securityLabel];
    NSPopUpButton *security=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(104,280,386,28) pullsDown:NO];
    [security addItemsWithTitles:@[@"Network Level Authentication (recommended)",@"TLS only (for servers without NLA)"]];
    [security selectItemAtIndex:draft.useNLA ? 0 : 1]; [form addSubview:security];
    NSTextField *hint=Label(@"Passwords you enter here are saved in macOS Keychain.\nThe selected resolution scales to fit the tile or expanded view.",11,NSFontWeightRegular);
    hint.textColor=NSColor.secondaryLabelColor; hint.maximumNumberOfLines=2; hint.frame=NSMakeRect(0,321,490,34); [form addSubview:hint];
    QDFormValidation *validator=[QDFormValidation new];
    validator.fields=fields; validator.profile=draft; validator.save=alert.buttons.firstObject;
    validator.message=Label(@"",11,NSFontWeightRegular);
    validator.message.textColor=NSColor.systemOrangeColor;
    validator.message.maximumNumberOfLines=2; validator.message.frame=NSMakeRect(0,362,490,34);
    [form addSubview:validator.message]; form.retainedController=validator;
    for (NSTextField *field in fields) field.delegate=validator;
    [validator validate];
    alert.accessoryView=form;
    [self present:alert session:nil completion:^(NSModalResponse response) {
        if (response!=NSAlertFirstButtonReturn) return;
        draft.name=fields[0].stringValue;
        draft.host=[fields[1].stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *portText=fields[2].stringValue;
        NSCharacterSet *notDigits=NSCharacterSet.decimalDigitCharacterSet.invertedSet;
        draft.port=[portText rangeOfCharacterFromSet:notDigits].location==NSNotFound ? portText.integerValue : 0;
        draft.username=[fields[3].stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        draft.domain=fields[4].stringValue;
        NSArray *size=sizes[resolution.indexOfSelectedItem]; draft.width=[size[0] integerValue]; draft.height=[size[1] integerValue];
        draft.useNLA=security.indexOfSelectedItem==0;
        if (!draft.name.length) draft.name=draft.host;
        NSString *validation=draft.validationError;
        if (validation) { [self showError:validation]; return; }
        NSError *error=nil;
        NSString *secret=fields[5].stringValue;
        if (forget.state==NSControlStateValueOn || secret.length) {
            if (![draft savePassword:forget.state==NSControlStateValueOn ? @"" : secret error:&error]) { [self showError:error.localizedDescription]; return; }
        }
        NSMutableArray *updated=[self.profiles mutableCopy]; updated[index]=draft;
        if (!QDSaveProfiles(updated,&error)) { [self showError:error.localizedDescription]; return; }
        fields[5].stringValue=@""; self.profiles=updated; tile.profile=draft; [self refresh];
    }];
}
- (void)windowDidResignKey:(NSNotification *)notification { for (QDTile *tile in self.tiles) [tile.desktop releaseInputs]; }
- (void)applicationDidResignActive:(NSNotification *)notification { for (QDTile *tile in self.tiles) [tile.desktop releaseInputs]; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (self.quitting) return NSTerminateLater;
    BOOL busy=NO;
    for (QDTile *tile in self.tiles) if (tile.session.state==QDConnected || tile.session.state==QDConnecting || tile.session.state==QDStopping) busy=YES;
    if (!busy) return NSTerminateNow;
    self.quitting=YES; [self disconnectAll:nil];
    if (self.activeAlert) [self.window endSheet:self.activeAlert.window returnCode:NSModalResponseCancel];
    [self.prompts removeAllObjects]; return NSTerminateLater;
}
@end
