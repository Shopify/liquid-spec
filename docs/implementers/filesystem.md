---
title: "Filesystem: include and render template lookup"
description: >
  How Liquid's file system resolves template names for {% include %} and
  {% render %}. Covers extension handling, case sensitivity, path traversal,
  and error behavior. Essential for implementing partial template loading.
optional: false
order: 6
---

# Filesystem: `include` and `render` template lookup

When a template uses `{% include "snippet" %}` or `{% render "snippet" %}`,
Liquid calls the file system to look up the partial template by name.
This document explains how that lookup works.

## How the File System Works

The file system is an object passed to the template via `registers[:file_system]`.
It must respond to `read_template_file(template_path)` and return the template
source string, or raise `Liquid::FileSystemError` if the template is not found.

### Name Normalization

Both the **keys** (when building the file system from a hash) and the **lookup
path** are normalized:

1. **Lowercased** — all template names are compared case-insensitively
2. **`.liquid` appended** — if the name doesn't already end with `.liquid`,
   the extension is added automatically

So `{% include "foo" %}` looks for `foo.liquid`, and a file system key `"Foo"`
is stored as `foo.liquid`. This means:

```liquid
{% include "MySnippet" %}
```

matches a key `"mysnippet.liquid"` or `"MySnippet"` or `"MYSNIPPET.liquid"`.

### Case Sensitivity

**Template lookup is case-insensitive.** The path is lowercased, and matching
uses case-insensitive comparison. This is a deliberate choice — Shopify themes
run on case-insensitive filesystems in production.

```liquid
{% include "HEADER" %}        ← matches "header.liquid"
{% render "Header" %}         ← matches "header.liquid"
```

### Extension Handling

The `.liquid` extension is optional in both the template tag and the file
system key. If omitted, it's appended automatically:

| Template tag              | File system key       | Match? |
|---------------------------|-----------------------|--------|
| `{% include "foo" %}`     | `"foo.liquid"`        | ✅ Yes |
| `{% include "foo" %}`     | `"foo"`               | ✅ Yes |
| `{% include "foo.liquid" %}` | `"foo.liquid"`     | ✅ Yes |
| `{% include "foo.liquid" %}` | `"foo"`            | ✅ Yes |

### Subpaths

Forward-slash subpaths are supported and preserved during lookup:

```liquid
{% include "snippets/header" %}
```

This looks for `snippets/header.liquid` (after normalization). The file system
key must match the full path including the subdirectory.

### Path Traversal (`..`)

**No path normalization or sanitization is performed.** The path is passed
as-is to the file system (after lowercasing and extension appending). This
means:

| Template tag              | Looks for (normalized)    | Notes |
|---------------------------|----------------------------|-------|
| `{% include "../secret" }`| `../secret.liquid`         | Literal `..` preserved |
| `{% include "foo/../bar" }`| `foo/../bar.liquid`      | NOT normalized to `bar.liquid` |

The file system implementation is responsible for any security checks.
The reference `SimpleFileSystem` does **not** block `..` — it looks up the
literal path. Production file systems (like Shopify's) should sanitize paths.

### Not Found Behavior

When a template is not found, the file system raises `Liquid::FileSystemError`
with the message `"Liquid error: Could not find asset <name>"`.

- With **strict errors** (`rethrow_errors: true`): the exception propagates
- With **inline errors** (`rethrow_errors: false`): the error is rendered
  inline as `"Liquid error: Could not find asset <name>"`

### `include` vs `render` Differences

| Feature               | `include`              | `render`                     |
|-----------------------|------------------------|------------------------------|
| Template name         | Variable or string     | **String literal only**      |
| Not found error       | Inline or raised       | Inline or raised             |
| File system lookup    | Same normalization     | Same normalization           |
| Nested partials       | Allowed (any depth)    | **Cannot nest `render`**     |
| Recursion limit       | "Nesting too deep"     | "Nesting too deep"           |

`{% render %}` requires a quoted string literal for the template name.
Using a variable is a **syntax error**:

```liquid
{% assign s = "foo" %}
{% include s %}        ← OK (include allows variables)
{% render s %}         ← SyntaxError: Template name must be a quoted string
```

### Recursion

Self-referencing partials are caught at render time with a "Nesting too deep"
error (rendered inline or raised depending on error mode). There is no
infinite loop — Liquid tracks nesting depth and aborts.

## Implementing a File System

A minimal file system implementation:

```ruby
class MyFileSystem
  def read_template_file(template_path)
    path = template_path.to_s.downcase
    path = "#{path}.liquid" unless path.end_with?(".liquid")
    
    content = @templates[path]
    raise Liquid::FileSystemError, "Could not find asset #{template_path}" unless content
    content
  end
end
```

Key points:
1. Lowercase the path
2. Append `.liquid` if missing
3. Case-insensitive comparison
4. Raise `FileSystemError` (not a generic error) when not found
5. The error message uses the **original** path, not the normalized one

## See Also

- `liquid-spec docs partials` — Differences between `include` and `render`
- `liquid-spec docs scopes` — Variable scoping in partials
