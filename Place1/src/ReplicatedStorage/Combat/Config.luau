-- Combat tuning. Every timing is in seconds, every distance in studs.
-- Server and client both read this, so changes stay in sync automatically.

local Config = {}

Config.Debug = {
	ShowHitboxes = false, -- draw server hitboxes for a moment when an attack goes out
}

Config.Keybinds = {
	Attack = Enum.UserInputType.MouseButton1,
	Block = Enum.KeyCode.F,
	Heavy = Enum.KeyCode.R,
	Dodge = Enum.KeyCode.Q,
	Slide = Enum.KeyCode.C,
	SprintHold = Enum.KeyCode.LeftControl, -- hold to sprint (double-tapping W also sprints)

	GamepadAttack = Enum.KeyCode.ButtonR2,
	GamepadBlock = Enum.KeyCode.ButtonL2,
	GamepadHeavy = Enum.KeyCode.ButtonY,
	GamepadDodge = Enum.KeyCode.ButtonB,
	GamepadSlide = Enum.KeyCode.ButtonX,
	GamepadSprint = Enum.KeyCode.ButtonL3, -- toggles sprint
}

Config.Movement = {
	WalkSpeed = 16,
	AttackWalkSpeed = 6,
	HeavyWalkSpeed = 3,
	BlockWalkSpeed = 7,
	StunWalkSpeed = 2,
	JumpHeight = 7.2,
	-- You leave "combat mode" (fighting stance) this long after your last combat action.
	CombatModeDuration = 6,
}

Config.Sprint = {
	Speed = 26,
	Acceleration = 40, -- studs/s^2 ramp from walk speed up to sprint speed
	DoubleTapWindow = 0.3,
	BaseFOV = 70,
	SprintFOV = 82,
	SpeedLinesFrom = 22, -- speed at which anime speed lines start to appear
}

Config.Slide = {
	MinSpeed = 17, -- you need to be moving at least this fast (sprinting) to slide
	Boost = 9, -- added to your current speed when the slide starts
	MaxStartSpeed = 44,
	Friction = 24, -- deceleration on flat ground (studs/s^2)
	SlopeGravity = 60, -- how strongly slopes speed you up / slow you down
	EndSpeed = 9, -- the slide ends once you're slower than this
	MaxDuration = 1.6,
	Cooldown = 0.45,
	Steering = 2.2, -- radians per second you can steer while sliding
	JumpKeep = 0.95, -- fraction of slide speed kept when you jump out of a slide
	MomentumDecay = 0.7, -- seconds that slide-jump momentum takes to fade back to normal speed
}

Config.Dodge = {
	Duration = 0.26,
	Speed = 62,
	EndSpeed = 18,
	Cooldown = 1.4,
	IFrames = 0.22, -- invulnerable for this long from the start of the dodge
	CanCancelRecovery = true, -- dodge out of the end of a punch (not out of the windup)
}

-- The 4 hit M1 chain. Windup = time from the press until the hitbox fires, which is also
-- the "impact" key in that punch's animation. Duration = time until you can act again.
Config.M1 = {
	ComboResetTime = 0.85, -- how long after a punch ends before the chain resets to hit 1
	ComboEndCooldown = 0.75, -- extra lockout after the 4th hit
	InputBuffer = 0.18, -- a press this close to the end of a punch queues the next one
	Hits = {
		{
			Anim = "Jab",
			Windup = 0.11,
			Duration = 0.33,
			Damage = 4,
			Stun = 0.55,
			PostureDamage = 12,
			Knockback = 9,
			Lunge = 10,
		},
		{
			Anim = "Cross",
			Windup = 0.12,
			Duration = 0.34,
			Damage = 4,
			Stun = 0.55,
			PostureDamage = 12,
			Knockback = 9,
			Lunge = 10,
		},
		{
			Anim = "Hook",
			Windup = 0.14,
			Duration = 0.36,
			Damage = 5,
			Stun = 0.58,
			PostureDamage = 14,
			Knockback = 10,
			Lunge = 11,
		},
		{
			Anim = "Uppercut",
			Windup = 0.19,
			Duration = 0.55,
			Damage = 7,
			Stun = 0.95,
			PostureDamage = 26,
			Knockback = 46,
			KnockUp = 24,
			Lunge = 16,
			Finisher = true,
		},
	},
	Hitbox = {
		Size = Vector3.new(5, 5.5, 6),
		Offset = CFrame.new(0, 0, -3.2),
	},
}

Config.Heavy = {
	Anim = "Heavy",
	Windup = 0.52,
	Duration = 1.0,
	Cooldown = 4.5,
	Damage = 14,
	Stun = 1.0,
	PostureDamage = 100,
	Knockback = 62,
	KnockUp = 26,
	Lunge = 26,
	GuardBreak = true, -- a heavy that hits a block (not a parry) breaks it
	Hitbox = {
		Size = Vector3.new(6, 6, 7.5),
		Offset = CFrame.new(0, 0, -3.8),
	},
}

Config.Block = {
	MaxPosture = 100,
	DamageMultiplier = 0, -- 0 = blocked hits deal no damage, 0.2 = 20% chip damage
	FacingDot = -0.2, -- how far around you a block covers (1 = only dead ahead, -1 = all around)
	PostureRegenDelay = 1.6,
	PostureRegenRate = 22, -- per second
	BlockedPushback = 10,
}

Config.Parry = {
	-- The first part of every block is a parry. A parry stops the attack dead and stuns the
	-- attacker. The window includes a little server leeway to cover average ping.
	Window = 0.24,
	-- Re-pressing block this soon after a failed parry attempt gives a plain block with
	-- no parry window, so mashing block doesn't work.
	Cooldown = 0.7,
	AttackerStun = 1.25,
	PostureRestore = 25,
	AttackerPushback = 14,
}

Config.GuardBreak = {
	Stun = 1.5,
	PostureAfter = 1, -- fraction of max posture you get back once the guard break stun ends
}

Config.Dummy = {
	MaxHealth = 150,
	RespawnTime = 3,
	RegenDelay = 4, -- full heal after this long without being hit
	AttackRange = 6.5,
	AggroRange = 22,
	LeashRange = 28, -- attacking dummies won't wander further than this from their pad
}

Config.Damage = {
	ShowNumbers = true,
}

-- Hitstop (a tiny freeze on contact) sells the impact. Applied to both fighters.
Config.HitStop = {
	Light = 0.055,
	Finisher = 0.11,
	Heavy = 0.14,
	Block = 0.04,
	Parry = 0.16,
	GuardBreak = 0.14,
}

return Config
