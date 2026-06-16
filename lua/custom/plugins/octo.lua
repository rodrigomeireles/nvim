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
      --
      -- `gx`: open the file a review comment refers to (default is `gf`).
      -- `gb`: open in browser. octo defaults this to <C-b>, which shadows Vim's
      --       native scroll-back in its buffers; moving it frees <C-b>.
      review_diff = { goto_file = { lhs = 'gx', desc = 'go to file' } },
      pull_request = {
        goto_file = { lhs = 'gx', desc = 'go to file' },
        open_in_browser = { lhs = 'gb', desc = 'open PR in browser' },
      },
      issue = { open_in_browser = { lhs = 'gb', desc = 'open issue in browser' } },
      discussion = { open_in_browser = { lhs = 'gb', desc = 'open discussion in browser' } },
      repo = { open_in_browser = { lhs = 'gb', desc = 'open repo in browser' } },
      release = { open_in_browser = { lhs = 'gb', desc = 'open release in browser' } },
      runs = { open_in_browser = { lhs = 'gb', desc = 'open workflow run in browser' } },
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

    -- Global (work from anywhere; the comment list also detects the PR from an
    -- octo buffer, so it works even when you aren't on the PR's branch).
    vim.keymap.set('n', '<leader>pc', pr 'list', { desc = 'PR: list [c]omments' })
    vim.keymap.set('n', '<leader>pl', pr 'pins', { desc = 'PR: [l]ist pinned' })
    vim.keymap.set('n', '<leader>po', '<cmd>Octo pr list<cr>', { desc = 'PR: [o]cto pr list' })
    vim.keymap.set('n', '<leader>pr', '<cmd>Octo review start<cr>', { desc = 'PR: start [r]eview' })

    -- Inside octo buffers: pin / unpin the comment under the cursor.
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'octo',
      desc = 'PR pin/unpin maps in octo buffers',
      callback = function(ev)
        vim.keymap.set('n', '<leader>pp', pr 'pin_at_cursor', { buffer = ev.buf, desc = 'PR: [p]in comment under cursor' })
        vim.keymap.set('n', '<leader>pP', pr 'unpin_at_cursor', { buffer = ev.buf, desc = 'PR: un[P]in comment under cursor' })
      end,
    })

    pcall(function()
      require('which-key').add { { '<leader>p', group = '[P]R/Octo' } }
    end)
  end,
}
