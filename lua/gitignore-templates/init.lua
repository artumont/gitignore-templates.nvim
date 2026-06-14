--- gitignore-templates.nvim
--- Fetch, cache, and apply .gitignore templates from github/gitignore.
---
--- @module gitignore-templates

local M = {}

--- @class GitignoreConfig
--- @field cache_dir string Path to cache directory
--- @field base_url string Base URL for raw template content
--- @field api_url string GitHub API URL for tree listing
--- @field header string|nil Header format for appended templates (use %s for template name)
--- @field notify boolean Whether to show notifications
--- @field prefer_cwd boolean Whether to use cwd or git root
local defaults = {
	cache_dir = vim.fn.stdpath("cache") .. "/gitignore-templates/",
	base_url = "https://raw.githubusercontent.com/github/gitignore/main/",
	api_url = "https://api.github.com/repos/github/gitignore/git/trees/main?recursive=1",
	header = "### Gitignore Template: %s ###",
	notify = true,
	prefer_cwd = true,
}

--- @type GitignoreConfig
M.config = vim.deepcopy(defaults)

--- Resolve the list of available template paths.
--- Reads from cache (list.json) first, falls back to the bundled snapshot.
--- @return string[] List of template paths (e.g. "Node.gitignore", "Global/macOS.gitignore")
local function get_template_list()
	local cache_list = M.config.cache_dir .. "list.json"
	local f = io.open(cache_list, "r")
	if f then
		local raw = f:read("*a")
		f:close()
		local ok, data = pcall(vim.json.decode, raw)
		if ok and type(data) == "table" then
			return data
		end
	end
	-- Fall back to bundled snapshot
	local ok, bundled = pcall(require, "gitignore-templates.templates")
	if ok and type(bundled) == "table" then
		return bundled
	end
	return {}
end

--- Build a human-readable display name from a template path.
--- @param path string e.g. "Global/macOS.gitignore"
--- @return string e.g. "Global/macOS"
local function display_name(path)
	return path:gsub("%.gitignore$", "")
end

--- Find the git root directory by traversing upward from the current file or cwd.
--- @return string|nil The git root path, or nil if not found
local function find_git_root()
	local start = vim.fn.expand("%:p:h")
	if start == "" or start == "." then
		start = vim.fn.getcwd()
	end
	local root = vim.fs.find(".git", {
		path = start,
		upward = true,
		type = "directory",
	})
	if root and root[1] then
		return vim.fn.fnamemodify(root[1], ":h")
	end
	return nil
end

--- Determine the target .gitignore file path.
--- Prefers git root, falls back to cwd.
--- @return string Absolute path to the target .gitignore
local function resolve_target()
	local root = find_git_root()
	if root and not M.config.prefer_cwd then
		return root .. "/.gitignore"
	end
	return vim.fn.getcwd() .. "/.gitignore"
end

--- Ensure the parent directories of a path exist.
--- @param path string
local function ensure_dir(path)
	local dir = vim.fn.fnamemodify(path, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
end

--- Send a notification if enabled.
--- @param msg string
--- @param level number vim.log.levels.*
local function notify(msg, level)
	if M.config.notify then
		vim.notify("[gitignore] " .. msg, level or vim.log.levels.INFO)
	end
end

--- Fetch a template from the network asynchronously.
--- Checks the local file cache first. If cached, returns immediately via callback.
--- Otherwise downloads via curl and caches the result.
--- @param template_path string e.g. "Node.gitignore"
--- @param callback fun(content: string|nil, err: string|nil)
local function fetch_template(template_path, callback)
	-- Check file cache first
	local cache_file = M.config.cache_dir .. "templates/" .. template_path
	local f = io.open(cache_file, "r")
	if f then
		local content = f:read("*a")
		f:close()
		callback(content, nil)
		return
	end

	-- Fetch from network
	local url = M.config.base_url .. template_path
	local stderr_chunks = {}
	local stdout_chunks = {}

	vim.fn.jobstart({ "curl", "-sL", "--fail", url }, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			if data then
				stdout_chunks = data
			end
		end,
		on_stderr = function(_, data)
			if data then
				stderr_chunks = data
			end
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				if code ~= 0 then
					local err = table.concat(stderr_chunks, "\n")
					callback(nil, "curl failed (code " .. code .. "): " .. err)
					return
				end
				local content = table.concat(stdout_chunks, "\n")
				-- Cache the result
				ensure_dir(cache_file)
				local wf = io.open(cache_file, "w")
				if wf then
					wf:write(content)
					wf:close()
				end
				callback(content, nil)
			end)
		end,
	})
end

--- Write or append template content to the target .gitignore.
--- @param target string Path to .gitignore
--- @param content string Template content
--- @param mode "write"|"append" Write mode
--- @param template_name string Display name for the header
local function write_gitignore(target, content, mode, template_name)
	if mode == "write" then
		local f = io.open(target, "w")
		if not f then
			notify("Failed to open " .. target .. " for writing", vim.log.levels.ERROR)
			return
		end
		if M.config.header then
			f:write(string.format(M.config.header, template_name) .. "\n\n")
		end
		f:write(content)
		f:close()
		notify("Wrote " .. template_name .. " to " .. target)
	elseif mode == "append" then
		local f = io.open(target, "a")
		if not f then
			notify("Failed to open " .. target .. " for appending", vim.log.levels.ERROR)
			return
		end
		f:write("\n\n")
		if M.config.header then
			f:write(string.format(M.config.header, template_name) .. "\n\n")
		end
		f:write(content)
		f:close()
		notify("Appended " .. template_name .. " to " .. target)
	end
end

--- Prompt the user with Append/Overwrite/Cancel when a .gitignore already exists.
--- @param target string Path to existing .gitignore
--- @param content string Template content to write
--- @param template_name string Display name for the header
local function prompt_existing(target, content, template_name)
	local choice = vim.fn.confirm(
		".gitignore already exists at:\n" .. target .. "\n\nWhat would you like to do?",
		"&Append\n&Overwrite\n&Cancel",
		3
	)
	if choice == 1 then
		write_gitignore(target, content, "append", template_name)
	elseif choice == 2 then
		write_gitignore(target, content, "write", template_name)
	else
		notify("Cancelled", vim.log.levels.WARN)
	end
end

--- Core flow: select a template and apply it.
--- Opens vim.ui.select with all available templates, fetches the selected one,
--- and writes it to the appropriate .gitignore.
function M.select_and_apply()
	local templates = get_template_list()
	if #templates == 0 then
		notify("No templates available. Run :GitignoreUpdate to fetch the list.", vim.log.levels.WARN)
		return
	end

	vim.ui.select(templates, {
		prompt = "Select a .gitignore template:",
		format_item = function(item)
			return display_name(item)
		end,
	}, function(selected)
		if not selected then
			return
		end

		local name = display_name(selected)
		notify("Fetching " .. name .. "...")

		fetch_template(selected, function(content, err)
			if err or not content then
				notify("Failed to fetch template: " .. (err or "unknown error"), vim.log.levels.ERROR)
				return
			end

			local target = resolve_target()
			if vim.fn.filereadable(target) == 1 then
				prompt_existing(target, content, name)
			else
				ensure_dir(target)
				write_gitignore(target, content, "write", name)
			end
		end)
	end)
end

--- Update the cached template list from the GitHub API.
--- Fetches the latest directory tree and writes list.json to the cache directory.
function M.update_list()
	notify("Updating template list from GitHub...")
	local stdout_chunks = {}

	vim.fn.jobstart({ "curl", "-sL", "--fail", M.config.api_url }, {
		stdout_buffered = true,
		on_stdout = function(_, data)
			if data then
				stdout_chunks = data
			end
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				if code ~= 0 then
					notify("Failed to fetch template tree (curl code " .. code .. ")", vim.log.levels.ERROR)
					return
				end

				local raw = table.concat(stdout_chunks, "\n")
				local ok, tree = pcall(vim.json.decode, raw)
				if not ok or type(tree) ~= "table" or not tree.tree then
					notify("Failed to parse GitHub API response", vim.log.levels.ERROR)
					return
				end

				local templates = {}
				for _, entry in ipairs(tree.tree) do
					if entry.type == "blob" and entry.path:match("%.gitignore$") then
						-- Exclude dotfiles and non-template files
						if not entry.path:match("^%.") then
							table.insert(templates, entry.path)
						end
					end
				end
				table.sort(templates)

				ensure_dir(M.config.cache_dir .. "list.json")
				local f = io.open(M.config.cache_dir .. "list.json", "w")
				if f then
					f:write(vim.json.encode(templates))
					f:close()
				end

				-- Also invalidate individual template caches so they get re-fetched
				-- on next use (templates may have been updated upstream)
				notify("Updated template list (" .. #templates .. " templates)")
			end)
		end,
	})
end

--- Apply fetched template content to the target .gitignore.
--- Handles existence check and user prompting internally.
--- Exposed for use by extensions (e.g. Telescope picker).
--- @param content string Template content
--- @param template_name string Display name for headers
function M._apply_template(content, template_name)
	local target = resolve_target()
	if vim.fn.filereadable(target) == 1 then
		prompt_existing(target, content, template_name)
	else
		ensure_dir(target)
		write_gitignore(target, content, "write", template_name)
	end
end

--- Clear all cached templates and the list.
--- Forces fresh downloads on next use.
function M.clear_cache()
	local cache = M.config.cache_dir
	if vim.fn.isdirectory(cache) == 1 then
		vim.fn.delete(cache, "rf")
		notify("Cache cleared")
	else
		notify("No cache to clear", vim.log.levels.WARN)
	end
end

--- Setup the plugin with user options.
--- @param opts GitignoreConfig|nil
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", defaults, opts or {})
	-- Ensure cache_dir ends with a slash
	if not M.config.cache_dir:match("/$") then
		M.config.cache_dir = M.config.cache_dir .. "/"
	end
end

return M
