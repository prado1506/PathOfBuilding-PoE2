describe("TestWard", function()
	before_each(function()
		newBuild()
	end)

	teardown(function()
		-- newBuild() takes care of resetting everything in setup()
	end)

	it("Ward stat from items", function()
		build.configTab.input.customMods = "\z
		+100 to Ward\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.are.equals(100, build.calcsTab.calcsOutput.Ward)
	end)

	it("Ward increased modifier", function()
		build.configTab.input.customMods = "\z
		+100 to Ward\n\z
		50% increased Ward\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.are.equals(150, build.calcsTab.calcsOutput.Ward)
	end)

	it("Ward regeneration", function()
		build.configTab.input.customMods = "\z
		+1000 to Ward\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		-- 5% per second = 300% per minute, so 1000 * 300/100/60 = 50 per second
		assert.are.equals(50, build.calcsTab.calcsOutput.WardRegen)
	end)

	it("Ward regeneration with increased", function()
		build.configTab.input.customMods = "\z
		+1000 to Ward\n\z
		100% increased Ward Regeneration\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		-- 50 base * (1 + 100/100) = 100 per second
		assert.are.equals(100, build.calcsTab.calcsOutput.WardRegen)
	end)

	it("Ward bypass", function()
		build.configTab.input.customMods = "\z
		+100 to Ward\n\z
		50% of Damage taken bypasses Ward\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.are.equals(50, build.calcsTab.calcsOutput.WardBypass)
	end)

	it("Ward recharge delay", function()
		build.configTab.input.customMods = "\z
		+100 to Ward\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		-- Base ward recharge delay is 2 seconds
		assert.are.equals(2, build.calcsTab.calcsOutput.WardRechargeDelay)
	end)

	it("Ward recharge delay faster", function()
		build.configTab.input.customMods = "\z
		+100 to Ward\n\z
		50% faster Restoration of Ward\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		-- 2 / (1 + 50/100) = 2 / 1.5 = 1.33
		assert.is_near(1.33, build.calcsTab.calcsOutput.WardRechargeDelay, 0.01)
	end)

	it("Runic Ward keyword maps to Ward (import alias)", function()
		build.configTab.input.customMods = "\z
		+100 to Runic Ward\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.are.equals(100, build.calcsTab.calcsOutput.Ward)
	end)

	it("increased Runic Ward keyword maps to Ward INC", function()
		build.configTab.input.customMods = "\z
		+100 to Runic Ward\n\z
		50% increased Runic Ward\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.are.equals(150, build.calcsTab.calcsOutput.Ward)
	end)

	it("faster Restoration of Runic Ward maps to ward recharge", function()
		build.configTab.input.customMods = "\z
		+100 to Runic Ward\n\z
		50% faster Restoration of Runic Ward\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		-- 2 / (1 + 50/100) = 1.33
		assert.is_near(1.33, build.calcsTab.calcsOutput.WardRechargeDelay, 0.01)
	end)

	it("damage taken bypasses Runic Ward maps to WardBypass", function()
		build.configTab.input.customMods = "\z
		+100 to Runic Ward\n\z
		50% of Damage taken bypasses Runic Ward\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.are.equals(50, build.calcsTab.calcsOutput.WardBypass)
	end)

	it("Ward config options", function()
		build.configTab.input.customMods = "\z
		+100 to Ward\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.are.equals(100, build.calcsTab.calcsOutput.Ward)

		build.configTab.input.conditionLowWard = true
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.is_true(build.calcsTab.calcsOutput.LowWard)
	end)

	it("WardRegen is included in TotalNetRegen", function()
		build.configTab.input.customMods = "\z
		+1000 to Ward\n\z
		1 Physical Damage taken per second\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.are.equals(50, build.calcsTab.calcsOutput.WardRegen)
		-- TotalNetRegen = WardRegen (50) - degen (1) = 49; tolerance of 2 for floor/rounding
		assert.is_near(49, build.calcsTab.calcsOutput.TotalNetRegen, 2)
	end)

	it("ward_rune_maximum_ward_+%_final maps as Ward MORE (not INC)", function()
		-- Verify MORE stacks multiplicatively: 100 base * (1 + 0.5 INC) * (1 + 0.5 MORE) = 225
		build.configTab.input.customMods = "\z
		+100 to Ward\n\z
		50% increased Ward\n\z
		50% more Ward\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.are.equals(225, build.calcsTab.calcsOutput.Ward)
	end)

	it("Runeforged Ward from item with rune mods does not double-count (paste path regression)", function()
		-- Create an item through the build (paste a Runeforged item with rune-like Ward mod)
		local item = new("Item", [[
			Rarity: Rare
			Mock Runeforged Coat
			Runeforged Serpentscale Coat
			--------
			Runic Ward: 104
			--------
			Item Level: 67
			--------
			+65 to maximum Ward
		]])
		-- The game displays the FINAL ward value in the property line (post-quality, post-all-mods).
		-- "Runic Ward: 104" means 104 is the game-computed final value.
		-- PoB must NOT re-apply quality or add the +65 mod on top of the authoritative value.
		-- Without fix: Ward = round((104+65) * 1.2) = 203 (double-counts flat mod and quality)
		-- With fix (property line authoritative): Ward = 104 (no re-scaling)
		item:BuildModList()
		-- 104 = property line verbatim; the +65 mod is consumed (not re-applied) and quality is already baked in
		assert.are.equals(104, item.armourData.Ward)
	end)

	it("WardCoverOnMinionDeath stat ID parses correctly", function()
		build.configTab.input.customMods = "\z
		recover 10% of maximum ward on persistent minion death\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.are.equals(10, build.calcsTab.calcsOutput.WardCoverOnMinionDeath)
	end)

	it("Authoritative Ward is not re-scaled by local defencesInc mod", function()
		-- When a Runeforged item has a 'Runic Ward: X' property line AND a local
		-- '% increased Defences' mod, the authoritative Ward must stay at X.
		-- defencesInc should apply to Armour/Evasion/ES but not to the baked-in Ward value.
		local item = new("Item", [[
			Rarity: Rare
			Mock Runeforged Coat
			Runeforged Serpentscale Coat
			--------
			Runic Ward: 83
			--------
			Item Level: 67
			--------
			20% increased Defences
		]])
		item:BuildModList()
		-- Authoritative path: Ward must equal the property line value verbatim.
		-- Without fix: round(83 * (1 + 20/100)) = 100 (defencesInc wrongly re-applied)
		-- With fix: 83 (property line is final; defencesInc excluded from Ward)
		assert.are.equals(83, item.armourData.Ward)
	end)

	it("WardPerLevel in authoritative path scales with wardInc and quality but Ward stays authoritative", function()
		-- Authoritative Ward: the property line value is final; the local 112% INC Ward mod is
		-- consumed to prevent double-application in CalcDefence, but WardPerLevel is NOT baked
		-- into the property line, so wardInc must still be applied to it — same as EvasionPerLevel
		-- and EnergyShieldPerLevel which both scale with their respective local INC mods.
		-- Ward    = 83 (authoritative; INC does not re-scale it)
		-- WardPerLevel = 1 * (1 + 112/100) * (1 + 20/100) = 2.12 * 1.2 = 2.544
		local item = new("Item", [[
			Rarity: Rare
			Empyrean Shelter
			Runeforged Serpentscale Coat
			--------
			Quality: 20
			Runic Ward: 83
			--------
			Item Level: 36
			Implicits: 1
			Has +1 to maximum Runic Ward per player level (implicit)
			--------
			112% increased Ward
		]])
		item:BuildModList()
		assert.are.equals(83, item.armourData.Ward)
		assert.is_near(2.544, item.armourData.WardPerLevel, 0.01)
	end)

	it("WardPerLevel scales with defencesInc in authoritative path but Ward does not", function()
		-- defencesInc should scale WardPerLevel (not yet baked into the property line) but
		-- must NOT re-scale the authoritative Ward value itself.
		-- WardPerLevel = 1 * (1 + 20/100) * (1 + 0/100) = 1.2
		local item = new("Item", [[
			Rarity: Rare
			Empyrean Shelter
			Runeforged Serpentscale Coat
			--------
			Runic Ward: 83
			--------
			Item Level: 36
			Implicits: 1
			Has +1 to maximum Runic Ward per player level (implicit)
			--------
			20% increased Defences
		]])
		item:BuildModList()
		assert.are.equals(83, item.armourData.Ward)
		assert.is_near(1.2, item.armourData.WardPerLevel, 0.01)
	end)

	it("Non-authoritative Ward path: plain Ward mods scale correctly (no property line)", function()
		-- Test that when Ward comes only from customMods (no property line),
		-- the non-authoritative path in Item.lua applies INC and quality correctly.
		-- Use a Runeforged item without a Runic Ward property line:
		-- wardBase comes from mods, wardInc from mods, quality from item.
		local item = new("Item", [[
			Rarity: Rare
			Mock Runeforged Coat
			Runeforged Serpentscale Coat
			--------
			Quality: 20
			--------
			+65 to maximum Ward
			30% increased Ward
		]])
		item:BuildModList()
		-- Non-authoritative: no "Runic Ward" property line → armourData.Ward was nil on entry
		-- wardBase = calcLocal(Ward,BASE,0) + base.armour.Ward = 65 + 0 = 65
		-- wardInc = calcLocal(Ward,INC,0) = 30
		-- quality = 20
		-- Expected: round(65 * (1 + 30/100) * (1 + 20/100)) = round(65 * 1.3 * 1.2) = round(101.4) = 101
		assert.are.equals(101, item.armourData.Ward)
	end)
end)
