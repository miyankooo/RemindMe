-- Loads every addon file in toc order against a small client stub, then checks parsing, scheduling,
-- catch-up, delivery, snooze links, zone entry, every slash command and the window's flows.
--
-- What it cannot prove: anything the real client decides. GetGameTime's realm clock, the raid warning
-- frame, chat tab routing, sounds, LibDBIcon and every pixel of the window still need an in-game pass.
--
-- Run with: lua Tests/Reminders.lua (from the addon folder)

local here = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local ADDON = here .. "../"

unpack = unpack or table.unpack

local failures, passes = 0, 0
local function check(name, ok)
    if ok then
        passes = passes + 1
    else
        failures = failures + 1
        io.write("FAIL ", name, "\n")
    end
end

-- === clock and world the tests move ===
local NOW = 1793700000 -- 2026-11-04 08:00:00 UTC, a Wednesday
local REALM_OFFSET = -8 * 3600
local world = { now = NOW, zone = "Elwynn Forest", subzone = "Goldshire", localTime = false }

local chat, sounds, warnings = {}, {}, {}
local ticker, focused

-- === frame stub: unknown methods record and chain, a few keep state ===
local CHILDREN = { Instructions = true, ScrollBar = true, Inset = true, Text = true, Bg = true, TopTileStreaks = true,
    NineSlice = true, BackgroundTile = true, BGCornerTopLeft = true, BGCornerTopRight = true, BGCornerBottomLeft = true,
    BGCornerBottomRight = true }
local created = {}

local function newRegion(kind, template)
    local r = { kind = kind, template = template, scripts = {}, hooks = {}, shown = true, height = 0 }
    local methods = {
        SetText = function(self, text) self.text = text end,
        GetText = function(self) return self.text or "" end,
        SetHeight = function(self, h) self.height = h end,
        GetHeight = function(self) return self.height end,
        SetScript = function(self, name, fn) self.scripts[name] = fn end,
        GetScript = function(self, name) return self.scripts[name] end,
        HookScript = function(self, name, fn) self.hooks[name] = fn end,
        IsShown = function(self) return self.shown end,
        Show = function(self) self:SetShown(true) end,
        Hide = function(self) self:SetShown(false) end,
        SetShown = function(self, shown)
            local was = self.shown
            self.shown = shown and true or false
            if self.shown ~= was then
                local script = self.scripts[self.shown and "OnShow" or "OnHide"]
                if script then script(self) end
            end
        end,
        GetTextWidth = function() return 60 end,
        GetStringWidth = function() return 60 end,
        GetStringHeight = function() return 12 end,
        GetTextColor = function() return 0.35, 0.35, 0.35 end,
        GetVerticalScroll = function() return 0 end,
        GetVerticalScrollRange = function() return 0 end,
        SetupMenu = function(self, generator) self.generator = generator end,
        AddMessage = function(self, line) chat[#chat + 1] = line end,
        ContainsMessageGroup = function() return true end,
        Cancel = function(self) self.cancelled = true end,
        CreateTexture = function() return newRegion("Texture") end,
        CreateFontString = function() return newRegion("FontString") end,
        SetEnabled = function(self, enabled) self.disabled = not enabled end,
        SetColorTexture = function(self, r, g, b, a) self.colorTexture = { r, g, b, a } end,
        IsEnabled = function(self) return not self.disabled end,
        SetChecked = function(self, checked) self.checked = checked and true or false end,
        GetChecked = function(self) return self.checked or false end,
        SetFocus = function(self) focused = self end,
        ClearFocus = function(self) if focused == self then focused = nil end end,
    }
    setmetatable(r, {
        __index = function(t, k)
            if methods[k] then return methods[k] end
            if CHILDREN[k] then
                local child = newRegion("Region")
                rawset(t, k, child)
                return child
            end
            if type(k) == "string" and k:match("^%l") then return nil end
            return function(self) return self end
        end,
    })
    return r
end

function CreateFrame(kind, name, parent, template)
    local frame = newRegion(kind, template)
    if kind == "Frame" or kind == "Button" or kind == "EditBox" or kind == "DropdownButton" then
        frame.shown = true
    end
    created[#created + 1] = frame
    if name then _G[name] = frame end
    return frame
end

UIParent = newRegion("Frame")
-- Blizzard's quarter turns swap a texture's size and texture coordinates (Blizzard_SharedXMLBase/TextureUtil.lua).
function SetClampedTextureRotation(texture, degrees) texture.rotation = degrees end
DEFAULT_CHAT_FRAME = newRegion("ScrollingMessageFrame")
GameTooltip = newRegion("GameTooltip")
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tContains = function(t, item)
    for _, value in ipairs(t) do if value == item then return true end end
    return false
end
tDeleteItem = function(t, item)
    for i = #t, 1, -1 do if t[i] == item then table.remove(t, i) end end
end
strlower, strmatch = string.lower, string.match
date, time = os.date, os.time
local realPrint = print
print = function(line) chat[#chat + 1] = line end

-- === client globals the addon reads ===
local function color()
    return {
        WrapTextInColorCode = function(_, text) return text end,
        GetRGB = function() return 1, 1, 1 end,
    }
end
NORMAL_FONT_COLOR, HIGHLIGHT_FONT_COLOR, GRAY_FONT_COLOR = color(), color(), color()
GREEN_FONT_COLOR, RED_FONT_COLOR, WARNING_FONT_COLOR, YELLOW_FONT_COLOR = color(), color(), color(), color()
local function font() return { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12 end } end
GameFontNormalLarge, GameFontNormal, GameFontHighlight, GameFontDisable = font(), font(), font(), font()
LINK_FONT_COLOR = color()
SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT = 6
PANEL_INSET_LEFT_OFFSET, PANEL_INSET_RIGHT_OFFSET = 4, -6
PANEL_INSET_BOTTOM_OFFSET, PANEL_INSET_BOTTOM_BUTTON_OFFSET = 4, 26
PANEL_INSET_TOP_OFFSET, PANEL_INSET_ATTIC_OFFSET = -24, -60

ZONE, WHISPER, CHAT, RAID_WARNING = "Zone", "Whisper", "Chat", "Raid Warning"
SAVE, DELETE, CANCEL = "Save", "Delete", "Cancel"
TIMEMANAGER_LOCALTIME = "Use Local Time"
CHAT_WHISPER_GET = "%s whispers: "
CALENDAR_WEEKDAY_NAMES = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
ChatTypeInfo = { WHISPER = { r = 1, g = 0.5, b = 1, id = 7 }, SYSTEM = { r = 1, g = 1, b = 0, id = 1 }, RAID_WARNING = { r = 1, g = 0.3, b = 0, id = 9 } }
SOUNDKIT = { TELL_MESSAGE = 3081, RAID_WARNING = 8959 }
SlashCmdList = {}

function GetCVarBool(name) return name == "timeMgrUseLocalTime" and world.localTime end
function GetServerTime() return world.now end
function GetGameTime()
    local wall = os.date("!*t", world.now + REALM_OFFSET)
    return wall.hour, wall.min
end
function GetZoneText() return world.zone end
function GetSubZoneText() return world.subzone end
function PlaySound(id) sounds[#sounds + 1] = id end
function FlashClientIcon() end
function FCF_IterateActiveChatWindows(callback) callback(DEFAULT_CHAT_FRAME, 1) end
function GameTime_GetFormattedTime(hour, minute) return string.format("%02d:%02d", hour, minute) end
function SecondsToTime(seconds) return tostring(math.floor(seconds)) .. "s" end
RaidWarningUtil = { AddMessage = function(text) warnings[#warnings + 1] = text end }
C_ChatInfo = { ReplaceIconAndGroupExpressions = function(text) return text end }
C_Timer = {
    NewTicker = function(_, fn)
        local handle = newRegion("Ticker")
        handle.fn = fn
        ticker = ticker or handle
        return handle
    end,
}
FrameUtil = { RegisterFrameForEvents = function() end }
-- Blizzard's chat hands a clicked addon link to this callback (ItemRefHandlersShared.lua).
local linkCallbacks = {}
EventRegistry = {
    RegisterCallback = function(_, event, fn, owner)
        if event == "SetItemRef" then linkCallbacks[owner] = fn end
    end,
}
local function clickLink(link)
    for owner, fn in pairs(linkCallbacks) do fn(owner, link, "[link]", "LeftButton", DEFAULT_CHAT_FRAME) end
end
function GameTooltip_SetTitle() end
function GameTooltip_AddNormalLine() end
function GameTooltip_AddDisabledLine() end
function GameTooltip_AddInstructionLine() end
function GameTooltip_AddBlankLineToTooltip() end
function GameTooltip_AddColoredDoubleLine() end
GameTooltip_Hide = function() end
function ButtonFrameTemplate_HideAttic() end
function ButtonFrameTemplate_HideButtonBar() end
function MagicButton_OnLoad() end

-- === libraries: the real LibStub and LibNativeUI, fake broker and icon ===
local function load(path, ns)
    local chunk = assert(loadfile(ADDON .. path))
    chunk("RemindMe", ns)
end
load("Libs/LibStub/LibStub.lua")
load("Libs/LibNativeUI-1.0/LibNativeUI-1.0.lua")
local broker = LibStub:NewLibrary("LibDataBroker-1.1", 1)
function broker:NewDataObject(_, object) return object end
local icon = LibStub:NewLibrary("LibDBIcon-1.0", 1)
local registered = {}
function icon:IsRegistered(name) return registered[name] end
function icon:Register(name) registered[name] = true end
function icon:AddButtonToCompartment() end
function icon:Show() end
function icon:Hide() end

local ns = {}
for _, file in ipairs({
    "Core/Init.lua", "Core/Time.lua", "Core/Reminders.lua", "Core/Commands.lua",
    "UI/Panel.lua", "UI/MinimapButton.lua", "Bootstrap.lua",
}) do
    load(file, ns)
end

local Time, Reminders = ns.Time, ns.Reminders
local slash = SlashCmdList.REMINDME

-- Bootstrap's loader is the first frame Bootstrap created with a PLAYER_LOGIN script.
local function fire(frame, event, ...) frame.scripts.OnEvent(frame, event, ...) end
local loader, events
for _, frame in ipairs(created) do
    if frame.scripts.OnEvent then loader = loader or frame end
end
fire(loader, "PLAYER_LOGIN")
for _, frame in ipairs(created) do
    if frame.scripts.OnEvent and frame ~= loader then events = frame end
end
check("events frame created at login", events ~= nil)
fire(events, "PLAYER_ENTERING_WORLD", true, false)
check("ticker started on entering the world", ticker ~= nil)

local db = RemindMeDB
local function tick(seconds)
    world.now = world.now + (seconds or 0)
    ticker.fn()
end
local function last() return chat[#chat] or "" end
local function starts(line, prefix) return line:sub(1, #prefix) == prefix end
local function hasSnooze(line) return line:find("|Haddon:RemindMe:snooze:", 1, true) ~= nil end
local function reset()
    Reminders.Clear()
    chat, warnings, sounds = {}, {}, {}
    world.now = NOW
end

-- === durations ===
local function duration(text) return Time.ParseDuration(text) end
check("30m", duration("30m") == 1800)
check("1h 30m", duration("1h 30m") == 5400)
check("1h30m", duration("1h30m") == 5400)
check("bare number is minutes", duration("90") == 5400)
check("90s", duration("90s") == 90)
check("2 hours", duration("2 hours") == 7200)
check("zero is no duration", duration("0") == nil)
check("word is no duration", duration("soon") == nil)
check("trailing word is no duration", duration("30m tea") == nil)

-- === times of day ===
local function clock(text) return { Time.ParseClock(text) } end
local function same(a, b) return a[1] == b[1] and a[2] == b[2] end
check("20:30", same(clock("20:30"), { 20, 30 }))
check("20.30", same(clock("20.30"), { 20, 30 }))
check("8pm", same(clock("8pm"), { 20, 0 }))
check("8 pm", same(clock("8 pm"), { 20, 0 }))
check("8:30PM", same(clock("8:30PM"), { 20, 30 }))
check("12am is midnight", same(clock("12am"), { 0, 0 }))
check("12pm is noon", same(clock("12pm"), { 12, 0 }))
check("20 alone", same(clock("20"), { 20, 0 }))
check("24:00 refused", clock("24:00")[1] == nil)
check("13pm refused", clock("13pm")[1] == nil)
check("8:61 refused", clock("8:61")[1] == nil)
check("8xm refused", clock("8xm")[1] == nil)
local _, _, after = Time.TakeClock({ "8", "pm", "Raid" }, 1)
check("8 pm consumes two words", after == 3)
_, _, after = Time.TakeClock({ "8", "Raid" }, 1)
check("8 then text consumes one word", after == 2)

-- === next occurrence ===
check("realm offset read from GetGameTime", Time.RealmOffset(NOW) == REALM_OFFSET)
local realmDaily = { kind = "clock", hour = 20, minute = 0, realm = true, rep = true }
local due = Time.NextClock(realmDaily, NOW)
local wall = os.date("!*t", due + REALM_OFFSET)
check("realm daily lands on 20:00 realm", wall.hour == 20 and wall.min == 0)
check("realm daily is within a day", due > NOW and due - NOW <= 86400)
-- GetGameTime always reads the current moment, so the clock moves with the argument.
world.now = due
check("due moment itself moves to the next day", Time.NextClock(realmDaily, due) == due + 86400)
world.now = NOW

local realmMonday = { kind = "clock", hour = 19, minute = 45, realm = true, rep = { 2 } }
due = Time.NextClock(realmMonday, NOW)
wall = os.date("!*t", due + REALM_OFFSET)
check("weekly lands on a realm Monday", wall.wday == 2 and wall.hour == 19 and wall.min == 45)
check("weekly is within a week", due > NOW and due - NOW <= 7 * 86400)
local realmMonFri = { kind = "clock", hour = 19, minute = 45, realm = true, rep = { 2, 6 } }
local monFriDue, monFriDay = Time.NextClock(realmMonFri, NOW)
check("several weekdays take the nearest", monFriDay == 6 and monFriDue < due)

local localDaily = { kind = "clock", hour = 6, minute = 15, realm = false, rep = false }
due = Time.NextClock(localDaily, NOW)
wall = os.date("*t", due)
check("local lands on 06:15 local", wall.hour == 6 and wall.min == 15)
check("local is within a day", due > NOW and due - NOW <= 86400 + 3600)

-- === adding and firing ===
reset()
local r = Reminders.Add({ kind = "timer", seconds = 60, text = "  Tea  ", output = "whisper" })
check("timer stored", #db.reminders == 1 and r.text == "Tea" and r.due == NOW + 60)
check("Add refuses empty text", select(2, Reminders.Add({ kind = "timer", seconds = 60, text = " " })) == ns.NEED_TEXT)
check("Add refuses empty zone", select(2, Reminders.Add({ kind = "zone", zone = " ", text = "x" })) == ns.NEED_ZONE)
tick(59)
check("not due early", #db.reminders == 1 and #chat == 0)
tick(1)
check("whisper delivered", starts(last(), "[Remind Me Later] whispers: Tea ") and sounds[1] == SOUNDKIT.TELL_MESSAGE)
check("a fired whisper carries the snooze link", hasSnooze(last()))
check("one-time removed after firing", #db.reminders == 0)

reset()
Reminders.Add({ kind = "timer", seconds = 30, text = "Stretch", output = "print", rep = true })
tick(30)
check("system line delivered", starts(last(), "[Remind Me Later]: Stretch ") and hasSnooze(last()))
check("repeating timer restarts", #db.reminders == 1 and db.reminders[1].due == NOW + 60)

reset()
Reminders.Add({ kind = "timer", seconds = 5, text = "Pull {star}", output = "warning" })
tick(5)
check("warning shows centre text and chat line", warnings[1] == "Pull {star}" and starts(last(), "[Remind Me Later]: Pull {star} "))
check("the snooze link stays out of the centre text", hasSnooze(last()) and not hasSnooze(warnings[1]))
check("warning plays the raid warning sound", sounds[1] == SOUNDKIT.RAID_WARNING)

reset()
Reminders.Add({ kind = "clock", hour = 20, minute = 0, realm = true, rep = true, text = "Raid", output = "whisper" })
local first = db.reminders[1].due
world.now = first
tick()
check("daily clock fires and reschedules", last():find("Raid") and db.reminders[1].due == first + 86400)

-- === zones ===
reset()
world.zone, world.subzone = "Stormwind City", "Trade District"
Reminders.Add({ kind = "zone", zone = "stormwind", text = "Reagents", output = "print", rep = true })
fire(events, "ZONE_CHANGED")
check("standing in the zone when adding is no entry", #chat == 0)
world.zone, world.subzone = "Elwynn Forest", ""
fire(events, "ZONE_CHANGED_NEW_AREA")
world.zone, world.subzone = "Stormwind City", "Cathedral Square"
fire(events, "ZONE_CHANGED_NEW_AREA")
check("entering fires, partial name matches", starts(last(), "[Remind Me Later]: Reagents "))
fire(events, "ZONE_CHANGED")
check("moving inside the zone does not fire again", #chat == 1)
world.zone = ""
fire(events, "ZONE_CHANGED_NEW_AREA")
world.zone = "Stormwind City"
fire(events, "ZONE_CHANGED_NEW_AREA")
check("an empty zone name around loading is no exit", #chat == 1)
world.zone = "Elwynn Forest"
fire(events, "ZONE_CHANGED_NEW_AREA")
world.zone = "Stormwind City"
fire(events, "PLAYER_ENTERING_WORLD", false, true)
check("a reload inside the zone is no entry", #chat == 1)

reset()
world.zone, world.subzone = "Ironforge", "The Commons"
Reminders.Add({ kind = "zone", zone = "Trade District", text = "Sell", output = "print" })
world.subzone = "Trade District"
fire(events, "ZONE_CHANGED")
check("subzone match fires once and removes a one-time reminder", starts(last(), "[Remind Me Later]: Sell ") and #db.reminders == 0)

-- === weekdays ===
reset()
r = Reminders.Add({ kind = "clock", hour = 19, minute = 45, realm = true, rep = { 4, 2, 4 }, text = "Raid", output = "print" })
check("weekdays stored once each in week order", #r.rep == 2 and r.rep[1] == 2 and r.rep[2] == 4)
check("weekdays read as a sentence", Reminders.Describe(r, NOW):find("every Monday and Wednesday at 19:45 realm time, next in", 1, true) ~= nil)
r = Reminders.Add({ kind = "clock", hour = 9, minute = 0, realm = true, rep = { 1, 2, 3, 4, 5, 6, 7 }, text = "All", output = "print" })
check("all seven weekdays are every day", r.rep == true)
r = Reminders.Add({ kind = "clock", hour = 9, minute = 0, realm = true, rep = {}, text = "None", output = "print" })
check("no weekday is once", r.rep == false)
r = Reminders.Add({ kind = "clock", hour = 9, minute = 0, realm = true, rep = { 2, 4, 6 }, text = "Three", output = "print" })
check("three weekdays read with commas", Reminders.Describe(r, NOW):find("every Monday, Wednesday and Friday at", 1, true) ~= nil)

-- === snooze ===
reset()
Reminders.Add({ kind = "timer", seconds = 5, text = "Tea", output = "print" })
tick(5)
local link = last():match("|H(addon:RemindMe:snooze:[%d:]+)|h")
check("the fired line links a snooze", link ~= nil and #db.reminders == 0)
clickLink(link)
r = db.reminders[1]
check("snooze adds the reminder again as a one-time countdown", #db.reminders == 1 and r.kind == "timer"
    and r.seconds == ns.SNOOZE and r.due == world.now + ns.SNOOZE and r.text == "Tea" and r.output == "print" and r.rep == false)
check("snooze confirms in one line", last():find("Snoozed for", 1, true) ~= nil)
clickLink(link)
check("a link snoozes once", #db.reminders == 1 and last():find("Already snoozed", 1, true) ~= nil)
clickLink("addon:RemindMe:snooze:1:1")
check("a link from before a reload is refused", #db.reminders == 1 and last():find("reload", 1, true) ~= nil)
local before = #chat
clickLink("item:6948")
check("other links are left alone", #chat == before)

-- === catch-up at login ===
reset()
db.reminders = {
    { id = 101, kind = "timer", seconds = 600, text = "Missed once", output = "print", rep = false, due = NOW - 3600 },
    { id = 102, kind = "timer", seconds = 600, text = "Missed repeat", output = "print", rep = true, due = NOW - 3600 },
    { id = 103, kind = "timer", seconds = 600, text = "Reload repeat", output = "print", rep = true, due = NOW - 10 },
}
Reminders.Start()
check("long-missed repeat is rescheduled silently", db.reminders[2].due == NOW + 600)
tick()
check("one-time missed reminder fires", table.concat(chat, "|"):find("Missed once", 1, true) ~= nil)
check("repeat missed by seconds still fires", table.concat(chat, "|"):find("Reload repeat", 1, true) ~= nil)
check("long-missed repeat does not fire", table.concat(chat, "|"):find("Missed repeat", 1, true) == nil)

reset()
db.reminders = { { id = 201, kind = "clock", hour = 19, minute = 45, realm = true, rep = 2, text = "Old weekly", output = "print" } }
Reminders.Start()
check("a weekday saved as a number becomes a list", type(db.reminders[1].rep) == "table" and db.reminders[1].rep[1] == 2)

-- === slash commands ===
reset()
slash("in 1h 30m tea")
check("/rm in adds a whisper countdown", #db.reminders == 1 and db.reminders[1].seconds == 5400 and db.reminders[1].output == "whisper")
check("/rm in confirms in one line", last():find("Added: tea", 1, true) ~= nil)

reset()
slash("at 19:45 warning monday Raid tonight")
r = db.reminders[1]
check("/rm at with options", r and r.kind == "clock" and r.output == "warning" and r.text == "Raid tonight")
check("/rm at takes one weekday", type(r.rep) == "table" and #r.rep == 1 and r.rep[1] == 2)
slash("at 19:45 monday wed Two nights")
r = db.reminders[2]
check("/rm at takes several weekdays", type(r.rep) == "table" and #r.rep == 2 and r.rep[1] == 2 and r.rep[2] == 4 and r.text == "Two nights")
slash("at 9 mon tue wed thu fri sat sun Every day")
check("/rm at with all weekdays is every day", db.reminders[3].rep == true)
slash("at 9 daily monday Daily wins")
check("/rm at daily wins over a weekday", db.reminders[4].rep == true)
check("/rm at follows the realm clock setting", r.realm == true)

reset()
world.localTime = true
slash("at 8 pm daily Dailies")
r = db.reminders[1]
check("/rm at 8 pm daily on local clock", r and r.hour == 20 and r.rep == true and r.realm == false and r.text == "Dailies")
slash("at 8 pm realm Realm one")
check("realm option overrides the setting", db.reminders[2].realm == true)
world.localTime = false

reset()
slash("zone Stormwind City: print repeat Buy reagents")
r = db.reminders[1]
check("/rm zone with colon", r and r.zone == "Stormwind City" and r.output == "print" and r.rep == true and r.text == "Buy reagents")
slash("zone Orgrimmar Visit the bank")
check("/rm zone without colon takes one word", db.reminders[2].zone == "Orgrimmar" and db.reminders[2].text == "Visit the bank")
world.zone = "Darnassus"
slash("here Feed the cat")
check("/rm here uses the current zone", db.reminders[3].zone == "Darnassus")

reset()
slash("in tea")
check("/rm in without a duration explains", last():find(ns.NEED_DURATION, 1, true) ~= nil and #db.reminders == 0)
slash("at 25:00 x")
check("/rm at with a bad time explains", last():find(ns.NEED_CLOCK, 1, true) ~= nil)
slash("in 5m")
check("/rm in without text explains", last():find(ns.NEED_TEXT, 1, true) ~= nil)
slash("in 5m monday tea")
check("weekday on a countdown refused", last():find("Weekdays", 1, true) ~= nil and #db.reminders == 0)
slash("bogus")
check("unknown command points to help", last():find("/rm help", 1, true) ~= nil)

reset()
slash("in 10m First")
slash("in 5m Second")
slash("list")
check("/rm list sorts by due time", chat[#chat - 1]:find("^1%. Second") and last():find("^2%. First"))
slash("test 1")
check("/rm test shows without removing", last() == "[Remind Me Later] whispers: Second" and #db.reminders == 2)
slash("remove 1")
check("/rm remove takes the list number", #db.reminders == 1 and db.reminders[1].text == "First")
slash("remove 9")
check("/rm remove with a bad number explains", last():find("/rm list", 1, true) ~= nil)
slash("clear")
check("/rm clear empties", #db.reminders == 0)
slash("help")
check("/rm help prints the commands", #chat > 8)
slash("minimap")
check("/rm minimap hides the button", db.minimap.hide == true)
slash("minimap")
check("/rm minimap shows it again", db.minimap.hide == false)

-- === field text for editing ===
check("duration field reads 1h 30m", Time.FormatDuration(5400) == "1h 30m")
check("duration field reads 1m 30s", Time.FormatDuration(90) == "1m 30s")
check("duration field parses back", Time.ParseDuration(Time.FormatDuration(3725)) == 3725)
check("clock field parses back", Time.FormatClockField(20, 30) == "20:30")

-- === editing in place ===
reset()
r = Reminders.Add({ kind = "timer", seconds = 600, text = "Old", output = "whisper" })
local id, due0 = r.id, r.due
world.now = NOW + 100
check("edit refuses empty text", Reminders.Update(r, { kind = "timer", seconds = 600, text = " " }) == nil and r.text == "Old")
Reminders.Update(r, { kind = "timer", seconds = 600, text = "New text", output = "print" })
check("text edit keeps the countdown running", r.id == id and r.due == due0 and r.text == "New text" and r.output == "print")
Reminders.Update(r, { kind = "timer", seconds = 60, text = "New text", output = "print" })
check("new length restarts the countdown", r.due == NOW + 160)
world.zone = "Stormwind City"
Reminders.Update(r, { kind = "zone", zone = "Stormwind", text = "Now a zone", output = "print" })
check("trigger change clears old fields", r.kind == "zone" and r.due == nil and r.seconds == nil and r.zone == "Stormwind")
fire(events, "ZONE_CHANGED")
check("edited into the current zone is no entry", #chat == 0 and #db.reminders == 1)
Reminders.Update(r, { kind = "clock", hour = 21, minute = 0, realm = true, rep = true, text = "Now a time", output = "print" })
check("zone to time of day schedules it", r.due and r.due > world.now and r.zone == nil)

-- === window ===
reset()
slash("")
local window = RemindMeFrame
check("/rm opens the window", window and window.shown)
local boxes, bar = {}, {}
for _, frame in ipairs(created) do
    if frame.template == "InputBoxInstructionsTemplate" then boxes[#boxes + 1] = frame end
    if frame.template == "MagicButtonTemplate" then bar[#bar + 1] = frame end
end
local textBox, valueBox = boxes[1], boxes[2]
local saveButton, newButton, deleteButton = bar[1], bar[2], bar[3]
local kinds, outputs, days = window.kindRadios, window.outputRadios, window.dayChecks
local timerRepeat, zoneRepeat = window.repeatChecks.timer, window.repeatChecks.zone
local preview, dialog = window.preview, window.deleteDialog
local hereButton
for _, frame in ipairs(created) do
    if frame.text == "Current Zone" then hereButton = frame end
end

local function rows()
    local found = {}
    for _, frame in ipairs(created) do
        if frame.kind == "Button" and frame.reminder and frame.shown then found[#found + 1] = frame end
    end
    table.sort(found, function(a, b) return (a.reminder.due or math.huge) < (b.reminder.due or math.huge) end)
    return found
end

-- A CheckButton flips itself before its OnClick, as the client does.
local function click(button)
    if button.kind == "CheckButton" then button.checked = not button.checked end
    button.scripts.OnClick(button)
end

-- Typing sets the text and fires the hooked OnTextChanged as user input.
local function typeInto(box, text)
    box.text = text
    box.hooks.OnTextChanged(box, true)
end

local bareInsets, insets = true, 0
for _, frame in ipairs(created) do
    if frame.template == "InsetFrameTemplate" then
        insets = insets + 1
        if frame.Bg.shown then bareInsets = false end
    end
end
local background = window.Background
check("both columns sit on one brown panel, its corners hidden", background.template == "CollectionsBackgroundTemplate"
    and not background.BGCornerTopLeft.shown and not background.BGCornerBottomRight.shown
    and not window.Inset.Bg.shown and not window.Inset.NineSlice.shown)
check("the window keeps its stone, only the status box is an inset", window.Bg.colorTexture == nil and bareInsets and insets == 1, insets)
check("a new reminder is the start", saveButton.text == "Add Reminder" and window.help.text:find("Fill in", 1, true))
check("the message takes the keyboard on open", focused == textBox)
check("New and Delete wait for a selection", newButton.disabled and deleteButton.disabled)
check("Add waits for a complete form", saveButton.disabled)
check("the picks start on Countdown and Whisper", kinds.timer.checked and not kinds.clock.checked and outputs.whisper.checked)
check("a countdown shows Repeat, not the clock or the weekdays", timerRepeat.shown and not window.localCheck.shown and not hereButton.shown)
check("the empty preview says what a countdown does", preview.text == "Fires once the countdown runs out.")

typeInto(textBox, "Check mail")
typeInto(valueBox, "soon")
check("an unreadable countdown shows in the preview", preview.text == ns.NEED_DURATION and saveButton.disabled)
window:SaveForm()
check("an incomplete form adds nothing and points at the value", #db.reminders == 0 and focused == valueBox)
typeInto(valueBox, "15m")
check("a readable countdown previews its time", preview.text == "Fires in 900s." and not saveButton.disabled)
click(timerRepeat)
check("Repeat previews the next turns", preview.text == "Fires in 900s, then every 900s.")
click(timerRepeat)
window:SaveForm()
check("form adds a countdown", #db.reminders == 1 and db.reminders[1].seconds == 900 and db.reminders[1].output == "whisper" and db.reminders[1].rep == false)
check("form clears its fields and confirms", textBox.text == "" and valueBox.text == "" and window.status.text == "Added.")
typeInto(textBox, "x")
check("typing clears the confirmation", window.status.text ~= "Added.")
typeInto(textBox, "")

-- Time of Day with weekdays.
click(kinds.clock)
check("Time of Day shows the clock and the weekdays", window.localCheck.shown and not timerRepeat.shown and kinds.clock.checked and not kinds.timer.checked)
check("the value hint follows the trigger", valueBox.Instructions.text == "20:30 or 8:30 PM")
click(kinds.clock)
check("clicking the picked radio keeps it picked", kinds.clock.checked)
typeInto(textBox, "Raid")
typeInto(valueBox, "19:45")
click(days[2])
click(days[4])
check("a time previews its next day", preview.text:find("Next: Wednesday at 19:45 realm time", 1, true) ~= nil)
click(window.localCheck)
check("Use Local Time drops the realm clock", preview.text:find("Next: Wednesday at 19:45, in", 1, true) ~= nil)
click(window.localCheck)
click(outputs.warning)
check("an output radio picks one output", outputs.warning.checked and not outputs.whisper.checked)
window:SaveForm()
r = db.reminders[2]
check("ticked weekdays are stored", r and r.kind == "clock" and r.realm == true and #r.rep == 2 and r.rep[1] == 2 and r.rep[2] == 4 and r.output == "warning")
check("picks stay for the next reminder", kinds.clock.checked and days[2].checked and outputs.warning.checked)
for _, wday in ipairs(ns.WEEK_ORDER) do
    if not days[wday].checked then click(days[wday]) end
end
typeInto(textBox, "Every day")
typeInto(valueBox, "6:00")
window:SaveForm()
check("all weekdays ticked is every day", db.reminders[3].rep == true)

-- Zone with the current zone and Every Time.
click(kinds.zone)
check("a zone shows Current Zone and clears the weekdays", hereButton.shown and not days[2].checked and preview.text == "Fires when you enter this zone or an area in it.")
click(hereButton)
check("Current Zone fills the field", valueBox.text == world.zone)
-- The client fires OnTextChanged for text set from code too, with userInput false.
valueBox.hooks.OnTextChanged(valueBox, false)
check("a zone previews its next entry", preview.text == "Fires the next time you enter " .. world.zone .. ".")
click(zoneRepeat)
check("Every Time previews every entry", preview.text == "Fires every time you enter " .. world.zone .. ".")
typeInto(textBox, "Home")
window:SaveForm()
check("a zone with Every Time is stored", db.reminders[4].kind == "zone" and db.reminders[4].rep == true)

-- Editing.
reset()
click(kinds.timer)
click(outputs.whisper)
slash("in 15m Check mail")
slash("at 20:30 print daily Raid")
check("the list shows both reminders", #rows() == 2)
local mail = rows()[1]
click(mail)
check("clicking a row loads it", textBox.text == "Check mail" and valueBox.text == "15m" and kinds.timer.checked)
check("a selection switches to editing", saveButton.text == "Save" and window.help.text:find("Changes save", 1, true))
check("New and Delete turn on", not newButton.disabled and not deleteButton.disabled)
check("the row shows as selected", mail.selection.shown and not mail.hover.shown)

local mailReminder, mailDue = mail.reminder, mail.reminder.due
world.now = NOW + 60
typeInto(textBox, "Check the mailbox")
window:SaveForm()
check("Save edits in place", #db.reminders == 2 and mailReminder.text == "Check the mailbox" and mailReminder.due == mailDue)
check("Save stays on the reminder and confirms", saveButton.text == "Save" and window.status.text == "Saved.")
typeInto(valueBox, "1h")
window:SaveForm()
check("a new countdown restarts on Save", mailReminder.due == world.now + 3600)

-- Rows are pooled frames, so a refresh may give a frame another reminder. Keep the reminder.
typeInto(textBox, "Mail again")
local raid = rows()[2].reminder
click(rows()[2])
check("switching rows keeps the changes, as the macro window does", mailReminder.text == "Mail again")
check("a daily time ticks every weekday", raid.kind == "clock" and valueBox.text == "20:30" and days[2].checked and days[1].checked)

typeInto(valueBox, "25:99")
click(rows()[1])
check("an unreadable change is dropped on switching", raid.hour == 20 and raid.minute == 30)

typeInto(textBox, "Closed edit")
slash("")
check("closing keeps the changes", mailReminder.text == "Closed edit")
slash("")

newButton.scripts.OnClick(newButton)
check("New Reminder empties the editor", textBox.text == "" and valueBox.text == "" and saveButton.text == "Add Reminder")
check("New Reminder clears the selection and takes the keyboard", not rows()[1].selection.shown and focused == textBox)

local target = rows()[1]
click(target)
local deleting = target.reminder
click(deleteButton)
check("Delete asks first and names the reminder", dialog.shown and dialog.subject.text == deleting.text and #db.reminders == 2)
click(dialog.cancelButton)
check("Cancel keeps the reminder", not dialog.shown and #db.reminders == 2 and saveButton.text == "Save")
click(deleteButton)
click(dialog.deleteButton)
check("Delete removes the selected reminder", #db.reminders == 1 and not tContains(db.reminders, deleting))
check("Delete returns to a new reminder", saveButton.text == "Add Reminder" and deleteButton.disabled and not dialog.shown)

reset()
slash("in 5m Tea")
local tea = rows()[1]
click(tea)
tick(300)
check("a fired reminder leaves the editor, its text stays", saveButton.text == "Add Reminder" and textBox.text == "Tea")

slash("")
check("/rm closes the window", not window.shown)
slash("in 5m First")
slash("in 10m Second")
slash("edit 2")
check("/rm edit opens the window on that reminder", window.shown and textBox.text == "Second" and saveButton.text == "Save")
slash("edit 9")
check("/rm edit with a bad number explains", last():find("/rm list", 1, true) ~= nil)
print = realPrint
print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
