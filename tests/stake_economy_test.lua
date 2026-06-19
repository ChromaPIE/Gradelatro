local H = dofile("tests/test_helper.lua")
local Config = dofile("src/core/config.lua")
local Storage = dofile("src/core/storage.lua")
local StakeEconomy = dofile("src/domain/stake_economy.lua")

local config = Config.normalize({})

H.assert_equal(StakeEconomy.entry_fee(1), 0, "white fee")
H.assert_equal(StakeEconomy.entry_fee(2), 0, "red fee")
H.assert_equal(StakeEconomy.entry_fee(3), 10, "green fee")
H.assert_equal(StakeEconomy.entry_fee(8), 83, "gold fee")
H.assert_equal(StakeEconomy.entry_fee(32), 553, "ascendant fee")

H.assert_equal(StakeEconomy.core_net_g(1), 20, "white net")
H.assert_equal(StakeEconomy.core_net_g(8), 130, "gold net")
H.assert_equal(StakeEconomy.core_net_g(32), 774, "ascendant net")
H.assert_equal(StakeEconomy.fixed_reward(8), 213, "gold fixed")
H.assert_equal(StakeEconomy.cash_cap(8), 45, "gold cap")

local quote = StakeEconomy.win_quote(8, 1000)
H.assert_equal(quote.entry_fee, 83, "quote fee")
H.assert_equal(quote.fixed_reward, 213, "quote fixed")
H.assert_equal(quote.cash_cap, 45, "quote cap")
H.assert_equal(quote.cash_component, 45, "quote capped cash")
H.assert_equal(quote.gross, 258, "quote gross")
H.assert_equal(quote.net, 175, "quote max net")

local runtime = {
    GAME = { stake = 2, pseudorandom = { seed = "STAKE-RUN" }, grdl_run_started_at = 1700000000 },
    P_CENTER_POOLS = {
        Stake = {
            { key = "stake_white" },
            { key = "stake_branch" }
        }
    },
    P_STAKES = {
        stake_white = { stake_level = 1 },
        stake_branch = { stake_level = 9 }
    }
}
H.assert_equal(StakeEconomy.stake_key_from_index(runtime, 2), "stake_branch", "stake key from pool")
H.assert_equal(StakeEconomy.stake_count(runtime), 2, "stake count from pool")
H.assert_equal(StakeEconomy.stake_level_for_run(runtime), 9, "stake level from center pool key")
H.assert_equal(StakeEconomy.stake_count({ P_STAKES = { a = {}, b = {}, c = {} } }), 3, "stake count fallback")
H.assert_equal(StakeEconomy.stake_level_for_run({ GAME = { stake = 7 } }), 7, "stake fallback to game stake")

local paid_collection = Storage.normalize({ currency_g = 200 })
local paid = StakeEconomy.ensure_entry_state(config, paid_collection, runtime, 1800000000)
H.assert_equal(paid.paid, true, "entry fee paid")
H.assert_equal(paid.enabled, true, "paid run enabled")
H.assert_equal(paid.fee, 99, "branch fee by effective level")
H.assert_equal(paid_collection.currency_g, 101, "fee deducted once")
local paid_again = StakeEconomy.ensure_entry_state(config, paid_collection, runtime, 1800000001)
H.assert_equal(paid_again.paid, true, "paid state reused")
H.assert_equal(paid_collection.currency_g, 101, "fee not double charged")

local poor_runtime = {
    GAME = { stake = 8, pseudorandom = { seed = "POOR-RUN" }, grdl_run_started_at = 1700000000 },
    P_STAKES = { stake_gold = { stake_level = 8 } }
}
local poor_collection = Storage.normalize({ currency_g = 42 })
local poor = StakeEconomy.ensure_entry_state(config, poor_collection, poor_runtime, 1800000000)
H.assert_equal(poor.paid, false, "insufficient fee unpaid")
H.assert_equal(poor.enabled, false, "insufficient fee disables run features")
H.assert_equal(poor.fee, 83, "gold fee required")
H.assert_equal(poor.balance, 42, "balance recorded")
H.assert_equal(poor_collection.currency_g, 42, "insufficient fee not deducted")

local free_runtime = { GAME = { stake = 2, run_id = "FREE", grdl_run_started_at = 1700000000 } }
local free_collection = Storage.normalize({ currency_g = 0 })
local free = StakeEconomy.ensure_entry_state(config, free_collection, free_runtime, 1800000000)
H.assert_equal(free.paid, true, "free stake treated as paid")
H.assert_equal(free.enabled, true, "free stake enabled")
H.assert_equal(free.fee, 0, "free stake fee")

print("stake economy tests ok")
