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

```ebnf
expression     = logical_expr

(* RIGHT-ASSOCIATIVE—unusual! *)
logical_expr   = comparison_expr
               | comparison_expr 'and' logical_expr
               | comparison_expr 'or' logical_expr

comparison_expr = primary (comp_op primary)*
comp_op         = '==' | '!=' | '<>' | '<' | '<=' | '>' | '>=' | 'contains'

primary        = literal
               | variable
               | '(' expression ')'           (* grouped *)
               | '(' expression '..' expression ')'  (* range *)
               | '[' expression ']' property* (* dynamic root *)

literal        = 'nil' | 'null' | 'true' | 'false'
               | 'empty' | 'blank'
               | NUMBER | STRING

variable       = IDENTIFIER property*
property       = '.' IDENTIFIER
               | '[' expression ']'
               | '=>' IDENTIFIER              (* lax mode *)
```

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
filtered_expr  = expression ('|' filter)*
filter         = IDENTIFIER (':' arguments)?
arguments      = argument (',' argument)*
argument       = IDENTIFIER ':' expression    (* keyword *)
               | expression                   (* positional *)
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
if_tag     = '{%' 'if' expression '%}'
             block
             ('{%' 'elsif' expression '%}' block)*
             ('{%' 'else' '%}' block)?
             '{%' 'endif' '%}'

unless_tag = '{%' 'unless' expression '%}'
             block
             ('{%' 'elsif' expression '%}' block)*   (* yes, elsif in unless *)
             ('{%' 'else' '%}' block)?
             '{%' 'endunless' '%}'

case_tag   = '{%' 'case' expression '%}'
             ignored_content                          (* DISCARDED *)
             (when_clause | else_clause)*
             '{%' 'endcase' '%}'

when_clause = '{%' 'when' when_values '%}' block
when_values = expression ((',' | 'or') expression)*

else_clause = '{%' 'else' '%}' block
```

### Irregularity: Case/When

- Content between `{% case %}` and first `{% when %}` is **discarded**
- Multiple `{% else %}` clauses allowed—each runs only if no prior `when` matched
- `when` can use comma OR `or` keyword for multiple values

### Loops

```ebnf
for_tag    = '{%' 'for' IDENTIFIER 'in' expression for_opts '%}'
             block
             ('{%' 'else' '%}' block)?
             '{%' 'endfor' '%}'

for_opts   = (limit | offset | 'reversed')*   (* order independent *)
limit      = 'limit' ':' expression
offset     = 'offset' ':' (expression | 'continue')

tablerow   = '{%' 'tablerow' IDENTIFIER 'in' expression tablerow_opts '%}'
             block
             '{%' 'endtablerow' '%}'

tablerow_opts = (cols | limit | offset)*      (* no reversed, no else *)
cols       = 'cols' ':' (expression | 'nil')
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
with_clause = 'with' expression
for_clause  = 'for' expression
as_clause   = 'as' IDENTIFIER
kwarg       = IDENTIFIER ':' expression

include    = '{%' 'include' (STRING | expression) include_opts '%}'
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
