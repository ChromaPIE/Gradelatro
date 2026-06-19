local H = dofile("tests/test_helper.lua")
local Config = dofile("src/core/config.lua")
local Storage = dofile("src/core/storage.lua")
local RunEnd = dofile("src/domain/run_end.lua")
local rng = H.install_pseudorandom_stub()

local config = Config.normalize({})

local function joker_card(id, center_key, edition)
    return {
        ID = id,
        config = { center = { key = center_key, set = "Joker" } },
        ability = { set = "Joker" },
        edition = edition
    }
end

local snapshots = RunEnd.collect_joker_snapshots({
    cards = {
        joker_card(11, "j_common", { key = "e_negative" }),
        {
            ID = 12,
            config = { center = { key = "c_fool", set = "Tarot" } },
            ability = { set = "Tarot" }
        },
        {
            sort_id = 13,
            config = { center_key = "j_fallback" },
            ability = { set = "Joker" },
            edition = { holo = true }
        }
    }
})

H.assert_equal(#snapshots, 2, "only jokers snapshotted")
H.assert_equal(snapshots[1].id, "11", "card ID normalized")
H.assert_equal(snapshots[1].center_key, "j_common", "center key extracted")
H.assert_equal(snapshots[1].edition.key, "e_negative", "edition preserved")
H.assert_equal(snapshots[2].id, "13", "sort id fallback")
H.assert_equal(snapshots[2].center_key, "j_fallback", "center_key fallback")

local anchors = RunEnd.stake_anchors({
    stake_red = { stake_level = 3 },
    stake_blue = { stake_level = 6 },
    stake_gold = { stake_level = 9 }
})
H.assert_equal(anchors.stake_red, 3, "red anchor from runtime")
H.assert_equal(anchors.stake_blue, 6, "blue anchor from runtime")
H.assert_equal(anchors.stake_gold, 9, "gold anchor from runtime")

local game_state = {}
H.assert_equal(RunEnd.ensure_run_started_at(game_state, 1700000000), 1700000000, "start time assigned")
H.assert_equal(RunEnd.ensure_run_started_at(game_state, 1800000000), 1700000000, "start time preserved")
H.assert_equal(RunEnd.year_from_timestamp(1767225600), 2026, "year from timestamp")

local namespace = {
    config = config,
    collection = Storage.normalize({ currency_g = 1000 }),
    mod = { id = "Gradelatro", config = {} }
}
local previous_smods_global = rawget(_G, "SMODS")
local save_count = 0
_G.SMODS = {
    load_file = previous_smods_global.load_file,
    save_mod_config = function(mod)
        H.assert_equal(mod, namespace.mod, "run end saves namespace mod")
        save_count = save_count + 1
        return true
    end
}

local runtime = {
    GAME = {
        stake = 2,
        dollars = 100,
        pseudorandom = { seed = "RUNSEED" },
        grdl_run_started_at = 1767225600
    },
    P_CENTERS = {
        j_common = { key = "j_common", original_key = "common_joker", set = "Joker", rarity = 1, name = "Common", order = 1 },
        j_rare = { key = "j_rare", original_key = "rare_joker", set = "Joker", rarity = 3, name = "Rare", order = 2 },
        c_fool = { key = "c_fool", set = "Tarot", rarity = 1 }
    },
    P_STAKES = {
        stake_red = { stake_level = 2 },
        stake_blue = { stake_level = 5 },
        stake_gold = { stake_level = 8 }
    },
    jokers = {
        cards = {
            joker_card(21, "j_common"),
            joker_card(22, "j_rare")
        }
    }
}
local smods = {
    Mods = {
        Balatro = { id = "Balatro", name = "BALATRO" }
    }
}

local offer = RunEnd.capture_win_buyout_offer(namespace, runtime, smods, 1800000000)

H.assert_equal(namespace.pending_buyout_offer, offer, "offer stored on namespace")
H.assert_equal(namespace.collection.pending_buyout_offer, offer, "offer persisted on collection")
H.assert_equal(namespace.collection.currency_g, 1050, "win settlement added before buyout")
H.assert_equal(namespace.last_settlement_result.amount, 50, "settlement result stored")
H.assert_equal(namespace.last_settlement_result.duplicate, false, "first settlement not duplicate")
H.assert_equal(save_count, 1, "first settlement saved")
H.assert_equal(offer.run_id, "RUNSEED", "run id from seed")
H.assert_equal(offer.run_started_at, 1767225600, "run start timestamp kept")
H.assert_equal(offer.acquired_year, 2026, "acquired year from run start")
H.assert_equal(offer.gate, "red", "gate derived from runtime stake")
H.assert_equal(#offer.eligible, 1, "red gate eligible count")
H.assert_equal(offer.eligible[1].center_key, "j_common", "common eligible")
H.assert_equal(namespace.collection.market.last_refresh, 1800000000, "win capture refreshes market heat")
H.assert_true(offer.eligible[1].rav >= 35 * 0.75 and offer.eligible[1].rav <= 35 * 1.35, "offer prices through the heat band")
H.assert_true(namespace.collection.market.black_market ~= nil, "win capture generates black market offers")
H.assert_true(rng.has_call("pseudorandom", "grdl_market_"), "run end market refresh uses native pseudorandom")
H.assert_true(rng.has_call("pseudorandom", "grdl_black_market_"), "run end black market uses native pseudorandom")
H.assert_equal(#namespace.collection.market.black_market.offers, 3, "three black market offers")
H.assert_equal(namespace.collection.market.black_market.run_id, "RUNSEED", "black market bound to the run")
H.assert_equal(#offer.blocked, 1, "rare blocked")
H.assert_equal(offer.blocked[1].reason, "rarity_locked", "blocked reason code")

local duplicate_offer = RunEnd.capture_win_buyout_offer(namespace, runtime, smods, 1800000001)
H.assert_equal(namespace.collection.currency_g, 1050, "duplicate capture does not add currency")
H.assert_equal(namespace.last_settlement_result.duplicate, true, "duplicate settlement flagged")
H.assert_equal(duplicate_offer.run_id, "RUNSEED", "duplicate capture still refreshes offer")
H.assert_equal(namespace.collection.pending_buyout_offer, duplicate_offer, "duplicate capture persists refreshed offer")
H.assert_equal(save_count, 2, "duplicate offer refresh is saved")

local disabled_namespace = {
    config = config,
    collection = Storage.normalize({ currency_g = 1 }),
    mod = { id = "Gradelatro", config = {} }
}
local disabled_runtime = {
    GAME = {
        stake = 8,
        dollars = 1000,
        pseudorandom = { seed = "DISABLED" },
        grdl_run_started_at = 1767225600,
        grdl_entry = { enabled = false, paid = false, fee = 83, balance = 1 }
    },
    P_STAKES = runtime.P_STAKES,
    P_CENTERS = runtime.P_CENTERS,
    jokers = runtime.jokers
}
local disabled_offer = RunEnd.capture_win_buyout_offer(disabled_namespace, disabled_runtime, smods, 1800000002)
H.assert_equal(disabled_offer, nil, "unpaid entry disables buyout offer")
H.assert_equal(disabled_namespace.pending_buyout_offer, nil, "unpaid entry stores no offer")
H.assert_equal(disabled_namespace.collection.pending_buyout_offer, nil, "unpaid entry clears persisted offer")
H.assert_equal(disabled_namespace.last_settlement_result, nil, "unpaid entry skips settlement")
H.assert_equal(disabled_namespace.collection.currency_g, 1, "unpaid entry grants no currency")
H.assert_equal(disabled_namespace.collection.market.black_market, nil, "unpaid entry skips black market")
_G.SMODS = previous_smods_global

rng.restore()
print("run end tests ok")
