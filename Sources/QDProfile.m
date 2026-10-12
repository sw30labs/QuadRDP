#import "QDProfile.h"
#import <Security/Security.h>

static NSError *QDError(NSString *message) {
    return [NSError errorWithDomain:@"QuadRDP" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSURL *QDDataDirectory(void) {
    NSString *override = NSProcessInfo.processInfo.environment[@"QUADRDP_DATA_DIR"];
    if (override.length) return [NSURL fileURLWithPath:override isDirectory:YES];
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                        inDomains:NSUserDomainMask].firstObject;
    return [support URLByAppendingPathComponent:@"QuadRDP" isDirectory:YES];
}

@implementation QDProfile
+ (instancetype)emptyProfile:(NSInteger)index {
    QDProfile *p = [QDProfile new];
    p.identifier = NSUUID.UUID.UUIDString;
    p.name = [NSString stringWithFormat:@"Computer %ld", (long)index + 1];
    p.host = @""; p.username = @""; p.domain = @"";
    p.port = 3389; p.width = 1600; p.height = 900; p.useNLA = YES;
    return p;
}
- (NSDictionary *)dictionary {
    return @{@"id": self.identifier, @"name": self.name, @"host": self.host,
             @"username": self.username, @"domain": self.domain, @"port": @(self.port),
             @"width": @(self.width), @"height": @(self.height), @"nla": @(self.useNLA)};
}
- (id)copyWithZone:(NSZone *)zone {
    QDProfile *p = [QDProfile new];
    p.identifier = self.identifier; p.name = self.name; p.host = self.host;
    p.username = self.username; p.domain = self.domain; p.port = self.port;
    p.width = self.width; p.height = self.height; p.useNLA = self.useNLA;
    return p;
}
- (NSString *)validationError {
    if (!self.host.length) return @"Enter a hostname or IP address.";
    if ([self.host rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound ||
        [self.host containsString:@"/"] || [self.host containsString:@"\\"])
        return @"Use a hostname or IP address without a URL prefix, path, or spaces. Enter the port separately.";
    if (self.port < 1 || self.port > 65535) return @"The port must be between 1 and 65535.";
    if (self.width < 640 || self.width > 3840 || self.height < 480 || self.height > 2160)
        return @"Choose a desktop resolution between 640×480 and 3840×2160.";
    if (!self.username.length) return @"Enter a Windows username. For a Microsoft account, use MicrosoftAccount\\email@example.com.";
    return nil;
}
- (NSDictionary *)keychainQuery {
    // JSON keeps identity components unambiguous, including domain-qualified usernames.
    NSData *identity = [NSJSONSerialization dataWithJSONObject:@[self.identifier, self.host.lowercaseString,
                        @(self.port), self.domain, self.username] options:0 error:nil];
    NSString *account = [[NSString alloc] initWithData:identity encoding:NSUTF8StringEncoding];
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: @"local.quadrdp.password",
             (__bridge id)kSecAttrAccount: account};
}
- (NSString *)password:(NSError **)error {
    NSMutableDictionary *query = [[self keychainQuery] mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef value = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &value);
    if (status == errSecItemNotFound) return nil;
    if (status != errSecSuccess) {
        if (error) *error = QDError(CFBridgingRelease(SecCopyErrorMessageString(status, NULL)) ?: @"Could not read Keychain.");
        return nil;
    }
    return [[NSString alloc] initWithData:CFBridgingRelease(value) encoding:NSUTF8StringEncoding];
}
- (BOOL)savePassword:(NSString *)password error:(NSError **)error {
    NSDictionary *query = [self keychainQuery];
    OSStatus status;
    if (!password.length) {
        status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecItemNotFound) status = errSecSuccess;
    } else {
        NSDictionary *values = @{(__bridge id)kSecValueData: [password dataUsingEncoding:NSUTF8StringEncoding]};
        status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)values);
        if (status == errSecItemNotFound) {
            NSMutableDictionary *item = [query mutableCopy];
            [item addEntriesFromDictionary:values];
            item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
            status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        }
    }
    if (status == errSecSuccess) return YES;
    if (error) *error = QDError(CFBridgingRelease(SecCopyErrorMessageString(status, NULL)) ?: @"Could not update Keychain.");
    return NO;
}
@end

NSArray<QDProfile *> *QDLoadProfiles(NSError **error) {
    NSMutableArray *profiles = [NSMutableArray array];
    for (NSInteger i = 0; i < 4; i++) [profiles addObject:[QDProfile emptyProfile:i]];
    NSURL *file = [QDDataDirectory() URLByAppendingPathComponent:@"profiles.json"];
    if (![NSFileManager.defaultManager fileExistsAtPath:file.path]) return profiles;
    NSData *data = [NSData dataWithContentsOfURL:file options:0 error:error];
    if (!data) return profiles;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:NSArray.class] || [json count] != 4) {
        if (error && !*error) *error = QDError(@"profiles.json must contain exactly four profiles. The file has not been changed.");
        return profiles;
    }
    NSMutableSet *ids = [NSMutableSet set];
    for (NSUInteger i = 0; i < 4; i++) {
        id d = json[i];
        if (![d isKindOfClass:NSDictionary.class]) goto invalid;
        for (NSString *key in @[@"id", @"name", @"host", @"username", @"domain"])
            if (![d[key] isKindOfClass:NSString.class]) goto invalid;
        for (NSString *key in @[@"port", @"width", @"height", @"nla"])
            if (![d[key] isKindOfClass:NSNumber.class]) goto invalid;
        if (![d[@"id"] length] || [ids containsObject:d[@"id"]]) goto invalid;
        [ids addObject:d[@"id"]];
        QDProfile *p = profiles[i];
        p.identifier = d[@"id"]; p.name = d[@"name"]; p.host = d[@"host"];
        p.username = d[@"username"]; p.domain = d[@"domain"]; p.port = [d[@"port"] integerValue];
        p.width = [d[@"width"] integerValue]; p.height = [d[@"height"] integerValue];
        p.useNLA = [d[@"nla"] boolValue];
        if (p.host.length && p.validationError) goto invalid;
    }
    return profiles;
invalid:
    if (error) *error = QDError(@"A saved connection profile is invalid. Fix profiles.json before saving changes.");
    [profiles removeAllObjects];
    for (NSInteger i = 0; i < 4; i++) [profiles addObject:[QDProfile emptyProfile:i]];
    return profiles;
}

BOOL QDSaveProfiles(NSArray<QDProfile *> *profiles, NSError **error) {
    if (profiles.count != 4) { if (error) *error = QDError(@"Exactly four profiles are required."); return NO; }
    if (![NSFileManager.defaultManager createDirectoryAtURL:QDDataDirectory() withIntermediateDirectories:YES
                                                attributes:@{NSFilePosixPermissions: @0700} error:error]) return NO;
    NSMutableArray *json = [NSMutableArray array];
    for (QDProfile *p in profiles) [json addObject:p.dictionary];
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    NSURL *file = [QDDataDirectory() URLByAppendingPathComponent:@"profiles.json"];
    if (!data || ![data writeToURL:file options:NSDataWritingAtomic error:error]) return NO;
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:file.path error:error];
}
