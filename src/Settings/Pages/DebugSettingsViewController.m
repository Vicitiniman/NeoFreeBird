//
//  DebugSettingsViewController.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Settings/Pages/DebugSettingsViewController.h"
#import "Compatibility/BHTCompatibilityReporter.h"
#import "Core/BHTBundle.h"
#import "Headers/TWHeaders.h"
#import "Reply/BHTDetailedReplyDiagnostics.h"

@implementation DebugSettingsViewController

- (NSString*)pageKey {
    return @"debug";
}

- (void)viewWillAppear:(BOOL)animated {
    // Clears an armed preference left by a terminated process; invasive
    // capture always requires fresh confirmation in the current launch.
    (void)BHTDetailedReplyDiagnosticsIsArmed();
    [super viewWillAppear:animated];
}

- (void)switchChanged:(UISwitch*)sender {
    NSString* key = BHTSettingsKeyForSwitch(sender);
    if ([key isEqualToString:@"detailed_reply_diagnostics"]) {
        if (!sender.isOn) {
            BHTDisarmDetailedReplyDiagnostics();
            [self.tableView reloadData];
            return;
        }

        // Do not persist ON until the user accepts the disclosure.
        sender.on = NO;
        BHTBundle* bundle = BHTBundle.sharedBundle;
        UIAlertController* warning = [UIAlertController
            alertControllerWithTitle:[bundle localizedStringForKey:
                @"DETAILED_REPLY_DIAGNOSTICS_WARNING_TITLE"]
                                 message:[bundle localizedStringForKey:
                @"DETAILED_REPLY_DIAGNOSTICS_WARNING_MESSAGE"]
                          preferredStyle:UIAlertControllerStyleAlert];
        __weak typeof(self) weakSelf = self;
        [warning addAction:[UIAlertAction
            actionWithTitle:[bundle localizedStringForKey:
                @"DETAILED_REPLY_DIAGNOSTICS_ENABLE_ONCE"]
                      style:UIAlertActionStyleDestructive
                    handler:^(__unused UIAlertAction* action) {
                        BHTArmDetailedReplyDiagnostics();
                        [weakSelf.tableView reloadData];
                    }]];
        [warning addAction:[UIAlertAction
            actionWithTitle:[bundle localizedStringForKey:
                @"DETAILED_REPLY_DIAGNOSTICS_CANCEL"]
                      style:UIAlertActionStyleCancel
                    handler:^(__unused UIAlertAction* action) {
                        BHTDisarmDetailedReplyDiagnostics();
                        [weakSelf.tableView reloadData];
                    }]];
        [self presentViewController:warning
                           animated:YES
                         completion:nil];
        return;
    }

    [super switchChanged:sender];
    if ([key isEqualToString:@"flex_twitter"]) {
        if (sender.isOn) {
            [[objc_getClass("FLEXManager") sharedManager] showExplorer];
        } else {
            [[objc_getClass("FLEXManager") sharedManager] hideExplorer];
        }
    }
}

- (void)shareCompatibilityReportIncludingDetails:(BOOL)includeDetails {
    __weak typeof(self) weakSelf = self;
    void (^completion)(NSURL*) = ^(NSURL* reportURL) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            if (reportURL.isFileURL) {
                [NSFileManager.defaultManager
                    removeItemAtURL:reportURL
                              error:nil];
            }
            return;
        }
        if (!reportURL.isFileURL) {
            BHTBundle* bundle = BHTBundle.sharedBundle;
            UIAlertController* error = [UIAlertController
                alertControllerWithTitle:[bundle localizedStringForKey:
                    @"DETAILED_REPLY_DIAGNOSTICS_EXPORT_ERROR_TITLE"]
                                     message:[bundle localizedStringForKey:
                    @"DETAILED_REPLY_DIAGNOSTICS_EXPORT_ERROR_MESSAGE"]
                              preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction
                actionWithTitle:@"OK"
                          style:UIAlertActionStyleDefault
                        handler:nil]];
            [strongSelf presentViewController:error
                                     animated:YES
                                   completion:nil];
            return;
        }

        UIActivityViewController* share =
            [[UIActivityViewController alloc]
                initWithActivityItems:@[reportURL]
                applicationActivities:nil];
        share.popoverPresentationController.sourceView = strongSelf.view;
        share.popoverPresentationController.sourceRect = CGRectMake(
            CGRectGetMidX(strongSelf.view.bounds),
            CGRectGetMidY(strongSelf.view.bounds), 1, 1);
        __weak typeof(strongSelf) weakPresenter = strongSelf;
        share.completionWithItemsHandler =
            ^(__unused UIActivityType activityType,
              BOOL completed,
              __unused NSArray* returnedItems,
              __unused NSError* activityError) {
                [NSFileManager.defaultManager
                    removeItemAtURL:reportURL
                              error:nil];
                if (includeDetails && completed) {
                    BHTClearDetailedReplyDiagnostics();
                    [weakPresenter.tableView reloadData];
                }
            };
        [strongSelf presentViewController:share
                                 animated:YES
                               completion:nil];
    };
    if (includeDetails) {
        BHTWriteDetailedCompatibilityReportAsync(completion);
    } else {
        BHTWriteCompatibilityReportAsync(completion);
    }
}

- (void)exportCompatibilityReport:(__unused id)sender {
    if (!BHTDetailedReplyDiagnosticsHasCapture()) {
        [self shareCompatibilityReportIncludingDetails:NO];
        return;
    }

    BHTBundle* bundle = BHTBundle.sharedBundle;
    UIAlertController* disclosure = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:
            @"DETAILED_REPLY_DIAGNOSTICS_EXPORT_WARNING_TITLE"]
                         message:[bundle localizedStringForKey:
            @"DETAILED_REPLY_DIAGNOSTICS_EXPORT_WARNING_MESSAGE"]
                  preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [disclosure addAction:[UIAlertAction
        actionWithTitle:[bundle localizedStringForKey:
            @"DETAILED_REPLY_DIAGNOSTICS_SHARE_DETAILED"]
                  style:UIAlertActionStyleDestructive
                handler:^(__unused UIAlertAction* action) {
                    [weakSelf
                        shareCompatibilityReportIncludingDetails:YES];
                }]];
    [disclosure addAction:[UIAlertAction
        actionWithTitle:[bundle localizedStringForKey:
            @"DETAILED_REPLY_DIAGNOSTICS_SHARE_STANDARD"]
                  style:UIAlertActionStyleDefault
                handler:^(__unused UIAlertAction* action) {
                    [weakSelf
                        shareCompatibilityReportIncludingDetails:NO];
                }]];
    [disclosure addAction:[UIAlertAction
        actionWithTitle:[bundle localizedStringForKey:
            @"DETAILED_REPLY_DIAGNOSTICS_CANCEL"]
                  style:UIAlertActionStyleCancel
                handler:nil]];
    [self presentViewController:disclosure
                       animated:YES
                     completion:nil];
}

@end
