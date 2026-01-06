---
title: Parsing in Strict Mode
description: >
  Advanced guide to building a high-performance Liquid parser based on liquid-c's two-stage approach.
  Covers template tokenization, strict expression lexing, and error handling. Optional reading - a
  simple recursive descent parser works fine. Only needed if optimizing parse performance.
optional: true
order: 10
---

# Parsing in Strict Mode

This document summarizes how the liquid-c codebase parses Liquid in strict mode, and turns it into a practical guide for writing a correct, fast parser. The focus here is only strict mode behavior (no lax recovery).

## Overview: Two-Stage Parse

Strict parsing in liquid-c is split into two stages:

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

Important lexer rules observed in liquid-c:

- Whitespace is skipped between tokens.
- Strings must be properly closed; otherwise this is a syntax error.
- A leading `-` is part of a number only if it is followed by digits.
- Identifiers include letters, digits, underscore, and hyphen, and may end with `?`.

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

liquid-c includes a micro-optimization: when the lookup key is a known command (`size`, `first`, `last`), it emits a specialized lookup instruction. This is optional but can be useful for performance.

## Ranges

Strict mode expects range syntax to be fully parenthesized: `(start..end)`.

liquid-c attempts to parse **constant ranges** first:

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
- liquid-c enforces a hard limit on the number of keyword args (255) to avoid unbounded growth.

At the end of parsing, strict mode must see **end-of-string**. Any remaining token is a syntax error.

## Error Reporting

Strict mode aims to fail fast and precisely:

- Use token names in error messages (e.g., "Expected identifier but found end_of_string").
- Include a snippet of the offending token when possible.
- Attach line numbers from the template tokenizer to the error.

## Implementation Tips From liquid-c

- Keep the lexer tiny and deterministic; avoid backtracking.
- Use two-token lookahead to keep the parser single-pass.
- Separate template tokenization from expression parsing.
- Consider compiling expressions directly to a simple instruction stream instead of building a full AST.
- Enforce end-of-string after every strict parse to catch trailing garbage.

## See also

- [Core Abstractions](core-abstractions.md)
- [For Loops](for-loops.md)
- [Liquid IL](il.md)
