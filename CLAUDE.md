# SimpleReminders

Reminders by countdown, time of day or zone, shown as a whisper, a chat line or a raid warning. Features, commands and options are in `README.md`.

## Target

- WoW Forever 1.60.x only, `## Interface: 16001`. No client branches, no `WOW_PROJECT_*`, no compat layer.
- Verify every API against Gethe `wow-ui-source` and Ketho `BlizzardInterfaceResources`, branch `forever`.

## Rules

- Every reminder has `kind` (`timer`, `clock`, `zone`), `output` (`whisper`, `print`, `warning`) and `rep`. `rep` is false for once and true for every time or every day. A weekday 1 to 7 (1 is Sunday, `date("*t").wday`) means a weekly time of day.
- Timed reminders keep an epoch `due` from `GetServerTime()`. Realm time comes from `GetGameTime()`, the clock Blizzard's minimap shows, as a UTC offset rounded to 15 minutes. Local time goes through `time()` with a date table, so DST is handled by the client.
- The default clock follows the `timeMgrUseLocalTime` CVar, the player's own clock setting. The default output is Whisper.
- Outputs stay on this client. Whisper is a local line in the whisper colour and sound, never `SendChatMessage`, which is `HasRestrictions` on Forever. Raid warning follows `TimeManager_FireAlarm`: a system chat line plus `RaidWarningUtil.AddMessage` and the raid warning sound.
- Login catch-up: a one-time reminder that came due offline fires on the first tick. A repeating one fires only within `ns.MISSED_GRACE` (a reload), otherwise it moves to its next turn.
- Zone reminders fire on entry only: adding one inside its zone, moving within it, a `/reload` and an empty zone name around a loading screen never fire. Login inside the zone counts as entry.
- Reminders live in `SimpleRemindersDB.reminders`, account-wide. `/sr list` and `/sr remove` share `Reminders.Sorted()` numbering.
- Every command has a window counterpart and the other way round. Update `HELP`, the README tables and the window together.
- Build the UI from LibNativeUI-1.0 roles and tokens: `UI.Font`, `UI.Space`, `UI.Native` and the 4 px grid. No literal `|cff` codes. Feedback goes through `UI.Print`, one line per action. Window problems show in the status line, not in chat.
- Keep the LibDBIcon minimap icon, shown by default. Click toggles the window, the tooltip lists the next five reminders. `/sr minimap` hides only the minimap button.
- No `## AddonCompartmentFunc*` toc fields. LibDBIcon registers the addon menu entry.
- The icon `Interface\Icons\INV_Misc_Bell_01` (file 133706) is the toc `IconTexture` and `ns.ICON`. Change both together.
- Title Case for headings and buttons, sentence case ending in a period for chat lines. No dashes in copy.

## Libraries

- `Libs/` holds tracked, unedited upstream copies. No `.pkgmeta` externals.
- LibNativeUI-1.0 is a byte-identical copy. Its reference copy lives in ChatScan, so never edit it here. `shasum */Libs/LibNativeUI-1.0/LibNativeUI-1.0.lua` must print one hash.

## Checks

- Run `luac -p` on every Lua file and `lua Tests/Reminders.lua` after a change. Run it under another `TZ` too, such as `TZ=Australia/Sydney`.
- `Tests/Reminders.lua` stubs the client. A new client API needs a stub there.
- Test in game from a clone symlinked into `World of Warcraft/_forever_/Interface/AddOns/`. Turn on `/console scriptErrors 1` first.

## Release

- The toc version stays 1.0.0 until the first CurseForge release.
- A `v*` tag runs `.github/workflows/release.yml` with the BigWigs packager. The CurseForge upload also needs the `CF_API_TOKEN` secret and a toc `## X-Curse-Project-ID`. `.pkgmeta` leaves out `CLAUDE.md`, `Tests` and `Tools`. `CHANGELOG.md` is the release changelog.
- Licence: MIT (`LICENSE`).
