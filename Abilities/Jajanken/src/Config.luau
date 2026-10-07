--!strict
--[[
	Jajanken settings: Gon Freecss's Hatsu. Hold a key to gather aura into the fist, let go to cast.

	  Rock      a lunging punch that detonates the aura in the fist (close range, heavy)
	  Paper     an open palm that throws the aura as a ball, which explodes (ranged)
	  Scissors  two fingers become a blade of aura swept across the front (wide, fast)

	Charge: tap for a quick cast, or hold up to MaxCharge seconds for full power. Letting go at any
	point casts it. At MaxCharge it casts by itself. Damage, knockback, size, range and the effects
	all scale with the charge (0 = tapped, 1 = full).

	Each pair { min, max } below is { tapped, fully charged }.
]]

local Config = {}

-- controls
Config.Keys = {
	Rock = Enum.KeyCode.Z,
	Paper = Enum.KeyCode.X,
	Scissors = Enum.KeyCode.C,
}
Config.GamepadButtons = {
	Rock = Enum.KeyCode.ButtonX,
	Paper = Enum.KeyCode.ButtonY,
	Scissors = Enum.KeyCode.ButtonB,
}
Config.MobileButtons = true -- on-screen buttons on touch devices

-- charging
Config.MaxCharge = 3 -- seconds to full power; it casts itself when it gets there
Config.ChargeWalkSpeed = 4 -- walk speed while charging and casting (0 = rooted in the stance)
Config.CanJumpWhileCharging = false
Config.Chant = true -- "Saisho wa guu! Jan... Ken..." over the charge bar

-- cooldowns (seconds, counted from the cast)
Config.Cooldown = {
	Rock = 4,
	Paper = 5,
	Scissors = 3.5,
}
Config.SharedCooldown = 0.8 -- after any cast, all three wait at least this long

-- who can be hit
Config.HitPlayers = true -- false: only NPCs (Humanoids without a Player)
Config.TeamCheck = true -- don't hit players on the caster's team (when Teams are used)
Config.KnockbackTime = 0.18 -- seconds the knockback push lasts

Config.Rock = {
	Damage = { 12, 45 },
	Knockback = { 35, 95 }, -- studs/s
	Hitbox = { Vector3.new(5, 5, 6), Vector3.new(9, 8, 10) }, -- in front of the caster
	HitDelay = 24 / 60, -- seconds from the release to the hit: the "Hit" marker in Jajanken Rock
	Recovery = 0.85, -- seconds the caster is busy after the release
}

Config.Paper = {
	Damage = { 10, 38 }, -- a direct hit; the blast falls off to half at its edge
	Knockback = { 25, 80 },
	Speed = { 75, 120 }, -- studs/s
	Range = { 70, 140 }, -- studs before it bursts by itself
	Radius = { 1.2, 2.6 }, -- the ball's size for hitting things
	BlastRadius = { 7, 15 },
	HitDelay = 22 / 60, -- the "Hit" marker in Jajanken Paper (the ball leaves the palm)
	Recovery = 0.8,
	AimWithCamera = true, -- throw it where the camera looks (within MaxAimAngle of the facing)
	MaxAimAngle = 70,
}

Config.Scissors = {
	Damage = { 9, 32 },
	Knockback = { 15, 40 },
	Hitbox = { Vector3.new(10, 5, 7), Vector3.new(16, 6, 12) }, -- wide and flat in front
	HitDelay = 20 / 60, -- the "Hit" marker in Jajanken Scissors
	Recovery = 0.8,
}

-- Published animation ids (rbxassetid://...). Leave empty to use the KeyframeSequences inside
-- Jajanken/Animations, which only play in Studio: publish them (Animation Editor) and paste the
-- ids here before a live game.
Config.Animations = {
	Charge = "",
	Hold = "",
	Rock = "",
	Paper = "",
	Scissors = "",
}

Config.Modes = { "Rock", "Paper", "Scissors" }

-- charge (0..1) -> a value between a { tapped, full } pair
function Config.scaled(pair: { any }, charge: number): any
	return pair[1] + (pair[2] - pair[1]) * math.clamp(charge, 0, 1)
end

return Config
