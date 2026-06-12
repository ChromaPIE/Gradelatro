local H = dofile("tests/test_helper.lua")
local Loadout = dofile("src/loadout.lua")

H.assert_equal(Loadout.run_identity({ pseudorandom = { seed = "ABC" } }), "ABC", "run identity from seed")
H.assert_equal(Loadout.run_identity({}), "unknown", "run identity fallback")

print("loadout tests ok")
