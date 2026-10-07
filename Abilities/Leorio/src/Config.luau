--!strict
--[[
	Leorio settings: Leorio Paladiknight's warp punches (Hunter x Hunter), tuned for a parry-style
	fight. He's an Emitter: he punches something near him (the floor, the air) into a warp hole, and
	the fist comes out of another one by his target.

	  WarpPunch     the ground punch he lands on Ging: he drives his fist into the floor and it comes
	                out of a hole that opens beside his target's head. The hole shows for the whole
	                trip (HitDelay - PunchAt), and the blow comes from it: block or parry facing the
	                hole, not him.
	  RemoteJab     a quick jab into a hole at his knuckles; the fist comes out of a hole that opens
	                behind his target, punching them toward him (a combo starter). From behind: turn
	                round to block it.
	  WarpBarrage   down low, hammering the floor: each punch comes out of a new hole round his
	                target, from a different side every time, and the last, double-handed one comes
	                down on them from a hole overhead.
	  PortalBurst   both fists slammed into the floor between his feet: holes open in a ring round
	                him and fists come up out of them, launching everyone near. Blockable from any
	                side, never parryable.

	Every number is in studs, seconds or studs per second. Damage is in health points.
]]

local Config = {}

-- controls (only used when the place has no Loadout menu; with one, Loadout.Slots decide the keys)
Config.Keys = {
	WarpPunch = Enum.KeyCode.Z,
	RemoteJab = Enum.KeyCode.X,
	WarpBarrage = Enum.KeyCode.C,
	PortalBurst = Enum.KeyCode.V,
}
Config.GamepadButtons = {
	WarpPunch = Enum.KeyCode.ButtonX,
	RemoteJab = Enum.KeyCode.ButtonY,
	WarpBarrage = Enum.KeyCode.ButtonB,
	PortalBurst = Enum.KeyCode.ButtonR1,
}
Config.MobileButtons = true
Config.Abilities = { "WarpPunch", "RemoteJab", "WarpBarrage", "PortalBurst" }
Config.DisplayNames = {
	WarpPunch = "Warp Punch",
	RemoteJab = "Remote Jab",
	WarpBarrage = "Warp Barrage",
	PortalBurst = "Portal Burst",
}

Config.SharedCooldown = 0.5 -- after any of them, all four wait at least this long
Config.HitPlayers = true -- false: only NPCs (Humanoids without a Player)
Config.TeamCheck = true -- don't hit players on the caster's team (when Teams are used)
Config.KnockbackTime = 0.18 -- seconds a push lasts (when the place has no Combat module)

-- picking a target: someone within Range of him and within Angle of where the camera looks (the
-- nearest to that line). With nobody there, the hole opens out along the look instead.
Config.Targeting = {
	AimWithCamera = true,
	Angle = 30,
	Fallback = 14, -- studs out along the look the hole opens when there's nobody to aim at
}

Config.WarpPunch = {
	Damage = 16,
	Knockback = 55, -- studs/s, out of the hole
	Lift = 16,
	Stun = 1.0,
	GuardDamage = 55,
	PunchAt = 22 / 60, -- the fist goes into the floor: the "Hit" marker in Leorio Warp Punch
	HitDelay = 37 / 60, -- the blow lands out of the hole: the "Warp" marker
	Range = 50,
	Side = 60, -- degrees round from the line to him that the hole opens (60: in front of a blocker who faces him)
	Distance = 3.6, -- studs from the target the hole opens
	Height = 1.3, -- and this high (head height)
	Radius = 2.4, -- the hole's size
	Reach = 5.5, -- how far out of the hole the blow carries (the hitbox's length)
	Width = 4.5, -- and its width
	Recovery = 1.0, -- seconds he is busy from the press
	Cooldown = 8,
}

Config.RemoteJab = {
	Damage = 7,
	Pull = 18, -- studs/s, toward him (the fist comes from behind)
	Stun = 0.7,
	GuardDamage = 20,
	JabAt = 10 / 60, -- the fist into the hole at his knuckles: the "Hit" marker in Leorio Remote Jab
	HitDelay = 24 / 60, -- it comes out by the target: the "Warp" marker
	Range = 45,
	Distance = 3.2, -- studs behind the target the hole opens
	Height = 1.2,
	Radius = 1.7,
	Reach = 4.5,
	Width = 4,
	Recovery = 0.5,
	Cooldown = 5,
}

Config.WarpBarrage = {
	Range = 40,
	Travel = 7 / 60, -- each fist comes out this long after it goes into the floor
	Distance = 3.4,
	Height = 1.0,
	Radius = 1.9,
	Reach = 4.5,
	Width = 4.2,
	-- each punch, timed to the "Hit" markers in Leorio Barrage: At = when the fist goes into the floor;
	-- Angle = degrees round the target from the line to him that its hole opens (+ = his right)
	Hits = {
		{ At = 16 / 60, Angle = 70, Damage = 3, Stun = 0.6 },
		{ At = 24 / 60, Angle = -110, Damage = 3, Stun = 0.6 },
		{ At = 32 / 60, Angle = -45, Damage = 3, Stun = 0.6 },
		{ At = 40 / 60, Angle = 150, Damage = 3, Stun = 0.6 },
		{ At = 48 / 60, Angle = 15, Damage = 3, Stun = 0.8 },
		-- the last, double-handed: from a hole overhead, down on them
		{ At = 70 / 60, Above = true, Damage = 10, Stun = 1.0, Knockback = 30, Radius = 2.8 },
	},
	GuardDamage = 12, -- each
	Length = 96 / 60, -- the whole animation (Leorio Barrage)
	Recovery = 1.6,
	Cooldown = 12,
}

Config.PortalBurst = {
	Damage = 10,
	Knockback = 30, -- studs/s, out from him
	Lift = 45, -- and up: a launch
	Stun = 1.0,
	GuardDamage = 45,
	HitDelay = 24 / 60, -- both fists into the floor: the "Hit" marker in Leorio Burst
	Erupt = 7 / 60, -- the fists come up this long after
	Holes = 6, -- in the ring
	RingRadius = 6.5, -- studs from him
	Radius = 9.5, -- everyone this close is launched
	HoleRadius = 1.9,
	Recovery = 0.9,
	Cooldown = 10,
}

-- the fists that come out of the holes (built by LeorioVFX)
Config.Fist = {
	Scale = 1.5, -- times an R6 arm (Warp Punch, Portal Burst); the jab and barrage are a little smaller
	SleeveColor = Color3.fromRGB(28, 32, 46), -- his dark suit
	CuffColor = Color3.fromRGB(235, 236, 240), -- his shirt cuff
	SkinFromCaster = true, -- the fist takes the caster's Right Arm colour (false: SkinColor)
	SkinColor = Color3.fromRGB(234, 184, 146),
}

-- Published animation ids (rbxassetid://...). Leave empty to use the KeyframeSequences inside
-- Leorio/Animations, which only play in Studio: publish them and paste the ids here.
Config.Animations = {
	WarpPunch = "",
	RemoteJab = "",
	Barrage = "",
	Burst = "",
}

Config.AuraColor = Color3.fromRGB(133, 255, 231)

return Config
