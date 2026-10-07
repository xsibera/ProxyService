--!strict
--[[
	Brawler settings: basic fighting moves - punches, kicks, a slam, grabs and the throws and slams
	that follow them - tuned for the parry-style fight the other kits use.

	The rules of the fight (through ReplicatedStorage.Combat):
	  Strikes      Haymaker, Uppercut, Roundhouse: block or parry them, facing the striker.
	  Teep         a heavy push kick that breaks a block outright: parry it, or get out of the way.
	  Axe Kick     comes down from above: blockable from any side, never parryable, and it takes most
	               of a guard (GuardDamage 70 of 100).
	  Ground Slam  from above too, all round him.
	  Grabs        Grab & Throw, Suplex, Chokeslam: grabs beat blocks (a blocker is grabbed anyway),
	               and can't be parried. Answer one by hitting him first (the reach has a short wind-
	               up), by rolling through it, or by not being there.

	Every number is in studs, seconds or studs per second. Damage is in health points.
]]

local Config = {}

-- controls (only used when the place has no Loadout menu; with one, Loadout.Slots decide the keys)
Config.Keys = {
	Haymaker = Enum.KeyCode.Z,
	Uppercut = Enum.KeyCode.X,
	Roundhouse = Enum.KeyCode.C,
	AxeKick = Enum.KeyCode.V,
	Teep = Enum.KeyCode.E,
	GroundSlam = Enum.KeyCode.B,
	GrabThrow = Enum.KeyCode.T,
	Suplex = Enum.KeyCode.G,
	Chokeslam = Enum.KeyCode.H,
}
Config.GamepadButtons = {
	Haymaker = Enum.KeyCode.ButtonX,
	Uppercut = Enum.KeyCode.ButtonY,
	Roundhouse = Enum.KeyCode.ButtonB,
	AxeKick = Enum.KeyCode.ButtonR1,
}
Config.MobileButtons = true
Config.Abilities = {
	"Haymaker",
	"Uppercut",
	"Roundhouse",
	"AxeKick",
	"Teep",
	"GroundSlam",
	"GrabThrow",
	"Suplex",
	"Chokeslam",
}
Config.DisplayNames = {
	Haymaker = "Haymaker",
	Uppercut = "Uppercut",
	Roundhouse = "Roundhouse",
	AxeKick = "Axe Kick",
	Teep = "Teep",
	GroundSlam = "Ground Slam",
	GrabThrow = "Grab & Throw",
	Suplex = "Suplex",
	Chokeslam = "Chokeslam",
}

Config.SharedCooldown = 0.4 -- after any of them, all of them wait at least this long
Config.HitPlayers = true -- false: only NPCs (Humanoids without a Player)
Config.TeamCheck = true -- don't hit players on the caster's team (when Teams are used)
Config.KnockbackTime = 0.18 -- seconds a push lasts (when the place has no Combat module)
Config.TurnToCamera = true -- each move turns you to face where the camera looks
Config.MoveWalkSpeed = 6 -- walk speed while a strike plays out
Config.Color = nil :: Color3? -- tints the wind of the swing trails and hits (nil: white and grey)

-- The strikes. HitDelay is the "Hit" marker in the move's animation (the build checks it). The
-- hit box sits in front of him: Box (width, height, depth), its near face Ahead studs in front.
-- Lunge: he steps in Distance studs over Time seconds from At.
Config.Haymaker = {
	Animation = "Haymaker",
	Swing = "FistSwing",
	HitDelay = 22 / 60,
	Damage = 14,
	Stun = 0.9,
	Knockback = 45, -- away from him
	Lift = 10,
	GuardDamage = 45,
	Box = Vector3.new(6, 5, 6),
	Ahead = 0,
	Lunge = { At = 16 / 60, Distance = 4, Time = 0.12 },
	Effect = "HeavyHit",
	Recovery = 0.75,
	Cooldown = 5,
}

Config.Uppercut = {
	Animation = "Uppercut",
	Swing = "FistSwing",
	HitDelay = 16 / 60,
	Damage = 10,
	Stun = 1.1,
	StunKind = "Launch",
	Knockback = 8,
	Lift = 55, -- straight up: a launcher
	GuardDamage = 30,
	Box = Vector3.new(5, 6, 5.5),
	Ahead = 0,
	Lunge = { At = 12 / 60, Distance = 2.5, Time = 0.08 },
	Effect = "M1Final",
	Recovery = 0.7,
	Cooldown = 6,
}

Config.Roundhouse = {
	Animation = "Roundhouse",
	Swing = "KickSwing",
	HitDelay = 17 / 60,
	Damage = 12,
	Stun = 0.9,
	Knockback = 50, -- swept off to his left (the way the leg goes)
	Sideways = true,
	Lift = 12,
	GuardDamage = 40,
	Box = Vector3.new(8, 5.5, 6),
	Ahead = 0,
	Effect = "M1Final",
	Recovery = 0.8,
	Cooldown = 6,
}

Config.AxeKick = {
	Animation = "AxeKick",
	Swing = "KickSwing",
	HitDelay = 30 / 60,
	Damage = 15,
	Stun = 1.2,
	Knockback = 12,
	Lift = 0,
	GuardDamage = 70,
	FromAbove = true, -- blockable from any side, never parryable
	Box = Vector3.new(4.5, 6, 6),
	Ahead = 0,
	Lunge = { At = 26 / 60, Distance = 2, Time = 0.08 },
	Effect = "HeavyHit",
	Recovery = 0.95,
	Cooldown = 8,
}

Config.Teep = {
	Animation = "Teep",
	Swing = "KickSwing",
	HitDelay = 31 / 60, -- a long, heavy wind-up: the tell
	Damage = 13,
	Stun = 1.1,
	Knockback = 85, -- shoved straight back, hard
	Lift = 10,
	GuardDamage = 100,
	GuardBreak = true, -- breaks a block outright (parry it instead)
	Box = Vector3.new(4.5, 5, 7.5),
	Ahead = 0,
	Lunge = { At = 25 / 60, Distance = 3.5, Time = 0.12 },
	Effect = "HeavyHit",
	EffectScale = 1.35, -- a bigger impact than the other strikes'
	Shake = 1.6, -- and a harder camera shake
	Recovery = 1.1,
	Cooldown = 8,
}

Config.GroundSlam = {
	Animation = "GroundSlam",
	HitDelay = 32 / 60, -- both fists into the floor as he lands
	Damage = 12,
	Stun = 1.0,
	StunKind = "Launch",
	Knockback = 35, -- out from him
	Lift = 30,
	GuardDamage = 50,
	FromAbove = true,
	Radius = 11,
	Ahead = 2, -- the slam's centre: this far in front of him (his fists)
	Recovery = 1.05,
	Cooldown = 10,
}

-- The grabs. The reach (Brawler Grab) closes its hands at Grab.At, on whoever is in the box in front
-- of him (the nearest). A grab that connects carries both into the throw: the victim is held (the
-- server anchors them; every client moves them along the path in Brawler.GrabPaths) until Release,
-- and the slam lands at the throw's Hit. A whiff leaves him open for Grab.WhiffRecovery.
Config.Grab = {
	At = 10 / 60, -- the "Hit" marker in Brawler Grab
	Box = Vector3.new(4.5, 6, 4.5),
	Ahead = 0.5,
	Lunge = { At = 4 / 60, Distance = 3.5, Time = 0.1 },
	WhiffRecovery = 0.7,
	Lead = 0.05, -- seconds after the grab connects that the throw starts (so every client starts it together)
	GetUp = 54 / 60, -- the length of Brawler Get Up: the victim can't act until they're back up
}

Config.GrabThrow = {
	Throw = "Throw", -- Brawler.GrabPaths key
	Damage = 9,
	Stun = 1.2,
	StunKind = "Launch",
	Knockback = 60, -- hurled along the swing
	Lift = 22,
	Cooldown = 7,
}

Config.Suplex = {
	Throw = "Suplex",
	Damage = 18,
	Effect = "BodySlam",
	Cooldown = 10,
}

Config.Chokeslam = {
	Throw = "Chokeslam",
	Damage = 20,
	Effect = "BodySlam",
	Cooldown = 11,
}

-- Published animation ids (rbxassetid://...). Leave empty to use the KeyframeSequences inside
-- Brawler/Animations, which only play in Studio: publish them and paste the ids here.
Config.Animations = {
	Haymaker = "",
	Uppercut = "",
	Roundhouse = "",
	AxeKick = "",
	Teep = "",
	GroundSlam = "",
	Grab = "",
	Suplex = "",
	Chokeslam = "",
	Throw = "",
	HeldSuplex = "",
	HeldChokeslam = "",
	HeldThrow = "",
	GetUp = "",
}

return Config
