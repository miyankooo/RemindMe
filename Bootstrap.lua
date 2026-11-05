local _, ns = ...

-- Loads last, so every Core and UI file has registered itself. Saved variables are in place by
-- PLAYER_LOGIN. Reminders are account-wide, so a reminder fires on whichever character is online.
-- They start before the launcher is built, so a broken library can never cost a reminder.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    RemindMeDB = RemindMeDB or {}
    local db = RemindMeDB
    db.minimap = db.minimap or { hide = false, minimapPos = 235 }
    db.window = db.window or {}
    db.reminders = db.reminders or {}
    db.nextId = db.nextId or 1

    ns.Reminders.Start()
    ns.SetupLauncher()
end)
