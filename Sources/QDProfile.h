#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface QDProfile : NSObject <NSCopying>
@property NSString *identifier;
@property NSString *name;
@property NSString *host;
@property NSString *username;
@property NSString *domain;
@property NSInteger port;
@property NSInteger width;
@property NSInteger height;
@property BOOL useNLA;
+ (instancetype)emptyProfile:(NSInteger)index;
- (NSDictionary *)dictionary;
- (nullable NSString *)validationError;
- (nullable NSString *)password:(NSError **)error;
- (BOOL)savePassword:(NSString *)password error:(NSError **)error;
@end

NSURL *QDDataDirectory(void);
NSArray<QDProfile *> *QDLoadProfiles(NSError **error);
BOOL QDSaveProfiles(NSArray<QDProfile *> *profiles, NSError **error);
NS_ASSUME_NONNULL_END
