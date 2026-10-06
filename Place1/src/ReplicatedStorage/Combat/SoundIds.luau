-- Sound IDs for every combat / movement sound.
--
-- Put Creator Store (toolbox) audio IDs in the `Ids` lists. When a list has several IDs, a
-- random one plays each time for variety. A sound with no IDs, or whose IDs fail to load,
-- automatically uses its built-in `Fallback`. Fallbacks are layered, pitched and EQ'd
-- versions of sounds that ship with every Roblox client, so the game never goes silent.
--
-- Fields:
--   Ids       = { "rbxassetid://123", ... }
--   Volume    = number
--   Pitch     = { min, max }       random PlaybackSpeed per play
--   Length    = seconds           optional: fade the sound out after this long
--   Fallback  = { layer, ... }     built-in layers: { Id, Volume, Pitch = {min,max}, Start,
--                                  Length, Eq = {Low, Mid, High}, Distortion, Reverb }

local BUILTIN = {
	Wind = "rbxasset://sounds/action_falling.ogg",
	Boom = "rbxasset://sounds/impact_explosion_03.mp3",
	Thud = "rbxasset://sounds/action_jump_land.mp3",
	Steps = "rbxasset://sounds/action_footsteps_plastic.mp3",
	Swim = "rbxasset://sounds/action_swim.mp3",
	Click = "rbxasset://sounds/volume_slider.ogg",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
}

return {
	Swing = {
		Ids = {},
		Volume = 0.55,
		Pitch = { 0.95, 1.1 },
		Fallback = {
			{ Id = BUILTIN.Wind, Volume = 1.4, Pitch = { 2.3, 2.7 }, Start = 0.4, Length = 0.2, Eq = { -30, 0, 6 } },
		},
	},
	SwingHeavy = {
		Ids = {},
		Volume = 0.7,
		Pitch = { 0.92, 1.0 },
		Fallback = {
			{ Id = BUILTIN.Wind, Volume = 1.8, Pitch = { 1.45, 1.6 }, Start = 0.3, Length = 0.42, Eq = { -20, 2, 4 } },
		},
	},
	Hit = {
		Ids = {},
		Volume = 0.8,
		Pitch = { 0.92, 1.1 },
		Fallback = {
			{
				Id = BUILTIN.Boom,
				Volume = 0.9,
				Pitch = { 2.4, 2.8 },
				Length = 0.16,
				Eq = { 4, 0, -4 },
				Distortion = 0.35,
			},
			{ Id = BUILTIN.Thud, Volume = 1.2, Pitch = { 1.25, 1.45 }, Length = 0.18, Eq = { 6, 0, -10 } },
		},
	},
	HitFinisher = {
		Ids = {},
		Volume = 0.95,
		Pitch = { 0.9, 1.0 },
		Fallback = {
			{
				Id = BUILTIN.Boom,
				Volume = 1.2,
				Pitch = { 1.7, 1.9 },
				Length = 0.32,
				Eq = { 6, 0, -2 },
				Distortion = 0.45,
			},
			{ Id = BUILTIN.Thud, Volume = 1.4, Pitch = { 0.95, 1.05 }, Length = 0.25, Eq = { 8, 0, -10 } },
			{ Id = BUILTIN.Wind, Volume = 0.9, Pitch = { 1.9, 2.1 }, Start = 0.4, Length = 0.3, Eq = { -30, 0, 4 } },
		},
	},
	HitHeavy = {
		Ids = {},
		Volume = 1,
		Pitch = { 0.88, 0.96 },
		Fallback = {
			{
				Id = BUILTIN.Boom,
				Volume = 1.5,
				Pitch = { 1.2, 1.35 },
				Length = 0.55,
				Eq = { 8, 0, 0 },
				Distortion = 0.55,
				Reverb = 0.25,
			},
			{ Id = BUILTIN.Thud, Volume = 1.5, Pitch = { 0.8, 0.9 }, Length = 0.3, Eq = { 10, 0, -10 } },
		},
	},
	Block = {
		Ids = {},
		Volume = 0.75,
		Pitch = { 0.95, 1.08 },
		Fallback = {
			{ Id = BUILTIN.Thud, Volume = 1.3, Pitch = { 1.6, 1.8 }, Length = 0.16, Eq = { 0, 4, -8 } },
			{ Id = BUILTIN.Boom, Volume = 0.45, Pitch = { 3.2, 3.6 }, Length = 0.09, Eq = { -10, 4, 2 } },
		},
	},
	GuardBreak = {
		Ids = {},
		Volume = 1,
		Pitch = { 0.95, 1.02 },
		Fallback = {
			{ Id = BUILTIN.Boom, Volume = 1.3, Pitch = { 1.5, 1.6 }, Length = 0.5, Eq = { 0, 4, 6 }, Distortion = 0.6 },
			{ Id = BUILTIN.Click, Volume = 2, Pitch = { 0.6, 0.65 }, Length = 0.4, Eq = { -10, 0, 8 }, Reverb = 0.6 },
		},
	},
	Parry = {
		Ids = {},
		Volume = 1,
		Pitch = { 0.98, 1.06 },
		Fallback = {
			{
				Id = BUILTIN.Boom,
				Volume = 1,
				Pitch = { 3.4, 3.7 },
				Length = 0.14,
				Eq = { -20, 2, 10 },
				Distortion = 0.3,
			},
			{ Id = BUILTIN.Click, Volume = 3, Pitch = { 1.45, 1.55 }, Length = 0.9, Eq = { -20, 0, 10 }, Reverb = 0.9 },
			{
				Id = BUILTIN.Click,
				Volume = 2.2,
				Pitch = { 2.15, 2.25 },
				Length = 0.7,
				Eq = { -20, 0, 10 },
				Reverb = 0.9,
			},
		},
	},
	HeavyCharge = {
		Ids = {},
		Volume = 0.6,
		Pitch = { 1, 1 },
		Length = 0.55,
		Fallback = {
			{
				Id = BUILTIN.Wind,
				Volume = 1.5,
				Pitch = { 0.75, 0.8 },
				Start = 0.2,
				Length = 0.55,
				Eq = { 4, 0, -4 },
				Rise = 1.9,
			},
		},
	},
	Dodge = {
		Ids = {},
		Volume = 0.6,
		Pitch = { 0.95, 1.08 },
		Fallback = {
			{ Id = BUILTIN.Wind, Volume = 1.6, Pitch = { 1.8, 2.0 }, Start = 0.2, Length = 0.3, Eq = { -24, 0, 4 } },
			{ Id = BUILTIN.Jump, Volume = 0.35, Pitch = { 1.3, 1.4 }, Length = 0.2 },
		},
	},
	SlideStart = {
		Ids = {},
		Volume = 0.7,
		Pitch = { 0.95, 1.05 },
		Fallback = {
			{ Id = BUILTIN.Thud, Volume = 0.9, Pitch = { 1.1, 1.2 }, Length = 0.2, Eq = { 4, 0, -6 } },
			{ Id = BUILTIN.Swim, Volume = 0.8, Pitch = { 1.6, 1.7 }, Length = 0.5, Eq = { -10, 2, 2 } },
		},
	},
	SlideLoop = {
		Ids = {},
		Volume = 0.45,
		Pitch = { 1, 1 },
		Looped = true,
		Fallback = {
			{
				Id = BUILTIN.Steps,
				Volume = 1.2,
				Pitch = { 2.6, 2.6 },
				Eq = { -12, 2, 0 },
				Distortion = 0.5,
				Looped = true,
			},
		},
	},
	Land = {
		Ids = {},
		Volume = 0.6,
		Pitch = { 0.9, 1.05 },
		Fallback = {
			{ Id = BUILTIN.Thud, Volume = 1.1, Pitch = { 0.9, 1.0 }, Length = 0.3 },
		},
	},
	BodySlam = {
		Ids = {},
		Volume = 0.8,
		Pitch = { 0.9, 1.0 },
		Fallback = {
			{ Id = BUILTIN.Thud, Volume = 1.6, Pitch = { 0.7, 0.78 }, Length = 0.4, Eq = { 8, 0, -8 } },
			{ Id = BUILTIN.GetUp, Volume = 0.6, Pitch = { 0.9, 1.0 }, Length = 0.4 },
		},
	},
	SprintWind = {
		Ids = {},
		Volume = 0.3,
		Pitch = { 1, 1 },
		Looped = true,
		Fallback = {
			{ Id = BUILTIN.Wind, Volume = 0.55, Pitch = { 1.1, 1.1 }, Eq = { -18, 0, -4 }, Looped = true },
		},
	},
}
