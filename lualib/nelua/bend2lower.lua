-- Lower the explicitly supported, pure uint32 subset of Nelua to Bend.
local lower = {}

local arithmetic = {add = 'add', sub = 'sub', mul = 'mul'}
local comparisons = {eq = 'is_eq', ne = 'is_ne', lt = 'is_lt',
  le = 'is_le', gt = 'is_gt', ge = 'is_ge'}

local function reject(node, message, ...)
  node:raisef('Bend2 Nelua: ' .. message, ...)
end

local function is_id(node, name)
  return node and node.tag == 'Id' and (not name or node[1] == name)
end

local function declaration(node)
  if node.tag ~= 'IdDecl' or type(node[1]) ~= 'string' or
      not is_id(node[2], 'uint32') or node[3] then
    reject(node, 'expected an explicit, unannotated uint32 declaration')
  end
  return node[1]
end

local function literal(node, contextual)
  local digits, suffix = node[1], node[2]
  local n = type(digits) == 'string' and digits:match('^%d+$') and math.tointeger(tonumber(digits))
  if not n or n < 0 or n > 4294967295 or
      (suffix ~= '_u32' and suffix ~= '_uint32' and (suffix or not contextual)) then
    reject(node, 'expected a decimal uint32 literal (use the _u32 suffix in expressions)')
  end
  return tostring(n)
end

local function expression(node, vars, functions, contextual)
  local tag = node.tag
  if tag == 'Paren' then
    return expression(node[1], vars, functions, contextual)
  elseif tag == 'Number' then
    -- Bend needs a typed expression when inferring the type of a let binding.
    return 'U32.add(0, ' .. literal(node, contextual) .. ')'
  elseif tag == 'Id' then
    local var = vars[node[1]]
    if not var then reject(node, 'unknown uint32 value %q', node[1]) end
    return var
  elseif tag == 'BinaryOp' and arithmetic[node[2]] then
    return ('U32.%s(%s, %s)'):format(arithmetic[node[2]],
      expression(node[1], vars, functions), expression(node[3], vars, functions))
  elseif tag == 'Call' and is_id(node[2]) then
    local name = node[2][1]
    local target = not vars[name] and functions[name]
    if not target then reject(node, 'call must name an earlier function in this block') end
    if #node[1] ~= target.arity then reject(node, 'wrong number of arguments to %q', name) end
    local args = {}
    for i, arg in ipairs(node[1]) do args[i] = expression(arg, vars, functions, true) end
    return ('%s(%s)'):format(target.name, table.concat(args, ', '))
  end
  reject(node, 'unsupported uint32 expression %s', tag == 'BinaryOp' and node[2] or tag)
end

local function condition(node, vars, functions)
  if node.tag == 'Paren' then return condition(node[1], vars, functions) end
  local op = node.tag == 'BinaryOp' and comparisons[node[2]]
  if not op then reject(node, 'expected a comparison of uint32 expressions') end
  return ('U32.%s(%s, %s)'):format(op,
    expression(node[1], vars, functions), expression(node[3], vars, functions))
end

local function copy_vars(vars)
  local copy = {}
  for name, value in pairs(vars) do copy[name] = value end
  return copy
end

local function reduce(node, vars, state)
  local index = declaration(node[1])
  local loop = node[6]
  if node[2].tag ~= 'Number' or literal(node[2], true) ~= '0' or node[3] ~= 'lt' or
      node[5] or #loop ~= 1 or loop[1].tag ~= 'Assign' then
    reject(node, 'expected a reduction loop: for i: uint32 = 0, < limit do total = total + value end')
  end
  local assign = loop[1]
  local target, value = assign[1][1], assign[2][1]
  local acc = is_id(target) and target[1]
  if #assign[1] ~= 1 or #assign[2] ~= 1 or not acc or not vars[acc] or acc == index or
      value.tag ~= 'BinaryOp' or value[2] ~= 'add' or not is_id(value[1], acc) then
    reject(assign, 'expected a single total = total + value reduction')
  end
  local formal, actual, recur = {}, {}, {}
  local scope = setmetatable({[index] = 'start'}, {__index = function(scope, name)
    if name == acc then reject(value[3], 'the reduction term cannot read its accumulator') end
    if not vars[name] then return nil end
    local i = #formal + 1
    local param = 'capture' .. i
    scope[name] = param
    formal[i] = ', +' .. param .. ': U32'
    actual[i] = ', ' .. vars[name]
    recur[i] = ', ' .. param
    return param
  end})
  local fn = state.fresh('reduce')
  local term = expression(value[3], scope, state.functions)
  local captured = table.concat(recur)
  state.helpers[#state.helpers + 1] = ([[
def %s(+depth: Nat, +start: U32, +stride: U32, +limit: U32, valid: Bool%s) -> U32:
  match depth valid:
    case 0n False{}:
      0
    case 0n True{}:
      %s
    case 1n+k False{}:
      0
    case 1n+k True{}:
      +half = U32.shrn(stride, 1n)
      +right = U32.add(start, stride)
      a b = %s(k, start, half, limit, True{}%s) %s(k, right, half, limit, U32.is_lt(right, limit)%s)
      U32.add(a, b)
]]):format(fn, table.concat(formal), term, fn, captured, fn, captured)
  local limit = expression(node[4], vars, state.functions, true)
  local initial = vars[acc]
  local bound = state.fresh('limit')
  local power = state.fresh('power')
  local result = state.fresh('value')
  vars[acc] = result
  -- Use the smallest power-of-two range covering the bound and prune its tail.
  return {
    ('+%s = %s'):format(bound, limit),
    ('+%s = U32.log2(U32.sub(%s, 1))'):format(power, bound),
    ('+%s = U32.add(%s, %s(Nat.add(%s, 1n), 0, U32.shln(1, %s), %s, U32.is_ne(%s, 0)%s))'):format(
      result, initial, fn, power, power, bound, bound, table.concat(actual)),
  }
end

local function block_code(block, vars, state, indent)
  local lines = {}
  local functions = state.functions
  local function emit(line)
    lines[#lines + 1] = indent .. line
  end
  for i, node in ipairs(block) do
    if node.tag == 'VarDecl' and node[1] == 'local' then
      local decls, values = node[2], node[3]
      if not values or #decls ~= #values then reject(node, 'each local needs one initializer') end
      local names, expressions = {}, {}
      for j, var in ipairs(decls) do
        names[j] = declaration(var)
        expressions[j] = expression(values[j], vars, functions, true)
      end
      for j, name in ipairs(names) do
        local id = state.fresh('value')
        vars[name] = id
        emit('+' .. id .. ' = ' .. expressions[j])
      end
    elseif node.tag == 'ForNum' then
      for _, line in ipairs(reduce(node, vars, state)) do emit(line) end
    elseif node.tag == 'Return' and i == #block and #node == 1 then
      emit(expression(node[1], vars, functions, true))
      return table.concat(lines, '\n')
    elseif node.tag == 'If' and i == #block and node[2] then
      local clauses = node[1]
      local args = {}
      for _, id in pairs(vars) do args[#args + 1] = id end
      table.sort(args)
      local params = {}
      for j, id in ipairs(args) do params[j] = ', +' .. id .. ': U32' end
      local function branches(at, padding)
        if at > #clauses then return block_code(node[2], copy_vars(vars), state, padding) end
        local check = condition(clauses[at], vars, functions)
        local fn = state.fresh('branch')
        local yes = block_code(clauses[at + 1], copy_vars(vars), state, '      ')
        local no = branches(at + 2, '      ')
        state.helpers[#state.helpers + 1] = table.concat({
          ('def %s(test: Bool%s) -> U32:'):format(fn, table.concat(params)),
          '  match test:',
          '    case True{}:', yes,
          '    case False{}:', no,
        }, '\n')
        return padding .. fn .. '(' .. check .. (#args > 0 and ', ' .. table.concat(args, ', ') or '') .. ')'
      end
      lines[#lines + 1] = branches(1, indent)
      return table.concat(lines, '\n')
    else
      reject(node, 'unsupported statement %s; use locals, a uint32 reduction, or a final return/if', node.tag)
    end
  end
  reject(block, 'every path must return one uint32 value')
end

function lower.translate(block)
  local counter = 0
  local function fresh(stem)
    counter = counter + 1
    return 'nelua_lower_' .. stem .. counter
  end
  local state = {fresh = fresh, functions = {}, helpers = {}}
  local code = {'import Base'}
  for _, node in ipairs(block) do
    if node.tag ~= 'FuncDef' or node[1] ~= 'local' or node[5] or
        not node[4] or #node[4] ~= 1 or not is_id(node[4][1], 'uint32') then
      reject(node, 'expected a local function with one uint32 return type')
    end
    local name = node[2][1]
    if type(name) ~= 'string' or state.functions[name] then
      reject(node, 'function needs a distinct, plain name')
    end
    local fn = fresh('function')
    local vars, params, types = {}, {}, {}
    for i, arg in ipairs(node[3]) do
      local key = declaration(arg)
      if vars[key] then reject(arg, 'duplicate parameter %q', key) end
      local id = fresh('value')
      vars[key] = id
      params[i] = '+' .. id .. ': U32'
      types[i] = 'uint32'
    end
    state.helpers = {}
    local body = block_code(node[6], vars, state, '  ')
    for _, helper in ipairs(state.helpers) do code[#code + 1] = helper end
    code[#code + 1] = ('def %s(%s) -> U32:\n%s'):format(fn, table.concat(params, ', '), body)
    state.functions[name] = {name = fn, arity = #params, params = types}
  end
  return table.concat(code, '\n\n'), state.functions
end

return lower
