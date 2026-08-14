-- LSP for octo's PR review diffs.
--
-- The review panes are `octo://…` scratch buffers, so no language server ever
-- attaches to them, and octo's own `use_local_fs` cure is worse than the disease
-- (see the note on it in plugins/octo.lua). But octo does record the
-- repo-relative path of the file being reviewed in `b:octo_diff_props`, so the
-- real file is one join away: load it in a *hidden* buffer, let the normal LSP
-- setup attach to that, and forward the request with the position re-anchored
-- onto the symbol under the cursor. The review layout is never touched; only
-- `gd` leaves the tab, and it gets a tab of its own.
--
-- The one honest caveat: the line numbers belong to the PR, the hidden buffer is
-- your working tree. They line up on the right pane when you're on the PR branch
-- and clean; on the base pane they never do. So the anchor is symbol-based with
-- the diff line as a hint -- the identifier under the cursor is looked up on that
-- line first, then on the nearest lines either side. That can land on the wrong
-- overload of a name; it won't silently land on some unrelated symbol.
local M = {}

--- How far from the diff line to look for the symbol in the working-tree copy.
local ANCHOR_RADIUS = 60

--- Absolute path of the file under review in the current diff buffer, if any.
local function reviewed_file()
  local props = vim.b.octo_diff_props
  if not (props and props.path) then
    return nil
  end
  -- octo resolves review paths against the git root, falling back to cwd; do the
  -- same, in the same order, so this agrees with what `gx` opens.
  local cwd = vim.fn.getcwd()
  for _, base in ipairs { vim.fs.root(cwd, '.git') or cwd, cwd } do
    local path = vim.fs.joinpath(base, props.path)
    if vim.uv.fs_stat(path) then
      return path
    end
  end
  return nil
end

--- Load the real file without displaying it. `bufload()` fires BufRead/FileType,
--- so lspconfig's autostart attaches exactly as if the file had been opened, and
--- `bufadd()` leaves the buffer unlisted so it stays out of the buffer list.
local function hidden_buf(path)
  local bufnr = vim.fn.bufadd(path)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end
  return bufnr
end

--- 0-indexed byte column of `word` in `line` as a whole word, or nil.
local function find_word(line, word)
  local from = 1
  while true do
    local s, e = line:find(word, from, true)
    if not s then
      return nil
    end
    local before = s > 1 and line:sub(s - 1, s - 1) or ''
    if not before:match '[%w_]' and not line:sub(e + 1, e + 1):match '[%w_]' then
      return s - 1
    end
    from = e + 1
  end
end

--- 0-indexed (row, col) of `word` in `bufnr`, closest to diff line `lnum`.
local function anchor(bufnr, lnum, word)
  local last = vim.api.nvim_buf_line_count(bufnr)
  local function at(l)
    if l < 1 or l > last then
      return nil
    end
    local line = vim.api.nvim_buf_get_lines(bufnr, l - 1, l, false)[1]
    local col = line and find_word(line, word)
    if col then
      return l - 1, col
    end
    return nil
  end

  local row, col = at(lnum)
  if row then
    return row, col
  end
  for d = 1, ANCHOR_RADIUS do
    row, col = at(lnum - d)
    if row then
      return row, col
    end
    row, col = at(lnum + d)
    if row then
      return row, col
    end
  end
  return nil
end

--- Ask the servers attached to the real file about the symbol under the cursor.
--- `on_result(result, client)` runs for the first client that answers usefully.
local function request(method, on_result)
  local path = reviewed_file()
  if not path then
    return vim.notify('octo-lsp: no reviewed file here', vim.log.levels.WARN)
  end
  local word = vim.fn.expand '<cword>'
  if word == '' then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = hidden_buf(path)

  -- bufload() started the client, but it only registers once initialize()
  -- returns, so the first request into a cold project has to wait for it.
  local clients = vim.lsp.get_clients { bufnr = bufnr, method = method }
  if #clients == 0 then
    vim.wait(3000, function()
      clients = vim.lsp.get_clients { bufnr = bufnr, method = method }
      return #clients > 0
    end, 50)
  end
  if #clients == 0 then
    return vim.notify(('octo-lsp: no %s client for %s'):format(method, vim.fs.basename(path)),
      vim.log.levels.WARN)
  end

  local row, col = anchor(bufnr, lnum, word)
  if not row then
    return vim.notify(('octo-lsp: %s is not in the working-tree copy of %s')
      :format(word, vim.fs.basename(path)), vim.log.levels.WARN)
  end

  local answered = false
  for _, client in ipairs(clients) do
    local params = {
      textDocument = { uri = vim.uri_from_fname(path) },
      position = {
        line = row,
        character = vim.lsp.util.character_offset(bufnr, row, col, client.offset_encoding),
      },
    }
    client:request(method, params, function(err, result)
      local empty = result == nil or (type(result) == 'table' and vim.tbl_isempty(result))
      if answered or err or empty then
        return
      end
      answered = true
      on_result(result, client)
    end, bufnr)
  end
end

--- Hover, floated over the review pane. Nothing in the layout moves.
function M.hover()
  request('textDocument/hover', function(result)
    local lines = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
    if vim.tbl_isempty(lines) then
      return vim.notify('octo-lsp: nothing to hover', vim.log.levels.INFO)
    end
    vim.lsp.util.open_floating_preview(lines, 'markdown', {
      border = 'rounded',
      title = ' review hover ',
      focus_id = 'octo-review-hover', -- K again jumps into the float
    })
  end)
end

--- Definition in a new tab, so the review tab survives untouched. `:tabclose`
--- (or `<C-w>c`) puts you back in the review exactly where you were.
function M.definition()
  request('textDocument/definition', function(result, client)
    local loc = vim.islist(result) and result[1] or result
    vim.cmd.tabnew()
    if not vim.lsp.util.show_document(loc, client.offset_encoding, { focus = true }) then
      vim.cmd.tabclose()
      vim.notify('octo-lsp: could not open that definition', vim.log.levels.WARN)
    end
  end)
end

return M
