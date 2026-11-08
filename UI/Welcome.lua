local addonName, ns = ...

-- The first login on an account prints one line: what the addon does, with a link that opens the
-- window. It waits for login, when the client's own load lines are already in chat. Blizzard
-- reserves the addon link type for addons and hands every click on one to all of them through one
-- EventRegistry event (ItemRefHandlersShared.lua). Gold is the colour of Blizzard's own action links
-- in chat, such as club invites (ItemRef.lua).
local LINK = LinkTypes.AddOn .. ":" .. addonName

local function SurfaceLink(label)
    return NORMAL_FONT_COLOR:WrapTextInColorCode(LinkUtil.FormatLink(LinkTypes.AddOn, "[" .. label .. "]", addonName))
end

function ns.PrintWelcome()
    ns.Print("Reminds you of anything by countdown, time of day or zone, as a whisper, a chat line or a raid"
        .. " warning. Open the " .. SurfaceLink(ns.title) .. " window or type /rm to add your first reminder.")
end

-- /rm intro: the welcome line now, and the help tip again, at once in an open window.
function ns.ReplayIntro()
    RemindMeDB.tipSeen = nil
    ns.PrintWelcome()
    ns.ShowTip()
end

-- Another addon's link may be secret, so it is checked before the comparison.
EventRegistry:RegisterCallback("SetItemRef", function(_, link)
    if ns.CanAccess(link) and link == LINK then ns.OpenPanel() end
end, ns)

EventUtil.ContinueOnPlayerLogin(function()
    if ns.firstRun then ns.PrintWelcome() end
end)
