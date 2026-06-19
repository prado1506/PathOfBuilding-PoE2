-- cspell:ignore maxhit deadend ntype minionsplash
describe("Advisor", function()
	local Advisor

	before_each(function()
		newBuild()
		Advisor = require("Modules/Advisor")
	end)

	-- A defensively "healthy" build: capped resists, ample EHP, recovery, and a mitigation
	-- layer, so no check fires unless a test overrides the relevant stats.
	local function healthyOutput(overrides)
		local out = {
			FireResist = 75, FireResistOverCap = 0,
			ColdResist = 75, ColdResistOverCap = 0,
			LightningResist = 75, LightningResistOverCap = 0,
			ChaosResist = 0, ChaosResistOverCap = 0,
			Life = 4000, EnergyShield = 0, TotalEHP = 40000,
			LifeRegenRecovery = 200, EnergyShieldRegenRecovery = 0,
			LifeLeechGainRate = 0, EnergyShieldLeechGainRate = 0,
			PhysicalDamageReduction = 30, EvadeChance = 0,
			EffectiveBlockChance = 0, EffectiveSpellSuppressionChance = 0,
		}
		if overrides then
			for k, v in pairs(overrides) do out[k] = v end
		end
		return out
	end

	local function makeBuild(mainOutput, level)
		return { calcsTab = { mainOutput = mainOutput }, characterLevel = level or 90 }
	end

	local function byId(findings, id)
		for _, f in ipairs(findings) do
			if f.id == id then return f end
		end
		return nil
	end

	it("returns no findings when the build is not calculated", function()
		assert.are.equal(0, #Advisor.analyze({ }))
		assert.are.equal(0, #Advisor.analyze(makeBuild(nil)))
	end)

	it("produces no survivability findings for a healthy build", function()
		assert.are.equal(0, #Advisor.analyze(makeBuild(healthyOutput())))
	end)

	it("flags an under-cap elemental resistance with the exact deficit", function()
		local findings = Advisor.analyze(makeBuild(healthyOutput({ FireResist = 58, FireResistOverCap = -17 })))
		local f = byId(findings, "res.fire.uncapped")
		assert.is_truthy(f)
		assert.are.equal("high", f.severity)
		assert.is_truthy(f.detail:find("58"))
		assert.is_truthy(f.detail:find("17"))
	end)

	it("flags chaos as med severity and respects Chaos Inoculation", function()
		local under = Advisor.analyze(makeBuild(healthyOutput({ ChaosResist = -30, ChaosResistOverCap = -30 })))
		local f = byId(under, "res.chaos.uncapped")
		assert.is_truthy(f)
		assert.are.equal("med", f.severity)

		local immune = Advisor.analyze(makeBuild(healthyOutput({ ChaosResist = -30, ChaosResistOverCap = -30, ChaosInoculation = true })))
		assert.is_nil(byId(immune, "res.chaos.uncapped"))
	end)

	it("sorts higher severity before lower", function()
		local findings = Advisor.analyze(makeBuild(healthyOutput({ FireResistOverCap = -25, ChaosResistOverCap = -30, ChaosResist = -30 })))
		assert.is_true(#findings >= 2)
		assert.are.equal("high", findings[1].severity)
	end)

	it("flags wasted elemental resistance over the cap as info", function()
		local f = byId(Advisor.analyze(makeBuild(healthyOutput({ FireResistOverCap = 20 }))), "res.fire.surplus")
		assert.is_truthy(f)
		assert.are.equal("info", f.severity)
		assert.is_truthy(f.detail:find("20"))
	end)

	it("flags low effective HP for the level and not when ample", function()
		local low = byId(Advisor.analyze(makeBuild(healthyOutput({ TotalEHP = 5000 }), 90)), "ehp.low")
		assert.is_truthy(low)
		assert.are.equal("med", low.severity)
		assert.is_nil(byId(Advisor.analyze(makeBuild(healthyOutput({ TotalEHP = 40000 }), 90)), "ehp.low"))
	end)

	it("flags missing recovery", function()
		local f = byId(Advisor.analyze(makeBuild(healthyOutput({ LifeRegenRecovery = 0, EnergyShieldRegenRecovery = 0, LifeLeechGainRate = 0, EnergyShieldLeechGainRate = 0 }))), "recovery.none")
		assert.is_truthy(f)
		assert.are.equal("med", f.severity)
	end)

	it("flags missing mitigation layers", function()
		local f = byId(Advisor.analyze(makeBuild(healthyOutput({ PhysicalDamageReduction = 0, EvadeChance = 0, EffectiveBlockChance = 0, EffectiveSpellSuppressionChance = 0 }))), "mitigation.none")
		assert.is_truthy(f)
		assert.are.equal("med", f.severity)
	end)

	it("counts projectile evade and spell block as mitigation layers", function()
		assert.is_nil(byId(Advisor.analyze(makeBuild(healthyOutput({ PhysicalDamageReduction = 0, EvadeChance = 0, MeleeEvadeChance = 0, ProjectileEvadeChance = 25, EffectiveBlockChance = 0, EffectiveSpellBlockChance = 0, EffectiveSpellSuppressionChance = 0 }))), "mitigation.none"))
		assert.is_nil(byId(Advisor.analyze(makeBuild(healthyOutput({ PhysicalDamageReduction = 0, EvadeChance = 0, EffectiveBlockChance = 0, EffectiveSpellBlockChance = 15, EffectiveSpellSuppressionChance = 0 }))), "mitigation.none"))
	end)

	it("surfaces the weakest damage type by max hit", function()
		local f = byId(Advisor.analyze(makeBuild(healthyOutput({
			PhysicalMaximumHitTaken = 5000, FireMaximumHitTaken = 3000,
			ColdMaximumHitTaken = 8000, LightningMaximumHitTaken = 8000, ChaosMaximumHitTaken = 9000,
		}))), "maxhit.weakest")
		assert.is_truthy(f)
		assert.is_truthy(f.detail:find("Fire"))
		assert.is_truthy(f.detail:find("3000"))
	end)

	local function activeGem(name, skillType)
		return { enabled = true, gemData = { name = name, gameId = name, grantedEffect = { name = name, skillTypes = { [skillType] = true } } } }
	end

local function supportGem(name, gameId, opts)
	opts = opts or { }
	return { enabled = true, gemData = { name = name, gameId = gameId or name, grantedEffect = {
		name = name, support = true,
		requireSkillTypes = opts.require or { },
		excludeSkillTypes = opts.exclude or { },
		addSkillTypes = opts.add or { },
		ignoreMinionTypes = opts.ignoreMinionTypes,
	} } }
end

	local function makeSkillBuild(socketGroupList, outOverrides)
		return { calcsTab = { mainOutput = healthyOutput(outOverrides) }, characterLevel = 90, skillsTab = { socketGroupList = socketGroupList } }
	end

	it("flags a support whose tags do not match the active skill", function()
		local group = { enabled = true, gemList = {
			activeGem("Spark", SkillType.Spell),
			supportGem("Melee Infusion", "melee", { require = { SkillType.Attack } }),
		} }
		local f = byId(Advisor.analyze(makeSkillBuild({ group })), "support.inapplicable.Melee Infusion")
		assert.is_truthy(f)
		assert.are.equal("high", f.severity)
	end)

	it("does not flag inapplicable supports in a disabled group", function()
		local group = { enabled = false, gemList = {
			activeGem("Spark", SkillType.Spell),
			supportGem("Melee Infusion", "melee", { require = { SkillType.Attack } }),
		} }
		assert.is_nil(byId(Advisor.analyze(makeSkillBuild({ group })), "support.inapplicable.Melee Infusion"))
	end)

	it("does not flag a support whose tags match", function()
		local group = { enabled = true, gemList = {
			activeGem("Spark", SkillType.Spell),
			supportGem("Spell Echo", "echo", { require = { SkillType.Spell } }),
		} }
		assert.is_nil(byId(Advisor.analyze(makeSkillBuild({ group })), "support.inapplicable.Spell Echo"))
	end)

	it("respects addSkillTypes broadening from enabled supports only", function()
		-- Adder adds SkillType.Area to the effective type set; Follower requires Area.
		-- Follower should not be flagged when Adder is enabled, but SHOULD be when it is disabled.
		local adder = supportGem("Area Adder", "adder", { add = { SkillType.Area } })
		local follower = supportGem("Area Follower", "follower", { require = { SkillType.Area } })
		local group_enabled = { enabled = true, gemList = {
			activeGem("Spark", SkillType.Spell), adder, follower,
		} }
		assert.is_nil(byId(Advisor.analyze(makeSkillBuild({ group_enabled })), "support.inapplicable.Area Follower"))

		local adder_off = supportGem("Area Adder", "adder", { add = { SkillType.Area } })
		adder_off.enabled = false
		local group_disabled = { enabled = true, gemList = {
			activeGem("Spark", SkillType.Spell), adder_off, follower,
		} }
		assert.is_truthy(byId(Advisor.analyze(makeSkillBuild({ group_disabled })), "support.inapplicable.Area Follower"))
	end)

	it("flags a group with no support gems", function()
		local group = { enabled = true, gemList = { activeGem("Spark", SkillType.Spell) } }
		assert.is_truthy(byId(Advisor.analyze(makeSkillBuild({ group })), "support.empty.Spark"))
	end)

	it("does not flag empty supports in a disabled group", function()
		local group = { enabled = false, gemList = { activeGem("Spark", SkillType.Spell) } }
		assert.is_nil(byId(Advisor.analyze(makeSkillBuild({ group })), "support.empty.Spark"))
	end)

	it("flags a duplicate support gem", function()
		local group = { enabled = true, gemList = {
			activeGem("Spark", SkillType.Spell),
			supportGem("Spell Echo", "echo", { require = { SkillType.Spell } }),
			supportGem("Spell Echo", "echo", { require = { SkillType.Spell } }),
		} }
		local f = byId(Advisor.analyze(makeSkillBuild({ group })), "support.duplicate.echo")
		assert.is_truthy(f)
		assert.are.equal("med", f.severity)
	end)

	it("emits exactly one duplicate finding even when three copies are socketed", function()
		local group = { enabled = true, gemList = {
			activeGem("Spark", SkillType.Spell),
			supportGem("Spell Echo", "echo", { require = { SkillType.Spell } }),
			supportGem("Spell Echo", "echo", { require = { SkillType.Spell } }),
			supportGem("Spell Echo", "echo", { require = { SkillType.Spell } }),
		} }
		local findings = Advisor.analyze(makeSkillBuild({ group }))
		local count = 0
		for _, f in ipairs(findings) do
			if f.id == "support.duplicate.echo" then count = count + 1 end
		end
		assert.are.equal(1, count)
	end)

	it("does not flag a support that applies via minionSkillTypes", function()
		local active = { enabled = true, gemData = { name = "Summon Raging Spirits", gameId = "Summon Raging Spirits", grantedEffect = {
			name = "Summon Raging Spirits",
			skillTypes = { [SkillType.Spell] = true },
			minionSkillTypes = { [SkillType.Attack] = true, [SkillType.Melee] = true },
		} } }
		local sup = supportGem("Melee Infusion", "melee", { require = { SkillType.Attack } })
		local group = { enabled = true, gemList = { active, sup } }
		assert.is_nil(byId(Advisor.analyze(makeSkillBuild({ group })), "support.inapplicable.Melee Infusion"))
	end)

	it("does not flag a support valid for any active in a multi-active group", function()
		local group = { enabled = true, gemList = {
			activeGem("Spark", SkillType.Spell),
			activeGem("Heavy Strike", SkillType.Attack),
			supportGem("Melee Infusion", "melee", { require = { SkillType.Attack } }),
		} }
		assert.is_nil(byId(Advisor.analyze(makeSkillBuild({ group })), "support.inapplicable.Melee Infusion"))
	end)

	it("flags a support that cannot support any active in a multi-active group", function()
		local group = { enabled = true, gemList = {
			activeGem("Spark", SkillType.Spell),
			activeGem("Fireball", SkillType.Spell),
			supportGem("Melee Infusion", "melee", { require = { SkillType.Attack } }),
		} }
		local f = byId(Advisor.analyze(makeSkillBuild({ group })), "support.inapplicable.Melee Infusion")
		assert.is_truthy(f)
		assert.is_truthy(f.detail:find("any active skill in this group"))
	end)

	it("does not flag a minion support excluded only by the active skill's types", function()
		-- The support targets the minion, so an active-skill-only type in its exclude list should not matter.
		local active = { enabled = true, gemData = { name = "Raise Zombie", gameId = "RaiseZombie", grantedEffect = {
			name = "Raise Zombie",
			skillTypes = { [SkillType.Spell] = true, [SkillType.Minion] = true, [SkillType.CreatesMinion] = true },
			minionSkillTypes = { [SkillType.Attack] = true, [SkillType.Melee] = true, [SkillType.MeleeSingleTarget] = true },
		} } }
		local sup = supportGem("Minion Splash", "minionsplash", { require = { SkillType.CreatesMinion, SkillType.MeleeSingleTarget, SkillType.AND }, exclude = { SkillType.Spell } })
		local group = { enabled = true, gemList = { active, sup } }
		assert.is_nil(byId(Advisor.analyze(makeSkillBuild({ group })), "support.inapplicable.Minion Splash"))
	end)

	it("does not let an incompatible support enable another support via addSkillTypes", function()
		-- Adder requires Attack (active is Spell), so it is invalid and its Area tag must not enable Follower.
		local adder = supportGem("Area Adder", "adder", { require = { SkillType.Attack }, add = { SkillType.Area } })
		local follower = supportGem("Area Follower", "follower", { require = { SkillType.Area } })
		local group = { enabled = true, gemList = {
			activeGem("Spark", SkillType.Spell), adder, follower,
		} }
		local findings = Advisor.analyze(makeSkillBuild({ group }))
		assert.is_truthy(byId(findings, "support.inapplicable.Area Adder"))
		assert.is_truthy(byId(findings, "support.inapplicable.Area Follower"))
	end)

	it("flags an unmet attribute requirement", function()
		local gem = activeGem("Heavy Skill", SkillType.Spell)
		gem.reqStr = 200
		local group = { enabled = true, gemList = { gem } }
		local f = byId(Advisor.analyze(makeSkillBuild({ group }, { Str = 100 })), "attr.unmet.Str.Heavy Skill")
		assert.is_truthy(f)
		assert.are.equal("high", f.severity)
		assert.is_truthy(f.detail:find("200"))
	end)

	it("does not flag unmet attribute requirements for gems in a disabled group", function()
		local gem = activeGem("Heavy Skill", SkillType.Spell)
		gem.reqStr = 200
		local group = { enabled = false, gemList = { gem } }
		assert.is_nil(byId(Advisor.analyze(makeSkillBuild({ group }, { Str = 100 })), "attr.unmet.Str.Heavy Skill"))
	end)

	it("flags over-reserved and unused spirit", function()
		local over = byId(Advisor.analyze(makeBuild(healthyOutput({ Spirit = 100, SpiritUnreserved = -10 }))), "spirit.over")
		assert.is_truthy(over)
		assert.are.equal("high", over.severity)
		local unused = byId(Advisor.analyze(makeBuild(healthyOutput({ Spirit = 100, SpiritUnreserved = 50 }))), "spirit.unused")
		assert.is_truthy(unused)
		assert.are.equal("info", unused.severity)
	end)

	local function makeNode(id, ntype, name, sd)
		return { id = id, type = ntype, name = name, sd = sd, linked = { } }
	end

	local function linkNodes(a, b)
		table.insert(a.linked, b)
		table.insert(b.linked, a)
	end

	local function makeTreeBuild(nodes, allocIds, allocMode, nodeModes)
		local nodeMap = { }
		for _, n in ipairs(nodes) do nodeMap[n.id] = n end
		local allocNodes = { }
		for _, id in ipairs(allocIds) do
			local node = nodeMap[id]
			if nodeModes and nodeModes[id] then
				node.allocMode = nodeModes[id]
			end
			allocNodes[id] = node
		end
		return {
			calcsTab = { mainOutput = healthyOutput() },
			characterLevel = 90,
			spec = {
				nodes = nodeMap,
				allocNodes = allocNodes,
				allocMode = allocMode or 0,
				CanPathThroughAllocMode = function(_, mode, node)
					local nodeMode = node.allocMode or 0
					return nodeMode == 0 or mode > 0 and nodeMode == mode
				end,
			},
		}
	end

	it("suggests an unallocated notable adjacent to the allocated tree", function()
		local start = makeNode(1, "ClassStart", "Start")
		local a = makeNode(2, "Notable", "Allocated Notable")
		local n = makeNode(3, "Notable", "Nearby Notable", { "+30% increased damage" })
		linkNodes(start, a)
		linkNodes(a, n)
		local f = byId(Advisor.analyze(makeTreeBuild({ start, a, n }, { 1, 2 })), "tree.adjacent.3")
		assert.is_truthy(f)
		assert.are.equal("info", f.severity)
		assert.is_truthy(f.title:find("Nearby Notable"))
	end)

	it("flags a dead-end travel node and not a productive path", function()
		local start = makeNode(1, "ClassStart", "Start")
		local a = makeNode(2, "Normal", "Travel A")
		local b = makeNode(3, "Normal", "Travel B")
		linkNodes(start, a)
		linkNodes(a, b)
		local findings = Advisor.analyze(makeTreeBuild({ start, a, b }, { 1, 2, 3 }))
		local dead = byId(findings, "tree.deadend.3")
		assert.is_truthy(dead)
		assert.are.equal("med", dead.severity)
		assert.is_nil(byId(findings, "tree.deadend.2"))
	end)

	it("does not flag a travel node that reaches a notable", function()
		local start = makeNode(1, "ClassStart", "Start")
		local a = makeNode(2, "Normal", "Travel A")
		local n = makeNode(3, "Notable", "Payoff")
		linkNodes(start, a)
		linkNodes(a, n)
		assert.is_nil(byId(Advisor.analyze(makeTreeBuild({ start, a, n }, { 1, 2, 3 })), "tree.deadend.2"))
	end)

	it("does not flag a travel node that reaches a mastery node", function()
		local start = makeNode(1, "ClassStart", "Start")
		local a = makeNode(2, "Normal", "Travel A")
		local m = makeNode(3, "Mastery", "A Mastery")
		linkNodes(start, a)
		linkNodes(a, m)
		assert.is_nil(byId(Advisor.analyze(makeTreeBuild({ start, a, m }, { 1, 2, 3 })), "tree.deadend.2"))
	end)

	it("does not flag a Normal leaf that leads to an unallocated notable", function()
		-- Start → A(Normal, allocated) → B(Notable, NOT allocated)
		-- A is pathing to a payoff, so it is not a dead-end; only the adjacent-notable suggestion should fire.
		local start = makeNode(1, "ClassStart", "Start")
		local a = makeNode(2, "Normal", "Travel A")
		local b = makeNode(3, "Notable", "Nearby Notable", { "+10 strength" })
		linkNodes(start, a)
		linkNodes(a, b)
		local findings = Advisor.analyze(makeTreeBuild({ start, a, b }, { 1, 2 }))
		assert.is_nil(byId(findings, "tree.deadend.2"))
		assert.is_truthy(byId(findings, "tree.adjacent.3"))
	end)

	it("flags disconnected (floating) allocations", function()
		local start = makeNode(1, "ClassStart", "Start")
		local a = makeNode(2, "Notable", "Connected")
		local floatNode = makeNode(9, "Notable", "Floating")
		linkNodes(start, a)
		local f = byId(Advisor.analyze(makeTreeBuild({ start, a, floatNode }, { 1, 2, 9 })), "tree.floating")
		assert.is_truthy(f)
		assert.are.equal("med", f.severity)
	end)

	it("does not flag a Normal leaf that provides stats", function()
		local start = makeNode(1, "ClassStart", "Start")
		local a = makeNode(2, "Normal", "+10 Strength", { "+10 to Strength" })
		linkNodes(start, a)
		assert.is_nil(byId(Advisor.analyze(makeTreeBuild({ start, a }, { 1, 2 })), "tree.deadend.2"))
	end)

	it("does not flag a bridge node to the ascendancy start", function()
		local start = makeNode(1, "ClassStart", "Start")
		local a = makeNode(2, "Normal", "Ascendancy Bridge")
		local ascStart = makeNode(3, "AscendClassStart", "Ascendancy Start")
		linkNodes(start, a)
		linkNodes(a, ascStart)
		assert.is_nil(byId(Advisor.analyze(makeTreeBuild({ start, a, ascStart }, { 1, 2, 3 })), "tree.deadend.2"))
	end)

	it("ignores allocations from a different weapon set", function()
		local start = makeNode(1, "ClassStart", "Start")
		local a = makeNode(2, "Normal", "Travel A")
		local b = makeNode(3, "Normal", "Travel B")
		linkNodes(start, a)
		linkNodes(a, b)
		-- In mode 0, only the start is active; a and b are mode 2 and should not be flagged.
		local findings = Advisor.analyze(makeTreeBuild({ start, a, b }, { 1, 2, 3 }, 0, { [2] = 2, [3] = 2 }))
		assert.is_nil(byId(findings, "tree.deadend.2"))
		assert.is_nil(byId(findings, "tree.deadend.3"))
		assert.is_nil(byId(findings, "tree.floating"))
	end)
end)
