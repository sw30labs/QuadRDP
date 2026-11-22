#import "QDDesktopView.h"
#import "QDApp.h"
#define REFIID WINPR_REFIID
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmacro-redefined"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include <freerdp/freerdp.h>
#include <freerdp/peer.h>
#include <freerdp/settings.h>
#include <freerdp/transport_io.h>
#include <freerdp/crypto/certificate.h>
#include <freerdp/crypto/privatekey.h>
#include <freerdp/input.h>
#include <freerdp/update.h>
#include <freerdp/channels/channels.h>
#include <freerdp/channels/wtsvc.h>
#include <freerdp/server/rdpgfx.h>
#include <winpr/synch.h>
#pragma clang diagnostic pop
#undef REFIID
#include <sys/socket.h>
#include <unistd.h>
#include <signal.h>

static int assertions=0;
#define Check(test) do { __atomic_fetch_add(&assertions,1,__ATOMIC_RELAXED); if (!(test)) { fprintf(stderr,"FAIL %s:%d: %s\n",__FILE__,__LINE__,#test); exit(1); } } while(0)
static BOOL Spin(NSTimeInterval seconds, BOOL (^condition)(void)) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && end.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return condition();
}

// A synthetic TLS RDP peer; no listening ports, network hosts, or Windows credentials.
@interface TestPeer : NSObject
@property int socketFD;
@property NSUInteger color;
@property (atomic) NSUInteger mouseCount, keyCount;
@property (atomic) BOOL stopped;
@property dispatch_semaphore_t finished;
@property BOOL alternateCertificate;
@property BOOL useGfx;
@property (atomic) NSUInteger gfxAcknowledgements;
- (void)run;
@end
typedef struct { rdpContext base; void *owner; HANDLE vcm; } PeerContext;
static TestPeer *PeerOwner(rdpContext *c) { return (__bridge TestPeer *)((PeerContext *)c)->owner; }
static BOOL Mouse(rdpInput *input, UINT16 flags, UINT16 x, UINT16 y) { PeerOwner(input->context).mouseCount++; return TRUE; }
static BOOL Key(rdpInput *input, UINT16 flags, UINT8 code) { PeerOwner(input->context).keyCount++; return TRUE; }
static BOOL Sync(rdpInput *input, UINT32 flags) { return TRUE; }
static BOOL PeerConnected(freerdp_peer *peer) { return TRUE; }
static BOOL PeerCapabilities(freerdp_peer *peer) {
    if (!PeerOwner(peer->context).useGfx) return TRUE;
    return freerdp_settings_get_bool(peer->context->settings, FreeRDP_SupportGraphicsPipeline) &&
        WTSVirtualChannelManagerIsChannelJoined(((PeerContext *)peer->context)->vcm, "drdynvc");
}
static UINT GfxFrameAcknowledged(RdpgfxServerContext *gfx, const RDPGFX_FRAME_ACKNOWLEDGE_PDU *ack) {
    ((__bridge TestPeer *)gfx->custom).gfxAcknowledgements++;
    return CHANNEL_RC_OK;
}
static UINT GfxCapsAdvertise(RdpgfxServerContext *gfx, const RDPGFX_CAPS_ADVERTISE_PDU *caps) {
    Check(caps->capsSetCount > 0);
    RDPGFX_CAPS_CONFIRM_PDU confirm={.capsSet=&caps->capsSets[0]};
    Check(gfx->CapsConfirm(gfx,&confirm)==CHANNEL_RC_OK);
    MONITOR_DEF monitor={.left=0,.top=0,.right=639,.bottom=479,.flags=1};
    RDPGFX_RESET_GRAPHICS_PDU reset={.width=640,.height=480,.monitorCount=1,.monitorDefArray=&monitor};
    Check(gfx->ResetGraphics(gfx,&reset)==CHANNEL_RC_OK);
    RDPGFX_CREATE_SURFACE_PDU surface={.surfaceId=1,.width=640,.height=480,.pixelFormat=GFX_PIXEL_FORMAT_XRGB_8888};
    Check(gfx->CreateSurface(gfx,&surface)==CHANNEL_RC_OK);
    RDPGFX_MAP_SURFACE_TO_OUTPUT_PDU mapping={.surfaceId=1};
    Check(gfx->MapSurfaceToOutput(gfx,&mapping)==CHANNEL_RC_OK);
    RDPGFX_START_FRAME_PDU start={.frameId=1};
    Check(gfx->StartFrame(gfx,&start)==CHANNEL_RC_OK);
    RECTANGLE_16 rectangle={.left=0,.top=0,.right=64,.bottom=64};
    RDPGFX_SOLID_FILL_PDU fill={.surfaceId=1,.fillRectCount=1,.fillRects=&rectangle};
    fill.fillPixel.B=20; fill.fillPixel.G=40; fill.fillPixel.R=(UINT8)((__bridge TestPeer *)gfx->custom).color; fill.fillPixel.XA=255;
    Check(gfx->SolidFill(gfx,&fill)==CHANNEL_RC_OK);
    RDPGFX_END_FRAME_PDU end={.frameId=1};
    Check(gfx->EndFrame(gfx,&end)==CHANNEL_RC_OK);
    return CHANNEL_RC_OK;
}
static BOOL Activate(freerdp_peer *peer) {
    if (PeerOwner(peer->context).useGfx) return TRUE;
    uint8_t bytes[64*64*4];
    NSUInteger color=PeerOwner(peer->context).color;
    for (int i=0;i<64*64;i++) { bytes[i*4]=20; bytes[i*4+1]=40; bytes[i*4+2]=(uint8_t)color; bytes[i*4+3]=255; }
    SURFACE_BITS_COMMAND command={0};
    command.cmdType=CMDTYPE_SET_SURFACE_BITS; command.destRight=64; command.destBottom=64;
    command.bmp.bpp=32; command.bmp.width=64; command.bmp.height=64;
    command.bmp.bitmapDataLength=sizeof(bytes); command.bmp.bitmapData=bytes;
    return peer->context->update->SurfaceBits(peer->context, &command);
}
@implementation TestPeer
- (void)run {
    @autoreleasepool {
        freerdp_peer *peer=freerdp_peer_new(self.socketFD);
        Check(peer); peer->ContextSize=sizeof(PeerContext);
        Check(freerdp_peer_context_new(peer)); ((PeerContext *)peer->context)->owner=(__bridge void *)self;
        rdpSettings *s=peer->context->settings;
        rdpCertificate *cert=freerdp_certificate_new_from_file(self.alternateCertificate ? "build/test-data/cert2.pem" : "build/test-data/cert.pem");
        rdpPrivateKey *key=freerdp_key_new_from_file(self.alternateCertificate ? "build/test-data/key2.pem" : "build/test-data/key.pem");
        Check(cert && key);
        Check(freerdp_settings_set_pointer(s,FreeRDP_RdpServerCertificate,cert));
        Check(freerdp_settings_set_pointer(s,FreeRDP_RdpServerRsaKey,key));
        Check(freerdp_settings_set_bool(s,FreeRDP_NlaSecurity,FALSE));
        Check(freerdp_settings_set_bool(s,FreeRDP_TlsSecurity,TRUE));
        Check(freerdp_settings_set_bool(s,FreeRDP_RdpSecurity,FALSE));
        Check(freerdp_settings_set_uint32(s,FreeRDP_ColorDepth,32));
        Check(freerdp_settings_set_bool(s,FreeRDP_SupportGraphicsPipeline,self.useGfx));
        peer->Capabilities=PeerCapabilities; peer->PostConnect=PeerConnected; peer->Activate=Activate;
        HANDLE vcm=NULL; RdpgfxServerContext *gfx=NULL; BOOL gfxOpened=NO;
        if (self.useGfx) {
            vcm=WTSOpenServerA((LPSTR)peer->context); Check(vcm && vcm!=INVALID_HANDLE_VALUE);
            ((PeerContext *)peer->context)->vcm=vcm;
            gfx=rdpgfx_server_context_new(vcm); Check(gfx);
            gfx->rdpcontext=peer->context; gfx->custom=(__bridge void *)self;
            gfx->CapsAdvertise=GfxCapsAdvertise; gfx->FrameAcknowledge=GfxFrameAcknowledged;
        }
        peer->context->input->MouseEvent=Mouse; peer->context->input->KeyboardEvent=Key;
        peer->context->input->SynchronizeEvent=Sync;
        Check(peer->Initialize(peer));
        while (!self.stopped) {
            HANDLE handles[MAXIMUM_WAIT_OBJECTS];
            DWORD count=peer->GetEventHandles(peer,handles,MAXIMUM_WAIT_OBJECTS);
            if (!count || WaitForMultipleObjects(count,handles,FALSE,50)==WAIT_FAILED) break;
            if (!peer->CheckFileDescriptor(peer)) break;
            if (vcm && peer->connected) {
                Check(WTSVirtualChannelManagerCheckFileDescriptor(vcm));
                if (!gfxOpened && WTSVirtualChannelManagerGetDrdynvcState(vcm)==DRDYNVC_STATE_READY) {
                    Check(gfx->Open(gfx)); gfxOpened=YES;
                }
            }
        }
        if (gfx) { Check(gfx->Close(gfx)); rdpgfx_server_context_free(gfx); }
        if (vcm) WTSCloseServer(vcm);
        peer->Disconnect(peer); freerdp_peer_context_free(peer); freerdp_peer_free(peer);
        self.stopped=YES; dispatch_semaphore_signal(self.finished);
    }
}
@end

@interface QDSession (TransportTestSeam)
- (BOOL)prepareTransport:(void *)context;
@end
@interface TestSession : QDSession
@property TestPeer *peer;
@property int clientFD;
@property BOOL stall;
@property BOOL alternateCertificate;
@property BOOL useGfx;
@end
static int PairConnect(rdpContext *context, rdpSettings *settings, const char *host, int port, DWORD timeout) {
    TestSession *session=(__bridge TestSession *)freerdp_get_io_callback_context(context);
    int descriptor=session.clientFD; session.clientFD=-1; return descriptor;
}
@implementation TestSession
- (BOOL)prepareTransport:(void *)nativeContext {
    int pair[2]; if (socketpair(AF_UNIX,SOCK_STREAM,0,pair)) return NO;
    self.clientFD=pair[0];
    TestPeer *peer=[TestPeer new]; peer.socketFD=pair[1]; peer.color=100+arc4random_uniform(140);
    peer.alternateCertificate=self.alternateCertificate;
    peer.useGfx=self.useGfx;
    peer.finished=dispatch_semaphore_create(0); self.peer=peer;
    if (!self.stall) dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{ [peer run]; });
    rdpContext *context=nativeContext;
    rdpTransportIo callbacks=*freerdp_get_io_callbacks(context); callbacks.TCPConnect=PairConnect;
    return freerdp_set_io_callback_context(context,(__bridge void *)self) && freerdp_set_io_callbacks(context,&callbacks);
}
@end

static QDProfile *TestProfile(void) {
    QDProfile *p=[QDProfile emptyProfile:0]; p.host=@"localhost"; p.username=@"test";
    p.width=640; p.height=480; p.useNLA=NO; return p;
}

@interface QDApp (LaunchTestSeam)
- (void)connectOnLaunch;
- (void)connectAll:(id)sender;
- (void)connectTile:(NSInteger)index;
- (void)disconnectAll:(id)sender;
- (void)toggleConnection:(NSButton *)sender;
- (void)editProfile:(NSButton *)sender;
@end
@interface TestApp : QDApp
@property NSMutableArray<NSNumber *> *connectedTiles;
@property NSUInteger editorRequests;
@end
@implementation TestApp
- (void)connectTile:(NSInteger)index { [self.connectedTiles addObject:@(index)]; }
- (void)editSelected:(id)sender { self.editorRequests++; }
@end

@interface CredentialTestSession : QDSession
@property NSUInteger connections;
@end
@implementation CredentialTestSession
- (BOOL)connectProfile:(QDProfile *)profile password:(NSString *)password {
    Check(NSThread.isMainThread); Check([password isEqualToString:@"synthetic-credential"]);
    self.connections++; return YES;
}
@end
@interface CredentialTestApp : QDApp
@property dispatch_semaphore_t credentialGate;
@property (atomic) NSUInteger reads, activeReads, maximumActiveReads;
@property NSUInteger errors;
@property BOOL missingPassword, failedRead;
@end
@implementation CredentialTestApp
- (NSString *)passwordForProfile:(QDProfile *)profile error:(NSError **)error {
    Check(!NSThread.isMainThread);
    @synchronized (self) {
        self.reads++; self.activeReads++;
        self.maximumActiveReads=MAX(self.maximumActiveReads,self.activeReads);
    }
    Check(dispatch_semaphore_wait(self.credentialGate,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    @synchronized (self) { self.activeReads--; }
    if (self.failedRead) { *error=[NSError errorWithDomain:@"Synthetic" code:1 userInfo:nil]; return nil; }
    return self.missingPassword ? nil : @"synthetic-credential";
}
- (void)showError:(NSString *)message { Check(NSThread.isMainThread); self.errors++; }
- (void)processPrompt {} // Inspect queued app prompts without opening a window.
@end
static CredentialTestApp *CredentialApp(void) {
    CredentialTestApp *app=[CredentialTestApp new]; app.credentialGate=dispatch_semaphore_create(0);
    NSMutableArray *tiles=[NSMutableArray array], *profiles=[NSMutableArray array];
    for (NSInteger i=0;i<4;i++) {
        QDProfile *profile=TestProfile(); [profiles addObject:profile];
        id tile=[[NSClassFromString(@"QDTile") alloc] initWithFrame:NSZeroRect];
        [tile setValue:profile forKey:@"profile"];
        [tile setValue:[CredentialTestSession new] forKey:@"session"];
        [[tile valueForKey:@"connectButton"] setTag:i]; [[tile valueForKey:@"editButton"] setTag:i];
        [tiles addObject:tile];
    }
    [app setValue:tiles forKey:@"tiles"]; [app setValue:profiles forKey:@"profiles"];
    [app setValue:[NSMutableArray array] forKey:@"prompts"];
    return app;
}
static void DrainCredentialQueue(CredentialTestApp *app) {
    __block BOOL drained=NO;
    dispatch_async([app valueForKey:@"credentialQueue"], ^{ dispatch_async(dispatch_get_main_queue(), ^{ drained=YES; }); });
    Check(Spin(3,^BOOL{ return drained; }));
}
static void CredentialConnectionTests(void) {
    CredentialTestApp *app=CredentialApp(); NSArray *tiles=[app valueForKey:@"tiles"];
    [app connectAll:nil]; [app connectAll:nil];
    Check(Spin(2,^BOOL{ return app.reads==1; }));
    for (id tile in tiles) {
        Check([[[tile valueForKey:@"statusLabel"] stringValue] isEqualToString:@"Waiting for Keychain…"]);
        Check(![[tile valueForKey:@"editButton"] isEnabled]);
        Check([[[tile valueForKey:@"connectButton"] title] isEqualToString:@"Cancel"]);
        [app editProfile:[tile valueForKey:@"editButton"]];
    }
    Check([[app valueForKey:@"prompts"] count]==0);
    // The main queue remains responsive while the first credential read is blocked.
    __block BOOL responsive=NO; dispatch_async(dispatch_get_main_queue(), ^{ responsive=YES; });
    Check(Spin(1,^BOOL{ return responsive; }));
    [app disconnectAll:nil]; dispatch_semaphore_signal(app.credentialGate); DrainCredentialQueue(app);
    Check(app.reads==1 && app.errors==0); // Cancelled queued reads never reach the provider.
    for (id tile in tiles) {
        Check(![tile valueForKey:@"connectionRequest"]);
        Check([[tile valueForKey:@"editButton"] isEnabled]);
        Check(((CredentialTestSession *)[tile valueForKey:@"session"]).connections==0);
    }

    app=CredentialApp(); tiles=[app valueForKey:@"tiles"];
    [app connectAll:nil];
    for (NSUInteger i=1;i<=4;i++) {
        Check(Spin(2,^BOOL{ return app.reads==i; }));
        Check(app.activeReads==1 && app.maximumActiveReads==1);
        dispatch_semaphore_signal(app.credentialGate);
    }
    DrainCredentialQueue(app);
    for (id tile in tiles) Check(((CredentialTestSession *)[tile valueForKey:@"session"]).connections==1);

    app=CredentialApp(); id tile=[[app valueForKey:@"tiles"] firstObject];
    [app connectTile:0]; Check(Spin(2,^BOOL{ return app.reads==1; }));
    [app toggleConnection:[tile valueForKey:@"connectButton"]]; [app connectTile:0];
    id newer=[tile valueForKey:@"connectionRequest"];
    dispatch_semaphore_signal(app.credentialGate);
    Check(Spin(2,^BOOL{ return app.reads==2; }));
    Check([tile valueForKey:@"connectionRequest"]==newer);
    Check(((CredentialTestSession *)[tile valueForKey:@"session"]).connections==0);
    dispatch_semaphore_signal(app.credentialGate); DrainCredentialQueue(app);
    Check(((CredentialTestSession *)[tile valueForKey:@"session"]).connections==1);

    app=CredentialApp(); app.missingPassword=YES; tile=[[app valueForKey:@"tiles"] firstObject];
    [app connectTile:0]; dispatch_semaphore_signal(app.credentialGate); DrainCredentialQueue(app);
    Check([tile valueForKey:@"connectionRequest"]!=nil);
    Check([[[tile valueForKey:@"statusLabel"] stringValue] isEqualToString:@"Password required"]);
    [app connectTile:0]; Check(app.reads==1 && [[app valueForKey:@"prompts"] count]==1);
    [app disconnectAll:nil];
    void (^queuedPrompt)(void)=[[app valueForKey:@"prompts"] firstObject]; queuedPrompt();
    Check(![app valueForKey:@"activeAlert"] && ![tile valueForKey:@"connectionRequest"]);
    Check(((CredentialTestSession *)[tile valueForKey:@"session"]).connections==0);

    app=CredentialApp(); app.failedRead=YES; tile=[[app valueForKey:@"tiles"] firstObject];
    [app connectTile:0]; Check(Spin(2,^BOOL{ return app.reads==1; }));
    Check([app applicationShouldTerminate:NSApp]==NSTerminateNow);
    Check(![tile valueForKey:@"connectionRequest"]);
    dispatch_semaphore_signal(app.credentialGate); DrainCredentialQueue(app);
    Check(app.errors==0 && ((CredentialTestSession *)[tile valueForKey:@"session"]).connections==0);
    puts("PASS responsive serialized credential reads, duplicate prevention, cancel-all, cancel/retry, stale prompts/errors, immediate quit");
}

static void LaunchConnectionTests(void) {
    // Override only this process's defaults; do not write the user's preferences.
    NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;
    NSDictionary *original=[defaults volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *arguments=[original mutableCopy];
    arguments[@"AutoConnectOnLaunch"]=@NO;
    [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
    TestApp *app=[TestApp new]; app.connectedTiles=[NSMutableArray array];
    NSMutableArray *profiles=[NSMutableArray array];
    for (NSInteger i=0;i<4;i++) [profiles addObject:[QDProfile emptyProfile:i]];
    profiles[0]=TestProfile(); profiles[2]=TestProfile();
    [app setValue:profiles forKey:@"profiles"];
    [app connectOnLaunch]; Check(app.connectedTiles.count==0 && app.editorRequests==0);
    arguments[@"AutoConnectOnLaunch"]=@YES;
    [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
    [app connectOnLaunch]; Check(([app.connectedTiles isEqualToArray:@[@0,@2]]));
    [app.connectedTiles removeAllObjects];
    [app setValue:@YES forKey:@"profileLoadFailed"];
    [app connectOnLaunch]; Check(app.connectedTiles.count==0 && app.editorRequests==0);
    [app setValue:@NO forKey:@"profileLoadFailed"];
    [app setValue:@YES forKey:@"quitting"];
    [app connectOnLaunch]; Check(app.connectedTiles.count==0);
    [app setValue:@NO forKey:@"quitting"];
    profiles[0]=[QDProfile emptyProfile:0]; profiles[2]=[QDProfile emptyProfile:2];
    [app connectOnLaunch]; Check(app.connectedTiles.count==0 && app.editorRequests==0);
    [app connectAll:nil]; Check(app.editorRequests==1);
    [defaults setVolatileDomain:original forName:NSArgumentDomain];
    puts("PASS optional startup connections, empty tiles, profile-load failure, shutdown, manual configure fallback");
}
static void ModelAndInputTests(void) {
    NSError *error=nil;
    NSArray *profiles=QDLoadProfiles(&error); Check(!error && profiles.count==4);
    QDProfile *p=TestProfile(); Check(!p.validationError);
    p.host=@"https://server"; Check(p.validationError); p.host=@"::1"; Check(!p.validationError);
    p.port=65536; Check(p.validationError); p.port=3389;
    NSMutableArray *saved=[profiles mutableCopy]; saved[0]=p;
    Check(QDSaveProfiles(saved,&error)); Check(!error);
    NSArray *loaded=QDLoadProfiles(&error); Check([loaded[0] host] && [[loaded[0] host] isEqualToString:@"::1"]);
    NSData *json=[NSData dataWithContentsOfURL:[QDDataDirectory() URLByAppendingPathComponent:@"profiles.json"]];
    NSString *serialized=[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    Check(serialized.length>0 && ![serialized.lowercaseString containsString:@"password"]);
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:[QDDataDirectory() URLByAppendingPathComponent:@"profiles.json"].path error:&error];
    Check(([attributes[NSFilePosixPermissions] intValue]&0777)==0600);
    NSURL *profileFile=[QDDataDirectory() URLByAppendingPathComponent:@"profiles.json"];
    Check([@"{broken" writeToURL:profileFile atomically:YES encoding:NSUTF8StringEncoding error:&error]);
    error=nil; Check(QDLoadProfiles(&error).count==4 && error!=nil);
    Check([[NSString stringWithContentsOfURL:profileFile encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"{broken"]);
    error=nil; Check(QDSaveProfiles(saved,&error));
    Check(QDScanCode(0)==0x1e); Check(QDScanCode(123)==0x14b); Check(QDScanCode(62)==0x11d); Check(QDScanCode(400)==0);
    NSRect fit=QDAspectFit(NSMakeSize(1920,1080),NSMakeRect(0,0,800,600));
    Check(NSEqualRects(fit,NSMakeRect(0,75,800,450)));
    Check(NSEqualPoints(QDRemotePoint(NSMakePoint(400,300),fit,NSMakeSize(1920,1080)),NSMakePoint(960,540)));
    Check(NSEqualPoints(QDRemotePoint(NSMakePoint(-10,0),fit,NSMakeSize(1920,1080)),NSZeroPoint));
    Check(NSEqualPoints(QDRemotePoint(NSMakePoint(900,900),fit,NSMakeSize(1920,1080)),NSMakePoint(1919,1079)));
    uint8_t pixel[]={0x00,0x00,0xff,0xff};
    QDFrame *frame=[QDFrame new]; frame.pixels=[NSData dataWithBytes:pixel length:4]; frame.width=1; frame.height=1; frame.stride=4;
    CGImageRef image=[frame createImage]; Check(image); Check(CGImageGetWidth(image)==1); CGImageRelease(image);
    puts("PASS profile persistence, validation, permissions, keyboard mapping, letterbox coordinates, image creation");
}

int main(void) {
    @autoreleasepool {
        signal(SIGPIPE,SIG_IGN);
        [NSApplication sharedApplication];
        Check(WTSRegisterWtsApiFunctionTable(FreeRDP_InitWtsApi()));
        LaunchConnectionTests();
        CredentialConnectionTests();
        ModelAndInputTests();
        TestSession *gfxSession=[TestSession new]; gfxSession.useGfx=YES;
        gfxSession.certificateRequest=^(NSString *d,BOOL changed,void (^done)(uint32_t)){ done(2); };
        Check([gfxSession connectProfile:TestProfile() password:@"synthetic-test"]);
        Check(Spin(15,^BOOL{ return gfxSession.state==QDConnected && gfxSession.frame!=nil && gfxSession.peer.gfxAcknowledgements>0; }));
        Check(gfxSession.frame.width==640 && gfxSession.frame.height==480);
        Check(((const uint8_t *)gfxSession.frame.pixels.bytes)[2]==gfxSession.peer.color);
        [gfxSession disconnect]; Check(Spin(5,^BOOL{ return gfxSession.state==QDIdle; }));
        Check([gfxSession connectProfile:TestProfile() password:@"synthetic-test"]);
        Check(Spin(15,^BOOL{ return gfxSession.state==QDConnected && gfxSession.frame!=nil && gfxSession.peer.gfxAcknowledgements>0; }));
        [gfxSession disconnect]; Check(Spin(5,^BOOL{ return gfxSession.state==QDIdle; }));
        puts("PASS required graphics capability, dynamic channel, GFX rendered pixels, frame acknowledgement, reconnect");
        NSMutableArray<TestSession *> *sessions=[NSMutableArray array];
        __block NSUInteger certificates=0;
        for (NSUInteger i=0;i<4;i++) {
            TestSession *session=[TestSession new];
            session.certificateRequest=^(NSString *details, BOOL changed, void (^completion)(uint32_t)) {
                certificates++; Check([details containsString:@"localhost"]); completion(2);
            };
            Check([session connectProfile:TestProfile() password:@"synthetic-test"]); [sessions addObject:session];
        }
        BOOL live=Spin(20,^{ for (TestSession *s in sessions) if (s.state!=QDConnected || !s.frame) return NO; return YES; });
        if (!live) for (TestSession *s in sessions) fprintf(stderr,"session state %ld: %s, frame %p\n",(long)s.state,s.status.UTF8String,s.frame);
        Check(live); Check(certificates==4);
        for (TestSession *s in sessions) {
            QDFrame *frame=s.frame; Check(frame.width==640 && frame.height==480);
            const uint8_t *bytes=frame.pixels.bytes; Check(bytes[2]==s.peer.color);
        }
        [sessions[1] mouseFlags:0x9000 x:24 y:32]; [sessions[1] mouseFlags:0x1000 x:24 y:32];
        [sessions[1] keyScanCode:0x1e down:YES repeat:NO]; [sessions[1] keyScanCode:0x1e down:NO repeat:NO];
        Check(Spin(3,^BOOL{ return sessions[1].peer.mouseCount==2 && sessions[1].peer.keyCount==2; }));
        Check(sessions[0].peer.mouseCount==0 && sessions[2].peer.keyCount==0 && sessions[3].peer.mouseCount==0);
        puts("PASS four simultaneous TLS RDP handshakes, certificate callbacks, decoded pixels, isolated mouse and keyboard input");
        for (TestSession *s in sessions) [s disconnect];
        Check(Spin(5,^{ for (TestSession *s in sessions) if (s.state!=QDIdle) return NO; return YES; }));
        TestSession *again=sessions[0];
        Check([again connectProfile:TestProfile() password:@"synthetic-test"]);
        Check(Spin(10,^BOOL{ return again.state==QDConnected && again.frame!=nil; }));
        [again disconnect]; Check(Spin(5,^BOOL{ return again.state==QDIdle; }));
        TestSession *reject=[TestSession new];
        reject.certificateRequest=^(NSString *d,BOOL c,void (^done)(uint32_t)){ done(0); };
        Check([reject connectProfile:TestProfile() password:@"synthetic-test"]);
        Check(Spin(10,^BOOL{ return reject.state==QDFailed; })); Check(!reject.frame);
        TestSession *remember=[TestSession new]; __block NSUInteger prompts=0;
        remember.certificateRequest=^(NSString *d,BOOL changed,void (^done)(uint32_t)){ prompts++; Check(!changed); done(1); };
        Check([remember connectProfile:TestProfile() password:@"synthetic-test"]);
        Check(Spin(10,^BOOL{ return remember.state==QDConnected && remember.frame; }));
        [remember disconnect]; Check(Spin(5,^BOOL{ return remember.state==QDIdle; })); Check(prompts==1);
        Check([remember connectProfile:TestProfile() password:@"synthetic-test"]);
        Check(Spin(10,^BOOL{ return remember.state==QDConnected && remember.frame; })); Check(prompts==1);
        [remember disconnect]; Check(Spin(5,^BOOL{ return remember.state==QDIdle; }));
        remember.alternateCertificate=YES;
        remember.certificateRequest=^(NSString *d,BOOL changed,void (^done)(uint32_t)){ prompts++; Check(changed); done(0); };
        Check([remember connectProfile:TestProfile() password:@"synthetic-test"]);
        Check(Spin(10,^BOOL{ return remember.state==QDFailed; })); Check(prompts==2);
        puts("PASS disconnect, reconnect, certificate rejection, saved trust, changed-certificate rejection");
        TestSession *stall=[TestSession new]; stall.stall=YES;
        Check([stall connectProfile:TestProfile() password:@"synthetic-test"]);
        Check(Spin(3,^BOOL{ return stall.peer!=nil; }));
        [stall disconnect]; Check(Spin(3,^BOOL{ return stall.state==QDIdle; })); close(stall.peer.socketFD);
        TestSession *pending=[TestSession new]; __block BOOL asked=NO; pending.alternateCertificate=YES;
        pending.certificateRequest=^(NSString *d,BOOL c,void (^done)(uint32_t)){ asked=YES; };
        Check([pending connectProfile:TestProfile() password:@"synthetic-test"]);
        Check(Spin(5,^BOOL{ return asked; }));
        [pending disconnect]; Check(Spin(3,^BOOL{ return pending.state==QDIdle; }));
        puts("PASS cancellation during a stalled handshake and an unanswered certificate prompt");
        printf("All %d assertions passed.\n",assertions);
    }
    return 0;
}
