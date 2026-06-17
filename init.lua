--[[

=====================================================================
=================== READ THIS BEFORE CONTINUING ====================
=====================================================================

Kickstart.nvim is *not* a distribution.

Kickstart.nvim is a template for your own configuration.
  The goal is that you can read every line of code, top-to-bottom, understand
  what your configuration is doing, and modify it to suit your needs.

  Once you've done that, you should start exploring, configuring and tinkering to
  explore Neovim!

  If you don't know anything about Lua, I recommend taking some time to read through
  a guide. One possible example:
  - https://learnxinyminutes.com/docs/lua/


  And then you can explore or search through `:help lua-guide`
  - https://neovim.io/doc/user/lua-guide.html


Kickstart Guide:

I have left several `:help X` comments throughout the init.lua
You should run that command and read that help section for more information.

In addition, I have some `NOTE:` items throughout the file.
These are for you, the reader to help understand what is happening. Feel free to delete
them once you know what you're doing, but they should serve as a guide for when you
are first encountering a few different constructs in your nvim config.

I hope you enjoy your Neovim journey,
- TJ

P.S. You can delete this when you're done too. It's your config now :)
--]]
-- Set <space> as the leader key
-- See `:help mapleader`
--  NOTE: Must happen before plugins are required (otherwise wrong leader will be used)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '
vim.g.have_nerd_font = true

vim.filetype.add({
  extension = {
    templ = "templ",
  },
})

-- Install package manager
--    https://github.com/folke/lazy.nvim
--    `:help lazy.nvim.txt` for more info
local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system {
    'git',
    'clone',
    '--filter=blob:none',
    'https://github.com/folke/lazy.nvim.git',
    '--branch=stable', -- latest stable release
    lazypath,
  }
end
vim.opt.rtp:prepend(lazypath)

-- NOTE: Here is where you install your plugins.
--  You can configure plugins using the `config` key.
--
--  You can also configure plugins after the setup call,
--    as they will be available in your neovim runtime.
require('lazy').setup({
  -- NOTE: First, some plugins that don't require any configuration

  -- Git related plugins
  'tpope/vim-fugitive',
  'tpope/vim-rhubarb',
  "nvim-neotest/nvim-nio",

  -- Detect tabstop and shiftwidth automatically
  'tpope/vim-sleuth',

  -- NOTE: This is where your plugins related to LSP can be installed.
  --  The configuration is done below. Search for lspconfig to find it below.
  {
    -- LSP Configuration & Plugins
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Automatically install LSPs to stdpath for neovim
      'williamboman/mason.nvim',
      'williamboman/mason-lspconfig.nvim',

      -- Useful status updates for LSP
      -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
      { 'j-hui/fidget.nvim', tag = 'legacy', opts = {} },

      -- Additional lua configuration, makes nvim stuff amazing!
      'folke/neodev.nvim',
    },
  },
  {
    -- TypeScript/JavaScript LSP (tsserver-based). setup() is called in the LSP
    -- section below so it reuses the shared on_attach + blink capabilities.
    'pmizio/typescript-tools.nvim',
    dependencies = { 'nvim-lua/plenary.nvim', 'neovim/nvim-lspconfig' },
  },
  -- Useful plugin to show you pending keybinds.
  { 'folke/which-key.nvim',  opts = {} },
  {
    -- Adds git related signs to the gutter, as well as utilities for managing changes
    'lewis6991/gitsigns.nvim',
    opts = {
      -- See `:help gitsigns.txt`
      signs = {
        add = { text = '+' },
        change = { text = '~' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
      on_attach = function(bufnr)
        vim.keymap.set('n', '<leader>hp', require('gitsigns').preview_hunk, { buffer = bufnr, desc = 'Preview git hunk' })

        -- don't override the built-in and fugitive keymaps
        local gs = package.loaded.gitsigns
        vim.keymap.set({ 'n', 'v' }, ']c', function()
          if vim.wo.diff then
            return ']c'
          end
          vim.schedule(function()
            gs.next_hunk()
          end)
          return '<Ignore>'
        end, { expr = true, buffer = bufnr, desc = 'Jump to next hunk' })
        vim.keymap.set({ 'n', 'v' }, '[c', function()
          if vim.wo.diff then
            return '[c'
          end
          vim.schedule(function()
            gs.prev_hunk()
          end)
          return '<Ignore>'
        end, { expr = true, buffer = bufnr, desc = 'Jump to previous hunk' })
      end,
    },
  },

  {
    -- Theme inspired by Atom
    'navarasu/onedark.nvim',
    priority = 1000,
    config = function()
      vim.cmd.colorscheme 'onedark'
    end,
  },

  {
    -- Set lualine as statusline
    'nvim-lualine/lualine.nvim',
    -- See `:help lualine.txt`
    opts = {
      options = {
        icons_enabled = false,
        theme = 'onedark',
        component_separators = '|',
        section_separators = '',
      },
    },
  },

  {
    -- Add indentation guides even on blank lines
    'lukas-reineke/indent-blankline.nvim',
    -- Enable `lukas-reineke/indent-blankline.nvim`
    -- See `:help ibl`
    main = 'ibl',
    opts = {},
  },

  -- "gc" to comment visual regions/lines
  { 'numToStr/Comment.nvim', opts = {} },

  -- Fuzzy Finder (files, lsp, etc)
  {
    'nvim-telescope/telescope.nvim',
    -- master, not 0.1.x: the 0.1.x release line predates nvim-treesitter `main`
    -- and crashes in the previewer (ts_parsers.ft_to_lang removed). master uses
    -- native vim.treesitter.
    branch = 'master',
    dependencies = {
      'nvim-lua/plenary.nvim',
      -- Fuzzy Finder Algorithm which requires local dependencies to be built.
      -- Only load if `make` is available. Make sure you have the system
      -- requirements installed.
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        -- NOTE: If you are having trouble with this installation,
        --       refer to the README for telescope-fzf-native for more instructions.
        build = vim.fn.has 'win32' == 1
            and 'cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release && cmake --install build --prefix build'
          or 'make',
        cond = function()
          if vim.fn.has 'win32' == 1 then
            return vim.fn.executable 'cmake' == 1
          end
          return vim.fn.executable 'make' == 1
        end,
      },
    },
  },

  { 'echasnovski/mini.pairs', version = false, opts = {} },

  {
    -- Highlight, edit, and navigate code.
    -- `main` branch is the rewrite required for Neovim 0.12 (master is frozen
    -- and unsupported on 0.12). Configured in the `-- [[ Treesitter ]]` block.
    'nvim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    build = ':TSUpdate',
    dependencies = {
      { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' },
    },
  },

  -- NOTE: Next Step on Your Neovim Journey: Add/Configure additional "plugins" for kickstart
  --       These are some example plugins that I've included in the kickstart repository.
  --       Uncomment any of the lines below to enable them.
  require 'kickstart.plugins.autoformat',
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = function() vim.fn["mkdp#util#install"]() end,
    init = function()
      vim.g.mkdp_markdown_css = vim.fn.stdpath("config") .. "/markdown-preview.css"
    end,
  },
  {
    'numToStr/Comment.nvim',
    opts = {
      -- add any options here
    },
    lazy = false,
  },
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    ---@type Flash.Config
    opts = {},
    -- stylua: ignore
    keys = {
      { "s",     mode = { "n", "x", "o" }, function() require("flash").jump() end,              desc = "Flash" },
      { "S",     mode = { "n", "x", "o" }, function() require("flash").treesitter() end,        desc = "Flash Treesitter" },
      { "r",     mode = "o",               function() require("flash").remote() end,            desc = "Remote Flash" },
      { "R",     mode = { "o", "x" },      function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
      { "<c-s>", mode = { "c" },           function() require("flash").toggle() end,            desc = "Toggle Flash Search" },
    },
  },



  -- NOTE: The import below can automatically add your own plugins, configuration, etc from `lua/custom/plugins/*.lua`
  --    You can use this folder to prevent any conflicts with this init.lua if you're interested in keeping
  --    up-to-date with whatever is in the kickstart repo.
  --    Uncomment the following line and add your plugins to `lua/custom/plugins/*.lua` to get going.
  --
  --    For additional information see: https://github.com/folke/lazy.nvim#-structuring-your-plugins
  { import = 'custom.plugins' }
}, {})

-- [[ Setting options ]]
-- See `:help vim.o`
-- NOTE: You can change these options as you wish!

-- Set highlight on search
vim.o.hlsearch = false

-- Make line numbers default
vim.wo.number = true

-- Enable mouse mode
vim.o.mouse = 'a'

-- Sync clipboard between OS and Neovim.
--  Remove this option if you want your OS clipboard to remain independent.
--  See `:help 'clipboard'`
vim.o.clipboard = 'unnamedplus'

-- Enable break indent
vim.o.breakindent = true

-- Save undo history
vim.o.undofile = true

-- Case-insensitive searching UNLESS \C or capital in search
vim.o.ignorecase = true
vim.o.smartcase = true

-- Keep signcolumn on by default
vim.wo.signcolumn = 'yes'

-- Decrease update time
vim.o.updatetime = 250
vim.o.timeoutlen = 300

-- Set completeopt to have a better completion experience
vim.o.completeopt = 'menuone,noselect'

-- NOTE: You should make sure your terminal supports this
vim.o.termguicolors = true

vim.o.rnu = true

-- [[ Folding ]]
-- Treesitter-based folding; start with everything open
vim.o.foldmethod = 'expr'
vim.o.foldexpr = 'nvim_treesitter#foldexpr()'
vim.o.foldlevelstart = 99

-- [[ Basic Keymaps ]]

-- Keymaps for better default experience
-- See `:help vim.keymap.set()`
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- [[ Highlight on yank ]]
-- See `:help vim.hl.on_yank()`
local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
vim.api.nvim_create_autocmd('TextYankPost', {
  callback = function()
    vim.hl.on_yank()
  end,
  group = highlight_group,
  pattern = '*',
})

-- [[ Configure Telescope ]]
-- See `:help telescope` and `:help telescope.setup()`
require('telescope').setup {
  defaults = {
    mappings = {
      i = {
        ['<C-u>'] = false,
        ['<C-d>'] = false,
      },
    },
  },
}

-- Enable telescope fzf native, if installed
pcall(require('telescope').load_extension, 'fzf')

-- See `:help telescope.builtin`
vim.keymap.set('n', '<leader>?', require('telescope.builtin').oldfiles, { desc = '[?] Find recently opened files' })
vim.keymap.set('n', '<leader><space>', require('telescope.builtin').buffers, { desc = '[ ] Find existing buffers' })
vim.keymap.set('n', '<leader>/', function()
  -- You can pass additional configuration to telescope to change theme, layout, etc.
  require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
    winblend = 10,
    previewer = false,
  })
end, { desc = '[/] Fuzzily search in current buffer' })

vim.keymap.set('n', '<leader>gf', require('telescope.builtin').git_files, { desc = 'Search [G]it [F]iles' })
vim.keymap.set('n', '<leader>sf', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' })
vim.keymap.set('n', '<leader>sh', require('telescope.builtin').help_tags, { desc = '[S]earch [H]elp' })
vim.keymap.set('n', '<leader>sw', require('telescope.builtin').grep_string, { desc = '[S]earch current [W]ord' })
vim.keymap.set('n', '<leader>sg', require('telescope.builtin').live_grep, { desc = '[S]earch by [G]rep' })
vim.keymap.set('n', '<leader>sd', require('telescope.builtin').diagnostics, { desc = '[S]earch [D]iagnostics' })
vim.keymap.set('n', '<leader>sr', require('telescope.builtin').resume, { desc = '[S]earch [R]esume' })

-- [[ Configure Treesitter ]]
-- [[ Treesitter ]]  See `:help nvim-treesitter` (the `main`-branch rewrite).
-- The new plugin only installs parsers; highlight/indent are Neovim built-ins.
local ts_parsers = {
  'c', 'cpp', 'go', 'lua', 'python', 'rust', 'tsx', 'javascript', 'typescript',
  'vimdoc', 'vim', 'bash', 'templ', 'nu', 'gdscript', 'markdown', 'markdown_inline',
}
do
  local installed = require('nvim-treesitter.config').get_installed()
  local missing = vim.iter(ts_parsers)
    :filter(function(p) return not vim.tbl_contains(installed, p) end)
    :totable()
  if #missing > 0 then
    require('nvim-treesitter').install(missing)
  end
end

-- Enable treesitter highlighting + (experimental) indentation per filetype.
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('treesitter-start', { clear = true }),
  callback = function()
    if pcall(vim.treesitter.start) then
      vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})

-- Text objects (select / move / swap) — nvim-treesitter-textobjects `main` API.
require('nvim-treesitter-textobjects').setup {
  select = { lookahead = true },
  move = { set_jumps = true },
}
-- select
for lhs, query in pairs {
  aa = '@parameter.outer', ia = '@parameter.inner',
  af = '@function.outer', ['if'] = '@function.inner',
  ac = '@class.outer', ic = '@class.inner',
} do
  vim.keymap.set({ 'x', 'o' }, lhs, function()
    require('nvim-treesitter-textobjects.select').select_textobject(query, 'textobjects')
  end, { desc = 'TS select ' .. query })
end
-- swap
vim.keymap.set('n', '<leader>a', function()
  require('nvim-treesitter-textobjects.swap').swap_next '@parameter.inner'
end, { desc = 'Swap next parameter' })
vim.keymap.set('n', '<leader>A', function()
  require('nvim-treesitter-textobjects.swap').swap_previous '@parameter.inner'
end, { desc = 'Swap previous parameter' })
-- move (function/class, next/prev, start/end)
for lhs, spec in pairs {
  [']m'] = { 'goto_next_start', '@function.outer' },
  [']]'] = { 'goto_next_start', '@class.outer' },
  [']M'] = { 'goto_next_end', '@function.outer' },
  ['][' ] = { 'goto_next_end', '@class.outer' },
  ['[m'] = { 'goto_previous_start', '@function.outer' },
  ['[['] = { 'goto_previous_start', '@class.outer' },
  ['[M'] = { 'goto_previous_end', '@function.outer' },
  ['[]'] = { 'goto_previous_end', '@class.outer' },
} do
  vim.keymap.set({ 'n', 'x', 'o' }, lhs, function()
    require('nvim-treesitter-textobjects.move')[spec[1]](spec[2], 'textobjects')
  end, { desc = 'TS move ' .. spec[1] .. ' ' .. spec[2] })
end
-- NOTE: incremental_selection (was <c-space>/<c-s>/<M-space>) is dropped — the
-- `main` rewrite has no such module.

-- Diagnostic keymaps
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Go to previous diagnostic message' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Go to next diagnostic message' })
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Open floating diagnostic message' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostics list' })

-- [[ Configure LSP ]]
--  This function gets run when an LSP connects to a particular buffer.
-- PyTorch (and other C-extension libs) inject their real docstrings at RUNTIME,
-- so a static server like pyright only sees the patchy `.pyi` stubs: tensor
-- methods usually carry just ``See `torch.foo` `` and some have no body at all.
-- `smart_hover` does a normal LSP hover, but when it spots that degraded stub doc
-- it redirects to the real runtime doc via `python -m pydoc`, run through the
-- project's own interpreter (so torch is importable).
local function project_python(bufnr)
  for _, c in ipairs(vim.lsp.get_clients { bufnr = bufnr, name = 'pyright' }) do
    local pp = vim.tbl_get(c, 'config', 'settings', 'python', 'pythonPath')
    if pp then
      local root = c.config.root_dir or vim.fn.getcwd()
      local abs = pp:sub(1, 1) == '/' and pp or (root .. '/' .. pp)
      if vim.fn.executable(abs) == 1 then
        return abs
      end
    end
  end
  local venv = vim.fn.getcwd() .. '/.venv/bin/python'
  return vim.fn.executable(venv) == 1 and venv or 'python3'
end

local function pydoc_float(symbol, py)
  local out = vim.fn.systemlist { py, '-m', 'pydoc', symbol }
  if vim.v.shell_error ~= 0 or #out == 0 or (out[1] or ''):match 'No Python documentation found' then
    return false
  end
  vim.lsp.util.open_floating_preview(out, '', {
    border = 'rounded',
    title = ' pydoc: ' .. symbol .. ' ',
    max_width = 100,
    max_height = 30,
    focus_id = 'pydoc', -- press K again to jump into the float and scroll
    wrap = true,
  })
  return true
end

local function smart_hover()
  if vim.bo.filetype ~= 'python' then
    return vim.lsp.buf.hover()
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = pos[1] - 1, character = pos[2] },
  }
  local responses = vim.lsp.buf_request_sync(bufnr, 'textDocument/hover', params, 1000) or {}
  local md = ''
  for _, r in pairs(responses) do
    local contents = r.result and r.result.contents
    if contents then
      md = type(contents) == 'table' and (contents.value or '') or tostring(contents)
      if #md > 0 then
        break
      end
    end
  end

  -- 1) stub redirect: ``See `torch.squeeze` `` -> pydoc the free fn (the one with the real doc)
  local target = md:match 'See%s+`(torch%.[%w_%.]+)`' or md:match 'See%s+:func:`(torch%.[%w_%.]+)`'
  -- 2) a torch-qualified symbol typed in the source, e.g. hovering `torch.where`
  if not target then
    local cexpr = vim.fn.expand '<cexpr>'
    if cexpr:match '^torch%.[%w_%.]+$' then
      target = cexpr
    end
  end

  if target and pydoc_float(target, project_python(bufnr)) then
    return
  end
  vim.lsp.buf.hover() -- nothing better to offer -> normal LSP float
end

local on_attach = function(_, bufnr)
  -- NOTE: Remember that lua is a real programming language, and as such it is possible
  -- to define small helper and utility functions so you don't have to repeat yourself
  -- many times.
  --
  -- In this case, we create a function that lets us more easily define mappings specific
  -- for LSP related items. It sets the mode, buffer and description for us each time.
  local nmap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  vim.keymap.set({ 'i', 'v' }, '<C-k>', vim.lsp.buf.hover, { buffer = bufnr, desc = 'Open documentation in insert mode' })

  nmap('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
  nmap('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

  nmap('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
  nmap('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
  nmap('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
  nmap('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')
  nmap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
  nmap('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

  -- See `:help K` for why this keymap
  nmap('K', smart_hover, 'Hover Documentation (pydoc fallback for torch)')
  nmap('<C-k>', vim.lsp.buf.signature_help, 'Signature Documentation')

  -- Lesser used LSP functionality
  nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
  nmap('<leader>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
  nmap('<leader>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
  nmap('<leader>wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, '[W]orkspace [L]ist Folders')

  -- Create a command `:Format` local to the LSP buffer
  vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
    vim.lsp.buf.format()
  end, { desc = 'Format current buffer with LSP' })
end

-- -- document existing key chains
-- require('which-key').register {
--   ['<leader>c'] = { name = '[C]ode', _ = 'which_key_ignore' },
--   ['<leader>d'] = { name = '[D]ocument', _ = 'which_key_ignore' },
--   ['<leader>g'] = { name = '[G]it', _ = 'which_key_ignore' },
--   ['<leader>h'] = { name = 'More git', _ = 'which_key_ignore' },
--   ['<leader>r'] = { name = '[R]ename', _ = 'which_key_ignore' },
--   ['<leader>s'] = { name = '[S]earch', _ = 'which_key_ignore' },
--   ['<leader>w'] = { name = '[W]orkspace', _ = 'which_key_ignore' },
-- }

require('mason').setup()
local mason_lspconfig = require 'mason-lspconfig'

-- Enable the following language servers
--  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
--
--  Add any additional override configuration in the following tables. They will be passed to
--  the `settings` field of the server config. You must look up that documentation yourself.
--
--  If you want to override the default filetypes that your language server will attach to you can
--  define the property 'filetypes' to the map in question.
--
local servers = {
  -- clangd = {},
  gopls = {
    -- gopls reads its options from the `gopls` settings section, so the
    -- table must be nested (mirrors lua_ls/pyright using `Lua`/`python`).
    gopls = {
      usePlaceholders = true,
    },
  },
  -- templ = {},
  ruff = {},
  pyright = {
    python = {
      venvPath = '.',
      venv = '.venv',
      pythonPath = '.venv/bin/python',
    },
  },
  rust_analyzer = {},
  tailwindcss = { filetypes = { 'templ', 'html', 'tsx', 'typescriptreact', 'typescript' } },
  -- JS/TS handled by typescript-tools.nvim (see setup below), not mason/lspconfig.
  -- htmx = { filetypes = { 'html', 'templ' } },
  html = { filetypes = { 'html', 'twig', 'hbs', 'templ' } },

  lua_ls = {
    Lua = {
      workspace = { checkThirdParty = false },
      telemetry = { enable = false },
    },
  },
}

-- Setup neovim lua configuration
require('neodev').setup()

-- nvim-cmp supports additional completion capabilities, so broadcast that to servers
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('blink.cmp').get_lsp_capabilities(capabilities)

mason_lspconfig.setup {
  ensure_installed = vim.tbl_keys(servers),
  automatic_enable = false,
}

local function setup_lsp(server_name, config)
  config = vim.deepcopy(config or {})
  local filetypes = config.filetypes
  config.filetypes = nil

  vim.lsp.config(server_name, {
    capabilities = capabilities,
    on_attach = on_attach,
    settings = config,
    filetypes = filetypes,
  })
  vim.lsp.enable(server_name)
end

setup_lsp('gdscript')

for server_name, config in pairs(servers) do
  setup_lsp(server_name, config)
end

-- TypeScript / JavaScript LSP via typescript-tools.nvim.
-- It's not a mason/lspconfig server, so it's configured separately here, but
-- with the same on_attach + capabilities as every other server.
require('typescript-tools').setup {
  on_attach = on_attach,
  capabilities = capabilities,
}

if vim.fn.has 'win32' == 0 then
  vim.g.python3_host_prog = '/home/rmo/.pyenv/versions/nvim311/bin/python'
end
vim.bo.tabstop = 4      -- size of a hard tabstop (ts).
vim.bo.shiftwidth = 4   -- size of an indentation (sw).
vim.bo.expandtab = true -- always uses spaces instead of tab characters (et).
vim.bo.softtabstop = 4  -- number of spaces a <Tab> counts for. When 0, feature is off (sts).
-- The line beneath this is called `modeline`. See `:help modeline`
-- vim: ts=2 sts=2 sw=2 et
