local H = dofile("tests/test_helper.lua")
local Label = dofile("src/domain/label.lua")

local lines = Label.slab_lines({
    year = 2026,
    mod_name = "Monarchy",
    local_key = "air_freshener",
    series_index = 1,
    edition = "negative",
    grade = 10,
    cert_number = 1
})

H.assert_equal(lines[1].left, "2026 MONARCHY", "line 1 left")
H.assert_equal(lines[1].right, "#001", "line 1 right")
H.assert_equal(lines[2].left, "AIR FRESHENER", "line 2 left")
H.assert_equal(lines[2].right, "GEM MT", "line 2 right")
H.assert_equal(lines[3].left, "NEGATIVE", "line 3 left")
H.assert_equal(lines[3].right, "10", "line 3 right")
H.assert_equal(lines[4].left, "", "line 4 left")
H.assert_equal(lines[4].right, "000001", "line 4 right")

local lower_grade = Label.slab_lines({
    year = 2027,
    mod_name = "Cryptid",
    local_key = "very_strange_key",
    series_index = 12,
    edition = "polychrome",
    grade = 4,
    cert_number = "000123"
})

H.assert_equal(lower_grade[1].right, "#012", "padded series index")
H.assert_equal(lower_grade[2].left, "VERY STRANGE KEY", "key upper spacing")
H.assert_equal(lower_grade[2].right, "VG-EX", "grade 4 descriptor")
H.assert_equal(lower_grade[3].left, "POLYCHROME", "edition descriptor")
H.assert_equal(lower_grade[4].right, "000123", "string cert preserved")

local localized = Label.slab_lines({
    local_key = "joker",
    edition = "negative",
    grade = 10,
    text = {
        grade_text = { [10] = "宝石完美" },
        edition_text = { negative = "负片" }
    }
})

H.assert_equal(localized[2].right, "宝石完美", "localized grade descriptor")
H.assert_equal(localized[3].left, "负片", "localized edition descriptor")

H.assert_equal(Label.grade_full(10), "10 - Gem Mint", "grade ten full name")
H.assert_equal(Label.grade_full(9), "9 - Mint", "grade nine full name")
H.assert_equal(Label.grade_full(8), "8 - Near Mint-Mint", "grade eight full name")
H.assert_equal(Label.grade_full(7), "7 - Near Mint", "grade seven full name")
H.assert_equal(Label.grade_full(6), "6 - Excellent-Mint", "grade six full name")
H.assert_equal(Label.grade_full(5), "5 - Excellent", "grade five full name")
H.assert_equal(Label.grade_full(4), "4 - Very Good-Excellent", "grade four full name")
H.assert_equal(Label.grade_full(3), "3 - Very Good", "grade three full name")
H.assert_equal(Label.grade_full(2), "2 - Good", "grade two full name")
H.assert_equal(Label.grade_full(1), "1 - Poor", "grade one full name")
H.assert_equal(Label.grade_full(nil), "AUTH", "missing grade falls back to authentic")

print("label tests ok")
