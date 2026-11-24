# 空模様ニュース / SkyNews Flow for iOS

Weather clock, static weather sky, and personalized continuous RSS scroll on iPhone.
Requirements: iOS 17 or later.

## Features
- Weather forecast and static cloud/rain/snow/night wallpaper
- Continuous scrolling through RSS content, with optional public webpage text extraction using SwiftSoup
- On-device likes and dislikes; Japanese and English keyword personalization
- Adjustable scroll speed, font size, favorite-to-latest ratio, custom HTTPS RSS
- AQI and UV index from Open-Meteo; 10-minute refresh and cached articles
- Opt-in ARKit face/gaze estimation: 0.8s looking away pauses, 0.5s looking resumes
- Adjustable gaze timing, manual pause precedence; unsupported/denied -> normal scroll

## Build
With XcodeGen installed on macOS:
  xcodegen generate --spec project.yml
  xcodebuild -project SkyNews.xcodeproj -scheme SkyNews -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

The GitHub Actions workflow sky-news-flow-ipa.yml builds and packages
SkyNews-unsigned.ipa as a downloadable workflow artifact.

## Installation
Unsigned IPA cannot be installed directly. Use Sideloadly to re-sign this IPA
with your Apple ID or configure Xcode signing and build locally.
Free Apple account installs may require periodic renewal.

## Content and privacy
When RSS has only a summary, the app optionally extracts text from public article
HTML (max 24 webpages per refresh). Failed retrieval falls back to the RSS
summary and the original link. It never bypasses paywalls or logins. Follow
each publisher's usage terms. JavaScript-only sites may not be supported. On-device ratings and
cached articles are saved locally. Weather services receive coordinates.
The app cannot replace the lock screen or scroll after iOS suspends it.
## Gaze detection and privacy

The optional gaze feature starts disabled. When enabled it uses ARKit
ARFaceTrackingConfiguration and the camera permission prompt.
The app estimates whether the user's eyes are directed toward the display,
using ARFaceAnchor.lookAtPoint and hysteresis (configurable), not whether the
person is actually reading. An enabled session pauses automatically when
face tracking is lost. On unsupported devices, denied permission, camera errors
or interrupted sessions, the app reverts to regular automatic scrolling and
shows a status. Manual pause always overrides gaze events.

No face image, eye image, ARFrame, eye coordinate, or face geometry is stored,
uploaded, transmitted or used for identity recognition; only transient binary
gaze estimates are used to decide whether to scroll. The face-tracking session
is stopped when the app is backgrounded, settings are shown or the option is
disabled. Battery consumption rises while camera tracking is active. ARKit
isSupport check is performed at runtime, so the app installs on other iPhones.

## Stability changes (0.2.1)

Native article panels are now recycled with a 4-card rolling window. Previous
releases eagerly rendered up to 500 full-length panels, which could exhaust
iPhone memory. The camera ARSession is created only when gaze control is
explicitly turned on, and gaze updates are sampled at roughly 8Hz. HTML
article extraction uses at most two concurrent requests to reduce peaks.

## Headline marquee mode (v0.3.0)

- Default view is a subtle glass ticker board that preserves the existing
  cloud wallpaper, clock, weather and white AQI/UV gauges.
- 2 to 6 independently animated rows show **RSS headlines only**, continuously
  moving right to left in a lightweight UIKit view. No full article HTML is
  downloaded in headline-only mode.
- The lane category is derived from matching headline keywords; when a topic
  is missing, a real populated category is split or repeated rather than
  displaying unrelated articles under a false heading.
- Tap a moving title to pause and open the publisher's original URL. Long
  press a title to vote "interesting" or "not interesting" using the existing
  on-device preference model. The old vertically scrolling full-text mode
  remains available via the bottom mode switch or settings.
- Default: 6 lanes, 42 points/sec, 19-point white text, restrained pastel
  accents on semitransparent charcoal strips.
- The gaze-controlled pause applies to either mode, and the publisher link
  remains the sole route to accessing article HTML from a headline.

## Weather-conditioned wallpaper (v0.3.1)

- Static muted blue/gray background preserves the lock-screen aesthetic.
- Current Open-Meteo weather code, cloud cover, precipitation, snowfall and
  day/night state change its cloud density, sky palette and weather details.
- Clear/partly cloudy/overcast/rain/snow/fog/thunder/night are distinct.
- Local hour can add a slight warm tone near dawn and dusk.
- Updated roughly every ten minutes and when returning to the app.
- When location is denied, the weather fallback is explicitly labeled Tokyo.
  Network failures retain the last successfully received condition.


## Performance and crash mitigation (v0.3.2)

- Weather sky is rendered only when the conditions or view size change,
  to a single opaque low-resolution bitmap. It no longer draws more than
  a hundred animated/blurred/transparent SwiftUI layers.
- Each headline lane keeps only two recycled UIButton instances (12 buttons
  total across 6 lanes) instead of dozens per lane. CADisplayLink updates at
  12 fps, and the display link is invalidated as soon as the view disappears.
- Full-text scroll view also invalidates its CADisplayLink when detached to
  avoid a permanent UIKit display-link retain cycle.
- Feed cache is bounded to 90 articles and 2000 characters each, discarding
  oversized legacy caches on upgrade to prevent OOM during launch.
- At most 120 articles are loaded per refresh; web-text enrichment is bounded
  to 8 pages. Existing RSS/title selection and user preference features remain.

This is a performance fix based on code inspection. Actual iPhone crash logs
and device memory traces have not been obtained, so device-specific crash
resolution must be verified on real hardware.