//
//  Theme.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import "Branding/BHTBranding.h"
#import "Compatibility/BHTCompatibilityReporter.h"
#import "Likes/BHTLikesTab.h"

// MARK: - Custom accent color

static NSNumber* selectedThemeColor(void) {
    return [NSUserDefaults.standardUserDefaults objectForKey:@"bh_color_theme_selectedColor"];
}

// Every apply path (launch re-apply, trait changes, both settings pickers)
// funnels through this setter, so coercing here keeps the custom color pinned.
%hook TAEColorSettings

- (void)setPrimaryColorOption:(NSInteger)colorOption {
    NSNumber* selectedColor = selectedThemeColor();
    %orig(selectedColor ? selectedColor.integerValue : colorOption);
}

- (NSInteger)primaryColorOption {
    NSNumber* selectedColor = selectedThemeColor();
    return selectedColor ? selectedColor.integerValue : %orig;
}

%end

void applySelectedThemeColor(void) {
    NSNumber* selectedColor = selectedThemeColor();
    if (selectedColor) {
        [[objc_getClass("TAEColorSettings") sharedSettings]
            setPrimaryColorOption:selectedColor.integerValue];
    }
}

// MARK: - Custom tab bar order and visibility

static NSString* scribePageForEntry(id<T1AppNavigationTabEntry> entry) {
    if (![entry respondsToSelector:@selector(tabView)]) {
        return nil;
    }
    return [entry tabView].scribePage;
}

// Operates on the tab ENTRIES, not the button views: the app derives both the
// buttons and their content view controllers from this one array.
static NSArray* orderedTabEntries(NSArray* entries) {
    entries = BHTEntriesByInstallingLikesDestination(entries);
    BHTRecordNavigationEntryClasses(entries);

    // Record the underlying tab views so the editor can show real titles and icons.
    NSMutableArray* tabViews = [NSMutableArray new];
    for (id<T1AppNavigationTabEntry> entry in entries) {
        T1TabView* tabView = [entry respondsToSelector:@selector(tabView)] ? [entry tabView] : nil;
        if (tabView) {
            [tabViews addObject:tabView];
        }
    }
    [CustomTabBarUtility recordTabViews:tabViews];

    NSArray<NSString*>* savedVisibleOrder =
        [CustomTabBarUtility visiblePageIDsInOrder];
    BOOL hasCustomOrder = savedVisibleOrder != nil;
    NSMutableArray<NSString*>* visibleOrder =
        [(savedVisibleOrder ?: [CustomTabBarUtility defaultVisiblePageIDs])
            mutableCopy];
    BOOL likesEnabled = [CustomTabBarUtility likesTabEnabled];
    NSUInteger likesIndex = [visibleOrder indexOfObject:BHTLikesPageID()];
    if (likesEnabled) {
        // Likes is its own entry. Keep Grok exactly where the user placed it
        // and add Likes to the default layout without replacing any native tab.
        if (!hasCustomOrder && likesIndex == NSNotFound) {
            [visibleOrder addObject:BHTLikesPageID()];
        }
    } else if (likesIndex != NSNotFound) {
        [visibleOrder removeObjectAtIndex:likesIndex];
    }

    NSMutableDictionary<NSString*, id>* entriesByPage = [NSMutableDictionary new];
    for (id<T1AppNavigationTabEntry> entry in entries) {
        NSString* page = scribePageForEntry(entry);
        if (page && !entriesByPage[page]) {
            entriesByPage[page] = entry;
        }
    }

    // Not customised yet: show the default set (Home, Search, Notifications, Chats)
    // in that order, hiding everything else the app builds.
    if (!hasCustomOrder) {
        NSMutableArray* defaultEntries = [NSMutableArray new];
        for (NSString* pageID in visibleOrder) {
            id entry = entriesByPage[pageID];
            if (entry) {
                [defaultEntries addObject:entry];
            }
        }
        return defaultEntries;
    }

    // Only the chosen tabs show; anything the editor hasn't been told to show
    // (including tabs unlocked after the user last saved) stays hidden.
    NSMutableArray* orderedEntries = [NSMutableArray new];
    NSMutableSet* placed = [NSMutableSet new];
    for (NSString* pageID in visibleOrder) {
        id entry = entriesByPage[pageID];
        if (entry && ![placed containsObject:pageID]) {
            [orderedEntries addObject:entry];
            [placed addObject:pageID];
        }
    }

    return orderedEntries;
}

// The single ordered spine that feeds both the tab buttons and their content, so
// filtering/reordering here keeps taps mapped to the right panel.
%hook T1TabbedAppNavigationViewController

- (void)setVisibleTabEntries:(NSArray*)entries {
    %orig(orderedTabEntries(entries));
}

%end

// MARK: - Keep tab bar visible

static BOOL shouldPinCollapsibleTabBar(
    T1TabBarViewController* controller) {
    if (![BHTSettings boolForKey:@"no_tab_bar_hiding"]) {
        return NO;
    }

    UIUserInterfaceIdiom idiom =
        controller.traitCollection.userInterfaceIdiom;
    if (idiom == UIUserInterfaceIdiomUnspecified) {
        idiom = UIDevice.currentDevice.userInterfaceIdiom;
    }

    // On iPad the same "collapse ratio" drives the vertical rail between its
    // compact and expanded widths; it is not the phone's scroll-to-hide
    // animation. Pinning that value locks the rail in its narrow icon-only
    // state and can fight X's split-view relayouts. The iPad rail already stays
    // on-screen, so preserve its native expansion state.
    return idiom != UIUserInterfaceIdiomPad;
}

static void BHTUpdateAdaptiveRailBranding(
    T1TabBarViewController* controller);

%hook T1TabBarViewController

// X 12.9 consults these capabilities before sending collapse-ratio updates.
- (BOOL)tfn_supportsTabBarCollapsing {
    return shouldPinCollapsibleTabBar(self) ? NO : %orig;
}

- (BOOL)tfn_prefersTabBarPinned {
    return shouldPinCollapsibleTabBar(self) ? YES : %orig;
}

// The scroll-driven hide only reaches the tab bar as a collapse ratio, so
// clamping it spares the deliberate hides (fullscreen media, immersive player).
- (void)setTabBarCollapseRatio:(double)ratio {
    if (shouldPinCollapsibleTabBar(self)) {
        %orig(0.0);
    } else {
        %orig(ratio);
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    BHTUpdateAdaptiveRailBranding(self);
}

- (void)_t1_syncNativeTabBarItems {
    %orig;
    BHTUpdateAdaptiveRailBranding(self);
}

- (void)_t1_syncNativeTabBarSelection {
    %orig;
    BHTUpdateAdaptiveRailBranding(self);
}

%end

// MARK: - Tab bar icon and label theming

static BOOL updatingTabIconColor = NO;

static UIColor* tabItemColor(BOOL selected) {
    return selected ? CurrentAccentColor() : [UIColor secondaryLabelColor];
}

%hook T1TabView

- (void)_t1_updateImageViewAnimated:(BOOL)animated {
    // setIconColor: re-enters this method, so swallow the inner call and let
    // %orig below render once with the new color
    if (updatingTabIconColor) {
        return;
    }

    updatingTabIconColor = YES;
    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        self.iconColor = tabItemColor(self.selected);
    } else if (self.iconColor) {
        self.iconColor = nil;
    }
    updatingTabIconColor = NO;

    %orig(animated);
}

- (void)_t1_updateTitleLabel {
    %orig;

    if ([BHTSettings boolForKey:@"tab_bar_theming"]) {
        self.titleLabel.textColor = tabItemColor(self.selected);
    }
}

- (BOOL)showsTitleInDisplayMode:(long long)displayMode {
    if ([BHTSettings boolForKey:@"restore_tab_labels"]) {
        return YES;
    }
    return %orig;
}

%new
- (void)applyCurrentThemeToIcon {
    [self _t1_updateImageViewAnimated:NO];
    [self _t1_updateTitleLabel];
}

%end

// MARK: - Home and iPad rail branding

static char kBHTOriginalRailLogoImageKey;
static char kBHTOriginalRailLogoTintKey;

static BOOL BHTUsesPadNavigation(UIViewController* controller) {
    UIUserInterfaceIdiom idiom =
        controller.traitCollection.userInterfaceIdiom;
    if (idiom == UIUserInterfaceIdiomUnspecified) {
        idiom = UIDevice.currentDevice.userInterfaceIdiom;
    }
    return idiom == UIUserInterfaceIdiomPad;
}

static NSMapTable<T1TabBarViewController*, UIImageView*>*
BHTAdaptiveRailLogoCache(void) {
    static NSMapTable* cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSMapTable weakToWeakObjectsMapTable];
    });
    return cache;
}

static UIImageView* BHTAdaptiveRailLogoView(
    T1TabBarViewController* controller) {
    if (!controller.isViewLoaded || !BHTUsesPadNavigation(controller)) {
        return nil;
    }

    UIView* root = controller.view;
    UIImageView* cached =
        [BHTAdaptiveRailLogoCache() objectForKey:controller];
    if (cached && [cached isDescendantOfView:root]) {
        return cached;
    }

    UIEdgeInsets safeArea = root.safeAreaInsets;
    // The controller can own either the full iPad canvas or only the narrow
    // rail. Keep a rail-width-safe minimum so a 50–65 pt centered logo is not
    // excluded when the root itself is roughly 100–130 pt wide.
    CGFloat maximumX =
        MIN(120.0,
            MAX(76.0, CGRectGetWidth(root.bounds) * 0.12));
    CGFloat maximumY = MAX(76.0, safeArea.top + 68.0);
    __block UIImageView* best = nil;
    __block CGFloat bestScore = CGFLOAT_MAX;

    EnumerateSubviewsRecursively(root, ^(UIView* candidate) {
        if (![candidate isKindOfClass:UIImageView.class] ||
            candidate.hidden || candidate.alpha < 0.05) {
            return;
        }
        UIImageView* imageView = (UIImageView*)candidate;
        if (!imageView.image) return;
        CGRect rect = [imageView convertRect:imageView.bounds toView:root];
        CGFloat width = CGRectGetWidth(rect);
        CGFloat height = CGRectGetHeight(rect);
        if (width < 16.0 || height < 16.0 ||
            width > 68.0 || height > 68.0 ||
            fabs(width - height) > 12.0 ||
            CGRectGetMidX(rect) > maximumX ||
            CGRectGetMidY(rect) > maximumY) {
            return;
        }

        // The rail mark is the first square image below the status area.
        // Scoring instead of relying on a private class name keeps this valid
        // for both compact and expanded iPad split-view layouts.
        CGFloat targetY = safeArea.top + 30.0;
        CGFloat score = fabs(CGRectGetMidY(rect) - targetY) +
                        CGRectGetMidX(rect) * 0.08;
        if (score < bestScore) {
            best = imageView;
            bestScore = score;
        }
    });
    if (best) {
        [BHTAdaptiveRailLogoCache() setObject:best
                                       forKey:controller];
    }
    return best;
}

static void BHTUpdateAdaptiveRailBranding(
    T1TabBarViewController* controller) {
    UIImageView* logoView = BHTAdaptiveRailLogoView(controller);
    if (!logoView) return;

    BOOL enabled =
        [BHTSettings boolForKey:@"color_twitter_icon_in_top_bar"];
    UIImage* originalImage =
        objc_getAssociatedObject(logoView,
                                 &kBHTOriginalRailLogoImageKey);
    if (enabled) {
        if (!originalImage && logoView.image) {
            objc_setAssociatedObject(
                logoView, &kBHTOriginalRailLogoImageKey,
                logoView.image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (logoView.tintColor) {
                objc_setAssociatedObject(
                    logoView, &kBHTOriginalRailLogoTintKey,
                    logoView.tintColor,
                    OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        BHTApplyTwitterBirdToImageView(logoView, CurrentAccentColor());
    } else if (originalImage) {
        logoView.image = originalImage;
        UIColor* originalTint =
            objc_getAssociatedObject(logoView,
                                     &kBHTOriginalRailLogoTintKey);
        if (originalTint) logoView.tintColor = originalTint;
        objc_setAssociatedObject(
            logoView, &kBHTOriginalRailLogoImageKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            logoView, &kBHTOriginalRailLogoTintKey, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook _TtC11TwitterHome39HomeDefaultNavigationBarTitleViewPlugin

- (UIView*)titleView {
    UIView* titleView = %orig;

    if ([BHTSettings boolForKey:@"color_twitter_icon_in_top_bar"] &&
        [titleView isKindOfClass:[UIImageView class]]) {
        UIImageView* logoView = (UIImageView*)titleView;
        BHTApplyTwitterBirdToImageView(logoView, CurrentAccentColor());
    }

    return titleView;
}

%end
