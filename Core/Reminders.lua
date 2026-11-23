local addonName, ns = ...

local Time = ns.Time

local Reminders = {}
ns.Reminders = Reminders

-- Problems the window and /rm report in the same words.
ns.NEED_TITLE = "Type a title."
ns.NEED_DURATION = "Type a countdown, such as 30m or 1h 30m."
ns.NEED_CLOCK = "Type a time, such as 20:30 or 8:30 PM."
ns.NEED_ZONE = "Type a zone, such as Stormwind City."

-- Zone reminders whose zone the player is in right now, by id, so each fires once per entry.
local inside = {}

local function list()
    return RemindMeDB.reminders
end

-- Timed reminders by due time, then zone reminders in the order added. The window and /rm list
-- share this order, so /rm remove takes the numbers /rm list shows.
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

-- A time of day keeps its weekdays as a list in week order (Monday first), true for every day and
-- false for once. A list of all seven becomes true and an empty one false, and the list is always new,
-- so the stored reminder owns it. Countdowns and zones only repeat or not. A lone number is a weekday
-- saved before several were possible.
local function normalizeRep(r)
    local rep = r.rep
    if type(rep) == "number" then rep = { rep } end
    if r.kind ~= "clock" or type(rep) ~= "table" then return rep and true or false end
    local picked = {}
    for _, wday in ipairs(rep) do picked[wday] = true end
    local days = {}
    for _, wday in ipairs(ns.WEEK_ORDER) do
        if picked[wday] then days[#days + 1] = wday end
    end
    if #days == 0 then return false end
    if #days == 7 then return true end
    return days
end

-- Zone reminders and those without a trigger have no due time, also after an edit turned a timed
-- reminder into one.
local function schedule(r, now)
    if r.kind == "timer" then
        r.due = now + r.seconds
    elseif r.kind == "clock" then
        r.due = Time.NextClock(r, now)
    else
        r.due = nil
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

-- Weekday names joined as a sentence reads them: "Monday", "Monday and Friday", "Monday, Wednesday
-- and Friday".
local function dayNames(days)
    local names = {}
    for i, wday in ipairs(days) do names[i] = CALENDAR_WEEKDAY_NAMES[wday] end
    if #names == 1 then return names[1] end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- The trigger as a phrase, such as "in 12 Min" or "every Monday and Friday at 20:00 realm time,
-- next in 2 Day", or nil without a trigger.
function Reminders.Describe(r, now)
    if r.kind == "none" then return nil end
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
    elseif type(r.rep) == "table" then
        days = "every " .. dayNames(r.rep) .. " at "
    end
    local clock = r.realm and " realm time, " or " local time, "
    return days .. Time.FormatClock(r.hour, r.minute) .. clock .. (r.rep and "next " or "") .. left
end

-- The title, or the placeholder for a reminder still without one.
function Reminders.Name(r)
    return r.title ~= "" and r.title or ns.UNTITLED
end

-- The ticked and total items of a checklist.
function Reminders.Progress(r)
    local done = 0
    for _, item in ipairs(r.items) do
        if item.done then done = done + 1 end
    end
    return done, #r.items
end

-- The trigger and the checklist's progress, the line under the title in the window: "In 12 Min, 2 of
-- 5 done". Empty for a note without a trigger.
function Reminders.Detail(r, now)
    local parts = {}
    local when = Reminders.Describe(r, now)
    if when then parts[1] = when end
    if r.body == "checklist" and #r.items > 0 then
        parts[#parts + 1] = string.format("%d of %d done", Reminders.Progress(r))
    end
    local detail = table.concat(parts, ", ")
    return detail:sub(1, 1):upper() .. detail:sub(2)
end

function Reminders.Summary(r, now)
    local when = Reminders.Describe(r, now)
    return Reminders.Name(r) .. (when and (" (" .. when .. ")") or "")
end

function Reminders.Find(id)
    for _, r in ipairs(list()) do
        if r.id == id then return r end
    end
end

local function addToChat(frame, line, info)
    frame:AddMessage(line, info.r, info.g, info.b, info.id)
end

-- A whisper from the addon itself, shown only on this client. A real whisper to yourself goes
-- through SendChatMessage, which is restricted for addons on Forever (HasRestrictions) and prints a
-- second "To" line. It lands in every open chat tab that shows whispers, with the whisper sound.
local function whisper(text)
    local info = ChatTypeInfo.WHISPER
    local line = CHAT_WHISPER_GET:format("[" .. ns.title .. "]") .. text
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
    addToChat(DEFAULT_CHAT_FRAME, "[" .. ns.title .. "]: " .. text, ChatTypeInfo.SYSTEM)
end

local DELIVER = { whisper = whisper, print = systemLine }

-- The window previews an output with this, so the player sees and hears it before adding. A preview
-- shows the bare title.
function Reminders.Preview(output, text)
    DELIVER[output](text)
end

-- The title as an addon link (|Haddon:RemindMe:open:<id>|h) that opens the reminder in the window.
-- Blizzard's chat hands a click on it to the SetItemRef callback (ItemRefHandlersShared.lua). Gold
-- is the colour of Blizzard's own chat links such as club invites (ItemRef.lua) and of the welcome
-- line's link. Ids stay with a reminder, so a link from before a /reload still finds it.
local OPEN_PATTERN = "^" .. LinkTypes.AddOn .. ":" .. addonName .. ":open:(%d+)$"
local function openLink(r)
    local label = "[" .. Reminders.Name(r) .. "]"
    return NORMAL_FONT_COLOR:WrapTextInColorCode(LinkUtil.FormatLink(LinkTypes.AddOn, label, addonName, "open", r.id))
end

local function remove(r)
    tDeleteItem(list(), r)
    inside[r.id] = nil
end

-- Sends the title, then sets the next turn. A reminder that fires once stays in the list without a
-- trigger, so its note or checklist is kept and its link still opens it.
function Reminders.Fire(r, now)
    DELIVER[r.output](openLink(r))
    if r.rep then
        schedule(r, now)
    else
        r.kind, r.rep, r.due = "none", false, nil
        inside[r.id] = nil
    end
    ns.RefreshPanel(r)
end

-- An item is kept with its text, and an empty one is dropped.
local function checkItems(items)
    local kept = {}
    for _, item in ipairs(items or {}) do
        local text = ns.trim(item.text)
        if text ~= "" then kept[#kept + 1] = { text = text, done = item.done == true } end
    end
    return kept
end

-- Checks a reminder from the window or /rm and fills in its defaults. The callers parse the
-- countdown and the time, so only the zone is checked here. A title may still be empty while the
-- window fills it in. Returns the reminder, or nil and the problem.
local function check(r)
    r.title = ns.trim(r.title)
    r.note = r.note or ""
    r.items = checkItems(r.items)
    r.body = ns.BODY_LABELS[r.body] and r.body or "note"
    r.kind = ns.KIND_LABELS[r.kind] and r.kind or "none"
    if r.kind == "zone" then
        r.zone = ns.trim(r.zone)
        if r.zone == "" then return nil, ns.NEED_ZONE end
    end
    r.rep = normalizeRep(r)
    r.output = DELIVER[r.output] and r.output or ns.DEFAULT_OUTPUT
    return r
end

-- A scheduled copy of a trigger for the window's preview line. Nothing is checked or stored.
function Reminders.Plan(spec, now)
    local r = { kind = spec.kind, seconds = spec.seconds, hour = spec.hour, minute = spec.minute, realm = spec.realm, zone = spec.zone }
    r.rep = normalizeRep(spec)
    schedule(r, now)
    return r
end

-- Everything an edit may change. id and due stay with the stored reminder.
local FIELDS = { "kind", "title", "body", "note", "items", "output", "rep", "seconds", "hour", "minute", "realm", "zone" }

-- Rewrites a stored reminder in place, so it keeps its id and its place in the list. A countdown
-- keeps running unless its length or trigger changed. A time of day is rescheduled from its new
-- time. A zone reminder keeps its entry state unless its zone changed.
function Reminders.Update(r, spec)
    local changed, problem = check(spec)
    if not changed then return nil, problem end
    local restart = changed.kind ~= r.kind or changed.kind == "clock" or changed.seconds ~= r.seconds
    local rezone = changed.kind == "zone" and (r.kind ~= "zone" or changed.zone ~= r.zone)
    for _, key in ipairs(FIELDS) do r[key] = changed[key] end
    if restart then schedule(r, GetServerTime()) end
    if rezone then
        inside[r.id] = inZone(r)
    elseif r.kind ~= "zone" then
        inside[r.id] = nil
    end
    ns.RefreshPanel()
    return r
end

function Reminders.Add(r)
    local problem
    r, problem = check(r)
    if not r then return nil, problem end

    local db = RemindMeDB
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

-- A click on a reminder's title link opens it in the window. Every addon's link arrives here, and
-- another addon's may be secret, so it is checked first.
local function onLink(_, link)
    if not ns.CanAccess(link) or type(link) ~= "string" then return end
    local id = link:match(OPEN_PATTERN)
    if not id then return end
    local r = Reminders.Find(tonumber(id))
    if r then
        ns.EditInPanel(r)
    else
        ns.Print("This reminder was deleted.")
    end
end

-- Reminders saved before titles had one text, which becomes the title. The raid warning output is
-- gone, so its reminders whisper.
local function migrate(r)
    if r.text then r.title, r.text = r.text, nil end
    r.title = r.title or ""
    r.note = r.note or ""
    r.items = r.items or {}
    r.body = r.body or "note"
    if not DELIVER[r.output] then r.output = ns.DEFAULT_OUTPUT end
    r.rep = normalizeRep(r)
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
    for _, r in ipairs(list()) do migrate(r) end
    catchUp()
    EventRegistry:RegisterCallback("SetItemRef", onLink, Reminders)
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
