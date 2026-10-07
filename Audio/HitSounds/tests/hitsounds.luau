--!nocheck
-- Headless test of HitSounds: nothing until it has ids, a different take every time (never the same
-- one twice in a row, every take used), the pitch and volume nudged within their spreads, ids as
-- numbers or strings, a single take, playing at a point or on a part, the options, and the cleanup.
-- Run from this folder:  cd Audio/HitSounds && luaurun tests/hitsounds.luau

local H = assert(loadfile("../../Abilities/Shared/tests/engine.luau"))()
local mock, check, near = H.mock, H.check, H.near
local RS = game:GetService("ReplicatedStorage")
local HitSounds = require(mock.module(RS, "HitSounds", "HitSounds.luau"))
if workspace:FindFirstChild("Terrain") == nil then
	local terrain = mock.newInstance("Terrain", "Terrain")
	terrain.Parent = workspace
	rawset(workspace, "Terrain", terrain)
end
local AT = Vector3.new(4, 3, -6)

print("== Before the ids are in")
check(HitSounds.Play("FistHit", AT) == nil, "no ids: plays nothing")
check(#workspace.Terrain:GetChildren() == 0, "and leaves nothing behind")
check(HitSounds.Play("Nonsense", AT) == nil, "an unknown kind: nothing")
check(#HitSounds.Ids.FistHit == 8 and #HitSounds.Ids.FistHeavy == 4, "8 fist hits, 4 heavy")
check(#HitSounds.Ids.BloodySlash == 6 and #HitSounds.Ids.BloodyStab == 4, "6 slashes, 4 stabs")

print("== Variation")
HitSounds.Ids.FistHit = { 11, 12, 13, 14, 15, 16, 17, 18 }
local s = HitSounds.Play("FistHit", AT)
check(s ~= nil and s:IsA("Sound") and string.match(s.SoundId, "^rbxassetid://1%d$") ~= nil, "plays one of the takes")
check(
	s and s.Parent and s.Parent:IsA("Attachment") and s.Parent.Parent == workspace.Terrain,
	"from a point in the world"
)
check(s and near(s.Parent.CFrame.Position.X, AT.X) and near(s.Parent.CFrame.Position.Z, AT.Z), "there")
check(s and s.RollOffMaxDistance == HitSounds.RollOffMaxDistance, "rolling off with distance")
local previous, repeats, used = s.SoundId, 0, { [s.SoundId] = true }
local lowest, highest, quietest, loudest = math.huge, -math.huge, math.huge, -math.huge
for _ = 1, 200 do
	local t = HitSounds.Play("FistHit", AT)
	if t.SoundId == previous then
		repeats += 1
	end
	previous = t.SoundId
	used[t.SoundId] = true
	lowest, highest = math.min(lowest, t.PlaybackSpeed), math.max(highest, t.PlaybackSpeed)
	quietest, loudest = math.min(quietest, t.Volume), math.max(loudest, t.Volume)
end
local count = 0
for _ in pairs(used) do
	count += 1
end
check(repeats == 0, "never the same take twice in a row")
check(count == 8, "every take gets used (" .. count .. ")")
check(
	lowest >= 1 - HitSounds.Spread - 1e-9 and highest <= 1 + HitSounds.Spread + 1e-9,
	"the pitch nudged within Spread"
)
check(highest - lowest > HitSounds.Spread, "and it really does vary")
local v = HitSounds.Volume.FistHit
check(
	quietest >= v * (1 - HitSounds.VolumeSpread) - 1e-9 and loudest <= v * (1 + HitSounds.VolumeSpread) + 1e-9,
	"the volume too"
)

print("== Ids, a single take, a part, the options")
HitSounds.Ids.BloodySlash = { "rbxassetid://777", "", "", "", "", "" }
local a = HitSounds.Play("BloodySlash", AT)
local b = HitSounds.Play("BloodySlash", AT)
check(
	a and b and a.SoundId == "rbxassetid://777" and b.SoundId == a.SoundId,
	"only one take filled in: it plays every time"
)
HitSounds.Ids.BloodyStab = { "555", "", "", "" }
check(HitSounds.Play("BloodyStab", AT).SoundId == "rbxassetid://555", "a bare number as a string gets the prefix")
local part = mock.newPart("Target", Vector3.new(2, 2, 1), CFrame.new(0, 3, 0))
part.Parent = workspace
local onPart = HitSounds.Play("BloodyStab", part, { Volume = 2, Pitch = 0.5, Spread = 0 })
check(onPart and onPart.Parent == part, "on a part: it moves with it")
check(onPart and near(onPart.PlaybackSpeed, 0.5), "Pitch (with no spread)")
local stab = HitSounds.Volume.BloodyStab
check(onPart and onPart.Volume >= 2 * stab * 0.9 - 1e-9 and onPart.Volume <= 2 * stab * 1.1 + 1e-9, "Volume")

print("== Cleanup")
mock.advance(3.1)
check(#workspace.Terrain:GetChildren() == 0, "the point holders are gone after they've played")
check(part:FindFirstChildOfClass("Sound") == nil, "and the sound on the part")

H.finish("HitSounds")
