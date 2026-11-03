# Simple Reminders

Reminders for WoW Forever. Set them by countdown, by time of day or by zone, and get them as a whisper, a chat line or a raid warning.

## Features

- Countdown reminders, such as 30 minutes from now, once or repeating
- Time of day reminders on realm time or local time, once, every day or every week on one weekday
- Zone reminders that fire when you enter a zone or an area in it, such as Stormwind or the Trade District
- Three ways to get them: a whisper with the whisper sound, a chat line, or a raid warning across the screen with its sound
- A window to add, test and remove reminders, and slash commands that do the same
- A minimap button and an Addon Compartment entry. The tooltip shows the next reminders
- Reminders are saved for your account and fire on whichever character is online
- A one-time reminder that came due while you were offline fires at login. A repeating one skips to its next turn

## Installation

1. Install it with the CurseForge app under WoW Forever, or copy the `SimpleReminders` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
2. Restart the game or type `/reload`.
3. Enable Simple Reminders in the AddOns list.

## Usage

1. Type `/sr`, or click the minimap button or the Addon Compartment entry.
2. Under Message, type what to remind you of.
3. Under When, pick Countdown, Time of Day or Zone and fill in the field below it. Current Zone fills in the zone you stand in.
4. Pick Realm Time or Local Time for a time of day, and Once or a repeat.
5. Under Send As, pick Whisper, Chat or Raid Warning. Test shows how it arrives.
6. Press Add Reminder, or Enter in a field. The list on the left counts down, and the X removes a reminder.

## Commands

| Command | Does |
| --- | --- |
| `/sr` | Opens or closes the window |
| `/sr in 30m <text>` | Countdown, such as `90s`, `45m`, `2 hours` or `1h 30m` |
| `/sr at 20:30 <text>` | Time of day, such as `8:30pm` or `8 pm` |
| `/sr zone Stormwind City: <text>` | When you enter a zone. Without a colon the zone is one word: `/sr zone Orgrimmar Visit the bank` |
| `/sr here <text>` | When you come back to the zone you are in |
| `/sr list` | Lists your reminders with numbers |
| `/sr remove 2` | Removes reminder 2 from the list |
| `/sr test 2` | Shows reminder 2 once now and keeps it |
| `/sr clear` | Removes every reminder |
| `/sr minimap` | Hides or shows the minimap button |
| `/sr help` | Prints the commands |

`/simplereminders` works as well.

Options go between the trigger and the text, in any order:

| Option | Does |
| --- | --- |
| `whisper`, `print` or `chat`, `warning` or `rw` | How the reminder arrives. Whisper is the default |
| `repeat` | Restarts a countdown after it fires, or fires a zone reminder on every entry |
| `daily` | Repeats a time of day every day |
| `monday` to `sunday`, or `mon` to `sun` | Repeats a time of day every week on that day |
| `realm`, `local` | The clock for a time of day. The default follows your minimap clock setting |

| Example | Reminds you |
| --- | --- |
| `/sr in 1h 30m Check the auction house` | in 90 minutes, as a whisper |
| `/sr in 30m repeat print Drink water` | every 30 minutes, in chat |
| `/sr at 19:45 warning monday Raid tonight` | every Monday at 19:45, as a raid warning |
| `/sr at 8pm local daily Do your dailies` | every day at 8 PM your time |
| `/sr zone Stormwind City: repeat Buy reagents` | every time you enter Stormwind City |

## Requirements

WoW Forever 1.60.x (Interface `16001`). No other addons needed.

## Notes

- The whisper comes from Simple Reminders inside your own client. Nothing is sent to the server, so it also works where the game limits addon chat.
- A raid warning reminder shows only on your screen, like the game's own alarm clock. Nobody in your raid sees it.
- Zone names match the start, middle or end of the zone or area name in any case, so `storm` also matches Stormwind City.
