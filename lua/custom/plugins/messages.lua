local function open_messages_in_buffer()
	local messages = vim.fn.execute("messages")
	vim.cmd("enew") -- Use 'enew' to ensure a new buffer is created in a more predictable manner
	vim.bo.buftype = 'nofile'
	vim.bo.bufhidden = 'hide'
	vim.bo.swapfile = false
	vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(messages, '\n'))
	vim.bo.readonly = true
end
vim.api.nvim_create_user_command('OpenMessages', open_messages_in_buffer, {})
return {}
