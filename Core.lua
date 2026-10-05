-- SecondaryToolsPlus: combined replacement for five separate addons built
-- earlier (ClassColoredForeverFrames, SwingTimerBuffTracking,
-- HiddenMicroMenuBagBar, SymmetricalChatAndDamageMeter, HudTooltipTweaks) -
-- merged so there's one Interface: version to bump per WoW patch and one
-- settings panel instead of five. Each former addon's feature lives in its
-- own file here (ClassColors.lua, SwingTimer.lua, HiddenBars.lua,
-- ChatDamageMeter.lua, Tooltip.lua) with its logic otherwise unchanged from
-- the original, standalone version - only how each one gets its saved
-- variables changed.
--
-- Two SavedVariables tables instead of one, to preserve the original
-- per-character vs account-wide scoping each feature had standalone:
-- SecondaryToolsPlusDB (account-wide: hiddenBars, chatDamageMeter, tooltip)
-- and SecondaryToolsPlusCharDB (per-character: swingTimer, which was
-- SwingTimerBuffTracking's own SavedVariablesPerCharacter). ClassColors has
-- no settings at all, so it has no namespace in either table.
--
-- Each feature file keeps its own local "db" upvalue and its own PLAYER_
-- LOGIN/PLAYER_ENTERING_WORLD event handling exactly as it did standalone
-- (every one of them already defensively checks "if not db then return end"
-- before using it, since originally db wasn't set until that addon's own
-- ADDON_LOADED fired) - this file just hands each feature its namespaced
-- sub-table once, via Addon.InitX(ns) functions each feature file exposes,
-- rather than restructuring their internals.

local ADDON_NAME = "SecondaryToolsPlus"

SecondaryToolsPlus = {}
local Addon = SecondaryToolsPlus
Addon.name = ADDON_NAME

local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = value
		end
	end
end

local function EnsureNamespace(root, key, defaults)
	root[key] = root[key] or {}
	ApplyDefaults(root[key], defaults)
	return root[key]
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, _, arg1)
	if arg1 ~= ADDON_NAME then
		return
	end

	SecondaryToolsPlusDB = SecondaryToolsPlusDB or {}
	SecondaryToolsPlusCharDB = SecondaryToolsPlusCharDB or {}
	Addon.db = SecondaryToolsPlusDB
	Addon.charDb = SecondaryToolsPlusCharDB

	local hiddenBarsNs = EnsureNamespace(Addon.db, "hiddenBars", Addon.HiddenBarsDefaults)
	local chatDamageMeterNs = EnsureNamespace(Addon.db, "chatDamageMeter", Addon.ChatDamageMeterDefaults)
	local tooltipNs = EnsureNamespace(Addon.db, "tooltip", Addon.TooltipDefaults)
	local swingTimerNs = EnsureNamespace(Addon.charDb, "swingTimer", Addon.SwingTimerDefaults)

	if Addon.InitHiddenBars then
		Addon.InitHiddenBars(hiddenBarsNs)
	end
	if Addon.InitChatDamageMeter then
		Addon.InitChatDamageMeter(chatDamageMeterNs)
	end
	if Addon.InitTooltip then
		Addon.InitTooltip(tooltipNs)
	end
	if Addon.InitSwingTimer then
		Addon.InitSwingTimer(swingTimerNs)
	end

	if Addon.Options then
		Addon.Options:Init()
	end
end)
