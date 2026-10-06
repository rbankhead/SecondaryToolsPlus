-- SecondaryToolsPlus: one combined settings panel for all five merged
-- features, Leatrix_Plus-style - one long scrollable list of labeled
-- sections rather than five separate panels. Hand-built with plain
-- CreateFrame + stock templates (not the Settings-system initializers:
-- Settings.RegisterProxySetting + Settings.CreateCheckbox/CreateDropdown is
-- CONFIRMED BROKEN on this client - a checkbox's write never reached its
-- saved value in-game, while this exact hand-built CreateFrame approach,
-- already proven in the original standalone SwingTimerBuffTracking panel,
-- worked fine) and registered via Settings.RegisterCanvasLayoutCategory.

local Addon = SecondaryToolsPlus

local Options = {}
Addon.Options = Options

local category
local panel

----------------------------------------------------------------------------
-- Shared widget helpers (ported from the original SwingTimerBuffTracking
-- options panel, the only one of the five that needed anything beyond plain
-- checkboxes/dropdowns).
----------------------------------------------------------------------------

local function MakeCheck(parent, text, onClick)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	local label = c.Text or c.text or c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:ClearAllPoints()
	label:SetPoint("LEFT", c, "RIGHT", 2, 1)
	label:SetText(text)
	c:SetScript("OnClick", function(self)
		onClick(self:GetChecked() and true or false)
	end)
	return c
end

local function MakeSlider(parent, label, minValue, maxValue, step, onChange)
	local s = CreateFrame("Slider", nil, parent, "UISliderTemplateWithLabels")
	s:SetWidth(220)
	s:SetHeight(17)
	s:SetMinMaxValues(minValue, maxValue)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s.Text:SetText(label)
	s.Low:SetText(tostring(minValue))
	s.High:SetText(tostring(maxValue))

	local valueText = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	valueText:SetPoint("LEFT", s, "RIGHT", 12, 0)
	s.valueText = valueText

	s:SetScript("OnValueChanged", function(self, value)
		value = math.floor(value + 0.5)
		valueText:SetText(tostring(value))
		onChange(value)
	end)

	return s
end

local function MakeButton(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

local function MakeBox(parent, width)
	local b = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	b:SetSize(width or 220, 20)
	b:SetAutoFocus(false)
	b:SetScript("OnEscapePressed", b.ClearFocus)
	return b
end

-- items is a list of { label, value, tooltip }. MenuUtil.CreateRadioMenu has
-- no per-item tooltip hook, so SetupMenu (what it calls internally) is used
-- directly here so each radio item can carry its own tooltip via
-- :SetTitleAndTextTooltip.
local function MakeRadioDropdown(parent, width, items, isSelected, setSelected)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(width)
	dropdown:SetupMenu(function(_, rootDescription)
		for _, item in ipairs(items) do
			local radio = rootDescription:CreateRadio(item.label, isSelected, setSelected, item.value)
			radio:SetTitleAndTextTooltip(item.label, item.tooltip)
		end
	end)
	return dropdown
end

local LIST_ROWS = 6 -- fixed visible rows; longer lists scroll instead of growing the panel
local LIST_ROW_HEIGHT = 18

-- A label, an Add box+button, and a fixed LIST_ROWS-tall window of entries
-- (each with its own "x" remove button) that scrolls via a manual slider, so
-- a long list can't push the panel taller than expected. topLeft is an
-- explicit {x, y} pair (this panel tracks a running Y cursor rather than
-- anchor-chaining to the previous widget, so every section's total height is
-- known up front for sizing the scroll child).
local function MakeListEditor(parent, x, y, titleText, addFn, removeFn, getList)
	local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	label:SetWidth(300)
	label:SetJustifyH("LEFT")
	label:SetText(titleText)

	local box = MakeBox(parent, 170)
	box:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 4, -6)

	local addBtn = MakeButton(parent, "Add", 70, nil)
	addBtn:SetPoint("LEFT", box, "RIGHT", 6, 1)

	local rows = {}
	for i = 1, LIST_ROWS do
		local text = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		text:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -6 - (i - 1) * LIST_ROW_HEIGHT)
		text:SetWidth(220)
		text:SetJustifyH("LEFT")

		local removeBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
		removeBtn:SetSize(20, 18)
		removeBtn:SetPoint("LEFT", text, "RIGHT", 6, 0)
		removeBtn:SetText("x")

		rows[i] = { text = text, removeBtn = removeBtn }
	end

	local scrollBar = CreateFrame("Slider", nil, parent)
	scrollBar:SetOrientation("VERTICAL")
	scrollBar:SetWidth(14)
	scrollBar:SetPoint("TOPLEFT", rows[1].removeBtn, "TOPRIGHT", 10, 0)
	scrollBar:SetPoint("BOTTOMLEFT", rows[LIST_ROWS].removeBtn, "BOTTOMRIGHT", 10, 0)
	local track = scrollBar:CreateTexture(nil, "BACKGROUND")
	track:SetAllPoints()
	if track.SetColorTexture then
		track:SetColorTexture(0, 0, 0, 0.35)
	end
	local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture([[Interface\Buttons\UI-ScrollBar-Knob]])
	thumb:SetSize(18, 24)
	scrollBar:SetThumbTexture(thumb)
	scrollBar:SetMinMaxValues(0, 0)
	scrollBar:SetValueStep(1)
	scrollBar:SetObeyStepOnDrag(true)
	scrollBar:SetValue(0)
	scrollBar:Hide() -- shown only once a list actually overflows LIST_ROWS

	local editor = {}
	local offset = 0

	local function RenderRows()
		local names = getList()
		for i = 1, LIST_ROWS do
			local name = names[offset + i]
			local row = rows[i]
			if name then
				row.text:SetText(name)
				row.removeBtn:SetScript("OnClick", function()
					removeFn(name)
					editor:Refresh()
				end)
				row.text:Show()
				row.removeBtn:Show()
			else
				row.text:Hide()
				row.removeBtn:Hide()
			end
		end
	end
	scrollBar:SetScript("OnValueChanged", function(_, value)
		offset = math.floor(value + 0.5)
		RenderRows()
	end)

	function editor:Refresh()
		local names = getList()
		local maxOffset = math.max(0, #names - LIST_ROWS)
		if offset > maxOffset then
			offset = maxOffset
		end
		scrollBar:SetMinMaxValues(0, maxOffset)
		scrollBar:SetShown(maxOffset > 0)
		scrollBar:SetValue(offset)
		RenderRows() -- SetValue above only fires OnValueChanged when it actually changes
	end

	local function DoAdd()
		addFn(box:GetText())
		box:SetText("")
		box:ClearFocus()
		editor:Refresh()
	end
	box:SetScript("OnEnterPressed", DoAdd)
	addBtn:SetScript("OnClick", DoAdd)

	-- label + box row + LIST_ROWS rows + bottom padding
	local height = 20 + 28 + (LIST_ROWS * LIST_ROW_HEIGHT) + 12
	return editor, height
end

-- Bold section header + one-line description. Returns the Y position
-- (negative, relative to scrollChild's TOPLEFT) where this section's own
-- controls should start.
local function MakeSection(scrollChild, y, title, description)
	local header = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	header:SetText(title)

	local divider = scrollChild:CreateTexture(nil, "ARTWORK")
	divider:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	divider:SetPoint("RIGHT", scrollChild, "RIGHT", -16, 0)
	divider:SetHeight(1)
	if divider.SetColorTexture then
		divider:SetColorTexture(1, 1, 1, 0.2)
	end

	y = y - 26

	if description then
		local desc = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		desc:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
		desc:SetPoint("RIGHT", scrollChild, "RIGHT", -16, 0)
		desc:SetJustifyH("LEFT")
		desc:SetText(description)
		y = y - 20
	end

	return y - 8
end

----------------------------------------------------------------------------
-- Panel assembly
----------------------------------------------------------------------------

function Options:Init()
	if category then
		return
	end

	panel = CreateFrame("Frame")
	panel.name = Addon.name

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText(Addon.name)

	local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
	subtitle:SetText("Class Colors, Swing Timer Buff Tracking, Hidden Micro Menu/Bags Bar, Symmetrical Chat & Damage Meter, Tooltip Tweaks.")

	local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -12)
	scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 16)

	local scrollChild = CreateFrame("Frame", nil, scrollFrame)
	scrollChild:SetWidth(560)
	scrollFrame:SetScrollChild(scrollChild)

	local y = -8
	local refreshers = {}

	------------------------------------------------------------------
	-- Class Colors - no settings, always on.
	------------------------------------------------------------------
	y = MakeSection(scrollChild, y, "Class Colors",
		"Colors the player and target health bars by class. Always on, nothing to configure.")

	------------------------------------------------------------------
	-- Swing Timer Buff Tracking
	------------------------------------------------------------------
	y = MakeSection(scrollChild, y, "Swing Timer Buff Tracking",
		"Tracks buffs whose remaining time drops under the threshold below, as icons sliding across a native Swing Timer bar.")

	-- Resolved lazily (not cached) since Addon.charDb may not exist yet the
	-- moment this panel is built - Options:Init() is called from Core.lua's
	-- ADDON_LOADED handler right after both DBs are created, so by the time
	-- any of these closures actually run (a click, or panel:Refresh on show)
	-- it's always populated.
	local function SwingDb()
		return Addon.charDb and Addon.charDb.swingTimer
	end

	local stEnable = MakeCheck(scrollChild, "Enabled", function(value)
		SwingDb().enabled = value
		Addon.SwingTimer.ApplyEnabled()
	end)
	stEnable:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	y = y - 26

	local stSelfOnly = MakeCheck(scrollChild, "Show only buffs cast by self", function(value)
		SwingDb().selfOnly = value
		Addon.SwingTimer.RefreshBuff()
	end)
	stSelfOnly:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	y = y - 30

	local stThreshold = MakeSlider(scrollChild, "Max tracked duration (sec)", 5, 180, 1, function(value)
		SwingDb().durationThreshold = value
		Addon.SwingTimer.RefreshBuff()
	end)
	stThreshold:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 20, y)
	y = y - 44

	local stIconSize = MakeSlider(scrollChild, "Icon size", 12, 48, 2, function(value)
		SwingDb().iconSize = value
		Addon.SwingTimer.ApplyIconSize()
	end)
	stIconSize:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 20, y)
	y = y - 50

	local stAttachLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	stAttachLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	stAttachLabel:SetText("Attach to bar")
	y = y - 20

	local stAttachDropdown = MakeRadioDropdown(scrollChild, 300, {
		{ label = "Main Hand", value = "mainhand", tooltip = "Attach to the native main-hand Swing Timer bar." },
		{ label = "Off Hand", value = "offhand", tooltip = "Attach to the native off-hand Swing Timer bar." },
		{ label = "Ranged", value = "ranged", tooltip = "Attach to the native ranged Swing Timer bar - useful for Hunters." },
	}, function(value) return SwingDb() and value == SwingDb().attachTo end,
		function(value)
			SwingDb().attachTo = value
			Addon.SwingTimer.ApplyAttachTo()
		end)
	stAttachDropdown:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 18, y)
	y = y - 34

	local stScaleLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	stScaleLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	stScaleLabel:SetText("Bar scale")
	y = y - 20

	local stScaleDropdown = MakeRadioDropdown(scrollChild, 300, {
		{ label = "Per-Buff Scale", value = "appear",
			tooltip = "Every icon starts at the right edge the moment it's first tracked, then crosses the bar at a speed based on how much time it had left at that moment. A fresh 30s buff crosses faster than a long buff that just dropped to its last 3 minutes." },
		{ label = "Fixed Scale (Max Tracked Duration)", value = "threshold",
			tooltip = "All icons share one scale: the Max tracked duration setting above. A fresh short buff starts partway across; a long buff that just crossed the threshold starts at the right edge." },
	}, function(value) return SwingDb() and value == SwingDb().scaleMode end,
		function(value) SwingDb().scaleMode = value end)
	stScaleDropdown:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 18, y)
	y = y - 34

	local stSourceLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	stSourceLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	stSourceLabel:SetText("Buff source")
	y = y - 20

	local stSourceDropdown = MakeRadioDropdown(scrollChild, 300, {
		{ label = "Buffs Under Max Duration", value = "duration",
			tooltip = "Any buff whose remaining time is under Max tracked duration qualifies. The default - no list to maintain." },
		{ label = "Allowlist Only", value = "allowlist",
			tooltip = "Only buffs on the Allowlist below are shown, regardless of their remaining time." },
		{ label = "Allowlist + Max Duration", value = "both",
			tooltip = "Only buffs that are both on the Allowlist below AND under Max tracked duration are shown." },
	}, function(value) return SwingDb() and value == SwingDb().buffSourceMode end,
		function(value) SwingDb().buffSourceMode = value end)
	stSourceDropdown:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 18, y)
	y = y - 34

	local blockEditor, blockHeight = MakeListEditor(scrollChild, 16, y,
		"Blocklist (always excluded)",
		function(name) Addon.SwingTimer.AddBlock(name) end,
		function(name) Addon.SwingTimer.RemoveBlock(name) end,
		function() return SwingDb().blocklist end)
	y = y - blockHeight

	local allowEditor, allowHeight = MakeListEditor(scrollChild, 16, y,
		"Allowlist (used by Buff source above)",
		function(name) Addon.SwingTimer.AddAllow(name) end,
		function(name) Addon.SwingTimer.RemoveAllow(name) end,
		function() return SwingDb().allowlist end)
	y = y - allowHeight - 8

	-- No combat-tracked-buffs list here on purpose - that used to be a
	-- manual "Name:Seconds" list, explicitly rejected in favor of fully
	-- automatic tracking. It's automatic now: Core.lua learns each ability's
	-- duration itself from combat log timestamps the first time it's seen,
	-- and uses the existing Buff source/Blocklist/Allowlist settings above
	-- for everything it tracks afterward, in or out of combat - nothing to
	-- configure here.

	table.insert(refreshers, function()
		local d = SwingDb()
		if not d then
			return
		end
		stEnable:SetChecked(d.enabled)
		stSelfOnly:SetChecked(d.selfOnly)
		stThreshold:SetValue(d.durationThreshold)
		stIconSize:SetValue(d.iconSize)
		blockEditor:Refresh()
		allowEditor:Refresh()
	end)

	------------------------------------------------------------------
	-- Hidden Micro Menu / Bags Bar
	------------------------------------------------------------------
	y = MakeSection(scrollChild, y, "Hidden Micro Menu / Bags Bar",
		"Controls visibility of the Micro Menu and Bags bar - neither is hideable via Edit Mode.")

	local function HiddenBarsDb()
		return Addon.db and Addon.db.hiddenBars
	end

	local MODE_ITEMS = {
		{ label = "Visible", value = "visible", tooltip = "Always shown." },
		{ label = "On Mouseover", value = "mouseover", tooltip = "Hidden until you mouse over it." },
		{ label = "Hidden", value = "hidden", tooltip = "Always hidden. Still shown while Edit Mode is active, so you can reposition it." },
	}

	local bagLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	bagLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	bagLabel:SetText("Bag bar visibility")
	y = y - 20

	local bagDropdown = MakeRadioDropdown(scrollChild, 300, MODE_ITEMS,
		function(value) return HiddenBarsDb() and value == HiddenBarsDb().bagBarMode end,
		function(value)
			HiddenBarsDb().bagBarMode = value
			Addon.HiddenBars.UpdateVisibility()
		end)
	bagDropdown:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 18, y)
	y = y - 34

	local microLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	microLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	microLabel:SetText("Micro menu visibility")
	y = y - 20

	local microDropdown = MakeRadioDropdown(scrollChild, 300, MODE_ITEMS,
		function(value) return HiddenBarsDb() and value == HiddenBarsDb().microMenuMode end,
		function(value)
			HiddenBarsDb().microMenuMode = value
			Addon.HiddenBars.UpdateVisibility()
		end)
	microDropdown:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 18, y)
	y = y - 34

	------------------------------------------------------------------
	-- Symmetrical Chat & Damage Meter
	------------------------------------------------------------------
	y = MakeSection(scrollChild, y, "Symmetrical Chat & Damage Meter",
		"Mirrors the Damage Meter in the bottom-right corner, matching chat's size, split evenly into the number of windows below.")

	local function ChatDmDb()
		return Addon.db and Addon.db.chatDamageMeter
	end

	local function MaxWindowCount()
		return (DamageMeter and DamageMeter.GetMaxSessionWindowCount and DamageMeter:GetMaxSessionWindowCount()) or 3
	end

	local windowCountItems = {}
	for i = 1, 3 do -- built against this client's confirmed max (3); harmless if it's ever lower
		windowCountItems[i] = {
			label = (i == 1) and "1 window" or (i .. " windows"),
			value = i,
			tooltip = "Mirror the Damage Meter as " .. i .. (i == 1 and " window." or " equal-width windows side by side."),
		}
	end

	local windowCountLabel = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	windowCountLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	windowCountLabel:SetText("Damage Meter window count")
	y = y - 20

	local windowCountDropdown = MakeRadioDropdown(scrollChild, 300, windowCountItems,
		function(value) return ChatDmDb() and value == ChatDmDb().damageMeterWindowCount end,
		function(value)
			if value > MaxWindowCount() then
				value = MaxWindowCount()
			end
			ChatDmDb().damageMeterWindowCount = value
			Addon.ChatDamageMeter.MirrorToChat()
		end)
	windowCountDropdown:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 18, y)
	y = y - 34

	------------------------------------------------------------------
	-- Tooltip Tweaks
	------------------------------------------------------------------
	y = MakeSection(scrollChild, y, "Tooltip Tweaks",
		"Cursor-following and per-line visibility for player tooltips. Cursor-following is always on.")

	local function TooltipDb()
		return Addon.db and Addon.db.tooltip
	end

	local ttTarget = MakeCheck(scrollChild, "Show target in tooltip", function(value)
		TooltipDb().showMouseoverTarget = value
	end)
	ttTarget:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	y = y - 26

	local ttGuild = MakeCheck(scrollChild, "Show guild line", function(value)
		TooltipDb().showGuildLine = value
	end)
	ttGuild:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	y = y - 26

	local ttLevel = MakeCheck(scrollChild, "Show level/race line", function(value)
		TooltipDb().showLevelLine = value
	end)
	ttLevel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	y = y - 26

	local ttClass = MakeCheck(scrollChild, "Show class line", function(value)
		TooltipDb().showClassLine = value
	end)
	ttClass:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	y = y - 26

	local ttFaction = MakeCheck(scrollChild, "Show faction line", function(value)
		TooltipDb().showFactionLine = value
	end)
	ttFaction:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 16, y)
	y = y - 26

	table.insert(refreshers, function()
		local d = TooltipDb()
		if not d then
			return
		end
		ttTarget:SetChecked(d.showMouseoverTarget)
		ttGuild:SetChecked(d.showGuildLine)
		ttLevel:SetChecked(d.showLevelLine)
		ttClass:SetChecked(d.showClassLine)
		ttFaction:SetChecked(d.showFactionLine)
	end)

	------------------------------------------------------------------

	scrollChild:SetHeight(math.abs(y) + 24)

	function panel:Refresh()
		for _, refresh in ipairs(refreshers) do
			refresh()
		end
	end
	panel:SetScript("OnShow", panel.Refresh)

	category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
	Settings.RegisterAddOnCategory(category)
end

function Options:Open()
	if not category then
		return
	end
	-- OpenToCategory's argument has shifted between client builds; try the
	-- category object first and its numeric id as a fallback.
	if not pcall(Settings.OpenToCategory, category) then
		pcall(Settings.OpenToCategory, category.GetID and category:GetID() or nil)
	end
end
