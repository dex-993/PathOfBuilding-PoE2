-- Path of Building
--
-- Module: Tree Tab
-- Passive skill tree tab for the current build.
--
local ipairs = ipairs
local pairs = pairs
local next = next
local t_insert = table.insert
local t_remove = table.remove
local t_sort = table.sort
local t_concat = table.concat
local m_max = math.max
local m_min = math.min
local m_floor = math.floor
local m_abs = math.abs
local s_format = string.format
local s_gsub = string.gsub
local s_byte = string.byte
local dkjson = require "dkjson"

-- Helper function to find toast index by content pattern
-- TODO: remove this when when we can control toast notifications better
local function findToastIndex(pattern)
	for i, msg in ipairs(main.toastMessages) do
		if msg:match(pattern) then
			return i
		end
	end
	return nil
end

local TreeTabClass = newClass("TreeTab", "ControlHost", function(self, build)
	self.ControlHost()

	self.build = build
	self.isComparing = false;
	self.isCustomMaxDepth = false;

	self.viewer = new("PassiveTreeView")

	self.specList = { }
	self.specList[1] = new("PassiveSpec", build, latestTreeVersion)
	self:SetActiveSpec(1)
	self:SetCompareSpec(1)

	self.anchorControls = new("Control", nil, {0, 0, 0, 20})

	-- Tree list dropdown
	self.controls.specSelect = new("DropDownControl", { "LEFT",self.anchorControls,"RIGHT" }, { 0, 0, 190, 20 }, nil, function(index, value)
		if self.specList[index] then
			self.build.modFlag = true
			self:SetActiveSpec(index)
		else
			self:OpenSpecManagePopup()
		end
	end)
	self.controls.specSelect.maxDroppedWidth = 1000
	self.controls.specSelect.enableDroppedWidth = true
	self.controls.specSelect.enableChangeBoxWidth = true
	self.controls.specSelect.controls.scrollBar.enabled = true
	self.controls.specSelect.tooltipFunc = function(tooltip, mode, selIndex, selVal)
		tooltip:Clear()
		if mode ~= "OUT" then
			local spec = self.specList[selIndex]
			if spec then
				local used, ascUsed, secondaryAscUsed, sockets = spec:CountAllocNodes()
				tooltip:AddLine(16, "Class: "..spec.curClassName)
				tooltip:AddLine(16, "Ascendancy: "..spec.curAscendClassName)
				tooltip:AddLine(16, "Points used: "..used)
				if sockets > 0 then
					tooltip:AddLine(16, "Jewel sockets: "..sockets)
				end
				if selIndex ~= self.activeSpec then
					local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator()
					if calcFunc then
						local output = calcFunc({ spec = spec })
						self.build:AddStatComparesToTooltip(tooltip, calcBase, output, "^7Switching to this tree will give you:")
					end
					if spec.curClassId == self.build.spec.curClassId then
						local respec = 0
						local respecAscendancy = 0
						for nodeId, node in pairs(self.build.spec.allocNodes) do
							-- Assumption: Nodes >= 65536 are small cluster passives.
							if node.type ~= "ClassStart" and node.type ~= "AscendClassStart"
							and (self.build.spec.tree.clusterNodeMap[node.dn] == nil or node.isKeystone or node.isJewelSocket) and nodeId < 65536
							and not spec.allocNodes[nodeId] then
								if node.ascendancyName then
									respecAscendancy = respecAscendancy + 1
								else
									respec = respec + 1
								end
							end
						end
						if respec > 0 or respecAscendancy > 0 then
							local goldCost = data.goldRespecPrices[build.characterLevel]
							local totalGold = (respec * goldCost) + (respecAscendancy * goldCost * 5)
							local goldStr = formatNumSep(tostring(totalGold))
							tooltip:AddLine(16, "^xFFD700" .. goldStr .. " Gold ^7required to switch to this tree.")
							if respec > 0 then
								local nodeWord = respec == 1 and "Passive node to be refunded" or "Passive nodes to be refunded"
								tooltip:AddLine(16, s_format("^7\t%d %s.", respec, nodeWord))
							end
							if respecAscendancy > 0 then
								local ascendWord = respecAscendancy == 1 and "Ascendancy node to be refunded" or "Ascendancy nodes to be refunded"
								tooltip:AddLine(16, s_format("^7\t%d %s.", respecAscendancy, ascendWord))
							end
						end
					end
				end
				tooltip:AddLine(16, "^7Game Version: "..treeVersions[spec.treeVersion].display)
			end
		end
	end

	-- Compare checkbox
	self.controls.compareCheck = new("CheckBoxControl", { "LEFT", self.controls.specSelect, "RIGHT" }, { 74, 0, 20 }, "Compare:", function(state)
		self.isComparing = state
		self:SetCompareSpec(self.activeCompareSpec)
		self.controls.compareSelect.shown = state
		if state then
			self.controls.reset:SetAnchor("LEFT", self.controls.compareSelect, "RIGHT", nil, nil, nil)
		else
			self.controls.reset:SetAnchor("LEFT", self.controls.compareCheck, "RIGHT", nil, nil, nil)
		end
	end)

	-- Compare tree dropdown
	self.controls.compareSelect = new("DropDownControl", { "LEFT", self.controls.compareCheck, "RIGHT" }, { 8, 0, 190, 20 }, nil, function(index, value)
		if self.specList[index] then
			self:SetCompareSpec(index)
		else
			self:OpenSpecManagePopup()
		end
	end)
	self.controls.compareSelect.shown = false
	self.controls.compareSelect.maxDroppedWidth = 1000
	self.controls.compareSelect.enableDroppedWidth = true
	self.controls.compareSelect.enableChangeBoxWidth = true
	self.controls.reset = new("ButtonControl", { "LEFT", self.controls.compareCheck, "RIGHT" }, { 8, 0, 100, 20 }, "Reset Tree", function()
		local controls = { }
		local buttonY = 65
		controls.warningLabel = new("LabelControl", nil, { 0, 30, 0, 16 }, "^7Warning: resetting your passive tree cannot be undone.\n")
		controls.reset = new("ButtonControl", nil, { -65, buttonY, 100, 20 }, "Reset", function()
			wipeTable(self.build.spec.hashOverrides) -- reset attribute nodes to "Attribute"
			self.build.spec:ResetNodes()
			self.build.spec:BuildAllDependsAndPaths()
			self.build.spec:AddUndoState()
			self.build.buildFlag = true
			main:ClosePopup()
		end)
		controls.cancel = new("ButtonControl", nil, { 65, buttonY, 100, 20 }, "Cancel", function()
			main:ClosePopup()
		end)
		main:OpenPopup(470, 100, "Reset Tree", controls, nil, "edit", "cancel")
	end)

	-- Tree Version Dropdown
	self.treeVersions = { }
	for _, num in ipairs(treeVersionList) do
		local value = {
			label = treeVersions[num].display,
			value = num
		}
		t_insert(self.treeVersions, value)
	end
	self.controls.versionText = new("LabelControl", { "LEFT", self.controls.reset, "RIGHT" }, { 8, 0, 0, 16 }, "Version:")
	self.controls.versionSelect = new("DropDownControl", { "LEFT", self.controls.versionText, "RIGHT" }, { 8, 0, 60, 20 }, self.treeVersions, function(index, selected)
		if selected.value ~= self.build.spec.treeVersion then
			self:OpenVersionConvertPopup(selected.value, true)
		end
	end)
	self.controls.versionSelect.maxDroppedWidth = 1000
	self.controls.versionSelect.enableDroppedWidth = true
	self.controls.versionSelect.enableChangeBoxWidth = true
	self.controls.versionSelect.selIndex = #self.treeVersions

	-- Tree Search Textbox
	self.controls.treeSearch = new("EditControl", { "LEFT", self.controls.versionSelect, "RIGHT" }, { 8, 0, main.portraitMode and 200 or 300, 20 }, "", "Search", "%c", 100, function(buf)
		self.viewer.searchStr = buf
		self.searchFlag = buf ~= self.viewer.searchStrSaved
	end, nil, nil, true)
	self.controls.treeSearch.tooltipText = "Uses Lua pattern matching for complex searches.\nPrefix your search with \"oil:\" to search by anoint recipe.\nTo search for multiple terms: (increased.fire.damage|increased.area.of.effect|etc)"

	self.tradeLeaguesList = { }
	-- Find Timeless Jewel Button
	-- Add button back if/when we figure out how to search for them again
	--self.controls.findTimelessJewel = new("ButtonControl", { "LEFT", self.controls.treeSearch, "RIGHT" }, { 8, 0, 150, 20 }, "Find Timeless Jewel", function()
		--self:FindTimelessJewel()
	--end)

	-- Show Node Power Checkbox
	self.controls.treeHeatMap = new("CheckBoxControl", { "LEFT", self.controls.treeSearch, "RIGHT" }, { 130, 0, 20 }, "Show Node Power:", function(state)
		self.viewer.showHeatMap = state
		self.controls.treeHeatMapStatSelect.shown = state

		if state == false then
			self.controls.powerReportList.shown = false 
		end
	end)

	-- Control for setting max node depth to limit calculation time of the heat map
	self.controls.nodePowerMaxDepthSelect = new("DropDownControl", { "LEFT", self.controls.treeHeatMap, "RIGHT" }, { 8, 0, 55, 20 }, { "All", 5, 10, 15, "Custom" }, function(index, value)
		-- Show custom value control and resize/move elements
		self.isCustomMaxDepth = value == "Custom"
		if self.isCustomMaxDepth then
			self.controls.nodePowerMaxDepthSelect.width = 70
			self.controls.nodePowerMaxDepthCustom.shown = true
			self.controls.treeHeatMapStatSelect:SetAnchor("LEFT", self.controls.nodePowerMaxDepthCustom, "RIGHT", nil, nil, nil)
			return
		end

		self.controls.nodePowerMaxDepthSelect.width = 55
		self.controls.nodePowerMaxDepthCustom.shown = false
		self.controls.treeHeatMapStatSelect:SetAnchor("LEFT", self.controls.nodePowerMaxDepthSelect, "RIGHT", nil, nil, nil)

		local oldMax = self.build.calcsTab.nodePowerMaxDepth

		if type(value) == "number" then
			self.build.calcsTab.nodePowerMaxDepth = value
		else
			self.build.calcsTab.nodePowerMaxDepth = nil
		end

		-- If the heat map is shown, tell it to recalculate
		-- if the new value is larger than the old
		if oldMax ~= value and self.viewer.showHeatMap then
			if oldMax ~= nil and (self.build.calcsTab.nodePowerMaxDepth == nil or self.build.calcsTab.nodePowerMaxDepth > oldMax) then
				self:SetPowerCalc(self.build.calcsTab.powerStat)
			end
		end
	end)
	self.controls.nodePowerMaxDepthSelect.tooltipText = "Limit of Node distance to search (lower = faster)"

	-- Control for setting max node depth by custom value
	self.controls.nodePowerMaxDepthCustom = new("EditControl", { "LEFT", self.controls.nodePowerMaxDepthSelect, "RIGHT" }, { 8, 0, 70, 20 }, "0", nil, "%D", nil, function(value)
		self.build.calcsTab.nodePowerMaxDepth = tonumber(value)

		-- If the heat map is shown, recalculate it with new value
		if self.viewer.showHeatMap then
			self:SetPowerCalc(self.build.calcsTab.powerStat)
		end
	end)
	self.controls.nodePowerMaxDepthCustom.shown = false

	-- Control for selecting the power stat to sort by (Defense, DPS, etc)
	self.controls.treeHeatMapStatSelect = new("DropDownControl", { "LEFT", self.controls.nodePowerMaxDepthSelect, "RIGHT" }, { 8, 0, 150, 20 }, nil, function(index, value)
		self:SetPowerCalc(value)
	end)
	self.controls.treeHeatMap.tooltipText = function()
		local offCol, defCol = main.nodePowerTheme:match("(%a+)/(%a+)")
		return "When enabled, an estimate of the offensive and defensive strength of\neach unallocated passive is calculated and displayed visually.\nOffensive power shows as "..offCol:lower()..", defensive power as "..defCol:lower().."."
	end

	self.powerStatList = { }
	for _, stat in ipairs(data.powerStatList) do
		if not stat.ignoreForNodes then
			t_insert(self.powerStatList, stat)
		end
	end

	-- Show/Hide Power Report Button
	self.controls.powerReport = new("ButtonControl", { "LEFT", self.controls.treeHeatMapStatSelect, "RIGHT" }, { 8, 0, 150, 20 },
		function() return self.controls.powerReportList.shown and "Hide Power Report" or "Show Power Report" end, function()
		self.controls.powerReportList.shown = not self.controls.powerReportList.shown
	end)

	-- Auto Allocate Tree Button
	self.controls.autoAllocate = new("ButtonControl", { "LEFT", self.controls.powerReport, "RIGHT" }, { 8, 0, 100, 20 }, "Auto Allocate Tree", function()
		self:AutoAllocateTree()
	end)

	-- Remove Worst Node Button
	self.controls.removeWorstNode = new("ButtonControl", { "LEFT", self.controls.autoAllocate, "RIGHT" }, { 8, 0, 100, 20 }, "Remove Worst Node", function()
		self:RemoveWorstAllocatedNode()
	end)

	-- Auto Allocate Jewels Button
	self.controls.autoAllocateJewels = new("ButtonControl", { "LEFT", self.controls.removeWorstNode, "RIGHT" }, { 8, 0, 100, 20 }, "Auto Allocate Jewels", function()
		self:AutoAllocateJewels()
	end)


	-- Power Report List
	local yPos = self.controls.treeHeatMap.y == 0 and self.controls.specSelect.height + 4 or self.controls.specSelect.height * 2 + 8
	self.controls.powerReportList = new("PowerReportListControl", { "TOPLEFT", self.controls.specSelect, "BOTTOMLEFT" }, { 0, yPos, 700, 170 }, function(selectedNode)
		-- this code is called by the list control when the user "selects" one of the passives in the list.
		-- we use this to set a flag which causes the next Draw() to recenter the passive tree on the desired node.
		if selectedNode.x then
			self.jumpToNode = true
			self.jumpToX = selectedNode.x
			self.jumpToY = selectedNode.y
		end
	end)
	self.controls.powerReportList.shown = false
	-- Progress callback from the CalcsTab power builder coroutine
	self.powerBuilderToastActive = false
	self.lastProgressToastUpdate = 0
	self.build.powerBuilderProgressCallback = function(percent)
		local now = GetTime()
		if now - self.lastProgressToastUpdate < 100 then
			return
		end

		local message = percent and string.format("Building Power Report... (%d%%)", percent) or "Building Power Report..."

		self.controls.powerReportList.label = message
		self.lastProgressToastUpdate = now
		local toastIndex = findToastIndex("^Building Power Report")
		if toastIndex then
			main.toastMessages[toastIndex] = message
		else
			t_insert(main.toastMessages, message)
			self.powerBuilderToastActive = true
		end
	end
	-- Completion callback from the CalcsTab power builder coroutine
	self.build.powerBuilderCallback = function()
		local powerStat = self.build.calcsTab.powerStat or data.powerStatList[1]
		local report = self:BuildPowerReportList(powerStat)
		self.controls.powerReportList:SetReport(powerStat, report)
		local toastIndex = findToastIndex("^Building Power Report")
		if self.powerBuilderToastActive and toastIndex then
			-- Remove the toast from the queue instead of triggering hide animation
			-- This prevents issues when the toast is not currently displayed (queued behind another toast)
			-- TODO: look into allowing toast notifications to stack and have UUID's we can control them better
			if toastIndex == 1 then
				main.toastMode = "HIDING"
				main.toastStart = GetTime()
			else
				t_remove(main.toastMessages, toastIndex)
			end
		end
		self.powerBuilderToastActive = false
	end

	self.controls.specConvertText = new("LabelControl", { "BOTTOMLEFT", self.controls.specSelect, "TOPLEFT" }, { 0, -14, 0, 16 }, "^7This is an older tree version, which may not be fully compatible with the current game version.")
	self.controls.specConvertText.shown = function()
		return self.showConvert
	end
	local function getLatestTreeVersion()
		return latestTreeVersion .. (self.specList[self.activeSpec].treeVersion:match("^" .. latestTreeVersion .. "(.*)") or "")
	end
	local function buildConvertButtonLabel()
		return colorCodes.POSITIVE.."Convert to "..treeVersions[getLatestTreeVersion()].display
	end
	local function buildConvertAllButtonLabel()
		return colorCodes.POSITIVE.."Convert all trees to "..treeVersions[getLatestTreeVersion()].display
	end
	self.controls.specConvert = new("ButtonControl", { "LEFT", self.controls.specConvertText, "RIGHT" }, { 8, 0, function() return DrawStringWidth(16, "VAR", buildConvertButtonLabel()) + 20 end, 20 }, buildConvertButtonLabel, function()
		self:ConvertToVersion(getLatestTreeVersion(), false, true)
	end)
	self.controls.specConvertAll = new("ButtonControl", { "LEFT", self.controls.specConvert, "RIGHT" }, { 8, 0, function() return DrawStringWidth(16, "VAR", buildConvertAllButtonLabel()) + 20 end, 20 }, buildConvertAllButtonLabel, function()
		self:OpenVersionConvertAllPopup(getLatestTreeVersion())
	end)
	self.jumpToNode = false
	self.jumpToX = 0
	self.jumpToY = 0
end)

function TreeTabClass:Draw(viewPort, inputEvents)
	self.anchorControls.x = viewPort.x + 4
	self.anchorControls.y = viewPort.y + viewPort.height - 24

	for id, event in ipairs(inputEvents) do
		if event.type == "KeyDown" then
			if event.key == "z" and IsKeyDown("CTRL") then
				self.build.spec:Undo()
				self.build.buildFlag = true
				inputEvents[id] = nil
			elseif event.key == "y" and IsKeyDown("CTRL") then
				self.build.spec:Redo()
				self.build.buildFlag = true
				inputEvents[id] = nil
			elseif event.key == "UP" then
				local index = self.activeSpec - 1
				if self.specList[index] and not self.controls.specSelect:IsMouseOver() and not self.controls.specSelect.dropped then
					self.build.modFlag = true
					self:SetActiveSpec(index)
				end
			elseif event.key == "DOWN" and not self.controls.specSelect:IsMouseOver() and not self.controls.specSelect.dropped then
				local index = self.activeSpec + 1
				if self.specList[index] then
					self.build.modFlag = true
					self:SetActiveSpec(index)
				end
			elseif event.key == "f" and IsKeyDown("CTRL") then
				self:SelectControl(self.controls.treeSearch)
			elseif event.key == "m" and IsKeyDown("CTRL") then
				self:OpenSpecManagePopup()
			end
		end
	end
	self:ProcessControlsInput(inputEvents, viewPort)

	-- Determine positions if one line of controls doesn't fit in the screen width
	local linesHeight = 24
	local rightMargin = 10
	local widthFirstLineControls = self.controls.specSelect.width + 8
								+ self.controls.compareCheck.width + self.controls.compareCheck.x
								+ self.controls.reset.width + self.controls.reset.x
								+ self.controls.versionText.width() + self.controls.versionText.x
								+ self.controls.versionSelect.width + self.controls.versionSelect.x
								+ (self.isComparing and (self.controls.compareSelect.width + self.controls.compareSelect.x) or 0)

	local widthSecondLineControls = self.controls.treeSearch.width + 8
									--+ self.controls.findTimelessJewel.width + self.controls.findTimelessJewel.x
									+ self.controls.treeHeatMap.width + 130
									+ self.controls.nodePowerMaxDepthSelect.width + self.controls.nodePowerMaxDepthSelect.x
									+ (self.isCustomMaxDepth and (self.controls.nodePowerMaxDepthCustom.width + self.controls.nodePowerMaxDepthCustom.x) or 0)
									+ (self.viewer.showHeatMap and (self.controls.treeHeatMapStatSelect.width + self.controls.treeHeatMapStatSelect.x
																					+ self.controls.powerReport.width + self.controls.powerReport.x) or 0)
									+ self.controls.autoAllocate.width + self.controls.autoAllocate.x
									+ self.controls.removeWorstNode.width + self.controls.removeWorstNode.x
									+ self.controls.autoAllocateJewels.width + self.controls.autoAllocateJewels.x

	-- Check first line
	if viewPort.width >= widthFirstLineControls + widthSecondLineControls + rightMargin then
		linesHeight = 0
		self.controls.treeSearch:SetAnchor("LEFT", self.controls.versionSelect, "RIGHT", 8, 0)
		self.controls.powerReportList:SetAnchor("TOPLEFT", self.controls.specSelect, "BOTTOMLEFT", 0, self.controls.specSelect.height + 6)
	else
		self.controls.treeSearch:SetAnchor("TOPLEFT", self.controls.specSelect, "BOTTOMLEFT", 0, 4)
		self.controls.powerReportList:SetAnchor("TOPLEFT", self.controls.treeSearch, "BOTTOMLEFT", 0, self.controls.treeSearch.height + 6)
	end

	-- Check second line
	-- Revert comments if we add back find Timeless Jewel function
	if viewPort.width >= widthSecondLineControls + rightMargin then
		self.controls.treeHeatMap:SetAnchor("LEFT", self.controls.treeSearch, "RIGHT", 130, 0)
	else
		linesHeight = linesHeight * 2
		self.controls.treeHeatMap:SetAnchor("TOPLEFT", self.controls.treeSearch, "BOTTOMLEFT", 124, 4)
		self.controls.powerReportList:SetAnchor("TOPLEFT", self.controls.treeHeatMap, "BOTTOMLEFT", -124, self.controls.treeHeatMap.height + 6)
	end

	-- determine positions for convert line of controls
	local convertTwoLineHeight = 24
	local convertMaxWidth = 900
	if viewPort.width >= convertMaxWidth then
		convertTwoLineHeight = 0
		self.controls.specConvert:SetAnchor("LEFT", self.controls.specConvertText, "RIGHT", 8, 0)
		self.controls.specConvertText:SetAnchor("BOTTOMLEFT", self.controls.specSelect, "TOPLEFT", 0, -14)
	else
		self.controls.specConvert:SetAnchor("TOPLEFT", self.controls.specConvertText, "BOTTOMLEFT", 0, 4)
		self.controls.specConvertText:SetAnchor("BOTTOMLEFT", self.controls.specSelect, "TOPLEFT", 0, -38)
	end

	local bottomDrawerHeight = self.controls.powerReportList.shown and 194 or 0
	self.controls.specSelect.y = -bottomDrawerHeight - linesHeight

	local treeViewPort = { x = viewPort.x, y = viewPort.y, width = viewPort.width, height = viewPort.height - (self.showConvert and 64 + bottomDrawerHeight + linesHeight or 32 + bottomDrawerHeight + linesHeight)}
	if self.jumpToNode then
		self.viewer:Focus(self.jumpToX, self.jumpToY, treeViewPort, self.build)
		self.jumpToNode = false
	end
	self.viewer.compareSpec = self.isComparing and self.specList[self.activeCompareSpec] or nil
	self.viewer:Draw(self.build, treeViewPort, inputEvents)

	local newSpecList = self:GetSpecList()
	self.controls.compareSelect.selIndex = self.activeCompareSpec
	self.controls.compareSelect:SetList(newSpecList)
	t_insert(newSpecList, "Manage trees... (ctrl-m)")
	self.controls.specSelect.selIndex = self.activeSpec
	self.controls.specSelect:SetList(newSpecList)

	if not self.controls.treeSearch.hasFocus then
		self.controls.treeSearch:SetText(self.viewer.searchStr)
	end

	self.controls.treeHeatMap.state = self.viewer.showHeatMap
	self.controls.treeHeatMapStatSelect.shown = self.viewer.showHeatMap
	self.controls.treeHeatMapStatSelect.list = self.powerStatList
	self.controls.treeHeatMapStatSelect.selIndex = 1
	self.controls.treeHeatMapStatSelect:CheckDroppedWidth(true)
	if self.build.calcsTab.powerStat then
		self.controls.treeHeatMapStatSelect:SelByValue(self.build.calcsTab.powerStat.stat, "stat")
	end

	SetDrawLayer(1)

	SetDrawColor(0.05, 0.05, 0.05)
	DrawImage(nil, viewPort.x, viewPort.y + viewPort.height - (28 + bottomDrawerHeight + linesHeight), viewPort.width, 28 + bottomDrawerHeight + linesHeight)
	if self.showConvert then
		local height = viewPort.width < convertMaxWidth and (bottomDrawerHeight + linesHeight) or 0
		SetDrawColor(0.05, 0.05, 0.05)
		DrawImage(nil, viewPort.x, viewPort.y + viewPort.height - (60 + bottomDrawerHeight + linesHeight + convertTwoLineHeight), viewPort.width, 28 + height)
		SetDrawColor(0.85, 0.85, 0.85)
		DrawImage(nil, viewPort.x, viewPort.y + viewPort.height - (64 + bottomDrawerHeight + linesHeight + convertTwoLineHeight), viewPort.width, 4)
	end
	-- let white lines overwrite the black sections, regardless of showConvert
	SetDrawColor(0.85, 0.85, 0.85)
	DrawImage(nil, viewPort.x, viewPort.y + viewPort.height - (32 + bottomDrawerHeight + linesHeight), viewPort.width, 4)

	-- Resume auto-allocate coroutine and manage button states
	local progress = self.build.autoAllocateProgress
	if self.build.autoAllocateBuilder then
		self:ResumeAutoAllocate()
		self.controls.autoAllocate.enabled = false
		self.controls.autoAllocate.label = progress or "Working..."
		if IsKeyDown("ESCAPE") and self.build.autoAllocateBuilder then
			self.build.autoAllocateProgress = nil
			self.build.autoAllocateBuilder = nil
			self.controls.autoAllocate.enabled = true
			self.controls.autoAllocate.label = "Auto Allocate Tree"
		end
	else
		self.controls.autoAllocate.enabled = true
		self.controls.autoAllocate.label = "Auto Allocate Tree"
	end

	-- Resume auto-allocate jewels coroutine
	local jewelsProgress = self.build.autoAllocateJewelsProgress
	if self.build.autoAllocateJewelsBuilder then
		self:ResumeAutoAllocateJewels()
		self.controls.autoAllocateJewels.enabled = false
		self.controls.autoAllocateJewels.label = jewelsProgress or "Working..."
		if IsKeyDown("ESCAPE") and self.build.autoAllocateJewelsBuilder then
			self.build.autoAllocateJewelsProgress = nil
			self.build.autoAllocateJewelsBuilder = nil
			self.controls.autoAllocateJewels.enabled = true
			self.controls.autoAllocateJewels.label = "Auto Allocate Jewels"
		end
	else
		self.controls.autoAllocateJewels.enabled = true
		self.controls.autoAllocateJewels.label = "Auto Allocate Jewels"
	end


	self:DrawControls(viewPort)
end

function TreeTabClass:GetSpecList()
	local newSpecList = { }
	for _, spec in ipairs(self.specList) do
		t_insert(newSpecList, (spec.treeVersion ~= latestTreeVersion and ("["..treeVersions[spec.treeVersion].display.."] ") or "")..(spec.title or "Default"))
	end
	return newSpecList
end

function TreeTabClass:Load(xml, dbFileName)
	self.specList = { }
	if xml.elem == "Spec" then
		-- Import single spec from old build
		self.specList[1] = new("PassiveSpec", self.build, defaultTreeVersion)
		self.specList[1]:Load(xml, dbFileName)
		self.activeSpec = 1
		self.build.spec = self.specList[1]
		return
	end
	for _, node in pairs(xml) do
		if type(node) == "table" then
			if node.elem == "Spec" then
				if node.attrib.treeVersion and not treeVersions[node.attrib.treeVersion] then
					main:OpenMessagePopup("Unknown Passive Tree Version", "The build you are trying to load uses an unrecognised version of the passive skill tree.\nYou may need to update the program before loading this build.")
					return true
				end
				local newSpec = new("PassiveSpec", self.build, node.attrib.treeVersion or defaultTreeVersion)
				newSpec:Load(node, dbFileName)
				t_insert(self.specList, newSpec)
			end
		end
	end
	if not self.specList[1] then
		self.specList[1] = new("PassiveSpec", self.build, latestTreeVersion)
	end
	self:SetActiveSpec(tonumber(xml.attrib.activeSpec) or 1)
end

function TreeTabClass:PostLoad()
	for _, spec in ipairs(self.specList) do
		spec:PostLoad()
	end
end

function TreeTabClass:Save(xml)
	xml.attrib = {
		activeSpec = tostring(self.activeSpec)
	}
	for specId, spec in ipairs(self.specList) do
		local child = {
			elem = "Spec"
		}
		spec:Save(child)
		t_insert(xml, child)
	end
end

function TreeTabClass:SetActiveSpec(specId)
	local prevSpec = self.build.spec
	self.activeSpec = m_min(specId, #self.specList)
	local curSpec = self.specList[self.activeSpec]
	data.setJewelRadiiGlobally(curSpec.treeVersion)
	self.build.spec = curSpec
	self.build.buildFlag = true
	self.build.spec:SetWindowTitleWithBuildClass()
	self.build:UpdateClassDropdowns(curSpec.treeVersion)
	for _, slot in pairs(self.build.itemsTab.slots) do
		if slot.nodeId then
			if prevSpec then
				-- Update the previous spec's jewel for this slot
				prevSpec.jewels[slot.nodeId] = slot.selItemId
			end
			if curSpec.jewels[slot.nodeId] then
				-- Socket the jewel for the new spec
				slot.selItemId = curSpec.jewels[slot.nodeId]
			else
				-- Unsocket the old jewel from the previous spec
				slot.selItemId = 0
			end
		end
	end
	self.showConvert = not curSpec.treeVersion:match("^" .. latestTreeVersion)
	if self.build.itemsTab.itemOrderList[1] then
		-- Update item slots if items have been loaded already
		self.build.itemsTab:PopulateSlots()
	end
	-- Update the passive tree dropdown control in itemsTab
	self.build.itemsTab.controls.specSelect.selIndex = specId
	-- Update Version dropdown to active spec's
	if self.controls.versionSelect then
		self.controls.versionSelect:SelByValue(curSpec.treeVersion, 'value')
	end
	self.build:SyncLoadouts()
end

function TreeTabClass:SetCompareSpec(specId)
	self.activeCompareSpec = m_min(specId, #self.specList)
	local curSpec = self.specList[self.activeCompareSpec]

	self.compareSpec = curSpec
end

function TreeTabClass:ConvertToVersion(version, remove, success, ignoreRuthlessCheck)
	if not ignoreRuthlessCheck and self.build.spec.treeVersion:match("ruthless") and not version:match("ruthless") then
		if isValueInTable(treeVersionList, version.."_ruthless") then
			version = version.."_ruthless"
		end
	end
	local newSpec = new("PassiveSpec", self.build, version)
	newSpec.title = self.build.spec.title
	newSpec.jewels = copyTable(self.build.spec.jewels)
	newSpec:RestoreUndoState(self.build.spec:CreateUndoState(), version)
	newSpec:BuildClusterJewelGraphs()
	t_insert(self.specList, self.activeSpec + 1, newSpec)
	if remove then
		t_remove(self.specList, self.activeSpec)
		-- activeSpec + 1 is shifted down one on remove, otherwise we would set the spec below it if it exists
		self:SetActiveSpec(self.activeSpec)
	else
		self:SetActiveSpec(self.activeSpec + 1)
	end
	self.modFlag = true
	if success then
		main:OpenMessagePopup("Tree Converted", "The tree has been converted to "..treeVersions[version].display..".\nNote that some or all of the passives may have been de-allocated due to changes in the tree.\n\nYou can switch back to the old tree using the tree selector at the bottom left.")
	end
end

function TreeTabClass:ConvertAllToVersion(version)
	local currActiveSpec = self.activeSpec
	local specVersionList = { }
	for _, spec in ipairs(self.specList) do
		t_insert(specVersionList, spec.treeVersion)
	end
	for index, specVersion in ipairs(specVersionList) do
		if specVersion ~= version then
			self:SetActiveSpec(index)
			self:ConvertToVersion(version, true, false)
		end
	end
	self:SetActiveSpec(currActiveSpec)
end

function TreeTabClass:OpenSpecManagePopup()
	local importTree =
		new("ButtonControl", nil, {-99, 259, 90, 20}, "Import Tree", function()
			self:OpenImportPopup()
		end)
	local exportTree =
		new("ButtonControl", {"LEFT", importTree, "RIGHT"}, {8, 0, 90, 20}, "Export Tree", function()
			self:OpenExportPopup()
		end)
	importTree.enabled = false
	exportTree.enabled = false

	main:OpenPopup(370, 290, "Manage Passive Trees", {
		new("PassiveSpecListControl", nil, {0, 50, 350, 200}, self),
		importTree,
		exportTree,
		new("ButtonControl", {"LEFT", exportTree, "RIGHT"}, {8, 0, 90, 20}, "Done", function()
			main:ClosePopup()
		end),
	})
end

function TreeTabClass:OpenVersionConvertPopup(version, ignoreRuthlessCheck)
	local controls = { }
	controls.warningLabel = new("LabelControl", nil, {0, 20, 0, 16}, "^7Warning: some or all of the passives may be de-allocated due to changes in the tree.\n\n" ..
		"Convert will replace your current tree.\nCopy + Convert will backup your current tree.\n")
	controls.convert = new("ButtonControl", nil, {-125, 105, 100, 20}, "Convert", function()
		self:ConvertToVersion(version, true, false, ignoreRuthlessCheck)
		main:ClosePopup()
	end)
	controls.convertCopy = new("ButtonControl", nil, {0, 105, 125, 20}, "Copy + Convert", function()
		self:ConvertToVersion(version, false, false, ignoreRuthlessCheck)
		main:ClosePopup()
	end)
	controls.cancel = new("ButtonControl", nil, {125, 105, 100, 20}, "Cancel", function()
		self.controls.versionSelect:SelByValue(self.build.spec.treeVersion, 'value')
		main:ClosePopup()
	end)
	main:OpenPopup(570, 140, "Convert to Version "..treeVersions[version].display, controls, "convert", "edit")
end

function TreeTabClass:OpenVersionConvertAllPopup(version)
	local controls = { }
	controls.warningLabel = new("LabelControl", nil, {0, 20, 0, 16}, "^7Warning: some or all of the passives may be de-allocated due to changes in the tree.\n\n" ..
		"Convert will replace all trees that are not Version "..treeVersions[version].display..".\nThis action cannot be undone.\n")
	controls.convert = new("ButtonControl", nil, {-58, 105, 100, 20}, "Convert", function()
		self:ConvertAllToVersion(version)
		main:ClosePopup()
	end)
	controls.cancel = new("ButtonControl", nil, {58, 105, 100, 20}, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(570, 140, "Convert all to Version "..treeVersions[version].display, controls, "convert", "edit")
end

function TreeTabClass:OpenImportPopup()
	local versionLookup = "tree/([0-9]+)%.([0-9]+)%.([0-9]+)/"
	local controls = { }
	local function decodePoePlannerTreeLink(treeLink)
		-- treeVersion is not known at this point. We need to decode the URL to get it.
		local tmpSpec = new("PassiveSpec", self.build, latestTreeVersion)
		local newTreeVersion_or_errMsg = tmpSpec:DecodePoePlannerURL(treeLink, true)
		-- Check for an error message
		if string.find(newTreeVersion_or_errMsg, "Invalid") then
			controls.msg.label = "^1"..newTreeVersion_or_errMsg
			return
		end

		-- 20230908. We always create a new Spec()
		local newSpec = new("PassiveSpec", self.build, newTreeVersion_or_errMsg)
		newSpec.title = controls.name.buf
		newSpec:DecodePoePlannerURL(treeLink, false)  --DecodePoePlannerURL was used above and URL proven correct.
		t_insert(self.specList, newSpec)
		-- trigger all the things that go with changing a spec
		self:SetActiveSpec(#self.specList)
		self.modFlag = true
		self.build.spec:AddUndoState()
		self.build.buildFlag = true
		main:ClosePopup()
	end

	local function decodeTreeLink(treeLink, newTreeVersion)
		-- newTreeVersion is passed in as an output of validateTreeVersion(). It will always be a valid tree version text string
		-- 20230908. We always create a new Spec()
		local newSpec = new("PassiveSpec", self.build, newTreeVersion)
		newSpec.title = controls.name.buf
		local errMsg = newSpec:DecodeURL(treeLink)
		if errMsg then
			controls.msg.label = "^1"..errMsg.."^7"
		else
			t_insert(self.specList, newSpec)
			-- trigger all the things that go with changing a spec
			self:SetActiveSpec(#self.specList)
			self.modFlag = true
			self.build.spec:AddUndoState()
			self.build.buildFlag = true
			main:ClosePopup()
		end
	end
	local function validateTreeVersion(isRuthless, major, minor)
		-- Take the Major and Minor version numbers and confirm it is a valid tree version. The point release is also passed in but it is not used
		-- Return: the passed in tree version as text or latestTreeVersion
		if major and minor then
			--need leading 0 here
			local newTreeVersionNum = tonumber(string.format("%d.%02d", major, minor))
			if newTreeVersionNum >= treeVersions[defaultTreeVersion].num and newTreeVersionNum <= treeVersions[latestTreeVersion].num then
				-- no leading 0 here
				return string.format("%s_%s", major, minor) .. (isRuthless and "_ruthless" or "")
			else
				print(string.format("Version '%d_%02d' is out of bounds", major, minor))
			end
		end
		return latestTreeVersion .. (isRuthless and "_ruthless" or "")
	end

	controls.nameLabel = new("LabelControl", nil, {-180, 20, 0, 16}, "Enter name for this passive tree:")
	controls.name = new("EditControl", nil, {100, 20, 350, 18}, "", nil, nil, nil, function(buf)
		controls.msg.label = ""
		controls.import.enabled = buf:match("%S") and controls.edit.buf:match("%S")
	end)
	controls.editLabel = new("LabelControl", nil, {-150, 45, 0, 16}, "Enter passive tree link:")
	controls.edit = new("EditControl", nil, {100, 45, 350, 18}, "", nil, nil, nil, function(buf)
		controls.msg.label = ""
		controls.import.enabled = buf:match("%S") and controls.name.buf:match("%S")
	end)
	controls.msg = new("LabelControl", nil, {0, 65, 0, 16}, "")
	controls.import = new("ButtonControl", nil, {-45, 85, 80, 20}, "Import", function()
		local treeLink = controls.edit.buf
		if #treeLink == 0 then
			return
		end
		-- EG: http://poeurl.com/dABz
		if treeLink:match("poeurl%.com/") then
			controls.import.enabled = false
			controls.msg.label = "Resolving PoEURL link..."
			local id = LaunchSubScript([[
				local treeLink = ...
				local curl = require("lcurl.safe")
				local easy = curl.easy()
				easy:setopt_url(treeLink)
				easy:setopt_writefunction(function(data)
					return true
				end)
				easy:perform()
				local redirect = easy:getinfo(curl.INFO_REDIRECT_URL)
				easy:close()
				if not redirect or redirect:match("poeurl%.com/") then
					return nil, "Failed to resolve PoEURL link"
				end
				return redirect
			]], "", "", treeLink)
			if id then
				launch:RegisterSubScript(id, function(treeLink, errMsg)
					if errMsg then
						controls.msg.label = "^1"..errMsg.."^7"
						controls.import.enabled = true
						return
					else
						decodeTreeLink(treeLink, validateTreeVersion(treeLink:match("tree/ruthless"), treeLink:match(versionLookup)))
					end
				end)
			end
		elseif treeLink:match("poeplanner.com/") then
			decodePoePlannerTreeLink(treeLink:gsub("/%?v=.+#","/"))
		elseif treeLink:match("poeskilltree.com/") then
			local oldStyleVersionLookup = "/%?v=([0-9]+)%.([0-9]+)%.([0-9]+)%-?r?u?t?h?l?e?s?s?#"
			-- Strip the version from the tree : https://poeskilltree.com/?v=3.6.0#AAAABAMAABEtfIOFMo6-ksHfsOvu -> https://poeskilltree.com/AAAABAMAABEtfIOFMo6-ksHfsOvu
			decodeTreeLink(treeLink:gsub("/%?v=.+#","/"), validateTreeVersion(treeLink:match("-ruthless#"), treeLink:match(oldStyleVersionLookup)))
		else
			-- EG: https://www.pathofexile.com/passive-skill-tree/3.15.0/AAAABgMADI6-HwKSwQQHLJwtH9-wTLNfKoP3ES3r5AAA
			-- EG: https://www.pathofexile.com/fullscreen-passive-skill-tree/3.15.0/AAAABgMADAQHES0fAiycLR9Ms18qg_eOvpLB37Dr5AAA
			-- EG: https://www.pathofexile.com/passive-skill-tree/ruthless/AAAABgAAAAAA (Ruthless doesn't have versions)
			decodeTreeLink(treeLink, validateTreeVersion(treeLink:match("tree/ruthless"), treeLink:match(versionLookup)))
		end
	end)
	controls.import.enabled = false
	controls.cancel = new("ButtonControl", nil, {45, 85, 80, 20}, "Cancel", function()
		main:ClosePopup()
	end)
	main:OpenPopup(580, 115, "Import Tree", controls, "import", "name")
end

function TreeTabClass:OpenExportPopup()
	local treeLink = self.build.spec:EncodeURL(treeVersions[self.build.spec.treeVersion].url)
	local popup
	local controls = { }
	controls.label = new("LabelControl", nil, {0, 20, 0, 16}, "Passive tree link:")
	controls.edit = new("EditControl", nil, {0, 40, 350, 18}, treeLink, nil, "%Z")
	controls.shrink = new("ButtonControl", nil, {-90, 70, 140, 20}, "Shrink with PoEURL", function()
		controls.shrink.enabled = false
		controls.shrink.label = "Shrinking..."
		launch:DownloadPage("http://poeurl.com/shrink.php?url="..treeLink, function(response, errMsg)
			controls.shrink.label = "Done"
			if errMsg or not response.body:match("%S") then
				main:OpenMessagePopup("PoEURL Shortener", "Failed to get PoEURL link. Try again later.")
			else
				treeLink = "http://poeurl.com/"..response.body
				controls.edit:SetText(treeLink)
				popup:SelectControl(controls.edit)
			end
		end)
	end)
	controls.copy = new("ButtonControl", nil, {30, 70, 80, 20}, "Copy", function()
		Copy(treeLink)
	end)
	controls.done = new("ButtonControl", nil, {120, 70, 80, 20}, "Done", function()
		main:ClosePopup()
	end)
	popup = main:OpenPopup(380, 100, "Export Tree", controls, "done", "edit")
end

function TreeTabClass:ModifyAttributePopup(hoverNode)
	local controls = { }
	local spec = self.build.spec
	local attributes = { "Strength", "Dexterity", "Intelligence" }

	controls.attrSelect = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, {225, 30, 100, 18}, attributes, nil)
	controls.save = new("ButtonControl", nil, {-50, 65, 80, 20}, "Allocate", function()
		spec:SwitchAttributeNode(hoverNode.id, controls.attrSelect.selIndex)
		spec.attributeIndex = controls.attrSelect.selIndex
		spec:AllocNode(hoverNode, spec.tracePath and hoverNode == spec.tracePath[#spec.tracePath] and spec.tracePath)
		spec:AddUndoState()
		self.build.buildFlag = true
		main:ClosePopup()
	end)
	controls.close = new("ButtonControl", nil, {50, 65, 80, 20}, "Cancel", function()
		spec:DeallocNode(hoverNode)
		main:ClosePopup()
	end)
	controls.hotkeyTooltip = new("LabelControl", nil, {0, 100, 0, 16}, 
		"^8You can switch attributes quicker by holding hotkeys while allocating:\n"..colorCodes.INTELLIGENCE.."\"1\" or \"I\" for Intelligence, "
		..colorCodes.STRENGTH.."\"2\" or \"S\" for Strength, "..colorCodes.DEXTERITY.."\"3\" or \"D\" for Dexterity\n\n"
		..colorCodes.RARE.."Right-click ^8an allocated node to toggle attribute types or to set an\n" .. 
		"unallocated node to your last used attribute\n\n"
	)
	main:OpenPopup(550, 185, "Choose Attribute", controls, "save")
end

function TreeTabClass:SaveMasteryPopup(node, listControl)
		if listControl.selValue == nil then
			return
		end
		local effect = self.build.spec.tree.masteryEffects[listControl.selValue.id]
		node.sd = effect.sd
		node.allMasteryOptions = false
		node.reminderText = { "Tip: Right click to select a different effect" }
		self.build.spec.tree:ProcessStats(node)
		self.build.spec.masterySelections[node.id] = effect.id
		if not node.alloc then
			self.build.spec:AllocNode(node, self.viewer.tracePath and node == self.viewer.tracePath[#self.viewer.tracePath] and self.viewer.tracePath)
		end
		self.build.spec:AddUndoState()
		self.modFlag = true
		self.build.buildFlag = true
		main:ClosePopup()
end

function TreeTabClass:OpenMasteryPopup(node, viewPort)
	local controls = { }
	local effects = { }
	local cachedSd = node.sd
	local cachedAllMasteryOption = node.allMasteryOptions

	wipeTable(effects)
	for _, effect in pairs(node.masteryEffects) do
		local assignedNodeId = isValueInTable(self.build.spec.masterySelections, effect.effect)
		if not assignedNodeId or assignedNodeId == node.id then
			t_insert(effects, {label = t_concat(effect.stats, " / "), id = effect.effect})
		end
	end
	--Check to make sure that the effects list has a potential mod to apply to a mastery
	if not (next(effects) == nil) then
		local passiveMasteryControlHeight = (#effects + 1) * 14 + 2
		controls.close =  new("ButtonControl", nil, {0, 30 + passiveMasteryControlHeight, 90, 20}, "Cancel", function()
			node.sd = cachedSd
			node.allMasteryOptions = cachedAllMasteryOption
			self.build.spec.tree:ProcessStats(node)
			main:ClosePopup()
		end)
		controls.effect = new("PassiveMasteryControl", {"TOPLEFT",nil,"TOPLEFT"}, {6, 25, 0, passiveMasteryControlHeight}, effects, self, node, controls.save)
		main:OpenPopup(controls.effect.width + 12, controls.effect.height + 60, node.name, controls)
	end
end

function TreeTabClass:SetPowerCalc(powerStat)
	self.viewer.showHeatMap = true
	self.build.buildFlag = true
	self.build.calcsTab.powerBuildFlag = true
	self.build.calcsTab.powerStat = powerStat
	self.controls.powerReportList:SetReport(powerStat, nil)
end

function TreeTabClass:BuildPowerReportList(currentStat)
	local report = {}

	if not (currentStat and currentStat.stat) then
		return report
	end

	-- locate formatting information for the type of heat map being used.
	-- maybe a better place to find this? At the moment, it is the only place
	-- in the code that has this information in a tidy place.
	local displayStat = nil

	for index, ds in ipairs(self.build.displayStats) do
		if ds.stat == currentStat.stat then
			displayStat = ds
			break
		end
	end

	-- not every heat map has an associated "stat" in the displayStats table
	-- this is due to not every stat being displayed in the sidebar, I believe.
	-- But, we do want to use the formatting knowledge stored in that table rather than duplicating it here.
	-- If no corresponding stat is found, just default to a generic stat display (>0=good, one digit of precision).
	if not displayStat then
		displayStat = {
			fmt = ".1f"
		}
	end

	-- search all nodes, ignoring ascendancies, sockets, etc.
	for nodeId, node in pairs(self.build.spec.nodes) do
		local isAlloc = node.alloc or self.build.calcsTab.mainEnv.grantedPassives[nodeId]
		if (node.type == "Normal" or node.type == "Keystone" or node.type == "Notable") and not node.ascendancyName then
			local pathDist
			if isAlloc then
				pathDist = #(node.depends or { }) == 0 and 1 or #node.depends
			else
				pathDist = #(node.path or { }) == 0 and 1 or #node.path
			end
			local nodePower = (node.power.singleStat or 0) * ((displayStat.pc or displayStat.mod) and 100 or 1)
			local pathPower = (node.power.pathPower or 0) / pathDist * ((displayStat.pc or displayStat.mod) and 100 or 1)
			local nodePowerStr = s_format("%"..displayStat.fmt, nodePower)
			local pathPowerStr = s_format("%"..displayStat.fmt, pathPower)

			nodePowerStr = formatNumSep(nodePowerStr)
			pathPowerStr = formatNumSep(pathPowerStr)

			if (nodePower > 0 and not displayStat.lowerIsBetter) or (nodePower < 0 and displayStat.lowerIsBetter) then
				nodePowerStr = colorCodes.POSITIVE .. nodePowerStr
			elseif (nodePower < 0 and not displayStat.lowerIsBetter) or (nodePower > 0 and displayStat.lowerIsBetter) then
				nodePowerStr = colorCodes.NEGATIVE .. nodePowerStr
			end
			if (pathPower > 0 and not displayStat.lowerIsBetter) or (pathPower < 0 and displayStat.lowerIsBetter) then
				pathPowerStr = colorCodes.POSITIVE .. pathPowerStr
			elseif (pathPower < 0 and not displayStat.lowerIsBetter) or (pathPower > 0 and displayStat.lowerIsBetter) then
				pathPowerStr = colorCodes.NEGATIVE .. pathPowerStr
			end

			t_insert(report, {
				name = node.dn,
				power = nodePower,
				powerStr = nodePowerStr,
				pathPower = pathPower,
				pathPowerStr = pathPowerStr,
				allocated = isAlloc,
				id = node.id,
				x = node.x,
				y = node.y,
				type = node.type,
				pathDist = pathDist
			})
		end
	end

	-- search all cluster notables and add to the list
	for nodeName, node in pairs(self.build.spec.tree.clusterNodeMap) do
		local isAlloc = node.alloc
		if not isAlloc then
			local nodePower = (node.power and node.power.singleStat or 0) * ((displayStat.pc or displayStat.mod) and 100 or 1)
			local nodePowerStr = s_format("%"..displayStat.fmt, nodePower)

			nodePowerStr = formatNumSep(nodePowerStr)

			if (nodePower > 0 and not displayStat.lowerIsBetter) or (nodePower < 0 and displayStat.lowerIsBetter) then
				nodePowerStr = colorCodes.POSITIVE .. nodePowerStr
			elseif (nodePower < 0 and not displayStat.lowerIsBetter) or (nodePower > 0 and displayStat.lowerIsBetter) then
				nodePowerStr = colorCodes.NEGATIVE .. nodePowerStr
			end

			t_insert(report, {
				name = node.dn,
				power = nodePower,
				powerStr = nodePowerStr,
				pathPower = 0,
				pathPowerStr = "--",
				id = node.id,
				type = node.type,
				pathDist = "Cluster"
			})
		end
	end

	-- sort it
	if displayStat.lowerIsBetter then
		t_sort(report, function (a,b)
			return a.power < b.power
		end)
	else
		t_sort(report, function (a,b)
			return a.power > b.power
		end)
	end

	return report
end

function TreeTabClass:FindTimelessJewel()
	local socketViewer = new("PassiveTreeView")
	local treeData = self.build.spec.tree
	local legionNodes = treeData.legion.nodes
	local legionAdditions = treeData.legion.additions
	local timelessData = self.build.timelessData
	local controls = { }
	local modData = { }
	local ignoredMods = { "Might of the Vaal", "Legacy of the Vaal", "Strength", "Add Strength", "Dex", "Add Dexterity", "Devotion", "Price of Glory" }
	local totalMods = { [2] = "Strength", [3] = "Dexterity", [4] = "Devotion" }
	local totalModIDs = {
		["total_strength"] = { ["karui_notable_add_strength"] = true, ["karui_attribute_strength"] = true, ["karui_small_strength"] = true },
		["total_dexterity"] = { ["maraketh_notable_add_dexterity"] = true, ["maraketh_attribute_dex"] = true, ["maraketh_small_dex"] = true },
		["total_devotion"] = { ["templar_notable_devotion"] = true, ["templar_devotion_node"] = true, ["templar_small_devotion"] = true }
	}
	local reverseTotalModIDs = {
		["karui_notable_add_strength"] = true,
		["karui_attribute_strength"] = true,
		["karui_small_strength"] = true,
		["maraketh_notable_add_dexterity"] = true,
		["maraketh_attribute_dex"] = true,
		["maraketh_small_dex"] = true,
		["templar_notable_devotion"] = true,
		["templar_devotion_node"] = true,
		["templar_small_devotion"] = true
	}
	local jewelTypes = {
		{ label = "Glorious Vanity", name = "vaal", id = 1 },
		{ label = "Lethal Pride", name = "karui", id = 2 },
		{ label = "Brutal Restraint", name = "maraketh", id = 3 },
		{ label = "Militant Faith", name = "templar", id = 4 },
		{ label = "Elegant Hubris", name = "eternal", id = 5 }
	}
	-- rebuild `timelessData.jewelType` as we only store the minimum amount of `jewelType` data in build XML
	if next(timelessData.jewelType) then
		for idx, jewelType in ipairs(jewelTypes) do
			if jewelType.id == timelessData.jewelType.id then
				timelessData.jewelType = jewelType
				break
			end
		end
	else
		timelessData.jewelType = jewelTypes[1]
	end
	local conquerorTypes = {
		[1] = {
			{ label = "Any", id = 1 },
			{ label = "Doryani (Corrupted Soul)", id = 2 },
			{ label = "Xibaqua (Divine Flesh)", id = 3 },
			{ label = "Ahuana (Immortal Ambition)", id = 4 }
		},
		[2] = {
			{ label = "Any", id = 1 },
			{ label = "Kaom (Strength of Blood)", id = 2 },
			{ label = "Rakiata (Tempered by War)", id = 3 },
			{ label = "Akoya (Chainbreaker)", id = 4 }
		},
		[3] = {
			{ label = "Any", id = 1 },
			{ label = "Asenath (Dance with Death)", id = 2 },
			{ label = "Nasima (Second Sight)", id = 3 },
			{ label = "Balbala (The Traitor)", id = 4 }
		},
		[4] = {
			{ label = "Any", id = 1 },
			{ label = "Avarius (Power of Purpose)", id = 2 },
			{ label = "Dominus (Inner Conviction)", id = 3 },
			{ label = "Maxarius (Transcendence)", id = 4 }
		},
		[5] = {
			{ label = "Any", id = 1 },
			{ label = "Cadiro (Supreme Decadence)", id = 2 },
			{ label = "Victario (Supreme Grandstanding)", id = 3 },
			{ label = "Caspiro (Supreme Ostentation)", id = 4 }
		}
	}
	-- rebuild `timelessData.conquerorType` as we only store the minimum amount of `conquerorType` data in build XML
	if next(timelessData.conquerorType) then
		for idx, conquerorType in ipairs(conquerorTypes[timelessData.jewelType.id]) do
			if conquerorType.id == timelessData.conquerorType.id then
				timelessData.conquerorType = conquerorType
				break
			end
		end
	else
		timelessData.conquerorType = conquerorTypes[timelessData.jewelType.id][1]
	end
	local devotionVariants = {
		{ id = 1 , label = "Any" },
		{ id = 2 , label = "Totem Damage" },
		{ id = 3 , label = "Brand Damage" },
		{ id = 4 , label = "Channelling Damage" },
		{ id = 5 , label = "Area Damage" },
		{ id = 6 , label = "Elemental Damage" },
		{ id = 7 , label = "Elemental Resistances" },
		{ id = 8 , label = "Effect of non-Damaging Ailments" },
		{ id = 9 , label = "Elemental Ailment Duration" },
		{ id = 10, label = "Duration of Curses" },
		{ id = 11, label = "Minion Attack and Cast Speed" },
		{ id = 12, label = "Minions Accuracy Rating" },
		{ id = 13, label = "Mana Regen" },
		{ id = 14, label = "Skill Cost" },
		{ id = 15, label = "Non-Curse Aura Effect" },
		{ id = 16, label = "Defences from Shield" }
	}
	local jewelSockets = { }
	for socketId, socketData in pairs(self.build.spec.nodes) do
		if socketData.isJewelSocket and socketData.name ~= "Charm Socket"then
			local keystone = "Unknown"
			if socketId == 26725 then
				keystone = "Marauder"
			elseif socketId == 54127 then
				keystone = "Duelist"
			elseif socketId == 7960 then
				keystone = "Templar/Witch"
			else
				local minDistance = math.huge
				for _, nodeInRadius in pairs(treeData.nodes[socketId].nodesInRadius[3]) do
					if nodeInRadius.isKeystone then
						local distance = math.sqrt((nodeInRadius.x - socketData.x) ^ 2 + (nodeInRadius.y - socketData.y) ^ 2)
						if distance < minDistance then
							keystone = nodeInRadius.name
							minDistance = distance
						end
					end
				end
			end
			local label = keystone .. ": " .. socketId
			if self.build.spec.allocNodes[socketId] then
				label = "# " .. label
			end
			t_insert(jewelSockets, {
				label = label,
				keystone = keystone,
				id = socketId
			})
		end
	end
	t_sort(jewelSockets, function(a, b) return a.label < b.label end)
	-- rebuild `timelessData.jewelSocket` as we only store the minimum amount of `jewelSocket` data in build XML
	if next(timelessData.jewelSocket) then
		for idx, jewelSocket in ipairs(jewelSockets) do
			if jewelSocket.id == timelessData.jewelSocket.id then
				timelessData.jewelSocket = jewelSocket
				break
			end
		end
	else
		timelessData.jewelSocket = jewelSockets[1]
	end

	local function buildMods()
		wipeTable(modData)
		local smallModData = { }
		for _, node in pairs(legionNodes) do
			if node.id:match("^" .. timelessData.jewelType.name .. "_.+") and not isValueInArray(ignoredMods, node.dn) and not node.ks then
				if node["not"] then
					t_insert(modData, {
						label = node.dn .. "                                                " .. node.sd[1],
						descriptions = copyTable(node.sd),
						type = timelessData.jewelType.name,
						id = node.id
					})
					if node.sd[2] then
						modData[#modData].label = modData[#modData].label .. " " .. node.sd[2]
					end
				else
					t_insert(smallModData, {
						label = node.dn,
						descriptions = copyTable(node.sd),
						type = timelessData.jewelType.name,
						id = node.id
					})
				end
			end
		end
		for _, addition in pairs(legionAdditions) do
			-- exclude passives that are already added (vaal, attributes, devotion)
			if addition.id:match("^" .. timelessData.jewelType.name .. "_.+") and not isValueInArray(ignoredMods, addition.dn) and timelessData.jewelType.name ~= "vaal" then
				t_insert(modData, {
					label = addition.dn,
					descriptions = copyTable(addition.sd),
					type = timelessData.jewelType.name,
					id = addition.id
				})
			end
		end
		t_sort(modData, function(a, b) return a.label < b.label end)
		t_sort(smallModData, function (a, b) return a.label < b.label end)
		if totalMods[timelessData.jewelType.id] then
			t_insert(modData, 1, {
				label = "Total " .. totalMods[timelessData.jewelType.id],
				descriptions = { "This is a hybrid node containing all additions to " .. totalMods[timelessData.jewelType.id] },
				type = timelessData.jewelType.name,
				id = "total_" .. totalMods[timelessData.jewelType.id]:lower(),
				totalMod = true
			})
		end
		t_insert(modData, 1, { label = "..." })
		for i = 1, #smallModData do
			modData[#modData + 1] = smallModData[i]
		end
	end

	local function getNodeWeights()
		local nodeWeights = {
			[1] = controls.nodeSliderValue.label:sub(3):lower(),
			[2] = controls.nodeSlider2Value.label:sub(3):lower(),
			[3] = controls.nodeSlider3Value.label:sub(3):lower()
		}
		for i, nodeWeight in ipairs(nodeWeights) do
			if tonumber(nodeWeight) ~= nil then
				nodeWeights[i] = round(tonumber(nodeWeight), 3)
			end
		end
		return nodeWeights
	end

	local searchListTbl = { }
	local searchListFallbackTbl = { }
	local function parseSearchList(mode, fallback)
		if mode == 0 then
			if fallback then
				-- timelessData.searchListFallback => searchListFallbackTbl
				if timelessData.searchListFallback then
					searchListFallbackTbl = { }
					for inputLine in timelessData.searchListFallback:gmatch("[^\r\n]+") do
						searchListFallbackTbl[#searchListFallbackTbl + 1] = { }
						for splitLine in inputLine:gmatch("([^,%s]+)") do
							searchListFallbackTbl[#searchListFallbackTbl][#searchListFallbackTbl[#searchListFallbackTbl] + 1] = splitLine
						end
					end
				end
			else
				-- timelessData.searchList => searchListTbl
				if timelessData.searchList then
					searchListTbl = { }
					for inputLine in timelessData.searchList:gmatch("[^\r\n]+") do
						searchListTbl[#searchListTbl + 1] = { }
						for splitLine in inputLine:gmatch("([^,%s]+)") do
							searchListTbl[#searchListTbl][#searchListTbl[#searchListTbl] + 1] = splitLine
						end
					end
				end
			end
		else
			if fallback then
				-- searchListFallbackTbl => controls.searchListFallback
				if controls.searchListFallback and controls.nodeSelect then
					local searchText = ""
					for _, curRow in ipairs(searchListFallbackTbl) do
						if curRow[1] == controls.nodeSelect.list[controls.nodeSelect.selIndex].id then
							local nodeWeights = getNodeWeights()
							curRow[2] = nodeWeights[1]
							curRow[3] = nodeWeights[2]
							curRow[4] = nodeWeights[3]
						end
						if #searchText > 0 then
							searchText = searchText .. "\n"
						end
						searchText = searchText .. t_concat(curRow, ", ")
					end
					if timelessData.searchListFallback ~= searchText then
						timelessData.searchListFallback = searchText
						controls.searchListFallback:SetText(searchText)
						self.build.modFlag = true
					end
				end
			else
				-- searchListTbl => controls.searchList
				if controls.searchList and controls.nodeSelect then
					local searchText = ""
					for _, curRow in ipairs(searchListTbl) do
						if curRow[1] == controls.nodeSelect.list[controls.nodeSelect.selIndex].id then
							local nodeWeights = getNodeWeights()
							curRow[2] = nodeWeights[1]
							curRow[3] = nodeWeights[2]
							curRow[4] = nodeWeights[3]
						end
						if #searchText > 0 then
							searchText = searchText .. "\n"
						end
						searchText = searchText .. t_concat(curRow, ", ")
					end
					if timelessData.searchList ~= searchText then
						timelessData.searchList = searchText
						controls.searchList:SetText(searchText)
						self.build.modFlag = true
					end
				end
			end
		end
	end
	parseSearchList(0, false) -- initial load: [timelessData.searchList => searchListTbl]
	parseSearchList(0, true)  -- initial load: [timelessData.searchListFallback => searchListFallbackTbl]
	local function updateSearchList(text, fallback)
		if fallback then
			timelessData.searchListFallback = text
			controls.searchListFallback:SetText(text)
		else
			timelessData.searchList = text
			controls.searchList:SetText(text)
		end
		parseSearchList(0, fallback)
		self.build.modFlag = true
	end

	controls.devotionSelectLabel = new("LabelControl", {"TOPRIGHT", nil, "TOPLEFT"}, {820, 25, 0, 16}, "^7Devotion modifiers:")
	controls.devotionSelectLabel.shown = timelessData.jewelType.id == 4
	controls.devotionSelect1 = new("DropDownControl", {"TOP", controls.devotionSelectLabel, "BOTTOM"}, {0, 8, 200, 18}, devotionVariants, function(index, value)
		timelessData.devotionVariant1 = index
	end)
	controls.devotionSelect1.selIndex = timelessData.devotionVariant1
	controls.devotionSelect2 = new("DropDownControl", {"TOP", controls.devotionSelect1, "BOTTOM"}, {0, 7, 200, 18}, devotionVariants, function(index, value)
		timelessData.devotionVariant2 = index
	end)
	controls.devotionSelect2.selIndex = timelessData.devotionVariant2

	controls.jewelSelectLabel = new("LabelControl", {"TOPRIGHT", nil, "TOPLEFT"}, {405, 25, 0, 16}, "^7Jewel Type:")
	controls.jewelSelect = new("DropDownControl", {"LEFT", controls.jewelSelectLabel, "RIGHT"}, {10, 0, 200, 18}, jewelTypes, function(index, value)
		timelessData.jewelType = value
		controls.devotionSelectLabel.shown = value.id == 4 -- Militant Faith
		controls.protectAllocatedLabel.shown = (value.id == 4 and controls.socketFilter.state)
		controls.conquerorSelect.list = conquerorTypes[timelessData.jewelType.id]
		controls.conquerorSelect.selIndex = 1
		timelessData.conquerorType = conquerorTypes[timelessData.jewelType.id][1]
		controls.nodeSelect.selIndex = 1
		buildMods()
		updateSearchList("", false)
		updateSearchList("", true)
	end)
	controls.jewelSelect.selIndex = timelessData.jewelType.id

	controls.conquerorSelectLabel = new("LabelControl", {"TOPRIGHT", nil, "TOPLEFT"}, {405, 50, 0, 16}, "^7Conqueror:")
	controls.conquerorSelect = new("DropDownControl", {"LEFT", controls.conquerorSelectLabel, "RIGHT"}, {10, 0, 200, 18}, conquerorTypes[timelessData.jewelType.id], function(index, value)
		timelessData.conquerorType = value
		self.build.modFlag = true
	end)
	controls.conquerorSelect.selIndex = timelessData.conquerorType.id

	local allocatedNodes = { }
	local protectedNodes = { }
	local protectedNodesCount = 0
	self.allocatedNodesInRadiusCount = 0
	local function setAllocatedNodes() -- find allocated nodes in radius for Militant Faith filtering / protected nodes dropdown
		local nodeNames = { }
		local radiusNodes = treeData.nodes[timelessData.jewelSocket.id].nodesInRadius[3] -- large radius around timelessData.jewelSocket.id
		for nodeId in pairs(radiusNodes) do
			if self.build.calcsTab.mainEnv.grantedPassives[nodeId] ~= nil or self.build.spec.allocNodes[nodeId] ~= nil then
				allocatedNodes[nodeId] = true
				if treeData.nodes[nodeId] and treeData.nodes[nodeId].isNotable then
					t_insert(nodeNames, treeData.nodes[nodeId].dn)
				end
			end
		end
		controls.protectAllocatedSelect:SetList(nodeNames)
		self.allocatedNodesInRadiusCount = #nodeNames
	end

	controls.socketSelectLabel = new("LabelControl", {"TOPRIGHT", nil, "TOPLEFT"}, {405, 75, 0, 16}, "^7Jewel Socket:")
	controls.socketSelect = new("TimelessJewelSocketControl", {"LEFT", controls.socketSelectLabel, "RIGHT"}, {10, 0, 200, 18}, jewelSockets, function(index, value)
		timelessData.jewelSocket = value
		setAllocatedNodes() -- reset list when changing sockets
		self.build.modFlag = true
	end, self.build, socketViewer)
	-- we need to search through `jewelSockets` for the correct `id` as the `idx` can become stale due to dynamic sorting
	for idx, jewelSocket in ipairs(jewelSockets) do
		if jewelSocket.id == timelessData.jewelSocket.id then
			controls.socketSelect.selIndex = idx
			break
		end
	end

	local function clearProtected() -- clear all controls, nodes related to Militant Faith filtering
		protectedNodesCount = 0
		protectedNodes = { }
		for index, _ in pairs(controls) do
			if index:find("protected:") then
				controls[index] = nil
			end
		end
	end
	controls.socketFilterLabel = new("LabelControl", { "TOPRIGHT", nil, "TOPLEFT" }, { 405, 100, 0, 16 }, "^7Filter Nodes:")
	controls.socketFilter = new("CheckBoxControl", { "LEFT", controls.socketFilterLabel, "RIGHT" }, { 10, 0, 18 }, nil, function(value)
		timelessData.socketFilter = value
		self.build.modFlag = true
		controls.socketFilterAdditionalDistanceLabel.shown = value
		controls.socketFilterAdditionalDistance.shown = value
		controls.socketFilterAdditionalDistanceValue.shown = value
		controls.protectAllocatedLabel.shown = (value and timelessData.jewelType.label == "Militant Faith")

		if value then
			setAllocatedNodes()
		else
			clearProtected()
		end
	end)
	controls.socketFilter.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		tooltip:AddLine(16, "^7Enable this option to exclude nodes that you do not have allocated on your active passive skill tree.")
		tooltip:AddLine(16, "^7This can be useful if you're never going to path towards those excluded nodes and don't care what happens to them.")
	end
	controls.socketFilter.state = timelessData.socketFilter

	-- Militant Faith protect notables controls
	controls.protectAllocatedLabel = new("LabelControl", { "TOPLEFT", nil, "TOPLEFT" }, { 15, 25, 0, 16 }, "^7Protect allocated nodes from changing:")
	controls.protectAllocatedSelect = new("DropDownControl", { "TOPLEFT", controls.protectAllocatedLabel, "BOTTOMLEFT" }, { 0, 8, 200, 18 }, nil, nil)
	controls.protectAllocatedButtonAdd = new("ButtonControl", { "LEFT", controls.protectAllocatedSelect, "RIGHT" }, { 5, 0, 44, 18 }, "Add", function()
		local selValue = controls.protectAllocatedSelect:GetSelValue()
		if selValue and not controls["protected:"..selValue] then
			protectedNodesCount = protectedNodesCount + 1
			t_insert(protectedNodes, selValue)
			controls["protected:"..selValue] = new("LabelControl", { "TOPLEFT", controls.protectAllocatedSelect, "BOTTOMLEFT" }, { 0, 16 * protectedNodesCount - 10, 0, 16 }, "^7"..selValue)
		end
	end)
	controls.protectAllocatedButtonClear = new("ButtonControl", { "LEFT", controls.protectAllocatedButtonAdd, "RIGHT" }, { 5, 0, 44, 18 }, "Clear", function()
		clearProtected()
	end)
	-- set shown and list on load
	if controls.socketFilter.state then
		setAllocatedNodes()
	end
	controls.protectAllocatedLabel.shown = controls.jewelSelect.selIndex == 4 and controls.socketFilter.state

	controls.protectAllocatedButtonAdd.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		tooltip:AddLine(16, "^7Protect allocated nodes during search.")
		tooltip:AddLine(16, "^7This can be useful if transforming certain notables would break your build.")
	end

	local socketFilterAdditionalDistanceMAX = 10
	controls.socketFilterAdditionalDistanceLabel = new("LabelControl", {"LEFT", controls.socketFilter, "RIGHT"}, {10, 0, 0, 16}, "^7Node Distance:")
	controls.socketFilterAdditionalDistance = new("SliderControl", {"LEFT", controls.socketFilterAdditionalDistanceLabel, "RIGHT"}, {10, 0, 66, 18}, function(value)
		timelessData.socketFilterDistance = m_floor(value * socketFilterAdditionalDistanceMAX + 0.01)
		controls.socketFilterAdditionalDistanceValue.label = s_format("^7%d", timelessData.socketFilterDistance)
	end, { ["SHIFT"] = 1, ["CTRL"] = 1 / (socketFilterAdditionalDistanceMAX * 2), ["DEFAULT"] = 1 / socketFilterAdditionalDistanceMAX })
	controls.socketFilterAdditionalDistance.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if not controls.socketFilterAdditionalDistance.dragging then
			tooltip:AddLine(16, "^7This controls the maximum amount of points that need to be spent to grab a node before its filtered out")
		end
	end
	controls.socketFilterAdditionalDistance.tooltip.realDraw = controls.socketFilterAdditionalDistance.tooltip.Draw
	controls.socketFilterAdditionalDistance.tooltip.Draw = function(self, x, y, width, height, viewPort)
		local sliderOffsetX = round(184 * (1 - controls.socketFilterAdditionalDistance.val))
		local tooltipWidth, tooltipHeight = self:GetSize()
		if main.screenW >= 1384 - sliderOffsetX then
			return controls.socketFilterAdditionalDistance.tooltip.realDraw(self, x - 8 - sliderOffsetX, y - 4 - tooltipHeight, width, height, viewPort)
		end
		return controls.socketFilterAdditionalDistance.tooltip.realDraw(self, x, y, width, height, viewPort)
	end
	controls.socketFilterAdditionalDistanceValue = new("LabelControl", {"LEFT", controls.socketFilterAdditionalDistance, "RIGHT"}, {5, 0, 0, 16}, "^70")
	controls.socketFilterAdditionalDistance:SetVal((timelessData.socketFilterDistance or 0) / socketFilterAdditionalDistanceMAX)
	controls.socketFilterAdditionalDistanceLabel.shown = timelessData.socketFilter
	controls.socketFilterAdditionalDistance.shown = timelessData.socketFilter
	controls.socketFilterAdditionalDistanceValue.shown = timelessData.socketFilter

	local scrollWheelSpeedTbl = { ["SHIFT"] = 0.01, ["CTRL"] = 0.0001, ["DEFAULT"] = 0.001 }
	local scrollWheelSpeedTbl2 = { ["SHIFT"] = 0.2, ["CTRL"] = 0.002, ["DEFAULT"] = 0.02 }

	local nodeSliderStatLabel = "None"
	controls.nodeSliderLabel = new("LabelControl", {"TOPRIGHT", nil, "TOPLEFT"}, {405, 125, 0, 16}, "^7Primary Node Weight:")
	controls.nodeSlider = new("SliderControl", {"LEFT", controls.nodeSliderLabel, "RIGHT"}, {10, 0, 200, 16}, function(value)
		controls.nodeSliderValue.label = s_format("^7%.3f", value * 10)
		parseSearchList(1, controls.searchListFallback and controls.searchListFallback.shown or false)
	end, scrollWheelSpeedTbl)
	controls.nodeSlider.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if not controls.nodeSlider.dragging then
			if nodeSliderStatLabel == "None" then
				tooltip:AddLine(16, "^7For nodes with multiple stats this slider controls the weight of the first stat listed.")
			else
				tooltip:AddLine(16, "^7This slider controls the weight of the following stat:")
				tooltip:AddLine(16, "^7        " .. nodeSliderStatLabel)
			end
		end
	end
	controls.nodeSliderValue = new("LabelControl", {"LEFT", controls.nodeSlider, "RIGHT"}, {5, 0, 0, 16}, "^71.000")
	controls.nodeSlider.tooltip.realDraw = controls.nodeSlider.tooltip.Draw
	controls.nodeSlider.tooltip.Draw = function(self, x, y, width, height, viewPort)
		local sliderOffsetX = round(184 * (1 - controls.nodeSlider.val))
		local tooltipWidth, tooltipHeight = self:GetSize()
		if main.screenW >= 1338 - sliderOffsetX then
			return controls.nodeSlider.tooltip.realDraw(self, x - 8 - sliderOffsetX, y - 4 - tooltipHeight, width, height, viewPort)
		end
		return controls.nodeSlider.tooltip.realDraw(self, x, y, width, height, viewPort)
	end
	controls.nodeSlider:SetVal(0.1)

	local nodeSlider2StatLabel = "None"
	controls.nodeSlider2Label = new("LabelControl", {"TOPRIGHT", nil, "TOPLEFT"}, {405, 150, 0, 16}, "^7Secondary Node Weight:")
	controls.nodeSlider2 = new("SliderControl", {"LEFT", controls.nodeSlider2Label, "RIGHT"}, {10, 0, 200, 16}, function(value)
		controls.nodeSlider2Value.label = s_format("^7%.3f", value * 10)
		parseSearchList(1, controls.searchListFallback and controls.searchListFallback.shown or false)
	end, scrollWheelSpeedTbl)
	controls.nodeSlider2.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if not controls.nodeSlider2.dragging then
			if nodeSlider2StatLabel == "None" then
				tooltip:AddLine(16, "^7For nodes with multiple stats this slider controls the weight of the second stat listed.")
			else
				tooltip:AddLine(16, "^7This slider controls the weight of the following stat:")
				tooltip:AddLine(16, "^7        " .. nodeSlider2StatLabel)
			end
		end
	end
	controls.nodeSlider2Value = new("LabelControl", {"LEFT", controls.nodeSlider2, "RIGHT"}, {5, 0, 0, 16}, "^71.000")
	controls.nodeSlider2.tooltip.realDraw = controls.nodeSlider2.tooltip.Draw
	controls.nodeSlider2.tooltip.Draw = function(self, x, y, width, height, viewPort)
		local sliderOffsetX = round(184 * (1 - controls.nodeSlider2.val))
		local tooltipWidth, tooltipHeight = self:GetSize()
		if main.screenW >= 1384 - sliderOffsetX then
			return controls.nodeSlider2.tooltip.realDraw(self, x - 8 - sliderOffsetX, y - 4 - tooltipHeight, width, height, viewPort)
		end
		return controls.nodeSlider2.tooltip.realDraw(self, x, y, width, height, viewPort)
	end
	controls.nodeSlider2:SetVal(0.1)

	controls.nodeSlider3Label = new("LabelControl", {"TOPRIGHT", nil, "TOPLEFT"}, {405, 175, 0, 16}, "^7Minimum Node Weight:")
	controls.nodeSlider3 = new("SliderControl", {"LEFT", controls.nodeSlider3Label, "RIGHT"}, {10, 0, 200, 16}, function(value)
		if value == 1 then
			controls.nodeSlider3Value.label = "^7Required"
		else
			controls.nodeSlider3Value.label = s_format("^7%.f", value * 500)
		end
		parseSearchList(1, controls.searchListFallback and controls.searchListFallback.shown or false)
	end, scrollWheelSpeedTbl2)
	controls.nodeSlider3.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if not controls.nodeSlider3.dragging then
			tooltip:AddLine(16, "^7Seeds that do not meet the minimum weight threshold for a desired node are excluded from the search results.")
		end
	end
	controls.nodeSlider3Value = new("LabelControl", {"LEFT", controls.nodeSlider3, "RIGHT"}, {5, 0, 0, 16}, "^70")
	controls.nodeSlider3.tooltip.realDraw = controls.nodeSlider3.tooltip.Draw
	controls.nodeSlider3.tooltip.Draw = function(self, x, y, width, height, viewPort)
		local sliderOffsetX = round(184 * (1 - controls.nodeSlider3.val))
		local tooltipWidth, tooltipHeight = self:GetSize()
		if main.screenW >= 1728 - sliderOffsetX then
			return controls.nodeSlider3.tooltip.realDraw(self, x - 8 - sliderOffsetX, y - 4 - tooltipHeight, width, height, viewPort)
		end
		return controls.nodeSlider3.tooltip.realDraw(self, x, y, width, height, viewPort)
	end
	controls.nodeSlider3:SetVal(0)

	local function updateSliders(sliderData)
		if sliderData[2] == "required" then
			controls.nodeSlider.val = 1
			controls.nodeSliderValue.label = s_format("^7%.3f", 10)
		else
			controls.nodeSlider.val = m_min(m_max((tonumber(sliderData[2]) or 0) / 10, 0), 1)
			controls.nodeSliderValue.label = s_format("^7%.3f", controls.nodeSlider.val * 10)
		end
		if controls.nodeSlider2.enabled then
			if sliderData[3] == "required" then
				controls.nodeSlider2.val = 1
				controls.nodeSlider2Value.label = s_format("^7%.3f", 10)
			else
				controls.nodeSlider2.val = m_min(m_max((tonumber(sliderData[3]) or 0) / 10, 0), 1)
				controls.nodeSlider2Value.label = s_format("^7%.3f", controls.nodeSlider2.val * 10)
			end
		end
		if sliderData[4] == "required" then
			controls.nodeSlider3.val = 1
			controls.nodeSlider3Value.label = "^7Required"
		else
			controls.nodeSlider3.val = m_min(m_max((tonumber(sliderData[4]) or 0) / 500, 0), 1)
			controls.nodeSlider3Value.label = s_format("^7%.f", controls.nodeSlider3.val * 500)
		end
	end

	buildMods()
	controls.nodeSelectLabel = new("LabelControl", {"TOPRIGHT", nil, "TOPLEFT"}, {405, 200, 0, 16}, "^7Search for Node:")
	controls.nodeSelect = new("DropDownControl", {"LEFT", controls.nodeSelectLabel, "RIGHT"}, {10, 0, 200, 18}, modData, function(index, value)
		nodeSliderStatLabel = "None"
		nodeSlider2StatLabel = "None"
		if value.id then
			local statCount = 0
			for _, legionNode in ipairs(legionNodes) do
				if legionNode.id == value.id then
					statCount = #legionNode.sd
					nodeSliderStatLabel = legionNode.sd[1] or "None"
					nodeSlider2StatLabel = legionNode.sd[2] or "None"
					break
				end
			end
			if statCount == 0 then
				for _, legionAddition in ipairs(legionAdditions) do
					if legionAddition.id == value.id then
						statCount = #legionAddition.sd
						nodeSliderStatLabel = legionAddition.sd[1] or "None"
						nodeSlider2StatLabel = legionAddition.sd[2] or "None"
						break
					end
				end
			end
			if statCount <= 1 then
				controls.nodeSlider2Label.label = "^9Secondary Node Weight:"
				controls.nodeSlider2.val = 0
				controls.nodeSlider2Value.label = s_format("^9%.3f", 0)
			else
				controls.nodeSlider2Label.label = "^7Secondary Node Weight:"
				controls.nodeSlider2Value.label = s_format("^7%.3f", controls.nodeSlider2.val * 10)
			end
			controls.nodeSlider2.enabled = statCount > 1

			local nodeWeights = getNodeWeights()
			local newNode = value.id .. ", " .. nodeWeights[1] .. ", " .. nodeWeights[2] .. ", " .. nodeWeights[3]
			if controls.searchListFallback and controls.searchListFallback.shown then
				for _, searchRow in ipairs(searchListFallbackTbl) do
					-- update nodeSlider values and prevent duplicate searchList entries
					if searchRow[1] == value.id then
						updateSliders(searchRow)
						return
					end
				end
				controls.searchListFallback.caret = #controls.searchListFallback.buf + 1
				controls.searchListFallback:Insert((#controls.searchListFallback.buf > 0 and "\n" or "") .. newNode)
			else
				for _, searchRow in ipairs(searchListTbl) do
					-- update nodeSlider values and prevent duplicate searchList entries
					if searchRow[1] == value.id then
						updateSliders(searchRow)
						return
					end
				end
				controls.searchList.caret = #controls.searchList.buf + 1
				controls.searchList:Insert((#controls.searchList.buf > 0 and "\n" or "") .. newNode)
			end
			self.build.modFlag = true
		end
	end)
	controls.nodeSelect.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if mode ~= "OUT" and value.descriptions then
			for _, line in ipairs(value.descriptions) do
				tooltip:AddLine(16, "^7" .. line)
			end
		end
	end

	local function generateFallbackWeights(nodes, selection)
		local calcFunc, calcBase = self.build.calcsTab:GetMiscCalculator(self.build)
		local newList = { }
		local baseOutput = calcFunc()
		if baseOutput.Minion then
			baseOutput = baseOutput.Minion
		end
		local baseValue = baseOutput[selection.stat] or 1
		if selection.transform then
			baseValue = selection.transform(baseValue)
		end
		for _, newNode in ipairs(nodes) do
			local output = nil
			if newNode.calcMultiple then
				output = calcFunc({ addNodes = { [newNode.node[1]] = true } })
			else
				output = calcFunc({ addNodes = { [newNode] = true } })
			end
			if output.Minion then
				output = output.Minion
			end
			local outputValue = output[selection.stat] or 0
			if selection.transform then
				outputValue = selection.transform(outputValue)
			end
			outputValue = outputValue / baseValue
			if outputValue ~= outputValue then
				outputValue = 1
			end
			t_insert(newList, {
				id = newNode.id,
				weight1 = (outputValue - 1) / (newNode.divisor or 1)
			})
			if newNode.calcMultiple then
				output = calcFunc({ addNodes = { [newNode.node[2]] = true } })
				if output.Minion then
					output = output.Minion
				end
				outputValue = output[selection.stat] or 0
				if selection.transform then
					outputValue = selection.transform(outputValue)
				end
				outputValue = outputValue / baseValue
				if outputValue ~= outputValue then
					outputValue = 1
				end
				newList[#newList].weight2 = (outputValue - 1) / (newNode.divisor or 1)
			end
		end
		return newList
	end

	local function setupFallbackWeights()
		-- replaceHelperFunc is duplicated from PassiveSpec.lua
		local replaceHelperFunc = function(statToFix, statKey, statMod, value)
			if statMod.fmt == "g" then -- note the only one we actually care about is "Ritual of Flesh" life regen
				if statKey:find("per_minute") then
					value = round(value / 60, 1)
				elseif statKey:find("permyriad") then
					value = value / 100
				elseif statKey:find("_ms") then
					value = value / 1000
				end
			end
			--if statMod.fmt == "d" then -- only ever d or g, and we want both past here
			if statMod.min ~= statMod.max then
				return statToFix:gsub("%(" .. statMod.min .. "%-" .. statMod.max .. "%)", value)
			elseif statMod.min ~= value then -- only true for might/legacy of the vaal which can combine stats
				return statToFix:gsub(statMod.min, value)
			end
			return statToFix -- if it doesn't need to be changed
		end

		local nodes = { }
		for _, modNode in ipairs(modData) do
			if modNode.id then
				local newNode = nil
				for _, legionNode in ipairs(legionNodes) do
					if legionNode.id == modNode.id or (totalModIDs[modNode.id] and totalModIDs[modNode.id][legionNode.id]) then
							newNode = { }
							newNode.id = modNode.id
							if modNode.type == "vaal" then
								if #legionNode.sd == 2 then
									newNode.calcMultiple = true
									if legionNode.modListGenerated then
										newNode.node = copyTable(legionNode.modListGenerated)
									else
										-- generate modList
										local modList1, extra1 = modLib.parseMod(replaceHelperFunc(legionNode.sd[1], legionNode.sortedStats[1], legionNode.stats[legionNode.sortedStats[1]], 100))
										local modList2, extra2 = modLib.parseMod(replaceHelperFunc(legionNode.sd[2], legionNode.sortedStats[2], legionNode.stats[legionNode.sortedStats[2]], 100))
										local modLists = { { modList = modList1 }, { modList = modList2 } }
										legionNode.modListGenerated = copyTable(modLists)
										newNode.node = copyTable(modLists)
									end
									newNode.node[1].id = legionNode.id
									newNode.node[2].id = legionNode.id
								else
									if legionNode.modListGenerated then
										newNode.modList = copyTable(legionNode.modListGenerated)
									else
										-- generate modList
										local modList, extra = modLib.parseMod(replaceHelperFunc(legionNode.sd[1], legionNode.sortedStats[1], legionNode.stats[legionNode.sortedStats[1]], 100))
										legionNode.modListGenerated = modList
										newNode.modList = modList
									end
								end
								newNode.divisor = 100
							else
								newNode.modList = legionNode.modList
								if modNode.totalMod then
									newNode.divisor = legionNode.modList[1].value
								end
							end
						break
					end
				end
				if not newNode then
					for _, legionAddition in ipairs(legionAdditions) do
						if legionAddition.id == modNode.id or (totalModIDs[modNode.id] and totalModIDs[modNode.id][legionAddition.id]) then
							newNode = { }
							newNode.id = modNode.id
							if legionAddition.modList then
								newNode.modList = legionAddition.modList
							elseif legionAddition.modListGenerated then
								newNode.modList = legionAddition.modListGenerated
							else
								-- generate modList
								local line = legionAddition.sd[1]
								if modNode.type == "vaal" then
									for key, stat in legionAddition.stats do -- should only be length 1
										line = replaceHelperFunc(line, key, stat, 100)
									end
								end
								local modList, extra = modLib.parseMod(line)
								legionAddition.modListGenerated = modList
								newNode.modList = modList
							end
							if modNode.type == "vaal" then
								newNode.divisor = 100
							elseif modNode.totalMod then
								newNode.divisor = newNode.modList[1].value
							end
							break
						end
					end
				end
				if newNode then
					t_insert(nodes, newNode)
				end
			end
		end
		local output = generateFallbackWeights(nodes, controls.fallbackWeightsList.list[controls.fallbackWeightsList.selIndex])
		local newList = ""
		local weightScalar = 100
		for _, legionNode in ipairs(output) do
			if legionNode.weight1 ~= 0 or (legionNode.weight2 and legionNode.weight2 ~= 0) then
				if #newList > 0 then
					newList = newList .. "\n"
				end
				newList = newList .. legionNode.id .. ", " .. round(legionNode.weight1 * weightScalar, 3) .. ", " .. round((legionNode.weight2 or 0) * weightScalar, 3) .. ", 0"
			end
		end
		updateSearchList(newList, true)
	end

	controls.fallbackWeightsLabel = new("LabelControl", {"TOPRIGHT", nil, "TOPLEFT"}, {405, 225, 0, 16}, "^7Fallback Weight Mode:")
	local fallbackWeightsList = { }
	for id, stat in pairs(data.powerStatList) do
		if not stat.ignoreForItems and stat.label ~= "Name" then
			t_insert(fallbackWeightsList, {
				label = "Sort by " .. stat.label,
				stat = stat.stat,
				transform = stat.transform,
			})
		end
	end
	controls.fallbackWeightsList = new("DropDownControl", {"LEFT", controls.fallbackWeightsLabel, "RIGHT"}, {10, 0, 200, 18}, fallbackWeightsList, function(index)
		timelessData.fallbackWeightMode.idx = index
	end)
	controls.fallbackWeightsList.selIndex = timelessData.fallbackWeightMode.idx or 1
	controls.fallbackWeightsButton = new("ButtonControl", {"LEFT", controls.fallbackWeightsList, "RIGHT"}, {5, 0, 66, 18}, "Generate", function()
		setupFallbackWeights()
		controls.searchListFallbackButton.label = "^4Fallback Nodes"
	end)
	controls.fallbackWeightsButton.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		tooltip:AddLine(16, "^7Click this button to generate new fallback node weights, replacing your old ones.")
	end

	controls.searchListButton = new("ButtonControl", {"TOPLEFT", nil, "TOPLEFT"}, {12, 250, 106, 20}, "^7Desired Nodes", function()
		if controls.searchListFallback.shown then
			controls.searchListFallback.shown = false
			controls.searchListFallback.enabled = false
			controls.searchList.shown = true
			controls.searchList.enabled = true
		end
	end)
	controls.searchListButton.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		tooltip:AddLine(16, "^7This contains a list of your desired nodes along with their primary, secondary, and minimum weights.")
		tooltip:AddLine(16, "^7This list can be updated manually or by selecting the node you want to update via the search dropdown list and then moving the node weight sliders.")
	end
	controls.searchListButton.locked = function() return controls.searchList.shown end
	controls.searchListFallbackButton = new("ButtonControl", {"LEFT", controls.searchListButton, "RIGHT"}, {5, 0, 110, 20}, "^7Fallback Nodes", function()
		controls.searchList.shown = false
		controls.searchList.enabled = false
		controls.searchListFallback.shown = true
		controls.searchListFallback.enabled = true
		controls.searchListFallbackButton.label = "^7Fallback Nodes"
	end)
	controls.searchListFallbackButton.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		tooltip:AddLine(16, "^7This contains a list of your fallback nodes along with their primary, secondary, and minimum weights.")
		tooltip:AddLine(16, "^7This list can be updated manually or by selecting the node you want to update via the search dropdown list and then moving the node weight sliders.")
		tooltip:AddLine(16, "^7Fallback node weights are only used when no matching entry exists in the desired nodes list, allowing you to override or disable specific automatic weights.")
		tooltip:AddLine(16, "^7Fallback node weights typically contain automatically generated stat weights based on your current build.")
		tooltip:AddLine(16, "^7Any manual changes made to your fallback nodes are lost when you click the generate button, as it completely replaces them.")
	end
	controls.searchListFallbackButton.locked = function() return controls.searchListFallback.shown end
	controls.searchList = new("EditControl", {"TOPLEFT", nil, "TOPLEFT"}, {12, 275, 438, 200}, timelessData.searchList, nil, "^%C\t\n", nil, function(value)
		timelessData.searchList = value
		parseSearchList(0, false)
		self.build.modFlag = true
	end, 16, true)
	controls.searchList.shown = true
	controls.searchList.enabled = true
	controls.searchList:SetText(timelessData.searchList and timelessData.searchList or "")
	controls.searchListFallback = new("EditControl", {"TOPLEFT", nil, "TOPLEFT"}, {12, 275, 438, 200}, timelessData.searchListFallback, nil, "^%C\t\n", nil, function(value)
		timelessData.searchListFallback = value
		parseSearchList(0, true)
		self.build.modFlag = true
	end, 16, true)
	controls.searchListFallback.shown = false
	controls.searchListFallback.enabled = false
	controls.searchListFallback:SetText(timelessData.searchListFallback and timelessData.searchListFallback or "")

	controls.searchResultsLabel = new("LabelControl", { "TOPLEFT", nil, "TOPRIGHT" }, { -450, 250, 0, 16 }, "^7Search Results:")
	controls.searchResults = new("TimelessJewelListControl", { "TOPLEFT", nil, "TOPRIGHT" }, { -450, 275, 438, 200 }, self.build)
	controls.searchTradeLeagueSelect = new("DropDownControl", { "BOTTOMRIGHT", controls.searchResults, "TOPRIGHT" }, { -175, -5, 140, 20 }, nil, function(_, value)
		self.timelessJewelLeagueSelect = value
	end)
	self.tradeQueryRequests = new("TradeQueryRequests")
	controls.msg = new("LabelControl", nil, { -280, 5, 0, 16 }, "")
	if #self.tradeLeaguesList > 0 then
		controls.searchTradeLeagueSelect:SetList(self.tradeLeaguesList)
		-- restore the last league selected
		for i, league in ipairs(self.tradeLeaguesList) do
			if league == self.timelessJewelLeagueSelect then
				controls.searchTradeLeagueSelect:SetSel(i)
				break
			end
		end
	else
		self.tradeQueryRequests:FetchLeagues("poe2", function(leagues, errMsg)
			if errMsg then
				controls.msg.label = "^1Error fetching league list, default league will be used\n"..errMsg.."^7"
				return
			end
			local tempLeagueTable = { }
			for _, league in ipairs(leagues) do
				if league ~= "Standard" and league ~= "Hardcore" then
					if not league:find("Hardcore") then
						-- set the dynamic, base league name to index 1 to sync league shown in dropdown on load with default/old behavior of copy trade url
						t_insert(tempLeagueTable, league)
						for _, val in ipairs(self.tradeLeaguesList) do
							t_insert(tempLeagueTable, val)
						end
						self.tradeLeaguesList = copyTable(tempLeagueTable)
					else
						t_insert(self.tradeLeaguesList, league)
					end
				end
			end
			t_insert(self.tradeLeaguesList, "Standard")
			t_insert(self.tradeLeaguesList, "Hardcore")
			controls.searchTradeLeagueSelect:SetList(self.tradeLeaguesList)
		end)
	end
	controls.searchTradeButton = new("ButtonControl", { "BOTTOMRIGHT", controls.searchResults, "TOPRIGHT" }, { 0, -5, 170, 20 }, "Copy Trade URL", function()
		local seedTrades = {}
		local startRow = controls.searchResults.selIndex or 1
		local endRow = startRow + m_floor(10 / ((timelessData.sharedResults.conqueror.id == 1) and 3 or 1))
		if controls.searchResults.highlightIndex then
			startRow = m_min(controls.searchResults.selIndex, controls.searchResults.highlightIndex)
			endRow = m_max(controls.searchResults.selIndex, controls.searchResults.highlightIndex)
		end

		local seedCount = m_min(#timelessData.searchResults - startRow, endRow - startRow) + 1
		-- update if not highlighted already

		local prevSearch = controls.searchTradeButton.lastSearch
		if prevSearch and prevSearch[1] == startRow and prevSearch[2] == seedCount then
			startRow = endRow + 1
			if (startRow > #timelessData.searchResults) then
				return
			end
			seedCount = m_min(#timelessData.searchResults - startRow + 1, seedCount)
			endRow = startRow + seedCount - 1
		end
		controls.searchResults.selIndex = startRow
		controls.searchResults.highlightIndex = endRow

		controls.searchTradeButton.lastSearch = {startRow, seedCount}

		for i = startRow, startRow + seedCount - 1 do
			local result = timelessData.searchResults[i]

			local conquerorKeystoneTradeIds = data.timelessJewelTradeIDs[timelessData.jewelType.id].keystone
			local conquerorTradeIds = { conquerorKeystoneTradeIds[1], conquerorKeystoneTradeIds[2], conquerorKeystoneTradeIds[3] }
			if timelessData.sharedResults.conqueror.id > 1 then
				conquerorTradeIds = { conquerorKeystoneTradeIds[timelessData.sharedResults.conqueror.id - 1] }
			end

			for _, tradeId in ipairs(conquerorTradeIds) do
				t_insert(seedTrades, {
					id = tradeId,
					value = {
						min = result.seed,
						max = result.seed
					}
				})
			end
		end

		local search = {
			query = {
				status = {
					option = "available"
				},
				stats = {
					{
						filters = seedTrades,
						type = "count",
						value = {
							min = 1
						}
					}
				}
			},
			sort = {
				price = "asc"
			}
		}

		if data.timelessJewelTradeIDs[timelessData.jewelType.id].devotion ~= nil then
			local devotionFilters = {}
			if timelessData.sharedResults.devotionVariant1.id > 1 then
				t_insert(devotionFilters, { id = data.timelessJewelTradeIDs[timelessData.jewelType.id].devotion[timelessData.sharedResults.devotionVariant1.id - 1] })
			end
			if timelessData.sharedResults.devotionVariant2.id > 1 then
				t_insert(devotionFilters, { id = data.timelessJewelTradeIDs[timelessData.jewelType.id].devotion[timelessData.sharedResults.devotionVariant2.id - 1] })
			end
			if next(devotionFilters) then
				t_insert(search.query.stats, {
					filters = devotionFilters,
					type = "and"
				})
			end
		end

		-- if the league was not selected via dropdown, then default to the first league in the dropdown or "" if the leagues could not be read
		self.timelessJewelLeagueSelect = self.timelessJewelLeagueSelect or (self.tradeLeaguesList and #self.tradeLeaguesList > 0 and self.tradeLeaguesList[1]) or ""

		Copy("https://www.pathofexile.com/trade/search/"..(self.timelessJewelLeagueSelect).."/?q=" .. (s_gsub(dkjson.encode(search), "[^a-zA-Z0-9]", function(a)
			return s_format("%%%02X", s_byte(a))
		end)))

		controls.searchTradeButton.label = "Copy Next Trade URL"
	end)
	controls.searchTradeButton.enabled = timelessData.searchResults and #timelessData.searchResults > 0
	controls.searchTradeButton.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		tooltip:AddLine(16, "^7Click to generate and copy a trade URL for searching for jewels in this list.")
		tooltip:AddLine(16, "^7Paste the URL in a web browser to search.")
		tooltip:AddLine(16, "")
		tooltip:AddLine(16, "^7You can click to select a row so that search begins from there.")
		tooltip:AddLine(16, "^7After selecting a row You can also shift+click on another row to select a range of rows to search.")
	end

	local width = 80
	local divider = 10
	local buttons = 3
	local totalWidth = m_floor(width * buttons + divider * (buttons - 1))
	local buttonX = -totalWidth / 2 + width / 2

	controls.searchButton = new("ButtonControl", nil, {buttonX, 485, width, 20}, "Search", function()
		if treeData.nodes[timelessData.jewelSocket.id] and treeData.nodes[timelessData.jewelSocket.id].isJewelSocket then
			local radiusNodes = treeData.nodes[timelessData.jewelSocket.id].nodesInRadius[3] -- large radius around timelessData.jewelSocket.id
			local allocatedNodes = { }
			local unAllocatedNodesDistance = { }
			local targetNodes = { }
			local targetSmallNodes = { ["attributeSmalls"] = 0, ["otherSmalls"] = 0 }
			local desiredNodes = { }
			local minimumWeights = { }
			local resultNodes = { }
			local rootNodes = { }
			local desiredIdx = 0
			local searchListCombinedTbl = { }
			local searchListNodeFound = { }
			for _, curRow in ipairs(searchListTbl) do
				searchListNodeFound[curRow[1]] = true
				searchListCombinedTbl[#searchListCombinedTbl + 1] = copyTable(curRow)
			end
			for _, curRow in ipairs(searchListFallbackTbl) do
				if not searchListNodeFound[curRow[1]] then
					searchListCombinedTbl[#searchListCombinedTbl + 1] = copyTable(curRow)
				end
			end
			for _, desiredNode in ipairs(searchListCombinedTbl) do
				if #desiredNode > 1 then
					local displayName = nil
					local singleStat = false
					if totalMods[timelessData.jewelType.id] and desiredNode[1] == "total_" .. totalMods[timelessData.jewelType.id]:lower() then
						desiredNode[1] = "totalStat"
						displayName = totalMods[timelessData.jewelType.id]
					end
					if displayName == nil then
						for _, legionNode in ipairs(legionNodes) do
							if legionNode.id == desiredNode[1] then
								-- non-vaal replacements only support one nodeWeight
								if timelessData.jewelType.id > 1 then
									singleStat = true
								end
								displayName = t_concat(legionNode.sd, " + ")
								break
							end
						end
					end
					if displayName == nil then
						for _, legionAddition in ipairs(legionAdditions) do
							if legionAddition.id == desiredNode[1] then
								-- additions only support one nodeWeight
								singleStat = true
								displayName = t_concat(legionAddition.sd, " + ")
								break
							end
						end
					end
					if displayName ~= nil then
						for i, val in ipairs(desiredNode) do
							if singleStat and i == 2 then
								desiredNode[2] = tonumber(desiredNode[2]) or tonumber(desiredNode[3]) or 1
							end
							if val == "required" then
								desiredNode[i] = (singleStat and i == 2) and desiredNode[2] or 0
								if desiredNode[4] == nil or desiredNode[4] < 0.001 then
									desiredNode[4] = 0.001
								end
							end
						end
						if desiredNode[4] ~= nil and tonumber(desiredNode[4]) > 0 then
							t_insert(minimumWeights, { reqNode = desiredNode[1], weight = tonumber(desiredNode[4]) })
						end
						-- if we're protecting a node and the number of protected nodes is less than the total allocated in radius and the total desired nodes is less than the total allocated in radius
						-- these constraints avoid a blank result in the case where you set a min weight of 1 onto a non devotion stat with zero unprotected nodes
						if protectedNodesCount > 0 and protectedNodesCount < self.allocatedNodesInRadiusCount and (#searchListCombinedTbl < self.allocatedNodesInRadiusCount) then
							t_insert(minimumWeights, { reqNode = desiredNode[1], weight = 1 })
						end
						if desiredNodes[desiredNode[1]] then
							desiredNodes[desiredNode[1]] = {
								nodeWeight = tonumber(desiredNode[2]) or 0.001,
								nodeWeight2 = tonumber(desiredNode[3]) or 0.001,
								displayName = displayName or desiredNode[1],
								desiredIdx = desiredNodes[desiredNode[1]].desiredIdx
							}
						else
							desiredIdx = desiredIdx + 1
							desiredNodes[desiredNode[1]] = {
								nodeWeight = tonumber(desiredNode[2]) or 0.001,
								nodeWeight2 = tonumber(desiredNode[3]) or 0.001,
								displayName = displayName or desiredNode[1],
								desiredIdx = desiredIdx
							}
						end
					end
				end
			end
			wipeTable(searchListCombinedTbl)
			for _, class in pairs(treeData.classes) do
				rootNodes[class.startNodeId] = true
			end
			if controls.socketFilter.state then
				timelessData.socketFilterDistance = timelessData.socketFilterDistance or 0
				for nodeId in pairs(radiusNodes) do
					allocatedNodes[nodeId] = self.build.calcsTab.mainEnv.grantedPassives[nodeId] ~= nil or self.build.spec.allocNodes[nodeId] ~= nil
					if timelessData.socketFilterDistance > 0 then
						unAllocatedNodesDistance[nodeId] = self.build.spec.nodes[nodeId].pathDist or 1000
					end
				end
			end
			for nodeId in pairs(radiusNodes) do
				if not rootNodes[nodeId]
				and not treeData.nodes[nodeId].isJewelSocket
				and not treeData.nodes[nodeId].isKeystone
				and (not controls.socketFilter.state or allocatedNodes[nodeId] or (timelessData.socketFilterDistance > 0 and unAllocatedNodesDistance[nodeId] <= timelessData.socketFilterDistance)) then
					if (treeData.nodes[nodeId].isNotable or timelessData.jewelType.id == 1) then
						targetNodes[nodeId] = true
					elseif desiredNodes["totalStat"] and not treeData.nodes[nodeId].isNotable then
						if isValueInArray({ "Strength", "Intelligence", "Dexterity" }, treeData.nodes[nodeId].dn) then
							targetSmallNodes.attributeSmalls = targetSmallNodes.attributeSmalls + 1
						else
							targetSmallNodes.otherSmalls = targetSmallNodes.otherSmalls + 1
						end
					end
				end
			end
			local seedWeights = { }
			local seedMultiplier = timelessData.jewelType.id == 5 and 20 or 1 -- Elegant Hubris
			for curSeed = data.timelessJewelSeedMin[timelessData.jewelType.id] * seedMultiplier, data.timelessJewelSeedMax[timelessData.jewelType.id] * seedMultiplier, seedMultiplier do
				seedWeights[curSeed] = 0
				resultNodes[curSeed] = { }
				for targetNode in pairs(targetNodes) do
					local jewelDataTbl = data.readLUT(curSeed, targetNode, timelessData.jewelType.id)
					if not next(jewelDataTbl) then
						ConPrintf("Missing LUT: " .. timelessData.jewelType.label)
					else
						local curNode = nil
						local curNodeId = nil
						if (timelessData.jewelType.id == 4 and isValueInTable(protectedNodes, treeData.nodes[targetNode].dn)) then
							if not desiredNodes["totalStat"] then -- only add if user has not entered their own Devotion to the table
								desiredNodes["totalStat"] = {
									nodeWeight = 0.1, -- keeps total score low to let desired stats decide sort
									nodeWeight2 = 0,
									displayName = "Devotion",
									desiredIdx = desiredIdx + 1
								}
							end
							curNodeId = "totalStat"
						end
						if jewelDataTbl[1] >= data.timelessJewelAdditions and not isValueInTable(protectedNodes, treeData.nodes[targetNode].dn) then -- replace
							curNode = legionNodes[jewelDataTbl[1] + 1 - data.timelessJewelAdditions]
							curNodeId = curNode and legionNodes[jewelDataTbl[1] + 1 - data.timelessJewelAdditions].id or nil
						else -- add
							curNode = legionAdditions[jewelDataTbl[1] + 1]
							curNodeId = curNode and legionAdditions[jewelDataTbl[1] + 1].id or nil
						end
						if desiredNodes["totalStat"] and reverseTotalModIDs[curNodeId] then
							curNodeId = "totalStat"
						end
						if timelessData.jewelType.id == 1 then
							local headerSize = #jewelDataTbl
							if headerSize == 2 or headerSize == 3 then
								if desiredNodes[curNodeId] then
									resultNodes[curSeed][curNodeId] = resultNodes[curSeed][curNodeId] or { targetNodeNames = { }, totalWeight = 0 }
									local statMod1 = curNode.stats[curNode.sortedStats[1]]
									local weight = desiredNodes[curNodeId].nodeWeight * jewelDataTbl[statMod1.index + 1]
									local statMod2 = curNode.stats[curNode.sortedStats[2]]
									if statMod2 then
										weight = weight + desiredNodes[curNodeId].nodeWeight2 * jewelDataTbl[statMod2.index + 1]
									end
									t_insert(resultNodes[curSeed][curNodeId], targetNode)
									t_insert(resultNodes[curSeed][curNodeId].targetNodeNames, treeData.nodes[targetNode].name)
									resultNodes[curSeed][curNodeId].totalWeight = resultNodes[curSeed][curNodeId].totalWeight + weight
									seedWeights[curSeed] = seedWeights[curSeed] + weight
								end
							elseif headerSize == 6 or headerSize == 8 then
								for i, jewelData in ipairs(jewelDataTbl) do
									curNode = legionAdditions[jewelDataTbl[i] + 1]
									curNodeId = curNode and legionAdditions[jewelDataTbl[i] + 1].id or nil
									if i <= (headerSize / 2) then
										if desiredNodes[curNodeId] then
											resultNodes[curSeed][curNodeId] = resultNodes[curSeed][curNodeId] or { targetNodeNames = { }, totalWeight = 0 }
											local weight = desiredNodes[curNodeId].nodeWeight * jewelDataTbl[i + (headerSize / 2)]
											resultNodes[curSeed][curNodeId].totalWeight = resultNodes[curSeed][curNodeId].totalWeight + weight
											t_insert(resultNodes[curSeed][curNodeId], targetNode)
											t_insert(resultNodes[curSeed][curNodeId].targetNodeNames, treeData.nodes[targetNode].name)
											seedWeights[curSeed] = seedWeights[curSeed] + weight
										end
									else
										break
									end
								end
							end
						elseif desiredNodes[curNodeId] then
							resultNodes[curSeed][curNodeId] = resultNodes[curSeed][curNodeId] or { targetNodeNames = { }, totalWeight = 0 }
							resultNodes[curSeed][curNodeId].totalWeight = resultNodes[curSeed][curNodeId].totalWeight + desiredNodes[curNodeId].nodeWeight
							t_insert(resultNodes[curSeed][curNodeId], targetNode)
							t_insert(resultNodes[curSeed][curNodeId].targetNodeNames, treeData.nodes[targetNode].name)
							seedWeights[curSeed] = seedWeights[curSeed] + desiredNodes[curNodeId].nodeWeight
						end
					end
				end
				if desiredNodes["totalStat"] then
					resultNodes[curSeed]["totalStat"] = resultNodes[curSeed]["totalStat"] or { targetNodeNames = { }, totalWeight = 0 }
					if timelessData.jewelType.id == 4 then -- Militant Faith
						local addedWeight = desiredNodes["totalStat"].nodeWeight * (5 * targetSmallNodes.otherSmalls + 10 * targetSmallNodes.attributeSmalls)
						addedWeight = addedWeight + resultNodes[curSeed]["totalStat"].totalWeight * 4
						resultNodes[curSeed]["totalStat"].totalWeight = resultNodes[curSeed]["totalStat"].totalWeight + addedWeight
						seedWeights[curSeed] = seedWeights[curSeed] + addedWeight
					else
						local addedWeight = desiredNodes["totalStat"].nodeWeight * (4 * targetSmallNodes.otherSmalls + 2 * targetSmallNodes.attributeSmalls)
						addedWeight = addedWeight + resultNodes[curSeed]["totalStat"].totalWeight * 19
						resultNodes[curSeed]["totalStat"].totalWeight = resultNodes[curSeed]["totalStat"].totalWeight + addedWeight
						seedWeights[curSeed] = seedWeights[curSeed] + addedWeight
					end
				end
				-- check minimum weights
				for _, val in ipairs(minimumWeights) do
					if (resultNodes[curSeed][val.reqNode] and resultNodes[curSeed][val.reqNode].totalWeight or 0) < val.weight then
						resultNodes[curSeed] = nil
						break
					end
				end
			end
			wipeTable(timelessData.searchResults)
			wipeTable(timelessData.sharedResults)
			timelessData.sharedResults.type = timelessData.jewelType
			timelessData.sharedResults.conqueror = timelessData.conquerorType
			timelessData.sharedResults.devotionVariant1 = devotionVariants[timelessData.devotionVariant1]
			timelessData.sharedResults.devotionVariant2 = devotionVariants[timelessData.devotionVariant2]
			timelessData.sharedResults.socket = timelessData.jewelSocket
			timelessData.sharedResults.desiredNodes = desiredNodes
			local function formatSearchValue(input)
				local   matchPattern1 = " 0"
				local replacePattern1 = "   "
				local   matchPattern2 = ".0 "
				local replacePattern2 = "    "
				local   matchPattern3 = "  %."
				local replacePattern3 = "0."
				local   matchPattern4 = "%.([0-9])0"
				local replacePattern4 = ".%1  "
				return (" " .. s_format("%006.2f", input))
				:gsub(matchPattern1, replacePattern1):gsub(matchPattern1, replacePattern1)
				:gsub(matchPattern2, replacePattern2):gsub(matchPattern2, replacePattern2)
				:gsub(matchPattern3, replacePattern3)
				:gsub(matchPattern4, replacePattern4)
			end
			local searchResultsIdx = 1
			for seedMatch, seedData in pairs(resultNodes) do
				if seedWeights[seedMatch] > 0 then
					timelessData.searchResults[searchResultsIdx] = { label = seedMatch .. ":" }
					if timelessData.jewelType.id == 1 or timelessData.jewelType.id == 3 then
						-- Glorious Vanity [100-8000], Brutal Restraint [500-8000]
						if seedMatch < 1000 then
							timelessData.searchResults[searchResultsIdx].label = "  " .. timelessData.searchResults[searchResultsIdx].label
						end
					elseif timelessData.jewelType.id == 4 then
						-- Militant Faith [2000-10000]
						if seedMatch < 10000 then
							timelessData.searchResults[searchResultsIdx].label = "  " .. timelessData.searchResults[searchResultsIdx].label
						end
					else
						-- Elegant Hubris [2000-160000]
						if seedMatch < 10000 then
							timelessData.searchResults[searchResultsIdx].label = "    " .. timelessData.searchResults[searchResultsIdx].label
						elseif seedMatch < 100000 then
							timelessData.searchResults[searchResultsIdx].label = "  " .. timelessData.searchResults[searchResultsIdx].label
						end
					end
					local sortedNodeArray = { }
					for legionId, desiredNode in pairs(desiredNodes) do
						if seedData[legionId] then
							if desiredNode.desiredIdx == 8 then
								sortedNodeArray[8] = " ..."
							elseif desiredNode.desiredIdx < 8 then
								sortedNodeArray[desiredNode.desiredIdx] = formatSearchValue(seedData[legionId].totalWeight)
							end
							timelessData.searchResults[searchResultsIdx][legionId] = timelessData.searchResults[searchResultsIdx][legionId] or { }
							timelessData.searchResults[searchResultsIdx][legionId].targetNodeNames = seedData[legionId].targetNodeNames
						elseif desiredNode.desiredIdx < 8 then
							sortedNodeArray[desiredNode.desiredIdx] = "     0     "
						end
					end
					timelessData.searchResults[searchResultsIdx].label = timelessData.searchResults[searchResultsIdx].label .. t_concat(sortedNodeArray)
					timelessData.searchResults[searchResultsIdx].seed = seedMatch
					timelessData.searchResults[searchResultsIdx].total = seedWeights[seedMatch]
					searchResultsIdx = searchResultsIdx + 1
				end
			end
			t_sort(timelessData.searchResults, function(a, b) return a.total > b.total end)
			controls.searchTradeButton.enabled = timelessData.searchResults and #timelessData.searchResults > 0
			controls.searchTradeButton.lastSearch = nil
			controls.searchTradeButton.label = "Copy Trade URL"
			controls.searchResults.highlightIndex = nil
			controls.searchResults.selIndex = 1
		end
	end)
	controls.resetButton = new("ButtonControl", nil, {buttonX + (width + divider), 485, width, 20}, "Reset", function()
		updateSearchList("", true)
		updateSearchList("", false)
		wipeTable(timelessData.searchResults)
		controls.searchTradeButton.enabled = false
		clearProtected()
	end)
	controls.closeButton = new("ButtonControl", nil, {buttonX + (width + divider) * 2, 485, width, 20}, "Cancel", function()
		main:ClosePopup()
	end)

	main:OpenPopup(910, 517, "Find a Timeless Jewel", controls)
end


-- Auto Allocate Tree
function TreeTabClass:AutoAllocateTree()
	if self.build.autoAllocateBuilder then return end
	local spec = self.build.spec
	local candidateCount = 0
	for nodeId, node in pairs(spec.nodes) do
		if not node.alloc and not node.ascendancyName and node.path and node.modKey ~= "" then
			candidateCount = candidateCount + 1
		end
	end
	if candidateCount == 0 then return end
	local controls = { }
	local attributes = { "Strength", "Dexterity", "Intelligence" }
	controls.attrSelect = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, {225, 30, 100, 18}, attributes, function()
		-- Show the tooltip note when selection changes
	end)
	controls.start = new("ButtonControl", nil, {-50, 65, 80, 20}, "Start", function()
		spec.attributeIndex = controls.attrSelect.selIndex
		main:ClosePopup()
		self:AutoAllocateTreeConfirmed(candidateCount)
	end)
	controls.close = new("ButtonControl", nil, {50, 65, 80, 20}, "Cancel", function()
		main:ClosePopup()
	end)
	controls.tooltip = new("LabelControl", nil, {0, 100, 0, 16},
		"^8Choose the attribute type for pathing nodes.\n"..
		"All attribute nodes on the path will use this selection.")
	main:OpenPopup(450, 135, "Auto Allocate Tree - Attribute Selection", controls, "start")
end

function TreeTabClass:AutoAllocateTreeConfirmed(candidateCount)
	if candidateCount == 0 then return end
	if self.build.autoAllocateBuilder then return end
	self.build.autoAllocateProgress = "Starting..."
	self.build.autoAllocateBuilder = coroutine.create(function()
		local spec = self.build.spec

		local totalPoints = (self.build.characterLevel - 1)
		if self.build.acts and self.build.acts[self.build.maxActs] then
			totalPoints = totalPoints + (self.build.acts[self.build.maxActs].questPoints or 0)
		end
		local origNormal = totalPoints
		self.build.autoAllocateProgress = string.format(
			"Level %d, %d points available...", self.build.characterLevel, origNormal)
		coroutine.yield()

		wipeTable(spec.hashOverrides)
		spec:ResetNodes()
		spec:BuildAllDependsAndPaths()

		local calcFunc = self.build.calcsTab:GetMiscCalculator()
		local baseOutput = calcFunc({ }, false)
		local emptyTreeDamage = baseOutput.AverageDamage or 0
		local initialUndoState = spec:CreateUndoState()

		local cache = { }
		local candidates = { }
		local nodeIndex = 0
		local yieldEvery = 5

		for nodeId, node in pairs(spec.nodes) do
			if not node.alloc and not node.ascendancyName and node.path and node.modKey ~= "" then
				if not cache[node.modKey] then
					cache[node.modKey] = calcFunc({ addNodes = { [node] = true } }, false)
				end
				local power = (cache[node.modKey].AverageDamage or 0) - emptyTreeDamage
				t_insert(candidates, { node = node, power = power, modKey = node.modKey })
			end
			nodeIndex = nodeIndex + 1
			if nodeIndex % yieldEvery == 0 then
				local pct = m_floor(nodeIndex / candidateCount * 100)
				self.build.autoAllocateProgress = string.format(
					"Phase 1: Evaluating nodes... %d / %d nodes (%d%%)", nodeIndex, candidateCount, pct)
				coroutine.yield()
			end
		end


				local function getNodeCost(node)
			if #node.intuitiveLeapLikesAffecting > 0 then
				local n = node
				if not n.alloc and n.type ~= "ClassStart" and n.type ~= "AscendClassStart" and not n.ascendancyName then
					return 1
				end
				return 0
			end
			local cost = 0
			if node.path then
				for _, pathNode in ipairs(node.path) do
					if not pathNode.alloc and pathNode.type ~= "ClassStart" and pathNode.type ~= "AscendClassStart" and not pathNode.ascendancyName then
						cost = cost + 1
					end
				end
			end
			return cost
		end

-- Pre-compute cost for each candidate
		for _, cand in ipairs(candidates) do
			cand.cost = getNodeCost(cand.node)
		end
		t_sort(candidates, function(a, b)
			local ratioA = a.cost > 0 and (a.power / a.cost) or a.power
			local ratioB = b.cost > 0 and (b.power / b.cost) or b.power
			if ratioA ~= ratioB then return ratioA > ratioB end
			return a.power > b.power
		end)



		local allocated = { }
		local allocatedModKeys = { }
		local pointsUsed = 0

		for i = 1, #candidates do
			local cand = candidates[i]
			if cand.power <= 0 then break end
			if pointsUsed >= origNormal then break end
			if not allocatedModKeys[cand.modKey] then
				local newNodes = 0
				if #cand.node.intuitiveLeapLikesAffecting > 0 then
					local n = cand.node
					if not n.alloc and n.type ~= "ClassStart" and n.type ~= "AscendClassStart" and not n.ascendancyName then
						newNodes = 1
					end
				else
					for _, pathNode in ipairs(cand.node.path) do
						local n = pathNode
						if not n.alloc and n.type ~= "ClassStart" and n.type ~= "AscendClassStart" and not n.ascendancyName then
							newNodes = newNodes + 1
						end
					end
				end
				if pointsUsed + newNodes <= origNormal then
					spec:AllocNode(cand.node)
					pointsUsed = pointsUsed + newNodes
					t_insert(allocated, { node = cand.node, points = newNodes })
					allocatedModKeys[cand.modKey] = true
					if pointsUsed % 10 == 0 then
						self.build.autoAllocateProgress = string.format(
							"Phase 2: Allocating... %d / %d", pointsUsed, origNormal)
						coroutine.yield()
					end
				end
			end
		end

		spec:BuildAllDependsAndPaths()
		spec:AddUndoState()
		self.build.buildFlag = true

		-- Helper: count allocated normal nodes
		local function countAlloc()
			local c = 0
			for _, n in pairs(spec.allocNodes) do
				if n.type ~= "ClassStart" and n.type ~= "AscendClassStart" and n.isFreeAllocate == nil and not n.ascendancyName then
					c = c + 1
				end
			end
			return c
		end

		-- ========================================================================
		-- PHASE 3: Fine-tuning -- remove each allocated node and check if damage
		-- improves or stays the same (meaning the node was redundant).
		-- ========================================================================
		local currentDamage = calcFunc({ }, false).AverageDamage or 0
		self.build.autoAllocateProgress = string.format(
			"Phase 3: Fine-tuning %d nodes...", #allocated)
		coroutine.yield()

		for _, entry in ipairs(allocated) do
			local node = entry.node
			if node.alloc then
				spec:DeallocNode(node)
				spec:BuildAllDependsAndPaths()
				local newDamage = calcFunc({ }, false).AverageDamage or 0
				if newDamage >= currentDamage then
					currentDamage = newDamage
				else
					spec:AllocNode(node)
					spec:BuildAllDependsAndPaths()
					currentDamage = calcFunc({ }, false).AverageDamage or 0
				end
			end
			if node.id % 20 == 0 then
				self.build.autoAllocateProgress = string.format(
					"Phase 3: Fine-tuning... (node %d)", node.id)
				coroutine.yield()
			end
		end

		self.build.autoAllocateProgress = string.format(
			"Phase 3: Fine-tuned, %d nodes remain", #allocated)
		coroutine.yield()

		-- ========================================================================
		-- REFINEMENT LOOP: re-check allocations after tree state changes
		-- ========================================================================
		for refineRound = 1, 2 do
			self.build.autoAllocateProgress = string.format(
				"Refine round %d/2: Fine-tuning %d nodes...", refineRound, #allocated)
			coroutine.yield()

			local removedAny = false
			for idx = #allocated, 1, -1 do
				local entry = allocated[idx]
				local node = entry.node
				if node.alloc then
					spec:DeallocNode(node)
					spec:BuildAllDependsAndPaths()
					local dmg = calcFunc({ }, false).AverageDamage or 0
					if dmg >= currentDamage then
						currentDamage = dmg
						t_remove(allocated, idx)
						removedAny = true
					else
						spec:AllocNode(node)
						spec:BuildAllDependsAndPaths()
					end
				end
				if idx % 10 == 0 then
					self.build.autoAllocateProgress = string.format(
						"Refine round %d/2: Fine-tuning... %d / %d", refineRound, #allocated - idx, #allocated)
					coroutine.yield()
				end
			end

			-- Phase 3b: Cascading fine-tune
			local cascadeRemoved = 0
			local cascadeChanged = true
			while cascadeChanged do
				cascadeChanged = false
				for idx = #allocated, 1, -1 do
					local entry = allocated[idx]
					local node = entry.node
					if node.alloc then
						spec:DeallocNode(node)
						spec:BuildAllDependsAndPaths()
						local dmg = calcFunc({ }, false).AverageDamage or 0
						if dmg >= currentDamage then
							currentDamage = dmg
							t_remove(allocated, idx)
							cascadeRemoved = cascadeRemoved + 1
							cascadeChanged = true
						else
							spec:AllocNode(node)
							spec:BuildAllDependsAndPaths()
						end
					end
				end
				if cascadeRemoved % 3 == 0 and cascadeRemoved > 0 then
					self.build.autoAllocateProgress = string.format(
						"Refine round %d/2: Cascading fine-tune... removed %d", refineRound, cascadeRemoved)
					coroutine.yield()
				end
			end

			if removedAny or cascadeRemoved > 0 then
				spec:AddUndoState()
				self.build.buildFlag = true
			end
			self.build.autoAllocateProgress = string.format(
				"Refine round %d/2: %d nodes + %d cascaded removed", refineRound, #allocated, cascadeRemoved)
			coroutine.yield()
		end

		-- ========================================================================
		-- PHASE 3c: Re-evaluate already-allocated mastery effects.
		-- ========================================================================
		self.build.autoAllocateProgress = "Phase 3c: Re-evaluating mastery effects..."
		coroutine.yield()
		local masteryChanges = 0
		local masteryIdx = 0
		for _, entry in ipairs(allocated) do
			local node = entry.node
			if node.alloc and node.type == "Mastery" and node.masteryEffects and #node.masteryEffects > 0 then
				local currentEffect = spec.masterySelections[node.id]
				if currentEffect then
					local baselineDamage = calcFunc({ }, false).AverageDamage or 0
					local bestPower = 0
					local bestEffect = currentEffect
					for _, me in ipairs(node.masteryEffects) do
						spec.masterySelections[node.id] = me.effect
						spec:BuildAllDependsAndPaths()
						local out = calcFunc({ }, false)
						local power = (out.AverageDamage or 0) - baselineDamage
						if power > bestPower then bestPower = power; bestEffect = me.effect end
					end
					if bestEffect ~= currentEffect then
						spec.masterySelections[node.id] = bestEffect
						masteryChanges = masteryChanges + 1
					end
					spec:BuildAllDependsAndPaths()
				end
			end
			masteryIdx = masteryIdx + 1
			if masteryIdx % 3 == 0 then
				self.build.autoAllocateProgress = string.format(
					"Phase 3c: Re-evaluating masteries... %d / %d", masteryIdx, #allocated)
				coroutine.yield()
			end
		end

		if masteryChanges > 0 then
			spec:AddUndoState()
			self.build.buildFlag = true
		end
		self.build.autoAllocateProgress = string.format(
			"Phase 3c: Changed %d mastery effects", masteryChanges)
		coroutine.yield()

		-- Update currentDamage for swap optimisation
		currentDamage = calcFunc({ }, false).AverageDamage or 0

		-- ========================================================================
		-- PHASE 3.5: Multi-round swap optimisation
		-- Runs up to 3 rounds of weak->strong node replacement.
		-- ========================================================================
		local totalSwapAttempts = 0
		local swapRoundsDone = 0

		for swapRound = 1, 3 do
			if #allocated <= 0 then break end

			self.build.autoAllocateProgress = string.format(
				"Phase 3.5 round %d/3: Swapping weak nodes...", swapRound)
			coroutine.yield()

			-- Collect allocated entries sorted by ratio ascending (worst first)
			local allocatedOrder = { }
			for _, entry in ipairs(allocated) do
				if entry.node.alloc then
					local cost = getNodeCost(entry.node)
					if cost > 0 then
						t_insert(allocatedOrder, {
							entry = entry,
							ratio = (entry.power or 0) / cost,
						})
					end
				end
			end
			t_sort(allocatedOrder, function(a, b) return a.ratio < b.ratio end)

			-- Build unallocated candidates from Phase 1 data
			local unallocCands = { }
			for _, cand in ipairs(candidates) do
				if not cand.node.alloc then
					local cost = getNodeCost(cand.node)
					if cost > 0 then
						t_insert(unallocCands, {
							cand = cand,
							cost = cost,
							ratio = (cand.power or 0) / cost,
						})
					end
				end
			end
			t_sort(unallocCands, function(a, b)
				if a.ratio ~= b.ratio then return a.ratio > b.ratio end
				return (a.cand.power or 0) > (b.cand.power or 0)
			end)

			local swapSuccesses = 0
			local maxSwapAttempts = 10

			for _, weak in ipairs(allocatedOrder) do
				local weakNode = weak.entry.node
				if not weakNode.alloc then break end
				if swapSuccesses >= maxSwapAttempts then break end

				-- Snapshot state before swap attempt
				local allocSnapshot = { }
				for id, n in pairs(spec.allocNodes) do
					allocSnapshot[id] = n
				end
				local masterySnapshot = { }
				for id, eid in pairs(spec.masterySelections) do
					masterySnapshot[id] = eid
				end

				-- Deallocate weak node and note how many points are freed
				local beforeAlloc = 0
				for id, n in pairs(spec.allocNodes) do
					if n.type ~= "ClassStart" and n.type ~= "AscendClassStart" and not n.ascendancyName then
						beforeAlloc = beforeAlloc + 1
					end
				end
				spec:DeallocNode(weakNode)
				spec:BuildAllDependsAndPaths()
				local afterDealloc = 0
				for id, n in pairs(spec.allocNodes) do
					if n.type ~= "ClassStart" and n.type ~= "AscendClassStart" and not n.ascendancyName then
						afterDealloc = afterDealloc + 1
					end
				end
				local freedPoints = beforeAlloc - afterDealloc

				if freedPoints <= 0 then
					-- Restore and skip
					for id, n in pairs(spec.allocNodes) do
						n.alloc = false
						spec.allocNodes[id] = nil
					end
					for id, n in pairs(allocSnapshot) do
						n.alloc = true
						spec.allocNodes[id] = n
					end
					wipeTable(spec.masterySelections)
					for id, eid in pairs(masterySnapshot) do
						spec.masterySelections[id] = eid
					end
					spec:BuildAllDependsAndPaths()
					goto continue_swap
				end

				-- Find the best unallocated candidate that fits in freed budget
				local bestSwapCand = nil
				for _, uc in ipairs(unallocCands) do
					if not uc.cand.node.alloc and uc.cost <= freedPoints then
						bestSwapCand = uc
						break
					end
				end

				if not bestSwapCand then
					-- Nothing fits -- restore
					for id, n in pairs(spec.allocNodes) do
						n.alloc = false
						spec.allocNodes[id] = nil
					end
					for id, n in pairs(allocSnapshot) do
						n.alloc = true
						spec.allocNodes[id] = n
					end
					wipeTable(spec.masterySelections)
					for id, eid in pairs(masterySnapshot) do
						spec.masterySelections[id] = eid
					end
					spec:BuildAllDependsAndPaths()
					goto continue_swap
				end

				-- Allocate the replacement candidate
				local replCand = bestSwapCand.cand
				if replCand.node.type == "Mastery" and replCand.bestEffect then
					spec:AllocNode(replCand.node)
					spec.masterySelections[replCand.node.id] = replCand.bestEffect
				else
					spec:AllocNode(replCand.node)
				end
				spec:BuildAllDependsAndPaths()

				-- Check if damage improved
				local newDamage = calcFunc({ }, false).AverageDamage or 0
				if newDamage > currentDamage then
					currentDamage = newDamage
					swapSuccesses = swapSuccesses + 1
				else
					-- Revert to pre-swap state
					for id, n in pairs(spec.allocNodes) do
						n.alloc = false
						spec.allocNodes[id] = nil
					end
					for id, n in pairs(allocSnapshot) do
						n.alloc = true
						spec.allocNodes[id] = n
					end
					wipeTable(spec.masterySelections)
					for id, eid in pairs(masterySnapshot) do
						spec.masterySelections[id] = eid
					end
					spec:BuildAllDependsAndPaths()
				end

				if swapSuccesses % 3 == 0 then
					self.build.autoAllocateProgress = string.format(
						"Phase 3.5 round %d/3: %d swaps so far...", swapRound, swapSuccesses)
					coroutine.yield()
				end

				::continue_swap::
			end

			if swapSuccesses > 0 then
				spec:AddUndoState()
				self.build.buildFlag = true
			end

			totalSwapAttempts = totalSwapAttempts + swapSuccesses
			swapRoundsDone = swapRound

			self.build.autoAllocateProgress = string.format(
				"Phase 3.5 round %d/3: %d swaps", swapRound, swapSuccesses)
			coroutine.yield()

			if swapSuccesses == 0 then break end
		end

		self.build.autoAllocateProgress = string.format(
			"Phase 3.5: %d total swaps across %d rounds", totalSwapAttempts, swapRoundsDone)
		coroutine.yield()


		-- ========================================================================
		-- BUDGET REFILL: After Phase 3/Refine/3c/3.5, scan unallocated candidates
		-- with fresh DPS evaluation and allocate best fitting freed budget.
		-- ========================================================================
		self.build.autoAllocateProgress = "Budget Refill: Scanning for refill candidates..."
		coroutine.yield()

		local refillBudget = origNormal - countAlloc()
		if refillBudget > 0 then
			-- Build fresh candidate list from current tree state
			local refillCands = { }
			local refillCount = 0
			local refillMax = 50
			for _, cand in ipairs(candidates) do
				if not cand.node.alloc and not allocatedModKeys[cand.modKey] then
					if refillCount >= refillMax then break end
					local cost = getNodeCost(cand.node)
					if cost > 0 and cost <= refillBudget then
						local out = calcFunc({ addNodes = { [cand.node] = true } }, false)
						local freshPower = (out.AverageDamage or 0) - currentDamage
						if freshPower > 0 then
							t_insert(refillCands, {
								cand = cand,
								cost = cost,
								power = freshPower,
								ratio = freshPower / cost,
							})
						end
						refillCount = refillCount + 1
					end
				end
			end
			t_sort(refillCands, function(a, b)
				if a.ratio ~= b.ratio then return a.ratio > b.ratio end
				return a.power > b.power
			end)

			local refilled = 0
			for _, rc in ipairs(refillCands) do
				if refillBudget <= 0 then break end
				if not rc.cand.node.alloc and rc.cost <= refillBudget then
					if rc.cand.node.type == "Mastery" and rc.cand.bestEffect then
						spec:AllocNode(rc.cand.node)
						spec.masterySelections[rc.cand.node.id] = rc.cand.bestEffect
					else
						spec:AllocNode(rc.cand.node)
					end
					refillBudget = refillBudget - rc.cost
					refilled = refilled + 1
					allocatedModKeys[rc.cand.modKey] = true
					t_insert(allocated, { node = rc.cand.node, points = rc.cost })
				end
			end

			if refilled > 0 then
				spec:BuildAllDependsAndPaths()
				spec:AddUndoState()
				self.build.buildFlag = true
			end

			self.build.autoAllocateProgress = string.format(
				"Budget Refill: Added %d nodes, %d points used", refilled, origNormal - refillBudget)
			coroutine.yield()
		end

		currentDamage = calcFunc({ }, false).AverageDamage or 0

		-- ========================================================================
		-- PHASE 5: Scan all unallocated nodes for missed strong nodes
		-- ========================================================================
		self.build.autoAllocateProgress = "Phase 5: Scanning for missed strong nodes..."
		coroutine.yield()

		local phase5Baseline = calcFunc({ }, true)
		local phase5BaseDPS = phase5Baseline.CombinedDPS or phase5Baseline.AverageDamage or 0

		-- Collect all unallocated non-socket, non-ascendancy nodes with a path
		local phase5Cands = { }
		for nodeId, node in pairs(spec.nodes) do
			if not node.alloc and node.path and not node.ascendancyName and node.type ~= "Socket" then
				if node.type == "Normal" or node.type == "Notable" or node.type == "Keystone" or node.type == "Mastery" then
					t_insert(phase5Cands, node)
				end
			end
		end

		-- Score candidates by DPS boost (up to 20 evaluations)
		local phase5Scored = { }
		local phase5EvalCount = 0
		local phase5MaxEval = 20

		self.build.autoAllocateProgress = string.format(
			"Phase 5: Evaluating %d unallocated nodes...", math.min(#phase5Cands, phase5MaxEval))
		coroutine.yield()

		for _, node in ipairs(phase5Cands) do
			if phase5EvalCount >= phase5MaxEval then break end
			local out = calcFunc({ addNodes = { [node] = true } }, true)
			local dps = out.CombinedDPS or out.AverageDamage or 0
			local boost = dps - phase5BaseDPS
			if boost > 0 then
				t_insert(phase5Scored, { node = node, boost = boost })
			end
			phase5EvalCount = phase5EvalCount + 1
			if phase5EvalCount % 5 == 0 then
				self.build.autoAllocateProgress = string.format(
					"Phase 5: Evaluating... %d / %d", phase5EvalCount, phase5MaxEval)
				coroutine.yield()
			end
		end
		t_sort(phase5Scored, function(a, b) return a.boost > b.boost end)

		local phase5HotCount = math.min(5, #phase5Scored)
		local phase5Swaps = 0
		local phase5MaxTotalSwaps = 5

		if phase5HotCount > 0 then
			-- Build weakest-allocated list
			local phase5WeakOrder = { }
			for _, entry in ipairs(allocated) do
				if entry.node.alloc then
					local cost = getNodeCost(entry.node)
					if cost > 0 then
						t_insert(phase5WeakOrder, { entry = entry, cost = cost, ratio = (entry.power or 0) / cost })
					end
				end
			end
			t_sort(phase5WeakOrder, function(a, b) return a.ratio < b.ratio end)
			local phase5MaxWeak = math.min(10, #phase5WeakOrder)

			self.build.autoAllocateProgress = string.format(
				"Phase 5: Trying %d hot vs %d weak...", phase5HotCount, phase5MaxWeak)
			coroutine.yield()

			for hi = 1, phase5HotCount do
				local hot = phase5Scored[hi]
				if phase5Swaps >= phase5MaxTotalSwaps then break end
				if not hot.node.alloc then
					for wi = 1, phase5MaxWeak do
						local weak = phase5WeakOrder[wi]
						if phase5Swaps >= phase5MaxTotalSwaps then break end
						if weak.entry.node.alloc and not hot.node.alloc then
							local hotCost = getNodeCost(hot.node)
							if hotCost > 0 and hotCost <= weak.cost + 1 then
							-- Snapshot
							local snap = { }
							for id, n in pairs(spec.allocNodes) do
								snap[id] = n
							end
							local masterySnap = { }
							for id, eid in pairs(spec.masterySelections) do
								masterySnap[id] = eid
							end

							-- Deallocate weak, check freed budget
							local beforeDealloc = 0
							for id, n in pairs(spec.allocNodes) do
								if n.type ~= "ClassStart" and n.type ~= "AscendClassStart" and not n.ascendancyName then
								beforeDealloc = beforeDealloc + 1
								end
							end
							spec:DeallocNode(weak.entry.node)
							spec:BuildAllDependsAndPaths()
							local afterDealloc = 0
							for id, n in pairs(spec.allocNodes) do
								if n.type ~= "ClassStart" and n.type ~= "AscendClassStart" and not n.ascendancyName then
								afterDealloc = afterDealloc + 1
								end
							end
							local freedPoints = beforeDealloc - afterDealloc

							if freedPoints > 0 and hotCost <= freedPoints then
								spec:AllocNode(hot.node)
								spec:BuildAllDependsAndPaths()
								local newOut = calcFunc({ }, true)
								local newDPS = newOut.CombinedDPS or newOut.AverageDamage or 0
								if newDPS > phase5BaseDPS then
									phase5BaseDPS = newDPS
									phase5Swaps = phase5Swaps + 1
									spec:AddUndoState()
									self.build.buildFlag = true
									self.build.autoAllocateProgress = string.format(
										"Phase 5: Swap %d successful", phase5Swaps)
									coroutine.yield()
								else
									-- Revert
									for id, n in pairs(spec.allocNodes) do
										n.alloc = false
										spec.allocNodes[id] = nil
									end
									for id, n in pairs(snap) do
										n.alloc = true
										spec.allocNodes[id] = n
									end
									wipeTable(spec.masterySelections)
									for id, eid in pairs(masterySnap) do
										spec.masterySelections[id] = eid
									end
									spec:BuildAllDependsAndPaths()
								end
							else
								-- Not enough budget freed, revert deallocation
								for id, n in pairs(spec.allocNodes) do
									n.alloc = false
									spec.allocNodes[id] = nil
								end
								for id, n in pairs(snap) do
									n.alloc = true
									spec.allocNodes[id] = n
								end
								wipeTable(spec.masterySelections)
								for id, eid in pairs(masterySnap) do
									spec.masterySelections[id] = eid
								end
								spec:BuildAllDependsAndPaths()
							end
							end
						end
					end
				end
			end

			if phase5Swaps > 0 then
				spec:AddUndoState()
				self.build.buildFlag = true
			end
		end

		self.build.autoAllocateProgress = string.format(
			"Phase 5: %d heatmap swaps", phase5Swaps)
		coroutine.yield()

		-- Check if overall damage improved; rollback if not
		local finalDamage = calcFunc({ }, false).AverageDamage or 0
		if finalDamage < emptyTreeDamage - 1 then
			self.build.autoAllocateProgress = string.format(
				"Rolling back: damage dropped from %d to %d", emptyTreeDamage, finalDamage)
			coroutine.yield()
			spec:RestoreUndoState(initialUndoState)
			spec:BuildAllDependsAndPaths()
			self.build.buildFlag = true
			self.build.autoAllocateProgress = "Rolled back: tree restored to pre-optimization state"
			coroutine.yield()
		end

		self.build.autoAllocateProgress = "Auto allocation complete!"
		coroutine.yield()
		self.build.autoAllocateProgress = nil
		self.build.autoAllocateBuilder = nil
	end)
end

function TreeTabClass:ResumeAutoAllocate()
	local builder = self.build.autoAllocateBuilder
	if builder and coroutine.status(builder) ~= "dead" then
		local res, errMsg = coroutine.resume(builder)
		if not res then error(errMsg) end
		if coroutine.status(builder) == "dead" then
			self.controls.autoAllocate.enabled = true
			self.controls.autoAllocate.label = "Auto Allocate Tree"
			self.build.autoAllocateProgress = nil
			self.build.autoAllocateBuilder = nil
		end
	end
end

-- Remove the allocated node that contributes the least to AverageDamage
function TreeTabClass:RemoveWorstAllocatedNode()
	if self.build.autoAllocateBuilder then return end

	local spec = self.build.spec
	local calcFunc = self.build.calcsTab:GetMiscCalculator()
	local currentDamage = calcFunc({ }, false).AverageDamage or 0

	local testNodes = { }
	for nodeId, node in pairs(spec.allocNodes) do
		if node.type ~= "ClassStart" and node.type ~= "AscendClassStart"
		   and node.isFreeAllocate == nil and not node.ascendancyName then
			t_insert(testNodes, node)
		end
	end

	if #testNodes == 0 then return end

	local allocSnapshot = { }
	for id, node in pairs(spec.allocNodes) do
		allocSnapshot[id] = node.alloc
	end
	local hashSnapshot = { }
	for id, node in pairs(spec.hashOverrides) do
		hashSnapshot[id] = node
	end

	local worstNode = nil
	local smallestDelta = math.huge

	for _, node in ipairs(testNodes) do
		for id, alloced in pairs(allocSnapshot) do
			local n = spec.nodes[id]
			if n then
				n.alloc = alloced
				spec.allocNodes[id] = alloced and n or nil
			end
		end
		for id, attrNode in pairs(hashSnapshot) do
			spec.hashOverrides[id] = attrNode
		end
		spec:BuildAllDependsAndPaths()

		spec:DeallocSingleNode(node)
		spec:BuildAllDependsAndPaths()
		local newDamage = calcFunc({ }, false).AverageDamage or 0
		local delta = currentDamage - newDamage

		if delta < smallestDelta then
			smallestDelta = delta
			worstNode = node
		end
	end

	if worstNode then
		for id, alloced in pairs(allocSnapshot) do
			local n = spec.nodes[id]
			if n then
				n.alloc = alloced
				spec.allocNodes[id] = alloced and n or nil
			end
		end
		for id, attrNode in pairs(hashSnapshot) do
			spec.hashOverrides[id] = attrNode
		end
		spec:BuildAllDependsAndPaths()

		spec:DeallocSingleNode(worstNode)
		spec:BuildAllDependsAndPaths()

		spec:AddUndoState()
		self.build.buildFlag = true
	end
end




function TreeTabClass:AutoAllocateJewels()
	if self.build.autoAllocateJewelsBuilder then return end
	local spec = self.build.spec
	local totalCandidates = 0
	for nodeId, node in pairs(spec.nodes) do
		if not node.alloc and not node.ascendancyName and node.path and node.modKey ~= "" then
			totalCandidates = totalCandidates + 1
		end
	end
	if totalCandidates == 0 then return end
	local controls = { }
	local attributes = { "Strength", "Dexterity", "Intelligence" }
	controls.attrSelect = new("DropDownControl", {"TOPLEFT",nil,"TOPLEFT"}, {225, 30, 100, 18}, attributes, nil)
	controls.start = new("ButtonControl", nil, {-50, 65, 80, 20}, "Start", function()
		spec.attributeIndex = controls.attrSelect.selIndex
		main:ClosePopup()
		self:AutoAllocateJewelsConfirmed(totalCandidates)
	end)
	controls.close = new("ButtonControl", nil, {50, 65, 80, 20}, "Cancel", function()
		main:ClosePopup()
	end)
	controls.tooltip = new("LabelControl", nil, {0, 100, 0, 16},
		"^8Choose the attribute type for pathing nodes.\n"..
		"All attribute nodes on the path will use this selection.")
	main:OpenPopup(450, 135, "Auto Allocate Jewels - Attribute Selection", controls, "start")
end

-- List of individual jewel mods to test for socket evaluation
local JEWEL_MOD_TEXTS = {
	"16% increased Global Physical Damage",
	"12% increased Elemental Damage with Attacks",
	"7% increased Attack Speed",
	"16% increased Spell Damage",
	"6% increased Cast Speed",
	"20% to Critical Strike Multiplier",
	"12% increased Fire Damage",
	"12% increased Cold Damage",
	"12% increased Lightning Damage",
	"16% increased Damage over Time",
	"10% increased Area Damage",
	"12% increased Projectile Damage",
	"16% increased Minion Damage",
	"14% increased Chaos Damage",
	"12% increased Damage",
}

function TreeTabClass:AutoAllocateJewelsConfirmed(candidateCount)
	if self.build.autoAllocateJewelsBuilder then return end
	self.build.autoAllocateJewelsProgress = "Starting..."
	self.build.autoAllocateJewelsBuilder = coroutine.create(function()
		local spec = self.build.spec
		local itemsTab = self.build.itemsTab
		local startTime = os.clock()

		-- Count available points (normal nodes, exclude ascendancy/class starts/free)
		local function countNormalAlloc()
			local c = 0
			for _, n in pairs(spec.allocNodes) do
				if n.type ~= "ClassStart" and n.type ~= "AscendClassStart"
				   and n.isFreeAllocate == nil and not n.ascendancyName then
					c = c + 1
				end
			end
			return c
		end

		local totalPoints = (self.build.characterLevel - 1)
		if self.build.acts and self.build.acts[self.build.maxActs] then
			totalPoints = totalPoints + (self.build.acts[self.build.maxActs].questPoints or 0)
		end
		local origNormal = totalPoints

		-- Reset tree to empty baseline (class starts kept)
		wipeTable(spec.hashOverrides)
		wipeTable(spec.masterySelections)
		spec:ResetNodes()
		spec:BuildAllDependsAndPaths()

		local calcFunc = self.build.calcsTab:GetMiscCalculator()
		local baseOutput = calcFunc({ }, false)
		local baselineDamage = baseOutput.AverageDamage or 0

		-- Helper: count unallocated non-essential nodes along a candidate's path
		local function getNodeCost(node)
			if #node.intuitiveLeapLikesAffecting > 0 then
				local n = node
				if not n.alloc and n.type ~= "ClassStart" and n.type ~= "AscendClassStart" and not n.ascendancyName then
					return 1
				end
				return 0
			end
			local cost = 0
			if node.path then
				for _, pathNode in ipairs(node.path) do
					if not pathNode.alloc and pathNode.type ~= "ClassStart" and pathNode.type ~= "AscendClassStart" and not pathNode.ascendancyName then
						cost = cost + 1
					end
				end
			end
			return cost
		end

		-- ========================================================================
		-- PHASE 1: Evaluate every candidate from baseline (empty tree)
		-- Uses the same approach as AutoAllocateTree: calcFunc with addNodes.
		-- Mastery nodes: try each effect separately, record the best one.
		-- ========================================================================
		self.build.autoAllocateJewelsProgress = string.format(
			"Phase 1: Evaluating %d nodes from baseline...", candidateCount)
		coroutine.yield()

		local cache = { }
		local candidates = { }
		local nodeIndex = 0
		local yieldEvery = 5
		local reevalCount = 0

		for nodeId, node in pairs(spec.nodes) do
			local isMastery = node.type == "Mastery"
			-- Skip sockets (handled in Phase 4), include masteries
			if not node.alloc and not node.ascendancyName and node.path and node.modKey ~= ""
			   and node.type ~= "Socket" then
				if isMastery then
					-- Mastery: allocate, try each possible effect, pick the best one
					if node.masteryEffects and #node.masteryEffects > 0 then
						-- Snapshot: allocate the mastery, try each effect, then restore
						local allocSnapshot = { }
						for id_, n_ in pairs(spec.allocNodes) do
							allocSnapshot[id_] = n_
						end
						local masterySnapshot = { }
						for id_, eid_ in pairs(spec.masterySelections) do
							masterySnapshot[id_] = eid_
						end

						spec:AllocNode(node)

						local bestPower = 0
						local bestEffect = nil
						for _, me in ipairs(node.masteryEffects) do
							local effectId = me.effect
							spec.masterySelections[node.id] = effectId
							spec:BuildAllDependsAndPaths()
							local out = calcFunc({ }, false)
							local power = (out.AverageDamage or 0) - baselineDamage
							if power > bestPower then
								bestPower = power
								bestEffect = effectId
							end
						end

						-- Restore snapshot (full state rollback)
						for id_, n_ in pairs(spec.allocNodes) do
							if not allocSnapshot[id_] then
								n_.alloc = false
								spec.allocNodes[id_] = nil
							end
						end
						wipeTable(spec.masterySelections)
						for id_, eid_ in pairs(masterySnapshot) do
							spec.masterySelections[id_] = eid_
						end
						spec:BuildAllDependsAndPaths()

						if bestPower > 0 and bestEffect then
							t_insert(candidates, {
								node = node,
								power = bestPower,
								modKey = node.modKey,
								bestEffect = bestEffect,
							})
						end
					end
				else
					if not cache[node.modKey] then
						cache[node.modKey] = calcFunc({ addNodes = { [node] = true } }, false)
						reevalCount = reevalCount + 1
					end
					local power = (cache[node.modKey].AverageDamage or 0) - baselineDamage
					t_insert(candidates, {
						node = node,
						power = power,
						modKey = node.modKey,
					})
				end
			end
			nodeIndex = nodeIndex + 1
			if nodeIndex % yieldEvery == 0 then
				local pct = m_floor(nodeIndex / candidateCount * 100)
				self.build.autoAllocateJewelsProgress = string.format(
					"Phase 1: Evaluating... %d / %d (%d%%)", nodeIndex, candidateCount, pct)
				coroutine.yield()
			end
		end

		if #candidates == 0 then
			self.build.autoAllocateJewelsProgress = "No beneficial nodes found."
			coroutine.yield()
			self.build.autoAllocateJewelsProgress = nil
			self.build.autoAllocateJewelsBuilder = nil
			return
		end

		self.build.autoAllocateJewelsProgress = string.format(
			"Phase 1: %d positive candidates (%d unique mods + masteries)", #candidates, reevalCount)
		coroutine.yield()

		-- ========================================================================
		-- PHASE 2: Greedy allocation by power-per-point
		-- Each round picks the candidate with best power/cost ratio that fits
		-- remaining budget. After each allocation the tree is rebuilt so
		-- remaining candidates' path costs reflect shared-path savings.
		-- Mastery candidates: also set spec.masterySelections on allocation.
		-- ========================================================================
		self.build.autoAllocateJewelsProgress = string.format(
			"Phase 2: Allocating %d points...", origNormal)
		coroutine.yield()

		local pointsUsed = 0
		local allocated = { }  -- the "head" (target) nodes allocated
		local allocatedModKeys = { }

		-- Pre-compute cost and sort by DPS/point (same as Tree version)
		for _, cand in ipairs(candidates) do
			cand.cost = getNodeCost(cand.node)
		end
		t_sort(candidates, function(a, b)
			local ratioA = a.cost > 0 and (a.power / a.cost) or a.power
			local ratioB = b.cost > 0 and (b.power / b.cost) or b.power
			if ratioA ~= ratioB then return ratioA > ratioB end
			return a.power > b.power
		end)

		for i = 1, #candidates do
			local cand = candidates[i]
			if cand.power <= 0 then break end
			if pointsUsed >= origNormal then break end
			if not allocatedModKeys[cand.modKey] then
				if not cand.node.alloc then
					local cost = getNodeCost(cand.node)
					if cost > 0 and pointsUsed + cost <= origNormal then
						if cand.node.type == "Mastery" and cand.bestEffect then
							spec:AllocNode(cand.node)
							spec.masterySelections[cand.node.id] = cand.bestEffect
						else
							spec:AllocNode(cand.node)
						end
						pointsUsed = pointsUsed + cost
						t_insert(allocated, cand)
						allocatedModKeys[cand.modKey] = true
						if pointsUsed % 10 == 0 then
							self.build.autoAllocateJewelsProgress = string.format(
								"Phase 2: Allocating... %d / %d", pointsUsed, origNormal)
							coroutine.yield()
						end
					end
				end
			end
		end

		spec:BuildAllDependsAndPaths()
		spec:AddUndoState()
		self.build.buildFlag = true

		self.build.autoAllocateJewelsProgress = string.format(
			"Phase 2: %d nodes allocated using %d points", #allocated, countNormalAlloc())
		coroutine.yield()

		-- ========================================================================
		-- PHASE 3: Fine-tuning — remove each allocated node and check if damage
		-- holds.  If damage doesn't drop the node was wasteful (its mods were
		-- already provided by other allocated nodes).
		-- Snapshot includes allocNodes AND masterySelections for correct restore.
		-- ========================================================================
		self.build.autoAllocateJewelsProgress = string.format(
			"Phase 3: Fine-tuning %d nodes...", #allocated)
		coroutine.yield()

		local currentDamage = calcFunc({ }, false).AverageDamage or 0

		for idx, entry in ipairs(allocated) do
			local node = entry.node
			if node.alloc then
				-- Snapshot current state (DeallocNode cascades to dependents)
				local allocSnapshot = { }
				for id, n in pairs(spec.allocNodes) do
					allocSnapshot[id] = n
				end
				local masterySnapshot = { }
				for id, eid in pairs(spec.masterySelections) do
					masterySnapshot[id] = eid
				end

				spec:DeallocNode(node)
				spec:BuildAllDependsAndPaths()
				local newDamage = calcFunc({ }, false).AverageDamage or 0
				if newDamage >= currentDamage then
					currentDamage = newDamage
				else
					-- Restore full snapshot
					for id, n in pairs(spec.allocNodes) do
						n.alloc = false
						spec.allocNodes[id] = nil
					end
					for id, n in pairs(allocSnapshot) do
						n.alloc = true
						spec.allocNodes[id] = n
					end
					wipeTable(spec.masterySelections)
					for id, eid in pairs(masterySnapshot) do
						spec.masterySelections[id] = eid
					end
					spec:BuildAllDependsAndPaths()
					currentDamage = calcFunc({ }, false).AverageDamage or 0
				end
			end
			if idx % 5 == 0 then
				self.build.autoAllocateJewelsProgress = string.format(
					"Phase 3: Fine-tuning... %d / %d", idx, #allocated)
				coroutine.yield()
			end
		end

		spec:AddUndoState()
		self.build.buildFlag = true
		self.build.autoAllocateJewelsProgress = string.format(
			"Phase 3: Fine-tuned, %d nodes remain", countNormalAlloc())
		coroutine.yield()

		-- ========================================================================
		-- REFINEMENT LOOP: Re-evaluate from the current tree, allocate remaining
		-- points, and fine-tune.  Each round corrects the bias from the previous
		-- round's power values and catches nodes that were under/over-rated.
		-- ========================================================================
		for refineRound = 1, 2 do
			self.build.autoAllocateJewelsProgress = string.format(
				"Refinement round %d/2: Re-evaluating...", refineRound)
			coroutine.yield()

			local currentDamage = calcFunc({ }, false).AverageDamage or 0
			local roundCands = { }
			local roundCache = { }
			local rnIdx = 0
			local rnYieldEvery = 5

			for nodeId, node in pairs(spec.nodes) do
				if not node.alloc and not node.ascendancyName and node.path and node.modKey ~= ""
					and node.type ~= "Socket" then
					if node.type == "Mastery" then
						if node.masteryEffects and #node.masteryEffects > 0 then
							local allocSnapshot = { }
							for id_, n_ in pairs(spec.allocNodes) do
								allocSnapshot[id_] = n_
							end
							local masterySnapshot = { }
							for id_, eid_ in pairs(spec.masterySelections) do
								masterySnapshot[id_] = eid_
							end

							spec:AllocNode(node)

							local bestPower = 0
							local bestEffect = nil
							for _, me in ipairs(node.masteryEffects) do
								local effectId = me.effect
								spec.masterySelections[node.id] = effectId
								spec:BuildAllDependsAndPaths()
								local out = calcFunc({ }, false)
								local power = (out.AverageDamage or 0) - currentDamage
								if power > bestPower then
									bestPower = power
									bestEffect = effectId
								end
							end

							for id_, n_ in pairs(spec.allocNodes) do
								if not allocSnapshot[id_] then
									n_.alloc = false
									spec.allocNodes[id_] = nil
								end
							end
							wipeTable(spec.masterySelections)
							for id_, eid_ in pairs(masterySnapshot) do
								spec.masterySelections[id_] = eid_
							end
							spec:BuildAllDependsAndPaths()

							if bestPower > 0 and bestEffect then
								t_insert(roundCands, {
									node = node,
									power = bestPower,
									modKey = node.modKey,
									bestEffect = bestEffect,
								})
							end
						end
					end
				else
					if not roundCache[node.modKey] then
						roundCache[node.modKey] = calcFunc({ addNodes = { [node] = true } }, false)
					end
					local power = (roundCache[node.modKey].AverageDamage or 0) - currentDamage
					if power > 0 then
						t_insert(roundCands, {
							node = node,
							power = power,
							modKey = node.modKey,
						})
					end
				end
				rnIdx = rnIdx + 1
				if rnIdx % rnYieldEvery == 0 then
					self.build.autoAllocateJewelsProgress = string.format(
						"Refinement round %d/2: Re-evaluating... %d nodes processed", refineRound, rnIdx)
					coroutine.yield()
				end
			end

			t_sort(roundCands, function(a, b)
				local ac = getNodeCost(a.node)
				local bc = getNodeCost(b.node)
				local ar = ac > 0 and a.power / ac or 0
				local br = bc > 0 and b.power / bc or 0
				if ar ~= br then return ar > br end
				return a.power > b.power
			end)

			self.build.autoAllocateJewelsProgress = string.format(
				"Refinement round %d/2: %d re-evaluated candidates", refineRound, #roundCands)
			coroutine.yield()

			-- Allocate remaining points with re-evaluated power values
			local roundBudget = origNormal - countNormalAlloc()
			if roundBudget <= 0 or #roundCands == 0 then break end

			self.build.autoAllocateJewelsProgress = string.format(
				"Refinement round %d/2: Allocating %d points...", refineRound, roundBudget)
			coroutine.yield()

			local rpUsed = 0
			local rpAllocated = { }
			local rpAllocatedModKeys = { }
			local rpKept = { }
			for _, cand in ipairs(roundCands) do
				rpKept[#rpKept + 1] = cand
			end

			local rpRoundCount = 0
			while rpUsed < roundBudget and #rpKept > 0 do
				spec:BuildAllDependsAndPaths()

				local bestIdx = nil
				local bestRatio = -1
				local bestPower = -1
				local bestCost = 0

				for idx, cand in ipairs(rpKept) do
					if not rpAllocatedModKeys[cand.modKey] then
						local node = cand.node
						if not node.alloc then
							local cost = getNodeCost(node)
							if cost > 0 and rpUsed + cost <= roundBudget then
								local ratio = cand.power / cost
								if ratio > bestRatio or (ratio == bestRatio and cand.power > bestPower) then
									bestRatio = ratio
									bestPower = cand.power
									bestIdx = idx
									bestCost = cost
								end
							end
						end
					end
				end

				if not bestIdx then break end

				local cand = rpKept[bestIdx]
				if cand.node.type == "Mastery" and cand.bestEffect then
					spec:AllocNode(cand.node)
					spec.masterySelections[cand.node.id] = cand.bestEffect
				else
					spec:AllocNode(cand.node)
				end
				rpUsed = rpUsed + bestCost
				t_insert(rpAllocated, cand)
				rpAllocatedModKeys[cand.modKey] = true
				t_remove(rpKept, bestIdx)

				rpRoundCount = rpRoundCount + 1
				if rpRoundCount % 3 == 0 then
					self.build.autoAllocateJewelsProgress = string.format(
						"Refinement round %d/2: Allocating... %d / %d", refineRound, rpUsed, roundBudget)
					coroutine.yield()
				end
			end

			spec:BuildAllDependsAndPaths()

			for _, cand in ipairs(rpAllocated) do
				t_insert(allocated, cand)
			end

			spec:AddUndoState()
			self.build.buildFlag = true

			self.build.autoAllocateJewelsProgress = string.format(
				"Refinement round %d/2: Allocated %d nodes (%d total)",
					refineRound, #rpAllocated, countNormalAlloc())
			coroutine.yield()

			-- Fine-tune new allocations from this round
			if #rpAllocated > 0 then
				self.build.autoAllocateJewelsProgress = string.format(
					"Refinement round %d/2: Fine-tuning %d new nodes...", refineRound, #rpAllocated)
				coroutine.yield()

				currentDamage = calcFunc({ }, false).AverageDamage or 0

				for idx, entry in ipairs(rpAllocated) do
					local node = entry.node
					if node.alloc then
						local allocSnapshot = { }
						for id_, n_ in pairs(spec.allocNodes) do
							allocSnapshot[id_] = n_
						end
						local masterySnapshot = { }
						for id_, eid_ in pairs(spec.masterySelections) do
							masterySnapshot[id_] = eid_
						end

						spec:DeallocNode(node)
						spec:BuildAllDependsAndPaths()
						local newDamage = calcFunc({ }, false).AverageDamage or 0
						if newDamage >= currentDamage then
							currentDamage = newDamage
						else
							for id_, n_ in pairs(spec.allocNodes) do
								n_.alloc = false
								spec.allocNodes[id_] = nil
							end
							for id_, n_ in pairs(allocSnapshot) do
								n_.alloc = true
								spec.allocNodes[id_] = n_
							end
							wipeTable(spec.masterySelections)
							for id_, eid_ in pairs(masterySnapshot) do
								spec.masterySelections[id_] = eid_
							end
							spec:BuildAllDependsAndPaths()
							currentDamage = calcFunc({ }, false).AverageDamage or 0
						end
					end
					if idx % 5 == 0 then
						self.build.autoAllocateJewelsProgress = string.format(
							"Refinement round %d/2: Fine-tuning... %d / %d", refineRound, idx, #rpAllocated)
						coroutine.yield()
					end
				end

				spec:AddUndoState()
				self.build.buildFlag = true
			end
		end -- for refineRound

		-- ========================================================================
		-- PHASE 3b: Cascading fine-tune -- try removing each allocated node;
		-- some early-allocated nodes may have been made redundant by later ones.
		-- ========================================================================
		self.build.autoAllocateJewelsProgress = string.format(
			"Phase 3b: Cascading fine-tune %d nodes...", #allocated)
		coroutine.yield()

		local cascadeDamage = calcFunc({ }, false).AverageDamage or 0
		local cascadeRemoved = 0

		for idx, entry in ipairs(allocated) do
			local node = entry.node
			if node.alloc then
				local allocSnapshot = { }
				for id_, n_ in pairs(spec.allocNodes) do
					allocSnapshot[id_] = n_
				end
				local masterySnapshot = { }
				for id_, eid_ in pairs(spec.masterySelections) do
					masterySnapshot[id_] = eid_
				end

				spec:DeallocNode(node)
				spec:BuildAllDependsAndPaths()
				local newDamage = calcFunc({ }, false).AverageDamage or 0
				if newDamage >= cascadeDamage then
					cascadeDamage = newDamage
					cascadeRemoved = cascadeRemoved + 1
				else
					for id_, n_ in pairs(spec.allocNodes) do
						n_.alloc = false
						spec.allocNodes[id_] = nil
					end
					for id_, n_ in pairs(allocSnapshot) do
						n_.alloc = true
						spec.allocNodes[id_] = n_
					end
					wipeTable(spec.masterySelections)
					for id_, eid_ in pairs(masterySnapshot) do
						spec.masterySelections[id_] = eid_
					end
					spec:BuildAllDependsAndPaths()
				end
			end
			if idx % 5 == 0 then
				self.build.autoAllocateJewelsProgress = string.format(
					"Phase 3b: Cascading... %d / %d (removed %d)", idx, #allocated, cascadeRemoved)
				coroutine.yield()
			end
		end

		if cascadeRemoved > 0 then
			spec:AddUndoState()
			self.build.buildFlag = true
		end

		self.build.autoAllocateJewelsProgress = string.format(
			"Phase 3b: Removed %d redundant nodes, %d remain",
				cascadeRemoved, countNormalAlloc())
		coroutine.yield()


		-- ========================================================================
		-- BUDGET REFILL: After Phase 3/3b, scan unallocated candidates
		-- with fresh DPS evaluation and allocate best fitting freed budget.
		-- ========================================================================
		self.build.autoAllocateJewelsProgress = "Budget Refill: Scanning for refill candidates..."
		coroutine.yield()

		local refillBudget = origNormal - countNormalAlloc()
		if refillBudget > 0 then
			local refillCands = { }
			local refillCount = 0
			local refillMax = 50
			for _, cand in ipairs(candidates) do
				if not cand.node.alloc and not allocatedModKeys[cand.modKey] then
					if refillCount >= refillMax then break end
					local cost = getNodeCost(cand.node)
					if cost > 0 and cost <= refillBudget then
						local out = calcFunc({ addNodes = { [cand.node] = true } }, false)
						local freshPower = (out.AverageDamage or 0) - currentDamage
						if freshPower > 0 then
							t_insert(refillCands, {
								cand = cand,
								cost = cost,
								power = freshPower,
								ratio = freshPower / cost,
							})
						end
						refillCount = refillCount + 1
					end
				end
			end
			t_sort(refillCands, function(a, b)
				if a.ratio ~= b.ratio then return a.ratio > b.ratio end
				return a.power > b.power
			end)

			local refilled = 0
			for _, rc in ipairs(refillCands) do
				if refillBudget <= 0 then break end
				if not rc.cand.node.alloc and rc.cost <= refillBudget then
					if rc.cand.node.type == "Mastery" and rc.cand.bestEffect then
						spec:AllocNode(rc.cand.node)
						spec.masterySelections[rc.cand.node.id] = rc.cand.bestEffect
					else
						spec:AllocNode(rc.cand.node)
					end
					refillBudget = refillBudget - rc.cost
					refilled = refilled + 1
					allocatedModKeys[rc.cand.modKey] = true
					t_insert(allocated, rc.cand)
				end
			end

			if refilled > 0 then
				spec:BuildAllDependsAndPaths()
				spec:AddUndoState()
				self.build.buildFlag = true
			end

			self.build.autoAllocateJewelsProgress = string.format(
				"Budget Refill: Added %d nodes, %d points used", refilled, origNormal - refillBudget)
			coroutine.yield()
		end

		currentDamage = calcFunc({ }, false).AverageDamage or 0

		-- ========================================================================
		-- PHASE 3c: Re-evaluate already-allocated mastery effects.
		-- Mastery effects were selected in Phase 1 from the empty tree, but
		-- the optimal effect depends on which other nodes are allocated.  This
		-- pass tries every alternative effect for each allocated mastery.
		-- ========================================================================
		self.build.autoAllocateJewelsProgress = "Phase 3c: Re-evaluating mastery effects..."
		coroutine.yield()

		local masteryChanges = 0
		local masteryIdx = 0
		for _, entry in ipairs(allocated) do
			local node = entry.node
			if node.alloc and node.type == "Mastery" and node.masteryEffects and #node.masteryEffects > 0 then
				local currentEffect = spec.masterySelections[node.id]
				if currentEffect then
					local baselineDamage = calcFunc({ }, false).AverageDamage or 0
					local bestPower = 0
					local bestEffect = currentEffect
					for _, me in ipairs(node.masteryEffects) do
						spec.masterySelections[node.id] = me.effect
						spec:BuildAllDependsAndPaths()
						local out = calcFunc({ }, false)
						local power = (out.AverageDamage or 0) - baselineDamage
						if power > bestPower then
							bestPower = power
							bestEffect = me.effect
						end
					end
					if bestEffect ~= currentEffect then
						spec.masterySelections[node.id] = bestEffect
						masteryChanges = masteryChanges + 1
					end
					spec:BuildAllDependsAndPaths()
				end
			end
			masteryIdx = masteryIdx + 1
			if masteryIdx % 3 == 0 then
				self.build.autoAllocateJewelsProgress = string.format(
					"Phase 3c: Re-evaluating masteries... %d / %d", masteryIdx, #allocated)
				coroutine.yield()
			end
		end

		if masteryChanges > 0 then
			spec:AddUndoState()
			self.build.buildFlag = true
		end

		self.build.autoAllocateJewelsProgress = string.format(
			"Phase 3c: Changed %d mastery effects", masteryChanges)
		coroutine.yield()

		-- Update currentDamage for Phase 3.5 swap optimisation
		currentDamage = calcFunc({ }, false).AverageDamage or 0

		-- ========================================================================
		-- PHASE 3.5: Multi-round swap optimisation
		-- Runs up to 3 rounds of weak->strong node replacement. Each round
		-- rebuilds candidate lists since tree state changes after swaps.
		-- ========================================================================
		local totalSwapAttempts = 0
		local swapRoundsDone = 0

		for swapRound = 1, 3 do
			if countNormalAlloc() <= 0 then break end

			self.build.autoAllocateJewelsProgress = string.format(
				"Phase 3.5 round %d/3: Swapping weak nodes...", swapRound)
			coroutine.yield()

			-- Collect allocated entries sorted by ratio ascending (worst first)
			local allocatedOrder = { }
			for _, entry in ipairs(allocated) do
				if entry.node.alloc then
					local cost = getNodeCost(entry.node)
					if cost > 0 then
						t_insert(allocatedOrder, {
							entry = entry,
							ratio = entry.power / cost,
						})
					end
				end
			end
			t_sort(allocatedOrder, function(a, b) return a.ratio < b.ratio end)

			-- Build best unallocated candidates list (sorted by ratio DESC)
			local unallocCands = { }
			for _, cand in ipairs(candidates) do
				if not cand.node.alloc then
					local cost = getNodeCost(cand.node)
					if cost > 0 then
						t_insert(unallocCands, {
							cand = cand,
							cost = cost,
							ratio = cand.power / cost,
						})
					end
				end
			end
			-- Also check allocated[] list for entries that got deallocated
			for _, entry in ipairs(allocated) do
				if not entry.node.alloc then
					local cost = getNodeCost(entry.node)
					if cost > 0 then
						t_insert(unallocCands, {
							cand = entry,
							cost = cost,
							ratio = entry.power / cost,
						})
					end
				end
			end
			t_sort(unallocCands, function(a, b)
				if a.ratio ~= b.ratio then return a.ratio > b.ratio end
				return a.cand.power > b.cand.power
			end)

			local swapSuccesses = 0
			local maxSwapAttempts = 10

			for _, weak in ipairs(allocatedOrder) do
				local weakNode = weak.entry.node
				if not weakNode.alloc then break end
				if swapSuccesses >= maxSwapAttempts then break end

				-- Snapshot state before swap attempt
				local allocSnapshot = { }
				for id, n in pairs(spec.allocNodes) do
					allocSnapshot[id] = n
				end
				local masterySnapshot = { }
				for id, eid in pairs(spec.masterySelections) do
					masterySnapshot[id] = eid
				end

				-- Deallocate weak node and note how many points are freed
				local beforeAlloc = countNormalAlloc()
				spec:DeallocNode(weakNode)
				spec:BuildAllDependsAndPaths()
				local afterDealloc = countNormalAlloc()
				local freedPoints = beforeAlloc - afterDealloc

				if freedPoints <= 0 then
					-- Restore and skip
					for id, n in pairs(spec.allocNodes) do
						n.alloc = false
						spec.allocNodes[id] = nil
					end
					for id, n in pairs(allocSnapshot) do
						n.alloc = true
						spec.allocNodes[id] = n
					end
					wipeTable(spec.masterySelections)
					for id, eid in pairs(masterySnapshot) do
						spec.masterySelections[id] = eid
					end
					spec:BuildAllDependsAndPaths()
					goto continue_swap
				end

				-- Find the best unallocated candidate that fits in freed budget
				local bestSwapCand = nil
				for _, uc in ipairs(unallocCands) do
					if not uc.cand.node.alloc and uc.cost <= freedPoints then
						bestSwapCand = uc
						break
					end
				end

				if not bestSwapCand then
					-- Nothing fits, restore
					for id, n in pairs(spec.allocNodes) do
						n.alloc = false
						spec.allocNodes[id] = nil
					end
					for id, n in pairs(allocSnapshot) do
						n.alloc = true
						spec.allocNodes[id] = n
					end
					wipeTable(spec.masterySelections)
					for id, eid in pairs(masterySnapshot) do
						spec.masterySelections[id] = eid
					end
					spec:BuildAllDependsAndPaths()
					goto continue_swap
				end

				-- Allocate the replacement candidate
				local replCand = bestSwapCand.cand
				if replCand.node.type == "Mastery" and replCand.bestEffect then
					spec:AllocNode(replCand.node)
					spec.masterySelections[replCand.node.id] = replCand.bestEffect
				else
					spec:AllocNode(replCand.node)
				end
				spec:BuildAllDependsAndPaths()

				-- Check if damage improved
				local newDamage = calcFunc({ }, false).AverageDamage or 0
				if newDamage > currentDamage then
					currentDamage = newDamage
					swapSuccesses = swapSuccesses + 1
				else
					-- Revert to pre-swap state
					for id, n in pairs(spec.allocNodes) do
						n.alloc = false
						spec.allocNodes[id] = nil
					end
					for id, n in pairs(allocSnapshot) do
						n.alloc = true
						spec.allocNodes[id] = n
					end
					wipeTable(spec.masterySelections)
					for id, eid in pairs(masterySnapshot) do
						spec.masterySelections[id] = eid
					end
					spec:BuildAllDependsAndPaths()
				end

				if swapSuccesses % 3 == 0 then
					self.build.autoAllocateJewelsProgress = string.format(
						"Phase 3.5 round %d/3: %d swaps so far...", swapRound, swapSuccesses)
					coroutine.yield()
				end

				::continue_swap::
			end

			if swapSuccesses > 0 then
				spec:AddUndoState()
				self.build.buildFlag = true
			end

			totalSwapAttempts = totalSwapAttempts + swapSuccesses
			swapRoundsDone = swapRound

			self.build.autoAllocateJewelsProgress = string.format(
				"Phase 3.5 round %d/3: %d swaps", swapRound, swapSuccesses)
			coroutine.yield()

			if swapSuccesses == 0 then break end
		end

		self.build.autoAllocateJewelsProgress = string.format(
			"Phase 3.5: %d total swaps across %d rounds", totalSwapAttempts, swapRoundsDone)
		coroutine.yield()
		-- ========================================================================
		-- PHASE 4: Allocate reachable sockets (with leftover budget), then
		-- find and insert the best jewels.
		-- ========================================================================
		-- Count spare points after tree optimisation
		local finalAllocCount = countNormalAlloc()
		local sparePoints = origNormal - finalAllocCount

		local socketNodes = { }
		for nodeId, node in pairs(spec.nodes) do
			if not node.alloc and node.type == "Socket" and node.path then
				t_insert(socketNodes, node)
			end
		end

		if #socketNodes > 0 and sparePoints > 0 then
			-- Score socket candidates by DPS/cost, allocate best first
			local baselineOut = calcFunc({ }, true)
			local baselineDPS = baselineOut.CombinedDPS or baselineOut.AverageDamage or 0

			-- Use first 4 JEWEL_MOD_TEXTS as reference for DPS evaluation
			local refMods = { }
			for i = 1, math.min(4, #JEWEL_MOD_TEXTS) do
				t_insert(refMods, JEWEL_MOD_TEXTS[i])
			end
			local refRaw = "Rarity: RARE\nRef Jewel\nRuby\nImplicits: 0\n" .. t_concat(refMods, "\n")

			local scoredSockets = { }
			local evalCount = 0
			local maxEval = 15

			self.build.autoAllocateJewelsProgress = "Phase 4: Evaluating socket DPS..."
			coroutine.yield()

			for _, node in ipairs(socketNodes) do
				local cost = getNodeCost(node)
				if cost > 0 and cost <= sparePoints and evalCount < maxEval then
					local jewel = new("Item", refRaw)
					if jewel and jewel.base then
						local override = {
							addNodes = { [node] = true },
							repSlotName = "Jewel " .. node.id,
							repItem = jewel,
						}
						local out = calcFunc(override, true)
						local dps = out.CombinedDPS or out.AverageDamage or 0
						local boost = dps - baselineDPS
						if boost > 0 then
							t_insert(scoredSockets, { node = node, cost = cost, score = boost / cost })
						else
							t_insert(scoredSockets, { node = node, cost = cost, score = 0 })
						end
						evalCount = evalCount + 1
					end
				elseif cost > 0 and cost <= sparePoints then
					t_insert(scoredSockets, { node = node, cost = cost, score = 0 })
				end
			end

			t_sort(scoredSockets, function(a, b)
				if a.score ~= b.score then return a.score > b.score end
				return a.cost < b.cost
			end)

			for _, scored in ipairs(scoredSockets) do
				if sparePoints <= 0 then break end
				if scored.cost <= sparePoints then
					spec:AllocNode(scored.node)
					sparePoints = sparePoints - scored.cost
				end
			end

			spec:BuildAllDependsAndPaths()
			spec:AddUndoState()
			self.build.buildFlag = true
		end

		-- Count allocated sockets
		local socketCount = 0
		for nodeId, node in pairs(spec.nodes) do
			if node.alloc and node.type == "Socket" then
				socketCount = socketCount + 1
			end
		end

		if socketCount > 0 and itemsTab then
			itemsTab:UpdateSockets()

			self.build.autoAllocateJewelsProgress = string.format(
				"Phase 4: Evaluating jewels for %d sockets...", socketCount)
			coroutine.yield()

			-- Pick first allocated socket as reference for mod evaluation
			local refSocket
			for nodeId, node in pairs(spec.nodes) do
				if node.alloc and node.type == "Socket" then
					refSocket = node
					break
				end
			end

			if refSocket then
				local jewelCalcFunc = self.build.calcsTab:GetMiscCalculator()
				local currentOutput = jewelCalcFunc({ }, true)
				local baseDPS = currentOutput.CombinedDPS or currentOutput.AverageDamage or 0

				-- --- Evaluate individual rare jewel mods ---
				local modBoosts = { }
				for _, modText in ipairs(JEWEL_MOD_TEXTS) do
					local raw = "Rarity: MAGIC\nRuby\nImplicits: 0\n" .. modText
					local jewel = new("Item", raw)
					if jewel and jewel.base then
						local override = {
							addNodes = { [refSocket] = true },
							repSlotName = "Jewel " .. refSocket.id,
							repItem = jewel,
						}
						local out = jewelCalcFunc(override, true)
						local boost = (out.CombinedDPS or out.AverageDamage or 0) - baseDPS
						t_insert(modBoosts, { text = modText, boost = boost })
					end
				end

				t_sort(modBoosts, function(a, b) return a.boost > b.boost end)

				-- Top mods for the rare jewel template
				local templateMods = { }
				for i = 1, math.min(4, #modBoosts) do
					if modBoosts[i].boost > 0 then
						t_insert(templateMods, modBoosts[i].text)
					end
				end

				-- --- Unique jewel candidates ---
				local UNIQUE_JEWEL_RAW = {
					{ name = "Grand Spectrum (Ruby)", raw = "Grand Spectrum\nRuby\nLimited to: 3\n2% increased Maximum Life per socketed Grand Spectrum" },
					{ name = "Grand Spectrum (Emerald)", raw = "Grand Spectrum\nEmerald\nLimited to: 3\n2% increased Spirit per socketed Grand Spectrum" },
					{ name = "Grand Spectrum (Sapphire)", raw = "Grand Spectrum\nSapphire\nVariant: Pre 0.4.0\nVariant: Current\nSelected Variant: 2\nLimited to: 3\n{variant:2}+6% to all Elemental Resistances per socketed Grand Spectrum" },
				}

				local function tryAddUnique(name)
					local sources = { data.uniques.jewel, data.uniques.generated }
					for _, tbl in ipairs(sources) do
						if tbl then
							for _, raw in ipairs(tbl) do
								if raw:match("^" .. name .. "\n") then
									t_insert(UNIQUE_JEWEL_RAW, { name = name, raw = raw })
									return
								end
							end
						end
					end
				end
				if data and data.uniques then
					tryAddUnique("Heroic Tragedy")
					tryAddUnique("Undying Hate")
					tryAddUnique("Against the Darkness")
					tryAddUnique("Heart of the Well")
					tryAddUnique("Prism of Belief")
					tryAddUnique("The Adorned")
					tryAddUnique("Controlled Metamorphosis")
					tryAddUnique("From Nothing")
					tryAddUnique("Megalomaniac")
				end

				local uniqueBoosts = { }
				if #UNIQUE_JEWEL_RAW > 0 then
					self.build.autoAllocateJewelsProgress = string.format(
						"Evaluating %d unique jewels...", #UNIQUE_JEWEL_RAW)
					coroutine.yield()
				end
				for _, entry in ipairs(UNIQUE_JEWEL_RAW) do
					local jewel = new("Item", entry.raw)
					if jewel and jewel.base then
						local override = {
							addNodes = { [refSocket] = true },
							repSlotName = "Jewel " .. refSocket.id,
							repItem = jewel,
						}
						local out = jewelCalcFunc(override, true)
						local boost = (out.CombinedDPS or out.AverageDamage or 0) - baseDPS
						if boost > 0 then
							t_insert(uniqueBoosts, { name = entry.name, raw = entry.raw, boost = boost })
						end
					end
				end
				t_sort(uniqueBoosts, function(a, b) return a.boost > b.boost end)

				-- --- Decide: best unique or best rare combination ---
				local bestRareBoost = #templateMods > 0 and modBoosts[1].boost or 0
				local bestUniqueBoost = #uniqueBoosts > 0 and uniqueBoosts[1].boost or 0

				self.build.autoAllocateJewelsProgress = string.format(
					"Phase 4: Inserting jewels into %d sockets...", socketCount)
				coroutine.yield()

				if bestUniqueBoost > bestRareBoost and #uniqueBoosts > 0 then
					-- Use the best unique jewel (respect Limited to: N)
					local bestEntry = uniqueBoosts[1]
					local maxCount = 999
					for line in bestEntry.raw:gmatch("[^\n]+") do
						local limit = tonumber(line:match("Limited to: (%d+)"))
						if limit then maxCount = limit break end
					end
					local inserted = 0
					for nodeId, node in pairs(spec.nodes) do
						if node.alloc and node.type == "Socket" and inserted < maxCount then
							local jewel = new("Item", bestEntry.raw)
							if jewel and jewel.base then
								itemsTab:AddItem(jewel, true)
								local slot = itemsTab.sockets[nodeId]
								if slot then slot:SetSelItemId(jewel.id) end
								inserted = inserted + 1
							end
						end
					end
					itemsTab:AddUndoState()
				elseif #templateMods > 0 then
					-- Use rare jewels with the 4 best evaluated mods
					local jewelIndex = 0
					for nodeId, node in pairs(spec.nodes) do
						if node.alloc and node.type == "Socket" then
							jewelIndex = jewelIndex + 1
							local title = jewelIndex == 1 and "Optimal Jewel" or "Optimal Jewel " .. jewelIndex
							local raw = "Rarity: RARE\n" .. title .. "\nRuby\nImplicits: 0\n" .. t_concat(templateMods, "\n")
							local jewel = new("Item", raw)
							if jewel and jewel.base then
								itemsTab:AddItem(jewel, true)
								local slot = itemsTab.sockets[nodeId]
								if slot then slot:SetSelItemId(jewel.id) end
							end
						end
					end
					itemsTab:AddUndoState()
				end
				self.build.buildFlag = true
			end
		end

		-- ========================================================================
		-- PHASE 5: Heatmap-inspired final optimisation
		-- Scan all unallocated nodes for strong nodes missed by earlier phases.
		-- ========================================================================
		self.build.autoAllocateJewelsProgress = "Phase 5: Scanning for missed strong nodes..."
		coroutine.yield()

		local phase5Baseline = calcFunc({ }, true)
		local phase5BaseDPS = phase5Baseline.CombinedDPS or phase5Baseline.AverageDamage or 0

		-- Collect all unallocated non-socket, non-ascendancy nodes with a path
		local phase5Cands = { }
		for nodeId, node in pairs(spec.nodes) do
			if not node.alloc and node.path and not node.ascendancyName and node.type ~= "Socket" then
				if node.type == "Normal" or node.type == "Notable" or node.type == "Keystone" or node.type == "Mastery" then
					t_insert(phase5Cands, node)
				end
			end
		end

		-- Score candidates by DPS boost (up to 20 evaluations)
		local phase5Scored = { }
		local phase5EvalCount = 0
		local phase5MaxEval = 20

		self.build.autoAllocateJewelsProgress = string.format(
			"Phase 5: Evaluating %d unallocated nodes...", math.min(#phase5Cands, phase5MaxEval))
		coroutine.yield()

		for _, node in ipairs(phase5Cands) do
			if phase5EvalCount >= phase5MaxEval then break end
			local out = calcFunc({ addNodes = { [node] = true } }, true)
			local dps = out.CombinedDPS or out.AverageDamage or 0
			local boost = dps - phase5BaseDPS
			if boost > 0 then
				t_insert(phase5Scored, { node = node, boost = boost })
			end
			phase5EvalCount = phase5EvalCount + 1
			if phase5EvalCount % 5 == 0 then
				self.build.autoAllocateJewelsProgress = string.format(
					"Phase 5: Evaluating... %d / %d", phase5EvalCount, phase5MaxEval)
				coroutine.yield()
			end
		end
		t_sort(phase5Scored, function(a, b) return a.boost > b.boost end)

		local phase5HotCount = math.min(5, #phase5Scored)
		local phase5Swaps = 0
		local phase5MaxTotalSwaps = 5

		if phase5HotCount > 0 then
			-- Build weakest-allocated list from Phase 2 data
			local phase5WeakOrder = { }
			for _, entry in ipairs(allocated) do
				if entry.node.alloc then
					local cost = getNodeCost(entry.node)
					if cost > 0 then
						t_insert(phase5WeakOrder, { entry = entry, cost = cost, ratio = entry.power / cost })
					end
				end
			end
			t_sort(phase5WeakOrder, function(a, b) return a.ratio < b.ratio end)
			local phase5MaxWeak = math.min(10, #phase5WeakOrder)

			self.build.autoAllocateJewelsProgress = string.format(
				"Phase 5: Trying %d hot vs %d weak...", phase5HotCount, phase5MaxWeak)
			coroutine.yield()

			for hi = 1, phase5HotCount do
				local hot = phase5Scored[hi]
				if phase5Swaps >= phase5MaxTotalSwaps then break end
				if not hot.node.alloc then
					for wi = 1, phase5MaxWeak do
						local weak = phase5WeakOrder[wi]
						if phase5Swaps >= phase5MaxTotalSwaps then break end
						if weak.entry.node.alloc and not hot.node.alloc then
						local hotCost = getNodeCost(hot.node)
						if hotCost > 0 and hotCost <= weak.cost + 1 then

						-- Snapshot current tree state
						local snap = { }
						for id, n in pairs(spec.allocNodes) do
							snap[id] = n
						end
						local masterySnap = { }
						for id, eid in pairs(spec.masterySelections) do
							masterySnap[id] = eid
						end

						-- Deallocate weak, check freed budget
						local beforeDealloc = countNormalAlloc()
						spec:DeallocNode(weak.entry.node)
						spec:BuildAllDependsAndPaths()
						local afterDealloc = countNormalAlloc()
						local freedPoints = beforeDealloc - afterDealloc

						if freedPoints > 0 and hotCost <= freedPoints then
							-- Allocate hot node
							spec:AllocNode(hot.node)
							spec:BuildAllDependsAndPaths()

							local newOut = calcFunc({ }, true)
							local newDPS = newOut.CombinedDPS or newOut.AverageDamage or 0

							if newDPS > phase5BaseDPS then
								phase5BaseDPS = newDPS
								phase5Swaps = phase5Swaps + 1
								spec:AddUndoState()
								self.build.buildFlag = true
								self.build.autoAllocateJewelsProgress = string.format(
									"Phase 5: Swap %d successful", phase5Swaps)
								coroutine.yield()
							else
								-- Revert
								for id, n in pairs(spec.allocNodes) do
									n.alloc = false
									spec.allocNodes[id] = nil
								end
								for id, n in pairs(snap) do
									n.alloc = true
									spec.allocNodes[id] = n
								end
								wipeTable(spec.masterySelections)
								for id, eid in pairs(masterySnap) do
									spec.masterySelections[id] = eid
								end
								spec:BuildAllDependsAndPaths()
							end
						else
							-- Not enough budget freed, revert deallocation
							for id, n in pairs(spec.allocNodes) do
								n.alloc = false
								spec.allocNodes[id] = nil
							end
							for id, n in pairs(snap) do
								n.alloc = true
								spec.allocNodes[id] = n
							end
							wipeTable(spec.masterySelections)
							for id, eid in pairs(masterySnap) do
								spec.masterySelections[id] = eid
							end
							spec:BuildAllDependsAndPaths()
						end
						end
						end
					end
				end
			end

			if phase5Swaps > 0 then
				spec:AddUndoState()
				self.build.buildFlag = true
			end
		end

		self.build.autoAllocateJewelsProgress = string.format(
			"Phase 5: %d heatmap swaps", phase5Swaps)
		coroutine.yield()
		local elapsed = m_floor((os.clock() - startTime) * 10) / 10
		self.build.autoAllocateJewelsProgress = string.format(
			"Done: %d nodes + %d jewels optimized (%.1fs)",
			countNormalAlloc(), socketCount, elapsed)
		coroutine.yield()
		self.build.autoAllocateJewelsProgress = nil
		self.build.autoAllocateJewelsBuilder = nil
	end)
end

function TreeTabClass:ResumeAutoAllocateJewels()
	local builder = self.build.autoAllocateJewelsBuilder
	if builder and coroutine.status(builder) ~= "dead" then
		local res, errMsg = coroutine.resume(builder)
		if not res then error(errMsg) end
		if coroutine.status(builder) == "dead" then
			self.controls.autoAllocateJewels.enabled = true
			self.controls.autoAllocateJewels.label = "Auto Allocate Jewels"
			self.build.autoAllocateJewelsProgress = nil
			self.build.autoAllocateJewelsBuilder = nil
		end
	end
end
