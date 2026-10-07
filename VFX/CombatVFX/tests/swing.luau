--!nocheck
-- Headless test of CombatVFX.Swing / WatchSwings against Place1's mock engine. It plays every frame of
-- the real fist and sword M1s (tests/swing_frames.luau, from make_swing_fixture.py) on a character that
-- is running and turning, and checks when the trails come on, which hand trails and where the bursts go.
-- Run from this folder's parent:
--   cd VFX/CombatVFX && luaurun tests/swing.luau

local mock = assert(loadfile("../../Place1/tests/mock.luau"))()
local fixture = assert(loadfile("tests/swing_frames.luau"))()

local failures, passes = 0, 0
local function check(cond, msg)
	if cond then
		passes += 1
	else
		failures += 1
		print("  FAIL: " .. msg)
	end
end

-- the mock's sequences are opaque; give them real keypoints
NumberSequenceKeypoint = {
	new = function(t, v, e)
		return { __type = "NumberSequenceKeypoint", Time = t, Value = v, Envelope = e or 0 }
	end,
}
NumberSequence = {
	new = function(a, b)
		if type(a) == "number" then
			a = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }
		end
		return { __type = "NumberSequence", Keypoints = a }
	end,
}
ColorSequence = {
	new = function(a, b)
		if a.R ~= nil then
			a = { { Time = 0, Value = a }, { Time = 1, Value = b or a } }
		end
		return { __type = "ColorSequence", Keypoints = a }
	end,
}
NumberRange = {
	new = function(a, b)
		return { __type = "NumberRange", Min = a, Max = b or a }
	end,
}

-- no floor anywhere (the mock's own Raycast returns hits with no Instance); Emit does nothing
local instanceMT = getmetatable(workspace)
local baseIndex = instanceMT.__index
instanceMT.__index = function(self, key)
	if key == "Raycast" and self == workspace then
		return function()
			return nil
		end
	end
	return baseIndex(self, key)
end

local WHITE = Color3.new(1, 1, 1)
local function emitter(parent, name, attrs)
	local e = mock.newInstance("ParticleEmitter", name)
	e.Enabled = false
	e.Lifetime = NumberRange.new(0.1, 0.3)
	e.TimeScale = 1
	e.Size = NumberSequence.new(1)
	e.Speed = NumberRange.new(1, 2)
	e.Acceleration = Vector3.zero
	e.Color = ColorSequence.new(WHITE)
	for k, v in pairs(attrs) do
		e:SetAttribute(k, v)
	end
	e.Parent = parent
	return e
end
local function attachment(parent, name, attrs)
	local a = Instance.new("Attachment")
	a.Name = name
	for k, v in pairs(attrs or {}) do
		a:SetAttribute(k, v)
	end
	a.Parent = parent
	return a
end

-- module + effects: the swing templates with the shipped settings, and the bursts they fire
local holderFolder = mock.newInstance("Folder", "ReplicatedStorage")
local module = mock.module(holderFolder, "CombatVFX", "CombatVFX.luau")
local effects = mock.newInstance("Folder", "Effects")
effects.Parent = module
for name, spec in pairs(fixture.templates) do
	local root = attachment(effects, name, spec.attrs)
	for _, t in ipairs(spec.trails) do
		local trail = mock.newInstance("Trail", t.name)
		trail.Enabled = false
		trail.Lifetime = t.life
		trail.Color = ColorSequence.new(WHITE)
		for k, v in pairs(t.attrs) do
			trail:SetAttribute(k, v)
		end
		trail.Parent = root
	end
	local wake = attachment(root, "Wake", spec.wake.attrs)
	for _, n in ipairs(spec.wake.emitters) do
		emitter(wake, n, { Continuous = true })
	end
end
for _, name in ipairs({ "SwordCut", "SwordThrust", "FistPush", "KickPush" }) do
	emitter(attachment(effects, name), "Air", { EmitCount = 1, EmitDelay = 0 })
end

local VFX = require(module)

-- record every burst
local plays = {}
local frameNow = 0
local realPlay = VFX.Play
VFX.Play = function(name, cframe, options)
	table.insert(plays, { name = name, cframe = cframe, frame = frameNow, options = options })
	return realPlay(name, cframe, options)
end

-- an R6 fighter (with a sword: a Handle with SwingBase / SwingTip, like SwordCombo.rbxm's)
local TIP = Vector3.new(0, 0, -4.195)
local function makeCharacter(name, withSword)
	local character = mock.newInstance("Model", name)
	character.Parent = workspace
	local parts = {}
	local function part(n, size)
		local p = mock.newPart(n, size, CFrame.identity)
		p.Parent = character
		parts[n] = p
		return p
	end
	part("HumanoidRootPart", Vector3.new(2, 2, 1))
	local torso = part("Torso", Vector3.new(2, 2, 1))
	for side, x in pairs({ Right = 1, Left = -1 }) do
		local arm = part(side .. " Arm", Vector3.new(1, 2, 1))
		local shoulder = mock.newInstance("Motor6D", side .. " Shoulder")
		shoulder.Part0, shoulder.Part1, shoulder.C0 = torso, arm, CFrame.new(x, 0.5, 0)
		shoulder.Parent = torso
		local leg = part(side .. " Leg", Vector3.new(1, 2, 1))
		local hip = mock.newInstance("Motor6D", side .. " Hip")
		hip.Part0, hip.Part1, hip.C0 = torso, leg, CFrame.new(x, -1, 0)
		hip.Parent = torso
	end
	if withSword then
		local handle = part("Handle", Vector3.new(0.24, 0.24, 0.95))
		local base = attachment(handle, "SwingBase")
		base.CFrame = CFrame.new(0, 0, -0.75)
		local tip = attachment(handle, "SwingTip")
		tip.CFrame = CFrame.new(TIP)
	end
	return character, parts
end

-- the character runs forward at 40 studs/s while turning (115 deg/s): none of that may count
local function rootAt(t)
	return CFrame.new(0, 3, -40 * t) * CFrame.fromEulerAnglesYXZ(0, 2 * t, 0)
end
local function pose(parts, f, frame)
	local root = rootAt(f / 60)
	parts.HumanoidRootPart.CFrame = root
	for n, v in pairs(frame) do
		parts[n].CFrame = root * CFrame.new(table.unpack(v))
	end
end

local function count(root, name)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			n += 1
		end
	end
	return n
end
local function trailsOn(parts)
	local on = {}
	for n, p in pairs(parts) do
		for _, c in ipairs(p:GetChildren()) do
			if c.ClassName == "Trail" and c.Enabled then
				on[n] = true
			end
		end
	end
	return on
end

-- plays a clip through Swing; returns the frames each part's trails were on, and the bursts
local function playClip(kind, character, parts, clip)
	plays = {}
	VFX.Swing(kind, character, nil, { Duration = #clip.frames / 60 + 0.05 })
	local on = {}
	for i, frame in ipairs(clip.frames) do
		frameNow = i - 1
		pose(parts, frameNow, frame)
		mock.advance(1 / 60)
		for n in pairs(trailsOn(parts)) do
			on[n] = on[n] or {}
			table.insert(on[n], frameNow)
		end
	end
	mock.advance(1)
	check(count(character, "SwingTrail") == 0 and count(character, "SwingWake") == 0, kind .. ": cleaned up after")
	return on, plays
end

-- root-space position of a point on a part, per frame, and the peak of its speed
local function track(clip, partName, point)
	local pos = {}
	for i, frame in ipairs(clip.frames) do
		pos[i - 1] = CFrame.new(table.unpack(frame[partName])) * point
	end
	local peak, best = 0, -1
	for f = 1, #clip.frames - 1 do
		local speed = (pos[f] - pos[f - 1]).Magnitude * 60
		if speed > best then
			peak, best = f, speed
		end
	end
	return pos, peak
end
local function span(frames)
	return frames and (frames[1] .. ".." .. frames[#frames]) or "never"
end

print("== Sword M1s (running and turning the whole time)")
local swordman, swordParts = makeCharacter("Swordsman", true)
for _, name in ipairs({ "m1-1", "m1-2", "running attack", "aerial attack" }) do
	local clip = fixture.sword[name]
	local on, bursts = playClip("SwordSwing", swordman, swordParts, clip)
	local pos, peak = track(clip, "Handle", TIP)
	local frames = on.Handle or {}
	print(
		("  %-15s trail %s  speed peak %d  hit %d  burst %s"):format(
			name,
			span(on.Handle),
			peak,
			clip.hit,
			bursts[1] and (bursts[1].name .. "@" .. bursts[1].frame) or "none"
		)
	)
	check(
		#frames >= 3 and frames[1] >= peak - 6 and frames[#frames] <= peak + 5,
		name .. ": trail only around the slash"
	)
	check(#bursts == 1 and bursts[1].name == "SwordCut", name .. ": one SwordCut")
	local b = bursts[1]
	if b then
		check(b.frame >= peak and b.frame <= peak + 3, name .. ": cut right after the fastest point")
		local travel = rootAt(peak / 60):VectorToWorldSpace((pos[peak] - pos[peak - 1]).Unit)
		check(b.cframe.LookVector:Dot(travel) > 0.9, name .. ": cut looks along the blade's travel")
		local handle = CFrame.new(table.unpack(clip.frames[peak + 1].Handle))
		local axis = rootAt(peak / 60):VectorToWorldSpace(handle:VectorToWorldSpace(-Vector3.zAxis))
		check(math.abs(b.cframe.UpVector:Dot(axis)) < 0.15, name .. ": cut's top is off the swing plane")
		local at = rootAt(peak / 60) * (handle * Vector3.new(0, 0, -0.75):Lerp(TIP, 0.8))
		check((b.cframe.Position - at).Magnitude < 0.05, name .. ": cut at the blade's last fifth")
		check(b.options.Ignore[1] == swordman, name .. ": burst ignores the swinger")
	end
end

print("== Sword stab")
do
	local clip = fixture.sword["m1-3"]
	local on, bursts = playClip("SwordSwing", swordman, swordParts, clip)
	local pos, peak = track(clip, "Handle", TIP)
	print(
		("  %-15s trail %s  speed peak %d  hit %d  burst %s"):format(
			"m1-3",
			span(on.Handle),
			peak,
			clip.hit,
			bursts[1] and (bursts[1].name .. "@" .. bursts[1].frame) or "none"
		)
	)
	check(on.Handle ~= nil and #on.Handle >= 2, "stab trails the point")
	check(#bursts == 1 and bursts[1].name == "SwordThrust", "stab fires one SwordThrust (no cut)")
	if bursts[1] then
		check(bursts[1].frame >= peak and bursts[1].frame <= peak + 3, "thrust burst right after the fastest point")
		local travel = rootAt(peak / 60):VectorToWorldSpace((pos[peak] - pos[peak - 1]).Unit)
		check(bursts[1].cframe.LookVector:Dot(travel) > 0.95, "thrust burst looks along the stab")
	end
end

print("== Unsheathe (a fast draw, but not a swing)")
do
	local on, bursts = playClip("SwordSwing", swordman, swordParts, fixture.sword.unsheathe)
	check(on.Handle == nil and #bursts == 0, "no trail or burst on the draw")
end

print("== Fist M1s: only the punching hand trails")
local STRIKER = {
	["m1-1"] = "Left Arm",
	["m1-2"] = "Right Arm",
	["m1-3"] = "Left Arm",
	["m1-4"] = "Left Arm",
	["m1-5"] = "Right Arm",
	["running attack"] = "Right Arm",
	["aerial attack"] = "Right Arm",
}
local boxer, boxerParts = makeCharacter("Boxer", false)
local FIST = Vector3.new(0, -1, 0)
for _, name in ipairs({ "m1-1", "m1-2", "m1-3", "m1-4", "m1-5", "running attack", "aerial attack" }) do
	local clip = fixture.fist[name]
	local striker = STRIKER[name]
	local guard = striker == "Right Arm" and "Left Arm" or "Right Arm"
	local on, bursts = playClip("FistSwing", boxer, boxerParts, clip)
	local pos, peak = track(clip, striker, FIST)
	print(
		("  %-15s %s %s, %s %s  peak %d  hit %d  burst %s"):format(
			name,
			striker,
			span(on[striker]),
			guard,
			span(on[guard]),
			peak,
			clip.hit,
			bursts[1] and (bursts[1].name .. "@" .. bursts[1].frame) or "none"
		)
	)
	check(on[striker] ~= nil and #on[striker] >= 2, name .. ": the punching fist trails")
	check(on[guard] == nil, name .. ": the guard hand doesn't")
	check(#bursts == 1 and bursts[1].name == "FistPush", name .. ": one FistPush")
	if bursts[1] then
		check(bursts[1].frame >= peak and bursts[1].frame <= peak + 3, name .. ": push right after the fastest point")
		local travel = rootAt(peak / 60):VectorToWorldSpace((pos[peak] - pos[peak - 1]).Unit)
		check(bursts[1].cframe.LookVector:Dot(travel) > 0.9, name .. ": push looks along the punch")
		local fist = rootAt(peak / 60) * pos[peak]
		check(
			(bursts[1].cframe.Position - (fist + travel * 0.6)).Magnitude < 0.05,
			name .. ": push just ahead of the knuckles"
		)
	end
end

print("== Kicks: only the kicking foot trails")
local kicker, kickerParts = makeCharacter("Kicker", false)
local FOOT = Vector3.new(0, -1, 0)
for _, name in ipairs({ "roundhouse", "axe kick" }) do
	local clip = fixture.kick[name]
	local on, bursts = playClip("KickSwing", kicker, kickerParts, clip)
	local pos, peak = track(clip, "Right Leg", FOOT)
	print(
		("  %-15s Right Leg %s, Left Leg %s, arms %s/%s  peak %d  hit %d  burst %s"):format(
			name,
			span(on["Right Leg"]),
			span(on["Left Leg"]),
			span(on["Right Arm"]),
			span(on["Left Arm"]),
			peak,
			clip.hit,
			bursts[1] and (bursts[1].name .. "@" .. bursts[1].frame) or "none"
		)
	)
	check(on["Right Leg"] ~= nil and #on["Right Leg"] >= 3, name .. ": the kicking foot trails")
	check(on["Left Leg"] == nil, name .. ": the standing foot doesn't")
	check(on["Right Arm"] == nil and on["Left Arm"] == nil, name .. ": the arms don't (it's a kick swing)")
	local frames = on["Right Leg"] or {}
	check(
		#frames > 0 and frames[1] <= clip.hit and frames[#frames] >= clip.hit - 1,
		name .. ": trailing through the hit"
	)
	-- a push on each swing of the leg (the axe kick's rise and its chop), one of them at the hit, looking
	-- the way the foot was going round then (it travels on an arc, so within a few frames of it)
	local atHit = nil
	for _, b in ipairs(bursts) do
		check(b.name == "KickPush", name .. ": KickPush bursts")
		if b.frame >= clip.hit - 1 and b.frame <= clip.hit + 3 then
			atHit = b
		end
	end
	check(atHit ~= nil, name .. ": a push at the hit")
	if atHit then
		local along = false
		for f = math.max(atHit.frame - 4, 1), atHit.frame do
			local travel = rootAt(f / 60):VectorToWorldSpace((pos[f] - pos[f - 1]).Unit)
			along = along or atHit.cframe.LookVector:Dot(travel) > 0.9
		end
		check(along, name .. ": the push looks along the kick")
	end
	_ = peak
end

print("== Dashing and spinning with the arms still")
do
	plays = {}
	VFX.Swing("FistSwing", boxer, nil, { Duration = 0.5 })
	local any = false
	for f = 0, 29 do
		local root = CFrame.new(0, 3, -80 * f / 60) * CFrame.fromEulerAnglesYXZ(0, 6 * f / 60, 0)
		boxerParts.HumanoidRootPart.CFrame = root
		for n, v in pairs(fixture.fist["m1-1"].frames[1]) do
			boxerParts[n].CFrame = root * CFrame.new(table.unpack(v))
		end
		mock.advance(1 / 60)
		any = any or next(trailsOn(boxerParts)) ~= nil
	end
	check(not any and #plays == 0, "80 studs/s dash + 340 deg/s spin: no trail, no burst")
	mock.advance(1)
end

print("== Tracks, reuse, colour")
do
	local stopped = mock.Signal.new()
	local animTrack = mock.newInstance("AnimationTrack", "m1-1")
	animTrack.Length, animTrack.Speed, animTrack.Stopped = 1, 1, stopped
	local h1 = VFX.Swing("FistSwing", boxer, animTrack, { Color = Color3.new(1, 0, 0) })
	local h2 = VFX.Swing("FistSwing", boxer, animTrack)
	check(h1 == h2, "a second Swing on the same character reuses the first")
	check(count(boxer, "SwingTrail") == 8, "one set of trails (2 per fist, 2 fists, 2 attachments each)")
	local trail = boxerParts["Right Arm"]:FindFirstChild("Streak")
	check(trail and trail.Color.Keypoints[1].Value.G == 0, "Color recolours the Accent trails")
	mock.advance(0.5)
	check(count(boxer, "SwingTrail") == 8, "still watching while the track plays")
	stopped:Fire()
	mock.advance(1 / 60)
	mock.advance(0.5)
	check(count(boxer, "SwingTrail") == 0, "track stopped: trails removed")

	local h3 = VFX.Swing("FistSwing", boxer, nil, { Duration = 5 })
	mock.advance(0.1)
	h3:Stop()
	mock.advance(0.5)
	check(count(boxer, "SwingTrail") == 0, "handle:Stop() ends it early")
end

print("== No blade")
do
	local bare = makeCharacter("Unarmed", false)
	local h = VFX.Swing("SwordSwing", bare)
	h:Stop()
	check(
		#mock.warnings == 1 and mock.warnings[1]:find("SwingBase") ~= nil,
		"warns once that the sword needs SwingBase / SwingTip"
	)
	VFX.Swing("SwordSwing", bare)
	check(#mock.warnings == 1, "only once per character")
	table.clear(mock.warnings)
	local ok = pcall(VFX.Swing, "Nope", bare)
	check(not ok, "unknown swing name errors")
end

print("== WatchSwings")
do
	local character, parts = makeCharacter("Player1", false)
	local humanoid = mock.newInstance("Humanoid", "Humanoid")
	humanoid.Parent = character
	local animator = mock.newInstance("Animator", "Animator")
	animator.AnimationPlayed = mock.Signal.new()
	animator.Parent = humanoid
	local player = mock.newInstance("Player", "Player1")
	player.Character = character
	table.insert(mock.players, player)

	local watcher = VFX.WatchSwings({ [12345] = "FistSwing", ["Jab"] = "FistSwing" })
	mock.advance(1 / 60)
	local function played(id, name)
		local animation = mock.newInstance("Animation", name)
		animation.AnimationId = id
		local t = mock.newInstance("AnimationTrack", name)
		t.Animation, t.Length, t.Speed, t.Stopped = animation, 0.5, 1, mock.Signal.new()
		animator.AnimationPlayed:Fire(t)
		return t
	end
	played("rbxassetid://999", "Walk")
	check(count(character, "SwingTrail") == 0, "other animations ignored")
	local t = played("rbxassetid://12345", "Animation")
	check(count(character, "SwingTrail") == 8, "matched by animation id")
	t.Stopped:Fire()
	mock.advance(1)
	played("", "Jab")
	check(count(character, "SwingTrail") == 8, "matched by Animation name")
	mock.advance(2)
	watcher:Stop()
	played("rbxassetid://12345", "Animation")
	check(count(character, "SwingTrail") == 0, "Stop() unhooks")
	-- a character spawned later gets hooked too
	local later = makeCharacter("Player1Respawn", false)
	local h2 = mock.newInstance("Humanoid", "Humanoid")
	h2.Parent = later
	local a2 = mock.newInstance("Animator", "Animator")
	a2.AnimationPlayed = mock.Signal.new()
	a2.Parent = h2
	local w2 = VFX.WatchSwings({ [12345] = "FistSwing" })
	player.CharacterAdded:Fire(later)
	mock.advance(1 / 60)
	local animation = mock.newInstance("Animation", "Animation")
	animation.AnimationId = "http://www.roblox.com/asset/?id=12345"
	local t2 = mock.newInstance("AnimationTrack", "x")
	t2.Animation, t2.Length, t2.Speed, t2.Stopped = animation, 0.5, 1, mock.Signal.new()
	a2.AnimationPlayed:Fire(t2)
	check(count(later, "SwingTrail") == 8, "respawned character hooked (asset URL id form)")
	w2:Stop()
	mock.advance(1)
	local _ = parts
end

for _, w in ipairs(mock.warnings) do
	print("  WARNING: " .. w)
end
check(#mock.warnings == 0, "no warnings")
print(("\n%d passed, %d failed"):format(passes, failures))
if failures > 0 then
	error("CombatVFX swing test failed", 0)
end
