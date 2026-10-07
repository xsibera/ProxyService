--!nocheck
-- Stands in for the combat effects pack (ReplicatedStorage.CombatVFX) in the kits' tests: records
-- every call. The pack has its own tests in VFX/CombatVFX/tests.
local CombatVFX = { calls = { Play = {}, Start = {}, Swing = {} } }

function CombatVFX.Play(name, cframe, options)
	table.insert(CombatVFX.calls.Play, { name = name, cframe = cframe, options = options })
	return nil
end

function CombatVFX.Start(name, part, options)
	local call = { name = name, part = part, options = options, stopped = false }
	table.insert(CombatVFX.calls.Start, call)
	return {
		Stop = function()
			call.stopped = true
		end,
	}
end

function CombatVFX.Swing(kind, character, track, options)
	table.insert(CombatVFX.calls.Swing, { kind = kind, character = character, track = track, options = options })
	return { Stop = function() end }
end

function CombatVFX.clear()
	for _, list in pairs(CombatVFX.calls) do
		table.clear(list)
	end
end

return CombatVFX
