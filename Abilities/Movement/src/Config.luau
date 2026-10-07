--!strict
--[[
	Movement settings: sprinting, rolling, jumping and landing.

	Sprint   hold Left Ctrl, or double-tap W and keep it held (gamepad: click the left stick to
	         toggle; touch: the Sprint button toggles). You run at SprintSpeed, and dust kicks up
	         behind you. Anything that slows you (swinging, charging, blocking, a stun) takes over
	         while it lasts; you're back to sprinting after if you still are.
	Roll     Q (gamepad L2, touch: the Roll button): a forward roll the way you're moving (or facing),
	         untouchable for the first part of it. Not while stunned or in the middle of an attack.
	Jumping  Roblox's own jump, with the kit's jump, fall and landing animations: the landing as hard
	         as the fall was, lighter when you land running.

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
Config.RunAnimationSpeed = 26 -- the run's feet are planted for this speed: it plays faster or slower
-- to match the speed you're really going (so set it to SprintSpeed's default, not your SprintSpeed)

Config.Roll = {
	Key = Enum.KeyCode.Q,
	Button = Enum.KeyCode.ButtonL2,
	Speed = 40, -- studs/s at the start, easing off over Time (about 11 studs in all)
	Time = 0.45,
	Intangible = 0.3, -- seconds hits pass through you, from the start of the roll
	Busy = 0.5, -- seconds you can't attack or block
	Cooldown = 1.0,
}

Config.Air = {
	FallDelay = 0.2, -- seconds off an edge before the fall pose comes in (a jump hands over when it ends)
	SoftLanding = 20, -- landing slower than this (studs/s, falling) plays no landing: a step down
	HardLanding = 50, -- this fast or faster plays the full landing (a jump comes down at about 53)
	MovingLandWeight = 0.55, -- landing on the move: the landing at this weight over the run,
	MovingLandSpeed = 1.5, -- and quicker
	DustSpeed = 60, -- landing this fast kicks up dust (a jump off something high)
}

Config.MobileButtons = true
Config.DustSpeed = 21 -- studs/s: anyone running faster than this on the ground kicks up dust

-- Published animation ids (rbxassetid://...). Leave empty to use the KeyframeSequences inside
-- Movement/Animations, which only play in Studio: publish them and paste the ids here.
Config.Animations = {
	Sprint = "",
	Roll = "",
	Jump = "",
	Fall = "",
	Land = "",
}

return Config
