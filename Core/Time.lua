local _, ns = ...

local Time = {}
ns.Time = Time

local DAY = 86400

-- A bare number counts as minutes, the unit players mean most often.
local UNITS = {
    [""] = 60,
    h = 3600, hr = 3600, hrs = 3600, hour = 3600, hours = 3600,
    m = 60, min = 60, mins = 60, minute = 60, minutes = 60,
    s = 1, sec = 1, secs = 1, second = 1, seconds = 1,
}

-- A suffix glued to the time ("8pm", "8p") or the word after it ("8 pm").
local MERIDIEM = { am = "am", a = "am", ["a.m."] = "am", pm = "pm", p = "pm", ["p.m."] = "pm" }
local MERIDIEM_WORDS = { am = true, pm = true, ["a.m."] = true, ["p.m."] = true }

-- One word of one or more number and unit pairs, such as "90", "30m" or "1h30m". Nil when the
-- word is not a duration.
local function durationWord(word)
    word = word:lower()
    local total, pos = 0, 1
    while pos <= #word do
        local count, unit, nextPos = word:match("^(%d+)(%a*)()", pos)
        local scale = count and UNITS[unit]
        if not scale then return nil end
        total = total + tonumber(count) * scale
        pos = nextPos
    end
    return total
end

-- Reads a duration from words[i] on, so "1h 30m" and "2 hours" span two words. Returns the
-- seconds and the index of the first word after it, or nil when words[i] is no duration.
function Time.TakeDuration(words, i)
    local start, total = i, 0
    while words[i] do
        local unit = words[i + 1] and UNITS[strlower(words[i + 1])]
        if unit and words[i]:match("^%d+$") then
            total = total + tonumber(words[i]) * unit
            i = i + 2
        else
            local seconds = durationWord(words[i])
            if not seconds then break end
            total = total + seconds
            i = i + 1
        end
    end
    if i == start or total == 0 then return nil end
    return total, i
end

-- Reads a time of day from words[i] on: "20:30", "20.30", "20", "8:30pm", "8pm" or "8 pm".
-- Returns hour, minute and the index of the first word after it, or nil when it is no time.
function Time.TakeClock(words, i)
    local word = (words[i] or ""):lower()
    local hour, minute, suffix = word:match("^(%d%d?)[:.](%d%d)(%S*)$")
    if not hour then hour, suffix = word:match("^(%d%d?)(%S*)$") end
    if not hour then return nil end

    local nextIndex = i + 1
    local following = words[nextIndex] and words[nextIndex]:lower()
    if suffix == "" and MERIDIEM_WORDS[following] then
        suffix, nextIndex = following, nextIndex + 1
    end
    local half = MERIDIEM[suffix]
    if suffix ~= "" and not half then return nil end

    hour, minute = tonumber(hour), tonumber(minute or 0)
    if minute > 59 then return nil end
    if half then
        if hour < 1 or hour > 12 then return nil end
        hour = hour % 12 + (half == "pm" and 12 or 0)
    elseif hour > 23 then
        return nil
    end
    return hour, minute, nextIndex
end

-- The window's fields hold nothing but the duration or the time.
function Time.ParseDuration(text)
    local words = ns.words(text)
    local seconds, nextIndex = Time.TakeDuration(words, 1)
    if seconds and nextIndex > #words then return seconds end
end

function Time.ParseClock(text)
    local words = ns.words(text)
    local hour, minute, nextIndex = Time.TakeClock(words, 1)
    if hour and nextIndex > #words then return hour, minute end
end

-- Seconds the realm clock runs ahead of UTC. GetGameTime is the realm time Blizzard's minimap
-- clock shows, without seconds, so the gap is rounded to the 15 minutes time zones use.
function Time.RealmOffset(now)
    local hour, minute = GetGameTime()
    local utc = date("!*t", now)
    local minutes = (hour * 60 + minute) - (utc.hour * 60 + utc.min)
    minutes = (minutes + 720) % 1440 - 720
    return math.floor(minutes / 15 + 0.5) * 15 * 60
end

-- The epoch and weekday of hour:minute, days after today, on the reminder's clock.
-- shortcut: the realm offset is read once per scheduling, so a realm DST change shifts a
-- reminder set before it by an hour until the next login reschedules it.
local function candidate(r, now, days)
    if r.realm then
        local offset = Time.RealmOffset(now)
        local wall = date("!*t", now + offset)
        local midnight = now + offset - (wall.hour * 3600 + wall.min * 60 + wall.sec)
        return midnight + days * DAY + r.hour * 3600 + r.minute * 60 - offset, (wall.wday - 1 + days) % 7 + 1
    end
    -- time() normalises the day past the month's end and applies the player's DST rules.
    local wall = date("*t", now)
    local due = time({ year = wall.year, month = wall.month, day = wall.day + days, hour = r.hour, min = r.minute, sec = 0 })
    return due, date("*t", due).wday
end

-- The next moment after now that a time of day reminder is due. rep is a weekday (1 is Sunday)
-- for a weekly reminder, anything else matches every day.
function Time.NextClock(r, now)
    for days = 0, 7 do
        local due, wday = candidate(r, now, days)
        if due > now and (type(r.rep) ~= "number" or wday == r.rep) then return due end
    end
end

-- Hour and minute in the player's 12 or 24 hour clock setting.
function Time.FormatClock(hour, minute)
    return GameTime_GetFormattedTime(hour, minute, true)
end

-- Time left in Blizzard's short units: seconds under a minute, otherwise at most two units.
function Time.FormatLeft(seconds)
    seconds = math.max(seconds, 1)
    return SecondsToTime(seconds, seconds >= 60, false, 2)
end
