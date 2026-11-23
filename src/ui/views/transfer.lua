local Components = require("src/ui/shared/components")
local Base = require("src/ui/views/view")
local Notes = require("src/notes/notes")
local ShareSelection = require("src/notes/share_selection")
local TextLayout = require("src/ui/shared/text_layout")
local WordWrap = require("src/ui/shared/word_wrap")
local ImportPreview = require("src/notes/import_preview")
local Preview = require("src/ui/views/import_preview")

local Transfer = {}
Transfer.__index = Transfer
setmetatable(Transfer, {__index = Base})
local SHARE_MAX_LENGTH = ShareSelection.LIMIT
local MUTED = 0xB7B1A7FF
local label, noteFont, editorFrame = Base.Label, Base.NoteFont, Base.EditorFrame

local function normalizeLineEndings(text)
    return text:gsub("\r\n", "\n"):gsub("\r", "\n")
end

function Transfer.new(parent, options, callbacks)
    local self = Base.Init(setmetatable({}, Transfer), parent, options, callbacks)
    self.transferData, self.draft = options.transferData, options.draft
    self.shareSelection = options.selection
    self.transferText = options.text or ""
    self:RenderTransfer()
    if self.view == "import" and options.importSession and options.importSession.text == self.transferText then
        self:PreviewImport(options.importSession)
    end
    return self
end

function Transfer:Snapshot()
    local text = self.transfer and self.transfer:GetText() or self.transferText
    local session
    if self.preview and self.preview.source and self.importSourceText == text then
        session = {text = text, selected = self.preview:SelectionSnapshot(), visible = self.previewVisible,
            page = self.preview.page, scroll = self.preview.scroll.scrollY}
    end
    return {text = text, importSession = session}
end

function Transfer:Back()
    if self.shareSelection then
        self:Navigate("shareSelect", {selection = self.shareSelection})
    elseif self.transferData and self.draft then
        self:Navigate("edit", {draft = self.draft})
    else self:ShowList() end
end

function Transfer:InvalidatePreview(clearSelection)
    self.previewVisible = false
    if self.preview then
        self.preview.root.hidden = true
        if clearSelection ~= false then
            self.preview.plan, self.preview.source, self.preview.destination = nil, nil, nil
            self.preview.entries, self.preview.selected, self.preview.selectedCount = {}, {}, 0
        end
    end
    if clearSelection ~= false then self.importSourceText = nil end
    if self.previewButton then self.previewButton.content.content = "Preview" end
    if self.importButton then
        if clearSelection == false then self:UpdateImportSelection()
        else self.importButton:SetDisabled(false) end
    end
    if self.layout then self.layout() end
end

function Transfer:UpdateImportSelection()
    local preview = self.preview
    if not preview or not preview.source then return end
    local plan = preview.plan
    local empty = #preview.source.notes > 0 and preview.selectedCount == 0
        or plan and plan.addedCount == 0 and #plan.categoryChanges == 0
    self.importButton:SetDisabled(preview.error ~= nil or empty == true or plan == nil)
    local instruction = self.previewVisible and "Choose notes, then press Import."
        or preview.selectedCount .. " / " .. #preview.source.notes .. " notes selected. Preview to review."
    self:Status(preview.error or empty and "Select at least one note to import." or instruction,
        preview.error ~= nil)
end

function Transfer:PreviewImport(session)
    if self.destroyed or self.clearing or self.view ~= "import" then return end
    if self.previewVisible and not session then
        self:InvalidatePreview(false)
        return
    end
    local text = self.transfer:GetText()
    local source, message = ImportPreview.Parse(text)
    if not source then
        self:InvalidatePreview()
        self:Status(message, true)
        self.importButton:SetDisabled(true)
        return
    end
    local selected = session and session.selected
        or self.importSourceText == text and self.preview and self.preview.source and self.preview:SelectionSnapshot() or nil
    self.preview = self.preview or Preview.new(self.surface, function(control)
        if not self.destroyed and not self.clearing and self.preview == control then self:UpdateImportSelection() end
    end)
    self.preview:SetSource(source, self.data, selected)
    self.importSourceText, self.activeInput = text, nil
    self.previewVisible = not session or session.visible == true
    self.previewButton.content.content = self.previewVisible and "Paste" or "Preview"
    if session then self.preview.page = math.max(1, math.min(self.preview.pages, session.page or 1)) end
    self:UpdateImportSelection()
    self.layout()
    if session then self.preview.scroll:SetScrollPosition(session.scroll or 0) end
end

function Transfer:ImportError(message)
    self:Status(message, true)
    if self.previewVisible then
        self.preview.error = message
        self.preview.scroll:SetScrollPosition(0)
        self.layout()
    end
end

function Transfer:ImportNotes()
    if self.destroyed or self.clearing or self.view ~= "import" then return end
    local text = self.transfer:GetText()
    if self.preview and self.preview.source then
        if text ~= self.importSourceText then
            self:InvalidatePreview()
            self:Status("The pasted text changed. Preview it again to choose notes.", true)
            self.importButton:SetDisabled(true)
            return
        end
        local source, message = ImportPreview.Parse(text)
        if not source then self:ImportError(message); return end
        local called, selectedText, selectedCount = pcall(ImportPreview.SelectedText, source, self.preview:SelectionSnapshot())
        if not called then self:ImportError("The selected notes could not be prepared for import."); return end
        if #source.notes > 0 and selectedCount == 0 then self:ImportError("Select at least one note to import."); return end
        text = selectedText
    end
    local categories, nextCategoryID, notes = self.data.categories, self.data.nextCategoryID, self.data.notes
    local called, ok, message = pcall(Notes.Import, self.data, text)
    if not called then ok, message = nil, "These notes could not be imported (" .. tostring(ok):sub(1, 160) .. ")." end
    if not ok then
        self.data.categories, self.data.nextCategoryID, self.data.notes = categories, nextCategoryID, notes
        self:ImportError(message or "These notes could not be imported.")
        return
    end
    local saved
    called, saved, message = pcall(self.Save, self)
    if not called then saved, message = nil, "The imported notes could not be saved. Please try again." end
    if not saved then
        self.data.categories, self.data.nextCategoryID, self.data.notes = categories, nextCategoryID, notes
        self:ImportError(message or "The imported notes could not be saved.")
        return
    end
    self.state.query, self.state.scroll, self.state.categoryID = "", 0, nil
    self:ShowList()
end

function Transfer:RenderBlockedShare(text)
    local detail = self.shareSelection and "Cannot share this selection. Go back and deselect notes."
        or self.transferData and "This note is too large to share. Shorten its text or attachments."
        or "Cannot share all notes at once. Go back and select fewer notes to share."
    local warningText = "Share code: " .. #text .. " characters (limit: 9,999). " .. detail
    local font = config.Font.MUSEO_SANS_13PT_REGULAR
    self.warningScroll = self:Track(prettyui.SimpleView.new(self.surface, Components.Options({
        x = 8, y = 8, width = self.width, height = math.max(1, self.height - 54), scrollStep = 36
    })))
    self.transferWarning = label(self.warningScroll.content, "", 6, 6, 1, 18, 0xFF3333FF)
    local back = self:Button("Back", self.width - 88, self.height - 34, 88, function() self:Back() end)
    self.layout = function()
        local width, height = self.width, self.height
        local scroll = self.warningScroll.scrollY
        self.warningScroll:SetSize(width, math.max(1, height - 54))
        local available = math.max(1, self.warningScroll.contentWidth - 12)
        local lines = TextLayout.Lines(warningText, font, available)
        self.transferWarning.content = table.concat(lines, "<br>")
        self.transferWarning:SetSize(available, math.max(18, #lines * 18))
        self.warningScroll:SetContentHeight(self.transferWarning.height + 12)
        self.warningScroll:SetScrollPosition(scroll)
        local buttonWidth = math.min(88, math.max(1, width - 16))
        back.root:SetPos(importing and 8 or width - buttonWidth, height - 34)
        back.root:SetSize(buttonWidth, 28)
    end
    self.layout()
end

function Transfer:RenderTransfer()
    local width, height = self.width, self.height
    local importing = self.view == "import"
    local single = self.transferData ~= nil and self.shareSelection == nil
    local data = self.transferData or self.data
    local titles = {
        share = self.shareSelection and "Share selected notes" or single and "Share note" or "Share notes",
        copy = single and "Copy note" or "Copy notes",
        import = "Import notes"
    }
    local text = importing and (self.transferText or "") or self.view == "copy"
        and Notes.PlainText(data) or Notes.Export(data)
    if importing then text = normalizeLineEndings(text); self.transferText = text end
    self:Heading(titles[self.view])
    if self.view == "share" and #text > SHARE_MAX_LENGTH then
        self:RenderBlockedShare(text)
        return
    end
    local compactHeight = height < 230
    local instructionHeight = compactHeight and 24 or 44
    local fieldY = compactHeight and (importing and 6 or 34) or 54
    local statusHeight = importing and (compactHeight and 28 or 44) or 0
    local footerHeight = importing and width < 310 and 70 or 38
    local statusY = height - statusHeight - footerHeight - 6
    local instruction = label(self.surface, importing and "Paste shared notes or copied note text."
        or "Click the text, then press Ctrl+A and Ctrl+C.", 8, 6, width, instructionHeight, MUTED)
    instruction.hidden = importing and compactHeight
    local fontName = noteFont(self.settings)
    local font = config.Font[fontName]
    local frameWidth = width - 24
    local textWidth = math.max(1, frameWidth - 32)
    local fieldHeight = math.max(importing and 1 or 28, statusY - fieldY - (importing and 8 or 0))

    local frame = editorFrame(self.surface, frameWidth)
    frame:SetPos(8, fieldY)
    frame:SetSize(frameWidth, fieldHeight)
    local viewportHeight = math.max(1, fieldHeight - 20)
    self.transferScroll = self:Track(prettyui.SimpleView.new(self.surface, Components.Options({
        x = 20, y = fieldY + 10, width = width - 12, height = viewportHeight, scrollStep = 36
    })))
    local measuredText, measuredWidth, contentHeight
    local function updateFieldHeight(field)
        if measuredText ~= field.root.content or measuredWidth ~= textWidth then
            measuredText, measuredWidth = field.root.content, textWidth
            contentHeight = font:GetStringHeightAndLineCount(measuredText .. "\n", textWidth, 0, true, false, true)
        end
        field.root:SetSize(textWidth, math.max(viewportHeight, contentHeight))
        field.root:UpdateLayout()
        self.transferScroll:SetContentHeight(field.root.height)
    end
    self.transfer = self:TrackField(self.transferScroll:AddTextField({
        x = 0, y = 0, width = textWidth, height = viewportHeight,
        stylesheetID = id.StyleSheet.INPUT_INVISIBLE,
        contentMargin = ui.Margin.new(0),
        text = "", maxLength = Notes.MAX_EXPORT,
        onChange = function(field, reason, value)
            if self.destroyed or self.transfer ~= field then return end
            if importing then
                local normalized = normalizeLineEndings(value)
                if normalized ~= value then field:SetText(normalized, false); value = normalized end
            end
            self.transferText = value
            if reason == ui.InputFieldActionResult.CONTENT_CHANGE then
                self:Status("")
                if importing then self:InvalidatePreview() end
            end
            field:Wrap(font, textWidth)
            updateFieldHeight(field)
        end
    }), true)
    self.transfer.editorFrame = frame
    self.transfer.root.text.font = id.Font[fontName]
    self.transfer.root.text.rgba = 0xFFFFFFFF
    self.transfer.root.text.maxLines = 255
    self.transfer.root.text.alignHorizontal = ui.AlignMode.TOPLEFT
    self.transfer.root.text.alignVertical = ui.AlignMode.TOPLEFT
    self.transfer.root.scrollbar.size = 0
    self.transfer.root.scrollbar.visible = false
    WordWrap.Bind(self.transfer, text)
    self.transfer:Wrap(font, textWidth)
    updateFieldHeight(self.transfer)
    -- The managed frame must draw behind the category-zero scrolling content.
    frame:MoveToBack()
    if importing then
        self.status = label(self.surface, "", 8, statusY, width, statusHeight, MUTED)
    end
    local buttonWidth = math.min(88, math.floor((width - 16) / (importing and 3 or 1)))
    if importing then
        self.previewButton = self:Button("Preview", 16 + buttonWidth, height - 34, buttonWidth, function() self:PreviewImport() end)
        self.importButton = self:Button("Import", width - buttonWidth, height - 34, buttonWidth, function() self:ImportNotes() end)
    end
    local back = self:Button("Back", importing and 8 or width - buttonWidth, height - 34, buttonWidth, function() self:Back() end)
    self.layout = function()
        local oldTextWidth = textWidth
        local scroll = self.transferScroll.scrollY
        width, height = self.width, self.height
        compactHeight = height < 230
        instructionHeight, fieldY = compactHeight and 24 or 44, compactHeight and (importing and 6 or 34) or 54
        statusHeight = importing and (self.previewVisible and compactHeight and 0 or compactHeight and 28 or 44) or 0
        footerHeight = importing and width < 310 and 70 or 38
        statusY = height - statusHeight - footerHeight - 6
        instruction.hidden = importing and compactHeight
        instruction:SetSize(width, instructionHeight)
        frameWidth, textWidth = width - 24, math.max(1, width - 56)
        fieldHeight = math.max(importing and 1 or 28, statusY - fieldY - (importing and 8 or 0))
        viewportHeight = math.max(1, fieldHeight - 20)
        frame:SetPos(8, fieldY)
        frame:SetSize(frameWidth, fieldHeight)
        self.transferScroll.root:SetPos(20, fieldY + 10)
        self.transferScroll:SetSize(width - 12, viewportHeight)
        if oldTextWidth ~= textWidth then self.transfer:Wrap(font, textWidth) end
        updateFieldHeight(self.transfer)
        self.transferScroll:SetScrollPosition(scroll)
        buttonWidth = math.min(88, math.floor((width - 16) / (importing and 3 or 1)))
        if importing then
            self.status.hidden = self.previewVisible and compactHeight or false
            self.status:SetPos(8, statusY)
            self.status:SetSize(width, statusHeight)
            local narrow = width < 310
            buttonWidth = math.min(88, math.floor((width - (narrow and 24 or 32)) / (narrow and 2 or 3)))
            self.importButton.root:SetPos(width - buttonWidth, height - 34)
            self.importButton.root:SetSize(buttonWidth, 28)
            self.previewButton.root:SetPos(narrow and width - buttonWidth or 16 + buttonWidth, height - (narrow and 66 or 34))
            self.previewButton.root:SetSize(buttonWidth, 28)
            frame.hidden, self.transferScroll.root.hidden = self.previewVisible == true, self.previewVisible == true
            if self.preview then
                self.preview.root.hidden = not self.previewVisible
                if self.previewVisible then self.preview:SetBounds(8, fieldY, frameWidth, fieldHeight) end
            end
        end
        back.root:SetPos(importing and 8 or width - buttonWidth, height - (importing and width < 310 and 66 or 34))
        back.root:SetSize(buttonWidth, 28)
    end
    self.layout()
end

function Transfer:Destroy(detached)
    if self.destroyed then return end
    if self.preview then self.preview:Destroy(detached); self.preview = nil end
    Base.Destroy(self, detached)
end

return Transfer
