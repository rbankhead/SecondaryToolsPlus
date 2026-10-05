-- ClassColors (originally the standalone ClassColoredForeverFrames addon):
-- the player/target health bars are nested four levels deep, not direct
-- children:
--   PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar
--   TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar
-- Both set lockColor = true at OnLoad, so nothing else in the default UI
-- recolors them - a one-time SetStatusBarColor per relevant event is
-- enough, no need to fight a competing update.
--
-- Their bar texture is a styled portrait-frame atlas with its own baked-in
-- gradient, not a neutral white bar, so SetStatusBarColor multiplies against
-- that instead of replacing it (a near-white class color like Priest's looks
-- like a no-op; anything else comes out muddy). Swapping to a different
-- texture file fixes the color but loses the mask/shape Blizzard tuned for
-- this exact atlas (the bar renders as a flat rectangle instead of the
-- curved portrait style). Desaturating the existing texture instead strips
-- its baked-in hue while keeping the real shape/shading, so the tint reads
-- as the correct color without changing the bar's look.
--
-- No settings - always on, same as the original standalone addon.

local function GetPlayerHealthBar()
	local content = PlayerFrame and PlayerFrame.PlayerFrameContent
	local main = content and content.PlayerFrameContentMain
	return main and main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
end

local function GetTargetHealthBar()
	local content = TargetFrame and TargetFrame.TargetFrameContent
	local main = content and content.TargetFrameContentMain
	return main and main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
end

local function ApplyUnitColor(healthBar, unit)
	if not healthBar or not UnitExists(unit) then
		return
	end

	local barTexture = healthBar:GetStatusBarTexture()
	if barTexture then
		barTexture:SetDesaturated(true)
	end

	if UnitIsPlayer(unit) then
		local _, classFilename = UnitClass(unit)
		local color = classFilename and RAID_CLASS_COLORS[classFilename]
		if color then
			healthBar:SetStatusBarColor(color.r, color.g, color.b)
			return
		end
	end

	healthBar:SetStatusBarColor(UnitSelectionColor(unit))
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		ApplyUnitColor(GetPlayerHealthBar(), "player")
	elseif event == "PLAYER_TARGET_CHANGED" then
		ApplyUnitColor(GetTargetHealthBar(), "target")
	end
end)
