local addonName, ns = ...

-- The toc Title, the name for everything the player reads: the window title, the chat prefix and
-- the launcher, whose LibDataBroker name it also is.
ns.title = C_AddOns.GetAddOnMetadata(addonName, "Title")

-- The bell from the toc's IconTexture, file 133706.
ns.ICON = "Interface\\Icons\\INV_Misc_Bell_01"

-- What starts a reminder, in the order the window offers them. None keeps it as a note or list
-- that never fires.
ns.KINDS = { "none", "timer", "clock", "zone" }
ns.KIND_LABELS = { none = NONE, timer = "Countdown", clock = "Time of Day", zone = ZONE }

-- How a reminder reaches the player, with Blizzard's own names for the two chat types.
ns.OUTPUTS = { "whisper", "print" }
ns.OUTPUT_LABELS = { whisper = WHISPER, print = CHAT }
ns.DEFAULT_OUTPUT = "whisper"

-- What a reminder holds under its title: a note or a checklist.
ns.BODIES = { "note", "checklist" }
ns.BODY_LABELS = { note = "Note", checklist = "Checklist" }

-- A reminder's title, note and checklist items each take up to this many letters, a chat line's
-- length.
ns.MAX_LETTERS = 255

-- The list and the alerts name a reminder without a title by this.
ns.UNTITLED = "New Reminder"

-- Weekdays in date("*t").wday numbering (1 is Sunday), listed from Monday as players read a week.
ns.WEEK_ORDER = { 2, 3, 4, 5, 6, 7, 1 }

-- A repeating reminder that came due more than this long before login is skipped to its next
-- turn, so a daily reminder never fires hours late. A one-time reminder always fires.
ns.MISSED_GRACE = 60

-- Every chat line goes through here: the bracketed title in the gold of Blizzard's own chat links,
-- then the message in the chat frame's own colour.
function ns.Print(message)
    print(NORMAL_FONT_COLOR:WrapTextInColorCode("[" .. ns.title .. "]") .. ": " .. message)
end

-- Another addon's link, or a chat line kept from restricted content, can be a secret value that
-- raises on comparison. issecretvalue's own SecretArguments flag leaves open whether it raises for
-- addon code, so pcall answers either way: a raise counts as secret, and nil never reaches it.
function ns.CanAccess(value)
    if value == nil then return true end
    local ok, secret = pcall(issecretvalue, value)
    return ok and not secret
end

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
