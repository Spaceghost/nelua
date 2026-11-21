--[[
Erroer module

The erroer module is used to format and print pretty error messages.
]]

local colors = require 'nelua.utils.console'.colors
local stringer = require 'nelua.utils.stringer'

local errorer = {}

-- Throw a formatted error message if condition is not met.
function errorer.assertf(cond, message, ...)
  if not cond then
    error(stringer.pformat(message, ...), 2)
  end
  return cond
end

-- Throw a formatted error message.
function errorer.errorf(message, ...)
  error(stringer.pformat(message, ...), 2)
end

-- Generate a pretty error message associated with location from a source.
local function get_source_pos_errmsg(loc, errmsg, errname, stable)
  local srcname, lineno, colno, line, len = loc.srcname, loc.lineno, loc.colno, loc.line, loc.len
  local colbright, colreset, colgreen, colmagenta = colors.bright, colors.reset, colors.green, colors.magenta
  if stable then
    -- Runtime messages are baked into generated programs, so they must not
    -- depend on the compiler's terminal or checkout path.
    colbright, colreset, colgreen, colmagenta = '', '', '', ''
  end
  local lineloc = ''
  if line and colno then
    -- count number of tabs and spaces up to the text
    local ntabs = select(2, line:sub(1,colno-1):gsub('\t',''))
    local nspaces = colno-1-ntabs
    -- generate a line helper to assist showing the exact line column for the error
    local linehelper = string.rep('\t', ntabs)..string.rep(' ', nspaces)..colbright..colgreen..'^'..colreset
    if len and len > 1 then
      -- remove comments and trailing spaces
      local trimmedline = line:sub(1,colno+len-1):gsub('%-%-.*',''):gsub('%s+$','')
      len = math.min(#trimmedline-colno, len)
      linehelper = linehelper..colmagenta..string.rep('~',len)..colreset
    end
    lineloc = '\n'..line..'\n'..linehelper
  end
  local errtraceback = ''
  -- extract traceback from message, to move it to the end of the message
  local tracebackpos = errmsg:find('%s*stack traceback%:')
  if tracebackpos then
    errtraceback = '\n'..errmsg:sub(tracebackpos)
    errmsg = errmsg:sub(1, tracebackpos-1)
  end
  -- choose the color for the message
  local errcolor = colreset
  if stable then
    errcolor = ''
  elseif string.find(errname, 'error', 1, true) then
    errcolor = colors.error
  elseif string.find(errname, 'warning', 1, true) then
    errcolor = colors.warn
  end
  -- generate the error message
  local msg = ''
  if srcname then
    if stable or errcolor == '' then -- no color, or stable generated output
      srcname = srcname:match('[^/\\]+$') -- remove path prefix
    end
    msg = msg..srcname..colbright..':'
    if lineno then
      msg = msg..lineno..':'
      if colno then
        msg = msg..colno..':'
      end
    end
    msg=msg..' '
  end
  msg = msg..errcolor..errname..': '..colreset..colbright..errmsg..colreset..
        lineloc..errtraceback..'\n'
  return msg
end

function errorer.get_pretty_source_pos_errmsg(loc, errmsg, errname)
  -- Runtime diagnostics are embedded into generated programs, so their text
  -- must not depend on the compiler's terminal or checkout path.
  return get_source_pos_errmsg(loc, errmsg, errname, errname == 'runtime error')
end

return errorer
