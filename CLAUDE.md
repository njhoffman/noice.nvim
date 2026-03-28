# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Noice.nvim is a Neovim plugin that replaces the UI for messages, cmdline, and popupmenu using the `vim.ui_attach` API. It's a fork/mirror of [folke/noice.nvim](https://github.com/folke/noice.nvim). Requires Neovim 0.10.0+.

## Commands

### Testing
```bash
./scripts/test                    # Run all tests (uses lazy.nvim minitest)
nvim -l tests/minit.lua --minitest tests/text/markdown_spec.lua  # Run single test file
```

Tests bootstrap lazy.nvim into `.tests/` directory. Test files use `_spec.lua` suffix in `tests/`.

### Formatting & Linting
```bash
stylua lua/                       # Format (2-space indent, 120 col width, sort requires)
selene lua/                       # Lint (vim std)
```

### CI
CI delegates to `folke/github/.github/workflows/ci.yml@main` - runs on push to main and PRs.

## Architecture

### Data Flow
```
Neovim UI events --> UI Handlers (msg, cmdline, popupmenu)
                         |
                    Message Manager (store + tick tracking)
                         |
                    Router (filter messages against routes ~30Hz)
                         |
                    Views (notify, popup, split, virtualtext, mini, snacks, notify_send)
```

### Key Modules

| Module | Purpose |
|--------|---------|
| `lua/noice/init.lua` | Entry point: `setup()`, `enable()`, `disable()` |
| `lua/noice/config/` | Configuration defaults, routes, views, presets, highlights |
| `lua/noice/message/router.lua` | Core routing engine - matches messages to views via filters |
| `lua/noice/message/filter.lua` | Declarative filter system (event, kind, level, find, cond, any/not) |
| `lua/noice/message/manager.lua` | Message store with tick-based change detection |
| `lua/noice/ui/` | Neovim UI attachment and event handlers (msg.lua, cmdline.lua, popupmenu/) |
| `lua/noice/view/` | Abstract view base + backends in `view/backend/` |
| `lua/noice/text/block.lua` | Base text container (NuiLine arrays), parent class of Message |
| `lua/noice/lsp/` | LSP hover, signature, progress - hooks into `vim.lsp.util` |
| `lua/noice/source/notify.lua` | Replaces `vim.notify` to route notifications through the system |

### Key Patterns

- **OOP via nui.object**: `NoiceMessage` extends `NoiceBlock`, `NoiceView` is the abstract view base
- **Lazy loading**: All modules use `require = require("noice.util.lazy")` for deferred requires
- **Error protection**: `Util.protect(fn)` wraps handlers to prevent errors from breaking the event loop
- **Route = filter + view**: Routes are ordered; first matching route wins (unless `opts.stop = false`)
- **Tick-based updates**: Manager increments tick on changes; Router skips processing when tick is unchanged

### Dependencies

- **nui.nvim** (required): Provides popup/split windows, NuiLine/NuiText primitives, object system
- **nvim-notify** (optional): Notification backend
- **snacks.nvim** (optional): Alternative notification backend
