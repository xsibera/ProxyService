--!strict
--[[
	CombatVFX: the parry, block and guard-break effects (script.Effects, script.Sounds), played with
	the shared EffectPlayer (see EffectPlayer for Play / Attach / Sound).
]]

local EffectPlayer = require(script:WaitForChild("EffectPlayer")) :: any

return EffectPlayer.new(script:WaitForChild("Effects"), script:WaitForChild("Sounds"), "CombatVFX")
