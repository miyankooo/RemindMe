local _, ns = ...

local UI = LibStub("LibNativeUI-1.0")
local Time = ns.Time
local Reminders = ns.Reminders

-- Two equal wells as in Chat Scan: the reminders on the left, the form for a new one on the right.
-- The outer width carries Blizzard's 4/-6 inset offsets, so it is 674.
local COLUMN_W = 328
local PANEL_W = PANEL_INSET_LEFT_OFFSET + 2 * COLUMN_W + UI.Space.gap - PANEL_INSET_RIGHT_OFFSET

-- Tall enough for the form's longest layout, Time of Day, without a scroll bar. A long list
-- scrolls inside its well.
local PANEL_H = 440

-- WowStyle1Dropdown art reaches 9px below the button (Blizzard_Menu/Mainline/MenuTemplates.xml:10),
-- so a dropdown's grid slot holds that art too.
local DROPDOWN_ART_BELOW = 9
local DROPDOWN_SLOT = UI.Snap(UI.Native.dropdownHeight + DROPDOWN_ART_BELOW)

-- The form well has no scroll bar, so its content keeps one padding on both sides.
local FORM_W = COLUMN_W - 2 * UI.Space.padding
local LIST_W = COLUMN_W - UI.Space.padding - UI.ScrollGutter()

-- A list row: the text over its trigger line, two heading-tall lines a tight gap apart, with the
-- remove button in a trailing column one row wide.
local ROW_H = 2 * UI.Size.heading + UI.Space.tight
local ROW_PITCH = ROW_H + UI.Space.gap
local TRAILING_W = UI.Size.row + UI.Space.gap

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

-- The status sits in an inset that fills the button bar left of the add button, as in Chat Scan.
local function createStatus(frame, addButton)
    local box = UI.CreateInset(frame)
    box:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PANEL_INSET_LEFT_OFFSET, PANEL_INSET_BOTTOM_OFFSET)
    box:SetPoint("TOPRIGHT", addButton, "TOPLEFT", -UI.Space.gap, 0)

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
end

local function createRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    UI.AttachTooltip(row, fillRowTooltip)

    local remove = UI.CreateRemoveButton(row)
    remove:SetPoint("RIGHT")
    remove:SetScript("OnClick", function() Reminders.Remove(row.reminder) end)

    row.text = UI.CreateText(row, "body")
    row.text:SetPoint("TOPLEFT")
    row.text:SetPoint("TOPRIGHT", -TRAILING_W, 0)
    row.text:SetHeight(UI.Size.heading)
    row.text:SetWordWrap(false)

    row.detail = UI.CreateText(row, "muted")
    row.detail:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -UI.Space.tight)
    row.detail:SetPoint("TOPRIGHT", row.text, "BOTTOMRIGHT", 0, -UI.Space.tight)
    row.detail:SetHeight(UI.Size.heading)
    row.detail:SetWordWrap(false)
    return row
end

local function buildPanel()
    local frame = UI.CreateWindow({
        name = "RemindMeFrame", title = ns.TITLE, icon = ns.ICON,
        width = PANEL_W, height = PANEL_H, position = RemindMeDB.window, attic = false,
    })
    local left, right = createColumns(frame)

    -- The picks a new reminder starts from. The clock follows the player's minimap clock setting.
    local form = { kind = "timer", output = ns.DEFAULT_OUTPUT, realm = ns.DefaultRealm(), rep = false }
    local problem

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

    -- Send As section: the output and a test that shows the message the way it will arrive.
    local outputSection = UI.CreateSection(right, "Send As")
    UI.StackBelow(outputSection, whenSection)
    local outputSlot = createSlot(outputSection.body, DROPDOWN_SLOT)
    placeSlot(outputSlot, outputSection.body, 0)
    outputSection:SetBodyHeight(DROPDOWN_SLOT)
    local outputDropdown = createDropdown(outputSlot)
    local testButton = UI.CreateButton(outputSlot, "Test")
    testButton:SetPoint("LEFT", outputDropdown, "RIGHT", UI.Native.dropdownArt + UI.Space.gap, 0)

    local addButton = UI.AddBarButton(frame, "Add Reminder", function() frame:AddFromForm() end)
    local status = createStatus(frame, addButton)

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

    function frame:RefreshStatus()
        if problem then
            status:SetText(UI.Color.bad:WrapTextInColorCode(problem))
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

    -- A problem stays in the status until the player changes the field it names.
    local function showProblem(message, box)
        problem = message
        frame:RefreshStatus()
        box:SetFocus()
    end

    local function clearProblem()
        if not problem then return end
        problem = nil
        frame:RefreshStatus()
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
            local row = table.remove(rows.pool) or createRow(listSection.body)
            local y = -(i - 1) * ROW_PITCH
            row:SetPoint("TOPLEFT", listSection.body, "TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", listSection.body, "TOPRIGHT", 0, y)
            row.reminder = r
            row.text:SetText(r.text)
            row:Show()
            rows.active[i] = row
        end
        listSection:SetBodyHeight(#sorted > 0 and #sorted * ROW_PITCH - UI.Space.gap or UI.Size.row)

        -- The scroll child follows the list, and the offset comes back into range when it shrinks.
        scroll.content:SetHeight(listSection:GetHeight())
        scroll:UpdateScrollChildRect()
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange()))
        self:RefreshTimes()
    end

    -- The same checks as /rm, top to bottom, so the first field to fix gets the caret. The picks
    -- stay after adding, so several similar reminders go in quickly.
    function frame:AddFromForm()
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

        local reminder, message = Reminders.Add(spec)
        if not reminder then return showProblem(message, valueBox) end
        textBox:SetText("")
        valueBox:SetText("")
        textBox:ClearFocus()
        valueBox:ClearFocus()
        clearProblem()
    end

    local function setKind(kind)
        if form.kind == kind then return end
        form.kind = kind
        form.rep = false
        valueBox:SetText("")
        valueBox.Instructions:SetText(VALUE_HINTS[kind])
        repeatDropdown:GenerateMenu()
        layoutWhen()
        clearProblem()
    end

    kindDropdown:SetupMenu(function(_, root)
        for _, kind in ipairs(ns.KINDS) do
            root:CreateRadio(ns.KIND_LABELS[kind], function() return form.kind == kind end, function() setKind(kind) end)
        end
    end)

    clockDropdown:SetupMenu(function(_, root)
        root:CreateRadio("Realm Time", function() return form.realm end, function() form.realm = true end)
        root:CreateRadio("Local Time", function() return not form.realm end, function() form.realm = false end)
    end)

    repeatDropdown:SetupMenu(function(_, root)
        for _, choice in ipairs(repeatChoices(form.kind)) do
            local label, rep = choice[1], choice[2]
            root:CreateRadio(label, function() return form.rep == rep end, function() form.rep = rep end)
        end
    end)

    outputDropdown:SetupMenu(function(_, root)
        for _, output in ipairs(ns.OUTPUTS) do
            root:CreateRadio(ns.OUTPUT_LABELS[output], function() return form.output == output end, function() form.output = output end)
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

    -- Enter in the text moves on to an empty value, otherwise both fields add. Tab swaps them.
    textBox:SetScript("OnEnterPressed", function()
        if ns.trim(valueBox:GetText()) == "" then valueBox:SetFocus() else frame:AddFromForm() end
    end)
    valueBox:SetScript("OnEnterPressed", function() frame:AddFromForm() end)
    textBox:SetScript("OnTabPressed", function() valueBox:SetFocus() end)
    valueBox:SetScript("OnTabPressed", function() textBox:SetFocus() end)

    -- Hooked, so the template's own handler keeps hiding the hint while there is text.
    textBox:HookScript("OnTextChanged", function(_, userInput) if userInput then clearProblem() end end)
    valueBox:HookScript("OnTextChanged", function() clearProblem() end)

    layoutWhen()

    local ticker
    frame:SetScript("OnShow", function(self)
        for _, dropdown in ipairs({ kindDropdown, clockDropdown, repeatDropdown, outputDropdown }) do
            dropdown:GenerateMenu()
        end
        self:RefreshList()
        ticker = C_Timer.NewTicker(1, function() self:RefreshTimes() end)
    end)
    frame:SetScript("OnHide", function()
        ticker:Cancel()
        problem = nil
    end)

    panel = frame
    return frame
end

-- One toggle for /rm, the minimap button and the addon menu. The window is built on first use.
ns.TogglePanel = UI.CreateToggle(buildPanel)

-- Called after any change to the reminders, so an open window mirrors them.
function ns.RefreshPanel()
    if panel and panel:IsShown() then panel:RefreshList() end
end
