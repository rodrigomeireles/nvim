-- Thin layer over the `gh` CLI for the two things octo.nvim doesn't do:
--   * a flat Telescope picker of every review comment on the current PR
--   * pinning a comment to revisit later ("what am I working on right now")
-- octo handles the rest (review diff, react/reply/resolve, gx-to-file).
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

------------------------------------------------------------------- gh queries
-- `gh repo view` works in any clone (no PR needed) -> "owner/repo".
local function repo_slug(cb)
  vim.system({ 'gh', 'repo', 'view', '--json', 'nameWithOwner', '-q', '.nameWithOwner' }, { text = true }, function(res)
    if res.code ~= 0 then
      return vim.schedule(function()
        notify('not a GitHub repo: ' .. trim(res.stderr), vim.log.levels.WARN)
      end)
    end
    local slug = trim(res.stdout)
    vim.schedule(function()
      cb(slug)
    end)
  end)
end

-- The PR associated with the current branch.
local function current_pr(cb)
  vim.system({ 'gh', 'pr', 'view', '--json', 'number,url' }, { text = true }, function(res)
    if res.code ~= 0 then
      return vim.schedule(function()
        notify('no open PR for the current branch', vim.log.levels.WARN)
      end)
    end
    local ok, data = pcall(vim.json.decode, res.stdout)
    if not ok or type(data) ~= 'table' or not data.number then
      return vim.schedule(function()
        notify('could not parse PR info from gh', vim.log.levels.ERROR)
      end)
    end
    local owner, repo = tostring(data.url):match '://[^/]+/([^/]+)/([^/]+)/pull/'
    vim.schedule(function()
      cb { number = data.number, owner = owner, repo = repo, url = data.url }
    end)
  end)
end

-- Review (file-anchored) comments. `gh api --paginate` merges array pages into a
-- single flat JSON array, so one decode is enough.
local function fetch(pr, cb)
  if not (pr.owner and pr.repo) then
    return notify('could not determine owner/repo from PR url', vim.log.levels.ERROR)
  end
  local path = string.format('repos/%s/%s/pulls/%d/comments', pr.owner, pr.repo, pr.number)
  vim.system({ 'gh', 'api', path, '--paginate' }, { text = true }, function(res)
    if res.code ~= 0 then
      return vim.schedule(function()
        notify('gh api failed: ' .. trim(res.stderr), vim.log.levels.ERROR)
      end)
    end
    local ok, data = pcall(vim.json.decode, res.stdout)
    if not ok or type(data) ~= 'table' then
      return vim.schedule(function()
        notify('could not parse comments JSON', vim.log.levels.ERROR)
      end)
    end
    local out = {}
    for _, c in ipairs(data) do
      out[#out + 1] = {
        path = c.path,
        -- `line` is null on comments anchored to an outdated diff.
        line = c.line or c.original_line or c.original_start_line or 1,
        body = c.body or '',
        user = (c.user and c.user.login) or '?',
        url = c.html_url,
        diff_hunk = c.diff_hunk,
      }
    end
    vim.schedule(function()
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

--------------------------------------------------------------- shared actions
local function open_at(e)
  local p = resolve(e.path)
  if not p then
    return notify('file not found locally: ' .. (e.path or '?') .. '  (run :Octo pr checkout)', vim.log.levels.WARN)
  end
  vim.cmd.edit(vim.fn.fnameescape(p))
  pcall(vim.api.nvim_win_set_cursor, 0, { e.line or 1, 0 })
  vim.cmd 'normal! zz'
end

local function open_thread(e)
  if not e.url then
    return notify('comment has no url', vim.log.levels.WARN)
  end
  vim.cmd('Octo ' .. e.url) -- loads octo on demand; opens the PR/thread context
end

------------------------------------------------------------- telescope picker
local function previewer()
  local previewers = require 'telescope.previewers'
  return previewers.new_buffer_previewer {
    title = 'Comment',
    define_preview = function(self, entry)
      local e = entry.value
      local lines = { string.format('@%s  %s:%d', e.user or '?', e.path or '?', e.line or 0), '' }
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

--- @param extra table[] list of { lhs, fn } -- normal-mode secondary actions
local function pick(title, entries, on_default, extra)
  if vim.tbl_isempty(entries) then
    return notify(title .. ': nothing to show')
  end
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
          local body = (e.body or ''):gsub('%s+', ' ')
          if #body > 60 then
            body = body:sub(1, 60) .. '…'
          end
          local display = string.format('%s:%d  @%s  %s', e.path or '?', e.line or 0, e.user or '?', body)
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
          map('n', m.lhs, function()
            local sel = state.get_selected_entry()
            if sel then
              m.fn(sel.value, bufnr)
            end
          end)
        end
        return true
      end,
    })
    :find()
end

------------------------------------------------------------------- public API
-- List every review comment on the current PR.
-- <CR> open file at line · p pin · o open thread in octo
function M.list()
  current_pr(function(pr)
    fetch(pr, function(comments)
      local actions = require 'telescope.actions'
      pick('PR #' .. pr.number .. ' comments', comments, open_at, {
        {
          lhs = 'p',
          fn = function(e)
            M._pin(pr, e)
          end,
        },
        {
          lhs = 'o',
          fn = function(e, b)
            actions.close(b)
            open_thread(e)
          end,
        },
      })
    end)
  end)
end

function M._pin(pr, e)
  local slug = pr.owner .. '/' .. pr.repo
  local pins = load_pins(slug)
  for _, p in ipairs(pins) do
    if p.url == e.url then
      return notify 'already pinned'
    end
  end
  pins[#pins + 1] =
    { path = e.path, line = e.line, body = e.body, user = e.user, url = e.url, pr = pr.number, diff_hunk = e.diff_hunk }
  save_pins(slug, pins)
  notify('pinned ' .. (e.path or '?') .. ':' .. (e.line or 0))
end

-- List pinned comments for this repo.
-- <CR> open file at line · o open thread in octo · dd unpin
function M.pins()
  repo_slug(function(slug)
    local actions = require 'telescope.actions'
    pick('Pinned comments (' .. slug .. ')', load_pins(slug), open_at, {
      {
        lhs = 'o',
        fn = function(e, b)
          actions.close(b)
          open_thread(e)
        end,
      },
      {
        lhs = 'dd',
        fn = function(e, b)
          local kept = {}
          for _, p in ipairs(load_pins(slug)) do
            if p.url ~= e.url then
              kept[#kept + 1] = p
            end
          end
          save_pins(slug, kept)
          notify 'unpinned'
          actions.close(b)
          M.pins() -- reopen, refreshed
        end,
      },
    })
  end)
end

return M
