local _, ns = ...

local Time = ns.Time
local Reminders = ns.Reminders

-- The tooltip names the next reminders, so a glance at the minimap answers what is coming up.
local TOOLTIP_LIMIT = 5

-- One launcher for the minimap button and the Addon Compartment: LibDBIcon draws the button and adds the
-- compartment entry through AddonCompartmentFrame, so both share the click and the tooltip. Such an addon has no
-- AddonCompartmentFunc toc keys. LibStub, CallbackHandler-1.0, LibDataBroker-1.1 and LibDBIcon-1.0 load first.
local function CreateLauncher(icon, db, onClick, fillTooltip)
    local LDBIcon = LibStub("LibDBIcon-1.0")
    if not LDBIcon:IsRegistered(ns.title) then
        local object = LibStub("LibDataBroker-1.1"):NewDataObject(ns.title, {
            type = "launcher",
            text = ns.title,
            icon = icon,
            OnClick = function(_, button) onClick(button) end,
            OnTooltipShow = function(tooltip)
                GameTooltip_SetTitle(tooltip, ns.title)
                fillTooltip(tooltip)
            end,
        })
        LDBIcon:Register(ns.title, object, db)
        LDBIcon:AddButtonToCompartment(ns.title)
    end
    -- Shows or hides only the minimap button and remembers it in db.hide; the addon menu entry stays.
    return function(shown)
        db.hide = not shown
        if shown then LDBIcon:Show(ns.title) else LDBIcon:Hide(ns.title) end
    end
end

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
            GameTooltip_AddColoredDoubleLine(tooltip, r.text, when, HIGHLIGHT_FONT_COLOR, GRAY_FONT_COLOR)
        end
        if #sorted > TOOLTIP_LIMIT then
            GameTooltip_AddDisabledLine(tooltip, ns.countLabel(#sorted - TOOLTIP_LIMIT, "more reminder", "more reminders") .. ".")
        end
    end
    GameTooltip_AddBlankLineToTooltip(tooltip)
    GameTooltip_AddInstructionLine(tooltip, "Click to toggle the window.")
end

local setMinimapShown

-- The minimap button and the addon menu entry share this click and tooltip. Its position lives in
-- the account-wide table, so every character shares it.
function ns.SetupLauncher()
    setMinimapShown = CreateLauncher(ns.ICON, RemindMeDB.minimap, function() ns.TogglePanel() end, fillTooltip)
end

-- /rm minimap flips only the minimap button. The addon menu entry always stays as the way back.
-- Hiding says how to undo it; showing needs no line, since the button itself appears.
function ns.ToggleMinimap()
    local show = RemindMeDB.minimap.hide
    setMinimapShown(show)
    if not show then ns.Print("Minimap button hidden. Type /rm minimap to show it again.") end
end
