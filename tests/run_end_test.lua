local H = dofile("tests/test_helper.lua")
local Config = dofile("src/config.lua")
local Storage = dofile("src/storage.lua")
local RunEnd = dofile("src/run_end.lua")

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
    collection = Storage.normalize({ currency_g = 1000 })
}

local runtime = {
    GAME = {
        stake = 2,
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
H.assert_equal(offer.run_id, "RUNSEED", "run id from seed")
H.assert_equal(offer.run_started_at, 1767225600, "run start timestamp kept")
H.assert_equal(offer.acquired_year, 2026, "acquired year from run start")
H.assert_equal(offer.gate, "red", "gate derived from runtime stake")
H.assert_equal(#offer.eligible, 1, "red gate eligible count")
H.assert_equal(offer.eligible[1].center_key, "j_common", "common eligible")
H.assert_equal(#offer.blocked, 1, "rare blocked")
H.assert_equal(offer.blocked[1].reason, "rarity_locked", "blocked reason code")

print("run end tests ok")
