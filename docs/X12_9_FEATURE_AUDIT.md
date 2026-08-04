# X 12.9 feature audit

Target inspected during the compatibility pass: X 12.9 (build 10), bundle
`com.atebits.Tweetie2`, minimum iOS 15.0. The supplied IPA contained 62 Mach-O
images and no encrypted executable images.

This branch uses NeoFreeBird v6's modular source layout while keeping the X
12.9-specific hook decisions from the earlier BHTwitter audit. All user-visible
new behavior has a setting. Compatibility shims and runtime reporting are the
only unconditional code paths.

## Safety boundary

- No attestation bypass is implemented.
- Native X sign-in remains the default. A user-invoked X 12.9-only
  Compatibility Sign-in fallback calls X's own password command, native
  challenge UI, account registration, and credential storage. Every required
  class and method is checked before use.
- No cookie harvesting, session-token extraction, web GraphQL credential
  reuse, plaintext credential backup, or diagnostic secret logging is
  compiled.
- Subscription state is not spoofed. Native/server-backed eligibility remains
  authoritative.
- Tweet source labels use X 12.9's on-device `TFNTwitterStatus-composerSource`
  path.

## Ad blocking

The blocker is deliberately layered because X now inserts promoted material at
several points:

1. `TFNTwitterAPICommandContext-allowPromotedContent` prevents promoted results
   from being requested where the API honors the flag.
2. X 12.9 feature switches disable SSP, dynamic-video, unified-card, article
   webview, and promoted-profile paths.
3. `TFNItemsDataViewAdapterRegistry-dataViewAdapterForItem:` rejects promoted
   statuses plus the exact Google-native, `PromotableTrend`, immersive-card,
   and Explore-promoted models before adapter creation.
4. `T1PlayerMediaEntitySessionProducible` keeps the real playable media entity
   but removes only its separate `promotedContent` session payload.
5. `TFSTwitterSspMetadata` disables preroll eligibility and ad-tag URLs.
6. `TFNItemsDataViewController` section filtering removes promoted statuses,
   promoted Explore trends/heroes, and their orphaned module chrome without
   leaving blank cells.
7. `TFNTwitterStatus` ad flags, SSP metadata, dynamic-ad permission, and
   `isCardHidden` form the final card/video fallback.

The obsolete `TFSTwitterAPICommandAccountStateProvider-allowPromotedContent`
hook is intentionally absent.

## Feature matrix

Status meanings:

- **Updated**: retargeted or behavior corrected for the newer app.
- **Ported**: adopted from the newer NeoFreeBird/Theacrat architecture.
- **Combined**: uses both the X 12.9-specific and newer modular approaches.
- **Runtime check**: compiled defensively and included in the exported report;
  it needs an on-device pass because the private Swift surface can move.

| Area | Setting | Status | X 12.9 implementation |
|---|---|---|---|
| General | `hide_promoted` | Combined | Layered request, model, section, player, metadata, status, and feature-switch blocker described above |
| General | `hide_premium_offer` | Updated | Upsells only; genuine subscription state is preserved |
| General | `padlock` | Ported | In-memory relock and app-switcher cover |
| General | `no_tab_bar_hiding` | Updated | X 12.9 pin/collapse capabilities plus ratio clamp on iPhone; iPad keeps its native adaptive rail width and fullscreen hides remain intact |
| General | `disable_rtl` | Ported | Rebuilds paragraph styles with LTR direction |
| General | `strip_share_tracking` | Updated | Removes `s`/`t` parameters only when enabled |
| General | `expand_tco_links` | Updated | No longer unconditional |
| General | `show_scroll_indicator` | Ported | Typed account feature-switch accessor |
| Appearance | theme and app icon controls | Updated | Modern settings pages and guarded live theme reapply; nine built-in choices include Native Blue plus Apollo-inspired, classic Twitter, Midnight OLED, Evergreen, Rose Quartz, Solarized Coast, Amethyst, and Cinder. A native visual builder creates, previews, saves, applies, edits, duplicates, and deletes strictly validated personal light/dark themes with mode-specific accents, readability warnings, and profile portability. Themes attach to the validated active, Twitter, and TFNUI palette providers. A narrow public named-color bridge covers only matching neutral assets from `XColorEngine_XColorEngine.bundle`, which keeps both Objective-C XDS and Swift Following/detail surfaces themed while preserving destructive, media-overlay, and other context-sensitive native colors. NeoFreeBird uses X's guarded native palette apply and observes—never synthesizes—its private dynamic-colors-did-reload event. A coalesced, bounded loaded-view-tree refresh runs only when that native event is absent or a replacement provider is attached after its synchronous observers, so changes apply without a force quit and never add scrolling-path work. Immutable per-provider generation/dark snapshots prevent mixed or stale colors while keeping hot palette reads cheap, and weak tracking clears every still-live provider when Native Blue is restored. Sideloaded/TrollStore packages preserve X's stock icon choices and add the supplied loose Twitter-bird alternate |
| Settings | search and preference profiles | New | Localized global search covers every page, title, detail, subsection, and category; result routing waits for X's search dismissal and destination layout, then visibly spotlights the exact row or opens the requested theme, navigation item, Likes waterfall selector, sidebar item, media action, or For You filter list without changing a toggle. Versioned JSON export/import lives in a separate Backup & restore page, uses a strict NeoFreeBird-only preference allow-list, and never includes Twitter account state |
| Appearance | custom navigation | Combined | Captures/reorders native tab entries; Grok remains native while opt-in Likes is an independent movable entry; selected editor tiles and the preview row both support drag reordering |
| Appearance | sidebar navigation | New/runtime check | Reorders or hides Profile, Blue, History, Communities, News, Lists, Chat, Notifications, Spaces, and Follower Requests through X 12.9's observable `TwitterDash` array setters while preserving unknown/native rows. A coalesced post-factory reapply also covers the late drawer rebuild triggered by Add Account |
| Appearance | `tab_bar_theming` | Ported | Native selected/unselected colors |
| Appearance | `restore_tab_labels` | Updated | Current `T1TabView` title path; the Likes carrier is relabeled before its first selection |
| Appearance | `restore_launch_animation` | Updated | No longer forced on; replaces the animated X with the bundled Twitter bird and removes only the X-shaped reveal mask |
| Appearance | `restore_refresh_sounds` | Updated | No longer always on |
| Appearance | `custom_fonts` | Updated | Persists concrete PostScript faces, migrates former family-name selections, and covers both legacy `TFNUIDefaultFontGroup` and X 12.9's SwiftUI `XFontCatalog` |
| Timeline | `hide_who_to_follow` | Combined | Section model filter plus targeted iPad controller |
| Timeline | `hide_timeline_prompts` | Combined | Prompt/module filter plus targeted update pill |
| Timeline | `hide_discover_more` | Updated | Exact related-post entry IDs; no broad footer/header deletion |
| Timeline | `hide_topics` | Updated | Exact topic banners and topic-marked prompts |
| Timeline | `hide_topics_to_follow` | Updated | Exact profile topic collections/suggestion identifiers |
| Timeline | `hide_spaces` | Updated | Fleet-line visibility seam; runtime checked |
| Timeline | `hide_custom_timelines` | Updated | Hides without persisting an empty pinned list |
| Timeline | `remember_timeline_tab` | Updated | Disabled preference now leaves X's native value alone |
| Timeline | For You keyword filters | New/runtime check | Two independent, bounded lists match authors/reposters, real `@handle` tokens, or primary visible post text. Cached normalized terms and content-aware per-item decisions keep repeated layout checks light. The gate carries an explicit primary-Home model marker through `TFNTwitterHomeTimeline-deserializeStream`; section filtering accepts only a verified T1URT owner, while exact `T1URTViewController` row-height callbacks provide the X 12.9 render fallback. Following and every unknown runtime state fail open |
| Timeline | `enable_likes_tab` | New/runtime check | Independent bottom destination backed by native Likes history; opens raw Activity History tab 4 on X 12.9, guards against delayed native offset restoration on its first presentation without a loading cover, preserves position on later tab switches, and retains Profile, History, Lists, and other native destinations pushed from X's side drawer |
| Timeline | `likes_media_waterfall` | New/runtime check | Newest-first extraction from the same ad-filtered native section snapshot, continuous pagination, medium-size grid previews plus original-quality close-up/download URLs, highest-bitrate MP4 selection, 2–5 columns, a window-level edge-to-edge viewer on iPhone and iPad, a Posts/Media selector with native segmented-control artwork and a guarded 32-point minimum navigation-title height, Apple-style contextual Photo/Video/GIF previews and action menus in both surfaces (with the guarded TFN sheet retained only as a legacy fallback), and percent-driven modal swipe-down dismissal |
| Grok | `enable_grok_translations` | Updated | Manual translation gates are no longer forced globally |
| Grok | `hide_grok_analyze` | Updated | Backend switch plus current button paths |
| Grok | `hide_grok_sidebar` | Ported | Current navigation model filtering |
| Grok | `hide_grok_create` | Updated | Composer, photo, timeline and immersive gates |
| Grok | `disable_auto_translate` | Ported | Leaves manual translation available |
| Media | `download_videos` | Updated | Modern MP4/HLS/GIF quality sheet across X 12.9's `MultiMediaView`, separate carousel, legacy inline-video, overflow, and exact native media-action path; replaces X's Blue-gated duplicate with working Download Video/GIF and temporary-file Share actions |
| Media | media action editors | New/runtime check | Independent Photo, Video, and GIF tap-to-hide/drag-to-reorder editors; recognized native actions are reordered safely, explicitly tagged Neo actions win duplicate IDs, and unknown/future X actions plus Cancel are preserved |
| Media | `dm_media_downloads` | Updated/runtime check | Default-off opt-in; Swift attachment view and save-plugin availability are reported |
| Media | `voice_creation_enabled` | Updated/runtime check | X 12.9 keyed voice-post and voice-reply gates |
| Media | `no_voice_messages` | Corrected/runtime check | Turns legacy DM and XChat voice creation/rendering off when enabled |
| Media | `old_compose_bar` | Corrected/runtime check | Disables the XChat v2 composer when enabled |
| Media | `dm_reply_later_enabled` | Updated/runtime check | Native keyed gate; server/account support remains authoritative |
| Media | `media_upload_4k_enabled` | Updated/runtime check | Legacy and X Lite 4K keyed gates; upload server limits remain authoritative |
| Media | `custom_voice_upload` | Updated | Previously always on; now opt-in |
| Media | `direct_save` | Ported | Share sheet or direct Photos save |
| Media | `disable_video_captions` | Ported | Current switch family |
| Media | `auto_highest_load` | Updated | X 12.9 `isLoadingHighestQualityImageVariantPermitted` plus timeline image and slideshow paths; default on |
| Media | `force_highest_video_quality` | New/runtime check | Sorts variants and prefers the highest MP4 primary URL |
| Media | `force_tweet_full_frame` | Updated | Photo attachment adapter display type |
| Media | `restore_video_timestamp` | Ported | Current immersive progress plugin |
| Media | `disable_immersive_scroll` | Ported | Feature threshold and gesture fallback |
| Profile | `follow_confirm` | Ported | Current `TUIFollowControl` action |
| Profile | `copy_profile_info` | Ported | Native-style profile action provider |
| Profile | `disable_articles` | Corrected | Off now preserves X's native gate |
| Profile | `disable_highlights` | Corrected | Off now preserves X's native gate |
| Profile | `hide_blue_verified` | Updated | User, source, typeahead, DM and cached status-model paths |
| Profile | `hide_follow_button` | Updated | Current author view |
| Profile | `restore_follow_button` | Updated | Keeps genuine active subscriptions intact |
| Profile | `square_avatars` | Ported | Live avatar/image/shadow restyling |
| Profile | `full_profile_counts` | Updated | Previously always on; now opt-in |
| Account access | Compatibility Sign-in | New/runtime check | Explicit X 12.9-only fallback available from signed-out onboarding, Profiles settings, and Add Account; uses X's password command, native challenge/account services, and native credential storage while leaving normal sign-in untouched |
| Account/replies | `web_reply_fallback` | New/runtime check | Default-off X 12.9 route for supported reply taps. Inline replies first try X's guarded visible web controller with the exact hook account object and requested authentication, then fall back to the native-themed Web Intent shell. Persistent-compose replies retain the shared-session shell because that path has no authoritative hook account. Neither route captures native draft text or auto-posts, and both fall through to native behavior when they cannot be presented |
| Profile/Grok | bio translation | Combined | Old `bio_translate` preference migrates to native Grok translations; only X 12.9's available canonical-user selector is hooked |
| Tweets | `enable_edit_tweet` | Updated | Exposes native UI only; server eligibility still applies |
| Tweets | undo timeout | Ported | Unified timeout picker and old-key migration |
| Tweets | `tweet_confirm` / `like_confirm` | Updated | Current composer plus X 12.9 `TTAStatusInlineActionButton-didTap`, slideshow, and immersive actions |
| Tweets | `tweet_to_image` | Ported | Long-press share with table/collection fallback |
| Tweets | inline-button hides | Updated | `TTAStatusInlineAnalyticsButton` and current class list |
| Tweets | sensitive/age controls | Ported | Explicit toggles; age bypass defaults off |
| Tweets | `reply_sorting` | Corrected | Covers `reply_sorting_enabled` and X 12.9's minimal-detail v2 switch; off preserves native behavior |
| Tweets | `restore_reply_context` | Corrected | Off leaves X's native switch untouched |
| Tweets | `restore_tweet_labels` | Updated | Native `composerSource`; no account/session web request |
| Search | `no_history` | Updated | Read and write paths on recent-search datastore |
| Search | `hide_trends` | Combined | Phone Explore controller and targeted iPad sidebar |
| Search | `hide_trend_videos` | Ported | Explore carousel model filter |
| Web | sharing domain | Ported | Applied independently of tracking removal |
| Web | `always_open_safari` | Updated | Keeps login/2FA flows in-app |
| Web | `new_inapp_webview` | Ported | Current feature-switch path |
| Branding | terminology, pill label, bird logos | Updated | Modern bundle/text/tab paths; the Home title, adaptive iPad rail, and optional classic launch animation use one bundled tintable bird, while sideloaded/TrollStore packaging sets localized display names to Twitter and registers the supplied bird as a loose alternate icon without replacing stock icons |
| Privacy | screenshot toggles | Ported/updated | Detection and branding cleanup are opt-in and grouped with app lock |
| Debug | FLEX | Ported | Explicit toggle |
| Debug | compatibility report | New | Exports a non-sensitive JSON runtime probe report |

## Selected newer-source ports

Worthwhile pieces taken from the newer Theacrat/NeoFreeBird work include the
central settings registry and migration, structural timeline filtering, modern
Swift DM media discovery, native tab-entry ordering, configurable undo timing,
Grok surface cleanup, reply context restoration, video timestamps, square
avatars, full count formatting, and the modular build/FFmpeg layout.

From the Orion-derived changes, this branch keeps only targeted versions of the
refresh-pill, iPad trends/recommendations, and screenshot-overlay cleanup. It
does not use the broad global `UIView-didMoveToWindow` hook, and it does not
change the FFmpeg TLS backend without a demonstrated build need.

## Intentionally retired or deferred

- The old custom DM background hooked
  `T1DirectMessageConversationEntriesViewController`, a controller removed by
  X's Swift DM rewrite. A global view/background hook would be fragile and could
  obscure message content, so it is not ported.
- The dormant `always_following_page` preference was never exposed in the last
  BHTwitter settings screen. The X 12.9 audit found the current
  `selectTimelineVariant:shouldRefresh:` path but not a stable enum value; the
  branch does not guess one.
- Hidden web posting, cookie extraction, credential/token backups,
  subscription spoofing, and attestation evasion remain excluded. The guarded
  Compatibility Sign-in fallback is not a web-session replacement and stores
  the resulting account only through X's native account service.
- The optional Compatibility reply composer is always visible and never posts
  automatically. On the verified inline-reply path, beta 44 first attempts X
  12.9's guarded `T1WebViewController`, passes the exact account argument X
  supplied for that tap, requests authentication, and verifies that the
  controller retained the same object. This verifies wiring, not the
  server-side web account, which requires two-account device testing. If the class, initializer ABI,
  keep-in-webview selector, account getter, or UIKit presentation check fails,
  it falls back to the existing visible x.com Web Intent. Only the custom
  fallback shares one persistent WebKit session across native app accounts and
  therefore retains the explicit account-review boundary and optional local,
  unverified account label. Neither route inspects or exports cookies,
  credentials, page account data, or reply text, and neither separately
  persists, logs, or exports raw URLs or identifiers. The tapped status
  identifier necessarily remains in X's official visible reply URL while that
  screen is open.

## Device validation

After launching a test build, open:

`Settings > NeoFreeBird > Debug > Export compatibility report`

The JSON is also written to:

`Library/Caches/BHTwitter-X12.9-Compatibility.json`

The first device pass should focus on Photo/Video/GIF action ordering, Download
and temporary-file Share, first-open Likes position, waterfall and close-up
contextual previews, interactive swipe-down cancellation/completion, theme
presets in both light and dark appearance, switching back to Native Blue,
profile round-tripping, global settings search, the single iPad
rail bird and pre-injection launch bird, sidebar hiding/reordering, the native
Likes post route, DM save-action plugin, Home/Spaces Swift aliases,
source-label model access, highest-video preference, and the Likes viewer's
`viewerFullScreenCoverage` result after opening media. The report's
privacy-safe `likesRuntime` section
records root creation, selection/reset counts, media count, and URL acceptance.
Missing private selectors degrade to native behavior and are listed in the
report rather than being guessed silently.

Beta 29 adds the opt-in X 12.9 Compatibility Sign-in fallback. It preserves
normal X sign-in, validates the full private method shape before invocation,
uses nonpersistent UI-metrics loading, clears the password field immediately,
routes two-factor challenges through X's native challenge controller, and
registers successful accounts only through X's account service. Its
compatibility diagnostics contain aggregate stages and categories only—never
credentials, tokens, URLs, response bodies, or account identifiers.

Beta 30 extends Compatibility Sign-in to X's Add Account flow. Beta 31 adds
privacy-bounded reply workflow diagnostics. Beta 32 introduces the default-off
Compatibility reply composer as a visible x.com Web Intent with a separate
persistent WebKit session and an account-mismatch warning. Betas 33 and 34
harden loading, navigation policy, popup handling, and blank setup recovery.
Beta 35 recognizes a successful `/home` setup landing, replaces the
browser-like chrome with a native-themed reply shell, and keeps posting
entirely inside the visible X web surface without reading cookies, reply text,
or account data.

Beta 36 completes setup as soon as signed-in `/home` commits or arrives through
a settled same-document transition, keeps a visible Done escape hatch for
alternate successful routes, adds a shared-web-session account review when a
native account-context change is detected, and reapplies saved sidebar
visibility after Add Account finishes rebuilding the drawer.

Beta 37 routes account review through the sign-in path that succeeds on X 12.9,
falls back once to X's official intent shell when a pre-commit WebKit policy
interruption occurs, and always replaces an unrecoverable opening spinner with
a retry state. It also adds an optional local **Last confirmed** web-account
label without reading cookies or exporting the label in profiles or reports.

Beta 38 opens every web-account setup path through the same official intent
route already proven by compatibility replies, keeps that page visible for
account review, and provides an explicit native **Use This Web Account**
confirmation instead of relying on X's committed login shell. Confirmation is
blocked while a navigation is pending, an error is visible, or X is still on a
login URL. A `/home` landing or return to the intent after a visible login
transition can confirm automatically. Its original For You owner bridge was
later replaced in beta 48 after device diagnostics proved X 12.9 has no such
declared inner-controller relationship.

Beta 39 hardens Compatibility Add Account for account-specific authentication
responses. It checks a returned native verification challenge before treating
an unsuccessful command completion as a rejection, normalizes a simple leading
`@` from handles, and exports only bounded class/domain/code fingerprints and
aggregate completion counters. Credentials, identifiers, response contents,
error descriptions, and error user-info dictionaries remain excluded.

Beta 42 restores Compatibility Sign-in as a dedicated, opt-in screen instead
of sending the user through X 12.9's JetX/Jetfuel onboarding route. It retains
the exact guarded password-command ABI, native verification challenge,
account-registration, and account-switching checks from betas 39 and 40. The
normal X sign-in remains visible and untouched. Password text is cleared before
the request starts and is never persisted or included in diagnostics. Beta 42
also retains the signed-out Share Report action added in beta 41 so a failed
attempt can be investigated without first reaching the app's settings.

Beta 43 removes beta 42's experimental password-request client-version
override after the device report showed that X returned the same payload-less
401 even though the scoped override installed and applied correctly. The
compatibility password request again uses X 12.9's native metadata. It also
holds the diagnostic preflight for at least 12 seconds before starting the
password command, reproducing the timing and `uiMetrics:nil` request profile
recorded by the successful beta 29 and beta 36 reports. Reports identify this
fixed request profile and elapsed preflight without recording headers,
credentials, account identifiers, or response contents.

Beta 44 adds an ordered monotonic trace for native reply validation, composition
handoff, outbox notifications, and composer closure. It also tags only exact
`CreateTweet` and `CreateTweetWithUndo` tasks created during a short active
reply window and observes their completion at a runtime-guarded TNL seam. X
12.9's verified URL-session delegate callback is used when the private
finalizer candidate is absent. Reports contain fixed constructor, host,
HTTP-class, error-class,
and duration buckets only. While the short correlation window is active, the
observer transiently classifies the HTTP method, URL scheme, exact first-party
host, and operation name. Requests are forwarded unchanged; bodies, headers,
cookies, tokens, raw URLs, identifiers, response contents, account data, and
raw errors are never retained or exported. The same beta introduces the
guarded account-aware visible web controller described above, with the custom
Web Intent retained as the pre-presentation fallback.

Beta 45 follows the beta 44 device result that recorded an exact CreateTweet
request with HTTP 2xx and no transport error even though X later emitted its
composition-send failure notification and the reply was absent when checked.
It adds one X 12.9-only checkpoint at
`GraphQLEndpointResponse -modelWithParseError:APIErrors:`. The exact method ABI,
inherited `originalRequest` getter, and request `URL` getter are all verified
before the hook installs. A lock-free window hint keeps ordinary GraphQL
traffic off the reply-state lock. Only the numeric active-reply generation is
captured before X's decoder, which is then called exactly once and remains
unchanged. Afterward, only a 30-second active reply window and an exact HTTPS
API-host `CreateTweet` or `CreateTweetWithUndo` URL may produce a record.
The report reduces the result to fixed booleans and enums for model presence,
parse-error presence, and whether the API-error collection is absent, empty,
nonempty, or an unexpected present object. It never reads collection elements,
error messages or descriptions, response bodies, raw URLs, headers, cookies,
tokens, tweet text, identifiers, or account data, and it never persists or
exports decoded objects. The operation-scoped temporal association cannot
prove application success or distinguish a concurrent CreateTweet from
another app action, so the report states that limitation explicitly.

Beta 46 follows the beta 45 device result in which the decoded CreateTweet
model was present and both decoder out-parameter error categories were absent,
but X still emitted its composition-send failure notification. It adds a
second X 12.9-only checkpoint after
`GraphQLEndpointResponse -prepare` has returned. The exact no-argument `void`
ABI, inherited effective response getters, final override getters, original
request getter, and request URL getter are all verified before this separate
hook installs; failure to verify it does not disable beta 45's decoder hook.
Only the same active reply generation and exact HTTPS API-host CreateTweet
allowlist may produce a record. Effective model/error values and the override
values visible when preparation returns are reduced immediately to fixed
presence states, including the private response's explicit-absence sentinel.
A getter exception is reported only as a fixed observation failure and is
never conflated with an absent value. API-error arrays are classified only as
absent, empty, nonempty, or unexpected without reading any element.
No error domain, code, message, description, user info, response body, raw URL,
identifier, tweet text, token, cookie, header, or account value is retained or
exported. Later finalizers may still replace these sampled override values,
and these prepared-response states do not prove posting success. They
distinguish an error already visible after preparation from the next suspected
typed-model assimilation/outbox layer.

The same beta also gave the existing decoder checkpoint a guarded structural
presence category for X 12.9's exact `CreateTweetOperationResponse` and nested
`CreateTweet` classes. Both classes must expose exactly their single expected
pointer-sized ivar at offset 16 within a 24-byte instance before the direct
model check is enabled. The beta 46 device result was initially reported as an
unexpected model class, but later binary verification showed that this
Objective-C seam normally returns the outer Swift
`GraphQLActionResponse<CreateTweetOperationResponse>` value in an opaque
`__SwiftValue` box rather than returning the generated operation model
directly. Beta 47 therefore recognizes only that exact wrapper class as
`opaqueSwiftValueBox` before considering the defensive direct-model layout.
It never unboxes, reflects on, or reads the wrapper. The direct fallback still
records only whether `createTweet` and then `tweetResults` are present. The
objects are transient and never persisted, and the 17-byte Swift
`TweetResultsFragment.result` union remains deliberately unread. Neither an
opaque box nor a present direct payload proves that the server created a
tweet.

Beta 47 also follows a controlled Undo Tweet comparison. With Undo set to ten
seconds, the reply reached the outbox after the expected delay; with Undo off,
it reached the outbox immediately. Both attempts still used the ordinary
`CreateTweet` operation, received HTTP 2xx with an effective prepared model and
no surfaced prepared parse, operation, or API error, and then ended in the
same composition-send failure. Undo scheduling is therefore not the root
cause, and this beta does not change it.

To identify the next layer without changing reply behavior, beta 47 observes
only X 12.9's two allowlisted terminal reply-failure notifications while an
active, forwarded native-reply generation still exists. It captures only that
process-local generation before the ordinary workflow recorder closes the
session, records the existing terminal stage first, and then reads only the
value associated with
X's exact exported
`TFNTwitterCompositionOutboxNotificationErrorUserInfoKey`. An all-or-nothing,
same-image set of X's exported `HTTPRequestActionResponseError` classifier
bridges is called only when that value has the exact opaque `__SwiftValue`
wrapper expected by the exported Swift ABI, and reduces it to fixed API, REST,
parse, authentication, operation, invalid-response-model, internal,
response-without-data-or-error, multiple, or unclassified categories. The
wrapper itself is never opened; an `NSError` or any other object type is
reported only as a fixed type state and is never passed to those bridges. The
notification dictionary is never enumerated, and account, composition,
status, and index keys are never read. The diagnostic does not retain or
export the notification, dictionary, error object, API-error elements,
descriptions, domains, codes, error user info, reply text, identifiers,
accounts, request or response contents, headers, cookies, or tokens. Its
process-temporal correlation is not request-identity-bound, and its category
cannot by itself establish whether a reply was persisted.

Beta 49 adds a temporary, explicitly confirmed one-shot diagnostic for the
remaining native-reply investigation. It does not weaken or replace the three
privacy-bounded sections above. When armed from Debug settings, only the next
active X 12.9 native reply may be accepted, and the switch consumes itself as
soon as the exact HTTPS API-host `CreateTweet` decoder checkpoint runs. X's
decoder is still called first and its model and error outputs are forwarded
unchanged. The diagnostic then obtains the same bounded response bytes X has
already retained through the verified inherited `response.info.data`
accessors, parses them as JSON, and keeps a recursively bounded copy. Raw
non-JSON data is omitted. The same capture may add the post-prepare error
values, the exact Objective-C status/error pair received by
`TFNTwitterCompositionUpdateStatusOperation`, and the terminal failure
notification payload for the matching process-local reply generation. It
does not invoke the generic Swift assimilation ABI or unbox `__SwiftValue`.

This mode can contain reply text returned by X, account handles and IDs,
post/conversation/media IDs, GraphQL data, and private error descriptions. Its
warning says so before arming. Response data is capped at 256 KiB; recursive
depth, collection counts, and strings are separately bounded. Keys and text
matching authorization, cookie, password, secret, OAuth/bearer/guest/access/
refresh token, CSRF/ct0, known-device-token, and attestation values are
redacted. The code never reads request or response headers, cookies, WebKit
storage, an HTTP body or body stream, or credential stores. The arm expires
after ten minutes, an active generation expires after ninety seconds, and
only one attempt is retained in memory. Automatic, pre-login, and ordinary
compatibility reports continue to omit this data. Debug export explicitly
offers a sensitive detailed report or the normal report; the detailed report
uses a temporary file and clears the in-memory capture after a successful
share. This beta-only module must be removed before a public release.

Beta 40 stopped feeding captured WebKit instrumentation into the native
password command and restored `uiMetrics:nil`, matching the successful beta 29
and beta 36 reports. The following beta 40 device report still returned the
same payload-less 401, so the captured metrics value was ruled out as the
continuing cause. Privacy-safe command diagnostics and native verification
handling remain in place so account-specific rejection can still be
distinguished from a returned verification challenge.

Beta 14 also restricts launch cleanup to NeoFreeBird's own temporary directory,
uses asynchronous Photos saves, scopes the font-picker customization, avoids
stacked app-lock presentations, caches and cancels settings-avatar requests,
and debounces automatic compatibility reports off the main thread.

Beta 15 introduced a 128 MB cost-aware decoded-image cache, ImageIO
downsampling, and deferred pager refreshes during horizontal transitions. Beta
16 added Apple-style contextual previews and menus for consistent iPhone/iPad
media actions plus coalesced image requests. Beta 17 targets the guarded iPad
rail-header image path, adds complete light/dark theme palettes, and presents
waterfall close-ups at full app-window size. Beta 18 expands coverage to X
12.9's dark timeline, tweet, card, modal, and capsule-tab palette tokens,
reapplies presets through its guarded dynamic-color refresh paths, and changes
waterfall thumbnails to complete-image aspect fit. Beta 19 also attaches those
roles to X's separate Twitter/TFNUI providers, themes repost and top/bottom tab
chrome, and makes the Likes waterfall adapt its tile height and span from the
decoded media dimensions. Beta 20 adds the narrowly scoped XDS named-color path
used by both Objective-C and Swift Following, Tweet Details, and reused
timeline cells, and restores the Likes Posts/Media selector after native
navigation rebuilds. Beta 21 removes the one-pixel segmented-control artwork
that could collapse that selector on iPhone, preserves native sizing with a
minimum intrinsic height, and exports its live geometry for diagnosis. Beta 22
stops painting X's independently mounted tab-bar host and divider, and retains
the native tab-bar appearance's background material while theming only its
items. This keeps the selected palette without leaving an opaque strip when X
collapses the lower navigation controls during scrolling. Beta 24 prevents
theme-provider installation from recursively querying X's hooked
`currentColorPalette`, which removes the beta 23 launch-time stack overflow
while retaining appearance-specific accents. Beta 23 expands the
built-in library with six contrast-checked palettes and adds a native custom
theme builder. Personal themes are stored as strictly validated opaque
light/dark role maps, can be managed without editing JSON, use mode-specific
accents, and round-trip through backward-compatible preference-profile v2
exports without exposing their names or UUIDs in compatibility diagnostics.
Full themes hook only
validated zero-argument color getters on X's concrete provider instances plus
the exact neutral XColorEngine named assets, cache provider colors away from
scrolling paths, and fall through to preserved native implementations when
Native Blue or a standalone accent is selected. The
close-up viewer is forced to the app window instead of an
adaptive iPad column while keeping its safe-area controls, rotation, paging,
zoom, video playback, and percent-driven dismissal. Equal URL/size-bucket
requests are coalesced across prefetching, visible cells, contextual previews,
and the close-up viewer; each consumer can cancel independently, and the shared
transfer is cancelled only when no consumer remains.

Beta 48 repairs the For You filter at the runtime path actually used by X
12.9. Device diagnostics showed that section deliveries could arrive through
a helper controller with no declared owner link, so that path now fails open
instead of scanning nonexistent ownership fields. The structurally verified
`T1URTViewController` row-height callbacks recheck the explicit primary-Home
timeline marker and collapse matching rows without changing reusable cell
visibility state. The Following timeline therefore remains untouched. Account
filters now also parse bounded, valid `@handle` tokens from X's trusted full
text/display-text models, making an entry such as `grok` catch `@grok` without
treating the ordinary body word “grok” as an account mention. Returning from
settings reloads only the already-loaded primary For You table when the filter
generation changed; it does not make a network request.
