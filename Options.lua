AutoPIRemix.defaults = {
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
	ilvl_clamp = 0.10,
	show_target_frame = true,
}

local function CreateIcon(icon, width, height, parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width, height)
	f.tex = f:CreateTexture()
	f.tex:SetAllPoints(f)
	f.tex:SetTexture(icon)
	return f
end

local function RegisterCanvas(frame)
	local cat = Settings.RegisterCanvasLayoutCategory(frame, frame.name, frame.name);
		Settings.RegisterAddOnCategory(cat)
	AutoPIRemix.settingsCategoryID = (cat.GetID and cat:GetID()) or cat.ID
end

function AutoPIRemix:CreateCheckbox(option, label, parent, updateFunc)
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
	cb:HookScript("OnClick", function(_, btn, down)
		UpdateOption(cb:GetChecked())
	end)
	EventRegistry:RegisterCallback("AutoPIRemix.OnReset", function()
		UpdateOption(self.defaults[option])
	end, cb)
	return cb
end


function AutoPIRemix:CreateNumberBox(option, label, parent, width, onChange, allowFloat)
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

	eb:SetScript("OnEnterPressed", function(self) self:ClearFocus(); commit() end)
	eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); eb:SetNumber(tonumber(this.db[option]) or 0) end)
	eb:SetScript("OnEditFocusLost", function() commit() end)

	EventRegistry:RegisterCallback("AutoPIRemix.OnReset", function()
		this.db[option] = this.defaults[option]
		eb:SetNumber(tonumber(this.db[option]) or 0)
		if onChange then onChange(this.db[option]) end
	end, eb)

	frame.editBox = eb
	return frame
end

function AutoPIRemix:CreateMultiLineTextBoxWithBackground(option, parent)
	local this = self
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(420, 130)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -50)

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
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            this.db[option] = self:GetText()
            this:rewriteMacro()
        end
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox
    return frame
end

function AutoPIRemix:InitializeOptions()
	-- main panel
	self.panel_main = CreateFrame("Frame")
	self.panel_main.name = "AutoPI Remix"

	-- Create main scroll frame for the entire panel
	local mainScrollFrame = CreateFrame("ScrollFrame", nil, self.panel_main, "UIPanelScrollFrameTemplate")
	mainScrollFrame:SetPoint("TOPLEFT", 16, -16)
	mainScrollFrame:SetPoint("BOTTOMRIGHT", -32, 16)

	local mainContent = CreateFrame("Frame", nil, mainScrollFrame)
	mainContent:SetSize(600, 1000) -- Large enough to hold all content
	mainScrollFrame:SetScrollChild(mainContent)

	-- Add trinkets section at the top
	local trinketsTitle = mainContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	trinketsTitle:SetPoint("TOPLEFT", 0, 0)
	trinketsTitle:SetText("Trinkets")

	local trinket1CB = self:CreateCheckbox("trinket1", "Use Trinket 1 in macro", mainContent, function(value)
		AutoPIRemix:rewriteMacro()
	end)
	trinket1CB:SetPoint("TOPLEFT", trinketsTitle, "BOTTOMLEFT", 10, -10)

	local trinket2CB = self:CreateCheckbox("trinket2", "Use Trinket 2 in macro", mainContent, function(value)
		AutoPIRemix:rewriteMacro()
	end)
	trinket2CB:SetPoint("LEFT", trinket1CB, "RIGHT", 200, 0)

	local spell391109Info = C_Spell.GetSpellInfo(391109)
	local spell228260Info = C_Spell.GetSpellInfo(228260)

	local spell391109CB = self:CreateCheckbox("spell391109", "Cast " .. spell391109Info.name .. " if known", mainContent, function(value)
		AutoPIRemix:rewriteMacro()
	end)
	spell391109CB:SetPoint("TOPLEFT", trinket1CB, "BOTTOMLEFT", 0, -10)

	local spell228260CB = self:CreateCheckbox("spell228260", "Cast " .. spell228260Info.name .. " if known", mainContent, function(value)
		AutoPIRemix:rewriteMacro()
	end)
	spell228260CB:SetPoint("LEFT", spell391109CB, "RIGHT", 200, 0)

	-- Add players list section below
	local playersTitle = mainContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	playersTitle:SetPoint("TOPLEFT", spell391109CB, "BOTTOMLEFT", 0, -30)
	playersTitle:SetText("Preferred Players (only character name), one by line")

	self.panel_main.playerslist = self:CreateMultiLineTextBoxWithBackground("playerslist", mainContent)
	self.panel_main.playerslist:SetPoint("TOPLEFT", playersTitle, "BOTTOMLEFT", 0, -10)

	-- Add specs list section below
	local title = mainContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", self.panel_main.playerslist, "BOTTOMLEFT", 0, -30)
	title:SetText("Spec Order Configuration")


	-- Weighted scoring section (spec order + ilvl)
	local scoringTitle = mainContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	scoringTitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -30)
	scoringTitle:SetText("Target Scoring")

	local baselineBox
	local function UpdateBaselineEnabled()
		if baselineBox and baselineBox.editBox then
			if AutoPIRemix.db.ilvl_auto_baseline then
				baselineBox.editBox:Disable()
				baselineBox.editBox:SetAlpha(0.5)
			else
				baselineBox.editBox:Enable()
				baselineBox.editBox:SetAlpha(1.0)
			end
		end
	end

	local weightedCB = self:CreateCheckbox("use_weighted_scoring", "Use weighted scoring (spec order + item level)", mainContent, function()
		AutoPIRemix:rewriteMacro()
	end)
	weightedCB:SetPoint("TOPLEFT", scoringTitle, "BOTTOMLEFT", 10, -10)

	local autoBaseCB = self:CreateCheckbox("ilvl_auto_baseline", "Auto-detect baseline from group average ilvl", mainContent, function()
		UpdateBaselineEnabled()
		AutoPIRemix:rewriteMacro()
	end)
	autoBaseCB:SetPoint("TOPLEFT", weightedCB, "BOTTOMLEFT", 0, -6)
local kBox
local function UpdateKEnabled()
	if kBox and kBox.editBox then
		if AutoPIRemix.db.ilvl_auto_k then
			kBox.editBox:Disable()
			kBox.editBox:SetAlpha(0.5)
		else
			kBox.editBox:Enable()
			kBox.editBox:SetAlpha(1.0)
		end
	end
end

local autoKCB = self:CreateCheckbox("ilvl_auto_k", "Auto-scale K from baseline (baseline*0.8, clamped 60-140)", mainContent, function()
	UpdateKEnabled()
	AutoPIRemix:rewriteMacro()
end)
autoKCB:SetPoint("TOPLEFT", autoBaseCB, "BOTTOMLEFT", 0, -6)



	baselineBox = self:CreateNumberBox("ilvl_baseline", "Baseline ilvl", mainContent, 220, function() AutoPIRemix:rewriteMacro() end)
	baselineBox:SetPoint("TOPLEFT", autoKCB, "BOTTOMLEFT", 0, -10)
	UpdateBaselineEnabled()

	kBox = self:CreateNumberBox("ilvl_k", "K (ilvl per +1.0 score)", mainContent, 260, function() AutoPIRemix:rewriteMacro() end)
	kBox:SetPoint("LEFT", baselineBox, "RIGHT", 40, 0)
	UpdateKEnabled()


	local clampBox = self:CreateNumberBox("ilvl_clamp", "Clamp (max +/- score)", mainContent, 260, function() AutoPIRemix:rewriteMacro() end, true)
	clampBox:SetPoint("TOPLEFT", baselineBox, "BOTTOMLEFT", 0, -10)

		-- Spec-order section title (separate from the main title to avoid anchor cycles)
		local specTitle = mainContent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
		specTitle:SetText("Spec Priority Order")
		specTitle:SetPoint("TOPLEFT", clampBox, "BOTTOMLEFT", -10, -30)


	local content = CreateFrame("Frame", nil, mainContent)
	content:SetSize(600, 800)
	content:SetPoint("TOPLEFT", specTitle, "BOTTOMLEFT", 0, -10)

	local function RefreshList()
		for i, child in ipairs({content:GetChildren()}) do
			child:Hide()
		end

		for i, specID in ipairs(AutoPIRemix.db.specIDs_order or {}) do
			local id, name, desc, icon, role, classFile, className = GetSpecializationInfoByID(specID)

			local line = content:CreateTexture(nil, "BACKGROUND")
			local frame = CreateFrame("Frame", nil, content)
			frame:SetSize(580, 30)
			frame:SetPoint("TOPLEFT", 10, -((i - 1) * 30))

			local upBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
			upBtn:SetSize(20, 20)
			upBtn:SetPoint("LEFT", 5, 0)
			upBtn:SetText("+")
			if i == 1 then
				upBtn:Hide()
			end
			upBtn:SetScript("OnClick", function()
				if i > 1 then
					AutoPIRemix.db.specIDs_order[i], AutoPIRemix.db.specIDs_order[i-1] = AutoPIRemix.db.specIDs_order[i-1], AutoPIRemix.db.specIDs_order[i]
					RefreshList()
				end
			end)

			local downBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
			downBtn:SetSize(20, 20)
			downBtn:SetPoint("LEFT", 30, 0)
			downBtn:SetText("-")
			if i == #AutoPIRemix.db.specIDs_order then
				downBtn:Hide()
			end
			downBtn:SetScript("OnClick", function()
				if i < #AutoPIRemix.db.specIDs_order then
					AutoPIRemix.db.specIDs_order[i], AutoPIRemix.db.specIDs_order[i+1] = AutoPIRemix.db.specIDs_order[i+1], AutoPIRemix.db.specIDs_order[i]
					AutoPIRemix:rewriteMacro()
					RefreshList()
				end
			end)

			local iconTexture = frame:CreateTexture(nil, "ARTWORK")
			iconTexture:SetSize(18, 18)
			iconTexture:SetPoint("LEFT", downBtn, "RIGHT", 5, 0)
			iconTexture:SetTexture(icon)

			local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
			label:SetPoint("LEFT", iconTexture, "RIGHT", 5, 0)
			label:SetText(name .. " - " .. className)
		end
	end

	-- Create all UI elements at initialization
	infoText = mainContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	infoText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	infoText:SetText("Spec order by bloodmallet data. Please update the addon regularly to stay fresh. Or click the button below to order them yourself.")
	infoText:SetWidth(580)

	manualModeBtn = CreateFrame("Button", nil, mainContent, "UIPanelButtonTemplate")
	manualModeBtn:SetSize(200, 30)
	manualModeBtn:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -10)
	manualModeBtn:SetText("Order Specs Manually")
	manualModeBtn:SetScript("OnClick", function()
		AutoPIRemix.db.use_bloodmallet_spec_ids = false
		if not AutoPIRemix.db.specIDs_order or #AutoPIRemix.db.specIDs_order == 0 then
			AutoPIRemix.db.specIDs_order = {}
			for _, specID in ipairs(AutoPIRemix.bloodmallet_spec_ids) do
				table.insert(AutoPIRemix.db.specIDs_order, specID)
			end
		end
		infoText:Hide()
		manualModeBtn:Hide()
		autoModeBtn:Show()
		content:Show()
		content:SetPoint("TOPLEFT", autoModeBtn, "BOTTOMLEFT", 0, -10)
		RefreshList()
		AutoPIRemix:rewriteMacro()
	end)

	autoModeBtn = CreateFrame("Button", nil, mainContent, "UIPanelButtonTemplate")
	autoModeBtn:SetSize(200, 30)
	autoModeBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
	autoModeBtn:SetText("Use Automatic Ordering")
	autoModeBtn:SetScript("OnClick", function()
		AutoPIRemix.db.use_bloodmallet_spec_ids = true
		content:Hide()
		autoModeBtn:Hide()
		manualModeBtn:Show()
		infoText:Show()
		AutoPIRemix:rewriteMacro()
	end)

	local function ShowManualMode()
		content:Show()
		infoText:Hide()
		manualModeBtn:Hide()
		autoModeBtn:Show()
		content:SetPoint("TOPLEFT", autoModeBtn, "BOTTOMLEFT", 0, -10)
		RefreshList()
	end

	local function ShowAutomaticMode()
		content:Hide()
		autoModeBtn:Hide()
		infoText:Show()
		manualModeBtn:Show()
	end

	if AutoPIRemix.db.use_bloodmallet_spec_ids then
		ShowAutomaticMode()
	else
		ShowManualMode()
	end

	RefreshList()

	RegisterCanvas(self.panel_main)
end
