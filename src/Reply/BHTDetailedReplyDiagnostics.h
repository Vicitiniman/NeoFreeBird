#pragma once

#import <Foundation/Foundation.h>

// Temporary beta-only diagnostics. Arming is explicit and one-shot. The
// existing compatibility diagnostics remain metadata-only; this module is
// included only by the explicit detailed-report export path.
void BHTArmDetailedReplyDiagnostics(void);
void BHTDisarmDetailedReplyDiagnostics(void);
BOOL BHTDetailedReplyDiagnosticsIsArmed(void);
BOOL BHTDetailedReplyDiagnosticsHasCapture(void);
void BHTClearDetailedReplyDiagnostics(void);

// Called only after the existing X 12.9 active-reply and exact first-party
// CreateTweet URL gates have accepted the response. The response's decoded
// JSON data is bounded and recursively redacted before it is retained.
void BHTDetailedReplyDiagnosticsCaptureDecodedResponse(
    NSUInteger sessionGeneration,
    id _Nullable response,
    id _Nullable model,
    id _Nullable parseError,
    id _Nullable APIErrors);

void BHTDetailedReplyDiagnosticsCapturePreparedResponse(
    NSUInteger sessionGeneration,
    BOOL observationComplete,
    id _Nullable effectiveModel,
    id _Nullable effectiveParseError,
    id _Nullable effectiveOperationError,
    id _Nullable effectiveAPIErrors,
    id _Nullable finalModel,
    id _Nullable finalParseError,
    id _Nullable finalOperationError,
    id _Nullable finalAPIErrors);

void BHTDetailedReplyDiagnosticsCaptureFailure(
    NSUInteger sessionGeneration,
    NSString* source,
    NSNotification* _Nullable notification);

// Captures the exact Objective-C status/error pair at X's typed
// update-status completion seam. This avoids touching the generic Swift ABI.
void BHTDetailedReplyDiagnosticsCaptureTypedResult(
    NSUInteger sessionGeneration,
    NSString* stage,
    id _Nullable status,
    id _Nullable error);

NSDictionary* BHTDetailedReplyDiagnosticSnapshot(void);
