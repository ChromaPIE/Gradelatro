local H = dofile("tests/test_helper.lua")
local Persistence = dofile("src/persistence.lua")

local saved_mod = nil
local smods = {
    save_mod_config = function(mod)
        saved_mod = mod
        return true
    end
}
local mod = { id = "Gradelatro", config = { collection = {} } }
local namespace = { mod = mod }

H.assert_equal(Persistence.save(namespace, smods), true, "save returns smods result")
H.assert_equal(saved_mod, mod, "save receives namespace mod")
H.assert_equal(Persistence.save({}, smods), false, "missing mod is not saved")
H.assert_equal(Persistence.save(namespace, {}), false, "missing save api is not saved")

print("persistence tests ok")
