#import <AppKit/AppKit.h>
#import "QDProfile.h"

typedef NS_ENUM(NSInteger, QDSessionState) { QDIdle, QDConnecting, QDConnected, QDStopping, QDFailed };

@interface QDFrame : NSObject
@property NSData *pixels;
@property NSUInteger width, height, stride;
@property uint64_t sequence;
- (CGImageRef)createImage CF_RETURNS_RETAINED;
@end

@interface QDSession : NSObject
@property (atomic, readonly) QDSessionState state;
@property (atomic, readonly) NSString *status;
@property (atomic, readonly) BOOL stopping;
@property (atomic, readonly) QDFrame *frame;
@property (atomic, readonly) NSCursor *remoteCursor;
// Called on the main queue. Completion: 0 reject, 1 trust and store, 2 this connection only.
@property (copy) void (^certificateRequest)(NSString *details, BOOL changed, void (^completion)(uint32_t));
@property (copy) void (^stateChanged)(void);
- (BOOL)connectProfile:(QDProfile *)profile password:(NSString *)password;
- (void)disconnect;
- (void)mouseFlags:(uint16_t)flags x:(uint16_t)x y:(uint16_t)y;
- (void)keyScanCode:(uint32_t)code down:(BOOL)down repeat:(BOOL)repeat;
- (void)synchronizeCapsLock:(BOOL)caps;
- (void)sendControlAltDelete;
@end
