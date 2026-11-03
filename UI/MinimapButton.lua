local _, ns = ...

local UI = LibStub("LibNativeUI-1.0")
local Time = ns.Time
local Reminders = ns.Reminders

-- The tooltip names the next reminders, so a glance at the minimap answers what is coming up.
local TOOLTIP_LIMIT = 5

-- Blizzard's tooltip line helpers keep the colours of every native tooltip.
local function fillTooltip(tooltip)
    local sorted = Reminders.Sorted()
    if #sorted == 0 then
        GameTooltip_AddDisabledLine(tooltip, "No reminders yet.")
    else
        local now = GetServerTime()
        for i = 1, math.min(#sorted, TOOLTIP_LIMIT) do
            local r = sorted[i]
            local when = r.due and ("in " .. Time.FormatLeft(r.due - now)) or r.zone
            GameTooltip_AddColoredDoubleLine(tooltip, r.text, when, UI.Color.body, UI.Color.muted)
        end
        if #sorted > TOOLTIP_LIMIT then
            GameTooltip_AddDisabledLine(tooltip, ns.countLabel(#sorted - TOOLTIP_LIMIT, "more reminder", "more reminders") .. ".")
        end
    end
    GameTooltip_AddBlankLineToTooltip(tooltip)
    GameTooltip_AddInstructionLine(tooltip, "Click to toggle the window.")
end

local launcher

-- The minimap button and the addon menu entry share this click and tooltip. Its position lives in
-- the account-wide table, so every character shares it.
function ns.SetupLauncher()
    launcher = UI.CreateLauncher({
        title = ns.TITLE,
        icon = ns.ICON,
        db = SimpleRemindersDB.minimap,
        onClick = function() ns.TogglePanel() end,
        tooltip = fillTooltip,
    })
end

-- /sr minimap flips only the minimap button. The addon menu entry always stays as the way back.
function ns.ToggleMinimap()
    local show = SimpleRemindersDB.minimap.hide
    launcher.setShown(show)
    UI.Print(ns.TITLE, show and "Minimap button shown." or "Minimap button hidden. Type /sr minimap to show it again.")
end
