local _, ns = ...

local Time = ns.Time
local Reminders = ns.Reminders

-- Spacing roles on the 8 px grid: tight from text to its control, gap between related controls, padding
-- inside a column, a section break between sections. Rows, checkboxes and content buttons are 24 tall.
local TIGHT, GAP, PADDING, SECTION_GAP = 4, 8, 16, 24
local ROW = 24

-- InputBoxTemplate draws its left cap 5 px outside the box (Shared/InputBox/InputBoxTemplates.xml:49), and
-- InputScrollFrameTemplate its border 5 px outside each side (:83-104), so a box sits in by that much to line
-- its art up with the column.
local INPUT_CAP = 5

-- WowStyle1DropdownTemplate's art hangs 8 px past each side of its frame (Blizzard_Menu/Mainline/MenuTemplates.xml:9-10).
local DROPDOWN_ART = 8

-- The right margin a ScrollFrameTemplate leaves for its bar: SCROLL_FRAME_SCROLL_BAR_OFFSET_LEFT 6, the
-- 8 px bar and a gap, rounded up to the grid.
local SCROLL_GUTTER = 24

-- Text in a font role: GameFontNormal (heading, gold), GameFontHighlight (body, white), GameFontDisable (muted,
-- grey), GameFontNormalLarge (title, 16 px, a dialog's subject line only).
local function CreateText(parent, fontObject, layer)
    local text = parent:CreateFontString(nil, layer or "ARTWORK")
    text:SetFontObject(fontObject or GameFontHighlight)
    text:SetJustifyH("LEFT")
    return text
end

-- A GameTooltip owned by the hovered frame, filled with Blizzard's GameTooltip_* line helpers. A frame whose
-- template already sets OnEnter gets HookScript instead.
local function AttachTooltip(frame, fill, anchor)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        fill(GameTooltip, self)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- AttachTooltip for a frame whose template already sets OnEnter and OnLeave, such as Blizzard's buttons and
-- hint boxes: the tooltip is hooked in after the template's own handlers.
local function HookTooltip(frame, fill, anchor)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
        fill(GameTooltip, self)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", GameTooltip_Hide)
end

-- Rounds a length derived from text up to the 4 px step text takes on the grid.
local function Snap(length)
    return math.ceil(length / 4) * 4
end

-- A content button one row (24) tall. Without a width it fits its label the way UIPanelButtonTemplate's FitToText
-- does (text plus 40, SecureUIPanelTemplates.xml:42), at least 64, rounded up to 8 so neighbours share widths.
local function CreateButton(parent, label, width)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetText(label)
    width = width or math.max(64, math.ceil((button:GetTextWidth() + 40) / 8) * 8)
    button:SetSize(width, 24)
    return button
end

-- CheckboxWithLabelTemplate: the minimal art Blizzard's Settings use, at the 24 px AddonList gives it
-- (Blizzard_AddOnList/AddonList.xml:73-74). The label joins the hit rect, so a click on it toggles the box.
local function CreateCheckbox(parent, label)
    local checkbox = CreateFrame("CheckButton", nil, parent, "CheckboxWithLabelTemplate")
    checkbox:SetSize(24, 24)
    checkbox.Text:SetFontObject(GameFontHighlight)
    checkbox.Text:ClearAllPoints()
    checkbox.Text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
    checkbox.Text:SetText(label)
    checkbox:SetHitRectInsets(0, -(4 + checkbox.Text:GetStringWidth()), 0, 0)
    return checkbox
end

-- UIRadialButtonTemplate (Shared/Button/CheckButtonTemplates.xml:26), the radial tick of Blizzard's dropdown menus at
-- its 18 px atlas size, centred in a 24 px row like the checkbox, with the same clickable body label. The caller
-- unchecks the other radios of its group in OnClick.
local RADIO_SIZE = 18
local RADIO_INSET = (24 - RADIO_SIZE) / 2
local function CreateRadio(parent, label)
    local radio = CreateFrame("CheckButton", nil, parent, "UIRadialButtonTemplate")
    radio.label = CreateText(radio, GameFontHighlight)
    radio.label:SetPoint("LEFT", radio, "RIGHT", 4 + RADIO_INSET, 0)
    radio.label:SetText(label)
    radio:SetHitRectInsets(0, -(4 + RADIO_INSET + radio.label:GetStringWidth()), 0, 0)
    return radio
end

-- InputBoxInstructionsTemplate: the same box plus Blizzard's grey hint, so an empty field says what it takes.
-- The hint moves to the muted font where typed text starts, keeping the template's grey.
local function CreateHintBox(parent, hint, width)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxInstructionsTemplate")
    box:SetSize(width or 160, 20)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlight)
    local r, g, b = box.Instructions:GetTextColor()
    box.Instructions:SetFontObject(GameFontDisable)
    box.Instructions:SetTextColor(r, g, b)
    box.Instructions:ClearAllPoints()
    box.Instructions:SetAllPoints()
    box.Instructions:SetText(hint)
    return box
end

-- InputScrollFrameTemplate, the Group Finder's listing description (Blizzard_GroupFinder/Mainline/LFGList.xml:1764):
-- a bordered multi-line box with its own scroll bar and grey hint, here at a fixed width the caller passes and
-- any height. Its OnLoad sized the box while it was still 0 wide, so the widths are set again
-- (InputScrollFrame_OnLoad, InputBoxTemplates.lua:82). Typed text and the hint move to the 12 px roles, the hint
-- keeping its grey, and the character count stays hidden as in the Group Finder.
local function CreateNoteBox(parent, hint, width, maxLetters)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "InputScrollFrameTemplate")
    scroll:SetWidth(width)
    local box = scroll.EditBox
    box:SetWidth(width - 18)
    box:SetMaxLetters(maxLetters)
    box:SetFontObject(GameFontHighlight)
    local r, g, b = box.Instructions:GetTextColor()
    box.Instructions:SetFontObject(GameFontDisable)
    box.Instructions:SetTextColor(r, g, b)
    box.Instructions:SetWidth(width)
    InputScrollFrame_SetInstructions(scroll, hint)
    scroll.CharCount:Hide()
    return scroll
end

-- Blizzard's menu dropdown, filled with SetupMenu. Its frame sits on the column edge and its art hangs 8 px past each
-- side, as the Group Finder lines it up under an edit box (LFGList.xml:1794-1795).
local function CreateDropdown(parent, width)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(width or 160)
    return dropdown
end

-- The close button Blizzard uses for one row of a list, sized to the row.
local function CreateRemoveButton(parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelCloseButtonNoScripts")
    button:SetSize(24, 24)
    return button
end

-- The gold Settings divider stood on end, to split the brown panel into columns. SetClampedTextureRotation turns it
-- a quarter and swaps its size (Blizzard_SharedXMLBase/TextureUtil.lua). The caller anchors its top and bottom.
local function CreateVerticalDivider(parent)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    SetClampedTextureRotation(divider, 90)
    return divider
end

-- A window section, the way Blizzard's Settings panel heads one: a gold heading, its divider a tight step under it
-- (Blizzard_SettingsList.xml, AddonList.xml), the body a tight step under that. The caller sets the height to
-- SECTION_BODY_TOP plus the body's height.
local SECTION_DIVIDER_TOP = 16
local SECTION_BODY_TOP = 24
local function CreateSection(parent, title)
    local section = CreateFrame("Frame", nil, parent)
    local heading = CreateText(section, GameFontNormal)
    heading:SetPoint("TOPLEFT")
    heading:SetPoint("TOPRIGHT")
    heading:SetText(title)
    local divider = section:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOPLEFT", 0, -SECTION_DIVIDER_TOP)
    divider:SetPoint("TOPRIGHT", 0, -SECTION_DIVIDER_TOP)
    section.body = CreateFrame("Frame", nil, section)
    section.body:SetPoint("TOPLEFT", 0, -SECTION_BODY_TOP)
    section.body:SetPoint("BOTTOMRIGHT")
    return section
end

-- A ScrollFrameTemplate with its scroll child. Leave the 24 px gutter free on its right for the bar, which hides
-- while everything fits.
local function CreateScroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
    scroll.ScrollBar:SetHideIfUnscrollable(true)
    scroll.content = CreateFrame("Frame", nil, scroll)
    scroll.content:SetSize(1, 1)
    scroll:SetScrollChild(scroll.content)
    return scroll
end

-- Scrolls just enough to show the band from top to bottom of the scroll child.
local function Reveal(scroll, top, bottom)
    scroll:UpdateScrollChildRect()
    local offset, view = scroll:GetVerticalScroll(), scroll:GetHeight()
    if bottom > offset + view then
        scroll:SetVerticalScroll(math.min(bottom - view, scroll:GetVerticalScrollRange()))
    elseif top < offset then
        scroll:SetVerticalScroll(top)
    end
end

-- The list rows of the character window's Statistics tab (Blizzard_Statistics/Camelot/StatisticsFrame.xml,
-- StatisticsEntryTemplate): LIST_GAP apart, the text LIST_INDENT in from the row's edge, and Blizzard's rounded line
-- from character creation's dropdowns behind it, white at 0.10 alpha on hover (StatisticsEntryMixin) and 0.20 while
-- selected (SkillsEntryMixin). The title wraps so it shows in full, with the trigger and the checklist's progress in
-- one muted line under it, so a row grows with its text; a one-line row is the template's 24, its text ROW_PAD from
-- the top and bottom. Built from the atlases, since the template reads the player's statistics.
local LIST_GAP, LIST_INDENT, ROW_PAD = 3, 2, 6
local function CreateListRow(parent, textWidth)
    local row = CreateFrame("Button", nil, parent)
    row.highlight = CreateFrame("Frame", nil, row)
    row.highlight:SetAllPoints()
    row.highlight:SetAlpha(0)
    local left = row.highlight:CreateTexture(nil, "BACKGROUND")
    left:SetAtlas("charactercreate-customize-dropdown-linemouseover-side")
    left:SetWidth(6)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    local right = row.highlight:CreateTexture(nil, "BACKGROUND")
    right:SetAtlas("charactercreate-customize-dropdown-linemouseover-side")
    right:SetTexCoord(1, 0, 0, 1)
    right:SetWidth(6)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    local middle = row.highlight:CreateTexture(nil, "BACKGROUND")
    middle:SetAtlas("charactercreate-customize-dropdown-linemouseover-middle")
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    row.name = CreateText(row, GameFontHighlight, "OVERLAY")
    row.name:SetPoint("TOPLEFT", LIST_INDENT, -ROW_PAD)
    row.name:SetWidth(textWidth)
    row.name:SetWordWrap(true)
    row.detail = CreateText(row, GameFontDisable, "OVERLAY")
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -TIGHT)
    row.detail:SetWidth(textWidth)
    row.detail:SetWordWrap(false)
    local function refresh(self)
        self.highlight:SetAlpha((self.isSelected and 0.20) or (self.hovered and 0.10) or 0)
    end
    row:SetScript("OnEnter", function(self)
        self.hovered = true
        refresh(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.hovered = false
        refresh(self)
    end)
    function row:SetSelected(selected)
        self.isSelected = selected
        refresh(self)
    end
    return row
end

-- An empty list says what fills it and how, in one muted line centred in the list.
local function CreateEmptyState(parent, text)
    local empty = CreateText(parent, GameFontDisable)
    empty:SetPoint("LEFT", 16, 0)
    empty:SetPoint("RIGHT", -16, 0)
    empty:SetJustifyH("CENTER")
    empty:SetText(text or "")
    return empty
end

-- Blizzard's yellow help tip, the Auction House's undercut tip (Blizzard_AuctionHouseSellFrame.lua:507), as an
-- own HelpTipTemplate frame on the target. HelpTip:Show takes a frame from Blizzard's shared pool, and addon
-- code writing to it taints the tips Blizzard shows later. The tip shows each time its target shows until the
-- player closes it or uses the feature, then never again on the account. It hides with its target unmarked.
-- Reset runs before every Init: only Blizzard's pool resets a tip, and Init leaves acknowledged set
-- (Blizzard_SharedXML/HelpTip.lua:419-431, 495, 687), so a tip closed once and brought back by intro would
-- count as seen when it merely hides with its target. On hide, Close hands the tip to HelpTip:Release, which
-- ignores a frame its pool does not own (HelpTip.lua:343-346).
local function AttachTip(target, text, targetPoint, relativeRegion)
    local tip
    local info = {
        text = text,
        buttonStyle = HelpTip.ButtonStyle.Close,
        targetPoint = targetPoint,
        onAcknowledgeCallback = function() SimpleRemindersDB.tipSeen = true end,
    }
    local function ShowTip()
        if SimpleRemindersDB.tipSeen or (tip and tip:IsShown()) then return end
        if not tip then
            tip = CreateFrame("Frame", nil, target, "HelpTipTemplate")
            tip.width = HelpTip.width
            tip:SetWidth(tip.width)
        end
        tip:Reset()
        tip:Init(target, info, relativeRegion or target)
        tip:Show()
    end
    target:HookScript("OnShow", ShowTip)
    if target:IsVisible() then ShowTip() end

    -- The player used the feature: the tip goes for good, shown or not.
    local function Retire()
        if tip and tip.info then tip:Acknowledge() else SimpleRemindersDB.tipSeen = true end
    end
    return ShowTip, Retire
end

-- The collections panel's ornaments, which a tool window leaves out.
local BACKGROUND_CORNERS = { "BGCornerTopLeft", "BGCornerTopRight", "BGCornerBottomLeft", "BGCornerBottomRight" }

-- Restores a saved position, or centres the frame.
local function RestorePosition(frame, position)
    frame:ClearAllPoints()
    if position and position.point then
        frame:SetPoint(position.point, UIParent, position.relPoint or position.point, position.x or 0, position.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

-- Windows and dialogs: toplevel, clamped, dragged with the left button, closed by Escape through UISpecialFrames,
-- never UIPanelWindows, so they never drive Blizzard's panel layout.
local function MakeMovable(frame, name, strata, position)
    frame:SetFrameStrata(strata)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if position then
            local point, _, relPoint, x, y = self:GetPoint(1)
            position.point, position.relPoint, position.x, position.y = point, relPoint, x, y
        end
    end)
    RestorePosition(frame, position)
    frame:Hide()
    tinsert(UISpecialFrames, name)
end

-- A tool window on ButtonFrameTemplate: portrait, title, close button, inset, attic and button bar come from the
-- template. The wardrobe's brown panel (CollectionsBackgroundTemplate, Mainline/SharedCollectionTemplates.xml) takes
-- the inset's place without its corner ornaments; Inset stays the content parent and draws nothing.
local function CreateWindow(name, title, icon, width, height, position)
    local frame = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
    frame:SetSize(width, height)
    frame.Inset.Bg:Hide()
    frame.Inset.NineSlice:Hide()
    local background = CreateFrame("Frame", nil, frame, "CollectionsBackgroundTemplate")
    background:ClearAllPoints()
    background:SetAllPoints(frame.Inset)
    for _, corner in ipairs(BACKGROUND_CORNERS) do background[corner]:Hide() end
    frame.Background = background
    frame:SetTitle(title)
    frame:SetPortraitToAsset(icon)

    -- The close button goes through HideUIPanel, which refuses insecure callers in combat. UIPanelCloseButton_OnClick
    -- asks onCloseCallback first, so the window hides itself instead.
    frame.onCloseCallback = function()
        frame:Hide()
        return false
    end

    MakeMovable(frame, name, "HIGH", position)
    return frame
end

-- The button bar: the window's 4 px bottom border, a gap, a row-tall button and a gap. The template's 26 px bar fits
-- a 22 px button flush to its edges only, so the inset ends at this height instead.
local BAR_BORDER = 4
local BAR_H = BAR_BORDER + GAP + ROW + GAP

-- A bar button, 128 wide and a row tall, a gap above the bottom border and lined up with the padded content above
-- it: a destructive one such as Delete in the bottom-left corner, as the macro window places its Delete, the others
-- in the bottom-right. x is the content's padded edge.
local function CreateBarButton(window, label, point, x)
    local button = CreateButton(window, label, 128)
    button:SetPoint(point, x, BAR_BORDER + GAP)
    return button
end

-- A help line in the attic, from title left 58 to the rows' right edge, cut rather than wrapped. Two lines sit one
-- gap either side of the attic's middle: a gold how-to over a white next step.
local function CreateAtticLine(frame, fontObject, y, rightOffset)
    local line = CreateText(frame, fontObject)
    line:SetPoint("LEFT", frame, "TOPLEFT", 58, y)
    line:SetPoint("RIGHT", frame, "TOPRIGHT", rightOffset, y)
    line:SetWordWrap(false)
    return line
end

-- Builds the window on first use and flips it after that, so no frame exists until the player asks.
local function CreateToggle(build)
    local window
    return function()
        window = window or build()
        window:SetShown(not window:IsShown())
    end
end

-- A dialog in Blizzard's dialog chrome: DialogBorderTemplate, DialogHeaderTemplate with the title and
-- UIPanelCloseButton 2 px in from the corner (Blizzard_Channels/Mainline/CreateChannelPopup.xml:72). Width is a
-- multiple of 8 from 400 to 480. Add content top to bottom with AddText and AddField, then call Fit.
local DIALOG_SIDE, DIALOG_TOP = 24, 40
local function CreateDialog(name, title, width, parent, position)
    local dialog = CreateFrame("Frame", name, parent or UIParent)
    dialog:SetSize(width, DIALOG_TOP + DIALOG_SIDE)
    dialog.contentWidth = width - 2 * DIALOG_SIDE
    dialog.contentHeight = 0
    dialog.buttons = {}
    dialog.Border = CreateFrame("Frame", nil, dialog, "DialogBorderTemplate")
    dialog.Header = CreateFrame("Frame", nil, dialog, "DialogHeaderTemplate")
    dialog.Header:Setup(title)
    -- UIPanelCloseButton_OnClick goes through HideUIPanel, which refuses insecure callers in combat.
    dialog.CloseButton = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
    dialog.CloseButton:SetPoint("TOPRIGHT", -2, -2)
    dialog.CloseButton:SetScript("OnClick", function() dialog:Hide() end)

    -- Places a widget the caller sized in the content column below everything added so far; indent covers native
    -- art, 5 for an edit box. The gap defaults to 8; AddText passes a section break.
    function dialog:AddField(region, height, gap, indent)
        if self.hasContent then self.contentHeight = self.contentHeight + (gap or 8) end
        self.hasContent = true
        region:SetPoint("TOPLEFT", self, "TOPLEFT", DIALOG_SIDE + (indent or 0), -(DIALOG_TOP + self.contentHeight))
        self.contentHeight = self.contentHeight + height
    end

    -- Wrapped text across the column, never less than one line, so text filled in later keeps its line.
    function dialog:AddText(fontObject, text, gap)
        local line = CreateText(self, fontObject)
        line:SetWidth(self.contentWidth)
        line:SetWordWrap(true)
        line:SetText(text or "")
        local _, lineHeight = fontObject:GetFont()
        local height = math.ceil(math.max(line:GetStringHeight(), lineHeight))
        line:SetHeight(height)
        self:AddField(line, height, gap or SECTION_GAP)
        return line
    end

    -- A 24 px fit-to-text button in the bottom-right corner; later ones chain leftwards 8 apart.
    function dialog:AddButton(label, onClick)
        local button = CreateButton(self, label)
        local previous = self.buttons[#self.buttons]
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -8, 0)
        else
            button:SetPoint("BOTTOMRIGHT", -DIALOG_SIDE, DIALOG_SIDE)
        end
        button:SetScript("OnClick", onClick)
        self.buttons[#self.buttons + 1] = button
        return button
    end

    -- 40 top, the content, a section break and the button row if there are buttons, 24 bottom, on the grid.
    function dialog:Fit()
        local height = DIALOG_TOP + self.contentHeight + DIALOG_SIDE
        if #self.buttons > 0 then height = height + SECTION_GAP + 24 end
        self:SetHeight(Snap(height))
    end

    MakeMovable(dialog, name, "DIALOG", position)
    return dialog
end

-- Laid out like Blizzard's macro window (Blizzard_MacroUI.xml): the reminders on the left, the picked one in
-- full on the right, Delete in the bar's bottom-left corner and New Reminder in its bottom-right. Two equal
-- columns; the outer width carries Blizzard's 4/-6 inset offsets, so it is 674.
local COLUMN_W = 328
local PANEL_W = PANEL_INSET_LEFT_OFFSET + 2 * COLUMN_W + GAP - PANEL_INSET_RIGHT_OFFSET

-- The detail's inner width, and the list's width left of its scroll gutter.
local BODY_W = COLUMN_W - 2 * PADDING
local LIST_W = COLUMN_W - PADDING - SCROLL_GUTTER

-- The detail from the top: the title, the Note and Checklist radios, then the note or the checklist down to When.
local CONTENT_TOP = 2 * (ROW + GAP)

-- The When dropdown takes the width of a bar button; the value box fills the rest of its row.
local KIND_W = 128

-- Checklist rows sit 24 tall at the editable list's pitch of 32.
local ITEM_PITCH = ROW + GAP

-- Weekdays in three columns, rows stacked a tight gap apart.
local DAY_COLUMNS = 3
local DAY_W = 4 * math.floor((BODY_W + GAP) / DAY_COLUMNS / 4)
local DAY_ROWS = math.ceil(#ns.WEEK_ORDER / DAY_COLUMNS)
local DAYS_H = DAY_ROWS * ROW + (DAY_ROWS - 1) * TIGHT

-- The preview line under the trigger has room for two lines.
local PREVIEW_H = 32

-- When's body at its tallest, a time of day: the dropdown, Use Local Time, the weekdays and the preview.
local WHEN_CLOCK_H = ROW + GAP + ROW + GAP + DAYS_H + GAP + PREVIEW_H

-- Alert: the outputs with Test, then Character Specific.
local ALERT_H = SECTION_BODY_TOP + ROW + GAP + ROW

-- The note or checklist keeps at least four checklist rows beside the tallest When.
local CONTENT_MIN = 4 * ITEM_PITCH

local EDITOR_H = CONTENT_TOP + CONTENT_MIN + SECTION_GAP + SECTION_BODY_TOP + WHEN_CLOCK_H + SECTION_GAP + ALERT_H

-- The template's attic keeps the columns below the portrait, which hangs 55px down from the top edge
-- (Mainline/SharedUIPanelTemplates.xml:584). The attic offset (60) is off the grid, so the height snaps up and the
-- extra px fall to the note or checklist.
local PANEL_H = Snap(-PANEL_INSET_ATTIC_OFFSET + 2 * PADDING + EDITOR_H + BAR_H)

local DIALOG_W = 400

-- The window's player-facing text, kept in one table: as separate locals the panel builder would pass Lua 5.1's
-- limit of 60 upvalues per function, and the client refuses to load the file.
local TEXT = {
    ATTIC = "Changes save as you type. Click a reminder's title in chat to open it here.",
    EMPTY_LIST = "No reminders yet.",
    EMPTY_FIRST = "Click New Reminder to add your first reminder.",
    EMPTY_PICK = "Pick a reminder on the left, or click New Reminder.",

    -- The help tip stands right of New Reminder, outside the window, until the first reminder is added.
    TIP_TEXT = "Click New Reminder to add a reminder with a note or a checklist.",

    NEW_LABEL = "New Reminder",
    TITLE_HINT = "Title",
    NOTE_HINT = "Add a note",
    ADD_ITEM = "Add an item",

    -- What the empty value field asks for under each trigger.
    VALUE_HINTS = { timer = "30m or 1h 30m", clock = "20:30 or 8:30 PM", zone = "Stormwind City" },

    -- The preview line while the value field is empty: what the trigger does.
    PREVIEW_HINTS = {
        none = "Never fires. It stays on your list until you delete it.",
        timer = "Fires once the countdown runs out.",
        clock = "Fires once, or on every weekday you tick.",
        zone = "Fires when you enter this zone or an area in it.",
    },

    -- Tooltips for the choices, so each says what it does before it is picked.
    KIND_TIPS = {
        none = "Keeps it as a note or a list that never fires.",
        timer = "Fires once a countdown runs out, such as 30m or 1h 30m.",
        clock = "Fires at a time of day, once or on the weekdays you tick.",
        zone = "Fires when you enter a zone or an area in it, such as Stormwind or Trade District.",
    },
    BODY_TIPS = {
        note = "Free text under the title, up to 255 characters.",
        checklist = "Items under the title that you tick off one by one.",
    },
    OUTPUT_TIPS = {
        whisper = "A pink whisper line in chat with the whisper sound. Only you see it.",
        print = "A yellow line in your main chat tab, without a sound.",
    },
    TITLE_TIP = "What the reminder is about. Its alert in chat shows the title as a link that opens it here.",
    CHARACTER_LABEL = "Character Specific",
    CHARACTER_TIP = "Keeps the reminder to this character: only it lists the reminder and gets its alert. Unticked, every character on the account has it.",
    NEVER_FIRES = "Pick a trigger under When first.",
    WHEN_TIP = "What makes the reminder fire. With None it never fires.",
    TIMER_REPEAT_TIP = "Starts the countdown again each time it fires.",
    ZONE_REPEAT_TIP = "Fires on every entry, not only the next one.",
    LOCAL_TIME_TIP = "Use your computer's clock instead of the realm clock.",
    DAY_TIP = "Fires on this day every week. With no day ticked, it fires once.",
    VALUE_TIPS = {
        timer = "How long until it fires, such as 90s, 30m or 1h 30m.",
        clock = "The time it fires, such as 20:30 or 8:30 PM.",
        zone = "The zone or an area in it, such as Stormwind City or Trade District.",
    },
}

-- The picks of a stored reminder. Every day ticks all seven weekdays, and the items are copies, so typing
-- never writes to the stored list before a save.
local function picksOf(r)
    local picks = {
        kind = r.kind, output = r.output, body = r.body, realm = ns.DefaultRealm(), rep = false, days = {}, items = {},
        character = r.character ~= nil,
    }
    if r.kind == "clock" then
        picks.realm = r.realm
        for _, wday in ipairs(ns.WEEK_ORDER) do
            picks.days[wday] = (r.rep == true or (type(r.rep) == "table" and tContains(r.rep, wday))) or nil
        end
    else
        picks.rep = r.rep == true
    end
    for i, item in ipairs(r.items) do picks.items[i] = { text = item.text, done = item.done } end
    return picks
end

-- What the value field shows for a stored trigger.
local function valueOf(r)
    if r.kind == "timer" then return Time.FormatDuration(r.seconds) end
    if r.kind == "clock" then return Time.FormatClockField(r.hour, r.minute) end
    if r.kind == "zone" then return r.zone end
    return ""
end

-- A stored trigger as a spec, for a save while the trigger field is still unfinished.
local function triggerOf(r)
    return { kind = r.kind, rep = r.rep, seconds = r.seconds, hour = r.hour, minute = r.minute, realm = r.realm, zone = r.zone }
end

-- A reminder New Reminder made and the player left without a word in it.
local function isEmpty(r)
    return r.title == "" and ns.trim(r.note) == "" and #r.items == 0 and r.kind == "none"
end

local panel

-- A title and one help line. A control that can be off says why in a red line, as Blizzard's dungeon finder does,
-- so it takes the mouse while disabled too.
local function fillTip(frame, title, text, whyOff)
    if whyOff then frame:SetMotionScriptsWhileDisabled(true) end
    return function(tooltip, self)
        GameTooltip_SetTitle(tooltip, title)
        GameTooltip_AddNormalLine(tooltip, text, true)
        if whyOff and not self:IsEnabled() then GameTooltip_AddErrorLine(tooltip, whyOff, true) end
    end
end

local function attachTip(frame, title, text, whyOff)
    AttachTooltip(frame, fillTip(frame, title, text, whyOff))
end

-- Buttons and hint boxes keep their template's own handlers.
local function hookTip(frame, title, text, whyOff)
    HookTooltip(frame, fillTip(frame, title, text, whyOff))
end

-- Radios and checkboxes with their tooltips. The caller anchors a radio by its LEFT edge, RADIO_INSET
-- into a row, so radio and checkbox labels start at the same x.
local function createRadio(parent, label, tip, whyOff)
    local radio = CreateRadio(parent, label)
    attachTip(radio, label, tip, whyOff)
    return radio
end

local function createCheck(parent, label, tip)
    local check = CreateCheckbox(parent, label)
    attachTip(check, label, tip)
    return check
end

-- A slot spans the When body at a top offset and holds one line of controls.
local function createSlot(body, height)
    local slot = CreateFrame("Frame", nil, body)
    slot:SetHeight(height)
    return slot
end

local function placeSlot(slot, body, top)
    slot:ClearAllPoints()
    slot:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -top)
    slot:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -top)
end

-- Radios in a row, each a padding step after the label before it.
local function createRadioRow(slot, keys, labels, tips, whyOff)
    local radios, previous = {}, nil
    for _, key in ipairs(keys) do
        local radio = createRadio(slot, labels[key], tips[key], whyOff)
        if previous then
            radio:SetPoint("LEFT", previous.label, "RIGHT", PADDING + RADIO_INSET, 0)
        else
            radio:SetPoint("LEFT", slot, "LEFT", RADIO_INSET, 0)
        end
        radios[key] = radio
        previous = radio
    end
    return radios
end

-- The template's Inset becomes the left column and a plain frame the right one, one gap apart on
-- Blizzard's own inset offsets. The window's brown panel spans both, and the gold divider stood on end
-- splits them in the middle of the gap, as high as the padded content.
local function createColumns(frame)
    local left = frame.Inset
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", PANEL_INSET_LEFT_OFFSET + COLUMN_W, BAR_H)

    local right = CreateFrame("Frame", nil, frame)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", GAP, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", PANEL_INSET_RIGHT_OFFSET, BAR_H)

    local background = frame.Background
    background:ClearAllPoints()
    background:SetPoint("TOPLEFT", left)
    background:SetPoint("BOTTOMRIGHT", right)
    local divider = CreateVerticalDivider(background)
    divider:SetPoint("TOP", left, "TOPRIGHT", GAP / 2, -PADDING)
    divider:SetPoint("BOTTOM", left, "BOTTOMRIGHT", GAP / 2, PADDING)
    return left, right
end

-- One help line in the attic, the band between the title bar and the columns, centred on its height.
local function createAtticHelp(frame)
    local atticMiddle = (PANEL_INSET_TOP_OFFSET + PANEL_INSET_ATTIC_OFFSET) / 2
    local line = CreateAtticLine(frame, GameFontHighlight, atticMiddle, PANEL_INSET_RIGHT_OFFSET - PADDING)
    line:SetText(TEXT.ATTIC)
    return line
end

-- The list's scroll area: one padding in from the top, left and bottom, the scroll bar's gutter free on
-- the right.
local function createListScroll(column)
    local scroll = CreateScroll(column)
    scroll:SetPoint("TOPLEFT", PADDING, -PADDING)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLL_GUTTER, PADDING)
    scroll.content:SetWidth(LIST_W)
    return scroll
end

-- Delete asks first, as the macro window's Delete does (CONFIRM_DELETE_SELECTED_MACRO), and names the
-- reminder it would remove. Accept sits left of Cancel, as on Blizzard's popups.
local function createDeleteDialog()
    local dialog = CreateDialog("SimpleRemindersDeleteDialog", ns.title, DIALOG_W)
    dialog:AddText(GameFontHighlight, "Delete this reminder?")
    dialog.subject = dialog:AddText(GameFontDisable, "", TIGHT)
    dialog.subject:SetWordWrap(false)
    dialog.cancelButton = dialog:AddButton(CANCEL, function() dialog:Hide() end)
    dialog.deleteButton = dialog:AddButton(DELETE, nil)
    hookTip(dialog.cancelButton, CANCEL, "Keeps the reminder.")
    hookTip(dialog.deleteButton, DELETE, "Removes the reminder with its note or checklist for good.")
    dialog:Fit()
    return dialog
end

-- The trigger in words: when a countdown or time of day fires next, or which entry a zone waits for.
-- A realm time also shows on the player's own clock when the two differ.
local function describeNext(spec)
    local now = GetServerTime()
    local r = Reminders.Plan(spec, now)
    if r.kind == "zone" then
        return (r.rep and "Fires every time you enter " or "Fires the next time you enter ") .. r.zone .. "."
    end
    local left = Time.FormatLeft(r.due - now)
    if r.kind == "timer" then
        if r.rep then return "Fires in " .. left .. ", then every " .. Time.FormatLeft(r.seconds) .. "." end
        return "Fires in " .. left .. "."
    end
    local _, wday = Time.NextClock(r, now)
    local line = "Next: " .. CALENDAR_WEEKDAY_NAMES[wday] .. " at " .. Time.FormatClock(r.hour, r.minute)
    if r.realm then
        line = line .. " realm time"
        local here = date("*t", r.due)
        if here.hour ~= r.hour or here.min ~= r.minute then
            line = line .. " (" .. Time.FormatClock(here.hour, here.min) .. " local)"
        end
    end
    return line .. ", in " .. left .. "."
end

-- A checklist line in the editable list's layout: the checkbox on the left, the item a gap after it in a hint
-- box indented for its cap, the remove button on the right edge. The last row adds an item and shows only its
-- hint until typed in.
local function createItemRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ITEM_PITCH)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ITEM_PITCH)
    row.index = index
    row.check = createCheck(row, "", "Ticks the item off. It stays in the list.")
    row.check:SetPoint("LEFT")
    row.remove = CreateRemoveButton(row)
    row.remove:SetPoint("RIGHT")
    attachTip(row.remove, REMOVE, "Removes this item.")
    row.box = CreateHintBox(row, "")
    row.box:SetMaxLetters(ns.MAX_LETTERS)
    row.box:SetPoint("LEFT", row.check, "RIGHT", GAP + INPUT_CAP, 0)
    row.box:SetPoint("RIGHT", row.remove, "LEFT", -(GAP + INPUT_CAP), 0)
    return row
end

-- An item row shows its tick and remove button, the add row its hint. A ticked item's text turns grey.
local function styleItem(row, item)
    row.check:SetShown(item ~= nil)
    row.remove:SetShown(item ~= nil)
    row.check:SetChecked(item ~= nil and item.done)
    row.box.Instructions:SetText(item and "" or TEXT.ADD_ITEM)
    row.box:SetTextColor((item and item.done and GRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR):GetRGB())
end

-- When, a section break above Alert: the trigger dropdown with its value, the trigger's own options, the weekdays of a
-- time of day and the preview line, last, so a one-line preview leaves its spare line at the section's end.
local function createWhen(editor, alert)
    local when = CreateSection(editor, "When")
    when:SetPoint("BOTTOMLEFT", alert, "TOPLEFT", 0, SECTION_GAP)
    when:SetPoint("BOTTOMRIGHT", alert, "TOPRIGHT", 0, SECTION_GAP)
    local body = when.body

    when.kindDropdown = CreateDropdown(body, KIND_W)
    when.kindDropdown:SetPoint("LEFT", body, "TOPLEFT", 0, -ROW / 2)
    hookTip(when.kindDropdown, "When", TEXT.WHEN_TIP)
    when.valueBox = CreateHintBox(body, "")
    when.valueBox:SetMaxLetters(ns.MAX_LETTERS)
    when.valueBox:SetPoint("LEFT", when.kindDropdown, "RIGHT", DROPDOWN_ART + GAP + INPUT_CAP, 0)
    when.valueBox:SetPoint("RIGHT", body, "TOPRIGHT", -INPUT_CAP, -ROW / 2)

    local optionSlot = createSlot(body, ROW)
    when.timerRepeat = createCheck(optionSlot, "Repeat", TEXT.TIMER_REPEAT_TIP)
    when.timerRepeat:SetPoint("LEFT")
    when.localCheck = createCheck(optionSlot, TIMEMANAGER_LOCALTIME, TEXT.LOCAL_TIME_TIP)
    when.localCheck:SetPoint("LEFT")
    when.zoneRepeat = createCheck(optionSlot, "Every Time", TEXT.ZONE_REPEAT_TIP)
    when.zoneRepeat:SetPoint("LEFT")
    when.hereButton = CreateButton(optionSlot, "Current Zone")
    when.hereButton:SetPoint("RIGHT")
    hookTip(when.hereButton, "Current Zone", "Fills in the zone you are in.")

    -- Weekdays from Monday, three to a row.
    local daysSlot = createSlot(body, DAYS_H)
    when.dayChecks = {}
    for i, wday in ipairs(ns.WEEK_ORDER) do
        local check = createCheck(daysSlot, CALENDAR_WEEKDAY_NAMES[wday], TEXT.DAY_TIP)
        local column, line = (i - 1) % DAY_COLUMNS, math.floor((i - 1) / DAY_COLUMNS)
        check:SetPoint("TOPLEFT", daysSlot, "TOPLEFT", column * DAY_W, -line * (ROW + TIGHT))
        when.dayChecks[wday] = check
    end

    when.preview = CreateText(body, GameFontHighlight)
    when.preview:SetHeight(PREVIEW_H)
    when.preview:SetJustifyV("TOP")
    when.preview:SetWordWrap(true)

    -- The trigger decides which fields show. A countdown has Repeat, a time of day Use Local Time and the
    -- weekdays, a zone Every Time and the Current Zone button. None shows only its preview line.
    function when:Layout(kind)
        local isNone, isClock, isZone = kind == "none", kind == "clock", kind == "zone"
        self.valueBox:SetShown(not isNone)
        local top = ROW + GAP
        optionSlot:SetShown(not isNone)
        if not isNone then
            placeSlot(optionSlot, body, top)
            self.timerRepeat:SetShown(kind == "timer")
            self.localCheck:SetShown(isClock)
            self.zoneRepeat:SetShown(isZone)
            self.hereButton:SetShown(isZone)
            top = top + ROW + GAP
        end
        daysSlot:SetShown(isClock)
        if isClock then
            placeSlot(daysSlot, body, top)
            top = top + DAYS_H + GAP
        end
        self.preview:ClearAllPoints()
        self.preview:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -top)
        self.preview:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -top)
        self:SetHeight(SECTION_BODY_TOP + top + PREVIEW_H)
    end

    return when
end

-- Alert, held to the detail's bottom: the outputs with Test, then Character Specific. The outputs and Test grey out
-- while the reminder never fires, as Blizzard's Settings grey a row that does not apply, so nothing moves.
local function createAlert(editor)
    local alert = CreateSection(editor, "Alert")
    alert:SetPoint("BOTTOMLEFT")
    alert:SetPoint("BOTTOMRIGHT")
    alert:SetHeight(ALERT_H)
    local body = alert.body

    local sendSlot = createSlot(body, ROW)
    placeSlot(sendSlot, body, 0)
    alert.outputRadios = createRadioRow(sendSlot, ns.OUTPUTS, ns.OUTPUT_LABELS, TEXT.OUTPUT_TIPS, TEXT.NEVER_FIRES)
    alert.testButton = CreateButton(sendSlot, "Test")
    alert.testButton:SetPoint("RIGHT")
    hookTip(alert.testButton, "Test", "Shows the alert once now, the way it arrives.", TEXT.NEVER_FIRES)

    alert.characterCheck = createCheck(body, TEXT.CHARACTER_LABEL, TEXT.CHARACTER_TIP)
    alert.characterCheck:SetPoint("TOPLEFT", 0, -(ROW + GAP))

    function alert:SetFires(fires)
        for _, radio in pairs(self.outputRadios) do
            radio:SetEnabled(fires)
            radio:GetCheckedTexture():SetDesaturated(not fires)
            radio.label:SetFontObject(fires and GameFontHighlight or GameFontDisable)
        end
        self.testButton:SetEnabled(fires)
    end

    return alert
end

local function buildPanel()
    local frame = CreateWindow("SimpleRemindersFrame", ns.title, ns.ICON, PANEL_W, PANEL_H, SimpleRemindersDB.window)
    local left, right = createColumns(frame)
    createAtticHelp(frame)

    -- selected is the stored reminder the detail shows, nil while it shows none. The form holds its picks;
    -- every change saves at once.
    local form = picksOf({ kind = "none", output = ns.DEFAULT_OUTPUT, body = "note", items = {} })
    local selected

    -- Reminders list: rows by list place, made on first need and hidden past the end of the list.
    local scroll = createListScroll(left)
    local emptyList = CreateEmptyState(left, TEXT.EMPTY_LIST)
    local rows, shownRows = {}, 0

    -- The detail spans the right column inside its padding, and says what to do while no reminder is picked.
    local editor = CreateFrame("Frame", nil, right)
    editor:SetPoint("TOPLEFT", PADDING, -PADDING)
    editor:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    local emptyEditor = CreateEmptyState(right)

    -- The title, the edit box's art inset by its cap on both sides.
    local titleBox = CreateHintBox(editor, TEXT.TITLE_HINT)
    titleBox:SetMaxLetters(ns.MAX_LETTERS)
    titleBox:SetPoint("TOPLEFT", INPUT_CAP, -(ROW - 20) / 2)
    titleBox:SetPoint("TOPRIGHT", -INPUT_CAP, -(ROW - 20) / 2)
    hookTip(titleBox, TEXT.TITLE_HINT, TEXT.TITLE_TIP)

    -- Note or Checklist, a gap under the title.
    local bodySlot = createSlot(editor, ROW)
    placeSlot(bodySlot, editor, ROW + GAP)
    local bodyRadios = createRadioRow(bodySlot, ns.BODIES, ns.BODY_LABELS, TEXT.BODY_TIPS)

    -- Alert at the detail's bottom and When above it; the note or checklist fills the space above When down to a
    -- section break, so it grows while the trigger needs fewer fields.
    local alert = createAlert(editor)
    local outputRadios, characterCheck = alert.outputRadios, alert.characterCheck
    local when = createWhen(editor, alert)
    local valueBox, preview = when.valueBox, when.preview
    local timerRepeat, localCheck, zoneRepeat, dayChecks = when.timerRepeat, when.localCheck, when.zoneRepeat, when.dayChecks

    local note = CreateNoteBox(editor, TEXT.NOTE_HINT, BODY_W - 2 * INPUT_CAP, ns.MAX_LETTERS)
    note:SetPoint("TOPLEFT", INPUT_CAP, -(CONTENT_TOP + INPUT_CAP))
    note:SetPoint("BOTTOMRIGHT", when, "TOPRIGHT", -INPUT_CAP, SECTION_GAP + INPUT_CAP)

    local checklist = CreateScroll(editor)
    checklist:SetPoint("TOPLEFT", 0, -CONTENT_TOP)
    checklist:SetPoint("BOTTOMRIGHT", when, "TOPRIGHT", -SCROLL_GUTTER, SECTION_GAP)
    checklist.content:SetWidth(BODY_W - SCROLL_GUTTER)
    local itemRows = {}

    HookTooltip(valueBox, function(tooltip)
        GameTooltip_SetTitle(tooltip, ns.KIND_LABELS[form.kind])
        GameTooltip_AddNormalLine(tooltip, TEXT.VALUE_TIPS[form.kind], true)
    end)

    local newButton = CreateBarButton(frame, TEXT.NEW_LABEL, "BOTTOMRIGHT", PANEL_INSET_RIGHT_OFFSET - PADDING)
    local deleteButton = CreateBarButton(frame, DELETE, "BOTTOMLEFT", PANEL_INSET_LEFT_OFFSET + PADDING)
    newButton:SetScript("OnClick", function() frame:NewReminder() end)
    deleteButton:SetScript("OnClick", function() frame:DeleteSelected() end)
    local deleteDialog = createDeleteDialog()
    hookTip(newButton, TEXT.NEW_LABEL, "Adds a reminder and opens it here.")
    hookTip(deleteButton, DELETE, "Removes the reminder shown here, after asking.", "Pick a reminder on the left first.")
    local showTip, retireTip = AttachTip(newButton, TEXT.TIP_TEXT, HelpTip.Point.RightEdgeCenter)
    frame.showTip = showTip

    -- The trigger as a spec, or nil and the problem. An empty value is no problem yet, only unfinished.
    local function readWhen()
        if form.kind == "none" then return { kind = "none" } end
        local value = ns.trim(valueBox:GetText())
        if value == "" then return nil end
        local spec = { kind = form.kind, rep = form.rep }
        if form.kind == "timer" then
            spec.seconds = Time.ParseDuration(value)
            if not spec.seconds then return nil, ns.NEED_DURATION end
        elseif form.kind == "clock" then
            spec.hour, spec.minute = Time.ParseClock(value)
            if not spec.hour then return nil, ns.NEED_CLOCK end
            spec.realm = form.realm
            spec.rep = {}
            for _, wday in ipairs(ns.WEEK_ORDER) do
                if form.days[wday] then spec.rep[#spec.rep + 1] = wday end
            end
        else
            spec.zone = value
        end
        return spec
    end

    -- Every change saves the whole form. An unfinished trigger keeps the stored one until it reads.
    local function commit()
        if not selected then return end
        local spec = readWhen() or triggerOf(selected)
        spec.output = form.output
        spec.title = titleBox:GetText()
        spec.body = form.body
        spec.note = note.EditBox:GetText()
        spec.items = form.items
        spec.character = form.character and ns.character or nil
        Reminders.Update(selected, spec)
    end

    -- The preview says what the trigger will do as it is typed.
    local function refreshForm()
        local spec, problem = readWhen()
        if spec and spec.kind ~= "none" then
            preview:SetText(describeNext(spec))
        elseif problem then
            preview:SetText(RED_FONT_COLOR:WrapTextInColorCode(problem))
        else
            preview:SetText(GRAY_FONT_COLOR:WrapTextInColorCode(TEXT.PREVIEW_HINTS[form.kind]))
        end
    end

    -- The checklist's rows follow the form's items, with the add row after the last.
    local function itemRow(index)
        local row = itemRows[index]
        if row then return row end
        row = createItemRow(checklist.content, index)
        row.check:SetScript("OnClick", function(check)
            form.items[row.index].done = check:GetChecked()
            styleItem(row, form.items[row.index])
            commit()
        end)
        row.remove:SetScript("OnClick", function()
            table.remove(form.items, row.index)
            frame:RenderItems()
            commit()
        end)
        -- Typing in the add row makes it an item and opens a new add row under it.
        row.box:HookScript("OnTextChanged", function(box, userInput)
            if not userInput then return end
            local item = form.items[row.index]
            if item then
                item.text = box:GetText()
            elseif box:GetText() ~= "" then
                form.items[row.index] = { text = box:GetText(), done = false }
                styleItem(row, form.items[row.index])
                local addRow = itemRow(row.index + 1)
                addRow.box:SetText("")
                styleItem(addRow, nil)
                addRow:Show()
                checklist.content:SetHeight(#form.items * ITEM_PITCH + ROW)
            end
            commit()
        end)
        -- Enter and Tab move to the next row, the last row lets go of the keyboard.
        local function nextRow()
            local after = itemRows[row.index + 1]
            if after and after:IsShown() then
                after.box:SetFocus()
                Reveal(checklist, row.index * ITEM_PITCH, row.index * ITEM_PITCH + ROW)
            else
                row.box:ClearFocus()
            end
        end
        row.box:SetScript("OnEnterPressed", nextRow)
        row.box:SetScript("OnTabPressed", nextRow)
        itemRows[index] = row
        return row
    end

    function frame:RenderItems()
        local count = #form.items
        for i = 1, count + 1 do
            local row = itemRow(i)
            row.box:SetText(form.items[i] and form.items[i].text or "")
            row.box:SetCursorPosition(0)
            styleItem(row, form.items[i])
            row:Show()
        end
        for i = count + 2, #itemRows do itemRows[i]:Hide() end
        checklist.content:SetHeight(count * ITEM_PITCH + ROW)
    end

    -- The radios, checkboxes and dropdown show the picks, and the detail the fields they need.
    local function showPicks()
        for body, radio in pairs(bodyRadios) do radio:SetChecked(body == form.body) end
        for output, radio in pairs(outputRadios) do radio:SetChecked(output == form.output) end
        alert:SetFires(form.kind ~= "none")
        characterCheck:SetChecked(form.character)
        timerRepeat:SetChecked(form.rep)
        zoneRepeat:SetChecked(form.rep)
        localCheck:SetChecked(not form.realm)
        for wday, check in pairs(dayChecks) do check:SetChecked(form.days[wday] == true) end
        valueBox.Instructions:SetText(TEXT.VALUE_HINTS[form.kind] or "")
        note:SetShown(form.body == "note")
        checklist:SetShown(form.body == "checklist")
        when:Layout(form.kind)
        refreshForm()
    end

    -- The detail shows while a reminder is picked, the empty line otherwise, and the picked row is lit.
    local function refreshMode()
        editor:SetShown(selected ~= nil)
        emptyEditor:SetShown(selected == nil)
        emptyEditor:SetText(shownRows == 0 and TEXT.EMPTY_FIRST or TEXT.EMPTY_PICK)
        deleteButton:SetEnabled(selected ~= nil)
        for i = 1, shownRows do rows[i]:SetSelected(rows[i].reminder == selected) end
    end

    local function clearFocus()
        titleBox:ClearFocus()
        note.EditBox:ClearFocus()
        valueBox:ClearFocus()
        for _, row in ipairs(itemRows) do row.box:ClearFocus() end
    end

    -- A reminder New Reminder made goes again when it is left without a word in it.
    local function leave()
        if selected and isEmpty(selected) then Reminders.Remove(selected) end
    end

    -- Countdowns tick down in place, without measuring the rows again.
    function frame:RefreshTimes()
        local now = GetServerTime()
        for i = 1, shownRows do
            rows[i].detail:SetText(Reminders.Detail(rows[i].reminder, now))
        end
        refreshForm()
    end

    -- Each row is as tall as its title wraps, plus the muted line when it has one.
    local _, detailHeight = GameFontDisable:GetFont()
    local function fillRow(row, r, now)
        row.reminder = r
        row.name:SetText(r.title ~= "" and r.title or GRAY_FONT_COLOR:WrapTextInColorCode(ns.UNTITLED))
        local nameHeight = math.ceil(row.name:GetStringHeight())
        row.name:SetHeight(nameHeight)
        local detail = Reminders.Detail(r, now)
        row.detail:SetText(detail)
        row.detail:SetShown(detail ~= "")
        local height = ROW_PAD + nameHeight + ROW_PAD
        if detail ~= "" then height = height + TIGHT + math.ceil(detailHeight) end
        row:SetHeight(height)
    end

    function frame:RefreshList()
        local sorted = Reminders.Sorted()
        local now = GetServerTime()
        emptyList:SetShown(#sorted == 0)
        local top = 0
        for i, r in ipairs(sorted) do
            local row = rows[i]
            if not row then
                row = CreateListRow(scroll.content, LIST_W - 2 * LIST_INDENT)
                row:SetScript("OnClick", function() frame:Select(row.reminder) end)
                rows[i] = row
            end
            fillRow(row, r, now)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -top)
            row:SetPoint("TOPRIGHT", 0, -top)
            row.top = top
            row:Show()
            top = top + row:GetHeight() + LIST_GAP
        end
        for i = #sorted + 1, #rows do
            rows[i]:Hide()
            rows[i].reminder = nil
        end
        shownRows = #sorted

        -- A reminder removed by command or by Delete leaves the detail.
        if selected and not tContains(sorted, selected) then selected = nil end
        refreshMode()

        -- The scroll child follows the list, and the offset comes back into range when it shrinks.
        scroll.content:SetHeight(math.max(top - LIST_GAP, 1))
        scroll:UpdateScrollChildRect()
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange()))
        refreshForm()
    end

    -- Scrolls the list to the picked reminder's row.
    local function revealSelected()
        for i = 1, shownRows do
            local row = rows[i]
            if row.reminder == selected then Reveal(scroll, row.top, row.top + row:GetHeight()) end
        end
    end

    -- Shows a stored reminder in the detail, after letting go of an empty one left behind.
    function frame:Select(r)
        if r == selected then return end
        clearFocus()
        leave()
        selected = r
        form = picksOf(r)
        titleBox:SetText(r.title)
        note.EditBox:SetText(r.note)
        valueBox:SetText(valueOf(r))
        titleBox:SetCursorPosition(0)
        valueBox:SetCursorPosition(0)
        self:RenderItems()
        when.kindDropdown:GenerateMenu()
        note:SetVerticalScroll(0)
        checklist:SetVerticalScroll(0)
        showPicks()
        refreshMode()
        revealSelected()
    end

    -- Loads the picked reminder again from what is stored, when the window opens or after it fired.
    function frame:Reload(fired)
        local r = selected
        if not r or (fired and fired ~= r) then return end
        selected = nil
        self:Select(r)
    end

    -- Adds a reminder without a trigger and puts the keyboard in its title. An empty one already picked is
    -- used as it is.
    function frame:NewReminder()
        retireTip()
        if not (selected and isEmpty(selected)) then
            self:Select(Reminders.Add({ title = "", kind = "none", output = ns.DEFAULT_OUTPUT }))
        end
        titleBox:SetFocus()
    end

    function frame:DeleteSelected()
        if not selected then return end
        deleteDialog.reminder = selected
        deleteDialog.subject:SetText(Reminders.Name(selected))
        deleteDialog:Show()
    end

    -- Removes the reminder the dialog names, even if another was picked meanwhile.
    function frame:ConfirmDelete()
        local r = deleteDialog.reminder
        deleteDialog.reminder = nil
        deleteDialog:Hide()
        if r then Reminders.Remove(r) end
    end

    -- A trigger change empties the value, which means something else under each trigger.
    local function setKind(kind)
        if form.kind ~= kind then
            form.kind, form.rep, form.days = kind, false, {}
            valueBox:SetText("")
        end
        showPicks()
        commit()
    end

    when.kindDropdown:SetupMenu(function(_, rootDescription)
        for _, kind in ipairs(ns.KINDS) do
            local radio = rootDescription:CreateRadio(ns.KIND_LABELS[kind], function() return form.kind == kind end, function()
                setKind(kind)
            end)
            radio:SetTooltip(function(tooltip)
                GameTooltip_SetTitle(tooltip, ns.KIND_LABELS[kind])
                GameTooltip_AddNormalLine(tooltip, TEXT.KIND_TIPS[kind], true)
            end)
        end
    end)

    -- A click on a radio picks it, and showPicks checks it again even when it was picked already.
    for body, radio in pairs(bodyRadios) do
        radio:SetScript("OnClick", function()
            form.body = body
            showPicks()
            commit()
        end)
    end
    for output, radio in pairs(outputRadios) do
        radio:SetScript("OnClick", function()
            form.output = output
            showPicks()
            commit()
        end)
    end

    characterCheck:SetScript("OnClick", function(check)
        form.character = check:GetChecked()
        commit()
    end)

    local function onRepeat(check)
        form.rep = check:GetChecked()
        showPicks()
        commit()
    end
    timerRepeat:SetScript("OnClick", onRepeat)
    zoneRepeat:SetScript("OnClick", onRepeat)

    localCheck:SetScript("OnClick", function(check)
        form.realm = not check:GetChecked()
        refreshForm()
        commit()
    end)

    for wday, check in pairs(dayChecks) do
        check:SetScript("OnClick", function()
            form.days[wday] = check:GetChecked() or nil
            refreshForm()
            commit()
        end)
    end

    alert.testButton:SetScript("OnClick", function()
        local title = ns.trim(titleBox:GetText())
        Reminders.Preview(form.output, title ~= "" and title or ns.UNTITLED)
    end)

    when.hereButton:SetScript("OnClick", function()
        valueBox:SetText(GetZoneText())
        valueBox:SetCursorPosition(0)
        refreshForm()
        commit()
    end)

    deleteDialog.deleteButton:SetScript("OnClick", function() frame:ConfirmDelete() end)

    -- Enter or Tab in the title moves on to the note or the checklist's add row.
    local function toContent()
        if form.body == "note" then
            note.EditBox:SetFocus()
        else
            local index = #form.items + 1
            itemRows[index].box:SetFocus()
            Reveal(checklist, (index - 1) * ITEM_PITCH, (index - 1) * ITEM_PITCH + ROW)
        end
    end
    titleBox:SetScript("OnEnterPressed", toContent)
    titleBox:SetScript("OnTabPressed", toContent)
    valueBox:SetScript("OnEnterPressed", valueBox.ClearFocus)

    -- Hooked, so the templates' own handlers keep hiding the hints while there is text. Typing saves.
    local function onTyped(_, userInput)
        if userInput then commit() end
    end
    titleBox:HookScript("OnTextChanged", onTyped)
    note.EditBox:HookScript("OnTextChanged", onTyped)
    valueBox:HookScript("OnTextChanged", function(_, userInput)
        refreshForm()
        if userInput then commit() end
    end)

    local ticker
    frame:SetScript("OnShow", function(self)
        self:RefreshList()
        self:Reload()
        ticker = C_Timer.NewTicker(1, function() self:RefreshTimes() end)
    end)
    frame:SetScript("OnHide", function()
        clearFocus()
        leave()
        ticker:Cancel()
        deleteDialog:Hide()
    end)

    panel = frame
    return frame
end

-- One toggle for /rm, the minimap button and the addon menu. The window is built on first use.
ns.TogglePanel = CreateToggle(buildPanel)

-- Opens the window and keeps it open, for the welcome link and /rm edit.
function ns.OpenPanel()
    if not (panel and panel:IsShown()) then ns.TogglePanel() end
end

-- Opens the window with a reminder in the detail, for its chat link and /rm edit.
function ns.EditInPanel(r)
    ns.OpenPanel()
    panel:Select(r)
end

-- /rm intro brings the help tip back at once while the window is open, else at its next open.
function ns.ShowTip()
    if panel and panel:IsVisible() then panel.showTip() end
end

-- Called after any change to the reminders, so an open window mirrors them. A reminder that fired is loaded
-- again when it is the one shown, since firing changed its trigger.
function ns.RefreshPanel(fired)
    if not (panel and panel:IsShown()) then return end
    panel:RefreshList()
    if fired then panel:Reload(fired) end
end
