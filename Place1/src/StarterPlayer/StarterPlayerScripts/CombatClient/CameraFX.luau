-- Camera feel: trauma-based shake, FOV kicks, colour flashes, blur pulses and speed lines.
-- The shake offset is removed again before Roblox's camera scripts run each frame, so it
-- never drifts or fights the default camera.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Combat = ReplicatedStorage:WaitForChild("Combat")
local Config = require(Combat.Config)
local Util = require(Combat.Util)

local create = Util.create

local CameraFX = {}

local trauma = 0
local lastOffset = CFrame.identity
local fovBase = Config.Sprint.BaseFOV
local fovTarget = fovBase
local fovCurrent = fovBase
local fovKick = 0
local speedLineIntensity = 0
local seed = math.random() * 1000

local colorCorrection, blur
local flashColor, flashStrength, flashDecay = Color3.new(1, 1, 1), 0, 6
local blurStrength, blurDecay = 0, 8

local function effects()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if not colorCorrection or colorCorrection.Parent ~= camera then
		colorCorrection = create("ColorCorrectionEffect", { Name = "CombatFlash", Parent = camera })
		blur = create("BlurEffect", { Name = "CombatBlur", Size = 0, Parent = camera })
	end
end

function CameraFX.Shake(amount)
	trauma = math.min(1, trauma + amount)
end

function CameraFX.Kick(fovDelta)
	fovKick += fovDelta
end

function CameraFX.SetFOV(target)
	fovTarget = target
end

function CameraFX.Flash(color, strength, decay)
	flashColor = color
	flashStrength = math.max(flashStrength, strength)
	flashDecay = decay or 6
end

function CameraFX.Blur(size, decay)
	blurStrength = math.max(blurStrength, size)
	blurDecay = decay or 8
end

function CameraFX.SetSpeedLines(intensity)
	speedLineIntensity = math.clamp(intensity, 0, 1)
end

----------------------------------------------------------------------------------------------
-- Speed lines (screen-space, pooled)

local linesGui, linesFrame
local pool, active = {}, {}

local function ensureLines()
	if linesGui and linesGui.Parent then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	linesGui = create("ScreenGui", {
		Name = "SpeedLines",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = -5,
		Parent = playerGui,
	})
	linesFrame = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Parent = linesGui,
	})
end

local function spawnLine()
	local line = table.remove(pool)
	if not line then
		line = create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = linesFrame,
		})
		create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.35, 0.15),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = line,
		})
	end
	local size = linesFrame.AbsoluteSize
	local half = size / 2
	local angle = math.random() * math.pi * 2
	local dir = Vector2.new(math.cos(angle), math.sin(angle))
	local radius = math.max(half.X, half.Y) * (0.55 + math.random() * 0.25)
	local data = {
		Frame = line,
		Dir = dir,
		Radius = radius,
		Length = 80 + math.random() * 160,
		Thickness = 1 + math.random() * 2,
		Age = 0,
		Life = 0.16 + math.random() * 0.1,
		Center = half,
	}
	line.Rotation = math.deg(angle)
	line.Visible = true
	table.insert(active, data)
end

local function updateLines(dt)
	if speedLineIntensity > 0.01 then
		ensureLines()
		local count = speedLineIntensity * 70 * dt
		while count > 0 do
			if math.random() < count then
				spawnLine()
			end
			count -= 1
		end
	end
	for i = #active, 1, -1 do
		local d = active[i]
		d.Age += dt
		local a = d.Age / d.Life
		if a >= 1 then
			d.Frame.Visible = false
			table.insert(pool, d.Frame)
			table.remove(active, i)
		else
			local r = d.Radius + a * d.Length * 1.5
			local pos = d.Center + d.Dir * r
			d.Frame.Position = UDim2.fromOffset(pos.X, pos.Y)
			d.Frame.Size = UDim2.fromOffset(d.Length, d.Thickness)
			d.Frame.BackgroundTransparency = 0.25 + 0.75 * a
		end
	end
end

----------------------------------------------------------------------------------------------

function CameraFX.Start()
	-- 1) remove last frame's shake before the default camera reads its CFrame
	RunService:BindToRenderStep("CombatCameraFX_Undo", Enum.RenderPriority.Camera.Value - 1, function()
		local camera = Workspace.CurrentCamera
		if camera and lastOffset ~= CFrame.identity then
			camera.CFrame = camera.CFrame * lastOffset:Inverse()
			lastOffset = CFrame.identity
		end
	end)

	-- 2) apply this frame's shake + FOV after the default camera has updated
	RunService:BindToRenderStep("CombatCameraFX", Enum.RenderPriority.Camera.Value + 1, function(dt)
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		effects()
		local t = os.clock()
		trauma = math.max(0, trauma - dt * 1.6)
		local shake = trauma * trauma
		if shake > 0.0005 then
			local freq = 22
			local ax = math.noise(seed, t * freq) * math.rad(2.6) * shake
			local ay = math.noise(seed + 10, t * freq) * math.rad(2.6) * shake
			local az = math.noise(seed + 20, t * freq) * math.rad(3.2) * shake
			local ox = math.noise(seed + 30, t * freq) * 0.35 * shake
			local oy = math.noise(seed + 40, t * freq) * 0.35 * shake
			lastOffset = CFrame.new(ox, oy, 0) * CFrame.Angles(ax, ay, az)
			camera.CFrame = camera.CFrame * lastOffset
		end

		fovKick += (0 - fovKick) * (1 - math.exp(-9 * dt))
		fovCurrent += (fovTarget - fovCurrent) * (1 - math.exp(-6 * dt))
		camera.FieldOfView = math.clamp(fovCurrent + fovKick, 40, 110)

		if colorCorrection then
			flashStrength = math.max(0, flashStrength - flashStrength * flashDecay * dt - 0.01 * dt)
			colorCorrection.TintColor = Color3.new(1, 1, 1):Lerp(flashColor, math.min(1, flashStrength))
			colorCorrection.Brightness = flashStrength * 0.25
			colorCorrection.Contrast = flashStrength * 0.25
			colorCorrection.Saturation = -flashStrength * 0.2
			blurStrength = math.max(0, blurStrength - blurStrength * blurDecay * dt - 0.1 * dt)
			blur.Size = blurStrength
		end

		updateLines(dt)
	end)
end

return CameraFX
