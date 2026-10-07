--!strict
--[[
	Loadout (ReplicatedStorage.Loadout): which abilities a player has on their four keys.

	The server keeps each player's loadout in the "Loadout" attribute on the Player (the ability
	names in slot order, comma-separated), so every client can read it. LoadoutServer changes it when
	a player picks something in the menu (LoadoutClient), and the ability kits ask it:

	  Loadout.has(player, ability) -> boolean        (servers: refuse abilities that aren't equipped)
	  Loadout.get(player) -> { string }              slot -> ability name ("" = empty)
	  Loadout.slotOf(player, ability) -> number?

	On the client, LoadoutClient owns the keys (Z X C V, or Slots below) and hands each press to the
	kit that registered the ability equipped in that slot:

	  Loadout.bind(ability, handler)                 handler(state: Enum.UserInputState)
	  Loadout.setCooldown(ability, readyAt, total)   for the hotbar (os.clock times)
	  Loadout.deny(ability)                          flash the slot red (on cooldown, busy...)

	To add a kit: list its abilities in Loadout.Abilities and, if you like, a preset.
]]

local Loadout = {}

Loadout.Slots = { Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.V }
Loadout.GamepadSlots = { Enum.KeyCode.ButtonX, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonB, Enum.KeyCode.ButtonR1 }
Loadout.MenuKey = Enum.KeyCode.M

export type Ability = { Kit: string, Character: string, Name: string, Hint: string }

Loadout.Abilities = {
	Rock = {
		Kit = "Jajanken",
		Character = "Gon",
		Name = "Rock",
		Hint = "Hold to charge, let go: a lunging punch that sets off the aura in the fist.",
	},
	Paper = {
		Kit = "Jajanken",
		Character = "Gon",
		Name = "Paper",
		Hint = "Hold to charge, let go: the aura thrown from the palm as a ball that explodes.",
	},
	Scissors = {
		Kit = "Jajanken",
		Character = "Gon",
		Name = "Scissors",
		Hint = "Hold to charge, let go: a blade of aura swept wide across the front.",
	},
	LightningPalm = {
		Kit = "Killua",
		Character = "Killua",
		Name = "Lightning Palm",
		Hint = "A lunging palm that shocks: the target is paralysed. Parryable.",
	},
	Thunderbolt = {
		Kit = "Killua",
		Character = "Killua",
		Name = "Thunderbolt",
		Hint = "Leap and bring lightning down where you aim. Blockable, never parryable: get out of the ring.",
	},
	Whirlwind = {
		Kit = "Killua",
		Character = "Killua",
		Name = "Whirlwind",
		Hint = "Counter stance: if you're hit, vanish behind the attacker and strike back. Whiffing leaves you open.",
	},
	LightningDash = {
		Kit = "Killua",
		Character = "Killua",
		Name = "Lightning Dash",
		Hint = "Up to three lightning-quick teleports, striking whoever you pass. Untouchable mid-dash.",
	},
	WarpPunch = {
		Kit = "Leorio",
		Character = "Leorio",
		Name = "Warp Punch",
		Hint = "Punch the floor: your fist comes out of a warp hole beside your target's head. Face the hole to block it.",
	},
	RemoteJab = {
		Kit = "Leorio",
		Character = "Leorio",
		Name = "Remote Jab",
		Hint = "A quick jab into a warp hole: it lands from behind your target and pulls them toward you.",
	},
	WarpBarrage = {
		Kit = "Leorio",
		Character = "Leorio",
		Name = "Warp Barrage",
		Hint = "Pound the floor: fists come at your target from all sides, then one hammers down from above.",
	},
	PortalBurst = {
		Kit = "Leorio",
		Character = "Leorio",
		Name = "Portal Burst",
		Hint = "Both fists into the floor: fists burst up from a ring of warp holes, launching everyone near you.",
	},
} :: { [string]: Ability }

-- the order the menu lists them in, by character
Loadout.Order = {
	"Rock",
	"Paper",
	"Scissors",
	"LightningPalm",
	"Thunderbolt",
	"Whirlwind",
	"LightningDash",
	"WarpPunch",
	"RemoteJab",
	"WarpBarrage",
	"PortalBurst",
}

Loadout.Presets = {
	Gon = { "Rock", "Paper", "Scissors", "" },
	Killua = { "LightningPalm", "Thunderbolt", "Whirlwind", "LightningDash" },
	Leorio = { "WarpPunch", "RemoteJab", "WarpBarrage", "PortalBurst" },
}
Loadout.PresetOrder = { "Gon", "Killua", "Leorio" }
Loadout.Default = "Killua"

--------------------------------------------------------------------------- reading and writing

function Loadout.parse(text: any): { string }
	local out = {}
	local parts = if typeof(text) == "string" then string.split(text, ",") else {}
	for i = 1, #Loadout.Slots do
		local name = parts[i] or ""
		out[i] = if Loadout.Abilities[name] then name else ""
	end
	return out
end

function Loadout.format(slots: { string }): string
	local parts = {}
	for i = 1, #Loadout.Slots do
		table.insert(parts, slots[i] or "")
	end
	return table.concat(parts, ",")
end

function Loadout.get(player: Player): { string }
	return Loadout.parse(player:GetAttribute("Loadout"))
end

function Loadout.slotOf(player: Player, ability: string): number?
	for i, name in Loadout.get(player) do
		if name == ability then
			return i
		end
	end
	return nil
end

function Loadout.has(player: Player, ability: string): boolean
	return Loadout.slotOf(player, ability) ~= nil
end

-- the loadout after putting `ability` in `slot` ("" empties it): an ability sits in one slot at
-- most, so if it was elsewhere it swaps with whatever the slot held
function Loadout.place(slots: { string }, slot: number, ability: string): { string }
	local out = table.clone(slots)
	if ability ~= "" then
		for i, name in out do
			if name == ability then
				out[i] = out[slot] or ""
			end
		end
	end
	out[slot] = ability
	return out
end

--------------------------------------------------------------------------- client side: keys and the hotbar

local handlers: { [string]: (Enum.UserInputState) -> () } = {}
local cooldowns: { [string]: { readyAt: number, total: number } } = {}
local denied: { [string]: number } = {}

function Loadout.bind(ability: string, handler: (Enum.UserInputState) -> ())
	handlers[ability] = handler
end

function Loadout.handler(ability: string): ((Enum.UserInputState) -> ())?
	return handlers[ability]
end

function Loadout.setCooldown(ability: string, readyAt: number, total: number)
	cooldowns[ability] = { readyAt = readyAt, total = math.max(total, 0.01) }
end

-- seconds left and the full cooldown
function Loadout.cooldown(ability: string, now: number): (number, number)
	local entry = cooldowns[ability]
	if not entry then
		return 0, 1
	end
	return math.max(entry.readyAt - now, 0), entry.total
end

function Loadout.deny(ability: string)
	denied[ability] = os.clock()
end

function Loadout.deniedAt(ability: string): number
	return denied[ability] or -math.huge
end

return Loadout
