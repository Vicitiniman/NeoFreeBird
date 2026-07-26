#import "Compatibility/BHTCompatibilityReporter.h"
#import "Core/BHTSettings.h"
#import "Likes/BHTLikesTab.h"
#import "MediaActions/BHTMediaActionUtility.h"
#import "Sidebar/BHTSidebarNavigationUtility.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSArray<NSString*>* BHTNavigationEntryClasses;
static NSMutableDictionary<NSString*, NSMutableDictionary*>*
    BHTTimelineItemObservations;
static NSMutableDictionary<NSString*, NSMutableDictionary*>*
    BHTMediaActionObservations;
static NSUInteger BHTNavigationReportGeneration;

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
        BHTProbe(@"home", @"T1FleetLineHeaderController", @"_t1_shouldShowFleetLine", NO),
        BHTProbe(@"home", @"TUIUpdateIndicator", @"_recreatePillControlForContentNotification:hideOnScroll:", NO),
        BHTProbe(@"appearance", @"TwitterHome.HomeDefaultNavigationBarTitleViewPlugin", @"titleView", NO),
        BHTProbe(@"appearance", @"T1AnimatedLaunchScreenView", @"layoutSubviews", NO),
        BHTProbe(@"appearance", @"T1AnimatedLaunchScreenView", @"animateRevealWithCompletion:", NO),
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
        BHTProbe(@"settings", @"TFSInstrumentedFeatureSwitches", @"boolForKey:", NO)
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

void BHTWriteCompatibilityReport(void) {
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
    NSDictionary* report = @{
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
            @"webSessionHarvestingIncluded": @NO
        },
        @"summary": @{
            @"checks": @(probes.count),
            @"available": @(available),
            @"missing": @(probes.count - available)
        },
        @"features": featureSummary,
        @"settings": BHTSettingsSnapshot(),
        @"mediaActionMenus": BHTMediaActionSettingsSnapshot(),
        @"likesRuntime": BHTLikesDiagnosticsSnapshot(),
        @"sidebarNavigation": @{
            @"visibleItems":
                [BHTSidebarNavigationUtility visibleItemIDsInOrder]
        },
        @"navigationEntryClasses": BHTNavigationEntryClassSnapshot(),
        @"navigationMethods": BHTNavigationMethodSnapshot(),
        @"timelineItemObservations": BHTTimelineObservationSnapshot(),
        @"mediaActionRuntime": BHTMediaActionObservationSnapshot(),
        @"probes": probes
    };

    NSData* data = [NSJSONSerialization dataWithJSONObject:report
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    if (data) [data writeToURL:BHTCompatibilityReportURL() options:NSDataWritingAtomic error:nil];
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
