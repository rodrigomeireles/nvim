-- Make hover docs readable.
--
-- Python docstrings in the wild are reStructuredText, but pyright hands nvim a
-- "markdown" blob that still carries the raw RST field lists (`:param x:` /
-- `:type x:` / `:rtype:`) plus its own transport artefacts: every `_` comes
-- back escaped as `\_`, and docstring indentation is re-encoded as runs of
-- `&nbsp;`. Markdown has no idea what to do with any of that, so the float
-- renders as a wall of `:param`/`:type` pairs with visible backslashes.
--
-- This rewrites those field lists into real markdown lists before the float is
-- drawn. It is a no-op on docs that contain no RST fields, so it is safe to
-- leave on for every server.
--
-- Hook point: nvim 0.12's `vim.lsp.buf.hover` assembles its contents inline and
-- never calls `vim.lsp.handlers['textDocument/hover']`, so the handler override
-- that used to work no longer does. The remaining choke point is
-- `vim.lsp.util.open_floating_preview`, which every doc float funnels through.

local M = {}

local NBSP = '&nbsp;'

-- Only these field names get restructured. Anything else (`:math:`, a stray
-- `:foo:` in prose) is left verbatim rather than risking a mangle.
local KNOWN = {
  param = 'param',
  parameter = 'param',
  arg = 'param',
  argument = 'param',
  key = 'param',
  keyword = 'param',
  kwarg = 'param',
  type = 'type',
  kwtype = 'type',
  ['return'] = 'return',
  returns = 'return',
  rtype = 'rtype',
  yield = 'yield',
  yields = 'yield',
  ytype = 'ytype',
  raise = 'raise',
  raises = 'raise',
  except = 'raise',
  exception = 'raise',
  var = 'var',
  ivar = 'var',
  cvar = 'var',
  vartype = 'vartype',
  meta = 'meta', -- sphinx bookkeeping (`:meta private:`) -> dropped
}

-- RST admonitions survive the trip too. Their indented body is left alone (it
-- reads fine once `&nbsp;` renders as a space); only the marker line is turned
-- into something markdown knows.
local ADMONITIONS = {
  note = 'Note',
  warning = 'Warning',
  caution = 'Caution',
  important = 'Important',
  attention = 'Attention',
  tip = 'Tip',
  seealso = 'See also',
  deprecated = 'Deprecated',
  versionadded = 'New in',
  versionchanged = 'Changed in',
}

-- pyright escapes markdown punctuation inside docstrings. Backslash escapes are
-- inert inside a code span, so anything we wrap in backticks has to be
-- unescaped by hand; elsewhere we only undo `\_`, which is pure noise in
-- snake_case-heavy Python (the rest keeps protecting the markdown).
local function uncode(s)
  return (s:gsub('\\(%p)', '%1'))
end

local function untick(s)
  return (s:gsub('\\_', '_'))
end

local function plain(s)
  return (s:gsub(NBSP, ' '):gsub('%s+$', '')) -- also drops the trailing hard break
end

--- Split the field block out of `lines`, if there is one.
--- @return table[] fields, integer? first, integer? last
local function scan(lines)
  local fields, first, last = {}, nil, nil
  local fence, prev_blank = false, true

  for i, raw in ipairs(lines) do
    local s = plain(raw)
    local t = vim.trim(s)

    if t:match '^```' then
      fence = not fence
    elseif not fence then
      local tag, arg, text = t:match '^:(%a+)%s*([^:]*):%s?(.*)$'
      tag = tag and KNOWN[tag:lower()]

      if tag then
        first = first or i
        last = i
        fields[#fields + 1] = { tag = tag, arg = vim.trim(arg), text = vim.trim(text) }
      elseif first and t ~= '' then
        -- A field's description can spill onto following lines. RST indents
        -- them, but pyright soft-joins some without any indent at all, so also
        -- accept an unindented line that directly follows a non-blank one.
        -- A blank line *and* no indent means real prose resumed: stop there and
        -- leave everything after it untouched.
        local prev = fields[#fields]
        if prev and (not prev_blank or s:match '^%s') then
          prev.text = vim.trim(prev.text .. ' ' .. t)
          last = i
        else
          break
        end
      end
    end

    prev_blank = t == ''
  end

  return fields, first, last
end

local function as_type(s)
  s = vim.trim(s or '')
  if s == '' then
    return nil
  end
  return '*' .. untick(s) .. '*'
end

local function bullet(name, ty, desc)
  local parts = { '- `' .. uncode(name) .. '`' }
  if ty then
    parts[#parts + 1] = ty
  end
  if desc and desc ~= '' then
    parts[#parts + 1] = '— ' .. untick(desc)
  end
  return table.concat(parts, ' ')
end

--- @param fields table[]
--- @return string[]
local function render(fields)
  local params, param_order = {}, {}
  local attrs, attr_order = {}, {}
  local raises = {}
  local ret, rtype, yield, ytype

  local function slot(map, order, name)
    if not map[name] then
      map[name] = { name = name }
      order[#order + 1] = name
    end
    return map[name]
  end

  for _, f in ipairs(fields) do
    if f.tag == 'param' then
      -- sphinx also allows the type inline: `:param str filename: ...`
      local ty, name = f.arg:match '^(%S+)%s+(%S+)$'
      local e = slot(params, param_order, name or f.arg)
      e.desc = f.text
      e.type = e.type or ty
    elseif f.tag == 'type' then
      slot(params, param_order, f.arg).type = f.text
    elseif f.tag == 'var' then
      slot(attrs, attr_order, f.arg).desc = f.text
    elseif f.tag == 'vartype' then
      slot(attrs, attr_order, f.arg).type = f.text
    elseif f.tag == 'raise' then
      raises[#raises + 1] = { name = f.arg, desc = f.text }
    elseif f.tag == 'return' then
      ret = f.text
    elseif f.tag == 'rtype' then
      rtype = f.text
    elseif f.tag == 'yield' then
      yield = f.text
    elseif f.tag == 'ytype' then
      ytype = f.text
    end
  end

  local out = {}
  local function heading(title)
    if #out > 0 then
      out[#out + 1] = ''
    end
    out[#out + 1] = '**' .. title .. '**'
    out[#out + 1] = ''
  end

  local function listing(title, map, order)
    if #order == 0 then
      return
    end
    heading(title)
    for _, name in ipairs(order) do
      local e = map[name]
      out[#out + 1] = bullet(e.name, as_type(e.type), e.desc)
    end
  end

  local function oneline(title, ty, desc)
    if not ty and (not desc or desc == '') then
      return
    end
    if #out > 0 then
      out[#out + 1] = ''
    end
    local parts = { '**' .. title .. '**' }
    if ty then
      parts[#parts + 1] = ty
    end
    if desc and desc ~= '' then
      parts[#parts + 1] = '— ' .. untick(desc)
    end
    out[#out + 1] = table.concat(parts, ' ')
  end

  listing('Parameters', params, param_order)
  listing('Attributes', attrs, attr_order)
  oneline('Returns', as_type(rtype), ret)
  oneline('Yields', as_type(ytype), yield)

  if #raises > 0 then
    heading 'Raises'
    for _, r in ipairs(raises) do
      out[#out + 1] = bullet(r.name, nil, r.desc)
    end
  end

  return out
end

--- Turn `.. note:: text` marker lines into blockquotes.
--- @param lines string[]
--- @return string[]
local function admonitions(lines)
  local out, fence = {}, false
  for i, raw in ipairs(lines) do
    local t = vim.trim(plain(raw))
    local quoted
    if t:match '^```' then
      fence = not fence
    elseif not fence then
      local name, arg = t:match '^%.%.%s+([%a_-]+)::%s*(.*)$'
      local label = name and ADMONITIONS[name:lower()]
      if label then
        arg = vim.trim(arg)
        if name:lower():match '^version' or name:lower() == 'deprecated' then
          quoted = ('> **%s%s**'):format(label, arg ~= '' and ' ' .. arg or '')
        else
          quoted = ('> **%s**%s'):format(label, arg ~= '' and ' — ' .. untick(arg) or '')
        end
      end
    end

    if quoted then
      out[#out + 1] = quoted
      -- without a blank line the next paragraph gets swallowed into the quote
      -- by markdown's lazy continuation
      if vim.trim(plain(lines[i + 1] or '')) ~= '' then
        out[#out + 1] = ''
      end
    else
      out[#out + 1] = raw
    end
  end
  return out
end

--- @param lines string[]
--- @return string[]
function M.rewrite(lines)
  local fields, first, last = scan(lines)
  if not first then
    return admonitions(lines)
  end

  local body = render(fields)
  if #body == 0 then
    return admonitions(lines)
  end

  local out = {}
  for i = 1, first - 1 do
    out[#out + 1] = lines[i]
  end
  if #out > 0 and vim.trim(out[#out]) ~= '' then
    out[#out + 1] = ''
  end
  vim.list_extend(out, body)
  for i = last + 1, #lines do
    out[#out + 1] = lines[i]
  end
  return admonitions(out)
end

local patched = false

function M.setup()
  if patched then
    return
  end
  patched = true

  local open = vim.lsp.util.open_floating_preview
  --- @diagnostic disable-next-line: duplicate-set-field
  vim.lsp.util.open_floating_preview = function(contents, syntax, opts)
    if syntax == 'markdown' and type(contents) == 'table' then
      local ok, rewritten = pcall(M.rewrite, vim.split(table.concat(contents, '\n'), '\n'))
      if ok then
        contents = rewritten
      end
    end
    return open(contents, syntax, opts)
  end
end

return M
