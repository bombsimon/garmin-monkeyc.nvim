" Vim syntax file for Garmin Connect IQ jungle build files.
"
" Ported from Garmin's official Monkey C VS Code extension
" (syntaxes/jungle.tmLanguage.json). Dormant when a tree-sitter parser is active.

if exists("b:current_syntax")
  finish
endif

syn case match

" Line comments start with '#'.
syn match jungleComment "#.*$" contains=@Spell

" Assignment operator on `key = value` lines.
syn match jungleOperator "="

" Known jungle properties (.manifest, .sourcePath, ...).
syn match jungleProperty "\.\%(manifest\|sourcePath\|resourcePath\|excludeAnnotations\|barrelPath\|annotations\|lang\|personality\)\>"

" Variable lookups: $(...).
syn match jungleLookup "\$(\%(\w\|-\|\.\)*)"

hi def link jungleComment  Comment
hi def link jungleOperator Operator
hi def link jungleProperty Type
hi def link jungleLookup   PreProc

let b:current_syntax = "jungle"
