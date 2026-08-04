#import "Reply/BHTDetailedReplyDiagnostics.h"

#import "Core/BHTSettings.h"

#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const NSTimeInterval BHTDetailedReplyArmLifetime = 10.0 * 60.0;
static const NSTimeInterval BHTDetailedReplyCaptureLifetime = 90.0;
static const NSUInteger BHTDetailedReplyResponseLimit = 256 * 1024;
static const NSUInteger BHTDetailedReplyMaximumDepth = 8;
static const NSUInteger BHTDetailedReplyMaximumDictionaryKeys = 32;
static const NSUInteger BHTDetailedReplyMaximumArrayElements = 16;
static const NSUInteger BHTDetailedReplyMaximumStringLength = 2048;

static BOOL BHTDetailedReplyArmed;
static NSTimeInterval BHTDetailedReplyArmedAt;
static NSTimeInterval BHTDetailedReplyCaptureStartedAt;
static NSUInteger BHTDetailedReplySessionGeneration;
static NSString* BHTDetailedReplyCaptureState = @"idle";
static NSDictionary* BHTDetailedReplyCapture;
static NSUInteger BHTDetailedReplyRedactionCount;
static NSUInteger BHTDetailedReplyTruncationCount;
static BOOL BHTDetailedReplyResponseAccessorsObserved;

static NSObject* BHTDetailedReplyLock(void) {
    static NSObject* lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static NSTimeInterval BHTDetailedReplyNow(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

static void BHTDetailedReplySetPreference(BOOL enabled) {
    [NSUserDefaults.standardUserDefaults
        setBool:enabled
         forKey:@"detailed_reply_diagnostics"];
}

static void BHTDetailedReplyPruneLocked(void) {
    NSTimeInterval now = BHTDetailedReplyNow();
    if (BHTDetailedReplyArmed &&
        now - BHTDetailedReplyArmedAt > BHTDetailedReplyArmLifetime) {
        BHTDetailedReplyArmed = NO;
        BHTDetailedReplyCaptureState = @"armExpired";
        BHTDetailedReplySetPreference(NO);
    }
    if (BHTDetailedReplySessionGeneration != 0 &&
        now - BHTDetailedReplyCaptureStartedAt >
            BHTDetailedReplyCaptureLifetime) {
        BHTDetailedReplySessionGeneration = 0;
        if (BHTDetailedReplyCapture) {
            BHTDetailedReplyCaptureState = @"captureExpiredWithData";
        } else {
            BHTDetailedReplyCaptureState = @"captureExpired";
        }
    }
}

static BOOL BHTDetailedReplyMethodReturnsObjectWithNoArguments(
    Class cls,
    SEL selector) {
    if (!cls || !selector) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* type = returnType;
    while (type &&
           (*type == 'r' || *type == 'n' || *type == 'N' ||
            *type == 'o' || *type == 'O' || *type == 'R' ||
            *type == 'V')) {
        type++;
    }
    return type && type[0] == '@' && type[1] == '\0';
}

static NSString* BHTDetailedReplyNormalizedKey(NSString* key) {
    if (![key isKindOfClass:NSString.class]) return @"";
    NSMutableString* normalized = [NSMutableString string];
    NSString* lowercase = key.lowercaseString;
    NSCharacterSet* allowed = NSCharacterSet.alphanumericCharacterSet;
    for (NSUInteger index = 0; index < lowercase.length; index++) {
        unichar character = [lowercase characterAtIndex:index];
        if ([allowed characterIsMember:character]) {
            [normalized appendFormat:@"%C", character];
        }
    }
    return normalized;
}

static BOOL BHTDetailedReplyShouldRedactKey(NSString* key) {
    NSString* normalized = BHTDetailedReplyNormalizedKey(key);
    if (normalized.length == 0) return NO;
    NSArray<NSString*>* denied = @[
        @"authorization", @"cookie", @"setcookie", @"password",
        @"passwd", @"secret", @"clientsecret", @"accesstoken",
        @"refreshtoken", @"oauthtoken", @"bearertoken",
        @"guesttoken", @"knowndevicetoken", @"xcsrftoken",
        @"csrftoken", @"authtoken", @"token", @"header",
        @"attestation", @"ct0"
    ];
    for (NSString* fragment in denied) {
        if ([normalized containsString:fragment]) return YES;
    }
    return NO;
}

static NSString* BHTDetailedReplyScrubString(
    NSString* value,
    NSUInteger* redactions,
    NSUInteger* truncations) {
    if (![value isKindOfClass:NSString.class]) return @"";
    NSMutableString* result = [value mutableCopy];
    static NSArray<NSRegularExpression*>* patterns;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray* compiled = [NSMutableArray array];
        NSArray* sources = @[
            @"(?i)\\bBearer\\s+[^\\s,;]+",
            @"(?i)\\b(auth[_-]?token|access[_-]?token|refresh[_-]?token|oauth[_-]?token|guest[_-]?token|token|ct0|password|passwd|client[_-]?secret)\\s*[:=]\\s*[^\\s,;&]+",
            @"(?i)\\b(authorization|cookie|set-cookie)\\s*[:=]\\s*[^\\r\\n]+"
        ];
        for (NSString* source in sources) {
            NSRegularExpression* expression =
                [NSRegularExpression regularExpressionWithPattern:source
                                                          options:0
                                                            error:nil];
            if (expression) [compiled addObject:expression];
        }
        patterns = [compiled copy];
    });
    for (NSRegularExpression* expression in patterns) {
        NSUInteger matches = [expression
            numberOfMatchesInString:result
                            options:0
                              range:NSMakeRange(0, result.length)];
        if (matches > 0) {
            [expression replaceMatchesInString:result
                                       options:0
                                         range:NSMakeRange(0, result.length)
                                  withTemplate:@"<redacted credential>"];
            if (redactions) *redactions += matches;
        }
    }
    if (result.length > BHTDetailedReplyMaximumStringLength) {
        [result deleteCharactersInRange:NSMakeRange(
            BHTDetailedReplyMaximumStringLength,
            result.length - BHTDetailedReplyMaximumStringLength)];
        [result appendString:@"...<truncated>"];
        if (truncations) (*truncations)++;
    }
    return [result copy];
}

static BOOL BHTDetailedReplyDescriptionDeniedForClassName(
    NSString* className) {
    NSString* lowercase = className.lowercaseString;
    for (NSString* fragment in
         @[@"account", @"credential", @"token", @"cookie", @"session",
           @"urlrequest", @"urlresponse"]) {
        if ([lowercase containsString:fragment]) return YES;
    }
    return NO;
}

static id BHTDetailedReplySanitizedObject(
    id value,
    NSUInteger depth,
    NSUInteger* redactions,
    NSUInteger* truncations);

static NSDictionary* BHTDetailedReplySanitizedError(
    NSError* error,
    NSUInteger depth,
    NSUInteger* redactions,
    NSUInteger* truncations) {
    NSMutableDictionary* result = [@{
        @"class": NSStringFromClass(error.class) ?: @"NSError",
        @"domain": BHTDetailedReplyScrubString(
            error.domain ?: @"", redactions, truncations),
        @"code": @(error.code),
        @"localizedDescription": BHTDetailedReplyScrubString(
            error.localizedDescription ?: @"", redactions, truncations),
    } mutableCopy];
    if (error.localizedFailureReason.length > 0) {
        result[@"localizedFailureReason"] = BHTDetailedReplyScrubString(
            error.localizedFailureReason, redactions, truncations);
    }
    if (error.localizedRecoverySuggestion.length > 0) {
        result[@"localizedRecoverySuggestion"] = BHTDetailedReplyScrubString(
            error.localizedRecoverySuggestion, redactions, truncations);
    }
    id userInfo = BHTDetailedReplySanitizedObject(
        error.userInfo, depth + 1, redactions, truncations);
    if (userInfo) result[@"userInfo"] = userInfo;
    return [result copy];
}

static id BHTDetailedReplySanitizedObject(
    id value,
    NSUInteger depth,
    NSUInteger* redactions,
    NSUInteger* truncations) {
    if (!value || value == NSNull.null) return NSNull.null;
    if (depth > BHTDetailedReplyMaximumDepth) {
        if (truncations) (*truncations)++;
        return @"<maximum depth reached>";
    }
    if ([value isKindOfClass:NSString.class]) {
        return BHTDetailedReplyScrubString(
            value, redactions, truncations);
    }
    if ([value isKindOfClass:NSNumber.class]) {
        double numericValue = [(NSNumber*)value doubleValue];
        if (isfinite(numericValue)) return value;
        if (truncations) (*truncations)++;
        return @"<non-finite number omitted>";
    }
    if ([value isKindOfClass:NSError.class]) {
        return BHTDetailedReplySanitizedError(
            value, depth, redactions, truncations);
    }
    if ([value isKindOfClass:NSURL.class]) {
        if (redactions) (*redactions)++;
        return @"<redacted URL>";
    }
    if ([value isKindOfClass:NSData.class]) {
        return @{
            @"class": @"NSData",
            @"byteCount": @([(NSData*)value length]),
            @"contentsRetained": @NO,
        };
    }
    if ([value isKindOfClass:NSDictionary.class]) {
        NSDictionary* dictionary = value;
        NSArray* keys = [dictionary.allKeys
            sortedArrayUsingComparator:^NSComparisonResult(id left, id right) {
                return [[left description]
                    compare:[right description]
                   options:NSCaseInsensitiveSearch];
            }];
        NSMutableDictionary* result = [NSMutableDictionary dictionary];
        NSUInteger count = MIN(
            keys.count, BHTDetailedReplyMaximumDictionaryKeys);
        for (NSUInteger index = 0; index < count; index++) {
            id rawKey = keys[index];
            NSString* key = [rawKey isKindOfClass:NSString.class]
                ? rawKey
                : [rawKey description];
            key = BHTDetailedReplyScrubString(
                key ?: @"<key>", redactions, truncations);
            if (BHTDetailedReplyShouldRedactKey(key)) {
                result[key] = @"<redacted credential value>";
                if (redactions) (*redactions)++;
                continue;
            }
            result[key] = BHTDetailedReplySanitizedObject(
                dictionary[rawKey], depth + 1,
                redactions, truncations) ?: NSNull.null;
        }
        if (keys.count > count) {
            result[@"<truncatedKeys>"] = @(keys.count - count);
            if (truncations) (*truncations)++;
        }
        return [result copy];
    }
    if ([value isKindOfClass:NSArray.class]) {
        NSArray* array = value;
        NSUInteger count = MIN(
            array.count, BHTDetailedReplyMaximumArrayElements);
        NSMutableArray* result = [NSMutableArray arrayWithCapacity:count];
        for (NSUInteger index = 0; index < count; index++) {
            [result addObject:BHTDetailedReplySanitizedObject(
                array[index], depth + 1,
                redactions, truncations) ?: NSNull.null];
        }
        if (array.count > count) {
            [result addObject:@{
                @"truncatedElements": @(array.count - count)
            }];
            if (truncations) (*truncations)++;
        }
        return [result copy];
    }

    NSString* className = NSStringFromClass([value class]) ?: @"unknown";
    NSMutableDictionary* result = [@{ @"class": className } mutableCopy];
    if (BHTDetailedReplyDescriptionDeniedForClassName(className)) {
        result[@"description"] = @"<omitted for credential safety>";
        if (redactions) (*redactions)++;
        return [result copy];
    }
    @try {
        result[@"description"] = BHTDetailedReplyScrubString(
            [value description] ?: @"", redactions, truncations);
        if ([value respondsToSelector:@selector(debugDescription)]) {
            result[@"debugDescription"] = BHTDetailedReplyScrubString(
                [value debugDescription] ?: @"",
                redactions, truncations);
        }
    } @catch (__unused NSException* exception) {
        result[@"description"] = @"<description raised an exception>";
    }
    return [result copy];
}

static NSDictionary* BHTDetailedReplyObjectSummary(
    id value,
    NSUInteger* redactions,
    NSUInteger* truncations) {
    if (!value) return @{ @"present": @NO };
    return @{
        @"present": @YES,
        @"value": BHTDetailedReplySanitizedObject(
            value, 0, redactions, truncations) ?: NSNull.null,
    };
}

static NSData* BHTDetailedReplyResponseData(id response) {
    if (!response) return nil;
    SEL infoSelector = NSSelectorFromString(@"info");
    if (!BHTDetailedReplyMethodReturnsObjectWithNoArguments(
            [response class], infoSelector)) {
        return nil;
    }
    @try {
        id info = ((id (*)(id, SEL))objc_msgSend)(
            response, infoSelector);
        SEL dataSelector = NSSelectorFromString(@"data");
        if (!info ||
            !BHTDetailedReplyMethodReturnsObjectWithNoArguments(
                [info class], dataSelector)) {
            return nil;
        }
        @synchronized(BHTDetailedReplyLock()) {
            BHTDetailedReplyResponseAccessorsObserved = YES;
        }
        id data = ((id (*)(id, SEL))objc_msgSend)(
            info, dataSelector);
        return [data isKindOfClass:NSData.class] ? data : nil;
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

void BHTArmDetailedReplyDiagnostics(void) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyArmed = YES;
        BHTDetailedReplyArmedAt = BHTDetailedReplyNow();
        BHTDetailedReplyCaptureStartedAt = 0;
        BHTDetailedReplySessionGeneration = 0;
        BHTDetailedReplyCapture = nil;
        BHTDetailedReplyRedactionCount = 0;
        BHTDetailedReplyTruncationCount = 0;
        BHTDetailedReplyCaptureState = @"armedForNextNativeReply";
        BHTDetailedReplySetPreference(YES);
    }
}

void BHTDisarmDetailedReplyDiagnostics(void) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyArmed = NO;
        if (!BHTDetailedReplyCapture) {
            BHTDetailedReplyCaptureState = @"disarmed";
        }
        BHTDetailedReplySetPreference(NO);
    }
}

BOOL BHTDetailedReplyDiagnosticsIsArmed(void) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        // A persisted ON value from a previous process must never re-arm this
        // invasive diagnostic without a fresh in-app confirmation.
        if (!BHTDetailedReplyArmed &&
            [BHTSettings boolForKey:@"detailed_reply_diagnostics"]) {
            BHTDetailedReplySetPreference(NO);
        }
        return BHTDetailedReplyArmed;
    }
}

BOOL BHTDetailedReplyDiagnosticsHasCapture(void) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        return BHTDetailedReplyCapture != nil;
    }
}

void BHTClearDetailedReplyDiagnostics(void) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyArmed = NO;
        BHTDetailedReplyArmedAt = 0;
        BHTDetailedReplyCaptureStartedAt = 0;
        BHTDetailedReplySessionGeneration = 0;
        BHTDetailedReplyCapture = nil;
        BHTDetailedReplyRedactionCount = 0;
        BHTDetailedReplyTruncationCount = 0;
        BHTDetailedReplyCaptureState = @"cleared";
        BHTDetailedReplySetPreference(NO);
    }
}

void BHTDetailedReplyDiagnosticsCaptureDecodedResponse(
    NSUInteger sessionGeneration,
    id response,
    id model,
    id parseError,
    id APIErrors) {
    if (sessionGeneration == 0 || !response) return;

    BOOL accepted = NO;
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        if (BHTDetailedReplyArmed) {
            BHTDetailedReplyArmed = NO;
            BHTDetailedReplySetPreference(NO);
            BHTDetailedReplySessionGeneration = sessionGeneration;
            BHTDetailedReplyCaptureStartedAt = BHTDetailedReplyNow();
            BHTDetailedReplyCaptureState = @"capturingDecodedResponse";
            accepted = YES;
        } else if (BHTDetailedReplySessionGeneration ==
                   sessionGeneration) {
            accepted = YES;
        }
    }
    if (!accepted) return;

    NSData* data = BHTDetailedReplyResponseData(response);
    NSUInteger redactions = 0;
    NSUInteger truncations = 0;
    NSMutableDictionary* capture = [NSMutableDictionary dictionary];
    capture[@"sessionGeneration"] = @(sessionGeneration);
    capture[@"modelClass"] = model
        ? (NSStringFromClass([model class]) ?: @"unknown")
        : @"absent";
    capture[@"parseError"] = BHTDetailedReplyObjectSummary(
        parseError, &redactions, &truncations);
    capture[@"apiErrors"] = BHTDetailedReplyObjectSummary(
        APIErrors, &redactions, &truncations);
    capture[@"responseByteCount"] = @(data.length);
    capture[@"responseLimitBytes"] =
        @(BHTDetailedReplyResponseLimit);

    if (!data) {
        capture[@"responseJSONState"] = @"infoDataUnavailable";
    } else if (data.length > BHTDetailedReplyResponseLimit) {
        capture[@"responseJSONState"] = @"overLimitOmitted";
        truncations++;
    } else {
        NSError* JSONError = nil;
        id JSON = [NSJSONSerialization JSONObjectWithData:data
                                                  options:0
                                                    error:&JSONError];
        if (JSON) {
            capture[@"responseJSONState"] = @"parsedAndRedacted";
            capture[@"responseJSON"] = BHTDetailedReplySanitizedObject(
                JSON, 0, &redactions, &truncations) ?: NSNull.null;
        } else {
            // Never retain a raw non-JSON fallback: it cannot be reliably
            // key-redacted and could contain an unexpected credential.
            capture[@"responseJSONState"] = @"nonJSONOmitted";
            capture[@"responseJSONError"] =
                BHTDetailedReplySanitizedError(
                    JSONError, 0, &redactions, &truncations);
        }
    }

    @synchronized(BHTDetailedReplyLock()) {
        if (BHTDetailedReplySessionGeneration != sessionGeneration) return;
        NSMutableDictionary* merged =
            [BHTDetailedReplyCapture mutableCopy] ?:
                [NSMutableDictionary dictionary];
        [merged addEntriesFromDictionary:capture];
        BHTDetailedReplyCapture = [merged copy];
        BHTDetailedReplyRedactionCount += redactions;
        BHTDetailedReplyTruncationCount += truncations;
        BHTDetailedReplyCaptureState = @"decodedResponseCaptured";
    }
}

void BHTDetailedReplyDiagnosticsCapturePreparedResponse(
    NSUInteger sessionGeneration,
    BOOL observationComplete,
    id effectiveModel,
    id effectiveParseError,
    id effectiveOperationError,
    id effectiveAPIErrors,
    id finalModel,
    id finalParseError,
    id finalOperationError,
    id finalAPIErrors) {
    if (sessionGeneration == 0) return;
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        if (BHTDetailedReplySessionGeneration != sessionGeneration ||
            !BHTDetailedReplyCapture) {
            return;
        }
    }

    NSUInteger redactions = 0;
    NSUInteger truncations = 0;
    NSDictionary* prepared = @{
        @"observationComplete": @(observationComplete),
        @"effectiveModelClass": effectiveModel
            ? (NSStringFromClass([effectiveModel class]) ?: @"unknown")
            : @"absent",
        @"effectiveParseError": BHTDetailedReplyObjectSummary(
            effectiveParseError, &redactions, &truncations),
        @"effectiveOperationError": BHTDetailedReplyObjectSummary(
            effectiveOperationError, &redactions, &truncations),
        @"effectiveAPIErrors": BHTDetailedReplyObjectSummary(
            effectiveAPIErrors, &redactions, &truncations),
        @"finalModelClass": finalModel
            ? (NSStringFromClass([finalModel class]) ?: @"unknown")
            : @"absent",
        @"finalParseError": BHTDetailedReplyObjectSummary(
            finalParseError, &redactions, &truncations),
        @"finalOperationError": BHTDetailedReplyObjectSummary(
            finalOperationError, &redactions, &truncations),
        @"finalAPIErrors": BHTDetailedReplyObjectSummary(
            finalAPIErrors, &redactions, &truncations),
    };

    @synchronized(BHTDetailedReplyLock()) {
        if (BHTDetailedReplySessionGeneration != sessionGeneration ||
            !BHTDetailedReplyCapture) {
            return;
        }
        NSMutableDictionary* capture =
            [BHTDetailedReplyCapture mutableCopy];
        capture[@"prepared"] = prepared;
        BHTDetailedReplyCapture = [capture copy];
        BHTDetailedReplyRedactionCount += redactions;
        BHTDetailedReplyTruncationCount += truncations;
        BHTDetailedReplyCaptureState = @"preparedResponseCaptured";
    }
}

void BHTDetailedReplyDiagnosticsCaptureFailure(
    NSUInteger sessionGeneration,
    NSString* source,
    NSNotification* notification) {
    if (sessionGeneration == 0) return;
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        if (BHTDetailedReplySessionGeneration != sessionGeneration ||
            !BHTDetailedReplyCapture) {
            return;
        }
    }

    NSUInteger redactions = 0;
    NSUInteger truncations = 0;
    NSMutableDictionary* failure = [NSMutableDictionary dictionary];
    failure[@"source"] = source ?: @"unknown";
    failure[@"notificationPresent"] =
        @([notification isKindOfClass:NSNotification.class]);
    if ([notification isKindOfClass:NSNotification.class]) {
        failure[@"notificationName"] = BHTDetailedReplyScrubString(
            notification.name ?: @"", &redactions, &truncations);
        failure[@"userInfo"] = BHTDetailedReplySanitizedObject(
            notification.userInfo, 0,
            &redactions, &truncations) ?: NSNull.null;
    }

    @synchronized(BHTDetailedReplyLock()) {
        if (BHTDetailedReplySessionGeneration != sessionGeneration ||
            !BHTDetailedReplyCapture) {
            return;
        }
        NSMutableDictionary* capture =
            [BHTDetailedReplyCapture mutableCopy];
        capture[@"failure"] = [failure copy];
        BHTDetailedReplyCapture = [capture copy];
        BHTDetailedReplyRedactionCount += redactions;
        BHTDetailedReplyTruncationCount += truncations;
        BHTDetailedReplyCaptureState = @"failureCaptured";
        BHTDetailedReplySessionGeneration = 0;
    }
}

void BHTDetailedReplyDiagnosticsCaptureTypedResult(
    NSUInteger sessionGeneration,
    NSString* stage,
    id status,
    id error) {
    if (sessionGeneration == 0) return;
    BOOL accepted = NO;
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        if (BHTDetailedReplyArmed) {
            BHTDetailedReplyArmed = NO;
            BHTDetailedReplySetPreference(NO);
            BHTDetailedReplySessionGeneration = sessionGeneration;
            BHTDetailedReplyCaptureStartedAt = BHTDetailedReplyNow();
            BHTDetailedReplyCaptureState = @"capturingTypedResult";
            BHTDetailedReplyCapture = @{
                @"sessionGeneration": @(sessionGeneration),
                @"responseJSONState": @"decoderCaptureNotObservedYet",
            };
            accepted = YES;
        } else if (BHTDetailedReplySessionGeneration ==
                       sessionGeneration &&
                   BHTDetailedReplyCapture) {
            accepted = YES;
        }
    }
    if (!accepted) return;

    NSUInteger redactions = 0;
    NSUInteger truncations = 0;
    NSDictionary* typedResult = @{
        @"stage": stage ?: @"unknown",
        @"status": BHTDetailedReplyObjectSummary(
            status, &redactions, &truncations),
        @"error": BHTDetailedReplyObjectSummary(
            error, &redactions, &truncations),
    };

    @synchronized(BHTDetailedReplyLock()) {
        if (BHTDetailedReplySessionGeneration != sessionGeneration ||
            !BHTDetailedReplyCapture) {
            return;
        }
        NSMutableDictionary* capture =
            [BHTDetailedReplyCapture mutableCopy];
        NSMutableArray* stages =
            [capture[@"typedResultStages"] mutableCopy] ?: [NSMutableArray array];
        if (stages.count < 8) {
            [stages addObject:typedResult];
        } else {
            truncations++;
        }
        capture[@"typedResultStages"] = [stages copy];
        BHTDetailedReplyCapture = [capture copy];
        BHTDetailedReplyRedactionCount += redactions;
        BHTDetailedReplyTruncationCount += truncations;
        BHTDetailedReplyCaptureState = @"typedResultCaptured";
    }
}

NSDictionary* BHTDetailedReplyDiagnosticSnapshot(void) {
    @synchronized(BHTDetailedReplyLock()) {
        BHTDetailedReplyPruneLocked();
        return @{
            @"schemaVersion": @1,
            @"mode": @"temporary_one_shot_beta49",
            @"temporaryInvasiveBeta": @YES,
            @"containsSensitivePersonalData": @YES,
            @"captureState": BHTDetailedReplyCaptureState ?: @"unknown",
            @"armed": @(BHTDetailedReplyArmed),
            @"includedOnlyByExplicitDetailedExport": @YES,
            @"attempt": BHTDetailedReplyCapture ?: NSNull.null,
            @"responseInfoDataAccessorsObserved":
                @(BHTDetailedReplyResponseAccessorsObserved),
            @"redactionCount": @(BHTDetailedReplyRedactionCount),
            @"truncationCount": @(BHTDetailedReplyTruncationCount),
            @"limits": @{
                @"attempts": @1,
                @"armLifetimeSeconds": @(BHTDetailedReplyArmLifetime),
                @"captureLifetimeSeconds":
                    @(BHTDetailedReplyCaptureLifetime),
                @"responseBytes": @(BHTDetailedReplyResponseLimit),
                @"maximumDepth": @(BHTDetailedReplyMaximumDepth),
                @"dictionaryKeys":
                    @(BHTDetailedReplyMaximumDictionaryKeys),
                @"arrayElements":
                    @(BHTDetailedReplyMaximumArrayElements),
                @"stringCharacters":
                    @(BHTDetailedReplyMaximumStringLength),
            },
            @"exclusions": @{
                @"passwordsAndCredentialValues": @YES,
                @"authorizationHeaders": @YES,
                @"requestAndResponseHeaders": @YES,
                @"cookiesAndWebKitStorage": @YES,
                @"authenticationTokens": @YES,
                @"rawNonJSONResponseBytes": @YES,
            },
            @"mayInclude": @[
                @"reply text returned by X",
                @"account handles and IDs",
                @"post, conversation, and media IDs",
                @"GraphQL response data and error messages",
                @"redacted error descriptions and userInfo",
            ],
        };
    }
}
