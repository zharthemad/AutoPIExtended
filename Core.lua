AutoPIRemix = CreateFrame("Frame")

function AutoPIRemix:OnEvent(event, ...)
	self[event](self, event, ...)
end
AutoPIRemix:SetScript("OnEvent", AutoPIRemix.OnEvent)
AutoPIRemix:RegisterEvent("ADDON_LOADED")

-- List taken the 2025-04-10 from bloodmallet calcs
AutoPIRemix.bloodmallet_spec_ids = {
	255, -- Survival Hunter
	1467, -- Devastation Evoker
	252, -- Unholy Death Knight
	266, -- Demonology Warlock
	265, -- Affliction Warlock
	254, -- Marksmanship Hunter
	253, -- Beast Mastery Hunter
	251, -- Frost Death Knight
	103, -- Feral Druid
	63, -- Fire Mage
	269, -- Windwalker Monk
	71, -- Arms Warrior
	259, -- Assassination Rogue
	267, -- Destruction Warlock
	263, -- Enhancement Shaman
	62, -- Arcane Mage
	577, -- Havoc Demon Hunter
	70, -- Retribution Paladin
	102, -- Balance Druid
	262, -- Elemental Shaman
	581, -- Vengeance Demon Hunter
	64, -- Frost Mage
	73, -- Protection Warrior
	66, -- Protection Paladin
	258, -- Shadow Priest
	72, -- Fury Warrior
	104, -- Guardian Druid
	261, -- Subtlety Rogue
	250, -- Blood Death Knight
	260, -- Outlaw Rogue
	268, -- Brewmaster Monk
	1473, -- Augmentation Evoker
	105, -- Restoration Druid
	270, -- Mistweaver Monk
	65, -- Holy Paladin
	256, -- Discipline Priest
	257, -- Holy Priest
	264, -- Restoration Shaman
	1468, -- Preservation Evoker
}

-- ------------------------------------------------------------
-- Lightweight group spec tracking (no LibGroupInSpecT required)
-- Uses Inspect APIs with throttling + caching.
-- ------------------------------------------------------------

-- How often to rescan group for missing/stale spec info (seconds)
AutoPIRemix.SCAN_INTERVAL = 4
-- How long we trust a cached spec before refreshing (seconds)
AutoPIRemix.CACHE_TTL = 60

function AutoPIRemix:isDPS(specID)
	local _, _, _, _, role = GetSpecializationInfoByID(specID)
	return role == "DAMAGER"
end

local function unit_iter()
	if IsInRaid() then
		local n = GetNumGroupMembers()
		local i = 0
		return function()
			i = i + 1
			if i <= n then return "raid" .. i end
		end
	elseif IsInGroup() then
		local i = 0
		return function()
			i = i + 1
			if i <= 4 then return "party" .. i end
		end
	else
		return function() return nil end
	end
end


-- ------------------------------------------------------------
-- Scoring helpers (spec order + inspect ilvl)
-- ------------------------------------------------------------

function AutoPIRemix:_ComputeAutoBaseline()
	-- Returns baseline, sourceString
	local manual = tonumber(self.db.ilvl_baseline) or 0
	if not self.db.ilvl_auto_baseline then
		self._last_baseline_used = manual
		self._last_baseline_source = "manual"
		return manual, "manual"
	end

	local sum, n = 0, 0
	for guid, entry in pairs(self.group_cache or {}) do
		if entry and entry.ilvl and entry.ilvl > 0 and entry.spec and self:isDPS(entry.spec) then
			-- Exclude the priest (player) from target baseline
			if entry.name and not UnitIsUnit(entry.name, "player") then
				sum = sum + entry.ilvl
				n = n + 1
			end
		end
	end

	if n > 0 then
		local avg = sum / n
		self._last_baseline_used = avg
		self._last_baseline_source = "auto(n=" .. n .. ")"
		return avg, self._last_baseline_source
	end

	-- Fallback if nothing inspectable yet
	self._last_baseline_used = manual
	self._last_baseline_source = "manual(fallback)"
	return manual, "manual(fallback)"
end

function AutoPIRemix:_ComputeEffectiveK(baseline)
	local manualK = tonumber(self.db.ilvl_k) or 100
	if manualK == 0 then manualK = 100 end

	if not self.db.ilvl_auto_k then
		self._last_k_used = manualK
		self._last_k_source = "manual"
		return manualK, "manual"
	end

	local b = tonumber(baseline) or 0
	local k = b * 0.8
	-- Keep K sane across scaling contexts
	if k < 60 then k = 60 end
	if k > 140 then k = 140 end
	self._last_k_used = k
	self._last_k_source = "auto(baseline*0.8 clamped 60-140)"
	return k, self._last_k_source
end

function AutoPIRemix:_IlvlToTrackLabel(ilvl)
	local x = tonumber(ilvl) or 0
	-- Lookup table based on common 12.0 conversion chart values
	local map = {
		[98]  = "Explorer 1",
		[99]  = "Explorer 2",
		[100] = "Explorer 3",
		[101] = "Explorer 4",
		[102] = "Explorer 5 / Adventure 1",
		[103] = "Explorer 6 / Adventure 2",
		[104] = "Explorer 7 / Adventure 3",
		[105] = "Explorer 8 / Adventure 4",
		[108] = "Adventure 5 / Veteran 1",
		[111] = "Adventure 6 / Veteran 2",
		[115] = "Adventure 7 / Veteran 3",
		[118] = "Adventure 8 / Veteran 4",
		[121] = "Veteran 5 / Champion 1",
		[124] = "Veteran 6 / Champion 2",
		[128] = "Veteran 7 / Champion 3",
		[131] = "Veteran 8 / Champion 4",
		[134] = "Champion 5 / Hero 1",
		[137] = "Champion 6 / Hero 2",
		[141] = "Champion 7 / Hero 3",
		[144] = "Champion 8 / Hero 4",
		[147] = "Hero 5 / Mythic 1",
		[150] = "Hero 6 / Mythic 2",
		[154] = "Hero 7 / Mythic 3",
		[157] = "Hero 8 / Mythic 4",
		[160] = "Mythic 5",
		[163] = "Mythic 6",
		[167] = "Mythic 7",
		[170] = "Mythic 8",
	}
	local bestKey, bestLabel = nil, nil
	for k, v in pairs(map) do
		if x >= k and (not bestKey or k > bestKey) then
			bestKey, bestLabel = k, v
		end
	end
	return bestLabel
end

function AutoPIRemix:_ComputeCandidateScores(list, rank, N, baseline, K, c)
	local function clamp(x, lo, hi)
		if x < lo then return lo end
		if x > hi then return hi end
		return x
	end

	local out = {}
	for _, specID in ipairs(list or {}) do
		local bucket = self.spec_cache[specID]
		if bucket and next(bucket) then
			local thisRank = rank[specID] or N
			local specScore = (N > 1) and ((N - thisRank) / (N - 1)) or 1.0

			for guid, name in pairs(bucket) do
				local entry = self.group_cache[guid]
				if entry and entry.spec and self:isDPS(entry.spec) then
					local ilvl = entry.ilvl
					local ilvlScore = 0
					local rawIlvlScore = 0
					if self.db.use_weighted_scoring and ilvl and ilvl > 0 then
						local raw = (ilvl - baseline) / K
						rawIlvlScore = raw
						ilvlScore = clamp(raw, -c, c)
					end
					local score = specScore + ilvlScore
					table.insert(out, {
						name = name,
						specID = specID,
						rank = thisRank,
						ilvl = ilvl or 0,
						specScore = specScore,
						ilvlScore = ilvlScore,
						rawIlvlScore = rawIlvlScore,
						total = score,
					})
				end
			end
		end
	end

	table.sort(out, function(a,b)
		if a.total ~= b.total then return a.total > b.total end
		if a.rank ~= b.rank then return a.rank < b.rank end
		if a.ilvl ~= b.ilvl then return a.ilvl > b.ilvl end
		return (a.name or "") < (b.name or "")
	end)

	return out
end

function AutoPIRemix:_ResetCaches()
	self.group_cache = {}   -- [guid] = { name=..., spec=..., ts=... }
	self.name_cache = {}    -- [lower(name)] = guid
	self.spec_cache = {}    -- [specID] = { [guid]=name, ... }
	self.inspectQueue = {}  -- array of {guid=..., unit=...}
	self.inspectPending = nil -- {guid=..., unit=...}
	self.inspectInProgress = false

	-- Inspect pipeline telemetry
	self.inspectStats = { requests = 0, success = 0, timeouts = 0, skips = 0 }
	self.inspectLastRequestAt = nil
	self.inspectCurrent = nil -- {guid=..., unit=..., name=...}
	self._inspectTimeoutToken = 0
end

function AutoPIRemix:_RemoveGuid(guid)
	local entry = self.group_cache[guid]
	if not entry then return end
	self.name_cache[(entry.name or ""):lower()] = nil
	if entry.spec and self.spec_cache[entry.spec] then
		self.spec_cache[entry.spec][guid] = nil
		if not next(self.spec_cache[entry.spec]) then
			self.spec_cache[entry.spec] = nil
		end
	end
	self.group_cache[guid] = nil
end

function AutoPIRemix:_UpsertGuidSpec(guid, name, specID)
	if not guid or not name or not specID or specID <= 0 then return end

	-- Remove previous spec mapping if changed
	local old = self.group_cache[guid]
	if old and old.spec and old.spec ~= specID and self.spec_cache[old.spec] then
		self.spec_cache[old.spec][guid] = nil
	end

	local prev = self.group_cache[guid]
	self.group_cache[guid] = { name = name, spec = specID, ts = time(), ilvl = prev and prev.ilvl }
	self.name_cache[name:lower()] = guid

	self.spec_cache[specID] = self.spec_cache[specID] or {}
	self.spec_cache[specID][guid] = name
end

function AutoPIRemix:_RebuildRoster()
	-- Remove anyone no longer in group
	local still = {}

	for unit in unit_iter() do
		if unit and UnitExists(unit) then
			local guid = UnitGUID(unit)
			if guid then still[guid] = unit end
		end
	end

	for guid in pairs(self.group_cache) do
		if not still[guid] then
			self:_RemoveGuid(guid)
		end
	end
end

function AutoPIRemix:_QueueInspect(guid, unit)
	-- Avoid duplicates / already have pending
	for _, item in ipairs(self.inspectQueue) do
		if item.guid == guid then return end
	end
	if self.inspectPending and self.inspectPending.guid == guid then return end
	table.insert(self.inspectQueue, { guid = guid, unit = unit })
end

function AutoPIRemix:_ScanGroupForSpecs()
	if InCombatLockdown() then return end
	if not (IsInGroup() or IsInRaid()) then return end

	self:_RebuildRoster()

	local now = time()
	for unit in unit_iter() do
		if unit and UnitExists(unit) and UnitIsConnected(unit) and not UnitIsUnit(unit, "player") then
			local guid = UnitGUID(unit)
			local name = UnitName(unit)
			if guid and name and CanInspect(unit) then
				local cached = self.group_cache[guid]
				local stale = (not cached) or (not cached.spec) or (not cached.ts) or (now - cached.ts > self.CACHE_TTL)
				if stale then
					self:_QueueInspect(guid, unit)
				end
			end
		end
	end

	self:_ProcessInspectQueue()
end

function AutoPIRemix:_ProcessInspectQueue()
	if self.inspectInProgress then return end
	if InCombatLockdown() then return end
	if not self.inspectQueue[1] then return end

	-- Pop next valid unit
	local item = table.remove(self.inspectQueue, 1)
	while item and (not item.unit or not UnitExists(item.unit) or not CanInspect(item.unit)) do
		-- Telemetry: this unit was not inspectable right now
		if self.inspectStats then self.inspectStats.skips = (self.inspectStats.skips or 0) + 1 end
		item = table.remove(self.inspectQueue, 1)
	end
	if not item then return end

	self.inspectInProgress = true
	self.inspectPending = item
	self.inspectCurrent = { guid = item.guid, unit = item.unit, name = (item.unit and UnitName(item.unit)) }

	-- NotifyInspect is throttled by Blizzard; we keep it single-flight
	if self.inspectStats then self.inspectStats.requests = (self.inspectStats.requests or 0) + 1 end
	self.inspectLastRequestAt = GetTime()
	self._inspectTimeoutToken = (self._inspectTimeoutToken or 0) + 1
	local token = self._inspectTimeoutToken

	NotifyInspect(item.unit)

	-- Timeout guard: if INSPECT_READY never fires, don't get stuck forever
	C_Timer.After(3.25, function()
		if not self.inspectPending then return end
		if token ~= self._inspectTimeoutToken then return end
		-- Still pending: count a timeout and move on
		if self.inspectStats then self.inspectStats.timeouts = (self.inspectStats.timeouts or 0) + 1 end
		ClearInspectPlayer()
		local pending = self.inspectPending
		self.inspectPending = nil
		self.inspectInProgress = false
		self.inspectCurrent = nil
		-- Requeue at end (it may become inspectable shortly)
		if pending and pending.guid and pending.unit and UnitExists(pending.unit) then
			table.insert(self.inspectQueue, pending)
		end
		C_Timer.After(0.25, function() self:_ProcessInspectQueue() end)
	end)
end

function AutoPIRemix:INSPECT_READY(event, guid)
	-- Only accept the inspect we initiated
	if not self.inspectPending or guid ~= self.inspectPending.guid then return end

	-- Telemetry: successful inspect response
	if self.inspectStats then self.inspectStats.success = (self.inspectStats.success or 0) + 1 end
	self.inspectCurrent = nil
	-- Bump token so the timeout callback won't fire for this request
	self._inspectTimeoutToken = (self._inspectTimeoutToken or 0) + 1

	local unit = self.inspectPending.unit
	local name = unit and UnitName(unit)
	local specID = (unit and UnitExists(unit)) and GetInspectSpecialization(unit) or nil
	local ilvl = (unit and UnitExists(unit) and C_PaperDollInfo and C_PaperDollInfo.GetInspectItemLevel) and C_PaperDollInfo.GetInspectItemLevel(unit) or nil

	-- Clear inspect state asap
	ClearInspectPlayer()
	self.inspectPending = nil
	self.inspectInProgress = false

	if name and specID and specID > 0 then
		self:_UpsertGuidSpec(guid, name, specID)
		if ilvl and ilvl > 0 and self.group_cache[guid] then self.group_cache[guid].ilvl = ilvl end
		self:rewriteMacro()
	end

	-- Process next, slightly delayed to respect throttle
	C_Timer.After(0.25, function() self:_ProcessInspectQueue() end)
end

function AutoPIRemix:_StartScanner()
	if self._scanner then return end
	self._scanner = C_Timer.NewTicker(self.SCAN_INTERVAL, function()
		self:_ScanGroupForSpecs()
	end)
	-- Initial scan shortly after load/roster changes
	C_Timer.After(1.0, function() self:_ScanGroupForSpecs() end)
end

function AutoPIRemix:_StopScanner()
	if self._scanner then
		self._scanner:Cancel()
		self._scanner = nil
	end
end

-- ------------------------------------------------------------

function AutoPIRemix:ADDON_LOADED(event, addOnName)
	if addOnName ~= "AutoPIRemix" then return end

	AutoPIRemixDB = AutoPIRemixDB or {}
	self.db = AutoPIRemixDB
	for k, v in pairs(self.defaults) do
		if self.db[k] == nil then
			self.db[k] = v
		end
	end

	if self.db.use_bloodmallet_spec_ids == nil then
		self.db.use_bloodmallet_spec_ids = true
	end

	self:_ResetCaches()

	local _, classid = UnitClassBase("player")
	if classid == 5 then
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		self:RegisterEvent("GROUP_ROSTER_UPDATE")
		self:RegisterEvent("INSPECT_READY")
		self:_StartScanner()
	end

	self:InitializeOptions()
	self:UnregisterEvent(event)

	C_Timer.After(2, function()
		self:rewriteMacro()
	end)
end

function AutoPIRemix:GROUP_ROSTER_UPDATE()
	-- Rebuild roster + kick a scan soon
	self:_RebuildRoster()
	C_Timer.After(0.5, function() self:_ScanGroupForSpecs() end)
end

function AutoPIRemix:PLAYER_REGEN_ENABLED()
	-- Leaving combat: refresh macro + continue inspections
	self:rewriteMacro()
	C_Timer.After(0.5, function() self:_ProcessInspectQueue() end)
end

function AutoPIRemix:rewriteMacro()
	if InCombatLockdown() then return end

	-- Prefer GetMacroIndexByName over hard-coded index ranges (future-proof)
	local found = GetMacroIndexByName("PI_WA_AUTO")
	if found == 0 then found = nil end

	local targetname = nil

	-- First check preferred players, if in DPS spec
	for name in (self.db.playerslist or ""):gmatch("[^\n]+") do
		local guid = self.name_cache[name:lower()]
		if guid and self.group_cache[guid] and self.group_cache[guid].spec and self:isDPS(self.group_cache[guid].spec) then
			targetname = self.group_cache[guid].name
			break
		end
	end

	-- If no preferred player found, select from DPS specs
	if not targetname then
		local list = self.db.use_bloodmallet_spec_ids and self.bloodmallet_spec_ids or self.db.specIDs_order
		if list then
			-- Build rank map (specID -> rank)
			local rank = {}
			for i, specID in ipairs(list) do rank[specID] = i end
			local N = #list


			local baseline, baselineSource = self:_ComputeAutoBaseline()
			local K_manual = tonumber(self.db.ilvl_k) or 100
			if K_manual == 0 then K_manual = 100 end
			local K = (self._ComputeEffectiveK and select(1, self:_ComputeEffectiveK(baseline))) or K_manual
			local c = tonumber(self.db.ilvl_clamp) or 0.10
			if c < 0 then c = -c end

			local bestScore, bestName, bestRank, bestIlvl = nil, nil, nil, nil

			local scores = self:_ComputeCandidateScores(list, rank, N, baseline, K, c)
			-- Group inspection coverage (for debug visibility)
			local dpsTotal, dpsInspected = 0, 0
			local function _CountUnit(unit)
				if not UnitExists(unit) or UnitIsUnit(unit, "player") then return end
				if UnitIsConnected(unit) == false then return end
				local guid = UnitGUID(unit)
				local entry = guid and self.group_cache and self.group_cache[guid] or nil
				local role = UnitGroupRolesAssigned(unit)
				local isDps = (role == "DAMAGER") or (entry and entry.spec and self:isDPS(entry.spec))
				if not isDps then return end
				dpsTotal = dpsTotal + 1
				if entry and entry.spec and self:isDPS(entry.spec) and entry.ilvl and entry.ilvl > 0 then
					dpsInspected = dpsInspected + 1
				end
			end
			if IsInRaid() then
				for i=1, GetNumGroupMembers() do _CountUnit("raid"..i) end
			elseif IsInGroup() then
				for i=1, GetNumSubgroupMembers() do _CountUnit("party"..i) end
			end
			local inspectedPct = (dpsTotal > 0) and (100 * dpsInspected / dpsTotal) or 0
			local candidatesInspected = 0
			if scores then
				for _, s in ipairs(scores) do if s.ilvl and s.ilvl > 0 then candidatesInspected = candidatesInspected + 1 end end
			end
			if scores and scores[1] then
				bestScore = scores[1].total
				bestName = scores[1].name
				bestRank = scores[1].rank
				bestIlvl = scores[1].ilvl
			end

			targetname = bestName

			-- Fallback to pure spec order if weighted scoring is disabled AND we didn't find anything via iteration
			if not targetname and not self.db.use_weighted_scoring then
				for _, specID in ipairs(list) do
					if self.spec_cache[specID] and next(self.spec_cache[specID]) then
						local _, name = next(self.spec_cache[specID])
						targetname = name
						break
					end
				end
			end
		end
	end

	local spellname = C_Spell.GetSpellName(10060) -- Power Infusion
	local macro = "#showtooltip"

	if self.db.spell391109 then
		macro = macro .. "\n/cast [known:391109] " .. C_Spell.GetSpellName(391109)
	end

	if self.db.spell228260 then
		macro = macro .. "\n/cast [known:228260] " .. C_Spell.GetSpellName(228260)
	end

	if targetname then
		macro = macro .. ("\n/cast [@%s,exists,help,nodead] %s; [@focus,exists,help,nodead] %s; %s"):format(targetname, spellname, spellname, spellname)
	else
		macro = macro .. ("\n/cast [@focus,exists,help,nodead] %s; %s"):format(spellname, spellname)
	end

	if self.db.trinket1 then
		macro = macro .. "\n/use 13"
	end

	if self.db.trinket2 then
		macro = macro .. "\n/use 14"
	end

	if self._current_macro == macro then return end
	self._current_macro = macro

	if found then
		EditMacro(found, "PI_WA_AUTO", "INV_MISC_QUESTIONMARK", macro)
	else
		CreateMacro("PI_WA_AUTO", "INV_MISC_QUESTIONMARK", macro, true)
	end

	
print("Updated PI macro: winner is " .. (targetname or "default/focus") .. "!")
end


function AutoPIRemix:PrintDebugScores()
	local list = self.db.use_bloodmallet_spec_ids and self.bloodmallet_spec_ids or self.db.specIDs_order
	if not list or #list == 0 then
		print("AutoPIRemix debug: no spec order list configured.")
		return
	end

	-- Build rank map
	local rank = {}
	for i, specID in ipairs(list) do rank[specID] = i end
	local N = #list

	local baseline, baselineSource = self:_ComputeAutoBaseline()
	local K_manual = tonumber(self.db.ilvl_k) or 100
	if K_manual == 0 then K_manual = 100 end
	local K, Ksource = self:_ComputeEffectiveK(baseline)
	local c = tonumber(self.db.ilvl_clamp) or 0.10
	if c < 0 then c = -c end
	-- Baseline may be nil if no inspect data has been collected yet
	if not baseline or baseline == 0 then
		baseline = tonumber(self.db.ilvl_baseline) or self._last_baseline_used or 0
		baselineSource = baselineSource or "manual/fallback"
	end

	-- Group inspection coverage (DPS only)
	local dpsTotal, dpsInspected = 0, 0
	local function _CountUnit(unit)
		if not UnitExists(unit) or UnitIsUnit(unit, "player") then return end
		if UnitIsConnected(unit) == false then return end
		local guid = UnitGUID(unit)
		local entry = guid and self.group_cache and self.group_cache[guid] or nil
		local role = UnitGroupRolesAssigned(unit)
		local isDps = (role == "DAMAGER") or (entry and entry.spec and self:isDPS(entry.spec))
		if not isDps then return end
		dpsTotal = dpsTotal + 1
		if entry and entry.spec and self:isDPS(entry.spec) and entry.ilvl and entry.ilvl > 0 then
			dpsInspected = dpsInspected + 1
		end
	end
	if IsInRaid() then
		for i=1, GetNumGroupMembers() do _CountUnit("raid"..i) end
	elseif IsInGroup() then
		for i=1, GetNumSubgroupMembers() do _CountUnit("party"..i) end
	end
	local inspectedPct = (dpsTotal > 0) and (100 * dpsInspected / dpsTotal) or 0


	local scores = self:_ComputeCandidateScores(list, rank, N, baseline, K, c)

	local candidatesInspected = 0
	if scores then
		for _, s in ipairs(scores) do
			if s.ilvl and s.ilvl > 0 then candidatesInspected = candidatesInspected + 1 end
		end
	end

	print(("AutoPIRemix debug: weighted=%s  DPS=%d inspected=%d (%.0f%%)  candidates=%d (inspected=%d)  baseline=%.1f (%s)  K=%.1f (%s)%s  clamp=%.2f")
		:format(tostring(self.db.use_weighted_scoring), dpsTotal, dpsInspected, inspectedPct, (scores and #scores or 0), candidatesInspected, baseline, baselineSource or "?", K, Ksource or "?", (self.db.ilvl_auto_k and (" [manualK="..tostring(K_manual).."]") or ""), c))

	-- Inspect pipeline telemetry
	local qlen = self.inspectQueue and #self.inspectQueue or 0
	local cur = self.inspectCurrent
	local curName = cur and cur.name or "nil"
	local curGuid = cur and cur.guid or "nil"
	local age = self.inspectLastRequestAt and (GetTime() - self.inspectLastRequestAt) or nil
	local st = self.inspectStats or {}
	print("Inspect pipeline:")
	print(("  queue=%d"):format(qlen))
	print(("  current=%s (GUID=%s)"):format(curName, curGuid))
	if age then
		print(("  lastRequest=%.1fs ago"):format(age))
	else
		print("  lastRequest=nil")
	end
	print(("  stats: requests=%d  success=%d  timeouts=%d  skips=%d")
		:format(tonumber(st.requests) or 0, tonumber(st.success) or 0, tonumber(st.timeouts) or 0, tonumber(st.skips) or 0))


		if not scores or #scores == 0 then
			print("AutoPIRemix debug: no eligible DPS candidates with known spec yet (inspect may still be warming up).")
			return
		end

		local delta
		if scores[2] then
			delta = (scores[1].total or 0) - (scores[2].total or 0)
		else
			delta = (scores[1].total or 0)
		end

		local conf = "LOW"
		if delta >= 0.08 then
			conf = "HIGH"
		elseif delta >= 0.04 then
			conf = "MED"
		end

		print(("AutoPIRemix debug: winner=%s  confidence=%s (Δ=%.3f)")
			:format(scores[1].name or "?", conf, delta))

	-- Print top 10 candidates
	local maxLines = math.min(10, #scores)
	for i = 1, maxLines do
		local s = scores[i]
		local _, specName = GetSpecializationInfoByID(s.specID)
		specName = specName or ("specID " .. tostring(s.specID))
		local track = self:_IlvlToTrackLabel(s.ilvl)
		local raw = tonumber(s.rawIlvlScore) or 0
		print(("%2d) %-16s  %-22s  ilvl=%d%s  rank=%d  spec=%.3f  ilvl=%.3f(raw=%.3f)  total=%.3f")
			:format(i, s.name or "?", specName, tonumber(s.ilvl) or 0, track and (" ["..track.."]") or "", tonumber(s.rank) or 0, tonumber(s.specScore) or 0, tonumber(s.ilvlScore) or 0, raw, tonumber(s.total) or 0))
	end
end


SLASH_AUTOPIREMIX1 = "/autopiremix"
SLASH_AUTOPIREMIX2 = "/apir"
SLASH_AUTOPIREMIX3 = "/autopi" -- legacy alias (pre-rename)
SlashCmdList.AUTOPIREMIX = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$","")
	if msg == "debug" then
		AutoPIRemix:PrintDebugScores()
		return
	end
	-- default: open settings
	if AutoPIRemix.settingsCategoryID then
		Settings.OpenToCategory(AutoPIRemix.settingsCategoryID)
	elseif AutoPIRemix.panel_main and AutoPIRemix.panel_main.name then
		Settings.OpenToCategory(AutoPIRemix.panel_main.name)
	end
end