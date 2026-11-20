local lester = require 'nelua.thirdparty.lester'
local describe, it = lester.describe, lester.it
local expect = require 'spec.tools.expect'
local aster = require 'nelua.aster'
local lower = require 'nelua.bend2lower'

local function translate(src)
  return lower.translate(aster.parse(src, 'bend2lower.nelua'))
end

describe('Nelua to Bend2 lowering', function()
  it('preserves explicit uint32 arithmetic and earlier helper calls', function()
    local code, functions = translate([[
local function adjust(x: uint32): uint32
  return x - 1_u32
end
local function run(x: uint32): uint32
  local y: uint32 = adjust(x)
  return y * x
end
]])
    expect.contains('U32.sub(', code)
    expect.contains('U32.mul(', code)
    expect.contains(functions.adjust.name .. '(', code)
    expect.equal(functions.run.params[1], 'uint32')
  end)

  it('lowers a ranged sum to a pruned, balanced reduction', function()
    local code = translate([[
local function run(n: uint32): uint32
  local result: uint32 = 10
  for i: uint32 = 0, < n do
    result = result + (i * i)
  end
  return result
end
]])
    expect.contains('case 1n+k True{}:', code)
    expect.contains('a b = nelua_lower_reduce', code)
    expect.contains('U32.is_lt(right, limit)', code)
  end)

  it('rejects effects and direct accumulator dependencies', function()
    local ok, err = pcall(translate, [[
local function run(n: uint32): uint32
  print(n)
  return n
end
]])
    expect.equal(ok, false)
    expect.contains('unsupported statement Call', tostring(err))
    ok, err = pcall(translate, [[
local function run(n: uint32): uint32
  local result: uint32 = 0
  for i: uint32 = 0, < n do
    result = result + (result * i)
  end
  return result
end
]])
    expect.equal(ok, false)
    expect.contains('the reduction term cannot read its accumulator', tostring(err))
  end)
end)
