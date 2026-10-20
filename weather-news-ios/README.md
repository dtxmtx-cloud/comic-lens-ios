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