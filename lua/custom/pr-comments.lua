-- Thin layer over the `gh` CLI + octo.nvim for two things octo doesn't do:
--   * a flat picker of every comment on the current PR (review + conversation)
--   * pinning a comment to revisit later ("what am I working on right now"),
--     including the comment under the cursor inside an octo PR buffer.
--
-- Commands/keymaps are registered in lua/custom/plugins/octo.lua; this module is
-- required lazily the first time one of them fires.
local M = {}

local function notify(msg, level)
  vim.notify('[pr] ' .. msg, level or vim.log.levels.INFO)
end

local function trim(s)
  return (tostring(s or '')):gsub('%s+$', '')
end

--- Resolve a repo-relative path to something editable (cwd first, then git root).
local function resolve(path)
  if not path then
    return nil
  end
  if vim.uv.fs_stat(path) then
    return path
  end
  local root = vim.fs.root(0, '.git')
  if root then
    local p = vim.fs.joinpath(root, path)
    if vim.uv.fs_stat(p) then
      return p
    end
  end
  return nil
end

----------------------------------------------------------- octo buffer access
-- If the current buffer is an octo PR buffer, describe it without touching gh.
-- Returns { number, owner, repo, url } or nil.
local function pr_from_octo_buffer()
  local ok, octo_utils = pcall(require, 'octo.utils')
  if not ok then
    return nil
  end
  local b = octo_utils.get_current_buffer()
  if not b or not b.number or not b.repo then
    return nil
  end
  if b.kind ~= 'pull' and b.kind ~= 'reviewthread' then
    return nil
  end
  local owner, repo = tostring(b.repo):match '([^/]+)/(.+)'
  return { number = b.number, owner = owner, repo = repo, url = b.node and b.node.url }
end

-- The comment under the cursor in an octo buffer, normalized to a pin entry.
-- Returns entry or nil (+ notifies why). `path`/`line` only for review comments.
local function comment_at_cursor()
  local ok, octo_utils = pcall(require, 'octo.utils')
  if not ok then
    notify('octo is not available', vim.log.levels.WARN)
    return nil
  end
  local b = octo_utils.get_current_buffer()
  if not b then
    notify('not in an octo buffer', vim.log.levels.WARN)
    return nil
  end
  local comment = b.get_comment_at_cursor and b:get_comment_at_cursor()
  if not comment then
    notify('put the cursor on a comment first', vim.log.levels.WARN)
    return nil
  end
  local thread = b.get_thread_at_cursor and b:get_thread_at_cursor() or nil
  local path = comment.path or (thread and thread.path)
  local line = comment.snippetStartLine or (thread and thread.line)
  return {
    body = comment.body or '',
    path = path,
    line = path and (line or 1) or nil,
    user = (comment.author ~= nil and comment.author ~= '') and comment.author or nil,
    url = b.node and b.node.url, -- PR url (octo metadata lacks a per-comment url)
    pr = b.number,
    repo = b.repo,
  }
end

------------------------------------------------------------------- gh queries
local function gh_json(args, cb)
  vim.system(vim.list_extend({ 'gh' }, args), { text = true }, function(res)
    if res.code ~= 0 then
      return vim.schedule(function()
        cb(nil, trim(res.stderr))
      end)
    end
    local ok, data = pcall(vim.json.decode, res.stdout)
    vim.schedule(function()
      cb((ok and type(data) == 'table') and data or nil)
    end)
  end)
end

-- Resolve the PR for the comment list: prefer the octo buffer, else the branch.
local function current_pr(cb)
  local from_buf = pr_from_octo_buffer()
  if from_buf and from_buf.owner then
    return cb(from_buf)
  end
  gh_json({ 'pr', 'view', '--json', 'number,url' }, function(data, err)
    if not data or not data.number then
      return notify('no open PR here (' .. (err or 'and not in a PR buffer') .. ')', vim.log.levels.WARN)
    end
    local owner, repo = tostring(data.url):match '://[^/]+/([^/]+)/([^/]+)/pull/'
    cb { number = data.number, owner = owner, repo = repo, url = data.url }
  end)
end

-- The repo slug for the pin store: octo buffer first, else gh.
local function current_repo(cb)
  local from_buf = pr_from_octo_buffer()
  if from_buf and from_buf.owner then
    return cb(from_buf.owner .. '/' .. from_buf.repo)
  end
  gh_json({ 'repo', 'view', '--json', 'nameWithOwner' }, function(data, err)
    if not data or not data.nameWithOwner then
      return notify('not a GitHub repo (' .. (err or '?') .. ')', vim.log.levels.WARN)
    end
    cb(data.nameWithOwner)
  end)
end

-- All comments on the PR: review (file-anchored) + conversation (issue) comments.
local function fetch(pr, cb)
  if not (pr.owner and pr.repo) then
    return notify('could not determine owner/repo', vim.log.levels.ERROR)
  end
  local base = string.format('repos/%s/%s', pr.owner, pr.repo)
  gh_json({ 'api', base .. '/pulls/' .. pr.number .. '/comments', '--paginate' }, function(review)
    gh_json({ 'api', base .. '/issues/' .. pr.number .. '/comments', '--paginate' }, function(conv)
      local out = {}
      for _, c in ipairs(review or {}) do
        out[#out + 1] = {
          path = c.path,
          line = c.line or c.original_line or c.original_start_line or 1,
          body = c.body or '',
          user = (c.user and c.user.login) or '?',
          url = c.html_url,
          diff_hunk = c.diff_hunk,
          pr = pr.number,
        }
      end
      for _, c in ipairs(conv or {}) do
        out[#out + 1] = {
          path = nil, -- conversation comment: no file/line
          body = c.body or '',
          user = (c.user and c.user.login) or '?',
          url = c.html_url,
          pr = pr.number,
        }
      end
      if vim.tbl_isempty(out) then
        return notify('PR #' .. pr.number .. ' has no comments')
      end
      cb(out)
    end)
  end)
end

------------------------------------------------------------------ pin storage
local function pin_dir()
  return vim.fs.joinpath(vim.fn.stdpath 'state', 'pr-pins')
end

local function pin_file(slug)
  return vim.fs.joinpath(pin_dir(), (slug:gsub('/', '__')) .. '.json')
end

local function load_pins(slug)
  local f = pin_file(slug)
  if vim.fn.filereadable(f) == 0 then
    return {}
  end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(f), '\n'))
  return (ok and type(data) == 'table') and data or {}
end

local function save_pins(slug, pins)
  vim.fn.mkdir(pin_dir(), 'p')
  vim.fn.writefile({ vim.json.encode(pins) }, pin_file(slug))
end

-- Stable-ish identity for dedupe/removal: url, else path:line, else body.
local function pin_key(p)
  return p.url or (p.path and (p.path .. ':' .. tostring(p.line))) or p.body
end

local function add_pin(slug, entry)
  local pins = load_pins(slug)
  for _, p in ipairs(pins) do
    if pin_key(p) == pin_key(entry) then
      return false
    end
  end
  pins[#pins + 1] = entry
  save_pins(slug, pins)
  return true
end

local function remove_pin(slug, entry)
  local kept, removed = {}, false
  for _, p in ipairs(load_pins(slug)) do
    if pin_key(p) == pin_key(entry) then
      removed = true
    else
      kept[#kept + 1] = p
    end
  end
  save_pins(slug, kept)
  return removed
end

--------------------------------------------------------------- shared actions
local function open_thread(e)
  if not e.url then
    return notify('comment has no url', vim.log.levels.WARN)
  end
  vim.cmd('Octo ' .. e.url) -- loads octo on demand; opens the PR/thread context
end

-- Jump to the code a comment refers to; conversation comments fall back to octo.
local function open_at(e)
  if not e.path then
    return open_thread(e)
  end
  local p = resolve(e.path)
  if not p then
    return notify('file not found locally: ' .. e.path .. '  (run :Octo pr checkout)', vim.log.levels.WARN)
  end
  vim.cmd.edit(vim.fn.fnameescape(p))
  pcall(vim.api.nvim_win_set_cursor, 0, { e.line or 1, 0 })
  vim.cmd 'normal! zz'
end

------------------------------------------------------------- telescope picker
local function previewer()
  local previewers = require 'telescope.previewers'
  return previewers.new_buffer_previewer {
    title = 'Comment',
    define_preview = function(self, entry)
      local e = entry.value
      local loc = e.path and (e.path .. ':' .. (e.line or 0)) or '(conversation)'
      local lines = { string.format('@%s  %s', e.user or '?', loc), '' }
      vim.list_extend(lines, vim.split(e.body or '', '\n', { plain = true }))
      if e.diff_hunk and e.diff_hunk ~= '' then
        lines[#lines + 1] = ''
        lines[#lines + 1] = '```diff'
        vim.list_extend(lines, vim.split(e.diff_hunk, '\n', { plain = true }))
        lines[#lines + 1] = '```'
      end
      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      vim.bo[self.state.bufnr].filetype = 'markdown'
    end,
  }
end

--- @param extra table[] list of { lhs, fn, keep? } -- mapped in BOTH insert and
---        normal mode (telescope's <Esc> closes the picker, so normal-mode-only
---        maps are unreachable). keep=true leaves the picker open after the action.
local function pick(title, entries, on_default, extra)
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local actions = require 'telescope.actions'
  local state = require 'telescope.actions.state'

  pickers
    .new({}, {
      prompt_title = title,
      finder = finders.new_table {
        results = entries,
        entry_maker = function(e)
          local loc = e.path and (e.path .. ':' .. (e.line or 0)) or '(conversation)'
          local body = (e.body or ''):gsub('%s+', ' ')
          if #body > 60 then
            body = body:sub(1, 60) .. '…'
          end
          local display = string.format('%s  @%s  %s', loc, e.user or '?', body)
          return { value = e, display = display, ordinal = display }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = previewer(),
      attach_mappings = function(bufnr, map)
        actions.select_default:replace(function()
          local sel = state.get_selected_entry()
          actions.close(bufnr)
          if sel then
            on_default(sel.value)
          end
        end)
        for _, m in ipairs(extra or {}) do
          local handler = function()
            local sel = state.get_selected_entry()
            if not sel then
              return
            end
            if not m.keep then
              actions.close(bufnr)
            end
            m.fn(sel.value, bufnr)
          end
          map('i', m.lhs, handler)
          map('n', m.lhs, handler)
        end
        return true
      end,
    })
    :find()
end

------------------------------------------------------------------- public API
-- List every comment on the current PR (review + conversation).
-- <CR> open file/thread · <C-y> pin · <C-o> open thread
function M.list()
  current_pr(function(pr)
    fetch(pr, function(comments)
      current_repo(function(slug)
        pick('PR #' .. pr.number .. ' comments', comments, open_at, {
          {
            lhs = '<C-y>',
            keep = true,
            fn = function(e)
              notify(add_pin(slug, e) and ('pinned ' .. (e.path and (e.path .. ':' .. e.line) or 'comment')) or 'already pinned')
            end,
          },
          { lhs = '<C-o>', fn = open_thread },
        })
      end)
    end)
  end)
end

-- Pin / unpin the comment under the cursor (octo buffer only).
function M.pin_at_cursor()
  local e = comment_at_cursor()
  if not e then
    return
  end
  local slug = e.repo
  if add_pin(slug, e) then
    notify('pinned ' .. (e.path and (e.path .. ':' .. e.line) or 'conversation comment'))
  else
    notify 'already pinned'
  end
end

function M.unpin_at_cursor()
  local e = comment_at_cursor()
  if not e then
    return
  end
  notify(remove_pin(e.repo, e) and 'unpinned' or 'that comment was not pinned')
end

-- Retrieve pinned comments for this repo.
-- <CR> open file/thread · <C-o> open thread · <C-d> unpin
function M.pins()
  current_repo(function(slug)
    local pins = load_pins(slug)
    if vim.tbl_isempty(pins) then
      return notify('no pinned comments for ' .. slug)
    end
    pick('Pinned comments (' .. slug .. ')', pins, open_at, {
      { lhs = '<C-o>', fn = open_thread },
      {
        lhs = '<C-d>',
        keep = true,
        fn = function(e, bufnr)
          remove_pin(slug, e)
          notify 'unpinned'
          require('telescope.actions').close(bufnr)
          M.pins() -- reopen, refreshed
        end,
      },
    })
  end)
end

return M
