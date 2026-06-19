local H = dofile("tests/test_helper.lua")
local Config = dofile("src/core/config.lua")
local Storage = dofile("src/core/storage.lua")
local Settlement = dofile("src/domain/settlement.lua")

local config = Config.normalize({})
local state = Storage.normalize({ currency_g = 10 })

local first = Settlement.apply(config, state, {
    run_id = "RUNSEED",
    run_started_at = 1767225600,
    gate = "red",
    stake_level = 2,
    won = true,
    dollars = 100,
    settled_at = 1800000000
})

H.assert_equal(first.ok, true, "first settlement succeeds")
H.assert_equal(first.duplicate, false, "first settlement not duplicate")
H.assert_equal(first.amount, 50, "red settlement amount")
H.assert_equal(state.currency_g, 60, "settlement adds currency")
H.assert_true(state.settlements[first.key] ~= nil, "settlement ledger entry stored")
H.assert_equal(state.settlements[first.key].run_id, "RUNSEED", "ledger run id")
H.assert_equal(state.settlements[first.key].stake_level, 2, "ledger stake level")
H.assert_equal(state.settlements[first.key].fixed_reward, 31, "ledger fixed reward")
H.assert_equal(state.settlements[first.key].cash_cap, 19, "ledger cash cap")
H.assert_equal(state.settlements[first.key].cash_component, 19, "ledger cash component")
H.assert_equal(state.settlements[first.key].settled_at, 1800000000, "ledger settled time")

local duplicate = Settlement.apply(config, state, {
    run_id = "RUNSEED",
    run_started_at = 1767225600,
    gate = "red",
    stake_level = 2,
    won = true,
    dollars = 100,
    settled_at = 1800000001
})

H.assert_equal(duplicate.ok, true, "duplicate settlement is non-fatal")
H.assert_equal(duplicate.duplicate, true, "duplicate flagged")
H.assert_equal(duplicate.amount, 0, "duplicate grants no currency")
H.assert_equal(state.currency_g, 60, "duplicate keeps currency")

local loss_state = Storage.normalize({ currency_g = 0 })
local loss = Settlement.apply(config, loss_state, {
    run_id = "LOSS",
    run_started_at = 1767225601,
    gate = "blue",
    won = false,
    dollars = 500
})

H.assert_equal(loss.amount, 20, "loss settlement respects cap")
H.assert_equal(loss_state.currency_g, 20, "loss settlement adds capped currency")

print("settlement tests ok")
