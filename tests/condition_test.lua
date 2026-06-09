local H = dofile("tests/test_helper.lua")
local Condition = dofile("src/condition.lua")

local perfect = {
    centering = 9.8,
    print_quality = 9.8,
    corners = 9.8,
    edges = 9.8,
    surface = 9.8
}

local near_mint = {
    centering = 9.4,
    print_quality = 9.2,
    corners = 9.1,
    edges = 9.0,
    surface = 9.2
}

local damaged_surface = {
    centering = 9.8,
    print_quality = 9.8,
    corners = 9.8,
    edges = 9.8,
    surface = 7.0
}

local short_corner = {
    centering = 10.0,
    print_quality = 10.0,
    corners = 9.0,
    edges = 10.0,
    surface = 10.0
}

H.assert_equal(Condition.grade(perfect), 10, "perfect grade")
H.assert_equal(Condition.grade(near_mint), 9, "near mint grade")
H.assert_equal(Condition.grade(damaged_surface), 7, "surface cap")
H.assert_equal(Condition.grade(short_corner), 9, "short corner blocks gem mint")

local worn = Condition.apply_wear(perfect, "polychrome", 0.50)
H.assert_true(worn.surface < perfect.surface, "wear lowers surface")
H.assert_equal(worn.centering, perfect.centering, "wear does not alter centering")
H.assert_equal(worn.print_quality, perfect.print_quality, "wear does not alter print quality")

local generated = Condition.generate(12345, "negative")
H.assert_true(generated.centering >= 6.0 and generated.centering <= 10.0, "generated centering range")
H.assert_true(generated.surface >= 6.0 and generated.surface <= 10.0, "generated surface range")

H.assert_near(Condition.grade_multiplier(10), 6.0, 0.000001, "grade 10 multiplier")
H.assert_near(Condition.grade_multiplier(8), 1.2, 0.000001, "grade 8 multiplier")

print("condition tests ok")
