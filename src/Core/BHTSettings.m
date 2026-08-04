//
//  BHTSettings.m
//  NeoFreeBird
//
//  Created by nyaathea
//

#import "Core/BHTSettings.h"
#import "Core/BHTBundle.h"
#import "Core/BHTManager.h"
#import "ThemeColor/BHTThemePresets.h"

NSString* const BHTSettingsProfileDidApplyNotification =
    @"BHTSettingsProfileDidApplyNotification";

static NSString* const BHTSettingsProfileErrorDomain =
    @"com.neofreebird.preference-profile";

static NSArray<NSString*>* BHTSettingsPageOrder(void) {
    return @[
        @"general", @"appearance", @"grok", @"timelines", @"tweets",
        @"media_downloads", @"profiles", @"search", @"backup", @"web",
        @"branding", @"debug"
    ];
}

static NSDictionary<NSString*, NSDictionary*>* BHTSettingsPages(void) {
    static NSDictionary<NSString*, NSDictionary*>* pages;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pages = @{
            @"general": @{
                @"titleKey": @"MODERN_SETTINGS_LAYOUT_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_LAYOUT_SUBTITLE",
                @"settings": @[
                    @{@"key": @"padlock",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_APP_LOCK"},
                    @{@"key": @"disable_screenshot_detection",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_SCREENSHOTS"},
                    @{@"key": @"hide_screenshot_branding",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_SCREENSHOTS"}
                ]
            },
            @"appearance": @{
                @"titleKey": @"MODERN_SETTINGS_APPEARANCE_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_APPEARANCE_SUBTITLE",
                @"settings": @[
                    @{
                        @"titleKey": @"THEME_OPTION_TITLE",
                        @"action": @"showThemeViewController:",
                        @"type": @"button",
                        @"searchPageKey": @"themes",
                        @"searchTargetIdentifier": @"themes.current",
                        @"sectionKey": @"SETTINGS_SECTION_VISUALS"
                    },
                    @{
                        @"titleKey": @"APP_ICON_TITLE",
                        @"action": @"showAppIconViewController:",
                        @"type": @"button",
                        @"searchAutoOpen": @YES,
                        @"sectionKey": @"SETTINGS_SECTION_VISUALS"
                    },
                    @{
                        @"titleKey": @"CUSTOM_TAB_BAR_OPTION_TITLE",
                        @"action": @"showCustomTabBarVC:",
                        @"type": @"button",
                        @"searchAutoOpen": @YES,
                        @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"
                    },
                    @{
                        @"titleKey": @"LIKES_NAVIGATION_EDITOR_TITLE",
                        @"action": @"showLikesNavigationVC:",
                        @"type": @"button",
                        @"searchAutoOpen": @YES,
                        @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"
                    },
                    @{
                        @"titleKey": @"SIDEBAR_NAVIGATION_EDITOR_TITLE",
                        @"action": @"showSidebarNavigationVC:",
                        @"type": @"button",
                        @"searchAutoOpen": @YES,
                        @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"
                    },
                    @{@"key": @"tab_bar_theming",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"},
                    @{@"key": @"restore_tab_labels",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"},
                    @{@"key": @"no_tab_bar_hiding",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"},
                    @{@"key": @"disable_rtl",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"},
                    @{@"key": @"show_scroll_indicator",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_NAVIGATION"},
                    @{@"key": @"restore_launch_animation",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_MOTION_SOUND"},
                    @{@"key": @"restore_refresh_sounds",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_MOTION_SOUND"},
                    @{@"key": @"custom_fonts",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_FONTS"},
                    @{
                        @"type": @"compactButton",
                        @"parentKey": @"custom_fonts",
                        @"key": @"regular_font_button",
                        @"titleKey": @"REGULAR_FONTS_PICKER_OPTION_TITLE",
                        @"action": @"showRegularFontPicker:",
                        @"searchAutoOpen": @YES,
                        @"prefKeyForSubtitle": @"bhtwitter_font_1",
                        @"subtitleDefaultKey": @"FONT_SYSTEM_DEFAULT_SUBTITLE",
                        @"sectionKey": @"SETTINGS_SECTION_FONTS"
                    },
                    @{
                        @"type": @"compactButton",
                        @"parentKey": @"custom_fonts",
                        @"key": @"bold_font_button",
                        @"titleKey": @"BOLD_FONTS_PICKER_OPTION_TITLE",
                        @"action": @"showBoldFontPicker:",
                        @"searchAutoOpen": @YES,
                        @"prefKeyForSubtitle": @"bhtwitter_font_2",
                        @"subtitleDefaultKey": @"FONT_SYSTEM_DEFAULT_SUBTITLE",
                        @"sectionKey": @"SETTINGS_SECTION_FONTS"
                    }
                ]
            },
            @"timelines": @{
                @"titleKey": @"MODERN_SETTINGS_TIMELINES_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_TIMELINES_SUBTITLE",
                @"settings": @[
                    @{
                        @"titleKey": @"FOR_YOU_KEYWORD_FILTERS_TITLE",
                        @"action": @"showForYouKeywordFilters:",
                        @"type": @"button",
                        @"searchAutoOpen": @YES,
                        @"sectionKey": @"SETTINGS_SECTION_FOR_YOU_FILTERS"
                    },
                    @{@"key": @"hide_promoted",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_ADS_OFFERS"},
                    @{@"key": @"hide_premium_offer",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_ADS_OFFERS"},
                    @{@"key": @"hide_who_to_follow",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_CLEANUP"},
                    @{@"key": @"hide_timeline_prompts",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_CLEANUP"},
                    @{@"key": @"hide_discover_more",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_CLEANUP"},
                    @{@"key": @"hide_topics",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_CLEANUP"},
                    @{@"key": @"hide_topics_to_follow",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_CLEANUP"},
                    @{@"key": @"hide_spaces",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_BEHAVIOR"},
                    @{@"key": @"hide_custom_timelines",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_BEHAVIOR"},
                    @{@"key": @"remember_timeline_tab",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_TIMELINE_BEHAVIOR"}
                ]
            },
            @"grok": @{
                @"titleKey": @"MODERN_SETTINGS_GROK_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_GROK_SUBTITLE",
                @"settings": @[
                    @{
                        @"key": @"enable_grok_translations",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_grok_analyze",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_grok_sidebar",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"hide_grok_create",
                        @"default": @YES,
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"disable_auto_translate",
                        @"default": @NO,
                        @"type": @"toggle"
                    }
                ]
            },
            @"media_downloads": @{
                @"titleKey": @"MODERN_SETTINGS_MEDIA_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_MEDIA_SUBTITLE",
                @"settings": @[
                    @{
                        @"titleKey": @"MEDIA_ACTION_MENU_EDITOR_TITLE",
                        @"action": @"showMediaActionMenus:",
                        @"type": @"button",
                        @"searchAutoOpen": @YES,
                        @"sectionKey": @"SETTINGS_SECTION_DOWNLOADS_ACTIONS"
                    },
                    @{
                        @"key": @"download_videos",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_DOWNLOADS_ACTIONS"
                    },
                    @{
                        @"key": @"dm_media_downloads",
                        @"parentKey": @"download_videos",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_DOWNLOADS_ACTIONS"
                    },
                    @{@"key": @"direct_save",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_DOWNLOADS_ACTIONS"
                    },
                    @{
                        @"key": @"voice_creation_enabled",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_MESSAGES_CREATION"
                    },
                    @{
                        @"key": @"no_voice_messages",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_MESSAGES_CREATION"
                    },
                    @{
                        @"key": @"old_compose_bar",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_MESSAGES_CREATION"
                    },
                    @{
                        @"key": @"dm_reply_later_enabled",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_MESSAGES_CREATION"
                    },
                    @{
                        @"key": @"media_upload_4k_enabled",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_MESSAGES_CREATION"
                    },
                    @{
                        @"key": @"custom_voice_upload",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_MESSAGES_CREATION"
                    },
                    @{
                        @"key": @"disable_video_captions",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_QUALITY_PLAYBACK"
                    },
                    @{
                        @"key": @"auto_highest_load",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_QUALITY_PLAYBACK"
                    },
                    @{
                        @"key": @"force_highest_video_quality",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_QUALITY_PLAYBACK"
                    },
                    @{
                        @"key": @"force_tweet_full_frame",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_QUALITY_PLAYBACK"
                    },
                    @{
                        @"key": @"restore_video_timestamp",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_QUALITY_PLAYBACK"
                    },
                    @{
                        @"key": @"disable_immersive_scroll",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_QUALITY_PLAYBACK"
                    }
                ]
            },
            @"profiles": @{
                @"titleKey": @"MODERN_SETTINGS_PROFILES_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_PROFILES_SUBTITLE",
                @"settings": @[
                    @{
                        @"titleKey":
                            @"COMPATIBILITY_SIGN_IN_TITLE",
                        @"action":
                            @"showCompatibilitySignIn:",
                        @"type": @"button",
                        @"searchAutoOpen": @YES,
                        @"sectionKey":
                            @"SETTINGS_SECTION_ACCOUNT_ACCESS"
                    },
                    @{@"key": @"follow_confirm",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_PROFILE_ACTIONS"},
                    @{
                        @"key": @"copy_profile_info",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_ACTIONS"
                    },
                    @{
                        @"key": @"disable_articles",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_TABS"
                    },
                    @{
                        @"key": @"disable_highlights",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_TABS"
                    },
                    @{
                        @"key": @"hide_blue_verified",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_APPEARANCE"
                    },
                    @{
                        @"key": @"hide_follow_button",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_ACTIONS"
                    },
                    @{
                        @"key": @"restore_follow_button",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_ACTIONS"
                    },
                    @{@"key": @"square_avatars",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_PROFILE_APPEARANCE"},
                    @{
                        @"key": @"full_profile_counts",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_PROFILE_APPEARANCE"
                    }
                ]
            },
            @"tweets": @{
                @"titleKey": @"MODERN_SETTINGS_TWEETS_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_TWEETS_SUBTITLE",
                @"settings": @[
                    @{
                        @"key": @"enable_edit_tweet",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_COMPOSING"
                    },
                    @{
                        @"key": @"web_reply_fallback",
                        @"default": @NO,
                        @"type": @"toggle",
                        // Reply routing can select a different signed-in web
                        // account, so a shared profile must never enable it.
                        @"excludeFromProfile": @YES,
                        @"sectionKey": @"SETTINGS_SECTION_COMPOSING"
                    },
                    @{
                        @"type": @"compactButton",
                        @"key": @"web_reply_sign_in_setup",
                        @"titleKey": @"WEB_REPLY_SIGN_IN_SETUP_TITLE",
                        @"action": @"showWebReplySignInSetup:",
                        @"parentKey": @"web_reply_fallback",
                        @"searchAutoOpen": @YES,
                        @"sectionKey": @"SETTINGS_SECTION_COMPOSING"
                    },
                    @{
                        @"type": @"compactButton",
                        @"key": @"undo_tweet_timeout",
                        @"default": @10,
                        @"titleKey": @"UNDO_TWEET_TITLE",
                        @"action": @"showUndoTimeoutPicker:",
                        @"searchAutoOpen": @YES,
                        @"sectionKey": @"SETTINGS_SECTION_COMPOSING"
                    },
                    @{@"key": @"tweet_confirm",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_COMPOSING"},
                    @{@"key": @"like_confirm",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_INTERACTIONS"},
                    @{@"key": @"tweet_to_image",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_COMPOSING"},
                    @{
                        @"key": @"hide_view_count",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_INTERACTIONS"
                    },
                    @{
                        @"key": @"hide_bookmark_button",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_INTERACTIONS"
                    },
                    @{
                        @"key": @"hide_downvote_button",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_INTERACTIONS"
                    },
                    @{
                        @"key": @"disable_sensitive_tweet_warnings",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_SAFETY_CONTEXT"
                    },
                    @{
                        @"key": @"bypass_age_verification",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_SAFETY_CONTEXT"
                    },
                    @{@"key": @"reply_sorting",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_SAFETY_CONTEXT"},
                    @{
                        @"key": @"restore_reply_context",
                        @"default": @YES,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_SAFETY_CONTEXT"
                    },
                    @{
                        @"key": @"restore_tweet_labels",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"sectionKey": @"SETTINGS_SECTION_SAFETY_CONTEXT"
                    }
                ]
            },
            @"search": @{
                @"titleKey": @"MODERN_SETTINGS_SEARCH_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_SEARCH_SUBTITLE",
                @"settings": @[
                    @{@"key": @"no_history",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{@"key": @"hide_trends",
                      @"default": @NO,
                      @"type": @"toggle"},
                    @{
                        @"key": @"hide_trend_videos",
                        @"default": @NO,
                        @"type": @"toggle"
                    }
                ]
            },
            @"backup": @{
                @"titleKey": @"MODERN_SETTINGS_BACKUP_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_BACKUP_SUBTITLE",
                @"settings": @[
                    @{
                        @"titleKey": @"EXPORT_PREFERENCE_PROFILE_TITLE",
                        @"action": @"exportPreferenceProfile:",
                        @"type": @"button",
                        @"sectionKey":
                            @"PREFERENCE_PROFILES_SECTION_TITLE"
                    },
                    @{
                        @"titleKey": @"IMPORT_PREFERENCE_PROFILE_TITLE",
                        @"action": @"importPreferenceProfile:",
                        @"type": @"button",
                        @"sectionKey":
                            @"PREFERENCE_PROFILES_SECTION_TITLE"
                    }
                ]
            },
            @"branding": @{
                @"titleKey": @"MODERN_SETTINGS_BRANDING_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_BRANDING_SUBTITLE",
                @"settings": @[
                    @{
                        @"key": @"restore_twitter_names",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"refresh_pill_label",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    },
                    @{
                        @"key": @"color_twitter_icon_in_top_bar",
                        @"default": @([BHTManager isTwitterBranded]),
                        @"type": @"toggle"
                    }
                ]
            },
            @"experimental": @{
                @"titleKey": @"MODERN_SETTINGS_EXPERIMENTAL_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_EXPERIMENTAL_SUBTITLE",
                @"settings": @[]
            },
            @"web": @{
                @"titleKey": @"MODERN_SETTINGS_WEB_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_WEB_SUBTITLE",
                @"settings": @[
                    @{
                        @"type": @"compactButton",
                        @"key": @"sharing_domain",
                        @"action": @"showSharingDomainPrompt:",
                        @"searchAutoOpen": @YES,
                        @"prefKeyForSubtitle": @"sharing_domain",
                        @"subtitleDefault": @"x.com",
                        @"sectionKey": @"SETTINGS_SECTION_LINKS_SHARING"
                    },
                    @{@"key": @"strip_share_tracking",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_LINKS_SHARING"},
                    @{@"key": @"expand_tco_links",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_LINKS_SHARING"},
                    @{@"key": @"always_open_safari",
                      @"default": @NO,
                      @"sectionKey": @"SETTINGS_SECTION_BROWSER"},
                    @{@"key": @"new_inapp_webview",
                      @"default": @YES,
                      @"sectionKey": @"SETTINGS_SECTION_BROWSER"}
                ]
            },
            @"debug": @{
                @"titleKey": @"MODERN_SETTINGS_DEBUG_TITLE",
                @"subtitleKey": @"MODERN_SETTINGS_DEBUG_SUBTITLE",
                @"settings": @[
                    @{
                        @"key": @"detailed_reply_diagnostics",
                        @"default": @NO,
                        @"type": @"toggle",
                        @"excludeFromProfile": @YES,
                        @"sectionKey": @"SETTINGS_SECTION_REPLY_DIAGNOSTICS"
                    },
                    @{
                        @"titleKey": @"EXPORT_COMPATIBILITY_REPORT_TITLE",
                        @"action": @"exportCompatibilityReport:",
                        @"type": @"button",
                        @"sectionKey": @"SETTINGS_SECTION_REPLY_DIAGNOSTICS"
                    },
                    @{@"key": @"flex_twitter",
                      @"default": @NO,
                      @"type": @"toggle",
                      @"sectionKey": @"SETTINGS_SECTION_VIEW_INSPECTION"}
                ]
            }
        };
    });
    return pages;
}

static NSDictionary<NSString*, NSDictionary*>* BHTSettingsIndex(void) {
    static NSDictionary<NSString*, NSDictionary*>* index;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableDictionary<NSString*, NSDictionary*>* map =
            [NSMutableDictionary dictionary];
        for (NSDictionary* page in BHTSettingsPages().allValues) {
            for (NSDictionary* setting in page[@"settings"]) {
                NSString* key = setting[@"key"];
                if (key) {
                    map[key] = setting;
                }
            }
        }
        index = [map copy];
    });
    return index;
}

static NSError* BHTProfileError(NSInteger code, NSString* description) {
    return [NSError errorWithDomain:BHTSettingsProfileErrorDomain
                               code:code
                           userInfo:@{
                               NSLocalizedDescriptionKey:
                                   description ?: @"The profile is invalid."
                           }];
}

static BOOL BHTIsStringArray(id value) {
    if (![value isKindOfClass:NSArray.class]) return NO;
    if ([(NSArray*)value count] > 128) return NO;
    for (id item in (NSArray*)value) {
        if (![item isKindOfClass:NSString.class] ||
            [(NSString*)item length] > 128) {
            return NO;
        }
    }
    return YES;
}

static BOOL BHTIsValidCustomAccent(id value) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString* candidate =
        [(NSString*)value stringByTrimmingCharactersInSet:
                              NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([candidate hasPrefix:@"#"]) {
        candidate = [candidate substringFromIndex:1];
    }
    if (candidate.length != 6 && candidate.length != 8) return NO;
    NSCharacterSet* allowed =
        [NSCharacterSet
            characterSetWithCharactersInString:@"0123456789abcdefABCDEF"];
    NSRange invalidRange =
        [candidate rangeOfCharacterFromSet:[allowed invertedSet]];
    return invalidRange.location == NSNotFound;
}

static BOOL BHTProfileVersionIsExactly(id value, NSInteger expected) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
        return NO;
    }
    return [value doubleValue] == (double)expected;
}

static BOOL BHTUserThemeIdentifierExists(
    NSString* identifier, NSArray<NSDictionary*>* themes) {
    if (![BHTThemePresets isUserPresetIdentifier:identifier]) return NO;
    for (NSDictionary* theme in themes) {
        if ([theme[@"identifier"] isEqualToString:identifier]) {
            return YES;
        }
    }
    return NO;
}

static NSSet<NSString*>* BHTStringPreferenceKeys(void) {
    return [NSSet setWithArray:@[
        @"bht_custom_accent_hex",
        @"bht_theme_preset_identifier",
        @"bhtwitter_font_1",
        @"bhtwitter_font_2",
        @"sharing_domain"
    ]];
}

static NSSet<NSString*>* BHTStringArrayPreferenceKeys(void) {
    return [NSSet setWithArray:@[
        @"bh_tabs_visible",
        @"bht_likes_navigation_visible",
        @"bht_sidebar_navigation_visible",
        @"bht_media_actions_photo_order",
        @"bht_media_actions_photo_hidden",
        @"bht_media_actions_gif_order",
        @"bht_media_actions_gif_hidden",
        @"bht_media_actions_video_order",
        @"bht_media_actions_video_hidden"
    ]];
}

static NSSet<NSString*>* BHTKeywordArrayPreferenceKeys(void) {
    return [NSSet setWithArray:@[
        @"bht_for_you_username_filter_keywords",
        @"bht_for_you_post_text_filter_keywords"
    ]];
}

static BOOL BHTIsValidKeywordArray(id value, BOOL usernameKeywords) {
    if (![value isKindOfClass:NSArray.class] ||
        [(NSArray*)value count] > 64) {
        return NO;
    }

    NSCharacterSet* whitespace =
        NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSCharacterSet* controls = NSCharacterSet.controlCharacterSet;
    NSMutableSet<NSString*>* normalizedTerms = [NSMutableSet set];
    for (id item in (NSArray*)value) {
        if (![item isKindOfClass:NSString.class]) return NO;
        NSString* term =
            [(NSString*)item stringByTrimmingCharactersInSet:whitespace];
        if (usernameKeywords && [term hasPrefix:@"@"]) {
            term = [[term substringFromIndex:1]
                stringByTrimmingCharactersInSet:whitespace];
        }
        if (term.length == 0 || term.length > 128 ||
            [term rangeOfCharacterFromSet:controls].location != NSNotFound ||
            [term rangeOfCharacterFromSet:
                      NSCharacterSet.newlineCharacterSet].location !=
                NSNotFound) {
            return NO;
        }
        NSString* normalized =
            [term stringByFoldingWithOptions:
                      NSCaseInsensitiveSearch |
                      NSDiacriticInsensitiveSearch |
                      NSWidthInsensitiveSearch
                                      locale:
                                          [NSLocale
                                              localeWithLocaleIdentifier:
                                                  @"en_US_POSIX"]];
        if ([normalizedTerms containsObject:normalized]) return NO;
        [normalizedTerms addObject:normalized];
    }
    return YES;
}

@implementation BHTSettings

#pragma mark - Migration

// One-time migration of preferences saved under the old (inconsistent) key
// names to the normalised keys, so existing installs keep their settings.
+ (void)load {
    [self migrateUndoTweetToggle];

    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"nfb_key_migration_v2_done"]) {
        NSDictionary<NSString*, NSString*>* x129RenamedKeys = @{
            @"dis_VODCaptions": @"disable_video_captions",
            @"strip_tracking_params": @"strip_share_tracking",
            // X 12.9 exposes bio translation through the same native Grok
            // translation controls as posts, polls and Community Notes.
            @"bio_translate": @"enable_grok_translations",
        };
        [x129RenamedKeys enumerateKeysAndObjectsUsingBlock:^(
                            NSString* oldKey, NSString* newKey, BOOL* stop) {
            id value = [defaults objectForKey:oldKey];
            if (value != nil && [defaults objectForKey:newKey] == nil) {
                [defaults setObject:value forKey:newKey];
            }
            if (value != nil) {
                [defaults removeObjectForKey:oldKey];
            }
        }];
        [defaults setBool:YES forKey:@"nfb_key_migration_v2_done"];
    }

    if ([defaults boolForKey:@"nfb_key_migration_v1_done"]) {
        return;
    }

    NSDictionary<NSString*, NSString*>* renamedKeys = @{
        @"dis_rtl": @"disable_rtl",
        @"showScollIndicator": @"show_scroll_indicator",
        @"en_font": @"custom_fonts",
        @"dw_v": @"download_videos",
        @"video_layer_caption": @"disable_video_captions",
        @"autoHighestLoad": @"auto_highest_load",
        @"follow_con": @"follow_confirm",
        @"CopyProfileInfo": @"copy_profile_info",
        @"disableArticles": @"disable_articles",
        @"disableHighlights": @"disable_highlights",
        @"TweetToImage": @"tweet_to_image",
        @"like_con": @"like_confirm",
        @"tweet_con": @"tweet_confirm",
        @"disableSensitiveTweetWarnings": @"disable_sensitive_tweet_warnings",
        @"no_his": @"no_history",
        @"openInBrowser": @"always_open_safari",
        @"reply_sorting_enabled": @"reply_sorting",
        @"ios_in_app_article_webview_enabled": @"new_inapp_webview",
        @"tweet_url_host": @"sharing_domain",
    };

    // These old names double as Twitter's own feature-switch keys, so copy the
    // value across but leave the original in place rather than risk removing it.
    NSSet<NSString*>* sharedWithTwitter = [NSSet setWithArray:@[
        @"reply_sorting_enabled",
        @"ios_in_app_article_webview_enabled",
    ]];

    [renamedKeys enumerateKeysAndObjectsUsingBlock:^(
                     NSString* oldKey, NSString* newKey, BOOL* stop) {
        id value = [defaults objectForKey:oldKey];
        if (value == nil) {
            return;
        }
        if ([defaults objectForKey:newKey] == nil) {
            [defaults setObject:value forKey:newKey];
        }
        if (![sharedWithTwitter containsObject:oldKey]) {
            [defaults removeObjectForKey:oldKey];
        }
    }];

    [defaults setBool:YES forKey:@"nfb_key_migration_v1_done"];
}

// The Undo Tweet on/off toggle was merged into the timeout picker, where a
// timeout of 0 means off. Carry a prior "off" state across as a 0 timeout.
+ (void)migrateUndoTweetToggle {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"nfb_undo_timeout_migration_done"]) {
        return;
    }

    id oldToggle = [defaults objectForKey:@"undo_tweet"];
    if (oldToggle != nil && ![oldToggle boolValue] &&
        [defaults objectForKey:@"undo_tweet_timeout"] == nil) {
        [defaults setInteger:0 forKey:@"undo_tweet_timeout"];
    }
    [defaults removeObjectForKey:@"undo_tweet"];
    [defaults setBool:YES forKey:@"nfb_undo_timeout_migration_done"];
}

#pragma mark - Accessors

+ (NSArray<NSDictionary*>*)settingsForPage:(NSString*)pageKey {
    return pageKey ? BHTSettingsPages()[pageKey][@"settings"] : nil;
}

+ (NSArray<NSString*>*)allPageKeys {
    return BHTSettingsPageOrder();
}

+ (NSArray<NSDictionary*>*)allSearchableSettings {
    NSMutableArray<NSDictionary*>* settings = [NSMutableArray array];
    for (NSString* pageKey in BHTSettingsPageOrder()) {
        for (NSDictionary* setting in [self settingsForPage:pageKey]) {
            NSMutableDictionary* searchable = [setting mutableCopy];
            searchable[@"pageKey"] = pageKey;
            [settings addObject:[searchable copy]];
        }
    }
    return [settings copy];
}

+ (NSString*)titleKeyForPage:(NSString*)pageKey {
    return pageKey ? BHTSettingsPages()[pageKey][@"titleKey"] : nil;
}

+ (NSString*)subtitleKeyForPage:(NSString*)pageKey {
    return pageKey ? BHTSettingsPages()[pageKey][@"subtitleKey"] : nil;
}

+ (NSDictionary*)settingForKey:(NSString*)key {
    NSDictionary* setting = key ? BHTSettingsIndex()[key] : nil;
    if (setting) return setting;
    // Retain defaults for the two beta.8 keys after moving their user-facing
    // controls into the navigation editors.
    if ([key isEqualToString:@"enable_likes_tab"]) {
        return @{@"key": key, @"default": @NO};
    }
    if ([key isEqualToString:@"likes_media_waterfall"]) {
        return @{@"key": key, @"default": @YES};
    }
    return nil;
}

+ (BOOL)boolForKey:(NSString*)key {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value != nil) {
        return [value boolValue];
    }
    return [[self settingForKey:key][@"default"] boolValue];
}

+ (NSInteger)integerForKey:(NSString*)key {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value != nil) {
        return [value integerValue];
    }
    return [[self settingForKey:key][@"default"] integerValue];
}

+ (NSSet<NSString*>*)exportablePreferenceKeys {
    static NSSet<NSString*>* keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableSet<NSString*>* allowList = [NSMutableSet set];
        for (NSDictionary* setting in BHTSettingsIndex().allValues) {
            // Entries without defaults are navigation buttons or font-picker
            // affordances, not actual preferences.
            if (setting[@"default"] != nil && setting[@"key"] != nil &&
                ![setting[@"excludeFromProfile"] boolValue]) {
                [allowList addObject:setting[@"key"]];
            }
        }
        [allowList addObjectsFromArray:@[
            @"enable_likes_tab",
            @"likes_media_waterfall",
            @"bh_color_theme_selectedColor"
        ]];
        [allowList unionSet:BHTStringPreferenceKeys()];
        [allowList unionSet:BHTStringArrayPreferenceKeys()];
        [allowList unionSet:BHTKeywordArrayPreferenceKeys()];
        keys = [allowList copy];
    });
    return keys;
}

+ (NSDictionary*)preferenceProfile {
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary<NSString*, id>* preferences =
        [NSMutableDictionary dictionary];

    for (NSString* key in [self exportablePreferenceKeys]) {
        id value = [defaults objectForKey:key];
        NSDictionary* setting = [self settingForKey:key];
        if (!value && setting[@"default"] != nil) {
            value = setting[@"default"];
        }
        if (!value && [key isEqualToString:@"bh_color_theme_selectedColor"]) {
            NSInteger nativeOption =
                [defaults objectForKey:@"T1ColorSettingsPrimaryColorOptionKey"]
                    ? [defaults integerForKey:
                                   @"T1ColorSettingsPrimaryColorOptionKey"]
                    : 1;
            value = @(MIN(6, MAX(1, nativeOption)));
        }
        preferences[key] = value ?: NSNull.null;
    }

    NSISO8601DateFormatter* formatter = [NSISO8601DateFormatter new];
    return @{
        @"format": @"NeoFreeBird Preference Profile",
        @"formatVersion": @2,
        @"createdAt": [formatter stringFromDate:NSDate.date],
        @"preferences": [preferences copy],
        @"userThemes": [BHTThemePresets userThemes]
    };
}

+ (NSData*)preferenceProfileJSONDataWithError:(NSError**)error {
    return [NSJSONSerialization dataWithJSONObject:[self preferenceProfile]
                                           options:NSJSONWritingPrettyPrinted |
                                                   NSJSONWritingSortedKeys
                                             error:error];
}

+ (BOOL)applyPreferenceProfile:(NSDictionary*)profile error:(NSError**)error {
    id format = [profile isKindOfClass:NSDictionary.class]
                    ? profile[@"format"]
                    : nil;
    id formatVersion = [profile isKindOfClass:NSDictionary.class]
                           ? profile[@"formatVersion"]
                           : nil;
    NSInteger version = BHTProfileVersionIsExactly(formatVersion, 1)
                            ? 1
                            : (BHTProfileVersionIsExactly(formatVersion, 2)
                                   ? 2
                                   : NSNotFound);
    if (![profile isKindOfClass:NSDictionary.class] ||
        ![format isKindOfClass:NSString.class] ||
        ![format isEqualToString:@"NeoFreeBird Preference Profile"] ||
        (version != 1 && version != 2)) {
        if (error) {
            *error = BHTProfileError(
                1, @"This is not a supported NeoFreeBird preference profile.");
        }
        return NO;
    }

    NSDictionary* preferences = profile[@"preferences"];
    if (![preferences isKindOfClass:NSDictionary.class] ||
        preferences.count == 0 || preferences.count > 256) {
        if (error) {
            *error =
                BHTProfileError(2, @"The profile has no usable preferences.");
        }
        return NO;
    }

    NSArray<NSDictionary*>* mergedUserThemes =
        [BHTThemePresets userThemes];
    BOOL replacesUserThemes = version == 2;
    if (replacesUserThemes) {
        NSArray<NSDictionary*>* importedUserThemes =
            [BHTThemePresets
                validatedUserThemesFromObject:profile[@"userThemes"]
                                        error:error];
        if (!importedUserThemes) return NO;
        mergedUserThemes =
            [BHTThemePresets
                userThemesByMergingImportedThemes:importedUserThemes
                                            error:error];
        if (!mergedUserThemes) return NO;
    }

    NSSet<NSString*>* allowed = [self exportablePreferenceKeys];
    NSMutableDictionary<NSString*, id>* accepted =
        [NSMutableDictionary dictionary];
    for (id rawKey in preferences) {
        if (![rawKey isKindOfClass:NSString.class] ||
            ![allowed containsObject:rawKey]) {
            // Ignore preferences introduced by a newer NeoFreeBird build.
            continue;
        }
        NSString* key = rawKey;
        id value = preferences[key];
        if (value == NSNull.null) {
            accepted[key] = value;
            continue;
        }

        BOOL valid = NO;
        NSDictionary* setting = [self settingForKey:key];
        id defaultValue = setting[@"default"];
        if ([defaultValue isKindOfClass:NSNumber.class]) {
            if ([key isEqualToString:@"undo_tweet_timeout"] &&
                [value isKindOfClass:NSNumber.class]) {
                valid = [@[@0, @5, @10, @20, @30, @60]
                    containsObject:value];
            } else if ([value isKindOfClass:NSNumber.class]) {
                NSInteger boolValue = [value integerValue];
                valid = boolValue == 0 || boolValue == 1;
            }
        } else if ([BHTKeywordArrayPreferenceKeys() containsObject:key]) {
            valid = BHTIsValidKeywordArray(
                value,
                [key isEqualToString:
                         @"bht_for_you_username_filter_keywords"]);
        } else if ([BHTStringArrayPreferenceKeys() containsObject:key]) {
            valid = BHTIsStringArray(value);
        } else if ([BHTStringPreferenceKeys() containsObject:key]) {
            valid = [value isKindOfClass:NSString.class] &&
                    [(NSString*)value length] <= 256;
            if (valid && [key isEqualToString:@"bht_custom_accent_hex"]) {
                valid = BHTIsValidCustomAccent(value);
            } else if (valid &&
                       [key isEqualToString:
                                 @"bht_theme_preset_identifier"]) {
                valid =
                    [BHTThemePresets
                        isBuiltInPresetIdentifier:value] ||
                    BHTUserThemeIdentifierExists(
                        value, mergedUserThemes);
            }
        } else if ([key isEqualToString:@"enable_likes_tab"] ||
                   [key isEqualToString:@"likes_media_waterfall"]) {
            if ([value isKindOfClass:NSNumber.class]) {
                NSInteger boolValue = [value integerValue];
                valid = boolValue == 0 || boolValue == 1;
            }
        } else if ([key
                       isEqualToString:@"bh_color_theme_selectedColor"]) {
            if ([value isKindOfClass:NSNumber.class]) {
                NSInteger colorOption = [value integerValue];
                valid = colorOption >= 1 && colorOption <= 6;
            }
        }

        if (!valid) {
            if (error) {
                *error = BHTProfileError(
                    3, [NSString stringWithFormat:
                                     @"The value for “%@” is invalid.", key]);
            }
            return NO;
        }
        accepted[key] = value;
    }

    if (accepted.count == 0) {
        if (error) {
            *error =
                BHTProfileError(4, @"The profile contains no recognized settings.");
        }
        return NO;
    }

    // Validation completes before the first write, so a malformed profile can
    // never leave the preferences half imported.
    NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
    [accepted enumerateKeysAndObjectsUsingBlock:^(
                  NSString* key, id value, BOOL* stop) {
        if (value == NSNull.null) {
            [defaults removeObjectForKey:key];
        } else {
            [defaults setObject:value forKey:key];
        }
    }];
    if (replacesUserThemes &&
        ![BHTThemePresets replaceUserThemes:mergedUserThemes
                                      error:error]) {
        return NO;
    }
    [NSNotificationCenter.defaultCenter
        postNotificationName:BHTSettingsProfileDidApplyNotification
                      object:nil
                    userInfo:@{@"keys": accepted.allKeys}];
    return YES;
}

@end
