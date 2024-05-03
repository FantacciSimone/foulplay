-- euclidean sample instrument
-- with trigger conditions.
--
-- ----------
--
-- based on tehn/playfair,
-- with generous contributions
-- from junklight and okyeron.
--
-- ----------
--
-- samples can be loaded
-- via the parameter menu.
--
-- ----------
-- home
--
-- enc1 = cycle through
--         the tracks.
-- enc2 = set the number
--         of trigs.
-- enc3 = set the number
--         of steps.
-- key2 = start and stop the
--         clock.
--
-- on the home screen,
-- key3 is alt.
--
-- alt + enc1 = mix volume
-- alt + enc2 = rotation
-- alt + enc3 = bpm
--
-- ----------
-- holding key1 will bring up the
-- track edit screen. release to
-- return home.
-- ----------
-- track edit
--
-- encoders 1-3 map to
-- parameters 1-3.
--
-- key2 = advance to the
--         next track.
-- key3 = advance to the
--         next page.
--
-- ----------
-- grid
-- ----------
--
-- col 1 select track edit
-- col 2 provides mute toggles
--
-- the dimly lit 5x5 grid is
-- made up of memory cells.
-- memory cells hold both
-- pattern and pset data.
-- simply pressing a cell
-- will load the pattern
-- data.
--
-- button 4 on row 7 starts
-- and stops the clock.
-- while the clock is stopped
-- the button will blink.
--
-- button 5 on row 7 is
-- the phase reset button.
--
-- button 8 on row 7 is
-- the pset load button.
--
-- to load a pset, press
-- and hold the pset load
-- button while touching
-- the desired memory cell.
--
-- open track edit pages
-- with grid buttons 4-7 on
-- the bottom row.
--
-- button 8 on the bottom row
-- is the copy button.
--
-- to copy a pattern to a new
-- cell hold the copy button,
-- and press the cell you'd
-- like to copy.
-- the cell will blink. while
-- still holding copy, press the
-- destination cell.
-- release the copy button.
--
-- v1.2 @justmat
--
-- llllllll.co/t/21081

er = require 'er'

engine.name = 'Ack'
local ack = require 'ack/lib/ack'
local MusicUtil = require "musicutil"

local g = grid.connect()
local midi_device = {}
local midi_device_names = {}

local alt = 0
local reset = false
-- 0 == home, 1 == track edit
local view = 0
local page = 0
local track_edit = 1
local stopped = 1
local pset_load_mode = false
local current_pset = 0

local note_root = 60
local scale_notes = {}
local scale_names = {}

-- for new clock system
local clock_id = 0
local draw_cycle = 0
local draw_cycle_i = 0

function pulse()
  while true do
    clock.sync(1/4)
    step()
  end
end


function clock.transport.stop()
  clock.cancel(clock_id)
  reset_pattern()
  stopped = 1
end


function clock.transport.start()
  clock_id = clock.run(pulse)
end

-- a table of midi note on/off status i = 1/0
local note_off_queue = {}
for i = 1, 8 do
  note_off_queue[i] = 0
end

local track_trig = {}
for i = 1, 8 do
  track_trig[i] = 0
end

-- added for grid support - junklight
local current_mem_cell = 1
local current_mem_cell_x = 4
local current_mem_cell_y = 1

local copy_mode = false
local blink = false
local copy_source_x = -1
local copy_source_y = -1

function simplecopy(obj)
  if type(obj) ~= 'table' then return obj end
  local res = {}
  for k, v in pairs(obj) do
    res[simplecopy(k)] = simplecopy(v)
  end
  return res
end

local memory_cell = {}
for j = 1,25 do
  memory_cell[j] = {
      n = 0,
      s = 1
  }
  for i=1, 8 do
    memory_cell[j][i] = {
      k = 0,
      n = 16,
      pos = 1,
      s = {},
      prob = 100,
      trig_logic = 0,
      logic_target = track_edit,
      rotation = 0,
      mute = 0,
      root = 1,
      root_x = 1,
      root_y = 1,
      scale = 1,
      scale_x = 1,
      scale_y = 1,
      last_note = note_root
  }
  end
end


local function gettrack( cell , tracknum )
  return memory_cell[cell][tracknum]
end

local function cellfromgrid( x , y )
    return (((y - 1) * 5) + (x -4)) + 1
end

local function notefromgrid( i, x , y )
    local _pos =  (((y - 2) * 6) + (x - 10))
    local _note =  params:get(i .. "_root_note") + _pos
    --print("NOTE FROM GRID | ".._note)    
    if params:get(i.."_use_scale") == 2 then
        --print(_pos +1 .." | "..note_root.." | ".._note)    
        _note = params:get(i .. "_root_note") - note_root + scale_notes[params:get(i.."_the_scale")][_pos + 1]
        --print("NOTE FROM GRID SCALED | ".._note)    
    end
    return _note
end

local function scalefromgrid( i, x , y )
    draw_cycle = 1
    draw_cycle_i = i
    _pos = (((y - 1) * 8) + (x - 9)) + 1
    if y>1 and y<=8 then
        if x==16 and y<8 then
            _pos = _pos - (6*(y-1)) 
        elseif x>=9 then
            _pos = _pos - (6*(y-1)) + 6 
        end
    end
    if params:get(i.."_use_scale") == 2 then
        if params:get(i.."_the_scale") == _pos then
            params:set(i.."_use_scale", 1)
        else
            params:set(i.."_the_scale", _pos)
        end
    else
        params:set(i.."_use_scale", 2)
        params:set(i.."_the_scale", _pos)
    end
    return _pos
end

local function rotate_pattern(t, rot, n, r)
  -- rotate_pattern comes to us via okyeron and stackexchange
  n, r = n or #t, {}
  rot = rot % n
  for i = 1, rot do
    r[i] = t[n - rot + i]
  end
  for i = rot + 1, n do
    r[i] = t[i - rot]
  end
  return r
end

local function reer(i)
  if gettrack(current_mem_cell,i).k == 0 then
    for n=1,32 do gettrack(current_mem_cell,i).s[n] = false end
  else
    gettrack(current_mem_cell,i).s = rotate_pattern(er.gen(gettrack(current_mem_cell,i).k, gettrack(current_mem_cell,i).n), gettrack(current_mem_cell, i).rotation)
  end
end

local function send_engine_trig(i)
    if params:get(i .. "_send_ack") == 2 then
        track_trig[i] = 1
        engine.trig(i-1)
    end
end

local function send_crow(i,_note_playing)
	if params:get(i .. "_send_crow") > 1 then
		if params:get(i .. "_send_crow") == 2 then
		    crow.output[1].volts=(_note_playing-60)/12
            crow.output[2].execute()    
		elseif params:get(i .. "_send_crow") == 3 then
		    crow.output[3].volts=(_note_playing-60)/12
            crow.output[4].execute()    
		elseif params:get(i .. "_send_crow") >= 4 then
		    crow.output[params:get(i .. "_send_crow")-3]()
		end
		track_trig[i] = 2
	end
end

local function send_jf_note(i,_note_playing)
    if params:get(i .. "_send_jf") == 2 then
	    crow.ii.jf.play_note((_note_playing - 60) / 12, 5) -- TODO 5v -> 9v or add param?
	    track_trig[i] = 3
    end
end

local function send_midi_note_on(i,_note_playing)
    if params:get(i .. "_midi_send") == 2 then
        midi_device[params:get(i.."_midi_target")]:note_on(_note_playing, params:get(i.."_midi_vel"), params:get(i.."_midi_chan"))
        note_off_queue[i] = 1
        track_trig[i] = 4
    end
end

local function send_midi_note_off(i)
  if note_off_queue[i] == 1 then
    midi_device[params:get(i.."_midi_target")]:note_off(gettrack(current_mem_cell,i).last_note, 0, params:get(i.."_midi_chan"))
    note_off_queue[i] = 0
  end
end

local function send_note(i,t)
    
    send_engine_trig(i)

    _note_playing = gettrack(current_mem_cell,i).root
    if params:get(i.."_use_scale") == 2 then
        if params:get(i.."_rnd_scale_note") == 2 then 
            p = math.random(t.pos)
        else
            p = t.pos        
        end
        _note_playing = _note_playing + scale_notes[params:get(i.."_the_scale")][p] - note_root

    end
	gettrack(current_mem_cell,i).last_note=_note_playing
	
	send_midi_note_on(i,_note_playing)
	send_jf_note(i,_note_playing)
	send_crow(i,_note_playing)
	
end

local function trig()
  -- mute state is ignored for trigger logics
  for i, t in ipairs(memory_cell[current_mem_cell]) do
    -- no trigger logic
    if t.trig_logic==0 and t.s[t.pos]  then
      if math.random(100) <= t.prob and t.mute == 0 then
        send_note(i,t)
      end
    else
      send_midi_note_off(i)
    end
    -- logical and
    if t.trig_logic == 1 then
      if t.s[t.pos] and gettrack(current_mem_cell,t.logic_target).s[gettrack(current_mem_cell,t.logic_target).pos]  then
        if math.random(100) <= t.prob and t.mute == 0 then
          send_note(i,t)
        else break end
      else
        send_midi_note_off(i)
      end
    -- logical or
    elseif t.trig_logic == 2 then
      if t.s[t.pos] or gettrack(current_mem_cell,t.logic_target).s[gettrack(current_mem_cell,t.logic_target).pos] then
        if math.random(100) <= t.prob and t.mute == 0 then
          send_note(i,t)
        else break end
      else
        send_midi_note_off(i)
      end
    -- logical nand
    elseif t.trig_logic == 3 then
      if t.s[t.pos] and gettrack(current_mem_cell,t.logic_target).s[gettrack(current_mem_cell,t.logic_target).pos]  then
      elseif t.s[t.pos] then
        if math.random(100) <= t.prob and t.mute == 0 then
          send_note(i,t)
        else break end
      else
        send_midi_note_off(i)
      end
    -- logical nor
    elseif t.trig_logic == 4 then
      if not t.s[t.pos] and math.random(100) <= t.prob then
        if not gettrack(current_mem_cell,t.logic_target).s[gettrack(current_mem_cell,t.logic_target).pos] and t.mute == 0 then
          send_note(i,t)
        else break end
      else
        send_midi_note_off(i)
      end
    -- logical xor
    elseif t.trig_logic == 5 then
      if t.mute == 0 and math.random(100) <= t.prob then
        if not t.s[t.pos] and not gettrack(current_mem_cell,t.logic_target).s[gettrack(current_mem_cell,t.logic_target).pos] then
        elseif t.s[t.pos] and gettrack(current_mem_cell,t.logic_target).s[gettrack(current_mem_cell,t.logic_target).pos] then
        else
          send_note(i,t) -- maybe to remove
          send_midi_note_off(i)
        end
      else break end
    end
  end
end

local function note_formatter(param)
  note_number = param:get()
  note_name = MusicUtil.note_num_to_name(note_number, true)
  return note_number.." ["..note_name.."]"
end

function init()
  for i=1, 8 do reer(i) end

  for i = 1,#midi.vports do
    midi_device[i] = midi.connect(i)
    table.insert(midi_device_names, util.trim_string_to_width(midi_device[i].name,70))
  end

  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_notes, MusicUtil.generate_scale_of_length(note_root, i, 36))
    table.insert(scale_names, MusicUtil.SCALES[i].name)
  end

  screen.line_width(1)
  params:add_separator('tracks')
  for i = 1, 8 do
    params:add_group("track " .. i, 38)
    params:add_separator('root')
    params:add_number(i.."_root_note", i..": note", 0, 127, note_root, note_formatter)

    params:add_separator('scale')
    params:add_option(i.."_use_scale", i..": use scale", {"no", "yes"}, 1)
    params:add_option(i.."_the_scale", i..": scale", scale_names, 1)
    params:add_option(i.."_rnd_scale_note", i..": randomize note", {"no", "yes"}, 1)
    
    params:add_separator('midi')
    params:add_option(i.."_midi_send", i..": send", {"no", "yes"}, 1)
    params:add_option(i.."_midi_target", i..": device", midi_device_names, 1)
    params:add_number(i.."_midi_chan", i..": channel", 1, 16, 1)
    params:add_number(i.."_midi_vel", i..": velocity", 0, 127, 100)
    
    params:add_separator('crow | jf')
    params:add_option(i.."_send_crow", i ..": send crow", {"no", "cv/gate 1+2", "cv/gate 3+4", "trig 1", "trig t2", "trig t3", "trig t4"}, 1)
    params:add_option(i.."_send_jf", i..": send jf", {"no", "yes"}, 1)

    params:add_separator('engine')
    params:add_option(i.."_send_ack", i..": send", {"no", "yes"}, 1)
    ack.add_channel_params(i)
    
  end
  
  params:add_separator('effects')
  ack.add_effects_params()
  -- load default pset
  params:read()
  params:bang()
  -- load pattern data
  loadstate()

  if stopped==1 then
    clock.cancel(clock_id)
  else
    clock_id = clock.run(pulse)
  end
  
  -- grid refresh timer, 15 fps
  metro_grid_redraw = metro.init(function(stage) grid_redraw() end, 1 / 15)
  metro_grid_redraw:start()
  -- blink for copy mode
  metro_blink = metro.init(function(stage) blink = not blink end, 1 / 4)
  metro_blink:start()
  -- savestate timer
  metro_save = metro.init(function(stage) savestate() end, 10)
  metro_save:start()
  
  -- crow triggers
  for i = 1, 4 do
    crow.output[i].action = "pulse(.1, 5, 1)"
  end
  -- jf pullup
  crow.ii.pullup(true)
  crow.ii.jf.mode(1)
end


function reset_pattern()
  reset = true
end


function step()
  if reset then
    for i=1,8 do
      gettrack(current_mem_cell,i).pos = 1
    end
    reset = false
  else
    for i=1,8 do
      gettrack(current_mem_cell,i).pos = (gettrack(current_mem_cell,i).pos % gettrack(current_mem_cell,i).n) + 1
    end
  end
  
  -- song mode
  if memory_cell[current_mem_cell].n > 0 then
      
      if gettrack(current_mem_cell,1).pos == gettrack(current_mem_cell,1).n then
        --print("< " ..  memory_cell[current_mem_cell].s)
        memory_cell[current_mem_cell].s = memory_cell[current_mem_cell].s + 1
        
        if memory_cell[current_mem_cell].s == memory_cell[current_mem_cell].n + 1  then
            if memory_cell[current_mem_cell+1].n > 0 then
               current_mem_cell = current_mem_cell+1 
            else
               current_mem_cell = 1
            end
            memory_cell[current_mem_cell].s = 1
            --print("P_" .. current_mem_cell)
        end
      else
        -- percentuale avanzamento parte
        --print((memory_cell[current_mem_cell].s / memory_cell[current_mem_cell].n) * 100)
      end

  end

  trig()
  redraw()
end


function key(n,z)
  -- home and track edit views
  if n==1 then view = z end
  -- track edit view
  if view==1 then
    if n==3 and z==1 then
      if params:get(track_edit.."_midi_send") == 1 then
        page = (page + 1) % 4
      -- there are only 2 pages of midi options
      else page = (page + 1) % 2 end
    end
  end
  if n==3 then alt = z end
  -- track selection in track edit view
  if view==1 then
    if n==2 and z==1 then
      track_edit = (track_edit % 8) + 1
    end
  end

  if alt==1 then
    -- track phase reset
    if n==2 and z==1 then
      if gettrack(current_mem_cell, track_edit).mute == 1 then
        gettrack(current_mem_cell, track_edit).mute = gettrack(current_mem_cell, track_edit).mute == 0 and 1 or 0
      else
        reset_pattern()
        if stopped == 1 then
            step()
        end
      end
    end
  end
  -- home view. start/stop
  if alt==0 and view==0 then
    if n==2 and z==1 then
      if stopped==0 then
        stopped = 1
        clock.cancel(clock_id)
      elseif stopped==1 then
        stopped = 0
        clock_id = clock.run(pulse)
      end
    end
  end
  redraw()
end


function enc(n,d)
  if alt==1 then

    -- mem lenght  
    if n==1 then
      memory_cell[current_mem_cell].n = util.clamp(memory_cell[current_mem_cell].n + d, 0, 32)

    -- mix volume control
    elseif n==2 then
      params:delta("output_level", d)

    -- bpm control
    elseif n==3 then
      params:delta("clock_tempo", d)

    -- track rotation control    
    elseif n==4 then
      gettrack(current_mem_cell,track_edit).rotation = util.clamp(gettrack(current_mem_cell,track_edit).rotation + d, 0, 32)
      gettrack(current_mem_cell,track_edit).s = rotate_pattern( gettrack(current_mem_cell,track_edit).s, gettrack(current_mem_cell, track_edit).rotation )
      redraw()
    end

  -- track edit view
  elseif view==1 and page==0 then
    if n==1 then
      params:delta(track_edit .. "_root_note", d)
    elseif n==2 then
      --params:delta(track_edit .. "_", d)
    elseif n==3 then
      --params:delta(track_edit .. "_", d)
    end
    
  elseif view==1 and page==1 then
    if n==1 then
      params:delta(track_edit .. "_midi_send", d)
    elseif n==2 then
      params:delta(track_edit .. "_send_crow", d)
    elseif n==3 then
      params:delta(track_edit .. "_send_jf", d)
    end

  elseif view==1 and page==2 then
    if n==1 then
      params:delta(track_edit .. "_midi_target", d)
    elseif n==2 then
      params:delta(track_edit .. "_midi_chan", d)
    elseif n==3 then
      params:delta(track_edit .. "_midi_vel", d)
    end

  elseif view==1 and page==3 then
    if n==1 then
      params:delta(track_edit .. "_use_scale", d)
    elseif n==2 then
      params:delta(track_edit .. "_the_scale", d)
    elseif n==3 then
      params:delta(track_edit .. "_rnd_scale_note", d)
    end

  elseif view==1 and page==4 then
    -- trigger logic and probability settings
    if n==1 then
      gettrack(current_mem_cell,track_edit).trig_logic = util.clamp(d + gettrack(current_mem_cell,track_edit).trig_logic, 0, 5)
    elseif n==2 then
      gettrack(current_mem_cell,track_edit).logic_target = util.clamp(d+ gettrack(current_mem_cell,track_edit).logic_target, 1, 8)
    elseif n==3 then
      gettrack(current_mem_cell,track_edit).prob = util.clamp(d + gettrack(current_mem_cell,track_edit).prob, 1, 100)
    end
    
  elseif view==1 and page==6 then
    -- per track volume control
    if n==1 then
      params:delta(track_edit .. "_send_ack", d)
    elseif n==2 then
      params:delta(track_edit .. "_vol", d)
    elseif n==3 then
      params:delta(track_edit .. "_loop", d)
    end
  
  elseif view==1 and page==7 then
    -- sample playback settings
    if n==1 then
      params:delta(track_edit .. "_speed", d)
    elseif n==2 then
      params:delta(track_edit .. "_start_pos", d)
    elseif n==3 then
      params:delta(track_edit .. "_end_pos", d)
    end

  elseif view==1 and page==8 then
    -- filter and fx sends
    if n==1 then
      params:delta(track_edit .. "_filter_mode", d)
    elseif n==2 then
      params:delta(track_edit .. "_filter_cutoff", d)
    elseif n==3 then
      params:delta(track_edit .. "_filter_res", d)
    end
    
  elseif view==1 and page==9 then
    -- filter and fx sends
    if n==1 then
      params:delta(track_edit .. "_sample_rate", d)
    elseif n==2 then
      params:delta(track_edit .. "_bit_depth", d)
    elseif n==3 then
      params:delta(track_edit .. "_dist", d)
    end
    
  elseif view==1 and page==10 then
    -- filter and fx sends
    if n==1 then
      params:delta(track_edit .. "_pan", d)
    elseif n==2 then
      params:delta(track_edit .. "_delay_send", d)
    elseif n==3 then
      params:delta(track_edit .. "_reverb_send", d)
    end

--"1_sample"
--"1_loop"
--"1_loop_point"
--"1_vol_env_atk"
--"1_vol_env_rel"
--"1_filter_env_atk"
--"1_filter_env_rel"
--"1_filter_env_mod"

  -- HOME
  -- choose focused track, track fill, and track length
  elseif n==1 and d==1 then
    track_edit = (track_edit % 8) + d
  elseif n==1 and d==-1 then
    track_edit = (track_edit + 6) % 8 + 1
  elseif n == 2 then
    gettrack(current_mem_cell,track_edit).k = util.clamp(gettrack(current_mem_cell,track_edit).k+d,0,gettrack(current_mem_cell,track_edit).n)
  elseif n==3 then
    gettrack(current_mem_cell,track_edit).n = util.clamp(gettrack(current_mem_cell,track_edit).n+d,1,32)
    gettrack(current_mem_cell,track_edit).k = util.clamp(gettrack(current_mem_cell,track_edit).k,0,gettrack(current_mem_cell,track_edit).n)
  -- track rotation control
  elseif n==4 then
      gettrack(current_mem_cell, track_edit).rotation = util.clamp(gettrack(current_mem_cell, track_edit).rotation + d, 0, 32)
      gettrack(current_mem_cell,track_edit).s = rotate_pattern( gettrack(current_mem_cell,track_edit).s, gettrack(current_mem_cell, track_edit).rotation )
      redraw()
  end
  reer(track_edit)
  redraw()
end


function redraw()
  screen.aa(0)
  screen.clear()
  
    if view==0 then
        screen.level(15)
        if draw_cycle > 0 then
          
          -- overlay action
          if draw_cycle >= 1 and draw_cycle < 10  then
            --scale select
            draw_cycle = draw_cycle + 1
            screen.move(70,3*7.70)
            screen.text_center("Track #"..draw_cycle_i)
            screen.move(70,4*7.70)
            screen.text_center(MusicUtil.SCALES[params:get(track_edit .. "_the_scale")].name)
            screen.move(70,5*7.70)
            screen.text_center((params:get(track_edit.."_use_scale") == 2 and "ON" or "OFF"))
          
          elseif draw_cycle >= 10 and draw_cycle < 20  then
            --copy mode
            draw_cycle = draw_cycle + 1
            screen.move(70,4*7.70)
            screen.text_center("COPY")
            
            --- TODO
            --if copy_mode then
            --    screen.move(70,5*7.70)
            --   screen.text_center(copy_source_x.."x"..copy_source_y)
            --end  
          end
    
        else
            
            
            if alt==1 then
                -- alt redraw
                
                --mem leght
                screen.move(110, 0 + 11)
                screen.text("P"..current_mem_cell)
                screen.move(110, 6 + 11)
                if memory_cell[current_mem_cell].n > 0 then
                    screen.text(memory_cell[current_mem_cell].s .. "/" .. memory_cell[current_mem_cell].n)
                else
                    screen.text(utf8.char(0x221E))
                end
                    
                --main vol
                screen.move(110, 18 + 11)
                screen.text("vol")
                screen.move(112, 26 + 11)
                screen.text(string.format("%.1f", params:get("output_level")))
                
                --main bpm
                screen.move(110, 38 + 11)
                screen.text("bpm")
                screen.move(112, 46 + 11)
                screen.text(string.format("%.1f", clock.get_tempo()))
                
                for i=1,8 do
                  --step rotation
                  screen.level((i == track_edit) and 15 or 4)
                  screen.move(4, i*7.70)
                  screen.text_center(gettrack(current_mem_cell, i).rotation)
                end
            else
    
                -- progress
                if memory_cell[current_mem_cell].n > 0 then
                    _o = (gettrack(current_mem_cell,1).pos / gettrack(current_mem_cell,1).n) * 128
                    _p = (memory_cell[current_mem_cell].s / memory_cell[current_mem_cell].n) * 128
                    screen.move(1,1)
                    screen.line_rel(_o,0)
                    screen.move(1,64)
                    screen.line_rel(_p,0)
                end

                -- default redraw
                for i=1, 8 do
                  --active step
                  screen.move(4, i*7.70)
                  screen.text_center(gettrack(current_mem_cell,i).k)
                  
                  --root note
                  screen.move(119,i*7.70)
                  screen.text_center(MusicUtil.note_num_to_name(gettrack(current_mem_cell,i).root, true))
    
            end

        end
            -- common redraw
            for i=1,8 do
                
                -- mute and scale
                screen.level((i == track_edit) and 15 or 4)
                  if gettrack(current_mem_cell, i).mute == 1 then
                   screen.move(12,i*7.70)
                   screen.text_center("m")
                  else
                   if params:get(i.."_use_scale") == 2 then
                    if params:get(i.."_rnd_scale_note") == 2 then
                        screen.move(11,i*7.70)
                        screen.line_rel(0,-1-(math.random(5)))
                        screen.move(12,i*7.70)
                        screen.line_rel(0,-1-(math.random(5)))
                        screen.move(13,i*7.70)
                        screen.line_rel(0,-1-(math.random(5)))
                        screen.move(14,i*7.70)
                        screen.line_rel(0,-1-(math.random(5)))
                        screen.move(15,i*7.70)
                        screen.line_rel(0,-1-(math.random(5)))
                    else
                        screen.move(11,i*7.70)
                        screen.line_rel(0,-1)
                        screen.move(12,i*7.70)
                        screen.line_rel(0,-2)
                        screen.move(13,i*7.70)
                        screen.line_rel(0,-3)
                        screen.move(14,i*7.70)
                        screen.line_rel(0,-4)
                        screen.move(15,i*7.70)
                        screen.line_rel(0,-5)
                    end
                   else
                    screen.move(11,i*7.70-3)
                    screen.line_rel(0,1)
                    screen.move(12,i*7.70-3)
                    screen.line_rel(0,1)
                    screen.move(13,i*7.70-3)
                    screen.line_rel(0,1)
                    screen.move(14,i*7.70-3)
                    screen.line_rel(0,1)
                    screen.move(15,i*7.70-3)
                    screen.line_rel(0,1)
                   end
                  end
                
                --play note
                screen.move(25, i*7.70)
                if gettrack(current_mem_cell,i).s[gettrack(current_mem_cell,i).pos] then
                  if track_trig[i] > 1 then
                    screen.text_center(MusicUtil.note_num_to_name(gettrack(current_mem_cell,i).last_note, true))
                  elseif track_trig[i] == 1 then
                    screen.text_center("o")                        
                  end
                end
                  
                --track lenght
                screen.move(38,i*7.70)
                screen.text_center(gettrack(current_mem_cell,i).n)
                
                -- grid
                for x=1,gettrack(current_mem_cell,i).n do
                    screen.level(gettrack(current_mem_cell,i).pos==x and 15 or 2)
                    screen.move(x*2 + 45, i*7.70)
                    if gettrack(current_mem_cell,i).s[x] then
                      screen.line_rel(0,-6)
                    else
                      screen.line_rel(0,-1)
                    end
                    screen.stroke()
                  end
            end

        end  
        
        --overlay cycle reset count
        if draw_cycle == 5 or draw_cycle == 15 or stopped == 1 then
            draw_cycle = 0
            draw_cycle_i = 0
        end 

    elseif view==1 and page==0 then
      screen.move(5, 10)
      screen.level(15)
      screen.text("track : " .. track_edit)
      screen.move(120, 10)
      screen.text_right("page " .. page + 1)
      screen.move(5, 15)
      screen.line(121, 15)
      screen.move(64, 25)
      screen.level(4)
      _root_note = params:get(track_edit .. "_root_note")
      screen.text_center("1. root note : " .. _root_note .." ["..MusicUtil.note_num_to_name(_root_note, true).."]")
      screen.move(64, 35)
	  --screen.text_center("2. vol : " .. params:get(track_edit .. "_midi_chan"))
      screen.move(64, 45)
      --screen.text_center("3. bpm : " .. params:get(track_edit .. "_midi_vel"))

    elseif view==1 and page==1 then
      screen.move(5, 10)
      screen.level(15)
      screen.text("track : " .. track_edit)
      screen.move(120, 10)
      screen.text_right("page " .. page + 1)
      screen.move(5, 15)
      screen.line(121, 15)
      screen.move(64, 25)
      screen.level(4)
      screen.text_center("1. midi : " .. (params:get(track_edit .. "_midi_send") == 2 and "yes" or "no"))
      screen.move(64, 35)
      local _send_crow = ""
      if params:get(track_edit .. "_send_crow") == 1 then
          _send_crow = "no"    
      elseif params:get(track_edit .. "_send_crow") == 2 then
          _send_crow = "cv/gate 1+2"
      elseif params:get(track_edit .. "_send_crow") == 3 then
          _send_crow = "cv/gate 3+4"
      elseif params:get(track_edit .. "_send_crow") == 4 then
          _send_crow = "trig 1"
      elseif params:get(track_edit .. "_send_crow") == 5 then
          _send_crow = "trig 2"
      elseif params:get(track_edit .. "_send_crow") == 6 then
          _send_crow = "trig 3"
      elseif params:get(track_edit .. "_send_crow") == 7 then
          _send_crow = "trig 4"
      end
      screen.text_center("2. crow : " .. _send_crow)
      screen.move(64, 45)
      screen.text_center("3. jf : " .. (params:get(track_edit .. "_send_jf") == 2 and "yes" or "no"))

    elseif view==1 and page==2 then
      screen.move(5, 10)
      screen.level(15)
      screen.text("track : " .. track_edit)
      screen.move(120, 10)
      screen.text_right("page " .. page + 1)
      screen.move(5, 15)
      screen.line(121, 15)
      screen.move(64, 25)
      screen.level(4)
      screen.text_center("1. midi device : " .. midi_device[params:get(track_edit .. "_midi_target")].name)
      screen.move(64, 35)
	  screen.text_center("2. midi channel : " .. params:get(track_edit .. "_midi_chan"))
      screen.move(64, 45)
      screen.text_center("3. midi velocity : " .. params:get(track_edit .. "_midi_vel"))

   elseif view==1 and page==3 then
      screen.move(5, 10)
      screen.level(15)
      screen.text("track : " .. track_edit)
      screen.move(120, 10)
      screen.text_right("page " .. page + 1)
      screen.move(5, 15)
      screen.line(121, 15)
      screen.move(64, 25)
      screen.level(4)
      screen.text_center("1. use scale : " .. (params:get(track_edit .. "_use_scale") == 2 and "yes" or "no"))
      screen.move(64, 35)
	  screen.text_center("2. scale : " .. MusicUtil.SCALES[params:get(track_edit .. "_the_scale")].name)
      screen.move(64, 45)
      screen.text_center("3. randomize note : " .. (params:get(track_edit .. "_rnd_scale_note") == 2 and "yes" or "no"))

  elseif view==1 and page==4 then
    screen.move(5, 10)
    screen.level(15)
    screen.text("track : " .. track_edit)
    screen.move(120, 10)
    screen.text_right("page " .. page + 1)
    screen.move(5, 15)
    screen.line(121, 15)
    screen.move(64, 25)
    screen.level(4)
    if gettrack(current_mem_cell,track_edit).trig_logic == 0 then
      screen.text_center("1. trig logic : -")
      screen.move(64, 35)
      screen.level(1)
      screen.text_center("2. logic target : -")
      screen.level(4)
    elseif gettrack(current_mem_cell,track_edit).trig_logic == 1 then
      screen.text_center("1. trig logic : and")
      screen.move(64, 35)
      screen.text_center("2. logic target : " .. gettrack(current_mem_cell,track_edit).logic_target)
    elseif gettrack(current_mem_cell,track_edit).trig_logic == 2 then
      screen.text_center("1. trig logic : or")
      screen.move(64, 35)
      screen.text_center("2. logic target : " .. gettrack(current_mem_cell,track_edit).logic_target)
    elseif gettrack(current_mem_cell,track_edit).trig_logic == 3 then
      screen.text_center("1. trig logic : nand")
      screen.move(64, 35)
      screen.text_center("2. logic target : " .. gettrack(current_mem_cell,track_edit).logic_target)
    elseif gettrack(current_mem_cell,track_edit).trig_logic == 4 then
      screen.text_center("1. trig logic : nor")
      screen.move(64, 35)
      screen.text_center("2. logic target : " .. gettrack(current_mem_cell,track_edit).logic_target)
    elseif gettrack(current_mem_cell,track_edit).trig_logic == 5 then
      screen.text_center("1. trig logic : xor")
      screen.move(64, 35)
      screen.text_center("2. logic target : " .. gettrack(current_mem_cell,track_edit).logic_target)
    end
    screen.move(64, 45)
    screen.text_center("3. trig probability : " .. gettrack(current_mem_cell,track_edit).prob .. "%")


  elseif view==1 and page==6 then
    screen.move(5, 10)
    screen.level(15)
    screen.text("track : " .. track_edit)
    screen.move(120, 10)
    screen.text_right("page " .. page)
    screen.move(5, 15)
    screen.line(121, 15)
    screen.move(64, 25)
    screen.level(4)
    screen.text_center("1. engine : " .. (params:get(track_edit .. "_send_ack") == 2 and "yes" or "no"))
    screen.move(64, 35)
    screen.text_center("2. vol : " .. string.format("%.1f", params:get(track_edit .. "_vol")))
    screen.move(64, 45)
    screen.text_center("3. loop : " .. (params:get(track_edit .. "_loop") == 2 and "yes" or "no"))

  elseif view==1 and page==7 then
    screen.move(5, 10)
    screen.level(15)
    screen.text("track : " .. track_edit)
    screen.move(120, 10)
    screen.text_right("page " .. page)
    screen.move(5, 15)
    screen.line(121, 15)
    screen.move(64, 25)
    screen.level(4)
    screen.text_center("1. speed : " .. params:get(track_edit .. "_speed"))
    screen.move(64, 35)
    screen.text_center("2. start pos : " .. params:get(track_edit .. "_start_pos"))
    screen.move(64, 45)
    screen.text_center("3. end pos : " .. params:get(track_edit .. "_end_pos"))

  elseif view==1 and page==8 then
    screen.move(5, 10)
    screen.level(15)
    screen.text("track : " .. track_edit)
    screen.move(120, 10)
    screen.text_right("page " .. page)
    screen.move(5, 15)
    screen.line(121, 15)
    screen.level(4)
    screen.move(64, 25)

    _filter_mode = ""
    if params:get(track_edit .. "_filter_mode") == 1 then
          _filter_mode = "lowpass"    
      elseif params:get(track_edit .. "_filter_mode") == 2 then
          _filter_mode = "bandpass"
      elseif params:get(track_edit .. "_filter_mode") == 3 then
          _filter_mode = "highpass"
      elseif params:get(track_edit .. "_filter_mode") == 4 then
          _filter_mode = "notch"
      elseif params:get(track_edit .. "_filter_mode") == 5 then
          _filter_mode = "peak"
      end
    screen.text_center("1. filter mode : " .._filter_mode)

    screen.move(64, 35)
    screen.text_center("2. filter cutoff : " .. math.floor(params:get(track_edit .. "_filter_cutoff") + 0.5))
    screen.move(64, 45)
    screen.text_center("3. filter res : " .. params:get(track_edit .. "_filter_res"))
  
elseif view==1 and page==9 then
    screen.move(5, 10)
    screen.level(15)
    screen.text("track : " .. track_edit)
    screen.move(120, 10)
    screen.text_right("page " .. page)
    screen.move(5, 15)
    screen.line(121, 15)
    screen.level(4)
    screen.move(64, 25)
    screen.text_center("1. sample rate : " .. params:get(track_edit .. "_sample_rate"))
    screen.move(64, 35)
    screen.text_center("2. bit rate : " .. params:get(track_edit .. "_bit_depth"))
    screen.move(64, 45)
    screen.text_center("3. distortion : " .. params:get(track_edit .. "_dist") * 100 .. "%")
    
 elseif view==1 and page==10 then
    screen.move(5, 10)
    screen.level(15)
    screen.text("track : " .. track_edit)
    screen.move(120, 10)
    screen.text_right("page " .. page)
    screen.move(5, 15)
    screen.line(121, 15)
    screen.level(4)
    screen.move(64, 25)
    screen.text_center("1. pan : " .. params:get(track_edit .. "_pan"))
    screen.move(64, 35)
    screen.text_center("2. delay : " .. params:get(track_edit .. "_delay_send"))
    screen.move(64, 45)
    screen.text_center("3. reverb : " .. params:get(track_edit .. "_reverb_send"))

  end
  screen.stroke()
  screen.update()
end
 
 
-- grid stuff - junklight
function g.key(x, y, state)
  -- use first column to switch track edit
  if x == 1 then
    track_edit = y
  end
  
  -- second column provides mutes
  if x == 2 and state == 1 then
    if gettrack(current_mem_cell, y).mute == 0 then
      gettrack(current_mem_cell, y).mute = 1
    elseif gettrack(current_mem_cell, y).mute == 1 then
      gettrack(current_mem_cell, y).mute = 0
    end
  end
  
  -- third column provides random note on scale
  if x == 3 and state == 1 then
    
    if params:get(y.."_rnd_scale_note") == 1 then
      params:set(y.."_rnd_scale_note",2)
    elseif params:get(y.."_rnd_scale_note") == 2 then
      params:set(y.."_rnd_scale_note",1)
    end
  end
  
  -- y 7-8 and x 4-8, are used to open track parameters 10 pages
  if y >= 7 and y <= 8 and x >= 4 and x <= 8 and state == 1 then
    view = 1
    page = x - 4 + (6 * (y - 7))
  else
    view = 0
  end
  
  -- start and stop button.
  if x == 4 and y == 6 and state == 1 then
    if stopped == 1 then
      stopped = 0
      clock_id = clock.run(pulse)
    else
      stopped = 1
      clock.cancel(clock_id)
    end
  end
  
  -- reset button
  if x == 5 and y == 6 and state == 1 then
    reset_pattern()
    if stopped == 1 then
      step()
    end
  end
  
  -- set pset load button
  if x == 7 and y == 6 and state == 1 then
    pset_load_mode = true
  elseif x == 7 and y == 6 and state == 0 then
    pset_load_mode = false
  end
  
  -- load pset 1-25
  if pset_load_mode then
    if y >= 1 and y <= 5 and x >= 4 and x <= 8 and state == 1 then
      params:read(cellfromgrid(x,y))
      params:bang()
      print("loaded pset " .. cellfromgrid(x, y))
      current_pset = cellfromgrid(x, y)
      -- if you were stopped before loading, stay stopped after loading
      if stopped == 1 then
        run = false
      end
    end
  end
  
  -- copy button
  if x == 8 and y==6 and state == 1 then
    copy_mode = true
    copy_source_x = -1
    copy_source_y = -1
    draw_cycle = 10
  elseif x == 8 and y==6 and state == 0 then
    copy_mode = false
    copy_source_x = -1
    copy_source_y = -1
  end
  
  -- memory cells
  -- switches on grid down
  if not copy_mode and not pset_load_mode then
    if y >= 1 and y <= 5 and x >= 4 and x <= 8 and state == 1 then
      current_mem_cell = cellfromgrid(x,y)
      current_mem_cell_x = x
      current_mem_cell_y = y
      for i = 1, 8 do reer(i) end
    end
  else
    if y >= 1 and y <= 5 and x >= 4 and x <= 8 and state == 0 then
      if not pset_load_mode then
        -- copy functionality
        if copy_source_x == -1 then
          -- first button sets the source
          copy_source_x = x
          copy_source_y = y
        else
          -- second button copies source into target
          if copy_source_x ~= -1 and not ( copy_source_x == x and copy_source_y == y) then
            sourcecell = cellfromgrid( copy_source_x , copy_source_y )
            targetcell = cellfromgrid( x , y )
            memory_cell[targetcell] = simplecopy(memory_cell[sourcecell])
          end
        end
      end
    end
  end
  
  -- root note cells
  -- switches on grid down
  if not copy_mode and not pset_load_mode then
    if y >= 1 and y <= 8 and x >= 9 and x <= 16 and state == 1 then
    
        if y >= 2 and y <= 7 and x >= 10 and x <= 15 and state == 1 then
          gettrack(current_mem_cell, track_edit).root = notefromgrid(track_edit,x,y)
          gettrack(current_mem_cell, track_edit).root_x = x-9
          gettrack(current_mem_cell, track_edit).root_y = y-1
        else
          gettrack(current_mem_cell, track_edit).scale = scalefromgrid(track_edit,x,y)
          gettrack(current_mem_cell, track_edit).scale_x = x-8
          gettrack(current_mem_cell, track_edit).scale_y = y      
        end
    end
  end
  
  redraw()
end


function grid_redraw()
  if g == nil then
    -- bail if we are too early
    return
  end
  g:all(0)

  -- highlight current track
  g:led(1, track_edit, 15)

  -- track edit page buttons
  for page = 0, 4 do
      g:led(page + 4, 7, 3)
      g:led(page + 4, 8, 3)
  end

  -- highlight page if open
  if view == 1 then
    if page <=5 then
        g:led(page + 4, 7, 14)
    else
        g:led(page + 4 - 6, 8, 14)
    end
  end

  -- mutes - bright for on, dim for off
  for i = 1,8 do
    if gettrack(current_mem_cell, i).mute == 1 then
      g:led(2, i, 4)
    else 
      g:led(2, i, 15)
    end
  end
  
  -- trig - bright for on, dim for off
  for i = 1,8 do
    g:led(3, i, 2)
    if track_trig[i] > 1 then
        g:led(3, i, 10 + track_trig[i])
        track_trig[i] = 0
    end
  end
  
  -- memory cells
  for x = 4,8 do
    for y = 1,5 do
      g:led(x, y, 3)
    end
  end

  -- highlight active cell
  g:led(current_mem_cell_x, current_mem_cell_y, 15)
  if copy_mode then
    -- copy mode - blink the source if set
    if copy_source_x ~= -1 then
      if blink then
        g:led(copy_source_x, copy_source_y, 4)
      else
        g:led(copy_source_x, copy_source_y, 12)
      end
    end
  end

  -- start/stop
  if stopped == 0 then
    g:led(4, 6, 15)
  elseif stopped == 1 then
    if blink then
      g:led(4, 6, 4)
    else
      g:led(4, 6, 12)
    end
  end

  -- reset button
  g:led(5, 6, 3)

  -- load pset button
  if pset_load_mode then
    g:led(7, 6, 12)
  else g:led(7, 6, 3) end

  -- copy button
  if copy_mode  then
    g:led(8, 6, 14)
  else
    g:led(8, 6, 3)
  end
  
  -- root note cells
  for x = 10,15 do
    for y = 2,7 do
      g:led(x, y, 3)
    end
  end

  -- highlight C root note cells
  g:led(10, 2, 10)
  g:led(10, 4, 10)
  g:led(10, 6, 10)

  -- highlight current track root note cell
  g:led(gettrack(current_mem_cell, track_edit).root_x+9, gettrack(current_mem_cell, track_edit).root_y+1, 15) 

  -- highlight current track scale cell
  g:led(gettrack(current_mem_cell, track_edit).scale_x+8, gettrack(current_mem_cell, track_edit).scale_y, (params:get(track_edit.."_use_scale") == 2) and 15 or 4) 

  g:refresh()
end


function savestate()
  local file = io.open(_path.data .. "foulplay/foulplay-pattern.data", "w+")
  io.output(file)
  io.write("v2" .. "\n")
  for j = 1, 25 do
    for i = 1, 8 do
      io.write(memory_cell[j][i].k .. "\n")
      io.write(memory_cell[j][i].n .. "\n")
      io.write(memory_cell[j][i].prob .. "\n")
      io.write(memory_cell[j][i].trig_logic .. "\n")
      io.write(memory_cell[j][i].logic_target .. "\n")
      io.write(memory_cell[j][i].rotation .. "\n")
      io.write(memory_cell[j][i].mute .. "\n")
      io.write(memory_cell[j][i].root .. "\n")
      io.write(memory_cell[j][i].root_x .. "\n")
      io.write(memory_cell[j][i].root_y .. "\n")
      io.write(memory_cell[j][i].scale .. "\n")
      io.write(memory_cell[j][i].scale_x .. "\n")
      io.write(memory_cell[j][i].scale_y .. "\n")
    end
  end
  io.close(file)
end


function loadstate()
  local file = io.open(_path.data .. "foulplay/foulplay-pattern.data", "r")
  if file then
    print("datafile found")
    io.input(file)
    if io.read() == "v2" then
      for j = 1, 25 do
        for i = 1, 8 do
          memory_cell[j][i].k = tonumber(io.read())
          memory_cell[j][i].n = tonumber(io.read())
          memory_cell[j][i].prob = tonumber(io.read())
          memory_cell[j][i].trig_logic = tonumber(io.read())
          memory_cell[j][i].logic_target = tonumber(io.read())
          memory_cell[j][i].rotation = tonumber(io.read())
          memory_cell[j][i].mute = tonumber(io.read())
          memory_cell[j][i].root = tonumber(io.read())
          memory_cell[j][i].root_x = tonumber(io.read())
          memory_cell[j][i].root_y = tonumber(io.read())
          memory_cell[j][i].scale = tonumber(io.read())
          memory_cell[j][i].scale_x = tonumber(io.read())
          memory_cell[j][i].scale_y = tonumber(io.read())
        end
      end
    else
      print("invalid data file")
    end
    io.close(file)
  end
  for i = 1, 8 do reer(i) end
end
