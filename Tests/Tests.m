#import "QDDesktopView.h"
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
- (void)run;
@end
typedef struct { rdpContext base; void *owner; } PeerContext;
static TestPeer *PeerOwner(rdpContext *c) { return (__bridge TestPeer *)((PeerContext *)c)->owner; }
static BOOL Mouse(rdpInput *input, UINT16 flags, UINT16 x, UINT16 y) { PeerOwner(input->context).mouseCount++; return TRUE; }
static BOOL Key(rdpInput *input, UINT16 flags, UINT8 code) { PeerOwner(input->context).keyCount++; return TRUE; }
static BOOL Sync(rdpInput *input, UINT32 flags) { return TRUE; }
static BOOL PeerConnected(freerdp_peer *peer) { return TRUE; }
static BOOL Activate(freerdp_peer *peer) {
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
        Check(freerdp_settings_set_bool(s,FreeRDP_SupportGraphicsPipeline,FALSE));
        peer->PostConnect=PeerConnected; peer->Activate=Activate;
        peer->context->input->MouseEvent=Mouse; peer->context->input->KeyboardEvent=Key;
        peer->context->input->SynchronizeEvent=Sync;
        Check(peer->Initialize(peer));
        while (!self.stopped) {
            HANDLE handles[MAXIMUM_WAIT_OBJECTS];
            DWORD count=peer->GetEventHandles(peer,handles,MAXIMUM_WAIT_OBJECTS);
            if (!count || WaitForMultipleObjects(count,handles,FALSE,50)==WAIT_FAILED) break;
            if (!peer->CheckFileDescriptor(peer)) break;
        }
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
        ModelAndInputTests();
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
