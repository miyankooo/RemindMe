local _, ns = ...

local Time = ns.Time
local Reminders = ns.Reminders

-- Spacing roles on the 4 px grid: tight from label to control, gap between related controls, padding
-- inside a column. Rows, checkboxes and content buttons are 24 tall, a heading line 16.
local TIGHT, GAP, PADDING = 4, 8, 16
local ROW, HEADING = 24, 16

-- InputBoxTemplate draws its left cap 5 px outside the box (Shared/InputBox/InputBoxTemplates.xml:49),
-- so a box sits in by that much to line its art up with the column.
local INPUT_CAP = 5

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

-- Rounds a length derived from text up to the 4 px grid.
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

-- UIRadioButtonTemplate, 16 px, centred in a 24 px row like the checkbox, with the same clickable body label.
-- The caller unchecks the other radios of its group in OnClick.
local RADIO_SIZE = 16
local RADIO_INSET = (24 - RADIO_SIZE) / 2
local function CreateRadio(parent, label)
    local radio = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
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

-- An inset's border on the stone without its marble tile, as the Auction House category list
-- (Blizzard_AuctionHouseCategoriesList.xml:60). For a status box in the button bar or a block on a settings page,
-- never on the brown panel.
local function CreateInset(parent)
    local inset = CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
    inset.Bg:Hide()
    return inset
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

-- A ScrollFrameTemplate with its scroll child. Leave the 24 px gutter free on its right for the bar.
local function CreateScroll(parent, name)
    local scroll = CreateFrame("ScrollFrame", name, parent, "ScrollFrameTemplate")
    scroll.content = CreateFrame("Frame", nil, scroll)
    scroll.content:SetSize(1, 1)
    scroll:SetScrollChild(scroll.content)
    return scroll
end

-- A selectable row in a list on the brown panel, from the pet journal (Blizzard_Collections): the dark tile, the gold
-- selection outline and the hover glow, stretched to the row. A name in heading over one muted detail line, both cut
-- rather than wrapped. Rows are 44 tall, 4 apart, text 12 in from the sides and 8 from the top.
local LIST_ROW, LIST_PITCH, LIST_INSET, LIST_TOP = 44, 48, 12, 8
local function CreateListRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(LIST_ROW)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * LIST_PITCH)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * LIST_PITCH)
    local tile = row:CreateTexture(nil, "BACKGROUND")
    tile:SetAtlas("PetList-ButtonBackground")
    tile:SetAllPoints()
    row.selected = row:CreateTexture(nil, "OVERLAY")
    row.selected:SetAtlas("PetList-ButtonSelect")
    row.selected:SetAllPoints()
    row.selected:Hide()
    row:SetHighlightAtlas("PetList-ButtonHighlight")
    row.name = CreateText(row, GameFontNormal)
    row.name:SetPoint("TOPLEFT", LIST_INSET, -LIST_TOP)
    row.name:SetPoint("TOPRIGHT", -LIST_INSET, -LIST_TOP)
    row.name:SetWordWrap(false)
    row.detail = CreateText(row, GameFontDisable)
    row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
    row.detail:SetPoint("TOPRIGHT", row.name, "BOTTOMRIGHT", 0, -4)
    row.detail:SetWordWrap(false)
    return row
end

-- An empty list says what fills it and how, in one muted line centred in the list.
local function CreateEmptyState(parent, text)
    local empty = CreateText(parent, GameFontDisable)
    empty:SetPoint("LEFT", 16, 0)
    empty:SetPoint("RIGHT", -16, 0)
    empty:SetJustifyH("CENTER")
    empty:SetText(text)
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
        onAcknowledgeCallback = function() RemindMeDB.tipSeen = true end,
    }
    local function ShowTip()
        if RemindMeDB.tipSeen or (tip and tip:IsShown()) then return end
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
        if tip and tip.info then tip:Acknowledge() else RemindMeDB.tipSeen = true end
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

-- A MagicButtonTemplate bar button, 128 wide: the first takes the bottom-right corner, later ones chain leftwards.
-- MagicButton_OnLoad runs after the anchor so Blizzard applies its corner and neighbour spacing.
local function AddBarButton(window, label, onClick, width)
    local button = CreateFrame("Button", nil, window, "MagicButtonTemplate")
    button:SetWidth(width or 128)
    window.barButtons = window.barButtons or {}
    local previous = window.barButtons[#window.barButtons]
    if previous then
        button:SetPoint("RIGHT", previous, "LEFT")
    else
        button:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT")
    end
    MagicButton_OnLoad(button)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    window.barButtons[#window.barButtons + 1] = button
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
local DIALOG_SIDE, DIALOG_TOP, SECTION_GAP = 20, 40, 24
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
    -- art, 5 for an edit box, 8 for a dropdown. The gap defaults to 8; AddText passes a section break.
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

    -- 40 top, the content, a section break and the button row if there are buttons, 20 bottom, on the grid.
    function dialog:Fit()
        local height = DIALOG_TOP + self.contentHeight + DIALOG_SIDE
        if #self.buttons > 0 then height = height + SECTION_GAP + 24 end
        self:SetHeight(Snap(height))
    end

    MakeMovable(dialog, name, "DIALOG", position)
    return dialog
end

-- Laid out like Blizzard's macro window (Blizzard_MacroUI.xml): a list to pick from, an editor for
-- the picked entry, Delete in the bar's bottom-left corner and New beside the primary button. Two
-- equal columns: the reminders on the left, the editor on the right. The outer width carries
-- Blizzard's 4/-6 inset offsets, so it is 674.
local COLUMN_W = 328
local PANEL_W = PANEL_INSET_LEFT_OFFSET + 2 * COLUMN_W + GAP - PANEL_INSET_RIGHT_OFFSET

-- The editor's inner width, and the half a short value box takes so a checkbox fits beside it.
local BODY_W = COLUMN_W - 2 * PADDING
local HALF_W = (BODY_W - GAP) / 2

-- Rows stacked a tight gap apart: the weekdays in three columns and the outputs.
local function stackHeight(rows)
    return rows * ROW + (rows - 1) * TIGHT
end
local DAY_COLUMNS = 3
local DAY_W = 4 * math.floor((BODY_W + GAP) / DAY_COLUMNS / 4)
local DAYS_H = stackHeight(math.ceil(#ns.WEEK_ORDER / DAY_COLUMNS))
local OUTPUTS_H = stackHeight(#ns.OUTPUTS)

-- The preview line under When has room for two lines.
local PREVIEW_H = 2 * HEADING

-- The editor's longest layout, Time of Day: padding, three section heads, two section breaks, the
-- message box, the When body (trigger, time, weekdays and preview) and the outputs.
local WHEN_CLOCK_H = 2 * (ROW + GAP) + DAYS_H + GAP + PREVIEW_H
local EDITOR_H = 2 * PADDING + 3 * SECTION_BODY_TOP + 2 * SECTION_GAP + ROW + WHEN_CLOCK_H + OUTPUTS_H

-- The template's attic keeps the columns below the portrait, which hangs 55px down from the top edge
-- (Mainline/SharedUIPanelTemplates.xml:584). The attic and button bar offsets (60 and 26) are off
-- the grid, so the height snaps up and the extra px fall into the columns' bottom padding.
local PANEL_H = Snap(-PANEL_INSET_ATTIC_OFFSET + EDITOR_H + PANEL_INSET_BOTTOM_BUTTON_OFFSET)

local LIST_W = COLUMN_W - PADDING - SCROLL_GUTTER

-- The window's player-facing text, kept in one table: as separate locals the panel builder would pass Lua 5.1's
-- limit of 60 upvalues per function, and the client refuses to load the file.
local TEXT = {
    -- The empty list says how to fill it, centred in the left column.
    EMPTY_TEXT = "No reminders yet. Add one on the right.",

    -- The help tip stands right of the primary button, outside the window, until the first reminder is added.
    TIP_TEXT = "Type a message and when it fires, then click Add Reminder to set it.",

    -- The attic line names the mode and the next step.
    HELP_NEW = "Fill in a new reminder, or click one on the left to change it.",
    HELP_EDIT = "Changes save with Save, or when you pick another reminder or close the window.",

    ADD_LABEL = "Add Reminder",
    NEW_LABEL = "New Reminder",

    -- What the empty value field asks for under each trigger.
    VALUE_HINTS = { timer = "30m or 1h 30m", clock = "20:30 or 8:30 PM", zone = "Stormwind City" },

    -- The preview line while the value field is empty: what the trigger does.
    PREVIEW_HINTS = {
        timer = "Fires once the countdown runs out.",
        clock = "Fires once, or on every weekday you tick.",
        zone = "Fires when you enter this zone or an area in it.",
    },

    -- Tooltips for the choices, so each says what it does before it is picked.
    KIND_TIPS = {
        timer = "Fires once a countdown runs out, such as 30m or 1h 30m.",
        clock = "Fires at a time of day, once or on the weekdays you tick.",
        zone = "Fires when you enter a zone or an area in it, such as Stormwind or Trade District.",
    },
    OUTPUT_TIPS = {
        whisper = "A pink whisper line in chat with the whisper sound. Only you see it.",
        print = "A yellow line in your main chat tab, without a sound.",
        warning = "Large text across the middle of the screen with the raid warning sound, and a chat line. Only you see it.",
    },
    TIMER_REPEAT_TIP = "Starts the countdown again each time it fires.",
    ZONE_REPEAT_TIP = "Fires on every entry, not only the next one.",
    LOCAL_TIME_TIP = "Use your computer's clock instead of the realm clock.",
    DAY_TIP = "Fires on this day every week. With no day ticked, it fires once.",
    MESSAGE_TIP = "What the reminder says when it fires.",
    VALUE_TIPS = {
        timer = "How long until it fires, such as 90s, 30m or 1h 30m.",
        clock = "The time it fires, such as 20:30 or 8:30 PM.",
        zone = "The zone or an area in it, such as Stormwind City or Trade District.",
    },
    INCOMPLETE_TIP = "Type a message and when it fires first.",
}

local DIALOG_W = 400

-- The picks a new reminder starts from. The clock follows the player's minimap clock setting.
-- rep is the Repeat or Every Time tick, days the ticked weekdays of a time of day.
local function newPicks()
    return { kind = "timer", output = ns.DEFAULT_OUTPUT, realm = ns.DefaultRealm(), rep = false, days = {} }
end

-- The picks of a stored reminder. Every day ticks all seven weekdays.
local function picksOf(r)
    local picks = newPicks()
    picks.kind, picks.output = r.kind, r.output
    if r.kind == "clock" then
        picks.realm = r.realm
        for _, wday in ipairs(ns.WEEK_ORDER) do
            picks.days[wday] = (r.rep == true or (type(r.rep) == "table" and tContains(r.rep, wday))) or nil
        end
    else
        picks.rep = r.rep == true
    end
    return picks
end

local panel

-- A title and one help line. Buttons and hint boxes keep their template's own handlers.
local function fillTip(title, text)
    return function(tooltip)
        GameTooltip_SetTitle(tooltip, title)
        GameTooltip_AddNormalLine(tooltip, text, true)
    end
end

local function attachTip(frame, title, text)
    AttachTooltip(frame, fillTip(title, text))
end

local function hookTip(frame, title, text)
    HookTooltip(frame, fillTip(title, text))
end

-- A bar button explains why it is off, as Blizzard's dungeon finder does, so it takes the mouse while
-- disabled too.
local function hookBarTip(button, fill)
    button:SetMotionScriptsWhileDisabled(true)
    HookTooltip(button, function(tooltip, self)
        local title, text, whyOff = fill()
        GameTooltip_SetTitle(tooltip, title)
        GameTooltip_AddNormalLine(tooltip, text, true)
        if not self:IsEnabled() then GameTooltip_AddErrorLine(tooltip, whyOff, true) end
    end)
end

-- Radios and checkboxes with their tooltips. The caller anchors a radio by its LEFT edge, RADIO_INSET
-- into a row, so radio and checkbox labels start at the same x.
local function createRadio(parent, label, tip)
    local radio = CreateRadio(parent, label)
    attachTip(radio, label, tip)
    return radio
end

local function createCheck(parent, label, tip)
    local check = CreateCheckbox(parent, label)
    attachTip(check, label, tip)
    return check
end

-- A section's height follows its body.
local function setBodyHeight(section, height)
    section:SetHeight(SECTION_BODY_TOP + height)
end

-- A slot spans a section body at a top offset and holds one line of controls.
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

-- The left column's scroll area: one padding in from the top, left and bottom, the scroll bar's
-- gutter free on the right. The bar hides while every row fits.
local function createListScroll(column)
    local scroll = CreateScroll(column)
    scroll.ScrollBar:SetHideIfUnscrollable(true)
    scroll:SetPoint("TOPLEFT", PADDING, -PADDING)
    scroll:SetPoint("BOTTOMRIGHT", -SCROLL_GUTTER, PADDING)
    scroll.content:SetWidth(LIST_W)
    return scroll
end

-- The template's Inset becomes the left column and a plain frame the right one, one gap apart on
-- Blizzard's own inset offsets. The window's brown panel spans both, and the gold divider stood on end
-- splits them in the middle of the gap, as high as the padded content.
local function createColumns(frame)
    local left = frame.Inset
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", PANEL_INSET_LEFT_OFFSET + COLUMN_W, PANEL_INSET_BOTTOM_BUTTON_OFFSET)

    local right = CreateFrame("Frame", nil, frame)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", GAP, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", PANEL_INSET_RIGHT_OFFSET, PANEL_INSET_BOTTOM_BUTTON_OFFSET)

    local background = frame.Background
    background:ClearAllPoints()
    background:SetPoint("TOPLEFT", left)
    background:SetPoint("BOTTOMRIGHT", right)
    local divider = CreateVerticalDivider(background)
    divider:SetPoint("TOP", left, "TOPRIGHT", GAP / 2, -PADDING)
    divider:SetPoint("BOTTOM", left, "BOTTOMRIGHT", GAP / 2, PADDING)
    return left, right
end

-- One line in the attic, the band between the title bar and the columns, centred on the band's height.
local function createAtticHelp(frame)
    local atticMiddle = (PANEL_INSET_TOP_OFFSET + PANEL_INSET_ATTIC_OFFSET) / 2
    return CreateAtticLine(frame, GameFontHighlight, atticMiddle, PANEL_INSET_RIGHT_OFFSET - PADDING)
end

-- Delete takes the bar's bottom-left corner, as MacroDeleteButton does. MagicButton_OnLoad runs
-- after the zero-offset anchor so Blizzard applies its corner inset, as AddBarButton does.
local function createDeleteButton(frame)
    local button = CreateFrame("Button", nil, frame, "MagicButtonTemplate")
    button:SetWidth(128)
    button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
    MagicButton_OnLoad(button)
    button:SetText(DELETE)
    return button
end

-- The status sits in an inset that fills the button bar between Delete and New Reminder.
local function createStatus(frame, leftButton, rightButton)
    local box = CreateInset(frame)
    box:SetPoint("BOTTOMLEFT", leftButton, "BOTTOMRIGHT", GAP, 0)
    box:SetPoint("TOPRIGHT", rightButton, "TOPLEFT", -GAP, 0)

    local status = CreateText(box, GameFontHighlight)
    status:SetPoint("LEFT", GAP, 0)
    status:SetPoint("RIGHT", -GAP, 0)
    status:SetWordWrap(false)
    return status
end

-- Delete asks first, as the macro window's Delete does (CONFIRM_DELETE_SELECTED_MACRO), and names the
-- reminder it would remove. Accept sits left of Cancel, as on Blizzard's popups.
local function createDeleteDialog()
    local dialog = CreateDialog("RemindMeDeleteDialog", ns.title, DIALOG_W)
    dialog:AddText(GameFontHighlight, "Delete this reminder?")
    dialog.subject = dialog:AddText(GameFontDisable, "", TIGHT)
    dialog.subject:SetWordWrap(false)
    dialog.cancelButton = dialog:AddButton(CANCEL, function() dialog:Hide() end)
    dialog.deleteButton = dialog:AddButton(DELETE, nil)
    hookTip(dialog.cancelButton, CANCEL, "Keeps the reminder.")
    hookTip(dialog.deleteButton, DELETE, "Removes the reminder for good.")
    dialog:Fit()
    return dialog
end

-- The full text and trigger, for rows whose text the row cuts off.
local function fillRowTooltip(tooltip, row)
    GameTooltip_SetTitle(tooltip, row.reminder.text, nil, true)
    GameTooltip_AddNormalLine(tooltip, Reminders.Detail(row.reminder, GetServerTime()), true)
    GameTooltip_AddInstructionLine(tooltip, "Click to edit this reminder.")
end

-- A reminder's row at its place in the list: its text over its trigger line. A click loads it into
-- the editor.
local function createRow(parent, index, onClick)
    local row = CreateListRow(parent, index)
    row:SetScript("OnClick", function() onClick(row.reminder) end)
    AttachTooltip(row, fillRowTooltip)
    return row
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

local function buildPanel()
    local frame = CreateWindow("RemindMeFrame", ns.title, ns.ICON, PANEL_W, PANEL_H, RemindMeDB.window)
    local left, right = createColumns(frame)
    local help = createAtticHelp(frame)
    frame.help = help

    -- selected is the stored reminder the editor shows, nil while it shows a new one. The form
    -- holds the picks either way.
    local form = newPicks()
    local selected

    -- A line in the status box until the player changes a field: Added or Saved.
    local notice, noticeColor

    -- Reminders list.
    local scroll = createListScroll(left)
    local listSection = CreateSection(scroll.content, "Reminders")
    listSection:SetPoint("TOPLEFT")
    listSection:SetPoint("TOPRIGHT")

    local empty = CreateEmptyState(left, TEXT.EMPTY_TEXT)

    -- Rows by list place, made on first need and hidden past the end of the list.
    local rows, shownRows = {}, 0

    -- Message section.
    local messageSection = CreateSection(right, "Message")
    messageSection:SetPoint("TOPLEFT", PADDING, -PADDING)
    messageSection:SetPoint("TOPRIGHT", -PADDING, -PADDING)
    local textSlot = createSlot(messageSection.body, ROW)
    placeSlot(textSlot, messageSection.body, 0)
    setBodyHeight(messageSection, ROW)

    -- The box sits in by the template's left cap, so its visible border lines up with the column.
    local textBox = CreateHintBox(textSlot, "What should it remind you of?")
    textBox:SetMaxLetters(255)
    textBox:SetPoint("LEFT", INPUT_CAP, 0)
    textBox:SetPoint("RIGHT")
    hookTip(textBox, "Message", TEXT.MESSAGE_TIP)

    -- When section, one section break below Message: the trigger radios, the value with what goes
    -- beside it, the weekdays of a time of day or the Every Time tick of a zone, and the preview line.
    local whenSection = CreateSection(right, "When")
    whenSection:SetPoint("TOPLEFT", messageSection, "BOTTOMLEFT", 0, -SECTION_GAP)
    whenSection:SetPoint("TOPRIGHT", messageSection, "BOTTOMRIGHT", 0, -SECTION_GAP)
    local whenBody = whenSection.body
    local kindSlot = createSlot(whenBody, ROW)
    local valueSlot = createSlot(whenBody, ROW)
    local daysSlot = createSlot(whenBody, DAYS_H)
    local zoneSlot = createSlot(whenBody, ROW)

    local kindRadios, previous = {}, nil
    for _, kind in ipairs(ns.KINDS) do
        local radio = createRadio(kindSlot, ns.KIND_LABELS[kind], TEXT.KIND_TIPS[kind])
        if previous then
            radio:SetPoint("LEFT", previous.label, "RIGHT", PADDING + RADIO_INSET, 0)
        else
            radio:SetPoint("LEFT", kindSlot, "LEFT", RADIO_INSET, 0)
        end
        kindRadios[kind] = radio
        previous = radio
    end

    local valueBox = CreateHintBox(valueSlot, TEXT.VALUE_HINTS[form.kind])
    valueBox:SetMaxLetters(255)
    HookTooltip(valueBox, function(tooltip)
        GameTooltip_SetTitle(tooltip, ns.KIND_LABELS[form.kind])
        GameTooltip_AddNormalLine(tooltip, TEXT.VALUE_TIPS[form.kind], true)
    end)
    local hereButton = CreateButton(valueSlot, "Current Zone")
    hereButton:SetPoint("RIGHT")
    hookTip(hereButton, "Current Zone", "Fills in the zone you are in.")
    local timerRepeat = createCheck(valueSlot, "Repeat", TEXT.TIMER_REPEAT_TIP)
    timerRepeat:SetPoint("LEFT", valueSlot, "LEFT", HALF_W + GAP, 0)
    local localCheck = createCheck(valueSlot, TIMEMANAGER_LOCALTIME, TEXT.LOCAL_TIME_TIP)
    localCheck:SetPoint("LEFT", valueSlot, "LEFT", HALF_W + GAP, 0)

    -- Weekdays from Monday, three to a row.
    local dayChecks = {}
    for i, wday in ipairs(ns.WEEK_ORDER) do
        local check = createCheck(daysSlot, CALENDAR_WEEKDAY_NAMES[wday], TEXT.DAY_TIP)
        local column, line = (i - 1) % DAY_COLUMNS, math.floor((i - 1) / DAY_COLUMNS)
        check:SetPoint("TOPLEFT", daysSlot, "TOPLEFT", column * DAY_W, -line * (ROW + TIGHT))
        dayChecks[wday] = check
    end

    local zoneRepeat = createCheck(zoneSlot, "Every Time", TEXT.ZONE_REPEAT_TIP)
    zoneRepeat:SetPoint("LEFT")

    local preview = CreateText(whenBody, GameFontHighlight)
    preview:SetHeight(PREVIEW_H)
    preview:SetJustifyV("TOP")
    preview:SetWordWrap(true)

    -- Send As section, held to the column's bottom so it never moves when the trigger changes. The
    -- outputs stack, as long names such as the German raid warning need the width.
    local outputSection = CreateSection(right, "Send As")
    outputSection:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    outputSection:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    setBodyHeight(outputSection, OUTPUTS_H)
    local outputRadios = {}
    for i, output in ipairs(ns.OUTPUTS) do
        local radio = createRadio(outputSection.body, ns.OUTPUT_LABELS[output], TEXT.OUTPUT_TIPS[output])
        local middle = (i - 1) * (ROW + TIGHT) + ROW / 2
        radio:SetPoint("LEFT", outputSection.body, "TOPLEFT", RADIO_INSET, -middle)
        outputRadios[output] = radio
    end
    local testButton = CreateButton(outputSection.body, "Test")
    testButton:SetPoint("TOPRIGHT")
    hookTip(testButton, "Test", "Shows the message once now, the way it arrives.")

    -- The primary button takes the bar's bottom-right corner and reads Save while editing.
    local saveButton = AddBarButton(frame, TEXT.ADD_LABEL, function() frame:SaveForm() end)
    local newButton = AddBarButton(frame, TEXT.NEW_LABEL, function() frame:NewReminder() end)
    local deleteButton = createDeleteButton(frame)
    local status = createStatus(frame, deleteButton, newButton)
    local deleteDialog = createDeleteDialog()

    hookBarTip(saveButton, function()
        if selected then return SAVE, "Keeps your changes to this reminder.", TEXT.INCOMPLETE_TIP end
        return TEXT.ADD_LABEL, "Adds the reminder to the list on the left.", TEXT.INCOMPLETE_TIP
    end)
    hookBarTip(newButton, function()
        return TEXT.NEW_LABEL, "Empties the editor for a new reminder. Changes to the one shown are kept.",
            "The editor already shows a new reminder."
    end)
    hookBarTip(deleteButton, function()
        return DELETE, "Removes the reminder shown in the editor, after asking.", "Click a reminder on the left first."
    end)
    local showTip, retireTip = AttachTip(saveButton, TEXT.TIP_TEXT, HelpTip.Point.RightEdgeCenter)
    frame.showTip = showTip

    frame.kindRadios, frame.outputRadios, frame.dayChecks = kindRadios, outputRadios, dayChecks
    frame.repeatChecks = { timer = timerRepeat, zone = zoneRepeat }
    frame.localCheck, frame.preview, frame.deleteDialog, frame.status = localCheck, preview, deleteDialog, status

    -- The trigger decides which fields show. A countdown has Repeat beside its value, a time of day
    -- Use Local Time and the weekdays, a zone the Current Zone button and Every Time.
    local function layoutWhen()
        local isTimer, isClock, isZone = form.kind == "timer", form.kind == "clock", form.kind == "zone"
        local top = 0
        placeSlot(kindSlot, whenBody, top)
        top = top + ROW + GAP

        placeSlot(valueSlot, whenBody, top)
        valueBox:ClearAllPoints()
        valueBox:SetPoint("LEFT", INPUT_CAP, 0)
        if isZone then
            valueBox:SetPoint("RIGHT", hereButton, "LEFT", -GAP, 0)
        else
            valueBox:SetPoint("RIGHT", valueSlot, "LEFT", HALF_W, 0)
        end
        hereButton:SetShown(isZone)
        timerRepeat:SetShown(isTimer)
        localCheck:SetShown(isClock)
        top = top + ROW + GAP

        daysSlot:SetShown(isClock)
        zoneSlot:SetShown(isZone)
        if isClock then
            placeSlot(daysSlot, whenBody, top)
            top = top + DAYS_H + GAP
        elseif isZone then
            placeSlot(zoneSlot, whenBody, top)
            top = top + ROW + GAP
        end

        preview:ClearAllPoints()
        preview:SetPoint("TOPLEFT", whenBody, "TOPLEFT", 0, -top)
        preview:SetPoint("TOPRIGHT", whenBody, "TOPRIGHT", 0, -top)
        setBodyHeight(whenSection, top + PREVIEW_H)
    end

    -- The trigger as a spec, or nil and the problem. An empty value is no problem yet, only unfinished.
    local function readWhen()
        local value = ns.trim(valueBox:GetText())
        if value == "" then return nil end
        local spec = { kind = form.kind, output = form.output, rep = form.rep }
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

    -- The whole form as a spec Add and Update take, or nil while the message or the value is missing.
    local function readForm()
        local spec = readWhen()
        if not spec or ns.trim(textBox:GetText()) == "" then return nil end
        spec.text = textBox:GetText()
        return spec
    end

    -- The preview says what the trigger will do as it is typed, and the primary button waits until the
    -- form is complete, as Send Mail's Send does (SendMailFrame_CanSend).
    local function refreshForm()
        local spec, problem = readWhen()
        if spec then
            preview:SetText(describeNext(spec))
        elseif problem then
            preview:SetText(RED_FONT_COLOR:WrapTextInColorCode(problem))
        else
            preview:SetText(GRAY_FONT_COLOR:WrapTextInColorCode(TEXT.PREVIEW_HINTS[form.kind]))
        end
        saveButton:SetEnabled(readForm() ~= nil)
    end

    -- The radios and checkboxes show the picks and the editor shows the fields of the current trigger.
    local function showPicks()
        for kind, radio in pairs(kindRadios) do radio:SetChecked(kind == form.kind) end
        for output, radio in pairs(outputRadios) do radio:SetChecked(output == form.output) end
        timerRepeat:SetChecked(form.rep)
        zoneRepeat:SetChecked(form.rep)
        localCheck:SetChecked(not form.realm)
        for wday, check in pairs(dayChecks) do check:SetChecked(form.days[wday] == true) end
        valueBox.Instructions:SetText(TEXT.VALUE_HINTS[form.kind])
        layoutWhen()
        refreshForm()
    end

    function frame:RefreshStatus()
        if notice then
            status:SetText(noticeColor:WrapTextInColorCode(notice))
            return
        end
        local sorted = Reminders.Sorted()
        if #sorted == 0 then
            status:SetText(GRAY_FONT_COLOR:WrapTextInColorCode("No reminders yet"))
            return
        end
        local text = ns.countLabel(#sorted, "reminder", "reminders")
        local nextUp = sorted[1]
        if nextUp.due then
            text = text .. ", next " .. GREEN_FONT_COLOR:WrapTextInColorCode("in " .. Time.FormatLeft(nextUp.due - GetServerTime()))
        end
        status:SetText(text)
    end

    local function setNotice(message, color)
        notice, noticeColor = message, color
        frame:RefreshStatus()
    end

    local function clearNotice()
        if notice then setNotice(nil) end
    end

    -- The attic, the bar buttons and the row bars follow the editor's mode.
    local function refreshMode()
        help:SetText(selected and TEXT.HELP_EDIT or TEXT.HELP_NEW)
        saveButton:SetText(selected and SAVE or TEXT.ADD_LABEL)
        newButton:SetEnabled(selected ~= nil)
        deleteButton:SetEnabled(selected ~= nil)
        for i = 1, shownRows do rows[i].selected:SetShown(rows[i].reminder == selected) end
    end

    local function clearFocus()
        textBox:ClearFocus()
        valueBox:ClearFocus()
    end

    -- Like the macro window, leaving a reminder keeps what was changed in it, as long as it reads.
    local function commit()
        local spec = selected and readForm()
        if spec then Reminders.Update(selected, spec) end
    end

    -- Countdowns tick down in place, without rebuilding the rows.
    function frame:RefreshTimes()
        local now = GetServerTime()
        for i = 1, shownRows do
            rows[i].detail:SetText(Reminders.Detail(rows[i].reminder, now))
        end
        self:RefreshStatus()
        refreshForm()
    end

    function frame:RefreshList()
        local sorted = Reminders.Sorted()
        empty:SetShown(#sorted == 0)
        for i, r in ipairs(sorted) do
            rows[i] = rows[i] or createRow(listSection.body, i, function(picked) frame:Select(picked) end)
            rows[i].reminder = r
            rows[i].name:SetText(r.text)
            rows[i]:Show()
        end
        for i = #sorted + 1, #rows do
            rows[i]:Hide()
            rows[i].reminder = nil
        end
        shownRows = #sorted
        setBodyHeight(listSection, #sorted > 0 and #sorted * LIST_PITCH - (LIST_PITCH - LIST_ROW) or 0)

        -- A reminder that fired once or was removed by command leaves the editor. Its fields stay,
        -- so Add Reminder can bring it back.
        if selected and not tContains(sorted, selected) then selected = nil end
        refreshMode()

        -- The scroll child follows the list, and the offset comes back into range when it shrinks.
        scroll.content:SetHeight(listSection:GetHeight())
        scroll:UpdateScrollChildRect()
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange()))
        self:RefreshTimes()
    end

    -- Loads a stored reminder into the editor, after keeping the changes to the one shown before.
    function frame:Select(r)
        if r == selected then return end
        commit()
        selected = r
        form = picksOf(r)
        textBox:SetText(r.text)
        if r.kind == "timer" then
            valueBox:SetText(Time.FormatDuration(r.seconds))
        elseif r.kind == "clock" then
            valueBox:SetText(Time.FormatClockField(r.hour, r.minute))
        else
            valueBox:SetText(r.zone)
        end
        textBox:SetCursorPosition(0)
        valueBox:SetCursorPosition(0)
        clearFocus()
        clearNotice()
        showPicks()
        refreshMode()
    end

    -- Empties the editor for a new reminder with the default picks, after keeping the changes to the
    -- reminder shown before.
    function frame:NewReminder()
        commit()
        selected = nil
        form = newPicks()
        textBox:SetText("")
        valueBox:SetText("")
        clearNotice()
        showPicks()
        refreshMode()
        textBox:SetFocus()
    end

    function frame:DeleteSelected()
        if not selected then return end
        deleteDialog.reminder = selected
        deleteDialog.subject:SetText(selected.text)
        deleteDialog:Show()
    end

    -- Removes the reminder the dialog names, even if another was picked meanwhile. Only the removed
    -- one's editor empties, and nothing is kept from it.
    function frame:ConfirmDelete()
        local r = deleteDialog.reminder
        deleteDialog.reminder = nil
        deleteDialog:Hide()
        if not r then return end
        local wasSelected = r == selected
        if wasSelected then selected = nil end
        Reminders.Remove(r)
        if wasSelected then self:NewReminder() end
    end

    -- A new reminder empties the fields and keeps the picks, so several similar ones go in quickly.
    -- A saved one stays selected. An incomplete form only moves the caret to the first field to
    -- finish, since the preview already names any problem.
    function frame:SaveForm()
        local spec = readForm()
        if not spec then
            local box = ns.trim(textBox:GetText()) == "" and textBox or valueBox
            box:SetFocus()
            return
        end
        if selected then
            if not Reminders.Update(selected, spec) then return end
            clearFocus()
            setNotice("Saved.", GREEN_FONT_COLOR)
            return
        end
        if not Reminders.Add(spec) then return end
        retireTip()
        textBox:SetText("")
        valueBox:SetText("")
        clearFocus()
        setNotice("Added.", GREEN_FONT_COLOR)
    end

    -- A trigger change empties the value, which means something else under each trigger.
    local function setKind(kind)
        if form.kind ~= kind then
            form.kind, form.rep, form.days = kind, false, {}
            valueBox:SetText("")
        end
        clearNotice()
        showPicks()
    end

    -- A click on a radio picks it, and showPicks checks it again even when it was picked already.
    for kind, radio in pairs(kindRadios) do
        radio:SetScript("OnClick", function() setKind(kind) end)
    end
    for output, radio in pairs(outputRadios) do
        radio:SetScript("OnClick", function()
            form.output = output
            clearNotice()
            showPicks()
        end)
    end

    local function onRepeat(check)
        form.rep = check:GetChecked()
        clearNotice()
        showPicks()
    end
    timerRepeat:SetScript("OnClick", onRepeat)
    zoneRepeat:SetScript("OnClick", onRepeat)

    localCheck:SetScript("OnClick", function(check)
        form.realm = not check:GetChecked()
        clearNotice()
        refreshForm()
    end)

    for wday, check in pairs(dayChecks) do
        check:SetScript("OnClick", function()
            form.days[wday] = check:GetChecked() or nil
            clearNotice()
            refreshForm()
        end)
    end

    testButton:SetScript("OnClick", function()
        local text = ns.trim(textBox:GetText())
        Reminders.Preview(form.output, text ~= "" and text or "This is how your reminder arrives.")
    end)

    hereButton:SetScript("OnClick", function()
        valueBox:SetText(GetZoneText())
        valueBox:SetCursorPosition(0)
        clearNotice()
    end)

    deleteButton:SetScript("OnClick", function() frame:DeleteSelected() end)
    deleteDialog.deleteButton:SetScript("OnClick", function() frame:ConfirmDelete() end)

    -- Enter in the text moves on to an empty value, otherwise both fields save. Tab swaps them.
    textBox:SetScript("OnEnterPressed", function()
        if ns.trim(valueBox:GetText()) == "" then valueBox:SetFocus() else frame:SaveForm() end
    end)
    valueBox:SetScript("OnEnterPressed", function() frame:SaveForm() end)
    textBox:SetScript("OnTabPressed", function() valueBox:SetFocus() end)
    valueBox:SetScript("OnTabPressed", function() textBox:SetFocus() end)

    -- Hooked, so the template's own handler keeps hiding the hint while there is text. Every change
    -- updates the preview and the primary button, and typing clears the notice.
    local function onTextChanged(_, userInput)
        if userInput then clearNotice() end
        refreshForm()
    end
    textBox:HookScript("OnTextChanged", onTextChanged)
    valueBox:HookScript("OnTextChanged", onTextChanged)

    showPicks()

    -- A new reminder takes the keyboard on open, so the message can be typed at once. Escape hands
    -- it back, a second Escape closes the window.
    local ticker
    frame:SetScript("OnShow", function(self)
        showPicks()
        self:RefreshList()
        ticker = C_Timer.NewTicker(1, function() self:RefreshTimes() end)
        if not selected then textBox:SetFocus() end
    end)
    frame:SetScript("OnHide", function()
        commit()
        ticker:Cancel()
        notice = nil
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

-- Opens the window with a reminder in the editor, for /rm edit.
function ns.EditInPanel(r)
    ns.OpenPanel()
    panel:Select(r)
end

-- /rm intro brings the help tip back at once while the window is open, else at its next open.
function ns.ShowTip()
    if panel and panel:IsVisible() then panel.showTip() end
end

-- Called after any change to the reminders, so an open window mirrors them.
function ns.RefreshPanel()
    if panel and panel:IsShown() then panel:RefreshList() end
end
