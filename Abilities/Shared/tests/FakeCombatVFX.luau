--!nocheck
-- Stands in for the combat effects pack in the tests: records every call (the pack has its own
-- tests in VFX/CombatVFX/tests).
local CombatVFX = { calls = { Play = {}, Swing = {} } }

function CombatVFX.Play(name, cframe, options)
	table.insert(CombatVFX.calls.Play, { name = name, cframe = cframe, options = options })
	return nil
end

function CombatVFX.Swing(kind, character, track, options)
	table.insert(CombatVFX.calls.Swing, { kind = kind, character = character, track = track, options = options })
	return { Stop = function() end }
end

return CombatVFX
