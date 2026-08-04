#import "Compatibility/BHTCompatibilityReporter.h"
#import "Core/BHTManager.h"
#import "Core/BHTSettings.h"
#import "Likes/BHTLikesTab.h"
#import "Login/BHTCompatibilityLogin.h"
#import "MediaActions/BHTMediaActionUtility.h"
#import "Reply/BHTDetailedReplyDiagnostics.h"
#import "Reply/BHTReplyApplicationDiagnostics.h"
#import "Reply/BHTReplyFailureDiagnostics.h"
#import "Reply/BHTReplyRequestDiagnostics.h"
#import "Reply/BHTWebReplyFallback.h"
#import "Security/BHTAuthenticationURLUtility.h"
#import "Sidebar/BHTSidebarNavigationUtility.h"
#import "ThemeColor/BHTThemePresets.h"

#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <float.h>
#import <objc/runtime.h>
#import <stdint.h>
#import <stdatomic.h>
#import <string.h>

@interface BHTRailBrandingObservationState : NSObject
@property(nonatomic, weak) UIImageView* logoView;
@property(nonatomic, copy) NSString* resolution;
@property(nonatomic) CGRect hostBounds;
@property(nonatomic) CGRect logoFrame;
@property(nonatomic) UIEdgeInsets safeAreaInsets;
@property(nonatomic) NSUInteger candidateCount;
@property(nonatomic) BOOL birdApplied;
@end

@implementation BHTRailBrandingObservationState
@end

static char kBHTRailBrandingObservationStateKey;
static NSArray<NSString*>* BHTNavigationEntryClasses;
static NSMutableDictionary<NSString*, NSMutableDictionary*>*
    BHTTimelineItemObservations;
static NSMutableDictionary<NSString*, NSMutableDictionary*>*
    BHTMediaActionObservations;
static NSDictionary* BHTRailBrandingObservation;
static NSDictionary* BHTThemeRuntimeObservation;
static NSUInteger BHTNavigationReportGeneration;
static atomic_ulong
    BHTForYouFilterDiagnosticCounters[
        BHTForYouFilterDiagnosticEventCount];
static atomic_ulong
    BHTReplyWorkflowDiagnosticCounters[
        BHTReplyWorkflowDiagnosticEventCount];
static NSString* BHTReplyWorkflowLastStage = @"idle";
static NSString* BHTReplyWorkflowLastOutcome = @"none";
static BOOL BHTReplyWorkflowSessionActive;
static BOOL BHTReplyWorkflowSendForwarded;
static BOOL BHTReplyWorkflowComposerPresented;
static BOOL BHTReplyWorkflowComposerVisible;
static BOOL BHTReplyWorkflowComposerClosed;
static BOOL BHTReplyWorkflowAwaitingComposerClose;
static CFAbsoluteTime BHTReplyWorkflowExpiresAt;
static NSTimeInterval BHTReplyWorkflowSendForwardedAt;
static atomic_bool BHTReplyWorkflowNetworkWindowOpen;
static atomic_bool BHTReplyWorkflowApplicationWindowOpen;
static NSUInteger BHTReplyWorkflowSessionGeneration;
static NSMutableDictionary<NSString*, id>*
    BHTReplyWorkflowObserverTokens;
static NSMutableDictionary<NSString*, NSNumber*>*
    BHTReplyWorkflowObserverAvailability;
static NSMutableArray<NSDictionary*>* BHTReplyWorkflowOrderedTrace;
static NSTimeInterval BHTReplyWorkflowTraceStartedAt;
static NSUInteger BHTReplyWorkflowTraceSequence;
static BOOL BHTReplyWorkflowTraceTruncated;

static NSObject* BHTObservationLock(void) {
    static NSObject* lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

static dispatch_queue_t BHTCompatibilityReportQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create(
            "com.neofreebird.compatibility-report",
            DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

void BHTRecordForYouFilterDiagnostic(
    BHTForYouFilterDiagnosticEvent event) {
    if (event >= BHTForYouFilterDiagnosticEventCount) return;
    atomic_fetch_add_explicit(
        &BHTForYouFilterDiagnosticCounters[event], 1,
        memory_order_relaxed);
}

static const NSTimeInterval
    BHTReplyWorkflowDiagnosticWindowSeconds = 90.0;
static const NSTimeInterval
    BHTReplyWorkflowNetworkCorrelationWindowSeconds = 15.0;
static const NSTimeInterval
    BHTReplyWorkflowApplicationCorrelationWindowSeconds = 30.0;
static const NSUInteger BHTReplyWorkflowTraceLimit = 64;

static void BHTSetReplyWorkflowActiveWindows(BOOL open) {
    atomic_store_explicit(
        &BHTReplyWorkflowNetworkWindowOpen,
        open, memory_order_release);
    atomic_store_explicit(
        &BHTReplyWorkflowApplicationWindowOpen,
        open, memory_order_release);
}

static NSString* const BHTReplyWorkflowEventNames[] = {
    @"replyActionTapped",
    @"replyActionForwardedToX",
    @"webFallbackPresented",
    @"persistentComposerPresented",
    @"composerPresented",
    @"composerDisappeared",
    @"composerClosed",
    @"sendButtonTapped",
    @"sendForwardedToX",
    @"validationEntered",
    @"validationReturned",
    @"sendCompositionsEntered",
    @"sendCompositionsReturned",
    @"containerCompleted",
    @"containerCancelled",
    @"outboxQueued",
    @"outboxProcessing",
    @"outboxProcessed",
    @"sendCompleted",
    @"outboxProcessFailed",
    @"compositionSendFailed",
    @"unattributedPersistentComposerPresented",
    @"unattributedComposerPresented",
    @"unattributedSendButtonTapped",
    @"unattributedSendForwardedToX",
};
_Static_assert(
    sizeof(BHTReplyWorkflowEventNames) /
            sizeof(BHTReplyWorkflowEventNames[0]) ==
        BHTReplyWorkflowDiagnosticEventCount,
    "Reply workflow event names must match the event enum");

static void BHTStartReplyWorkflowSessionLocked(void) {
    BHTReplyWorkflowSessionActive = YES;
    BHTReplyWorkflowSendForwarded = NO;
    BHTReplyWorkflowComposerPresented = NO;
    BHTReplyWorkflowComposerVisible = NO;
    BHTReplyWorkflowComposerClosed = NO;
    BHTReplyWorkflowAwaitingComposerClose = NO;
    BHTReplyWorkflowSendForwardedAt = 0;
    BHTSetReplyWorkflowActiveWindows(NO);
    BHTReplyWorkflowLastOutcome = @"none";
    BHTReplyWorkflowSessionGeneration++;
    BHTReplyWorkflowTraceStartedAt =
        NSProcessInfo.processInfo.systemUptime;
    BHTReplyWorkflowTraceSequence = 0;
    BHTReplyWorkflowTraceTruncated = NO;
    if (!BHTReplyWorkflowOrderedTrace) {
        BHTReplyWorkflowOrderedTrace =
            [NSMutableArray arrayWithCapacity:
                BHTReplyWorkflowTraceLimit];
    } else {
        [BHTReplyWorkflowOrderedTrace removeAllObjects];
    }
    BHTReplyWorkflowExpiresAt =
        CFAbsoluteTimeGetCurrent() +
        BHTReplyWorkflowDiagnosticWindowSeconds;
}

static NSString* BHTReplyWorkflowTraceSource(
    BHTReplyWorkflowDiagnosticEvent event) {
    switch (event) {
        case BHTReplyWorkflowDiagnosticWebFallbackPresented:
            return @"route_hook";
        case BHTReplyWorkflowDiagnosticPersistentComposerPresented:
        case BHTReplyWorkflowDiagnosticComposerPresented:
        case BHTReplyWorkflowDiagnosticComposerDisappeared:
        case BHTReplyWorkflowDiagnosticComposerClosed:
        case BHTReplyWorkflowDiagnosticContainerCompleted:
        case BHTReplyWorkflowDiagnosticContainerCancelled:
        case BHTReplyWorkflowDiagnosticUnattributedPersistentComposerPresented:
        case BHTReplyWorkflowDiagnosticUnattributedComposerPresented:
            return @"lifecycle_hook";
        case BHTReplyWorkflowDiagnosticValidationEntered:
        case BHTReplyWorkflowDiagnosticValidationReturned:
        case BHTReplyWorkflowDiagnosticSendCompositionsEntered:
        case BHTReplyWorkflowDiagnosticSendCompositionsReturned:
            return @"composer_hook";
        case BHTReplyWorkflowDiagnosticOutboxQueued:
        case BHTReplyWorkflowDiagnosticOutboxProcessing:
        case BHTReplyWorkflowDiagnosticOutboxProcessed:
        case BHTReplyWorkflowDiagnosticSendCompleted:
        case BHTReplyWorkflowDiagnosticOutboxProcessFailed:
        case BHTReplyWorkflowDiagnosticCompositionSendFailed:
            return @"notification";
        case BHTReplyWorkflowDiagnosticReplyActionTapped:
        case BHTReplyWorkflowDiagnosticReplyActionForwarded:
        case BHTReplyWorkflowDiagnosticSendButtonTapped:
        case BHTReplyWorkflowDiagnosticSendForwardedToX:
        case BHTReplyWorkflowDiagnosticUnattributedSendButtonTapped:
        case BHTReplyWorkflowDiagnosticUnattributedSendForwardedToX:
            return @"ui_hook";
        case BHTReplyWorkflowDiagnosticEventCount:
            return @"unknown";
    }
    return @"unknown";
}

static void BHTAppendReplyWorkflowTraceLocked(
    BHTReplyWorkflowDiagnosticEvent event) {
    if (event >= BHTReplyWorkflowDiagnosticEventCount) return;
    if (!BHTReplyWorkflowOrderedTrace) {
        BHTReplyWorkflowOrderedTrace =
            [NSMutableArray arrayWithCapacity:
                BHTReplyWorkflowTraceLimit];
    }
    if (BHTReplyWorkflowTraceStartedAt <= 0) {
        BHTReplyWorkflowTraceStartedAt =
            NSProcessInfo.processInfo.systemUptime;
    }
    if (BHTReplyWorkflowOrderedTrace.count >=
        BHTReplyWorkflowTraceLimit) {
        [BHTReplyWorkflowOrderedTrace removeObjectAtIndex:0];
        BHTReplyWorkflowTraceTruncated = YES;
    }
    NSTimeInterval elapsed = MAX(
        0.0,
        NSProcessInfo.processInfo.systemUptime -
            BHTReplyWorkflowTraceStartedAt);
    [BHTReplyWorkflowOrderedTrace addObject:@{
        @"sequence": @(BHTReplyWorkflowTraceSequence++),
        @"event": BHTReplyWorkflowEventNames[event],
        @"source": BHTReplyWorkflowTraceSource(event),
        @"relativeMillisecondsBucket":
            @(((NSUInteger)(elapsed * 10.0)) * 100),
        @"sessionGeneration":
            @(BHTReplyWorkflowSessionGeneration),
    }];
}

static void BHTRefreshReplyWorkflowExpiryLocked(void) {
    if (!BHTReplyWorkflowSessionActive) return;
    BHTReplyWorkflowExpiresAt =
        CFAbsoluteTimeGetCurrent() +
        BHTReplyWorkflowDiagnosticWindowSeconds;
}

static void BHTExpireReplyWorkflowSessionIfNeededLocked(void) {
    if (!BHTReplyWorkflowSessionActive ||
        BHTReplyWorkflowExpiresAt <= 0 ||
        CFAbsoluteTimeGetCurrent() <=
            BHTReplyWorkflowExpiresAt) {
        return;
    }
    BHTReplyWorkflowSessionActive = NO;
    BHTReplyWorkflowSendForwarded = NO;
    BHTReplyWorkflowAwaitingComposerClose = NO;
    BHTReplyWorkflowSendForwardedAt = 0;
    BHTSetReplyWorkflowActiveWindows(NO);
    BHTReplyWorkflowExpiresAt = 0;
    BHTReplyWorkflowLastOutcome = @"timed_out";
}

void BHTRecordReplyWorkflowDiagnostic(
    BHTReplyWorkflowDiagnosticEvent event) {
    if (event >= BHTReplyWorkflowDiagnosticEventCount) return;

    @synchronized(BHTObservationLock()) {
        BHTExpireReplyWorkflowSessionIfNeededLocked();
        BHTReplyWorkflowDiagnosticEvent recordedEvent = event;
        BOOL shouldRecord = YES;

        switch (event) {
            case BHTReplyWorkflowDiagnosticReplyActionTapped:
                BHTStartReplyWorkflowSessionLocked();
                break;
            case BHTReplyWorkflowDiagnosticReplyActionForwarded:
                if (!BHTReplyWorkflowSessionActive) {
                    BHTStartReplyWorkflowSessionLocked();
                }
                break;
            case BHTReplyWorkflowDiagnosticWebFallbackPresented:
                if (!BHTReplyWorkflowSessionActive) {
                    BHTStartReplyWorkflowSessionLocked();
                }
                BHTReplyWorkflowLastOutcome =
                    @"web_fallback_presented";
                BHTReplyWorkflowSessionActive = NO;
                BHTReplyWorkflowSendForwarded = NO;
                BHTReplyWorkflowComposerPresented = NO;
                BHTReplyWorkflowComposerVisible = NO;
                BHTReplyWorkflowComposerClosed = NO;
                BHTReplyWorkflowAwaitingComposerClose = NO;
                BHTSetReplyWorkflowActiveWindows(NO);
                BHTReplyWorkflowExpiresAt = 0;
                break;
            case BHTReplyWorkflowDiagnosticPersistentComposerPresented:
                if (!BHTReplyWorkflowSessionActive) {
                    recordedEvent =
                        BHTReplyWorkflowDiagnosticUnattributedPersistentComposerPresented;
                } else {
                    BHTReplyWorkflowComposerPresented = YES;
                    BHTReplyWorkflowComposerVisible = YES;
                    BHTReplyWorkflowComposerClosed = NO;
                }
                break;
            case BHTReplyWorkflowDiagnosticComposerPresented:
                if (!BHTReplyWorkflowSessionActive) {
                    if (BHTReplyWorkflowAwaitingComposerClose) {
                        BHTReplyWorkflowComposerVisible = YES;
                        BHTReplyWorkflowComposerClosed = NO;
                    } else {
                        recordedEvent =
                            BHTReplyWorkflowDiagnosticUnattributedComposerPresented;
                    }
                } else {
                    BHTReplyWorkflowComposerPresented = YES;
                    BHTReplyWorkflowComposerVisible = YES;
                    BHTReplyWorkflowComposerClosed = NO;
                }
                break;
            case BHTReplyWorkflowDiagnosticComposerDisappeared:
                if (!BHTReplyWorkflowSessionActive &&
                    !BHTReplyWorkflowAwaitingComposerClose) {
                    shouldRecord = NO;
                    break;
                }
                BHTReplyWorkflowComposerVisible = NO;
                break;
            case BHTReplyWorkflowDiagnosticComposerClosed:
                if (!BHTReplyWorkflowSessionActive &&
                    !BHTReplyWorkflowAwaitingComposerClose) {
                    shouldRecord = NO;
                    break;
                }
                BHTReplyWorkflowComposerVisible = NO;
                BHTReplyWorkflowComposerClosed = YES;
                if (BHTReplyWorkflowAwaitingComposerClose) {
                    BHTReplyWorkflowAwaitingComposerClose = NO;
                } else if (!BHTReplyWorkflowSendForwarded) {
                    BHTReplyWorkflowSessionActive = NO;
                    BHTReplyWorkflowExpiresAt = 0;
                    BHTReplyWorkflowLastOutcome =
                        @"closed_before_send";
                }
                break;
            case BHTReplyWorkflowDiagnosticSendButtonTapped:
                if (!BHTReplyWorkflowSessionActive) {
                    BOOL retryingFailedReply =
                        BHTReplyWorkflowAwaitingComposerClose &&
                        BHTReplyWorkflowComposerPresented &&
                        BHTReplyWorkflowComposerVisible &&
                        ([BHTReplyWorkflowLastOutcome
                             isEqualToString:
                                 @"outbox_process_failed"] ||
                         [BHTReplyWorkflowLastOutcome
                             isEqualToString:
                                 @"composition_send_failed"]);
                    if (retryingFailedReply) {
                        BHTStartReplyWorkflowSessionLocked();
                        BHTReplyWorkflowComposerPresented = YES;
                        BHTReplyWorkflowComposerVisible = YES;
                    } else {
                        recordedEvent =
                            BHTReplyWorkflowDiagnosticUnattributedSendButtonTapped;
                    }
                } else {
                    BHTReplyWorkflowSendForwarded = NO;
                    BHTReplyWorkflowAwaitingComposerClose = NO;
                    BHTReplyWorkflowSendForwardedAt = 0;
                    BHTSetReplyWorkflowActiveWindows(NO);
                    BHTReplyWorkflowLastOutcome = @"none";
                }
                break;
            case BHTReplyWorkflowDiagnosticSendForwardedToX:
                if (!BHTReplyWorkflowSessionActive) {
                    recordedEvent =
                        BHTReplyWorkflowDiagnosticUnattributedSendForwardedToX;
                } else {
                    BHTReplyWorkflowSendForwarded = YES;
                    BHTReplyWorkflowSendForwardedAt =
                        NSProcessInfo.processInfo.systemUptime;
                    BHTSetReplyWorkflowActiveWindows(YES);
                }
                break;
            case BHTReplyWorkflowDiagnosticValidationEntered:
            case BHTReplyWorkflowDiagnosticValidationReturned:
            case BHTReplyWorkflowDiagnosticSendCompositionsEntered:
            case BHTReplyWorkflowDiagnosticSendCompositionsReturned:
                shouldRecord =
                    BHTReplyWorkflowSessionActive &&
                    BHTReplyWorkflowSendForwarded;
                break;
            case BHTReplyWorkflowDiagnosticContainerCompleted:
            case BHTReplyWorkflowDiagnosticContainerCancelled:
                shouldRecord =
                    BHTReplyWorkflowSessionActive ||
                    BHTReplyWorkflowAwaitingComposerClose;
                if (shouldRecord) {
                    BHTReplyWorkflowComposerVisible = NO;
                    BHTReplyWorkflowComposerClosed = YES;
                    BHTReplyWorkflowAwaitingComposerClose = NO;
                    if (event ==
                            BHTReplyWorkflowDiagnosticContainerCancelled &&
                        !BHTReplyWorkflowSendForwarded) {
                        BHTReplyWorkflowSessionActive = NO;
                        BHTSetReplyWorkflowActiveWindows(NO);
                        BHTReplyWorkflowExpiresAt = 0;
                        BHTReplyWorkflowLastOutcome =
                            @"container_cancelled_before_send";
                    }
                }
                break;
            case BHTReplyWorkflowDiagnosticOutboxQueued:
            case BHTReplyWorkflowDiagnosticOutboxProcessing:
            case BHTReplyWorkflowDiagnosticOutboxProcessed:
                shouldRecord =
                    BHTReplyWorkflowSessionActive &&
                    BHTReplyWorkflowSendForwarded;
                break;
            case BHTReplyWorkflowDiagnosticSendCompleted:
                if (BHTReplyWorkflowSessionActive &&
                    BHTReplyWorkflowSendForwarded) {
                    BHTReplyWorkflowLastOutcome = @"completed";
                    BHTReplyWorkflowAwaitingComposerClose =
                        BHTReplyWorkflowComposerPresented &&
                        !BHTReplyWorkflowComposerClosed;
                    BHTReplyWorkflowSessionActive = NO;
                    BHTReplyWorkflowSendForwarded = NO;
                    BHTSetReplyWorkflowActiveWindows(NO);
                    BHTReplyWorkflowExpiresAt = 0;
                } else {
                    shouldRecord = NO;
                }
                break;
            case BHTReplyWorkflowDiagnosticOutboxProcessFailed:
            case BHTReplyWorkflowDiagnosticCompositionSendFailed:
                if (BHTReplyWorkflowSessionActive &&
                    BHTReplyWorkflowSendForwarded) {
                    BHTReplyWorkflowLastOutcome =
                        event ==
                                BHTReplyWorkflowDiagnosticOutboxProcessFailed
                            ? @"outbox_process_failed"
                            : @"composition_send_failed";
                    BHTReplyWorkflowSessionActive = NO;
                    BHTReplyWorkflowSendForwarded = NO;
                    BHTSetReplyWorkflowActiveWindows(NO);
                    BHTReplyWorkflowAwaitingComposerClose =
                        BHTReplyWorkflowComposerPresented &&
                        !BHTReplyWorkflowComposerClosed;
                    BHTReplyWorkflowExpiresAt = 0;
                } else {
                    shouldRecord = NO;
                }
                break;
            case BHTReplyWorkflowDiagnosticUnattributedPersistentComposerPresented:
            case BHTReplyWorkflowDiagnosticUnattributedComposerPresented:
            case BHTReplyWorkflowDiagnosticUnattributedSendButtonTapped:
            case BHTReplyWorkflowDiagnosticUnattributedSendForwardedToX:
            case BHTReplyWorkflowDiagnosticEventCount:
                break;
        }

        if (!shouldRecord) return;
        atomic_fetch_add_explicit(
            &BHTReplyWorkflowDiagnosticCounters[recordedEvent], 1,
            memory_order_relaxed);
        BHTReplyWorkflowLastStage =
            BHTReplyWorkflowEventNames[recordedEvent];
        BHTAppendReplyWorkflowTraceLocked(recordedEvent);
        BHTRefreshReplyWorkflowExpiryLocked();
    }
}

BOOL BHTReplyWorkflowNetworkDiagnosticWindowMayBeActive(void) {
    return atomic_load_explicit(
        &BHTReplyWorkflowNetworkWindowOpen,
        memory_order_acquire);
}

BOOL BHTReplyWorkflowDiagnosticSessionForNetworkRequest(
    NSUInteger* generation) {
    @synchronized(BHTObservationLock()) {
        BHTExpireReplyWorkflowSessionIfNeededLocked();
        NSTimeInterval elapsedSinceSend =
            BHTReplyWorkflowSendForwardedAt > 0
                ? NSProcessInfo.processInfo.systemUptime -
                    BHTReplyWorkflowSendForwardedAt
                : DBL_MAX;
        BOOL active =
            BHTReplyWorkflowSessionActive &&
            BHTReplyWorkflowSendForwarded &&
            BHTReplyWorkflowComposerPresented &&
            BHTReplyWorkflowSendForwardedAt > 0 &&
            elapsedSinceSend <=
                BHTReplyWorkflowNetworkCorrelationWindowSeconds;
        if (!active &&
            elapsedSinceSend >
                BHTReplyWorkflowNetworkCorrelationWindowSeconds) {
            atomic_store_explicit(
                &BHTReplyWorkflowNetworkWindowOpen,
                false, memory_order_release);
        }
        if (generation) {
            *generation = active
                ? BHTReplyWorkflowSessionGeneration
                : 0;
        }
        return active;
    }
}

BOOL BHTReplyWorkflowDiagnosticSessionForApplicationResponse(
    NSUInteger* generation) {
    @synchronized(BHTObservationLock()) {
        BHTExpireReplyWorkflowSessionIfNeededLocked();
        NSTimeInterval elapsedSinceSend =
            BHTReplyWorkflowSendForwardedAt > 0
                ? NSProcessInfo.processInfo.systemUptime -
                    BHTReplyWorkflowSendForwardedAt
                : DBL_MAX;
        BOOL active =
            BHTReplyWorkflowSessionActive &&
            BHTReplyWorkflowSendForwarded &&
            BHTReplyWorkflowComposerPresented &&
            BHTReplyWorkflowSessionGeneration > 0 &&
            BHTReplyWorkflowSendForwardedAt > 0 &&
            elapsedSinceSend <=
                BHTReplyWorkflowApplicationCorrelationWindowSeconds;
        if (!active &&
            elapsedSinceSend >
                BHTReplyWorkflowApplicationCorrelationWindowSeconds) {
            atomic_store_explicit(
                &BHTReplyWorkflowApplicationWindowOpen,
                false, memory_order_release);
        }
        if (generation) {
            *generation = active
                ? BHTReplyWorkflowSessionGeneration
                : 0;
        }
        return active;
    }
}

BOOL BHTReplyWorkflowApplicationDiagnosticWindowMayBeActive(void) {
    return atomic_load_explicit(
        &BHTReplyWorkflowApplicationWindowOpen,
        memory_order_acquire);
}

// Capture only the process-local generation while the workflow is still
// active. Failure notification handling calls this before the ordinary stage
// recorder closes the terminal session.
static NSUInteger
BHTReplyWorkflowGenerationForFailureNotification(void) {
    @synchronized(BHTObservationLock()) {
        BHTExpireReplyWorkflowSessionIfNeededLocked();
        BOOL active =
            BHTReplyWorkflowSessionActive &&
            BHTReplyWorkflowSendForwarded &&
            BHTReplyWorkflowComposerPresented &&
            BHTReplyWorkflowSessionGeneration > 0;
        return active ? BHTReplyWorkflowSessionGeneration : 0;
    }
}

typedef struct {
    const char* symbol;
    const char* key;
    BHTReplyWorkflowDiagnosticEvent event;
    BOOL observesFailure;
    BHTNativeReplyFailureSource failureSource;
} BHTReplyNotificationObserverSpec;

static const BHTReplyNotificationObserverSpec
    BHTReplyNotificationObserverSpecs[] = {
        {
            "TFNTwitterCompositionOutboxDidAddCompositionNotification",
            "outboxQueued",
            BHTReplyWorkflowDiagnosticOutboxQueued,
            NO,
            BHTNativeReplyFailureSourceOutboxProcess,
        },
        {
            "TFNTwitterCompositionOutboxWillProcessCompositionNotification",
            "outboxProcessing",
            BHTReplyWorkflowDiagnosticOutboxProcessing,
            NO,
            BHTNativeReplyFailureSourceOutboxProcess,
        },
        {
            "TFNTwitterCompositionOutboxDidProcessCompositionNotification",
            "outboxProcessed",
            BHTReplyWorkflowDiagnosticOutboxProcessed,
            NO,
            BHTNativeReplyFailureSourceOutboxProcess,
        },
        {
            "TFNTwitterCompositionDidSendNotification",
            "sendCompleted",
            BHTReplyWorkflowDiagnosticSendCompleted,
            NO,
            BHTNativeReplyFailureSourceCompositionSend,
        },
        {
            "TFNTwitterCompositionOutboxDidFailProcessCompositionNotification",
            "outboxFailed",
            BHTReplyWorkflowDiagnosticOutboxProcessFailed,
            YES,
            BHTNativeReplyFailureSourceOutboxProcess,
        },
        {
            "TFNTwitterCompositionSendDidFailNotification",
            "sendFailed",
            BHTReplyWorkflowDiagnosticCompositionSendFailed,
            YES,
            BHTNativeReplyFailureSourceCompositionSend,
        },
};

static NSString* BHTReplyNotificationNameForSymbol(
    const char* symbol) {
    if (!symbol) return nil;
    void* address = dlsym(RTLD_DEFAULT, symbol);
    if (!address) return nil;

    // These exact allowlisted X 12.9 symbols are NSString* constants. Avoid
    // ARC touching their storage until both the symbol and pointed-to object
    // resolve to mapped images.
    Dl_info symbolInfo = {0};
    if (dladdr(address, &symbolInfo) == 0) return nil;
    uintptr_t candidateBits = 0;
    memcpy(&candidateBits, address, sizeof(candidateBits));
    if (candidateBits == 0) return nil;
    Dl_info candidateInfo = {0};
    if (dladdr((void*)candidateBits, &candidateInfo) == 0) {
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

void BHTInstallReplyWorkflowDiagnosticObservers(void) {
    NSString* version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (![version isKindOfClass:NSString.class] ||
        ![version isEqualToString:@"12.9"]) {
        return;
    }

    BHTPrepareNativeReplyFailureDiagnostics();

    @synchronized(BHTObservationLock()) {
        if (!BHTReplyWorkflowObserverTokens) {
            BHTReplyWorkflowObserverTokens =
                [NSMutableDictionary dictionary];
        }
        if (!BHTReplyWorkflowObserverAvailability) {
            BHTReplyWorkflowObserverAvailability =
                [NSMutableDictionary dictionary];
        }

        for (NSUInteger index = 0;
             index < sizeof(BHTReplyNotificationObserverSpecs) /
                         sizeof(BHTReplyNotificationObserverSpecs[0]);
             index++) {
            BHTReplyNotificationObserverSpec spec =
                BHTReplyNotificationObserverSpecs[index];
            NSString* key =
                [NSString stringWithUTF8String:spec.key];
            if (BHTReplyWorkflowObserverTokens[key]) continue;

            NSString* name =
                BHTReplyNotificationNameForSymbol(spec.symbol);
            if (!name) {
                BHTReplyWorkflowObserverAvailability[key] = @NO;
                continue;
            }

            id token = [NSNotificationCenter.defaultCenter
                addObserverForName:name
                            object:nil
                             queue:nil
                        usingBlock:^(
                            NSNotification* notification) {
                            NSUInteger failureGeneration = 0;
                            if (spec.observesFailure) {
                                @try {
                                    failureGeneration =
                                        BHTReplyWorkflowGenerationForFailureNotification();
                                } @catch (__unused NSException* exception) {
                                }
                            }
                            BHTRecordReplyWorkflowDiagnostic(
                                spec.event);
                            if (spec.observesFailure) {
                                @try {
                                    BHTObserveNativeReplyFailureNotification(
                                        failureGeneration,
                                        spec.failureSource,
                                        notification);
                                } @catch (__unused NSException* exception) {
                                    // Diagnostics must never suppress X's
                                    // ordinary terminal workflow stage.
                                }
                            }
                        }];
            if (token) {
                BHTReplyWorkflowObserverTokens[key] = token;
                BHTReplyWorkflowObserverAvailability[key] = @YES;
            } else {
                BHTReplyWorkflowObserverAvailability[key] = @NO;
            }
        }
    }
}

static BOOL BHTReplySelectorIsSafeAndRelevant(
    NSString* selectorName) {
    NSString* lower = selectorName.lowercaseString;
    BOOL relevant =
        [lower containsString:@"reply"] ||
        [lower containsString:@"compose"] ||
        [lower containsString:@"send"] ||
        [lower containsString:@"outbox"] ||
        [lower containsString:@"tap"];
    if (!relevant) return NO;
    return ![lower containsString:@"statusid"] &&
           ![lower containsString:@"userid"] &&
           ![lower containsString:@"username"] &&
           ![lower containsString:@"text"] &&
           ![lower containsString:@"url"] &&
           ![lower containsString:@"error"];
}

static const NSUInteger BHTReplyRuntimeMethodLimit = 48;

static NSUInteger BHTAppendReplyMethodShape(
    Class methodClass,
    NSString* kind,
    NSMutableArray<NSDictionary*>* methods) {
    if (!methodClass) return 0;
    NSUInteger relevantCount = 0;
    unsigned int count = 0;
    Method* list = class_copyMethodList(methodClass, &count);
    for (unsigned int index = 0; index < count; index++) {
        NSString* selectorName =
            NSStringFromSelector(method_getName(list[index]));
        if (!BHTReplySelectorIsSafeAndRelevant(selectorName)) {
            continue;
        }
        relevantCount++;
        if (methods.count >= BHTReplyRuntimeMethodLimit) {
            continue;
        }
        const char* rawEncoding =
            method_getTypeEncoding(list[index]);
        [methods addObject:@{
            @"selector": selectorName,
            @"kind": kind,
            @"encoding":
                rawEncoding
                    ? [NSString stringWithUTF8String:rawEncoding]
                    : @"",
        }];
    }
    free(list);
    return relevantCount;
}

static NSDictionary* BHTReplyClassRuntimeShape(
    NSString* className) {
    Class cls = NSClassFromString(className);
    if (!cls) return @{@"classPresent": @NO};

    NSMutableArray<NSDictionary*>* methods =
        [NSMutableArray array];
    NSUInteger relevantCount =
        BHTAppendReplyMethodShape(
            cls, @"instance", methods) +
        BHTAppendReplyMethodShape(
            object_getClass(cls), @"class", methods);
    [methods sortUsingComparator:^NSComparisonResult(
                 NSDictionary* first, NSDictionary* second) {
        NSComparisonResult selectorOrder =
            [first[@"selector"]
                localizedCaseInsensitiveCompare:
                    second[@"selector"]];
        if (selectorOrder != NSOrderedSame) {
            return selectorOrder;
        }
        return [first[@"kind"]
            compare:second[@"kind"]];
    }];
    return @{
        @"classPresent": @YES,
        @"superclass":
            NSStringFromClass(class_getSuperclass(cls)) ?: @"",
        @"methods": [methods copy],
        @"totalRelevantMethodCount": @(relevantCount),
        @"truncated":
            @(relevantCount > BHTReplyRuntimeMethodLimit),
    };
}

static NSDictionary* BHTReplyWorkflowRuntimeShape(void) {
    static NSDictionary* shape;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary* classes =
            [NSMutableDictionary dictionary];
        for (NSString* className in @[
                 @"TTAStatusInlineReplyButton",
                 @"TTAStatusInlineActionButton",
                 @"T1StatusInlineActionsView",
                 @"TTAStatusInlineActionsView",
                 @"T1StatusViewInlineActionTapEventHandler",
                 @"T1TweetComposeViewController",
                 @"T1PersistentComposeViewController",
                 @"T1ComposePresenter",
                 @"T1TweetComposeContainerViewController",
                 @"T1TweetComposeTableViewController",
                 @"T1TweetComposeSingleTweetViewController",
                 @"T1TweetComposeReplyContextViewController",
                 @"T1MediaInlineComposeController",
                 @"TFNTwitterComposition",
             ]) {
            classes[className] =
                BHTReplyClassRuntimeShape(className);
        }
        shape = [classes copy];
    });
    return shape ?: @{};
}

static NSDictionary*
BHTReplyWorkflowObserverAvailabilitySnapshot(void) {
    NSMutableDictionary* snapshot =
        [NSMutableDictionary dictionary];
    @synchronized(BHTObservationLock()) {
        for (NSUInteger index = 0;
             index < sizeof(BHTReplyNotificationObserverSpecs) /
                         sizeof(BHTReplyNotificationObserverSpecs[0]);
             index++) {
            NSString* key = [NSString
                stringWithUTF8String:
                    BHTReplyNotificationObserverSpecs[index].key];
            snapshot[key] =
                BHTReplyWorkflowObserverAvailability[key] ?: @NO;
        }
    }
    return [snapshot copy];
}

static NSDictionary* BHTReplyWorkflowDiagnosticSnapshot(void) {
    BHTInstallReplyWorkflowDiagnosticObservers();
    NSMutableDictionary* counters =
        [NSMutableDictionary
            dictionaryWithCapacity:
                BHTReplyWorkflowDiagnosticEventCount];

    NSString* lastStage;
    NSString* lastOutcome;
    BOOL sessionActive;
    BOOL sendForwarded;
    BOOL composerPresented;
    BOOL composerVisible;
    BOOL composerClosed;
    BOOL awaitingComposerClose;
    NSUInteger sessionGeneration;
    NSArray<NSDictionary*>* orderedTrace;
    BOOL traceTruncated;
    @synchronized(BHTObservationLock()) {
        BHTExpireReplyWorkflowSessionIfNeededLocked();
        for (NSUInteger index = 0;
             index < BHTReplyWorkflowDiagnosticEventCount;
             index++) {
            counters[BHTReplyWorkflowEventNames[index]] =
                @(atomic_load_explicit(
                    &BHTReplyWorkflowDiagnosticCounters[index],
                    memory_order_relaxed));
        }
        lastStage =
            [BHTReplyWorkflowLastStage copy] ?: @"idle";
        lastOutcome =
            [BHTReplyWorkflowLastOutcome copy] ?: @"none";
        sessionActive = BHTReplyWorkflowSessionActive;
        sendForwarded = BHTReplyWorkflowSendForwarded;
        composerPresented =
            BHTReplyWorkflowComposerPresented;
        composerVisible = BHTReplyWorkflowComposerVisible;
        composerClosed = BHTReplyWorkflowComposerClosed;
        awaitingComposerClose =
            BHTReplyWorkflowAwaitingComposerClose;
        sessionGeneration =
            BHTReplyWorkflowSessionGeneration;
        orderedTrace =
            [BHTReplyWorkflowOrderedTrace copy] ?: @[];
        traceTruncated = BHTReplyWorkflowTraceTruncated;
    }
    return @{
        @"lastStage": lastStage,
        @"lastOutcome": lastOutcome,
        @"sessionActive": @(sessionActive),
        @"sessionGeneration": @(sessionGeneration),
        @"sendForwardedToX": @(sendForwarded),
        @"composerPresented": @(composerPresented),
        @"composerVisible": @(composerVisible),
        @"composerClosed": @(composerClosed),
        @"awaitingComposerCloseAfterTerminalSignal":
            @(awaitingComposerClose),
        @"correlation":
            @"process_level_temporal_heuristic",
        @"diagnosticWindowSeconds":
            @(BHTReplyWorkflowDiagnosticWindowSeconds),
        @"networkCorrelationWindowSeconds":
            @(BHTReplyWorkflowNetworkCorrelationWindowSeconds),
        @"applicationCorrelationWindowSeconds":
            @(BHTReplyWorkflowApplicationCorrelationWindowSeconds),
        @"counters": [counters copy],
        @"orderedTrace": orderedTrace,
        @"orderedTraceLimit": @(BHTReplyWorkflowTraceLimit),
        @"orderedTraceTruncated": @(traceTruncated),
        @"orderedTraceClock": @"process_monotonic_relative",
        @"notificationObservers":
            BHTReplyWorkflowObserverAvailabilitySnapshot(),
        @"notificationResolution":
            @"x_12_9_allowlist_mapped_constants",
        @"runtimeShape": BHTReplyWorkflowRuntimeShape(),
        @"runtimeShapeContainsPrivateAPIMetadata": @YES,
        @"capturesTweetOrReplyText": @NO,
        @"capturesUsersOrAccountData": @NO,
        @"capturesIdentifiers": @NO,
        @"capturesNotificationPayloads": @NO,
        @"capturesRawErrors": @NO,
        @"failureErrorClassificationIncludedSeparately": @YES,
        @"networkCorrelationRequiresActiveForwardedSession": @YES,
    };
}

static NSDictionary* BHTForYouControllerRuntimeShape(void) {
    Class controllerClass = NSClassFromString(@"T1URTViewController");
    if (!controllerClass) return @{@"classPresent": @NO};
    Class itemsControllerClass =
        NSClassFromString(@"TFNItemsDataViewController");

    NSMutableSet<NSString*>* methods = [NSMutableSet set];
    NSMutableArray<NSDictionary*>* ivars = [NSMutableArray array];
    for (Class current = controllerClass;
         current && current != NSObject.class;
         current = class_getSuperclass(current)) {
        unsigned int methodCount = 0;
        Method* methodList =
            class_copyMethodList(current, &methodCount);
        for (unsigned int index = 0; index < methodCount; index++) {
            NSString* name =
                NSStringFromSelector(
                    method_getName(methodList[index]));
            NSString* lower = name.lowercaseString;
            if ([lower containsString:@"timeline"] ||
                [lower containsString:@"urt"] ||
                [lower containsString:@"dataviewcontroller"]) {
                [methods addObject:name];
            }
        }
        free(methodList);

        unsigned int ivarCount = 0;
        Ivar* ivarList = class_copyIvarList(current, &ivarCount);
        for (unsigned int index = 0; index < ivarCount; index++) {
            const char* rawName = ivar_getName(ivarList[index]);
            NSString* name =
                rawName
                    ? [NSString stringWithUTF8String:rawName]
                    : @"";
            NSString* lower = name.lowercaseString;
            if (!([lower containsString:@"timeline"] ||
                  [lower containsString:@"urt"] ||
                  [lower containsString:@"dataviewcontroller"])) {
                continue;
            }
            const char* rawType =
                ivar_getTypeEncoding(ivarList[index]);
            [ivars addObject:@{
                @"declaringClass": NSStringFromClass(current),
                @"name": name,
                @"type":
                    rawType
                        ? [NSString stringWithUTF8String:rawType]
                        : @""
            }];
        }
        free(ivarList);
    }

    [ivars sortUsingComparator:^NSComparisonResult(
               NSDictionary* first, NSDictionary* second) {
        return [first[@"name"]
            localizedCaseInsensitiveCompare:second[@"name"]];
    }];
    return @{
        @"classPresent": @YES,
        @"superclass":
            NSStringFromClass(class_getSuperclass(controllerClass)) ?: @"none",
        @"inheritsItemsDataViewController":
            @(itemsControllerClass &&
              [controllerClass isSubclassOfClass:itemsControllerClass]),
        @"dataViewControllerAccessorPresent":
            @([controllerClass instancesRespondToSelector:
                  NSSelectorFromString(@"dataViewController")]),
        @"dataViewControllerIvarPresent":
            @(class_getInstanceVariable(
                  controllerClass, "_dataViewController") != NULL ||
              class_getInstanceVariable(
                  controllerClass, "dataViewController") != NULL),
        @"timelineMethods":
            [[methods allObjects]
                sortedArrayUsingSelector:
                    @selector(localizedCaseInsensitiveCompare:)],
        @"timelineIvars": [ivars copy],
        @"renderCallbacks": @{
            @"tableViewCellForItem":
                @([controllerClass instancesRespondToSelector:
                      NSSelectorFromString(
                          @"tableViewCellForItem:atIndexPath:")]),
            @"rowHeight":
                @([controllerClass instancesRespondToSelector:
                      NSSelectorFromString(
                          @"tableView:heightForRowAtIndexPath:")]),
            @"estimatedRowHeight":
                @([controllerClass instancesRespondToSelector:
                      NSSelectorFromString(
                          @"tableView:estimatedHeightForRowAtIndexPath:")]),
            @"itemRowHeight":
                @([controllerClass instancesRespondToSelector:
                      NSSelectorFromString(
                          @"tableViewHeightForItem:atIndexPath:")]),
            @"estimatedItemRowHeight":
                @([controllerClass instancesRespondToSelector:
                      NSSelectorFromString(
                          @"estimatedTableViewHeightForItem:atIndexPath:")]),
            @"itemAtIndexPath":
                @([controllerClass instancesRespondToSelector:
                      NSSelectorFromString(@"itemAtIndexPath:")]),
        },
        @"filterExecutionPolicy":
            @"verified_urt_role_section_then_exact_urt_item_height_fallback",
        @"unknownSectionOwnerFailsOpen": @YES,
    };
}

static NSDictionary* BHTForYouFilterDiagnosticSnapshot(void) {
    NSArray<NSString*>* names = @[
        @"primaryControllerChecks",
        @"nonForYouControllerChecks",
        @"unknownControllerChecks",
        @"ownerMissingChecks",
        @"directOwnerResolvedChecks",
        @"directOwnerMissingChecks",
        @"nonHomeControllerChecks",
        @"timelineObjectResolvedChecks",
        @"timelineObjectMissingChecks",
        @"missingStatusItems",
        @"trustedTextCandidateSetsNonEmpty",
        @"mentionHandleCandidatesExtracted",
        @"decisionCacheHits",
        @"usernameMatches",
        @"postTextMatches",
        @"noMatches",
        @"renderRowCollapses",
        @"renderReloads",
    ];
    NSMutableDictionary* snapshot =
        [NSMutableDictionary dictionaryWithCapacity:names.count];
    [names enumerateObjectsUsingBlock:^(
               NSString* name, NSUInteger index, BOOL* stop) {
        snapshot[name] =
            @(atomic_load_explicit(
                &BHTForYouFilterDiagnosticCounters[index],
                memory_order_relaxed));
    }];
    snapshot[@"controllerRuntimeShape"] =
        BHTForYouControllerRuntimeShape();
    return [snapshot copy];
}

static NSArray<NSString*>* BHTNavigationEntryClassSnapshot(void) {
    @synchronized(BHTObservationLock()) {
        return [BHTNavigationEntryClasses copy] ?: @[];
    }
}

static NSDictionary* BHTTimelineRuntimeShape(id item) {
    NSMutableArray<NSString*>* selectors = [NSMutableArray array];
    for (NSString* name in @[
             @"isPromoted", @"isAd", @"isAdvertisement", @"isSponsored",
             @"status", @"tweet", @"twitterStatus", @"displayedStatus",
             @"scribeItem", @"scribeParameters", @"promotedContent",
             @"promotedMetadata", @"adMetadata"
         ]) {
        if ([item respondsToSelector:NSSelectorFromString(name)]) {
            [selectors addObject:name];
        }
    }

    NSMutableArray<NSDictionary*>* ivars = [NSMutableArray array];
    for (Class current = [item class]; current && current != NSObject.class;
         current = class_getSuperclass(current)) {
        unsigned int count = 0;
        Ivar* list = class_copyIvarList(current, &count);
        for (unsigned int index = 0; index < count; index++) {
            const char* rawName = ivar_getName(list[index]);
            NSString* name = rawName ? [NSString stringWithUTF8String:rawName] : @"";
            NSString* lower = name.lowercaseString;
            if (!([lower containsString:@"status"] ||
                  [lower containsString:@"tweet"] ||
                  [lower containsString:@"promoted"] ||
                  [lower containsString:@"advert"] ||
                  [lower containsString:@"scribe"] ||
                  [lower containsString:@"model"] ||
                  [lower containsString:@"content"])) {
                continue;
            }
            const char* type = ivar_getTypeEncoding(list[index]);
            NSString* valueClass = @"";
            if (type && type[0] == '@') {
                id value = object_getIvar(item, list[index]);
                if (value) valueClass = NSStringFromClass([value classForCoder]);
            }
            [ivars addObject:@{
                @"name": name,
                @"type": type ? [NSString stringWithUTF8String:type] : @"",
                @"valueClass": valueClass ?: @""
            }];
        }
        free(list);
    }
    return @{@"selectors": selectors, @"ivars": ivars};
}

void BHTRecordTimelineItemObservation(id item, NSString* location, BOOL hidden) {
    if (!item) return;
    NSString* className = NSStringFromClass([item classForCoder]);
    if (className.length == 0) return;

    @synchronized(BHTObservationLock()) {
        if (!BHTTimelineItemObservations) {
            BHTTimelineItemObservations = [NSMutableDictionary dictionary];
        }
        NSMutableDictionary* observation =
            BHTTimelineItemObservations[className];
        if (!observation) {
            observation = [@{
                @"seen": @0,
                @"hidden": @0,
                @"locations": [NSMutableSet set],
                @"runtimeShape": BHTTimelineRuntimeShape(item)
            } mutableCopy];
            BHTTimelineItemObservations[className] = observation;
        }
        observation[@"seen"] =
            @([observation[@"seen"] unsignedIntegerValue] + 1);
        if (hidden) {
            observation[@"hidden"] =
                @([observation[@"hidden"] unsignedIntegerValue] + 1);
        }
        if (location.length > 0) {
            [(NSMutableSet*)observation[@"locations"] addObject:location];
        }
    }
}

static NSDictionary* BHTTimelineObservationSnapshot(void) {
    NSMutableDictionary* snapshot = [NSMutableDictionary dictionary];
    @synchronized(BHTObservationLock()) {
        [BHTTimelineItemObservations
            enumerateKeysAndObjectsUsingBlock:^(
                NSString* className, NSMutableDictionary* observation,
                BOOL* stop) {
                snapshot[className] = @{
                    @"seen": observation[@"seen"] ?: @0,
                    @"hidden": observation[@"hidden"] ?: @0,
                    @"locations":
                        [[(NSSet*)observation[@"locations"] allObjects]
                            sortedArrayUsingSelector:
                                @selector(localizedCaseInsensitiveCompare:)],
                    @"runtimeShape": observation[@"runtimeShape"] ?: @{}
                };
            }];
    }
    return [snapshot copy];
}

void BHTRecordRailBrandingObservation(NSString* resolution,
                                      UIView* hostView,
                                      UIImageView* logoView,
                                      NSUInteger candidateCount) {
    if (!hostView) return;
    NSString* resolved = resolution ?: @"unresolved";
    CGRect logoFrame =
        logoView ? [logoView convertRect:logoView.bounds toView:hostView]
                 : CGRectNull;
    UIEdgeInsets safeAreaInsets = hostView.safeAreaInsets;
    BOOL birdApplied =
        [logoView.accessibilityLabel isEqualToString:@"Twitter"];
    BHTRailBrandingObservationState* state =
        objc_getAssociatedObject(
            hostView, &kBHTRailBrandingObservationStateKey);
    if (!state) {
        state = [BHTRailBrandingObservationState new];
        objc_setAssociatedObject(
            hostView, &kBHTRailBrandingObservationStateKey, state,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // Rail layout can run alongside timeline scrolling. Avoid allocating
    // frame strings and dictionaries unless the compatibility state actually
    // changed.
    BOOL unchanged =
        state.logoView == logoView &&
        [state.resolution isEqualToString:resolved] &&
        CGRectEqualToRect(state.hostBounds, hostView.bounds) &&
        CGRectEqualToRect(state.logoFrame, logoFrame) &&
        UIEdgeInsetsEqualToEdgeInsets(state.safeAreaInsets,
                                     safeAreaInsets) &&
        state.candidateCount == candidateCount &&
        state.birdApplied == birdApplied;
    if (unchanged) return;

    state.logoView = logoView;
    state.resolution = resolved;
    state.hostBounds = hostView.bounds;
    state.logoFrame = logoFrame;
    state.safeAreaInsets = safeAreaInsets;
    state.candidateCount = candidateCount;
    state.birdApplied = birdApplied;

    NSDictionary* observation = @{
        @"resolution": resolved,
        @"hostClass": NSStringFromClass(hostView.class) ?: @"",
        @"hostBounds": NSStringFromCGRect(hostView.bounds),
        @"safeAreaInsets": NSStringFromUIEdgeInsets(safeAreaInsets),
        @"candidateCount": @(candidateCount),
        @"logoClass":
            logoView ? (NSStringFromClass(logoView.class) ?: @"") : @"",
        @"logoFrame":
            logoView ? NSStringFromCGRect(logoFrame) : @"",
        @"birdApplied": @(birdApplied)
    };
    @synchronized(BHTObservationLock()) {
        BHTRailBrandingObservation = observation;
    }
}

static NSDictionary* BHTRailBrandingObservationSnapshot(void) {
    @synchronized(BHTObservationLock()) {
        return [BHTRailBrandingObservation copy] ?: @{};
    }
}

void BHTRecordThemeRuntimeObservation(
    NSString* presetIdentifier,
    NSString* paletteClass,
    BOOL darkAppearance,
    NSArray<NSString*>* installedGetterNames,
    NSUInteger refreshAttempts,
    NSUInteger configurationGeneration,
    NSUInteger seenPaletteCount,
    NSArray<NSString*>* providerClasses,
    BOOL applyCurrentColorPaletteUsed,
    NSArray<NSString*>* t1RefreshSelectorsUsed,
    BOOL paletteSetterFallbackUsed,
    BOOL dynamicColorsDidReloadObserved,
    NSUInteger visibleViewsVisited,
    NSUInteger dynamicColorViewsUpdated) {
    // Class/selector names and aggregate counters are intentionally the only
    // runtime data recorded here. No view text, account state, URLs, or other
    // user content enters the compatibility report.
    NSArray<NSString*>* getters =
        [installedGetterNames isKindOfClass:NSArray.class]
            ? [installedGetterNames sortedArrayUsingSelector:
                                        @selector(compare:)]
            : @[];
    NSArray<NSString*>* refreshSelectors =
        [t1RefreshSelectorsUsed isKindOfClass:NSArray.class]
            ? [t1RefreshSelectorsUsed sortedArrayUsingSelector:
                                         @selector(compare:)]
            : @[];
    NSArray<NSString*>* providers =
        [providerClasses isKindOfClass:NSArray.class]
            ? [providerClasses sortedArrayUsingSelector:
                                  @selector(compare:)]
            : @[];
    NSString* reportedPreset =
        [BHTThemePresets isUserPresetIdentifier:presetIdentifier]
            ? @"user_theme"
            : (presetIdentifier.length > 0
                   ? presetIdentifier
                   : @"native");
    NSDictionary* observation = @{
        // Custom names and persistent UUIDs are private user data.
        @"activePreset": reportedPreset,
        @"activePaletteClass": paletteClass.length > 0
            ? paletteClass
            : @"unavailable",
        @"darkAppearance": @(darkAppearance),
        @"installedGetterCount": @(getters.count),
        @"installedGetters": getters,
        @"refreshAttempts": @(refreshAttempts),
        @"configurationGeneration":
            @(configurationGeneration),
        @"seenPaletteCount": @(seenPaletteCount),
        @"providerClasses": providers,
        @"applyCurrentColorPaletteUsed":
            @(applyCurrentColorPaletteUsed),
        @"t1RefreshSelectorsUsed": refreshSelectors,
        @"paletteSetterFallbackUsed":
            @(paletteSetterFallbackUsed),
        @"dynamicColorsDidReloadObserved":
            @(dynamicColorsDidReloadObserved),
        @"visibleViewsVisited": @(visibleViewsVisited),
        @"dynamicColorViewsUpdated":
            @(dynamicColorViewsUpdated)
    };
    @synchronized(BHTObservationLock()) {
        BHTThemeRuntimeObservation = observation;
    }
}

static NSDictionary* BHTThemeRuntimeObservationSnapshot(void) {
    @synchronized(BHTObservationLock()) {
        return [BHTThemeRuntimeObservation copy] ?: @{};
    }
}

void BHTRecordMediaActionObservation(NSString* stage,
                                     NSString* kind,
                                     NSUInteger originalCount,
                                     NSUInteger configuredCount,
                                     NSUInteger mediaEntityCount) {
    if (stage.length == 0) return;
    @synchronized(BHTObservationLock()) {
        if (!BHTMediaActionObservations) {
            BHTMediaActionObservations =
                [NSMutableDictionary dictionary];
        }
        NSMutableDictionary* observation =
            BHTMediaActionObservations[stage];
        if (!observation) {
            observation = [NSMutableDictionary dictionary];
            BHTMediaActionObservations[stage] = observation;
        }
        observation[@"hits"] =
            @([observation[@"hits"] unsignedIntegerValue] + 1);
        observation[@"kind"] = kind ?: @"unknown";
        observation[@"originalCount"] = @(originalCount);
        observation[@"configuredCount"] = @(configuredCount);
        observation[@"mediaEntityCount"] = @(mediaEntityCount);

        NSString* safeKind = kind.length > 0 ? kind : @"unknown";
        NSMutableDictionary* byKind = observation[@"byKind"];
        if (!byKind) {
            byKind = [NSMutableDictionary dictionary];
            observation[@"byKind"] = byKind;
        }
        NSMutableDictionary* kindObservation = byKind[safeKind];
        if (!kindObservation) {
            kindObservation = [NSMutableDictionary dictionary];
            byKind[safeKind] = kindObservation;
        }
        kindObservation[@"hits"] =
            @([kindObservation[@"hits"] unsignedIntegerValue] + 1);
        kindObservation[@"originalCount"] = @(originalCount);
        kindObservation[@"configuredCount"] = @(configuredCount);
        kindObservation[@"mediaEntityCount"] = @(mediaEntityCount);
    }
}

static NSDictionary* BHTMediaActionObservationSnapshot(void) {
    NSMutableDictionary* snapshot =
        [NSMutableDictionary dictionary];
    @synchronized(BHTObservationLock()) {
        [BHTMediaActionObservations
            enumerateKeysAndObjectsUsingBlock:^(
                NSString* stage, NSMutableDictionary* observation,
                BOOL* stop) {
                NSMutableDictionary* stageSnapshot =
                    [observation mutableCopy];
                NSDictionary* byKind = observation[@"byKind"];
                if (byKind) {
                    NSMutableDictionary* kindSnapshot =
                        [NSMutableDictionary dictionary];
                    [byKind enumerateKeysAndObjectsUsingBlock:^(
                                NSString* kind,
                                NSDictionary* kindObservation,
                                BOOL* innerStop) {
                        kindSnapshot[kind] = [kindObservation copy];
                    }];
                    stageSnapshot[@"byKind"] = [kindSnapshot copy];
                }
                snapshot[stage] = [stageSnapshot copy];
            }];
    }
    return [snapshot copy];
}

static NSArray<NSString*>* BHTInterestingMethodsForClass(Class cls) {
    if (!cls) return @[];
    NSMutableOrderedSet<NSString*>* names = [NSMutableOrderedSet orderedSet];
    for (Class current = cls; current && current != NSObject.class;
         current = class_getSuperclass(current)) {
        unsigned int count = 0;
        Method* methods = class_copyMethodList(current, &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString* name = NSStringFromSelector(method_getName(methods[i]));
            NSString* lower = name.lowercaseString;
            if ([lower containsString:@"tab"] ||
                [lower containsString:@"panel"] ||
                [lower containsString:@"select"] ||
                [lower containsString:@"tap"] ||
                [lower containsString:@"press"] ||
                [lower containsString:@"activate"] ||
                [lower containsString:@"navigation"] ||
                [lower containsString:@"visible"] ||
                [name isEqualToString:@"contentControllerFactory"] ||
                [name isEqualToString:@"createContentController"] ||
                [name isEqualToString:@"rootTabViewController"]) {
                [names addObject:name];
            }
        }
        free(methods);
    }
    return [[names array]
        sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

static NSDictionary* BHTNavigationMethodSnapshot(void) {
    NSMutableDictionary* fixed = [NSMutableDictionary dictionary];
    for (NSString* className in @[
             @"T1TabView", @"T1TabBarViewController",
             @"T1TabbedAppNavigationViewController"
         ]) {
        fixed[className] =
            BHTInterestingMethodsForClass(NSClassFromString(className));
    }

    NSMutableDictionary* entries = [NSMutableDictionary dictionary];
    for (NSString* className in BHTNavigationEntryClassSnapshot()) {
        entries[className] =
            BHTInterestingMethodsForClass(NSClassFromString(className));
    }
    return @{@"navigationClasses": fixed, @"entryClasses": entries};
}

NSURL* BHTCompatibilityReportURL(void) {
    NSURL* caches = [[[NSFileManager defaultManager]
        URLsForDirectory:NSCachesDirectory
               inDomains:NSUserDomainMask] firstObject];
    return [caches URLByAppendingPathComponent:@"BHTwitter-X12.9-Compatibility.json"];
}

static NSDictionary* BHTProbe(NSString* feature, NSString* className,
                              NSString* selectorName, BOOL classMethod) {
    Class cls = NSClassFromString(className);
    SEL selector = NSSelectorFromString(selectorName);
    BOOL methodPresent = classMethod ? [cls respondsToSelector:selector]
                                     : [cls instancesRespondToSelector:selector];
    return @{
        @"feature": feature,
        @"class": className,
        @"selector": selectorName,
        @"kind": classMethod ? @"class" : @"instance",
        @"classPresent": @(cls != Nil),
        @"methodPresent": @(cls != Nil && methodPresent)
    };
}

static NSArray* BHTRuntimeProbes(void) {
    return @[
        BHTProbe(@"ads", @"TFNItemsDataViewAdapterRegistry", @"dataViewAdapterForItem:", NO),
        BHTProbe(@"ads", @"TFNTwitterAPICommandContext", @"allowPromotedContent", NO),
        BHTProbe(@"ads", @"TFNItemsDataViewController", @"setSections:restoreScrollPosition:", NO),
        BHTProbe(@"ads", @"TFNItemsDataViewController", @"updateSections:reconfigureItemIdentifiers:withRowAnimation:completion:", NO),
        BHTProbe(@"ads", @"TFNItemsDataViewController", @"itemAtIndexPath:", NO),
        BHTProbe(@"ads", @"TFNItemsDataViewController", @"tableViewCellForItem:atIndexPath:", NO),
        BHTProbe(@"ads", @"TFNItemsDataViewController", @"tableView:heightForRowAtIndexPath:", NO),
        BHTProbe(@"ads", @"T1URTTimelineStatusItemViewModel", @"isPromoted", NO),
        BHTProbe(@"ads", @"T1URTTimelineStatusItemViewModel", @"status", NO),
        BHTProbe(@"ads", @"TwitterURT.URTTimelineGoogleNativeAdViewModel", @"init", NO),
        BHTProbe(@"ads", @"T1TwitterSwift.GoogleNativeAdCell", @"preferredLayoutAttributesFittingAttributes:", NO),
        BHTProbe(@"ads", @"UICollectionViewCell", @"preferredLayoutAttributesFittingAttributes:", NO),
        BHTProbe(@"ads", @"TwitterURT.PromotableTrend", @"promotedTrendID", NO),
        BHTProbe(@"ads", @"T1TwitterSwift.ImmersiveGoogleNativeAdCardViewModel", @"init", NO),
        BHTProbe(@"ads", @"T1TwitterSwift.ExplorePromotedViewModel", @"init", NO),
        BHTProbe(@"ads", @"T1PlayerMediaEntitySessionProducible", @"mediaEntity", NO),
        BHTProbe(@"ads", @"T1PlayerMediaEntitySessionProducible", @"initWithMediaEntity:contentMediaIdentifier:ownerIdentifier:baseScribeItem:promotedContent:", NO),
        BHTProbe(@"ads", @"TFSTwitterSspMetadata", @"isPrerollEligible", NO),
        BHTProbe(@"ads", @"TFSTwitterSspMetadata", @"adTagURL", NO),
        BHTProbe(@"ads", @"TFNTwitterStatus", @"allowDynamicAd", NO),
        BHTProbe(@"ads", @"TFNTwitterStatus", @"isAdsVideoCard", NO),
        BHTProbe(@"ads", @"T1StatusTableSlideshowManager", @"_t1_isPromotedTweetMediaDisabledInMultiStatusSlideshow", NO),

        BHTProbe(@"images", @"T1ImageDisplayView", @"_tfn_shouldUseHighestQualityImage", NO),
        BHTProbe(@"images", @"T1ImageDisplayView", @"_tfn_shouldUseHighQualityImage", NO),
        BHTProbe(@"images", @"T1SlideshowViewController", @"_t1_shouldDisplayLoadHighQualityImageItemForImageDisplayView:highestQuality:", NO),
        BHTProbe(@"images", @"T1StandardStatusAttachmentViewAdapter", @"displayType", NO),
        BHTProbe(@"images", @"TFNTwitterAccount", @"isLoadingHighestQualityImageVariantPermitted", NO),
        BHTProbe(@"images", @"TFNTwitterAccount", @"photoUploadHighQualityImagesSettingIsVisible", NO),
        BHTProbe(@"images", @"TFNTwitterAccount", @"isDoubleMaxZoomFor4KImagesEnabled", NO),
        BHTProbe(@"video", @"TFSTwitterEntityMediaVideoInfo", @"variants", NO),
        BHTProbe(@"video", @"TFSTwitterEntityMediaVideoInfo", @"primaryUrl", NO),
        BHTProbe(@"video", @"TFSTwitterEntityMedia", @"allowDownload", NO),
        BHTProbe(@"video", @"T1VideoDownloadViewModel", @"urlIfCanDownloadWithAccount:mediaEntity:", YES),
        BHTProbe(@"video", @"T1VideoDownloadViewModel", @"makeVideDownloaderWithAccount:fromViewController:mediaEntity:statusViewModel:scribeContext:", YES),
        BHTProbe(@"video", @"T1VideoDownloadViewModel", @"tappedDownload", NO),
        BHTProbe(@"video", @"T1TwitterSwift.VideoControlsView", @"init", NO),
        BHTProbe(@"video", @"TweetMediaAttachments.MultiMediaView", @"inlineMediaInfos", NO),
        BHTProbe(@"video", @"TweetMediaAttachments.MultiMediaCarouselView", @"inlineMediaInfos", NO),
        BHTProbe(@"video", @"T1InlineMediaView", @"viewModel", NO),
        BHTProbe(@"mediaActions", @"UIViewController", @"t1_mediaActivityViewActionItemsForStatus:account:image:mediaInfo:shortTitles:sourceView:", NO),
        BHTProbe(@"mediaActions", @"UIViewController", @"t1_mediaActivityViewActionItemsForStatus:account:image:mediaInfo:shortTitles:", NO),
        BHTProbe(@"mediaActions", @"UIViewController", @"_t1_actionItemsForStatus:account:shareableEntity:entityURL:source:options:scribeComponent:doneBlock:", NO),
        BHTProbe(@"mediaActions", @"TFNPreviewConfiguration", @"configurationWithPreviewViewControllerBlock:actionItems:sourceView:sourceRect:", YES),
        BHTProbe(@"mediaActions", @"TFNMenuSheetViewController", @"initWithTitle:actionItems:", NO),
        BHTProbe(@"mediaActions", @"TFNMenuSheetViewController", @"tfnPresentedCustomPresentFromViewController:animated:completion:", NO),

        BHTProbe(@"dmDownloads", @"DMConversation.MessageAttachmentView", @"layoutSubviews", NO),
        BHTProbe(@"dmDownloads", @"DMConversation.MessageSaveActionPlugin", @"init", NO),
        BHTProbe(@"dmDownloads", @"TweetMediaAttachments.MultiMediaView", @"inlineMediaInfos", NO),
        BHTProbe(@"messages", @"_TtC14DMConversation26ConversationViewController", @"viewDidLoad", NO),

        BHTProbe(@"likes", @"T1ActivityHistoryBridge", @"makeActivityHistoryViewControllerWithAccount:initialTab:", YES),
        BHTProbe(@"likes", @"T1URTFavoritesViewControllerFactory", @"makeViewControllerWithAccount:", YES),
        BHTProbe(@"likes", @"T1URTFavoritesViewControllerFactory", @"viewControllerWithAccount:", YES),
        BHTProbe(@"likes", @"T1TabbedAppNavigationViewController", @"setVisibleTabEntries:", NO),
        BHTProbe(@"likes", @"T1TabbedAppNavigationViewController", @"recalculateVisiblePanels", NO),
        BHTProbe(@"likes", @"T1TabView", @"scribePage", NO),
        BHTProbe(@"likes", @"T1TabView", @"setSelected:", NO),
        BHTProbe(@"likes", @"T1TabView", @"_t1_updateTitleLabel", NO),
        BHTProbe(@"likes", @"T1TabView", @"_t1_updateImageViewAnimated:", NO),
        BHTProbe(@"likes", @"T1TwitterSwift.GrokAppNavigationTabEntry", @"rootTabViewController", NO),

        BHTProbe(@"sourceLabels", @"TFNTwitterStatus", @"composerSource", NO),
        BHTProbe(@"sourceLabels", @"T1ConversationFooterTextView", @"updateFooterTextView", NO),
        BHTProbe(@"sourceLabels", @"T1ConversationFooterTextView", @"viewModel", NO),

        BHTProbe(@"home", @"HomeTimelineContainerViewController", @"pinnedTimelinesRepository:didChangeWithPinnedTimelineModels:", NO),
        BHTProbe(@"home", @"TwitterHomeFeatureImplementation.HomeTimelineContainerViewController", @"pinnedTimelinesRepository:didChangeWithPinnedTimelineModels:", NO),
        BHTProbe(@"home", @"TwitterHomeFeatureImplementation.HomeTimelineContainerViewController", @"tfn_supportsTabBarCollapsing", NO),
        BHTProbe(@"home", @"T1TabBarViewController", @"tfn_prefersTabBarPinned", NO),
        BHTProbe(@"forYouFilters", @"T1TimelineFactory", @"homeTimelineForAccount:", NO),
        BHTProbe(@"forYouFilters", @"T1TimelineFactory", @"homeCountryFilteredTimelineForAccount:", NO),
        BHTProbe(@"forYouFilters", @"T1TimelineFactory", @"homeTopicFilteredTimelineForAccount:", NO),
        BHTProbe(@"forYouFilters", @"T1TimelineFactory", @"homeLatestTimelineForAccount:", NO),
        BHTProbe(@"forYouFilters", @"T1TimelineFactory", @"homeRankedFollowingTimelineForAccount:", NO),
        BHTProbe(@"forYouFilters", @"T1TimelineFactory", @"rootViewControllerForHomeTimeline:homeCountryFilteredTimeline:homeLatestTimeline:homeRankedFollowingTimeline:account:", NO),
        BHTProbe(@"forYouFilters", @"TFNTwitterHomeTimeline", @"deserializeStream", NO),
        BHTProbe(@"forYouFilters", @"T1URTViewController", @"adDisplayLocation", NO),
        BHTProbe(@"forYouFilters", @"T1URTViewController", @"urtTimeline", NO),
        BHTProbe(@"forYouFilters", @"T1URTTimelineStatusItemViewModel", @"tweet", NO),
        BHTProbe(@"forYouFilters", @"TFNTwitterStatus", @"representedStatus", NO),
        BHTProbe(@"forYouFilters", @"TFNTwitterStatus", @"retweetedStatus", NO),
        BHTProbe(@"forYouFilters", @"TFNTwitterStatus", @"fullText", NO),
        BHTProbe(@"forYouFilters", @"TFNTwitterStatus", @"fromUserName", NO),
        BHTProbe(@"forYouFilters", @"TFNTwitterStatus", @"fromUserFullName", NO),
        BHTProbe(@"appearance", @"T1TabBarHostView", @"logoImageView", NO),
        BHTProbe(@"appearance", @"T1TabBarHostView", @"tabBarViewController", NO),
        BHTProbe(@"home", @"T1FleetLineHeaderController", @"_t1_shouldShowFleetLine", NO),
        BHTProbe(@"home", @"TUIUpdateIndicator", @"_recreatePillControlForContentNotification:hideOnScroll:", NO),
        BHTProbe(@"appearance", @"TwitterHome.HomeDefaultNavigationBarTitleViewPlugin", @"titleView", NO),
        BHTProbe(@"appearance", @"T1AnimatedLaunchScreenView", @"layoutSubviews", NO),
        BHTProbe(@"appearance", @"T1AnimatedLaunchScreenView", @"animateRevealWithCompletion:", NO),
        BHTProbe(@"appearance", @"TAEColorSettings", @"currentColorPalette", NO),
        BHTProbe(@"appearance", @"TAEColorSettings", @"setCurrentColorPalette:", NO),
        BHTProbe(@"appearance", @"TAEColorSettings", @"applyCurrentColorPalette", NO),
        BHTProbe(@"appearance", @"T1ColorSettings", @"_t1_applyTheme", YES),
        BHTProbe(@"appearance", @"T1ColorSettings", @"_t1_applyPrimaryColorOption", YES),
        BHTProbe(@"appearance", @"T1ColorSettings", @"_t1_updateOverrideUserInterfaceStyle", YES),
        BHTProbe(@"appearance", @"UIView", @"_t1_updateDynamicColors", NO),
        BHTProbe(@"appearance", @"UIColor", @"twitterColors", YES),
        BHTProbe(@"appearance", @"UIColor", @"setTwitterColors:", YES),
        BHTProbe(@"appearance", @"UIColor", @"tfnuiColors", YES),
        BHTProbe(@"appearance", @"UIColor", @"xds_backgroundPrimary", YES),
        BHTProbe(@"appearance", @"UIColor", @"xds_backgroundSheets", YES),
        BHTProbe(@"appearance", @"UIColor", @"xds_foregroundPrimary", YES),
        BHTProbe(@"appearance", @"UIColor", @"xds_borderNormal", YES),
        BHTProbe(@"appearance", @"UIColor", @"colorNamed:inBundle:compatibleWithTraitCollection:", YES),
        BHTProbe(@"appearance", @"T1TabBarViewController", @"nativeTabBar", NO),
        BHTProbe(@"appearance", @"T1TabBarViewController", @"tabBarBackgroundView", NO),
        BHTProbe(@"appearance", @"T1TabBarViewController", @"tabBarDivider", NO),
        BHTProbe(@"appearance", @"T1TabBarViewController", @"_t1_configureNativeTabBar", NO),
        BHTProbe(@"home", @"T1TwitterSwift.URTTimelineTopicCollectionViewModel", @"init", NO),

        BHTProbe(@"search", @"TTSRecentSearchesDatastore", @"_tse_setRecentSearch:", NO),
        BHTProbe(@"search", @"TTSRecentSearchesDatastore", @"recentSearches", NO),
        BHTProbe(@"search", @"T1TwitterSwift.GuideContainerViewController", @"viewDidLoad", NO),

        BHTProbe(@"profiles", @"T1ProfileHeaderViewController", @"actionButtonProviders", NO),
        BHTProbe(@"profiles", @"T1ProfileFriendsFollowingViewModel", @"_t1_followCountTextWithLabel:singularLabel:count:highlighted:", NO),
        BHTProbe(@"profiles", @"TFNTwitterCanonicalUser", @"isProfileBioTranslatable", NO),
        BHTProbe(@"profiles", @"TFNTwitterCanonicalUser", @"isProfileTranslationEnabled", NO),
        BHTProbe(@"profiles", @"TTAStatusAuthorView", @"setFollowControlHidden:", NO),
        BHTProbe(@"profiles", @"TFSTwitterRelationship", @"superFollowEligibleState", NO),

        BHTProbe(@"confirmations", @"TTAStatusInlineActionButton", @"didTap", NO),
        BHTProbe(@"appearance", @"TFNUIDefaultFontGroup", @"sharedFontGroup", YES),
        BHTProbe(@"appearance", @"XFontCatalog", @"fontForToken:", YES),
        BHTProbe(@"appearance", @"XFontCatalog", @"customFontOfSize:weight:scalesWithDynamicType:", YES),

        BHTProbe(@"sidebar", @"T1DashContentController", @"updateVisiblePanelIDs", NO),
        BHTProbe(@"sidebar", @"T1DashNavigationViewFactory", @"buildDashViewControllerForAccount:dashContentController:", YES),

        BHTProbe(@"badges", @"TFSTwitterUser", @"isBlueVerified", NO),
        BHTProbe(@"badges", @"TFSTwitterUserSource", @"isBlueVerified", NO),
        BHTProbe(@"badges", @"TFSTwitterTypeaheadUser", @"isBlueVerified", NO),
        BHTProbe(@"badges", @"TFSDirectMessageUser", @"isBlueVerified", NO),
        BHTProbe(@"badges", @"T1TwitterCoreStatusViewModelAdapter", @"isFromUserBlueVerified", NO),

        BHTProbe(@"grok", @"GrokAnalyzeButtonManager", @"init", NO),
        BHTProbe(@"grok", @"TTAStatusInlineAnalyticsButton", @"init", NO),
        BHTProbe(@"grok", @"T1StatusPhotoEditorHandler", @"photoEditorCanEditWithGrok:", NO),

        BHTProbe(@"settings", @"T1GenericSettingsViewController", @"viewWillAppear:", NO),
        BHTProbe(@"settings", @"TFSFeatureSwitches", @"boolForKey:", NO),
        BHTProbe(@"settings", @"TFSInstrumentedFeatureSwitches", @"boolForKey:", NO),

        BHTProbe(@"replyWorkflow", @"TTAStatusInlineReplyButton", @"didTap", NO),
        BHTProbe(@"replyWorkflow", @"T1StatusViewInlineActionTapEventHandler", @"performReplyActionWithAccount:event:controller:scribeContext:scribeElement:parameters:originalStatus:", NO),
        BHTProbe(@"replyWorkflow", @"T1TweetComposeViewController", @"viewDidAppear:", NO),
        BHTProbe(@"replyWorkflow", @"T1TweetComposeViewController", @"_t1_didTapSendButton:", NO),
        BHTProbe(@"replyWorkflow", @"T1TweetComposeViewController", @"_tweetButtonTapped:", NO),
        BHTProbe(@"replyWorkflow", @"T1TweetComposeViewController", @"_t1_main_sendTweet", NO),
        BHTProbe(@"replyWorkflow", @"T1TweetComposeViewController", @"_t1_checkForValidTweetsAndSend", NO),
        BHTProbe(@"replyWorkflow", @"T1TweetComposeViewController", @"_t1_sendCompositions:", NO),
        BHTProbe(@"replyWorkflow", @"T1TweetComposeViewController", @"_t1_sendReply", NO),
        BHTProbe(@"replyWorkflow", @"T1TweetComposeViewController", @"_t1_compositionDidSend:", NO),
        BHTProbe(@"replyWorkflow", @"T1TweetComposeViewController", @"didFailToSendComposition:", NO),
        BHTProbe(@"replyWorkflow", @"T1TweetComposeViewController", @"viewDidDisappear:", NO),
        BHTProbe(@"replyWorkflow", @"T1PersistentComposeViewController", @"statusViewModel", NO),
        BHTProbe(@"replyWorkflow", @"T1PersistentComposeViewController", @"viewDidAppear:", NO),
        BHTProbe(@"replyWorkflow", @"T1ComposePresenter", @"showComposerWithSessionConfig:", NO),
        BHTProbe(@"replyWorkflow", @"T1ComposePresenter", @"presentComposer", NO),
        BHTProbe(@"replyWorkflow", @"T1TweetComposeReplyContextViewController", @"setReplyToStatus:", NO),
        BHTProbe(@"replyWorkflow", @"T1TweetComposeReplyContextViewController", @"setReplyToStatusInfo:", NO),
        BHTProbe(@"nativeReplyNetwork", @"NSURLSession", @"dataTaskWithRequest:", NO),
        BHTProbe(@"nativeReplyNetwork", @"NSURLSession", @"dataTaskWithRequest:completionHandler:", NO),
        BHTProbe(@"nativeReplyNetwork", @"NSURLSession", @"uploadTaskWithRequest:fromData:", NO),
        BHTProbe(@"nativeReplyNetwork", @"NSURLSession", @"uploadTaskWithRequest:fromData:completionHandler:", NO),
        BHTProbe(@"nativeReplyNetwork", @"NSURLSession", @"uploadTaskWithRequest:fromFile:", NO),
        BHTProbe(@"nativeReplyNetwork", @"NSURLSession", @"uploadTaskWithRequest:fromFile:completionHandler:", NO),
        BHTProbe(@"nativeReplyNetwork", @"TNLURLSessionTaskOperation", @"_network_finalizeDidCompleteTask:URLSession:error:", NO),
        BHTProbe(@"nativeReplyNetwork", @"TNLURLSessionTaskOperation", @"URLSession:task:didCompleteWithError:", NO),
        BHTProbe(@"nativeReplyApplication", @"_TtC14GraphQLActions23GraphQLEndpointResponse", @"modelWithParseError:APIErrors:", NO),
        BHTProbe(@"nativeReplyApplication", @"_TtC14GraphQLActions23GraphQLEndpointResponse", @"prepare", NO),
        BHTProbe(@"nativeReplyApplication", @"_TtC14GraphQLActions23GraphQLEndpointResponse", @"originalRequest", NO),
        BHTProbe(@"nativeReplyApplication", @"_TtC14GraphQLActions23GraphQLEndpointResponse", @"model", NO),
        BHTProbe(@"nativeReplyApplication", @"_TtC14GraphQLActions23GraphQLEndpointResponse", @"parseError", NO),
        BHTProbe(@"nativeReplyApplication", @"_TtC14GraphQLActions23GraphQLEndpointResponse", @"operationError", NO),
        BHTProbe(@"nativeReplyApplication", @"_TtC14GraphQLActions23GraphQLEndpointResponse", @"APIErrors", NO),
        BHTProbe(@"nativeReplyApplication", @"_TtC14GraphQLActions23GraphQLEndpointResponse", @"finalModel", NO),
        BHTProbe(@"nativeReplyApplication", @"_TtC14GraphQLActions23GraphQLEndpointResponse", @"finalParseError", NO),
        BHTProbe(@"nativeReplyApplication", @"_TtC14GraphQLActions23GraphQLEndpointResponse", @"finalOperationError", NO),
        BHTProbe(@"nativeReplyApplication", @"_TtC14GraphQLActions23GraphQLEndpointResponse", @"finalAPIErrors", NO),
        BHTProbe(@"nativeReplyApplication", @"TFSAPIRequest", @"URL", NO),
        BHTProbe(@"webReplyAccountBound", @"T1WebViewController", @"initWithRootURL:account:shouldAuthenticate:shouldPresentAsNativePage:sourceStatus:scribeComponent:scribeParameters:", NO),
        BHTProbe(@"webReplyAccountBound", @"T1WebViewController", @"account", NO),
        BHTProbe(@"webReplyAccountBound", @"T1WebViewController", @"doesURLResultTypeOpenInWebview:", NO),

        BHTProbe(@"compatibilitySignIn", @"TFSTwitterAPIXAuthPasswordCommand", @"initWithContext:accountID:authContext:identifier:password:simCountryCode:httpRequestConfiguration:supportOneFactorAuthorization:knownDeviceToken:uiMetrics:authTokenStorage:source:responseModelBuilder:completionBlock:", NO),
        BHTProbe(@"compatibilitySignIn", @"TFSTwitterServiceRunner", @"APICommandContext", YES),
        BHTProbe(@"compatibilitySignIn", @"TFSTwitterServiceRunner", @"APICommandLoader", YES),
        BHTProbe(@"compatibilitySignIn", @"TNUServiceHTTPConfiguration", @"configurationForForegroundRetriableRequest", YES),
        BHTProbe(@"compatibilitySignIn", @"TFNTwitterAccount", @"initWithUsername:userID:", NO),
        BHTProbe(@"compatibilitySignIn", @"TFNTwitterAccount", @"updateUserInfoAndCredentialsWithToken:secret:username:", NO),
        BHTProbe(@"compatibilitySignIn", @"T1LoginChallengeFactory", @"loginChallengeWithMode:loginType:requestID:user:userID:URLString:loginCause:", YES),
        BHTProbe(@"compatibilitySignIn", @"T1AccountsViewController", @"viewWillAppear:", NO),
        BHTProbe(@"compatibilitySignIn", @"T1AccountsViewController", @"viewDidAppear:", NO),
        BHTProbe(@"compatibilitySignIn", @"T1AccountsViewController", @"didAddAccountBlock", NO)
    ];
}

static NSDictionary* BHTSettingsSnapshot(void) {
    NSArray<NSString*>* boolKeys = @[
        @"padlock", @"hide_promoted", @"hide_premium_offer",
        @"no_tab_bar_hiding", @"disable_rtl", @"strip_share_tracking",
        @"expand_tco_links", @"show_scroll_indicator",
        @"tab_bar_theming", @"restore_tab_labels",
        @"restore_launch_animation", @"restore_refresh_sounds",
        @"custom_fonts", @"hide_who_to_follow",
        @"hide_timeline_prompts", @"hide_discover_more", @"hide_topics",
        @"hide_topics_to_follow", @"hide_spaces", @"hide_custom_timelines",
        @"remember_timeline_tab", @"enable_likes_tab",
        @"likes_media_waterfall", @"enable_grok_translations",
        @"hide_grok_analyze", @"hide_grok_sidebar", @"hide_grok_create",
        @"disable_auto_translate", @"download_videos", @"dm_media_downloads",
        @"voice_creation_enabled", @"no_voice_messages", @"old_compose_bar",
        @"dm_reply_later_enabled", @"media_upload_4k_enabled",
        @"custom_voice_upload", @"direct_save", @"auto_highest_load",
        @"force_highest_video_quality", @"force_tweet_full_frame",
        @"disable_video_captions", @"disable_immersive_scroll",
        @"restore_video_timestamp", @"follow_confirm", @"copy_profile_info",
        @"disable_articles", @"disable_highlights", @"hide_blue_verified",
        @"hide_follow_button", @"restore_follow_button", @"square_avatars",
        @"full_profile_counts", @"enable_edit_tweet", @"tweet_confirm",
        @"like_confirm", @"tweet_to_image", @"hide_view_count",
        @"hide_bookmark_button", @"hide_downvote_button",
        @"disable_sensitive_tweet_warnings", @"bypass_age_verification",
        @"reply_sorting", @"restore_reply_context", @"restore_tweet_labels",
        @"web_reply_fallback", @"detailed_reply_diagnostics",
        @"no_history", @"hide_trends", @"hide_trend_videos",
        @"restore_twitter_names", @"refresh_pill_label",
        @"color_twitter_icon_in_top_bar", @"disable_screenshot_detection",
        @"hide_screenshot_branding", @"always_open_safari",
        @"new_inapp_webview", @"flex_twitter"
    ];
    NSMutableDictionary* snapshot =
        [NSMutableDictionary dictionaryWithCapacity:boolKeys.count + 1];
    for (NSString* key in boolKeys) {
        snapshot[key] = @([BHTSettings boolForKey:key]);
    }
    snapshot[@"undo_tweet_timeout"] =
        @([BHTSettings integerForKey:@"undo_tweet_timeout"]);
    id usernameKeywords =
        [NSUserDefaults.standardUserDefaults
            objectForKey:@"bht_for_you_username_filter_keywords"];
    id postTextKeywords =
        [NSUserDefaults.standardUserDefaults
            objectForKey:@"bht_for_you_post_text_filter_keywords"];
    snapshot[@"for_you_username_filter_count"] =
        @([usernameKeywords isKindOfClass:NSArray.class]
              ? [(NSArray*)usernameKeywords count]
              : 0);
    snapshot[@"for_you_post_text_filter_count"] =
        @([postTextKeywords isKindOfClass:NSArray.class]
              ? [(NSArray*)postTextKeywords count]
              : 0);
    return [snapshot copy];
}

static NSDictionary* BHTMediaActionSettingsSnapshot(void) {
    NSDictionary* (^snapshot)(BHTMediaActionKind) =
        ^NSDictionary*(BHTMediaActionKind kind) {
            return @{
                @"order":
                    [BHTMediaActionUtility
                        orderedActionIdentifiersForKind:kind],
                @"hidden":
                    [BHTMediaActionUtility
                        hiddenActionIdentifiersForKind:kind]
            };
        };
    return @{
        @"photo": snapshot(BHTMediaActionKindPhoto),
        @"video": snapshot(BHTMediaActionKindVideo),
        @"gif": snapshot(BHTMediaActionKindGIF)
    };
}

static NSURL* BHTWriteCompatibilityReportNow(
    BOOL includeDetailedReplyDiagnostics,
    NSURL* destinationURL) {
    NSArray* probes = BHTRuntimeProbes();
    NSUInteger available = 0;
    NSMutableDictionary<NSString*, NSMutableDictionary*>* featureSummary =
        [NSMutableDictionary dictionary];
    for (NSDictionary* probe in probes) {
        BOOL present = [probe[@"methodPresent"] boolValue];
        if (present) available++;
        NSString* feature = probe[@"feature"];
        NSMutableDictionary* summary = featureSummary[feature];
        if (!summary) {
            summary = [@{@"checks": @0, @"available": @0} mutableCopy];
            featureSummary[feature] = summary;
        }
        summary[@"checks"] = @([summary[@"checks"] unsignedIntegerValue] + 1);
        summary[@"available"] = @([summary[@"available"] unsignedIntegerValue] + (present ? 1 : 0));
    }

    NSBundle* app = NSBundle.mainBundle;
    NSMutableDictionary* report = [@{
        @"generatedAt": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date],
        @"app": @{
            @"bundleID": app.bundleIdentifier ?: @"",
            @"version": [app objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
            @"build": [app objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"",
            @"ios": UIDevice.currentDevice.systemVersion ?: @""
        },
        @"tweak": @{
#ifdef NFB_VERSION_STRING
            @"version": @NFB_VERSION_STRING,
#else
            @"version": @"NeoFreeBird",
#endif
#ifdef NFB_COMMIT_STRING
            @"commit": @NFB_COMMIT_STRING,
#else
            @"commit": @"unknown",
#endif
            @"unsafeLoginOverridesIncluded": @NO,
            @"webSessionHarvestingIncluded": @NO,
            @"compatibilityPasswordSignInIncluded": @YES,
            @"nativeOnboardingSignInIncluded": @NO,
            @"compatibilityXAuthClientMetadataIncluded": @NO,
            @"attestationOverridesIncluded": @NO,
            @"credentialBackupIncluded": @NO
        },
        @"summary": @{
            @"checks": @(probes.count),
            @"available": @(available),
            @"missing": @(probes.count - available)
        },
        @"features": featureSummary,
        @"settings": BHTSettingsSnapshot(),
        @"authenticationRouting":
            BHTAuthenticationRoutingDiagnosticSnapshot(),
        @"compatibilitySignIn":
            BHTCompatibilitySignInDiagnosticSnapshot(),
        @"replyWorkflow":
            BHTReplyWorkflowDiagnosticSnapshot(),
        @"nativeReplyNetwork":
            BHTReplyRequestDiagnosticSnapshot(),
        @"nativeReplyApplication":
            BHTNativeReplyApplicationDiagnosticSnapshot(),
        @"nativeReplyFailure":
            BHTNativeReplyFailureDiagnosticSnapshot(),
        @"webReplyFallback":
            BHTWebReplyFallbackDiagnosticSnapshot(),
        @"forYouFilterRuntime": BHTForYouFilterDiagnosticSnapshot(),
        @"mediaActionMenus": BHTMediaActionSettingsSnapshot(),
        @"likesRuntime": BHTLikesDiagnosticsSnapshot(),
        @"sidebarNavigation": @{
            @"visibleItems":
                [BHTSidebarNavigationUtility visibleItemIDsInOrder],
            @"runtime":
                [BHTSidebarNavigationUtility diagnosticSnapshot]
        },
        @"navigationEntryClasses": BHTNavigationEntryClassSnapshot(),
        @"navigationMethods": BHTNavigationMethodSnapshot(),
        @"timelineItemObservations": BHTTimelineObservationSnapshot(),
        @"mediaActionRuntime": BHTMediaActionObservationSnapshot(),
        @"railBrandingRuntime": BHTRailBrandingObservationSnapshot(),
        @"themeRuntime": BHTThemeRuntimeObservationSnapshot(),
        @"probes": probes
    } mutableCopy];
    if (includeDetailedReplyDiagnostics) {
        report[@"detailedReplyDiagnostics"] =
            BHTDetailedReplyDiagnosticSnapshot();
    }

    NSData* data = [NSJSONSerialization dataWithJSONObject:report
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    if (!data) return nil;

    NSURL* reportURL =
        destinationURL ?: BHTCompatibilityReportURL();
    BOOL wroteReport =
        [data writeToURL:reportURL
                 options:NSDataWritingAtomic
                   error:nil];
    return wroteReport ? reportURL : nil;
}

void BHTWriteCompatibilityReport(void) {
    (void)BHTWriteCompatibilityReportNow(NO, nil);
}

void BHTWriteCompatibilityReportAsync(
    void (^completion)(NSURL* _Nullable reportURL)) {
    dispatch_async(BHTCompatibilityReportQueue(), ^{
        NSURL* currentReportURL =
            BHTWriteCompatibilityReportNow(NO, nil);
        NSURL* reportURL = nil;
        if (currentReportURL) {
            NSURL* snapshotURL =
                [BHTManager
                    temporaryFileURLWithExtension:@"json"];
            BOOL copiedSnapshot =
                [NSFileManager.defaultManager
                    copyItemAtURL:currentReportURL
                            toURL:snapshotURL
                            error:nil];
            if (copiedSnapshot) {
                reportURL = snapshotURL;
            } else {
                [NSFileManager.defaultManager
                    removeItemAtURL:snapshotURL
                              error:nil];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(reportURL);
        });
    });
}

void BHTWriteDetailedCompatibilityReportAsync(
    void (^completion)(NSURL* _Nullable reportURL)) {
    dispatch_async(BHTCompatibilityReportQueue(), ^{
        NSURL* temporaryURL =
            [BHTManager temporaryFileURLWithExtension:@"json"];
        NSURL* reportURL = BHTWriteCompatibilityReportNow(
            YES, temporaryURL);
        if (!reportURL) {
            [NSFileManager.defaultManager
                removeItemAtURL:temporaryURL
                          error:nil];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(reportURL);
        });
    });
}

void BHTRecordNavigationEntryClasses(NSArray* entries) {
    NSMutableOrderedSet<NSString*>* names = [NSMutableOrderedSet orderedSet];
    for (id entry in entries) {
        NSString* name = NSStringFromClass([entry class]);
        if (name.length) [names addObject:name];
    }
    NSUInteger generation;
    @synchronized(BHTObservationLock()) {
        BHTNavigationEntryClasses = names.array;
        generation = ++BHTNavigationReportGeneration;
    }

    // Tab visibility can be recalculated several times in one layout pass.
    // Debounce the automatic report so JSON serialization and an atomic file
    // write do not run synchronously for every intermediate tab array.
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(750 * NSEC_PER_MSEC)),
        BHTCompatibilityReportQueue(), ^{
            @synchronized(BHTObservationLock()) {
                if (generation != BHTNavigationReportGeneration) return;
            }
            BHTWriteCompatibilityReport();
        });
}
