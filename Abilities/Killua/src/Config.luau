--!strict
--[[
	Killua settings: Killua Zoldyck's lightning (Hunter x Hunter), tuned for a parry-style fight.

	  LightningPalm   a lunging palm that shocks: the target is paralysed. Telegraphed by the
	                  wind-up (the palm drawn back crackling); parryable, blockable.
	  Thunderbolt     Narukami: Killua leaps and brings lightning down where he aims. A ring warns
	                  where it will land for the whole leap. Blockable from any side, never parryable:
	                  the answer is to get out of the ring (or guard and lose a lot of guard).
	  Whirlwind       Shippu Jinrai: a counter stance. If a hit lands on him during the window he
	                  vanishes, reappears behind the attacker and answers with a three-hit flurry
	                  that can't be blocked or parried. If nothing comes, he is left open.
	  LightningDash   up to three teleports in a row (Godspeed), each striking whoever he passes or
	                  lands next to; untouchable for a moment in each. The strikes can be parried, and
	                  a parry ends the chain.

	Every number is in studs, seconds or studs per second. Damage is in health points.
]]

local Config = {}

-- controls (only used when the place has no Loadout menu; with one, Loadout.Slots decide the keys)
Config.Keys = {
	LightningPalm = Enum.KeyCode.Z,
	Thunderbolt = Enum.KeyCode.X,
	Whirlwind = Enum.KeyCode.C,
	LightningDash = Enum.KeyCode.V,
}
Config.GamepadButtons = {
	LightningPalm = Enum.KeyCode.ButtonX,
	Thunderbolt = Enum.KeyCode.ButtonY,
	Whirlwind = Enum.KeyCode.ButtonB,
	LightningDash = Enum.KeyCode.ButtonR1,
}
Config.MobileButtons = true
Config.Abilities = { "LightningPalm", "Thunderbolt", "Whirlwind", "LightningDash" }
Config.DisplayNames = {
	LightningPalm = "Lightning Palm",
	Thunderbolt = "Thunderbolt",
	Whirlwind = "Whirlwind",
	LightningDash = "Lightning Dash",
}

Config.SharedCooldown = 0.5 -- after any of them, all four wait at least this long
Config.HitPlayers = true -- false: only NPCs (Humanoids without a Player)
Config.TeamCheck = true -- don't hit players on the caster's team (when Teams are used)
Config.KnockbackTime = 0.18 -- seconds a push lasts (when the place has no Combat module)

Config.LightningPalm = {
	Damage = 14,
	Knockback = 22, -- studs/s on a clean hit
	Paralyze = 1.1, -- seconds the target can't act ("Shock" stun)
	GuardDamage = 35, -- taken off a blocker's guard (Combat.Settings.GuardMax is 100)
	HitDelay = 21 / 60, -- from the press to the hit: the "Hit" marker in Killua Palm
	LungeAt = 16 / 60, -- when the lunge starts (client)
	Lunge = 7, -- studs the lunge carries him
	LungeTime = 0.1, -- seconds it takes
	Hitbox = Vector3.new(5, 5.5, 9.5), -- the box in front of him at the hit (long: the lunge, and lag)
	Recovery = 0.75, -- seconds he is busy from the press
	Cooldown = 7,
}

Config.Thunderbolt = {
	Damage = 22,
	Knockback = 38, -- out from the strike, studs/s
	Lift = 30, -- and up
	Paralyze = 0.7,
	GuardDamage = 70,
	HitDelay = 33 / 60, -- from the press to the strike: the "Hit" marker in Killua Thunderbolt
	LeapAt = 7 / 60, -- the take-off frame in the animation
	LeapSpeed = 52, -- studs/s straight up at take-off
	HangFrom = 0.34, -- seconds after the press he stops rising and hangs...
	HangUntil = 0.62, -- ...until here, then falls
	Range = 18, -- the furthest the bolt can land from him
	MinRange = 5,
	Radius = 9, -- what the strike covers (the warning ring is this size)
	AimWithCamera = true, -- land it where the camera looks (within MaxAimAngle of his facing)
	MaxAimAngle = 70,
	LockOn = true, -- if someone stands near the aim line within Range, drop it on them
	Recovery = 0.95,
	Cooldown = 10,
}

Config.Whirlwind = {
	Window = 0.65, -- seconds the counter stance is up
	WhiffRecovery = 0.45, -- seconds he stays open after a window that caught nothing
	CounterRange = 20, -- an attacker further than this is only evaded (a projectile, say), not countered
	Behind = 3.2, -- studs behind the attacker he reappears
	Length = 54 / 60, -- the counter flurry (Killua Counter)
	-- the flurry's hits, timed to the "Hit" markers in Killua Counter; none can be blocked or parried
	Hits = {
		{ At = 7 / 60, Damage = 5, Stun = 0.55 },
		{ At = 15 / 60, Damage = 7, Stun = 0.55 },
		{ At = 26 / 60, Damage = 11, Stun = 1.0, StunKind = "Shock", Knockback = 45 },
	},
	Cooldown = 9,
}

Config.LightningDash = {
	Dashes = 3, -- in a chain
	Distance = 18, -- studs each one covers at most
	ChainWindow = 0.9, -- seconds after a dash to make the next
	MinGap = 0.22, -- seconds between dashes
	Width = 3.5, -- studs either side of the path that a dash strikes
	ArriveRadius = 4.5, -- and round where it lands
	Intangible = 0.15, -- seconds hits pass through him in each dash
	-- each dash's strike, timed to the "Hit" markers in Killua Dash 1 / 2 / 3
	Strikes = {
		{ Delay = 6 / 60, Damage = 6, Stun = 0.45 },
		{ Delay = 6 / 60, Damage = 6, Stun = 0.45 },
		{ Delay = 7 / 60, Damage = 12, Stun = 0.8, StunKind = "Shock", Knockback = 35 },
	},
	GuardDamage = 20,
	AutoTarget = true, -- dash at someone within TargetAngle of the camera's look, if there is one
	TargetAngle = 35,
	Slack = 6, -- extra studs the server allows for lag when it checks a dash
	Recovery = 0.3,
	Cooldown = 8, -- from the end of the chain
}

-- Published animation ids (rbxassetid://...). Leave empty to use the KeyframeSequences inside
-- Killua/Animations, which only play in Studio: publish them and paste the ids here.
Config.Animations = {
	Palm = "",
	Thunderbolt = "",
	Land = "",
	Stance = "",
	Counter = "",
	Dash1 = "",
	Dash2 = "",
	Dash3 = "",
}

Config.LightningColor = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 225, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 190, 255)),
})

return Config
