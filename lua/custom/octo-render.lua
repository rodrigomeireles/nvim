-- Render fixes for octo's PR review diffs.
--
-- octo marks each comment thread with a "N comments (…)" badge placed as virtual
-- text with `virt_text_pos = "right_align"` (reviews/file-entry.lua, in
-- FileEntry:place_signs). right_align pins the badge to the right edge of the
-- window's text area, and the default hl_mode *replaces* the cells underneath, so
-- on any line long enough to reach the badge it eats the end of the code:
--
--   width 141:  secretResolveTimeout bounds credential discovery and the Se…
--   width  75:  secretResolveTimeout bounds cr    1 comment (29 minutes ago)
--
-- Every change to the text-area width re-lays that out, so the file appears to
-- rewrite itself. Same badge, placed at end-of-line instead, where it can never
-- cover code and never depends on the window width.
local M = {}

function M.patch()
  local FileEntry = require('octo.reviews.file-entry').FileEntry
  if FileEntry.__octo_badges_at_eol then
    return -- already patched (config can run more than once)
  end
  FileEntry.__octo_badges_at_eol = true

  local ns = require('octo.constants').OCTO_REVIEW_COMMENTS_NS
  local place_signs = FileEntry.place_signs

  FileEntry.place_signs = function(self, ...)
    place_signs(self, ...)
    -- built by hand, not `ipairs{left, right}`: either side can be nil early in a
    -- review, and a nil first element would end the iteration at the hole
    local bufs = {}
    for _, bufnr in pairs { self.left_bufid, self.right_bufid } do
      bufs[#bufs + 1] = bufnr
    end
    for _, bufnr in ipairs(bufs) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
          local id, row, details = mark[1], mark[2], mark[4]
          if details and details.virt_text and details.virt_text_pos == 'right_align' then
            vim.api.nvim_buf_set_extmark(bufnr, ns, row, -1, {
              id = id, -- reuse the id: replaces the mark rather than adding one
              virt_text = details.virt_text,
              virt_text_pos = 'eol',
              strict = false, -- octo passes this too: the line may not exist
            })
          end
        end
      end
    end
  end
end

--- Re-place the badges for the review that is open right now, so a live session
--- picks the fix up without restarting.
function M.refresh()
  local ok, reviews = pcall(require, 'octo.reviews')
  local review = ok and reviews.get_current_review() or nil
  local file = review and review.layout and review.layout:get_current_file() or nil
  if file then
    file:place_signs()
  end
  return file ~= nil
end

return M
