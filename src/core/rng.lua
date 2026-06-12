local Rng = {}

function Rng.lcg(seed)
    local state = math.floor(seed or os.time()) % 2147483647
    if state <= 0 then state = state + 2147483646 end
    return function()
        state = (state * 48271) % 2147483647
        return state / 2147483647
    end
end

function Rng.shuffle(list, rand)
    for index = #list, 2, -1 do
        local swap = math.floor(rand() * index) + 1
        list[index], list[swap] = list[swap], list[index]
    end
    return list
end

return Rng
