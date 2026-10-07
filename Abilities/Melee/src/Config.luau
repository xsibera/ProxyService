--!strict
--[[
	Melee settings: a basic stun fighting system. Left click throws a five-hit M1 string: a jab, an
	overhand, a hook, an uppercut, then a spinning backfist that knocks the target away. Every hit
	stuns the target for long enough that the next one lands (a true combo, if you keep clicking in
	time); the fifth ends the string.

	The stun itself (the timer, the hit reaction, being unable to attack or block while it lasts) is
	ReplicatedStorage.Combat's, so blocks and parries work against M1s too.

	Every number is in studs, seconds or studs per second. Damage is in health points.
]]

local Config = {}

-- controls: left click (hold to keep the string going); gamepad R2; an on-screen button on touch
Config.GamepadButton = Enum.KeyCode.ButtonR2
Config.MobileButton = true
Config.TurnToCamera = true -- each swing turns you to face where the camera looks

-- the string. HitDelay: from the swing to the hit (the animation's "Hit" marker). Next: when the next
-- hit can be thrown (the animation is cancelled into it then). Stun: how long the target is stunned,
-- which covers the gap to the next hit with time to spare.
Config.Hits = {
	{ Animation = "M1_1", HitDelay = 20 / 60, Next = 0.48, Damage = 4, Stun = 0.75 }, -- lead jab
	{ Animation = "M1_2", HitDelay = 24 / 60, Next = 0.55, Damage = 4, Stun = 0.75 }, -- rear overhand
	{ Animation = "M1_3", HitDelay = 24 / 60, Next = 0.55, Damage = 4, Stun = 0.75 }, -- lead hook
	{ Animation = "M1_4", HitDelay = 25 / 60, Next = 0.58, Damage = 4, Stun = 1.0 }, -- uppercut
	-- the finisher: a spinning backfist that sends them flying
	{ Animation = "M1_5", HitDelay = 39 / 60, Damage = 6, Stun = 0.9, Knockback = 55, Lift = 16 },
}
Config.ComboWindow = 0.6 -- seconds after a hit's Next to throw the following one, or the string starts over
Config.FinisherRecovery = 0.8 -- after the finisher, seconds before you can block or use an ability
Config.FinisherCooldown = 1.15 -- after the finisher starts, seconds before a new string

Config.Hitbox = Vector3.new(5, 5.5, 6) -- the box in front of you at the moment of each hit
Config.Push = 8 -- studs/s the target is pushed on hits 1-4 (with Lunge, you stay in range)
Config.Lunge = 10 -- studs/s you step in on each hit
Config.LungeTime = 0.15
Config.AttackWalkSpeed = 10 -- while swinging
Config.NpcDamage = 0.75 -- an NPC's hits (the village's bandits) deal this share of a player's damage
Config.HitPlayers = true -- false: only NPCs (Humanoids without a Player)
Config.TeamCheck = true -- don't hit players on your own team (when Teams are used)

-- Published animation ids (rbxassetid://...). Leave empty to use the KeyframeSequences inside
-- Melee/Animations, which only play in Studio: publish them and paste the ids here.
Config.Animations = {
	M1_1 = "",
	M1_2 = "",
	M1_3 = "",
	M1_4 = "",
	M1_5 = "",
}

-- the effects (ReplicatedStorage.CombatVFX, the combat effects pack) and sounds (Melee.Sounds)
Config.HitEffect = "M1Hit"
Config.FinisherEffect = "M1Final"
Config.SwingEffect = "FistSwing"
Config.Color = nil :: Color3? -- tint the wind for a move's colour (nil: white and grey)

return Config
