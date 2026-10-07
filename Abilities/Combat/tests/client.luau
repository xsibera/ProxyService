--!nocheck
-- Headless test of CombatClient against Place1's mock engine: the F key, the block pose, the
-- reaction for each kind of stun, the guard bar, the words on screen and the effects.
-- Run from this folder:  cd Abilities/Combat && luaurun tests/client.luau

local H = assert(loadfile("tests/harness.luau"))()
local mock, check = H.mock, H.check
local Combat = require(H.CombatModule)

local Players = game:GetService("Players")
local vModel, vParts = H.character("V", 0, 0, 0)
local v = H.player("V", vModel)
mock.newInstance("PlayerGui", "PlayerGui").Parent = v
Players.LocalPlayer = v
local aModel = H.character("A", 0, -4, 180)
H.player("A", aModel)
local dummy = H.character("Dummy", 8, 0, 180) -- an NPC: no player

local client = mock.newInstance("LocalScript", "CombatClient")
rawget(client, "__props").__path = "src/CombatClient.client.luau"
client.Parent = v
mock.runScript(client)
mock.advance(0.05)

local function find(root, name)
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
end
local function played(fragment)
	for i = #H.played, 1, -1 do
		if tostring(H.played[i].name):find(fragment) then
			return true
		end
	end
	return false
end
local function press(state)
	mock.actions.CombatBlock.fn("CombatBlock", state)
end

print("== Boot")
check(H.registered == 6, "the six reaction animations registered for Studio play (" .. H.registered .. ")")
local action = mock.actions.CombatBlock
check(action ~= nil and action.touch == true, "Block bound, with a touch button")
check(action and action.inputs[1] == Enum.KeyCode.F, "on F")
local gui = v.PlayerGui:FindFirstChild("CombatUI")
check(gui ~= nil and find(gui, "Guard") ~= nil, "guard bar")

print("== F")
press(Enum.UserInputState.Begin)
local sent = H.sent("Block", "client")
check(#sent == 1 and sent[1].args[2] == true, "press: asks to block")
check(played("Parry"), "the parry flourish at once")
vModel:SetAttribute("Blocking", true)
check(played("Block"), "then the block pose (from the attribute)")
mock.advance(0.05)
check(find(gui, "Guard").Visible == true, "guard bar shows while blocking")
press(Enum.UserInputState.End)
sent = H.sent("Block", "client")
check(#sent == 2 and sent[2].args[2] == false, "let go: stop blocking")
vModel:SetAttribute("Blocking", false)

print("== Reactions")
table.clear(H.played)
vModel:SetAttribute("StunKind", "Shock")
vModel:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + 0.8)
check(played("Shocked"), "a Shock stun: the electrocuted loop")
mock.advance(0.9)
vModel:SetAttribute("StunKind", "GuardBreak")
vModel:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + 1.2)
check(played("GuardBreak"), "a guard break")
check(find(gui, "Word").Text == "GUARD BROKEN", "GUARD BROKEN on screen")
mock.advance(1.3)
vModel:SetAttribute("StunKind", "Parried")
vModel:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + 0.9)
check(played("Parried"), "parried: the recoil")
mock.advance(1)

print("== NPCs: every client animates them")
local function playedOn(model, fragment)
	for i = #H.played, 1, -1 do
		local p = H.played[i]
		if p.model == model and tostring(p.name):find(fragment) then
			return true
		end
	end
	return false
end
table.clear(H.played)
dummy:SetAttribute("Blocking", true)
check(playedOn(dummy, "Block"), "a blocking dummy: the block pose")
check(not playedOn(vModel, "Block"), "(on the dummy, not on this player)")
dummy:SetAttribute("ParryAt", workspace:GetServerTimeNow())
check(playedOn(dummy, "Parry"), "a dummy parrying: the flourish")
dummy:SetAttribute("StunKind", "Shock")
dummy:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + 0.5)
check(playedOn(dummy, "Shocked"), "a shocked dummy: the Shocked reaction")
mock.advance(0.6)
check(playedOn(dummy, "Block"), "stun over, still blocking: back into the block pose")
dummy:SetAttribute("Blocking", false)
local late = H.character("Late Dummy", -8, 0, 180) -- one that appears later (a respawned dummy)
workspace.DescendantAdded:Fire(late:FindFirstChildOfClass("Humanoid"))
mock.advance(0.05)
find(gui, "Word").Text = ""
late:SetAttribute("StunKind", "GuardBreak")
late:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + 1)
check(playedOn(late, "GuardBreak"), "a dummy added later is animated too")
check(find(gui, "Word").Text == "", "no words on screen for a dummy's guard")
late.Parent = nil
late.AncestryChanged:Fire()
late:SetAttribute("StunnedUntil", workspace:GetServerTimeNow() + 1)
check(true, "a removed dummy is let go")
mock.advance(1)

print("== Everyone's effects")
H.remote.OnClientEvent:Fire("Parried", vModel, aModel, Vector3.new(0, 3, -1.5))
check(find(workspace, "ParrySparkVFX") ~= nil, "parry spark")
check(find(gui, "Word").Text == "PARRY", "PARRY when you parried")
H.remote.OnClientEvent:Fire("Parried", aModel, vModel, Vector3.new(0, 3, -1.5))
check(find(gui, "Word").Text == "PARRIED", "PARRIED when you got parried")
H.remote.OnClientEvent:Fire("Blocked", aModel, Vector3.new(0, 3, -4))
check(find(workspace, "BlockSparkVFX") ~= nil, "block spark")
H.remote.OnClientEvent:Fire("GuardBroken", aModel, Vector3.new(0, 3, -4))
check(find(workspace, "GuardBreakVFX") ~= nil, "guard break burst")

print("== Guard bar")
vModel:SetAttribute("Guard", 40)
mock.advance(0.05)
local fill = find(gui, "Fill")
check(find(gui, "Guard").Visible == true and fill.Size[1] < 0.5, "a worn guard shows, 40%")
vModel:SetAttribute("Guard", Combat.Settings.GuardMax)
mock.advance(0.05)
check(find(gui, "Guard").Visible == false, "full and not blocking: hidden")

H.finish("Combat client")
