#import "Reply/BHTReplyFailureDiagnostics.h"
#import "Reply/BHTDetailedReplyDiagnostics.h"

#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <stdatomic.h>
#import <stdint.h>
#import <string.h>

typedef id _Nullable (*BHTReplyFailureObjectClassifier)(
    id _Nullable error);
typedef BOOL (*BHTReplyFailureBooleanClassifier)(
    id _Nullable error);

typedef NS_ENUM(NSUInteger, BHTReplyFailureObservationState) {
    BHTReplyFailureObservationStateComplete = 0,
    BHTReplyFailureObservationStateErrorKeyUnavailable,
    BHTReplyFailureObservationStateNotificationUnavailable,
    BHTReplyFailureObservationStateUserInfoUnavailable,
    BHTReplyFailureObservationStateErrorMissing,
    BHTReplyFailureObservationStateUnexpectedErrorObject,
    BHTReplyFailureObservationStateClassifiersUnavailable,
    BHTReplyFailureObservationStateClassifierFailed,
    BHTReplyFailureObservationStateCount,
};

typedef NS_ENUM(NSUInteger, BHTReplyFailureErrorCategory) {
    BHTReplyFailureErrorCategoryNotObserved = 0,
    BHTReplyFailureErrorCategoryAPIErrors,
    BHTReplyFailureErrorCategoryRESTError,
    BHTReplyFailureErrorCategoryParseError,
    BHTReplyFailureErrorCategoryAuthenticationError,
    BHTReplyFailureErrorCategoryOperationError,
    BHTReplyFailureErrorCategoryInvalidResponseModel,
    BHTReplyFailureErrorCategoryInternalError,
    BHTReplyFailureErrorCategoryResponseWithoutDataOrError,
    BHTReplyFailureErrorCategoryMultiple,
    BHTReplyFailureErrorCategoryUnclassified,
    BHTReplyFailureErrorCategoryCount,
};

typedef NS_ENUM(NSUInteger, BHTReplyFailureAPIErrorState) {
    BHTReplyFailureAPIErrorStateNotObserved = 0,
    BHTReplyFailureAPIErrorStateAbsent,
    BHTReplyFailureAPIErrorStateEmptyCollection,
    BHTReplyFailureAPIErrorStateNonemptyCollection,
    BHTReplyFailureAPIErrorStateUnexpectedPresentObject,
    BHTReplyFailureAPIErrorStateCount,
};

typedef NS_ENUM(NSUInteger, BHTReplyFailureErrorObjectState) {
    BHTReplyFailureErrorObjectStateNotObserved = 0,
    BHTReplyFailureErrorObjectStateOpaqueSwiftValue,
    BHTReplyFailureErrorObjectStateNSError,
    BHTReplyFailureErrorObjectStateUnexpectedObject,
    BHTReplyFailureErrorObjectStateCount,
};

static NSString* const BHTReplyFailureSourceNames[] = {
    @"outboxProcessFailed",
    @"compositionSendFailed",
};
static NSString* const BHTReplyFailureObservationStateNames[] = {
    @"complete",
    @"errorKeyUnavailable",
    @"notificationUnavailable",
    @"userInfoUnavailable",
    @"errorMissing",
    @"unexpectedErrorObject",
    @"classifiersUnavailable",
    @"classifierFailed",
};
static NSString* const BHTReplyFailureErrorCategoryNames[] = {
    @"notObserved",
    @"apiErrors",
    @"restError",
    @"parseError",
    @"authenticationError",
    @"operationError",
    @"invalidResponseModel",
    @"internalError",
    @"responseWithoutDataOrError",
    @"multiple",
    @"unclassified",
};
static NSString* const BHTReplyFailureAPIErrorStateNames[] = {
    @"notObserved",
    @"absent",
    @"emptyCollection",
    @"nonemptyCollection",
    @"unexpectedPresentObject",
};
static NSString* const BHTReplyFailureErrorObjectStateNames[] = {
    @"notObserved",
    @"opaqueSwiftValue",
    @"nsError",
    @"unexpectedObject",
};

_Static_assert(
    sizeof(BHTReplyFailureSourceNames) /
            sizeof(BHTReplyFailureSourceNames[0]) ==
        BHTNativeReplyFailureSourceCount,
    "Native reply failure source names must match the enum");
_Static_assert(
    sizeof(BHTReplyFailureObservationStateNames) /
            sizeof(BHTReplyFailureObservationStateNames[0]) ==
        BHTReplyFailureObservationStateCount,
    "Native reply failure observation names must match the enum");
_Static_assert(
    sizeof(BHTReplyFailureErrorCategoryNames) /
            sizeof(BHTReplyFailureErrorCategoryNames[0]) ==
        BHTReplyFailureErrorCategoryCount,
    "Native reply failure category names must match the enum");
_Static_assert(
    sizeof(BHTReplyFailureAPIErrorStateNames) /
            sizeof(BHTReplyFailureAPIErrorStateNames[0]) ==
        BHTReplyFailureAPIErrorStateCount,
    "Native reply API-error state names must match the enum");
_Static_assert(
    sizeof(BHTReplyFailureErrorObjectStateNames) /
            sizeof(BHTReplyFailureErrorObjectStateNames[0]) ==
        BHTReplyFailureErrorObjectStateCount,
    "Native reply error-object state names must match the enum");
_Static_assert(
    BHTReplyFailureErrorCategoryResponseWithoutDataOrError -
            BHTReplyFailureErrorCategoryAPIErrors +
            1 ==
        8,
    "Native reply error categories must match the classifier set");

static NSString* BHTReplyFailureErrorUserInfoKey;
static BHTReplyFailureObjectClassifier
    BHTReplyFailureGetAPIErrors;
static BHTReplyFailureObjectClassifier
    BHTReplyFailureGetRESTError;
static BHTReplyFailureObjectClassifier
    BHTReplyFailureGetParseError;
static BHTReplyFailureObjectClassifier
    BHTReplyFailureGetAuthenticationError;
static BHTReplyFailureObjectClassifier
    BHTReplyFailureGetOperationError;
static BHTReplyFailureObjectClassifier
    BHTReplyFailureGetInvalidResponseModelError;
static BHTReplyFailureObjectClassifier
    BHTReplyFailureGetInternalError;
static BHTReplyFailureBooleanClassifier
    BHTReplyFailureIsResponseWithoutDataOrError;
static BOOL BHTReplyFailureClassifiersAvailable;
static BOOL BHTReplyFailurePrepared;
static Class BHTReplyFailureSwiftValueClass;

static atomic_ulong BHTReplyFailureCandidateNotifications;
static atomic_ulong BHTReplyFailureAcceptedNotifications;
static atomic_ulong BHTReplyFailureZeroGenerationRejections;
static atomic_ulong BHTReplyFailureSourceCounters[
    BHTNativeReplyFailureSourceCount];
static atomic_ulong BHTReplyFailureObservationCounters[
    BHTReplyFailureObservationStateCount];
static atomic_ulong BHTReplyFailureCategoryCounters[
    BHTReplyFailureErrorCategoryCount];
static atomic_ulong BHTReplyFailureErrorObjectCounters[
    BHTReplyFailureErrorObjectStateCount];
static NSMutableArray<NSDictionary*>*
    BHTReplyFailureRecentAttempts;
static const NSUInteger BHTReplyFailureRecentAttemptLimit = 8;

static NSObject* BHTReplyFailureLock(void) {
    static NSObject* lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static NSString* BHTReplyFailureMappedStringConstant(
    const char* symbol) {
    if (!symbol) return nil;
    void* address = dlsym(RTLD_DEFAULT, symbol);
    if (!address) return nil;

    Dl_info symbolInfo = {0};
    if (dladdr(address, &symbolInfo) == 0) return nil;
    uintptr_t candidateBits = 0;
    memcpy(&candidateBits, address, sizeof(candidateBits));
    if (candidateBits == 0 ||
        candidateBits % sizeof(void*) != 0) {
        return nil;
    }
    Dl_info candidateInfo = {0};
    if (dladdr((void*)candidateBits, &candidateInfo) == 0) {
        return nil;
    }
    if (!symbolInfo.dli_fbase ||
        symbolInfo.dli_fbase != candidateInfo.dli_fbase) {
        return nil;
    }

    __unsafe_unretained id candidate =
        (__bridge id)(void*)candidateBits;
    @try {
        if (![candidate isKindOfClass:NSString.class] ||
            [(NSString*)candidate length] == 0) {
            return nil;
        }
        return [(NSString*)candidate copy];
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

static void* BHTReplyFailureMappedFunction(
    const char* symbol,
    void** expectedImageBase) {
    if (!symbol || !expectedImageBase) return NULL;
    void* address = dlsym(RTLD_DEFAULT, symbol);
    if (!address) return NULL;
    Dl_info info = {0};
    if (dladdr(address, &info) == 0 || !info.dli_fbase ||
        !info.dli_fname) {
        return NULL;
    }
    NSString* imageName = [NSString
        stringWithUTF8String:info.dli_fname];
    if (![imageName.lastPathComponent
            isEqualToString:@"TwitterSPMMigration"]) {
        return NULL;
    }
    if (*expectedImageBase &&
        *expectedImageBase != info.dli_fbase) {
        return NULL;
    }
    *expectedImageBase = info.dli_fbase;
    return address;
}

static BHTReplyFailureObjectClassifier
BHTReplyFailureResolveObjectClassifier(
    const char* symbol,
    void** expectedImageBase) {
    void* address = BHTReplyFailureMappedFunction(
        symbol, expectedImageBase);
    BHTReplyFailureObjectClassifier function = NULL;
    if (address && sizeof(function) == sizeof(address)) {
        memcpy(&function, &address, sizeof(function));
    }
    return function;
}

static BHTReplyFailureBooleanClassifier
BHTReplyFailureResolveBooleanClassifier(
    const char* symbol,
    void** expectedImageBase) {
    void* address = BHTReplyFailureMappedFunction(
        symbol, expectedImageBase);
    BHTReplyFailureBooleanClassifier function = NULL;
    if (address && sizeof(function) == sizeof(address)) {
        memcpy(&function, &address, sizeof(function));
    }
    return function;
}

void BHTPrepareNativeReplyFailureDiagnostics(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* version = [NSBundle.mainBundle
            objectForInfoDictionaryKey:
                @"CFBundleShortVersionString"];
        if (![version isKindOfClass:NSString.class] ||
            ![version isEqualToString:@"12.9"]) {
            BHTReplyFailurePrepared = YES;
            return;
        }

        BHTReplyFailureErrorUserInfoKey =
            BHTReplyFailureMappedStringConstant(
                "TFNTwitterCompositionOutboxNotificationErrorUserInfoKey");
        BHTReplyFailureSwiftValueClass =
            NSClassFromString(@"__SwiftValue");
        void* expectedImageBase = NULL;
        BHTReplyFailureGetAPIErrors =
            BHTReplyFailureResolveObjectClassifier(
                "HTTPRequestActionResponseErrorGetAPIErrors",
                &expectedImageBase);
        BHTReplyFailureGetRESTError =
            BHTReplyFailureResolveObjectClassifier(
                "HTTPRequestActionResponseErrorGetRestErrors",
                &expectedImageBase);
        BHTReplyFailureGetParseError =
            BHTReplyFailureResolveObjectClassifier(
                "HTTPRequestActionResponseErrorGetParseError",
                &expectedImageBase);
        BHTReplyFailureGetAuthenticationError =
            BHTReplyFailureResolveObjectClassifier(
                "HTTPRequestActionResponseErrorGetAuthenticationError",
                &expectedImageBase);
        BHTReplyFailureGetOperationError =
            BHTReplyFailureResolveObjectClassifier(
                "HTTPRequestActionResponseErrorGetOperationError",
                &expectedImageBase);
        BHTReplyFailureGetInvalidResponseModelError =
            BHTReplyFailureResolveObjectClassifier(
                "HTTPRequestActionResponseErrorGetInvalidResponseModelError",
                &expectedImageBase);
        BHTReplyFailureGetInternalError =
            BHTReplyFailureResolveObjectClassifier(
                "HTTPRequestActionResponseErrorGetInternalError",
                &expectedImageBase);
        BHTReplyFailureIsResponseWithoutDataOrError =
            BHTReplyFailureResolveBooleanClassifier(
                "HTTPRequestActionResponseErrorIsResponseWithoutDataOrErrorError",
                &expectedImageBase);
        BHTReplyFailureClassifiersAvailable =
            BHTReplyFailureGetAPIErrors &&
            BHTReplyFailureGetRESTError &&
            BHTReplyFailureGetParseError &&
            BHTReplyFailureGetAuthenticationError &&
            BHTReplyFailureGetOperationError &&
            BHTReplyFailureGetInvalidResponseModelError &&
            BHTReplyFailureGetInternalError &&
            BHTReplyFailureIsResponseWithoutDataOrError;
        if (!BHTReplyFailureClassifiersAvailable) {
            BHTReplyFailureGetAPIErrors = NULL;
            BHTReplyFailureGetRESTError = NULL;
            BHTReplyFailureGetParseError = NULL;
            BHTReplyFailureGetAuthenticationError = NULL;
            BHTReplyFailureGetOperationError = NULL;
            BHTReplyFailureGetInvalidResponseModelError = NULL;
            BHTReplyFailureGetInternalError = NULL;
            BHTReplyFailureIsResponseWithoutDataOrError = NULL;
        }
        BHTReplyFailurePrepared = YES;
    });
}

static BHTReplyFailureAPIErrorState
BHTReplyFailureAPIErrorStateForObject(id value) {
    if (!value) return BHTReplyFailureAPIErrorStateAbsent;
    if (![value isKindOfClass:NSArray.class]) {
        return
            BHTReplyFailureAPIErrorStateUnexpectedPresentObject;
    }
    return [(NSArray*)value count] == 0
        ? BHTReplyFailureAPIErrorStateEmptyCollection
        : BHTReplyFailureAPIErrorStateNonemptyCollection;
}

static void BHTReplyFailureAppendAttempt(
    NSDictionary* attempt) {
    @synchronized(BHTReplyFailureLock()) {
        if (!BHTReplyFailureRecentAttempts) {
            BHTReplyFailureRecentAttempts =
                [NSMutableArray arrayWithCapacity:
                    BHTReplyFailureRecentAttemptLimit];
        }
        if (BHTReplyFailureRecentAttempts.count >=
            BHTReplyFailureRecentAttemptLimit) {
            [BHTReplyFailureRecentAttempts removeObjectAtIndex:0];
        }
        [BHTReplyFailureRecentAttempts addObject:attempt];
    }
}

void BHTObserveNativeReplyFailureNotification(
    NSUInteger sessionGeneration,
    BHTNativeReplyFailureSource source,
    NSNotification* notification) {
    if (source >= BHTNativeReplyFailureSourceCount) return;
    atomic_fetch_add_explicit(
        &BHTReplyFailureCandidateNotifications, 1,
        memory_order_relaxed);
    if (sessionGeneration == 0) {
        atomic_fetch_add_explicit(
            &BHTReplyFailureZeroGenerationRejections, 1,
            memory_order_relaxed);
        return;
    }
    BHTPrepareNativeReplyFailureDiagnostics();
    BHTReplyFailureObservationState observationState =
        BHTReplyFailureObservationStateComplete;
    BHTReplyFailureErrorCategory category =
        BHTReplyFailureErrorCategoryNotObserved;
    BHTReplyFailureAPIErrorState APIErrorState =
        BHTReplyFailureAPIErrorStateNotObserved;
    BHTReplyFailureErrorObjectState errorObjectState =
        BHTReplyFailureErrorObjectStateNotObserved;

    if (!BHTReplyFailureErrorUserInfoKey) {
        observationState =
            BHTReplyFailureObservationStateErrorKeyUnavailable;
    } else if (![notification isKindOfClass:NSNotification.class]) {
        observationState =
            BHTReplyFailureObservationStateNotificationUnavailable;
    } else {
        @try {
        NSDictionary* userInfo = notification.userInfo;
        if (![userInfo isKindOfClass:NSDictionary.class]) {
            observationState =
                BHTReplyFailureObservationStateUserInfoUnavailable;
        } else {
            id error = [userInfo objectForKey:
                BHTReplyFailureErrorUserInfoKey];
            if (!error) {
                observationState =
                    BHTReplyFailureObservationStateErrorMissing;
            } else if (BHTReplyFailureSwiftValueClass &&
                       object_getClass(error) ==
                           BHTReplyFailureSwiftValueClass) {
                errorObjectState =
                    BHTReplyFailureErrorObjectStateOpaqueSwiftValue;
                if (!BHTReplyFailureClassifiersAvailable) {
                    observationState =
                        BHTReplyFailureObservationStateClassifiersUnavailable;
                } else {
                    @try {
                        id APIErrors =
                            BHTReplyFailureGetAPIErrors(error);
                        APIErrorState =
                            BHTReplyFailureAPIErrorStateForObject(
                                APIErrors);
                        BOOL matches[] = {
                            APIErrorState ==
                                BHTReplyFailureAPIErrorStateNonemptyCollection,
                            BHTReplyFailureGetRESTError(error) != nil,
                            BHTReplyFailureGetParseError(error) != nil,
                            BHTReplyFailureGetAuthenticationError(error) != nil,
                            BHTReplyFailureGetOperationError(error) != nil,
                            BHTReplyFailureGetInvalidResponseModelError(error) != nil,
                            BHTReplyFailureGetInternalError(error) != nil,
                            BHTReplyFailureIsResponseWithoutDataOrError(error),
                        };
                        if (APIErrorState ==
                            BHTReplyFailureAPIErrorStateUnexpectedPresentObject) {
                            observationState =
                                BHTReplyFailureObservationStateClassifierFailed;
                        } else {
                            NSUInteger matchCount = 0;
                            NSUInteger matchedIndex = 0;
                            for (NSUInteger index = 0;
                                 index < sizeof(matches) / sizeof(matches[0]);
                                 index++) {
                                if (matches[index]) {
                                    matchCount++;
                                    matchedIndex = index;
                                }
                            }
                            if (matchCount == 0) {
                                category =
                                    BHTReplyFailureErrorCategoryUnclassified;
                            } else if (matchCount > 1) {
                                category =
                                    BHTReplyFailureErrorCategoryMultiple;
                            } else {
                                category =
                                    (BHTReplyFailureErrorCategory)(
                                        BHTReplyFailureErrorCategoryAPIErrors +
                                        matchedIndex);
                            }
                        }
                    } @catch (__unused NSException* exception) {
                        observationState =
                            BHTReplyFailureObservationStateClassifierFailed;
                        category =
                            BHTReplyFailureErrorCategoryNotObserved;
                        APIErrorState =
                            BHTReplyFailureAPIErrorStateNotObserved;
                    }
                }
            } else if ([error isKindOfClass:NSError.class]) {
                errorObjectState =
                    BHTReplyFailureErrorObjectStateNSError;
                observationState =
                    BHTReplyFailureObservationStateUnexpectedErrorObject;
            } else {
                errorObjectState =
                    BHTReplyFailureErrorObjectStateUnexpectedObject;
                observationState =
                    BHTReplyFailureObservationStateUnexpectedErrorObject;
            }
        }
        } @catch (__unused NSException* exception) {
            observationState =
                BHTReplyFailureObservationStateClassifierFailed;
            category =
                BHTReplyFailureErrorCategoryNotObserved;
            APIErrorState =
                BHTReplyFailureAPIErrorStateNotObserved;
        }
    }

    atomic_fetch_add_explicit(
        &BHTReplyFailureAcceptedNotifications, 1,
        memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTReplyFailureSourceCounters[source], 1,
        memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTReplyFailureObservationCounters[observationState], 1,
        memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTReplyFailureCategoryCounters[category], 1,
        memory_order_relaxed);
    atomic_fetch_add_explicit(
        &BHTReplyFailureErrorObjectCounters[errorObjectState], 1,
        memory_order_relaxed);
    BHTReplyFailureAppendAttempt(@{
        @"sessionGeneration": @(sessionGeneration),
        @"source": BHTReplyFailureSourceNames[source],
        @"observationState":
            BHTReplyFailureObservationStateNames[observationState],
        @"errorCategory":
            BHTReplyFailureErrorCategoryNames[category],
        @"apiErrorsState":
            BHTReplyFailureAPIErrorStateNames[APIErrorState],
        @"errorObjectState":
            BHTReplyFailureErrorObjectStateNames[errorObjectState],
    });
    BHTDetailedReplyDiagnosticsCaptureFailure(
        sessionGeneration,
        BHTReplyFailureSourceNames[source],
        notification);
}

static NSDictionary* BHTReplyFailureCounterDictionary(
    NSString* const names[],
    atomic_ulong counters[],
    NSUInteger count) {
    NSMutableDictionary* result =
        [NSMutableDictionary dictionaryWithCapacity:count];
    for (NSUInteger index = 0; index < count; index++) {
        result[names[index]] =
            @(atomic_load_explicit(
                &counters[index], memory_order_relaxed));
    }
    return [result copy];
}

NSDictionary* BHTNativeReplyFailureDiagnosticSnapshot(void) {
    BHTPrepareNativeReplyFailureDiagnostics();
    NSArray* attempts;
    @synchronized(BHTReplyFailureLock()) {
        attempts = [BHTReplyFailureRecentAttempts copy] ?: @[];
    }
    return @{
        @"prepared": @(BHTReplyFailurePrepared),
        @"failureErrorKeyAvailable":
            @(BHTReplyFailureErrorUserInfoKey != nil),
        @"allClassifiersAvailable":
            @(BHTReplyFailureClassifiersAvailable),
        @"swiftValueBoxRecognitionAvailable":
            @(BHTReplyFailureSwiftValueClass != Nil),
        @"candidateNotifications":
            @(atomic_load_explicit(
                &BHTReplyFailureCandidateNotifications,
                memory_order_relaxed)),
        @"acceptedNotifications":
            @(atomic_load_explicit(
                &BHTReplyFailureAcceptedNotifications,
                memory_order_relaxed)),
        @"zeroGenerationRejections":
            @(atomic_load_explicit(
                &BHTReplyFailureZeroGenerationRejections,
                memory_order_relaxed)),
        @"sourceCounters":
            BHTReplyFailureCounterDictionary(
                BHTReplyFailureSourceNames,
                BHTReplyFailureSourceCounters,
                BHTNativeReplyFailureSourceCount),
        @"observationCounters":
            BHTReplyFailureCounterDictionary(
                BHTReplyFailureObservationStateNames,
                BHTReplyFailureObservationCounters,
                BHTReplyFailureObservationStateCount),
        @"errorCategoryCounters":
            BHTReplyFailureCounterDictionary(
                BHTReplyFailureErrorCategoryNames,
                BHTReplyFailureCategoryCounters,
                BHTReplyFailureErrorCategoryCount),
        @"errorObjectCounters":
            BHTReplyFailureCounterDictionary(
                BHTReplyFailureErrorObjectStateNames,
                BHTReplyFailureErrorObjectCounters,
                BHTReplyFailureErrorObjectStateCount),
        @"recentAttempts": attempts,
        @"recentAttemptLimit":
            @(BHTReplyFailureRecentAttemptLimit),
        @"correlationScope":
            @"process_temporal_failure_notification",
        @"requestIdentityBound": @NO,
        @"strictX12_9Only": @YES,
        @"usesExportedActionErrorClassifierBridges": @YES,
        @"failureErrorKeyResolution":
            @"x_12_9_exact_mapped_constant",
        @"inspectsFailureNotificationErrorMetadata": @YES,
        @"inspectsOnlyExactFailureErrorUserInfoKey": @YES,
        @"classifiesOnlyExactOpaqueSwiftValueWrapper": @YES,
        @"inspectsOpaqueSwiftValueContents": @NO,
        @"enumeratesNotificationUserInfo": @NO,
        @"capturesNotificationPayloads": @NO,
        @"capturesRawErrors": @NO,
        @"capturesErrorDescriptionsOrUserInfo": @NO,
        @"inspectsErrorDomainsOrCodes": @NO,
        @"inspectsAPIErrorCollectionElements": @NO,
        @"capturesTweetOrReplyText": @NO,
        @"capturesIdentifiers": @NO,
        @"capturesAccountData": @NO,
        @"persistsNotificationOrErrorObjects": @NO,
        @"exportsNotificationOrErrorObjects": @NO,
        @"modifiesErrorsNotificationsOrCompletions": @NO,
        @"failureClassificationDoesNotInferPostingSuccess": @YES,
    };
}
