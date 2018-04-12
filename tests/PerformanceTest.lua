-- 1. If the number is used as the for loop limiter, no performance gain by replacing constant by number literals.
-- 2. Some 35% performance gains by replacing constant by number literals. (Performance of adding stuffs)
-- 3. traverse table by index (7.626s) without/with #, traverse by pairs/next (11.933s), traverse by ipairs (11.775s)
-- 4. Any reduction of table read benefits. lua does not do any optimization for those.
-- 5. Lua only evaluates the start, end, step of the loop once.
-- 6. Performance of ; adding number literals (1.062s); adding constants (1.414s); adding "#t" (2.887s)
-- 7. Mod by 16 (12.77s); bit_band(x, 15)  23.107s
-- 8. (x-x%16)/16  (15.136s); Divide by 16 and math floor(20.41s); bit_rshift(x, 4) (22.794s)
-- 9. string_char (20.446s) ; search a number table (16.865s)
-- 10. string_byte (6.774s) ; search a char table (5.886s)
-- 11. One call string_byte one by one 3.726s, call string.byte(1, 8), but reduces call times -- 1.204s
local RANGE = 100000000
local CONST = 997
local N_285 = 285
local math_floor = math.floor
local bit_rshift = bit.rshift
local string_char = string.char
local string_byte = string.byte
local math_random = math.random
local table_insert = table.insert

local bit_band = bit.band
local t = {}
for i = 1, 285 do
  t[i] = i
end

local numToChar = {}
for i=0, 255 do
  numToChar[i] = string_char(i)
end

local charToByte = {}
for i=0, 255 do
  charToByte[string_char(i)] = i
end

local pairs = pairs
local ipairs = ipairs

local function helper()
  print("end")
  return 285
end

local function helper1()
  print("start")
  return 1
end

local function helper2()
  print("step")
  return 1
end

local str ="abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1abj;sdfjakldjfldfjlaj;123012903912-3491-24-1"
local function test()
  local x = 192391309182031
  for i=1, 300000 do
    for j=1, 32 do
      local a,b,c,d,e, f, g, h=string_byte(str, j*8+1, j*8+8)
      x=x+a+b+c+d+e+f+g+h
    end
       
  end
  return x
end

local time = os.clock()
local x = test()
local elapsed = os.clock() - time
print("elapsed: ", elapsed)
print(x)