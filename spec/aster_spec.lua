local lester = require 'nelua.thirdparty.lester'
local aster = require 'nelua.aster'
local expect = require 'spec.tools.expect'
local Attr = require 'nelua.attr'
local describe, it = lester.describe, lester.it

local n = aster

describe("aster", function()

it("create a valid ASTNode", function()
  local node = n.Number{'10'}
  assert(node)
  expect.equal(node.tag, 'Number')
  expect.equal({table.unpack(node)}, {'10'})
end)


it("preserves byte locations across source edits and out-of-order lookups", function()
  local reference = require 'nelua.thirdparty.lpegrex'.calcline
  local node = n.Id{'x'}
  local src = {}
  node.src = src
  for _,content in ipairs{'a\r\n\nβz\n', '', 'no newline', '\n\n'} do
    src.content = content
    for pos=#content+2,0,-1 do
      node.pos = pos
      local loc = node:location()
      expect.equal({loc.lineno, loc.colno, loc.line, loc.linestart, loc.lineend},
                   {reference(content, pos)})
    end
  end
end)

it("error on invalid ASTNode", function()
  expect.fail(function() n.Invalid{} end)
  expect.fail(function() n.Block{1} end)
  expect.fail(function() n.Block{{1}} end)
  expect.fail(function() n.Block{{'a'}} end,
    [[invalid shape while creating AST node "Block"]])
  expect.fail(function() aster:create('Invalid') end)
end)

it("clone different ASTNode", function()
  local node =
    n.Block{attr=Attr{someattr = true},
      n.Return{
        n.Nil{attr=Attr{someattr = true},
  }}}
  local cloned = node:clone()
  assert(cloned.attr.someattr == nil)
  assert(#cloned.attr == 0)
  assert(cloned ~= node)
  assert(cloned[1] ~= node[1])
  assert(cloned[1][1] ~= node[1][1])
  expect.equal(tostring(cloned), [[Block {
  Return {
    Nil {
    }
  }
}]])
end)

it("pretty", function()
  local node =
    n.Block{attr=Attr{someattr = true},
      n.Return{
        n.Nil{attr=Attr{someattr = true},
  }}}
  expect.equal(aster.pretty(node), [[
Block
| Return
| | Nil]])
end)

it("clone", function()
  expect.equal(aster.pretty(aster.clone(n.Id{'x'})), aster.pretty(n.Id{'x'}))
  expect.equal(aster.pretty(aster.clone{n.Id{'x'},n.Number{1}}), aster.pretty{n.Id{'x'},n.Number{1}})
end)

end)
