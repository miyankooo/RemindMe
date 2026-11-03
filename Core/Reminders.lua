local _, ns = ...

local Time = ns.Time

local Reminders = {}
ns.Reminders = Reminders

-- Problems the window and /sr report in the same words.
ns.NEED_TEXT = "Type the reminder text."
ns.NEED_DURATION = "Type a countdown, such as 30m or 1h 30m."
ns.NEED_CLOCK = "Type a time, such as 20:30 or 8:30 PM."
ns.NEED_ZONE = "Type a zone, such as Stormwind City."

-- Zone reminders whose zone the player is in right now, by id, so each fires once per entry.
local inside = {}

local function list()
    return SimpleRemindersDB.reminders
end

-- Timed reminders by due time, then zone reminders in the order added. The window and /sr list
-- share this order, so /sr remove takes the numbers /sr list shows.
function Reminders.Sorted()
    local sorted = {}
    for i, r in ipairs(list()) do sorted[i] = r end
    table.sort(sorted, function(a, b)
        if (a.due == nil) ~= (b.due == nil) then return a.due ~= nil end
        if a.due and a.due ~= b.due then return a.due < b.due end
        return a.id < b.id
    end)
    return sorted
end

local function schedule(r, now)
    if r.kind == "timer" then
        r.due = now + r.seconds
    elseif r.kind == "clock" then
        r.due = Time.NextClock(r, now)
    end
end

-- The zone name or the area inside it, so "Stormwind" matches Stormwind City and "Trade District"
-- matches the district.
local function inZone(r)
    local target = strlower(r.zone)
    for _, name in ipairs({ GetZoneText(), GetSubZoneText() }) do
        if name ~= "" and strlower(name):find(target, 1, true) then return true end
    end
    return false
end

-- The trigger as a phrase, such as "in 12 Min" or "every Monday at 20:00 realm time, in 2 Day".
function Reminders.Describe(r, now)
    if r.kind == "zone" then
        return (r.rep and "every time you enter " or "when you enter ") .. r.zone
    end
    local left = "in " .. Time.FormatLeft(r.due - now)
    if r.kind == "timer" then
        return r.rep and ("every " .. Time.FormatLeft(r.seconds) .. ", next " .. left) or left
    end
    local days = "at "
    if r.rep == true then
        days = "every day at "
    elseif type(r.rep) == "number" then
        days = "every " .. CALENDAR_WEEKDAY_NAMES[r.rep] .. " at "
    end
    local clock = r.realm and " realm time, " or " local time, "
    return days .. Time.FormatClock(r.hour, r.minute) .. clock .. left
end

-- The output and the trigger, the line under the text in the window: "Whisper, in 12 Min".
function Reminders.Detail(r, now)
    return ns.OUTPUT_LABELS[r.output] .. ", " .. Reminders.Describe(r, now)
end

function Reminders.Summary(r, now)
    return r.text .. " (" .. Reminders.Detail(r, now) .. ")"
end

local function addToChat(frame, line, info)
    frame:AddMessage(line, info.r, info.g, info.b, info.id)
end

-- A whisper from the addon itself, shown only on this client. A real whisper to yourself goes
-- through SendChatMessage, which is restricted for addons on Forever (HasRestrictions) and prints a
-- second "To" line. It lands in every open chat tab that shows whispers, with the whisper sound.
local function whisper(text)
    local info = ChatTypeInfo.WHISPER
    local line = CHAT_WHISPER_GET:format("[" .. ns.TITLE .. "]") .. text
    local shown = false
    FCF_IterateActiveChatWindows(function(frame)
        if frame:ContainsMessageGroup("WHISPER") then
            addToChat(frame, line, info)
            shown = true
        end
    end)
    if not shown then addToChat(DEFAULT_CHAT_FRAME, line, info) end
    PlaySound(SOUNDKIT.TELL_MESSAGE)
    FlashClientIcon()
end

-- A system line in the main chat tab, as Blizzard's alarm clock prints its message.
local function systemLine(text)
    addToChat(DEFAULT_CHAT_FRAME, "[" .. ns.TITLE .. "]: " .. text, ChatTypeInfo.SYSTEM)
end

-- As Blizzard's alarm clock fires (TimeManager_FireAlarm): the chat line, then the text across
-- the screen centre in the raid warning frame. The icon codes and sound follow the frame's own
-- CHAT_MSG_RAID_WARNING handler, so {star} shows the raid marker.
local function warning(text)
    systemLine(text)
    RaidWarningUtil.AddMessage(C_ChatInfo.ReplaceIconAndGroupExpressions(text), ChatTypeInfo.RAID_WARNING)
    PlaySound(SOUNDKIT.RAID_WARNING)
end

local DELIVER = { whisper = whisper, print = systemLine, warning = warning }

-- The window previews an output with this, so the player sees and hears it before adding.
function Reminders.Preview(output, text)
    DELIVER[output](text)
end

local function remove(r)
    tDeleteItem(list(), r)
    inside[r.id] = nil
end

-- Sends the reminder, then sets its next turn or removes it.
function Reminders.Fire(r, now)
    DELIVER[r.output](r.text)
    if r.rep then schedule(r, now) else remove(r) end
    ns.RefreshPanel()
end

-- Stores a reminder from the window or /sr. The callers parse the countdown and the time, so
-- only the text and the zone are checked here. Returns the reminder, or nil and the problem.
function Reminders.Add(r)
    r.text = ns.trim(r.text)
    if r.text == "" then return nil, ns.NEED_TEXT end
    if r.kind == "zone" then
        r.zone = ns.trim(r.zone)
        if r.zone == "" then return nil, ns.NEED_ZONE end
    end
    r.rep = r.rep or false
    r.output = DELIVER[r.output] and r.output or ns.DEFAULT_OUTPUT

    local db = SimpleRemindersDB
    r.id = db.nextId
    db.nextId = db.nextId + 1
    schedule(r, GetServerTime())

    -- Already standing in the zone is no entry, so it waits until the player comes back.
    if r.kind == "zone" then inside[r.id] = inZone(r) end

    table.insert(list(), r)
    ns.RefreshPanel()
    return r
end

function Reminders.Remove(r)
    remove(r)
    ns.RefreshPanel()
end

function Reminders.Clear()
    wipe(list())
    wipe(inside)
    ns.RefreshPanel()
end

-- Walks backwards, so a reminder Fire removes never skips the next one.
local function tick()
    local now = GetServerTime()
    local reminders = list()
    for i = #reminders, 1, -1 do
        local r = reminders[i]
        if r.due and r.due <= now then Reminders.Fire(r, now) end
    end
end

-- fire is false after a /reload, which is no entry, so the state is only recorded. The zone name
-- can be empty for a moment around a loading screen, and reading that as leaving would fire the
-- reminder again on the next event, so the state waits for a name.
local function checkZones(fire)
    if GetZoneText() == "" then return end
    local reminders = list()
    for i = #reminders, 1, -1 do
        local r = reminders[i]
        if r.kind == "zone" then
            local here = inZone(r)
            if here and fire and not inside[r.id] then
                inside[r.id] = true
                Reminders.Fire(r, GetServerTime())
            else
                inside[r.id] = here or nil
            end
        end
    end
end

-- Catches up on what came due while logged out. A one-time reminder fires on the first tick. A
-- repeating one fires too if it came due moments ago, as across a /reload, and otherwise waits for
-- its next turn. Time of day reminders are rescheduled from their stored time, which follows a
-- realm or DST change since logout.
local function catchUp()
    local now = GetServerTime()
    for _, r in ipairs(list()) do
        if r.due and r.due <= now then
            if r.rep and r.due < now - ns.MISSED_GRACE then schedule(r, now) end
        elseif r.kind == "clock" then
            r.due = Time.NextClock(r, now)
        end
    end
end

local ZONE_EVENTS = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }

-- The ticker waits for the first PLAYER_ENTERING_WORLD, so reminders missed while logged out show
-- after the loading screen instead of under it. Logging in inside a reminder's zone counts as
-- entering it.
function Reminders.Start()
    catchUp()
    local events = CreateFrame("Frame")
    local ticker
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    FrameUtil.RegisterFrameForEvents(events, ZONE_EVENTS)
    events:SetScript("OnEvent", function(_, event, _, isReloadingUi)
        if event == "PLAYER_ENTERING_WORLD" then
            ticker = ticker or C_Timer.NewTicker(1, tick)
            checkZones(not isReloadingUi)
        else
            checkZones(true)
        end
    end)
end
