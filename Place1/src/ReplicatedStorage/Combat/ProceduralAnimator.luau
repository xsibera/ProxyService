-- ProceduralAnimator: a client-side R6 animation engine.
--
-- Instead of uploaded Animation assets, every R6 character tagged "Combatant" is posed each
-- frame by writing Motor6D.Transform directly (in RunService.PreSimulation, after Roblox's own
-- animation step). That gives:
--   * true frame-rate animation (sampled at 60/120/240 Hz, not 30 fps keyframes)
--   * stride-synced locomotion (walk/run cycles advance by distance travelled, so no skating)
--   * strafing / backpedalling, lean into acceleration, banking into turns, air poses, landings
--   * layered clips with fades, per-joint masks, hitstop freezes, impact shake and foot planting
--
-- Every client animates every combatant locally. Transform doesn't replicate, so the server
-- broadcasts *what* to play and each client plays it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Data = require(script.Parent.AnimationData)

local ProceduralAnimator = {}

local JOINTS = { "Root", "Neck", "RArm", "LArm", "RLeg", "LLeg" }
local JOINT_COUNT = #JOINTS
local MOTORS = {
	Root = { "HumanoidRootPart", "RootJoint" },
	Neck = { "Torso", "Neck" },
	RArm = { "Torso", "Right Shoulder" },
	LArm = { "Torso", "Left Shoulder" },
	RLeg = { "Torso", "Right Hip" },
	LLeg = { "Torso", "Left Hip" },
}
local CULL_DISTANCE = 300
local GROUND_TOLERANCE = 0.12

local rad = math.rad
local clamp = math.clamp
local abs = math.abs
local sin = math.sin
local exp = math.exp

----------------------------------------------------------------------------------------------
-- Data compilation: poses become flat arrays (6 joints x 6 numbers) so sampling is just math.

local function zeroPose()
	local p = table.create(JOINT_COUNT * 6, 0)
	return p
end

local function writeJoint(pose, jointIndex, values)
	local o = (jointIndex - 1) * 6
	for i = 1, 6 do
		pose[o + i] = values[i] or 0
	end
end

local poseLibrary = {}

local function compilePose(spec)
	if type(spec) == "string" then
		local p = poseLibrary[spec]
		assert(p, "Unknown pose " .. spec)
		return p
	end
	local pose
	if spec.base then
		local base = poseLibrary[spec.base]
		assert(base, "Unknown pose " .. tostring(spec.base))
		pose = table.clone(base)
	else
		pose = zeroPose()
	end
	for index, joint in ipairs(JOINTS) do
		if spec[joint] then
			writeJoint(pose, index, spec[joint])
		end
	end
	return pose
end

for name, spec in pairs(Data.Poses) do
	-- Poses don't reference each other, so plain compilation is enough.
	local pose = zeroPose()
	for index, joint in ipairs(JOINTS) do
		if spec[joint] then
			writeJoint(pose, index, spec[joint])
		end
	end
	poseLibrary[name] = pose
end

local function parseEase(text)
	if not text or text == "Linear" then
		return Enum.EasingStyle.Linear, Enum.EasingDirection.In
	end
	for _, dir in ipairs({ "InOut", "Out", "In" }) do
		if text:sub(-#dir) == dir then
			return Enum.EasingStyle[text:sub(1, -#dir - 1)], Enum.EasingDirection[dir]
		end
	end
	return Enum.EasingStyle[text], Enum.EasingDirection.InOut
end

local clips = {}
for name, spec in pairs(Data.Animations) do
	local keys = {}
	for i, k in ipairs(spec.Keyframes) do
		local style, dir = parseEase(k.ease)
		keys[i] = { t = k.t, pose = compilePose(k.pose), style = style, dir = dir }
	end
	local markers = table.clone(spec.Markers or {})
	table.sort(markers, function(a, b)
		return a.t < b.t
	end)
	clips[name] = {
		Name = name,
		Length = spec.Length,
		Looped = spec.Looped == true,
		FadeIn = spec.FadeIn or 0.05,
		FadeOut = spec.FadeOut or 0.15,
		Priority = spec.Priority or 1,
		UpperBodyWhileMoving = spec.UpperBodyWhileMoving == true,
		Tremble = spec.Tremble,
		Stride = spec.Stride,
		Keys = keys,
		Markers = markers,
	}
end
ProceduralAnimator.Clips = clips

-- Samples a clip at time t into `out` (a flat pose array).
local function sampleClip(clip, t, out)
	local keys = clip.Keys
	local n = #keys
	if t <= keys[1].t or n == 1 then
		table.move(keys[1].pose, 1, JOINT_COUNT * 6, 1, out)
		return out
	end
	if t >= keys[n].t then
		table.move(keys[n].pose, 1, JOINT_COUNT * 6, 1, out)
		return out
	end
	local a, b = keys[1], keys[2]
	for i = 2, n do
		if keys[i].t >= t then
			a, b = keys[i - 1], keys[i]
			break
		end
	end
	local span = b.t - a.t
	local alpha = if span > 0 then (t - a.t) / span else 1
	if b.style ~= Enum.EasingStyle.Linear then
		alpha = TweenService:GetValue(alpha, b.style, b.dir)
	end
	local pa, pb = a.pose, b.pose
	for i = 1, JOINT_COUNT * 6 do
		local va = pa[i]
		out[i] = va + (pb[i] - va) * alpha
	end
	return out
end

local function blendInto(dst, src, weight, mask)
	if weight <= 0 then
		return
	end
	for j = 1, JOINT_COUNT do
		local w = weight * (if mask then mask[j] else 1)
		if w > 0 then
			local o = (j - 1) * 6
			if w >= 1 then
				for i = o + 1, o + 6 do
					dst[i] = src[i]
				end
			else
				for i = o + 1, o + 6 do
					local d = dst[i]
					dst[i] = d + (src[i] - d) * w
				end
			end
		end
	end
end

local function jointCFrame(pose, j)
	local o = (j - 1) * 6
	return CFrame.new(pose[o + 4], pose[o + 5], pose[o + 6])
		* CFrame.fromEulerAnglesYXZ(rad(pose[o + 1]), rad(pose[o + 2]), rad(pose[o + 3]))
end

local function damp(current, target, speed, dt)
	return target + (current - target) * exp(-speed * dt)
end

-- Did a phase value in [0, 1) pass `mark` going from a to b? mark = 1 means the wrap point.
local function crossedMark(a, b, mark, forward)
	if forward then
		if b >= a then
			return a < mark and mark <= b
		end
		return mark > a or mark <= b
	end
	if b <= a then
		return b < mark and mark <= a
	end
	return mark <= a or mark > b
end

-- Clips that count as fighting (they put the rig into its fighting stance for a while).
local NON_COMBAT_CLIPS = { Slide = true, Land = true, Idle = true, Walk = true, Run = true }

----------------------------------------------------------------------------------------------
-- Rig

local Rig = {}
Rig.__index = Rig

local rigs = {} -- [Model] = Rig
local markerListeners = {}
local landListeners = {}
local stepListeners = {}

local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function newRig(model)
	local root = model:FindFirstChild("HumanoidRootPart")
	local torso = model:FindFirstChild("Torso")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not (root and torso and humanoid) then
		return nil
	end
	local motors, rotations, inverses = {}, {}, {}
	for j, joint in ipairs(JOINTS) do
		local info = MOTORS[joint]
		local parent = model:FindFirstChild(info[1])
		local motor = parent and parent:FindFirstChild(info[2])
		if not (motor and motor:IsA("Motor6D")) then
			return nil -- not an R6 rig
		end
		motors[j] = motor
		rotations[j] = motor.C0.Rotation
		inverses[j] = motor.C0.Rotation:Inverse()
	end

	local self = setmetatable({
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Motors = motors,
		Rot = rotations,
		RotInv = inverses,
		Tracks = {},
		Pose = zeroPose(),
		Scratch = zeroPose(),
		Scratch2 = zeroPose(),
		Phase = 0,
		IdleTime = math.random() * 3,
		CombatIdleTime = 0,
		SpeedSmooth = 0,
		RunBlend = 0,
		AirBlend = 0,
		VerticalSmooth = 0,
		LegYaw = 0,
		Backwards = 0,
		LeanPitch = 0,
		BankRoll = 0,
		LastForwardSpeed = 0,
		LastYaw = nil,
		Grounded = true,
		AirTime = 0,
		LastAirVY = 0,
		FrozenUntil = 0,
		ShakeUntil = 0,
		ShakeAmount = 0,
		CombatModeUntil = 0,
		GroundLift = 0,
		Enabled = true,
	}, Rig)

	-- Reference foot height in rest pose, used for foot planting.
	self.RestFootY = self:_lowestFootY(zeroPose())
	return self
end

function Rig:_lowestFootY(pose)
	local motors = self.Motors
	-- Torso in HumanoidRootPart space
	local rootMotor = motors[1]
	local rootT = self.RotInv[1] * jointCFrame(pose, 1) * self.Rot[1]
	local torsoCF = rootMotor.C0 * rootT * rootMotor.C1:Inverse()
	local lowest = math.huge
	for j = 5, 6 do
		local motor = motors[j]
		local t = self.RotInv[j] * jointCFrame(pose, j) * self.Rot[j]
		local legCF = torsoCF * motor.C0 * t * motor.C1:Inverse()
		local leg = motor.Part1
		local half = if leg then leg.Size * 0.5 else Vector3.new(0.5, 1, 0.5)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local y = (legCF * Vector3.new(half.X * sx, -half.Y, half.Z * sz)).Y
				if y < lowest then
					lowest = y
				end
			end
		end
	end
	return lowest
end

-- Plays a clip. opts: Speed, Weight, FadeIn, Looped, StartTime, Mask ({Joint = weight}).
function Rig:Play(name, opts)
	local clip = clips[name]
	if not clip then
		warn("[ProceduralAnimator] unknown clip", name)
		return nil
	end
	opts = opts or {}
	-- Restarting a clip that's already playing reuses its slot so it doesn't stack.
	for i = #self.Tracks, 1, -1 do
		local existing = self.Tracks[i]
		if existing.Clip == clip then
			table.remove(self.Tracks, i)
		end
	end
	local mask
	if opts.Mask then
		mask = table.create(JOINT_COUNT, 0)
		for j, joint in ipairs(JOINTS) do
			mask[j] = opts.Mask[joint] or 0
		end
	end
	local track = {
		Clip = clip,
		Name = name,
		Time = opts.StartTime or 0,
		Speed = opts.Speed or 1,
		TargetWeight = opts.Weight or 1,
		Weight = 0,
		FadeIn = opts.FadeIn or clip.FadeIn,
		FadeOut = clip.FadeOut,
		Looped = if opts.Looped ~= nil then opts.Looped else clip.Looped,
		Stopping = false,
		Mask = mask,
		Started = os.clock(),
		NextMarker = 1,
		Data = opts.Data,
	}
	if track.FadeIn <= 0 then
		track.Weight = track.TargetWeight
	end
	-- skip markers that are before the start time
	while clip.Markers[track.NextMarker] and clip.Markers[track.NextMarker].t < track.Time do
		track.NextMarker += 1
	end
	table.insert(self.Tracks, track)
	table.sort(self.Tracks, function(a, b)
		if a.Clip.Priority == b.Clip.Priority then
			return a.Started < b.Started
		end
		return a.Clip.Priority < b.Clip.Priority
	end)
	if clip.Priority >= 2 and not NON_COMBAT_CLIPS[name] then
		self.CombatModeUntil = math.max(self.CombatModeUntil, os.clock() + 6)
	end
	return track
end

function Rig:Stop(nameOrTrack, fadeOut)
	for _, track in ipairs(self.Tracks) do
		if track == nameOrTrack or track.Name == nameOrTrack then
			track.Stopping = true
			if fadeOut then
				track.FadeOut = fadeOut
			end
		end
	end
end

-- Stops every clip at or above minPriority (default: all non-locomotion clips).
function Rig:StopAll(fadeOut, minPriority)
	for _, track in ipairs(self.Tracks) do
		if track.Clip.Priority >= (minPriority or 1) then
			track.Stopping = true
			if fadeOut then
				track.FadeOut = fadeOut
			end
		end
	end
end

function Rig:IsPlaying(name)
	for _, track in ipairs(self.Tracks) do
		if track.Name == name and not track.Stopping then
			return true
		end
	end
	return false
end

-- Hitstop: freezes the rig's clips for a moment.
function Rig:Freeze(duration)
	self.FrozenUntil = math.max(self.FrozenUntil, os.clock() + duration)
end

function Rig:Shake(amount, duration)
	self.ShakeAmount = math.max(amount, if os.clock() < self.ShakeUntil then self.ShakeAmount else 0)
	self.ShakeUntil = math.max(self.ShakeUntil, os.clock() + duration)
end

function Rig:SetCombatMode(seconds)
	self.CombatModeUntil = math.max(self.CombatModeUntil, os.clock() + seconds)
end

function Rig:_isGrounded(velocity)
	local humanoid = self.Humanoid
	local localPlayer = Players.LocalPlayer
	if localPlayer and self.Model == localPlayer.Character then
		return humanoid.FloorMaterial ~= Enum.Material.Air
	end
	if abs(velocity.Y) > 6 then
		-- quick reject: clearly jumping or falling
		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
			return false
		end
	end
	raycastParams.FilterDescendantsInstances = { self.Model }
	local result = Workspace:Raycast(self.Root.Position, Vector3.new(0, -3.9, 0), raycastParams)
	return result ~= nil
end

local walkClip, runClip = clips.Walk, clips.Run
local idleClip, combatIdleClip = clips.Idle, clips.CombatIdle
local jumpPose, fallPose = poseLibrary.Jump, poseLibrary.Fall
local ARM_MASK = { 0, 1, 1, 1, 0, 0 } -- Neck + arms
local UPPER_MASK_MOVING = { 0.5, 1, 1, 1, 0, 0 }

function Rig:_locomotion(dt, now, frozen)
	local root = self.Root
	local velocity = root.AssemblyLinearVelocity
	local cf = root.CFrame
	local localVel = cf:VectorToObjectSpace(velocity)
	local forward, right = -localVel.Z, localVel.X
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	local grounded = self:_isGrounded(velocity)
	if grounded then
		if not self.Grounded and self.AirTime > 0.12 and self.LastAirVY < -18 then
			local impact = clamp((-self.LastAirVY - 18) / 50, 0.35, 1)
			self:Play("Land", { Weight = impact })
			for _, fn in ipairs(landListeners) do
				task.spawn(fn, self, impact)
			end
		end
		self.AirTime = 0
	else
		self.AirTime += dt
		self.LastAirVY = velocity.Y
	end
	self.Grounded = grounded

	self.SpeedSmooth = damp(self.SpeedSmooth, if grounded then speed else 0, 14, dt)
	local s = self.SpeedSmooth
	local moving = clamp((s - 0.6) / 3, 0, 1)
	self.RunBlend = damp(self.RunBlend, clamp((s - 17) / 6, 0, 1), 8, dt)
	local runW = self.RunBlend
	local airTarget = if grounded or self.AirTime < 0.08 then 0 else 1
	self.AirBlend = damp(self.AirBlend, airTarget, 12, dt)
	self.VerticalSmooth = damp(self.VerticalSmooth, velocity.Y, 10, dt)

	-- Movement direction relative to facing (for strafing / backpedalling)
	local yawTarget, backwards = 0, false
	if speed > 1.5 then
		local theta = math.deg(math.atan2(right, forward)) -- 0 forward, +90 right
		if abs(theta) > 105 then
			backwards = true
			theta = theta - 180 * math.sign(theta)
		end
		yawTarget = clamp(-theta, -70, 70)
	end
	self.LegYaw = damp(self.LegYaw, yawTarget, 10, dt)
	self.Backwards = damp(self.Backwards, if backwards then 1 else 0, 10, dt)

	-- Advance stride phase by distance travelled
	if not frozen then
		local stride = walkClip.Stride + (runClip.Stride - walkClip.Stride) * runW
		local dir = if backwards then -1 else 1
		self.Phase = (self.Phase + dir * s * dt / stride) % 1
		self.IdleTime += dt
		self.CombatIdleTime += dt
	end

	-- Footsteps: both cycles plant a foot at phase 0 and 0.5
	local phase = self.Phase
	local lastPhase = self.LastPhase or phase
	self.LastPhase = phase
	if grounded and s > 4 and #stepListeners > 0 and lastPhase ~= phase then
		if crossedMark(lastPhase, phase, 0.5, not backwards) or crossedMark(lastPhase, phase, 1, not backwards) then
			for _, fn in ipairs(stepListeners) do
				task.spawn(fn, self, runW, s)
			end
		end
	end

	-- Base: idle, or fighting stance when in combat
	local pose = self.Pose
	local combat = self.Model:GetAttribute("AlwaysCombat") == true or now < self.CombatModeUntil
	self.CombatBlend = damp(self.CombatBlend or 0, if combat then 1 else 0, 6, dt)
	local cw = self.CombatBlend
	local scratch = self.Scratch
	sampleClip(idleClip, self.IdleTime % idleClip.Length, pose)
	if cw > 0.001 then
		sampleClip(combatIdleClip, self.CombatIdleTime % combatIdleClip.Length, scratch)
		blendInto(pose, scratch, cw)
	end

	-- Walk / run cycles
	if moving > 0.001 then
		local cyc = self.Scratch2
		sampleClip(walkClip, phase, cyc)
		if runW > 0.001 then
			sampleClip(runClip, phase, scratch)
			blendInto(cyc, scratch, runW)
		end
		-- Fighting stance keeps the guard up while walking (not while sprinting)
		local guardArms = cw * (1 - runW)
		if guardArms > 0.001 then
			sampleClip(combatIdleClip, self.CombatIdleTime % combatIdleClip.Length, scratch)
			blendInto(cyc, scratch, guardArms * 0.85, ARM_MASK)
		end
		blendInto(pose, cyc, moving)
	end

	-- Strafing: turn the legs toward the travel direction
	local legYaw = self.LegYaw * moving
	if abs(legYaw) > 0.01 then
		pose[(5 - 1) * 6 + 2] += legYaw
		pose[(6 - 1) * 6 + 2] += legYaw
		pose[2] += legYaw * 0.25 -- torso follows a little
		pose[6 + 2] -= legYaw * 0.2 -- head stays forward
	end

	-- Air
	local air = self.AirBlend
	if air > 0.001 then
		local vy = self.VerticalSmooth
		local fallW = clamp((-vy + 4) / 30, 0, 1)
		local airPose = scratch
		for i = 1, JOINT_COUNT * 6 do
			airPose[i] = jumpPose[i] + (fallPose[i] - jumpPose[i]) * fallW
		end
		-- arms flail a little when falling
		local flail = sin(now * 9) * 7 * fallW
		airPose[(3 - 1) * 6 + 1] += flail
		airPose[(4 - 1) * 6 + 1] -= flail
		blendInto(pose, airPose, air)
	end

	-- Lean into acceleration and bank into turns (only while moving on the ground)
	local smoothedForward = damp(self.LastForwardSpeed, if grounded then forward else 0, 10, dt)
	local accel = if dt > 0 then (smoothedForward - self.LastForwardSpeed) / dt else 0
	self.LastForwardSpeed = smoothedForward
	local _, yaw = cf:ToEulerAnglesYXZ()
	local yawRate = 0
	if self.LastYaw and dt > 0 then
		local d = yaw - self.LastYaw
		if d > math.pi then
			d -= 2 * math.pi
		elseif d < -math.pi then
			d += 2 * math.pi
		end
		yawRate = d / dt
	end
	self.LastYaw = yaw
	self.LeanPitch = damp(self.LeanPitch, clamp(-accel * 0.18, -9, 7) * moving, 6, dt)
	self.BankRoll = damp(self.BankRoll, clamp(yawRate * s * 0.55, -14, 14) * (if grounded then 1 else 0.4), 7, dt)
	pose[1] += self.LeanPitch
	pose[3] += self.BankRoll

	return grounded, moving
end

function Rig:Step(dt, now)
	local frozen = now < self.FrozenUntil
	local clipDt = if frozen then 0 else dt

	local grounded, moving = self:_locomotion(dt, now, frozen)
	local pose = self.Pose
	local scratch = self.Scratch

	-- Clips
	local tracks = self.Tracks
	local i = 1
	while i <= #tracks do
		local track = tracks[i]
		local clip = track.Clip
		local prevTime = track.Time
		track.Time += clipDt * track.Speed
		if track.Looped then
			if track.Time >= clip.Length then
				track.Time %= clip.Length
				track.NextMarker = 1
			end
		elseif not track.Stopping and track.Time >= clip.Length - track.FadeOut then
			track.Stopping = true
		end
		-- markers
		local markers = clip.Markers
		while markers[track.NextMarker] and markers[track.NextMarker].t <= track.Time do
			local marker = markers[track.NextMarker]
			track.NextMarker += 1
			if marker.t >= prevTime or track.Looped then
				for _, fn in ipairs(markerListeners) do
					task.spawn(fn, self, track, marker)
				end
			end
		end
		-- weights
		if track.Stopping then
			local rate = if track.FadeOut > 0 then track.TargetWeight / track.FadeOut else math.huge
			track.Weight -= rate * dt
		elseif track.Weight < track.TargetWeight then
			local rate = if track.FadeIn > 0 then track.TargetWeight / track.FadeIn else math.huge
			track.Weight = math.min(track.TargetWeight, track.Weight + rate * dt)
		end
		if track.Weight <= 0 and track.Stopping then
			table.remove(tracks, i)
		else
			local t = if track.Looped then track.Time else math.min(track.Time, clip.Length)
			sampleClip(clip, t, scratch)
			if clip.Tremble and t >= clip.Tremble.from and t <= clip.Tremble.to then
				local amt = clip.Tremble.amount
				for j = 1, JOINT_COUNT do
					local o = (j - 1) * 6
					scratch[o + 1] += (math.random() - 0.5) * amt
					scratch[o + 2] += (math.random() - 0.5) * amt
				end
			end
			local mask = track.Mask
			if clip.UpperBodyWhileMoving and moving > 0.05 then
				track.DynMask = track.DynMask or table.create(JOINT_COUNT, 0)
				mask = track.DynMask
				for j = 1, JOINT_COUNT do
					local full = if track.Mask then track.Mask[j] else 1
					local upper = UPPER_MASK_MOVING[j]
					mask[j] = full * (1 + (upper - 1) * moving)
				end
			end
			blendInto(pose, scratch, math.clamp(track.Weight, 0, 1), mask)
			i += 1
		end
	end

	-- Impact shake
	if now < self.ShakeUntil then
		local remaining = (self.ShakeUntil - now)
		local amt = self.ShakeAmount * clamp(remaining * 8, 0, 1)
		pose[1] += (math.random() - 0.5) * amt
		pose[2] += (math.random() - 0.5) * amt
		pose[3] += (math.random() - 0.5) * amt
		pose[4] += (math.random() - 0.5) * amt * 0.02
		pose[6] += (math.random() - 0.5) * amt * 0.02
	end

	-- Foot planting: R6 legs are rigid, so when the torso dips we lift the hips just enough to
	-- keep the feet on the floor. Smoothed so it never pops.
	local lift = 0
	if grounded then
		local lowest = self:_lowestFootY(pose)
		lift = math.max(0, (self.RestFootY - GROUND_TOLERANCE) - lowest)
	end
	self.GroundLift = damp(self.GroundLift, lift, 30, dt)
	pose[5] += self.GroundLift

	-- Write the Motor6D transforms (parent-space pose conjugated into joint space)
	local motors, rot, rotInv = self.Motors, self.Rot, self.RotInv
	for j = 1, JOINT_COUNT do
		motors[j].Transform = rotInv[j] * jointCFrame(pose, j) * rot[j]
	end
end

function Rig:Reset()
	for _, motor in ipairs(self.Motors) do
		if motor.Parent then
			motor.Transform = CFrame.identity
		end
	end
end

----------------------------------------------------------------------------------------------
-- Public API

function ProceduralAnimator.Get(model)
	local rig = rigs[model]
	if rig == nil and model and model.Parent then
		rig = newRig(model)
		if rig then
			rigs[model] = rig
		end
	end
	return rig
end

function ProceduralAnimator.Remove(model)
	local rig = rigs[model]
	if rig then
		rigs[model] = nil
		rig:Reset()
	end
end

function ProceduralAnimator.All()
	return rigs
end

-- fn(rig, track, marker) for every marker crossed in any clip.
function ProceduralAnimator.OnMarker(fn)
	table.insert(markerListeners, fn)
end

-- fn(rig, impact01) when a rig lands from a real fall.
function ProceduralAnimator.OnLand(fn)
	table.insert(landListeners, fn)
end

-- fn(rig, runBlend, speed) on every footfall.
function ProceduralAnimator.OnStep(fn)
	table.insert(stepListeners, fn)
end

local started = false
function ProceduralAnimator.Start()
	if started then
		return
	end
	started = true
	RunService.PreSimulation:Connect(function(dt)
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		dt = math.min(dt, 0.1)
		for model, rig in pairs(rigs) do
			if not model.Parent or not rig.Root.Parent or not rig.Motors[1].Parent then
				rigs[model] = nil
			elseif rig.Enabled and rig.Humanoid.Health > 0 then
				if (rig.Root.Position - camPos).Magnitude < CULL_DISTANCE then
					local ok, err = pcall(rig.Step, rig, dt, now)
					if not ok then
						warn("[ProceduralAnimator]", model.Name, err)
						rig.Enabled = false
					end
				end
			end
		end
	end)
end

return ProceduralAnimator
