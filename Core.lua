AutoPIRemix = CreateFrame("Frame")

function AutoPIRemix:OnEvent(event, ...)
	self[event](self, event, ...)
end
AutoPIRemix:SetScript("OnEvent", AutoPIRemix.OnEvent)
AutoPIRemix:RegisterEvent("ADDON_LOADED")

-- Bloodmallet "Power Infusion" rankings, ordered by absolute DPS gained from PI
-- (the website chart's default "absolute" sort = bloodmallet sorted_data_keys_2),
-- which prioritizes raw raid DPS added and naturally sinks low-DPS tank specs.
-- Specs with no PI sim data (Augmentation, healers) are parked at the end;
-- healers are never selected anyway (isDPS filters to role == DAMAGER).
-- The active list is chosen by content type (see _ActiveBloodmalletList).
--
-- SINGLE TARGET (raids): "Castingpatchwerk", sim'd 2026-06-17 (SimC 9f3b11b).
AutoPIRemix.bloodmallet_spec_ids = {
	63,   -- Fire Mage
	254,  -- Marksmanship Hunter
	269,  -- Windwalker Monk
	253,  -- Beast Mastery Hunter
	262,  -- Elemental Shaman
	102,  -- Balance Druid
	266,  -- Demonology Warlock
	255,  -- Survival Hunter
	263,  -- Enhancement Shaman
	103,  -- Feral Druid
	70,   -- Retribution Paladin
	265,  -- Affliction Warlock
	104,  -- Guardian Druid
	62,   -- Arcane Mage
	258,  -- Shadow Priest
	71,   -- Arms Warrior
	259,  -- Assassination Rogue
	252,  -- Unholy Death Knight
	251,  -- Frost Death Knight
	1480, -- Devourer Demon Hunter
	64,   -- Frost Mage
	577,  -- Havoc Demon Hunter
	72,   -- Fury Warrior
	66,   -- Protection Paladin
	1467, -- Devastation Evoker
	267,  -- Destruction Warlock
	260,  -- Outlaw Rogue
	73,   -- Protection Warrior
	581,  -- Vengeance Demon Hunter
	250,  -- Blood Death Knight
	261,  -- Subtlety Rogue
	268,  -- Brewmaster Monk
	-- No bloodmallet PI data below this point:
	1473, -- Augmentation Evoker (support spec; not in PI sims)
	105,  -- Restoration Druid
	270,  -- Mistweaver Monk
	65,   -- Holy Paladin
	256,  -- Discipline Priest
	257,  -- Holy Priest
	264,  -- Restoration Shaman
	1468, -- Preservation Evoker
}

-- MULTITARGET (M+, dungeons, everything non-raid): "Castingpatchwerk5"
-- (5-target), sim'd 2026-06-17 (SimC 9f3b11b). Same parked tail.
AutoPIRemix.bloodmallet_spec_ids_multitarget = {
	266,  -- Demonology Warlock
	269,  -- Windwalker Monk
	63,   -- Fire Mage
	262,  -- Elemental Shaman
	263,  -- Enhancement Shaman
	1467, -- Devastation Evoker
	255,  -- Survival Hunter
	62,   -- Arcane Mage
	258,  -- Shadow Priest
	102,  -- Balance Druid
	254,  -- Marksmanship Hunter
	70,   -- Retribution Paladin
	265,  -- Affliction Warlock
	1480, -- Devourer Demon Hunter
	103,  -- Feral Druid
	577,  -- Havoc Demon Hunter
	104,  -- Guardian Druid
	251,  -- Frost Death Knight
	252,  -- Unholy Death Knight
	261,  -- Subtlety Rogue
	581,  -- Vengeance Demon Hunter
	250,  -- Blood Death Knight
	64,   -- Frost Mage
	66,   -- Protection Paladin
	73,   -- Protection Warrior
	253,  -- Beast Mastery Hunter
	260,  -- Outlaw Rogue
	72,   -- Fury Warrior
	267,  -- Destruction Warlock
	71,   -- Arms Warrior
	259,  -- Assassination Rogue
	268,  -- Brewmaster Monk
	-- No bloodmallet PI data below this point:
	1473, -- Augmentation Evoker (support spec; not in PI sims)
	105,  -- Restoration Druid
	270,  -- Mistweaver Monk
	65,   -- Holy Paladin
	256,  -- Discipline Priest
	257,  -- Holy Priest
	264,  -- Restoration Shaman
	1468, -- Preservation Evoker
}

-- Pick the bloodmallet ranking that matches current content:
-- single-target in a raid instance, multitarget (AoE) everywhere else
-- (M+, dungeons, scenarios, open world).
function AutoPIRemix:_ActiveBloodmalletList()
	local _, instanceType = IsInInstance()
	if instanceType == "raid" then
		return self.bloodmallet_spec_ids, "single-target (raid)"
	end
	return self.bloodmallet_spec_ids_multitarget, "multitarget (M+/other)"
end

-- ------------------------------------------------------------
-- Lightweight group spec tracking (no LibGroupInSpecT required)
-- Uses Inspect APIs with throttling + caching.
-- ------------------------------------------------------------

-- How often to rescan group for missing/stale spec info (seconds)
AutoPIRemix.SCAN_INTERVAL = 4
-- How long we trust a cached spec before refreshing (seconds)
AutoPIRemix.CACHE_TTL = 60

-- Auto-K scaling: K = baseline * K_MULTIPLIER, clamped to [K_MIN, K_MAX].
-- Shared so the options label can be generated from these (never drifts).
AutoPIRemix.K_MULTIPLIER = 0.8
AutoPIRemix.K_MIN = 60
AutoPIRemix.K_MAX = 240

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
	local k = b * self.K_MULTIPLIER
	-- Keep K sane across scaling contexts
	if k < self.K_MIN then k = self.K_MIN end
	if k > self.K_MAX then k = self.K_MAX end
	self._last_k_used = k
	self._last_k_source = ("auto(baseline*%g clamped %d-%d)"):format(self.K_MULTIPLIER, self.K_MIN, self.K_MAX)
	return k, self._last_k_source
end

function AutoPIRemix:_IlvlToTrackLabel(ilvl)
	local x = tonumber(ilvl) or 0
	-- Midnight Season 1 (12.0.5) gear upgrade tracks. Each track has 6 ranks;
	-- adjacent tracks overlap at shared item levels (shown as "A / B").
	local map = {
		[220] = "Adventurer 1",
		[224] = "Adventurer 2",
		[227] = "Adventurer 3",
		[230] = "Adventurer 4",
		[233] = "Adventurer 5 / Veteran 1",
		[237] = "Adventurer 6 / Veteran 2",
		[240] = "Veteran 3",
		[243] = "Veteran 4",
		[246] = "Veteran 5 / Champion 1",
		[250] = "Veteran 6 / Champion 2",
		[253] = "Champion 3",
		[256] = "Champion 4",
		[259] = "Champion 5 / Hero 1",
		[263] = "Champion 6 / Hero 2",
		[266] = "Hero 3",
		[269] = "Hero 4",
		[272] = "Hero 5 / Myth 1",
		[276] = "Hero 6 / Myth 2",
		[279] = "Myth 3",
		[282] = "Myth 4",
		[285] = "Myth 5",
		[289] = "Myth 6",
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
	self._lastAnnouncedTarget = nil
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

	-- Once the queue drains, announce the winner if it changed
	self:_MaybeAnnounceWinner()
end

function AutoPIRemix:_AnnounceWinner()
	local target = self._piTarget
	if not target or target == "" then return end
	if not (IsInGroup() or IsInRaid()) then return end

	local channel
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		channel = "INSTANCE_CHAT"
	elseif IsInRaid() then
		channel = "RAID"
	else
		channel = "PARTY"
	end

	local conf = self._piConfidence or ""
	local suffix = (conf == "preferred") and " (preferred)"
	                or (conf ~= "" and (" (" .. conf .. ")"))
	                or ""
	SendChatMessage("PI target: " .. target .. suffix, channel)
end

-- Force an announcement of the current target (manual HUD button). Syncs the
-- last-announced target so the auto logic won't immediately repeat it.
function AutoPIRemix:_ForceAnnounceWinner()
	local t = self._piTarget
	self._lastAnnouncedTarget = (t and t ~= "") and t or nil
	self:_AnnounceWinner()
end

-- Announce the winner only when scanning has settled and the target actually
-- changed since the last announcement (so joins/leaves re-announce, but a
-- steady target doesn't spam group chat).
function AutoPIRemix:_MaybeAnnounceWinner()
	if self.inspectInProgress or self.inspectQueue[1] then return end -- still scanning

	local target = self._piTarget
	local current = (target and target ~= "") and target or nil
	if current == self._lastAnnouncedTarget then return end

	self._lastAnnouncedTarget = current
	if current then
		self:_AnnounceWinner()
	end
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
	self:UnregisterEvent(event)

	-- Priests only: stay completely inert for every other class (no DB, no
	-- options panel, no frames, no scanner, no macro updates). classID 5 = Priest.
	local _, classid = UnitClassBase("player")
	if classid ~= 5 then return end

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

	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
	self:RegisterEvent("INSPECT_READY")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:_StartScanner()

	self:InitializeOptions()

	C_Timer.After(2, function()
		self:rewriteMacro()
	end)
end

function AutoPIRemix:GROUP_ROSTER_UPDATE()
	-- Rebuild roster + kick a scan soon. After it settles, recompute the winner
	-- and re-announce if it changed (covers leavers that need no new inspect).
	self:_RebuildRoster()
	C_Timer.After(0.5, function()
		self:_ScanGroupForSpecs()
		self:rewriteMacro()
		self:_MaybeAnnounceWinner()
	end)
end

function AutoPIRemix:PLAYER_ENTERING_WORLD()
	-- Instance/zone changed: the active ranking (raid vs M+) may differ, so
	-- refresh the macro and rescan the group shortly after the world loads.
	-- Clear the last-announced target so a fresh instance re-announces.
	self._lastAnnouncedTarget = nil
	C_Timer.After(1.0, function()
		self:rewriteMacro()
		self:_ScanGroupForSpecs()
	end)
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
	self._piConfidence = nil
	self._piDelta = nil

	-- First check preferred players (manual named-character list), if in DPS spec
	local hasNamedList = ((self.db.playerslist or ""):match("%S")) ~= nil
	for name in (self.db.playerslist or ""):gmatch("[^\n]+") do
		local guid = self.name_cache[name:lower()]
		if guid and self.group_cache[guid] and self.group_cache[guid].spec and self:isDPS(self.group_cache[guid].spec) then
			targetname = self.group_cache[guid].name
			self._piConfidence = "preferred"
			break
		end
	end

	-- If no preferred player found, select from DPS specs
	if not targetname then
		-- Score the group against a single spec-priority list and return the
		-- winning player name (or nil if no group DPS matches any spec in it).
		-- Sets self._piDelta / self._piConfidence as a side effect.
		local function selectFromList(list)
			if not list then return nil end
			-- Build rank map (specID -> rank)
			local rank = {}
			for i, specID in ipairs(list) do rank[specID] = i end
			local N = #list

			local baseline = self:_ComputeAutoBaseline()
			local K_manual = tonumber(self.db.ilvl_k) or 100
			if K_manual == 0 then K_manual = 100 end
			local K = (self._ComputeEffectiveK and select(1, self:_ComputeEffectiveK(baseline))) or K_manual
			local c = tonumber(self.db.ilvl_clamp) or 0.10
			if c < 0 then c = -c end

			local scores = self:_ComputeCandidateScores(list, rank, N, baseline, K, c)
			if scores and scores[1] then
				local delta = scores[2] and ((scores[1].total or 0) - (scores[2].total or 0)) or (scores[1].total or 0)
				self._piDelta = delta
				self._piConfidence = (delta >= 0.08 and "HIGH") or (delta >= 0.04 and "MED") or "LOW"
				return scores[1].name
			end

			-- Fallback to pure spec order if weighted scoring is disabled AND we didn't find anything via iteration
			if not self.db.use_weighted_scoring then
				for _, specID in ipairs(list) do
					if self.spec_cache[specID] and next(self.spec_cache[specID]) then
						local _, name = next(self.spec_cache[specID])
						return name
					end
				end
			end
			return nil
		end

		-- A configured named-character list with nobody present falls back to the
		-- auto Bloodmallet list, regardless of the spec-order mode setting.
		if hasNamedList then
			targetname = selectFromList(self:_ActiveBloodmalletList())
			if targetname then self._piConfidence = "auto-fallback" end
		elseif self.db.use_bloodmallet_spec_ids then
			targetname = selectFromList(self:_ActiveBloodmalletList())
		else
			targetname = selectFromList(self.db.specIDs_order)
		end
	end

	-- Refresh the on-screen target box (runs every out-of-combat update)
	self._piTarget = targetname
	self:_UpdateTargetFrame()

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

	print("AutoPIRemix: updated PI macro — winner is " .. (targetname or "default/focus"))
end


-- Build the debug report as an array of text lines (shared by the chat dump
-- and the live debug window).
function AutoPIRemix:_BuildDebugLines()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end

	-- Mirror rewriteMacro: a configured named-character list forces the auto list.
	local hasNamedList = ((self.db.playerslist or ""):match("%S")) ~= nil
	local list, listLabel
	if hasNamedList then
		list, listLabel = self:_ActiveBloodmalletList()
		listLabel = (listLabel or "auto") .. " (named-list fallback)"
	elseif self.db.use_bloodmallet_spec_ids then
		list, listLabel = self:_ActiveBloodmalletList()
	else
		list, listLabel = self.db.specIDs_order, "manual order"
	end
	if not list or #list == 0 then
		add("no spec order list configured.")
		return lines
	end
	add("spec list = " .. (listLabel or "?"))

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

	add(("weighted=%s  DPS=%d inspected=%d (%.0f%%)  candidates=%d (inspected=%d)  baseline=%.1f (%s)  K=%.1f (%s)%s  clamp=%.2f")
		:format(tostring(self.db.use_weighted_scoring), dpsTotal, dpsInspected, inspectedPct, (scores and #scores or 0), candidatesInspected, baseline, baselineSource or "?", K, Ksource or "?", (self.db.ilvl_auto_k and (" [manualK="..tostring(K_manual).."]") or ""), c))

	-- Inspect pipeline telemetry
	local qlen = self.inspectQueue and #self.inspectQueue or 0
	local cur = self.inspectCurrent
	local curName = cur and cur.name or "nil"
	local curGuid = cur and cur.guid or "nil"
	local age = self.inspectLastRequestAt and (GetTime() - self.inspectLastRequestAt) or nil
	local st = self.inspectStats or {}
	add("Inspect pipeline:")
	add(("  queue=%d"):format(qlen))
	add(("  current=%s (GUID=%s)"):format(curName, curGuid))
	if age then
		add(("  lastRequest=%.1fs ago"):format(age))
	else
		add("  lastRequest=nil")
	end
	add(("  stats: requests=%d  success=%d  timeouts=%d  skips=%d")
		:format(tonumber(st.requests) or 0, tonumber(st.success) or 0, tonumber(st.timeouts) or 0, tonumber(st.skips) or 0))

	if not scores or #scores == 0 then
		add("no eligible DPS candidates with known spec yet (inspect may still be warming up).")
		return lines
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

	add(("winner=%s  confidence=%s (Δ=%.3f)"):format(scores[1].name or "?", conf, delta))

	-- Top 10 candidates
	local maxLines = math.min(10, #scores)
	for i = 1, maxLines do
		local s = scores[i]
		local _, specName = GetSpecializationInfoByID(s.specID)
		specName = specName or ("specID " .. tostring(s.specID))
		local track = self:_IlvlToTrackLabel(s.ilvl)
		local raw = tonumber(s.rawIlvlScore) or 0
		add(("%2d) %-16s  %-22s  ilvl=%d%s  rank=%d  spec=%.3f  ilvl=%.3f(raw=%.3f)  total=%.3f")
			:format(i, s.name or "?", specName, tonumber(s.ilvl) or 0, track and (" ["..track.."]") or "", tonumber(s.rank) or 0, tonumber(s.specScore) or 0, tonumber(s.ilvlScore) or 0, raw, tonumber(s.total) or 0))
	end

	return lines
end

-- One-shot dump to the chat frame.
function AutoPIRemix:PrintDebugScores()
	for _, line in ipairs(self:_BuildDebugLines()) do
		print("AutoPIRemix debug: " .. line)
	end
end

-- ------------------------------------------------------------
-- Live debug window (refreshes in place, no chat scroll)
-- ------------------------------------------------------------

function AutoPIRemix:_RefreshDebugWindow()
	local f = self.debugWindow
	if not f or not f:IsShown() then return end
	-- Guard so a transient error never blanks the window or kills the ticker.
	local ok, text = pcall(function() return table.concat(self:_BuildDebugLines(), "\n") end)
	if ok then
		f.body:SetText(text)
	else
		f.body:SetText("|cffff5555error building debug report:|r\n" .. tostring(text))
	end
end

function AutoPIRemix:_StopDebugTicker()
	if self._debugTicker then
		self._debugTicker:Cancel()
		self._debugTicker = nil
	end
end

function AutoPIRemix:_EnsureDebugWindow()
	if self.debugWindow then return self.debugWindow end

	local f = CreateFrame("Frame", "AutoPIRemixDebugWindow", UIParent, "BackdropTemplate")
	f:SetSize(820, 380)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	f:SetBackdropColor(0, 0, 0, 0.9)

	-- Draggable by the whole frame
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("AutoPI Remix — Debug (live)")

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	body:SetPoint("TOPLEFT", 16, -34)
	body:SetPoint("BOTTOMRIGHT", -16, 14)
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")
	-- Leave word wrap at its default (on); explicit "\n" line breaks then render
	-- as separate lines. (SetWordWrap(false) collapses the text to one line.)
	f.body = body

	-- ESC closes; stop the refresh ticker whenever hidden
	tinsert(UISpecialFrames, "AutoPIRemixDebugWindow")
	f:SetScript("OnHide", function() AutoPIRemix:_StopDebugTicker() end)

	f:Hide()  -- start hidden so first ToggleDebugWindow shows rather than hides
	self.debugWindow = f
	return f
end

function AutoPIRemix:ToggleDebugWindow()
	local f = self:_EnsureDebugWindow()
	if f:IsShown() then
		f:Hide()
		return
	end
	f:Show()
	self:_RefreshDebugWindow()
	self:_StopDebugTicker()
	self._debugTicker = C_Timer.NewTicker(0.5, function() self:_RefreshDebugWindow() end)
end

-- ------------------------------------------------------------
-- On-screen PI target box (draggable HUD: icon + target + confidence)
-- ------------------------------------------------------------

function AutoPIRemix:_EnsureTargetFrame()
	if self.targetFrame then return self.targetFrame end

	local f = CreateFrame("Frame", "AutoPIRemixTargetFrame", UIParent, "BackdropTemplate")
	f:SetSize(230, 68)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	f:SetBackdropColor(0, 0, 0, 0.6)

	-- Position: restore saved spot or default near top-center
	local pos = self.db and self.db.target_frame_pos
	if pos and pos.point then
		f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
	else
		f:SetPoint("TOP", UIParent, "TOP", 0, -200)
	end

	-- Draggable; persist position on release
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		AutoPIRemix.db.target_frame_pos = { point = point, relPoint = relPoint, x = x, y = y }
	end)

	-- Icon is a secure button so clicking it targets the PI target (works in combat)
	local iconBtn = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
	iconBtn:SetSize(36, 36)
	iconBtn:SetPoint("LEFT", 8, 0)
	iconBtn:SetAttribute("type", "target")
	iconBtn:SetAttribute("unit", "")
	local icon = iconBtn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(C_Spell.GetSpellTexture(10060))
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	iconBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	iconBtn:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
		local t = AutoPIRemix._piTarget
		GameTooltip:SetText(t and ("Target: " .. t) or "No PI target")
		GameTooltip:Show()
	end)
	iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.icon = icon
	f.iconBtn = iconBtn

	local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	name:SetPoint("LEFT", iconBtn, "RIGHT", 8, 8)
	name:SetJustifyH("LEFT")
	f.name = name

	local conf = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	conf:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
	conf:SetJustifyH("LEFT")
	f.conf = conf

	local scan = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	scan:SetPoint("TOPLEFT", conf, "BOTTOMLEFT", 0, -2)
	scan:SetJustifyH("LEFT")
	f.scan = scan

	-- Small debug button in the upper-right corner
	local dbgBtn = CreateFrame("Button", nil, f)
	dbgBtn:SetSize(20, 14)
	dbgBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
	local dbgBg = dbgBtn:CreateTexture(nil, "BACKGROUND")
	dbgBg:SetAllPoints()
	dbgBg:SetColorTexture(0.15, 0.15, 0.4, 0.8)
	local dbgLabel = dbgBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dbgLabel:SetAllPoints()
	dbgLabel:SetText("D")
	dbgBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	dbgBtn:SetScript("OnClick", function() AutoPIRemix:ToggleDebugWindow() end)
	dbgBtn:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Toggle debug window")
		GameTooltip:Show()
	end)
	dbgBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.dbgBtn = dbgBtn

	-- Announce button, just left of the debug button: re-sends the current target
	local annBtn = CreateFrame("Button", nil, f)
	annBtn:SetSize(20, 14)
	annBtn:SetPoint("TOPRIGHT", dbgBtn, "TOPLEFT", -4, 0)
	local annBg = annBtn:CreateTexture(nil, "BACKGROUND")
	annBg:SetAllPoints()
	annBg:SetColorTexture(0.15, 0.4, 0.15, 0.8)
	local annLabel = annBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	annLabel:SetAllPoints()
	annLabel:SetText("A")
	annBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	annBtn:SetScript("OnClick", function() AutoPIRemix:_ForceAnnounceWinner() end)
	annBtn:SetScript("OnEnter", function(btn)
		GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Announce PI target to group")
		GameTooltip:Show()
	end)
	annBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	f.annBtn = annBtn

	self.targetFrame = f
	return f
end

function AutoPIRemix:_UpdateTargetFrame()
	if not self.db then return end
	if not self.db.show_target_frame then
		if self.targetFrame then self.targetFrame:Hide() end
		return
	end

	local f = self:_EnsureTargetFrame()
	f:Show()

	local target = self._piTarget
	if target and target ~= "" then
		f.name:SetText(target)
	else
		f.name:SetText("|cff888888(focus / default)|r")
	end

	-- Keep the icon button's target in sync (SecureActionButtonTemplate handles the actual targeting)
	if f.iconBtn and not InCombatLockdown() then
		f.iconBtn:SetAttribute("unit", target or "")
	end

	local conf = self._piConfidence
	if conf == "preferred" then
		f.conf:SetText("|cff66ccffpreferred player|r")
	elseif conf then
		local color = (conf == "HIGH" and "ff44ff44") or (conf == "MED" and "ffffcc33") or "ffff6644"
		local delta = self._piDelta and ("  (Δ%.3f)"):format(self._piDelta) or ""
		f.conf:SetText(("confidence: |c%s%s|r%s"):format(color, conf, delta))
	else
		f.conf:SetText("")
	end

	-- Scan progress: how many group members have been successfully inspected
	if f.scan then
		local total, scanned = 0, 0
		for unit in unit_iter() do
			if unit and UnitExists(unit) and not UnitIsUnit(unit, "player") and UnitIsConnected(unit) then
				total = total + 1
				local guid = UnitGUID(unit)
				local entry = guid and self.group_cache and self.group_cache[guid]
				if entry and entry.spec and entry.spec > 0 then
					scanned = scanned + 1
				end
			end
		end
		if total > 0 then
			f.scan:SetText("|cff888888scan " .. scanned .. "/" .. total .. "|r")
		else
			f.scan:SetText("")
		end
	end
end

function AutoPIRemix:ToggleTargetFrame()
	self.db.show_target_frame = not self.db.show_target_frame
	self:_UpdateTargetFrame()
	print("AutoPIRemix: PI target box " .. (self.db.show_target_frame and "shown" or "hidden"))
end


SLASH_AUTOPIREMIX1 = "/autopiremix"
SLASH_AUTOPIREMIX2 = "/apir"
SLASH_AUTOPIREMIX3 = "/autopi" -- legacy alias (pre-rename)
SlashCmdList.AUTOPIREMIX = function(msg)
	if not AutoPIRemix.db then return end -- inactive (non-priest)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$","")
	if msg == "debug print" or msg == "debug chat" then
		AutoPIRemix:PrintDebugScores()
		return
	end
	if msg == "debug" then
		AutoPIRemix:ToggleDebugWindow()
		return
	end
	if msg == "hud" or msg == "box" then
		AutoPIRemix:ToggleTargetFrame()
		return
	end
	-- default: open settings
	if AutoPIRemix.settingsCategoryID then
		Settings.OpenToCategory(AutoPIRemix.settingsCategoryID)
	elseif AutoPIRemix.panel_main and AutoPIRemix.panel_main.name then
		Settings.OpenToCategory(AutoPIRemix.panel_main.name)
	end
end