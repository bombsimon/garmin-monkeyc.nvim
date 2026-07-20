" Vim syntax file for Garmin Monkey C.
"
if exists("b:current_syntax")
  finish
endif

syn case match

" Operators come before the comment rules so those win the shared "/": on a
" shared start position Vim's last-defined match takes priority.
syn match   mcOperator "[-+*/%><|&^~=!]"

" //! doc comments come after // so they win the shared prefix.
syn keyword mcTodo contained TODO FIXME XXX NOTE
syn match   mcLineComment "//.*$" contains=mcTodo,@Spell
syn match   mcDocComment  "//!.*$" contains=mcTodo,@Spell
syn region  mcBlockComment start=+/\*+ end=+\*/+ contains=mcTodo,@Spell

syn match   mcEscape contained "\\u\x\{4}"
syn match   mcEscape contained +\\[nrtbf"'\\]+
syn region  mcString start=+"+ skip=+\\.+ end=+"+ contains=mcEscape,@Spell
syn region  mcCharacter start=+'+ skip=+\\.+ end=+'+ contains=mcEscape

syn match   mcNumber "\<0x\x\+[lL]\?\>"
syn match   mcFloat  "\<\d\+\(\.\d\+\)\?\([Ee][+-]\?\d\+\)\?[dlLf]\?\>"

syn keyword mcConditional if else switch case default
syn keyword mcRepeat do while for
syn keyword mcException try catch finally throw
syn keyword mcStatement return break continue
syn keyword mcOperatorKeyword or and as has instanceof new

" The grammar scopes these uniformly as storage; we map to the conventional Vim
" groups so colorschemes style them as they do for other languages.
syn keyword mcKeyword var extends
syn keyword mcInclude import using
syn keyword mcTypedef typedef
syn keyword mcStructure enum
syn keyword mcStorageClass public private protected const static hidden native

" nextgroup so the class/function name gets its own highlight. `function` is kept
" out of the keyword lists above so this match owns it.
syn match   mcStructure "\<\%(class\|module\)\>" nextgroup=mcTypeName skipwhite
syn match   mcTypeName contained "\<\w\+\>"
syn match   mcFunctionDef "\<function\>" nextgroup=mcFunctionName skipwhite
syn match   mcFunctionName contained "\<\w\+\>"

" A word before "(" is a call. Keywords are `syn keyword` and outrank this, so
" `if (`, `while (`, ... stay keywords.
syn match   mcFunctionCall "\<\w\+\ze\s*("

syn keyword mcBoolean true false null NaN
syn keyword mcSelf self me
syn match   mcSymbol ":\w\+"
syn keyword mcType Void Null interface

" PascalCase (upper then lower) reads as a type or module reference: Boolean,
" WatchUi.WatchFace, and so on. After the call rule so `new Foo()` is a type, not
" a call; ALL_CAPS constants do not match.
syn match   mcTypeRef "\<\u\l\w*\>"

" Block comments span many lines; resync from far enough back.
syn sync minlines=100

hi def link mcTodo            Todo
hi def link mcLineComment     Comment
hi def link mcDocComment      SpecialComment
hi def link mcBlockComment    Comment
hi def link mcEscape          SpecialChar
hi def link mcString          String
hi def link mcCharacter       Character
hi def link mcNumber          Number
hi def link mcFloat           Float
hi def link mcConditional     Conditional
hi def link mcRepeat          Repeat
hi def link mcException       Exception
hi def link mcStatement       Statement
hi def link mcOperatorKeyword Keyword
hi def link mcOperator        Operator
hi def link mcKeyword         Keyword
hi def link mcInclude         Include
hi def link mcTypedef         Typedef
hi def link mcStorageClass    StorageClass
hi def link mcStructure       Structure
hi def link mcTypeName        Type
hi def link mcFunctionDef     Keyword
hi def link mcFunctionName    Function
hi def link mcFunctionCall    Function
hi def link mcBoolean         Boolean
hi def link mcSelf            Identifier
hi def link mcSymbol          Constant
hi def link mcType            Type
hi def link mcTypeRef         Type

let b:current_syntax = "monkeyc"
