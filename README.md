# NeoFreeBird for X 12.9

This fork combines BHTwitter's X 12.9 compatibility work with NeoFreeBird's
newer modular architecture. It is currently a beta intended for testing against
X 12.9.

## Highlights

- Layered ad blocking for Home, profiles, search, conversations, Explore,
  cards, articles, and video ad paths.
- Highest-quality photo loading, optional full-frame timeline media, and a
  highest-video preference.
- Modern video/GIF downloads across X 12.9's timeline, carousel, player-menu,
  overflow-menu, and supported Direct Message paths.
- Native photo/video/GIF menus with working Download and temporary-file Share
  actions, plus separate tap-to-hide and drag-to-reorder editors for each media
  type.
- Native tab reordering plus an independent, movable **My Likes** bottom
  destination that can sit alongside Grok, with normal in-tab navigation and
  swipe-back. Its native Bookmarks carrier is relabeled before the first tap.
- Appearance editors for the bottom bar, the Likes section, and X 12.9's
  sidebar, with tap-to-hide tiles and drag reordering. The iPad rail retains
  X's adaptive expanded layout instead of using the iPhone collapse clamp.
- A Posts/Media view for Likes with a pinch-adjustable waterfall gallery,
  newest-first loading, continuous pagination, original-quality photo viewing,
  highest-available MP4 playback, X-native long-press actions for photos,
  videos, and GIFs in both views, and interactive swipe-down dismissal.
- Sideloaded and TrollStore builds install with the **Twitter** display name and
  include the supplied classic bird as a selectable app icon. The blue Home
  title logo, iPad navigation rail, and classic launch animation can also use
  the bird instead of the X glyph.
- Updated profile, search, Grok, timeline, confirmation, appearance, branding,
  custom-font, and accessibility-related features.
- Settings are grouped into named subsections for navigation, ads, media,
  privacy, profiles, tweets, and links.
- A runtime compatibility report that can be shared from the Debug settings.

Beta 15 extends the bird branding to the iPad rail and classic launch animation,
adds native waterfall and close-up media sheets, replaces the pushed media
viewer with a fluid percent-driven modal dismissal, and bounds/downsamples its
image cache for faster scrolling and lower memory use. Beta 14 fixes iPad rail
sizing, removes the first-frame Bookmarks label from My
Likes, replaces the blue X Home title with the classic Twitter bird, organizes
the settings pages, isolates temporary media cleanup to NeoFreeBird-owned
files, and hardens settings, app-lock, photo-save, and compatibility-report
paths. Beta 13 connected the customizable Download and Share File actions to X
12.9's actual Home-timeline photo/video/GIF preview menu.

Every new X 12.9 behavior has a setting; custom navigation is controlled from
its editor. Compatibility shims preserve native behavior when their option is
off.

The full per-feature review is in
[`docs/X12_9_FEATURE_AUDIT.md`](docs/X12_9_FEATURE_AUDIT.md).

## Important login note

X may reject modified clients through server/app attestation. This project does
not bypass attestation and does not include replacement login flows, cookie or
session-token harvesting, or subscription-state spoofing. Those approaches are
fragile, unsafe for accounts, and outside this fork's compatibility work.

## Build locally

Install [Theos](https://github.com/theos/theos) and
[cyan](https://github.com/asdfzxcvbn/pyzule-rw) for IPA/TrollStore output, then:

```bash
git clone --recursive https://github.com/Vicitiniman/NeoFreeBird.git
cd NeoFreeBird
chmod +x build.sh
```

Place a decrypted IPA at `packages/com.atebits.Tweetie2.ipa` for IPA builds and
run one of:

```bash
./build.sh --sideloaded
./build.sh --trollstore
./build.sh --rootless
./build.sh --rootfull
```

The FFmpeg stack is built from source on first use and reused afterward. macOS
uses `sips` to generate alternate-icon sizes; Linux IPA builds need
ImageMagick's `magick` or `convert` command.
Sideloaded/TrollStore output is branded during packaging; reinstall or update
the app before judging the new display name or alternate icon list.

## Build with GitHub Actions

Run **Build NeoFreeBird** from the Actions tab. Select a deployment format and,
for sideloaded/TrollStore builds, provide a direct URL to a decrypted IPA you
are authorized to use. The workflow checks out the selected branch/commit and
its submodules, so fork changes are included in the build.

## Test logs

After installing a test build:

1. Open `Settings > NeoFreeBird > Debug`.
2. Tap **Export compatibility report**.
3. Attach the resulting JSON to the GitHub issue or pull request.

The same report is stored inside the app container at
`Library/Caches/BHTwitter-X12.9-Compatibility.json`. It contains app/build and
hook-availability information, not account credentials.

## Credits

Built on the work of BHTwitter and NeoFreeBird contributors, with selected
targeted improvements reviewed from Theacrat's and Orion's NeoFreeBird branches.
