-- Fist combat server entry point.
-- Modules: CombatService (rules + networking), CharacterSetup (players, R6), DummyAI (dummies).

local CombatService = require(script.CombatService)
local CharacterSetup = require(script.CharacterSetup)
local DummyAI = require(script.DummyAI)

CombatService.Start()
CharacterSetup.Start()
DummyAI.Start()
