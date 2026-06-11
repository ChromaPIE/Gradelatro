local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Storage = dofile("src/storage.lua")
local Carry = dofile("src/carry.lua")
local CarryUI = dofile("src/carry_ui.lua")

local config = Config.normalize({})
local mint = { centering = 9.8, print_quality = 9.8, corners = 9.8, edges = 9.8, surface = 9.8 }

local namespace = {
    config = config,
    mod = { id = "Gradelatro", config = {} },
    collection = Storage.normalize({})
}
local raw = Storage.add_raw_card(namespace.collection, {
    center_key = "j_joker",
    local_key = "joker",
    mod_id = "Balatro",
    rarity = "common",
    edition = "negative",
    condition = { centering = mint.centering, print_quality = mint.print_quality, corners = mint.corners, edges = mint.edges, surface = mint.surface },
    acquired_at = 1000
})
Carry.select_for_run(config, namespace.collection, { card_id = raw.id })

local previous_smods = rawget(_G, "SMODS")
local previous_g = rawget(_G, "G")
local save_count = 0
local spawned_args = nil
local spawned_card = nil
_G.SMODS = {
    save_mod_config = function() save_count = save_count + 1 return true end,
    add_card = function(args)
        spawned_args = args
        spawned_card = { ability = {} }
        return spawned_card
    end
}

local funcs = {}
local game_class = {}
local start_run_calls = 0
function game_class.start_run(self, args)
    start_run_calls = start_run_calls + 1
    return "started"
end
local end_round_calls = 0
local function fake_end_round()
    end_round_calls = end_round_calls + 1
    return "ended"
end

local env = { funcs = funcs, game_class = game_class, end_round = fake_end_round }
H.assert_equal(CarryUI.install(namespace, env), true, "install hooks environment")
H.assert_equal(CarryUI.install(namespace, env), true, "second install is a no-op")
H.assert_true(type(funcs.grdl_carry_activate) == "function", "activate callback registered")
H.assert_true(type(env.wrapped_end_round) == "function", "end round wrapped")

_G.G = {
    GAME = {
        pseudorandom = { seed = "RUNSEED" },
        current_round = { hands_played = 0 },
        round_resets = { ante = 1 }
    },
    STATE = 7,
    STATES = { SELECTING_HAND = 7 },
    jokers = { cards = {}, config = { card_limit = 5 } }
}

H.assert_equal(game_class.start_run({}, {}), "started", "wrapped start run calls original")
H.assert_equal(start_run_calls, 1, "original start run ran")
H.assert_equal(namespace.collection.carry.run_id, "RUNSEED", "run start binds pending carry")

local ok, ante = CarryUI.can_activate_now(namespace)
H.assert_equal(ok, true, "activation window open")
H.assert_equal(ante, 1, "current ante reported")

_G.G.STATE = 99
local blocked, reason = CarryUI.can_activate_now(namespace)
H.assert_equal(blocked, false, "wrong state blocks activation")
H.assert_equal(reason, "not_in_window", "wrong state reason")
_G.G.STATE = 7

_G.G.GAME.current_round.hands_played = 1
H.assert_equal(select(2, CarryUI.can_activate_now(namespace)), "not_in_window", "played hand closes the window")
_G.G.GAME.current_round.hands_played = 0

_G.G.jokers.cards = { {}, {}, {}, {}, {} }
H.assert_equal(select(2, CarryUI.can_activate_now(namespace)), "no_joker_slot", "full joker area blocks activation")
_G.G.jokers.cards = {}

local surface_before = raw.condition.surface
local activated = CarryUI.activate(namespace, nil, 5000)
H.assert_equal(activated.ok, true, "activation succeeds")
H.assert_equal(spawned_args.key, "j_joker", "spawn uses center key")
H.assert_equal(spawned_args.edition, "e_negative", "spawn applies edition key")
H.assert_equal(spawned_card.ability.grdl_carry_id, raw.id, "spawned joker tagged with collection id")
H.assert_true(raw.condition.surface < surface_before, "activation settles wear")
H.assert_equal(_G.G.GAME.grdl_carry_active, raw.id, "active marker stored in run save")
H.assert_equal(save_count, 1, "activation saves config")

H.assert_equal(select(2, CarryUI.can_activate_now(namespace)), "already_active", "active carry blocks reactivation")
H.assert_equal(CarryUI.activate(namespace).reason, "already_active", "double activation rejected")

_G.G.jokers.cards = { { ability = { grdl_carry_id = raw.id } } }
local removed_card = nil
_G.G.jokers.remove_card = function(self, card)
    removed_card = card
    self.cards = {}
    return card
end
H.assert_equal(env.wrapped_end_round(), "ended", "wrapped end round calls original")
H.assert_equal(end_round_calls, 1, "original end round ran")
H.assert_true(removed_card ~= nil, "carry joker pulled back at blind end")
H.assert_equal(_G.G.GAME.grdl_carry_active, nil, "active marker cleared")
H.assert_equal(raw.status, "carried", "returned card still carried")
H.assert_true(namespace.collection.carry ~= nil, "carry survives a safe return")

_G.G.GAME.round_resets.ante = 2
_G.G.GAME.grdl_carry_active = nil
local second = CarryUI.activate(namespace, nil, 6000)
H.assert_equal(second.ok, true, "next ante can activate again")
_G.G.jokers.cards = {}
env.wrapped_end_round()
H.assert_equal(raw.status, "lost", "missing joker at blind end means permanent loss")
H.assert_equal(namespace.collection.carry, nil, "carry cleared after loss")
H.assert_equal(_G.G.GAME.grdl_carry_active, nil, "active marker cleared after loss")

H.assert_equal(CarryUI.build_peek(namespace), false, "peek build is a safe no-op without ui globals")

_G.SMODS = previous_smods
_G.G = previous_g

print("carry ui tests ok")
