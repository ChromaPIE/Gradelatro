local Bootstrap = {}

function Bootstrap.init(mod)
    local Gradelatro = rawget(_G, "Gradelatro") or {}
    Gradelatro.mod = mod
    Gradelatro.path = mod and mod.path or "."
    Gradelatro.version = mod and mod.version or "0.1.0"
    Gradelatro.modules = Gradelatro.modules or {}
    _G.Gradelatro = Gradelatro
    return Gradelatro
end

function Bootstrap.attach(namespace, name, module)
    namespace.modules[name] = module
    namespace[name] = module
    return module
end

return Bootstrap
