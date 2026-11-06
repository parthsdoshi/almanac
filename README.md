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
  DesignSystem/Almanac.swift Date chip and confetti, also used by the Live Activity
  Fonts/                     Display font (Fraunces, OFL)
  OccasionAttributes.swift   Live Activity data (a contract with the server)
  MuteOccasionIntent.swift   The Mute button
Widget/                Live Activity: Lock Screen + Dynamic Island  <- design pass
Tests/                 Swift Testing unit tests for the date, stats, parsing and merge logic
server/                Node push server (no dependencies)
render.yaml            Render Blueprint for the server
.github/workflows/     TestFlight upload (run by hand), build check on pull requests
ci/                    Export settings for that workflow
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

## 4. TestFlight (so others can install it)

`.github/workflows/testflight.yml` builds the app on a GitHub Mac runner, signs it with Apple's cloud-managed signing, and uploads it to TestFlight. Nothing runs on its own: you start it from Actions > TestFlight > Run workflow. Each run uses the run number as the build number.

One-time setup:

1. **Register the bundle ID.** developer.apple.com > Identifiers > + > App IDs. Use your `APP_BUNDLE_ID` and tick **Push Notifications**. (Building once from Xcode with Automatic signing does this too.)
2. **Create the app in App Store Connect.** appstoreconnect.apple.com > Apps > + > New App: iOS, Almanac (or any name that's free), pick that bundle ID, any SKU.
3. **Make an App Store Connect API key.** App Store Connect > Users and Access > Integrations > App Store Connect API > +. Give it the **Admin** role, because cloud signing has to create a distribution certificate. Download the `.p8` (only once) and note the **Key ID** and the **Issuer ID** at the top of the page. This is a different key from the APNs one.
4. **Add repo secrets** in GitHub > Settings > Secrets and variables > Actions:

   | Secret | Value |
   | --- | --- |
   | `APPLE_TEAM_ID` | your Team ID |
   | `APP_BUNDLE_ID` | your bundle ID |
   | `ASC_KEY_ID` | the API key's Key ID |
   | `ASC_ISSUER_ID` | the Issuer ID |
   | `ASC_KEY_P8` | the whole contents of the API key's `.p8` file |
   | `OCCASIONS_SERVER_HOST` | the Render host, no `https://` |
   | `OCCASIONS_API_KEY` | the `API_KEY` Render generated |

   The last two are optional; without them the TestFlight build runs without the server.

Then run the workflow. Processing in App Store Connect takes a few minutes after the upload finishes. In App Store Connect > your app > TestFlight, add testers by Apple ID email under Internal Testing (people on your team) or External Testing (anyone, but the first build of each version needs a short Beta App Review).

The icon in `App/Assets.xcassets` is a placeholder until the design pass. App Store Connect rejects uploads with no icon.

## What the server knows

For each occasion: an opaque id (a hash), birthday or anniversary, first names, month and day. Plus your push token, time zone and send hour. No last names, birth years, phone numbers or contact ids. The server drops any other field it's sent. Logs only show occasion ids.

## Debug vs release builds

Builds run from Xcode get sandbox push tokens; TestFlight and App Store builds get production ones. The app reports its best guess, and if Apple rejects the token as `BadDeviceToken`, the server retries the other environment and remembers whichever worked.

## Design: the almanac look

A paper birthday almanac: cream paper by day and warm ink by night (it follows the phone's light/dark setting), a chunky soft serif for names and numbers, tear-off calendar dates, a big day countdown per person, and confetti on the day and when you text or call someone. Reduce Motion turns the confetti burst off.

All visual decisions sit in these places:

- `Shared/DesignSystem/Theme.swift`: every color (light and dark), type, spacing, radii, icons. The single source of tokens.
- `Shared/DesignSystem/Almanac.swift`: `DateChip` (the tear-off date) and `ConfettiField`, shared with the Live Activity.
- `App/DesignSystem/Components.swift`: `OccasionRow`, `TodayCard`, `Countdown`, `SectionTitle`, `ActionButton`, `StatTile`, `StatusDot`, `LedgerRow`, `ConfettiBurst`.
- `App/DesignSystem/Appearance.swift`: navigation and tab bar fonts and colors.
- `Widget/OccasionLiveActivity.swift`: Lock Screen and Dynamic Island layouts.
- `Shared/Fonts`: the display font, cut from [Fraunces](https://github.com/undercasetype/Fraunces) (SIL Open Font License, see `OFL-Fraunces.txt`) into three static styles named "Almanac Display". If it fails to load, text falls back to the system serif.

## Known limits

- iOS keeps at most 64 pending local notifications per app. The app schedules the next 60 and rolls the window forward on each launch and background refresh.
- A Live Activity stays up for 8 hours, then sits on the Lock Screen for up to 4 more before iOS removes it. The app also clears it when you message, call or mute.
- Texting counts in stats only when Messages reports it sent. Calls count when you open the call prompt, because iOS doesn't tell apps whether a call happened.
- Lunar and other non-Gregorian birthdays are ignored.
- Mute from the Live Activity runs in the app's process in the background, so it needs the app to have been installed and opened once (it will have been).
- The app's API key is a shared secret baked into your build. That's fine for a personal app. It would need real auth before anyone else used it.
