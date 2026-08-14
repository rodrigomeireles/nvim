return {
	'hat0uma/csvview.nvim',
	ft = { 'csv', 'tsv' },
	cmd = { 'CsvViewEnable', 'CsvViewDisable', 'CsvViewToggle' },
	---@module 'csvview'
	---@type CsvView.Options
	opts = {
		parser = { comments = { '#', '//' } },
		keymaps = {
			textobject_field_inner = { 'if', mode = { 'o', 'x' } },
			textobject_field_outer = { 'af', mode = { 'o', 'x' } },
			jump_next_field_end = { '<Tab>', mode = { 'n', 'v' } },
			jump_prev_field_end = { '<S-Tab>', mode = { 'n', 'v' } },
			jump_next_row = { '<Enter>', mode = { 'n', 'v' } },
			jump_prev_row = { '<S-Enter>', mode = { 'n', 'v' } },
		},
	},
	config = function(_, opts)
		require('csvview').setup(opts)

		-- ft-triggered lazy-load fires config() after the buffer's own
		-- FileType event already ran, so the autocmd below misses it;
		-- catch that first buffer explicitly.
		vim.api.nvim_create_autocmd('FileType', {
			group = vim.api.nvim_create_augroup('CsvViewAutoEnable', { clear = true }),
			pattern = { 'csv', 'tsv' },
			callback = function()
				vim.cmd.CsvViewEnable()
			end,
		})
		if vim.tbl_contains({ 'csv', 'tsv' }, vim.bo.filetype) then
			vim.cmd.CsvViewEnable()
		end
	end,
}
