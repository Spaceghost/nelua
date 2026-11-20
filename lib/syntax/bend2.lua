local lpeg = require 'lpeglabel'
local config = require 'nelua.configer'.get()
local executor = require 'nelua.utils.executor'
local fs = require 'nelua.utils.fs'
local stringer = require 'nelua.utils.stringer'

local bend = os.getenv('NELUA_BEND') or 'bend'
local supported_version = 'bend 2.0.40'
local generated = {}
local types = {
  uint32 = {bend = 'U32', c = 'uint32_t', pack = '(Term)%s', unpack = '(uint32_t)%s'},
  float32 = {bend = 'F32', c = 'float', pack = 'f32_rewrap(%s)', unpack = 'f32_unbox(%s)'},
  string = {bend = 'String', c = 'void *', nelua = 'string', input = 'io_str', output = 'io_cstr'},
  bytes = {bend = 'List<&2, U32>', c = 'void *', nelua = 'string', input = 'io_list',
    output = 'io_cbuf', cons = ', CID(Con)'},
  u32s = {bend = 'List<&2, U32>', c = 'void *', nelua = 'vector(uint32)',
    input = 'nelua_bend_pack_u32s', output = 'nelua_bend_unpack_u32s'},
  void = {bend = 'Unit', c = 'void'},
}

local c_prelude = [[
static pthread_mutex_t nelua_bend_lock = PTHREAD_MUTEX_INITIALIZER;
static u64 *nelua_bend_heap;
#if BEND_CUDA
static CUcontext nelua_bend_gpu_ctx, nelua_bend_previous_ctx;

#if NELUA_BEND_AUTO
static pthread_once_t nelua_bend_cuda_probe_once = PTHREAD_ONCE_INIT;
static bool nelua_bend_cuda_ready;
static void nelua_bend_probe_cuda(void) {
  CUcontext previous;
  if (!nelua_bend_load_cuda() || cuInit(0) != CUDA_SUCCESS ||
      cuCtxGetCurrent(&previous) != CUDA_SUCCESS) return;
  if (gpu_probe() != NULL) return;
  nelua_bend_cuda_ready = cuCtxGetCurrent(&nelua_bend_gpu_ctx) == CUDA_SUCCESS;
  if (cuCtxSetCurrent(previous) != CUDA_SUCCESS)
    err_fail("cannot restore the calling CUDA context");
}

int NELUA_BEND_CUDA_READY(void) {
  if (pthread_once(&nelua_bend_cuda_probe_once, nelua_bend_probe_cuda) != 0) abort();
  return nelua_bend_cuda_ready;
}
#endif

static u64 nelua_bend_gpu_bytes(void) {
  const char *arg = getenv("NELUA_BEND_GPU_MIB");
  if (arg == NULL || *arg == 0) return 1024ull << 20;
  char *end;
  u64 mib = strtoull(arg, &end, 10);
  if (*end || arg[strspn(arg, "0123456789")] || mib == 0 || mib > (SIZE_MAX >> 20))
    err_fail("NELUA_BEND_GPU_MIB must be a positive MiB count");
  return mib << 20;
}
#endif

static void nelua_bend_enter(void) {
  if (pthread_mutex_lock(&nelua_bend_lock) != 0) abort();
#if BEND_CUDA
#if !NELUA_BEND_AUTO
  if (cuInit(0) != CUDA_SUCCESS) err_fail("cannot initialize CUDA");
#endif
  if (cuCtxGetCurrent(&nelua_bend_previous_ctx) != CUDA_SUCCESS)
    err_fail("cannot get the calling CUDA context");
#endif
  if (nelua_bend_heap == NULL) {
#if BEND_CUDA
#if NELUA_BEND_AUTO
    if (cuCtxSetCurrent(nelua_bend_gpu_ctx) != CUDA_SUCCESS)
      err_fail("cannot select the Bend CUDA context");
#else
    const char *reason = gpu_probe();
    if (reason != NULL) err_fail(reason);
    if (cuCtxGetCurrent(&nelua_bend_gpu_ctx) != CUDA_SUCCESS)
      err_fail("cannot retain the Bend CUDA context");
#endif
    nelua_bend_heap = corpus_setup(true, 1, nelua_bend_gpu_bytes());
#else
    nelua_bend_heap = corpus_setup(false, 1, 0);
#endif
    io_stk = pool_stack();
#if BEND_CUDA
  } else if (cuCtxSetCurrent(nelua_bend_gpu_ctx) != CUDA_SUCCESS) {
    err_fail("cannot select the Bend CUDA context");
#endif
  }
}

static void nelua_bend_leave(void) {
#if BEND_CUDA
  if (cuCtxSetCurrent(nelua_bend_previous_ctx) != CUDA_SUCCESS)
    err_fail("cannot restore the calling CUDA context");
#endif
  if (pthread_mutex_unlock(&nelua_bend_lock) != 0) abort();
}
]]

local function rebase_foreign(source, origin, scratch)
  local P, S, R, C, Cs = lpeg.P, lpeg.S, lpeg.R, lpeg.C, lpeg.Cs
  local function quoted(mark)
    return P(mark) * (P('\\') * P(1) + (P(1) - S(mark .. '\\')))^0 * P(mark)
  end
  local word = R('az', 'AZ', '09') + S('_.-')
  local space = S(' \t\r\n')
  local foreign = (C(P'import' * space^1 * P'"') * C((P(1) - P'"')^0) * P'"') /
    function(lead, path)
      if path:sub(1, 1) ~= '/' and (path:sub(-2) == '.c' or path:sub(-3) == '.js') then
        path = fs.relpath(fs.abspath(path, origin), scratch)
      end
      return lead .. path .. '"'
    end
  local comment = P'#' * (P(1) - S'\r\n')^0
  return Cs((comment + foreign + quoted('"') + quoted("'") + word^1 + P(1))^0):match(source)
end

-- Bend restricts import paths and derives namespaces from the scratch input's
-- directory. Stage local modules under plain names, keeping their alias and
-- canonical identity even when the original checkout is at an unusual path.
local function stage_imports(source, origin, scratch, cleanup)
  local staged = {}
  local rewrite

  local function stage(path, parent)
    local real, err = executor.evalex('realpath', {'-e', '--', fs.abspath(path, parent)})
    if not real then error(err, 0) end
    real = real:gsub('\n$', '')
    if staged[real] then return staged[real] end
    local name = 'module_' .. stringer.hash(real) .. '.bend'
    local target = fs.join(scratch, name)
    local content = assert(fs.readfile(real))
    staged[real] = './' .. name
    cleanup[#cleanup + 1] = target
    assert(fs.writefile(target, rewrite(content, fs.dirname(real))))
    return staged[real]
  end

  function rewrite(code, parent)
    local header = true
    local lines = {}
    for line in (code .. '\n'):gmatch('([^\n]*)\n') do
      if header and not line:match('^%s*$') and not line:match('^%s*#') then
        local lead, path, suffix = line:match('^(%s*import%s+)(%S+)(%s+as%s+.*)$')
        if path and path:sub(-5) == '.bend' and not path:match('^0x[0-9a-f]+/') and
            not path:match('^[^/]+@[^/]+/') then
          line = lead .. stage(path, parent) .. suffix
        elseif not line:match('^%s*import%s') then
          header = false
        end
      end
      lines[#lines + 1] = line
    end
    return rebase_foreign(table.concat(lines, '\n'), parent, scratch)
  end

  return rewrite(source, origin)
end

local function enable_io(code)
  local loop_start = code:find('OUTLINE void io_loop(u64* H) {', 1, true)
  local _, run_end = code:find('  io_spawn(m);', loop_start or #code, true)
  if not run_end then error('unsupported Bend2 IO loop format', 0) end
  return code:sub(1, loop_start - 1) ..
    'static void nelua_bend_io_loop(Env e, Term m) {\n  io_spawn(m);' ..
    code:sub(run_end + 1)
end

local function enable_cuda(code)
  if code:match('\n#define BANGS 0\n') then
    error('a Bend2 GPU block needs a reachable Bend ! call', 0)
  end
  local changed
  code, changed = code:gsub('  u64   key = gpu_hash%(%);.-(  if %(cuModuleLoadData)', '%1', 1)
  if changed ~= 1 then error('unsupported Bend2 CUDA compiler format', 0) end
  code, changed = code:gsub('(  free%(bin%);\n)  return ok;', '%1  return true;', 1)
  if changed ~= 1 then error('unsupported Bend2 CUDA result format', 0) end

  local cuda = code:find('\n#elif BEND_CUDA\n\nstatic u64 gpu_hash', 1, true)
  local load_start = cuda and code:find('static void gpu_load(u64 bytes) {', cuda, true)
  local load_rest = load_start and code:find('  if (cuModuleGetFunction', load_start, true)
  if not load_rest then error('unsupported Bend2 CUDA loader format', 0) end
  code = code:sub(1, load_start - 1) ..
    'static void gpu_load(u64 bytes) {\n  (void)bytes;\n  gpu_make(NULL);\n' .. code:sub(load_rest)
  code = code:gsub('  setenv%("CUDA_DEVICE_MAX_CONNECTIONS", "1", 0%);\n', '', 1)
  return '#ifndef __CUDACC_RTC__\n#define BEND_CUDA 1\n#endif\n' .. code
end

-- The pinned Bend runtime calls these CUDA APIs. Expand CUDA header aliases
-- before taking each symbol name so dlsym uses the ABI declared by the SDK.
local cuda_symbols = {
  'cuInit', 'cuCtxGetCurrent', 'cuCtxSetCurrent', 'cuCtxSynchronize',
  'cuDeviceGet', 'cuDeviceGetAttribute', 'cuDevicePrimaryCtxRelease',
  'cuDevicePrimaryCtxRetain', 'cuDeviceTotalMem', 'cuGetErrorName',
  'cuLaunchKernel', 'cuMemAdvise', 'cuMemAllocManaged', 'cuMemcpyHtoD',
  'cuMemsetD8', 'cuModuleGetFunction', 'cuModuleGetGlobal', 'cuModuleLoadData',
  'nvrtcCompileProgram', 'nvrtcCreateProgram', 'nvrtcDestroyProgram', 'nvrtcGetCUBIN',
  'nvrtcGetCUBINSize', 'nvrtcGetProgramLog', 'nvrtcGetProgramLogSize',
}

local function dynamic_cuda(code)
  local declarations, loads, aliases = {}, {}, {}
  for _, name in ipairs(cuda_symbols) do
    local slot = 'nelua_bend_' .. name
    local lib = name:sub(1, 2) == 'cu' and 'driver' or 'nvrtc'
    declarations[#declarations + 1] = ('static __typeof__(&%s) %s;'):format(name, slot)
    loads[#loads + 1] = ('  BEND_LOAD(%s, %s, %s);'):format(slot, lib, name)
    aliases[#aliases + 1] = ('#undef %s\n#define %s %s'):format(name, name, slot)
  end
  local loader = table.concat(declarations, '\n') .. '\n' .. [[
#define BEND_STRING_(x) #x
#define BEND_STRING(x) BEND_STRING_(x)
#define BEND_LOAD(slot, library, name) do { \
  slot = (__typeof__(slot))dlsym(library, BEND_STRING(name)); \
  if (slot == NULL) goto unavailable; \
} while (0)

static bool nelua_bend_load_cuda(void) {
  void *driver = dlopen("libcuda.so.1", RTLD_NOW | RTLD_LOCAL);
  if (driver == NULL) return false;
#if CUDA_VERSION >= 13000
  void *nvrtc = dlopen("libnvrtc.so.13", RTLD_NOW | RTLD_LOCAL);
#else
  void *nvrtc = dlopen("libnvrtc.so.12", RTLD_NOW | RTLD_LOCAL);
#endif
  if (nvrtc == NULL) goto unavailable;
]] .. table.concat(loads, '\n') .. '\n' .. [[
  return true;

unavailable:
  if (nvrtc != NULL) dlclose(nvrtc);
  dlclose(driver);
  return false;
}
#undef BEND_LOAD
#undef BEND_STRING
#undef BEND_STRING_
]] .. table.concat(aliases, '\n')
  local header = '#include <nvrtc.h>\n'
  local at = assert(code:find(header, 1, true))
  at = at + #header
  return code:sub(1, at - 1) .. '#include <dlfcn.h>\n' .. loader .. '\n' .. code:sub(at)
end

local c_auto_policy = [[
enum { BEND_AUTO, BEND_CPU, BEND_GPU };
static int nelua_bend_device;
static pthread_once_t nelua_bend_policy_once = PTHREAD_ONCE_INIT;

static void nelua_bend_read_policy(void) {
  const char *mode = getenv("NELUA_BEND_DEVICE");
  if (mode == NULL || !*mode || strcmp(mode, "auto") == 0) return;
  if (strcmp(mode, "cpu") == 0) nelua_bend_device = BEND_CPU;
  else if (strcmp(mode, "gpu") == 0) nelua_bend_device = BEND_GPU;
  else err_fail("NELUA_BEND_DEVICE must be auto, cpu, or gpu");
}

static bool nelua_bend_want_cuda(bool large) {
  if (pthread_once(&nelua_bend_policy_once, nelua_bend_read_policy) != 0) abort();
  return nelua_bend_device == BEND_GPU || (nelua_bend_device == BEND_AUTO && large);
}
]]

local function auto_sources(code, gpu, routes, prefix)
  local cpu_macros, undo, dispatch = {}, {}, {c_auto_policy}
  local ready = prefix .. '_cuda_ready'
  if gpu then
    dispatch[#dispatch + 1] = ('extern int %s(void);'):format(ready)
    gpu = '#define NELUA_BEND_AUTO 1\n#define NELUA_BEND_CUDA_READY ' .. ready .. '\n' ..
      dynamic_cuda(enable_cuda(gpu))
  end
  for _, route in ipairs(routes) do
    local symbol = route.symbol
    cpu_macros[#cpu_macros + 1] = '#define ' .. symbol .. ' ' .. symbol .. '_cpu'
    undo[#undo + 1] = '#undef ' .. symbol
    if gpu then
      dispatch[#dispatch + 1] = ('extern %s %s_gpu(%s);'):format(route.result, symbol, route.params)
    end
    dispatch[#dispatch + 1] = ('%s %s(%s) {'):format(route.result, symbol, route.params)
    dispatch[#dispatch + 1] = ('  if (nelua_bend_want_cuda(%s >= %sull)) {'):format(
      route.measure, route.cutoff)
    if gpu then
      dispatch[#dispatch + 1] = ('    if (%s()) return %s_gpu(%s);'):format(
        ready, symbol, route.args)
    end
    dispatch[#dispatch + 1] = [[
    if (nelua_bend_device == BEND_GPU) err_fail("Bend2 auto: CUDA is unavailable");
  }]]
    dispatch[#dispatch + 1] = ('  return %s_cpu(%s);\n}'):format(symbol, route.args)
  end

  local cpu = table.concat(cpu_macros, '\n') .. '\n' .. code ..
    table.concat(undo, '\n') .. '\n' .. table.concat(dispatch, '\n') .. '\n'
  return cpu, gpu
end

local function cuda_toolkit(link_directly)
  for _, root in ipairs{os.getenv('CUDA_HOME') or '', os.getenv('CUDA_PATH') or '',
    '/usr/local/cuda', '/opt/cuda'} do
    local include = fs.join(root, 'include')
    if root ~= '' and fs.isfile(fs.join(include, 'cuda.h')) and fs.isfile(fs.join(include, 'nvrtc.h')) then
      if not link_directly then return include end
      for _, lib in ipairs{'lib64', 'lib'} do
        local dir = fs.join(root, lib)
        if fs.isfile(fs.join(dir, 'libnvrtc.so')) then
          return include, dir
        end
      end
    end
  end
end

local c_io = [[
static bool nelua_bend_io_initialized;
static bool nelua_bend_io_done;
static Term nelua_bend_io_result;

static Term nelua_bend_run_io(Env e, Term action) {
  if (!nelua_bend_io_initialized) {
    if (pipe2(io_wake_fd, O_CLOEXEC) || fcntl(io_wake_fd[0], F_SETFL, O_NONBLOCK))
      err_fail("the embedded event loop failed to open");
    nelua_bend_io_initialized = true;
  }
  nelua_bend_io_done = false;
  nelua_bend_io_loop(e, action);
  io_sync();
  if (!nelua_bend_io_done) err_fail("the embedded IO call returned no result");
  return nelua_bend_io_result;
}
]]

local c_u32s = [[
static Term nelua_bend_pack_u32s(Env e, const uint32_t *data, size_t count) {
  Term list = term_pak(CID(Nil), 0);
  while (count > 0) list = io_node(e, CID(Con), data[--count], list);
  return list;
}

static uint32_t *nelua_bend_unpack_u32s(Env e, Term list, u64 *len) {
  size_t n = 0, capacity = 0;
  uint32_t *data = NULL;
  while (term_aux(list) == CID(Con)) {
    if (n == capacity) {
      if (capacity > SIZE_MAX / 2 / sizeof(*data))
        err_fail("Bend2 vector exceeds the host size limit");
      capacity = capacity ? capacity * 2 : 16;
      data = io_mem(realloc(data, capacity * sizeof(*data)));
    }
    Term fields[2];
    spare_free(e, cls_fit(2), ctr_take(e, list, 2, fields));
    data[n++] = (uint32_t)fields[0];
    list = fields[1];
  }
  *len = n;
  return data;
}
]]

local function compile(directory, source, bridge, origin, has_io, gpu, cleanup)
  local input = fs.join(directory, 'inline.bend')
  local output = fs.join(directory, 'inline.c')
  -- Bend resolves the input file's symlinks before opening its imports.
  local resolved, err = executor.evalex('realpath', {'-e', '--', origin, directory})
  if not resolved then error(err, 0) end
  local real_origin, real_scratch = resolved:match('^([^\n]+)\n([^\n]+)\n$')
  if not real_origin then error('unsupported newline in Bend2 source or scratch path', 0) end
  local user_source = stage_imports(source[1], real_origin, real_scratch, cleanup)
  assert(fs.writefile(input, user_source .. '\n' .. table.concat(source, '\n', 2)))
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
  library = library:gsub('\nTerm ([A-Za-z_][A-Za-z_0-9]*_run%()', '\nstatic Term %1')
  if has_io then library = enable_io(library) end
  if gpu then library = enable_cuda(library) end
  return library .. '#endif\n'
end

local function generate(source, bridge, prefix, origin, has_io, mode, cuda_include, routes, gpu_bridge)
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
  local cleanup = {}
  local staging
  local function cache_source(code)
    local cached = fs.join(cache, prefix .. '_' .. stringer.hash(code) .. '.c')
    if fs.readfile(cached) ~= code then
      staging = assert(executor.evalex('mktemp', {fs.join(cache, '.bend2.XXXXXXXX')})):gsub('\n$', '')
      assert(fs.writefile(staging, code))
      assert(os.rename(staging, cached))
      staging = nil
    end
    return cached
  end

  local success, path = pcall(function()
    local code = compile(directory, source, bridge, origin, has_io, mode == 'gpu', cleanup)
    local gpu_code
    if #routes > 0 then
      if cuda_include and not code:match('\n#define BANGS 0\n') then
        -- Only pure, cutoff-eligible exports belong in the device translation unit.
        gpu_code = compile(directory, source, table.concat(gpu_bridge, '\n'), origin, false, false, cleanup)
        if gpu_code:match('\n#define BANGS 0\n') then gpu_code = nil end
      end
      code, gpu_code = auto_sources(code, gpu_code, routes, prefix)
    end
    return {cpu = cache_source(code), gpu = gpu_code and cache_source(gpu_code)}
  end)
  if staging then os.remove(staging) end
  for _, file in ipairs(cleanup) do os.remove(file) end
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
                      `:` ('io' WORDSKIP $true / $false) NAME SKIP
                      (Bend2Cutoff / $false) |}
    Bend2Cutoff <-- 'gpu_at' WORDSKIP `(` {[0-9]+} SKIP `,` {[0-9]+} SKIP `)`
  ]])
  syntax.statement("'bend2' WORDSKIP ('gpu' WORDSKIP $'gpu' / 'auto' WORDSKIP $'auto' / $'cpu') `(` {| Bend2Export (`,` @Bend2Export)* |} @`)` @STRING_LONG SKIP",
    function(mode, exports, code)
      if config.generator ~= 'c' then syntax.raise('Bend2 requires the Nelua C backend') end

      local cuda_include, cuda_lib
      if mode ~= 'cpu' then
        cuda_include, cuda_lib = cuda_toolkit(mode == 'gpu')
        if mode == 'gpu' and not cuda_include then syntax.raise('Bend2 GPU requires CUDA; set CUDA_HOME to the toolkit') end
      end
      local signature, routes = {}, {}
      local names = {}
      local has_io, has_buffer_result, has_u32s, gpu_has_u32s
      for _, export in ipairs(exports) do
        local name, params, is_io, result, arg_index, cutoff = table.unpack(export)
        if not name:match('^[A-Za-z][A-Za-z0-9_]*$') or names[name] then
          syntax.raise('invalid or duplicate Bend2 export %q', name)
        end
        names[name] = true
        if not types[result] or (result == 'void' and not is_io) then
          syntax.raise('unsupported Bend2 result type %q for %s', result, name)
        end
        for _, param in ipairs(params) do
          has_u32s = has_u32s or param == 'u32s'
          if not types[param] or param == 'void' then
            syntax.raise('unsupported Bend2 parameter type %q', param)
          end
        end
        if arg_index then
          arg_index, cutoff = tonumber(arg_index), tonumber(cutoff)
          if mode ~= 'auto' or is_io then
            syntax.raise('gpu_at is available on pure Bend2 auto exports')
          end
          local measure = params[arg_index]
          if not measure or (measure ~= 'uint32' and not types[measure].input) then
            syntax.raise('gpu_at must name a uint32 or buffer parameter position')
          end
          if not math.tointeger(cutoff) or cutoff > 4294967295 then
            syntax.raise('gpu_at minimum must fit in uint32')
          end
          export[5], export[6] = arg_index, cutoff
          if result == 'u32s' then gpu_has_u32s = true end
          for _, param in ipairs(params) do
            if param == 'u32s' then gpu_has_u32s = true end
          end
        end
        has_io = has_io or is_io
        has_buffer_result = has_buffer_result or types[result].output
        has_u32s = has_u32s or result == 'u32s'
        signature[#signature + 1] = name .. '(' .. table.concat(params, ',') .. '):' ..
          (is_io and 'io ' or '') .. result .. (arg_index and ('@%d=%d'):format(arg_index, cutoff) or '')
      end

      local filename = syntax.filename()
      local origin = filename and fs.dirname(fs.abspath(filename)) or fs.curdir()
      local prefix = 'nelua_bend2_' .. stringer.hash(
        origin .. '\n' .. mode .. '\n' .. table.concat(signature, ',') .. '\n' .. code)
      local source = {code, ''}
      local bridge = {c_prelude}
      local gpu_bridge = {c_prelude}
      if gpu_has_u32s then gpu_bridge[#gpu_bridge + 1] = c_u32s end
      local declarations = {}
      local release
      if has_io then bridge[#bridge + 1] = c_io end
      if has_u32s then
        bridge[#bridge + 1] = c_u32s
        declarations[#declarations + 1] = "require 'vector'"
      end
      if has_buffer_result then
        release = syntax.gensym('bend2_free')
        declarations[#declarations + 1] = [[
require 'string'
require 'memory'
]] .. ('local function %s(p: pointer) <cimport "free", cinclude "<stdlib.h>"> end'):format(release)
      end

      for index, export in ipairs(exports) do
        local name, params, is_io, result, arg_index, cutoff = table.unpack(export)
        local result_type = types[result]
        local entry = prefix .. '_entry_' .. index
        local symbol = prefix .. '_call_' .. index
        local fid = 'FID(' .. entry .. ')'
        local bend_params, c_params, nelua_params, native_params = {}, {}, {}, {}
        local args, native_args, c_args, writes = {}, {}, {}, {}
        local wrap = result_type.output ~= nil

        for i, param in ipairs(params) do
          local arg = 'a' .. i
          local t = types[param]
          args[i] = arg
          bend_params[i] = arg .. ': ' .. t.bend
          nelua_params[i] = arg .. ': ' .. (t.nelua or param)
          local packed
          if t.input then
            wrap = true
            c_params[i] = 'void *' .. arg .. ', size_t ' .. arg .. '_size'
            c_args[i] = arg .. ', ' .. arg .. '_size'
            native_params[i] = arg .. ': pointer, ' .. arg .. '_size: usize'
            local data = param == 'u32s' and '.data.data' or '.data'
            native_args[i] = arg .. data .. ', ' .. arg .. '.size'
            packed = ('%s(e, %s, %s_size)'):format(t.input, arg, arg)
          else
            c_params[i] = t.c .. ' ' .. arg
            c_args[i] = arg
            native_params[i] = nelua_params[i]
            native_args[i] = arg
            packed = t.pack:format(arg)
          end
          writes[i] = ('  e.mem[task + %d] = %s;'):format(i - 1, packed)
        end

        local bend_call = ('%s(%s)'):format(name, table.concat(args, ', '))
        local bend_result = result_type.bend
        if is_io then
          local capture = entry .. '_capture'
          source[#source + 1] = ('def %s(v: %s) -> IO(Unit):\n  import "./bridge.c"\n'):format(
            capture, bend_result)
          bend_call = ('IO.bind(%s, Unit, %s, v => %s(v))'):format(
            bend_result, bend_call, capture)
          bend_result = 'IO(Unit)'
          bridge[#bridge + 1] = ([[
static Term %s_run(Env e, Term *f, IoWork *w) {
  (void)e;
  (void)w;
  nelua_bend_io_done = true;
  nelua_bend_io_result = f[0];
  return term_pak(CID(Unit), 0);
}

static void __attribute__((constructor)) %s_use(void) {
  io_eff(CID(%s), %s_run);
}
]]):format(capture, capture, capture, capture)
        end
        source[#source + 1] = ('def %s(%s) -> %s:\n  %s\n'):format(
          entry, table.concat(bend_params, ', '), bend_result, bend_call)

        local expression = ('corpus_eval(e.mem, term_tsk(%s, task))'):format(fid)
        if is_io then expression = 'nelua_bend_run_io(e, ' .. expression .. ')' end
        local body = {'  nelua_bend_enter();',
          '  Env e = { nelua_bend_heap, ALC[0] };',
          ('  u64 task = task_node(e, %s, TERM_HOLE, 0, 0);'):format(fid)}
        for _, write in ipairs(writes) do body[#body + 1] = write end
        body[#body + 1] = '  Term value = ' .. expression .. ';'

        local finish = ''
        local native_result = result
        if result_type.output then
          c_params[#c_params + 1] = 'size_t *out_size'
          c_args[#c_args + 1] = 'out_size'
          native_params[#native_params + 1] = 'out_size: *usize'
          native_args[#native_args + 1] = '&out_size'
          native_result = 'pointer'
          body[#body + 1] = '  u64 count = 0;'
          body[#body + 1] = ('  void *out = %s(e, value, &count%s);'):format(
            result_type.output, result_type.cons or '')
          if result == 'bytes' then
            body[#body + 1] = '  if (out == NULL) err_fail("Bend2 byte result contains a value above 255");'
          end
          body[#body + 1] = '  *out_size = (size_t)count;'
          finish = '\n  return out;'
        elseif result == 'void' then
          body[#body + 1] = '  term_drop(e, value);'
        else
          finish = '\n  return ' .. result_type.unpack:format('value') .. ';'
        end
        body[#body + 1] = '  nelua_bend_leave();'
        local parameters = #c_params == 0 and 'void' or table.concat(c_params, ', ')
        local function_format = '%s %s(%s) {\n%s%s\n}\n'
        local body_code = table.concat(body, '\n')
        bridge[#bridge + 1] = function_format:format(result_type.c, symbol, parameters, body_code, finish)
        if arg_index then
          gpu_bridge[#gpu_bridge + 1] = function_format:format(
            result_type.c, symbol .. '_gpu', parameters, body_code, finish)
          routes[#routes + 1] = {
            symbol = symbol, result = result_type.c, params = parameters,
            args = table.concat(c_args, ', '),
            measure = 'a' .. arg_index .. (types[params[arg_index]].input and '_size' or ''),
            cutoff = cutoff,
          }
        end

        local native_name = wrap and syntax.gensym('bend2_call') or name
        declarations[#declarations + 1] =
          ('local function %s(%s): %s <cimport %q> end'):format(
            native_name, table.concat(native_params, ', '), native_result, symbol)
        if wrap then
          local wrapper = ('local function %s(%s): %s\n'):format(
            name, table.concat(nelua_params, ', '), result_type.nelua or result)
          local call = native_name .. '(' .. table.concat(native_args, ', ') .. ')'
          if result_type.output then
            wrapper = wrapper .. ('  local out_size: usize\n  local data = %s\n'):format(call)
            if result == 'u32s' then
              wrapper = wrapper .. [[
  local result: vector(uint32)
  if out_size > 0 then
    result:reserve(out_size)
    result.size = out_size
    memory.copy(result.data.data, data, out_size * 4)
  end
]]
            else
              wrapper = wrapper .. [[
  local result: string
  if out_size > 0 then
    result = string.create(out_size)
    memory.copy(result.data, data, out_size)
  end
]]
            end
            wrapper = wrapper .. ('  %s(data)\n  return result\n'):format(release)
          else
            wrapper = wrapper .. (result == 'void' and '  ' or '  return ') .. call .. '\n'
          end
          declarations[#declarations + 1] = wrapper .. 'end'
        end
      end

      source[#source + 1] = [[
def nelua_bridge_anchor() -> IO(Unit):
  import "./bridge.c"

def main() -> IO(Unit):
  nelua_bridge_anchor()
]]
      local paths = generate(source, table.concat(bridge, '\n'),
        prefix, origin, has_io, mode, cuda_include, routes, gpu_bridge)
      local directives = ('## cfile(%q)\n## linklib "pthread"\n## linklib "m"\n'):format(paths.cpu)
      if paths.gpu then
        directives = directives .. ('## cfile(%q)\n## cincdir(%q)\n## linklib "dl"\n'):format(
          paths.gpu, cuda_include)
      elseif mode == 'gpu' then
        directives = directives ..
          ('## cincdir(%q)\n## linkdir(%q)\n## linklib "cuda"\n## linklib "nvrtc"\n'):format(
            cuda_include, cuda_lib)
      end
      return syntax.block(directives .. table.concat(declarations, '\n'))
    end)
end
