describe("TradeHelpers trade hash matching", function()
	local tradeHelpers = LoadModule("Classes/TradeHelpers")

	---@param ids number[]
	---@param expected number
	---@return boolean contains whether the given array contains the expected id
	local function contains(ids, expected)
		for _, id in ipairs(ids) do
			if id == expected then return true end
		end
		return false
	end

	describe("modLineValue", function()
		it("returns the single number on a line", function()
			assert.equal(50, tradeHelpers.modLineValue("+50 to maximum Life"))
		end)

		it("returns the midpoint of a '# to #' range", function()
			assert.equal(15, tradeHelpers.modLineValue("Adds 10 to 20 Fire Damage"))
			assert.equal(12.5, tradeHelpers.modLineValue("Adds 10 to 15 Fire Damage"))
		end)

		it("handles negative numbers", function()
			assert.equal(-10, tradeHelpers.modLineValue("-10% to Fire Resistance"))
		end)

		it("returns nil when onlyFromTo is set and there is no range", function()
			assert.is_nil(tradeHelpers.modLineValue("+50 to maximum Life", true))
		end)
	end)

	describe("findTradeHash", function()
		it("matches a simple mod", function()
			local ids, value = tradeHelpers.findTradeHash("+50 to maximum Life")
			assert.equal(50, value)
			assert.is_true(contains(ids, HashStats({ "base_maximum_life" })))
		end)

		it("matches a percentage mod", function()
			local ids, value = tradeHelpers.findTradeHash("25% reduced maximum Energy Shield")
			assert.equal(25, value)
			assert.is_true(contains(ids, HashStats({ "maximum_energy_shield_+%" })))
		end)

		it("matches a # to #  mod", function()
			local ids, value = tradeHelpers.findTradeHash("Adds 5 to 15 Fire Damage")
			assert.equal(10, value)
			assert.is_true(contains(ids, HashStats({ "local_minimum_added_fire_damage", "local_maximum_added_fire_damage" })))
		end)

		it("returns no results for an unmatchable line", function()
			local ids = tradeHelpers.findTradeHash("+100 to IQ")
			assert.equal(0, #ids)
		end)

		it("works thrice in a row", function()
			local a = tradeHelpers.findTradeHash("+50 to maximum Life")
			local b = tradeHelpers.findTradeHash("+50 to maximum Life")
			local c = tradeHelpers.findTradeHash("+50 to maximum Life")
			assert.same(a, b)
			assert.same(b, c)
		end)
	end)
end)
