# Tablerow Tag Implementation

The `{% tablerow %}` tag generates HTML table rows from a collection. It looks like a for loop but **it is not** - it's an HTML generator with specific output format requirements.

## Why Tablerow is Complex

Unlike a for loop, tablerow must:

1. **Generate HTML tags** - `<tr>`, `<td>` with class names
2. **Track two coordinate systems** - overall iteration AND grid position
3. **Emit specific whitespace** - newlines in exact positions
4. **Handle column wrapping** - start new `<tr>` when column count reached
5. **Provide extra loop variables** - `tablerowloop` has more properties than `forloop`

## Output Format

The exact HTML format matters. Here's an example with 5 items and `cols:2`:

```liquid
{% tablerow item in items cols:2 %}{{ item }}{% endtablerow %}
```

**Output** (whitespace is significant):
```html
<tr class="row1">
<td class="col1">a</td><td class="col2">b</td></tr>
<tr class="row2"><td class="col1">c</td><td class="col2">d</td></tr>
<tr class="row3"><td class="col1">e</td></tr>
```

**Whitespace rules:**
- Newline after the FIRST `<tr class="row1">` only
- NO newline before subsequent `<tr>` tags
- NO spaces between `</td>` and `<td>`
- Row closes with `</tr>` followed by newline (except possibly last)

## Implementation Strategy

Think of tablerow as a state machine:

```
State: START
  → emit "<tr class=\"row1\">\n"
  → go to FIRST_CELL

State: FIRST_CELL (first cell of any row)
  → emit "<td class=\"col{N}\">"
  → emit cell content
  → emit "</td>"
  → if more items AND not at cols limit: go to MIDDLE_CELL
  → if more items AND at cols limit: go to END_ROW
  → if no more items: go to END_TABLE

State: MIDDLE_CELL
  → emit "<td class=\"col{N}\">"
  → emit cell content
  → emit "</td>"
  → if at cols limit: go to END_ROW
  → if no more items: go to END_TABLE
  → else: stay in MIDDLE_CELL

State: END_ROW
  → emit "</tr>\n<tr class=\"row{N}\">"
  → go to FIRST_CELL

State: END_TABLE
  → emit "</tr>"
  → done
```

## The tablerowloop Object

Tablerow provides `tablerowloop` (NOT `forloop`) with these properties:

### Same as forloop:
| Property | Description |
|----------|-------------|
| `index` | 1-based iteration count |
| `index0` | 0-based iteration count |
| `first` | True on first iteration |
| `last` | True on last iteration |
| `length` | Total items being iterated |
| `rindex` | Reverse index (items remaining + 1) |
| `rindex0` | Reverse index (items remaining) |

### Unique to tablerow:
| Property | Description |
|----------|-------------|
| `col` | Current column (1-based), resets each row |
| `col0` | Current column (0-based) |
| `row` | Current row number (1-based) |
| `col_first` | True at first column of row |
| `col_last` | True at column position = cols value |

### col_last Quirk

`col_last` is true when at the `cols:` position, **not** when at the last item:

```liquid
{% tablerow item in items cols:2 %}
  {% if tablerowloop.col_first %}[{% endif %}
  {{ item }}
  {% if tablerowloop.col_last %}]{% endif %}
{% endtablerow %}
```

With `items = [a, b, c, d, e]`:
- Items a, c, e have `col_first = true`
- Items b, d have `col_last = true`
- Item e is the last item but `col_last = false` (it's at col 1, not col 2)

## Empty Collection Behavior

**QUIRK**: Empty collections still output a `<tr>` tag:

```liquid
{% tablerow item in empty_array %}{{ item }}{% endtablerow %}
```

Output:
```html
<tr class="row1">
</tr>
```

This is surprising but matches liquid-ruby behavior.

## Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `cols:N` | Items per row | `cols:3` |
| `limit:N` | Max items to process | `limit:5` |
| `offset:N` | Skip first N items | `offset:2` |

These work like their for loop equivalents.

## Interaction with break/continue

- `{% break %}` exits the tablerow immediately
- `{% continue %}` skips to next item but still outputs the `<td>` wrapper

```liquid
{% tablerow item in items cols:3 %}
  {% if item == 'c' %}{% break %}{% endif %}
  {{ item }}
{% endtablerow %}
```

The `<td>` for 'c' is still output (with break inside), then loop exits.

## Class Name Format

Classes follow this pattern:
- `<tr class="row{N}">` where N is 1-based row number
- `<td class="col{N}">` where N is 1-based column number

Example with `cols:3`:
```html
<tr class="row1">
<td class="col1">...</td><td class="col2">...</td><td class="col3">...</td></tr>
<tr class="row2"><td class="col1">...</td><td class="col2">...</td></tr>
```

## Common Implementation Mistakes

1. **Wrong whitespace** - Must have newline after first `<tr>`, not before subsequent ones
2. **Using forloop instead of tablerowloop** - Different variable name
3. **col_last at actual last item** - It's based on cols position, not iteration
4. **Empty output for empty collection** - Must still output empty `<tr></tr>`
5. **Spaces between cells** - No spaces between `</td>` and `<td>`

## Testing Your Implementation

Run tablerow-specific specs:
```bash
liquid-spec your_adapter.rb -n tablerow
```

Start with basic tablerow (complexity 180), then move to tablerowloop properties (250+).

## See Also

- `liquid-spec docs complexity` - Full complexity scoring guide
- `liquid-spec docs for-loops` - For loop implementation (similar but simpler)
- `liquid-spec docs interrupts` - Break/continue in tablerow
