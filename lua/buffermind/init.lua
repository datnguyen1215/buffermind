local chat = require("buffermind.chat")
local config = require("buffermind.config")

config.setup()

-- Set up commands and key mappings
vim.api.nvim_create_user_command("ChatReset", chat.reset_chat_buffer, {})

vim.api.nvim_create_user_command("ChatOpen", function(opts)
	local filename = opts.args or nil
	local chat_buf = chat.find_chat_buffer()
	-- print error logs if chat_buf is nil
	print("Chat buffer not found")

	if chat_buf then
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			local buf = vim.api.nvim_win_get_buf(win)
			if buf == chat_buf then
				vim.api.nvim_set_current_win(win)
				return
			end
		end
		vim.cmd("vsplit")
		vim.api.nvim_win_set_buf(0, chat_buf)
	else
		chat.open_chat(filename)
	end
end, { nargs = "?" })

-- Key mapping for <leader>chc to open chat
vim.api.nvim_set_keymap("n", "<leader>cho", "<cmd>ChatOpen<CR>", { noremap = true, silent = true })
vim.api.nvim_set_keymap("n", "<leader>chp", "<cmd>ChatOpen programmer.md<CR>", { noremap = true, silent = true })
