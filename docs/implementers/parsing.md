---
title: "Parsing in Strict Mode"
position: 20
description: "Read when parser errors or strict2 behavior matter. Describes tokenizer/parser structure, strict expression lexing, and error reporting."
optional: true
---

# Parsing in Strict Mode

This guide describes the observable parsing contract exercised by the strict and
strict2 specs. It uses a tokenizer and expression parser as a useful mental model,
but it does not require an AST, a particular parser generator, or the structure of
any existing Liquid implementation. The goal is a parser that reports the same
accepted language, error boundaries, and source locations as the reference.

## Overview: Two-Stage Parse

Most implementations benefit from separating parsing into two conceptual stages:

1. **Template tokenization**: scan the template source into raw text, tag, and variable tokens.
2. **Expression parsing**: inside tag/variable markup, run a strict expression lexer and parser.

This separation keeps the template scanner simple and allows the expression parser to be strict and precise about errors.

## Stage 1: Template Tokenization (Tags vs Raw)

The tokenizer walks the template and emits these token types:

- **Raw text** outside of any Liquid delimiters
- **Tag tokens** delimited by `{% ... %}`
- **Variable tokens** delimited by `{{ ... }}`

Whitespace trim markers (`{%-`, `-%}`, `{{-`, `-}}`) are handled in this stage. The tokenizer tracks whether the current token should strip leading or trailing whitespace from the surrounding raw text.

Key strict behaviors:

- Unterminated tags or variables are reported as errors.
- Tag/variable content is captured exactly (trim markers removed) for the strict expression parser.

### Inline Comments

The tokenizer or tag parser can recognize inline comment tags and skip expression parsing:

- `{%- # comment %}` is treated as a comment tag (no output).
- Inside `{% liquid %}`, any line that begins with `#` after trimming is a comment line:

```
{% liquid
  # comment here
  echo "hi"
%}
```

In strict mode, comment tags should bypass expression parsing entirely to avoid false syntax errors.

## Stage 2: Strict Expression Lexer

Inside tag/variable markup, strict mode uses a small lexer that emits tokens such as:

- identifiers
- numbers (including negative and floats)
- strings (single or double quoted)
- comparison operators (`==`, `!=`, `<`, `<=`, `>`, `>=`, `contains`)
- punctuation (`.`, `..`, `:`, `,`, `[`, `]`, `(`, `)`, `|`)
- end-of-string

Important lexer rules covered by the corpus include:

- Whitespace is skipped between tokens.
- Strings must be properly closed; otherwise this is a syntax error.
- A leading `-` is part of a number only if it is followed by digits.
- Identifiers include letters, digits, underscore, and hyphen, and may end with `?`.

### Keywords vs Identifiers

Tokens like `blank`, `empty`, `true`, and `false` are usually lexed as keywords/literals. However, the parser must handle the edge case where they function as variable names.

Rule: **If a keyword is followed by `.` or `[`, treat it as an identifier.**

```liquid
{{ blank }}       # literal blank (usually empty string or special value)
{{ blank.foo }}   # variable lookup: find variable "blank", access property "foo"
```

## Strict Expression Grammar

The strict expression parser is small and uses two-token lookahead. Conceptually:

```
expression :=
  literal
  | number
  | string
  | range
  | variable_lookup

literal := nil | null | true | false | empty | blank

range := "(" expression ".." expression ")"

variable_lookup :=
  identifier | "[" expression "]"
  ( "." identifier | "[" expression "]" )*
```

### Two-Token Lookahead

Lookahead is used to:

- Distinguish literals from variable lookups.
- Detect keyword arguments in filters (`name: value`).

Strict mode should emit an error if the current token does not match an expected token type.

## Variable Lookups

Variable lookup supports:

- A root identifier (e.g., `product`)
- A dynamic root via brackets (e.g., `[some_expr]`)
- Chained properties via dots (e.g., `product.title`)
- Chained bracket lookups (e.g., `product[handle]`)

Lookup keys such as `size`, `first`, and `last` are ordinary property/filter
names in the language contract. A compiler may specialize them for performance,
but correctness must not depend on a list of special names in the parser.

## Ranges

Strict mode expects range syntax to be fully parenthesized: `(start..end)`.

An implementation may parse **constant ranges** first:

- If both sides are constant expressions and can be converted to integers, precompute the range.
- Otherwise, fall back to dynamic evaluation with strict syntax checks.

If either side is not convertible to an integer in strict mode, raise a syntax error.

## Filter Parsing

Filter chains are parsed strictly as:

```
expression ("|" filter_name (":" filter_args)?)*
```

Rules:

- `filter_name` must be an identifier.
- Arguments are comma-separated expressions.
- A keyword argument is detected as `identifier ":" expression`.
- Keyword args are collected into a map, and passed as a single trailing argument.
- If the implementation imposes resource limits, report them through the advertised
  protocol/resource-limit contract rather than silently truncating arguments.

At the end of parsing, strict mode must see **end-of-string**. Any remaining token is a syntax error.

## Error Reporting

Strict mode aims to fail fast and precisely:

- Use token names in error messages (e.g., "Expected identifier but found end_of_string").
- Include a snippet of the offending token when possible.
- Attach line numbers from the template tokenizer to the error.

## Architecture-neutral implementation choices

- Keep lexing deterministic and make token boundaries visible in diagnostics.
- Separate template tokenization from expression parsing, whether the boundary is
  represented by modules, parser states, or compiler passes.
- Use as much lookahead as needed to distinguish literals, lookups, and keyword
  arguments; two-token lookahead is one option, not a requirement.
- Build an AST, bytecode, or an evaluated intermediate form according to the rest
  of the engine. Preserve enough source information for errors either way.
- Require the complete expression to be consumed in strict mode. Do not accept
  trailing garbage merely because a prefix parsed successfully.

## Strict, strict2, and lax are separate contracts

The runner selects a parse mode from the adapter's advertised capabilities. Strict
and strict2 generally reject malformed syntax, while lax mode may recover from
some constructs. Do not make one parser silently choose a mode based on an adapter
default: mode-sensitive specs declare their compatible modes explicitly.

For each mode, test both successful output and the error shape. A syntax error is a
valid Liquid outcome; it is not a JSON-RPC transport failure. Parsing should happen
in `template.compile`, and rendering should receive only a compiled handle. Keeping
that boundary makes timing measurements meaningful and prevents a render path from
re-parsing source accidentally.

## See also

- [Core Abstractions](core-abstractions.md)
- [For Loops](for-loops.md)
- [Liquid IL](il.md)
