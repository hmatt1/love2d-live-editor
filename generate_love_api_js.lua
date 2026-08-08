local api = require('love-api.love_api')

local function escape_str(s)
    if not s then return "" end
    s = s:gsub('\\', '\\\\')
    s = s:gsub('"', '\\"')
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    s = s:gsub('\t', '\\t')
    return s
end

local function to_json(val)
    local t = type(val)
    if t == "string" then
        return '"' .. escape_str(val) .. '"'
    elseif t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "table" then
        local is_array = false
        if #val > 0 then is_array = true end
        
        -- Special check for empty tables that should be arrays
        if next(val) == nil then
            return "[]"
        end

        -- Verify if it's really an array (keys are sequential integers starting from 1)
        local count = 0
        for _ in pairs(val) do count = count + 1 end
        if count == #val then is_array = true else is_array = false end

        local res = {}
        if is_array then
            for i=1, #val do
                table.insert(res, to_json(val[i]))
            end
            return "[" .. table.concat(res, ",") .. "]"
        else
            for k, v in pairs(val) do
                if type(k) == "string" then
                    table.insert(res, '"' .. escape_str(k) .. '":' .. to_json(v))
                end
            end
            return "{" .. table.concat(res, ",") .. "}"
        end
    elseif t == "nil" then
        return "null"
    end
    return "null"
end

local out = io.open("love_api.js", "w")
out:write("window.LOVE_API = " .. to_json(api) .. ";\n")
out:close()

print("Successfully generated love_api.js")
