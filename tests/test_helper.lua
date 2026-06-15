local Helper = {}

local smods = rawget(_G, "SMODS")
if type(smods) ~= "table" then
    smods = {}
    _G.SMODS = smods
end
if type(smods.load_file) ~= "function" then
    smods.load_file = function(path)
        return assert(loadfile(path))
    end
end

function Helper.assert_equal(actual, expected, label)
    if actual ~= expected then
        error((label or "assert_equal") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function Helper.assert_true(value, label)
    if not value then
        error((label or "assert_true") .. ": expected truthy value", 2)
    end
end

function Helper.assert_near(actual, expected, epsilon, label)
    epsilon = epsilon or 0.000001
    if math.abs(actual - expected) > epsilon then
        error((label or "assert_near") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function Helper.install_pseudorandom_stub()
    local previous_pseudorandom = rawget(_G, "pseudorandom")
    local previous_pseudoshuffle = rawget(_G, "pseudoshuffle")
    local states = {}
    local calls = {}

    local function initial_state(seed)
        local text = tostring(seed or "nil")
        local state = 0
        for index = 1, #text do
            state = (state * 131 + text:byte(index)) % 1000003
        end
        return state / 1000003
    end

    local function next_value(seed)
        local key = tostring(seed or "nil")
        local state = states[key]
        if state == nil then state = initial_state(key) end
        state = (state * 1.61803398875 + 0.27182818284) % 1
        states[key] = state
        return state
    end

    _G.pseudorandom = function(seed, min_value, max_value)
        calls[#calls + 1] = { kind = "pseudorandom", seed = seed, min = min_value, max = max_value }
        local value = next_value(seed)
        if min_value and max_value then
            return math.floor(value * (max_value - min_value + 1)) + min_value
        end
        return value
    end

    _G.pseudoshuffle = function(list, seed)
        calls[#calls + 1] = { kind = "pseudoshuffle", seed = seed }
        local shuffle_seed = tostring(seed or "nil") .. ":shuffle"
        for index = #list, 2, -1 do
            local swap = math.floor(next_value(shuffle_seed) * index) + 1
            list[index], list[swap] = list[swap], list[index]
        end
    end

    local control = { calls = calls }

    function control.reset()
        states = {}
        for index = #calls, 1, -1 do
            calls[index] = nil
        end
    end

    function control.restore()
        _G.pseudorandom = previous_pseudorandom
        _G.pseudoshuffle = previous_pseudoshuffle
    end

    function control.has_call(kind, seed_prefix)
        for _, call in ipairs(calls) do
            if call.kind == kind and tostring(call.seed):sub(1, #seed_prefix) == seed_prefix then
                return true
            end
        end
        return false
    end

    return control
end

return Helper
