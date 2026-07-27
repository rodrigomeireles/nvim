-- :QfSave [file] — save the current quickfix list as plain text, one entry
-- per line: `/abs/path|lnum type| text` (type word: error/warning/info/note).
-- Appends when the file exists (delete lines as you handle them); :QfSave!
-- overwrites. :QfLoad [file] — load such a file back as a new quickfix list
-- (untyped `path|lnum| text` lines work too). Both default to 'review.qf'.
-- Columns aren't persisted. Quickfix lists live in memory per instance, so
-- this is the way to keep one across nvim restarts.
local type_words = { e = 'error', w = 'warning', i = 'info', n = 'note' }

local function qf_save(opts)
	local fname = vim.fn.fnamemodify(opts.args ~= '' and opts.args or 'review.qf', ':p')
	local lines = {}
	for _, e in ipairs(vim.fn.getqflist()) do
		if e.valid == 1 then
			local word = type_words[e.type:lower()]
			lines[#lines + 1] = string.format('%s|%d%s| %s', vim.fn.fnamemodify(vim.fn.bufname(e.bufnr), ':p'), e.lnum, word and ' ' .. word or '', e.text)
		end
	end
	local append = not opts.bang and vim.fn.filereadable(fname) == 1
	vim.fn.writefile(lines, fname, append and 'a' or '')
	vim.notify(string.format('QfSave: %d entries %s %s', #lines, append and 'appended to' or 'written to', vim.fn.fnamemodify(fname, ':~:.')))
end

local function qf_load(opts)
	local fname = vim.fn.fnamemodify(opts.args ~= '' and opts.args or 'review.qf', ':p')
	if vim.fn.filereadable(fname) == 0 then
		vim.notify('QfLoad: cannot read ' .. fname, vim.log.levels.ERROR)
		return
	end
	vim.fn.setqflist({}, ' ', {
		title = vim.fn.fnamemodify(fname, ':~:.'),
		lines = vim.fn.readfile(fname),
		efm = [[%f|%l %t%*\S %m,%f|%l| %m]],
	})
	vim.notify(string.format('QfLoad: %d entries from %s', vim.fn.getqflist({ size = 1 }).size, vim.fn.fnamemodify(fname, ':~:.')))
end

-- In quickfix/location windows, dd (normal, takes a count) and d (visual)
-- delete entries. The qf buffer itself is never made modifiable — we edit the
-- list ('r' = replace in place) and nvim redraws the window, so what you see
-- and where <CR> jumps can't go out of sync. After pruning, :QfSave! persists
-- the survivors.
local function del_entries(first, last)
	local win = vim.api.nvim_get_current_win()
	local isloc = vim.fn.getwininfo(win)[1].loclist == 1
	local cur = isloc and vim.fn.getloclist(win, { items = 1, title = 1 }) or vim.fn.getqflist({ items = 1, title = 1 })
	for _ = first, math.min(last, #cur.items) do
		table.remove(cur.items, first)
	end
	local what = { items = cur.items, title = cur.title }
	if isloc then
		vim.fn.setloclist(win, {}, 'r', what)
	else
		vim.fn.setqflist({}, 'r', what)
	end
	vim.fn.cursor(math.min(first, math.max(#cur.items, 1)), 1)
end

local function qf_buf_maps(buf)
	vim.keymap.set('n', 'dd', function()
		local l = vim.fn.line '.'
		del_entries(l, l + vim.v.count1 - 1)
	end, { buffer = buf, desc = 'Delete quickfix entry (keeps list in sync)' })
	vim.keymap.set('x', 'd', function()
		local a, b = vim.fn.line 'v', vim.fn.line '.'
		if a > b then
			a, b = b, a
		end
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
		del_entries(a, b)
	end, { buffer = buf, desc = 'Delete selected quickfix entries' })
end

vim.api.nvim_create_autocmd('FileType', {
	pattern = 'qf',
	group = vim.api.nvim_create_augroup('QfEditable', { clear = true }),
	callback = function(ev)
		qf_buf_maps(ev.buf)
	end,
})

-- also cover qf buffers that already exist (e.g. when :luafile-ing this)
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
	if vim.bo[buf].filetype == 'qf' then
		qf_buf_maps(buf)
	end
end

return {
	vim.api.nvim_create_user_command('QfSave', qf_save, { nargs = '?', bang = true, complete = 'file', desc = 'Save quickfix list to a text file (appends; ! overwrites)' }),
	vim.api.nvim_create_user_command('QfLoad', qf_load, { nargs = '?', complete = 'file', desc = 'Load a quickfix list saved by :QfSave (new list on the stack)' }),
}
