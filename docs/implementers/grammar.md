---
title: "Liquid Grammar Reference"
position: 2
description: "Read while building the parser. A compact grammar for templates, tags, expressions, filters, and the important irregularities."
optional: false
---

# Liquid Grammar Reference

A pseudo-grammar for implementing Liquid. Liquid is **mostly regular** with specific documented irregularities.

---

## Two-Stage Lexing

```
Template → TemplateLexer → [RAW, TAG, VAR] → ExpressionLexer → tokens
```

---

## Stage 1: Template Lexer

### Tokens

| Type | Pattern | Example |
|------|---------|---------|
| RAW | text between delimiters | `Hello ` |
| TAG | `{%` ... `%}` | `{% if x %}` |
| VAR | `{{` ... `}}` | `{{ name }}` |

### Whitespace Trim

```
{%-  →  trim whitespace before (right-trim previous RAW)
-%}  →  trim whitespace after (left-trim next RAW)
{{-  →  trim before
-}}  →  trim after
```

### Irregularity: Empty Tags with Trim

```
{{-}}   →  single - is BOTH trim_left and trim_right
{%--%}  →  content is "-", both trims active
{%-%}   →  content is empty, both trims active
```

**Implementation:** Check for these patterns before greedy delimiter matching.

### Irregularity: Raw Tag

`{% raw %}...{% endraw %}` must be handled at lexer level—content is not tokenized.

```liquid
{% raw %}{{ not.parsed }}{% endraw %}
```

Raw content is also exempt from delimiter trimming at its own boundaries. The
opening tag's `{%-` may trim source *before* the raw block, and the closing tag's
`-%}` may trim source *after* it, but the opening `-%}` must not left-trim raw
content and `{%- endraw %}` must not right-trim raw content. Represent raw text
with a distinct token/node so a later trim marker cannot accidentally modify it.

### Irregularity: Blank Block Bodies

For `if`/`unless`, `case`, and `for`, the reference detects bodies made entirely
of blank nodes (whitespace-only text plus non-output tags such as `assign`,
`capture`, and comments). It removes the whitespace-only text from such a body:

```liquid
{% if true %} {% assign x = "set" %} {% endif %}{{ x }} → set
{% if true %} visible {% endif %}                         → " visible "
```

This is not global whitespace trimming. Preserve whitespace whenever any node in
the body can produce visible output.

---

## Stage 2: Expression Lexer

### Token Definitions

```ebnf
IDENTIFIER  = [a-zA-Z_] [a-zA-Z0-9_-]* '?'?
NUMBER      = '-'? [0-9]+ ('.' [0-9]+)?
            | '.' [0-9]+                      (* .5 is valid *)
STRING      = "'" [^']* "'" | '"' [^"]* '"'   (* no escapes *)
```

### Operators

```
==   !=   <>   <   <=   >   >=   =>
|    :    ,    .   ..   (   )   [   ]
```

### Keywords (case-insensitive)

```
nil  null  true  false  empty  blank  and  or  contains
```

### Irregularity: Hyphens in Identifiers

```liquid
{{ my-variable }}    (* valid identifier *)
{{ x - y }}          (* subtraction—context dependent *)
```

### Irregularity: Fat Arrow

```liquid
{{ x=>y }}   (* lax mode: equivalent to x['y'] *)
```

---

## Expression Grammar

Liquid has two expression contexts. Treating every output or assignment as a
boolean expression is observably wrong.

```ebnf
(* Used by if/unless/elsif conditions. RIGHT-ASSOCIATIVE—unusual! *)
condition_expr = comparison_expr
               | comparison_expr 'and' condition_expr
               | comparison_expr 'or' condition_expr

comparison_expr = value_expr (comp_op value_expr)*
comp_op          = '==' | '!=' | '<>' | '<' | '<=' | '>' | '>=' | 'contains'

(* Used by output, echo, assign, collections, and filter arguments. *)
value_expr      = literal | variable | range
range           = '(' value_expr '..' value_expr ')'

literal         = 'nil' | 'null' | 'true' | 'false'
                | 'empty' | 'blank'
                | NUMBER | STRING

variable        = IDENTIFIER property*
property        = '.' IDENTIFIER
                | '[' value_expr ']'
                | '=>' IDENTIFIER              (* lax mode *)
```

Parentheses are not general grouping syntax: `(a..b)` is a range, while `(a)` is
rejected by strict parsers. A dynamic root such as `[key]` is accepted by legacy
lax/strict parsing but rejected in `strict2`; use `self[key]` in portable code.

### Irregularity: Operators in Value Contexts

Operators do not turn a value context into a condition. In lax mode, the
reference consumes the first value and ignores an operator-looking suffix;
strict and strict2 reject that trailing syntax:

```liquid
                                  lax output   strict/strict2
{{ 1 == 2 }}                         1         parse error
{{ true and false }}                 true      parse error
{% assign x = "a" contains "a" %}    x = "a"  parse error
```

Conditions evaluate those operators normally in every applicable mode. Keep
`value_expr` and `condition_expr` as separate parser entry points even if they
share tokens and AST nodes, and make end-of-expression validation mode-aware.

### Irregularity: Keywords as Variables

When followed by property access, keywords become variable names:

```liquid
{{ empty.size }}   (* variable "empty", not literal *)
{{ empty }}        (* the empty literal *)
```

**Implementation:** Peek for `.` or `[` after keyword.

### Irregularity: Right-Associative Logic

```
a and b or c   →   a and (b or c)
a or b and c   →   a or (b and c)
```

---

## Filter Grammar

```ebnf
filtered_expr  = value_expr ('|' filter)*
filter         = IDENTIFIER (':' arguments)?
arguments      = argument (',' argument)*
argument       = IDENTIFIER ':' value_expr    (* keyword *)
               | value_expr                   (* positional *)
```

### Irregularity: Keyword Argument Order

Keyword args must be emitted **after** positional args on the stack.

```liquid
{{ x | f: a, k: 1, b }}   (* stack: x, a, b, {k:1} *)
```

---

## Tag Grammar

### Output

```ebnf
var_tag    = '{{' filtered_expr? '}}'
echo_tag   = '{%' 'echo' filtered_expr '%}'
```

### Control Flow

```ebnf
if_tag     = '{%' 'if' condition_expr '%}'
             block
             ('{%' 'elsif' condition_expr '%}' block)*
             ('{%' 'else' '%}' block)?
             '{%' 'endif' '%}'

unless_tag = '{%' 'unless' condition_expr '%}'
             block
             ('{%' 'elsif' condition_expr '%}' block)* (* yes, elsif in unless *)
             ('{%' 'else' '%}' block)?
             '{%' 'endunless' '%}'

case_tag   = '{%' 'case' value_expr '%}'
             ignored_content                          (* DISCARDED *)
             (when_clause | else_clause)*
             '{%' 'endcase' '%}'

when_clause = '{%' 'when' when_values '%}' block
when_values = value_expr ((',' | 'or') value_expr)*

else_clause = '{%' 'else' '%}' block
```

### Irregularity: Case/When

- Content between `{% case %}` and first `{% when %}` is **discarded**
- Multiple `{% else %}` clauses are allowed and may be interleaved with `when`;
  each else renders if no earlier `when` matched
- A matching `when` does **not** break the case: every matching `when` body renders
- `when` can use comma OR `or` keyword for multiple values

### Loops

```ebnf
for_tag    = '{%' 'for' IDENTIFIER 'in' value_expr for_opts '%}'
             block
             ('{%' 'else' '%}' block)?
             '{%' 'endfor' '%}'

for_opts   = (limit | offset | 'reversed')*   (* order independent *)
limit      = 'limit' ':' value_expr
offset     = 'offset' ':' (value_expr | 'continue')

tablerow   = '{%' 'tablerow' IDENTIFIER 'in' value_expr tablerow_opts '%}'
             block
             '{%' 'endtablerow' '%}'

tablerow_opts = (cols | limit | offset)*      (* no reversed, no else *)
cols       = 'cols' ':' (value_expr | 'nil')
```

### Irregularity: offset:continue

Uses loop identity = `"varname-collection_expr"` to resume from prior position.

### Assignment

```ebnf
assign     = '{%' 'assign' IDENTIFIER '=' filtered_expr '%}'
capture    = '{%' 'capture' (IDENTIFIER | STRING) '%}' block '{%' 'endcapture' '%}'
```

### Counters (separate namespace)

```ebnf
increment  = '{%' 'increment' IDENTIFIER '%}'   (* outputs then increments *)
decrement  = '{%' 'decrement' IDENTIFIER '%}'   (* decrements then outputs *)
```

### Cycle

```ebnf
cycle      = '{%' 'cycle' (group ':')? values '%}'
group      = STRING | NUMBER | IDENTIFIER
values     = value (',' value)*
value      = STRING | NUMBER | IDENTIFIER
```

### Irregularity: Cycle Groups

- String group: `{% cycle 'name': 'a', 'b' %}`
- Number group: `{% cycle 123: 'a', 'b' %}`
- Variable group: `{% cycle myvar: 'a', 'b' %}` (runtime lookup)
- `.5` in values means variable `"5"`, not float

### Comments

```ebnf
comment    = '{%' 'comment' '%}' ... '{%' 'endcomment' '%}'   (* nesting tracked *)
inline     = '{%' '#' ... '%}'
doc        = '{%' 'doc' '%}' ... '{%' 'enddoc' '%}'           (* no nesting *)
```

### Irregularity: Nested Comments

Track nesting depth. Also track raw depth independently:

```liquid
{% comment %}{% raw %}{% endcomment %}{% endraw %}{% endcomment %}
```

### Partials

```ebnf
render     = '{%' 'render' STRING render_opts '%}'
render_opts = (with_clause | for_clause | as_clause | kwarg)*
with_clause = 'with' value_expr
for_clause  = 'for' value_expr
as_clause   = 'as' IDENTIFIER
kwarg       = IDENTIFIER ':' value_expr

include    = '{%' 'include' (STRING | value_expr) include_opts '%}'
```

### Irregularity: Render vs Include

- `render`: partial name must be **quoted string**
- `include`: allows **variable** template names

### Liquid Tag

```ebnf
liquid_tag = '{%' 'liquid' newline_statements '%}'
```

Contains statements without delimiters, one per line. `#` starts comment.

**Implementation:** Split by newlines, parse each as tag. Track block depth for if/for/capture/comment.

### Other Tags

```ebnf
break      = '{%' 'break' '%}'
continue   = '{%' 'continue' '%}'
ifchanged  = '{%' 'ifchanged' '%}' block '{%' 'endifchanged' '%}'
raw        = '{%' 'raw' '%}' ... '{%' 'endraw' '%}'  (* lexer-level *)
```

---

## Irregularities Summary

| Area | Irregularity |
|------|--------------|
| Trim | `{{-}}` single `-` is both trims |
| Raw | Must handle at lexer level |
| Identifiers | Hyphens allowed: `my-var` |
| Numbers | Leading decimal: `.5` |
| Strings | No escape sequences |
| Keywords | Case-insensitive |
| Keywords | Can be variables when followed by `.` or `[` |
| Operators | `=>` fat arrow for lax parsing |
| Operators | `<>` alternate not-equals |
| Logic | Right-associative and/or |
| Case | Content before first when discarded |
| Case | Multiple else clauses allowed |
| For | `offset:continue` uses loop identity |
| Cycle | Variable groups, `.5` means var lookup |
| Comment | Nesting + raw depth tracking |
| Include | Allows variable template names |

---

## Implementation Notes

### Lexer

1. Byte lookup tables for punctuation (O(1))
2. StringScanner `skip` to avoid allocations
3. Deferred string extraction
4. Raw mode scan for raw/endraw

### Parser

1. Direct IL emission—no AST
2. Right-recursion for and/or
3. Lookahead for keyword-as-variable
4. State save/restore for keyword arg detection
5. Depth tracking for nested blocks in liquid tag

### Filter Args

```
1. Parse positional → emit immediately
2. Parse keyword → buffer
3. Emit buffered keywords after all args
4. Build hash from keywords
5. Call filter with argc
```
