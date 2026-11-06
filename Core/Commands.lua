local _, ns = ...

local UI = LibStub("LibNativeUI-1.0")
local Time = ns.Time
local Reminders = ns.Reminders

local function say(message)
    UI.Print(ns.TITLE, message)
end

local function setOutput(output)
    return function(spec) spec.output = output end
end

local function setRealm(realm)
    return function(spec) spec.realm = realm end
end

local function setRepeat(rep)
    return function(spec) spec.rep = rep end
end

-- Words that may stand between the trigger and the text, in any order.
local OPTIONS = {
    whisper = setOutput("whisper"),
    print = setOutput("print"),
    chat = setOutput("print"),
    warning = setOutput("warning"),
    rw = setOutput("warning"),
    realm = setRealm(true),
    server = setRealm(true),
    ["local"] = setRealm(false),
    ["repeat"] = setRepeat(true),
    daily = setRepeat(true),
}

-- Weekday names in the client's language. Latin names also take their first three letters, so
-- "mon" works on an English client.
for wday, name in ipairs(CALENDAR_WEEKDAY_NAMES) do
    local lower = strlower(name)
    OPTIONS[lower] = setRepeat(wday)
    if not lower:find("[\128-\255]") then OPTIONS[lower:sub(1, 3)] = setRepeat(wday) end
end

local USAGE = {
    timer = "/rm in 30m <text>",
    clock = "/rm at 20:30 <text>",
    zone = "/rm zone Stormwind City: <text>",
}

-- Reads the options after the trigger, then the text, and stores the reminder.
local function addFrom(spec, words, i)
    while words[i] and OPTIONS[strlower(words[i])] do
        OPTIONS[strlower(words[i])](spec)
        i = i + 1
    end
    if spec.kind ~= "clock" and type(spec.rep) == "number" then
        say("Weekdays work only with /rm at.")
        return
    end
    spec.text = table.concat(words, " ", i)
    local r, problem = Reminders.Add(spec)
    if not r then
        say(problem .. " " .. USAGE[spec.kind])
        return
    end
    say("Added: " .. Reminders.Summary(r, GetServerTime()) .. ".")
end

local function addTimer(words)
    local seconds, i = Time.TakeDuration(words, 2)
    if not seconds then
        say(ns.NEED_DURATION .. " " .. USAGE.timer)
        return
    end
    addFrom({ kind = "timer", seconds = seconds }, words, i)
end

local function addClock(words)
    local hour, minute, i = Time.TakeClock(words, 2)
    if not hour then
        say(ns.NEED_CLOCK .. " " .. USAGE.clock)
        return
    end
    addFrom({ kind = "clock", hour = hour, minute = minute, realm = ns.DefaultRealm() }, words, i)
end

-- A zone of several words ends at a colon. Without one the zone is the first word.
local function addZone(rest)
    local zone, after = rest:match("^([^:]*):(.*)$")
    if not zone then zone, after = rest:match("^(%S*)%s*(.*)$") end
    local words = ns.words(after)
    addFrom({ kind = "zone", zone = zone }, words, 1)
end

local function addHere(words)
    local zone = GetZoneText()
    if zone == "" then
        say("Your zone has no name right now. Try again in a moment.")
        return
    end
    addFrom({ kind = "zone", zone = zone }, words, 2)
end

local function list()
    local sorted = Reminders.Sorted()
    if #sorted == 0 then
        say("No reminders. Type /rm to add one.")
        return
    end
    local now = GetServerTime()
    say(ns.countLabel(#sorted, "reminder", "reminders") .. ":")
    for i, r in ipairs(sorted) do
        print(i .. ". " .. Reminders.Summary(r, now))
    end
end

-- The reminder at a number /rm list shows, or nil after saying why.
local function pick(word)
    local sorted = Reminders.Sorted()
    local r = sorted[tonumber(word or "")]
    if not r then
        say(#sorted == 0 and "No reminders." or "Pick a number from /rm list, such as /rm remove 1.")
    end
    return r
end

local function removeAt(word)
    local r = pick(word)
    if not r then return end
    Reminders.Remove(r)
    say("Removed: " .. r.text .. ".")
end

local function editAt(word)
    local r = pick(word)
    if r then ns.EditInPanel(r) end
end

local function testAt(word)
    local r = pick(word)
    if r then Reminders.Preview(r.output, r.text) end
end

local function clear()
    if #Reminders.Sorted() == 0 then
        say("No reminders to remove.")
        return
    end
    Reminders.Clear()
    say("Removed every reminder.")
end

-- Each command with what it does, in the order a new player needs them.
local HELP = {
    { "/rm", "opens or closes the window." },
    { "/rm in 30m <text>", "reminds you after a countdown, such as 90s, 45m or 1h 30m." },
    { "/rm at 20:30 <text>", "reminds you at a time of day, such as 8:30pm." },
    { "/rm zone Stormwind City: <text>", "reminds you when you enter a zone." },
    { "/rm here <text>", "reminds you when you come back to the zone you are in." },
    { "Options", "go before the text: whisper, print or warning, repeat, and for /rm at realm or local, daily or a weekday such as monday." },
    { "/rm at 19:45 warning monday Raid tonight", "warns you every Monday." },
    { "/rm list", "lists your reminders with numbers." },
    { "/rm edit 2", "opens reminder 2 in the window to change it." },
    { "/rm remove 2", "removes reminder 2. /rm test 2 shows it once now." },
    { "/rm clear", "removes every reminder." },
    { "/rm minimap", "hides or shows the minimap button." },
}

local function help()
    say("Commands:")
    for _, entry in ipairs(HELP) do
        print(UI.Color.prefix:WrapTextInColorCode(entry[1]) .. " " .. entry[2])
    end
end

-- A bare /rm toggles the window, the first word picks the command.
local function handleSlash(msg)
    local raw = ns.trim(msg)
    local words = ns.words(raw)
    local command = strlower(words[1] or "")

    if command == "" then
        ns.TogglePanel()
    elseif command == "in" then
        addTimer(words)
    elseif command == "at" then
        addClock(words)
    elseif command == "zone" then
        addZone(raw:match("^%S+%s*(.*)$"))
    elseif command == "here" then
        addHere(words)
    elseif command == "list" then
        list()
    elseif command == "remove" or command == "delete" then
        removeAt(words[2])
    elseif command == "edit" then
        editAt(words[2])
    elseif command == "test" then
        testAt(words[2])
    elseif command == "clear" then
        clear()
    elseif command == "minimap" then
        ns.ToggleMinimap()
    elseif command == "help" or command == "?" then
        help()
    else
        say("Unknown command. Type /rm help for the list.")
    end
end

UI.RegisterSlash("REMINDME", { "/remindme", "/rm" }, handleSlash)
