local Persistence = {}

function Persistence.save(namespace, smods)
    namespace = namespace or rawget(_G, "Gradelatro")
    smods = smods or rawget(_G, "SMODS")
    if not namespace or not namespace.mod then return false end
    if not smods or type(smods.save_mod_config) ~= "function" then return false end
    return smods.save_mod_config(namespace.mod) == true
end

return Persistence
