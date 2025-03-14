--[[
    Modified mpv history script
    Tracks watched media and logs:
    1. Date and time:                 14.03.2025 10:43 AM
    2. Minutes played:                23 min
    3. Completion percentage:         98%
    4. Filename:                      Big Buck Bunny.mkv
    
    Output format:
    14.03.2025 10:43 AM  |  23 min  |  98%  |  Big Buck Bunny.mkv
]]--

local mp = require 'mp'
local msg = require 'mp.msg'
local options = require 'mp.options'

-- Configuration
local o = {
    exclude = "",
    storage_path = "~~/history.txt",
    minimal_play_time = 120, -- minimum watch time to log in seconds
}

options.read_options(o)
o.storage_path = mp.command_native({"expand-path", o.storage_path})

-- State variables
local watch_data = {
    start_time = 0,     -- System time when playback started
    path = "",          -- File path
    filename = "",      -- Filename without path
    duration = 0,       -- Duration of the media in seconds
    start_pos = 0,      -- Position when playback started
    last_pos = 0,       -- Last known position
    is_playing = false  -- Whether playback is currently active
}

-- Utility functions
function trim(s)
    return s:match"^%s*(.-)%s*$"
end

function contains(str, substr)
    if str == nil or substr == nil then return false end
    return str:find(substr, 1, true) ~= nil
end

function get_filename(filepath)
    if not filepath then return "" end
    
    local filename = filepath:match("([^/\\]+)$")
    return filename or filepath
end

function format_time_12h()
    local hour = tonumber(os.date("%H"))
    local minute = os.date("%M")
    local period = "AM"
    
    if hour >= 12 then period = "PM" end
    if hour > 12 then hour = hour - 12
    elseif hour == 0 then hour = 12 end
    
    return string.format("%d:%s %s", hour, minute, period)
end

function round(num)
    return math.floor(num + 0.5)
end

function file_exists(path)
    local f = io.open(path, "r")
    if f then io.close(f) return true end
    return false
end

function ensure_file_exists(path)
    if not file_exists(path) then
        local f = io.open(path, "w")
        if f then f:close() return true end
        return false
    end
    return true
end

function file_append(path, content)
    local f = io.open(path, "a")
    if f then
        f:write(content)
        f:close()
        return true
    end
    return false
end

function should_exclude(path)
    if not path then return true end
    
    for _, pattern in ipairs(split(o.exclude, ";")) do
        pattern = trim(pattern)
        if pattern ~= "" and contains(path, pattern) then
            return true
        end
    end
    return false
end

function split(str, sep)
    if not str or str == "" then return {} end
    
    local result = {}
    for match in (str..sep):gmatch("(.-)"..sep) do
        table.insert(result, match)
    end
    return result
end

-- Core functions
function on_file_loaded()
    local path = mp.get_property("path")
    if not path then return end
    
    watch_data.path = path
    watch_data.start_time = os.time()
    watch_data.duration = mp.get_property_number("duration") or 0
    watch_data.start_pos = mp.get_property_number("time-pos") or 0
    watch_data.last_pos = watch_data.start_pos
    watch_data.is_playing = true
    
    if contains(path, "://") then
        watch_data.filename = mp.get_property("media-title") or path
    else
        watch_data.filename = get_filename(path)
    end
    
    msg.info("Started tracking: " .. watch_data.filename)
end

function on_playback_restart()
    watch_data.is_playing = true
    watch_data.last_pos = mp.get_property_number("time-pos") or watch_data.last_pos
end

function on_pause_change(_, is_paused)
    watch_data.is_playing = not is_paused
    if not is_paused then
        watch_data.last_pos = mp.get_property_number("time-pos") or watch_data.last_pos
    end
end

function on_seek()
    watch_data.last_pos = mp.get_property_number("time-pos") or watch_data.last_pos
end

function update_position()
    if watch_data.is_playing then
        watch_data.last_pos = mp.get_property_number("time-pos") or watch_data.last_pos
    end
end

function calculate_percentage()
    if watch_data.duration <= 0 then return 0 end
    
    local percentage = (watch_data.last_pos / watch_data.duration) * 100
    return math.min(round(percentage), 100)
end

function log_history()
    if not watch_data.path or watch_data.path == "" then return end
    
    -- Get the final position
    local final_pos = mp.get_property_number("time-pos") or watch_data.last_pos
    watch_data.last_pos = final_pos
    
    -- Calculate watch time
    local watch_time = os.time() - watch_data.start_time
    if watch_time < o.minimal_play_time then return end
    
    -- Calculate percentage
    local percentage = calculate_percentage()
    
    -- Format output
    local date_str = os.date("%d.%m.%Y ")
    local time_str = format_time_12h()
    local minutes = round(watch_time / 60)
    local min_str = string.format("%d min", minutes)
    
    local log_line = string.format("%s%s  |  %s  |  %d%%  |  %s\n",
                                  date_str, time_str, min_str, 
                                  percentage, watch_data.filename)
    
    -- Write to file
    if not should_exclude(watch_data.path) then
        if ensure_file_exists(o.storage_path) then
            if file_append(o.storage_path, log_line) then
                msg.info("Logged: " .. watch_data.filename)
            else
                msg.error("Failed to write to log file: " .. o.storage_path)
            end
        else
            msg.error("Could not create log file: " .. o.storage_path)
        end
    end
    
    -- Reset state
    watch_data = {
        start_time = 0,
        path = "",
        filename = "",
        duration = 0,
        start_pos = 0,
        last_pos = 0,
        is_playing = false
    }
end

-- Set up event handlers
mp.register_event("file-loaded", on_file_loaded)
mp.register_event("end-file", log_history)
mp.register_event("shutdown", log_history)
mp.observe_property("pause", "bool", on_pause_change)
mp.register_event("seek", on_seek)
mp.register_event("playback-restart", on_playback_restart)

-- Update position every second to keep track of playback
mp.add_periodic_timer(1, update_position)

-- Create history file if it doesn't exist on script load
if not ensure_file_exists(o.storage_path) then
    msg.error("Failed to create history file on startup: " .. o.storage_path)
else
    msg.info("History file ready: " .. o.storage_path)
end
