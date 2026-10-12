#import "QDSession.h"
// WinPR and CoreFoundation both define a different COM REFIID type.
#define REFIID WINPR_REFIID
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wmacro-redefined"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include <freerdp/freerdp.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/graphics.h>
#include <freerdp/input.h>
#include <freerdp/settings.h>
#include <freerdp/update.h>
#include <winpr/synch.h>
#pragma clang diagnostic pop
#undef REFIID

@implementation QDFrame
- (CGImageRef)createImage {
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)self.pixels);
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGImageRef result = CGImageCreate(self.width, self.height, 8, 32, self.stride, color,
        kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, provider, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(color); CGDataProviderRelease(provider);
    return result;
}
@end

typedef struct { rdpContext base; void *owner; } QDContext;
typedef struct { uint8_t type; uint16_t flags, x, y; uint32_t code; BOOL down, repeat; } QDInput;

@interface QDSession () {
    NSLock *_lifecycle;
    NSLock *_inputLock;
    NSMutableData *_inputs;
    freerdp *_instance; // Protected by _lifecycle; all protocol work belongs to the worker.
    HANDLE _wake;
    uint64_t _sequence;
}
@property (atomic, readwrite) QDSessionState state;
@property (atomic, readwrite) NSString *status;
@property (atomic, readwrite) BOOL stopping;
@property (atomic, readwrite) QDFrame *frame;
@property (atomic, readwrite) NSCursor *remoteCursor;
- (void)runProfile:(QDProfile *)profile password:(NSString *)password;
- (BOOL)prepareTransport:(void *)context;
- (void)capture:(rdpContext *)context;
- (uint32_t)verify:(NSString *)details changed:(BOOL)changed;
@end

static QDSession *Owner(rdpContext *context) { return (__bridge QDSession *)((QDContext *)context)->owner; }
static BOOL BeginPaint(rdpContext *context) {
    context->gdi->primary->hdc->hwnd->invalid->null = TRUE;
    context->gdi->primary->hdc->hwnd->ninvalid = 0;
    return TRUE;
}
static BOOL EndPaint(rdpContext *context) {
    if (!context->gdi->primary->hdc->hwnd->invalid->null) [Owner(context) capture:context];
    return TRUE;
}
static BOOL DesktopResize(rdpContext *context) {
    UINT32 w = freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopWidth);
    UINT32 h = freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopHeight);
    if (w > 8192 || h > 8192 || !w || !h) return FALSE;
    return gdi_resize(context->gdi, w, h);
}
static BOOL PointerNew(rdpContext *context, rdpPointer *pointer) { return TRUE; }
static void PointerFree(rdpContext *context, rdpPointer *pointer) {}
static BOOL PointerSet(rdpContext *context, rdpPointer *p) {
    if (!p->width || !p->height || p->width > 384 || p->height > 384) return TRUE;
    NSMutableData *data = [NSMutableData dataWithLength:p->width * p->height * 4];
    if (!freerdp_image_copy_from_pointer_data(data.mutableBytes, PIXEL_FORMAT_BGRA32, p->width * 4, 0, 0,
        p->width, p->height, p->xorMaskData, p->lengthXorMask, p->andMaskData, p->lengthAndMask, p->xorBpp, NULL)) return FALSE;
    NSData *pixels = [data copy]; NSUInteger w = p->width, h = p->height, x = p->xPos, y = p->yPos;
    QDSession *session = Owner(context);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (session.stopping || session.state != QDConnected) return;
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
        CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
        CGImageRef image = CGImageCreate(w, h, 8, 32, w * 4, color,
            kCGBitmapByteOrder32Little | kCGImageAlphaFirst, provider, NULL, false, kCGRenderingIntentDefault);
        if (image) {
            NSImage *native = [[NSImage alloc] initWithCGImage:image size:NSMakeSize(w, h)];
            session.remoteCursor = [[NSCursor alloc] initWithImage:native hotSpot:NSMakePoint(x, y)];
            CGImageRelease(image);
        }
        CGColorSpaceRelease(color); CGDataProviderRelease(provider);
    });
    return TRUE;
}
static BOOL PointerDefault(rdpContext *context) {
    QDSession *session = Owner(context);
    dispatch_async(dispatch_get_main_queue(), ^{ session.remoteCursor = NSCursor.arrowCursor; });
    return TRUE;
}
static BOOL PointerNull(rdpContext *context) {
    QDSession *session = Owner(context);
    dispatch_async(dispatch_get_main_queue(), ^{
        session.remoteCursor = [[NSCursor alloc] initWithImage:[[NSImage alloc] initWithSize:NSMakeSize(1, 1)] hotSpot:NSZeroPoint];
    });
    return TRUE;
}
static BOOL PostConnect(freerdp *instance) {
    if (!gdi_init(instance, PIXEL_FORMAT_BGRA32)) return FALSE;
    rdpContext *c = instance->context;
    c->update->BeginPaint = BeginPaint;
    c->update->EndPaint = EndPaint;
    c->update->DesktopResize = DesktopResize;
    rdpPointer pointer = {0};
    pointer.size = sizeof(rdpPointer); pointer.New = PointerNew; pointer.Free = PointerFree;
    pointer.Set = PointerSet; pointer.SetDefault = PointerDefault; pointer.SetNull = PointerNull;
    graphics_register_pointer(c->graphics, &pointer);
    return TRUE;
}
static void PostDisconnect(freerdp *instance) {
    if (instance->context->gdi) gdi_free(instance);
}
static BOOL Authenticate(freerdp *instance, char **username, char **password, char **domain, rdp_auth_reason reason) {
    // Credentials were supplied before connect. Re-prompting is an explicit profile edit/retry.
    return FALSE;
}
static NSString *SafeString(const char *value) { return value ? @(value) : @"(not supplied)"; }
static DWORD Verify(freerdp *instance, const char *host, UINT16 port, const char *cn,
                    const char *subject, const char *issuer, const char *fingerprint, DWORD flags) {
    NSString *details = [NSString stringWithFormat:@"Host: %@:%u\nName: %@\nSubject: %@\nIssuer: %@\nFingerprint: %@%@",
        SafeString(host), port, SafeString(cn), SafeString(subject), SafeString(issuer), SafeString(fingerprint),
        flags & VERIFY_CERT_FLAG_MISMATCH ? @"\n\nThe certificate name does not match the host." : @""];
    return [Owner(instance->context) verify:details changed:NO];
}
static DWORD VerifyChanged(freerdp *instance, const char *host, UINT16 port, const char *cn,
    const char *subject, const char *issuer, const char *fingerprint, const char *oldSubject,
    const char *oldIssuer, const char *oldFingerprint, DWORD flags) {
    NSString *details = [NSString stringWithFormat:@"The saved certificate for %@:%u has changed. Verify the new fingerprint with the computer owner.\n\nPrevious: %@\nNew: %@\nSubject: %@\nIssuer: %@",
        SafeString(host), port, SafeString(oldFingerprint), SafeString(fingerprint), SafeString(subject), SafeString(issuer)];
    return [Owner(instance->context) verify:details changed:YES];
}

@implementation QDSession
- (instancetype)init {
    if ((self = [super init])) {
        _lifecycle = [NSLock new]; _inputLock = [NSLock new]; _inputs = [NSMutableData data];
        _wake = CreateEvent(NULL, TRUE, FALSE, NULL);
        _state = QDIdle; _status = @"Ready to connect"; _remoteCursor = NSCursor.arrowCursor;
    }
    return self;
}
- (void)dealloc { if (_wake) CloseHandle(_wake); }
- (void)notifyState:(QDSessionState)state message:(NSString *)message {
    self.status = message; self.state = state;
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.stateChanged) self.stateChanged(); });
}
- (BOOL)connectProfile:(QDProfile *)profile password:(NSString *)password {
    NSAssert(NSThread.isMainThread, @"Connect on main thread");
    if (self.state == QDConnecting || self.state == QDConnected || self.state == QDStopping) return NO;
    NSString *validation = profile.validationError;
    if (validation) { [self notifyState:QDFailed message:validation]; return NO; }
    if (!_wake) { [self notifyState:QDFailed message:@"Could not create connection event."]; return NO; }
    self.stopping = NO; self.frame = nil; self.remoteCursor = NSCursor.arrowCursor;
    [_inputLock lock]; [_inputs setLength:0]; ResetEvent(_wake); [_inputLock unlock];
    [self notifyState:QDConnecting message:@"Connecting…"];
    QDProfile *snapshot = [profile copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool { [self runProfile:snapshot password:password ?: @""]; }
    });
    return YES;
}
- (void)disconnect {
    if (self.state != QDConnecting && self.state != QDConnected) return;
    self.stopping = YES;
    [self notifyState:QDStopping message:@"Disconnecting…"];
    [_lifecycle lock];
    if (_instance) freerdp_abort_connect_context(_instance->context);
    [_lifecycle unlock];
    SetEvent(_wake);
}
- (uint32_t)verify:(NSString *)details changed:(BOOL)changed {
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    __block uint32_t decision = 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.stopping && self.certificateRequest) {
            self.certificateRequest(details, changed, ^(uint32_t result) {
                decision = result; dispatch_semaphore_signal(done);
            });
        } else dispatch_semaphore_signal(done);
    });
    while (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC))) {
        if (self.stopping) return 0;
    }
    return self.stopping ? 0 : decision;
}
- (void)capture:(rdpContext *)context {
    rdpGdi *gdi = context->gdi;
    if (!gdi || gdi->width <= 0 || gdi->height <= 0) return;
    QDFrame *frame = [QDFrame new];
    frame.width = gdi->width; frame.height = gdi->height; frame.stride = gdi->stride;
    frame.sequence = ++_sequence;
    frame.pixels = [NSData dataWithBytes:gdi->primary_buffer length:(NSUInteger)gdi->stride * gdi->height];
    self.frame = frame; // One retained latest frame: the UI never accumulates a render backlog.
}
- (void)enqueue:(QDInput)input {
    if (self.state != QDConnected || self.stopping) return;
    [_inputLock lock];
    if (input.type == 0 && input.flags == PTR_FLAGS_MOVE && _inputs.length >= sizeof(QDInput)) {
        QDInput *last = (QDInput *)((uint8_t *)_inputs.mutableBytes + _inputs.length - sizeof(QDInput));
        if (last->type == 0 && last->flags == PTR_FLAGS_MOVE) { *last = input; [_inputLock unlock]; SetEvent(_wake); return; }
    }
    [_inputs appendBytes:&input length:sizeof(input)];
    [_inputLock unlock]; SetEvent(_wake);
}
- (void)mouseFlags:(uint16_t)flags x:(uint16_t)x y:(uint16_t)y {
    [self enqueue:(QDInput){.type=0, .flags=flags, .x=x, .y=y}];
}
- (void)keyScanCode:(uint32_t)code down:(BOOL)down repeat:(BOOL)repeat {
    [self enqueue:(QDInput){.type=1, .code=code, .down=down, .repeat=repeat}];
}
- (void)synchronizeCapsLock:(BOOL)caps { [self enqueue:(QDInput){.type=2, .code=caps ? KBD_SYNC_CAPS_LOCK : 0}]; }
- (void)sendControlAltDelete {
    for (NSNumber *code in @[@0x1d, @0x38, @0x153]) [self keyScanCode:code.unsignedIntValue down:YES repeat:NO];
    for (NSNumber *code in @[@0x153, @0x38, @0x1d]) [self keyScanCode:code.unsignedIntValue down:NO repeat:NO];
}
- (BOOL)drainInputs:(rdpInput *)rdpInput {
    [_inputLock lock]; ResetEvent(_wake); NSData *batch = [_inputs copy]; [_inputs setLength:0]; [_inputLock unlock];
    const QDInput *events = batch.bytes;
    for (NSUInteger i = 0; i < batch.length / sizeof(QDInput); i++) {
        QDInput e = events[i]; BOOL ok;
        if (e.type == 0) ok = freerdp_input_send_mouse_event(rdpInput, e.flags, e.x, e.y);
        else if (e.type == 1) ok = freerdp_input_send_keyboard_event_ex(rdpInput, e.down, e.repeat, e.code);
        else ok = freerdp_input_send_synchronize_event(rdpInput, e.code);
        if (!ok) return NO;
    }
    return YES;
}
- (void)runProfile:(QDProfile *)profile password:(NSString *)password {
    freerdp *instance = freerdp_new();
    NSString *failure = nil;
    BOOL connected = NO;
    if (!instance) { [self notifyState:QDFailed message:@"Could not allocate FreeRDP."]; return; }
    instance->ContextSize = sizeof(QDContext);
    instance->PostConnect = PostConnect; instance->PostDisconnect = PostDisconnect;
    instance->VerifyCertificateEx = Verify; instance->VerifyChangedCertificateEx = VerifyChanged;
    instance->AuthenticateEx = Authenticate;
    if (!freerdp_context_new(instance)) { freerdp_free(instance); [self notifyState:QDFailed message:@"Could not initialize FreeRDP."]; return; }
    ((QDContext *)instance->context)->owner = (__bridge void *)self;
    rdpSettings *s = instance->context->settings;
    NSURL *certs = [QDDataDirectory() URLByAppendingPathComponent:@"freerdp" isDirectory:YES];
    NSError *fileError = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:certs withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:&fileError]) {
        failure = fileError.localizedDescription;
    }
    NSString *user = profile.username, *domain = profile.domain;
    NSRange slash = [user rangeOfString:@"\\"];
    if (slash.location != NSNotFound && !domain.length) {
        domain = [user substringToIndex:slash.location]; user = [user substringFromIndex:slash.location + 1];
    }
    BOOL settingsOK =
        freerdp_settings_set_string(s, FreeRDP_ServerHostname, profile.host.UTF8String) &&
        freerdp_settings_set_uint32(s, FreeRDP_ServerPort, (UINT32)profile.port) &&
        freerdp_settings_set_string(s, FreeRDP_Username, user.UTF8String) &&
        freerdp_settings_set_string(s, FreeRDP_Domain, domain.UTF8String) &&
        freerdp_settings_set_string(s, FreeRDP_Password, password.UTF8String) &&
        freerdp_settings_set_string(s, FreeRDP_ConfigPath, certs.path.UTF8String) &&
        freerdp_settings_set_uint32(s, FreeRDP_DesktopWidth, (UINT32)profile.width) &&
        freerdp_settings_set_uint32(s, FreeRDP_DesktopHeight, (UINT32)profile.height) &&
        freerdp_settings_set_uint32(s, FreeRDP_ColorDepth, 32) &&
        freerdp_settings_set_uint32(s, FreeRDP_KeyboardLayout, 0x0409) &&
        freerdp_settings_set_uint32(s, FreeRDP_TcpConnectTimeout, 10000) &&
        freerdp_settings_set_bool(s, FreeRDP_NlaSecurity, profile.useNLA) &&
        freerdp_settings_set_bool(s, FreeRDP_TlsSecurity, !profile.useNLA) &&
        freerdp_settings_set_bool(s, FreeRDP_RdpSecurity, FALSE) &&
        freerdp_settings_set_bool(s, FreeRDP_SoftwareGdi, TRUE) &&
        freerdp_settings_set_bool(s, FreeRDP_SupportGraphicsPipeline, FALSE) &&
        freerdp_settings_set_bool(s, FreeRDP_RemoteFxCodec, FALSE) &&
        freerdp_settings_set_bool(s, FreeRDP_NSCodec, TRUE) &&
        freerdp_settings_set_bool(s, FreeRDP_AudioPlayback, FALSE) &&
        freerdp_settings_set_bool(s, FreeRDP_NetworkAutoDetect, FALSE) &&
        freerdp_settings_set_bool(s, FreeRDP_IgnoreCertificate, FALSE) &&
        freerdp_settings_set_bool(s, FreeRDP_AutoAcceptCertificate, FALSE) &&
        freerdp_settings_set_bool(s, FreeRDP_CertificateCallbackPreferPEM, FALSE);
    if (!settingsOK) failure = @"FreeRDP rejected the connection settings.";
    if (!failure && ![self prepareTransport:instance->context]) failure = @"Could not initialize the connection transport.";
    [_lifecycle lock]; _instance = instance; [_lifecycle unlock];
    if (!failure && !self.stopping) {
        connected = freerdp_connect(instance);
        if (connected && !self.stopping) {
            [self notifyState:QDConnected message:@"Connected"];
            while (!self.stopping && !freerdp_shall_disconnect_context(instance->context)) {
                @autoreleasepool {
                    HANDLE handles[MAXIMUM_WAIT_OBJECTS];
                    DWORD count = freerdp_get_event_handles(instance->context, handles, MAXIMUM_WAIT_OBJECTS - 1);
                    if (!count) { failure = @"The connection stopped responding."; break; }
                    handles[count++] = _wake;
                    if (WaitForMultipleObjects(count, handles, FALSE, 100) == WAIT_FAILED) { failure = @"Connection event wait failed."; break; }
                    if (self.stopping) break;
                    if (![self drainInputs:instance->context->input] || !freerdp_check_event_handles(instance->context)) break;
                }
            }
        }
        UINT32 code = freerdp_get_last_error(instance->context);
        if (!self.stopping && (!connected || code)) {
            const char *description = freerdp_get_last_error_string(code);
            failure = [NSString stringWithFormat:@"%@ (0x%08X)", description ? @(description) : @"Connection failed", code];
        }
    }
    freerdp_disconnect(instance);
    [_lifecycle lock]; _instance = NULL; [_lifecycle unlock];
    freerdp_context_free(instance); freerdp_free(instance);
    [_inputLock lock]; [_inputs setLength:0]; [_inputLock unlock];
    self.frame = nil;
    [self notifyState:self.stopping || !failure ? QDIdle : QDFailed
              message:self.stopping ? @"Disconnected" : (failure ?: @"Session ended")];
}
// Overridden by the test harness to exercise real TLS/RDP over an in-process socket pair.
// The shipped application always uses FreeRDP's normal TCP transport.
- (BOOL)prepareTransport:(void *)context { return YES; }
@end
