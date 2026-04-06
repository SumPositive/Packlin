# モチメモ Packlin

A packing list and checklist app for iOS, built with SwiftUI.

![Platform](https://img.shields.io/badge/platform-iOS%2016%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
[![App Store](https://img.shields.io/badge/App%20Store-Download-blue)](https://apps.apple.com/app/id495525984)

## Overview

Packlin helps you manage packing lists for travel, camping, work, and everyday carry. Originally released in 2010, fully rebuilt in SwiftUI for v3.

Includes **Chappie** — an AI assistant that generates and organizes list items on your behalf.

## Features

- Manage multiple lists with items and categories
- AI assistant (Chappie) for list suggestions
- In-app purchase for AI usage tickets
- Rewarded ads support

## Backend (azuki-api)

Some features require a lightweight backend:

- **Auth** — device-based authentication without login or personal data
- **Purchase** — validates in-app purchase tickets
- **Ads** — rewards users for watching ads

## StoreKit Testing

- Use a real device with a **Sandbox Apple ID** signed in to the App Store
- No `.storekit` configuration file is required
- TestFlight builds run in StoreKit sandbox mode — no real charges occur

## Requirements

- iOS 16.0+
- Xcode 16+
- Swift 6

## License

Source available for reference. All rights reserved.
