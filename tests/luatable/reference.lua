-- Reference transcript for only the documented native subset.
local t = {}
local alias = t
local sparse = 1099511627776
print(t[sparse] == nil)
t[sparse] = false
print(t[sparse] == false)
print(t[sparse + 1] == nil)
t[1] = 17
t['1'] = 'string-key'
print(t[1])
print(t['1'])
t['a\0b'] = 'nul-key'
print(t['a\0b'])
print(t['a'] == nil)
alias[1] = 29
print(t[1])
alias[1] = nil
print(t[1] == nil)
print(t['1'])
t[sparse] = nil
print(t[sparse] == nil)
for i = 1, 1024 do t[i * 4099] = i end
local sum = 0
for i = 1, 1024 do sum = sum + t[i * 4099] end
print(sum)
for i = 1, 1024, 2 do t[i * 4099] = nil end
print(t[4099] == nil)
print(t[8198])
t[4099] = 3
print(t[4099])

-- Fixed-seed mutation trace; compare to Lua with repeated whole-domain reads.
local model = {}
local seed = 197
local function step()
  seed = (seed * 48271) % 2147483647
  return seed
end
local function domain(i)
  if i % 2 == 0 then return i * 524287 - 1000000000 end
  return tostring(i)
end
local function checksum()
  local live = 0
  for i = 0, 255 do
    local v = model[domain(i)]
    if v ~= nil then print(v); live = live + 1 else print(-1) end
  end
  print(live)
end
for i = 1, 8192 do
  local slot = step() % 256
  if step() % 3 == 0 then model[domain(slot)] = nil
  else model[domain(slot)] = step() % 1000 end
  if i % 256 == 0 then checksum() end
end
