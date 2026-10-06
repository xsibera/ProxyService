-- Client-side sound player. Plays Creator Store IDs from SoundIds when they load, otherwise
-- the built-in layered fallback, so every action always has a sound.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local SoundIds = require(script.Parent.SoundIds)
local Util = require(script.Parent.Util)

local create = Util.create

local SFX = {}

local idStatus = {} -- [contentId] = true (loaded) | false (failed)

local function normalise(id)
	if type(id) == "number" then
		return "rbxassetid://" .. id
	end
	if type(id) == "string" and id:match("^%d+$") then
		return "rbxassetid://" .. id
	end
	return id
end

function SFX.Preload()
	local probes = {}
	for _, def in pairs(SoundIds) do
		for i, id in ipairs(def.Ids or {}) do
			id = normalise(id)
			def.Ids[i] = id
			if idStatus[id] == nil then
				table.insert(probes, create("Sound", { SoundId = id }))
			end
		end
	end
	if #probes == 0 then
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(probes, function(contentId, status)
				if status == Enum.AssetFetchStatus.Success then
					idStatus[contentId] = true
				elseif status == Enum.AssetFetchStatus.Failure or status == Enum.AssetFetchStatus.TimedOut then
					idStatus[contentId] = false
					warn("[SFX] couldn't load " .. contentId .. ", using the built-in fallback")
				end
			end)
		end)
		if not ok then
			warn("[SFX] preload failed:", err)
		end
		for _, probe in ipairs(probes) do
			probe:Destroy()
		end
	end)
end

local soundRoot
local function emitterAt(position)
	if not soundRoot or not soundRoot.Parent then
		soundRoot = create("Part", {
			Name = "CombatSFX_Local",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Transparency = 1,
			Size = Vector3.new(0.2, 0.2, 0.2),
			CFrame = CFrame.new(0, -500, 0),
			Parent = Workspace,
		})
	end
	-- soundRoot is axis-aligned, so a world position maps to a plain offset from it
	return create("Attachment", { Position = position - soundRoot.Position, Parent = soundRoot })
end

local function applyEffects(sound, layer)
	if layer.Eq then
		create("EqualizerSoundEffect", {
			LowGain = layer.Eq[1],
			MidGain = layer.Eq[2],
			HighGain = layer.Eq[3],
			Priority = 1,
			Parent = sound,
		})
	end
	if layer.Distortion then
		create("DistortionSoundEffect", { Level = layer.Distortion, Priority = 2, Parent = sound })
	end
	if layer.Reverb then
		create("ReverbSoundEffect", {
			DecayTime = 0.6 + layer.Reverb * 1.6,
			Density = 1,
			Diffusion = 1,
			DryLevel = 0,
			WetLevel = -18 + layer.Reverb * 14,
			Priority = 3,
			Parent = sound,
		})
	end
end

local function playOne(parent, id, volume, speed, opts)
	local sound = create("Sound", {
		SoundId = id,
		Volume = volume,
		PlaybackSpeed = speed,
		Looped = opts.Looped == true,
		RollOffMode = Enum.RollOffMode.InverseTapered,
		RollOffMinDistance = 12,
		RollOffMaxDistance = 160,
	})
	applyEffects(sound, opts)
	sound.Parent = parent
	if opts.Start then
		sound.TimePosition = opts.Start
	end
	sound:Play()
	if opts.Rise and opts.Length then
		TweenService:Create(sound, TweenInfo.new(opts.Length, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			PlaybackSpeed = speed * opts.Rise,
		}):Play()
	end
	if opts.Length and not opts.Looped then
		local fade = math.max(0.03, opts.Length * 0.4)
		task.delay(opts.Length - fade, function()
			if sound.Parent then
				TweenService:Create(sound, TweenInfo.new(fade, Enum.EasingStyle.Quad), { Volume = 0 }):Play()
			end
		end)
		Debris:AddItem(sound, opts.Length + 0.1)
	elseif not opts.Looped then
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		Debris:AddItem(sound, 8)
	end
	return sound
end

-- Plays a named sound at a Vector3, BasePart or Attachment.
-- opts: Volume (multiplier), Pitch (multiplier). Returns a handle with :Stop(fadeTime).
function SFX.Play(name, at, opts)
	local def = SoundIds[name]
	if not def then
		warn("[SFX] unknown sound", name)
		return nil
	end
	opts = opts or {}
	local parent, cleanupParent
	if typeof(at) == "Vector3" then
		parent = emitterAt(at)
		cleanupParent = parent
	elseif typeof(at) == "Instance" then
		parent = at
	else
		return nil
	end

	local volumeMul = opts.Volume or 1
	local pitchMul = opts.Pitch or 1
	local sounds = {}

	local usable = {}
	for _, id in ipairs(def.Ids or {}) do
		if idStatus[id] ~= false then
			table.insert(usable, id)
		end
	end

	if #usable > 0 then
		local id = usable[math.random(1, #usable)]
		table.insert(
			sounds,
			playOne(parent, id, (def.Volume or 0.6) * volumeMul, Util.randRange(def.Pitch or { 1, 1 }) * pitchMul, {
				Looped = def.Looped,
				Length = def.Length,
			})
		)
	else
		for _, layer in ipairs(def.Fallback or {}) do
			local volume = (layer.Volume or 1) * (def.Volume or 0.6) * volumeMul
			local speed = Util.randRange(layer.Pitch or { 1, 1 }) * pitchMul
			table.insert(sounds, playOne(parent, layer.Id, volume, speed, layer))
		end
	end

	if cleanupParent then
		Debris:AddItem(cleanupParent, 10)
	end

	local handle = {}
	function handle:Stop(fadeTime)
		for _, sound in ipairs(sounds) do
			if sound.Parent then
				if fadeTime and fadeTime > 0 then
					TweenService:Create(sound, TweenInfo.new(fadeTime), { Volume = 0 }):Play()
					Debris:AddItem(sound, fadeTime + 0.05)
				else
					sound:Destroy()
				end
			end
		end
	end
	function handle:SetVolume(multiplier)
		for i, sound in ipairs(sounds) do
			if sound.Parent then
				local base = sound:GetAttribute("BaseVolume") or sound.Volume
				sound:SetAttribute("BaseVolume", base)
				sounds[i].Volume = base * multiplier
			end
		end
	end
	return handle
end

return SFX
