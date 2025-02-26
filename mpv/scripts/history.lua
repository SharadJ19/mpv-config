--[[
    Original Script:
    https://github.com/stax76/mpv-scripts/blob/main/history.lua

    All this script does is writing to a log file.
    I just Modified the Format of the output like below:

    It writes:
    1. The date and time:              10.09.2022 7:50 PM
    2. How many minutes were played:   3 min
    3. Completion percentage:          85%
    4. Filename without path:          Big Buck Bunny.mkv
    
    This is how a log line looks:
    10.09.2022 7:50 PM  |  3 min  |  85%  |  Big Buck Bunny.mkv
]]--

----- string
function is_empty(input)
    if input == nil or input == "" then
        return true
    end
end

function trim(input)
    if is_empty(input) then
        return ""
    end
    return input:match "^%s*(.-)%s*$"
end

function contains(input, find)
    if not is_empty(input) and not is_empty(find) then
        return input:find(find, 1, true)
    end
end

function replace(str, what, with)
    if is_empty(str) then return "" end
    if is_empty(what) then return str end
    if with == nil then with = "" end
    what = string.gsub(what, "[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1")
    with = string.gsub(with, "[%%]", "%%%%")
    return string.gsub(str, what, with)
end

function split(input, sep)
    local tbl = {}
    if not is_empty(input) then
        for str in string.gmatch(input, "([^" .. sep .. "]+)") do
            table.insert(tbl, str)
        end
    end
    return tbl
end

function pad_left(input, len, char)
    if input == nil then
        input = ""
    end
    if char == nil then
        char = ' '
    end
    return string.rep(char, len - #input) .. input
end

-- Format minutes nicely
function format_minutes(minutes)
    return string.format("%d min", minutes)
end

-- Extract filename from path
function get_filename(filepath)
    if is_empty(filepath) then return "" end
    
    -- Handle both slash types for different OS
    local filename = filepath:match("([^/\\]+)$")
    if filename then
        return filename
    else
        return filepath -- If no path separator found, return the original string
    end
end

-- Format time in 12-hour format
function format_time_12h()
    local hour = tonumber(os.date("%H"))
    local minute = os.date("%M")
    local period = "AM"
    
    if hour >= 12 then
        period = "PM"
    end
    
    if hour > 12 then
        hour = hour - 12
    elseif hour == 0 then
        hour = 12
    end
    
    return string.format("%d:%s %s", hour, minute, period)
end

----- math
function round(value)
    return value >= 0 and math.floor(value + 0.5) or math.ceil(value - 0.5)
end

----- file
function file_exists(path)
    local f = io.open(path, "r")
    if f ~= nil then
        io.close(f)
        return true
    end
    return false
end

function ensure_file_exists(path)
    if not file_exists(path) then
        local f = io.open(path, "w")
        if f ~= nil then
            f:close()
            return true
        end
        return false
    end
    return true
end

function file_append(path, content)
    local h = assert(io.open(path, "ab"))
    h:write(content)
    h:close()
end

----- mpv
local msg = require "mp.msg"

----- history
time = 0 -- number of seconds since epoch
path = ""
fullpath = ""
start_pos = 0
local o = {
    exclude = "",
    storage_path = "~~/history.txt",
    minimal_play_time = 5, -- 5 minutes
}
opt = require "mp.options"
opt.read_options(o)
o.storage_path = mp.command_native({"expand-path", o.storage_path})

function discard()
    for _, v in pairs(split(o.exclude, ";")) do
        local p = replace(fullpath, "/", "\\")
        v = replace(trim(v), "/", "\\")
        if contains(p, v) then
            return true
        end
    end
end

function calculate_percentage()
    local duration = mp.get_property_number("duration")
    local position = mp.get_property_number("time-pos")
    
    if duration and position and duration > 0 then
        return math.min(round((position / duration) * 100), 100)
    else
        return 0
    end
end

function history()
    local seconds = round(os.time() - time)
    
    -- Ensure the history file exists
    if not ensure_file_exists(o.storage_path) then
        msg.error("Could not create log file: " .. o.storage_path)
        return
    end
    
    if not is_empty(path) and seconds > o.minimal_play_time and not discard() then
        local minutes = round(seconds / 60)
        local min_str = format_minutes(minutes)
        local percentage = calculate_percentage()
        local date_str = os.date("%d.%m.%Y ")
        local time_str = format_time_12h()
        
        -- Format with pipe separators for better readability
        local line = date_str .. time_str .. "  |  " ..
            min_str .. "  |  " ..
            percentage .. "%  |  " ..
            path .. "\n"
        file_append(o.storage_path, line)
    end
    
    fullpath = mp.get_property("path")
    if contains(fullpath, "://") then
        path = mp.get_property("media-title")
    else
        path = get_filename(fullpath)
    end
    time = os.time()
    start_pos = mp.get_property_number("time-pos") or 0
end

-- Create history file if it doesn't exist on script load
if not ensure_file_exists(o.storage_path) then
    msg.error("Failed to create history file on startup: " .. o.storage_path)
else
    msg.info("History file ready: " .. o.storage_path)
end

mp.register_event("shutdown", history)
mp.register_event("file-loaded", history)