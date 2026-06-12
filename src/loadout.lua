local Loadout = {}

function Loadout.run_identity(game_state)
    game_state = game_state or {}
    if game_state.run_id then return tostring(game_state.run_id) end
    if game_state.pseudorandom and game_state.pseudorandom.seed then
        return tostring(game_state.pseudorandom.seed)
    end
    if game_state.seed then return tostring(game_state.seed) end
    return "unknown"
end

return Loadout
