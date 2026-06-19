-- Path of Building
--
-- Module: Advisor Tab
-- Deterministic build-advisor tab. UI only — all rule logic lives in Modules/Advisor.lua.
--
local Advisor = LoadModule("Modules/Advisor")

local t_insert = table.insert
local s_format = string.format
local m_max = math.max
local m_min = math.min

local severityColor = {
	high = colorCodes.NEGATIVE,
	med = colorCodes.WARNING,
	low = colorCodes.NORMAL,
	info = "^8",
}
local SEVERITY_ORDER = { "high", "med", "low", "info" }
local SEVERITY_LABEL = { high = "High", med = "Med", low = "Low", info = "Info" }
local ROW_HEIGHT = 34
local HEADER_HEIGHT = 20
local BODY_TOP = 96

local AdvisorTabClass = newClass("AdvisorTab", "ControlHost", "Control", function(self, build)
	self.ControlHost()
	self.Control()

	self.build = build
	self.findings = { }
	self.highCount = 0
	self.scrollOffset = 0
	self.collapsed = { }
	self.filter = { high = true, med = true, low = true, info = true }
	self.lastOutput = false

	self.controls.title = new("LabelControl", {"TOPLEFT",self,"TOPLEFT"}, {8, 8, 0, 20}, "^7Advisor")
	self.controls.refresh = new("ButtonControl", {"TOPLEFT",self.controls.title,"TOPLEFT"}, {0, 26, 80, 20}, "Refresh", function()
		self:Refresh()
	end)
	self.controls.highOnly = new("ButtonControl", {"LEFT",self.controls.refresh,"RIGHT"}, {8, 0, 90, 20}, "High only", function()
		self.filter.high, self.filter.med, self.filter.low, self.filter.info = true, false, false, false
		self:SyncFilterControls()
	end)
	self.controls.showAll = new("ButtonControl", {"LEFT",self.controls.highOnly,"RIGHT"}, {8, 0, 70, 20}, "Show all", function()
		self.filter.high, self.filter.med, self.filter.low, self.filter.info = true, true, true, true
		self:SyncFilterControls()
	end)

	local prev = nil
	for _, sev in ipairs(SEVERITY_ORDER) do
		local cb = new("CheckBoxControl", prev and {"LEFT",prev,"RIGHT"} or {"TOPLEFT",self.controls.refresh,"BOTTOMLEFT"}, prev and {70, 0, 18} or {10, 8, 18}, severityColor[sev]..SEVERITY_LABEL[sev], function(state)
			self.filter[sev] = state and true or false
		end, nil, self.filter[sev])
		self.controls["filter_"..sev] = cb
		prev = cb
	end
end)

function AdvisorTabClass:SyncFilterControls()
	for _, sev in ipairs(SEVERITY_ORDER) do
		local cb = self.controls["filter_"..sev]
		if cb then cb.state = self.filter[sev] end
	end
end

function AdvisorTabClass:Refresh()
	self.findings = Advisor.analyze(self.build) or { }
	local high = 0
	for _, f in ipairs(self.findings) do
		if f.severity == "high" then high = high + 1 end
	end
	self.highCount = high
end

-- Group filtered findings by category, preserving the global severity sort order.
function AdvisorTabClass:GroupFindings()
	local order = { }
	local groups = { }
	for _, f in ipairs(self.findings) do
		if self.filter[f.severity] then
			local cat = f.category or "Other"
			if not groups[cat] then
				groups[cat] = { }
				t_insert(order, cat)
			end
			t_insert(groups[cat], f)
		end
	end
	return order, groups
end

function AdvisorTabClass:Draw(viewPort, inputEvents)
	self.x = viewPort.x
	self.y = viewPort.y
	self.width = viewPort.width
	self.height = viewPort.height

	-- Auto-refresh when the engine output changes (a new mainOutput table).
	local out = self.build.calcsTab and self.build.calcsTab.mainOutput
	if out ~= self.lastOutput then
		self.lastOutput = out
		self:Refresh()
	end

	self:ProcessControlsInput(inputEvents, viewPort)

	main:DrawBackground(viewPort)
	self:DrawControls(viewPort)

	local x = viewPort.x + 12
	local bodyTop = viewPort.y + BODY_TOP
	local bodyBottom = viewPort.y + viewPort.height - 8

	if not out then
		DrawString(x, bodyTop, "LEFT", 16, "VAR", "^7Build not calculated yet.")
		return
	end
	if #self.findings == 0 then
		DrawString(x, bodyTop, "LEFT", 16, "VAR", "^7No issues found.")
		return
	end

	local order, groups = self:GroupFindings()

	local layout = { }
	local y = bodyTop - self.scrollOffset
	for _, cat in ipairs(order) do
		local list = groups[cat]
		t_insert(layout, { kind = "header", cat = cat, count = #list, y = y })
		y = y + HEADER_HEIGHT
		if not self.collapsed[cat] then
			for _, f in ipairs(list) do
				t_insert(layout, { kind = "row", finding = f, y = y })
				y = y + ROW_HEIGHT
			end
		end
	end
	local maxScroll = m_max(0, (y + self.scrollOffset) - bodyBottom)

	for _, event in ipairs(inputEvents) do
		if event.type == "KeyUp" then
			if event.key == "WHEELUP" then
				self.scrollOffset = m_max(0, self.scrollOffset - 40)
			elseif event.key == "WHEELDOWN" then
				self.scrollOffset = m_min(maxScroll, self.scrollOffset + 40)
			elseif event.key == "LEFTBUTTON" then
				local cx, cy = GetCursorPos()
				local right = viewPort.x + viewPort.width
				for _, item in ipairs(layout) do
					if item.kind == "header" and cx >= x and cx < right and cy >= item.y and cy < item.y + HEADER_HEIGHT then
						self.collapsed[item.cat] = not self.collapsed[item.cat]
						break
					elseif item.kind == "row" and cx >= x and cx < right and cy >= item.y and cy < item.y + ROW_HEIGHT then
						local jump = item.finding.jump
						if jump and jump.mode then
							self.build.viewMode = jump.mode
						end
						break
					end
				end
			end
		end
	end

	for _, item in ipairs(layout) do
		if item.y >= bodyTop - ROW_HEIGHT and item.y <= bodyBottom then
			if item.kind == "header" then
				local marker = self.collapsed[item.cat] and "[+]" or "[-]"
				DrawString(x, item.y, "LEFT", 18, "VAR BOLD", s_format("^7%s %s (%d)", marker, item.cat, item.count))
			else
				local f = item.finding
				local color = severityColor[f.severity] or "^7"
				DrawString(x + 8, item.y, "LEFT", 16, "VAR BOLD", s_format("%s[%s] %s", color, SEVERITY_LABEL[f.severity] or f.severity, f.title or ""))
				if f.detail then
					DrawString(x + 24, item.y + 15, "LEFT", 12, "VAR", "^7" .. f.detail)
				end
			end
		end
	end
end
