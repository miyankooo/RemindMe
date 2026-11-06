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
        CreateTexture = function() return newRegion("Texture") end,
        CreateFontString = function() return newRegion("FontString") end,
        SetEnabled = function(self, enabled) self.disabled = not enabled end,
        IsEnabled = function(self) return not self.disabled end,
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
GameFontNormalLarge, GameFontNormal, GameFontHighlight, GameFontDisable = {}, {}, {}, {}
SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT = 6
PANEL_INSET_LEFT_OFFSET, PANEL_INSET_RIGHT_OFFSET = 4, -6
PANEL_INSET_BOTTOM_OFFSET, PANEL_INSET_BOTTOM_BUTTON_OFFSET = 4, 26
PANEL_INSET_TOP_OFFSET, PANEL_INSET_ATTIC_OFFSET = -24, -60

ZONE, WHISPER, CHAT, RAID_WARNING = "Zone", "Whisper", "Chat", "Raid Warning"
SAVE, DELETE = "Save", "Delete"
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
check("whisper delivered", last() == "[Remind Me Later] whispers: Tea" and sounds[1] == SOUNDKIT.TELL_MESSAGE)
check("one-time removed after firing", #db.reminders == 0)

reset()
Reminders.Add({ kind = "timer", seconds = 30, text = "Stretch", output = "print", rep = true })
tick(30)
check("system line delivered", last() == "[Remind Me Later]: Stretch")
check("repeating timer restarts", #db.reminders == 1 and db.reminders[1].due == NOW + 60)

reset()
Reminders.Add({ kind = "timer", seconds = 5, text = "Pull {star}", output = "warning" })
tick(5)
check("warning shows centre text and chat line", warnings[1] == "Pull {star}" and last() == "[Remind Me Later]: Pull {star}")
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
check("entering fires, partial name matches", last() == "[Remind Me Later]: Reagents")
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
check("subzone match fires once and removes a one-time reminder", last() == "[Remind Me Later]: Sell" and #db.reminders == 0)

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
check("/rm in adds a whisper countdown", #db.reminders == 1 and db.reminders[1].seconds == 5400 and db.reminders[1].output == "whisper")
check("/rm in confirms in one line", last():find("Added: tea", 1, true) ~= nil)

reset()
slash("at 19:45 warning monday Raid tonight")
r = db.reminders[1]
check("/rm at with options", r and r.kind == "clock" and r.output == "warning" and r.rep == 2 and r.text == "Raid tonight")
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
local function rows()
    local found = {}
    for _, frame in ipairs(created) do
        if frame.kind == "Button" and frame.reminder and frame.shown then found[#found + 1] = frame end
    end
    table.sort(found, function(a, b) return (a.reminder.due or math.huge) < (b.reminder.due or math.huge) end)
    return found
end

check("a new reminder is the start", saveButton.text == "Add Reminder" and window.help.text:find("Fill in", 1, true))
check("New and Delete wait for a selection", newButton.disabled and deleteButton.disabled)
window:SaveForm()
check("empty form names the text first", #db.reminders == 0)
textBox.text = "Check mail"
valueBox.text = "soon"
window:SaveForm()
check("bad countdown refused", #db.reminders == 0)
valueBox.text = "15m"
window:SaveForm()
check("form adds a countdown", #db.reminders == 1 and db.reminders[1].seconds == 900 and db.reminders[1].output == "whisper")
check("form clears its fields", textBox.text == "" and valueBox.text == "")
slash("at 20:30 print daily Raid")
check("the list shows both reminders", #rows() == 2)

local mail = rows()[1]
mail.scripts.OnClick(mail)
check("clicking a row loads it", textBox.text == "Check mail" and valueBox.text == "15m")
check("a selection switches to editing", saveButton.text == "Save" and window.help.text:find("Change", 1, true))
check("New and Delete turn on", not newButton.disabled and not deleteButton.disabled)
check("the row shows as selected", mail.selection.shown and not mail.hover.shown)

local mailReminder, mailDue = mail.reminder, mail.reminder.due
world.now = NOW + 60
textBox.text = "Check the mailbox"
window:SaveForm()
check("Save edits in place", #db.reminders == 2 and mailReminder.text == "Check the mailbox" and mailReminder.due == mailDue)
check("Save stays on the reminder", saveButton.text == "Save" and rows()[1].reminder == mailReminder)
valueBox.text = "1h"
window:SaveForm()
check("a new countdown restarts on Save", mailReminder.due == world.now + 3600)

local raid = rows()[2]
raid.scripts.OnClick(raid)
check("a time of day loads its time", raid.reminder.kind == "clock" and valueBox.text == "20:30" and textBox.text == "Raid")

newButton.scripts.OnClick(newButton)
check("New Reminder empties the editor", textBox.text == "" and valueBox.text == "" and saveButton.text == "Add Reminder")
check("New Reminder clears the selection", not raid.selection.shown)

local target = rows()[1]
target.scripts.OnClick(target)
local deleting = target.reminder
deleteButton.scripts.OnClick(deleteButton)
check("Delete removes the selected reminder", #db.reminders == 1 and not tContains(db.reminders, deleting))
check("Delete returns to a new reminder", saveButton.text == "Add Reminder" and deleteButton.disabled)

reset()
slash("in 5m Tea")
local tea = rows()[1]
tea.scripts.OnClick(tea)
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
