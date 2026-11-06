local _, ns = ...

local UI = LibStub("LibNativeUI-1.0")
local Time = ns.Time
local Reminders = ns.Reminders

-- Laid out like Blizzard's macro window (Blizzard_MacroUI.xml): a list to pick from, an editor for
-- the picked entry, Delete in the bar's bottom-left corner and New beside the primary button. Two
-- equal wells as in Chat Scan: the reminders on the left, the editor on the right. The outer width
-- carries Blizzard's 4/-6 inset offsets, so it is 674.
local COLUMN_W = 328
local PANEL_W = PANEL_INSET_LEFT_OFFSET + 2 * COLUMN_W + UI.Space.gap - PANEL_INSET_RIGHT_OFFSET

-- WowStyle1Dropdown art reaches 9px below the button (Blizzard_Menu/Mainline/MenuTemplates.xml:10),
-- so a dropdown's grid slot holds that art too.
local DROPDOWN_ART_BELOW = 9
local DROPDOWN_SLOT = UI.Snap(UI.Native.dropdownHeight + DROPDOWN_ART_BELOW)

-- The editor's longest layout, Time of Day: padding, three section headings, two section breaks,
-- the message box, the When body (trigger, value, clock and repeat) and the Send As dropdown.
local HEADING_H = UI.Size.heading + UI.Space.gap
local WHEN_CLOCK_H = 3 * DROPDOWN_SLOT + UI.Size.row + 3 * UI.Space.gap
local EDITOR_H = 2 * UI.Space.padding + 3 * HEADING_H + 2 * UI.Space.section + UI.Size.row + WHEN_CLOCK_H + DROPDOWN_SLOT

-- The template's attic keeps the wells below the portrait, which hangs 55px down from the top edge
-- (Mainline/SharedUIPanelTemplates.xml:584). The attic and button bar offsets (60 and 26) are off
-- the grid, so the height snaps up and the extra px fall into the wells' bottom padding.
local PANEL_H = UI.Snap(-PANEL_INSET_ATTIC_OFFSET + EDITOR_H + PANEL_INSET_BOTTOM_BUTTON_OFFSET)

local LIST_W = COLUMN_W - UI.Space.padding - UI.ScrollGutter()

-- A list row: the text over its trigger line, two heading-tall lines a tight gap apart with a tight
-- inset all round, so the hover and selection bars frame the text. Rows sit a tight gap apart.
local ROW_INSET = UI.Space.tight
local ROW_H = 2 * UI.Size.heading + UI.Space.tight + 2 * ROW_INSET
local ROW_PITCH = ROW_H + UI.Space.tight

-- The attic line names the mode and the next step.
local HELP_NEW = "Fill in a new reminder, or click one on the left to change it."
local HELP_EDIT = "Change the selected reminder, then press Save."

local ADD_LABEL = "Add Reminder"
local NEW_LABEL = "New Reminder"

-- What the empty value field asks for under each trigger.
local VALUE_HINTS = { timer = "30m or 1h 30m", clock = "20:30 or 8:30 PM", zone = "Stormwind City" }

-- The Repeat picks per trigger, as { label, rep }. A time of day repeats daily or on one weekday.
local function repeatChoices(kind)
    if kind == "clock" then
        local choices = { { "Once", false }, { "Every Day", true } }
        for _, wday in ipairs(ns.WEEK_ORDER) do
            choices[#choices + 1] = { "Every " .. CALENDAR_WEEKDAY_NAMES[wday], wday }
        end
        return choices
    end
    return { { "Once", false }, { kind == "zone" and "Every Time" or "Repeat", true } }
end

-- The picks a new reminder starts from. The clock follows the player's minimap clock setting.
local function newPicks()
    return { kind = "timer", output = ns.DEFAULT_OUTPUT, realm = ns.DefaultRealm(), rep = false }
end

local panel

-- InputBoxInstructionsTemplate is the InputBoxTemplate behind UI.CreateEditBox plus Blizzard's grey
-- hint, so an empty field says what it takes. The hint moves to the muted role and sits where the
-- typed text starts. Its template grey is read before the font object changes and put back after,
-- as UI.CreateSearchBox does.
local function createHintBox(parent, hint)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxInstructionsTemplate")
    box:SetHeight(UI.Native.inputHeight)
    box:SetAutoFocus(false)
    box:SetMaxLetters(255)
    box:SetFontObject(UI.Font.body)
    local r, g, b = box.Instructions:GetTextColor()
    box.Instructions:SetFontObject(UI.Font.muted)
    box.Instructions:SetTextColor(r, g, b)
    box.Instructions:ClearAllPoints()
    box.Instructions:SetAllPoints()
    box.Instructions:SetText(hint)
    return box
end

-- A dropdown in its grid slot. Its art hangs past both sides, so it is indented by that much.
local function createDropdown(slot)
    local dropdown = UI.CreateDropdown(slot)
    dropdown:SetPoint("TOPLEFT", UI.Native.dropdownArt, 0)
    return dropdown
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

-- The left well's scroll area, placed like Chat Scan's: one padding in from the top, left and bottom,
-- the scroll bar's gutter free on the right. The bar hides while every row fits.
local function createWellScroll(well)
    local scroll = UI.CreateScroll(well)
    scroll.ScrollBar:SetHideIfUnscrollable(true)
    scroll:SetPoint("TOPLEFT", UI.Space.padding, -UI.Space.padding)
    scroll:SetPoint("BOTTOMRIGHT", -UI.ScrollGutter(), UI.Space.padding)
    scroll.content:SetWidth(LIST_W)
    return scroll
end

-- The template's Inset becomes the left well and a second inset the right one, one gap apart and
-- both on Blizzard's own inset offsets.
local function createColumns(frame)
    local left = frame.Inset
    left:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", PANEL_INSET_LEFT_OFFSET + COLUMN_W, PANEL_INSET_BOTTOM_BUTTON_OFFSET)

    local right = UI.CreateInset(frame)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", UI.Space.gap, 0)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", PANEL_INSET_RIGHT_OFFSET, PANEL_INSET_BOTTOM_BUTTON_OFFSET)
    return left, right
end

-- One line in the attic, the band between the title bar and the wells, level with the title and
-- centred on the band's height, as in Target Finder.
local function createAtticHelp(frame)
    local atticMiddle = (PANEL_INSET_TOP_OFFSET + PANEL_INSET_ATTIC_OFFSET) / 2
    local help = UI.CreateText(frame, "body")
    help:SetPoint("LEFT", frame, "TOPLEFT", UI.Native.titleLeft, atticMiddle)
    help:SetPoint("RIGHT", frame, "TOPRIGHT", PANEL_INSET_RIGHT_OFFSET - UI.Space.padding, atticMiddle)
    help:SetWordWrap(false)
    return help
end

-- Delete takes the bar's bottom-left corner, as MacroDeleteButton does. MagicButton_OnLoad runs
-- after the zero-offset anchor so Blizzard applies its corner inset, as UI.AddBarButton does.
local function createDeleteButton(frame, onClick)
    local button = CreateFrame("Button", nil, frame, "MagicButtonTemplate")
    button:SetWidth(UI.Size.button)
    button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
    MagicButton_OnLoad(button)
    button:SetText(DELETE)
    button:SetScript("OnClick", onClick)
    return button
end

-- The status sits in an inset that fills the button bar between Delete and New Reminder.
local function createStatus(frame, leftButton, rightButton)
    local box = UI.CreateInset(frame)
    box:SetPoint("BOTTOMLEFT", leftButton, "BOTTOMRIGHT", UI.Space.gap, 0)
    box:SetPoint("TOPRIGHT", rightButton, "TOPLEFT", -UI.Space.gap, 0)

    local status = UI.CreateText(box, "body")
    status:SetPoint("LEFT", UI.Space.gap, 0)
    status:SetPoint("RIGHT", -UI.Space.gap, 0)
    status:SetWordWrap(false)
    return status
end

-- The full text and trigger, for rows whose text the row cuts off.
local function fillRowTooltip(tooltip, row)
    GameTooltip_SetTitle(tooltip, row.reminder.text, nil, true)
    GameTooltip_AddNormalLine(tooltip, Reminders.Detail(row.reminder, GetServerTime()), true)
    GameTooltip_AddInstructionLine(tooltip, "Click to edit this reminder.")
end

-- A selectable row with the hover and selection bars of Blizzard's Settings category list
-- (Blizzard_Settings_Shared/Blizzard_CategoryList.lua). The hover bar sits on the HIGHLIGHT layer,
-- which the button shows on mouse-over, and stays off on the selected row as it does there.
local function createRow(parent, onClick)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetScript("OnClick", function() onClick(row.reminder) end)
    UI.AttachTooltip(row, fillRowTooltip)

    row.selection = row:CreateTexture(nil, "BACKGROUND")
    row.selection:SetAtlas("Options_List_Active")
    row.selection:SetAllPoints()

    row.hover = row:CreateTexture(nil, "HIGHLIGHT")
    row.hover:SetAtlas("Options_List_Hover")
    row.hover:SetAllPoints()

    row.text = UI.CreateText(row, "body")
    row.text:SetPoint("TOPLEFT", ROW_INSET, -ROW_INSET)
    row.text:SetPoint("TOPRIGHT", -ROW_INSET, -ROW_INSET)
    row.text:SetHeight(UI.Size.heading)
    row.text:SetWordWrap(false)

    row.detail = UI.CreateText(row, "muted")
    row.detail:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -UI.Space.tight)
    row.detail:SetPoint("TOPRIGHT", row.text, "BOTTOMRIGHT", 0, -UI.Space.tight)
    row.detail:SetHeight(UI.Size.heading)
    row.detail:SetWordWrap(false)
    return row
end

local function setRowSelected(row, selected)
    row.selection:SetShown(selected)
    row.hover:SetShown(not selected)
end

local function buildPanel()
    local frame = UI.CreateWindow({
        name = "RemindMeFrame", title = ns.TITLE, icon = ns.ICON,
        width = PANEL_W, height = PANEL_H, position = RemindMeDB.window,
    })
    local left, right = createColumns(frame)
    local help = createAtticHelp(frame)
    frame.help = help

    -- selected is the stored reminder the editor shows, nil while it shows a new one. The form
    -- holds the dropdown picks either way.
    local form = newPicks()
    local selected

    -- A line in the status box until the player changes a field: a problem in red, or Saved.
    local notice, noticeColor

    -- Reminders list.
    local scroll = createWellScroll(left)
    local listSection = UI.CreateSection(scroll.content, "Reminders")
    listSection:SetPoint("TOPLEFT")
    listSection:SetPoint("TOPRIGHT")

    local empty = UI.CreateText(listSection.body, "muted")
    empty:SetPoint("TOPLEFT")
    empty:SetPoint("TOPRIGHT")
    empty:SetHeight(UI.Size.row)
    empty:SetText("No reminders yet.")

    local rows = { active = {}, pool = {} }

    -- Message section.
    local messageSection = UI.CreateSection(right, "Message")
    messageSection:SetPoint("TOPLEFT", UI.Space.padding, -UI.Space.padding)
    messageSection:SetPoint("TOPRIGHT", -UI.Space.padding, -UI.Space.padding)
    local textSlot = createSlot(messageSection.body, UI.Size.row)
    placeSlot(textSlot, messageSection.body, 0)
    messageSection:SetBodyHeight(UI.Size.row)

    -- The box sits in by the template's left cap, so its visible border lines up with the column.
    local textBox = createHintBox(textSlot, "What should it remind you of?")
    textBox:SetPoint("LEFT", UI.Native.inputArt, 0)
    textBox:SetPoint("RIGHT")

    -- When section: the trigger, its value, the clock for a time of day and the repeat pick.
    local whenSection = UI.CreateSection(right, "When")
    UI.StackBelow(whenSection, messageSection)
    local whenBody = whenSection.body
    local kindSlot = createSlot(whenBody, DROPDOWN_SLOT)
    local valueSlot = createSlot(whenBody, UI.Size.row)
    local clockSlot = createSlot(whenBody, DROPDOWN_SLOT)
    local repeatSlot = createSlot(whenBody, DROPDOWN_SLOT)

    local kindDropdown = createDropdown(kindSlot)
    local valueBox = createHintBox(valueSlot, VALUE_HINTS[form.kind])
    local hereButton = UI.CreateButton(valueSlot, "Current Zone")
    hereButton:SetPoint("RIGHT")
    local clockDropdown = createDropdown(clockSlot)
    local repeatDropdown = createDropdown(repeatSlot)
    local dropdowns = { kindDropdown, clockDropdown, repeatDropdown }

    -- Send As section: the output and a test that shows the message the way it will arrive.
    local outputSection = UI.CreateSection(right, "Send As")
    UI.StackBelow(outputSection, whenSection)
    local outputSlot = createSlot(outputSection.body, DROPDOWN_SLOT)
    placeSlot(outputSlot, outputSection.body, 0)
    outputSection:SetBodyHeight(DROPDOWN_SLOT)
    local outputDropdown = createDropdown(outputSlot)
    dropdowns[#dropdowns + 1] = outputDropdown
    local testButton = UI.CreateButton(outputSlot, "Test")
    testButton:SetPoint("LEFT", outputDropdown, "RIGHT", UI.Native.dropdownArt + UI.Space.gap, 0)

    -- The primary button takes the bar's bottom-right corner and reads Save while editing.
    local saveButton = UI.AddBarButton(frame, ADD_LABEL, function() frame:SaveForm() end)
    local newButton = UI.AddBarButton(frame, NEW_LABEL, function() frame:NewReminder() end)
    local deleteButton = createDeleteButton(frame, function() frame:DeleteSelected() end)
    local status = createStatus(frame, deleteButton, newButton)

    -- The trigger decides which fields show. A time of day adds the clock pick, a zone the button
    -- that fills in the zone the player stands in.
    local function layoutWhen()
        local isZone, isClock = form.kind == "zone", form.kind == "clock"
        local top = 0
        placeSlot(kindSlot, whenBody, top)
        top = top + DROPDOWN_SLOT + UI.Space.gap

        placeSlot(valueSlot, whenBody, top)
        valueBox:ClearAllPoints()
        valueBox:SetPoint("LEFT", UI.Native.inputArt, 0)
        valueBox:SetPoint("RIGHT", isZone and hereButton or valueSlot, isZone and "LEFT" or "RIGHT", isZone and -UI.Space.gap or 0, 0)
        hereButton:SetShown(isZone)
        top = top + UI.Size.row + UI.Space.gap

        clockSlot:SetShown(isClock)
        if isClock then
            placeSlot(clockSlot, whenBody, top)
            top = top + DROPDOWN_SLOT + UI.Space.gap
        end

        placeSlot(repeatSlot, whenBody, top)
        whenSection:SetBodyHeight(top + DROPDOWN_SLOT)
    end

    -- The dropdowns show the picks and the editor shows the fields of the current trigger.
    local function showPicks()
        valueBox.Instructions:SetText(VALUE_HINTS[form.kind])
        for _, dropdown in ipairs(dropdowns) do dropdown:GenerateMenu() end
        layoutWhen()
    end

    function frame:RefreshStatus()
        if notice then
            status:SetText(noticeColor:WrapTextInColorCode(notice))
            return
        end
        local sorted = Reminders.Sorted()
        if #sorted == 0 then
            status:SetText(UI.Color.muted:WrapTextInColorCode("No reminders yet"))
            return
        end
        local text = ns.countLabel(#sorted, "reminder", "reminders")
        local nextUp = sorted[1]
        if nextUp.due then
            text = text .. ", next " .. UI.Color.good:WrapTextInColorCode("in " .. Time.FormatLeft(nextUp.due - GetServerTime()))
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

    -- A problem stays in the status until the player changes the field it names.
    local function showProblem(message, box)
        setNotice(message, UI.Color.bad)
        box:SetFocus()
    end

    -- The attic, the bar buttons and the row bars follow the editor's mode.
    local function refreshMode()
        help:SetText(selected and HELP_EDIT or HELP_NEW)
        saveButton:SetText(selected and SAVE or ADD_LABEL)
        newButton:SetEnabled(selected ~= nil)
        deleteButton:SetEnabled(selected ~= nil)
        for _, row in ipairs(rows.active) do setRowSelected(row, row.reminder == selected) end
    end

    local function clearFocus()
        textBox:ClearFocus()
        valueBox:ClearFocus()
    end

    -- Countdowns tick down in place, without rebuilding the rows.
    function frame:RefreshTimes()
        local now = GetServerTime()
        for _, row in ipairs(rows.active) do
            row.detail:SetText(Reminders.Detail(row.reminder, now))
        end
        self:RefreshStatus()
    end

    function frame:RefreshList()
        for _, row in ipairs(rows.active) do
            row:Hide()
            rows.pool[#rows.pool + 1] = row
        end
        wipe(rows.active)

        local sorted = Reminders.Sorted()
        empty:SetShown(#sorted == 0)
        for i, r in ipairs(sorted) do
            local row = table.remove(rows.pool) or createRow(listSection.body, function(picked) frame:Select(picked) end)
            local y = -(i - 1) * ROW_PITCH
            row:SetPoint("TOPLEFT", listSection.body, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", listSection.body, "TOPRIGHT", 0, y)
            row.reminder = r
            row.text:SetText(r.text)
            row:Show()
            rows.active[i] = row
        end
        listSection:SetBodyHeight(#sorted > 0 and #sorted * ROW_PITCH - UI.Space.tight or UI.Size.row)

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

    -- Loads a stored reminder into the editor. Unsaved changes to the one shown before are dropped.
    function frame:Select(r)
        selected = r
        form = { kind = r.kind, output = r.output, rep = r.rep, realm = r.kind == "clock" and r.realm or ns.DefaultRealm() }
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
        showPicks()
        clearNotice()
        refreshMode()
    end

    -- Empties the editor for a new reminder with the default picks.
    function frame:NewReminder()
        selected = nil
        form = newPicks()
        textBox:SetText("")
        valueBox:SetText("")
        showPicks()
        clearNotice()
        refreshMode()
        textBox:SetFocus()
    end

    function frame:DeleteSelected()
        if not selected then return end
        Reminders.Remove(selected)
        self:NewReminder()
    end

    -- The same checks as /rm, top to bottom, so the first field to fix gets the caret. A new
    -- reminder empties the fields and keeps the picks, so several similar ones go in quickly. A
    -- saved one stays selected.
    function frame:SaveForm()
        local spec = { kind = form.kind, output = form.output, rep = form.rep, text = textBox:GetText() }
        if ns.trim(spec.text) == "" then return showProblem(ns.NEED_TEXT, textBox) end

        local value = valueBox:GetText()
        if form.kind == "timer" then
            spec.seconds = Time.ParseDuration(value)
            if not spec.seconds then return showProblem(ns.NEED_DURATION, valueBox) end
        elseif form.kind == "clock" then
            spec.hour, spec.minute = Time.ParseClock(value)
            if not spec.hour then return showProblem(ns.NEED_CLOCK, valueBox) end
            spec.realm = form.realm
        else
            spec.zone = value
        end

        if selected then
            local saved, problem = Reminders.Update(selected, spec)
            if not saved then return showProblem(problem, valueBox) end
            clearFocus()
            setNotice("Saved.", UI.Color.good)
            return
        end

        local added, problem = Reminders.Add(spec)
        if not added then return showProblem(problem, valueBox) end
        textBox:SetText("")
        valueBox:SetText("")
        clearFocus()
        clearNotice()
    end

    local function setKind(kind)
        if form.kind == kind then return end
        form.kind = kind
        form.rep = false
        valueBox:SetText("")
        repeatDropdown:GenerateMenu()
        valueBox.Instructions:SetText(VALUE_HINTS[kind])
        layoutWhen()
        clearNotice()
    end

    kindDropdown:SetupMenu(function(_, root)
        for _, kind in ipairs(ns.KINDS) do
            root:CreateRadio(ns.KIND_LABELS[kind], function() return form.kind == kind end, function() setKind(kind) end)
        end
    end)

    clockDropdown:SetupMenu(function(_, root)
        root:CreateRadio("Realm Time", function() return form.realm end, function() form.realm = true clearNotice() end)
        root:CreateRadio("Local Time", function() return not form.realm end, function() form.realm = false clearNotice() end)
    end)

    repeatDropdown:SetupMenu(function(_, root)
        for _, choice in ipairs(repeatChoices(form.kind)) do
            local label, rep = choice[1], choice[2]
            root:CreateRadio(label, function() return form.rep == rep end, function() form.rep = rep clearNotice() end)
        end
    end)

    outputDropdown:SetupMenu(function(_, root)
        for _, output in ipairs(ns.OUTPUTS) do
            root:CreateRadio(ns.OUTPUT_LABELS[output], function() return form.output == output end, function() form.output = output clearNotice() end)
        end
    end)

    testButton:SetScript("OnClick", function()
        local text = ns.trim(textBox:GetText())
        Reminders.Preview(form.output, text ~= "" and text or "This is how your reminder arrives.")
    end)

    hereButton:SetScript("OnClick", function()
        valueBox:SetText(GetZoneText())
        valueBox:SetCursorPosition(0)
    end)

    -- Enter in the text moves on to an empty value, otherwise both fields save. Tab swaps them.
    textBox:SetScript("OnEnterPressed", function()
        if ns.trim(valueBox:GetText()) == "" then valueBox:SetFocus() else frame:SaveForm() end
    end)
    valueBox:SetScript("OnEnterPressed", function() frame:SaveForm() end)
    textBox:SetScript("OnTabPressed", function() valueBox:SetFocus() end)
    valueBox:SetScript("OnTabPressed", function() textBox:SetFocus() end)

    -- Hooked, so the template's own handler keeps hiding the hint while there is text. Typing clears
    -- the notice, and so does Current Zone, which fills the value box from code.
    textBox:HookScript("OnTextChanged", function(_, userInput) if userInput then clearNotice() end end)
    valueBox:HookScript("OnTextChanged", function(_, userInput) if userInput then clearNotice() end end)
    hereButton:HookScript("OnClick", clearNotice)

    layoutWhen()

    local ticker
    frame:SetScript("OnShow", function(self)
        showPicks()
        self:RefreshList()
        ticker = C_Timer.NewTicker(1, function() self:RefreshTimes() end)
    end)
    frame:SetScript("OnHide", function()
        ticker:Cancel()
        notice = nil
    end)

    panel = frame
    return frame
end

-- One toggle for /rm, the minimap button and the addon menu. The window is built on first use.
ns.TogglePanel = UI.CreateToggle(buildPanel)

-- Opens the window with a reminder in the editor, for /rm edit.
function ns.EditInPanel(r)
    if not (panel and panel:IsShown()) then ns.TogglePanel() end
    panel:Select(r)
end

-- Called after any change to the reminders, so an open window mirrors them.
function ns.RefreshPanel()
    if panel and panel:IsShown() then panel:RefreshList() end
end
