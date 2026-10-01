" Syntax for the filemarks list buffer (filetype=filemarks)

if exists("b:current_syntax")
    finish
endif

syntax match filemarksComment /^\s*#.*/

highlight default link filemarksComment Comment

let b:current_syntax = "filemarks"
