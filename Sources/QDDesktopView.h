#import <AppKit/AppKit.h>
#import "QDSession.h"

uint32_t QDScanCode(unsigned short macKey);
NSRect QDAspectFit(NSSize image, NSRect bounds);
NSPoint QDRemotePoint(NSPoint point, NSRect imageRect, NSSize remoteSize);

@interface QDDesktopView : NSView
@property QDSession *session;
@property NSString *placeholderTitle;
@property NSString *placeholderDetail;
@property NSInteger slot;
@property (copy) void (^focused)(void);
- (void)refresh;
- (void)releaseInputs;
@end
