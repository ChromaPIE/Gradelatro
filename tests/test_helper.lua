local Helper = {}

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

return Helper
