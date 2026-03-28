# TODO - Upstream PR Review

PRs from folke/noice.nvim reviewed 2026-03-28. These need changes or further discussion before merging.

## Needs Changes

| PR | Title | Issues |
|----|-------|--------|
| [#1194](https://github.com/folke/noice.nvim/pull/1194) | feat(virtualtext): configurable `virt_text_pos` | No PR description/docs. Custom position names should be documented. Non-standard naming (`right_inline`, `left_upper`, etc.) instead of Neovim extmark position names. |
| [#1186](https://github.com/folke/noice.nvim/pull/1186) | feat(message): add `clear_history` | Missing `next_tick()` on the no-filter path -- tick-based change detection is broken for full history clears. No command/API wiring (only callable via raw Lua). |
| [#1177](https://github.com/folke/noice.nvim/pull/1177) | feat(lsp): multiple LSP hover servers | Uses deprecated `vim.tbl_isempty` (replace with `next(x) == nil`). Commented-out dead code (`-- local nresults = ...`). Fix those and it's good to merge. |
| [#1140](https://github.com/folke/noice.nvim/pull/1140) | view/nui: destroy on hide | Ordering bug: `destroy()` nullifies `self._nui` before the existing hide logic reads it, so `clear()`/`unmount()` are skipped. Heavy-handed approach -- better to fix positioning in `show()` instead. |
| [#1123](https://github.com/folke/noice.nvim/pull/1123) | fix(hover): incorrect doc positions | Missing fallback for non-popup types (regression). Padding format assumption (named keys vs array). camelCase naming inconsistency (`anchorAndResizePopup` vs codebase snake_case). |
| [#1070](https://github.com/folke/noice.nvim/pull/1070) | feat: cmdline command highlighting | Scattered across 3 files with redundant highlight definitions. Uses deprecated `nvim_buf_add_highlight`. Injects cmdline-specific logic into generic `syntax.lua` module. Should be consolidated into `cmdline.lua` only. |
| [#1066](https://github.com/folke/noice.nvim/pull/1066) | fix(lsp): trigger signature help on retrigger chars | Correct fix but targets `M.on_attach()` which doesn't exist on our `main`. Needs rebase to apply to `M.check()` instead. |
| [#1041](https://github.com/folke/noice.nvim/pull/1041) | feat(fzf-lua): open notification from fzf | Conflicts with #1038 (already merged). Must be rebased on top of it. Also missing the ordering fix that #1038 provides. |

## Do Not Merge

| PR | Title | Reason |
|----|-------|--------|
| [#1175](https://github.com/folke/noice.nvim/pull/1175) | fix(cmdline): blink.cmp cmdline completion | Re-enables a hack upstream deliberately disabled for 0.11+. Patches a `@deprecated` function. The fix belongs in blink.cmp, not noice. Potential `feedkeys`/`setcmdline` race condition. |

## Skipped

| PR | Title | Notes |
|----|-------|-------|
| [#1176](https://github.com/folke/noice.nvim/pull/1176) | feat(util): open for WSL | Simple, correct WSL support addition. Safe to merge when ready -- adds `powershell.exe Start-Process` branch for WSL URI opening. |
