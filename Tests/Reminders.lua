-- Loads every addon file in toc order against a small client stub, then checks parsing, scheduling,
-- catch-up, delivery, zone entry, every slash command and a smoke run of the window.
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
local ticker

-- === frame stub: unknown methods record and chain, a few keep state ===
local CHILDREN = { Instructions = true, ScrollBar = true, Inset = true, Text = true }
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
DEFAULT_CHAT_FRAME = newRegion("ScrollingMessageFrame")
GameTooltip = newRegion("GameTooltip")
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
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
GameFontNormalLarge, GameFontNormal, GameFontHighlight, GameFontDisable = {}, {}, {}, {}
SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT = 6
PANEL_INSET_LEFT_OFFSET, PANEL_INSET_RIGHT_OFFSET = 4, -6
PANEL_INSET_BOTTOM_OFFSET, PANEL_INSET_BOTTOM_BUTTON_OFFSET = 4, 26

ZONE, WHISPER, CHAT, RAID_WARNING = "Zone", "Whisper", "Chat", "Raid Warning"
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
    chunk("SimpleReminders", ns)
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
local slash = SlashCmdList.SIMPLEREMINDERS

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

local db = SimpleRemindersDB
local function tick(seconds)
    world.now = world.now + (seconds or 0)
    ticker.fn()
end
local function last() return chat[#chat] or "" end
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

local realmMonday = { kind = "clock", hour = 19, minute = 45, realm = true, rep = 2 }
due = Time.NextClock(realmMonday, NOW)
wall = os.date("!*t", due + REALM_OFFSET)
check("weekly lands on a realm Monday", wall.wday == 2 and wall.hour == 19 and wall.min == 45)
check("weekly is within a week", due > NOW and due - NOW <= 7 * 86400)

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
check("whisper delivered", last() == "[Simple Reminders] whispers: Tea" and sounds[1] == SOUNDKIT.TELL_MESSAGE)
check("one-time removed after firing", #db.reminders == 0)

reset()
Reminders.Add({ kind = "timer", seconds = 30, text = "Stretch", output = "print", rep = true })
tick(30)
check("system line delivered", last() == "[Simple Reminders]: Stretch")
check("repeating timer restarts", #db.reminders == 1 and db.reminders[1].due == NOW + 60)

reset()
Reminders.Add({ kind = "timer", seconds = 5, text = "Pull {star}", output = "warning" })
tick(5)
check("warning shows centre text and chat line", warnings[1] == "Pull {star}" and last() == "[Simple Reminders]: Pull {star}")
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
check("entering fires, partial name matches", last() == "[Simple Reminders]: Reagents")
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
check("subzone match fires once and removes a one-time reminder", last() == "[Simple Reminders]: Sell" and #db.reminders == 0)

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

-- === slash commands ===
reset()
slash("in 1h 30m tea")
check("/sr in adds a whisper countdown", #db.reminders == 1 and db.reminders[1].seconds == 5400 and db.reminders[1].output == "whisper")
check("/sr in confirms in one line", last():find("Added: tea", 1, true) ~= nil)

reset()
slash("at 19:45 warning monday Raid tonight")
r = db.reminders[1]
check("/sr at with options", r and r.kind == "clock" and r.output == "warning" and r.rep == 2 and r.text == "Raid tonight")
check("/sr at follows the realm clock setting", r.realm == true)

reset()
world.localTime = true
slash("at 8 pm daily Dailies")
r = db.reminders[1]
check("/sr at 8 pm daily on local clock", r and r.hour == 20 and r.rep == true and r.realm == false and r.text == "Dailies")
slash("at 8 pm realm Realm one")
check("realm option overrides the setting", db.reminders[2].realm == true)
world.localTime = false

reset()
slash("zone Stormwind City: print repeat Buy reagents")
r = db.reminders[1]
check("/sr zone with colon", r and r.zone == "Stormwind City" and r.output == "print" and r.rep == true and r.text == "Buy reagents")
slash("zone Orgrimmar Visit the bank")
check("/sr zone without colon takes one word", db.reminders[2].zone == "Orgrimmar" and db.reminders[2].text == "Visit the bank")
world.zone = "Darnassus"
slash("here Feed the cat")
check("/sr here uses the current zone", db.reminders[3].zone == "Darnassus")

reset()
slash("in tea")
check("/sr in without a duration explains", last():find(ns.NEED_DURATION, 1, true) ~= nil and #db.reminders == 0)
slash("at 25:00 x")
check("/sr at with a bad time explains", last():find(ns.NEED_CLOCK, 1, true) ~= nil)
slash("in 5m")
check("/sr in without text explains", last():find(ns.NEED_TEXT, 1, true) ~= nil)
slash("in 5m monday tea")
check("weekday on a countdown refused", last():find("Weekdays", 1, true) ~= nil and #db.reminders == 0)
slash("bogus")
check("unknown command points to help", last():find("/sr help", 1, true) ~= nil)

reset()
slash("in 10m First")
slash("in 5m Second")
slash("list")
check("/sr list sorts by due time", chat[#chat - 1]:find("^1%. Second") and last():find("^2%. First"))
slash("test 1")
check("/sr test shows without removing", last() == "[Simple Reminders] whispers: Second" and #db.reminders == 2)
slash("remove 1")
check("/sr remove takes the list number", #db.reminders == 1 and db.reminders[1].text == "First")
slash("remove 9")
check("/sr remove with a bad number explains", last():find("/sr list", 1, true) ~= nil)
slash("clear")
check("/sr clear empties", #db.reminders == 0)
slash("help")
check("/sr help prints the commands", #chat > 8)
slash("minimap")
check("/sr minimap hides the button", db.minimap.hide == true)
slash("minimap")
check("/sr minimap shows it again", db.minimap.hide == false)

-- === window smoke run ===
reset()
slash("")
local window = SimpleRemindersFrame
check("/sr opens the window", window and window.shown)
local boxes = {}
for _, frame in ipairs(created) do
    if frame.template == "InputBoxInstructionsTemplate" then boxes[#boxes + 1] = frame end
end
local textBox, valueBox = boxes[1], boxes[2]
window:AddFromForm()
check("empty form names the text first", #db.reminders == 0)
textBox.text = "Check mail"
valueBox.text = "soon"
window:AddFromForm()
check("bad countdown refused", #db.reminders == 0)
valueBox.text = "15m"
window:AddFromForm()
check("form adds a countdown", #db.reminders == 1 and db.reminders[1].seconds == 900 and db.reminders[1].output == "whisper")
check("form clears its fields", textBox.text == "" and valueBox.text == "")
window:RefreshTimes()
tick(900)
check("firing refreshes the open window", #db.reminders == 0)
slash("")
check("/sr closes the window", not window.shown)

print = realPrint
print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
