#!/usr/bin/env python3
"""Check source invariants that protect the X 12.9 compatibility fixes."""

from collections import Counter
from pathlib import Path
import re
import struct


ROOT = Path(__file__).resolve().parent.parent
SETTINGS = ROOT / "src" / "Core" / "BHTSettings.m"
ENGLISH = (
    ROOT
    / "layout"
    / "Library"
    / "Application Support"
    / "BHT"
    / "BHTwitter.bundle"
    / "en.lproj"
    / "Localizable.strings"
)
BUNDLE = ENGLISH.parents[1]
THEME_BUILDER = (
    ROOT
    / "src"
    / "ThemeColor"
    / "BHTThemeBuilderViewController.m"
)
THEME_BUILDER_HEADER = THEME_BUILDER.with_suffix(".h")


def png_size(path: Path) -> tuple[int, int]:
    raw = path.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n" or raw[12:16] != b"IHDR":
        raise AssertionError(f"{path} is not a PNG")
    return struct.unpack(">II", raw[16:24])


def relative_luminance(hex_color: str) -> float:
    channels = [
        int(hex_color[offset : offset + 2], 16) / 255
        for offset in (1, 3, 5)
    ]
    linear = [
        channel / 12.92
        if channel <= 0.04045
        else ((channel + 0.055) / 1.055) ** 2.4
        for channel in channels
    ]
    return (
        0.2126 * linear[0]
        + 0.7152 * linear[1]
        + 0.0722 * linear[2]
    )


def contrast_ratio(first: str, second: str) -> float:
    first_luminance = relative_luminance(first)
    second_luminance = relative_luminance(second)
    lighter = max(first_luminance, second_luminance)
    darker = min(first_luminance, second_luminance)
    return (lighter + 0.05) / (darker + 0.05)


def source_section(
    source: str, start: str, end: str, description: str
) -> str:
    """Return a bounded source section with a useful invariant failure."""
    if start not in source:
        raise AssertionError(
            f"Could not inspect {description}; its source boundaries moved"
        )
    remainder = source.split(start, 1)[1]
    if end not in remainder:
        raise AssertionError(
            f"Could not inspect {description}; its source boundaries moved"
        )
    return remainder.split(end, 1)[0]


def require_source_tokens(
    source: str, required: tuple[str, ...], description: str
) -> None:
    for token in required:
        if token not in source:
            raise AssertionError(f"Missing {description}: {token}")


def main() -> None:
    settings_source = SETTINGS.read_text(encoding="utf-8")
    english_source = ENGLISH.read_text(encoding="utf-8")
    localized_keys = set(
        re.findall(r'^\s*"([^"]+)"\s*=', english_source, re.MULTILINE)
    )
    localized_key_list = re.findall(
        r'^\s*"([^"]+)"\s*=', english_source, re.MULTILINE
    )
    duplicate_localizations = sorted(
        key
        for key, count in Counter(localized_key_list).items()
        if count > 1
    )
    if duplicate_localizations:
        raise AssertionError(
            f"Duplicate English localization keys: "
            f"{duplicate_localizations}"
        )
    missing_login_report_localizations = sorted(
        {
            "COMPATIBILITY_SIGN_IN_SHARE_REPORT",
            "COMPATIBILITY_SIGN_IN_REPORT_ERROR",
            "COMPATIBILITY_SIGN_IN_NETWORK_ERROR",
        }
        - localized_keys
    )
    if missing_login_report_localizations:
        raise AssertionError(
            "Missing pre-login report localizations: "
            f"{missing_login_report_localizations}"
        )

    setting_keys = re.findall(
        r'@"key"\s*:\s*@"([^"]+)"', settings_source
    )
    duplicates = sorted(
        key for key, count in Counter(setting_keys).items() if count > 1
    )
    if duplicates:
        raise AssertionError(f"Duplicate setting keys: {duplicates}")

    section_keys = set(
        re.findall(r'@"sectionKey"\s*:\s*@"([^"]+)"', settings_source)
    )
    missing_sections = sorted(section_keys - localized_keys)
    if missing_sections:
        raise AssertionError(
            f"Unlocalized settings sections: {missing_sections}"
        )

    compact_keys = {
        "regular_font_button",
        "bold_font_button",
        "undo_tweet_timeout",
    }
    missing_titles = sorted(
        key
        for key in setting_keys
        if key not in compact_keys
        and f"{key.upper()}_TITLE" not in localized_keys
    )
    missing_details = sorted(
        key
        for key in setting_keys
        if key not in compact_keys
        and f"{key.upper()}_DETAIL" not in localized_keys
    )
    if missing_titles or missing_details:
        raise AssertionError(
            f"Missing setting strings: titles={missing_titles}, "
            f"details={missing_details}"
        )

    parent_keys = set(
        re.findall(r'@"parentKey"\s*:\s*@"([^"]+)"', settings_source)
    )
    missing_parents = sorted(parent_keys - set(setting_keys))
    if missing_parents:
        raise AssertionError(
            f"Unknown parent setting keys: {missing_parents}"
        )

    expected_birds = {
        "twitter_bird.png": (24, 24),
        "twitter_bird@2x.png": (48, 48),
        "twitter_bird@3x.png": (72, 72),
    }
    for filename, expected_size in expected_birds.items():
        if png_size(BUNDLE / filename) != expected_size:
            raise AssertionError(f"{filename} has the wrong dimensions")

    source_files = list((ROOT / "src").rglob("*.m"))
    source_files.extend((ROOT / "src").rglob("*.x"))
    for path in source_files:
        source = path.read_text(encoding="utf-8")
        relative = path.relative_to(ROOT).as_posix()
        if (
            "NSTemporaryDirectory()" in source
            and relative != "src/Core/BHTManager.m"
        ):
            raise AssertionError(
                f"Temporary exports must use BHTManager: {relative}"
            )
        if "performChangesAndWait" in source:
            raise AssertionError(f"Blocking Photos save remains in {relative}")

    profile_source = (ROOT / "src" / "Hooks" / "Profile.x").read_text(
        encoding="utf-8"
    )
    if "- (BOOL)isProfileTranslationEnabled" in profile_source:
        raise AssertionError("Unavailable X 12.9 profile selector is hooked")

    page_source = (
        ROOT / "src" / "Settings" / "ModernSettingsPageViewController.m"
    ).read_text(encoding="utf-8")
    for unsafe_key in ('@"prefKey"', '@"fontType"'):
        if unsafe_key in page_source:
            raise AssertionError(
                f"Associated-object literal key remains: {unsafe_key}"
            )

    theme_source = (ROOT / "src" / "Hooks" / "Theme.x").read_text(
        encoding="utf-8"
    )
    for required in (
        "UIUserInterfaceIdiomPad",
        "T1TabBarHostView",
        "BHTRailHeaderLogoImageView",
        "BHTGuardedRailHeaderImageScan",
        "BHTRailHeaderCandidateBelongsToTab",
        "kBHTRailResolvedLogoViewKey",
        "kBHTOriginalRailLogoStateCapturedKey",
        "kBHTOriginalRailLogoAccessibilityLabelKey",
        "CGRectGetMaxY(frame) > headerBottom",
        '@"guardedHeaderScan"',
        "BHTThemeDidChangeNotification",
        "logoView.hidden = enabled && usesPadRail",
    ):
        if required not in theme_source:
            raise AssertionError(f"Missing compatibility fix: {required}")
    branding_theme_observer = source_section(
        theme_source,
        "static void BHTInstallBrandingThemeObserver(void)",
        "static BOOL BHTRailHeaderCandidateIsVisible",
        "branding theme observer",
    )
    require_source_tokens(
        branding_theme_observer,
        (
            "BHTThemeDidChangeNotification",
            "BHTSettingsProfileDidApplyNotification",
        ),
        "live bird-tint refresh notification",
    )
    if "BHTAdaptiveRailLogoView" in theme_source:
        raise AssertionError(
            "Geometry-based rail branding can replace the Home tab icon"
        )
    compatibility_source = (
        ROOT / "src" / "Compatibility" / "BHTCompatibilityReporter.m"
    ).read_text(encoding="utf-8")
    for required in (
        'BHTProbe(@"appearance", @"T1TabBarHostView", @"logoImageView", NO)',
        'BHTProbe(@"appearance", @"T1TabBarHostView", @"tabBarViewController", NO)',
        'BHTProbe(@"appearance", @"TAEColorSettings", @"currentColorPalette", NO)',
        'BHTProbe(@"appearance", @"T1ColorSettings", @"_t1_applyTheme", YES)',
        '@"railBrandingRuntime": BHTRailBrandingObservationSnapshot()',
        '@"themeRuntime": BHTThemeRuntimeObservationSnapshot()',
        '@"forYouFilterRuntime": BHTForYouFilterDiagnosticSnapshot()',
        "atomic_fetch_add_explicit(",
        "BHTForYouControllerRuntimeShape",
        '@"timelineMethods"',
        '@"timelineIvars"',
        '@"dataViewControllerAccessorPresent"',
        '@"dataViewControllerIvarPresent"',
        '@"directOwnerResolvedChecks"',
        '@"directOwnerMissingChecks"',
        '@"trustedTextCandidateSetsNonEmpty"',
        '@"mentionHandleCandidatesExtracted"',
        '@"renderRowCollapses"',
        '@"renderReloads"',
        '@"inheritsItemsDataViewController"',
        '@"itemRowHeight"',
        '@"estimatedItemRowHeight"',
        '@"filterExecutionPolicy"',
        '@"unknownSectionOwnerFailsOpen"',
        '@"configurationGeneration"',
        '@"seenPaletteCount"',
        '@"providerClasses"',
        '@"dynamicColorsDidReloadObserved"',
        'BHTProbe(@"appearance", @"UIColor", @"twitterColors", YES)',
        'BHTProbe(@"appearance", @"UIColor", @"setTwitterColors:", YES)',
        'BHTProbe(@"appearance", @"UIColor", @"tfnuiColors", YES)',
        'BHTProbe(@"appearance", @"UIColor", @"xds_backgroundPrimary", YES)',
        'BHTProbe(@"appearance", @"UIColor", @"xds_backgroundSheets", YES)',
        'BHTProbe(@"appearance", @"UIColor", @"colorNamed:inBundle:compatibleWithTraitCollection:", YES)',
        "BHTRailBrandingObservationState",
        "if (unchanged) return;",
    ):
        if required not in compatibility_source:
            raise AssertionError(
                f"Missing branding/theme compatibility probe: {required}"
            )
    theme_diagnostic = source_section(
        compatibility_source,
        "void BHTRecordThemeRuntimeObservation(",
        "void BHTRecordMediaActionObservation(",
        "theme compatibility diagnostic",
    )
    require_source_tokens(
        theme_diagnostic,
        (
            "[BHTThemePresets isUserPresetIdentifier:presetIdentifier]",
            '@"activePreset": reportedPreset',
        ),
        "custom-theme diagnostic privacy mask",
    )
    if not re.search(
        r"isUserPresetIdentifier:presetIdentifier\]\s*"
        r'\?\s*@"user_theme"',
        theme_diagnostic,
    ):
        raise AssertionError(
            "Compatibility diagnostics must mask every custom theme as "
            "user_theme"
        )
    for private_lookup in (
        '@"activePreset": presetIdentifier',
        "displayNameForPreset:",
        "presetForIdentifier:",
    ):
        if private_lookup in theme_diagnostic:
            raise AssertionError(
                "Compatibility diagnostics must not expose a custom theme "
                f"name or persistent identifier: {private_lookup}"
            )

    authentication_source = (
        ROOT / "src" / "Security" / "BHTAuthenticationURLUtility.m"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        authentication_source,
        (
            "BHTDeclaredAuthenticationSchemes",
            '@"CFBundleURLTypes"',
            '@"CFBundleURLSchemes"',
            '@"twitterauth"',
            '@"com.googleusercontent.apps."',
            '@"accounts.x.com"',
            '@"accounts.twitter.com"',
            '@"accounts.google.com"',
            '@"appleid.apple.com"',
            '@"/account"',
            '@"/login"',
            '@"/i/flow"',
            '@"/i/oauth2"',
            '@"/oauth"',
            '@"oauth_token"',
            '@"oauth_verifier"',
            '@"oauth_callback"',
            '@"redirect_uri"',
            '@"redirect_after_login"',
            "BHTHostMatchesDomain",
            "BHTPathEqualsOrDescendsFrom",
        ),
        "authentication URL preservation policy",
    )
    authentication_diagnostic = source_section(
        authentication_source,
        "BHTAuthenticationRoutingDiagnosticSnapshot(void)",
        "return [snapshot copy];",
        "authentication routing diagnostic",
    )
    for private_value in (
        "absoluteString",
        "components.host",
        "components.path",
        "components.query",
        "CFBundleURLSchemes",
        "BHTDeclaredAuthenticationSchemes",
    ):
        if private_value in authentication_diagnostic:
            raise AssertionError(
                "Authentication routing diagnostics must contain only "
                f"aggregate counters: {private_value}"
            )
    misc_source = (
        ROOT / "src" / "Hooks" / "Misc.x"
    ).read_text(encoding="utf-8")
    if misc_source.count(
        "BHTShouldKeepAuthenticationURLInApp(url)"
    ) != 2:
        raise AssertionError(
            "Both in-app browser routing hooks must preserve "
            "authentication URLs"
        )
    if "containsString:@\"twitter.com/account/\"" in misc_source:
        raise AssertionError(
            "Authentication routing must use parsed URL components, "
            "not substring matching"
        )

    compatibility_login_header = (
        ROOT / "src" / "Login" / "BHTCompatibilityLogin.h"
    ).read_text(encoding="utf-8")
    compatibility_login_source = (
        ROOT / "src" / "Login" / "BHTCompatibilityLogin.m"
    ).read_text(encoding="utf-8")
    compatibility_report_header = (
        ROOT / "src" / "Compatibility" / "BHTCompatibilityReporter.h"
    ).read_text(encoding="utf-8")
    compatibility_login_hook = (
        ROOT / "src" / "Hooks" / "CompatibilityLogin.x"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        compatibility_login_header,
        (
            "BHTCompatibilitySignInIsAvailable",
            "BHTPresentCompatibilitySignIn",
            "BHTPresentCompatibilitySignInForAddingAccount",
            "BHTInstallCompatibilitySignInEntry",
            "BHTInstallCompatibilityAddAccountSignInEntry",
            "BHTCompatibilitySignInDiagnosticSnapshot",
            "guarded X 12.9 compatibility password flow",
            "Successful accounts are registered and switched through X's account APIs",
        ),
        "compatibility sign-in public contract",
    )

    version_gate = source_section(
        compatibility_login_source,
        "static BOOL BHTCompatibilityVersionIsSupported(void)",
        "static BOOL BHTClassResponds(",
        "compatibility sign-in version gate",
    )
    require_source_tokens(
        compatibility_login_source,
        (
            'BHTCompatibilityTargetVersion = @"12.9"',
            "static void BHTLoadCompatibilityFrameworkIfNeeded(void)",
            '@"TwitterSPMMigration.framework"',
            '@"TwitterSPMMigration"',
            "RTLD_LAZY | RTLD_LOCAL",
            "dlsym(\n            BHTCompatibilityFrameworkHandle,",
            "static NSArray<NSString*>*\n"
            "BHTMissingCompatibilityRequirements(void)",
            "static BOOL BHTCompatibilityRuntimeIsAvailable(void)",
            "if (!BHTCompatibilityVersionIsSupported()) {",
            "BHTLoadCompatibilityFrameworkIfNeeded();",
            "return "
            "BHTMissingCompatibilityRequirements().count == 0;",
            "return BHTCompatibilityRuntimeIsAvailable();",
        ),
        "hard X 12.9 compatibility gate",
    )
    require_source_tokens(
        version_gate,
        (
            "BHTAppVersion()",
            "isEqualToString:BHTCompatibilityTargetVersion",
        ),
        "exact X 12.9 version comparison",
    )

    missing_runtime_requirements = source_section(
        compatibility_login_source,
        "static NSArray<NSString*>*\n"
        "BHTMissingCompatibilityRequirements(void)",
        "static BOOL BHTCompatibilityRuntimeIsAvailable(void)",
        "privacy-safe compatibility runtime requirements",
    )
    expected_requirement_ids = [
        "appVersion",
        "guestIdentifier",
        "commandClass",
        "serviceRunnerClass",
        "requestConfigurationClass",
        "authStorageClass",
        "resultBuilderClass",
        "accountClass",
        "accountManagerClass",
        "hostControllerClass",
        "challengeFactoryClass",
        "serviceContextMethod",
        "serviceLoaderMethod",
        "requestConfigurationMethod",
        "knownDeviceMethod",
        "accountABI",
        "sharedAccountManagerMethod",
        "saveAccountManagerMethod",
        "hostSwitchABI",
        "commandABI",
    ]
    emitted_requirement_ids = re.findall(
        r'\[missing addObject:@"([^"]+)"\];',
        missing_runtime_requirements,
    )
    if emitted_requirement_ids != expected_requirement_ids:
        raise AssertionError(
            "Compatibility diagnostics must emit only the ordered, "
            "fixed runtime-requirement identifiers: "
            f"{emitted_requirement_ids}"
        )
    if missing_runtime_requirements.count("[missing addObject:") != len(
        expected_requirement_ids
    ):
        raise AssertionError(
            "Compatibility diagnostics must not add dynamic runtime "
            "values to the missing-requirements list"
        )
    require_source_tokens(
        missing_runtime_requirements,
        (
            "BHTLoadCompatibilityFrameworkIfNeeded();",
            "BHTGuestAccountIdentifier()",
            "BHTClassResponds(",
            "BHTNativeAccountSignaturesAreSupported()",
            "BHTHostAccountSwitchSignatureIsSupported()",
            "BHTPasswordCommandSignatureIsSupported()",
            "return [missing copy];",
        ),
        "single-source compatibility runtime probes",
    )

    require_source_tokens(
        compatibility_login_hook,
        (
            '#import "Sidebar/BHTSidebarNavigationUtility.h"',
            "%hook T1HostViewController",
            "makeOnboardingViewControllerWithCompletion:",
            "void (^wrappedCompletion)(UIViewController*)",
            "BHTInstallCompatibilitySignInEntry(controller);",
            "completion(controller);",
            "%orig(wrappedCompletion);",
            "%hook T1AccountsViewController",
            "- (void)viewWillAppear:(BOOL)animated {",
            "- (void)viewDidAppear:(BOOL)animated {",
            "BHTInstallCompatibilityAddAccountSignInEntry(self);",
            'NSClassFromString(@"T1AccountsViewController")',
            "@selector(viewWillAppear:)",
            "@selector(viewDidAppear:)",
            "refreshRegisteredDashContentControllers",
            "%init(BHTCompatibilityAddAccountHooks);",
        ),
        "native onboarding and add-account entry wrappers",
    )
    if "BHTInstallCompatibilityXAuthClientMetadataOverride" in (
        compatibility_login_header + compatibility_login_hook
    ):
        raise AssertionError(
            "Beta 43 must not install the experimental X 12.3 metadata "
            "override"
        )
    if "private_startLoginFlowWithSender:" in compatibility_login_hook:
        raise AssertionError(
            "Compatibility sign-in must not replace X's native login action"
        )
    install_position = compatibility_login_hook.index(
        "BHTInstallCompatibilitySignInEntry(controller);"
    )
    completion_position = compatibility_login_hook.index(
        "completion(controller);"
    )
    original_position = compatibility_login_hook.index(
        "%orig(wrappedCompletion);"
    )
    if not install_position < completion_position < original_position:
        raise AssertionError(
            "Compatibility sign-in must decorate and forward X's native "
            "onboarding completion"
        )

    for removed_metadata_token in (
        "BHTCompatibilityXAuthAllHTTPHeaderFields",
        "BHTCompatibilityXAuthClientVersion",
        "BHTCompatibilityClientVersionHeader",
        "X-Twitter-Client-Version",
        '@"TFSTwitterAPIXAuthPasswordRequest"',
        "BHTEndCompatibilityClientMetadataScope",
    ):
        if removed_metadata_token in compatibility_login_source:
            raise AssertionError(
                "Beta 43 must use X 12.9's native password-request "
                f"metadata: {removed_metadata_token}"
            )
    if "T1APIRequestHeaderProvider" in compatibility_login_source:
        raise AssertionError(
            "Compatibility client metadata must not hook X's global header "
            "provider"
        )
    add_account_did_appear = source_section(
        compatibility_login_hook,
        "- (void)viewDidAppear:(BOOL)animated {",
        "%end",
        "add-account post-appearance reconciliation",
    )
    if (
        add_account_did_appear.find(
            "BHTInstallCompatibilityAddAccountSignInEntry(self);"
        )
        > add_account_did_appear.find(
            "refreshRegisteredDashContentControllers"
        )
    ):
        raise AssertionError(
            "Add Account must restore its own action before reconciling the "
            "saved sidebar layout"
        )

    password_signature = source_section(
        compatibility_login_source,
        "static BOOL BHTPasswordCommandSignatureIsSupported(void)",
        "static NSArray<NSString*>*\n"
        "BHTMissingCompatibilityRequirements(void)",
        "X password command signature guard",
    )
    require_source_tokens(
        password_signature,
        (
            '@"TFSTwitterAPIXAuthPasswordCommand"',
            '@"initWithContext:accountID:authContext:identifier:"',
            '"password:simCountryCode:httpRequestConfiguration:"',
            '"supportOneFactorAuthorization:knownDeviceToken:"',
            '"uiMetrics:authTokenStorage:source:responseModelBuilder:"',
            '"completionBlock:"',
            "signature.numberOfArguments != 16",
            "returnType[0] != '@'",
            "BHTSignatureArgumentIsObject",
            "BHTSignatureArgumentIsBoolean(signature, 9)",
            "for (NSUInteger index = 10; index <= 12; index++)",
            "BHTSignatureArgumentIsNSUInteger(signature, 13)",
            "for (NSUInteger index = 14; index <= 15; index++)",
        ),
        "exact native X password-command signature",
    )
    require_source_tokens(
        compatibility_login_source,
        (
            "static BOOL BHTSignatureArgumentIsNSUInteger(",
            "strcmp(type, @encode(NSUInteger)) == 0",
        ),
        "architecture-correct X source-argument ABI guard",
    )
    password_command = source_section(
        compatibility_login_source,
        "static id BHTCreatePasswordCommand(",
        "static BOOL BHTStartPasswordCommand(",
        "guarded password command construction",
    )
    require_source_tokens(
        password_command,
        (
            "BHTPasswordCommandSignatureIsSupported()",
            "id<BHTXAuthPasswordCommandInitializing> allocatedCommand",
            "return [allocatedCommand",
            "initWithContext:context",
            "accountID:accountID",
            "authContext:authContext",
            "identifier:identifier",
            "password:password",
            "simCountryCode:simCountryCode",
            "httpRequestConfiguration:requestConfiguration",
            "supportOneFactorAuthorization:"
            "supportOneFactorAuthorization",
            "knownDeviceToken:knownDeviceToken",
            "uiMetrics:metrics",
            "authTokenStorage:authTokenStorage",
            "NSUInteger source = 0;",
            "source:source",
            "responseModelBuilder:responseBuilder",
            "completionBlock:completionBlock",
        ),
        "typed password-command construction behind the ABI guard",
    )
    if "NSInvocation" in compatibility_login_source:
        raise AssertionError(
            "Compatibility sign-in must not invoke an ARC-owned private "
            "initializer through NSInvocation"
        )
    for stale_source_contract in (
        "source:(id _Nullable)source",
        "id source = nil;",
    ):
        if stale_source_contract in compatibility_login_source:
            raise AssertionError(
                "X 12.9 source: must remain an NSUInteger with the "
                f"native-compatible value 0: {stale_source_contract}"
            )
    require_source_tokens(
        compatibility_login_source,
        (
            "@protocol BHTXAuthPasswordCommandInitializing",
            "@protocol BHTNativeAccountInitializing",
            "v28@?0B8@12@20",
            "initWithContext:(id)context",
            "source:(NSUInteger)source",
            "(void (^)(BOOL success, id response, id error))completion;",
            "completionBlock:",
        ),
        "typed private password-command initializer contract",
    )

    require_source_tokens(
        compatibility_login_source,
        (
            '"TFSTwitterAPIGuestAccountID"',
            '@"TFSTwitterServiceRunner"',
            '@"APICommandContext"',
            '@"APICommandLoader"',
            '@"startCommand:"',
            '@"TNUServiceHTTPConfiguration"',
            '@"configurationForForegroundRetriableRequest"',
            '@"T1OnboardingAuthTokenStorage"',
            '@"TFSTwitterXAuthPasswordResponseBuilder"',
            '@"TFNTwitterAccount"',
            '@"initWithUsername:userID:"',
            '@"updateUserInfoAndCredentialsWithToken:secret:username:"',
            '@"TFNTwitter"',
            '@"sharedTwitter"',
            '@"accountService"',
            '@"addAccount:"',
            '@"saveSharedTwitter"',
            '@"viewAccount:animated:"',
            '@"TFSAccountNotification"',
            '@"TFSAccountsDidChange"',
            '@"T1LoginChallengeFactory"',
            '@"loginVerificationRequestId"',
            '@"challengeURLString"',
            '@"loginChallengeWithMode:loginType:requestID:user:"',
            '"userID:URLString:loginCause:"',
            '@"loginVerificationRequestType"',
            '@"loginVerificationRequestCause"',
            '@"loginVerificationUserId"',
            '@"setDidAddAccountBlock:"',
            '@"setLoginChallengeProvider:"',
            '@"presentLoginChallengeFromViewController:animated:completion:"',
        ),
        "native X account and challenge integration selectors",
    )
    require_source_tokens(
        compatibility_login_source,
        (
            "BHTNativeAccountSignaturesAreSupported",
            "BHTLoginChallengeFactorySignatureIsSupported",
            "BHTHostAccountSwitchSignatureIsSupported",
            "NSInteger mode = securityKeyEnabled ? 1 : 0;",
            "postNotificationName:notificationName",
            "object:twitter",
        ),
        "native account and challenge ABI guards",
    )
    challenge_completion = source_section(
        compatibility_login_source,
        "void (^didAddAccount)(id, id) =",
        "SEL setProvider =",
        "native challenge account completion",
    )
    register_position = challenge_completion.index(
        "BHTRegisterNativeAccount(account)"
    )
    switch_position = challenge_completion.index(
        "BHTSwitchToNativeAccount(account)"
    )
    if register_position >= switch_position:
        raise AssertionError(
            "Challenge completion must register before switching to the "
            "new account"
        )
    require_source_tokens(
        challenge_completion,
        (
            "dismissViewControllerAnimated:YES",
            "completion:switchAccount",
            '@"account_switch_failed"',
        ),
        "challenge dismissal before account switch",
    )
    direct_completion = source_section(
        compatibility_login_source,
        "static void BHTCompleteSignedOutFlowAndSwitchAccount(",
        "static BOOL BHTPresentNativeLoginChallenge(",
        "direct-login onboarding completion",
    )
    require_source_tokens(
        direct_completion,
        (
            '@"signedOutOnboardingFlow"',
            '@"completeFlowAnimated:completion:"',
            "BHTSwitchToNativeAccount(account)",
            '@"account_switch_failed"',
            "compatibilityController.navigationController",
            "dismissViewControllerAnimated:YES",
        ),
        "native signed-out flow completion before account switch",
    )
    add_account_callback_abi = source_section(
        compatibility_login_source,
        "static BOOL BHTNativeDidAddAccountBlockIsSupported(",
        "static void BHTCompleteSignedOutFlowAndSwitchAccount(",
        "native add-account callback ABI guard",
    )
    require_source_tokens(
        add_account_callback_abi,
        (
            'strstr(className, "Block")',
            "BHTBlockHasSignature",
            "signatureWithObjCTypes:typeEncoding",
            "signature.numberOfArguments == 3",
            "BHTSignatureArgumentIsObject(signature, 1)",
            "BHTSignatureArgumentIsObject(signature, 2)",
        ),
        "native add-account callback ABI validation",
    )
    add_account_completion = source_section(
        compatibility_login_source,
        "static void BHTCompleteAddAccountFlow(",
        "static BOOL BHTPresentNativeLoginChallenge(",
        "native signed-in add-account completion",
    )
    require_source_tokens(
        add_account_completion,
        (
            '@"didAddAccountBlock"',
            "didAddAccount(accountsController, account);",
            "compatibilityController.navigationController",
            "challengePresenter.presentedViewController",
            "dismissViewControllerAnimated:YES",
            "BHTSwitchToNativeAccount(account)",
            "BHTCompatibilityAccountHandoffAttempted",
            "BHTCompatibilityAccountHandoffDispatched",
            "BHTCompatibilityAccountHandoffFailed",
        ),
        "native signed-in add-account callback and dismissal",
    )
    challenge_flow = source_section(
        compatibility_login_source,
        "static BOOL BHTPresentNativeLoginChallenge(",
        "@interface BHTCompatibilityLoginViewController",
        "context-aware native challenge presentation",
    )
    require_source_tokens(
        challenge_flow,
        (
            "UIViewController* compatibilityController",
            "UIViewController* addAccountController",
            "? BHTTopViewController(compatibilityController)",
            "challengePresenter, YES, nil",
            "BHTCompleteAddAccountFlow(",
            "if (!addAccountController && signedOutFlow &&",
        ),
        "separate signed-in and signed-out challenge ownership",
    )
    if "presenter.presentingViewController" in compatibility_login_source:
        raise AssertionError(
            "Compatibility sign-in must not guess at X's modal hierarchy"
        )
    compatibility_presenter = source_section(
        compatibility_login_source,
        "static void BHTPresentCompatibilitySignInForContext(",
        "static void BHTSetReportShareSenderEnabled(",
        "compatibility sign-in presentation gate",
    )
    compatibility_entry = source_section(
        compatibility_login_source,
        "void BHTInstallCompatibilitySignInEntry(",
        "void BHTInstallCompatibilityAddAccountSignInEntry(",
        "compatibility onboarding entry gate",
    )
    compatibility_add_account_entry = source_section(
        compatibility_login_source,
        "void BHTInstallCompatibilityAddAccountSignInEntry(",
        "NSDictionary<NSString*, id>*",
        "compatibility add-account entry gate",
    )
    for diagnostic_path, description in (
        (compatibility_presenter, "sign-in presenter"),
        (compatibility_entry, "onboarding entry"),
    ):
        if "BHTCompatibilityVersionIsSupported()" not in diagnostic_path:
            raise AssertionError(
                f"The {description} must remain behind the exact X 12.9 "
                "version gate"
            )
        if "BHTCompatibilityRuntimeIsAvailable()" in diagnostic_path:
            raise AssertionError(
                f"The {description} must remain reachable when a private "
                "runtime requirement is missing"
            )

    require_source_tokens(
        compatibility_presenter,
        (
            "BHTCompatibilityPresentedSignInController",
            "BHTCompatibilityVersionIsSupported()",
            "BHTCompatibilityLoginViewController* login =",
            "login.addAccountController = addAccountController;",
            "UIModalPresentationFormSheet",
            "BHTCompatibilityPresentedSignInController =",
        ),
        "dedicated compatibility sign-in presentation",
    )
    require_source_tokens(
        compatibility_login_source,
        (
            "signature, 2, @encode(NSInteger)",
            'signature, 3, "@?"',
            "signature, 2, @encode(BOOL)",
            'signature, 3, "@"',
            '@"legacyPasswordCommandReachable": @YES',
            "BHTSharePreLoginCompatibilityReport(",
            '@"NeoFreeBird.ShareLoginReport"',
            "shareCompatibilityReport:",
        ),
        "dedicated login route and signed-out diagnostics",
    )
    public_login_routes = source_section(
        compatibility_login_source,
        "void BHTPresentCompatibilitySignIn(",
        "@interface BHTCompatibilityEntryTarget",
        "public compatibility login routes",
    )
    if "BHTPresentCompatibilitySignInForContext(" not in public_login_routes:
        raise AssertionError(
            "Public compatibility actions must dispatch the dedicated "
            "compatibility controller"
        )
    if (
        "BHTPresentNativeInitialCompatibilitySignIn(" in public_login_routes
        or "BHTPresentNativeAddAccountCompatibilitySignIn("
        in public_login_routes
    ):
        raise AssertionError(
            "Public compatibility actions must not route through X's native "
            "JetX/Jetfuel onboarding"
        )

    require_source_tokens(
        compatibility_add_account_entry,
        (
            "BHTCompatibilitySignInIsAvailable()",
            "BHTNativeAddAccountCompletionGetterIsSupported()",
            '@"COMPATIBILITY_SIGN_IN_ADD_ACCOUNT_ACTION"',
            '@"NeoFreeBird.CompatibilityAddAccountSignIn"',
            "rightBarButtonItems",
            "[currentItems containsObject:item]",
            "[updatedItems addObject:item]",
            "setRightBarButtonItems:[updatedItems copy]",
            "&BHTCompatibilityAddAccountItemKey",
            "&BHTCompatibilityAddAccountTargetKey",
        ),
        "idempotent add-account navigation action",
    )

    compatibility_view_setup = source_section(
        compatibility_login_source,
        "- (void)viewDidLoad {",
        "- (void)viewDidAppear:(BOOL)animated {",
        "diagnostic-capable compatibility sign-in screen",
    )
    require_source_tokens(
        compatibility_view_setup,
        (
            "self.runtimeAvailable =\n"
            "        BHTCompatibilityRuntimeIsAvailable();",
            "NSString* initialStatus =",
            "self.runtimeAvailable",
            '@"COMPATIBILITY_SIGN_IN_RUNTIME_ERROR"',
            "[self setBusy:NO status:initialStatus];",
        ),
        "runtime-aware compatibility sign-in screen",
    )
    compatibility_view_appearance = source_section(
        compatibility_login_source,
        "- (void)viewDidAppear:(BOOL)animated {",
        "- (void)shareLoginReport:",
        "compatibility sign-in keyboard behavior",
    )
    require_source_tokens(
        compatibility_view_appearance,
        (
            "if (self.runtimeAvailable) {",
            "[self.usernameField becomeFirstResponder];",
        ),
        "keyboard suppression on a diagnostic-only screen",
    )
    compatibility_view_disappearance = source_section(
        compatibility_login_source,
        "- (void)viewDidDisappear:(BOOL)animated {",
        "- (void)shareLoginReport:",
        "compatibility sign-in dismissal cleanup",
    )
    require_source_tokens(
        compatibility_view_disappearance,
        (
            "self.isBeingDismissed ||",
            "self.navigationController.isBeingDismissed",
            "if (dismissed && !self.requestStarted)",
            "self.cancelled = YES;",
            "[self.metricsCollector cancel];",
            "self.metricsCollector = nil;",
            'self.passwordField.text = @"";',
        ),
        "interactive compatibility sign-in dismissal cleanup",
    )

    metrics_collector = source_section(
        compatibility_login_source,
        "- (void)startWithCompletion:",
        "- (void)userContentController:",
        "ephemeral compatibility metrics collector",
    )
    if "[WKWebsiteDataStore nonPersistentDataStore]" not in metrics_collector:
        raise AssertionError(
            "Compatibility metrics must use a nonpersistent web data store"
        )
    if "[WKWebsiteDataStore defaultDataStore]" in metrics_collector:
        raise AssertionError(
            "Compatibility metrics must never use persistent web data"
        )
    require_source_tokens(
        metrics_collector,
        (
            "configuration.websiteDataStore =\n"
            "        [WKWebsiteDataStore nonPersistentDataStore];",
            "forMainFrameOnly:NO",
            "new URL(String(u),",
            "p.searchParams.get('result')",
            "postMessage(r)",
            "self.webView.navigationDelegate = self;",
            "self.webView.alpha = 0.0;",
            "self.webView.userInteractionEnabled = NO;",
            "self.webView.accessibilityElementsHidden = YES;",
            "self.webView.frame = self.hostView.bounds;",
            "UIViewAutoresizingFlexibleWidth |",
            "UIViewAutoresizingFlexibleHeight;",
            "[self.hostView addSubview:self.webView];",
            "BHTCompatibilityLoginEventMetricsCollectorAttached",
        ),
        "attached all-frame metrics result bridge",
    )
    if "postMessage(String(u))" in metrics_collector:
        raise AssertionError(
            "Compatibility metrics must not forward complete request URLs "
            "into native code"
        )

    metrics_navigation = source_section(
        compatibility_login_source,
        "- (BOOL)consumeURL:(NSURL*)URL {",
        "- (void)startWithCompletion:",
        "bounded compatibility metrics navigation receiver",
    )
    require_source_tokens(
        metrics_navigation,
        (
            "BHTCompatibilityMetricsURLIsAllowed(URL)",
            "componentsWithURL:URL resolvingAgainstBaseURL:NO",
            'if (![item.name isEqualToString:@"result"]) continue;',
            "metrics.length == 0 || metrics.length > 65536",
            "BHTCompatibilityLoginEventMetricsResolvedFromNavigation",
            "[self finishWithMetrics:metrics];",
        ),
        "host-limited result-only navigation metrics capture",
    )

    metrics_response = source_section(
        compatibility_login_source,
        "- (void)userContentController:",
        "- (void)finishWithMetrics:",
        "metrics result receiver",
    )
    if "NSURLComponents" in metrics_response:
        raise AssertionError(
            "The native metrics receiver must accept only the extracted "
            "result value, not a complete request URL"
        )
    require_source_tokens(
        metrics_response,
        (
            "message.frameInfo.request.URL",
            "BHTCompatibilityLoginEventMetricsResolvedFromScript",
            "decidePolicyForNavigationAction:",
            "navigationAction.request.URL",
            "decidePolicyForNavigationResponse:",
            "navigationResponse.response.URL",
            "didReceiveServerRedirectForProvisionalNavigation:",
            "didFinishNavigation:",
            "[self consumeURL:webView.URL];",
        ),
        "navigation-delegate compatibility metrics capture",
    )
    metrics_teardown = source_section(
        compatibility_login_source,
        "- (void)cancel {",
        "@end",
        "compatibility metrics teardown",
    )
    require_source_tokens(
        metrics_teardown,
        (
            "self.webView.navigationDelegate = nil;",
            "[self.webView removeFromSuperview];",
            "removeScriptMessageHandlerForName:BHTMetricsHandlerName",
        ),
        "deterministic hidden metrics WebView teardown",
    )

    cancellation_path = source_section(
        compatibility_login_source,
        "- (void)cancelTapped {",
        "- (BOOL)textFieldShouldReturn:",
        "compatibility sign-in cancellation",
    )
    require_source_tokens(
        cancellation_path,
        (
            "if (self.requestStarted) return;",
            "self.cancelled = YES;",
            "[self.metricsCollector cancel];",
            "self.metricsCollector = nil;",
            'self.passwordField.text = @"";',
        ),
        "pre-request cancellation teardown",
    )
    require_source_tokens(
        compatibility_login_source,
        (
            '#import "Compatibility/BHTCompatibilityReporter.h"',
            "- (void)cancel;",
            "self.completion = nil;",
            "if (self.cancelled) return;",
            "self.requestStarted = YES;",
            "self.navigationItem.leftBarButtonItem.enabled = NO;",
            "if (!strongSelf || strongSelf.cancelled) return;",
        ),
        "cancelled-request race guards",
    )

    report_share = source_section(
        compatibility_login_source,
        "- (void)shareLoginReport:(UIBarButtonItem*)sender {",
        "- (void)cancelTapped {",
        "pre-login compatibility report sharing",
    )
    require_source_tokens(
        compatibility_login_source,
        (
            '@"COMPATIBILITY_SIGN_IN_SHARE_REPORT"',
            "@selector(shareLoginReport:)",
            '@"NeoFreeBird.ShareLoginReport"',
        ),
        "pre-login report navigation item",
    )
    require_source_tokens(
        report_share,
        (
            "if (self.sharingReport || self.requestStarted ||",
            "self.metricsCollector || self.presentedViewController)",
            "self.sharingReport = YES;",
            "sender.enabled = NO;",
            "BHTWriteCompatibilityReportAsync(^(NSURL* reportURL)",
            "reportURL.isFileURL",
            "strongSelf.viewIfLoaded.window",
            "strongSelf.sharingReport = NO;",
            "if (!strongSelf)",
            "strongSelf.requestStarted ||",
            "strongSelf.metricsCollector ||",
            "strongSelf.presentedViewController ||",
            "initWithActivityItems:@[reportURL]",
            "applicationActivities:nil",
            "popover.barButtonItem = sender;",
            "popover.sourceView = strongSelf.view;",
            "popover.sourceRect = CGRectMake(",
            "share.completionWithItemsHandler =",
            "removeItemAtURL:reportURL",
            "[strongSelf presentViewController:share",
        ),
        "fresh file-only pre-login report share sheet",
    )
    require_source_tokens(
        compatibility_report_header,
        ("BHTWriteCompatibilityReportAsync(",),
        "asynchronous compatibility report API",
    )
    require_source_tokens(
        compatibility_source,
        ('#import "Core/BHTManager.h"',),
        "owned temporary report export directory",
    )
    async_report_writer = source_section(
        compatibility_source,
        "void BHTWriteCompatibilityReportAsync(",
        "void BHTRecordNavigationEntryClasses(",
        "asynchronous compatibility report writer",
    )
    require_source_tokens(
        async_report_writer,
        (
            "dispatch_async(BHTCompatibilityReportQueue(), ^{",
            "BHTWriteCompatibilityReportNow(NO, nil);",
            'temporaryFileURLWithExtension:@"json"',
            "copyItemAtURL:currentReportURL",
            "toURL:snapshotURL",
            "if (copiedSnapshot)",
            "removeItemAtURL:snapshotURL",
            "dispatch_async(dispatch_get_main_queue(), ^{",
            "if (completion) completion(reportURL);",
        ),
        "fresh background report generation with main-thread completion",
    )
    busy_state = source_section(
        compatibility_login_source,
        "- (void)setBusy:(BOOL)busy status:(NSString*)status {",
        "- (NSString*)messageForFailureCategory:",
        "compatibility sign-in busy state",
    )
    require_source_tokens(
        busy_state,
        (
            "BOOL controlsEnabled =\n"
            "        self.runtimeAvailable && !busy;",
            "self.usernameField.enabled = controlsEnabled;",
            "self.passwordField.enabled = controlsEnabled;",
            "self.signInButton.enabled = controlsEnabled;",
            "self.navigationItem.rightBarButtonItem.enabled =",
            "!busy && !self.sharingReport;",
            "self.navigationController.modalInPresentation = busy;",
        ),
        "report sharing disabled only during an active login or export",
    )
    report_request_position = report_share.index(
        "BHTWriteCompatibilityReportAsync(^(NSURL* reportURL)"
    )
    report_sheet_position = report_share.index(
        "initWithActivityItems:@[reportURL]"
    )
    report_present_position = report_share.index(
        "[strongSelf presentViewController:share"
    )
    if not (
        report_request_position
        < report_sheet_position
        < report_present_position
    ):
        raise AssertionError(
            "Pre-login report sharing must refresh the report before "
            "sharing its local file"
        )
    for private_value in (
        "usernameField",
        "passwordField",
        "absoluteString",
        "NSURLComponents",
        "localizedDescription",
        "response",
        "token",
        "secret",
        "cookie",
        "NSUserDefaults",
        "UIPasteboard",
    ):
        if private_value in report_share:
            raise AssertionError(
                "Pre-login report sharing must not include credentials, "
                f"authentication values, or raw runtime data: {private_value}"
            )

    sign_in_action = source_section(
        compatibility_login_source,
        "- (void)signInTapped {",
        "\n}\n\n@end",
        "compatibility password submission",
    )
    if "self.metricsCollector || self.sharingReport" not in sign_in_action:
        raise AssertionError(
            "Compatibility sign-in must not start while a report "
            "snapshot is being prepared"
        )
    version_check_position = sign_in_action.index(
        "if (!BHTCompatibilityVersionIsSupported())"
    )
    runtime_check_position = sign_in_action.index(
        "if (!BHTCompatibilityRuntimeIsAvailable())"
    )
    password_copy_position = sign_in_action.index(
        "NSString* password = [self.passwordField.text copy];"
    )
    password_clear_position = sign_in_action.index(
        'self.passwordField.text = @"";'
    )
    metrics_request_position = sign_in_action.index(
        "self.metricsCollector ="
    )
    if not (
        version_check_position
        < runtime_check_position
        < password_copy_position
        < password_clear_position
        < metrics_request_position
    ):
        raise AssertionError(
            "The compatibility runtime must be rechecked before credentials "
            "are read, and the visible password field must be cleared "
            "before any sign-in request begins"
        )
    if "self.runtimeAvailable = NO;" not in sign_in_action:
        raise AssertionError(
            "A failed runtime recheck must keep credential controls "
            "disabled"
        )
    require_source_tokens(
        sign_in_action,
        (
            "BHTNormalizedCompatibilityIdentifier(",
            "BHTCompatibilityLoginEventIdentifierNormalized",
            "self.metricsCollector.hostView = self.view;",
            "NSProcessInfo.processInfo.systemUptime;",
            "NSProcessInfo.processInfo.systemUptime -",
            "startWithCompletion:^(__unused NSString* metrics)",
            "BHTCompatibilityMinimumPreflightDuration - elapsed",
            "BHTCompatibilityLoginEventMinimumPreflightElapsed",
            "dispatch_after(",
            "metrics:nil",
        ),
        "beta 29 request timing and compatibility metrics isolation",
    )
    if "metrics:metrics" in sign_in_action:
        raise AssertionError(
            "Navigation-derived metrics must remain isolated from the "
            "compatibility password command"
        )

    password_response = source_section(
        compatibility_login_source,
        "- (void)handlePasswordResponse:",
        "- (void)startPasswordCommandForUsername:",
        "compatibility password response handling",
    )
    require_source_tokens(
        password_response,
        (
            "BHTCompatibilityRecordCommandCompletion(",
            '@"loginVerificationRequestId"',
            '@"challengeURLString"',
            "BHTCompatibilityLoginEventChallengeRecoveredFromFailedCompletion",
            "BHTCompatibilityLoginEventChallengeRecoveredFromFailureObject",
            "id challengePayload = response;",
            "id failureRequestID = BHTSendObject(error, requestIDSelector);",
            "if (requestID && challengeURL)",
            "BHTPresentNativeLoginChallenge(",
            "if (!success || !response)",
            "BHTCompatibilityLoginEventRejectionWithoutPayload",
            "BHTCompatibilityFailureCategory(",
        ),
        "challenge-before-rejection compatibility response flow",
    )
    if password_response.index(
        "BHTPresentNativeLoginChallenge("
    ) > password_response.index("if (!success || !response)"):
        raise AssertionError(
            "A returned X verification challenge must be handled before "
            "the completion Boolean is treated as a rejection"
        )
    if compatibility_login_source.count(
        'self.passwordField.text = @"";'
    ) < 3:
        raise AssertionError(
            "Compatibility sign-in must clear its password field on "
            "submit, cancel, and completion"
        )

    if "NSUserDefaults" in compatibility_login_source:
        raise AssertionError(
            "Compatibility sign-in must never store credentials or tokens "
            "in NSUserDefaults"
        )
    for logging_api in (
        "NSLog",
        "os_log",
        "localizedDescription",
        "debugDescription",
    ):
        if logging_api in compatibility_login_source:
            raise AssertionError(
                "Compatibility sign-in must not log sensitive runtime "
                f"values: {logging_api}"
            )

    login_diagnostic = compatibility_login_source.split(
        "BHTCompatibilitySignInDiagnosticSnapshot(void)", 1
    )[1]
    require_source_tokens(
        login_diagnostic,
        (
            '@"missingRuntimeRequirements":',
            '@"preLoginDiagnosticsEligible":',
            '@"nativeSignInRemainsDefault": @YES',
            '@"compatibilitySignInMode": @"dedicated_xauth_password"',
            '@"legacyPasswordCommandReachable": @YES',
            '@"credentialEntryOwner": @"compatibility_screen_ephemeral"',
            '@"credentialPersistence": @"x_native_account_storage"',
            '@"xAuthClientMetadataPolicy":',
            '@"native_x_12_9"',
            '@"xAuthClientMetadataTargetVersion":',
            '@"xAuthClientMetadataOverrideInstalled": @NO',
            '@"xAuthClientMetadataOverrideClaimed": @0',
            '@"xAuthClientMetadataOverrideApplied": @0',
            '@"xAuthClientMetadataScopeTimedOut": @0',
            '@"compatibilityRequestProfile":',
            '@"beta29_native_12_9_preflight"',
            '@"preflightPolicy":',
            '@"minimum_12_second_then_nil_metrics"',
            '@"preflightMinimumDelaySeconds":',
            '@"attestationOverridesIncluded": @NO',
            '@"credentialBackupIncluded": @NO',
            '@"uiMetricsPolicy": @"compatibility_nil"',
            '@"capturedMetricsUsedForAuthentication": @NO',
            '@"addAccountEntryAvailable":',
            '@"nativeAddAccountCompletionSelectorAvailable":',
            '@"addAccountEntryInstalled"',
            '@"addAccountEntryOpened"',
            '@"accountHandoffAttempted"',
            '@"accountHandoffDispatched"',
            '@"accountHandoffFailed"',
            '@"lastCommandCompletionSucceeded"',
            '@"lastCommandPayloadPresent"',
            '@"lastCommandFailureObjectPresent"',
            '@"lastCommandPayloadClass"',
            '@"lastCommandFailureClass"',
            '@"lastCommandFailureDomain"',
            '@"lastCommandFailureCode"',
            '@"capturesCredentials": @NO',
            '@"capturesIdentifiers": @NO',
            '@"capturesPayloadContents": @NO',
            '@"capturesFailureDescriptions": @NO',
            '@"capturesFailureUserInfo": @NO',
            '@"capturesPrivacySafeFailureFingerprint": @YES',
        ),
        "compatibility sign-in safety diagnostic",
    )
    for private_value in (
        "NSLog",
        "absoluteString",
        "URLString",
        "queryItems",
        "message.body",
        "localizedDescription",
        "debugDescription",
        "response",
        "NSError",
    ):
        if private_value in login_diagnostic:
            raise AssertionError(
                "Compatibility sign-in diagnostics must not expose raw "
                f"URLs, errors, or responses: {private_value}"
            )
    if re.search(
        r"\b(url|error|response|token|secret|password|username|cookie)\b",
        login_diagnostic,
        re.IGNORECASE,
    ):
        raise AssertionError(
            "Compatibility sign-in diagnostics must contain aggregate "
            "stages and counters only"
        )

    require_source_tokens(
        compatibility_source,
        (
            '#import "Login/BHTCompatibilityLogin.h"',
            '#import "Security/BHTAuthenticationURLUtility.h"',
            '@"authenticationRouting":',
            "BHTAuthenticationRoutingDiagnosticSnapshot()",
            '@"compatibilitySignIn":',
            "BHTCompatibilitySignInDiagnosticSnapshot()",
            '@"unsafeLoginOverridesIncluded": @NO',
            '@"webSessionHarvestingIncluded": @NO',
            '@"compatibilityPasswordSignInIncluded": @YES',
            '@"nativeOnboardingSignInIncluded": @NO',
            '@"compatibilityXAuthClientMetadataIncluded": @NO',
            '@"attestationOverridesIncluded": @NO',
            '@"credentialBackupIncluded": @NO',
        ),
        "redacted compatibility sign-in report integration",
    )

    reply_header_source = (
        ROOT / "src" / "Compatibility" / "BHTCompatibilityReporter.h"
    ).read_text(encoding="utf-8")
    reply_hook_source = (
        ROOT / "src" / "Hooks" / "ReplyDiagnostics.x"
    ).read_text(encoding="utf-8")
    confirmations_source = (
        ROOT / "src" / "Hooks" / "Confirmations.x"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        reply_header_source,
        (
            "BHTReplyWorkflowDiagnosticReplyActionTapped",
            "BHTReplyWorkflowDiagnosticReplyActionForwarded",
            "BHTReplyWorkflowDiagnosticWebFallbackPresented",
            "BHTReplyWorkflowDiagnosticPersistentComposerPresented",
            "BHTReplyWorkflowDiagnosticComposerPresented",
            "BHTReplyWorkflowDiagnosticComposerDisappeared",
            "BHTReplyWorkflowDiagnosticComposerClosed",
            "BHTReplyWorkflowDiagnosticSendButtonTapped",
            "BHTReplyWorkflowDiagnosticSendForwardedToX",
            "BHTReplyWorkflowDiagnosticValidationEntered",
            "BHTReplyWorkflowDiagnosticValidationReturned",
            "BHTReplyWorkflowDiagnosticSendCompositionsEntered",
            "BHTReplyWorkflowDiagnosticSendCompositionsReturned",
            "BHTReplyWorkflowDiagnosticContainerCompleted",
            "BHTReplyWorkflowDiagnosticContainerCancelled",
            "BHTReplyWorkflowDiagnosticOutboxQueued",
            "BHTReplyWorkflowDiagnosticOutboxProcessing",
            "BHTReplyWorkflowDiagnosticOutboxProcessed",
            "BHTReplyWorkflowDiagnosticSendCompleted",
            "BHTReplyWorkflowDiagnosticOutboxProcessFailed",
            "BHTReplyWorkflowDiagnosticCompositionSendFailed",
            "BHTReplyWorkflowDiagnosticUnattributedPersistentComposerPresented",
            "BHTRecordReplyWorkflowDiagnostic(",
            "BHTInstallReplyWorkflowDiagnosticObservers(void)",
            "BHTReplyWorkflowDiagnosticSessionForNetworkRequest(",
            "BHTReplyWorkflowDiagnosticSessionForApplicationResponse(",
            "BHTReplyWorkflowApplicationDiagnosticWindowMayBeActive(void)",
            "BHTReplyWorkflowNetworkDiagnosticWindowMayBeActive(void)",
        ),
        "privacy-preserving reply workflow diagnostic API",
    )
    require_source_tokens(
        compatibility_source,
        (
            "BHTReplyWorkflowDiagnosticCounters",
            "BHTReplyWorkflowLastStage",
            "BHTReplyWorkflowLastOutcome",
            "BHTReplyNotificationObserverSpecs",
            'dlsym(RTLD_DEFAULT, symbol)',
            "dladdr(address, &symbolInfo)",
            "dladdr((void*)candidateBits, &candidateInfo)",
            "_Static_assert(",
            "TFNTwitterCompositionOutboxDidAddCompositionNotification",
            "TFNTwitterCompositionOutboxWillProcessCompositionNotification",
            "TFNTwitterCompositionOutboxDidProcessCompositionNotification",
            "TFNTwitterCompositionDidSendNotification",
            "TFNTwitterCompositionOutboxDidFailProcessCompositionNotification",
            "TFNTwitterCompositionSendDidFailNotification",
            "NSNotification* notification",
            "if (spec.observesFailure)",
            "BHTReplyWorkflowGenerationForFailureNotification()",
            "BHTObserveNativeReplyFailureNotification(",
            '@"replyWorkflow":',
            "BHTReplyWorkflowDiagnosticSnapshot()",
            '@"capturesTweetOrReplyText": @NO',
            '@"capturesUsersOrAccountData": @NO',
            '@"capturesIdentifiers": @NO',
            '@"capturesNotificationPayloads": @NO',
            '@"capturesRawErrors": @NO',
            '@"failureErrorClassificationIncludedSeparately": @YES',
            '@"correlation":',
            '@"process_level_temporal_heuristic"',
            '@"diagnosticWindowSeconds":',
            '@"runtimeShapeContainsPrivateAPIMetadata": @YES',
            "BHTReplyWorkflowOrderedTrace",
            '@"orderedTrace": orderedTrace',
            '@"orderedTraceClock": @"process_monotonic_relative"',
            '@"relativeMillisecondsBucket":',
            '@"networkCorrelationRequiresActiveForwardedSession": @YES',
            '@"nativeReplyNetwork":',
            "BHTReplyRequestDiagnosticSnapshot()",
        ),
        "redacted reply workflow report integration",
    )
    reply_observer_source = source_section(
        compatibility_source,
        "void BHTInstallReplyWorkflowDiagnosticObservers(void)",
        "static BOOL BHTReplySelectorIsSafeAndRelevant(",
        "reply notification observers",
    )
    for private_value in (
        "notification.userInfo",
        "notification.object",
        "[notification ",
        "NSLog",
        "localizedDescription",
        "absoluteString",
        "statusID",
        "userID",
        "fromUserName",
        "password",
        "authToken",
    ):
        if private_value in reply_observer_source:
            raise AssertionError(
                "Reply observers must count fixed stages without reading "
                f"notification or account data: {private_value}"
            )
    require_source_tokens(
        reply_hook_source,
        (
            "BHTReplyDiagnosticMethodHasShape(",
            "BHTReplyDiagnosticMethodHasObjectArguments(",
            'isEqualToString:@"12.9"',
            "method_getNumberOfArguments(method)",
            "if (*type != '@') return NO;",
            "BHTInstallReplyWorkflowDiagnosticObservers();",
            "%hook TTAStatusInlineReplyButton",
            "BHTReplyWorkflowDiagnosticReplyActionTapped",
            "%hook T1StatusViewInlineActionTapEventHandler",
            "BHTReplyWorkflowDiagnosticReplyActionForwarded",
            "%hook T1TweetComposeViewController",
            "BHTReplyWorkflowDiagnosticComposerPresented",
            "BHTReplyWorkflowDiagnosticComposerDisappeared",
            "BHTReplyWorkflowDiagnosticComposerClosed",
            'NSSelectorFromString(\n                @"_t1_checkForValidTweetsAndSend")',
            'NSSelectorFromString(@"_t1_sendCompositions:")',
            "BHTReplyWorkflowDiagnosticValidationEntered",
            "BHTReplyWorkflowDiagnosticValidationReturned",
            "BHTReplyWorkflowDiagnosticSendCompositionsEntered",
            "BHTReplyWorkflowDiagnosticSendCompositionsReturned",
            "%hook T1TweetComposeContainerViewController",
            "BHTReplyWorkflowDiagnosticContainerCompleted",
            "BHTReplyWorkflowDiagnosticContainerCancelled",
            "%hook T1PersistentComposeViewController",
            "BHTReplyWorkflowDiagnosticPersistentComposerPresented",
        ),
        "guarded X 12.9 reply workflow hooks",
    )
    reply_forwarding_body = source_section(
        reply_hook_source,
        "originalStatus:(__unsafe_unretained id)originalStatus {",
        "%end",
        "opaque reply-action forwarding hook",
    )
    for private_value in (
        "[account ",
        "[event ",
        "[controller ",
        "[scribeContext ",
        "[scribeElement ",
        "[parameters ",
        "[originalStatus ",
        "objc_getAssociatedObject",
        "NSLog",
    ):
        if private_value in reply_forwarding_body:
            raise AssertionError(
                "Reply-action diagnostics must forward opaque arguments "
                f"without inspecting them: {private_value}"
            )
    if reply_forwarding_body.count("%orig(") != 1:
        raise AssertionError(
            "The reply-action diagnostic must forward to X exactly once"
        )
    reply_recorder_source = source_section(
        compatibility_source,
        "void BHTRecordReplyWorkflowDiagnostic(",
        "typedef struct {",
        "reply workflow state recorder",
    )
    persistent_case = source_section(
        reply_recorder_source,
        "case BHTReplyWorkflowDiagnosticPersistentComposerPresented:",
        "case BHTReplyWorkflowDiagnosticComposerPresented:",
        "persistent-composer attribution",
    )
    if (
        "BHTReplyWorkflowDiagnosticUnattributedPersistentComposerPresented"
        not in persistent_case
        or "BHTStartReplyWorkflowSessionLocked" in persistent_case
    ):
        raise AssertionError(
            "Persistent composer appearance must not start a reply session"
        )
    failure_cases = source_section(
        reply_recorder_source,
        "case BHTReplyWorkflowDiagnosticOutboxProcessFailed:",
        "case BHTReplyWorkflowDiagnosticUnattributedPersistentComposerPresented:",
        "terminal reply failure handling",
    )
    for required in (
        "BHTReplyWorkflowSessionActive = NO;",
        "BHTReplyWorkflowSendForwarded = NO;",
        "BHTReplyWorkflowAwaitingComposerClose =",
        "BHTReplyWorkflowExpiresAt = 0;",
    ):
        if required not in failure_cases:
            raise AssertionError(
                "A terminal reply failure must close temporal attribution: "
                f"{required}"
            )
    notification_gate = source_section(
        reply_recorder_source,
        "case BHTReplyWorkflowDiagnosticOutboxQueued:",
        "case BHTReplyWorkflowDiagnosticUnattributedPersistentComposerPresented:",
        "reply notification attribution gate",
    )
    if notification_gate.count(
        "BHTReplyWorkflowSessionActive &&"
    ) < 3 or notification_gate.count(
        "BHTReplyWorkflowSendForwarded"
    ) < 3:
        raise AssertionError(
            "Outbox, completion, and failure notifications must require "
            "both an active reply attempt and a completed send handoff"
        )
    retry_case = source_section(
        reply_recorder_source,
        "case BHTReplyWorkflowDiagnosticSendButtonTapped:",
        "case BHTReplyWorkflowDiagnosticSendForwardedToX:",
        "failed-reply retry attribution",
    )
    for required in (
        "retryingFailedReply",
        '@"outbox_process_failed"',
        '@"composition_send_failed"',
        "BHTStartReplyWorkflowSessionLocked();",
    ):
        if required not in retry_case:
            raise AssertionError(
                "A retry from the same failed reply composer must start a "
                f"new diagnostic attempt: {required}"
            )
    reply_snapshot_source = source_section(
        compatibility_source,
        "static NSDictionary* BHTReplyWorkflowDiagnosticSnapshot(void)",
        "static NSDictionary* BHTForYouControllerRuntimeShape(void)",
        "reply workflow snapshot",
    )
    if reply_snapshot_source.find(
        "@synchronized(BHTObservationLock())"
    ) > reply_snapshot_source.find(
        "atomic_load_explicit("
    ):
        raise AssertionError(
            "Reply counters and state must be captured under the same lock"
        )
    send_confirmation_source = source_section(
        confirmations_source,
        "- (void)_t1_didTapSendButton:",
        "%end",
        "composer send confirmation hook",
    )
    if (
        send_confirmation_source.count(
            "BHTReplyWorkflowDiagnosticSendButtonTapped"
        )
        != 1
        or send_confirmation_source.count(
            "BHTReplyWorkflowDiagnosticSendForwardedToX"
        )
        != 2
        or send_confirmation_source.count("%orig;") != 2
    ):
        raise AssertionError(
            "Both confirmed and unconfirmed sends must record handoff and "
            "forward to X exactly once"
        )
    send_hook_occurrences = sum(
        hook.read_text(encoding="utf-8").count(
            "- (void)_t1_didTapSendButton:"
        )
        for hook in (ROOT / "src" / "Hooks").glob("*.x")
    )
    if send_hook_occurrences != 1:
        raise AssertionError(
            "Reply diagnostics must instrument the existing send hook "
            "instead of installing a competing hook"
        )

    reply_network_header = (
        ROOT / "src" / "Reply" / "BHTReplyRequestDiagnostics.h"
    ).read_text(encoding="utf-8")
    reply_network_source = (
        ROOT / "src" / "Reply" / "BHTReplyRequestDiagnostics.m"
    ).read_text(encoding="utf-8")
    reply_network_hook = (
        ROOT / "src" / "Hooks" / "ReplyNetworkDiagnostics.x"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        reply_network_header + reply_network_source,
        (
            "BHTTagPotentialNativeReplyRequest(",
            "BHTCompletePotentialNativeReplyRequest(",
            "BHTReplyRequestDiagnosticSnapshot(void)",
            'URL.lastPathComponent',
            '@"CreateTweet"',
            '@"CreateTweetWithUndo"',
            'NSProcessInfo.processInfo.systemUptime',
            'BHTReplyRequestRecentAttemptLimit = 16',
            '@"activeForwardedReplyWindow": @YES',
            '@"sessionGeneration": @(tag.sessionGeneration)',
            '@"constructorHookAvailability":',
            '@"constructorCallsWhileWindowHintOpen":',
            '@"candidateRejectionCounters":',
            '@"duplicateTaskAlreadyTagged"',
            '@"taggedTasksWithoutObservedCompletion":',
            '@"correlationScope": @"process_temporal_strict"',
            '@"constructorToCompletionTimingIncludesQueueDelay": @YES',
            '@"graphQLApplicationErrorsInsideHTTP2xxAreUnobservedByThisLayer":',
            '@"graphQLApplicationDiagnosticIncludedSeparately": @YES',
            '@"strictHTTPSHostAllowlist": @YES',
            '@"requestForwardedUnchanged": @YES',
            '@"capturesRequestBodies": @NO',
            '@"capturesUploadDataOrFileURLs": @NO',
            '@"capturesRequestHeaders": @NO',
            '@"capturesCookiesOrTokens": @NO',
            '@"capturesURLs": @NO',
            '@"capturesResponseContents": @NO',
            '@"capturesAccountData": @NO',
            '@"capturesIdentifiers": @NO',
            '@"capturesRawErrors": @NO',
        ),
        "metadata-only native reply request diagnostics",
    )
    require_source_tokens(
        reply_network_hook,
        (
            'isEqualToString:@"12.9"',
            "%hook NSURLSession",
            "dataTaskWithRequest:(NSURLRequest*)request",
            "uploadTaskWithRequest:(NSURLRequest*)request",
            "fromData:(NSData*)bodyData",
            "fromFile:(NSURL*)fileURL",
            "completionHandler:(id)completionHandler",
            "%hook TNLURLSessionTaskOperation",
            "_network_finalizeDidCompleteTask:",
            "URLSession:(NSURLSession*)session",
            "didCompleteWithError:(NSError*)error",
            "BHTReplyNetworkMethodHasObjectShape(",
            "method_getNumberOfArguments(method)",
            "BHTMarkReplyRequestConstructorHookInstalled(",
            "BHTMarkReplyRequestCompletionHookInstalled(",
            "BHTReplyWorkflowNetworkDiagnosticWindowMayBeActive()",
            "@catch (__unused NSException* exception)",
        ),
        "guarded X 12.9 reply request hooks",
    )
    if reply_network_hook.count("%orig(") != 8:
        raise AssertionError(
            "Reply request diagnostics must forward each of the six "
            "constructors and both guarded TNL completion candidates "
            "exactly once"
        )
    for unsafe_network_value in (
        "absoluteString",
        "pathComponents",
        "HTTPBody",
        "allHTTPHeaderFields",
        "valueForHTTPHeaderField",
        "httpCookieStore",
        "NSHTTPCookieStorage",
        "auth_token",
        '"ct0"',
        "localizedDescription",
        ".userInfo",
    ):
        if unsafe_network_value in (
            reply_network_source + reply_network_hook
        ):
            raise AssertionError(
                "Native reply request diagnostics must not inspect or "
                f"rewrite sensitive traffic: {unsafe_network_value}"
            )

    reply_failure_header = (
        ROOT / "src" / "Reply" / "BHTReplyFailureDiagnostics.h"
    ).read_text(encoding="utf-8")
    reply_failure_source = (
        ROOT / "src" / "Reply" / "BHTReplyFailureDiagnostics.m"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        reply_failure_header + reply_failure_source,
        (
            "BHTNativeReplyFailureSourceOutboxProcess",
            "BHTNativeReplyFailureSourceCompositionSend",
            "BHTPrepareNativeReplyFailureDiagnostics(void)",
            "BHTObserveNativeReplyFailureNotification(",
            "BHTNativeReplyFailureDiagnosticSnapshot(void)",
            'isEqualToString:@"12.9"',
            '"TFNTwitterCompositionOutboxNotificationErrorUserInfoKey"',
            '"HTTPRequestActionResponseErrorGetAPIErrors"',
            '"HTTPRequestActionResponseErrorGetRestErrors"',
            '"HTTPRequestActionResponseErrorGetParseError"',
            '"HTTPRequestActionResponseErrorGetAuthenticationError"',
            '"HTTPRequestActionResponseErrorGetOperationError"',
            '"HTTPRequestActionResponseErrorGetInvalidResponseModelError"',
            '"HTTPRequestActionResponseErrorGetInternalError"',
            '"HTTPRequestActionResponseErrorIsResponseWithoutDataOrErrorError"',
            'isEqualToString:@"TwitterSPMMigration"',
            "BHTReplyFailureClassifiersAvailable",
            "BHTReplyFailureGetAPIErrors = NULL",
            "BHTReplyFailureGetRESTError = NULL",
            "BHTReplyFailureGetParseError = NULL",
            "BHTReplyFailureGetAuthenticationError = NULL",
            "BHTReplyFailureGetOperationError = NULL",
            "BHTReplyFailureGetInvalidResponseModelError = NULL",
            "BHTReplyFailureGetInternalError = NULL",
            "BHTReplyFailureIsResponseWithoutDataOrError = NULL",
            "BHTReplyFailureRecentAttemptLimit = 8",
            "BHTReplyFailureSourceNames[]",
            "BHTReplyFailureObservationStateNames[]",
            "BHTReplyFailureErrorCategoryNames[]",
            "BHTReplyFailureAPIErrorStateNames[]",
            "BHTReplyFailureErrorObjectStateNames[]",
            "_Static_assert(",
            "if (sessionGeneration == 0)",
            "[userInfo objectForKey:",
            "BHTReplyFailureErrorUserInfoKey]",
            'NSClassFromString(@"__SwiftValue")',
            "object_getClass(error) ==",
            "BHTReplyFailureSwiftValueClass",
            "BHTReplyFailureAPIErrorStateNonemptyCollection",
            '@"sessionGeneration": @(sessionGeneration)',
            '@"source": BHTReplyFailureSourceNames[source]',
            '@"errorObjectState":',
            '@"failureErrorKeyAvailable":',
            '@"allClassifiersAvailable":',
            '@"swiftValueBoxRecognitionAvailable":',
            '@"recentAttemptLimit":',
            '@"errorObjectCounters":',
            '@"correlationScope":',
            '@"process_temporal_failure_notification"',
            '@"requestIdentityBound": @NO',
            '@"strictX12_9Only": @YES',
            '@"usesExportedActionErrorClassifierBridges": @YES',
            '@"inspectsFailureNotificationErrorMetadata": @YES',
            '@"inspectsOnlyExactFailureErrorUserInfoKey": @YES',
            '@"classifiesOnlyExactOpaqueSwiftValueWrapper": @YES',
            '@"inspectsOpaqueSwiftValueContents": @NO',
            '@"enumeratesNotificationUserInfo": @NO',
            '@"capturesNotificationPayloads": @NO',
            '@"capturesRawErrors": @NO',
            '@"capturesErrorDescriptionsOrUserInfo": @NO',
            '@"inspectsErrorDomainsOrCodes": @NO',
            '@"inspectsAPIErrorCollectionElements": @NO',
            '@"capturesTweetOrReplyText": @NO',
            '@"capturesIdentifiers": @NO',
            '@"capturesAccountData": @NO',
            '@"persistsNotificationOrErrorObjects": @NO',
            '@"exportsNotificationOrErrorObjects": @NO',
            '@"modifiesErrorsNotificationsOrCompletions": @NO',
            '@"failureClassificationDoesNotInferPostingSuccess": @YES',
        ),
        "strict fixed-category native reply failure diagnostics",
    )
    failure_observer = source_section(
        reply_failure_source,
        "void BHTObserveNativeReplyFailureNotification(",
        "static NSDictionary* BHTReplyFailureCounterDictionary(",
        "native reply failure notification classifier",
    )
    if failure_observer.find("if (sessionGeneration == 0)") > (
        failure_observer.find("notification.userInfo")
    ):
        raise AssertionError(
            "Uncorrelated reply failure notifications must be rejected "
            "before their user-info dictionary is touched"
        )
    if failure_observer.count("notification.userInfo") != 1:
        raise AssertionError(
            "Reply failure diagnostics may access only one notification "
            "user-info dictionary"
        )
    swift_error_guard = (
        "BHTReplyFailureSwiftValueClass &&\n"
        "                       object_getClass(error) ==\n"
        "                           BHTReplyFailureSwiftValueClass"
    )
    swift_guard_index = failure_observer.find(swift_error_guard)
    first_classifier_index = failure_observer.find(
        "BHTReplyFailureGetAPIErrors(error)"
    )
    ns_error_index = failure_observer.find(
        "[error isKindOfClass:NSError.class]"
    )
    if not (
        0 <= swift_guard_index < first_classifier_index < ns_error_index
    ):
        raise AssertionError(
            "Private action-error classifiers must run only inside the "
            "exact opaque Swift-value wrapper branch"
        )
    for private_value in (
        "notification.object",
        "allKeys",
        "allValues",
        "keyEnumerator",
        "objectEnumerator",
        "objectAtIndex:",
        "firstObject",
        "lastObject",
        "enumerateObjectsUsingBlock:",
        "enumerateKeysAndObjectsUsingBlock:",
        "valueForKey:",
        "isKindOfClass:BHTReplyFailureSwiftValueClass",
        "class_getName(error)",
        "object_getClassName",
        "NSStringFromClass",
        "class_copyIvarList",
        "object_getIvar",
        "methodForSelector:",
        "performSelector:",
        "Mirror",
        "__SwiftValue.store",
        "localizedDescription",
        "debugDescription",
        "failureReason",
        "recoverySuggestion",
        "helpAnchor",
        "error.domain",
        "error.code",
        "error.userInfo",
        "NSLog",
        "TFNTwitterCompositionAccountIDUserInfoKey",
        "TFNTwitterCompositionNotificationStatusKey",
        "TFNTwitterCompositionOutboxNotificationCompositionIndexUserInfoKey",
        "TFNTwitterCompositionOutboxNotificationCompositionsCountUserInfoKey",
        "TFNTwitterCompositionOutboxNotificationCompositionsUserInfoKey",
        "TFNTwitterCompositionOutboxNotificationCompositionUserInfoKey",
        "TFNTwitterCompositionOutboxNotificationStatusUserInfoKey",
        "tweetText",
        "statusID",
        "userID",
        "accountID",
        "absoluteString",
        "HTTPBody",
        "allHTTPHeaderFields",
        "cookie",
        "authToken",
    ):
        if private_value in reply_failure_source:
            raise AssertionError(
                "Reply failure diagnostics must not inspect or retain "
                f"private notification/error data: {private_value}"
            )
    require_source_tokens(
        compatibility_source,
        (
            '#import "Reply/BHTReplyFailureDiagnostics.h"',
            '@"nativeReplyFailure":',
            "BHTNativeReplyFailureDiagnosticSnapshot()",
        ),
        "native reply failure report integration",
    )
    failure_spec_section = source_section(
        compatibility_source,
        "BHTReplyNotificationObserverSpecs[] = {",
        "static NSString* BHTReplyNotificationNameForSymbol(",
        "reply failure observer allowlist",
    )
    if failure_spec_section.count("YES,") != 2:
        raise AssertionError(
            "Exactly the two terminal reply-failure notification specs may "
            "enable error classification"
        )
    failure_observer_integration = source_section(
        compatibility_source,
        "usingBlock:^(\n                            NSNotification* notification)",
        "if (token)",
        "native reply failure observer integration",
    )
    capture_index = failure_observer_integration.find(
        "BHTReplyWorkflowGenerationForFailureNotification()"
    )
    classify_index = failure_observer_integration.find(
        "BHTObserveNativeReplyFailureNotification("
    )
    record_index = failure_observer_integration.find(
        "BHTRecordReplyWorkflowDiagnostic("
    )
    if not (0 <= capture_index < record_index < classify_index):
        raise AssertionError(
            "Failure observers must capture correlation, preserve the "
            "terminal workflow record, then reduce the transient error"
        )
    if "@catch (__unused NSException* exception)" not in (
        failure_observer_integration
    ):
        raise AssertionError(
            "A failure diagnostic exception must not suppress the ordinary "
            "terminal workflow record"
        )
    network_allowlist = source_section(
        reply_network_source,
        "static BOOL BHTReplyRequestHostKindForURL(",
        "static BOOL BHTReplyRequestOperationKindForURL(",
        "native reply exact host allowlist",
    )
    require_source_tokens(
        network_allowlist,
        (
            'isEqualToString:@"https"',
            'isEqualToString:@"api.twitter.com"',
            'isEqualToString:@"api.x.com"',
            'isEqualToString:@"twitter.com"',
            'isEqualToString:@"www.twitter.com"',
            'isEqualToString:@"x.com"',
            'isEqualToString:@"www.x.com"',
        ),
        "native reply exact host allowlist",
    )
    if (
        network_allowlist.count("return YES;") != 2
        or any(
            fuzzy in network_allowlist
            for fuzzy in ("hasSuffix:", "hasPrefix:", "containsString:")
        )
    ):
        raise AssertionError(
            "The native reply network allowlist must use only the two "
            "explicit API/web host branches"
        )
    network_allowlist_literals = set(
        re.findall(r'@"([^"]+)"', network_allowlist)
    )
    if network_allowlist_literals != {
        "https",
        "api.twitter.com",
        "api.x.com",
        "twitter.com",
        "www.twitter.com",
        "x.com",
        "www.x.com",
    }:
        raise AssertionError(
            "The native reply network allowlist contains an unexpected "
            f"scheme or host: {sorted(network_allowlist_literals)}"
        )
    request_tagger = source_section(
        reply_network_source,
        "void BHTTagPotentialNativeReplyRequest(",
        "void BHTCompletePotentialNativeReplyRequest(",
        "native reply task tagger",
    )
    require_source_tokens(
        request_tagger,
        (
            "BHTReplyWorkflowNetworkDiagnosticWindowMayBeActive()",
            "BHTReplyWorkflowDiagnosticSessionForNetworkRequest(",
            "&sessionGeneration",
            'request.HTTPMethod.uppercaseString',
            'isEqualToString:@"POST"',
            "tag.sessionGeneration = sessionGeneration",
        ),
        "strict reply task tagging",
    )
    if request_tagger.find(
        "BHTReplyWorkflowNetworkDiagnosticWindowMayBeActive()"
    ) > request_tagger.find("request.URL"):
        raise AssertionError(
            "The lock-free native reply gate must run before URL metadata "
            "is inspected"
        )
    fast_gate = source_section(
        compatibility_source,
        "BOOL BHTReplyWorkflowNetworkDiagnosticWindowMayBeActive(void)",
        "BOOL BHTReplyWorkflowDiagnosticSessionForNetworkRequest(",
        "lock-free native reply hint",
    )
    require_source_tokens(
        fast_gate,
        (
            "atomic_load_explicit(",
            "&BHTReplyWorkflowNetworkWindowOpen",
            "memory_order_acquire",
        ),
        "lock-free native reply hint",
    )
    for forbidden in (
        "@synchronized",
        "BHTObservationLock",
        "request",
        "URL",
        "dispatch_",
    ):
        if forbidden in fast_gate:
            raise AssertionError(
                "The app-global native reply hint must remain a single "
                f"lock-free atomic read: {forbidden}"
            )
    fail_open_tagger = source_section(
        reply_network_hook,
        "static void BHTReplyNetworkTagFailOpen(",
        "%group BHTNativeReplyDataRequestHook",
        "fail-open native reply tag helper",
    )
    gate_position = fail_open_tagger.find(
        "BHTReplyWorkflowNetworkDiagnosticWindowMayBeActive()"
    )
    try_position = fail_open_tagger.find("@try {")
    tag_position = fail_open_tagger.find(
        "BHTTagPotentialNativeReplyRequest("
    )
    catch_position = fail_open_tagger.find(
        "@catch (__unused NSException* exception)"
    )
    if not (
        -1 < gate_position < try_position < tag_position < catch_position
    ):
        raise AssertionError(
            "The constructor helper must fast-gate first and contain all "
            "tagging work inside its exception guard"
        )
    constructor_groups = (
        (
            "BHTNativeReplyDataRequestHook",
            "BHTNativeReplyDataRequestCompletionHook",
            "dataTaskWithRequest:(NSURLRequest*)request",
            "%orig(request);",
            "BHTReplyRequestConstructorData",
        ),
        (
            "BHTNativeReplyDataRequestCompletionHook",
            "BHTNativeReplyUploadDataHook",
            "completionHandler:(id)completionHandler",
            "%orig(request, completionHandler);",
            "BHTReplyRequestConstructorDataCompletion",
        ),
        (
            "BHTNativeReplyUploadDataHook",
            "BHTNativeReplyUploadDataCompletionHook",
            "fromData:(NSData*)bodyData",
            "%orig(request, bodyData);",
            "BHTReplyRequestConstructorUploadData",
        ),
        (
            "BHTNativeReplyUploadDataCompletionHook",
            "BHTNativeReplyUploadFileHook",
            "completionHandler:(id)completionHandler",
            "%orig(request, bodyData, completionHandler);",
            "BHTReplyRequestConstructorUploadDataCompletion",
        ),
        (
            "BHTNativeReplyUploadFileHook",
            "BHTNativeReplyUploadFileCompletionHook",
            "fromFile:(NSURL*)fileURL",
            "%orig(request, fileURL);",
            "BHTReplyRequestConstructorUploadFile",
        ),
        (
            "BHTNativeReplyUploadFileCompletionHook",
            "BHTNativeReplyTNLCompletionHooks",
            "completionHandler:(id)completionHandler",
            "%orig(request, fileURL, completionHandler);",
            "BHTReplyRequestConstructorUploadFileCompletion",
        ),
    )
    for (
        group_name,
        next_group,
        selector_fragment,
        orig_call,
        constructor_kind,
    ) in constructor_groups:
        group = source_section(
            reply_network_hook,
            f"%group {group_name}",
            f"%group {next_group}",
            f"fail-open reply constructor {group_name}",
        )
        if (
            group.count("%orig(") != 1
            or group.count("BHTReplyNetworkTagFailOpen(") != 1
            or group.find("%orig(") > group.find("BHTReplyNetworkTagFailOpen(")
            or selector_fragment not in group
            or orig_call not in group
            or constructor_kind not in group
        ):
            raise AssertionError(
                "Each native reply constructor must call X first, then "
                f"run one fail-open diagnostic: {group_name}"
            )
    completion_groups = (
        (
            "BHTNativeReplyTNLCompletionHooks",
            "BHTNativeReplyTNLDelegateCompletionHooks",
            "%orig(task, session, error);",
        ),
        (
            "BHTNativeReplyTNLDelegateCompletionHooks",
            None,
            "%orig(session, task, error);",
        ),
    )
    for group_name, next_group, orig_call in completion_groups:
        end_marker = (
            f"%group {next_group}" if next_group else "%ctor {"
        )
        completion_group = source_section(
            reply_network_hook,
            f"%group {group_name}",
            end_marker,
            f"fail-open native reply completion hook {group_name}",
        )
        if (
            completion_group.count("%orig(") != 1
            or orig_call not in completion_group
            or completion_group.find("%orig(")
            > completion_group.find("@try {")
            or "BHTCompletePotentialNativeReplyRequest(task, error);"
            not in completion_group
            or "@catch (__unused NSException* exception)"
            not in completion_group
        ):
            raise AssertionError(
                "Each TNL completion hook must call X first and contain "
                "all diagnostic work inside an exception guard: "
                f"{group_name}"
            )
    network_ctor = reply_network_hook.split("%ctor {", 1)[1]
    private_init = network_ctor.find(
        "%init(BHTNativeReplyTNLCompletionHooks);"
    )
    exclusive_else = network_ctor.find("} else {", private_init)
    delegate_init = network_ctor.find(
        "%init(BHTNativeReplyTNLDelegateCompletionHooks);"
    )
    if not (-1 < private_init < exclusive_else < delegate_init):
        raise AssertionError(
            "Exactly one TNL completion seam must install: use the private "
            "finalizer when present, otherwise the verified delegate seam"
        )
    constructor_install_specs = (
        (
            "dataTaskWithRequest:",
            "BHTNativeReplyDataRequestHook",
            "BHTReplyRequestConstructorData",
        ),
        (
            "dataTaskWithRequest:completionHandler:",
            "BHTNativeReplyDataRequestCompletionHook",
            "BHTReplyRequestConstructorDataCompletion",
        ),
        (
            "uploadTaskWithRequest:fromData:",
            "BHTNativeReplyUploadDataHook",
            "BHTReplyRequestConstructorUploadData",
        ),
        (
            "uploadTaskWithRequest:fromData:completionHandler:",
            "BHTNativeReplyUploadDataCompletionHook",
            "BHTReplyRequestConstructorUploadDataCompletion",
        ),
        (
            "uploadTaskWithRequest:fromFile:",
            "BHTNativeReplyUploadFileHook",
            "BHTReplyRequestConstructorUploadFile",
        ),
        (
            "uploadTaskWithRequest:fromFile:completionHandler:",
            "BHTNativeReplyUploadFileCompletionHook",
            "BHTReplyRequestConstructorUploadFileCompletion",
        ),
    )
    for selector, group_name, constructor_kind in constructor_install_specs:
        pattern = re.compile(
            rf"@selector\({re.escape(selector)}\)[\s\S]*?"
            rf"%init\({re.escape(group_name)}\);[\s\S]*?"
            r"BHTMarkReplyRequestConstructorHookInstalled\(\s*"
            rf"{re.escape(constructor_kind)}\s*\);"
        )
        if not pattern.search(network_ctor):
            raise AssertionError(
                "The guarded constructor install does not match its exact "
                f"selector/group/counter mapping: {selector}"
            )
    correlation_helper = source_section(
        compatibility_source,
        "BOOL BHTReplyWorkflowDiagnosticSessionForNetworkRequest(",
        "typedef struct {",
        "strict native reply network correlation window",
    )
    require_source_tokens(
        correlation_helper,
        (
            "BHTReplyWorkflowSessionActive &&",
            "BHTReplyWorkflowSendForwarded &&",
            "BHTReplyWorkflowComposerPresented &&",
            "BHTReplyWorkflowSendForwardedAt > 0",
            "BHTReplyWorkflowNetworkCorrelationWindowSeconds",
            "*generation = active",
            "BHTReplyWorkflowNetworkWindowOpen",
        ),
        "strict native reply network correlation window",
    )

    reply_application_header = (
        ROOT / "src" / "Reply" / "BHTReplyApplicationDiagnostics.h"
    ).read_text(encoding="utf-8")
    reply_application_source = (
        ROOT / "src" / "Reply" / "BHTReplyApplicationDiagnostics.m"
    ).read_text(encoding="utf-8")
    reply_application_hook = (
        ROOT / "src" / "Hooks" / "ReplyApplicationDiagnostics.x"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        reply_application_header + reply_application_source,
        (
            "BHTRecordNativeReplyApplicationResult(",
            "BHTNativeReplyApplicationRequestURLIsEligible(",
            "BHTRecordNativeReplyPreparedResponse(",
            "BHTMarkNativeReplyApplicationHookInstalled(void)",
            "BHTMarkNativeReplyPreparedHookInstalled(void)",
            "BHTMarkNativeReplySwiftValueBoxRecognitionAvailable(void)",
            "BHTNativeReplyApplicationDiagnosticSnapshot(void)",
            "BHTNativeReplyDecodedOutcomeModelPresent",
            "BHTNativeReplyDecodedOutcomeAPIErrors",
            "BHTNativeReplyDecodedOutcomeParseError",
            "BHTNativeReplyDecodedOutcomeEmptyResult",
            "BHTNativeReplyModelStructureStateUnexpectedModelClass",
            "BHTNativeReplyModelStructureStateOpaqueSwiftValueBox",
            '@"opaqueSwiftValueBox"',
            "BHTNativeReplyModelStructureStateMissingCreateTweet",
            "BHTNativeReplyModelStructureStateMissingTweetResults",
            "BHTNativeReplyModelStructureStatePayloadPresent",
            'URL.lastPathComponent',
            'isEqualToString:@"CreateTweet"',
            'isEqualToString:@"CreateTweetWithUndo"',
            'BHTNativeReplyApplicationAttemptLimit = 8',
            '@"sessionGeneration": @(sessionGeneration)',
            '@"modelPresent": @(modelPresent)',
            '@"parseErrorPresent": @(parseErrorPresent)',
            '@"apiErrorsState":',
            '@"modelStructureState":',
            '@"modelStructureLayoutAvailable":',
            '@"swiftValueBoxRecognitionAvailable":',
            '@"modelStructureCounters":',
            '@"effectiveModelPresent": @(effectiveModelPresent)',
            '@"effectiveParseErrorPresent":',
            '@"effectiveOperationErrorPresent":',
            '@"effectiveAPIErrorsState":',
            '@"effectiveErrorState":',
            '@"finalModelState":',
            '@"finalParseErrorState":',
            '@"finalOperationErrorState":',
            '@"finalAPIErrorsState":',
            '@"observationState":',
            '@"preparedObservationCounters":',
            '@"prepareHookInstalled":',
            '@"recentPreparedAttempts": preparedAttempts',
            '@"correlationScope": @"process_temporal_operation_only"',
            '@"requestIdentityBound": @NO',
            '@"applicationSuccessIsNotInferred": @YES',
            '@"preparedResponseSuccessIsNotInferred": @YES',
            '@"strictHTTPSAPIHostAndOperationAllowlist": @YES',
            '@"sanitizedAttemptsPersistWhenReportIsWritten": @YES',
            '@"capturesResponseBodies": @NO',
            '@"capturesResponseMessages": @NO',
            '@"capturesRawErrors": @NO',
            '@"capturesErrorDescriptionsOrUserInfo": @NO',
            '@"capturesURLs": @NO',
            '@"capturesHeadersCookiesOrTokens": @NO',
            '@"capturesTweetOrReplyText": @NO',
            '@"capturesIdentifiers": @NO',
            '@"capturesAccountData": @NO',
            '@"inspectsAPIErrorCollectionElements": @NO',
            '@"inspectsErrorDomainsOrCodes": @NO',
            '@"inspectsCreateTweetObjectPresence": @YES',
            '@"inspectsOpaqueSwiftValueContents": @NO',
            '@"opaqueBoxDoesNotImplyApplicationSuccess": @YES',
            '@"inspectsTweetResultsUnionPayload": @NO',
            '@"persistsDecodedObjects": @NO',
            '@"exportsDecodedObjects": @NO',
        ),
        "fixed-category native reply application diagnostics",
    )
    require_source_tokens(
        reply_application_hook,
        (
            'isEqualToString:@"12.9"',
            '%hook _TtC14GraphQLActions23GraphQLEndpointResponse',
            'modelWithParseError:(id __autoreleasing*)parseError',
            'APIErrors:(id __autoreleasing*)APIErrors',
            'BHTReplyApplicationMethodHasDecoderABI(',
            'method_getNumberOfArguments(method) != 4',
            "argument[0] != '^'",
            "argument[1] != '@'",
            'BHTReplyApplicationMethodReturnsObjectWithNoArguments(',
            'BHTReplyApplicationMethodReturnsVoidWithNoArguments(',
            'BHTReplyApplicationGetObject(',
            'BHTReplyApplicationResolveSingleObjectIvar(',
            'class_copyIvarList(cls, &count)',
            'count == 1',
            'object_getIvar(',
            'NSClassFromString(@"__SwiftValue")',
            'object_getClass(model) ==',
            'BHTReplyApplicationSwiftValueClass',
            '@"_TtC13GraphQLModels28CreateTweetOperationResponse"',
            '@"_TtCC13GraphQLModels28CreateTweetOperationResponse11CreateTweet"',
            '"createTweet", 16',
            '"tweetResults", 16',
            'BHTNativeReplyApplicationRequestURLIsEligible(',
            'BHTMarkNativeReplyModelStructureLayoutAvailable();',
            'BHTMarkNativeReplySwiftValueBoxRecognitionAvailable();',
            'NSClassFromString(@"TFSAPIRequest")',
            'NSSelectorFromString(@"originalRequest")',
            'NSSelectorFromString(@"URL")',
            'BHTReplyWorkflowDiagnosticSessionForApplicationResponse(',
            'BHTReplyWorkflowApplicationDiagnosticWindowMayBeActive()',
            'BHTRecordNativeReplyApplicationResult(',
            '%init(BHTNativeReplyApplicationDecoderHooks);',
            'BHTMarkNativeReplyApplicationHookInstalled();',
            '%group BHTNativeReplyApplicationPreparedHooks',
            '- (void)prepare',
            'BHTRecordNativeReplyPreparedResponse(',
            'observationComplete,',
            '@"finalOperationError"',
            '@"finalAPIErrors"',
            '%init(BHTNativeReplyApplicationPreparedHooks);',
            'BHTMarkNativeReplyPreparedHookInstalled();',
            '@catch (__unused NSException* exception)',
        ),
        "guarded X 12.9 decoded reply application hook",
    )
    for forbidden in (
        "class_getName(model",
        "NSStringFromClass(object_getClass(model))",
        "valueForKey:",
        "Mirror",
        "_bridgeAnythingToObjectiveC",
        "__SwiftValue.store",
    ):
        if forbidden in reply_application_hook:
            raise AssertionError(
                "The native reply diagnostic must recognize but never "
                f"inspect the opaque Swift value box: {forbidden}"
            )
    model_state_section = source_section(
        reply_application_hook,
        "BHTReplyApplicationModelStructureState(id model)",
        "static NSURL* BHTReplyApplicationRequestURL(",
        "opaque native reply response representation guard",
    )
    swift_identity_index = model_state_section.find(
        "object_getClass(model) =="
    )
    opaque_return_index = model_state_section.find(
        "BHTNativeReplyModelStructureStateOpaqueSwiftValueBox"
    )
    layout_index = model_state_section.find(
        "BHTReplyApplicationModelLayoutAvailable"
    )
    if not (
        0 <= swift_identity_index < opaque_return_index < layout_index
    ):
        raise AssertionError(
            "The exact opaque Swift-value representation must return before "
            "any direct generated-model layout inspection"
        )
    if reply_application_hook.count("%orig(") != 1:
        raise AssertionError(
            "The decoded reply diagnostic must forward to X exactly once"
        )
    decoded_hook_body = source_section(
        reply_application_hook,
        "- (id)modelWithParseError:",
        "%end",
        "decoded reply application hook",
    )
    fast_gate_position = decoded_hook_body.find(
        "BHTReplyWorkflowApplicationDiagnosticWindowMayBeActive()"
    )
    correlation_position = decoded_hook_body.find(
        "BHTReplyWorkflowDiagnosticSessionForApplicationResponse("
    )
    original_position = decoded_hook_body.find(
        "%orig(parseError, APIErrors);"
    )
    request_position = decoded_hook_body.find(
        "BHTReplyApplicationRequestURL(self)"
    )
    decoded_error_position = decoded_hook_body.find(
        "id decodedParseError ="
    )
    decoded_eligibility_position = decoded_hook_body.find(
        "BHTNativeReplyApplicationRequestURLIsEligible("
    )
    decoded_structure_position = decoded_hook_body.find(
        "BHTReplyApplicationModelStructureState(model)"
    )
    record_position = decoded_hook_body.find(
        "BHTRecordNativeReplyApplicationResult("
    )
    if not (
        -1 < fast_gate_position < correlation_position < original_position
        < request_position < decoded_error_position
        < decoded_eligibility_position < decoded_structure_position
        < record_position
    ):
        raise AssertionError(
            "The application hook must capture only the numeric reply "
            "generation before X, then inspect decoded presence after X"
        )
    if decoded_hook_body.count("return model;") != 2:
        raise AssertionError(
            "The decoded reply hook must preserve X's model on both the "
            "uncorrelated and correlated paths"
        )
    if reply_application_hook.count("object_getIvar(") != 2:
        raise AssertionError(
            "The model-structure diagnostic may inspect only the guarded "
            "createTweet and tweetResults object-presence fields"
        )
    prepared_hook_body = source_section(
        reply_application_hook,
        "- (void)prepare",
        "%end",
        "prepared reply application hook",
    )
    prepared_fast_gate_position = prepared_hook_body.find(
        "BHTReplyWorkflowApplicationDiagnosticWindowMayBeActive()"
    )
    prepared_correlation_position = prepared_hook_body.find(
        "BHTReplyWorkflowDiagnosticSessionForApplicationResponse("
    )
    prepared_orig_position = prepared_hook_body.find("%orig;")
    prepared_request_position = prepared_hook_body.find(
        "BHTReplyApplicationRequestURL(self)"
    )
    prepared_eligibility_position = prepared_hook_body.find(
        "BHTNativeReplyApplicationRequestURLIsEligible("
    )
    prepared_getter_position = prepared_hook_body.find(
        "BHTReplyApplicationGetObject("
    )
    prepared_record_position = prepared_hook_body.rfind(
        "BHTRecordNativeReplyPreparedResponse("
    )
    if not (
        -1 < prepared_fast_gate_position < prepared_correlation_position
        < prepared_orig_position < prepared_request_position
        < prepared_eligibility_position < prepared_getter_position
        < prepared_record_position
    ):
        raise AssertionError(
            "The prepared-response hook must capture only the numeric "
            "generation before X, then enforce the exact request allowlist "
            "before inspecting final presence after X"
        )
    if prepared_hook_body.count("%orig;") != 1:
        raise AssertionError(
            "The prepared-response diagnostic must call X exactly once"
        )
    application_allowlist = source_section(
        reply_application_source,
        "static BOOL BHTNativeReplyApplicationOperationForURL(",
        "static BHTNativeReplyAPIErrorState",
        "decoded reply exact URL allowlist",
    )
    application_allowlist_literals = set(
        re.findall(r'@"([^"]+)"', application_allowlist)
    )
    if application_allowlist_literals != {
        "https",
        "CreateTweet",
        "CreateTweetWithUndo",
        "api.twitter.com",
        "api.x.com",
    }:
        raise AssertionError(
            "The decoded reply allowlist contains an unexpected scheme, "
            f"host, or operation: {sorted(application_allowlist_literals)}"
        )
    for fuzzy in ("hasSuffix:", "hasPrefix:", "containsString:"):
        if fuzzy in application_allowlist:
            raise AssertionError(
                "The decoded reply allowlist must use exact comparisons: "
                f"{fuzzy}"
            )
    for unsafe_application_value in (
        "absoluteString",
        "HTTPBody",
        "allHTTPHeaderFields",
        "valueForHTTPHeaderField",
        "httpCookieStore",
        "NSHTTPCookieStorage",
        "localizedDescription",
        ".userInfo",
        "statusID",
        "userID",
        "fromUserName",
        "objectAtIndex:",
        "firstObject",
        "enumerateObjects",
        "valueForKey:",
        "JSONObjectWithData:",
        "dataWithJSONObject:",
    ):
        if unsafe_application_value in (
            reply_application_source + reply_application_hook
        ):
            raise AssertionError(
                "Decoded reply diagnostics must not inspect response or "
                f"account contents: {unsafe_application_value}"
            )
    application_correlation_helper = source_section(
        compatibility_source,
        "BOOL BHTReplyWorkflowDiagnosticSessionForApplicationResponse(",
        "typedef struct {",
        "native reply application correlation",
    )
    require_source_tokens(
        application_correlation_helper,
        (
            "BHTReplyWorkflowSessionActive &&",
            "BHTReplyWorkflowSendForwarded &&",
            "BHTReplyWorkflowComposerPresented &&",
            "BHTReplyWorkflowSessionGeneration > 0",
            "BHTReplyWorkflowSendForwardedAt > 0",
            "BHTReplyWorkflowApplicationCorrelationWindowSeconds",
            "*generation = active",
        ),
        "active native reply application correlation",
    )
    if application_correlation_helper.find(
        "BHTExpireReplyWorkflowSessionIfNeededLocked();"
    ) > application_correlation_helper.find(
        "BOOL active ="
    ):
        raise AssertionError(
            "Application correlation must expire stale workflow state "
            "before accepting a generation"
        )
    if "BHTReplyWorkflowNetworkCorrelationWindowSeconds" in (
        application_correlation_helper
    ):
        raise AssertionError(
            "Decoded application correlation must survive Undo Tweet's "
            "deferred outbox interval"
        )
    application_fast_gate = source_section(
        compatibility_source,
        "BOOL BHTReplyWorkflowApplicationDiagnosticWindowMayBeActive(void)",
        "static NSUInteger\nBHTReplyWorkflowGenerationForFailureNotification",
        "lock-free native reply application hint",
    )
    require_source_tokens(
        application_fast_gate,
        (
            "atomic_load_explicit(",
            "&BHTReplyWorkflowApplicationWindowOpen",
            "memory_order_acquire",
        ),
        "lock-free native reply application hint",
    )
    for forbidden in (
        "@synchronized",
        "BHTObservationLock",
        "request",
        "URL",
        "dispatch_",
    ):
        if forbidden in application_fast_gate:
            raise AssertionError(
                "The app-global decoded reply hint must remain a single "
                f"lock-free atomic read: {forbidden}"
            )
    require_source_tokens(
        compatibility_source,
        (
            '#import "Reply/BHTReplyApplicationDiagnostics.h"',
            '@"nativeReplyApplication":',
            'BHTNativeReplyApplicationDiagnosticSnapshot()',
            '@"applicationCorrelationWindowSeconds":',
            'BHTProbe(@"nativeReplyApplication", '
            '@"_TtC14GraphQLActions23GraphQLEndpointResponse", '
            '@"modelWithParseError:APIErrors:", NO)',
            'BHTProbe(@"nativeReplyApplication", '
            '@"_TtC14GraphQLActions23GraphQLEndpointResponse", '
            '@"prepare", NO)',
            'BHTProbe(@"nativeReplyApplication", '
            '@"_TtC14GraphQLActions23GraphQLEndpointResponse", '
            '@"originalRequest", NO)',
            'BHTProbe(@"nativeReplyApplication", '
            '@"_TtC14GraphQLActions23GraphQLEndpointResponse", '
            '@"finalOperationError", NO)',
            'BHTProbe(@"nativeReplyApplication", '
            '@"_TtC14GraphQLActions23GraphQLEndpointResponse", '
            '@"finalAPIErrors", NO)',
            'BHTProbe(@"nativeReplyApplication", '
            '@"TFSAPIRequest", @"URL", NO)',
        ),
        "decoded reply application report integration",
    )

    detailed_reply_header = (
        ROOT / "src" / "Reply" / "BHTDetailedReplyDiagnostics.h"
    ).read_text(encoding="utf-8")
    detailed_reply_source = (
        ROOT / "src" / "Reply" / "BHTDetailedReplyDiagnostics.m"
    ).read_text(encoding="utf-8")
    debug_settings_source = (
        ROOT / "src" / "Settings" / "Pages" /
        "DebugSettingsViewController.m"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        settings_source,
        (
            '@"key": @"detailed_reply_diagnostics"',
            '@"default": @NO',
            '@"excludeFromProfile": @YES',
            '@"SETTINGS_SECTION_REPLY_DIAGNOSTICS"',
        ),
        "default-off non-profile detailed reply setting",
    )
    require_source_tokens(
        detailed_reply_header + detailed_reply_source,
        (
            "BHTArmDetailedReplyDiagnostics(void)",
            "BHTDetailedReplyDiagnosticsCaptureDecodedResponse(",
            "BHTDetailedReplyDiagnosticsCapturePreparedResponse(",
            "BHTDetailedReplyDiagnosticsCaptureTypedResult(",
            "BHTDetailedReplyDiagnosticsCaptureFailure(",
            "BHTDetailedReplyDiagnosticSnapshot(void)",
            "BHTDetailedReplyArmLifetime = 10.0 * 60.0",
            "BHTDetailedReplyCaptureLifetime = 90.0",
            "BHTDetailedReplyResponseLimit = 256 * 1024",
            "BHTDetailedReplyMaximumDepth = 8",
            "BHTDetailedReplyMaximumDictionaryKeys = 32",
            "BHTDetailedReplyMaximumArrayElements = 16",
            "BHTDetailedReplyMaximumStringLength = 2048",
            'NSSelectorFromString(@"info")',
            'NSSelectorFromString(@"data")',
            "BHTDetailedReplyMethodReturnsObjectWithNoArguments(",
            "JSONObjectWithData:data",
            '@"overLimitOmitted"',
            '@"nonJSONOmitted"',
            '@"temporaryInvasiveBeta": @YES',
            '@"containsSensitivePersonalData": @YES',
            '@"includedOnlyByExplicitDetailedExport": @YES',
            '@"authorizationHeaders": @YES',
            '@"cookiesAndWebKitStorage": @YES',
            '@"authenticationTokens": @YES',
            '@"rawNonJSONResponseBytes": @YES',
        ),
        "bounded one-shot detailed reply capture",
    )
    for redacted_key in (
        "authorization",
        "cookie",
        "password",
        "clientsecret",
        "accesstoken",
        "refreshtoken",
        "oauthtoken",
        "bearertoken",
        "guesttoken",
        "token",
        "header",
        "csrftoken",
        "attestation",
        "ct0",
    ):
        if f'@"{redacted_key}"' not in detailed_reply_source:
            raise AssertionError(
                "Detailed reply capture must redact credential-like key: "
                f"{redacted_key}"
            )
    for forbidden_capture_api in (
        "allHTTPHeaderFields",
        "valueForHTTPHeaderField",
        "HTTPShouldHandleCookies",
        "NSHTTPCookie",
        "WKWebsiteDataStore",
        "HTTPBody",
        "HTTPBodyStream",
        "Authorization",
    ):
        if forbidden_capture_api in detailed_reply_source:
            raise AssertionError(
                "Detailed reply capture must never inspect credentials or "
                f"request transport state: {forbidden_capture_api}"
            )
    decoded_detail_position = decoded_hook_body.find(
        "BHTDetailedReplyDiagnosticsCaptureDecodedResponse("
    )
    if not (
        original_position < decoded_eligibility_position
        < decoded_detail_position
    ):
        raise AssertionError(
            "Detailed response capture must run after X's decoder and the "
            "exact CreateTweet allowlist"
        )
    require_source_tokens(
        reply_hook_source,
        (
            '%hook TFNTwitterCompositionUpdateStatusOperation',
            '_tfn_main_statusesUpdateCommandDidUpdateStatus:',
            'BHTReplyWorkflowApplicationDiagnosticWindowMayBeActive()',
            'BHTReplyWorkflowDiagnosticSessionForApplicationResponse(',
            'BHTDetailedReplyDiagnosticsCaptureTypedResult(',
            '%orig(status, error);',
            'NSClassFromString(\n        @"TFNTwitterCompositionUpdateStatusOperation")',
            'BHTReplyDiagnosticMethodHasObjectArguments(',
        ),
        "guarded typed reply-result checkpoint",
    )
    typed_hook = source_section(
        reply_hook_source,
        "- (void)_tfn_main_statusesUpdateCommandDidUpdateStatus:",
        "%end",
        "typed reply result hook",
    )
    if typed_hook.count("%orig(status, error);") != 1 or (
        typed_hook.find("BHTDetailedReplyDiagnosticsCaptureTypedResult(")
        > typed_hook.find("%orig(status, error);")
    ):
        raise AssertionError(
            "The typed result must be captured once before forwarding the "
            "exact status/error pair unchanged"
        )
    require_source_tokens(
        compatibility_report_header + compatibility_source,
        (
            "BHTWriteDetailedCompatibilityReportAsync(",
            "if (includeDetailedReplyDiagnostics)",
            '@"detailedReplyDiagnostics"',
            "BHTDetailedReplyDiagnosticSnapshot()",
            "BHTWriteCompatibilityReportNow(NO, nil)",
            "BHTWriteCompatibilityReportNow(\n            YES, temporaryURL)",
        ),
        "explicit-only detailed compatibility report",
    )
    require_source_tokens(
        debug_settings_source,
        (
            'isEqualToString:@"detailed_reply_diagnostics"',
            "BHTArmDetailedReplyDiagnostics();",
            "BHTDisarmDetailedReplyDiagnostics();",
            "BHTDetailedReplyDiagnosticsHasCapture()",
            "BHTWriteDetailedCompatibilityReportAsync(completion);",
            "BHTWriteCompatibilityReportAsync(completion);",
            "if (includeDetails && completed)",
            "BHTClearDetailedReplyDiagnostics();",
            "removeItemAtURL:reportURL",
        ),
        "confirmed detailed export and temporary-file cleanup",
    )

    web_reply_header = (
        ROOT / "src" / "Reply" / "BHTWebReplyFallback.h"
    ).read_text(encoding="utf-8")
    web_reply_source = (
        ROOT / "src" / "Reply" / "BHTWebReplyFallback.m"
    ).read_text(encoding="utf-8")
    account_bound_reply_header = (
        ROOT / "src" / "Reply" / "BHTAccountBoundWebReply.h"
    ).read_text(encoding="utf-8")
    account_bound_reply_source = (
        ROOT / "src" / "Reply" / "BHTAccountBoundWebReply.m"
    ).read_text(encoding="utf-8")
    account_bound_reply_hook = (
        ROOT / "src" / "Hooks" / "AccountBoundWebReply.x"
    ).read_text(encoding="utf-8")
    tweets_settings_source = (
        ROOT
        / "src"
        / "Settings"
        / "Pages"
        / "TweetsSettingsViewController.m"
    ).read_text(encoding="utf-8")
    settings_source = SETTINGS.read_text(encoding="utf-8")
    english_source = ENGLISH.read_text(encoding="utf-8")

    require_source_tokens(
        web_reply_header,
        (
            "BHTWebReplyRouteResultDisabled",
            "BHTWebReplyRouteResultMissingOrInvalidStatus",
            "BHTWebReplyRouteResultOffMainThread",
            "BHTWebReplyRouteResultPresentationUnavailable",
            "BHTWebReplyRouteResultPresented",
            "BHTWebReplyRouteResultAlreadyPresented",
            "BHTTryPresentWebReplyFallback(",
            "BHTTryPresentAccountBoundWebReplyFallback(",
            "id _Nullable nativeAccount",
            "BHTPresentWebReplySignInSetup(",
            "BHTPresentWebReplyAccountManager(",
            "BHTWebReplyAccountLabelDidChangeNotification",
            "BHTWebReplyAccountLabel(void)",
            "BHTWebReplyRouteResultConsumesTap(",
            "BHTWebReplyFallbackDiagnosticSnapshot(void)",
        ),
        "web reply fallback API",
    )
    require_source_tokens(
        web_reply_source,
        (
            "WKWebsiteDataStore.defaultDataStore",
            "preferredContentMode = WKContentModeMobile",
            "allowsContentJavaScript = YES",
            "UIModalPresentationFullScreen",
            "UIModalPresentationPageSheet",
            "UIModalPresentationFormSheet",
            "BHTWebReplyScreenModeReply",
            "BHTWebReplyScreenModeSignInSetup",
            "BHTWebReplyScreenModeAccountManagement",
            "setToolbarHidden:YES",
            "didCommitNavigation:",
            "BHTWebReplyDiagnosticNavigationCommitted",
            "BHTWebReplyDiagnosticLoaderHiddenOnCommit",
            "BHTWebReplyDiagnosticSignInLandingRecognized",
            "BHTWebReplyDiagnosticSetupCompletedManually",
            "BHTWebReplyDiagnosticAccountManagerCompleted",
            "BHTWebReplyDiagnosticNativeAccountChanged",
            "BHTWebReplyDiagnosticAccountBoundaryWarningShown",
            "BHTWebReplyDiagnosticAccountBoundaryContinued",
            "BHTWebReplyDiagnosticAccountBoundaryReviewOpened",
            "BHTWebReplyDiagnosticAccountBoundaryCancelled",
            "BHTWebReplyDiagnosticManageWebAccountOpened",
            "BHTWebReplyDiagnosticIgnoredNavigationBeforeCommit",
            "BHTWebReplyDiagnosticAccountManagerFallbackStarted",
            "BHTWebReplyDiagnosticAccountManagerFallbackCommitted",
            "BHTWebReplyDiagnosticAccountManagerFallbackFailed",
            "BHTWebReplyDiagnosticPageNavigationWatchdogArmed",
            "BHTWebReplyDiagnosticAccountManagerLandingRecognized",
            "BHTWebReplyDiagnosticTransitionPendingBlocked",
            "BHTWebReplyDiagnosticWebViewCloseReceived",
            "BHTWebReplyURLIsSignedInLanding(",
            "BHTWebReplyURLIsAccountSessionLanding(",
            "BHTWebReplyAccountURL(",
            "BHTWebReplyAccountFallbackURL(",
            "BHTNormalizedWebReplyAccountLabel(",
            "BHTSetWebReplyAccountLabel(",
            "BHTWebReplyAccountLabelDefaultsKey",
            "BHTWebReplyURLObservationContext",
            'forKeyPath:@"URL"',
            "considerSetupLandingURL:",
            "hasVisibleCommittedContent",
            "mainFrameDidFinish",
            "latestMainFrameNavigation",
            "mainFrameProvisionalNavigationInFlight",
            "explicitMainFrameNavigationAwaitingStart",
            "WKNavigation* requestedNavigation",
            "settleMainFrameProvisionalNavigationForCallback:",
            "showSetupReady",
            "doneTapped",
            "self.doneCompletion = nil;",
            "BHTPresentWebReplyAccountBoundary(",
            "BHTAcknowledgeWebReplyAccountBoundary(",
            "BHTPerformWhenWebReplyPresenterIsReady(",
            "BHTLastWebReplyNativeAccount",
            "BHTWebReplyAccountBoundaryAcknowledged",
            "BHTWebReplyTransitionPending",
            "if (!nativeAccount) return;",
            "recoverFromIgnoredNavigationError",
            "scheduleAccountManagerFallbackIfNeeded",
            "recordAccountManagerFallbackFailureIfNeeded",
            "accountManagerFallbackScheduled",
            "accountManagerFallbackAttempted",
            "accountManagerFallbackCommitted",
            "accountManagerFallbackFailureRecorded",
            "armLoadWatchdogForNavigation:",
            "BHTHostIsExactOrSubdomain(",
            'BHTHostIsExactOrSubdomain(host, @"x.com")',
            'BHTHostIsExactOrSubdomain(host, @"twitter.com")',
            '[host isEqualToString:@"accounts.google.com"]',
            '[host isEqualToString:@"appleid.apple.com"]',
            'componentsWithString:\n                @"https://x.com/intent/tweet"',
            'queryItemWithName:@"in_reply_to"',
            "BHTWebReplyURLIsLoginFlow(",
            "canExplicitlyConfirmWebAccount",
            "showExplicitConfirmationUnavailableAlert",
            "observedLoginNavigation",
            "BHTWebReplyIsExpectedAppHandoffURL(",
            '[scheme isEqualToString:@"x"]',
            '[scheme isEqualToString:@"twitter"]',
            "BHTWebKitFrameLoadInterruptedByPolicyChangeErrorCode = 102",
            "BHTWebReplyIsWebKitErrorDomain(",
            '[domain isEqualToString:@"WebKitErrorDomain"]',
            "BHTWebReplyDiagnosticPolicyInterruptionIgnored",
            "BHTWebReplyDiagnosticAppHandoffIgnored",
            "BHTWebReplyDiagnosticAutomaticPopupIgnored",
            "BHTWebReplyDiagnosticBlankPopupIgnored",
            "BHTWebReplyDiagnosticBlankMainFramePrevented",
            "BHTWebReplyDiagnosticBlankMainFrameFinished",
            "BHTWebReplyDiagnosticUserPopupRerouted",
            "BHTWebReplyDiagnosticMainFrameHTTPClientError",
            "BHTWebReplyDiagnosticMainFrameHTTPServerError",
            "BHTWebReplyDiagnosticMainFrameEmptyResponse",
            "BHTWebReplyDiagnosticMainFrameUnsupportedMIMEType",
            "BHTWebReplyDiagnosticLoadWatchdogExpired",
            "BHTWebReplyDiagnosticNavigationBlockedUserInitiated",
            "BHTWebReplyDiagnosticNavigationBlockedAutomatic",
            "BHTWebReplyNavigationIsUserInitiated(",
            "BOOL opensNewWindow =",
            "if (opensNewWindow && !userInitiated)",
            "BHTWebReplyURLIsAboutBlank(",
            "scheduleUserPopupRequest:",
            "loadRequestWithWatchdog:",
            "(int64_t)(20.0 * NSEC_PER_SEC)",
            "decidePolicyForNavigationResponse:",
            "BHTRecordWebReplyNavigationFailure(error, YES)",
            "BHTRecordWebReplyNavigationFailure(error, NO)",
            "BHTWebReplyDiagnosticFailureOfflineOrCannotConnect",
            "BHTWebReplyDiagnosticFailureDNS",
            "BHTWebReplyDiagnosticFailureTLS",
            "BHTWebReplyDiagnosticFailureTimedOut",
            "BHTWebReplyDiagnosticFailureUnsupportedURL",
            "BHTPresentWebReplyScreen(",
            '@"WEB_REPLY_SIGN_IN_TITLE"',
            '@"WEB_REPLY_SIGN_IN_LOAD_FAILED"',
            '@"WEB_REPLY_PREPARING"',
            '@"WEB_REPLY_SIGN_IN_LOADING"',
            "class_getInstanceMethod(object_getClass(object), selector)",
            "method_getNumberOfArguments(method) == 2",
            "@catch (__unused NSException* exception)",
            "const NSUInteger maximumObjects = 24;",
            "const NSUInteger maximumDepth = 4;",
            "BHTActiveWebReplyNavigationController",
            "BOOL presentationAccepted =",
            "presenter.presentedViewController == navigation",
            '@"usesOfficialWebIntent": @YES',
            '@"usesDefaultWebsiteDataStore": @YES',
            '@"offersVisiblePersistentSignInSetup": @YES',
            '@"revealsContentOnFirstMainFrameCommit": @YES',
            '@"usesModeSpecificNativeChrome": @YES',
            '@"showsPersistentBrowserToolbar": @NO',
            '@"recognizesSignedInLandingWithoutCookieInspection": @YES',
            '@"requiresCommittedOrSameDocumentSignedInLanding": @YES',
            '@"supportsManualSetupCompletion": @YES',
            '@"guardsAccountBoundaryTransitions": @YES',
            '@"customFallbackUsesSingleSharedWebAccountSession": @YES',
            '@"usesIntentForAccountManagement": @YES',
            '@"usesLoginFlowForAccountManagement": @NO',
            '@"usesOneShotAccountManagerIntentRetry": @YES',
            '@"usesIntentForInitialSignInSetup": @YES',
            '@"requiresExplicitConfirmationForInitialIntent": @YES',
            '@"autoConfirmsOnlyHomeOrPostLoginIntent": @YES',
            '@"precommitPolicyInterruptionsCannotLeaveLoaderVisible": @YES',
            '@"warnsWhenNativeAccountObjectChanges": @YES',
            '@"rechecksEveryReplyWithoutNativeAccountContext": @YES',
            '@"remembersNativeAccountOnlyInProcess": @YES',
            '@"persistsNativeAccountAssociation": @NO',
            '@"storesUserConfirmedAccountLabel": @YES',
            '@"automaticallyDetectsWebAccount": @NO',
            '@"accountLabelIsUserProvided": @YES',
            '@"exportsAccountLabelInReports": @NO',
            '@"exportsAccountLabelInPreferenceProfiles": @NO',
            '@"knownNativeContextBoundaryAcknowledged":',
            '@"accountBoundaryTransitionPending":',
            '@"tweakReadsOrWritesCookies": @NO',
            '@"injectsPageScripts": @NO',
            '@"inspectsRequestBodies": @NO',
            '@"capturesReplyText": @NO',
            '@"capturesStatusIdentifiers": @NO',
            '@"capturesAccountData": @NO',
            '@"observesSendCompletion": @NO',
            '@"postsThroughHiddenWebView": @NO',
            '@"verifiesWebAccountMatchesAppAccount": @NO',
            '@"capturesRawErrors": @NO',
        ),
        "privacy-safe native-style web reply composer",
    )
    require_source_tokens(
        account_bound_reply_header + account_bound_reply_source,
        (
            "BHTTryPresentAccountBoundWebReply(",
            "BHTAccountBoundInitializerHasExactABI(",
            "method_getNumberOfArguments(method) != 9",
            "const char expectedTypes[] = {'@', '@', 'B', 'B', '@', '@', '@'}",
            'NSClassFromString(@"T1WebViewController")',
            'NSClassFromString(@"T1BaseWebViewController")',
            'NSClassFromString(@"T1WebNavigationController")',
            'isEqualToString:@"12.9"',
            "replyURL, account, YES, NO,",
            "nil, nil, nil",
            "controllerAccount != account",
            "OBJC_ASSOCIATION_RETAIN_NONATOMIC",
            "UIAdaptivePresentationControllerDelegate",
            "BHTAccountBoundWebReplyEventCustomFallbackUsed",
            "BHTAccountBoundWebReplyEventCustomFallbackFailed",
            '@"passesHookAccountByObjectIdentity": @YES',
            '@"usesVisibleHostController": @YES',
            '@"providesVisibleCloseControl": @YES',
            "UIBarButtonSystemItemDone",
            "@selector(dismissVisibleReply:)",
            '@"accessesHostWebView": @NO',
            '@"readsCookiesOrTokens": @NO',
            '@"injectsPageScripts": @NO',
            '@"inspectsRequestBodies": @NO',
            '@"capturesAccountData": @NO',
            '@"capturesStatusIdentifiers": @NO',
            '@"capturesRawErrors": @NO',
            '@"observesSendCompletion": @NO',
            '@"postsThroughHiddenWebView": @NO',
        ),
        "guarded account-bound visible X reply controller",
    )
    account_bound_url_allowlist = source_section(
        account_bound_reply_source,
        "static BOOL BHTAccountBoundReplyURLIsAllowed(NSURL* URL)",
        "static BOOL BHTAccountBoundPresenterIsAvailable(",
        "account-aware visible reply URL allowlist",
    )
    require_source_tokens(
        account_bound_url_allowlist,
        (
            'isEqualToString:@"https"',
            'isEqualToString:@"x.com"',
            'isEqualToString:@"tweet"',
        ),
        "account-aware visible reply URL allowlist",
    )
    if (
        account_bound_url_allowlist.count("return YES;") != 1
        or any(
            fuzzy in account_bound_url_allowlist
            for fuzzy in ("hasSuffix:", "hasPrefix:", "containsString:")
        )
        or set(
            re.findall(r'@"([^"]+)"', account_bound_url_allowlist)
        )
        != {"https", "x.com", "tweet"}
    ):
        raise AssertionError(
            "The account-aware reply route must accept only the exact "
            "HTTPS x.com intent/tweet boundary"
        )
    account_bound_close = source_section(
        account_bound_reply_source,
        "@implementation BHTAccountBoundWebReplyDismissalDelegate",
        "@end",
        "account-aware visible reply close target",
    )
    require_source_tokens(
        account_bound_close,
        (
            "- (void)dismissVisibleReply:",
            "BHTActiveAccountBoundWebReplyNavigationController = nil;",
            "&BHTAccountBoundWebReplyTransitionPending",
            "false, memory_order_release",
            "dismissViewControllerAnimated:YES",
            "BHTAccountBoundWebReplyEventDismissed",
        ),
        "account-aware visible reply close target",
    )
    if (
        "webController.navigationItem.leftBarButtonItem = closeItem;"
        not in account_bound_reply_source
        or "action:@selector(dismissVisibleReply:)"
        not in account_bound_reply_source
    ):
        raise AssertionError(
            "The account-aware visible reply must wire its retained close "
            "target into the navigation item"
        )
    require_source_tokens(
        account_bound_reply_hook,
        (
            "%hook T1WebViewController",
            "doesURLResultTypeOpenInWebview:(NSInteger)resultType",
            "BHTAccountBoundWebReplyOwnsController(self)",
            "return %orig(resultType);",
            "BHTAccountBoundKeepMethodHasExactABI(",
            "method_getNumberOfArguments(method) != 3",
            "*result == 'B'",
            "*argument == 'q'",
            "BHTMarkAccountBoundWebReplyKeepInWebviewHookInstalled();",
        ),
        "scoped account-bound keep-in-webview hook",
    )
    for unsafe_account_bound_value in (
        "evaluateJavaScript",
        "WKUserScript",
        "httpCookieStore",
        "NSHTTPCookieStorage",
        "auth_token",
        '"ct0"',
        "HTTPBody",
        "allHTTPHeaderFields",
        "localizedDescription",
        "absoluteString",
        "currentAccount",
        "sharedHostViewController",
    ):
        if unsafe_account_bound_value in (
            account_bound_reply_source + account_bound_reply_hook
        ):
            raise AssertionError(
                "The account-bound host controller must stay visible and "
                "must not inspect web authentication or page data: "
                f"{unsafe_account_bound_value}"
            )
    if (
        "self.navigationItem.prompt =" in web_reply_source
        or "setToolbarHidden:NO" in web_reply_source
    ):
        raise AssertionError(
            "Compatibility replies must not expose persistent browser chrome"
        )
    setup_landing_source = source_section(
        web_reply_source,
        "- (void)considerSetupLandingURL:",
        "- (void)showSetupReady",
        "web reply signed-in landing recognition",
    )
    require_source_tokens(
        setup_landing_source,
        (
            "self.hasVisibleCommittedContent",
            "self.mainFrameProvisionalNavigationInFlight",
            "BHTWebReplyURLIsSignedInLanding(URL)",
            "BHTWebReplyURLIsAccountSessionLanding(URL)",
            "self.mainFrameDidFinish",
            "[self showSetupReady];",
        ),
        "commit-driven web reply setup completion",
    )
    for obsolete_gate in (
        "setupLandingGeneration",
        "dispatch_after(",
        "estimatedProgress",
    ):
        if obsolete_gate in setup_landing_source:
            raise AssertionError(
                "A committed signed-in landing must not wait on a one-shot "
                f"progress gate: {obsolete_gate}"
            )
    require_source_tokens(
        setup_landing_source,
        (
            "BHTWebReplyURLIsLoginFlow(URL)",
            "self.observedLoginNavigation = YES",
            "self.observedLoginNavigation &&",
            "signedInLanding || returnedToIntent",
            "signedInLanding || self.mainFrameDidFinish",
        ),
        "explicit-or-post-login account confirmation gate",
    )
    navigation_settlement_source = source_section(
        web_reply_source,
        "- (BOOL)settleMainFrameProvisionalNavigationForCallback:",
        "- (void)webView:(__unused WKWebView*)webView\n"
        "        didStartProvisionalNavigation:",
        "web reply navigation-token settlement",
    )
    require_source_tokens(
        navigation_settlement_source,
        (
            "WKNavigation* currentNavigation",
            "currentNavigation != navigation",
            "return NO;",
            "currentNavigation == navigation",
            "self.mainFrameProvisionalNavigationInFlight = nil;",
            "- (BOOL)finishMainFrameNavigationForCallback:",
            "self.latestMainFrameNavigation = nil;",
        ),
        "navigation-specific setup-ready protection",
    )
    load_watchdog_source = source_section(
        web_reply_source,
        "- (void)loadRequestWithWatchdog:\n"
        "    (NSURLRequest*)request {",
        "- (void)scheduleUserPopupRequest:",
        "web reply navigation-token watchdog",
    )
    require_source_tokens(
        load_watchdog_source,
        (
            "WKNavigation* requestedNavigation",
            "[self.webView loadRequest:request]",
            "self.latestMainFrameNavigation =",
            "self.mainFrameProvisionalNavigationInFlight =",
            "requestedNavigation",
            "self.explicitMainFrameNavigationAwaitingStart =",
            "strongSelf.mainFrameProvisionalNavigationInFlight !=",
        ),
        "navigation-specific reply load watchdog",
    )
    did_start_source = source_section(
        web_reply_source,
        "- (void)webView:(__unused WKWebView*)webView\n"
        "        didStartProvisionalNavigation:",
        "- (void)webView:(WKWebView*)webView\n"
        "        didCommitNavigation:",
        "web reply explicit-navigation start guard",
    )
    require_source_tokens(
        did_start_source,
        (
            "WKNavigation* explicitNavigation",
            "explicitMainFrameNavigationAwaitingStart",
            "explicitNavigation != navigation",
            "return;",
            "explicitNavigation == navigation",
            "self.latestMainFrameNavigation =",
            "self.mainFrameProvisionalNavigationInFlight =",
            "pageInitiatedNavigation",
            "BHTWebReplyDiagnosticPageNavigationWatchdogArmed",
            "armLoadWatchdogForNavigation:",
        ),
        "explicit and page-initiated navigation watchdog guard",
    )
    setup_ready_source = source_section(
        web_reply_source,
        "- (void)showSetupReady",
        "- (void)recoverFromIgnoredNavigationError",
        "web reply setup-ready transition",
    )
    if "[self.webView stopLoading]" in setup_ready_source:
        raise AssertionError(
            "Setup success must not interrupt X while its session finishes"
        )
    require_source_tokens(
        setup_ready_source,
        (
            "BHTWebReplyScreenModeAccountManagement",
            "BHTWebReplyDiagnosticAccountManagerLandingRecognized",
            "self.navigationItem.rightBarButtonItems =",
            "@[self.doneItem, self.accountLabelItem]",
        ),
        "native account-manager confirmation",
    )
    ignored_navigation_recovery = source_section(
        web_reply_source,
        "- (void)recoverFromIgnoredNavigationError",
        "- (BOOL)settleMainFrameProvisionalNavigationForCallback:",
        "pre-commit ignored-navigation recovery",
    )
    require_source_tokens(
        ignored_navigation_recovery,
        (
            "!self.hasVisibleCommittedContent",
            "BHTWebReplyDiagnosticIgnoredNavigationBeforeCommit",
            "scheduleAccountManagerFallbackIfNeeded",
            "recordAccountManagerFallbackFailureIfNeeded",
            "[self showLoadFailure];",
        ),
        "terminal pre-commit ignored-navigation recovery",
    )
    account_routes_source = source_section(
        web_reply_source,
        "static NSURL* BHTWebReplyAccountURL(void)",
        "static BOOL BHTHostIsExactOrSubdomain(",
        "web reply account routes",
    )
    require_source_tokens(
        account_routes_source,
        (
            "BHTWebReplyAccountFallbackURL(void)",
            '@"https://x.com/intent/tweet"',
            "BHTWebReplyAccountURL()",
        ),
        "supported account-management entry and fallback routes",
    )
    if (
        '[NSURL URLWithString:@"https://x.com/home"]'
        in account_routes_source
    ):
        raise AssertionError(
            "Account management must not directly reopen the /home route "
            "that report 27 showed being interrupted before commit"
        )
    if 'https://x.com/i/flow/login' in account_routes_source:
        raise AssertionError(
            "Account management must not reopen X's committed login shell "
            "that report 28 showed could spin indefinitely"
        )
    sign_in_setup_source = source_section(
        web_reply_source,
        "BOOL BHTPresentWebReplySignInSetup(",
        "BOOL BHTPresentWebReplyAccountManager(",
        "initial web reply sign-in setup route",
    )
    if (
        "BHTWebReplyAccountURL()" not in sign_in_setup_source
        or "BHTWebReplySignInURL" in sign_in_setup_source
    ):
        raise AssertionError(
            "Initial setup must use the proven intent route instead of X's "
            "committed login shell"
        )
    done_source = source_section(
        web_reply_source,
        "- (void)doneTapped",
        "- (void)recordCloseIfNeeded",
        "web reply Done diagnostics",
    )
    require_source_tokens(
        done_source,
        (
            "BHTWebReplyScreenModeSignInSetup",
            "!self.setupReady",
            "BHTWebReplyScreenModeReply",
            "BHTWebReplyDiagnosticSetupCompletedManually",
            "BHTWebReplyDiagnosticAccountManagerCompleted",
            "[self canExplicitlyConfirmWebAccount]",
            "[self showExplicitConfirmationUnavailableAlert]",
            "[self transitionToSetupReady];",
            "return;",
            "self.doneCompletion = nil;",
            "self.beginsReplyTransitionOnDone",
            "BHTSetWebReplyTransitionPending(YES)",
            "navigation.transitionCoordinator",
            "animateAlongsideTransition:nil",
        ),
        "mode-specific web reply Done behavior",
    )
    confirmation_source = source_section(
        web_reply_source,
        "- (BOOL)canExplicitlyConfirmWebAccount",
        "- (void)recordCloseIfNeeded",
        "web account explicit-confirmation gate",
    )
    require_source_tokens(
        confirmation_source,
        (
            "self.hasVisibleCommittedContent",
            "!self.mainFrameProvisionalNavigationInFlight",
            "self.errorView.hidden",
            "!BHTWebReplyURLIsLoginFlow(self.webView.URL)",
            'BHTWebReplyLocalized(\n                @"WEB_REPLY_CONFIRM_WAIT_TITLE")',
            'BHTWebReplyLocalized(\n                @"WEB_REPLY_CONFIRM_WAIT_DETAIL")',
        ),
        "stable web account explicit confirmation",
    )
    reply_options_source = source_section(
        web_reply_source,
        "- (void)moreTapped",
        "- (void)showWebAccountManager",
        "web reply options transition",
    )
    if (
        "BHTPerformWhenWebReplyPresenterIsReady("
        not in reply_options_source
        or "(int64_t)(0.25 * NSEC_PER_SEC)"
        in reply_options_source
    ):
        raise AssertionError(
            "Reply options must wait for actual modal readiness instead of "
            "assuming a fixed action-sheet dismissal time"
        )
    if "https://x.com/compose/post" in web_reply_source:
        raise AssertionError(
            "Compatibility replies must use X's supported Web Intent route"
        )
    for forbidden in (
        "httpCookieStore",
        "NSHTTPCookieStorage",
        "WKUserScript",
        "evaluateJavaScript",
        "addScriptMessageHandler",
        "document.cookie",
        "HTTPBody",
        "allHTTPHeaderFields",
        "Authorization",
        "auth_token",
        '"ct0"',
        '"Bearer',
        "NSURLSession",
        "NSLog",
        "localizedDescription",
    ):
        if forbidden in web_reply_source:
            raise AssertionError(
                "The compatibility composer must not inspect or seed web "
                f"session data: {forbidden}"
            )
    account_label_source = source_section(
        web_reply_source,
        "static NSString* BHTNormalizedWebReplyAccountLabel(",
        "static NSURL* BHTWebReplyURL(",
        "local web-reply account label",
    )
    require_source_tokens(
        account_label_source,
        (
            "handle.length == 0 || handle.length > 15",
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_",
            "BHTWebReplyAccountLabelDefaultsKey",
            "removeObjectForKey:",
            "BHTWebReplyAccountLabelDidChangeNotification",
        ),
        "strict local-only user-confirmed account label",
    )
    if "bht_web_reply_account_label" in settings_source:
        raise AssertionError(
            "The optional web-account label must not enter the exportable "
            "settings/profile index"
        )
    web_reply_diagnostic = source_section(
        web_reply_source,
        "NSDictionary* BHTWebReplyFallbackDiagnosticSnapshot(void)",
        "\n}",
        "web reply diagnostic snapshot",
    )
    for private_label_value in (
        '@"accountLabel":',
        '@"accountLabelPresent":',
        "accountLabelSaved",
        "accountLabelCleared",
        "BHTWebReplyAccountLabel()",
        "BHTWebReplyAccountLabelDefaultsKey",
        "stringForKey:",
    ):
        if private_label_value in web_reply_diagnostic:
            raise AssertionError(
                "Compatibility reports must not expose local account-label "
                "state or values: "
                f"{private_label_value}"
            )
    if (
        'hasSuffix:[@"." stringByAppendingString:' not in web_reply_source
        or "containsString" in source_section(
            web_reply_source,
            "static BOOL BHTHostIsExactOrSubdomain(",
            "static BOOL BHTWebReplyAllowsTopLevelURL(",
            "web reply host boundary check",
        )
    ):
        raise AssertionError(
            "Web reply navigation must use a suffix-boundary host check"
        )

    web_route_source = source_section(
        web_reply_source,
        "static BHTWebReplyRouteResult\n"
        "BHTTryPresentWebReplyFallbackInternal(",
        "BHTWebReplyRouteResult BHTTryPresentWebReplyFallback(",
        "web reply route",
    )
    if web_route_source.find(
        'boolForKey:@"web_reply_fallback"'
    ) > web_route_source.find("BHTResolveStatusIdentifier("):
        raise AssertionError(
            "The status object must remain opaque while web replies are off"
        )
    transition_guard_position = web_route_source.find(
        "&BHTWebReplyTransitionPending"
    )
    if (
        transition_guard_position < 0
        or transition_guard_position
        > web_route_source.find("BHTResolveStatusIdentifier(")
    ):
        raise AssertionError(
            "A reply tap during an account-boundary transition must be "
            "consumed before reading the status object"
        )
    require_source_tokens(
        web_route_source,
        (
            "if (!nativeAccount)",
            "BHTLastWebReplyNativeAccount = nil;",
            "&BHTWebReplyAccountBoundaryAcknowledged, NO",
            "!nativeAccount ||",
        ),
        "conservative unknown native-account boundary",
    )
    route_consumption_source = source_section(
        web_reply_source,
        "BOOL BHTWebReplyRouteResultConsumesTap(",
        "NSDictionary* BHTWebReplyFallbackDiagnosticSnapshot(void)",
        "web reply tap-consumption rule",
    )
    if (
        "BHTWebReplyRouteResultPresented" not in route_consumption_source
        or "BHTWebReplyRouteResultAlreadyPresented"
        not in route_consumption_source
    ):
        raise AssertionError(
            "Only a presented or already-visible web composer may consume "
            "the native reply tap"
        )
    for fallback_result in (
        "BHTWebReplyRouteResultDisabled",
        "BHTWebReplyRouteResultMissingOrInvalidStatus",
        "BHTWebReplyRouteResultOffMainThread",
        "BHTWebReplyRouteResultPresentationUnavailable",
    ):
        if fallback_result in route_consumption_source:
            raise AssertionError(
                "A failed web route must preserve X's native reply: "
                f"{fallback_result}"
            )
    account_boundary_source = source_section(
        web_reply_source,
        "static BOOL BHTPresentWebReplyAccountBoundary(",
        "BHTWebReplyRouteResult BHTTryPresentWebReplyFallback(",
        "web reply account boundary",
    )
    if (
        account_boundary_source.count(
            "BHTPerformWhenWebReplyPresenterIsReady("
        )
        < 3
        or "BHTSetWebReplyTransitionPending(YES)"
        not in account_boundary_source
        or "BHTSetWebReplyTransitionPending(NO)"
        not in account_boundary_source
        or "(int64_t)(0.35 * NSEC_PER_SEC)"
        in account_boundary_source
    ):
        raise AssertionError(
            "Account-boundary navigation must follow actual modal readiness "
            "instead of a fixed dismissal delay"
        )

    require_source_tokens(
        reply_hook_source,
        (
            '#import "Reply/BHTWebReplyFallback.h"',
            "BHTTryPresentWebReplyFallback(",
            "BHTTryPresentAccountBoundWebReplyFallback(",
            "BHTWebReplyRouteResultConsumesTap(routeResult)",
            "BHTReplyWorkflowDiagnosticWebFallbackPresented",
            "BHTCurrentNativeAccountForWebReply",
            'NSSelectorFromString(@"currentAccount")',
            "class_getClassMethod(cls, selector)",
            "method_getNumberOfArguments(method) != 2",
            "@catch (__unused NSException* exception)",
            "%group BHTPersistentReplyActionFallbackHooks",
            "- (void)persistentComposeViewDidTap:",
            'boolForKey:@"web_reply_fallback"',
            "self.statusViewModel",
            'NSSelectorFromString(@"persistentComposeViewDidTap:")',
        ),
        "native reply fallback integration",
    )
    primary_reply_fallback = source_section(
        reply_hook_source,
        "- (void)performReplyActionWithAccount:",
        "%end",
        "primary reply fallback account context",
    )
    if (
        "BHTTryPresentAccountBoundWebReplyFallback("
        not in primary_reply_fallback
        or
        "originalStatus, account, topMostController()"
        not in primary_reply_fallback
    ):
        raise AssertionError(
            "The primary reply fallback must prefer X's account-bound "
            "controller and forward the hook account with the status object"
        )
    persistent_fallback = source_section(
        reply_hook_source,
        "- (void)persistentComposeViewDidTap:",
        "%end",
        "persistent composer web fallback",
    )
    if persistent_fallback.count("%orig(sender);") != 1:
        raise AssertionError(
            "The persistent reply tap must forward to X exactly once when "
            "the web composer is unavailable"
        )
    if persistent_fallback.find(
        'boolForKey:@"web_reply_fallback"'
    ) > persistent_fallback.find("self.statusViewModel"):
        raise AssertionError(
            "Persistent reply metadata must not be read while web replies "
            "are disabled"
        )

    require_source_tokens(
        settings_source,
        (
            '@"key": @"web_reply_fallback"',
            '@"default": @NO',
            '@"excludeFromProfile": @YES',
            '@"key": @"web_reply_sign_in_setup"',
            '@"action": @"showWebReplySignInSetup:"',
            '@"parentKey": @"web_reply_fallback"',
            '![setting[@"excludeFromProfile"] boolValue]',
        ),
        "opt-in non-exportable web reply preference",
    )
    require_source_tokens(
        tweets_settings_source,
        (
            'isEqualToString:@"web_reply_fallback"',
            '@"WEB_REPLY_FALLBACK_DISCLOSURE"',
            '@"WEB_REPLY_FALLBACK_SIGN_IN_NOW"',
            '@"WEB_REPLY_FALLBACK_NOT_NOW"',
            '@"WEB_REPLY_FALLBACK_TURN_OFF"',
            "BHTPresentWebReplySignInSetup(",
            "BHTPresentWebReplyAccountManager(self)",
            'isEqualToString:@"web_reply_sign_in_setup"',
            "BHTWebReplyAccountLabel()",
            '@"WEB_REPLY_ACCOUNT_LABEL_NONE"',
            '@"WEB_REPLY_ACCOUNT_LABEL_FORMAT"',
            "BHTWebReplyAccountLabelDidChangeNotification",
        ),
        "web reply account-boundary disclosure",
    )
    require_source_tokens(
        english_source,
        (
            '"WEB_REPLY_FALLBACK_TITLE"',
            '"WEB_REPLY_FALLBACK_DETAIL"',
            '"WEB_REPLY_FALLBACK_DISCLOSURE"',
            '"WEB_REPLY_FALLBACK_SIGN_IN_NOW"',
            '"WEB_REPLY_FALLBACK_NOT_NOW"',
            '"WEB_REPLY_SIGN_IN_SETUP_TITLE"',
            '"WEB_REPLY_SIGN_IN_SETUP_DETAIL"',
            '"WEB_REPLY_SIGN_IN_TITLE"',
            '"WEB_REPLY_SIGN_IN_LOAD_FAILED"',
            '"WEB_REPLY_PREPARING"',
            '"WEB_REPLY_SIGN_IN_LOADING"',
            '"WEB_REPLY_SIGN_IN_READY_TITLE"',
            '"WEB_REPLY_SIGN_IN_READY_DETAIL"',
            '"WEB_REPLY_USE_WEB_ACCOUNT"',
            '"WEB_REPLY_CONFIRM_WAIT_TITLE"',
            '"WEB_REPLY_CONFIRM_WAIT_DETAIL"',
            '"WEB_REPLY_TITLE"',
            '"WEB_REPLY_MANAGE_ACCOUNT"',
            '"WEB_REPLY_ACCOUNT_SESSION_CHECK"',
            '"WEB_REPLY_ACCOUNT_LABEL_BUTTON"',
            '"WEB_REPLY_ACCOUNT_LABEL_ACTION"',
            '"WEB_REPLY_ACCOUNT_LABEL_TITLE"',
            '"WEB_REPLY_ACCOUNT_LABEL_DETAIL"',
            '"WEB_REPLY_ACCOUNT_LABEL_PLACEHOLDER"',
            '"WEB_REPLY_ACCOUNT_LABEL_SAVE"',
            '"WEB_REPLY_ACCOUNT_LABEL_FORGET"',
            '"WEB_REPLY_ACCOUNT_LABEL_INVALID_TITLE"',
            '"WEB_REPLY_ACCOUNT_LABEL_INVALID_DETAIL"',
            '"WEB_REPLY_ACCOUNT_LABEL_NONE"',
            '"WEB_REPLY_ACCOUNT_LABEL_FORMAT"',
            '"WEB_REPLY_ACCOUNT_LABEL_CONTEXT_FORMAT"',
            '"WEB_REPLY_ACCOUNT_BOUNDARY_TITLE"',
            '"WEB_REPLY_ACCOUNT_BOUNDARY_DETAIL"',
            '"WEB_REPLY_ACCOUNT_CHANGED_DETAIL"',
            '"WEB_REPLY_REVIEW_ACCOUNT"',
            '"WEB_REPLY_CONTINUE_TO_REPLY"',
            '"WEB_REPLY_DONE"',
            '"WEB_REPLY_MORE"',
            '"WEB_REPLY_ABOUT"',
            '"WEB_REPLY_CANCEL"',
            '"WEB_REPLY_LOAD_FAILED"',
            '"WEB_REPLY_BLOCKED_LINK_DETAIL"',
            '"Inline replies first ask X\'s visible web screen to authenticate',
            "Only that backup browser shares one persistent x.com session",
            "does not switch with it",
            "after this app launch",
            "may have changed",
        ),
        "web reply localization",
    )
    require_source_tokens(
        compatibility_source,
        (
            '#import "Reply/BHTWebReplyFallback.h"',
            '@"webReplyFallback":',
            "BHTWebReplyFallbackDiagnosticSnapshot()",
            '@"web_reply_fallback"',
        ),
        "redacted web reply compatibility report",
    )
    popup_policy_source = source_section(
        web_reply_source,
        "decidePolicyForNavigationAction:",
        "createWebViewWithConfiguration:",
        "web reply popup policy",
    )
    automatic_popup_guard = popup_policy_source.find(
        "if (opensNewWindow && !userInitiated)"
    )
    blank_popup_guard = popup_policy_source.find(
        "BHTWebReplyURLIsAboutBlank(destination)"
    )
    allowed_new_window_branch = popup_policy_source.find(
        "if (opensNewWindow) {\n"
        "        decisionHandler(WKNavigationActionPolicyAllow);"
    )
    if (
        automatic_popup_guard < 0
        or blank_popup_guard < 0
        or allowed_new_window_branch < 0
        or automatic_popup_guard > allowed_new_window_branch
        or blank_popup_guard > allowed_new_window_branch
        or "[webView loadRequest:" in popup_policy_source
        or "scheduleUserPopupRequest:" in popup_policy_source
    ):
        raise AssertionError(
            "Navigation policy must reject automatic/blank popups and "
            "leave permitted user popup loading to WKUIDelegate"
        )

    popup_creation_source = source_section(
        web_reply_source,
        "createWebViewWithConfiguration:",
        "@end",
        "web reply popup creation",
    )
    popup_creation_guard = popup_creation_source.find(
        "if (!userInitiated)"
    )
    popup_creation_blank_guard = popup_creation_source.find(
        "if (BHTWebReplyURLIsAboutBlank(destination))"
    )
    popup_creation_load = popup_creation_source.find(
        "[self scheduleUserPopupRequest:"
    )
    if (
        popup_creation_guard < 0
        or popup_creation_blank_guard < 0
        or popup_creation_load < 0
        or popup_creation_guard > popup_creation_load
        or popup_creation_blank_guard > popup_creation_load
    ):
        raise AssertionError(
            "WKUIDelegate must ignore automatic and about:blank popups "
            "before scheduling their request in the main WebView"
        )

    popup_schedule_source = source_section(
        web_reply_source,
        "- (void)scheduleUserPopupRequest:",
        "- (void)showLoadFailure",
        "asynchronous popup reroute",
    )
    if (
        "dispatch_async(dispatch_get_main_queue()" not in
            popup_schedule_source
        or popup_schedule_source.find(
            "dispatch_async(dispatch_get_main_queue()"
        )
        > popup_schedule_source.find(
            "loadRequestWithWatchdog:requestCopy"
        )
    ):
        raise AssertionError(
            "A user popup must be rerouted after returning from WebKit's "
            "navigation delegate"
        )

    if "Version: 6.1.0-beta.49" not in (
        ROOT / "control"
    ).read_text(encoding="utf-8"):
        raise AssertionError(
            "The one-shot detailed reply diagnostics must ship as beta.49"
        )

    branding_source = (
        ROOT / "src" / "Branding" / "BHTBranding.m"
    ).read_text(encoding="utf-8")
    if '@"twitter_bird"' not in branding_source:
        raise AssertionError("Central Twitter bird asset lookup is missing")

    ipa_branding_source = (
        ROOT / "branding" / "ipa_branding.py"
    ).read_text(encoding="utf-8")
    for required in (
        "_apply_builtin_launch_bird",
        'stock_name = b"xLogo"',
        '"tBird@3x.png"',
        "TWITTER_BLUE = (29, 161, 242)",
    ):
        if required not in ipa_branding_source:
            raise AssertionError(
                f"Missing pre-injection launch branding: {required}"
            )
    merged_car_source = (
        ROOT / "branding" / "build_merged_car.py"
    ).read_text(encoding="utf-8")
    for required in ('name.lower() == "xlogo"', "template-rendering-intent"):
        if required not in merged_car_source:
            raise AssertionError(
                f"Missing xLogo template invariant: {required}"
            )

    theme_preset_source = (
        ROOT / "src" / "ThemeColor" / "BHTThemePresets.m"
    ).read_text(encoding="utf-8")
    for required in (
        '@"apollo_inspired"',
        '@"classic_twitter"',
        '@"midnight_oled"',
        '@"evergreen"',
        '@"rose_quartz"',
        '@"solarized_coast"',
        '@"amethyst"',
        '@"cinder"',
        '@"native_blue"',
        '@"lightColors"',
        '@"darkColors"',
        "BHTThemeColorAccentKey",
        "BHTThemeColorBackgroundKey",
        "BHTThemeColorSurfaceKey",
        "BHTThemeColorTextKey",
        "BHTThemeColorSeparatorKey",
        "activeAppColorsForDarkAppearance",
        "newUserThemeDraftBasedOnPreset",
        "validatedUserThemesFromObject",
        "userThemesByMergingImportedThemes",
        "replaceUserThemes",
        "BHTMaximumUserThemeCount = 64",
        "BHTNormalizedOpaqueThemeHex",
        "BHTThemeVersionIsExactly",
        "CFBooleanGetTypeID",
        "Preflight both modes",
        "respondsToSelector:@selector(setPrimaryColorOption:)",
    ):
        if required not in theme_preset_source:
            raise AssertionError(f"Missing theme preset invariant: {required}")

    built_in_source = theme_preset_source.split(
        "+ (BOOL)isBuiltInPresetIdentifier:", 1
    )[0]
    chunks = built_in_source.split('@"identifier": @"')[1:]
    parsed_presets = []
    required_roles = {
        "Accent",
        "Background",
        "Surface",
        "ElevatedSurface",
        "Text",
        "SecondaryText",
        "Separator",
    }
    for chunk in chunks:
        identifier, remainder = chunk.split('"', 1)
        title_match = re.search(r'@"titleKey": @"([^"]+)"', remainder)
        detail_match = re.search(r'@"detailKey": @"([^"]+)"', remainder)
        if not title_match or not detail_match:
            raise AssertionError(
                f"Preset lacks title/detail localization: {identifier}"
            )
        title_key = title_match.group(1)
        detail_key = detail_match.group(1)
        if title_key not in localized_keys or detail_key not in localized_keys:
            raise AssertionError(
                f"Preset localization is missing: {identifier}"
            )

        maps = {}
        for mode in ("lightColors", "darkColors"):
            map_match = re.search(
                rf'@"{mode}": @\{{(.*?)\n\s*\}}',
                remainder,
                flags=re.DOTALL,
            )
            if map_match:
                colors = dict(
                    re.findall(
                        r"BHTThemeColor"
                        r"(Accent|Background|Surface|ElevatedSurface|"
                        r"Text|SecondaryText|Separator)"
                        r'Key: @"(#[0-9A-F]{6})"',
                        map_match.group(1),
                    )
                )
                if set(colors) != required_roles:
                    raise AssertionError(
                        f"Incomplete {mode} palette: {identifier}"
                    )
                maps[mode] = colors

        if identifier == "native_blue":
            if maps:
                raise AssertionError(
                    "Native Blue must preserve X's native palette"
                )
        else:
            if set(maps) != {"lightColors", "darkColors"}:
                raise AssertionError(
                    f"Full preset lacks both appearances: {identifier}"
                )
            for mode, colors in maps.items():
                surfaces = [
                    colors["Background"],
                    colors["Surface"],
                    colors["ElevatedSurface"],
                ]
                for role in ("Text", "SecondaryText", "Accent"):
                    minimum = min(
                        contrast_ratio(colors[role], surface)
                        for surface in surfaces
                    )
                    if minimum < 4.5:
                        raise AssertionError(
                            f"{identifier} {mode} {role} contrast "
                            f"is only {minimum:.2f}:1"
                        )
        parsed_presets.append(identifier)

    if len(parsed_presets) != len(set(parsed_presets)):
        raise AssertionError("Theme preset identifiers must be unique")
    if len(parsed_presets) < 9:
        raise AssertionError("Expected the expanded built-in theme library")

    save_user_theme = source_section(
        theme_preset_source,
        "+ (NSDictionary*)saveUserTheme:",
        "+ (BOOL)deleteUserThemeIdentifier:",
        "custom-theme save",
    )
    if "applyPresetIdentifier:" in save_user_theme:
        raise AssertionError(
            "Saving a custom theme must remain storage-only so Save & Apply "
            "cannot trigger two full theme refreshes"
        )

    if not THEME_BUILDER.exists() or not THEME_BUILDER_HEADER.exists():
        raise AssertionError(
            "The custom theme builder implementation and header must ship"
        )
    theme_builder_source = THEME_BUILDER.read_text(encoding="utf-8")
    theme_builder_header = THEME_BUILDER_HEADER.read_text(encoding="utf-8")
    require_source_tokens(
        theme_builder_header,
        (
            "@interface BHTThemeBuilderViewController",
            "initWithTheme:",
        ),
        "theme-builder public entry point",
    )

    builder_roles = source_section(
        theme_builder_source,
        "static NSArray<NSString*>* BHTThemeBuilderRoles(void)",
        "static NSString* BHTThemeBuilderRoleName",
        "theme-builder role list",
    )
    expected_builder_roles = {
        "BHTThemeColorAccentKey",
        "BHTThemeColorBackgroundKey",
        "BHTThemeColorSurfaceKey",
        "BHTThemeColorElevatedSurfaceKey",
        "BHTThemeColorTextKey",
        "BHTThemeColorSecondaryTextKey",
        "BHTThemeColorSeparatorKey",
    }
    builder_role_list = re.findall(
        r"\bBHTThemeColor[A-Za-z]+Key\b", builder_roles
    )
    actual_builder_roles = set(builder_role_list)
    if actual_builder_roles != expected_builder_roles:
        raise AssertionError(
            "Theme builder must edit exactly the seven coordinated roles: "
            f"{sorted(actual_builder_roles)}"
        )
    if len(builder_role_list) != len(expected_builder_roles):
        raise AssertionError(
            "Theme builder must expose each coordinated role exactly once"
        )

    opaque_hex_validation = source_section(
        theme_builder_source,
        "static NSString* BHTThemeBuilderNormalizedOpaqueHex",
        "static CGFloat BHTThemeBuilderClampColorComponent",
        "theme-builder opaque hex validation",
    )
    require_source_tokens(
        opaque_hex_validation,
        (
            "[Palette normalizedHexString:value]",
            "normalized.length == 7",
        ),
        "exact #RRGGBB validation",
    )
    require_source_tokens(
        theme_builder_source,
        (
            "@interface BHTThemeBuilderColorWell : UIColorWell",
            "self.colorWell.supportsAlpha = NO",
            "candidate.length > 7",
            'characterSetWithCharactersInString:@"#0123456789ABCDEFabcdef"',
        ),
        "opaque system color-well editing",
    )

    builder_initialization = source_section(
        theme_builder_source,
        "- (instancetype)initWithTheme:(NSDictionary*)theme",
        "- (void)viewDidLoad",
        "theme-builder draft initialization",
    )
    require_source_tokens(
        builder_initialization,
        (
            "_draft = [source mutableCopy]",
            '_draft[@"lightColors"] = lightColors',
            '_draft[@"darkColors"] = darkColors',
            "_lastValidLightColors = [lightColors mutableCopy]",
            "_lastValidDarkColors = [darkColors mutableCopy]",
        ),
        "isolated local theme draft",
    )
    preview_section = source_section(
        theme_builder_source,
        "- (NSDictionary*)previewColorsForCurrentAppearance",
        "- (BHTThemeBuilderColorCell*)colorCellContainingView",
        "theme-builder local preview",
    )
    if "lastValidColorsForMapKey" not in preview_section:
        raise AssertionError(
            "Theme-builder preview must use the last valid local draft colors"
        )
    before_save = theme_builder_source.split(
        "#pragma mark - Save and validation", 1
    )[0]
    for persistent_action in ("saveUserTheme:", "applyPresetIdentifier:"):
        if persistent_action in before_save:
            raise AssertionError(
                "Theme-builder editing must not change the active theme "
                f"before Save & Apply: {persistent_action}"
            )

    copy_actions = source_section(
        theme_builder_source,
        "- (void)tableView:(UITableView*)tableView\n"
        "    didSelectRowAtIndexPath:(NSIndexPath*)indexPath",
        "#pragma mark - Editing",
        "theme-builder copy actions",
    )
    require_source_tokens(
        copy_actions,
        (
            'copyColorsFromMapKey:@"lightColors"',
            'toMapKey:@"darkColors"',
            'copyColorsFromMapKey:@"darkColors"',
            'toMapKey:@"lightColors"',
        ),
        "two-way Light/Dark palette copy action",
    )
    require_source_tokens(
        theme_builder_source,
        (
            "THEME_BUILDER_COPY_LIGHT_TO_DARK",
            "THEME_BUILDER_COPY_DARK_TO_LIGHT",
            "theme-builder-copy-light-to-dark",
            "theme-builder-copy-dark-to-light",
        ),
        "discoverable two-way copy controls",
    )

    save_validation = theme_builder_source.split(
        "#pragma mark - Save and validation", 1
    )[1]
    require_source_tokens(
        save_validation,
        (
            '@[@"lightColors", @"darkColors"]',
            "BHTThemeBuilderContrastRatio(primary, surface) < 4.5",
            "BHTThemeBuilderContrastRatio(secondary, surface) < 3.0",
            "BHTThemeBuilderContrastRatio(accent, surface) < 3.0",
            "THEME_BUILDER_LOW_CONTRAST_WARNING",
            "THEME_BUILDER_SAVE_ANYWAY",
            "[BHTThemePresets saveUserTheme:self.draft error:&error]",
            "[BHTThemePresets applyPresetIdentifier:identifier]",
        ),
        "contrast warning and explicit save/apply flow",
    )
    if theme_builder_source.count("saveUserTheme:") != 1:
        raise AssertionError(
            "Theme-builder persistence must have one explicit save path"
        )

    require_source_tokens(
        theme_builder_source,
        (
            "BHTThemeBuilderMaximumReadableWidth = 720.0",
            "constraintLessThanOrEqualToConstant:",
            "BHTThemeBuilderMaximumReadableWidth",
            'self.tableView.accessibilityIdentifier = @"theme-builder-table"',
            '@"theme-builder-save-apply"',
            '@"theme-builder-preview"',
            "self.hexField.accessibilityLabel",
            "self.hexField.accessibilityIdentifier",
            "self.colorWell.accessibilityLabel",
            "self.colorWell.accessibilityIdentifier",
            "UIAccessibilityTraitButton",
        ),
        "720-point readable layout and accessibility metadata",
    )

    referenced_builder_localizations = set(
        re.findall(
            r'@"((?:THEME_BUILDER|THEME_LIBRARY)_[A-Z0-9_]+)"',
            theme_builder_source,
        )
    )
    missing_builder_localizations = sorted(
        referenced_builder_localizations - localized_keys
    )
    if missing_builder_localizations:
        raise AssertionError(
            "Theme-builder localization keys are missing from English: "
            f"{missing_builder_localizations}"
        )

    hook_helpers_source = (
        ROOT / "src" / "Hooks" / "HookHelpers.m"
    ).read_text(encoding="utf-8")
    if "[Palette customAccentColor]" not in hook_helpers_source:
        raise AssertionError("Custom theme accent is not resolved at runtime")
    theme_accent_source = (
        ROOT / "src" / "Hooks" / "ThemeAccent.x"
    ).read_text(encoding="utf-8")
    for required in (
        "BHTPrimaryColorMethodIsCompatible",
        "BHTColorGetterMethodIsCompatible",
        "BHTConfigureFullThemeForPalette",
        "BHTOriginalColorGetterIMP",
        "BHTVoidObjectSetterIsCompatible",
        "BHTInvokeGuardedVoidGetter",
        "TFNDynamicColorsDidReloadNotification",
        "BHTInstallDynamicColorDiagnosticObserver",
        "BHTDidObserveDynamicColorsReload",
        "BHTThemeRoleState",
        "kBHTPaletteRoleStateKey",
        "BHTThemeAccentState",
        "kBHTPaletteAccentStateKey",
        "BHTXDSRoleSnapshot",
        "BHTXDSRoleSnapshotForCurrentGeneration",
        "BHTThemeConfigurationToken",
        "BHTCurrentThemeConfigurationToken",
        "BHTColorFromRoleState",
        "BHTPaletteThemeConfigurationIsComplete",
        "customAccentColorForDarkAppearance:",
        "BHTCurrentThemeConfigurationGeneration",
        "BHTAdvanceThemeConfigurationGeneration",
        "BHTSeenThemePalettes",
        "weakObjectsHashTable",
        "BHTReconfigureSeenThemePalettes",
        "BHTInstallThemeHooksForProviders",
        "BHTInstallUIColorProviderGetterHooks",
        "BHTThemedUIColorProviderSetter",
        '@"setTwitterColors:"',
        "BHTThemeRoleForXDSNamedColor",
        '@"backgroundPrimary"',
        '@"backgroundSheets"',
        '@"foregroundPrimary"',
        '@"borderNormal"',
        '@"XColorEngine_XColorEngine.bundle"',
        '@"xcolorengine.XColorEngine.resources"',
        "colorWithDynamicProvider",
        "resolvedColorWithTraitCollection",
        '@"twitterColors"',
        '@"tfnuiColors"',
        "BHTLastThemeProviderClasses",
        "BHTRecordThemeRuntimeObservation",
        '@"_t1_updateDynamicColors"',
        "kBHTMaximumThemeTraversalViews",
        "BHTScheduleProviderAttachRefresh",
        "BHTPostReloadProviderRedrawNeeded",
        "BHTForcedProviderRedrawExecuting",
        '@"cardBackgroundColor"',
        '@"darkBackgroundColor"',
        '@"capsuleTabsSelectedBackgroundColor"',
        '@"textDetailsColor"',
        '@"conversationLineColor"',
        '@"textLinkColor"',
        '@"retweetButtonColor"',
        "if (colors.count == 0) return state;",
        "return original ?",
        '@"_t1_applyTheme"',
        '@"_t1_updateOverrideUserInterfaceStyle"',
        '@"applyCurrentColorPalette"',
        "@selector(setCurrentColorPalette:)",
        "method_getReturnType",
        "class_addMethod",
        "BHTSettingsProfileDidApplyNotification",
        "[Palette invalidateCustomAccentColorCache]",
    ):
        if required not in theme_accent_source:
            raise AssertionError(
                f"Missing guarded app-wide accent invariant: {required}"
            )
    palette_install = source_section(
        theme_accent_source,
        "static BOOL BHTInstallThemeHookForPalette(",
        "static id BHTThemeProviderFromUIColorSelector",
        "theme-provider installation",
    )
    if (
        "customAccentColorForDarkAppearance:" not in palette_install
        or "[Palette customAccentColor]" in palette_install
        or "currentPaletteUsesDarkAppearance" in palette_install
    ):
        raise AssertionError(
            "Theme-provider installation must resolve its accent from the "
            "known appearance without recursively reading currentColorPalette"
        )
    for contrast_sensitive in (
        '@"capsuleTabsOnMediaSelectedBackgroundColor"',
        '@"capsuleTabsOnMediaTextColor"',
        '@"capsuleTabsOnMediaBorderColor"',
    ):
        if contrast_sensitive in theme_accent_source:
            raise AssertionError(
                "Theme hook must preserve contextual media-tab contrast: "
                f"{contrast_sensitive}"
            )
    if "postNotificationName" in theme_accent_source:
        raise AssertionError(
            "Theme hook must not synthesize X's private dynamic-color "
            "notifications"
        )
    theme_traversal_source = theme_accent_source.split(
        "static void BHTUpdateDynamicColorsInVisibleView", 1
    )[1].split(
        "static void BHTScheduleVisibleDynamicColorRefresh", 1
    )[0]
    if "view.hidden" in theme_traversal_source:
        raise AssertionError(
            "Theme fallback must include loaded hidden subviews"
        )
    palette_source = (
        ROOT / "src" / "ThemeColor" / "Palette.m"
    ).read_text(encoding="utf-8")
    for required in (
        "BHTCustomAccentCacheIsValid",
        "BHTAppThemeColorCacheIsValid",
        "customThemeColorsForDarkAppearance",
        "customAccentColorForDarkAppearance",
        "currentSurfaceColor",
        "currentTextColor",
        "currentSeparatorColor",
        "invalidateCustomAccentColorCache",
        "BHTSettingsProfileDidApplyNotification",
    ):
        if required not in palette_source:
            raise AssertionError(
                f"Missing custom-accent cache invariant: {required}"
            )

    theme_source = (
        ROOT / "src" / "Hooks" / "Theme.x"
    ).read_text(encoding="utf-8")
    for required in (
        "BHTApplyCurrentThemeToTabBarController",
        "BHTApplyThemeToNativeTabBar",
        '@"nativeTabBar"',
        '@"_t1_configureNativeTabBar"',
        "BHTShouldThemeTabItems",
        "BHTTabChromeThemeGeneration",
        "BHTThemedTabBarAppearance",
        "BHTNativeTabBarStillMatches",
    ):
        if required not in theme_source:
            raise AssertionError(
                f"Missing live tab-bar theme invariant: {required}"
            )

    feature_switches_source = (
        ROOT / "src" / "Hooks" / "FeatureSwitches.x"
    ).read_text(encoding="utf-8")
    sidebar_utility_header = (
        ROOT
        / "src"
        / "Sidebar"
        / "BHTSidebarNavigationUtility.h"
    ).read_text(encoding="utf-8")
    sidebar_utility_source = (
        ROOT
        / "src"
        / "Sidebar"
        / "BHTSidebarNavigationUtility.m"
    ).read_text(encoding="utf-8")
    sidebar_runtime_source = (
        ROOT
        / "src"
        / "Sidebar"
        / "BHTSidebarRuntime.swift"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        feature_switches_source,
        (
            "BHTScheduleSidebarConfigurationReapply(",
            "BHTSidebarDeferredApplyScheduledKey",
            "BHTRecordSidebarDeferredApplyScheduled();",
            "BHTRecordSidebarDeferredApplyExecuted();",
            "BHTRecordSidebarDeferredApplyCoalesced();",
            "objc_getAssociatedObject(",
            "objc_setAssociatedObject(",
            "__weak id weakController",
            "dispatch_async(dispatch_get_main_queue()",
            "%hook T1DashContentController",
            "- (void)updateVisiblePanelIDs",
            "%hook T1DashNavigationViewFactory",
            "applyConfigurationToDashContentController:dashContentController",
        ),
        "late Add Account sidebar reconciliation",
    )
    require_source_tokens(
        sidebar_utility_header + sidebar_utility_source,
        (
            "diagnosticSnapshot",
            "BHTRecordSidebarDeferredApplyScheduled",
            "BHTRecordSidebarDeferredApplyExecuted",
            "BHTRecordSidebarDeferredApplyCoalesced",
            "BHTRecordSidebarAddAccountRefreshRequested",
            "BHTSidebarRegisterCallCount",
            "BHTSidebarApplyCallCount",
            "BHTSidebarControllerApplyHandledCount",
            "BHTSidebarControllerApplyChangedCount",
            "BHTSidebarDataSourceFallbackCallCount",
            "BHTSidebarRefreshRequestCount",
            "BHTSidebarRefreshControllerUpdateCount",
            "BHTSidebarDeferredApplyScheduledCount",
            "BHTSidebarDeferredApplyExecutedCount",
            "BHTSidebarDeferredApplyCoalescedCount",
            "BHTSidebarAddAccountRefreshRequestedCount",
            '@"registeredControllerCount"',
            '@"controllerAppliesHandled"',
            '@"dataSourceFallbackAttempts"',
            '@"refreshRequests"',
            '@"refreshControllerUpdateAttempts"',
            '@"deferredApplyScheduled"',
            '@"deferredApplyExecuted"',
            '@"deferredApplyCoalesced"',
            '@"addAccountRefreshRequested"',
            "atomic_load_explicit(",
        ),
        "privacy-safe sidebar reconciliation diagnostics",
    )
    require_source_tokens(
        sidebar_runtime_source + sidebar_utility_source,
        (
            "@objc(applyResultForDashContentController:)",
            "controllerApplyHandled",
            "controllerApplyChanged",
            '@"applyResultForDashContentController:"',
            "BHTSidebarControllerApplyResultHandled",
            "BHTSidebarControllerApplyResultChanged",
            "if (controllerHandled)",
        ),
        "single-pass idempotent sidebar application",
    )
    require_source_tokens(
        compatibility_login_hook,
        (
            "%hook T1AccountsViewController",
            "- (void)viewDidAppear:(BOOL)animated",
            "BHTRecordSidebarAddAccountRefreshRequested();",
            "refreshRegisteredDashContentControllers",
        ),
        "Add Account sidebar refresh diagnostics",
    )
    require_source_tokens(
        compatibility_source,
        (
            '@"sidebarNavigation":',
            '@"visibleItems":',
            '@"runtime":',
            "[BHTSidebarNavigationUtility diagnosticSnapshot]",
        ),
        "sidebar compatibility report diagnostics",
    )
    sidebar_deferred_apply = source_section(
        feature_switches_source,
        "static void BHTScheduleSidebarConfigurationReapply(",
        "%hook T1DashContentController",
        "coalesced sidebar deferred apply",
    )
    if (
        "@selector(updateVisiblePanelIDs)" in sidebar_deferred_apply
        or " updateVisiblePanelIDs]" in sidebar_deferred_apply
    ):
        raise AssertionError(
            "The deferred sidebar reconciliation must apply the saved arrays "
            "directly instead of recursively rebuilding native panel IDs"
        )
    deferred_marker_clear = sidebar_deferred_apply.find(
        "&BHTSidebarDeferredApplyScheduledKey, nil"
    )
    deferred_configuration_apply = sidebar_deferred_apply.find(
        "applyConfigurationToDashContentController:"
    )
    if (
        deferred_configuration_apply < 0
        or deferred_marker_clear < deferred_configuration_apply
        or "@finally" not in sidebar_deferred_apply
    ):
        raise AssertionError(
            "The sidebar coalescing marker must remain set through the "
            "deferred Swift array apply"
        )
    sidebar_factory = source_section(
        feature_switches_source,
        "+ (id)buildDashViewControllerForAccount:",
        "%end",
        "sidebar factory reconciliation",
    )
    original_factory_call = sidebar_factory.find(
        "%orig(account, dashContentController)"
    )
    post_factory_apply = sidebar_factory.rfind(
        "applyConfigurationToDashContentController:dashContentController"
    )
    deferred_factory_apply = sidebar_factory.find(
        "BHTScheduleSidebarConfigurationReapply("
    )
    if (
        original_factory_call < 0
        or post_factory_apply < original_factory_call
        or deferred_factory_apply < post_factory_apply
        or "return %orig(account, dashContentController);" in sidebar_factory
    ):
        raise AssertionError(
            "The saved sidebar layout must be reapplied after X finishes "
            "rebuilding its drawer and once more on the next main turn"
        )

    tab_chrome_source = theme_source.split(
        "// MARK: - Theme tab items without defeating X's native collapse",
        1,
    )[1].split(
        "// MARK: - Tab bar icon and label theming",
        1,
    )[0]
    for forbidden in (
        '@"tabBarBackgroundView"',
        '@"tabBarDivider"',
        "controller.view",
        "tabBar.backgroundColor",
        "tabBar.barTintColor",
        "configureWithOpaqueBackground",
    ):
        if forbidden in tab_chrome_source:
            raise AssertionError(
                "Tab-bar theming must preserve X's native collapse "
                f"background ownership: {forbidden}"
            )

    likes_hook_source = (
        ROOT / "src" / "Hooks" / "Likes.x"
    ).read_text(encoding="utf-8")
    if "[Palette currentSecondaryTextColor]" not in likes_hook_source:
        raise AssertionError(
            "Likes tab must use the active theme's secondary text color"
        )

    editor_colors_source = (
        ROOT / "src" / "CustomTabBar" / "CustomTabBarNativeColors.m"
    ).read_text(encoding="utf-8")
    for required in (
        "BHTThemeColorBackgroundKey",
        "BHTThemeColorSurfaceKey",
        "BHTThemeColorTextKey",
        "BHTThemeColorSeparatorKey",
    ):
        if required not in editor_colors_source:
            raise AssertionError(
                f"Missing themed editor color invariant: {required}"
            )

    modern_settings_source = (
        ROOT / "src" / "Settings" / "ModernSettingsViewController.m"
    ).read_text(encoding="utf-8")
    for required in (
        "UISearchResultsUpdating",
        "allSearchableSettings",
        'setting[@"sectionKey"]',
        'page[@"subtitle"]',
        "showPresetSettings",
        "showBackupSettings",
        '@"route": @"mainNavigation"',
        '@"route": @"likesNavigation"',
        '@"route": @"sidebarNavigation"',
        '@"route": @"mediaActionEditor"',
        '@"route": @"forYouKeywordFilters"',
        '@"identifier": @"waterfall"',
        "[BHTThemePresets allThemes]",
        "willPresentSearchController:",
        "didDismissSearchController:",
        "pendingSettingsSearchResult",
        "settingsSearchRowsVisible",
        "settingsSearchDismissalPending",
        "scheduleSettingsSearchDismissalFallback",
        "searchController.isActive || query.length > 0",
        "settingsSearchTargetIdentifier",
        "BHTThemeDidChangeNotification",
        "currentSurfaceColor",
    ):
        if required not in modern_settings_source:
            raise AssertionError(
                f"Missing settings search/profile UI invariant: {required}"
            )

    settings_page_source = (
        ROOT
        / "src"
        / "Settings"
        / "ModernSettingsPageViewController.m"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        settings_page_source,
        (
            "settingsSearchTargetIdentifier",
            "settingsSearchShouldOpenTarget",
            "[self updateVisibleToggles];",
            "didSelectRowAtIndexPath:match",
            "self.navigationController.topViewController != self",
            "spotlightSettingsSearchTargetCell:",
            "viewDidLayoutSubviews",
        ),
        "exact settings-search row routing",
    )

    preset_settings_source = (
        ROOT
        / "src"
        / "Settings"
        / "Pages"
        / "PresetSettingsViewController.m"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        preset_settings_source,
        (
            "BHTThemesSectionCurrent",
            "BHTThemesSectionBuiltIn",
            "BHTThemesSectionMyThemes",
            "BHTThemesSectionAdvanced",
            "themes.create",
            "themes.accent_only",
            "navigationController.topViewController !=",
        ),
        "unified Themes library",
    )
    for forbidden in (
        "UIDocumentPickerViewController",
        "exportPreferenceProfile:",
        "importPreferenceProfile:",
    ):
        if forbidden in preset_settings_source:
            raise AssertionError(
                "Theme/profile settings became redundant again: "
                f"{forbidden}"
            )

    accent_only_source = (
        ROOT / "src" / "ThemeColor" / "ColorThemeViewController.m"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        accent_only_source,
        (
            "theme-accent-only-swatches",
            "clearPresetSelection",
            "reapplyCurrentAccent",
        ),
        "Accent Only picker",
    )
    for forbidden in (
        "[BHTThemePresets availablePresets]",
        "BHTThemeBuilderViewController",
    ):
        if forbidden in accent_only_source:
            raise AssertionError(
                "Accent Only must not duplicate the full Themes library: "
                f"{forbidden}"
            )

    backup_settings_source = (
        ROOT
        / "src"
        / "Settings"
        / "Pages"
        / "BackupSettingsViewController.m"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        backup_settings_source,
        (
            'return @"backup";',
            "preferenceProfileJSONDataWithError:",
            "applyPreferenceProfile:",
            "kBHTMaximumPreferenceProfileBytes",
        ),
        "Backup & restore page",
    )

    for required in (
        "NeoFreeBird Preference Profile",
        "exportablePreferenceKeys",
        "bht_custom_accent_hex",
        "bht_theme_preset_identifier",
        "BHTSettingsProfileDidApplyNotification",
        "BHTProfileVersionIsExactly",
        "CFBooleanGetTypeID",
        '@"formatVersion": @2',
        '@"userThemes": [BHTThemePresets userThemes]',
        "validatedUserThemesFromObject",
        "userThemesByMergingImportedThemes",
        "isBuiltInPresetIdentifier",
        "BHTUserThemeIdentifierExists",
        "[(NSArray*)value count] > 128",
        "[(NSString*)item length] > 128",
        "BHTKeywordArrayPreferenceKeys",
        "BHTIsValidKeywordArray",
        "bht_for_you_username_filter_keywords",
        "bht_for_you_post_text_filter_keywords",
    ):
        if required not in settings_source:
            raise AssertionError(
                f"Missing preference-profile invariant: {required}"
            )
    profile_export = source_section(
        settings_source,
        "+ (NSDictionary*)preferenceProfile",
        "+ (NSData*)preferenceProfileJSONDataWithError:",
        "preference-profile export",
    )
    require_source_tokens(
        profile_export,
        (
            '@"formatVersion": @2',
            '@"preferences": [preferences copy]',
            '@"userThemes": [BHTThemePresets userThemes]',
        ),
        "version 2 profile with a top-level custom-theme library",
    )
    profile_import = source_section(
        settings_source,
        "+ (BOOL)applyPreferenceProfile:",
        "\n@end",
        "preference-profile import",
    )
    require_source_tokens(
        profile_import,
        (
            "(version != 1 && version != 2)",
            "BHTProfileVersionIsExactly(formatVersion, 1)",
            "BHTProfileVersionIsExactly(formatVersion, 2)",
            "[BHTThemePresets userThemes]",
            "BOOL replacesUserThemes = version == 2",
            "if (replacesUserThemes)",
            "validatedUserThemesFromObject:",
            "userThemesByMergingImportedThemes:",
            "BHTUserThemeIdentifierExists(",
        ),
        "backward-compatible profile validation",
    )
    first_preference_write = profile_import.find(
        "[accepted enumerateKeysAndObjectsUsingBlock:"
    )
    theme_validation = profile_import.find(
        "validatedUserThemesFromObject:"
    )
    theme_merge = profile_import.find(
        "userThemesByMergingImportedThemes:"
    )
    theme_replace = profile_import.find(
        "[BHTThemePresets replaceUserThemes:"
    )
    if not (
        0 <= theme_validation < first_preference_write
        and 0 <= theme_merge < first_preference_write
        and theme_replace > first_preference_write
    ):
        raise AssertionError(
            "Imported themes must validate and merge before preference writes, "
            "then replace the library only after accepted preferences are ready"
        )
    replace_guard = profile_import.rfind(
        "if (replacesUserThemes", 0, theme_replace
    )
    if replace_guard < first_preference_write:
        raise AssertionError(
            "Version 1 profiles must preserve the existing custom-theme library"
        )

    for forbidden in ("password", "cookie", "auth_token", "session_token"):
        export_method = settings_source.split(
            "+ (NSSet<NSString*>*)exportablePreferenceKeys", 1
        )[1].split("+ (NSDictionary*)preferenceProfile", 1)[0]
        if f'@"{forbidden}"' in export_method:
            raise AssertionError(
                f"Sensitive key entered profile allow-list: {forbidden}"
            )
    for nested_theme_key in (
        '@"userThemes"',
        "BHTUserThemeLibraryPreferenceKey",
    ):
        if nested_theme_key in export_method:
            raise AssertionError(
                "Custom theme data must remain a validated top-level profile "
                f"field, not a generic preference: {nested_theme_key}"
            )

    for required_key in (
        "SETTINGS_SEARCH_PLACEHOLDER",
        "THEME_PRESET_APOLLO_TITLE",
        "THEME_PRESET_MIDNIGHT_OLED_TITLE",
        "THEME_PRESET_CINDER_DETAIL",
        "THEME_LIBRARY_CREATE",
        "THEME_LIBRARY_MY_THEMES",
        "THEME_BUILDER_NEW_TITLE",
        "THEME_BUILDER_LOW_CONTRAST_WARNING",
        "EXPORT_PREFERENCE_PROFILE_TITLE",
        "IMPORT_PREFERENCE_PROFILE_TITLE",
        "FOR_YOU_KEYWORD_FILTERS_TITLE",
        "FOR_YOU_FILTERS_USERNAMES_SECTION_TITLE",
        "FOR_YOU_FILTERS_POST_TEXT_SECTION_TITLE",
    ):
        if required_key not in localized_keys:
            raise AssertionError(
                f"Missing settings/theme localization: {required_key}"
            )
    if "coordinated app palette" not in english_source.lower():
        raise AssertionError(
            "Theme settings still describe presets as accent-only"
        )

    launch_source = (
        ROOT / "src" / "Hooks" / "AppLifecycle.x"
    ).read_text(encoding="utf-8")
    if "applyClassicLaunchBird" not in launch_source:
        raise AssertionError("Classic launch bird replacement is missing")

    likes_source = (
        ROOT / "src" / "Likes" / "BHTLikesTab.m"
    ).read_text(encoding="utf-8")
    likes_navigation_install = source_section(
        likes_source,
        "void BHTInstallNativeLikesNavigationController(",
        "static void BHTActivateLikesTabViewNow(",
        "native Likes navigation installation",
    )
    require_source_tokens(
        likes_navigation_install,
        (
            "nativeNavigation.viewControllers.firstObject != likes",
            "nativeNavigation.viewControllers.count > 1",
            '@"nativeChildNavigationPreservations"',
            ").topViewController ==",
        ),
        "retained Likes child-navigation stack",
    )
    if "nativeNavigation.viewControllers.count != 1" in (
        likes_navigation_install
    ):
        raise AssertionError(
            "Likes navigation must not discard native drawer destinations"
        )

    ads_source = (
        ROOT / "src" / "Hooks" / "Ads.x"
    ).read_text(encoding="utf-8")
    likes_hook_source = (
        ROOT / "src" / "Hooks" / "Likes.x"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        ads_source,
        (
            "NSArray* BHTFilteredTimelineSections(",
            "ShouldHideAndRecord(items[i], location)",
        ),
        "shared filtered timeline snapshot",
    )
    if (
        likes_hook_source.count(
            "BHTFilteredTimelineSections(self, sections)"
        )
        < 2
    ):
        raise AssertionError(
            "Likes waterfall capture must filter both section update paths"
        )

    for_you_filter_source = (
        ROOT / "src" / "Timeline" / "BHTForYouKeywordFilter.m"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        for_you_filter_source,
        (
            "bht_for_you_username_filter_keywords",
            "bht_for_you_post_text_filter_keywords",
            "BHTForYouKeywordMaximumCount = 64",
            "NSDiacriticInsensitiveSearch",
            "NSWidthInsensitiveSearch",
            "matchesAnyUsernameCandidate:",
            "matchesPostText:",
            "matchesAnyPostTextCandidate:",
            "filterGenerationWithUsernameFilters:",
            "BHTSettingsProfileDidApplyNotification",
        ),
        "cached For You keyword filter store",
    )
    post_text_matcher = source_section(
        for_you_filter_source,
        "+ (BOOL)matchesAnyPostTextCandidate:",
        "+ (NSUInteger)filterGeneration",
        "post-text and @mention matcher",
    )
    require_source_tokens(
        post_text_matcher,
        (
            "for (id candidate in candidates)",
            "BHTCanonicalKeyword(",
            "BHTForYouKeywordFilterKindPostText",
            "[normalized containsString:needle]",
        ),
        "literal post-text and @mention matching",
    )

    for_you_editor_source = (
        ROOT
        / "src"
        / "Settings"
        / "Pages"
        / "BHTForYouKeywordFiltersViewController.m"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        for_you_editor_source,
        (
            "for_you_filters.usernames",
            "for_you_filters.post_text",
            "BHTForYouFiltersSectionUsernames",
            "BHTForYouFiltersSectionPostText",
            "addKeyword:",
            "replaceKeywordAtIndex:",
            "removeKeywordAtIndex:",
            "revealSettingsSearchTargetIfNeeded",
            "applyingLocalKeywordMutation",
            "UIAccessibilityTraitHeader",
            "UIAccessibilityIsReduceMotionEnabled()",
        ),
        "For You keyword filter editor",
    )

    timeline_source = (
        ROOT / "src" / "Hooks" / "Timeline.x"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        timeline_source,
        (
            "%group BHTForYouTimelineProvenance",
            "homeTimelineForAccount:",
            "homeRankedFollowingTimelineForAccount:",
            "rootViewControllerForHomeTimeline:",
            "BHTMergeHomeTimelineRole",
            "BHTHomeTimelineRolePrimaryForYou",
            "BHTHomeTimelineRoleNonForYou",
            "BHTHomeTimelineRoleAmbiguous",
            "TFNTwitterHomeTimeline",
            "deserializeStream",
            "T1URTViewController",
            '@"TIMELINE_HOME"',
            '@"urtTimeline"',
            "StatusFromTimelineItem",
            "representedStatus",
            'NSSelectorFromString(@"tweet")',
            "_tfn_fullNoteTweetDisplayTextModel",
            "fromUserFullName",
            "kBHTForYouKeywordDecisionKey",
            "BHTRecordForYouFilterDiagnostic",
            "matchesAnyPostTextCandidate:",
            "filterGenerationWithUsernameFilters:",
            "ItemObjectValueAllowingUntypedIvar",
            "NearestURTTimelineController",
            "BHTIsPrimaryForYouURTController",
            "IsPrimaryForYouTimelineController",
            "BHTShouldHideForYouKeywordItemInURTController",
        ),
        "strict For You-only runtime filtering",
    )
    for forbidden in (
        "lastSelectedTimelineTabIdentifier",
        "kBHTForYouControllerKey",
        'NSSelectorFromString(@"dataViewController")',
        '"_dataViewController"',
        "BHTRegisterURTController",
        "BHTDirectURTOwnerForDataController",
        "BHTBindURTDataController",
    ):
        if forbidden in timeline_source:
            raise AssertionError(
                "For You filter must fail open instead of caching or "
                f"guessing selected-feed state: {forbidden}"
            )

    post_text_candidates = source_section(
        timeline_source,
        "static NSArray<NSString*>* PostTextCandidates",
        "static BOOL ComputeShouldHideForYouKeywordItem",
        "For You post-text candidate extraction",
    )
    require_source_tokens(
        post_text_candidates,
        (
            "_tfn_fullNoteTweetDisplayTextModel",
            '@"displayTextModel"',
            '{"fullText", "fullText"}',
            '{"text", "text"}',
            '{"displayText", "displayText"}',
            '{"originalText", "originalText"}',
            "AddPostTextCandidate(candidates, value)",
        ),
        "complete post-text candidate extraction",
    )
    if "VisiblePostText" in timeline_source:
        raise AssertionError(
            "For You filtering must inspect every trusted text "
            "representation instead of selecting one visible string"
        )

    username_mention_candidates = source_section(
        timeline_source,
        "static void AddUsernameCandidates",
        "static void AddPostTextCandidate",
        "bounded username-filter @mention extraction",
    )
    require_source_tokens(
        username_mention_candidates,
        (
            "BHTForYouMaximumMentionCandidates = 32",
            "BHTForYouMaximumMentionScanLength = 32768",
            "BHTTwitterHandleMaximumLength = 15",
            "IsTwitterHandleCharacter",
            "AddMentionUsernameCandidates",
            "previous == '@'",
            "handleLength > BHTTwitterHandleMaximumLength",
            "[candidates addObject:handle]",
            "BHTForYouFilterDiagnosticMentionHandleCandidateExtracted",
        ),
        "bounded username-filter @mention extraction",
    )

    keyword_decision_cache = source_section(
        timeline_source,
        "static BOOL ShouldHideForYouKeywordItem",
        "static BOOL ItemHasTopicBanner",
        "For You keyword decision cache",
    )
    require_source_tokens(
        keyword_decision_cache,
        (
            "BHTForYouKeywordDecisionCache",
            "objc_getAssociatedObject(outerStatus",
            "cached.generation == generation",
            "isEqualToArray:usernameCandidates",
            "isEqualToArray:postTextCandidates",
            "return cached.hidden",
            "updated.hidden = hidden",
            "hasUsernameFilters || hasPostTextFilters",
            "BHTForYouFilterDiagnosticTrustedTextCandidateSetNonEmpty",
            "UsernameCandidatesForStatuses(",
        ),
        "content-aware For You keyword and @mention decision caching",
    )
    if not re.search(
        r"UsernameCandidatesForStatuses\s*\(\s*"
        r"outerStatus\s*,\s*representedStatus\s*,\s*"
        r"postTextCandidates\s*\)",
        keyword_decision_cache,
    ):
        raise AssertionError(
            "Username filters must derive @handle candidates from the same "
            "trusted post-text representations used by post-text filters"
        )
    if "(hidden ?" in keyword_decision_cache:
        raise AssertionError(
            "For You filtering must not use the stale packed decision cache"
        )

    keyword_filter_call = source_section(
        timeline_source,
        "static BOOL ShouldHideTimelineItem",
        "static NSArray* FilteredTimelineSections",
        "For You keyword filter call site",
    )
    if not re.search(
        r"if\s*\(\s*filterForYouKeywords\s*&&\s*"
        r"ShouldHideForYouKeywordItem\s*\(",
        keyword_filter_call,
    ):
        raise AssertionError(
            "Keyword decisions must remain behind the strict For You gate"
        )

    for_you_controller_gate = source_section(
        timeline_source,
        "static BOOL IsPrimaryForYouTimelineController",
        "static id StatusFromTimelineItem",
        "For You controller ownership gate",
    )
    require_source_tokens(
        for_you_controller_gate,
        (
            "NearestURTTimelineController(",
            "BHTForYouFilterDiagnosticDirectOwnerMissing",
            "BHTForYouFilterDiagnosticControllerOwnerMissing",
            "return NO",
            "return BHTIsPrimaryForYouURTController(urtController)",
        ),
        "fail-open section-controller ownership resolution",
    )
    direct_urt_gate = source_section(
        timeline_source,
        "static BOOL BHTIsPrimaryForYouURTController",
        "static BOOL IsPrimaryForYouTimelineController",
        "exact T1URT For You role gate",
    )
    require_source_tokens(
        direct_urt_gate,
        (
            'NSClassFromString(@"T1URTViewController")',
            '@"TIMELINE_HOME"',
            'NSSelectorFromString(@"urtTimeline")',
            'BHTUntypedIvarPointer(urtController, "urtTimeline")',
            "BHTHomeTimelineRoleForTrustedPointer(rawTimeline)",
            "BHTHomeTimelineRoleForTimeline(urtTimeline)",
            "BHTHomeTimelineRolePrimaryForYou",
        ),
        "exact T1URT timeline-object role resolution",
    )
    render_fallback = source_section(
        timeline_source,
        "%hook T1URTViewController",
        "%hook TFNItemsDataViewController",
        "exact T1URT render fallback",
    )
    require_source_tokens(
        render_fallback,
        (
            "viewWillAppear:",
            "renderedGeneration.unsignedIntegerValue != generation",
            "BHTIsPrimaryForYouURTController(self)",
            "reloadData",
            "BHTForYouFilterDiagnosticRenderReloaded",
            "tableViewHeightForItem:",
            "estimatedTableViewHeightForItem:",
            "BHTForYouFilterDiagnosticRenderRowCollapsed",
            "return 0.0",
        ),
        "role-gated T1URT item-height fallback",
    )
    if "heightForRowAtIndexPath:" in render_fallback:
        raise AssertionError(
            "The keyword fallback must use X's item-height callbacks so "
            "Ads.x remains the sole outer row-height hook"
        )
    require_source_tokens(
        timeline_source,
        (
            "BHTHomeTimelineRegistryEntry",
            "@property(nonatomic, weak) id timeline",
            "BHTRegisterHomeTimelineRole(timeline, mergedRole)",
            "(__bridge const void*)timeline == candidate",
        ),
        "trusted raw-pointer timeline registry",
    )

    app_lifecycle_source = (
        ROOT / "src" / "Hooks" / "AppLifecycle.x"
    ).read_text(encoding="utf-8")
    padlock_success_gate = source_section(
        app_lifecycle_source,
        "BOOL currentSuccess =",
        "if (!lockEnabled)",
        "padlock authentication success gate",
    )
    require_source_tokens(
        padlock_success_gate,
        (
            "authenticated &&",
            "authenticationGeneration ==",
            "padlockAuthenticationGeneration",
            "lockEnabled",
        ),
        "current-session padlock success validation",
    )
    if "UIApplicationStateActive" in padlock_success_gate:
        raise AssertionError(
            "Face ID success must not be rejected while iOS briefly marks "
            "the app inactive"
        )

    padlock_resign_active = source_section(
        app_lifecycle_source,
        "- (void)applicationWillResignActive:",
        "- (void)applicationDidEnterBackground:",
        "padlock inactive transition",
    )
    if "setAuthenticated(NO)" in padlock_resign_active:
        raise AssertionError(
            "Temporary system authentication UI must not invalidate the "
            "padlock session"
        )
    padlock_background = source_section(
        app_lifecycle_source,
        "- (void)applicationDidEnterBackground:",
        "%end",
        "padlock background invalidation",
    )
    require_source_tokens(
        padlock_background,
        (
            "padlockAuthenticationGeneration++",
            "setAuthenticated(NO)",
            "showPadlockOverlay()",
        ),
        "real-background padlock invalidation",
    )

    media_editor_source = (
        ROOT
        / "src"
        / "MediaActions"
        / "BHTMediaActionEditorViewController.m"
    ).read_text(encoding="utf-8")
    require_source_tokens(
        media_editor_source,
        (
            "NSString* stableTarget = [target copy];",
            "indexPathForSettingsSearchTarget:stableTarget",
            "navigationController.topViewController !=",
        ),
        "stable media-action search reveal",
    )

    likes_theme_diagnostic = source_section(
        likes_source,
        "NSString* activeTheme =",
        'BHTSetLikesDiagnostic(@"themeSegmentedControl"',
        "Likes theme diagnostic",
    )
    require_source_tokens(
        likes_theme_diagnostic,
        (
            "[BHTThemePresets isUserPresetIdentifier:activeTheme]",
            ': (activeTheme ?: @"native")',
        ),
        "Likes custom-theme diagnostic privacy mask",
    )
    if not re.search(
        r"isUserPresetIdentifier:activeTheme\]\s*\?\s*"
        r'@"user_theme"',
        likes_theme_diagnostic,
    ):
        raise AssertionError(
            "Likes diagnostics must mask every custom theme as user_theme"
        )
    for private_lookup in (
        "displayNameForPreset:",
        "presetForIdentifier:",
        '@"themePreset", activeTheme',
    ):
        if private_lookup in likes_theme_diagnostic:
            raise AssertionError(
                "Likes diagnostics must not expose a custom theme name or "
                f"persistent identifier: {private_lookup}"
            )
    for required in (
        "BHTLikedMediaContextConfiguration",
        "UIContextMenuInteraction",
        "TFNMenuSheetViewController",
        "UIPercentDrivenInteractiveTransition",
        'BHTPhotoURLForVariant(rawURL, @"medium")',
        "totalCostLimit = 128 * 1024 * 1024",
        "BHTCachedMediaImageEntry",
        "pixelBucket",
        "BHTPendingMediaImageRequests",
        "imageRequestsCoalesced",
        "if (!token.cancelled) completion(image)",
        '"waterfallImageScaling": @"completeAspectFitWithDecodedRatioCorrection"',
        '"waterfallAspectRatioPolicy": @"metadataThenDecodedImageAdaptiveMasonry"',
        '"waterfallColumnSpanPolicy": @"wideMediaMaySpanAdjacentColumns"',
        "return MAX(0.10, MIN(10.0, ratio));",
        "waterfallDecodedRatioCorrections",
        "waterfallAnchorPreservations",
        "collectionView.indexPathsForVisibleItems",
        "waterfallLayoutInvalidationPendingUntilIdle",
        "applyPendingWaterfallLayoutInvalidationIfIdle",
        "aspectRatioConfirmedByImage",
        "updateAdaptiveAspectRatioForItem",
        "desiredSpan = MIN(2, columns);",
        "bestGap <= acceptedGap",
        "self.imageView.backgroundColor = surfaceColor;",
        "[cell applyCurrentThemeSurface];",
        "BHTThemeDidChangeNotification",
        "BHTSettingsProfileDidApplyNotification",
        "TFNDynamicColorsDidReloadNotification",
        "applyCurrentThemeSurfaces",
        "self.collectionView.visibleCells",
        "themeSharedBarsOwnedByGlobalHook",
        "BHTLikesModeSelector",
        "intrinsicContentSize",
        "MAX(size.height, 32.0)",
        "setBackgroundImage:nil",
        "setDividerImage:nil",
        "invalidateIntrinsicContentSize",
        "recordWaterfallSelectorRuntimeState",
        '@"waterfallSelectorGeometryState"',
        '@"waterfallSelectorIntrinsicHeight"',
        '@"waterfallSelectorCustomBackgroundArtwork"',
        "themeNativePostsOwnedByProviderHooks",
        "BHTRefreshNativeTabViewAppearance(nativeLikesTab)",
        "themeRefreshScheduled",
        '@"themeRefreshes"',
        "ensureWaterfallSelectorInstalled",
        "restoreWaterfallSelectorVisibilityIfVisible",
        "self.navigationItem.titleView != self.selector",
        "navigation.topViewController != self",
        '@"waterfallSelectorInstalls"',
        '@"waterfallSelectorOwned"',
        '"viewerPresentation": @"windowFullScreen"',
        "BHTFullScreenPresenterForController",
        "UIModalPresentationFullScreen",
        "toView.frame = container.bounds",
        "UIScrollViewContentInsetAdjustmentNever",
        "supportedInterfaceOrientations",
        "viewerFullScreenCoverage",
    ):
        if required not in likes_source:
            raise AssertionError(
                f"Missing Likes media improvement: {required}"
            )
    if "BHTLikesSolidColorImage" in likes_source:
        raise AssertionError(
            "Likes selector must not use 1x1 custom artwork that collapses "
            "its navigation-title height"
        )

    print(
        f"Source smoke test passed ({len(setting_keys)} settings, "
        f"{len(section_keys)} localized subsections)."
    )


if __name__ == "__main__":
    main()
