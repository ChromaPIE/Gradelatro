local Persistence = {}

function Persistence.save_key(runtime)
    runtime = runtime or rawget(_G, "G")
    local profile = runtime and runtime.SETTINGS and runtime.SETTINGS.profile or 1
    return "profile_" .. tostring(profile)
end

function Persistence.activate_collection(namespace, storage, runtime)
    if not namespace or not namespace.mod then return nil end
    local config = namespace.config or namespace.mod.config or {}
    namespace.config = config
    namespace.mod.config = config
    config.saves = type(config.saves) == "table" and config.saves or {}

    local key = Persistence.save_key(runtime)
    local slot = type(config.saves[key]) == "table" and config.saves[key] or {}
    config.saves[key] = slot

    namespace.collection_migrated = nil
    if type(slot.collection) ~= "table" and type(config.collection) == "table" then
        slot.collection = config.collection
        namespace.collection_migrated = true
    end
    config.collection = nil

    if storage and type(storage.normalize) == "function" then
        slot.collection = storage.normalize(slot.collection)
    else
        slot.collection = type(slot.collection) == "table" and slot.collection or {}
    end

    namespace.save_key = key
    namespace.save_state = slot
    namespace.collection = slot.collection
    return namespace.collection
end

local function sync_collection(namespace)
    if not namespace or not namespace.mod then return end
    local config = namespace.config or namespace.mod.config
    if not config or not namespace.save_key or not namespace.collection then return end
    config.saves = type(config.saves) == "table" and config.saves or {}
    config.saves[namespace.save_key] = type(config.saves[namespace.save_key]) == "table"
        and config.saves[namespace.save_key] or {}
    config.saves[namespace.save_key].collection = namespace.collection
    namespace.save_state = config.saves[namespace.save_key]
end

function Persistence.ensure_active_collection(namespace, storage, runtime)
    if not namespace or not namespace.mod then return nil end
    local key = Persistence.save_key(runtime)
    if namespace.save_key == key and namespace.collection then
        return namespace.collection
    end
    sync_collection(namespace)
    return Persistence.activate_collection(namespace, storage, runtime)
end

function Persistence.install_profile_refresh(namespace, storage, runtime, game_class)
    runtime = runtime or rawget(_G, "G")
    game_class = game_class or rawget(_G, "Game")
    if not namespace or not game_class or type(game_class.load_profile) ~= "function" then return false end
    if namespace.profile_refresh_installed then return true end

    local original = game_class.load_profile
    game_class.load_profile = function(self, ...)
        local result = { original(self, ...) }
        Persistence.ensure_active_collection(namespace, storage, runtime)
        return unpack(result)
    end
    namespace.profile_refresh_installed = true
    return true
end

function Persistence.save(namespace, smods)
    namespace = namespace or rawget(_G, "Gradelatro")
    smods = smods or rawget(_G, "SMODS")
    if not namespace or not namespace.mod then return false end
    if not smods or type(smods.save_mod_config) ~= "function" then return false end
    if namespace.Storage then
        Persistence.ensure_active_collection(namespace, namespace.Storage)
    end
    sync_collection(namespace)
    local saved = smods.save_mod_config(namespace.mod) == true
    if saved then namespace.collection_migrated = nil end
    return saved
end

return Persistence
