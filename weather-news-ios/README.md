# 空模様ニュース / SkyNews Flow for iOS

Weather clock, animated sky, and personalized continuous RSS scroll on iPhone.
Requirements: iOS 17 or later.

## Features
- Weather forecast and animated cloud/rain/snow/night wallpaper
- Continuous scrolling through RSS-provided article content and summaries
- On-device likes and dislikes; Japanese and English keyword personalization
- Adjustable scroll speed, font size, favorite-to-latest ratio, custom HTTPS RSS
- AQI and UV index from Open-Meteo; 10-minute refresh and cached articles

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
The app only shows full text when RSS includes full content. For summary feeds,
it shows the available summary and an original article link; it does not
circumvent paywalls or copy entire publisher webpages. On-device ratings and
cached articles are saved locally. Weather services receive coordinates.
The app cannot replace the lock screen or scroll after iOS suspends it.