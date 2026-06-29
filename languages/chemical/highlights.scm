; Minimal syntax highlighting for Chemical.
;
; All visual highlighting is handled by the Chemical LSP via
; LSP Semantic Tokens (textDocument/semanticTokens/full).
; This file exists only for Zed compatibility.
;
; Only bare essentials: comments, strings, and statements for
; bracket matching context.

(comment) @comment
(multiline_comment) @comment
(string) @string
