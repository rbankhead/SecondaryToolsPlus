-- Tooltip (originally the standalone HudTooltipTweaks addon): this client's
-- tooltip no longer follows the mouse by default - GameTooltip_SetDefaultAnchor
-- (confirmed real, the shared function virtually every native OnEnter handler
-- calls to position GameTooltip) now anchors it to GameTooltipDefaultContainer,
-- a fixed Edit Mode HUD system (Enum.EditModeSystem.HudTooltip, confirmed in
-- the real API docs) the player can only drag to a new fixed spot, not make
-- follow the cursor again. Also adds a "Target: X" line to unit tooltips
-- showing who the hovered unit is targeting - not present natively in this
-- client's GameTooltip source.
--
-- Cursor-following is unconditional, not an option - confirmed in-game that
-- the Settings panel checkbox this used to gate it behind never actually
-- reached the saved value (a direct slash-command toggle worked fine, the
-- checkbox itself didn't), and the player wants this to just work on load
-- rather than deal with a broken toggle or a slash command.

local Addon = SecondaryToolsPlus

Addon.TooltipDefaults = {
	showMouseoverTarget = true,
	showGuildLine = true,
	showLevelLine = true,
	showClassLine = true,
	showFactionLine = true,
}

local db -- SecondaryToolsPlusDB.tooltip, set by Addon.InitTooltip

-- Repositions GameTooltip's bottom-left corner to the cursor, bottom-left
-- consistently (confirmed this is the corner the player wants - the
-- momentary centered-on-cursor flash before snapping to this came from a
-- now-removed ANCHOR_CURSOR call racing this on the next frame; calling this
-- synchronously from inside the GameTooltip_SetDefaultAnchor hook below,
-- rather than only from the OnUpdate driver, closes that gap so the very
-- first frame already uses this exact anchor instead of a different native
-- one for one frame first).
-- Confirmed in-game: pcall around a call into Blizzard's own SetWorldCursor
-- did NOT stop the secret-value error from surfacing (the error dialog still
-- showed "[C]: in function 'pcall'" right there in its own stack - pcall ran,
-- the error still displayed). This client deliberately makes secret-value
-- violations bypass pcall, the same way protected-action violations always
-- have - otherwise an addon could use pcall to probe for secret data by
-- timing/observing what it catches, defeating the whole point of marking it
-- secret. So wrapping the earlier SetWorldCursor override in pcall was never
-- going to work; the only real fix is to never put this addon's code
-- synchronously inside Blizzard's own tooltip-population call at all - that
-- override (and its anchorType substitution) is gone entirely now.
--
-- Repositions GameTooltip's bottom-left corner to the cursor, bottom-left
-- consistently (confirmed this is the corner the player wants). Also doubles
-- as the fix for the ~3s fade-out lingering on world unit/object mouseover:
-- GameTooltipDataMixin:SetWorldCursor (confirmed via this client's own
-- GameTooltip.lua) calls the tooltip's native :FadeOut() on mouse-off
-- whenever its anchorType was Default (the HUD mode this client defaults
-- to) - a slow built-in animation. Rather than intercept that call, this
-- just watches for GetAlpha() < 1 (a fade in progress, for any reason) from
-- this addon's own OnUpdate driver - a separate, clean call stack Blizzard's
-- tooltip code never runs inside of, so nothing here is at risk of tainting
-- whatever happens later - and hides it immediately, cutting the fade down
-- to at most one frame's worth instead of letting the full animation play.
local function PositionAtCursor()
	if not GameTooltip:IsShown() then
		return
	end
	if GameTooltip:GetAlpha() < 1 then
		GameTooltip:Hide()
		return
	end
	local scale = GameTooltip:GetEffectiveScale()
	if not scale or scale == 0 then
		return
	end
	local x, y = GetCursorPosition()
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (x / scale) + 16, (y / scale) + 16)
end

-- A third, separate slow-fade source, confirmed via this client's own
-- UnitFrame.lua: UnitFrame_OnLeave (used by the player frame, target frame,
-- party frames, etc.) unconditionally calls the same native GameTooltip:
-- FadeOut() on mouse-leave, with no anchorType check at all - unrelated to
-- either of the two paths already fixed above.
--
-- hooksecurefunc("UnitFrame_OnLeave", ...) alone didn't fix PlayerFrame -
-- confirmed in-game. Its real cause: PlayerFrame.xml binds
-- <OnLeave function="UnitFrame_OnLeave"/>, which resolves to
-- PlayerFrame:SetScript("OnLeave", UnitFrame_OnLeave) once, at PlayerFrame's
-- own creation during initial UI load - long before this addon's files run.
-- That captures the function it pointed to AT THAT MOMENT; wrapping the
-- global name UnitFrame_OnLeave afterward doesn't reach back and change
-- what PlayerFrame already bound. HookScript on the frame itself chains onto
-- whatever is actually bound right now instead, regardless of when it was
-- bound, so it reaches PlayerFrame and TargetFrame correctly (confirmed via
-- their own XML, both static, both created before this addon loads). Party/
-- raid frames and nameplates (CompactUnitFrame-based) are usually created
-- later, once you're actually in a group - after this addon has already
-- loaded - so the hooksecurefunc above still covers those.
if PlayerFrame then
	PlayerFrame:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end
if TargetFrame then
	TargetFrame:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
end

-- hooksecurefunc on a global function (unlike HookScript on a frame's own
-- script slot) can't be silently dropped by something later re-setting that
-- slot - confirmed the hard way, HookScript("OnUpdate", ...) on GameTooltip
-- itself did nothing visible, while this approach plus the driver below does.
hooksecurefunc("GameTooltip_SetDefaultAnchor", PositionAtCursor)

-- GameTooltip:HookScript(...) is avoided for the same reason as above - a
-- plain addon-owned frame polling on its own OnUpdate can't be clobbered by
-- anything this client's own tooltip code does to GameTooltip's scripts.
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", PositionAtCursor)

-- Per-line checkboxes for the player tooltip (guild/level/class/faction).
-- TooltipDataProcessor.AddTooltipPreCall (confirmed real) runs before the
-- tooltip's raw line data (tooltipData.lines, confirmed real array via this
-- client's own TooltipDataHandler.lua - each entry has .type and .leftText)
-- gets turned into actual FontStrings - removing an entry here means it's
-- never rendered at all, no leftover blank row the way hiding an already-
-- rendered line would leave. The level/race/classification line has its own
-- real type (Enum.TooltipDataLineType.UnitLevel/UnitType), confirmed in the
-- API docs, so that one's matched reliably by type; guild/class/faction
-- don't have dedicated types in that enum, so those are matched by comparing
-- each line's text against what the unit's own guild/class/faction actually
-- is (GetGuildInfo/UnitClass/UnitFactionGroup) - exact string compare rather
-- than a guessed pattern, so it can't accidentally eat an unrelated line
-- that happens to look similar.
TooltipDataProcessor.AddTooltipPreCall(Enum.TooltipDataType.Unit, function(tooltip, tooltipData)
	if not db or not tooltipData or not tooltipData.lines then
		return
	end

	local _, unit = tooltip:GetUnit()
	if not unit then
		return
	end

	local guildName = GetGuildInfo(unit)
	local className = UnitClass(unit)
	local factionToken = UnitFactionGroup(unit)

	local lines = tooltipData.lines
	for i = #lines, 2, -1 do -- line 1 is always the unit's name, never touched
		local lineData = lines[i]
		local text = lineData.leftText
		local remove = false

		if not db.showLevelLine and (lineData.type == Enum.TooltipDataLineType.UnitLevel or lineData.type == Enum.TooltipDataLineType.UnitType) then
			remove = true
		elseif not db.showGuildLine and guildName and text == guildName then
			remove = true
		elseif not db.showClassLine and className and text == className then
			remove = true
		elseif not db.showFactionLine and factionToken and text == factionToken then
			remove = true
		end

		if remove then
			table.remove(lines, i)
		end
	end
end)

-- GameTooltip:HookScript("OnTooltipSetUnit", ...) throws "bad argument #2" on
-- this client - confirmed in-game - because this client has moved unit-
-- tooltip population off that legacy script entirely, onto the newer
-- TooltipDataProcessor system (confirmed real via this client's own source,
-- Blizzard_PTRFeedback_Tooltips.lua uses exactly this same
-- TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ...)
-- call, tooltip:GetUnit() included, to do the same kind of per-unit tooltip
-- work this addon needs). This fires for any unit tooltip, not just world
-- mouseover (a unit frame's own tooltip triggers it too) - tooltip:GetUnit()
-- returns the real unit token being shown, which the real compound-token
-- suffix pattern (confirmed via this client's own source, e.g. UnitFrame.lua
-- building "targettarget" as unit.."target") extends to "<unit>target" to
-- read that unit's own target, without any extra event registration.
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
	if not db or not db.showMouseoverTarget then
		return
	end

	local _, unit = tooltip:GetUnit()
	if not unit then
		return
	end

	local targetUnit = unit .. "target"
	if not UnitExists(targetUnit) then
		return
	end

	local targetName
	if UnitIsUnit(targetUnit, "player") then
		targetName = ">> YOU <<"
		tooltip:AddLine("Target: " .. targetName, 1, 0.15, 0.15)
	else
		targetName = UnitName(targetUnit) or UNKNOWN
		tooltip:AddLine("Target: " .. targetName, 1, 1, 1)
	end

	tooltip:Show()
end)

function Addon.InitTooltip(ns)
	db = ns
end
