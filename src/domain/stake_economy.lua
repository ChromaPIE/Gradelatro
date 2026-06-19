local StakeEconomy = {}

local function load_src(path)
    return assert(SMODS.load_file("src/" .. path))()
end

local Storage = load_src("core/storage.lua")

local function floor_number(value, fallback)
    local number = tonumber(value)
    if not number then return fallback end
    return math.max(1, math.floor(number))
end

local function run_identity(game_state)
    game_state = game_state or {}
    if game_state.run_id then return tostring(game_state.run_id) end
    if game_state.pseudorandom and game_state.pseudorandom.seed then
        return tostring(game_state.pseudorandom.seed)
    end
    if game_state.seed then return tostring(game_state.seed) end
    return "unknown"
end

function StakeEconomy.round(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

function StakeEconomy.entry_fee(level)
    level = floor_number(level, 1)
    if level < 3 then return 0 end
    return StakeEconomy.round(10 * math.pow(level - 2, 1.18))
end

function StakeEconomy.core_net_g(level)
    level = floor_number(level, 1)
    return StakeEconomy.round(20 + 110 * (math.pow(level, 1.35) - 1) / (math.pow(8, 1.35) - 1))
end

function StakeEconomy.cash_cap(level)
    level = floor_number(level, 1)
    return StakeEconomy.round(15 + 30 * (math.pow(level, 1.15) - 1) / (math.pow(8, 1.15) - 1))
end

function StakeEconomy.fixed_reward(level)
    return StakeEconomy.entry_fee(level) + StakeEconomy.core_net_g(level)
end

function StakeEconomy.win_quote(level, dollars)
    level = floor_number(level, 1)
    dollars = math.max(0, math.floor(tonumber(dollars) or 0))
    local fee = StakeEconomy.entry_fee(level)
    local fixed = StakeEconomy.fixed_reward(level)
    local cap = StakeEconomy.cash_cap(level)
    local cash_component = math.min(math.floor(0.25 * dollars), cap)
    return {
        stake_level = level,
        entry_fee = fee,
        fixed_reward = fixed,
        cash_cap = cap,
        cash_component = cash_component,
        gross = fixed + cash_component,
        net = StakeEconomy.core_net_g(level) + cash_component
    }
end

function StakeEconomy.stake_key_from_index(runtime, index)
    local pools = runtime and runtime.P_CENTER_POOLS
    local stake_pool = pools and pools.Stake or nil
    local stake = stake_pool and stake_pool[index] or nil
    return stake and stake.key or nil
end

function StakeEconomy.stake_count(runtime)
    runtime = runtime or rawget(_G, "G")
    local pools = runtime and runtime.P_CENTER_POOLS
    local stake_pool = pools and pools.Stake or nil
    if type(stake_pool) == "table" then return #stake_pool end
    local count = 0
    for _, _ in pairs((runtime and runtime.P_STAKES) or {}) do
        count = count + 1
    end
    return count
end

function StakeEconomy.stake_level_for_run(runtime)
    runtime = runtime or rawget(_G, "G")
    local game = runtime and runtime.GAME or nil
    local stake_index = floor_number(game and game.stake, 1)
    local stake_key = StakeEconomy.stake_key_from_index(runtime, stake_index)
    local stake = stake_key and runtime and runtime.P_STAKES and runtime.P_STAKES[stake_key] or nil
    return floor_number(stake and (stake.stake_level or stake.order), stake_index)
end

function StakeEconomy.run_key(runtime, now)
    local game = runtime and runtime.GAME or {}
    game.grdl_run_started_at = game.grdl_run_started_at or now or os.time()
    return tostring(run_identity(game)) .. ":" .. tostring(game.grdl_run_started_at)
end

function StakeEconomy.ensure_entry_state(config, collection, runtime, now)
    runtime = runtime or rawget(_G, "G")
    local game = runtime and runtime.GAME or nil
    if not game or not collection then return nil end

    local key = StakeEconomy.run_key(runtime, now)
    local existing = game.grdl_entry
    if existing and existing.run_key == key then return existing end

    collection.entry_fees = type(collection.entry_fees) == "table" and collection.entry_fees or {}
    local stake_index = floor_number(game.stake, 1)
    local stake_key = StakeEconomy.stake_key_from_index(runtime, stake_index)
    local level = StakeEconomy.stake_level_for_run(runtime)
    local fee = StakeEconomy.entry_fee(level)
    local balance = math.max(0, math.floor(collection.currency_g or 0))
    local ledger = collection.entry_fees[key]
    local paid = fee == 0 or ledger ~= nil
    local charged = false

    if not paid and balance >= fee and Storage.spend_currency(collection, fee) then
        paid = true
        charged = true
        ledger = {
            run_key = key,
            run_id = run_identity(game),
            run_started_at = game.grdl_run_started_at,
            stake_index = stake_index,
            stake_key = stake_key,
            stake_level = level,
            fee = fee,
            paid_at = now or os.time()
        }
        collection.entry_fees[key] = ledger
    end

    local state = {
        run_key = key,
        run_id = run_identity(game),
        run_started_at = game.grdl_run_started_at,
        stake_index = stake_index,
        stake_key = stake_key,
        stake_level = level,
        fee = fee,
        balance = balance,
        paid = paid,
        enabled = paid,
        charged = charged
    }
    game.grdl_entry = state
    return state
end

function StakeEconomy.run_enabled(runtime)
    runtime = runtime or rawget(_G, "G")
    local state = runtime and runtime.GAME and runtime.GAME.grdl_entry or nil
    return not state or state.enabled == true
end

return StakeEconomy
