# Occasions

Birthday and anniversary reminders from your iOS Contacts, with a day-of Live Activity that puts Message, Call and Mute one tap away.

- Reads birthdays and anniversaries from Contacts. A couple's anniversary (linked through the spouse/partner field) becomes one occasion with both people.
- A heads-up notification X days before (Settings, default 3) at your chosen hour.
- On the day, a Live Activity started by the push server at your chosen hour, even if the app is closed:
  - **Message** opens Messages' compose sheet, addressed and prefilled. For a couple it's a group text.
  - **Call** opens iOS's call prompt. For a couple it asks which of them first.
  - **Mute** stops that occasion forever, without opening the app. You can undo it in Settings.
- Stats: how many unmuted occasions you reached out for vs missed, since you installed it.
- Suggestions: finds birthday events in your calendar that aren't in Contacts, and adds them with a tap.

iOS never sends a text or places a call without your tap. Message and Call open the app for a moment first, because Live Activity links can only open their own app.

## Layout

```
project.yml            XcodeGen spec (the .xcodeproj is generated, not committed)
Config/                Build settings. Your own values go in Secrets.xcconfig
App/                   The iOS app
  AppModel.swift       App state and every user action
  Models/              Occasion, dates, persisted state
  Services/            Contacts, notifications, Live Activities, calendar scan, push server client, stats
  Views/               Screens (layout only)
  DesignSystem/        Reusable components  <- design pass
Shared/                Compiled into the app and the widget
  DesignSystem/Theme.swift   Colors, type, spacing, icons  <- design pass
  OccasionAttributes.swift   Live Activity data (a contract with the server)
  MuteOccasionIntent.swift   The Mute button
Widget/                Live Activity: Lock Screen + Dynamic Island  <- design pass
Tests/                 Swift Testing unit tests for the date, stats, parsing and merge logic
server/                Node push server (no dependencies)
render.yaml            Render Blueprint for the server
```

## What you need

- Xcode 16 or newer, and an iPhone on iOS 17.2+. Test on a real phone: push-to-start doesn't work in the Simulator.
- A paid Apple Developer Program membership. A free personal team can't use push notifications.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.

## 1. Run the app

```sh
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Fill in `Config/Secrets.xcconfig`:

- `DEVELOPMENT_TEAM`: your Team ID (developer.apple.com/account, Membership details).
- `APP_BUNDLE_ID`: something unique like `com.parthdoshi.occasions`. The widget becomes `<APP_BUNDLE_ID>.widget`.
- Leave the two server values empty for now.

```sh
xcodegen generate
open Occasions.xcodeproj
```

Run the `Occasions` scheme on your phone. With Automatic signing, Xcode registers the bundle IDs and turns on Push Notifications for you. Without the server, reminders work and the day-of Live Activity starts when you open the app that day. Settings > "Preview Live Activity on this phone" shows it right away.

Run the tests with Cmd-U.

## 2. Make an APNs key

developer.apple.com > Certificates, IDs & Profiles > Keys > +. Name it, tick **Apple Push Notifications service (APNs)**, and set the environment to **Sandbox & Production**. Download `AuthKey_XXXXXXXXXX.p8`. Apple only lets you download it once. Note the **Key ID**.

The key stays with you and Render. Don't commit it (`*.p8` is gitignored).

## 3. Deploy the server on Render

1. Push this folder to a GitHub repo.
2. In Render: New > Blueprint, pick the repo. It reads `render.yaml` and creates `occasions-push`, a $7/month web service with a 1 GB disk ($0.25/month), in Virginia.
3. When asked, fill in:
   - `APNS_KEY_ID`: the Key ID from step 2
   - `APNS_TEAM_ID`: your Team ID
   - `APNS_BUNDLE_ID`: exactly your `APP_BUNDLE_ID`
4. On the service, open Environment > Secret Files, add a file named `AuthKey.p8` and paste the contents of the .p8. (Alternatively set an `APNS_PRIVATE_KEY` env var to the PEM text.)
5. Copy the generated `API_KEY` value and the service's host (like `occasions-push-abcd.onrender.com`) into `Config/Secrets.xcconfig`:

   ```
   OCCASIONS_SERVER_HOST = occasions-push-abcd.onrender.com
   OCCASIONS_API_KEY = <API_KEY from Render>
   ```

   No `https://` on the host: xcconfig treats `//` as a comment.
6. Rebuild and run. Open the app once so it uploads its push token, then Settings > "Send a test Live Activity". It should land on your Lock Screen within seconds.

### Why a web service and not just a cron job

A cron job can't receive the app's uploads, and Render cron jobs can't have a disk. "Cron only" would really be cron ($1+/month) + a web service + a $6/month Postgres, so three things to run for the same price. One small always-on service with a JSON file on a disk is simpler. It checks every 5 minutes, which also handles time zones: the push goes out at your send hour wherever your phone says you are, so it still lands in the morning when you're in Mumbai or Colombo.

## What the server knows

For each occasion: an opaque id (a hash), birthday or anniversary, first names, month and day. Plus your push token, time zone and send hour. No last names, birth years, phone numbers or contact ids. The server drops any other field it's sent. Logs only show occasion ids.

## Debug vs release builds

Builds run from Xcode get sandbox push tokens; TestFlight and App Store builds get production ones. The app reports its best guess, and if Apple rejects the token as `BadDeviceToken`, the server retries the other environment and remembers whichever worked.

## Design pass with Claude Design

All visual decisions sit in three places:

- `Shared/DesignSystem/Theme.swift`: colors, type, spacing, corner radii, icons. Used by the app and the Live Activity.
- `App/DesignSystem/Components.swift`: `OccasionRow`, `KindBadge`, `ActionButton`, `StatTile`, `StatusDot`.
- `Widget/OccasionLiveActivity.swift`: Lock Screen and Dynamic Island layouts.

Screens to design: Onboarding, Upcoming (Today / This week / This month / Later), Occasion detail, Stats, Suggestions, Settings, and the Live Activity on the Lock Screen and in the Dynamic Island (compact, minimal, expanded). Do the design in Claude Design, then hand it to Claude Code pointing at those three files. `App/Views` should only need layout changes.

## Known limits

- iOS keeps at most 64 pending local notifications per app. The app schedules the next 60 and rolls the window forward on each launch and background refresh.
- A Live Activity stays up for 8 hours, then sits on the Lock Screen for up to 4 more before iOS removes it. The app also clears it when you message, call or mute.
- Texting counts in stats only when Messages reports it sent. Calls count when you open the call prompt, because iOS doesn't tell apps whether a call happened.
- Lunar and other non-Gregorian birthdays are ignored.
- Mute from the Live Activity runs in the app's process in the background, so it needs the app to have been installed and opened once (it will have been).
- The app's API key is a shared secret baked into your build. That's fine for a personal app. It would need real auth before anyone else used it.
