local M = {}
local config = require("buffermind.config").get()
local Job = require("plenary.job")

function M.find_chat_buffer()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if
			vim.api.nvim_buf_is_loaded(buf)
			and vim.api.nvim_buf_get_name(buf):match(".*buffermind." .. config.platform .. ".md")
		then
			return buf
		end
	end
end

function M.reset_chat_buffer()
	-- Close the current chat buffer without saving any changes
	vim.cmd("bwipeout!")

	-- Reopen the chat buffer to its original state
	M.open_chat_buffer()
end

function M.open_chat_buffer()
	-- Store the current window to return focus later
	local current_win = vim.api.nvim_get_current_win()

	-- Open a new vertical split on the right
	vim.cmd("vsplit")
	local chat_win = vim.api.nvim_get_current_win()

	-- Set up the new buffer for the chat in the right window
	vim.cmd("enew") -- Open a new buffer in the newly created split
	vim.bo.buftype = "nofile"
	vim.bo.bufhidden = "hide"
	vim.bo.swapfile = false
	vim.api.nvim_buf_set_name(0, "buffermind." .. config.platform .. ".md")

	-- Determine the full path to 'prompt.md' in the plugin directory
	local plugin_dir = debug.getinfo(1).source:match("@?(.*/)")
	local prompt_file_path = plugin_dir .. "prompt.md"

	-- Load content from the 'prompt.md' file
	local file = io.open(prompt_file_path, "r")

	local lines
	if file then
		local prompt_content = file:read("*a")
		file:close()
		lines = vim.split(prompt_content, "\n", true)
	else
		lines = { "```", "```" }
		print("Failed to open prompt file: " .. prompt_file_path)
	end

	table.insert(lines, "You: ")

	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

	-- Define a local function for highlighting and concealing
	local function apply_highlights_and_conceal_code()
		local buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1) -- Clear previous highlights

		local n_lines = vim.api.nvim_buf_line_count(buf)
		for i = 0, n_lines - 1 do
			local line = vim.api.nvim_buf_get_lines(buf, i, i + 1, false)[1]
			if line:match("^You:") then
				vim.api.nvim_buf_add_highlight(buf, -1, "Keyword", i, 0, 3) -- Highlight "You:"
			elseif line:match("^Assistant:") then
				vim.api.nvim_buf_add_highlight(buf, -1, "Constant", i, 0, 9) -- Highlight "Assistant:"
			end
		end
	end

	-- Apply initial highlights and concealment
	apply_highlights_and_conceal_code()

	vim.api.nvim_create_augroup("ChatBufferHighlights", { clear = true })
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		callback = apply_highlights_and_conceal_code,
		buffer = 0,
		group = "ChatBufferHighlights",
	})

	vim.api.nvim_buf_set_keymap(
		0,
		"n",
		"<C-]>",
		'<cmd>lua require("buffermind.chat").send_message()<CR>',
		{ noremap = true, silent = true }
	)

	vim.api.nvim_buf_set_keymap(
		0,
		"i",
		"<C-]>",
		'<cmd>lua require("buffermind.chat").send_message()<CR>',
		{ noremap = true, silent = true }
	)

	vim.api.nvim_win_set_cursor(chat_win, { #lines, 5 }) -- Start at "You: " position
end

function M.send_message()
	-- Collect contents from all open buffers
	local all_buffers_content = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			table.insert(all_buffers_content, table.concat(lines, "\n"))
		end
	end
	local full_prompt = table.concat(all_buffers_content, "\n")

	local api_key
	if config.platform == "openai" then
		api_key = os.getenv("OPENAI_API_KEY")
	elseif config.platform == "claude" then
		api_key = os.getenv("ANTHROPIC_API_KEY")
	else
		print("Invalid platform specified:", config.platform)
		return
	end
	if not api_key or api_key == "" then
		print("API Key not found or empty for the platform:", config.platform)
		return
	end
	local url, request_data, headers
	if config.platform == "openai" then
		url = "https://api.openai.com/v1/chat/completions"
		request_data = vim.fn.json_encode({
			model = config.model,
			messages = { { role = "user", content = full_prompt } },
			stream = true,
		})
		headers = {
			"-H",
			"Authorization: Bearer " .. api_key,
			"-H",
			"Content-Type: application/json",
		}
	elseif config.platform == "claude" then
		url = "https://api.anthropic.com/v1/complete"
		request_data = vim.fn.json_encode({
			model = config.model,
			prompt = "\n\nHuman: " .. full_prompt .. "\n\nAssistant:",
			stream = true,
			max_tokens_to_sample = 300,
		})
		headers = {
			"-H",
			"X-API-Key: " .. api_key,
			"-H",
			"Content-Type: application/json",
			"-H",
			"anthropic-version: 2023-06-01",
		}
	end
	local buffer = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "Assistant:" })
	vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "" })
	local response_start_line = vim.api.nvim_buf_line_count(buffer)
	local args = vim.list_extend({ "-s", "-X", "POST" }, headers)
	args = vim.list_extend(args, { "-d", request_data, url })
	Job:new({
		command = "curl",
		args = args,
		on_stdout = function(_, data)
			if not data or data == "" then
				return
			end
			local lines = vim.split(data, "\n")
			vim.schedule(function()
				for _, line in ipairs(lines) do
					line = line:gsub("^data: ", "")
					if line ~= "[DONE]" and line ~= "" then
						local success, decoded_chunk = pcall(vim.fn.json_decode, line)
						if success and decoded_chunk then
							local content
							if config.platform == "openai" then
								content = decoded_chunk.choices
									and decoded_chunk.choices[1]
									and decoded_chunk.choices[1].delta
									and decoded_chunk.choices[1].delta.content
							elseif config.platform == "claude" then
								content = decoded_chunk.completion
							end
							if content then
								if vim.api.nvim_buf_is_valid(buffer) then
									local current_lines =
										vim.api.nvim_buf_get_lines(buffer, response_start_line - 1, -1, false)
									local last_line = current_lines[#current_lines]
									local new_lines = vim.split(content, "\n", true)
									current_lines[#current_lines] = last_line .. new_lines[1]
									for i = 2, #new_lines do
										table.insert(current_lines, new_lines[i])
									end
									vim.api.nvim_buf_set_lines(
										buffer,
										response_start_line - 1,
										-1,
										false,
										current_lines
									)

									local last_line_num = vim.api.nvim_buf_line_count(buffer)
									local last_col =
										#vim.api.nvim_buf_get_lines(buffer, last_line_num - 1, last_line_num, false)[1]
									vim.api.nvim_win_set_cursor(0, { last_line_num, last_col })
								end
							end
						end
					end
				end
			end)
		end,
		on_stderr = function(_, err)
			if err and err ~= "" then
				vim.schedule(function()
					print("Error while streaming: ", err)
				end)
			end
		end,
		on_exit = function(_, return_val)
			print("Job exited with return value:", return_val)
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(buffer) then
					vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "", "You: " })
					local last_line_num = vim.api.nvim_buf_line_count(buffer)
					vim.api.nvim_win_set_cursor(0, { last_line_num, 5 })
				end
			end)
		end,
	}):start()
end

return M
