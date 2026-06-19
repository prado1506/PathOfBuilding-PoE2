describe("TestStonefist", function()
	before_each(function()
		newBuild()
	end)

	-- ModParser: flag parsing

	it("GloveBaseTypeTransform flag is set from ascendancy mod string", function()
		build.configTab.input.customMods = "\z
		Gloves you equip have their base type transformed to fists of stone while equipped\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.is_true(build.calcsTab.mainEnv.modDB:Flag(nil, "GloveBaseTypeTransform"))
	end)

	it("IgnoreAttributeRequirementsForGloves flag is set from ascendancy mod string", function()
		build.configTab.input.customMods = "\z
		Ignore attribute requirements to equip gloves\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.is_true(build.calcsTab.mainEnv.modDB:Flag(nil, "IgnoreAttributeRequirementsForGloves"))
	end)

	it("GloveExplicitModTransform flag is set from ascendancy mod string", function()
		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		assert.is_true(build.calcsTab.mainEnv.modDB:Flag(nil, "GloveExplicitModTransform"))
	end)

	-- CalcPerform: base type transform overwrites glove armour values

	it("GloveBaseTypeTransform: pure-evasion gloves lose base Evasion and gain per-level Evasion from Fists of Stone", function()
		-- Suede Bracers: Evasion=10 (×1.2 quality = 12 from glove). After FoS transform,
		-- armourData.Evasion is zeroed (FoS armour={}) and only the +2-per-level implicit remains.
		-- At level 1 that is 2, so total evasion DECREASES but stays > 0.
		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Suede Bracers
			Evasion: 10
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")

		local baseEvasion = build.calcsTab.mainOutput.Evasion or 0

		-- Apply transform flag
		build.configTab.input.customMods = "\z
		Gloves you equip have their base type transformed to fists of stone while equipped\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		local transformedEvasion = build.calcsTab.mainOutput.Evasion or 0
		-- Glove base evasion is removed; per-level implicit is small at low level → net decrease
		assert.is_true(transformedEvasion < baseEvasion,
			("expected transformed evasion %d < base evasion %d (glove base removed, only per-level implicit remains)"):format(transformedEvasion, baseEvasion))
		assert.is_true(transformedEvasion > 0,
			("expected evasion > 0 after transform, got %d"):format(transformedEvasion))
	end)

	it("GloveBaseTypeTransform: armour-only gloves lose Armour and gain Evasion-per-level from Fists of Stone", function()
		-- Stocky Mitts: Armour only. Fists of Stone has no base Armour (armour={}),
		-- so after transform Armour drops to 0 and Evasion appears via per-level implicit.
		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Stocky Mitts
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")

		local baseArmour = build.calcsTab.mainOutput.Armour or 0
		local baseEvasion = build.calcsTab.mainOutput.Evasion or 0

		build.configTab.input.customMods = "\z
		Gloves you equip have their base type transformed to fists of stone while equipped\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		local transformedEvasion = build.calcsTab.mainOutput.Evasion or 0
		-- Armour goes away (FoS has no base Armour); Evasion appears via +3 per level implicit
		assert.is_true(transformedArmour < baseArmour,
			("expected transformed armour %d < base armour %d"):format(transformedArmour, baseArmour))
		assert.is_true(transformedEvasion > baseEvasion,
			("expected transformed evasion %d > base evasion %d"):format(transformedEvasion, baseEvasion))
	end)

	it("GloveBaseTypeTransform: Fists of Stone implicit injects Evasion per level into modDB", function()
		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Stocky Mitts
			Armour: 10
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")

		local baseEvasion = build.calcsTab.mainOutput.Evasion or 0

		build.configTab.input.customMods = "\z
		Gloves you equip have their base type transformed to fists of stone while equipped\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		-- Implicit: +2 Evasion per level; at level 1 that is +2, plus Fists of Stone base evasion (40)
		local transformedEvasion = build.calcsTab.mainOutput.Evasion or 0
		assert.is_true(transformedEvasion > baseEvasion,
			("expected evasion %d > base evasion %d after Fists of Stone transform"):format(transformedEvasion, baseEvasion))
	end)

	it("GloveBaseTypeTransform: Ward implicit is injected (Ward > 0 after transform)", function()
		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Stocky Mitts
			Armour: 10
		]])
		build.itemsTab:AddDisplayItem()
		build.configTab.input.customMods = "\z
		Gloves you equip have their base type transformed to fists of stone while equipped\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		-- Implicit: +1 Ward per level; should be > 0 at any character level
		local ward = build.calcsTab.calcsOutput.Ward or 0
		assert.is_true(ward > 0,
			("expected Ward > 0 from Fists of Stone implicit, got %d"):format(ward))
	end)

	it("GloveBaseTypeTransform: actual Fists of Stone base still receives per-level Evasion implicit", function()
		-- Equip an actual Fists of Stone item (not a transformed base).
		-- The guard must not skip implicit injection when baseName is already "Fists of Stone".
		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Fists of Stone
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")

		local baseEvasion = build.calcsTab.mainOutput.Evasion or 0

		build.configTab.input.customMods = "\z
		Gloves you equip have their base type transformed to fists of stone while equipped\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		-- +2 Evasion per level implicit must fire; Evasion should increase above the bare base
		local transformedEvasion = build.calcsTab.mainOutput.Evasion or 0
		assert.is_true(transformedEvasion > baseEvasion,
			("expected FoS implicit to increase Evasion from %d to >%d"):format(baseEvasion, baseEvasion))
	end)

	-- CalcPerform: scoped attribute requirement ignore

	it("IgnoreAttributeRequirementsForGloves does not zero global attribute requirements", function()
		-- The scoped flag should NOT zero requirements from non-glove sources
		build.configTab.input.customMods = "\z
		Ignore attribute requirements to equip gloves\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		-- Global flag should be nil; only the scoped flag should be set
		local globalFlag = build.calcsTab.mainEnv.modDB:Flag(nil, "IgnoreAttributeRequirements")
		assert.is_falsy(globalFlag)
		assert.is_true(build.calcsTab.mainEnv.modDB:Flag(nil, "IgnoreAttributeRequirementsForGloves"))
	end)

	-- CalcPerform: explicit mod transformation

	it("GloveExplicitModTransform: empty equivalencies table is a no-op", function()
		local origEquiv = data.modEquivalencies
		data.modEquivalencies = {}

		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			150% increased Armour
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")
		local baseArmour = build.calcsTab.mainOutput.Armour or 0

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")

		-- Armour should be unchanged because no equivalency is defined
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		assert.are.equal(baseArmour, transformedArmour)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: INC mod is upgraded when a matching equivalency exists", function()
		local origEquiv = data.modEquivalencies
		-- Map the specific mod text used in the raw item below to a stronger version
		data.modEquivalencies = {
			["150% increased Armour"] = "300% increased Armour",
		}

		-- Titan Mitts: base Armour = 132 (no quality on a New Item)
		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			150% increased Armour
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")
		-- Baseline: 132 * (1 + 150/100) = 330 (LOCAL INC baked into armourData)
		local baseArmour = build.calcsTab.mainOutput.Armour or 0

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		-- After transform: armourData adjusted to 300% INC → 132 * (1+3) = 528
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		assert.is_near(528, transformedArmour, 2)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: range-format mod text is matched and upgraded", function()
		local origEquiv = data.modEquivalencies
		-- Unique item data files use range text like "(150-200)% increased Armour".
		-- Verify that the raw modLine.line (which retains the range text) is used as the key.
		-- The VALUE must be a resolved numeric literal (parseMod cannot handle range notation).
		data.modEquivalencies = {
			["(150-200)% increased Armour"] = "300% increased Armour",
		}

		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			(150-200)% increased Armour
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")
		local baseArmour = build.calcsTab.mainOutput.Armour or 0

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		-- After transform: armourData adjusted to 300% INC → 132 * (1+3) = 528
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		assert.is_near(528, transformedArmour, 2)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: mapped mod transforms when item also has unmapped mods", function()
		local origEquiv = data.modEquivalencies
		-- Only the Armour INC mod is mapped; the Strength BASE mod has no equivalency
		data.modEquivalencies = {
			["150% increased Armour"] = "300% increased Armour",
		}

		-- Item has both a mapped mod and an unmapped mod
		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			150% increased Armour
			+25 to Strength
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")
		local baseArmour = build.calcsTab.mainOutput.Armour or 0

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		-- Mapped Armour mod upgrades: armourData adjusted to 300% INC → 132 * (1+3) = 528
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		assert.is_near(528, transformedArmour, 2)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: multiple local INC mods on same stat use full INC sum for ratio", function()
		local origEquiv = data.modEquivalencies
		-- Only the 150% mod is in the equivalency table; the 50% mod is NOT mapped.
		-- armourData bakes in both: 132 * (1+(150+50)/100) = 396.
		-- After transform: only the 150% mod changes to 300%, so total INC becomes 350%.
		-- Correct result: round(396 * (1+3.5) / (1+2)) = round(396*4.5/3) = 594.
		-- Buggy single-mod ratio would give: round(396 / 2.5 * 4) = 634 (wrong).
		data.modEquivalencies = {
			["150% increased Armour"] = "300% increased Armour",
		}

		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			150% increased Armour
			50% increased Armour
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		-- round(132*(1+(300+50)/100)) = 594
		assert.is_near(594, transformedArmour, 2)

		data.modEquivalencies = origEquiv
	end)

	it("GloveBaseTypeTransform and GloveExplicitModTransform work independently together", function()
		-- FoS has no base Armour (armour={}); use a flat BASE equivalency so both transforms
		-- produce a non-zero result we can compare:
		-- base-type-only: FoS with "+25 to Armour" explicit → armourData = round(0+25) = 25
		-- fully-transformed: bDelta=25 → round(0 + (25+25)*1*1) = 50; must exceed base-type-only.
		local origEquiv = data.modEquivalencies
		data.modEquivalencies = {
			["+25 to Armour"] = "+50 to Armour",
		}

		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			+25 to Armour
		]])
		build.itemsTab:AddDisplayItem()

		-- Baseline: only base type transform active (no explicit mod upgrade)
		build.configTab.input.customMods = "\z
		Gloves you equip have their base type transformed to fists of stone while equipped\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local baseTypeOnlyArmour = build.calcsTab.mainOutput.Armour or 0

		-- Enable both transforms together (as Way of the Stonefist does in game)
		build.configTab.input.customMods = "\z
		Gloves you equip have their base type transformed to fists of stone while equipped\n\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local fullyTransformedArmour = build.calcsTab.mainOutput.Armour or 0
		-- FoS raw base = 0; totalNewBase = old(25)+delta(25) = 50; round(0+50) = 50
		assert.is_near(50, fullyTransformedArmour, 2)
		assert.is_true(fullyTransformedArmour > baseTypeOnlyArmour,
			("expected fully-transformed armour %d > base-type-only armour %d"):format(fullyTransformedArmour, baseTypeOnlyArmour))

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: global (non-defence) mod is cancelled and upgraded in modDB", function()
		local origEquiv = data.modEquivalencies
		-- Map a global Life mod; Life is not in armStatMap so it follows the cancel+inject path.
		data.modEquivalencies = {
			["+25 to maximum Life"] = "+50 to maximum Life",
		}

		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			+25 to maximum Life
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")
		local baseLife = build.calcsTab.mainOutput.Life or 0

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local transformedLife = build.calcsTab.mainOutput.Life or 0
		-- Old +25 is cancelled; new +50 is injected.  Net: exactly +25 more Life.
		assert.is_near(baseLife + 25, transformedLife, 2)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: flat BASE defence mod is upgraded via baseDelta path", function()
		local origEquiv = data.modEquivalencies
		-- +25 to Armour is a local BASE defence mod (consumed by calcLocal into armourData).
		-- baseDelta = 25; with no INC, armourData goes from 157 to 182.
		data.modEquivalencies = {
			["+25 to Armour"] = "+50 to Armour",
		}

		-- Titan Mitts base Armour = 132 (New Item quality = 0); +25 flat → armourData = 157
		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			+25 to Armour
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		-- baseDelta = +25, no INC change: round(157 + 25 * 1 * 1) = 182
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		assert.is_near(182, transformedArmour, 2)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: implicit local INC is included in Phase 1 ratio", function()
		-- Phase 1 must scan both implicitModLines and explicitModLines.
		-- If implicit INC is missed, oldTotal is under-counted and Phase 3 over-corrects.
		-- armourData = round(132 * (1 + (50+150)/100)) = round(396) = 396
		-- With fix   : oldTotal=200 → ratio 4.5/3 → round(396*4.5/3) = 594
		-- Without fix: oldTotal=150 → ratio 4/2.5 → round(396*4/2.5) = 634 (wrong)
		local origEquiv = data.modEquivalencies
		data.modEquivalencies = {
			["150% increased Armour"] = "300% increased Armour",
		}

		-- Item format with Rarity header: first mod block = implicit, second = explicit.
		build.itemsTab:CreateDisplayItemFromRaw([[
			Rarity: Normal
			Titan Mitts
			--------
			50% increased Armour
			--------
			150% increased Armour
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		-- Correct: round(396 * (1+3.5)/(1+2)) = round(594) = 594
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		assert.is_near(594, transformedArmour, 2)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: compound ArmourAndEvasion INC mod fans out to both stats", function()
		local origEquiv = data.modEquivalencies
		-- "ArmourAndEvasion" maps to both Armour and Evasion in armStatMap.
		data.modEquivalencies = {
			["150% increased Armour and Evasion Rating"] = "300% increased Armour and Evasion Rating",
		}

		-- Titan Mitts base Armour=132, no base Evasion. Phase 3 skips Evasion because
		-- armData["Evasion"] is nil; only Armour is actually modified.
		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			150% increased Armour and Evasion Rating
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		-- oldTotal=150 for both; newTotal=300; Armour: round(330 * 4/2.5) = 528
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		assert.is_near(528, transformedArmour, 2)

		data.modEquivalencies = origEquiv
	end)

	it("GloveBaseTypeTransform + GloveExplicitModTransform: BASE delta uses totalOldLocalBASE + bDelta", function()
		local origEquiv = data.modEquivalencies
		-- When the base type was already swapped, armourData = FoS raw base with no baked-in
		-- explicit mods.  The formula must use the FULL new flat BASE (old+delta), not just
		-- the delta, or the old BASE contribution is silently dropped.
		data.modEquivalencies = {
			["+25 to Armour"] = "+50 to Armour",
		}

		-- Titan Mitts + +25 to Armour; base type will be swapped to Fists of Stone (Armour=0, armour={})
		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			+25 to Armour
		]])
		build.itemsTab:AddDisplayItem()

		build.configTab.input.customMods = "\z
		Gloves you equip have their base type transformed to fists of stone while equipped\n\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		-- FoS raw base Armour = 0; totalOldLocalBASE = 25; bDelta = 25; newTotal INC = 0
		-- armourData = round(0 + (25+25) * 1 * 1) = round(50) = 50
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		assert.is_near(50, transformedArmour, 2)

		data.modEquivalencies = origEquiv
	end)

	it("GloveBaseTypeTransform + GloveExplicitModTransform: BASE delta with quality>0 scales by qualityMult", function()
		-- With baseWasTransformed=true, Phase 3 formula is:
		--   armData[stat] = round(rawFoSBase * newIncFactor + totalNewBase * newIncFactor * qualityMult)
		-- FoS has no base Armour (armour={}), so rawFoSBase=0.  With quality=20 (qualityMult=1.2),
		-- totalNewBase=50: round(0 + 50*1*1.2) = 60.  Without qualityMult: round(0+50) = 50 (wrong).
		local origEquiv = data.modEquivalencies
		data.modEquivalencies = {
			["+25 to Armour"] = "+50 to Armour",
		}

		build.itemsTab:CreateDisplayItemFromRaw([[
			Rarity: Normal
			Titan Mitts
			Quality: 20
			--------
			+25 to Armour
		]])
		build.itemsTab:AddDisplayItem()

		build.configTab.input.customMods = "\z
		Gloves you equip have their base type transformed to fists of stone while equipped\n\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		-- round(0 + 50*1*1.2) = 60; wrong without qualityMult: round(0+50) = 50
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		assert.is_near(60, transformedArmour, 2)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: invalid equivalency leaves stats unchanged", function()
		-- If modLib.parseMod() returns nil (invalid equivalency string), the mod line
		-- must be skipped entirely — stats must equal the pre-transform baseline.
		local origEquiv = data.modEquivalencies
		data.modEquivalencies = {
			-- This is syntactically invalid and parseMod will return nil.
			["150% increased Armour"] = "NOT_A_VALID_MOD_STRING!!!",
		}

		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			150% increased Armour
		]])
		build.itemsTab:AddDisplayItem()

		-- Baseline without transform
		runCallback("OnFrame")
		local baselineArmour = build.calcsTab.mainOutput.Armour or 0

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0

		-- Stats must be unchanged: an invalid equivalency is a no-op.
		assert.is_near(baselineArmour, transformedArmour, 1)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: AlternateQualityArmour sets qualityMult=1 for BASE delta scaling", function()
		-- When "quality does not increase defences" is present, Item.lua already set
		-- qualityScalar=0 so armourData was computed without quality.  CalcPerform must
		-- also use qualityMult=1 for the bDelta term, or the BASE upgrade is over-scaled.
		-- With quality=20 and bDelta=25: correct=182, wrong=187 (1.2× instead of 1×).
		local origEquiv = data.modEquivalencies
		data.modEquivalencies = {
			["+25 to Armour"] = "+50 to Armour",
		}

		-- "quality does not increase defences" as implicit; "+25 to Armour" as explicit.
		-- Item.lua will see AlternateQualityArmour and set qualityScalar=0 → armourData=157.
		build.itemsTab:CreateDisplayItemFromRaw([[
			Rarity: Normal
			Titan Mitts
			Quality: 20
			--------
			quality does not increase defences
			--------
			+25 to Armour
		]])
		build.itemsTab:AddDisplayItem()

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		-- armourData = round(132+25)*1*1 = 157; bDelta=25; qualityMult=1
		-- result = round(157 + 25*1*1) = 182; wrong (qualityMult=1.2) would give 187
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		assert.is_near(182, transformedArmour, 2)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: equivalency containing a FLAG mod is skipped entirely", function()
		-- If an equivalency value parses to a non-BASE/INC mod (e.g. FLAG), the whole
		-- line must be skipped.  FLAG mods cannot be cancelled by value negation; injecting
		-- the upgraded FLAG while the original stays in modDB would double-activate it.
		-- We verify that armour stays at baseline and no extra mods appear.
		local origEquiv = data.modEquivalencies
		-- "Culling Strike" parses to a FLAG mod, which must trigger the guard.
		data.modEquivalencies = {
			["150% increased Armour"] = "Culling Strike",
		}

		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			150% increased Armour
		]])
		build.itemsTab:AddDisplayItem()

		-- Baseline without transform
		runCallback("OnFrame")
		local baselineArmour = build.calcsTab.mainOutput.Armour or 0

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0

		-- The FLAG equivalency must be a no-op: armour unchanged, no double-inject.
		assert.is_near(baselineArmour, transformedArmour, 1)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: BASE delta with quality>0 scales bDelta by qualityMult", function()
		-- The Phase 3 formula for non-baseWasTransformed is:
		--   armData = round(armData * newIncFactor/oldIncFactor + bDelta * newIncFactor * qualityMult)
		-- With quality=20 (qualityMult=1.2), bDelta=25, no INC change:
		--   armourData before = round((132+25)*1.2) = round(188.4) = 188
		--   after = round(188*1 + 25*1*1.2) = round(188+30) = 218
		-- Without the qualityMult factor: round(188 + 25*1) = 213 (wrong).
		local origEquiv = data.modEquivalencies
		data.modEquivalencies = {
			["+25 to Armour"] = "+50 to Armour",
		}

		build.itemsTab:CreateDisplayItemFromRaw([[
			Rarity: Normal
			Titan Mitts
			Quality: 20
			--------
			+25 to Armour
		]])
		build.itemsTab:AddDisplayItem()

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		-- bDelta=25, qualityMult=1.2, newIncFactor=1: round(188 + 25*1*1.2) = 218
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0
		assert.is_near(218, transformedArmour, 2)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: cross-stat local defence equivalency is a no-op", function()
		-- A cross-name local defence equivalency (e.g. Armour INC → ArmourAndEvasion INC) cannot
		-- be decomposed: armData adjustment would require a stat-name change, and injecting the
		-- new mod globally would double-count the stat.  CalcPerform suppresses injection and
		-- leaves armourData unchanged.  The result must equal the pre-transform baseline.
		local origEquiv = data.modEquivalencies
		data.modEquivalencies = {
			["150% increased Armour"] = "200% increased Armour and Evasion Rating",
		}

		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			150% increased Armour
		]])
		build.itemsTab:AddDisplayItem()

		-- Baseline without transform: Armour = round(132*(1+1.5)) = 330
		runCallback("OnFrame")
		local baselineArmour = build.calcsTab.mainOutput.Armour or 0

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0

		-- Cross-name equivalency must be a no-op: armour unchanged.
		assert.is_near(baselineArmour, transformedArmour, 1)

		data.modEquivalencies = origEquiv
	end)

	it("GloveExplicitModTransform: old FLAG on matched line is not doubled when remapped to BASE/INC", function()
		-- When an old mod line has a FLAG mod and the equivalency maps it to pure
		-- BASE/INC, PoB has no mechanism to cancel a FLAG once set (FlagInternal checks
		-- value truthiness, not sign).  The onlyBaseOrINC gate on new mods is the
		-- defence: the old FLAG stays active unchanged, no new FLAG is injected.
		-- This test verifies: no crash, old FLAG still truthy (preserved, not doubled),
		-- and armour increases from the new GLOBAL INC that was injected.
		local origEquiv = data.modEquivalencies
		data.modEquivalencies = {
			["culling strike"] = "150% increased Armour",
		}

		build.itemsTab:CreateDisplayItemFromRaw([[
			New Item
			Titan Mitts
			culling strike
		]])
		build.itemsTab:AddDisplayItem()
		runCallback("OnFrame")
		local baseArmour = build.calcsTab.mainOutput.Armour or 0

		build.configTab.input.customMods = "\z
		their explicit modifiers are transformed into more powerful related modifiers\n\z
		"
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local transformedArmour = build.calcsTab.mainOutput.Armour or 0

		-- Old FLAG remains (cannot be cancelled); no new FLAG was injected (onlyBaseOrINC).
		local postTransformCull = build.calcsTab.mainEnv.modDB:Flag(nil, "CanCull")
		assert.is_truthy(postTransformCull)
		-- New GLOBAL INC was injected into modDB, so armour should increase.
		assert.is_true(transformedArmour > baseArmour,
			("expected transformed armour %d > base armour %d"):format(transformedArmour, baseArmour))

		data.modEquivalencies = origEquiv
	end)
end)
