# モチメモ Packlin

A packing list and checklist app for iOS, built with SwiftUI.

![Platform](https://img.shields.io/badge/platform-iOS%2016%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
[![App Store](https://img.shields.io/badge/App%20Store-Download-blue)](https://apps.apple.com/app/id495525984)

## Overview

Packlin helps you manage packing lists for travel, camping, work, and everyday carry. Originally released in 2010, fully rebuilt in SwiftUI for v3.

Includes **Chappie** — an AI assistant that generates and organizes list items on your behalf.

## Features

### Core
- 3-tier hierarchy: **Pack → Group → Item**
- Check items individually; track required quantity and stock quantity
- Register weight per item (g); view total weight per pack
- Drag-and-drop reordering within any list
- Move or duplicate items across groups and packs
- Move or duplicate groups across packs
- Undo / Redo (up to 10 steps each)

### Item Overview
- Browse all items in a pack across every group from a single screen
- Sort by: unchecked, shortage count, shortage weight, or stock weight
- Keyword search (name and memo)
- Auto-sort: list re-orders automatically as you update items

### Quantity Input
- **Dial**: drag left/right to increment — customizable style and sensitivity (Dial Settings)
- **Numeric keypad**: tap a value field to open a dedicated keypad sheet

### Sharing & Backup
- Export a single pack as a `.packlin` file via AirDrop, email, etc.
- Export all packs as a backup file; import to restore on any device

### AI (Chappy)
- Generate a complete pack from a free-text description
- Revise an existing pack with AI suggestions
- 1 AI ticket per generation; tickets available via in-app purchase or rewarded ads

### Settings
- Display mode: Beginner (hints shown) / Expert (compact)
- Appearance: System / Light / Dark
- Row detail: Minimal / 1 line / 2 lines / 3 lines
- New item position: top or bottom of list
- Weight display: show required weight; switch to kg above 1,000 g
- Check ↔ stock linking: fill stock on check-on; clear stock on check-off

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
