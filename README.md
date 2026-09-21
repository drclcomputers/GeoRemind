# GeoRemind

Location reminders on a map. You drop a pin, set a radius, and the phone pings you when you get there (or when you leave). Optional: only on certain days, or between two hours. Still not a calendar.

<p align="center">
  <img src="GeoRemind/assets/img/1.png" width="30%" />
  <img src="GeoRemind/assets/img/2.png" width="30%" />
  <img src="GeoRemind/assets/img/3.png" width="30%" />
</p>
<p align="center">
  <sub>1. Map with pins and geofence circles &nbsp;·&nbsp; 2. New reminder (radius, group, when) &nbsp;·&nbsp; 3. Reminders list, sorted by distance</sub>
</p>

Works without an account — pins stay on that iPhone. Sign in (email, Google, or Facebook) if you want sync and groups. Guest pins get uploaded when you sign in. Sign out clears the local copy of cloud pins.

## What it does

- Pins on the map, each with a visible radius. Grey = off, accent = watching.
- Search a place, current location, or one-tap **Home / Work** (saved in Settings).
- Radius slider, 50 m to 2 km. Arrival, departure, or both.
- **When:** every time or once, weekdays, optional hour window (e.g. shop only 14:00–15:00). Once fires and turns the pin off; it isn't deleted.
- List tab: distance from you, swipe to delete / toggle, pull to refresh. Group pins show a small people icon.
- Notification actions on repeating pins: **Skip** (this visit) and **Snooze 1h**. Same pin also has a 2-minute cooldown so GPS jitter doesn't spam you.
- Groups: 6-character invite code, not “add anyone by username”. Shared reminders show on everyone's map. Kick someone and their group pins become personal — they keep them.
- Profile: username, photo, groups, join-by-code. Offline: you stay on the account, pins still edit locally, groups/sync wait for a connection.
- Settings: light / dark / system, metric or imperial, language (opens iOS Settings), sign out, link Google/Facebook, delete account.
- Siri / Shortcuts: “Add a reminder here in GeoRemind” — pin at your current location, 200 m, arrival.

iOS only lets an app monitor **20** regions in the background. GeoRemind keeps the closest active ones and reshuffles when you move. Always-location uses region monitoring + significant location changes, not continuous GPS.

<p align="center">
  <img src="GeoRemind/assets/img/4.png" width="30%" />
  <img src="GeoRemind/assets/img/5.png" width="30%" />
  <img src="GeoRemind/assets/img/6.png" width="30%" />
</p>
<p align="center">
  <sub>4. Profile / groups &nbsp;·&nbsp; 5. Sign in (optional) &nbsp;·&nbsp; 6. Settings</sub>
</p>

If you retake screenshots: **2** should show the When row (days + hours). **3** the offline banner isn't required. The rest can stay as they are.

## Stack

SwiftUI. MapKit and CoreLocation for the map and geofences. UserNotifications for the ping. App Intents for Siri. Supabase for auth, Postgres, storage (avatars), optional realtime.

Local cache on disk so geofences still work offline; edits queue and sync when you're back. Row-level security on the server: you write your own reminders; group members can read shared ones.

## Layout

```
GeoRemind/
  Views/        map, list, add, profile, auth, settings, group sheet, schedule
  Services/     geofence, auth, reminders, groups, search, network, notifications
  Models/       ReminderPin, profiles / groups / invites, Siri intent
```

`GeofenceManager` owns `CLCircularRegion`s. `ReminderStore` / `GroupStore` talk to Supabase (or the local cache). `AuthService` is email + OAuth. `AddReminderHereIntent` is the Siri shortcut.

## Run it

1. Clone, open `GeoRemind.xcodeproj`.
2. Add the [Supabase Swift](https://github.com/supabase/supabase-swift) package if Xcode hasn't resolved it.
3. URL scheme `georemind` is already in the project (OAuth callback).
4. Real device if you actually want geofences. Simulator is fine for UI.

You need your own Supabase project. Full SQL + Auth notes: [`SUPABASE_CONFIG.md`](SUPABASE_CONFIG.md). If the `reminders` table already exists, run the **Recurring reminders** `ALTER` at the bottom of that file or new pins won't sync the When fields.

The anon key in the client is the publishable one — RLS is what keeps other people out of your rows.

## Permissions

- **Location:** When In Use at first. **Always** if you want pings while the app is closed (swipe-killed is fine; don't disable location for the app).
- **Notifications:** otherwise the geofence fires and nobody hears it.
- **Photos:** only if you change the profile picture.
- **Siri:** optional. The shortcut is donated after you open the app once.

## License

See [LICENSE](LICENSE).
