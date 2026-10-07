--!nocheck
-- Headless test of LoadoutClient against Place1's mock engine: the four keys handed to whichever
-- ability sits in the slot, the hotbar (names, cooldowns, denial flash) and the menu (pick an
-- ability then a key, or a key then an ability; presets; right-click to empty).
-- Run from this folder:  cd Abilities/Loadout && luaurun tests/client.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check = H.mock, H.check
local Loadout = require(H.LoadoutModule)

local Players = game:GetService("Players")
local character = H.character("Gon", 0, 0, 0)
local gon = H.player("Gon", character)
mock.newInstance("PlayerGui", "PlayerGui").Parent = gon
Players.LocalPlayer = gon
gon:SetAttribute("Loadout", "LightningPalm,Thunderbolt,Whirlwind,LightningDash")

local calls = {}
for _, ability in ipairs(Loadout.Order) do
	Loadout.bind(ability, function(state)
		table.insert(calls, { ability = ability, state = state })
	end)
end

local client = mock.newInstance("LocalScript", "LoadoutClient")
rawget(client, "__props").__path = "src/LoadoutClient.client.luau"
client.Parent = gon
mock.runScript(client)
mock.advance(0.05)

local function find(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
end
local function key(slot, state)
	return mock.actions["AbilitySlot" .. slot].fn("AbilitySlot" .. slot, state)
end
local gui = gon.PlayerGui:FindFirstChild("LoadoutUI")

print("== Boot")
check(gui ~= nil, "UI made")
for slot = 1, 4 do
	local action = mock.actions["AbilitySlot" .. slot]
	check(
		action ~= nil and action.inputs[1] == Loadout.Slots[slot],
		"slot " .. slot .. " on " .. Loadout.Slots[slot].Name
	)
end
check(mock.actions.LoadoutMenu ~= nil and mock.actions.LoadoutMenu.inputs[1] == Enum.KeyCode.M, "M opens the menu")
local hotbar = find(gui, "Hotbar")
check(find(hotbar, "Slot1"):FindFirstChild("AbilityName").Text == "Lightning Palm", "hotbar: Z is Lightning Palm")
check(find(hotbar, "Slot4"):FindFirstChild("AbilityName").Text == "Lightning Dash", "hotbar: V is Lightning Dash")

print("== Keys")
key(1, Enum.UserInputState.Begin)
check(#calls == 1 and calls[1].ability == "LightningPalm", "Z goes to the ability in slot 1")
gon:SetAttribute("Loadout", "Rock,Thunderbolt,Whirlwind,LightningDash")
key(1, Enum.UserInputState.End)
check(#calls == 2 and calls[2].ability == "LightningPalm", "the release goes to the same ability, even after a change")
key(1, Enum.UserInputState.Begin)
key(1, Enum.UserInputState.End)
check(calls[3].ability == "Rock" and calls[4].ability == "Rock", "then Z is Rock")
check(find(hotbar, "Slot1"):FindFirstChild("AbilityName").Text == "Rock", "hotbar follows the change")
gon:SetAttribute("Loadout", ",Thunderbolt,Whirlwind,LightningDash")
local result = key(1, Enum.UserInputState.Begin)
check(#calls == 4 and result == Enum.ContextActionResult.Pass, "an empty slot does nothing and passes the key on")

print("== Cooldowns on the hotbar")
gon:SetAttribute("Loadout", "Rock,Thunderbolt,Whirlwind,LightningDash")
Loadout.setCooldown("Thunderbolt", os.clock() + 5, 10)
mock.advance(0.05)
local slot2 = find(hotbar, "Slot2")
check(slot2:FindFirstChild("Cooldown").Size[2] > 0.45, "half a cooldown left: half shaded")
check(slot2:FindFirstChild("Cooldown") and find(slot2, "AbilityName") and true, "slot parts")
mock.advance(5.1)
check(slot2:FindFirstChild("Cooldown").Size[2] == 0, "ready: no shade")

print("== The menu")
local menu = find(gui, "Menu")
check(menu.Visible == false, "closed at first")
mock.actions.LoadoutMenu.fn("LoadoutMenu", Enum.UserInputState.Begin)
check(menu.Visible == true, "M opens it")
table.clear(H.remoteLog)
find(menu, "Paper").Activated:Fire()
find(menu, "Key4").Activated:Fire()
local sent = H.sent("Set", "client")
check(#sent == 1 and sent[1].args[2] == 4 and sent[1].args[3] == "Paper", "ability then key: Set(4, Paper)")
find(menu, "Key1").Activated:Fire()
find(menu, "LightningDash").Activated:Fire()
sent = H.sent("Set", "client")
check(
	#sent == 2 and sent[2].args[2] == 1 and sent[2].args[3] == "LightningDash",
	"key then ability: Set(1, LightningDash)"
)
find(menu, "Key3").MouseButton2Click:Fire()
sent = H.sent("Set", "client")
check(#sent == 3 and sent[3].args[2] == 3 and sent[3].args[3] == "", "right-click empties a key")
find(menu, "PresetGon").Activated:Fire()
check(#H.sent("Preset", "client") == 1 and H.sent("Preset", "client")[1].args[2] == "Gon", "preset button")
check(find(menu, "Rock"):FindFirstChildOfClass("TextLabel") ~= nil, "cards have labels")
find(gui, "OpenMenu").Activated:Fire()
check(menu.Visible == false, "the Abilities button closes it again")

H.finish("Loadout client")
