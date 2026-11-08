local addonName, ns = ...

-- Loads last, so every Core and UI file has registered itself. The saved variables arrive with
-- ADDON_LOADED, and a missing table marks the account's first run, which the welcome line reads at
-- login. Reminders are account-wide, so a reminder fires on whichever character is online.
EventUtil.ContinueOnAddOnLoaded(addonName, function()
    ns.firstRun = RemindMeDB == nil
    RemindMeDB = RemindMeDB or {}
    local db = RemindMeDB
    db.minimap = db.minimap or { hide = false, minimapPos = 235 }
    db.window = db.window or {}
    db.reminders = db.reminders or {}
    db.nextId = db.nextId or 1
end)

-- Reminders start before the launcher is built, so a broken library can never cost a reminder.
EventUtil.ContinueOnPlayerLogin(function()
    ns.Reminders.Start()
    ns.SetupLauncher()
end)
