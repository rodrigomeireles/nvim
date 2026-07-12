local cpp_filetypes = { 'c', 'cpp', 'objc', 'objcpp', 'cuda' }

local function use_wsl_cppman_on_windows()
  if vim.fn.has 'win32' ~= 1 then
    return
  end

  local bin = vim.fn.stdpath 'config' .. '/bin'
  if vim.fn.executable(bin .. '/cppman.cmd') == 1 then
    vim.env.PATH = bin .. ';' .. (vim.env.PATH or '')
  end
end

local function cpp_symbol_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local search_from = 1

  while true do
    local start_col, end_col = line:find('[%w_:~]+', search_from)
    if not start_col then
      return vim.fn.expand '<cword>'
    end

    if start_col <= col and col <= end_col + 1 then
      local token = line:sub(start_col, end_col):gsub('^:+', ''):gsub(':+$', '')
      if token:find '::' then
        return token
      end

      local prefix = line:sub(1, start_col - 1):match '([%w_:]+::)$'
      return prefix and (prefix .. token) or token
    end

    search_from = end_col + 1
  end
end

return {
  'simonwinther/cppman.nvim',
  version = '*',
  cmd = 'CPPMan',
  dependencies = {
    'ibhagwan/fzf-lua',
  },
  opts = {
    source = 'cppreference.com',
    picker = {
      provider = 'fzf-lua',
      width = 0.5,
      height = 0.5,
    },
    viewer = {
      width = 0.85,
      height = 0.75,
      border = 'rounded',
    },
  },
  init = function()
    use_wsl_cppman_on_windows()

    vim.api.nvim_create_autocmd('FileType', {
      pattern = cpp_filetypes,
      callback = function(args)
        vim.keymap.set('n', '<leader>ck', function()
          require('cppman').search()
        end, { buffer = args.buf, desc = '[C++] cppman search' })

        vim.keymap.set('n', '<leader>cu', function()
          require('cppman').open_for(cpp_symbol_under_cursor())
        end, { buffer = args.buf, desc = '[C++] cppman under cursor' })
      end,
    })
  end,
}
