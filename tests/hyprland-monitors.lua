-- Execute the generated monitor snippets with the same Lua major version used
-- by Hyprland. Stubs let us check the monitor calls and toggle without a session.
local monitors, notifications = {}, {}
local binding, toggle
hl = {
  monitor = function(config)
    table.insert(monitors, config)
  end,
  bind = function(chord, action)
    binding, toggle = chord, action
  end,
  exec_cmd = function(command)
    table.insert(notifications, command)
  end,
}
mainMod = "SUPER"

assert(loadfile(arg[1]))()
assert(loadfile(arg[2]))()

local expectedOutput = 'DP-"quoted\\u0001' .. string.char(11) .. '3'
assert(#monitors == 1)
assert(monitors[1].output == expectedOutput)
assert(monitors[1].mode == 'mode\nwith"quotes')
assert(monitors[1].position == 'x\\y')
assert(monitors[1].scale == 1.5)
assert(monitors[1].bitdepth == 8)
assert(monitors[1].cm == 'srgb\tcustom')
assert(monitors[1].sdrbrightness == 0.7)
assert(binding == 'SUPER + SHIFT + H' and type(toggle) == 'function')

toggle()
assert(monitors[2].output == expectedOutput and monitors[2].mode == monitors[1].mode)
assert(monitors[2].position == monitors[1].position and monitors[2].scale == 1.5)
assert(monitors[2].bitdepth == 8 and monitors[2].cm == 'hdr')
assert(monitors[2].sdrbrightness == 1.2)

toggle()
assert(monitors[3].output == expectedOutput and monitors[3].cm == 'srgb\tcustom')
assert(monitors[3].sdrbrightness == 1.0)
assert(#notifications == 2 and notifications[1]:find('HDR Enabled', 1, true))
assert(notifications[2]:find('SDR Mode', 1, true))
