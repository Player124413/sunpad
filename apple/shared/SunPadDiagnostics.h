#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* Starts the persistent runtime log and rotates it when it grows beyond 1 MB.
 * The log lives in Library/Application Support/SunPad/Logs/runtime.log so it
 * survives app relaunches and can be retrieved with devicectl. */
FOUNDATION_EXPORT void SunPadDiagnosticsStart(void);

/* Writes one timestamped line to both the unified device log and SunPad's
 * persistent runtime log. Intended for low-frequency lifecycle breadcrumbs,
 * not per-frame tracing. */
FOUNDATION_EXPORT void SunPadLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

FOUNDATION_EXPORT NSString *SunPadDiagnosticsLogPath(void);

/* Copies the current raw runtime log to a timestamped temporary file that is
 * safe to hand to UIActivityViewController while logging continues. */
FOUNDATION_EXPORT NSURL *_Nullable SunPadDiagnosticsSnapshotURL(NSError **error);

NS_ASSUME_NONNULL_END
