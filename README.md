# Recall

Recall is an iOS app that lets you save a memory (photo + location) and navigate back to it later — even under inconsistent GPS conditions.

![Recall preview](Recall/docs/recall-preview.png)

## What it does

- Capture a memory with photo + location context
- Persist memories locally on device
- Browse memories in a timeline view
- Navigate back using distance, heading, and a breadcrumb trail
- Maintain usable guidance under weak or noisy GPS

## Key idea

Traditional navigation assumes GPS is reliable.

Recall instead treats location as uncertain:
- records breadcrumb trails over time
- uses movement + heading to guide direction
- adapts behavior when signal quality drops
- refines paths when better GPS becomes available

## Tech stack

- SwiftUI
- SwiftData
- CoreLocation
- MapKit
- AVFoundation
- Vision
- ActivityKit (Live Activities)

## Architecture

High-level architecture:

![Recall high-level architecture](Recall/docs/recall-high-level.png)

Low-level architecture:

<img src="Recall/docs/recall-low-level.png" alt="Recall low-level architecture" width="700" />

## Engineering approach
Instead of assuming location is always correct, Recall treats positioning as uncertain and adapts in real time by:
- tracking breadcrumb history rather than a single point
- scoring location confidence from signal quality/motion stability
- switching navigation behavior as confidence changes
- using estimated movement fallback during weak/absent GPS windows
- refining guidance once stronger GPS returns

## Experiments / Observations
Field and simulation results show navigation quality varies by signal conditions:
- **Stable GPS:** smooth breadcrumb trail and reliable return path in tests.
- **Mixed signal:** usable guidance with occasional drift; recovery improves after stronger updates return.
- **Poor indoor signal:** currently inconsistent in real-world tests; directional guidance may remain usable, but path accuracy can degrade substantially.

Simulation confirms fallback logic behavior, but under-represents indoor multipath/noise. 

Current focus is tuning indoor fallback thresholds using repeated field runs.

## Run locally

1. Open `Recall.xcodeproj` in Xcode.
2. Select an iPhone simulator or real device.
3. Build and run the `Recall` target.


## Current limitations (updated 26 April 2026)

- Indoor/deep-parking navigation remains less reliable than outdoor routing.
- Simulation performance is currently stronger than real-world indoor performance.
- Current focus: tuning fallback thresholds using repeated parking-to-mall field runs.

## Demo video notes

The short demo video is edited for pacing and clarity (cuts, sped-up walking segments with on-screen 2x speed, and minor transition smoothing).  
No core navigation behavior was altered.

Timeline extra entries shown in the demo were curated to quickly illustrate multiple use cases in a short video.

For full context:
- [Edited demo video](https://www.youtube.com/shorts/Bb99dfuGlN4)
- [Unedited capture (privacy-redacted)](https://www.youtube.com/shorts/3luxJZME3o0)

Privacy note: license plates are blurred in the unedited capture.
