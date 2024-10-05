local M = {}
local config = require("buffermind.config").get()
local Job = require("plenary.job")

-- save the initial prompt when opened chat buffer
local initial_prompt = nil

local ns_id = vim.api.nvim_create_namespace("chat_highlight_namespace")

local function clear_namespace_highlights()
	vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)
end

local function apply_line_highlights()
	-- Get all lines in the buffer
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	for i, line in ipairs(lines) do
		if line:find("^You:") then
			-- Apply highlight for "You:"
			vim.api.nvim_buf_add_highlight(0, ns_id, "Keyword", i - 1, 0, 4)
		elseif line:find("^Assistant:") then
			-- Apply highlight for "Assistant:"
			vim.api.nvim_buf_add_highlight(0, ns_id, "Identifier", i - 1, 0, 10)
		end
	end
end

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

local function open_vertical_split()
	-- save the current buffer
	local new_buf = vim.api.nvim_create_buf(true, true)

	-- Create a new vertical split and return the new window ID
	vim.cmd("vsplit")
	local chat_win = vim.api.nvim_get_current_win()

	-- set the new buffer to the current window
	vim.api.nvim_win_set_buf(chat_win, new_buf)

	return chat_win
end

local function get_plugin_path()
	local plugin_dir = debug.getinfo(1).source:match("@?(.*/)")
	return plugin_dir
end

local function get_prompt(filename)
	local plugin_dir = get_plugin_path()
	local prompt_path = plugin_dir .. "prompts/" .. filename
	print("Prompt path: " .. prompt_path)
	local file = io.open(prompt_path, "r")
	if not file then
		print("Failed to open prompt file: " .. prompt_path)
		return ""
	end
	local content = file:read("*a")
	file:close()
	return content
end

local function set_buffer_options()
	vim.bo.buftype = "nofile"
	vim.bo.bufhidden = "hide"
	vim.bo.swapfile = false
	vim.bo.filetype = "markdown"
	vim.api.nvim_buf_set_name(0, "buffermind." .. config.platform .. ".md")
end

local function apply_highlights_and_conceal()
	local function highlight_code()
		clear_namespace_highlights()
		apply_line_highlights()
	end

	highlight_code()

	vim.api.nvim_create_augroup("ChatBufferHighlights", { clear = true })
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		callback = highlight_code,
		buffer = 0,
		group = "ChatBufferHighlights",
	})
end

local function set_buffer_keymaps(func_name)
	local map_options = { noremap = true, silent = true }

	vim.api.nvim_buf_set_keymap(0, "n", "<C-r>", "<cmd>ChatReset<CR>", { noremap = true, silent = true })
	vim.api.nvim_buf_set_keymap(0, "i", "<C-r>", "<cmd>ChatReset<CR>", { noremap = true, silent = true })

	vim.api.nvim_buf_set_keymap(0, "n", "<C-c>", "<cmd>bd<CR>", { noremap = true, silent = true })
	vim.api.nvim_buf_set_keymap(0, "i", "<C-c>", "<cmd>bd<CR>", { noremap = true, silent = true })

	-- change send_message to func_name
	vim.api.nvim_buf_set_keymap(
		0,
		"n",
		"<C-]>",
		'<cmd>lua require("buffermind.chat").' .. func_name .. "()<CR>",
		map_options
	)
	vim.api.nvim_buf_set_keymap(
		0,
		"i",
		"<C-]>",
		'<cmd>lua require("buffermind.chat").' .. func_name .. "()<CR>",
		map_options
	)
end

function M.open_chat(filename)
	local chat_win = open_vertical_split()

	local prompt = "You: "

	-- if filename is not nil, then get the prompt from the file
	print(filename)
	if filename ~= "" then
		prompt = get_prompt(filename)
		prompt = prompt .. "\nYou: "
	end

	initial_prompt = vim.split(prompt, "\n", true)

	-- set initial prompt on the openned buffer
	vim.api.nvim_buf_set_lines(0, 0, -1, false, initial_prompt)

	set_buffer_options()
	apply_highlights_and_conceal()

	if filename == "" then
		set_buffer_keymaps("send_message")
	else
		set_buffer_keymaps("send_message_with_buffers")
	end

	vim.api.nvim_win_set_cursor(chat_win, { #initial_prompt, 5 })
end

function M.reset_chat_buffer()
	-- replace the enter buffer with the initial prompt, do not open a new buffer
	local chat_win = vim.api.nvim_get_current_win()
	vim.api.nvim_buf_set_lines(0, 0, -1, false, initial_prompt)
	vim.api.nvim_win_set_cursor(chat_win, { #initial_prompt, 5 })
end

local function get_all_buffers_content()
	local all_buffers_content = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			local buf_name = vim.api.nvim_buf_get_name(buf)
			if not buf_name:match("buffermind%..*%.md") then -- Exclude files matching buffermind.*.md
				local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				table.insert(all_buffers_content, "File: " .. (buf_name ~= "" and buf_name or "[No Name]"))
				table.insert(all_buffers_content, table.concat(lines, "\n"))
			end
		end
	end
	return table.concat(all_buffers_content, "\n")
end

function M.send_message(context)
	-- Convert the context into a usable string
	if context == nil then
		context = ""
	end

	-- include the current buffer's content
	local current_buffer_content = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local full_prompt = context .. "\n" .. table.concat(current_buffer_content, "\n")

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

function M.send_message_with_buffers()
	local all_buffers_content = get_all_buffers_content()
	M.send_message(all_buffers_content)
end

-- function M.send_message()
-- 	-- Collect contents from all open buffers
-- 	local all_buffers_content = {}
-- 	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
-- 		if vim.api.nvim_buf_is_loaded(buf) then
-- 			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
-- 			table.insert(all_buffers_content, table.concat(lines, "\n"))
-- 		end
-- 	end
-- 	local full_prompt = table.concat(all_buffers_content, "\n")
--
-- 	local api_key
-- 	if config.platform == "openai" then
-- 		api_key = os.getenv("OPENAI_API_KEY")
-- 	elseif config.platform == "claude" then
-- 		api_key = os.getenv("ANTHROPIC_API_KEY")
-- 	else
-- 		print("Invalid platform specified:", config.platform)
-- 		return
-- 	end
-- 	if not api_key or api_key == "" then
-- 		print("API Key not found or empty for the platform:", config.platform)
-- 		return
-- 	end
-- 	local url, request_data, headers
-- 	if config.platform == "openai" then
-- 		url = "https://api.openai.com/v1/chat/completions"
-- 		request_data = vim.fn.json_encode({
-- 			model = config.model,
-- 			messages = { { role = "user", content = full_prompt } },
-- 			stream = true,
-- 		})
-- 		headers = {
-- 			"-H",
-- 			"Authorization: Bearer " .. api_key,
-- 			"-H",
-- 			"Content-Type: application/json",
-- 		}
-- 	elseif config.platform == "claude" then
-- 		url = "https://api.anthropic.com/v1/complete"
-- 		request_data = vim.fn.json_encode({
-- 			model = config.model,
-- 			prompt = "\n\nHuman: " .. full_prompt .. "\n\nAssistant:",
-- 			stream = true,
-- 			max_tokens_to_sample = 300,
-- 		})
-- 		headers = {
-- 			"-H",
-- 			"X-API-Key: " .. api_key,
-- 			"-H",
-- 			"Content-Type: application/json",
-- 			"-H",
-- 			"anthropic-version: 2023-06-01",
-- 		}
-- 	end
-- 	local buffer = vim.api.nvim_get_current_buf()
-- 	vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "Assistant:" })
-- 	vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "" })
-- 	local response_start_line = vim.api.nvim_buf_line_count(buffer)
-- 	local args = vim.list_extend({ "-s", "-X", "POST" }, headers)
-- 	args = vim.list_extend(args, { "-d", request_data, url })
-- 	Job:new({
-- 		command = "curl",
-- 		args = args,
-- 		on_stdout = function(_, data)
-- 			if not data or data == "" then
-- 				return
-- 			end
-- 			local lines = vim.split(data, "\n")
-- 			vim.schedule(function()
-- 				for _, line in ipairs(lines) do
-- 					line = line:gsub("^data: ", "")
-- 					if line ~= "[DONE]" and line ~= "" then
-- 						local success, decoded_chunk = pcall(vim.fn.json_decode, line)
-- 						if success and decoded_chunk then
-- 							local content
-- 							if config.platform == "openai" then
-- 								content = decoded_chunk.choices
-- 									and decoded_chunk.choices[1]
-- 									and decoded_chunk.choices[1].delta
-- 									and decoded_chunk.choices[1].delta.content
-- 							elseif config.platform == "claude" then
-- 								content = decoded_chunk.completion
-- 							end
-- 							if content then
-- 								if vim.api.nvim_buf_is_valid(buffer) then
-- 									local current_lines =
-- 										vim.api.nvim_buf_get_lines(buffer, response_start_line - 1, -1, false)
-- 									local last_line = current_lines[#current_lines]
-- 									local new_lines = vim.split(content, "\n", true)
-- 									current_lines[#current_lines] = last_line .. new_lines[1]
-- 									for i = 2, #new_lines do
-- 										table.insert(current_lines, new_lines[i])
-- 									end
-- 									vim.api.nvim_buf_set_lines(
-- 										buffer,
-- 										response_start_line - 1,
-- 										-1,
-- 										false,
-- 										current_lines
-- 									)
--
-- 									local last_line_num = vim.api.nvim_buf_line_count(buffer)
-- 									local last_col =
-- 										#vim.api.nvim_buf_get_lines(buffer, last_line_num - 1, last_line_num, false)[1]
-- 									vim.api.nvim_win_set_cursor(0, { last_line_num, last_col })
-- 								end
-- 							end
-- 						end
-- 					end
-- 				end
-- 			end)
-- 		end,
-- 		on_stderr = function(_, err)
-- 			if err and err ~= "" then
-- 				vim.schedule(function()
-- 					print("Error while streaming: ", err)
-- 				end)
-- 			end
-- 		end,
-- 		on_exit = function(_, return_val)
-- 			print("Job exited with return value:", return_val)
-- 			vim.schedule(function()
-- 				if vim.api.nvim_buf_is_valid(buffer) then
-- 					vim.api.nvim_buf_set_lines(buffer, -1, -1, false, { "", "You: " })
-- 					local last_line_num = vim.api.nvim_buf_line_count(buffer)
-- 					vim.api.nvim_win_set_cursor(0, { last_line_num, 5 })
-- 				end
-- 			end)
-- 		end,
-- 	}):start()
-- end

return M
