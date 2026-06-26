AutoPIExtended.defaults = {
	trinket1 = false,
	trinket2 = false,
	spell391109 = false,
	spell228260 = false,
	use_bloodmallet_spec_ids = true,
	use_weighted_scoring = true,
	ilvl_auto_baseline = true,
	ilvl_auto_k = true,
	ilvl_baseline = 250,
	ilvl_k = 100,
	ilvl_clamp = 0.25,
	show_target_frame = true,
}

local function RegisterCanvas(frame)
	local cat = Settings.RegisterCanvasLayoutCategory(frame, frame.name, frame.name);
		Settings.RegisterAddOnCategory(cat)
	AutoPIExtended.settingsCategoryID = (cat.GetID and cat:GetID()) or cat.ID
end

function AutoPIExtended:CreateCheckbox(option, label, parent, updateFunc)
	local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
	cb.Text:SetText(label)
	local function UpdateOption(value)
		self.db[option] = value
		cb:SetChecked(value)
		if updateFunc then
			updateFunc(value)
		end
	end
	UpdateOption(self.db[option])
	-- there already is an existing OnClick script that plays a sound, hook it
	cb:HookScript("OnClick", function(_, _, _) -- luacheck: ignore 212 (btn/down unused; WoW click handler signature)
		UpdateOption(cb:GetChecked())
	end)
	EventRegistry:RegisterCallback("AutoPIExtended.OnReset", function()
		UpdateOption(self.defaults[option])
	end, cb)
	return cb
end


function AutoPIExtended:CreateNumberBox(option, label, parent, width, onChange, allowFloat)
	local this = self
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetSize(width or 200, 24)

	local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fs:SetPoint("LEFT", 0, 0)
	fs:SetText(label)

	local eb = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	eb:SetSize(80, 20)
	eb:SetPoint("LEFT", fs, "RIGHT", 10, 0)
	eb:SetAutoFocus(false)
	if not allowFloat then eb:SetNumeric(true) end
	eb:SetNumber(tonumber(this.db[option]) or 0)

	local function commit()
		local v = tonumber(eb:GetText())
		if v == nil then
			eb:SetNumber(tonumber(this.db[option]) or 0)
			return
		end
		this.db[option] = v
		if onChange then onChange(v) end
	end

	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commit() end) -- luacheck: ignore 432
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); eb:SetNumber(tonumber(this.db[option]) or 0) end) -- luacheck: ignore 432
	eb:SetScript("OnEditFocusLost", function() commit() end)

	EventRegistry:RegisterCallback("AutoPIExtended.OnReset", function()
		this.db[option] = this.defaults[option]
		eb:SetNumber(tonumber(this.db[option]) or 0)
		if onChange then onChange(this.db[option]) end
	end, eb)

	frame.editBox = eb
	return frame
end

function AutoPIExtended:CreateMultiLineTextBoxWithBackground(option, parent)
	local this = self
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(420, 130)
    -- Position is set by the caller (InitializeOptions).

    -- Add a background
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(400, 100)
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(380)
    editBox:SetAutoFocus(false)
    editBox:SetText(self.db[option] or "")

    -- Callback when text changes
    editBox:SetScript("OnTextChanged", function(self, userInput) -- luacheck: ignore 432 (self = editBox widget; WoW callback pattern)
        if userInput then
            this.db[option] = self:GetText()
            this:rewriteMacro()
        end
    end)

    editBox:SetScript("OnEscapePressed", function(self) -- luacheck: ignore 432
        self:ClearFocus()
    end)

    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox
    return frame
end

function AutoPIExtended:InitializeOptions()
	-- main panel
	self.panel_main = CreateFrame("Frame")
	self.panel_main.name = "AutoPI Extended"

	-- Create main scroll frame for the entire panel
	local mainScrollFrame = CreateFrame("ScrollFrame", nil, self.panel_main, "UIPanelScrollFrameTemplate")
	mainScrollFrame:SetPoint("TOPLEFT", 16, -16)
	mainScrollFrame:SetPoint("BOTTOMRIGHT", -32, 16)

	local mainContent = CreateFrame("Frame", nil, mainScrollFrame)
	mainContent:SetSize(600, 1900) -- tall enough for the full 40-row spec list
	mainScrollFrame:SetScrollChild(mainContent)

	-- ===== Trinkets =====
	local trinketsTitle = mainContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	trinketsTitle:SetPoint("TOPLEFT", 0, 0)
	trinketsTitle:SetText("Trinkets")

	local trinket1CB = self:CreateCheckbox("trinket1", "Use Trinket 1 in macro", mainContent, function() AutoPIExtended:rewriteMacro() end)
	trinket1CB:SetPoint("TOPLEFT", trinketsTitle, "BOTTOMLEFT", 10, -10)

	local trinket2CB = self:CreateCheckbox("trinket2", "Use Trinket 2 in macro", mainContent, function() AutoPIExtended:rewriteMacro() end)
	trinket2CB:SetPoint("LEFT", trinket1CB, "RIGHT", 200, 0)

	local spell391109Info = C_Spell.GetSpellInfo(391109)
	local spell228260Info = C_Spell.GetSpellInfo(228260)

	local spell391109CB = self:CreateCheckbox("spell391109", "Cast " .. ((spell391109Info and spell391109Info.name) or "spell") .. " if known", mainContent, function() AutoPIExtended:rewriteMacro() end)
	spell391109CB:SetPoint("TOPLEFT", trinket1CB, "BOTTOMLEFT", 0, -10)

	local spell228260CB = self:CreateCheckbox("spell228260", "Cast " .. ((spell228260Info and spell228260Info.name) or "spell") .. " if known", mainContent, function() AutoPIExtended:rewriteMacro() end)
	spell228260CB:SetPoint("LEFT", spell391109CB, "RIGHT", 200, 0)

	-- ===== Display =====
	local hudCB = self:CreateCheckbox("show_target_frame", "Show on-screen PI target box", mainContent, function() AutoPIExtended:_UpdateTargetFrame() end)
	hudCB:SetPoint("TOPLEFT", spell391109CB, "BOTTOMLEFT", 0, -10)

	-- ===== Preferred Players =====
	local playersTitle = mainContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	playersTitle:SetPoint("TOPLEFT", hudCB, "BOTTOMLEFT", -10, -20)
	playersTitle:SetText("Preferred Players (character name only, one per line)")

	self.panel_main.playerslist = self:CreateMultiLineTextBoxWithBackground("playerslist", mainContent)
	self.panel_main.playerslist:SetPoint("TOPLEFT", playersTitle, "BOTTOMLEFT", 0, -10)

	-- ===== Target Scoring =====
	local scoringTitle = mainContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	scoringTitle:SetPoint("TOPLEFT", self.panel_main.playerslist, "BOTTOMLEFT", 0, -24)
	scoringTitle:SetText("Target Scoring")

	-- Forward declarations so the enable/disable helper can see every control.
	local weightedCB, autoBaseCB, autoKCB, baselineBox, kBox, clampBox

	local function setBoxEnabled(box, enabled)
		if box and box.editBox then
			box.editBox:SetEnabled(enabled)
			box.editBox:SetAlpha(enabled and 1.0 or 0.5)
		end
	end
	local function setCBEnabled(cb, enabled)
		if not cb then return end
		cb:SetEnabled(enabled)
		cb:SetAlpha(enabled and 1.0 or 0.5)
	end
	-- Manual boxes are only relevant when weighted scoring is on AND the matching
	-- auto-toggle is off. Clamp has no auto-toggle, so it follows weighted only.
	local function UpdateScoringEnabled()
		local weighted = AutoPIExtended.db.use_weighted_scoring
		setCBEnabled(autoBaseCB, weighted)
		setCBEnabled(autoKCB, weighted)
		setBoxEnabled(baselineBox, weighted and not AutoPIExtended.db.ilvl_auto_baseline)
		setBoxEnabled(kBox, weighted and not AutoPIExtended.db.ilvl_auto_k)
		setBoxEnabled(clampBox, weighted)
	end

	weightedCB = self:CreateCheckbox("use_weighted_scoring", "Use weighted scoring (spec order + item level)", mainContent, function()
		UpdateScoringEnabled()
		AutoPIExtended:rewriteMacro()
	end)
	weightedCB:SetPoint("TOPLEFT", scoringTitle, "BOTTOMLEFT", 10, -10)

	autoBaseCB = self:CreateCheckbox("ilvl_auto_baseline", "Auto-detect baseline from group average ilvl", mainContent, function()
		UpdateScoringEnabled()
		AutoPIExtended:rewriteMacro()
	end)
	autoBaseCB:SetPoint("TOPLEFT", weightedCB, "BOTTOMLEFT", 0, -6)

	autoKCB = self:CreateCheckbox("ilvl_auto_k",
		("Auto-scale K from baseline (baseline*%g, clamped %d-%d)"):format(self.K_MULTIPLIER, self.K_MIN, self.K_MAX),
		mainContent, function()
			UpdateScoringEnabled()
			AutoPIExtended:rewriteMacro()
		end)
	autoKCB:SetPoint("TOPLEFT", autoBaseCB, "BOTTOMLEFT", 0, -6)

	baselineBox = self:CreateNumberBox("ilvl_baseline", ("Baseline ilvl (default %d)"):format(self.defaults.ilvl_baseline), mainContent, 240, function() AutoPIExtended:rewriteMacro() end)
	baselineBox:SetPoint("TOPLEFT", autoKCB, "BOTTOMLEFT", 0, -12)

	kBox = self:CreateNumberBox("ilvl_k", "K (ilvl per +1.0 score)", mainContent, 240, function() AutoPIExtended:rewriteMacro() end)
	kBox:SetPoint("LEFT", baselineBox, "RIGHT", 40, 0)

	clampBox = self:CreateNumberBox("ilvl_clamp", ("Clamp (max +/- score, default %.2f)"):format(self.defaults.ilvl_clamp), mainContent, 300, function() AutoPIExtended:rewriteMacro() end, true)
	clampBox:SetPoint("TOPLEFT", baselineBox, "BOTTOMLEFT", 0, -12)

	UpdateScoringEnabled()

	-- ===== Spec Priority Order =====
	local specTitle = mainContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	specTitle:SetPoint("TOPLEFT", clampBox, "BOTTOMLEFT", 0, -24)
	specTitle:SetText("Spec Priority Order")

	local infoText = mainContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	infoText:SetPoint("TOPLEFT", specTitle, "BOTTOMLEFT", 10, -10)
	infoText:SetWidth(560)
	infoText:SetJustifyH("LEFT")
	infoText:SetText("Using the built-in bloodmallet Power Infusion order (single-target in raids, multitarget elsewhere). Update the addon periodically to keep it current, or click below to order specs yourself.")

	-- Spec list container (manual mode only)
	local content = CreateFrame("Frame", nil, mainContent)
	content:SetSize(560, 1250)

	local function RefreshList()
		for _, child in ipairs({ content:GetChildren() }) do child:Hide() end
		local order = AutoPIExtended.db.specIDs_order or {}
		for i, specID in ipairs(order) do
			local _, name, _, icon, _, _, className = GetSpecializationInfoByID(specID)

			local row = CreateFrame("Frame", nil, content)
			row:SetSize(540, 30)
			row:SetPoint("TOPLEFT", 10, -((i - 1) * 30))

			local upBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			upBtn:SetSize(20, 20)
			upBtn:SetPoint("LEFT", 5, 0)
			upBtn:SetText("+")
			if i == 1 then upBtn:Hide() end
			upBtn:SetScript("OnClick", function()
				if i > 1 then
					order[i], order[i-1] = order[i-1], order[i]
					AutoPIExtended:rewriteMacro()
					RefreshList()
				end
			end)

			local downBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
			downBtn:SetSize(20, 20)
			downBtn:SetPoint("LEFT", 30, 0)
			downBtn:SetText("-")
			if i == #order then downBtn:Hide() end
			downBtn:SetScript("OnClick", function()
				if i < #order then
					order[i], order[i+1] = order[i+1], order[i]
					AutoPIExtended:rewriteMacro()
					RefreshList()
				end
			end)

			local iconTexture = row:CreateTexture(nil, "ARTWORK")
			iconTexture:SetSize(18, 18)
			iconTexture:SetPoint("LEFT", downBtn, "RIGHT", 5, 0)
			iconTexture:SetTexture(icon)

			local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			label:SetPoint("LEFT", iconTexture, "RIGHT", 5, 0)
			label:SetText((name or ("specID " .. tostring(specID))) .. (className and (" - " .. className) or ""))
		end
		content:SetHeight(math.max(1, #order) * 30 + 10)
	end

	-- Auto/manual toggle. Both buttons share the slot directly under specTitle;
	-- only one is shown at a time (infoText occupies that slot in auto mode).
	local manualModeBtn = CreateFrame("Button", nil, mainContent, "UIPanelButtonTemplate")
	manualModeBtn:SetSize(200, 26)
	manualModeBtn:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -10)
	manualModeBtn:SetText("Order Specs Manually")

	local autoModeBtn = CreateFrame("Button", nil, mainContent, "UIPanelButtonTemplate")
	autoModeBtn:SetSize(200, 26)
	autoModeBtn:SetPoint("TOPLEFT", specTitle, "BOTTOMLEFT", 10, -10)
	autoModeBtn:SetText("Use Automatic Ordering")

	content:SetPoint("TOPLEFT", autoModeBtn, "BOTTOMLEFT", 0, -10)

	local function ShowAutomaticMode()
		content:Hide()
		autoModeBtn:Hide()
		infoText:Show()
		manualModeBtn:Show()
	end

	local function ShowManualMode()
		infoText:Hide()
		manualModeBtn:Hide()
		autoModeBtn:Show()
		content:Show()
		RefreshList()
	end

	manualModeBtn:SetScript("OnClick", function()
		AutoPIExtended.db.use_bloodmallet_spec_ids = false
		if not AutoPIExtended.db.specIDs_order or #AutoPIExtended.db.specIDs_order == 0 then
			AutoPIExtended.db.specIDs_order = {}
			for _, specID in ipairs(AutoPIExtended.bloodmallet_spec_ids) do
				table.insert(AutoPIExtended.db.specIDs_order, specID)
			end
		end
		ShowManualMode()
		AutoPIExtended:rewriteMacro()
	end)

	autoModeBtn:SetScript("OnClick", function()
		AutoPIExtended.db.use_bloodmallet_spec_ids = true
		ShowAutomaticMode()
		AutoPIExtended:rewriteMacro()
	end)

	if AutoPIExtended.db.use_bloodmallet_spec_ids then
		ShowAutomaticMode()
	else
		ShowManualMode()
	end

	RegisterCanvas(self.panel_main)
end
