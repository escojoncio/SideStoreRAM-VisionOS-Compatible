//
//  LMRMemoryCapability.m
//  SideStoreSupport (LiveMoreRAM)
//
//  Automatically enables the "Increased Memory Limit" capability
//  (INCREASED_MEMORY_LIMIT) on every App ID that SideStore provisions,
//  right before SideStore asks Apple for that App ID's provisioning profile.
//
//  This is the same Developer Services request GetMoreRam sends by hand
//  (PATCH services/v1/bundleIds/<appIdId> with a bundleIdCapabilities
//  relationship), done for every install/refresh with no manual step.
//
//  How it works:
//   - An NSURLProtocol watches SideStore's own requests to
//     developerservices2.apple.com.
//   - listAppIds / addAppId / updateAppId responses are read (never modified)
//     to remember each App ID's bundle identifier and name.
//   - When a downloadTeamProvisioningProfile / createProvisioningProfile /
//     regenProvisioningProfile request is about to go out, the capability is
//     enabled first, re-using the same authentication headers SideStore just
//     prepared for that request. Then the original request continues
//     unchanged, so the profile Apple returns already contains
//     com.apple.developer.kernel.increased-memory-limit.
//   - If enabling the capability fails for any reason, the original request
//     still goes through exactly as before: installs and refreshes never break
//     because of this file.
//

#import <Foundation/Foundation.h>
#include "../LiveContainer/utils.h"

#define LMRLog(fmt, ...) NSLog(@"[LiveMoreRAM] " fmt, ##__VA_ARGS__)

static NSString *const LMRHandledProperty = @"LMRHandled";
static NSString *const LMRServicesHost    = @"developerservices2.apple.com";
static NSString *const LMRCapabilityID    = @"INCREASED_MEMORY_LIMIT";

// appIdId -> @{ @"identifier": bundle id, @"name": App ID name }
static NSMutableDictionary<NSString *, NSDictionary *> *LMRAppIDInfo;
// "teamId|appIdId" already enabled during this process run
static NSMutableSet<NSString *> *LMREnabledAppIDs;
static NSLock *LMRLock;

#pragma mark - Helpers

static NSString *LMRAction(NSURL *url) {
    return url.lastPathComponent ?: @"";
}

static BOOL LMRIsAppIDListingAction(NSString *action) {
    return [action isEqualToString:@"listAppIds.action"] ||
           [action isEqualToString:@"addAppId.action"] ||
           [action isEqualToString:@"updateAppId.action"];
}

static BOOL LMRIsProfileAction(NSString *action) {
    return [action isEqualToString:@"downloadTeamProvisioningProfile.action"] ||
           [action isEqualToString:@"createProvisioningProfile.action"] ||
           [action isEqualToString:@"regenProvisioningProfile.action"];
}

static NSData *LMRBodyData(NSURLRequest *request) {
    if (request.HTTPBody) {
        return request.HTTPBody;
    }
    NSInputStream *stream = request.HTTPBodyStream;
    if (!stream) {
        return nil;
    }
    NSMutableData *data = [NSMutableData data];
    [stream open];
    uint8_t buffer[16384];
    while (true) {
        NSInteger read = [stream read:buffer maxLength:sizeof(buffer)];
        if (read <= 0) {
            break;
        }
        [data appendBytes:buffer length:(NSUInteger)read];
    }
    [stream close];
    return data;
}

static id LMRParsePropertyList(NSData *data) {
    if (data.length == 0) {
        return nil;
    }
    id object = [NSPropertyListSerialization propertyListWithData:data
                                                          options:NSPropertyListImmutable
                                                           format:NULL
                                                            error:NULL];
    if (!object) {
        object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    }
    return object;
}

static void LMRRememberAppID(NSDictionary *appID) {
    if (![appID isKindOfClass:NSDictionary.class]) {
        return;
    }
    NSString *appIdId   = appID[@"appIdId"];
    NSString *bundleID  = appID[@"identifier"];
    NSString *name      = appID[@"name"];
    if (![appIdId isKindOfClass:NSString.class] || appIdId.length == 0) {
        return;
    }
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    if ([bundleID isKindOfClass:NSString.class]) info[@"identifier"] = bundleID;
    if ([name isKindOfClass:NSString.class])     info[@"name"] = name;

    [LMRLock lock];
    LMRAppIDInfo[appIdId] = info;
    [LMRLock unlock];
}

static void LMRRecordAppIDsFromResponse(NSData *data) {
    NSDictionary *response = LMRParsePropertyList(data);
    if (![response isKindOfClass:NSDictionary.class]) {
        return;
    }
    NSArray *appIDs = response[@"appIds"];
    if ([appIDs isKindOfClass:NSArray.class]) {
        for (NSDictionary *appID in appIDs) {
            LMRRememberAppID(appID);
        }
    }
    LMRRememberAppID(response[@"appId"]);
}

static NSURLSession *LMRSession(void) {
    static NSURLSession *session;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
        // Never route our own traffic back through the interceptor.
        NSMutableArray *classes = [NSMutableArray array];
        for (Class protocolClass in configuration.protocolClasses) {
            if (protocolClass != NSClassFromString(@"LMRMemoryCapabilityProtocol")) {
                [classes addObject:protocolClass];
            }
        }
        configuration.protocolClasses = classes;
        configuration.timeoutIntervalForRequest = 30;
        session = [NSURLSession sessionWithConfiguration:configuration];
    });
    return session;
}

#pragma mark - Capability request

static void LMREnableIncreasedMemoryLimit(NSURLRequest *templateRequest,
                                          NSString *appIdId,
                                          NSString *teamId,
                                          void (^completion)(void)) {
    NSString *enabledKey = [NSString stringWithFormat:@"%@|%@", teamId, appIdId];

    [LMRLock lock];
    BOOL alreadyEnabled = [LMREnabledAppIDs containsObject:enabledKey];
    NSDictionary *info = LMRAppIDInfo[appIdId];
    [LMRLock unlock];

    if (alreadyEnabled) {
        completion();
        return;
    }

    NSMutableDictionary *attributes = [@{
        @"teamId": teamId,
        @"seedId": teamId,
        @"bundleType": @"bundle",
        @"hasExclusiveManagedCapabilities": @NO,
    } mutableCopy];
    if (info[@"identifier"]) attributes[@"identifier"] = info[@"identifier"];
    if (info[@"name"])       attributes[@"name"] = info[@"name"];

    NSDictionary *payload = @{
        @"data": @{
            @"type": @"bundleIds",
            @"id": appIdId,
            @"attributes": attributes,
            @"relationships": @{
                @"bundleIdCapabilities": @{
                    @"data": @[@{
                        @"type": @"bundleIdCapabilities",
                        @"attributes": @{ @"enabled": @YES, @"settings": @[] },
                        @"relationships": @{
                            @"capability": @{
                                @"data": @{ @"type": @"capabilities", @"id": LMRCapabilityID }
                            }
                        }
                    }]
                }
            }
        }
    };

    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    NSString *urlString = [NSString stringWithFormat:@"https://%@/services/v1/bundleIds/%@", LMRServicesHost, appIdId];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!body || !url) {
        completion();
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"PATCH";
    request.HTTPBody = body;
    request.timeoutInterval = 30;

    // Same authentication (GS token, DSID, anisette) SideStore attached to the
    // request it is about to send.
    [templateRequest.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        NSString *lower = key.lowercaseString;
        if ([lower isEqualToString:@"content-type"] ||
            [lower isEqualToString:@"accept"] ||
            [lower isEqualToString:@"content-length"]) {
            return;
        }
        [request setValue:value forHTTPHeaderField:key];
    }];
    [request setValue:@"application/vnd.api+json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json, text/plain, */*" forHTTPHeaderField:@"Accept"];
    [NSURLProtocol setProperty:@YES forKey:LMRHandledProperty inRequest:request];

    LMRLog(@"Enabling %@ on App ID %@ (%@)", LMRCapabilityID, appIdId, info[@"identifier"] ?: @"unknown bundle id");

    [[LMRSession() dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
        BOOL success = !error && status >= 200 && status < 300;

        if (success) {
            [LMRLock lock];
            [LMREnabledAppIDs addObject:enabledKey];
            [LMRLock unlock];
            LMRLog(@"Increased Memory Limit enabled on App ID %@", appIdId);
        } else {
            NSString *text = data.length ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
            if (text.length > 600) text = [text substringToIndex:600];
            LMRLog(@"Could not enable Increased Memory Limit on App ID %@ (HTTP %ld, error: %@) %@",
                   appIdId, (long)status, error.localizedDescription ?: @"none", text ?: @"");
        }
        completion();
    }] resume];
}

#pragma mark - URL protocol

@interface LMRMemoryCapabilityProtocol : NSURLProtocol
@property (nonatomic, strong) NSURLSessionDataTask *forwardTask;
@property (nonatomic, strong) NSThread *clientThread;
@property (nonatomic, copy) NSArray<NSString *> *clientModes;
@property (atomic, assign) BOOL stopped;
@end

@implementation LMRMemoryCapabilityProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:LMRHandledProperty inRequest:request]) {
        return NO;
    }
    NSURL *url = request.URL;
    if (![url.host.lowercaseString isEqualToString:LMRServicesHost]) {
        return NO;
    }
    NSString *action = LMRAction(url);
    return LMRIsAppIDListingAction(action) || LMRIsProfileAction(action);
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)lmr_runBlock:(dispatch_block_t)block {
    block();
}

- (void)lmr_onClientThread:(dispatch_block_t)block {
    if (!self.clientThread) {
        block();
        return;
    }
    [self performSelector:@selector(lmr_runBlock:)
                 onThread:self.clientThread
               withObject:[block copy]
            waitUntilDone:NO
                    modes:self.clientModes];
}

- (void)startLoading {
    self.clientThread = NSThread.currentThread;
    NSMutableArray *modes = [NSMutableArray arrayWithObject:NSDefaultRunLoopMode];
    NSString *currentMode = NSRunLoop.currentRunLoop.currentMode;
    if (currentMode && ![currentMode isEqualToString:NSDefaultRunLoopMode]) {
        [modes addObject:currentMode];
    }
    self.clientModes = modes;

    NSData *body = LMRBodyData(self.request);
    NSMutableURLRequest *forwardRequest = [self.request mutableCopy];
    if (body) {
        forwardRequest.HTTPBody = body;
    }
    [NSURLProtocol setProperty:@YES forKey:LMRHandledProperty inRequest:forwardRequest];

    NSString *action = LMRAction(self.request.URL);

    __weak typeof(self) weakSelf = self;
    void (^forward)(void) = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self.stopped) return;
        self.forwardTask = [LMRSession() dataTaskWithRequest:forwardRequest
                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (!error && data && LMRIsAppIDListingAction(action)) {
                LMRRecordAppIDsFromResponse(data);
            }
            [self lmr_onClientThread:^{
                if (self.stopped) return;
                if (error) {
                    [self.client URLProtocol:self didFailWithError:error];
                    return;
                }
                if (response) {
                    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
                }
                if (data.length) {
                    [self.client URLProtocol:self didLoadData:data];
                }
                [self.client URLProtocolDidFinishLoading:self];
            }];
        }];
        [self.forwardTask resume];
    };

    if (LMRIsProfileAction(action)) {
        NSDictionary *parameters = LMRParsePropertyList(body);
        NSString *appIdId = [parameters isKindOfClass:NSDictionary.class] ? parameters[@"appIdId"] : nil;
        NSString *teamId  = [parameters isKindOfClass:NSDictionary.class] ? parameters[@"teamId"] : nil;
        if ([appIdId isKindOfClass:NSString.class] && appIdId.length &&
            [teamId isKindOfClass:NSString.class] && teamId.length) {
            LMREnableIncreasedMemoryLimit(self.request, appIdId, teamId, forward);
            return;
        }
    }

    forward();
}

- (void)stopLoading {
    self.stopped = YES;
    [self.forwardTask cancel];
}

@end

#pragma mark - Installation

@implementation NSURLSessionConfiguration (LiveMoreRAM)

static NSArray *LMRProtocolClassesWithInterceptor(NSArray *classes) {
    NSMutableArray *result = [NSMutableArray arrayWithObject:LMRMemoryCapabilityProtocol.class];
    for (Class protocolClass in classes) {
        if (protocolClass != LMRMemoryCapabilityProtocol.class) {
            [result addObject:protocolClass];
        }
    }
    return result;
}

+ (NSURLSessionConfiguration *)lmr_defaultSessionConfiguration {
    NSURLSessionConfiguration *configuration = [self lmr_defaultSessionConfiguration];
    configuration.protocolClasses = LMRProtocolClassesWithInterceptor(configuration.protocolClasses);
    return configuration;
}

+ (NSURLSessionConfiguration *)lmr_ephemeralSessionConfiguration {
    NSURLSessionConfiguration *configuration = [self lmr_ephemeralSessionConfiguration];
    configuration.protocolClasses = LMRProtocolClassesWithInterceptor(configuration.protocolClasses);
    return configuration;
}

@end

@interface LMRMemoryCapabilityInstaller : NSObject
@end

@implementation LMRMemoryCapabilityInstaller

+ (void)load {
    if (!NSUserDefaults.isSideStore) {
        return;
    }

    LMRAppIDInfo     = [NSMutableDictionary dictionary];
    LMREnabledAppIDs = [NSMutableSet set];
    LMRLock          = [NSLock new];

    // Our own session is created before the swizzle so it never contains the interceptor.
    (void)LMRSession();

    // URLSession.shared
    [NSURLProtocol registerClass:LMRMemoryCapabilityProtocol.class];
    // Any URLSession SideStore builds from a default/ephemeral configuration.
    swizzleClassMethod(NSURLSessionConfiguration.class,
                       @selector(defaultSessionConfiguration),
                       @selector(lmr_defaultSessionConfiguration));
    swizzleClassMethod(NSURLSessionConfiguration.class,
                       @selector(ephemeralSessionConfiguration),
                       @selector(lmr_ephemeralSessionConfiguration));

    LMRLog(@"Automatic Increased Memory Limit is active");
}

@end
