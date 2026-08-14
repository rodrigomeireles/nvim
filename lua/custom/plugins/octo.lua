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
  cmd = 'Octo',                    -- lazy-load octo on first :Octo
  opts = {
    picker = 'telescope',          -- reuse the telescope setup used everywhere else
    ui = {
      -- Comment marks as real signs, not via octo's 'statuscolumn' expression.
      -- That expression (ui/statuscolumn.lua, get_sign) calls
      -- nvim_win_text_height -- a window-measuring API -- during the window's own
      -- redraw, once per visible line inside a comment range. A statuscolumn is
      -- also sized from its rendered output, so the gutter width is dynamic; with
      -- the right pane at exact max width the layout has no slack, and a one-cell
      -- gutter change shifts the whole text area and re-renders every row.
      -- signcolumn is already 'yes' here, so this costs no extra columns.
      use_signcolumn = true,
      use_statuscolumn = false,
    },
    -- KEEP THIS OFF. It loads the right (head) pane from the working tree, which
    -- does get LSP to attach — but it also installs a `BufEnter *` handler
    -- (octo/autocmds.lua) calling update_layout_for_current_file, and octo's own
    -- FileEntry:show_diff() fires `doau BufEnter` on that now-real buffer. The
    -- handler re-enters the layout (set_current_file → diffoff! → load_buffers →
    -- show_diff → doau BufEnter → …), so the panes reload and re-equalize as the
    -- cursor moves, the cursor lands in the wrong pane after closing a thread,
    -- and `:filetype detect` on the base buffer spams "No matching autocommands:
    -- filetypedetect BufRead". For LSP on a reviewed file, use `gx` to open the
    -- real file instead (see the mappings below).
    use_local_fs = false,
    reviews = {
      -- Don't hijack the opposite diff pane with the comment-thread view every
      -- time the cursor crosses a commented line; open threads on demand with
      -- `:Octo review thread` (q closes them) instead.
      auto_show_threads = false,
    },
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
    -- move the comment-count badges off right_align so they stop overwriting code
    require('custom.octo-render').patch()
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
    -- Bare `Octo review` is start-or-resume. `Octo review start` always fires
    -- the addPullRequestReview mutation, and GitHub allows only one pending
    -- review per user per PR, so it errors out instead of reopening a review
    -- left over from an earlier session.
    vim.keymap.set('n', '<leader>pr', '<cmd>Octo review<cr>', { desc = 'PR: start/resume [r]eview' })

    -- Inside octo buffers: pin / unpin the comment under the cursor.
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'octo',
      desc = 'PR pin/unpin maps in octo buffers',
      callback = function(ev)
        vim.keymap.set('n', '<leader>pp', pr 'pin_at_cursor',
          { buffer = ev.buf, desc = 'PR: [p]in comment under cursor' })
        vim.keymap.set('n', '<leader>pP', pr 'unpin_at_cursor',
          { buffer = ev.buf, desc = 'PR: un[P]in comment under cursor' })
      end,
    })

    -- Diff mode folds every unchanged region (octo pins foldmethod=diff,
    -- foldlevel=0 in FileEntry.winopts) and the default 'foldopen' contains
    -- `hor` and `block`, so horizontal motion or a visual selection *opens* the
    -- fold the cursor lands in. Reviewing then looks like the file rewriting
    -- itself as you move -- the buffer is never touched (changedtick doesn't
    -- budge), it's the view unfolding. Keep review panes flat; `zi` still toggles
    -- folds per window when a long file wants them.
    vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinEnter', 'BufEnter' }, {
      pattern = 'octo://*',
      desc = 'octo review diffs: no diff folds',
      callback = function(ev)
        if not vim.b[ev.buf].octo_diff_props then
          return
        end
        -- after octo's own diffthis / _configure_windows, which set fdm and fdl
        vim.schedule(function()
          if not vim.api.nvim_buf_is_valid(ev.buf) then
            return
          end
          for _, win in ipairs(vim.fn.win_findbuf(ev.buf)) do
            vim.wo[win].foldenable = false
            vim.wo[win].foldlevel = 99 -- belt, in case something re-enables folds
          end
        end)
      end,
    })

    -- Inside a review diff, K and gd go through custom.octo-lsp, which serves
    -- them from the real file on disk (the diff buffer itself is a scratch
    -- buffer no server will attach to).
    --
    -- keywordprg has to be cleared too: octo runs `:filetype detect` on these
    -- buffers, so language ftplugins load against a path that is a URI, and
    -- anything they derive from `%` is then wrong. nvim's stock ftplugin/go.vim
    -- sets keywordprg=:GoKeywordPrg, which runs `go doc -C <%:h>` in a terminal
    -- split and fails with `go: chdir octo://…: no such file or directory`.
    -- Our K mapping covers normal mode; clearing kp stops visual-mode K (and
    -- anything else that consults it) from shelling out into the URI.
    vim.api.nvim_create_autocmd('FileType', {
      desc = 'octo review diffs: K/gd served from the real file',
      callback = function(ev)
        if not vim.b[ev.buf].octo_diff_props then
          return -- not a review diff pane (thread/PR buffers are filetype octo)
        end
        vim.bo[ev.buf].keywordprg = ''
        -- indent-blankline keeps ~120 virtual-text marks on a diff pane and
        -- re-renders them as the cursor moves (scope tracking), so the indent
        -- guides blink in and out across the visible rows while reading. Measured
        -- on this repo's own review: mark count walked 116<->121 on plain j/k.
        -- Indent guides aren't worth that inside a diff.
        pcall(function()
          require('ibl').setup_buffer(ev.buf, { enabled = false })
        end)
        local lsp = function(fn)
          return function()
            require('custom.octo-lsp')[fn]()
          end
        end
        vim.keymap.set('n', 'K', lsp 'hover',
          { buffer = ev.buf, desc = 'Hover (from the real file)' })
        vim.keymap.set('n', 'gd', lsp 'definition',
          { buffer = ev.buf, desc = 'Goto definition (new tab)' })
      end,
    })

    pcall(function()
      require('which-key').add { { '<leader>p', group = '[P]R/Octo' } }
    end)
  end,
}
