---
title: Intermediate Language (IL)
description: >
  Advanced guide to compiling Liquid templates into a flat bytecode-like IL for high-performance
  execution. Covers opcodes, control flow, and stack-based evaluation. Optional reading - a tree-walking
  interpreter works fine. Only needed if building a high-performance or compiled implementation.
optional: true
order: 11
---

# Liquid IL and AST Flattening (Strict Mode)

This document describes a clean, strict-mode pipeline that flattens parsing directly into an efficient Liquid IL. It is based on the liquid-c parser structure and AST-flattening ideas, but stays language-agnostic.

## Goals

- Single-pass strict parsing with immediate errors.
- Linear IL stream with explicit control flow.
- Explicit constant opcodes to avoid variable lookups.
- Low allocation: no deep AST required.

## Pipeline Overview

1. **Template tokenizer**: emits `RAW`, `TAG`, and `VAR` tokens.
2. **Strict markup parser**: parses tag/variable markup and emits IL directly.
3. **IL linker**: resolves labels to jump targets.
4. **IL runtime**: executes IL with a value stack, scope stack, and register store.

## Constant Opcodes (No Lookup)

To avoid variable lookup for literals, emit explicit constant opcodes:

- `CONST_NIL`
- `CONST_BOOL true|false`
- `CONST_NUMBER <value>`
- `CONST_STRING <value>`
- `CONST_RANGE <start> <end>` (only for constant ranges)

This keeps literals out of the variable path and reduces runtime overhead.

## Variable and Property Access Opcodes

- `FIND_VAR <name>`: root lookup by name.
- `LOOKUP_KEY`: dynamic key lookup (pops key).
- `LOOKUP_CONST_KEY <name>`: constant property key.
- `LOOKUP_COMMAND <name>`: optimized property lookup for well-known commands (e.g., `size`, `first`, `last`).

## Output Opcodes

- `WRITE_RAW <string>`: raw template text.
- `WRITE_VALUE`: pop, stringify, write.

## Control Flow Opcodes

- `LABEL <id>`
- `JUMP <label>`
- `JUMP_IF_FALSE <label>`
- `JUMP_IF_EMPTY <label>`
- `JUMP_IF_INTERRUPT <label>`

## Scope and Assignment Opcodes

- `PUSH_SCOPE`
- `POP_SCOPE`
- `ASSIGN <name>` (pops value)

## Loop and Interrupt Opcodes

- `FOR_INIT <name> <collection_expr>`
- `FOR_NEXT <label_continue> <label_break>`
- `FOR_END`
- `PUSH_FORLOOP <length>`
- `POP_FORLOOP`
- `PUSH_INTERRUPT <type>`
- `POP_INTERRUPT`

## Partial Opcodes

- `RENDER_PARTIAL <name> <args...>`: isolated context (new interrupt stack, counters, local scope)
- `INCLUDE_PARTIAL <name> <args...>`: shared context (new local scope only)

### Include/Render Inlining (Compile-Time)

If the compiler has access to a file system and the target is a **constant** string, you can inline the included/rendered template at compile time:

- Parse the included template into IL immediately.
- Splice the resulting IL into the caller stream.
- Preserve semantics:
  - `include`: shared execution state, shared registers, new local scope per include.
  - `render`: isolated execution state, new registers wrapper, new local scope.

Inlining removes runtime file lookups and enables further optimizations (e.g., constant folding across the include boundary).

### Dynamic Include/Render (Runtime)

When the target name is dynamic, or the object model requires late binding (e.g., drop method dispatch), emit a call-style opcode:

- `INCLUDE_PARTIAL` / `RENDER_PARTIAL` with runtime name resolution.
- `CALL_DROP` / `CALL_METHOD` (implementation-specific) for dynamic property or method calls.

These paths trade some performance for correctness when the template depends on runtime state.

## Strict Expression Flattening

Strict expressions are flattened as they are parsed:

```
expression :=
  literal
  | number
  | string
  | range
  | variable_lookup
```

Emit IL as soon as a term is recognized:

- `nil` -> `CONST_NIL`
- `true` -> `CONST_BOOL true`
- `false` -> `CONST_BOOL false`
- number -> `CONST_NUMBER n`
- string -> `CONST_STRING s`
- variable lookup -> `FIND_VAR` + `LOOKUP_*` chain

### Constant Range Folding

If both ends of a range are constants and convertible to integers:

```
(1..3) -> CONST_RANGE 1 3
```

Otherwise emit a dynamic range path:

```
<expr> <expr> NEW_RANGE
```

## Filter Flattening

Filters are parsed as a postfix chain:

```
expression ("|" filter_name (":" filter_args)?)*
```

The base expression emits its IL first. Each filter then emits:

```
CALL_FILTER <name> <argc>
```

Arguments are emitted in order (positional first, keyword map last).

## Example: Variable With Filters

Template:
```
{{ product.title | upcase | truncate: 10 }}
```

IL:
```
FIND_VAR "product"
LOOKUP_CONST_KEY "title"
CALL_FILTER "upcase" 0
CONST_NUMBER 10
CALL_FILTER "truncate" 1
WRITE_VALUE
```

## Example: If Block

Template:
```
{% if foo %}
  hello
{% else %}
  bye
{% endif %}
```

IL:
```
FIND_VAR "foo"
JUMP_IF_FALSE L_else
WRITE_RAW "hello"
JUMP L_end
LABEL L_else
WRITE_RAW "bye"
LABEL L_end
```

## Example: For Loop With parentloop

Template:
```
{% for i in items %}
  {{ forloop.index }} {{ i }}
{% endfor %}
```

IL (conceptual):
```
FIND_VAR "items"
FOR_INIT "i"
JUMP_IF_EMPTY L_else
PUSH_SCOPE
PUSH_FORLOOP <length>
LABEL L_loop
  FOR_NEXT L_continue L_break
  ASSIGN "i"
  FIND_VAR "forloop"
  LOOKUP_CONST_KEY "index"
  WRITE_VALUE
  FIND_VAR "i"
  WRITE_VALUE
  JUMP_IF_INTERRUPT L_break_or_continue
LABEL L_continue
  JUMP L_loop
LABEL L_break
  POP_FORLOOP
  POP_SCOPE
LABEL L_else
```

The `PUSH_FORLOOP/POP_FORLOOP` pair maintains the `parentloop` chain in the register store.

## Error Discipline (Strict Mode)

- Every strict parse must consume to end-of-string.
- Unexpected tokens are fatal.
- Use token names in errors to make debugging precise.

## See also

- [Parsing](parsing.md)
- [For Loops](for-loops.md)
- [Interrupts](interrupts.md)
