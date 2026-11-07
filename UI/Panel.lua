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

-- The editor's inner width, and the half a short value box takes so a checkbox fits beside it.
local BODY_W = COLUMN_W - 2 * UI.Space.padding
local HALF_W = (BODY_W - UI.Space.gap) / 2

-- Every choice shows at once as a radio or a checkbox, so a pick is one click. UIRadioButtonTemplate
-- is the 16px radio of Send Mail's Send Money and COD (Blizzard_MailFrame/MailFrame.xml:3). It sits
-- centred in a 24px row like UI.CreateCheckbox, so radio and checkbox labels start at the same x.
local RADIO_SIZE = 16
local RADIO_INSET = (UI.Size.row - RADIO_SIZE) / 2

-- Rows stacked a tight gap apart: the weekdays in three columns and the outputs.
local function stackHeight(rows)
    return rows * UI.Size.row + (rows - 1) * UI.Space.tight
end
local DAY_COLUMNS = 3
local DAY_W = 4 * math.floor((BODY_W + UI.Space.gap) / DAY_COLUMNS / 4)
local DAYS_H = stackHeight(math.ceil(#ns.WEEK_ORDER / DAY_COLUMNS))
local OUTPUTS_H = stackHeight(#ns.OUTPUTS)

-- The preview line under When has room for two lines.
local PREVIEW_H = 2 * UI.Size.heading

-- The editor's longest layout, Time of Day: padding, three section headings, two section breaks,
-- the message box, the When body (trigger, time, weekdays and preview) and the outputs.
local HEADING_H = UI.Size.heading + UI.Space.gap
local WHEN_CLOCK_H = 2 * (UI.Size.row + UI.Space.gap) + DAYS_H + UI.Space.gap + PREVIEW_H
local EDITOR_H = 2 * UI.Space.padding + 3 * HEADING_H + 2 * UI.Space.section + UI.Size.row + WHEN_CLOCK_H + OUTPUTS_H

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

-- The empty list also teaches the chat command, in two lines.
local EMPTY_TEXT = "Your reminders show here. To add one from chat, type /rm in 30m Stretch."
local EMPTY_H = 2 * UI.Size.heading

-- The attic line names the mode and the next step.
local HELP_NEW = "Fill in a new reminder, or click one on the left to change it."
local HELP_EDIT = "Changes save with Save, or when you pick another reminder or close the window."

local ADD_LABEL = "Add Reminder"
local NEW_LABEL = "New Reminder"

-- What the empty value field asks for under each trigger.
local VALUE_HINTS = { timer = "30m or 1h 30m", clock = "20:30 or 8:30 PM", zone = "Stormwind City" }

-- The preview line while the value field is empty: what the trigger does.
local PREVIEW_HINTS = {
    timer = "Fires once the countdown runs out.",
    clock = "Fires once, or on every weekday you tick.",
    zone = "Fires when you enter this zone or an area in it.",
}

-- Tooltips for the choices, so each says what it does before it is picked.
local KIND_TIPS = {
    timer = "Fires once a countdown runs out, such as 30m or 1h 30m.",
    clock = "Fires at a time of day, once or on the weekdays you tick.",
    zone = "Fires when you enter a zone or an area in it, such as Stormwind or Trade District.",
}
local OUTPUT_TIPS = {
    whisper = "A pink whisper line in chat with the whisper sound. Only you see it.",
    print = "A yellow line in your main chat tab, without a sound.",
    warning = "Large text across the middle of the screen with the raid warning sound, and a chat line. Only you see it.",
}
local TIMER_REPEAT_TIP = "Starts the countdown again each time it fires."
local ZONE_REPEAT_TIP = "Fires on every entry, not only the next one."
local LOCAL_TIME_TIP = "Use your computer's clock instead of the realm clock."

local DIALOG_W = 320

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

local function attachTip(frame, title, text)
    UI.AttachTooltip(frame, function(tooltip)
        GameTooltip_SetTitle(tooltip, title)
        GameTooltip_AddNormalLine(tooltip, text, true)
    end)
end

-- A radio with a 12px body label that is clickable too, as UI.CreateCheckbox's is. The caller
-- anchors it by its LEFT edge, RADIO_INSET into a row.
local function createRadio(parent, label, tip)
    local radio = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
    radio.label = UI.CreateText(radio, "body")
    radio.label:SetPoint("LEFT", radio, "RIGHT", UI.Space.tight + RADIO_INSET, 0)
    radio.label:SetText(label)
    radio:SetHitRectInsets(0, -(UI.Space.tight + RADIO_INSET + radio.label:GetStringWidth()), 0, 0)
    attachTip(radio, label, tip)
    return radio
end

local function createCheck(parent, label, tip)
    local check = UI.CreateCheckbox(parent, label)
    if tip then attachTip(check, label, tip) end
    return check
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
local function createDeleteButton(frame)
    local button = CreateFrame("Button", nil, frame, "MagicButtonTemplate")
    button:SetWidth(UI.Size.button)
    button:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
    MagicButton_OnLoad(button)
    button:SetText(DELETE)
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

-- Delete asks first, as the macro window's Delete does (CONFIRM_DELETE_SELECTED_MACRO), and names the
-- reminder it would remove. Accept sits left of Cancel, as on Blizzard's popups.
local function createDeleteDialog()
    local dialog = UI.CreateDialog({ name = "RemindMeDeleteDialog", title = ns.TITLE, width = DIALOG_W })
    dialog:AddText("body", "Delete this reminder?")
    dialog.subject = dialog:AddText("muted", "", UI.Space.tight)
    dialog.subject:SetWordWrap(false)
    dialog.cancelButton = dialog:AddButton(CANCEL, function() dialog:Hide() end)
    dialog.deleteButton = dialog:AddButton(DELETE, nil)
    dialog:Fit()
    return dialog
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
    local frame = UI.CreateWindow({
        name = "RemindMeFrame", title = ns.TITLE, icon = ns.ICON,
        width = PANEL_W, height = PANEL_H, position = RemindMeDB.window,
    })
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
    local scroll = createWellScroll(left)
    local listSection = UI.CreateSection(scroll.content, "Reminders")
    listSection:SetPoint("TOPLEFT")
    listSection:SetPoint("TOPRIGHT")

    local empty = UI.CreateText(listSection.body, "muted")
    empty:SetPoint("TOPLEFT")
    empty:SetPoint("TOPRIGHT")
    empty:SetHeight(EMPTY_H)
    empty:SetJustifyV("TOP")
    empty:SetWordWrap(true)
    empty:SetText(EMPTY_TEXT)

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

    -- When section: the trigger radios, the value with what goes beside it, the weekdays of a time
    -- of day or the Every Time tick of a zone, and the preview line.
    local whenSection = UI.CreateSection(right, "When")
    UI.StackBelow(whenSection, messageSection)
    local whenBody = whenSection.body
    local kindSlot = createSlot(whenBody, UI.Size.row)
    local valueSlot = createSlot(whenBody, UI.Size.row)
    local daysSlot = createSlot(whenBody, DAYS_H)
    local zoneSlot = createSlot(whenBody, UI.Size.row)

    local kindRadios, previous = {}, nil
    for _, kind in ipairs(ns.KINDS) do
        local radio = createRadio(kindSlot, ns.KIND_LABELS[kind], KIND_TIPS[kind])
        if previous then
            radio:SetPoint("LEFT", previous.label, "RIGHT", UI.Space.padding + RADIO_INSET, 0)
        else
            radio:SetPoint("LEFT", kindSlot, "LEFT", RADIO_INSET, 0)
        end
        kindRadios[kind] = radio
        previous = radio
    end

    local valueBox = createHintBox(valueSlot, VALUE_HINTS[form.kind])
    local hereButton = UI.CreateButton(valueSlot, "Current Zone")
    hereButton:SetPoint("RIGHT")
    local timerRepeat = createCheck(valueSlot, "Repeat", TIMER_REPEAT_TIP)
    timerRepeat:SetPoint("LEFT", valueSlot, "LEFT", HALF_W + UI.Space.gap, 0)
    local localCheck = createCheck(valueSlot, TIMEMANAGER_LOCALTIME, LOCAL_TIME_TIP)
    localCheck:SetPoint("LEFT", valueSlot, "LEFT", HALF_W + UI.Space.gap, 0)

    -- Weekdays from Monday, three to a row.
    local dayChecks = {}
    for i, wday in ipairs(ns.WEEK_ORDER) do
        local check = createCheck(daysSlot, CALENDAR_WEEKDAY_NAMES[wday])
        local column, line = (i - 1) % DAY_COLUMNS, math.floor((i - 1) / DAY_COLUMNS)
        check:SetPoint("TOPLEFT", daysSlot, "TOPLEFT", column * DAY_W, -line * (UI.Size.row + UI.Space.tight))
        dayChecks[wday] = check
    end

    local zoneRepeat = createCheck(zoneSlot, "Every Time", ZONE_REPEAT_TIP)
    zoneRepeat:SetPoint("LEFT")

    local preview = UI.CreateText(whenBody, "body")
    preview:SetHeight(PREVIEW_H)
    preview:SetJustifyV("TOP")
    preview:SetWordWrap(true)

    -- Send As section, held to the well's bottom so it never moves when the trigger changes. The
    -- outputs stack, as long names such as the German raid warning need the width.
    local outputSection = UI.CreateSection(right, "Send As")
    outputSection:SetPoint("BOTTOMLEFT", UI.Space.padding, UI.Space.padding)
    outputSection:SetPoint("BOTTOMRIGHT", -UI.Space.padding, UI.Space.padding)
    outputSection:SetBodyHeight(OUTPUTS_H)
    local outputRadios = {}
    for i, output in ipairs(ns.OUTPUTS) do
        local radio = createRadio(outputSection.body, ns.OUTPUT_LABELS[output], OUTPUT_TIPS[output])
        local middle = (i - 1) * (UI.Size.row + UI.Space.tight) + UI.Size.row / 2
        radio:SetPoint("LEFT", outputSection.body, "TOPLEFT", RADIO_INSET, -middle)
        outputRadios[output] = radio
    end
    local testButton = UI.CreateButton(outputSection.body, "Test")
    testButton:SetPoint("TOPRIGHT")

    -- The primary button takes the bar's bottom-right corner and reads Save while editing.
    local saveButton = UI.AddBarButton(frame, ADD_LABEL, function() frame:SaveForm() end)
    local newButton = UI.AddBarButton(frame, NEW_LABEL, function() frame:NewReminder() end)
    local deleteButton = createDeleteButton(frame)
    local status = createStatus(frame, deleteButton, newButton)
    local deleteDialog = createDeleteDialog()

    frame.kindRadios, frame.outputRadios, frame.dayChecks = kindRadios, outputRadios, dayChecks
    frame.repeatChecks = { timer = timerRepeat, zone = zoneRepeat }
    frame.localCheck, frame.preview, frame.deleteDialog, frame.status = localCheck, preview, deleteDialog, status

    -- The trigger decides which fields show. A countdown has Repeat beside its value, a time of day
    -- Use Local Time and the weekdays, a zone the Current Zone button and Every Time.
    local function layoutWhen()
        local isTimer, isClock, isZone = form.kind == "timer", form.kind == "clock", form.kind == "zone"
        local top = 0
        placeSlot(kindSlot, whenBody, top)
        top = top + UI.Size.row + UI.Space.gap

        placeSlot(valueSlot, whenBody, top)
        valueBox:ClearAllPoints()
        valueBox:SetPoint("LEFT", UI.Native.inputArt, 0)
        if isZone then
            valueBox:SetPoint("RIGHT", hereButton, "LEFT", -UI.Space.gap, 0)
        else
            valueBox:SetPoint("RIGHT", valueSlot, "LEFT", HALF_W, 0)
        end
        hereButton:SetShown(isZone)
        timerRepeat:SetShown(isTimer)
        localCheck:SetShown(isClock)
        top = top + UI.Size.row + UI.Space.gap

        daysSlot:SetShown(isClock)
        zoneSlot:SetShown(isZone)
        if isClock then
            placeSlot(daysSlot, whenBody, top)
            top = top + DAYS_H + UI.Space.gap
        elseif isZone then
            placeSlot(zoneSlot, whenBody, top)
            top = top + UI.Size.row + UI.Space.gap
        end

        preview:ClearAllPoints()
        preview:SetPoint("TOPLEFT", whenBody, "TOPLEFT", 0, -top)
        preview:SetPoint("TOPRIGHT", whenBody, "TOPRIGHT", 0, -top)
        whenSection:SetBodyHeight(top + PREVIEW_H)
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
            preview:SetText(UI.Color.bad:WrapTextInColorCode(problem))
        else
            preview:SetText(UI.Color.muted:WrapTextInColorCode(PREVIEW_HINTS[form.kind]))
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
        valueBox.Instructions:SetText(VALUE_HINTS[form.kind])
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

    -- Like the macro window, leaving a reminder keeps what was changed in it, as long as it reads.
    local function commit()
        local spec = selected and readForm()
        if spec then Reminders.Update(selected, spec) end
    end

    -- Countdowns tick down in place, without rebuilding the rows.
    function frame:RefreshTimes()
        local now = GetServerTime()
        for _, row in ipairs(rows.active) do
            row.detail:SetText(Reminders.Detail(row.reminder, now))
        end
        self:RefreshStatus()
        refreshForm()
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
        listSection:SetBodyHeight(#sorted > 0 and #sorted * ROW_PITCH - UI.Space.tight or EMPTY_H)

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
            setNotice("Saved.", UI.Color.good)
            return
        end
        if not Reminders.Add(spec) then return end
        textBox:SetText("")
        valueBox:SetText("")
        clearFocus()
        setNotice("Added.", UI.Color.good)
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
