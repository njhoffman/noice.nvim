# TODO

Reviewed: 2026-11-05

Fork state on that date: 14 commits ahead of `upstream/main`, 0 behind (upstream's last commit is 2025-11-03, so new
upstream work exists only as open PRs and issues). Suite passes on Neovim 0.13-dev; stylua is clean.

The PR tables further down are from the 2026-03-28 review, kept as written. Section 4 records what has changed since.

## 1. Bugs

- [x] **Hover crashes on a leading empty code fence.** (p1) [bug] Upstream #1232, reproduced on this fork.
      `"```lua\n```\nhello"` through `lsp.hover.on_hover` raises `vim/treesitter/_range.lua: Index out of bounds` twice
      and no window opens. Same for zig and markdown fences; `"hello\n```lua\n```\nworld"` is fine.
      Cause: `Markdown.parse` (`lua/noice/text/markdown.lua:93`) emits the empty block plus a blank separator line, so
      the rendered message starts with blank lines that get trimmed while the markdown syntax range still counts them.
      Fix: drop code blocks with no lines, then drop a blank line left at the start of the result. Tested as an
      in-memory patch: no error, popup shows `hello`, and a fence-only hover reports "No information available". Dropping
      only the empty block does not fix it. Done in `markdown.parse`, with `tests/lsp/hover_spec.lua` and parse cases.
- [ ] **Consecutive identical messages are dropped.** (p2) [bug] Upstream #1195, closed as stale without a fix.
      `State.skip` at `lua/noice/ui/msg.lua:92` discards a `msg_show` equal to the previous one, however much later it
      arrives, so `:echo "test"` run twice shows once. Confirm dialogs repeating (#1226) look like the same family; see
      #1230 in section 4. Fix needs a way to tell a redraw replay from a real repeat. Worth checking whether the
      newer `msg_show` `id` argument (section 3) provides that.
- [ ] **Router wakes about 30 times a second while idle.** (p2) [perf] Upstream #1225, closed as stale.
      `lua/noice/message/router.lua:32` creates the interval with no `enabled` predicate, though `Util.interval` supports
      one (`lua/noice/util/init.lua:116`). Measurable idle power cost. Fix: stop the timer when nothing is pending and
      restart it from `Manager.add`; needs care so a message added while stopped is not missed.
- [ ] **`Manager.add` may still hit the fast-event error.** (p3) [bug] Upstream #1196 (E5560, `localtime` in a fast event).
      `Message:init` already uses `os.time()`, but `lua/noice/message/manager.lua:24` still calls `vim.fn.localtime()`.
      Not reproduced; whether it can run in a fast context needs checking. Fix: use `os.time()` there too.
- [ ] **`checkhealth.info` calls an undefined global.** (p3) [bug] `lua/noice/health.lua:24` calls `info`, but the
      locals at the top of the file define only `start`, `ok`, `warn` and `error`. Latent: nothing calls `log.info` on
      that path today. Fix: add `local info = vim.health.info`. This is one of the 8 selene errors.

## 2. Overrides in ~/.config/nvim

- [x] **Retire the telescope extension shadow.** (p2) [chore] `~/.config/nvim/lua/telescope/_extensions/noice.lua` is an
      old copy that shadows this repo's module. It has nothing the repo lacks: its diff is only removals plus import
      order. It loses the numeric `hl_group` handling, preview `wrap`, and the open-in-float mapping. Nothing in the
      config references the extension by name. Fix: delete it from the config; no roll-in needed.
- [x] **Roll in the notify logging override.** (p2) [feature] The config's copy of `lua/noice/view/backend/notify.lua`
      replaced the repo file and would silently miss future fixes. Added an `on_notify` view option on the notify backend
      only; the config's `configs/noice/views.lua` passes its logger and both shadow files are gone. The hook gets the
      level the notification actually uses, so route `level` overrides now log correctly. Option applies only to the
      `notify` backend, not `snacks`.
- [x] **Statusline and silence counts read `#_history`.** (p2) [bug] `_history` is keyed by message id
      (`lua/noice/message/manager.lua:25`), so `#` was unreliable; a table holding ids 10-12 gives 0. After `:NoiceFlush`
      the count stayed near 0 for good. Added `api.history.count` and `api.history.clear`; the config's bars, feline,
      lualine, windline and `silence.lua` now use them, and `tests/unit/silence_spec.lua` guards against `_history`.
- [x] **`:Silence` routes never match.** (p2) [bug] `lua/core/commands/silence.lua` in the config filtered on
      `event = "msg_show.*"`, but the `event` filter is an exact comparison (`lua/noice/message/filter.lua:51-56`).
      Fixing the filter alone would not have worked: `noice.setup()` at runtime resets all options to defaults and appends
      routes after the existing ones, where they never win, and `config.routes` does not exist, so nothing was restored.
      Each `:Silence` was wiping your noice config until restart. Now uses `Router.add(route, 1)`, removes the route on
      stop, and leaves confirm-type prompts visible. Covered by `tests/unit/silence_spec.lua` in the config. It relies on
      the internal `Router._routes`, so a public route add/remove API would be cleaner.
- [ ] **Give the CodeCompanion progress bridge a public API.** (p3) [feature] `configs/codecompanion/extensions/
      notify-noice.lua` drives `Message`, `Manager`, `Router` and `Format` internals to fake LSP progress. Works today but
      breaks silently on refactors. A small exported "progress message" helper would let it stop reaching in.
- [ ] **Move stock noice defaults out of `configs/noice/`.** (p3) [chore] Check which entries in the config's `lsp.lua`
      and `views.lua` just repeat defaults, now that the plugin is under your control. Also note `lsp.override` enables
      `vim.lsp.util.stylize_markdown`, deprecated in Neovim's `deprecated.txt`; see section 3.

## 3. Neovim 0.11-0.13 compatibility

- [ ] **`msg_show` handler ignores newer event arguments.** (p2) [bug] Current signature is `kind, content, replace_last,
      history, append, id, trigger`; `M.on_show` (`lua/noice/ui/msg.lua:85`) reads only the first three. Expected
      effects, from reading the code and not yet observed: `append` output (`:echon`) splits into separate messages;
      `history = false` messages land in history; messages updated by `id` stack instead of replacing. Upstream #1197
      (`:verbose set` losing "Last set from") may be related. Fix: capture real events with `debug = true`, then
      handle `append` and `id` first.
- [ ] **Decide the position on ui2.** (p3) [feature] Upstream #1201: with `vim._core.ui2` enabled the native cmdline shows
      alongside noice's. The repo has no ui2 handling and your config does not enable it, so nothing is broken for you
      today. Minimum: a `:checkhealth` warning. Longer term: decide whether noice should coexist with it at all.
- [ ] **Plan for `stylize_markdown` removal.** (p3) [chore] `lua/noice/lsp/override.lua:22-23` and `health.lua:191-193`
      depend on a function deprecated upstream. Still present on 0.13-dev. Health check indexes it directly, so
      guard that before it disappears.
- [ ] **Remove unreachable compat branches.** (p3) [refactor] Minimum is now 0.10, so `require_language`
      (`lua/noice/text/treesitter.lua:26`) and the `query.get_query` fallback (`treesitter.lua:7`) cannot run.
      `get_query` no longer exists on 0.13-dev. The `get_lang` guards above them can go too.

## 4. Upstream PRs since the March review

None of these is merged here. "Applies" means `git apply --check` passed against this fork on 2026-11-05; behavior was
reviewed by reading the diff and has not been run.

- [ ] **Take #1231 for multi-client hover.** (p2) [bug] Applies. A single `K` with several clients focuses the float and
      shows only the first answer. Uses `buf_request_all` and merges results. Recommended over #1177 from the March table,
      which targets the same problem. Note it changes the `on_hover` signature, so the #1232 regression spec should
      be written against whichever is merged first.
- [ ] **Take #1230 for confirm popups, with a fix.** (p2) [bug] Applies. Fixes empty and repeated confirm windows (#1178,
      likely #1226). Concern: the scheduled closure reads `M.confirm.hidden`, but `M.confirm` can be set to nil before it
      runs, which would raise inside `vim.schedule`. Capture the table in a local first.
- [ ] **Take #1215 for signature focus stealing.** (p2) [bug] Applies. One-line `focus()` to `win()` change, and you run
      `signature.auto_open`. Side effect: a manual signature request no longer jumps into an open window.
- [ ] **Take #1207 for longer code fences, with cleanup.** (p3) [feature] Applies. Stores the closing pattern in a
      module-level variable; a local would do. A closing line is matched by prefix, so longer fences and fences with
      info strings also close the block.
- [ ] **Take #1216 for `lsp.signature.silent`.** (p3) [feature] Applies. Small, mirrors `lsp.hover.silent`.
- [ ] **Review #1218 before taking.** (p3) [bug] Applies. Flips the completion popup above the cursor near the bottom.
      Compares `screenrow()` (editor-wide) with `winheight(0)` (window), so it can misjudge with splits or a tabline, and
      uses `#state.items` as height. Your config places the popupmenu with `relative = "editor"`, so check whether this
      path runs for you at all.
- [ ] **Optional: #1200 and #1220.** (p3) [feature] Both apply. #1200 renders markdown headings via `MarkdownH1`-style
      groups, which your colorscheme would need to define. #1220 is a docs-only icon fix.
- [ ] **Consider #1212 for Neovide transparency.** (p3) [bug] Applies. Keeps user `winblend` on multigrid UIs. Only matters
      if you use Neovide, which `~/.config/neovide/` suggests. `multigrid_ui` is never reset once set and is only
      re-checked on `ColorScheme`, so a UI attaching later can be missed.
- [ ] **Update the March tables.** (p3) [docs] #1194 is now closed upstream, unmerged, though the patch still applies.
      #1066 and #1041 still conflict. #1228 and #1213 conflict only because this fork already made those changes
      (b40e59c, 664667b), so neither needs action. #1186 is no longer needed: `api.history.clear` covers it and also
      keeps messages not yet routed, which #1186 drops when called with no filter.

## 5. Repo maintenance

- [ ] **Convert the older changelog sections.** (p3) [chore] New sections use Keep a Changelog, from 4.13.0 on. Everything
      from 4.12.0 down is still in release-please format, and v4.11.0 and v4.12.0 stay untagged by decision (no backfill).
      Decide whether the old sections are worth converting; `.github/workflows` should also not regenerate this file.
- [ ] **Document the fork's `tail` option in the README.** (p2) [docs] Added to `doc/noice.nvim.txt` only (line 530).
      Upstream generates that file from the README, so a regenerate would remove it. Check other fork-only options at
      the same time.
- [ ] **Make selene pass.** (p3) [chore] 8 errors, 23 warnings. 7 errors are `bit` missing from `vim.yml` (false positive,
      add it to globals); the 8th is the `health.lua` bug in section 1. Then clear the unused-variable warnings.
- [ ] **Find out why views do not open under the test runner.** (p3) [test] Under `scripts/test`, noice is already disabled
      by the time specs run, and the hover window never opened even after `enable()` and `Router.update()`. Cause not
      found, so `tests/lsp/hover_spec.lua` runs `tests/lsp/hover_driver.lua` in a clean subprocess. Fixing this would
      make view-level specs simple. Separately, `lazy.minit` updates plugins on each run unless `LAZY_OFFLINE` is set.
- [ ] **Add tests for the untested core.** (p2) [test] Specs cover filter, manager, markdown parsing, ffi and `tail`.
      `ui/msg`, `ui/cmdline`, `router` and `lsp/*` have none, which is where the bugs above live. Start with hover and
      `msg_show` event handling.
- [ ] **Settle the fork's identity in repo metadata.** (p3) [chore] `lazy.lua` still names `folke/noice.nvim`, and
      the CI and update workflows call `folke/github`. On GitHub the repo is not marked as a fork. Decide what should
      point at this repo; check how `lazy.lua` behaves under your `njhoffman/noice.nvim` spec before changing it.

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
