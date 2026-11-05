local _, ns = ...

-- Spaced name for everything the player reads: the window title, the chat prefix and the
-- launcher, whose LibDataBroker name it also is.
ns.TITLE = "Remind Me Later"

-- The bell from the toc's IconTexture, file 133706.
ns.ICON = "Interface\\Icons\\INV_Misc_Bell_01"

-- What starts a reminder, in the order the window and /rm help offer them.
ns.KINDS = { "timer", "clock", "zone" }
ns.KIND_LABELS = { timer = "Countdown", clock = "Time of Day", zone = ZONE }

-- How a reminder reaches the player, with Blizzard's own names for the three chat types.
ns.OUTPUTS = { "whisper", "print", "warning" }
ns.OUTPUT_LABELS = { whisper = WHISPER, print = CHAT, warning = RAID_WARNING }
ns.DEFAULT_OUTPUT = "whisper"

-- Weekdays in date("*t").wday numbering (1 is Sunday), listed from Monday as players read a week.
ns.WEEK_ORDER = { 2, 3, 4, 5, 6, 7, 1 }

-- A repeating reminder that came due more than this long before login is skipped to its next
-- turn, so a daily reminder never fires hours late. A one-time reminder always fires.
ns.MISSED_GRACE = 60

function ns.trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

function ns.words(text)
    local list = {}
    for word in (text or ""):gmatch("%S+") do list[#list + 1] = word end
    return list
end

function ns.countLabel(count, one, many)
    return string.format("%d %s", count, count == 1 and one or many)
end

-- New reminders without a Realm or Local pick follow the player's own clock setting, the one
-- Blizzard's minimap clock uses (GameTime_GetTime).
function ns.DefaultRealm()
    return not GetCVarBool("timeMgrUseLocalTime")
end
