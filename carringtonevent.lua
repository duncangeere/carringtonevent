-- carringtonevent
-- v0.1 @duncangeere
--
-- carrington event
-- data sonification with Norns
--
-- ENC 3: select duration
-- KEY 3: toggle play/pause
-- KEY 2: reset and stop
--
-- Crow support
-- OUT1 = declination voltage
-- OUT2 = declination voltage
-- OUT3 = horizontal force voltage
-- OUT4 = storm voltage
--
--
music = require("musicutil")
-- Import musicutil library: https://monome.org/docs/norns/reference/lib/musicutil

-- Import library to update parameters (Thanks Eigen!)
local p_option = require "core/params/option"

-- Import csv library: https://github.com/geoffleyland/lua-csv
local csv = include("lib/csv")

-- Import chart library:
local Graph = include("lib/lightergraph")
chart = {}       -- line chart higher
chart_point = {} -- highlighting active point higher
spacing = 2

engine.name = "PolyPerc"

-- Init grid
g = grid.connect()

-- Init midi
if midi.devices ~= nil then my_midi = midi.connect() end

function init()
    -- DEFINING SYSTEM VARIABLES
    -- Data variables

    -- placeholder data
    data = { 1, 2, 3, 4, 5, 6, 7, 8 }

    columns = {}
    declinationcolumn = 2
    horizforcecolum = 3
    stormcolumn = 4
    data_length = 240

    -- SETTING UP
    file_name = "data"
    headers = {}
    grid_drawn = {}
    flash = 0
    gridflash = 0
    elapsed = 0
    loaded = false

    -- DATA
    params:add_separator("data")

    -- Add a duration parameters
    params:add {
        type = "number",
        id = "duration",
        name = "duration (mins)",
        min = 1,
        max = 30,
        default = 15,
        action = function() -- set the bpm when duration is changed
            params:set("clock_tempo", data_length / params:get("duration"))
            screen_dirty = true
            grid_dirty = true
        end
    }

    -- add datamin and datamax parameters
    params:add {
        type = "number",
        id = "datamin",
        name = "data min",
        min = -999999,
        max = 999999,
        default = 0,
        action = function() -- update the scale when it's changed
            if loaded then
                scale_data()
                update_chart_axes()
            end
            screen_dirty = true
            grid_dirty = true
        end
    }
    params:add {
        type = "number",
        id = "datamax",
        name = "data max",
        min = -999999,
        max = 999999,
        default = 0,
        action = function() -- update the scale when it's changed
            if loaded then
                scale_data()
                update_chart_axes()
            end
            screen_dirty = true
            grid_dirty = true
        end
    }

    -- CROW
    -- Setting slew of outputs
    crow.output[1].slew = 1.0
    crow.output[2].slew = 1.0
    crow.output[3].slew = 1.0
    crow.output[4].slew = 1.0

    -- MIDI
    params:add_separator("MIDI")

    -- Midi channel number
    params:add {
        type = "number",
        id = "midi_channel",
        name = "MIDI channel number",
        min = 1,
        max = 16,
        default = 1
    }

    -- Midi options
    params:add_binary("send_midi_cc", "Send MIDI CC?", "toggle", 1)

    -- Midi gate length
    params:add_control("midi_length", "MIDI note length (s)",
        controlspec.new(0.01, 5, "lin", 0.01, 0.1))

    params:add {
        type = "number",
        id = "midi_cc",
        name = "MIDI CC number",
        min = 0,
        max = 127,
        default = 1
    }

    params:add {
        type = "number",
        id = "midi_cc_min",
        name = "MIDI CC output min",
        min = 0,
        max = 126,
        default = 0
    }

    params:add {
        type = "number",
        id = "midi_cc_max",
        name = "MIDI CC output max",
        min = 1,
        max = 127,
        default = 127
    }

    reload_data()         -- initial load of data
    scale_data()          -- scale the data

    position = 1          -- Set initial position at start of data
    clock_playing = false -- whether notes are playing
    screen_dirty = true   -- track whether screen needs redrawing
    grid_dirty = true     -- track whether grid needs redrawing

    -- Start a clock to refresh the grid
    redraw_grid_clock_id = clock.run(redraw_grid_clock)

    -- Start a metro to track time that has passed
    elapsed_metro = metro.init(ticker, 1, -1)
end

function redraw()
    -- clear the screen
    screen.clear()

    -- flash rectangle across whole screen
    if flash >= 3 then
        if columns.storm[position] == 1 then
            screen.level(10)
        elseif columns.storm[position] == 0.5 then
            screen.level(3)
        else
            screen.level(0)
        end
        screen.rect(0, 0, 128, 64)
        screen.fill()
    end

    if loaded then
        -- Redraw background chart
        chart:redraw()
        chart_point:redraw()
    end

    -- Sync bpm to duration
    params:set("clock_tempo", data_length / params:get("duration"))
    params:bang()

    -- Text bits
    screen.level(15)
    screen.font_size(8)
    screen.font_face(1)

    screen.move(spacing + 1, 5)
    screen.text(loaded and (string.format("declination: %.0f", columns.declination[position]) or "loading..."))
    screen.move(spacing + 1, 13)
    screen.text(loaded and (string.format("horiz force: %.0f", columns.horizforce[position]) or "loading..."))

    screen.move(spacing + 1, 62)
    screen.text(clock_playing and "||" or "▶")

    screen.move(128 - 2, 5)
    screen.text_right(string.format("%.0fbpm", clock.get_tempo()))

    screen.move(128 - 2, 13)
    screen.text_right(string.format("%.0f mins", params:get("duration")))

    screen.move(128 - 2, 21)
    -- create a timestring with minutes and seconds as 00m00s
    local elapsedstring = string.format("%02.f", elapsed // 60) .. "m" .. string.format("%02.f", elapsed % 60) .. "s"
    screen.text_right(elapsedstring)

    screen.move(128 - 2, 62)
    screen.font_face(18)
    screen.font_size(10)
    screen.level(3 + (10 * columns.storm[position]))
    screen.text_right("fret: " .. columns.fret[position])

    -- trigger a screen update
    screen.update()
end

function redraw_grid()
    -- clear the grid
    g:all(0)

    -- flash the grid
    local gridflashbrightness = 0
    if columns.storm[position] == 0.5 then gridflashbrightness = 4 end
    if columns.storm[position] == 1 then gridflashbrightness = 15 end

    -- light the top row of the grid if a storm is happening
    if gridflash >= 3 then
        for i = 1, g.cols do
            for j = 1, g.rows do
                g:led(i, j, gridflashbrightness)
            end
        end
    end

    -- loop over the data and draw the bars
    for i = 1, #grid_drawn do
        -- calculate height and x positions
        local h = map(grid_drawn[i], params:get("datamin"), params:get("datamax"), 0, g.rows, true)
        h = math.ceil(h) -- round up for sub-pixel values
        local x = i
        local brightness = i == 1 and 15 or 7

        -- Light the column
        for j = 0, h do
            y = g.rows + 1 - h + j
            g:led(x, y, brightness)
        end
    end

    -- trigger a grid update
    g:refresh()
end

-- start playing the notes
function play_note()
    declination_volts = map(columns.declination[position], params:get("datamin"), params:get("datamax"), 0, 10, true)
    horizforce_volts = map(columns.horizforce[position], 100, -100, 0, 10, true)
    storm_volts = map(columns.storm[position], 0, 1, 0, 5, true)

    -- Send crow outputs
    crow.output[1].volts = declination_volts
    crow.output[2].volts = declination_volts
    crow.output[3].volts = horizforce_volts
    crow.output[4].volts = storm_volts

    -- Play midi
    if midi.devices ~= nil then
        -- If midi cc is being sent, send it
        if params:get("send_midi_cc") == 1 then
            -- Calculate CC value to send
            local cc_val = math.floor(
                map(
                    data[position],
                    params:get("datamin"),
                    params:get("datamax"),
                    params:get("midi_cc_min"),
                    params:get("midi_cc_max"),
                    true
                )
            );
            -- Send it
            my_midi:cc(params:get("midi_cc"), cc_val, params:get("midi_channel"))
        end
    end
end

-- when a key is depressed
function key(n, z)
    -- Button 2: play/pause
    if n == 2 and z == 1 then
        if not clock_playing then
            if midi.devices ~= nil then my_midi:start() end
            elapsed_metro:start()
            play = clock.run(function()
                while true do
                    -- Sync to the clock
                    clock.sync(1)

                    -- Play a note
                    play_note()

                    -- Increment position
                    increment_position()
                end
            end) -- starts the clock coroutine
            clock_playing = true
        elseif clock_playing then
            stop_play()
        end
    end

    -- Button 3: reset and stop
    if n == 3 and z == 1 then
        position = 1

        elapsed_metro:stop()
        elapsed = 0

        stop_play()
        update_chart()
    end

    screen_dirty = true
    grid_dirty = true
end

-- stops the coroutine playing the notes
function stop_play()
    if (play) then clock.cancel(play) end
    elapsed_metro:stop()
    if midi.devices ~= nil then my_midi:stop() end
    clock_playing = false
end

-- when an encoder is twiddled
function enc(n, d)
    -- ENC 3 select bpm
    if (n == 3) then
        params:set("duration", params:get("duration") + d)
    end

    params:bang()
    screen_dirty = true
    grid_dirty = true
end

-- Function to map values from one range to another
function map(n, start, stop, newStart, newStop, withinBounds)
    local value = ((n - start) / (stop - start)) * (newStop - newStart) +
        newStart

    -- // Returns basic value
    if not withinBounds then return value end

    -- // Returns values constrained to exact range
    if newStart < newStop then
        return math.max(math.min(value, newStop), newStart)
    else
        return math.max(math.min(value, newStart), newStop)
    end
end

-- Scale the data to the grid
function scale_data()
    if g.device ~= nil then
        grid_drawn = { table.unpack(data, position, position + (g.cols - 1)) }
    end
end

-- Updates graph y-axes
function update_chart_axes()
    chart:set_y_min(params:get("datamin"))
    chart:set_y_max(params:get("datamax"))
    chart_point:set_y_min(params:get("datamin"))
    chart_point:set_y_max(params:get("datamax"))

    chart:redraw()
    chart_point:redraw()
end

-- Adds 1 to the position and resets if it gets to the end of the data
function increment_position()
    update_chart()

    if (position == (#data)) then
        stop_play()
        elapsed_metro:stop()
    else
        position = position + 1
    end

    if g.device ~= nil then
        grid_drawn = { table.unpack(data, position, position + (g.cols - 1)) }
    end

    screen_dirty = true
    grid_dirty = true
end

function update_chart()
    chart_point:remove_all_points()
    chart_point:add_point(position, data[position], "lin", true)
    screen_dirty = true
    grid_dirty = true
end

-- Reloads the data once a new csv file is selected
function reload_data()
    print("reloading data")
    headers = {}
    columns = {}
    counter = 1;

    print(_path.code .. "carringtonevent" ..
        file_name .. ".csv")

    -- open the file
    f = csv.open(_path.code .. "carringtonevent/" ..
        file_name .. ".csv",
        { separator = ",", header = true })

    -- loop through each line
    for fields in f:lines() do
        for i, v in pairs(fields) do
            -- if the header isn't already in the columns table, add it
            if columns[i] == nil then
                columns[i] = {}
                headers[counter] = i
                counter = counter + 1
            end

            -- otherwise add the data
            table.insert(columns[i], tonumber(v) ~= nil and tonumber(v) or v)
        end
    end

    table.sort(headers)

    print("column headers found:")
    tab.print(headers)
    update_data()
    loaded = true
end

-- Runs when a new column is selected and when a new csv file is selected in params
function update_data()
    print("Loading column " .. headers[declinationcolumn])
    data = columns[headers[declinationcolumn]]
    position = 1

    update_data_range()

    -- Define the chart
    chart = Graph.new(1, #data, "lin", params:get("datamin"), params:get("datamax"), "lin", "line", false, false)
    chart:set_position_and_size(1 + spacing, 10, 128 - (spacing * 2), 52)
    -- Add data to it
    for i = 1, #data do chart:add_point(i, data[i]) end

    -- Make a chart with a single point
    chart_point = Graph.new(1, #data, "lin", params:get("datamin"), params:get("datamax"), "lin", "point", false,
        false)
    chart_point:set_position_and_size(1 + spacing, 10, 128 - (spacing * 2), 52)
end

-- Runs in the update_data function and on initial script load
function update_data_range()
    -- calculate default min and max for the data
    dMin = math.min(table.unpack(data)) -- min of the table
    dMax = math.max(table.unpack(data)) -- max of the table
    params:set("datamin", dMin)
    params:set("datamax", dMax)
    print("dMin is now " .. params:get("datamin"))
    print("dMax is now " .. params:get("datamax"))
end

-- Updates the options of a parameter dynamically (Thanks Eigen!)
-- This is used to refresh the list of columns in the param menu
-- when a new file is selected
function update_param_options(id, options, default)
    local p_i_id = params.lookup[id]
    if p_i_id ~= nil then
        local p = params.params[p_i_id]
        local new_p = p_option.new(p_id, id, options, default)
        params.params[p_i_id] = new_p
        params:set_action(id, p.action)
    end
end

-- Check if the screen needs redrawing 60 times a second
function refresh()
    -- Flash when a storm is happening
    if columns.storm[position] >= 0.5 then
        flash = flash + 1
        gridflash = gridflash + 1
        if flash == 6 then flash = 0 end
        if gridflash == 6 then gridflash = 0 end
        screen_dirty = true
        grid_dirty = true
    end

    if screen_dirty then
        redraw()
        screen_dirty = false
    end
end

-- Check if the grid needs redrawing 10 times a second
function redraw_grid_clock()
    while true do
        clock.sleep(1 / 60)
        if grid_dirty and g.device ~= nil then
            redraw_grid()
            grid_dirty = false
        end
    end
end

function ticker()
    elapsed = elapsed + 1
    screen_dirty = true
end
