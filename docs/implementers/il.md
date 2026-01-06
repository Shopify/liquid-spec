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

## Capture Opcodes

- `PUSH_CAPTURE`: begin capture buffer.
- `POP_CAPTURE`: end capture buffer and push captured string value.
- `WRITE_CAPTURED`: pop captured string and append to output (used by `{{ }}` inside capture, if needed).

## Control Flow Opcodes

- `LABEL <id>`
- `JUMP <label>`
- `JUMP_IF_FALSE <label>`
- `JUMP_IF_TRUE <label>`
- `JUMP_IF_EMPTY <label>`
- `JUMP_IF_INTERRUPT <label>`

## Comparison and Logic Opcodes

- `COMPARE <op>`: binary compare (`==`, `!=`, `<`, `<=`, `>`, `>=`).
- `CONTAINS`: binary contains check.
- `BOOL_NOT`: logical negation (used for `unless`).

## Scope and Assignment Opcodes

- `PUSH_SCOPE`
- `POP_SCOPE`
- `ASSIGN <name>` (pops value)

## Range Opcodes

- `NEW_RANGE`: build a range from two dynamic endpoints (pops end, start).

## Loop and Interrupt Opcodes

- `FOR_INIT <name> <collection_expr>`
- `FOR_NEXT <label_continue> <label_break>`
- `FOR_END`
- `PUSH_FORLOOP <length>`
- `POP_FORLOOP`
- `ENSURE_FORLOOP` (lazily materialize the `forloop` object in scope)
- `PUSH_INTERRUPT <type>`
- `POP_INTERRUPT`

### Lazy forloop Metadata

`forloop` and `forloop.parentloop` are rarely used. You can avoid the overhead of building and maintaining the forloop stack unless it is actually referenced.

Compile-time strategy:

- Scan the loop body for any access to `forloop` (or `forloop.parentloop`).
- If absent, **omit** `PUSH_FORLOOP/POP_FORLOOP` and skip maintaining the parentloop stack.
- If present, emit `PUSH_FORLOOP/POP_FORLOOP` for this loop.
- Emit `ENSURE_FORLOOP` immediately before the first access to `forloop` in the loop body.
- If a nested loop references `forloop.parentloop`, propagate the requirement outward so the parent loop emits forloop metadata too.

Include/render caveat:

- If an `include` is not inlined (dynamic target), assume it may access `forloop` and keep metadata.
- If an `include` is inlined, you can analyze the inlined body.
- `render` is isolated, so outer `forloop` is never visible inside it.

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

## Case/When Lowering (Jump-Only)

`case`/`when` can be compiled entirely with comparisons and jumps:

- Evaluate the case expression once and keep it on the stack or in a temp slot.
- For each `when`, emit comparisons and `JUMP_IF_TRUE` to that branch.
- Fall through to `else` if no branch matches.

This keeps the IL minimal and avoids dedicated `CASE_*` opcodes.

Example lowering:
```
# case x
#   when 1, 2 -> A
#   when 3    -> B
#   else      -> C

FIND_VAR "x"
STORE_TEMP 0

LOAD_TEMP 0
CONST_NUMBER 1
COMPARE EQ
JUMP_IF_TRUE L_when_1
LOAD_TEMP 0
CONST_NUMBER 2
COMPARE EQ
JUMP_IF_TRUE L_when_1

LOAD_TEMP 0
CONST_NUMBER 3
COMPARE EQ
JUMP_IF_TRUE L_when_2

JUMP L_else

LABEL L_when_1
  WRITE_RAW "A"
  JUMP L_end

LABEL L_when_2
  WRITE_RAW "B"
  JUMP L_end

LABEL L_else
  WRITE_RAW "C"

LABEL L_end
```

## Counter Opcodes

- `INCREMENT <name>`: shared counter in the current execution state.
- `DECREMENT <name>`: shared counter in the current execution state.

These are shared for `include` and isolated for `render`.

## Tablerow Lowering (For/Jump-Only)

`tablerow` can be lowered to a normal `for` loop plus jump logic:

- Use a standard loop segment iterator.
- Track the column index and emit row/column wrappers with conditional jumps.
- Emit `break`/`continue` via the same interrupt path as `for`.

This keeps tablerow as a compile-time pattern rather than a separate opcode family.

Example lowering (sketch):
```
FIND_VAR "items"
FOR_INIT "item"
JUMP_IF_EMPTY L_else
PUSH_SCOPE
CONST_NUMBER 0
STORE_TEMP 0            # col_index

LABEL L_loop
  FOR_NEXT L_continue L_break
  ASSIGN "item"

  LOAD_TEMP 0
  CONST_NUMBER 0
  COMPARE EQ
  JUMP_IF_FALSE L_cell
  WRITE_RAW "<tr>"
LABEL L_cell
  WRITE_RAW "<td>"
  ... body IL ...
  WRITE_RAW "</td>"

  LOAD_TEMP 0
  CONST_NUMBER 1
  ADD
  STORE_TEMP 0

  LOAD_TEMP 0
  LOAD_TEMP 1            # cols
  COMPARE EQ
  JUMP_IF_FALSE L_continue
  WRITE_RAW "</tr>"
  CONST_NUMBER 0
  STORE_TEMP 0

LABEL L_continue
  JUMP L_loop

LABEL L_break
  WRITE_RAW "</tr>"      # close if needed
  POP_SCOPE
LABEL L_else
```

## Cycle Opcodes

- `CYCLE_STEP <identity>`: rotate and emit the next value for a cycle group.

The cycle state lives in the register store. `render` must isolate it; `include` shares it.

## Raw and Comment Handling

- `{% raw %}` can be compiled as a single `WRITE_RAW` with the literal body.
- `{% comment %}` and `{% # ... %}` compile to no IL (or a `NOOP` if you want explicit placeholders).

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

IL (conceptual, with lazy forloop):
```
FIND_VAR "items"
FOR_INIT "i"
JUMP_IF_EMPTY L_else
PUSH_SCOPE
PUSH_FORLOOP <length>   # only if forloop is referenced
LABEL L_loop
  FOR_NEXT L_continue L_break
  ASSIGN "i"
  ENSURE_FORLOOP         # only if forloop is referenced
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

## Source Tracking

For better error reporting and debugging tools (like pretty-printers), track source spans for every instruction.

- **Lexer**: Include `start_pos` and `end_pos` in every token.
- **Parser**: When emitting IL, attach the source span of the generating token/construct.
- **IL Structure**: Store a parallel array of spans or include span info in the instruction object.

```
[  0]     FIND_VAR          "x"                   # {{ x | plus: y }}  → x
[  1]     FIND_VAR          "y"                   # {{ x | plus: y }}  → y
```

This allows you to reconstruct the context of a crash or display the original source alongside the bytecode.

## See also

- [Parsing](parsing.md)
- [For Loops](for-loops.md)
- [Interrupts](interrupts.md)
