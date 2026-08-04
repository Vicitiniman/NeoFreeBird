//
//  ReplyDiagnostics.x
//  NeoFreeBird
//
//  Privacy-preserving checkpoints for the X 12.9 reply workflow. The standard
//  report never retains hook arguments. A separately confirmed, one-shot beta
//  diagnostic may synchronously sanitize the exact typed status/error pair.
//

#import "Compatibility/BHTCompatibilityReporter.h"
#import "Core/BHTSettings.h"
#import "HookHelpers.h"
#import "Reply/BHTDetailedReplyDiagnostics.h"
#import "Reply/BHTWebReplyFallback.h"

#import <objc/message.h>
#import <objc/runtime.h>

static BOOL BHTReplyDiagnosticMethodHasShape(
    Class cls, SEL selector, unsigned int explicitArgumentCount) {
    if (!cls || !selector) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method ||
        method_getNumberOfArguments(method) !=
            explicitArgumentCount + 2) {
        return NO;
    }

    char returnType[8] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    return returnType[0] == 'v';
}

static BOOL BHTReplyDiagnosticMethodHasObjectArguments(
    Class cls, SEL selector, unsigned int explicitArgumentCount) {
    if (!BHTReplyDiagnosticMethodHasShape(
            cls, selector, explicitArgumentCount)) {
        return NO;
    }
    Method method = class_getInstanceMethod(cls, selector);
    for (unsigned int index = 0;
         index < explicitArgumentCount; index++) {
        char argumentType[16] = {0};
        method_getArgumentType(
            method, index + 2, argumentType,
            sizeof(argumentType));
        const char* type = argumentType;
        while (*type == 'r' || *type == 'n' || *type == 'N' ||
               *type == 'o' || *type == 'O' || *type == 'R' ||
               *type == 'V') {
            type++;
        }
        if (*type != '@') return NO;
    }
    return YES;
}

static BOOL BHTReplyDiagnosticMethodReturnsObjectWithNoArguments(
    Class cls, SEL selector, BOOL classMethod) {
    if (!cls || !selector) return NO;
    Method method = classMethod
        ? class_getClassMethod(cls, selector)
        : class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != 2) {
        return NO;
    }

    char returnType[16] = {0};
    method_getReturnType(method, returnType, sizeof(returnType));
    const char* type = returnType;
    while (*type == 'r' || *type == 'n' || *type == 'N' ||
           *type == 'o' || *type == 'O' || *type == 'R' ||
           *type == 'V') {
        type++;
    }
    return *type == '@';
}

static id BHTCurrentNativeAccountForWebReply(void) {
    Class hostClass = NSClassFromString(@"T1HostViewController");
    SEL sharedSelector =
        NSSelectorFromString(@"sharedHostViewController");
    SEL accountSelector = NSSelectorFromString(@"currentAccount");
    if (!BHTReplyDiagnosticMethodReturnsObjectWithNoArguments(
            hostClass, sharedSelector, YES)) {
        return nil;
    }
    @try {
        id host =
            ((id (*)(id, SEL))objc_msgSend)(
                (id)hostClass, sharedSelector);
        if (!host ||
            !BHTReplyDiagnosticMethodReturnsObjectWithNoArguments(
                [host class], accountSelector, NO)) {
            return nil;
        }
        return ((id (*)(id, SEL))objc_msgSend)(
            host, accountSelector);
    } @catch (__unused NSException* exception) {
        return nil;
    }
}

%group BHTReplyButtonDiagnosticHooks

%hook TTAStatusInlineReplyButton

- (void)didTap {
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticReplyActionTapped);
    %orig;
}

%end

%end

%group BHTReplyTypedUpdateStatusDiagnosticHooks

%hook TFNTwitterCompositionUpdateStatusOperation

- (void)_tfn_main_statusesUpdateCommandDidUpdateStatus:
            (__unsafe_unretained id)status
                                                   error:
            (__unsafe_unretained id)error {
    if (BHTReplyWorkflowApplicationDiagnosticWindowMayBeActive()) {
        @try {
            NSUInteger sessionGeneration = 0;
            if (BHTReplyWorkflowDiagnosticSessionForApplicationResponse(
                    &sessionGeneration)) {
                BHTDetailedReplyDiagnosticsCaptureTypedResult(
                    sessionGeneration,
                    @"updateStatusCommandCompletion",
                    status,
                    error);
            }
        } @catch (__unused NSException* exception) {
        }
    }
    %orig(status, error);
}

%end

%end

%group BHTReplyValidationCheckpointHooks

%hook T1TweetComposeViewController

- (void)_t1_checkForValidTweetsAndSend {
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticValidationEntered);
    %orig;
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticValidationReturned);
}

%end

%end

%group BHTReplySendCompositionsCheckpointHooks

%hook T1TweetComposeViewController

- (void)_t1_sendCompositions:(__unsafe_unretained id)compositions {
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticSendCompositionsEntered);
    %orig(compositions);
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticSendCompositionsReturned);
}

%end

%end

%group BHTReplyContainerLifecycleHooks

%hook T1TweetComposeContainerViewController

- (void)tweetComposeViewControllerDidCompleteComposing:
    (__unsafe_unretained id)composer {
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticContainerCompleted);
    %orig(composer);
}

- (void)tweetComposeViewControllerDidCancelComposing:
    (__unsafe_unretained id)composer {
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticContainerCancelled);
    %orig(composer);
}

%end

%end

%group BHTReplyActionDiagnosticHooks

%hook T1StatusViewInlineActionTapEventHandler

- (void)performReplyActionWithAccount:(__unsafe_unretained id)account
                                event:(__unsafe_unretained id)event
                           controller:(__unsafe_unretained id)controller
                        scribeContext:(__unsafe_unretained id)scribeContext
                        scribeElement:(__unsafe_unretained id)scribeElement
                           parameters:(__unsafe_unretained id)parameters
                       originalStatus:(__unsafe_unretained id)originalStatus {
    BHTWebReplyRouteResult routeResult =
        BHTTryPresentAccountBoundWebReplyFallback(
            originalStatus, account, topMostController());
    if (BHTWebReplyRouteResultConsumesTap(routeResult)) {
        BHTRecordReplyWorkflowDiagnostic(
            BHTReplyWorkflowDiagnosticWebFallbackPresented);
        return;
    }

    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticReplyActionForwarded);
    %orig(
        account, event, controller, scribeContext, scribeElement,
        parameters, originalStatus);
}

%end

%end

%group BHTReplyComposerDiagnosticHooks

%hook T1TweetComposeViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticComposerPresented);
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticComposerDisappeared);
    BOOL closing =
        self.isBeingDismissed ||
        self.isMovingFromParentViewController ||
        self.navigationController.isBeingDismissed ||
        self.navigationController.isMovingFromParentViewController;
    if (closing) {
        BHTRecordReplyWorkflowDiagnostic(
            BHTReplyWorkflowDiagnosticComposerClosed);
    }
}

%end

%end

%group BHTPersistentReplyComposerDiagnosticHooks

%hook T1PersistentComposeViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticPersistentComposerPresented);
}

%end

%end

%group BHTPersistentReplyActionFallbackHooks

%hook T1PersistentComposeViewController

- (void)persistentComposeViewDidTap:(__unsafe_unretained id)sender {
    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticReplyActionTapped);

    if ([BHTSettings boolForKey:@"web_reply_fallback"]) {
        BHTWebReplyRouteResult routeResult =
            BHTTryPresentWebReplyFallback(
                self.statusViewModel,
                BHTCurrentNativeAccountForWebReply(),
                topMostController());
        if (BHTWebReplyRouteResultConsumesTap(routeResult)) {
            BHTRecordReplyWorkflowDiagnostic(
                BHTReplyWorkflowDiagnosticWebFallbackPresented);
            return;
        }
    }

    BHTRecordReplyWorkflowDiagnostic(
        BHTReplyWorkflowDiagnosticReplyActionForwarded);
    %orig(sender);
}

%end

%end

%ctor {
    NSString* version = [NSBundle.mainBundle
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (![version isKindOfClass:NSString.class] ||
        ![version isEqualToString:@"12.9"]) {
        return;
    }

    BHTInstallReplyWorkflowDiagnosticObservers();

    Class replyButton =
        NSClassFromString(@"TTAStatusInlineReplyButton");
    if (BHTReplyDiagnosticMethodHasShape(
            replyButton, @selector(didTap), 0)) {
        %init(BHTReplyButtonDiagnosticHooks);
    }

    Class replyHandler = NSClassFromString(
        @"T1StatusViewInlineActionTapEventHandler");
    SEL replySelector = NSSelectorFromString(
        @"performReplyActionWithAccount:event:controller:scribeContext:scribeElement:parameters:originalStatus:");
    if (BHTReplyDiagnosticMethodHasObjectArguments(
            replyHandler, replySelector, 7)) {
        %init(BHTReplyActionDiagnosticHooks);
    }

    Class composer =
        NSClassFromString(@"T1TweetComposeViewController");
    if (BHTReplyDiagnosticMethodHasShape(
            composer, @selector(viewDidAppear:), 1) &&
        BHTReplyDiagnosticMethodHasShape(
            composer, @selector(viewDidDisappear:), 1)) {
        %init(BHTReplyComposerDiagnosticHooks);
    }
    if (BHTReplyDiagnosticMethodHasShape(
            composer,
            NSSelectorFromString(
                @"_t1_checkForValidTweetsAndSend"),
            0)) {
        %init(BHTReplyValidationCheckpointHooks);
    }
    if (BHTReplyDiagnosticMethodHasObjectArguments(
            composer,
            NSSelectorFromString(@"_t1_sendCompositions:"),
            1)) {
        %init(BHTReplySendCompositionsCheckpointHooks);
    }

    Class updateStatusOperation = NSClassFromString(
        @"TFNTwitterCompositionUpdateStatusOperation");
    SEL updateStatusSelector = NSSelectorFromString(
        @"_tfn_main_statusesUpdateCommandDidUpdateStatus:error:");
    if (BHTReplyDiagnosticMethodHasObjectArguments(
            updateStatusOperation, updateStatusSelector, 2)) {
        %init(BHTReplyTypedUpdateStatusDiagnosticHooks);
    }

    Class container = NSClassFromString(
        @"T1TweetComposeContainerViewController");
    SEL completedSelector = NSSelectorFromString(
        @"tweetComposeViewControllerDidCompleteComposing:");
    SEL cancelledSelector = NSSelectorFromString(
        @"tweetComposeViewControllerDidCancelComposing:");
    if (BHTReplyDiagnosticMethodHasObjectArguments(
            container, completedSelector, 1) &&
        BHTReplyDiagnosticMethodHasObjectArguments(
            container, cancelledSelector, 1)) {
        %init(BHTReplyContainerLifecycleHooks);
    }

    Class persistentComposer =
        NSClassFromString(@"T1PersistentComposeViewController");
    if (BHTReplyDiagnosticMethodHasShape(
            persistentComposer, @selector(viewDidAppear:), 1)) {
        %init(BHTPersistentReplyComposerDiagnosticHooks);
    }
    SEL persistentTapSelector =
        NSSelectorFromString(@"persistentComposeViewDidTap:");
    if (BHTReplyDiagnosticMethodHasObjectArguments(
            persistentComposer, persistentTapSelector, 1)) {
        %init(BHTPersistentReplyActionFallbackHooks);
    }
}
