local TextInput = {}

local function normalize_newlines(text)
    return tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
end

function TextInput.normalize(text)
    return normalize_newlines(text)
end

function TextInput.split_lines(text, max_lines)
    local normalized = normalize_newlines(text)
    local lines = {}
    for line in (normalized .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
        if max_lines and #lines >= max_lines then break end
    end
    if #lines == 0 then lines[1] = "" end
    return lines
end

function TextInput.apply_paste(state, provider)
    if type(state) ~= "table" then return { ok = false, reason = "missing_state" } end
    local text
    if provider then
        text = provider()
    else
        local love_obj = rawget(_G, "love")
        if love_obj and love_obj.system and love_obj.system.getClipboardText then
            local ok, value = pcall(love_obj.system.getClipboardText)
            if ok then text = value end
        end
        local runtime = rawget(_G, "G")
        if (text == nil or text == "") and runtime and runtime.F_LOCAL_CLIPBOARD then
            text = runtime.CLIPBOARD
        end
    end
    if text == nil or text == "" then return { ok = false, reason = "empty_clipboard" } end
    state.text = normalize_newlines(text)
    return { ok = true }
end

function TextInput.clear(state)
    if type(state) == "table" then state.text = "" end
end

function TextInput.accept_textinput(state, text)
    if type(state) ~= "table" then return { ok = false, reason = "missing_state" } end
    if text == nil or text == "" then return { ok = false, reason = "empty_text" } end
    state.text = normalize_newlines((state.text or "") .. tostring(text))
    return { ok = true }
end

return TextInput
