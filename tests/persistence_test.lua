local H = dofile("tests/test_helper.lua")
local Persistence = dofile("src/core/persistence.lua")
local Storage = dofile("src/core/storage.lua")

H.assert_equal(Persistence.save_key({ SETTINGS = { profile = 2 } }), "profile_2", "numeric profile save key")
H.assert_equal(Persistence.save_key({ SETTINGS = { profile = "cryptid_1" } }), "profile_cryptid_1", "string profile save key")
H.assert_equal(Persistence.save_key({}), "profile_1", "missing profile falls back to one")

local legacy_config = {
    collection = { currency_g = 77 },
    saves = {
        profile_2 = { collection = { currency_g = 222 } }
    }
}
local profile_mod = { id = "Gradelatro", config = legacy_config }
local profile_ns = { mod = profile_mod, config = legacy_config }
local profile_one = Persistence.activate_collection(profile_ns, Storage, { SETTINGS = { profile = 1 } })
H.assert_equal(profile_ns.save_key, "profile_1", "active profile key stored")
H.assert_equal(profile_one.currency_g, 77, "legacy collection migrates to active profile")
H.assert_equal(legacy_config.collection, nil, "legacy collection removed after migration")
H.assert_equal(legacy_config.saves.profile_1.collection, profile_one, "profile collection stored under save key")
H.assert_equal(profile_ns.collection_migrated, true, "legacy collection migration requests a config save")

profile_one.currency_g = 88
local profile_two_ns = { mod = profile_mod, config = legacy_config }
local profile_two = Persistence.activate_collection(profile_two_ns, Storage, { SETTINGS = { profile = 2 } })
H.assert_equal(profile_two.currency_g, 222, "second profile keeps its own collection")
H.assert_true(profile_two ~= profile_one, "profile collections are distinct tables")
H.assert_equal(profile_two_ns.collection_migrated, nil, "normal profile activation does not request migration save")

local mixed_legacy_config = {
    collection = { currency_g = 77 },
    saves = {
        profile_2 = { collection = { currency_g = 222 } }
    }
}
local mixed_ns = { mod = { id = "Gradelatro", config = mixed_legacy_config }, config = mixed_legacy_config }
Persistence.activate_collection(mixed_ns, Storage, { SETTINGS = { profile = 2 } })
H.assert_true(type(mixed_legacy_config.collection) == "table", "occupied active profile does not discard legacy collection")
H.assert_equal(mixed_legacy_config.collection.currency_g, 77, "legacy collection remains recoverable")

profile_ns.Storage = Storage
profile_ns.collection.currency_g = 99
local switched = Persistence.ensure_active_collection(profile_ns, Storage, { SETTINGS = { profile = 2 } })
H.assert_equal(legacy_config.saves.profile_1.collection.currency_g, 99, "profile switch saves previous active collection")
H.assert_equal(switched, profile_two, "profile switch reuses target profile collection")
H.assert_equal(profile_ns.save_key, "profile_2", "profile switch updates active key")

local profile_three_ns = { mod = profile_mod, config = legacy_config }
local profile_three = Persistence.activate_collection(profile_three_ns, Storage, { SETTINGS = { profile = 3 } })
H.assert_equal(profile_three.currency_g, 0, "new profile starts with empty collection")

local hook_config = {
    saves = {
        profile_1 = { collection = { currency_g = 11 } },
        profile_2 = { collection = { currency_g = 22 } }
    }
}
local hook_ns = { mod = { id = "Gradelatro", config = hook_config }, config = hook_config, Storage = Storage }
local saved_mod = nil
local smods = {
    save_mod_config = function(mod)
        saved_mod = mod
        return true
    end
}
local hook_runtime = { SETTINGS = { profile = 1 } }
local hook_game = {}
function hook_game:load_profile(profile)
    hook_runtime.SETTINGS.profile = profile
    return "loaded"
end
Persistence.activate_collection(hook_ns, Storage, hook_runtime)
H.assert_equal(Persistence.install_profile_refresh(hook_ns, Storage, hook_runtime, hook_game), true, "profile refresh hook installs on Game.load_profile")
H.assert_equal(hook_game:load_profile(2), "loaded", "profile refresh hook preserves load result")
H.assert_equal(hook_ns.save_key, "profile_2", "profile refresh hook updates save key")
H.assert_equal(hook_ns.collection.currency_g, 22, "profile refresh hook switches collection")

hook_game.load_profile = function(self, profile)
    hook_runtime.SETTINGS.profile = profile
    return "replaced"
end
H.assert_equal(Persistence.install_profile_refresh(hook_ns, Storage, hook_runtime, hook_game), true, "profile refresh hook reinstalls if replaced")
H.assert_equal(hook_game:load_profile(1), "replaced", "reinstalled hook preserves replacement result")
H.assert_equal(hook_ns.save_key, "profile_1", "reinstalled hook refreshes save key")
H.assert_equal(hook_ns.collection.currency_g, 11, "reinstalled hook switches collection")

hook_ns.pending_buyout_offer = { run_id = "RUN_A", eligible = { { id = "a" } }, blocked = {} }
Persistence.save(hook_ns, smods)
H.assert_equal(hook_config.saves.profile_1.collection.pending_buyout_offer.run_id, "RUN_A", "pending buyout offer syncs into active collection")
hook_ns.pending_buyout_offer = nil
Persistence.save(hook_ns, smods)
H.assert_equal(hook_config.saves.profile_1.collection.pending_buyout_offer, nil, "cleared pending buyout offer syncs into active collection")

local mod = { id = "Gradelatro", config = { collection = {} } }
local namespace = { mod = mod }

H.assert_equal(Persistence.save(namespace, smods), true, "save returns smods result")
H.assert_equal(saved_mod, mod, "save receives namespace mod")
local nil_return_saved = nil
local nil_return_smods = {
    save_mod_config = function(mod_arg)
        nil_return_saved = mod_arg
    end
}
H.assert_equal(Persistence.save(namespace, nil_return_smods), true, "save accepts nil-returning save api")
H.assert_equal(nil_return_saved, mod, "nil-returning save api still receives mod")
saved_mod = nil
local previous_g = rawget(_G, "G")
_G.G = { SETTINGS = { profile = 2 } }
profile_ns.collection.currency_g = 233
H.assert_equal(Persistence.save(profile_ns, smods), true, "profile save returns smods result")
H.assert_equal(saved_mod.config.saves.profile_2.collection.currency_g, 233, "profile save stores active collection under save key")
_G.G = previous_g
H.assert_equal(Persistence.save({}, smods), false, "missing mod is not saved")
H.assert_equal(Persistence.save(namespace, {}), false, "missing save api is not saved")

print("persistence tests ok")
