-- Headless smoke test: run the Advisor over a real, engine-calculated build to catch
-- nil-safety bugs that the crafted-fixture unit tests (spec/Modules/Advisor_spec.lua) miss.
describe("TestAdvisorSmoke", function()
	before_each(function()
		newBuild()
	end)

	it("returns a well-formed findings list for a real calculated build", function()
		runCallback("OnFrame")
		local Advisor = require("Modules/Advisor")
		local findings = Advisor.analyze(build)
		assert.are.equal("table", type(findings))
		for _, f in ipairs(findings) do
			assert.are.equal("string", type(f.id))
			assert.are.equal("string", type(f.title))
			assert.is_truthy(Advisor.severityRank[f.severity] ~= nil)
		end
	end)

	it("runs every check directly on real build data without erroring", function()
		runCallback("OnFrame")
		local Advisor = require("Modules/Advisor")
		local out = build.calcsTab.mainOutput
		assert.is_truthy(out)
		-- Call each check unguarded so a real-data crash fails the test. Advisor.analyze
		-- pcall-wraps checks, which would otherwise hide such a crash.
		for _, check in ipairs(Advisor.checks) do
			local findings = { }
			check(build, out, findings)
			for _, f in ipairs(findings) do
				assert.are.equal("string", type(f.id))
			end
		end
	end)
end)
