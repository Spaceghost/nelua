local config = require 'nelua.configer'.get()
local executor = require 'nelua.utils.executor'
local fs = require 'nelua.utils.fs'
local stringer = require 'nelua.utils.stringer'

local bend = os.getenv('NELUA_BEND') or 'bend'
local supported_version = 'bend 2.0.40'
local generated = {}
local scalars = {
  uint32 = {bend = 'U32', c = 'uint32_t', pack = '(Term)%s', unpack = '(uint32_t)%s'},
  float32 = {bend = 'F32', c = 'float', pack = 'f32_rewrap(%s)', unpack = 'f32_unbox(%s)'},
}

local c_prelude = [[
static pthread_mutex_t nelua_bend_lock = PTHREAD_MUTEX_INITIALIZER;
static u64 *nelua_bend_heap;

static void nelua_bend_enter(void) {
  if (pthread_mutex_lock(&nelua_bend_lock) != 0) abort();
  if (nelua_bend_heap == NULL) {
    nelua_bend_heap = corpus_setup(false, 1, 0);
    io_stk = pool_stack();
  }
}
]]

local function compile(directory, source, bridge)
  local input = fs.join(directory, 'inline.bend')
  local output = fs.join(directory, 'inline.c')
  assert(fs.writefile(input, source))
  assert(fs.writefile(fs.join(directory, 'bridge.c'), bridge))

  local ok, _, stdout, stderr = executor.execex('env',
    {'BEND_NO_TELEMETRY=1', bend, input, '-o', output})
  if not ok then error(stdout .. stderr, 0) end

  local code = assert(fs.readfile(output))
  local main = code:find('\nint main(int argc, char** argv) {', 1, true)
  if not main or not code:match('\n}\n\n#endif%s*$') or
      not code:find(c_prelude, 1, true) then
    error('unsupported Bend2 C output format', 0)
  end
  -- Each block is a separate C translation unit with its own Bend runtime.
  local library, changed = code:sub(1, main):gsub(
    '\nEffect io_eff_rows%[', '\nstatic Effect io_eff_rows[', 1)
  if changed ~= 1 then error('unsupported Bend2 effect table format', 0) end
  return library .. '#endif\n'
end

local function generate(source, bridge, prefix)
  local existing = generated[prefix]
  if existing then return existing end

  local version, err = executor.evalex(bend, {'version'})
  if not version then error('could not run Bend2: ' .. err, 0) end
  if version:match('^%s*(.-)%s*$') ~= supported_version then
    error('expected ' .. supported_version .. ', got ' .. version, 0)
  end

  local cache = fs.abspath(fs.join(config.cache_dir, 'bend2'))
  local ok, cache_error = fs.makepath(cache)
  if not ok and not fs.isdir(cache) then error(cache_error, 0) end
  local tmpdir = fs.abspath(os.getenv('TMPDIR') or cache)
  local directory, temp_error = executor.evalex('mktemp', {'-d', fs.join(tmpdir, 'nelua-bend2.XXXXXXXX')})
  if not directory then error(temp_error, 0) end
  directory = directory:gsub('\n$', '')
  local staging
  local success, path = pcall(function()
    local code = compile(directory, source, bridge)
    local cached = fs.join(cache, prefix .. '_' .. stringer.hash(code) .. '.c')
    if fs.readfile(cached) ~= code then
      staging = assert(executor.evalex('mktemp', {fs.join(cache, '.bend2.XXXXXXXX')})):gsub('\n$', '')
      assert(fs.writefile(staging, code))
      assert(os.rename(staging, cached))
    end
    return cached
  end)
  if staging then os.remove(staging) end
  for _, name in ipairs{'inline.bend', 'inline.c', 'bridge.c'} do
    os.remove(fs.join(directory, name))
  end
  os.remove(directory)
  if not success then error(path, 0) end
  generated[prefix] = path
  return path
end

return function(syntax)
  syntax.rules([[
    Bend2Export <-- {| NAME SKIP `(` {| (NAME SKIP (`,` NAME SKIP)*)? |} `)`
                      `:` NAME SKIP |}
  ]])
  syntax.statement("'bend2' WORDSKIP `(` {| Bend2Export (`,` @Bend2Export)* |} @`)` @STRING_LONG SKIP",
    function(exports, code)
      if config.generator ~= 'c' then syntax.raise('Bend2 requires the Nelua C backend') end

      local signature = {}
      local names = {}
      for _, export in ipairs(exports) do
        local name, params, result = table.unpack(export)
        if not name:match('^[A-Za-z][A-Za-z0-9_]*$') or names[name] then
          syntax.raise('invalid or duplicate Bend2 export %q', name)
        end
        names[name] = true
        if not scalars[result] then
          syntax.raise('unsupported Bend2 result type %q for %s', result, name)
        end
        for _, param in ipairs(params) do
          if not scalars[param] then syntax.raise('unsupported Bend2 parameter type %q', param) end
        end
        signature[#signature + 1] = name .. '(' .. table.concat(params, ',') .. '):' .. result
      end

      local prefix = 'nelua_bend2_' .. stringer.hash(table.concat(signature, ',') .. '\n' .. code)
      local source = {code, ''}
      local bridge = {c_prelude}
      local declarations = {}
      for index, export in ipairs(exports) do
        local name, params, result = table.unpack(export)
        local result_type = scalars[result]
        local entry = prefix .. '_entry_' .. index
        local symbol = prefix .. '_call_' .. index
        local fid = 'FID(' .. entry .. ')'
        local bend_params, nelua_params, c_params, args, writes = {}, {}, {}, {}, {}
        for i, param in ipairs(params) do
          local arg = 'a' .. i
          local param_type = scalars[param]
          args[i] = arg
          bend_params[i] = arg .. ': ' .. param_type.bend
          nelua_params[i] = arg .. ': ' .. param
          c_params[i] = param_type.c .. ' ' .. arg
          writes[i] = ('  e.mem[task + %d] = %s;\n'):format(i - 1, param_type.pack:format(arg))
        end
        source[#source + 1] = ('def %s(%s) -> %s:\n  %s(%s)\n'):format(
          entry, table.concat(bend_params, ', '), result_type.bend, name, table.concat(args, ', '))
        bridge[#bridge + 1] = ([[
%s %s(%s) {
  nelua_bend_enter();
  Env e = { nelua_bend_heap, ALC[0] };
  u64 task = task_node(e, %s, TERM_HOLE, 0, 0);
%s  Term value = corpus_eval(e.mem, term_tsk(%s, task));
  if (pthread_mutex_unlock(&nelua_bend_lock) != 0) abort();
  return %s;
}
]]):format(result_type.c, symbol, #params == 0 and 'void' or table.concat(c_params, ', '),
          fid, table.concat(writes), fid, result_type.unpack:format('value'))
        declarations[#declarations + 1] =
          ('local function %s(%s): %s <cimport %q> end'):format(
            name, table.concat(nelua_params, ', '), result, symbol)
      end

      source[#source + 1] = [[
def nelua_bridge_anchor() -> IO(Unit):
  import "./bridge.c"

def main() -> IO(Unit):
  nelua_bridge_anchor()
]]
      local path = generate(table.concat(source, '\n'), table.concat(bridge, '\n'), prefix)
      local directives = ('## cfile(%q)\n## linklib "pthread"\n## linklib "m"\n'):format(path)
      return syntax.block(directives .. table.concat(declarations, '\n'))
    end)
end
