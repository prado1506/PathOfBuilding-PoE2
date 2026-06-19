-- Path of Building
--
-- Module: Advisor
-- Pure, deterministic build-advisor logic. No UI references — unit-testable headlessly.
-- Reads the already-calculated build (build.calcsTab.mainOutput) and returns findings.
--
-- cspell:ignore maxhit deadend headlessly
--
-- Severity guide:
--   high = likely loss or disabled (uncapped elemental resistance)
--   med  = meaningful weakness (under-cap chaos, low EHP, no mitigation/recovery layer)
--   low  = minor improvement
--   info = informational (wasted resistance surplus, weakest max-hit type)
--
local t_insert = table.insert
local t_remove = table.remove
local t_sort = table.sort
local s_format = string.format
local m_max = math.max

local Advisor = { }

Advisor.severityRank = { high = 3, med = 2, low = 1, info = 0 }

-- Each check is function(build, out, findings) and appends 0..n findings.
-- A finding is { id, severity, category, title, detail, fix, jump }.
Advisor.checks = { }

-- Tunable heuristics (each documented inline).
local RESIST_SURPLUS_INFO = 10    -- >10% resistance over the cap is meaningful wasted gear budget
local EHP_FLOOR_BASE = 1500       -- heuristic effective-HP floor at level 1...
local EHP_FLOOR_PER_LEVEL = 150   -- ...growing per character level; below this a build is usually too squishy
local RECOVERY_EPSILON = 0.5      -- per-second recovery at/below this counts as "no sustain"
local PHYS_DR_MIN = 10            -- % physical damage reduction that counts as an armour layer
local EVADE_MIN = 20              -- % evade that counts as an evasion layer
local BLOCK_MIN = 10              -- % block that counts as a block layer
local SUPPRESS_MIN = 30           -- % spell suppression that counts as a suppression layer

local ELEM_RESISTS = {
	{ key = "Fire", label = "Fire", severity = "high" },
	{ key = "Cold", label = "Cold", severity = "high" },
	{ key = "Lightning", label = "Lightning", severity = "high" },
}

local ALL_RESISTS = {
	{ key = "Fire", label = "Fire", severity = "high" },
	{ key = "Cold", label = "Cold", severity = "high" },
	{ key = "Lightning", label = "Lightning", severity = "high" },
	{ key = "Chaos", label = "Chaos", severity = "med" },
}

local MAX_HIT_TYPES = {
	{ key = "Physical", label = "Physical" },
	{ key = "Fire", label = "Fire" },
	{ key = "Cold", label = "Cold" },
	{ key = "Lightning", label = "Lightning" },
	{ key = "Chaos", label = "Chaos" },
}

-- Check 1: resistances below cap.
t_insert(Advisor.checks, function(build, out, findings)
	for _, res in ipairs(ALL_RESISTS) do
		if not (res.key == "Chaos" and out.ChaosInoculation) then
			local value = out[res.key .. "Resist"]
			local overCap = out[res.key .. "ResistOverCap"]
			if value and overCap and overCap < 0 then
				local deficit = -overCap
				t_insert(findings, {
					id = "res." .. res.key:lower() .. ".uncapped",
					severity = res.severity,
					category = "Survivability",
					title = res.label .. " Resistance is below cap",
					detail = s_format("%s Res %d%% (-%d%% under the cap).", res.label, value, deficit),
					fix = s_format("Add ~%d%% %s Resistance on gear, runes, or the tree.", deficit, res.label),
					jump = { mode = "ITEMS" },
				})
			end
		end
	end
end)

-- Check 2: wasted elemental resistance over the cap (informational).
t_insert(Advisor.checks, function(build, out, findings)
	for _, res in ipairs(ELEM_RESISTS) do
		local overCap = out[res.key .. "ResistOverCap"]
		if overCap and overCap > RESIST_SURPLUS_INFO then
			t_insert(findings, {
				id = "res." .. res.key:lower() .. ".surplus",
				severity = "info",
				category = "Survivability",
				title = res.label .. " Resistance is over the cap",
				detail = s_format("%s Res is %d%% over the cap (wasted).", res.label, overCap),
				fix = s_format("You could move ~%d%% %s Resistance to another stat.", overCap, res.label),
			})
		end
	end
end)

-- Check 3: effective HP pool too low for the character level.
t_insert(Advisor.checks, function(build, out, findings)
	local ehp = out.TotalEHP
	if not ehp then
		ehp = (out.Life or 0) + (out.EnergyShield or 0)
	end
	if ehp and ehp > 0 then
		local level = (build and build.characterLevel) or 1
		local floor = EHP_FLOOR_BASE + EHP_FLOOR_PER_LEVEL * level
		if ehp < floor then
			t_insert(findings, {
				id = "ehp.low",
				severity = "med",
				category = "Survivability",
				title = "Effective HP looks low for your level",
				detail = s_format("Effective Hit Pool %d at level %d (heuristic floor ~%d).", ehp, level, floor),
				fix = "Add Life, Energy Shield, or mitigation to raise your effective HP.",
			})
		end
	end
end)

-- Check 4: no meaningful life/ES recovery layer.
t_insert(Advisor.checks, function(build, out, findings)
	local lifeRegen = out.LifeRegenRecovery or 0
	local esRegen = out.EnergyShieldRegenRecovery or 0
	local lifeLeech = out.LifeLeechGainRate or 0
	local esLeech = out.EnergyShieldLeechGainRate or 0
	if lifeRegen <= RECOVERY_EPSILON and esRegen <= RECOVERY_EPSILON
		and lifeLeech <= RECOVERY_EPSILON and esLeech <= RECOVERY_EPSILON then
		t_insert(findings, {
			id = "recovery.none",
			severity = "med",
			category = "Survivability",
			title = "No meaningful Life or ES recovery",
			detail = "No notable life/ES regeneration or leech was found.",
			fix = "Add life/ES regeneration, leech, or recoup so you recover between hits.",
		})
	end
end)

-- Check 5: no meaningful mitigation layer present.
t_insert(Advisor.checks, function(build, out, findings)
	local physDR = out.PhysicalDamageReduction or 0
	local evade = m_max(
		out.EvadeChance or 0,
		out.MeleeEvadeChance or 0,
		out.ProjectileEvadeChance or 0,
		out.SpellEvadeChance or 0,
		out.SpellProjectileEvadeChance or 0
	)
	local block = m_max(
		out.EffectiveBlockChance or 0,
		out.EffectiveProjectileBlockChance or 0,
		out.EffectiveSpellBlockChance or 0,
		out.EffectiveSpellProjectileBlockChance or 0
	)
	local suppress = out.EffectiveSpellSuppressionChance or 0
	local hasLayer = physDR >= PHYS_DR_MIN or evade >= EVADE_MIN or block >= BLOCK_MIN or suppress >= SUPPRESS_MIN
	if not hasLayer then
		t_insert(findings, {
			id = "mitigation.none",
			severity = "med",
			category = "Survivability",
			title = "No meaningful mitigation layer",
			detail = s_format("Phys DR %d%%, Evade %d%%, Block %d%%, Suppression %d%% - all below useful levels.", physDR, evade, block, suppress),
			fix = "Add armour, evasion, block, or spell suppression to reduce incoming damage.",
		})
	end
end)

-- Check 6: surface the weakest damage type by maximum hit taken (informational).
t_insert(Advisor.checks, function(build, out, findings)
	local weakestType, weakestValue
	for _, hit in ipairs(MAX_HIT_TYPES) do
		local v = out[hit.key .. "MaximumHitTaken"]
		if v and v > 0 and (not weakestValue or v < weakestValue) then
			weakestValue = v
			weakestType = hit.label
		end
	end
	if weakestType then
		t_insert(findings, {
			id = "maxhit.weakest",
			severity = "info",
			category = "Survivability",
			title = "Weakest defence is vs " .. weakestType,
			detail = s_format("Largest survivable %s hit is %d (your lowest max hit).", weakestType, weakestValue),
			fix = s_format("Shore up %s mitigation if you die to %s spikes.", weakestType, weakestType),
		})
	end
end)

-- ===== Issue #81: skill / support / attribute / spirit checks =====

local LARGE_UNUSED_SPIRIT = 30   -- unreserved Spirit above this is likely a wasted reservation slot

local function gemDisplayName(gem)
	local ge = gem.gemData and gem.gemData.grantedEffect
	return (gem.gemData and gem.gemData.name) or (ge and ge.name) or "a gem"
end

-- Returns the active (non-support) granted effects/gems for a socket group.
local function groupActiveEffects(group)
	local list = { }
	for _, gem in ipairs(group.gemList or { }) do
		local ge = gem.gemData and gem.gemData.grantedEffect
		if ge and not ge.support and gem.enabled ~= false then
			t_insert(list, { ge = ge, gem = gem })
		end
	end
	return list
end

-- Returns the first active (non-support) granted effect and gem for a socket group, or nil.
local function groupActiveEffect(group)
	for _, gem in ipairs(group.gemList or { }) do
		local ge = gem.gemData and gem.gemData.grantedEffect
		if ge and not ge.support and gem.enabled ~= false then
			return ge, gem
		end
	end
	return nil
end

-- Test whether a support's skill-type requirements/exclusions match an active skill.
-- `types` is the active skill's effective type set (including addSkillTypes from accepted supports).
local function supportAppliesToActive(supportGE, activeGE, types)
	local req = supportGE.requireSkillTypes
	local exc = supportGE.excludeSkillTypes
	local ignoreMinion = supportGE.ignoreMinionTypes
	local minionTypes = (not ignoreMinion) and activeGE.minionSkillTypes or nil
	if req and req[1] and not calcLib.doesTypeExpressionMatch(req, types, minionTypes) then
		return false
	end
	if exc and exc[1] then
		if ignoreMinion or not activeGE.minionSkillTypes then
			if calcLib.doesTypeExpressionMatch(exc, types) then return false end
		else
			-- Supports that target minions exclude based on the minion's types, not the active's.
			if calcLib.doesTypeExpressionMatch(exc, activeGE.minionSkillTypes) then return false end
		end
	end
	return true
end

-- Check: support gems that cannot apply to any active skill in their group (wasted sockets).
t_insert(Advisor.checks, function(build, out, findings)
	local skillsTab = build and build.skillsTab
	if not (skillsTab and skillsTab.socketGroupList) then return end
	if not calcLib then
		ConPrintf("Advisor: calcLib unavailable, skipping support-applicability check")
		return
	end
	for _, group in ipairs(skillsTab.socketGroupList) do
		if group.enabled ~= false then
			local activeList = groupActiveEffects(group)
			-- Active gems that cannot be supported can never make a support valid.
			for i = #activeList, 1, -1 do
				if activeList[i].ge.cannotBeSupported then
					t_remove(activeList, i)
				end
			end
			if #activeList > 0 then
				for _, active in ipairs(activeList) do
					active.types = { }
					for k, v in pairs(active.ge.skillTypes) do active.types[k] = v end
				end
				local supportList = { }
				for _, gem in ipairs(group.gemList or { }) do
					local ge = gem.gemData and gem.gemData.grantedEffect
					if ge and ge.support and gem.enabled ~= false then
						t_insert(supportList, { gem = gem, ge = ge })
					end
				end
				-- Iteratively accept supports whose tags match the current effective type set,
				-- adding their addSkillTypes each time, mirroring CalcActiveSkill.
				local changed = true
				while changed do
					changed = false
					for _, sup in ipairs(supportList) do
						if not sup.accepted then
							local appliedAny = false
							for _, active in ipairs(activeList) do
								if supportAppliesToActive(sup.ge, active.ge, active.types) then
									appliedAny = true
									local add = sup.ge.addSkillTypes
									if add then
										for _, st in ipairs(add) do
											if not active.types[st] then
												active.types[st] = true
												changed = true
											end
										end
									end
								end
							end
							if appliedAny then
								sup.accepted = true
							end
						end
					end
				end
				for _, sup in ipairs(supportList) do
					if not sup.accepted then
						local activeName
						if #activeList == 1 then
							activeName = gemDisplayName(activeList[1].gem)
						else
							activeName = "any active skill in this group"
						end
						t_insert(findings, {
							id = "support.inapplicable." .. tostring(sup.ge.name or gemDisplayName(sup.gem)),
							severity = "high",
							category = "Skills",
							title = "Support does not apply: " .. gemDisplayName(sup.gem),
							detail = s_format("%s does nothing for %s (skill-type tags do not match).", gemDisplayName(sup.gem), activeName),
							fix = "Replace it with a support whose tags match the skill, or move it to a compatible skill.",
							jump = { mode = "SKILLS" },
						})
					end
				end
			end
		end
	end
end)

-- Check: a socket group with an active skill but no support gems at all.
t_insert(Advisor.checks, function(build, out, findings)
	local skillsTab = build and build.skillsTab
	if not (skillsTab and skillsTab.socketGroupList) then return end
	for _, group in ipairs(skillsTab.socketGroupList) do
		if group.enabled ~= false then
			local activeGE, activeGem = groupActiveEffect(group)
			if activeGE then
				local hasSupport = false
				for _, gem in ipairs(group.gemList or { }) do
					local ge = gem.gemData and gem.gemData.grantedEffect
					if ge and ge.support and gem.enabled ~= false then
						hasSupport = true
						break
					end
				end
				if not hasSupport then
					t_insert(findings, {
						id = "support.empty." .. gemDisplayName(activeGem),
						severity = "info",
						category = "Skills",
						title = "No support gems on " .. gemDisplayName(activeGem),
						detail = gemDisplayName(activeGem) .. " has no supports — you are leaving sockets unused.",
						fix = "Add support gems to boost this skill.",
						jump = { mode = "SKILLS" },
					})
				end
			end
		end
	end
end)

-- Check: the same support gem socketed more than once in a group (redundant).
t_insert(Advisor.checks, function(build, out, findings)
	local skillsTab = build and build.skillsTab
	if not (skillsTab and skillsTab.socketGroupList) then return end
	for _, group in ipairs(skillsTab.socketGroupList) do
		if group.enabled ~= false then
			local seen = { }
			for _, gem in ipairs(group.gemList or { }) do
				local ge = gem.gemData and gem.gemData.grantedEffect
				local gid = gem.gemData and gem.gemData.gameId
				if ge and ge.support and gid and gem.enabled ~= false then
					if seen[gid] then
						if seen[gid] ~= "dup" then
							t_insert(findings, {
								id = "support.duplicate." .. tostring(gid),
								severity = "med",
								category = "Skills",
								title = "Duplicate support: " .. gemDisplayName(gem),
								detail = gemDisplayName(gem) .. " is socketed more than once in the same group.",
								fix = "Remove the duplicate; a support only applies once.",
								jump = { mode = "SKILLS" },
							})
							seen[gid] = "dup"
						end
					else
						seen[gid] = true
					end
				end
			end
		end
	end
end)

-- Check: gems whose attribute requirement exceeds the character's attribute (gem disabled).
local GEM_ATTRS = {
	{ req = "reqStr", attr = "Str", label = "Strength" },
	{ req = "reqDex", attr = "Dex", label = "Dexterity" },
	{ req = "reqInt", attr = "Int", label = "Intelligence" },
}
t_insert(Advisor.checks, function(build, out, findings)
	local skillsTab = build and build.skillsTab
	if not (skillsTab and skillsTab.socketGroupList) then return end
	for _, group in ipairs(skillsTab.socketGroupList) do
		if group.enabled ~= false then
			for _, gem in ipairs(group.gemList or { }) do
				if gem.enabled ~= false and gem.gemData then
					for _, a in ipairs(GEM_ATTRS) do
						local req = gem[a.req]
						local have = out[a.attr]
						if req and have and req > 0 and req > have then
							t_insert(findings, {
								id = "attr.unmet." .. a.attr .. "." .. gemDisplayName(gem),
								severity = "high",
								category = "Attributes",
								title = "Unmet " .. a.label .. " requirement: " .. gemDisplayName(gem),
								detail = s_format("%s needs %d %s but you have %d (gem disabled).", gemDisplayName(gem), req, a.label, have),
								fix = s_format("Add ~%d %s, or use a lower-level gem.", req - have, a.label),
								jump = { mode = "SKILLS" },
							})
						end
					end
				end
			end
		end
	end
end)

-- Check: Spirit reservation — over-reserved (negative unreserved) or large unused pool.
t_insert(Advisor.checks, function(build, out, findings)
	local total = out.Spirit
	local unreserved = out.SpiritUnreserved
	if total and unreserved then
		if unreserved < 0 then
			t_insert(findings, {
				id = "spirit.over",
				severity = "high",
				category = "Spirit",
				title = "Spirit is over-reserved",
				detail = s_format("Unreserved Spirit is %d (you have reserved more than your %d total).", unreserved, total),
				fix = "Drop or cheapen a reservation so unreserved Spirit is not negative.",
			})
		elseif total > 0 and unreserved >= LARGE_UNUSED_SPIRIT then
			t_insert(findings, {
				id = "spirit.unused",
				severity = "info",
				category = "Spirit",
				title = "Unused Spirit available",
				detail = s_format("%d of %d Spirit is unreserved.", unreserved, total),
				fix = "You could reserve another aura/herald or buff with the spare Spirit.",
			})
		end
	end
end)

-- ===== Issue #82: passive-tree efficiency checks =====

local MAX_NOTABLE_SUGGESTIONS = 8   -- cap adjacent-notable suggestions so the list stays readable
local PAYOFF_TYPES = { Notable = true, Keystone = true, Socket = true, Mastery = true }

-- Is a node currently allocated and active in the tree's current allocation mode?
local function isNodeActive(spec, node)
	if not (node and spec.allocNodes[node.id]) then return false end
	if not spec.CanPathThroughAllocMode then
		local mode = node.allocMode or 0
		return mode == 0 or mode == spec.allocMode
	end
	return spec:CanPathThroughAllocMode(spec.allocMode, node)
end

-- Does a node provide any stats of its own (so a leaf node is not necessarily wasted)?
local function nodeHasStats(node)
	return (node.sd and node.sd[1]) or (node.modList and node.modList[1])
end

-- Count a node's active allocated neighbours.
local function allocDegree(spec, node)
	local d = 0
	if node.linked then
		for _, other in ipairs(node.linked) do
			if other and isNodeActive(spec, other) then d = d + 1 end
		end
	end
	return d
end

-- Check: unallocated notables directly adjacent to your allocated tree (cheap upgrades).
t_insert(Advisor.checks, function(build, out, findings)
	local spec = build and build.spec
	if not (spec and spec.allocNodes) then return end
	local seen = { }
	local count = 0
	for _, node in pairs(spec.allocNodes) do
		if isNodeActive(spec, node) and node.linked then
			for _, other in ipairs(node.linked) do
				if other and other.type == "Notable" and not other.ascendancyName
					and not spec.allocNodes[other.id] and not seen[other.id] then
					seen[other.id] = true
					count = count + 1
					if count <= MAX_NOTABLE_SUGGESTIONS then
						local stat = (other.sd and other.sd[1]) or other.name or "a notable"
						t_insert(findings, {
							id = "tree.adjacent." .. tostring(other.id),
							severity = "info",
							category = "Tree",
							title = "Adjacent notable available: " .. (other.name or "Notable"),
							detail = s_format("%s is one node from your tree (%s).", other.name or "A notable", stat),
							fix = "Consider pathing into it if the stats suit your build.",
							jump = { mode = "TREE" },
						})
					end
				end
			end
		end
	end
end)

-- Check: allocated travel (Normal) leaf nodes that pay nothing (wasted points).
t_insert(Advisor.checks, function(build, out, findings)
	local spec = build and build.spec
	if not (spec and spec.allocNodes) then return end
	for id, node in pairs(spec.allocNodes) do
		if isNodeActive(spec, node) and node.type == "Normal" and not nodeHasStats(node) and allocDegree(spec, node) == 1 then
			local neighborIsPayoff = false
			if node.linked then
				for _, other in ipairs(node.linked) do
					if other and (PAYOFF_TYPES[other.type] or other.type == "ClassStart" or other.type == "AscendClassStart") then
						neighborIsPayoff = true
						break
					end
				end
			end
			if not neighborIsPayoff then
				t_insert(findings, {
					id = "tree.deadend." .. tostring(id),
					severity = "med",
					category = "Tree",
					title = "Dead-end travel node",
					detail = s_format("Allocated travel node '%s' leads to no notable, keystone, socket, or start.", node.name or tostring(id)),
					fix = "Refund this point (and its branch) unless it reaches something worthwhile.",
					jump = { mode = "TREE" },
				})
			end
		end
	end
end)

-- Check: allocated nodes with no allocated path back to a class start (should not happen).
t_insert(Advisor.checks, function(build, out, findings)
	local spec = build and build.spec
	if not (spec and spec.allocNodes) then return end
	local queue = { }
	local visited = { }
	for id, node in pairs(spec.allocNodes) do
		if isNodeActive(spec, node) and (node.type == "ClassStart" or node.type == "AscendClassStart") then
			visited[id] = true
			t_insert(queue, node)
		end
	end
	while #queue > 0 do
		local node = table.remove(queue)
		if node.linked then
			for _, other in ipairs(node.linked) do
				if other and isNodeActive(spec, other) and not visited[other.id] then
					visited[other.id] = true
					t_insert(queue, other)
				end
			end
		end
	end
	local floating = 0
	for id, node in pairs(spec.allocNodes) do
		if isNodeActive(spec, node) and not visited[id] and node.type ~= "ClassStart" and node.type ~= "AscendClassStart" then
			floating = floating + 1
		end
	end
	if floating > 0 then
		t_insert(findings, {
			id = "tree.floating",
			severity = "med",
			category = "Tree",
			title = "Disconnected passive allocations",
			detail = s_format("%d allocated node(s) are not connected to your class start.", floating),
			fix = "Re-path so every allocated node connects to your starting location.",
			jump = { mode = "TREE" },
		})
	end
end)

function Advisor.sort(findings)
	t_sort(findings, function(a, b)
		local ra = Advisor.severityRank[a.severity] or 0
		local rb = Advisor.severityRank[b.severity] or 0
		if ra ~= rb then return ra > rb end
		if a.category ~= b.category then return a.category < b.category end
		return (a.title or "") < (b.title or "")
	end)
	return findings
end

function Advisor.analyze(build)
	local findings = { }
	local out = build and build.calcsTab and build.calcsTab.mainOutput
	if not out then return findings end
	for _, check in ipairs(Advisor.checks) do
		local ok, err = pcall(check, build, out, findings)
		if not ok then
			ConPrintf("Advisor check error: %s", tostring(err))
		end
	end
	Advisor.sort(findings)
	return findings
end

return Advisor
