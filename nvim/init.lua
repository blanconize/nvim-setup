-- Neovim config for the TypeScript/Next.js + Python repos. Single file on purpose.
-- Leader is <Space>. Keymap cheat sheet: README.md in the dotfiles repo.

-------------------------------------------------------------------------------
-- Options
-------------------------------------------------------------------------------
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local o = vim.opt
o.number = true
o.numberwidth = 4
o.mouse = "a"
o.clipboard = "unnamedplus"
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.softtabstop = 2
o.smartindent = true
o.ignorecase = true
o.smartcase = true
o.hlsearch = false
o.splitright = true
o.splitbelow = true
o.undofile = true
o.swapfile = false
o.backup = false
o.writebackup = false
o.updatetime = 300
o.timeoutlen = 400
o.signcolumn = "yes"
o.termguicolors = true
o.scrolloff = 4
o.foldmethod = "indent"
o.foldlevel = 99
o.showmode = false
o.completeopt = { "menu", "menuone", "noselect" }

-- Files change underneath us all the time (Claude Code edits, git checkout):
-- reload silently instead of showing stale buffers.
o.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "TermClose" }, {
  callback = function()
    if vim.fn.mode() ~= "c" and vim.fn.getcmdwintype() == "" then
      vim.cmd("checktime")
    end
  end,
})

-- Trailing whitespace: strip on save, except Markdown (two spaces = line break)
vim.api.nvim_create_autocmd("BufWritePre", {
  callback = function()
    if vim.bo.filetype == "markdown" then return end
    local view = vim.fn.winsaveview()
    vim.cmd([[keeppatterns %s/\s\+$//e]])
    vim.fn.winrestview(view)
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "gitcommit" },
  callback = function() vim.opt_local.spell = true end,
})

-- Skeleton templates, resolved relative to this file (works through the symlink)
local dotfiles = vim.fs.dirname(vim.fs.dirname(vim.uv.fs_realpath(debug.getinfo(1, "S").source:sub(2))))
local skeletons = dotfiles .. "/skeletons"
local function template(pattern, file, guard)
  vim.api.nvim_create_autocmd("BufNewFile", {
    pattern = pattern,
    callback = function(ev)
      if guard and not guard(ev.file) then return end
      vim.cmd("0r " .. skeletons .. "/" .. file)
    end,
  })
end
template("*.test.tsx", "react-typescript.test.tsx")
template("*.tsx", "react-typescript.tsx", function(f) return not f:match("%.test%.tsx$") end)
template("*content/blog*.md", "blog-post.md")
template("*.sh", "script.sh")
template("*.html", "page.html")

-------------------------------------------------------------------------------
-- Plugins (lazy.nvim)
-------------------------------------------------------------------------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  { "folke/tokyonight.nvim", priority = 1000,
    config = function() vim.cmd.colorscheme("tokyonight-night") end },

  { "nvim-lualine/lualine.nvim",
    opts = { options = { globalstatus = true, section_separators = "", component_separators = "|" } } },

  { "folke/which-key.nvim", event = "VeryLazy", opts = {} },

  -- Syntax
  { "nvim-treesitter/nvim-treesitter", branch = "main", build = ":TSUpdate", lazy = false,
    config = function()
      -- vim.g so install.sh can install the same list headlessly
      vim.g.ts_langs = { "typescript", "tsx", "javascript", "json", "html", "css", "lua",
        "python", "markdown", "markdown_inline", "bash", "yaml", "toml", "prisma", "sql",
        "kotlin", "vue", "gitcommit", "diff", "dockerfile" }
      require("nvim-treesitter").install(vim.g.ts_langs)
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          pcall(vim.treesitter.start, ev.buf)
          vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end,
      })
    end },

  -- LSP: servers installed by mason, enabled via vim.lsp.enable (mason-lspconfig v2)
  { "neovim/nvim-lspconfig" },
  { "mason-org/mason.nvim", opts = {} },
  { "mason-org/mason-lspconfig.nvim",
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
    opts = {
      ensure_installed = { "ts_ls", "basedpyright", "jsonls", "html", "cssls",
        "tailwindcss", "lua_ls", "bashls", "yamlls" },
      -- tailwindcss-language-server costs ~600 MB; start it on demand with :TailwindOn
      automatic_enable = { exclude = { "tailwindcss", "eslint" } },
    } },

  -- Linting on save via eslint_d / ruff (no resident ESLint language server)
  { "mfussenegger/nvim-lint", event = { "BufReadPost", "BufWritePost" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = {
        javascript = { "eslint_d" }, javascriptreact = { "eslint_d" },
        typescript = { "eslint_d" }, typescriptreact = { "eslint_d" },
        python = { "ruff" },
      }
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
        callback = function() lint.try_lint(nil, { ignore_errors = true }) end,
      })
      -- lazy-loaded on BufReadPost: that event has already fired for the first buffer
      lint.try_lint(nil, { ignore_errors = true })
    end },

  -- Claude Code IDE protocol (selection/context sharing, diffs as Neovim buffers).
  -- provider = "none": Claude itself runs in the tmux pane next door (see `dev`).
  { "coder/claudecode.nvim", event = "VeryLazy",
    opts = { terminal = { provider = "none" }, diff_opts = { open_in_new_tab = true } } },

  -- Completion
  { "saghen/blink.cmp", version = "1.*", event = "InsertEnter",
    opts = {
      keymap = { preset = "enter" },
      completion = { documentation = { auto_show = true } },
      sources = { default = { "lsp", "path", "buffer" } },
    } },

  -- Formatting: Prettier (project-local), ruff for Python, stylua for Lua
  { "stevearc/conform.nvim", event = "BufWritePre",
    opts = {
      -- prettier: project node_modules/.bin first, Mason-installed prettier as fallback
      formatters_by_ft = {
        javascript = { "prettier" }, javascriptreact = { "prettier" },
        typescript = { "prettier" }, typescriptreact = { "prettier" },
        json = { "prettier" }, jsonc = { "prettier" }, css = { "prettier" },
        html = { "prettier" }, markdown = { "prettier" }, yaml = { "prettier" },
        vue = { "prettier" }, python = { "ruff_format" }, lua = { "stylua" },
      },
      format_on_save = function(bufnr)
        if vim.b[bufnr].disable_autoformat then return end
        return { timeout_ms = 3000, lsp_format = "never" }
      end,
    } },

  -- Fuzzy finding (uses the fzf + rg binaries)
  { "ibhagwan/fzf-lua", opts = { winopts = { height = 0.9, width = 0.9 } } },

  -- Git
  { "lewis6991/gitsigns.nvim", opts = { current_line_blame = false } },
  { "tpope/vim-fugitive" },
  { "tpope/vim-rhubarb" },
  { "sindrets/diffview.nvim", cmd = { "DiffviewOpen", "DiffviewFileHistory" } },

  -- Tests (Vitest / pytest) in a terminal split
  { "vim-test/vim-test",
    init = function()
      vim.g["test#strategy"] = "neovim"
      vim.g["test#neovim#term_position"] = "belowright 15"
      vim.g["test#javascript#runner"] = "vitest"
      vim.g["test#javascript#vitest#executable"] = "pnpm vitest run"
      vim.g["test#python#runner"] = "pytest"
    end },

  -- File explorer as a buffer
  { "stevearc/oil.nvim", opts = { view_options = { show_hidden = true } } },
}, { rocks = { enabled = false } })

-------------------------------------------------------------------------------
-- LSP behaviour
-------------------------------------------------------------------------------
vim.diagnostic.config({ virtual_text = true, severity_sort = true })

local function organize_imports(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = "ts_ls" })) do
    local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
    params.context = { only = { "source.organizeImports" }, diagnostics = {} }
    local ok, res = pcall(client.request_sync, client, "textDocument/codeAction", params, 1500, bufnr)
    if ok and res and res.result then
      for _, action in ipairs(res.result) do
        if action.edit then vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding) end
      end
    end
  end
end

-- On save for TS/TSX: organize imports (conform runs prettier afterwards)
vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.ts", "*.tsx", "*.js", "*.jsx" },
  callback = function(ev)
    if vim.b[ev.buf].disable_autoformat then return end
    organize_imports(ev.buf)
  end,
})

-- Cap tsserver memory; Tailwind LSP only on demand
vim.lsp.config("ts_ls", { init_options = { maxTsServerMemory = 3072 } })
vim.api.nvim_create_user_command("TailwindOn", function()
  vim.lsp.enable("tailwindcss")
  vim.cmd("LspStart tailwindcss")
end, {})

vim.api.nvim_create_user_command("FormatToggle", function()
  vim.b.disable_autoformat = not vim.b.disable_autoformat
  print("autoformat " .. (vim.b.disable_autoformat and "off" or "on"))
end, {})

vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(ev)
    local map = function(keys, fn, desc)
      vim.keymap.set("n", keys, fn, { buffer = ev.buf, silent = true, desc = desc })
    end
    local fzf = require("fzf-lua")
    map("gd", fzf.lsp_definitions, "Go to definition")
    map("gy", fzf.lsp_typedefs, "Go to type definition")
    map("gi", fzf.lsp_implementations, "Go to implementation")
    map("gr", fzf.lsp_references, "References")
    map("K", vim.lsp.buf.hover, "Hover")
    map("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
    map("<leader>c", fzf.lsp_code_actions, "Code action")
    map("<leader>qf", function()
      vim.lsp.buf.code_action({ context = { only = { "quickfix" } }, apply = true })
    end, "Quick fix")
    map("<leader>o", function() organize_imports(ev.buf) end, "Organize imports")
  end,
})

-------------------------------------------------------------------------------
-- Keymaps
-------------------------------------------------------------------------------
local map = function(mode, keys, fn, desc) vim.keymap.set(mode, keys, fn, { silent = true, desc = desc }) end
local fzf = require("fzf-lua")

-- Long lines
map({ "n", "v" }, "j", "gj")
map({ "n", "v" }, "k", "gk")

-- Search
map("n", "<C-p>", fzf.git_files, "Git files")
map("n", "<C-g>", fzf.live_grep, "Grep")
map("n", "<leader>a", fzf.grep, "Grep prompt")
map("n", "<leader>A", fzf.grep_cword, "Grep word under cursor")
map("n", "<leader>l", fzf.buffers, "Buffers")
map("n", "<leader>d", fzf.diagnostics_document, "Diagnostics")
map("n", "<leader>D", fzf.diagnostics_workspace, "Workspace diagnostics")

-- Files / windows
map("n", "-", "<cmd>Oil<CR>", "Explorer (parent dir)")
map("n", "<leader>e", "<cmd>Oil<CR>", "Explorer")
map("n", "<leader>\\", "<cmd>vsplit<CR>", "Vertical split")
map("n", "<leader>/", "<cmd>split<CR>", "Horizontal split")
map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")
map("n", "<leader>w", "<cmd>w!<CR>", "Save")
map("n", "<leader>q", "<cmd>q!<CR>", "Quit")
map("n", "<leader>x", "<cmd>x<CR>", "Save & quit")

-- Git
map("n", "<leader>g", "<cmd>Git blame<CR>", "Git blame")
map("n", "<leader>gd", "<cmd>DiffviewOpen<CR>", "Diff working tree")
map("n", "<leader>gh", "<cmd>DiffviewFileHistory %<CR>", "File history")
map("n", "<leader>gs", "<cmd>Git<CR>", "Git status")
map("n", "<leader>gb", "<cmd>GBrowse<CR>", "Open on GitHub")

-- Tests
map("n", "<leader>;", "<cmd>TestNearest<CR>", "Test nearest")
map("n", "<leader>'", "<cmd>TestFile<CR>", "Test file")
map("n", "<leader>t", "<cmd>TestLast<CR>", "Test last")

-- Claude Code under <leader>k (<leader>a is grep)
map("v", "<leader>ks", "<cmd>ClaudeCodeSend<CR>", "Send selection to Claude")
map("n", "<leader>kb", "<cmd>ClaudeCodeAdd %<CR>", "Add buffer to Claude context")
map("n", "<leader>ka", "<cmd>ClaudeCodeDiffAccept<CR>", "Accept Claude diff")
map("n", "<leader>kd", "<cmd>ClaudeCodeDiffDeny<CR>", "Reject Claude diff")
map("n", "<leader>kx", "<cmd>ClaudeCodeCloseAllDiffs<CR>", "Close all Claude diffs")
map("n", "<leader>ki", "<cmd>ClaudeCodeStatus<CR>", "Claude connection status")
map("n", "<leader>kt", "<cmd>TailwindOn<CR>", "Start Tailwind LSP")
vim.api.nvim_create_autocmd("User", {
  pattern = "ClaudeCodeSendComplete",
  callback = function()
    if vim.env.TMUX then vim.fn.system({ "tmux", "select-pane", "-R" }) end
  end,
})

-- Format / config
map("n", "<leader>f", function() require("conform").format({ lsp_format = "never" }) end, "Format")
map("n", "<leader>1", "<cmd>Lazy sync<CR>", "Sync plugins")
map("n", "<leader>2", "<cmd>e " .. dotfiles .. "/nvim/init.lua<CR>", "Edit config")
map("n", "<leader>tn", "<cmd>set relativenumber!<CR>", "Toggle relative numbers")

-- Terminal: Esc leaves insert mode
map("t", "<Esc><Esc>", "<C-\\><C-n>")

-- Text objects inside quotes
vim.keymap.set("o", "q", "i'")
vim.keymap.set("o", "Q", 'i"')
