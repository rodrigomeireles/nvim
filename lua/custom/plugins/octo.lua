-- octo.nvim: full GitHub PR/issue review from inside Neovim.
-- Drives the GitHub API through the `gh` CLI (already authenticated).
-- Requirements (all satisfied here): nvim >= 0.10, gh, plenary, a picker.
--
-- This config adds a thin custom layer (see lua/custom/pr-comments.lua) for the
-- one thing octo lacks: pinning comments and a flat "all PR comments" picker.
return {
  'pwntester/octo.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-telescope/telescope.nvim',
    'nvim-tree/nvim-web-devicons', -- file-panel icons
  },
  cmd = 'Octo', -- lazy-load octo on first :Octo
  opts = {
    picker = 'telescope', -- reuse the telescope setup used everywhere else
    mappings = {
      -- octo deep-merges mappings over its defaults, so these partial overrides
      -- keep every other default (react/reply/resolve, ]t/[t, etc.) intact.
      -- Open the file a review comment refers to with `gx` (default is `gf`).
      review_diff = { goto_file = { lhs = 'gx', desc = 'go to file' } },
      pull_request = { goto_file = { lhs = 'gx', desc = 'go to file' } },
    },
  },
  config = function(_, opts)
    require('octo').setup(opts)
  end,
  -- `init` runs at startup even though octo itself is lazy-loaded, so the custom
  -- commands/keymaps exist immediately; the heavy module is required only when
  -- one of them is actually invoked.
  init = function()
    local pr = function(fn)
      return function()
        require('custom.pr-comments')[fn]()
      end
    end

    vim.api.nvim_create_user_command('PrComments', pr 'list', { desc = 'List current PR comments' })
    vim.api.nvim_create_user_command('PrPins', pr 'pins', { desc = 'List pinned PR comments' })

    vim.keymap.set('n', '<leader>pc', pr 'list', { desc = 'PR: [c]omments' })
    vim.keymap.set('n', '<leader>pp', pr 'pins', { desc = 'PR: [p]inned comments' })
    vim.keymap.set('n', '<leader>po', '<cmd>Octo pr list<cr>', { desc = 'PR: [o]cto pr list' })
    vim.keymap.set('n', '<leader>pr', '<cmd>Octo review start<cr>', { desc = 'PR: start [r]eview' })

    pcall(function()
      require('which-key').add { { '<leader>p', group = '[P]R/Octo' } }
    end)
  end,
}
