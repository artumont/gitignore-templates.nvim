--- Optional Telescope extension for gitignore-templates.nvim
--- Provides a picker with preview support for cached templates.
---
--- Usage:
---   require("telescope").load_extension("gitignore")
---   :Telescope gitignore

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  return
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local gitignore = require("gitignore-templates")

--- Build a human-readable display name from a template path.
--- @param path string e.g. "Global/macOS.gitignore"
--- @return string e.g. "Global/macOS"
local function display_name(path)
  return path:gsub("%.gitignore$", "")
end

--- Try to read a cached template for preview.
--- @param template_path string
--- @return string|nil
local function read_cached(template_path)
  local cache_file = gitignore.config.cache_dir .. "templates/" .. template_path
  local f = io.open(cache_file, "r")
  if f then
    local content = f:read("*a")
    f:close()
    return content
  end
  return nil
end

--- The main gitignore Telescope picker.
--- @param opts table|nil Telescope picker options
local function gitignore_picker(opts)
  opts = opts or {}

  -- Resolve the template list (cache -> bundled)
  local templates = {}
  local cache_list = gitignore.config.cache_dir .. "list.json"
  local f = io.open(cache_list, "r")
  if f then
    local raw = f:read("*a")
    f:close()
    local ok, data = pcall(vim.json.decode, raw)
    if ok and type(data) == "table" then
      templates = data
    end
  end
  if #templates == 0 then
    local ok, bundled = pcall(require, "gitignore-templates.templates")
    if ok and type(bundled) == "table" then
      templates = bundled
    end
  end

  if #templates == 0 then
    vim.notify("[gitignore] No templates available. Run :GitignoreUpdate first.", vim.log.levels.WARN)
    return
  end

  pickers
    .new(opts, {
      prompt_title = "Gitignore Templates",
      finder = finders.new_table({
        results = templates,
        entry_maker = function(entry)
          return {
            value = entry,
            display = display_name(entry),
            ordinal = display_name(entry),
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        title = "Template Preview",
        define_preview = function(self, entry)
          local content = read_cached(entry.value)
          if content then
            local lines = vim.split(content, "\n")
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
            vim.bo[self.state.bufnr].filetype = "gitignore"
          else
            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
              "-- Template not cached locally --",
              "-- Will be fetched on selection --",
            })
          end
        end,
      }),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if not selection then
            return
          end
          -- Delegate to the core plugin flow
          local selected = selection.value
          local name = display_name(selected)

          vim.notify("[gitignore] Fetching " .. name .. "...", vim.log.levels.INFO)

          -- Reuse the internal fetch + write logic
          local cfg = gitignore.config
          local cache_file = cfg.cache_dir .. "templates/" .. selected

          -- Inline fetch to avoid circular dependency issues
          local cf = io.open(cache_file, "r")
          if cf then
            local tpl_content = cf:read("*a")
            cf:close()
            gitignore._apply_template(tpl_content, name)
          else
            local url = cfg.base_url .. selected
            local stdout_chunks = {}
            vim.fn.jobstart({ "curl", "-sL", "--fail", url }, {
              stdout_buffered = true,
              on_stdout = function(_, data)
                if data then
                  stdout_chunks = data
                end
              end,
              on_exit = function(_, code)
                vim.schedule(function()
                  if code ~= 0 then
                    vim.notify("[gitignore] Failed to fetch template", vim.log.levels.ERROR)
                    return
                  end
                  local tpl_content = table.concat(stdout_chunks, "\n")
                  -- Cache it
                  local dir = vim.fn.fnamemodify(cache_file, ":h")
                  if vim.fn.isdirectory(dir) == 0 then
                    vim.fn.mkdir(dir, "p")
                  end
                  local wf = io.open(cache_file, "w")
                  if wf then
                    wf:write(tpl_content)
                    wf:close()
                  end
                  gitignore._apply_template(tpl_content, name)
                end)
              end,
            })
          end
        end)
        return true
      end,
    })
    :find()
end

return telescope.register_extension({
  exports = {
    gitignore = gitignore_picker,
  },
})
