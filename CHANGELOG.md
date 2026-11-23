# Changelog

## [2.1.0](https://github.com/miyankooo/SimpleReminders/compare/v2.0.0...v2.1.0) (2026-11-23)


### Features

* Each reminder can be Character Specific, so only the character that ticked it lists it and gets its alert ([630138d](https://github.com/miyankooo/SimpleReminders/commit/630138df0f4598488e19f6407678ef185092e50e))
* The button bar has room around Delete and New Reminder ([630138d](https://github.com/miyankooo/SimpleReminders/commit/630138df0f4598488e19f6407678ef185092e50e))
* The window's radios take the round style of Blizzard's dropdown menus ([630138d](https://github.com/miyankooo/SimpleReminders/commit/630138df0f4598488e19f6407678ef185092e50e))
* Whisper, Chat, Test and Character Specific sit in a new Alert section under When ([630138d](https://github.com/miyankooo/SimpleReminders/commit/630138df0f4598488e19f6407678ef185092e50e))

## [2.0.0](https://github.com/miyankooo/SimpleReminders/compare/v1.1.0...v2.0.0) (2026-11-23)


### ⚠ BREAKING CHANGES

* The addon folder and its saved data are now SimpleReminders, so the reminder list starts empty. To keep your reminders, copy WTF/Account/<account>/SavedVariables/RemindMe.lua to SimpleReminders.lua and change RemindMeDB to SimpleRemindersDB at its top.

### Features

* The addon is now Simple Reminders, with /sr and /simplereminders beside /rm and /remindme ([bccb8c7](https://github.com/miyankooo/SimpleReminders/commit/bccb8c7903b8dd24387f342ab6dd84fe8876a530))

## [1.1.0](https://github.com/miyankooo/RemindMe/compare/v1.0.0...v1.1.0) (2026-11-23)


### Features

* A reminder that fires once stays on the list with its note or checklist ([6e14725](https://github.com/miyankooo/RemindMe/commit/6e147254c1c7d15b2d540fb5134af77e0e36d465))
* Alerts arrive as a whisper or a chat line, without the raid warning and the snooze link ([6e14725](https://github.com/miyankooo/RemindMe/commit/6e147254c1c7d15b2d540fb5134af77e0e36d465))
* Changes save as you type, and New Reminder starts a reminder in the window ([6e14725](https://github.com/miyankooo/RemindMe/commit/6e147254c1c7d15b2d540fb5134af77e0e36d465))
* Each reminder has a title with a note of up to 255 characters or a checklist ([6e14725](https://github.com/miyankooo/RemindMe/commit/6e147254c1c7d15b2d540fb5134af77e0e36d465))
* Reminders without a trigger stay on the list as notes and to-do lists ([6e14725](https://github.com/miyankooo/RemindMe/commit/6e147254c1c7d15b2d540fb5134af77e0e36d465))
* The alert shows the title as a link that opens the reminder in the window ([6e14725](https://github.com/miyankooo/RemindMe/commit/6e147254c1c7d15b2d540fb5134af77e0e36d465))
* The list shows each title in full with its trigger and checklist progress ([6e14725](https://github.com/miyankooo/RemindMe/commit/6e147254c1c7d15b2d540fb5134af77e0e36d465))

## 1.0.0 (2026-11-13)


### Features

* A welcome line, a help tip and tooltips introduce the addon ([26fba14](https://github.com/miyankooo/RemindMe/commit/26fba14cad4b52fc081cf28b4333114f0041f239))
* changes to a reminder save when you pick another one or close the window ([49f4b79](https://github.com/miyankooo/RemindMe/commit/49f4b79340756fea13260eb54b91d41c0780a361))
* Chat lines follow the Forever addons' style, with /rm help on one line ([77e5271](https://github.com/miyankooo/RemindMe/commit/77e52717a62dad01726bbd0c9accc26621230508))
* Delete asks before it removes a reminder ([49f4b79](https://github.com/miyankooo/RemindMe/commit/49f4b79340756fea13260eb54b91d41c0780a361))
* Each section of the window shows a gold divider under its heading ([39a0dad](https://github.com/miyankooo/RemindMe/commit/39a0dadb0a51e6838e3da9cba868b56d4d037313))
* repeat a time of day on several weekdays, in the window and with /rm at ([49f4b79](https://github.com/miyankooo/RemindMe/commit/49f4b79340756fea13260eb54b91d41c0780a361))
* rework the reminder window with radios, checkboxes and a live preview ([49f4b79](https://github.com/miyankooo/RemindMe/commit/49f4b79340756fea13260eb54b91d41c0780a361))
* select a reminder in the window to edit it, with Save, Delete and New Reminder ([1ca40d6](https://github.com/miyankooo/RemindMe/commit/1ca40d6c0db5f6a15fb73ed9beaa42d26d9c4570))
* snooze a fired reminder for 10 minutes from its chat line ([49f4b79](https://github.com/miyankooo/RemindMe/commit/49f4b79340756fea13260eb54b91d41c0780a361))
* The Delete dialog has the standard dialog width ([497abac](https://github.com/miyankooo/RemindMe/commit/497abac498386e3bd03c3377869d7a96c7218910))
* The reminder list uses the Collections list style ([f256bec](https://github.com/miyankooo/RemindMe/commit/f256beccab3a0ebb1bc67d485bfa12cf6310dd74))
* the window shows the wardrobe's brown panel, the list and the editor split by the gold divider ([273cefc](https://github.com/miyankooo/RemindMe/commit/273cefcac33077dd95ea1d4d0b663f1d8685afd7))
* the window's panels show the grey stone background instead of the dark marble ([ba4cf3e](https://github.com/miyankooo/RemindMe/commit/ba4cf3e6bcdadd5ac47afdf485b0c10f354adc9e))


### Bug Fixes

* /rm minimap prints a line only when it hides the button ([3cd1fc3](https://github.com/miyankooo/RemindMe/commit/3cd1fc37e4a0596c4827a27412a17eab5f9eb9e1))
* The Remind Me Later window loads again ([97ff945](https://github.com/miyankooo/RemindMe/commit/97ff945704acffb890c82e92dc49bc1a4d0c2181))
