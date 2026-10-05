-- HiddenBars (originally the standalone HiddenMicroMenuBagBar addon):
-- MicroMenu and BagsBar (the micro-menu buttons and bag slot buttons,
-- confirmed real global names on this client) aren't part of Edit Mode's
-- hideable systems. Each has its own mode - visible/mouseover/hidden.
-- SetAlpha keeps them mouse-interactive even at 0 (unlike Hide()), so
-- mouseover mode still reads real cursor position. Edit Mode is exempted
-- from all three modes, via EditModeManagerFrame:IsEditModeActive(), so both
-- bars stay visible while repositioning things even if set to Hidden.
--
-- Neither frame has mouse interaction enabled on itself (confirmed against
-- their real XML - only their child buttons do, and MicroMenu's template is
-- a layout-only GridLayoutFrame), so OnEnter/OnLeave never fire on them.
-- IsMouseOver() is polled on a timer instead of waiting for those events.

local Addon = SecondaryToolsPlus

Addon.HiddenBarsDefaults = {
	bagBarMode = "mouseover", -- "visible" | "mouseover" | "hidden"
	microMenuMode = "mouseover",
}

local db -- SecondaryToolsPlusDB.hiddenBars, set by Addon.InitHiddenBars

local function ComputeAlpha(mode, frameObj)
	if EditModeManagerFrame and EditModeManagerFrame:IsEditModeActive() then
		return 1
	elseif mode == "visible" then
		return 1
	elseif mode == "hidden" then
		return 0
	else -- "mouseover"
		return (frameObj and frameObj:IsMouseOver()) and 1 or 0
	end
end

local function UpdateVisibility()
	if not db then
		return
	end
	if MicroMenu then
		MicroMenu:SetAlpha(ComputeAlpha(db.microMenuMode, MicroMenu))
	end
	if BagsBar then
		BagsBar:SetAlpha(ComputeAlpha(db.bagBarMode, BagsBar))
	end
end
Addon.HiddenBars = { UpdateVisibility = UpdateVisibility }

local POLL_INTERVAL = 0.1
local elapsed = 0

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, delta)
	elapsed = elapsed + delta
	if elapsed < POLL_INTERVAL then
		return
	end
	elapsed = 0
	UpdateVisibility()
end)

local initialized = false

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function()
	if not initialized then
		initialized = true
		if EditModeManagerFrame then
			hooksecurefunc(EditModeManagerFrame, "EnterEditMode", UpdateVisibility)
			hooksecurefunc(EditModeManagerFrame, "ExitEditMode", UpdateVisibility)
		end
	end
	UpdateVisibility()
end)

function Addon.InitHiddenBars(ns)
	db = ns
	UpdateVisibility()
end
