" Vim syntax file for Garmin Monkey Style Sheets (MSS).
"
" Ported from Garmin's official Monkey C VS Code extension: mss.tmLanguage.json
" is `include source.css` with an injected `//` line comment. So we reuse
" Neovim's bundled CSS syntax and add MSS's line comments on top. Dormant when a
" tree-sitter parser is active.
"
" There is deliberately no `b:current_syntax` guard: loading css.vim triggers a
" syntax reload that re-sources this file, and on that second pass a leftover
" `b:current_syntax` would make css.vim bail (leaving MSS with no CSS rules,
" depending on runtimepath order). Clearing it before every css load keeps CSS
" loading reliably.

unlet! b:current_syntax
runtime! syntax/css.vim
unlet! b:current_syntax

" MSS adds // line comments, which plain CSS does not have.
syn match mssLineComment "//.*$" contains=@Spell
hi def link mssLineComment Comment

let b:current_syntax = "mss"
