# gitignore-templates.nvim

Neovim plugin to fetch, cache, and apply `.gitignore` templates from the official [github/gitignore](https://github.com/github/gitignore) repository.

## Usage

Configure with `lazy.nvim`:

```lua
{
  "artumont/gitignore-templates.nvim",
  cmd = { "Gitignore", "GitignoreUpdate", "GitignoreClear" },
  opts = {},
}
```

## Setup

```lua
require("gitignore-templates").setup({
  -- All options are optional; defaults shown below
  cache_dir = vim.fn.stdpath("cache") .. "/gitignore-templates/",
  base_url = "https://raw.githubusercontent.com/github/gitignore/main/",
  api_url = "https://api.github.com/repos/github/gitignore/git/trees/main?recursive=1",
  header = "### Gitignore Template: %s ###",  -- set to nil to disable
  notify = true,
  prefer_cwd = true,
})
```

## Commands

| Command            | Description                                           |
| ------------------ | ----------------------------------------------------- |
| `:Gitignore`       | Open template selector, fetch and apply to .gitignore |
| `:GitignoreUpdate` | Refresh the template list from GitHub API             |
| `:GitignoreClear`  | Clear all cached templates and list                   |

## Telescope Integration

If you have [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) installed:

```lua
require("telescope").load_extension("gitignore")
```

Then use:

```vim
:Telescope gitignore
```

This gives you fuzzy search over all templates with a preview pane showing cached template contents.
