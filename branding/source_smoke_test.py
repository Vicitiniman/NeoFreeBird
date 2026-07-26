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


def png_size(path: Path) -> tuple[int, int]:
    raw = path.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n" or raw[12:16] != b"IHDR":
        raise AssertionError(f"{path} is not a PNG")
    return struct.unpack(">II", raw[16:24])


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
        "BHTUpdateAdaptiveRailBranding",
    ):
        if required not in theme_source:
            raise AssertionError(f"Missing compatibility fix: {required}")

    branding_source = (
        ROOT / "src" / "Branding" / "BHTBranding.m"
    ).read_text(encoding="utf-8")
    if '@"twitter_bird"' not in branding_source:
        raise AssertionError("Central Twitter bird asset lookup is missing")

    launch_source = (
        ROOT / "src" / "Hooks" / "AppLifecycle.x"
    ).read_text(encoding="utf-8")
    if "applyClassicLaunchBird" not in launch_source:
        raise AssertionError("Classic launch bird replacement is missing")

    likes_source = (
        ROOT / "src" / "Likes" / "BHTLikesTab.m"
    ).read_text(encoding="utf-8")
    for required in (
        "TFNMenuSheetViewController",
        "UIPercentDrivenInteractiveTransition",
        'BHTPhotoURLForVariant(rawURL, @"medium")',
        "totalCostLimit = 128 * 1024 * 1024",
    ):
        if required not in likes_source:
            raise AssertionError(
                f"Missing Likes media improvement: {required}"
            )

    print(
        f"Source smoke test passed ({len(setting_keys)} settings, "
        f"{len(section_keys)} localized subsections)."
    )


if __name__ == "__main__":
    main()
