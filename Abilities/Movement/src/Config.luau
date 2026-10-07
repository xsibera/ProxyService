--!strict
--[[
	Movement settings: sprinting and rolling.

	Sprint   hold Left Ctrl, or double-tap W and keep it held (gamepad: click the left stick to
	         toggle; touch: the Sprint button toggles). You run at SprintSpeed with the game's own
	         run animation, and dust kicks up behind you. Anything that slows you (swinging, charging,
	         blocking, a stun) takes over while it lasts; you're back to sprinting after if you still are.
	Roll     Q (gamepad L2, touch: the Roll button): a forward roll the way you're moving (or facing),
	         untouchable for the first part of it. Not while stunned or in the middle of an attack.

	Every number is in studs, seconds or studs per second.
]]

local Config = {}

Config.WalkSpeed = 16 -- the normal walk speed (StarterPlayer.CharacterWalkSpeed)
Config.SprintSpeed = 26
Config.SprintKey = Enum.KeyCode.LeftControl
Config.DoubleTapW = true -- double-tap W (and keep holding it) to sprint too
Config.DoubleTapTime = 0.3
Config.SprintButton = Enum.KeyCode.ButtonL3 -- toggles
Config.SprintFOV = 80 -- the camera widens to this while sprinting (the default is 70)

Config.Roll = {
	Key = Enum.KeyCode.Q,
	Button = Enum.KeyCode.ButtonL2,
	Speed = 40, -- studs/s at the start, easing off over Time (about 11 studs in all)
	Time = 0.45,
	Intangible = 0.3, -- seconds hits pass through you, from the start of the roll
	Busy = 0.5, -- seconds you can't attack or block
	Cooldown = 1.0,
}

Config.MobileButtons = true
Config.DustSpeed = 21 -- studs/s: anyone running faster than this on the ground kicks up dust

-- Published animation ids (rbxassetid://...). Leave empty to use the KeyframeSequences inside
-- Movement/Animations, which only play in Studio: publish them and paste the ids here.
Config.Animations = {
	Sprint = "",
	Roll = "",
}

return Config
