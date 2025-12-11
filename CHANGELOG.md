# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added (2025-12-11)

#### Global Keys API
- **Type-safe keyboard handling system** with variant-based key definitions
- Extended `Keys.t` with new key types: `PageUp`, `PageDown`, `Home`, `End`, `Escape`, `Delete`, `Function of int`
- Global key reservations for application-wide actions: `Settings`, `Help`, `Menu`, `Quit`
- Registry validation to prevent key conflicts at page registration time
- `Registry.check_all_conflicts()` for detecting inter-page key conflicts
- `Registry.conflict_report()` for human-readable conflict summaries
- Helper functions: `Keys.is_global_key`, `Keys.get_global_action`, `Keys.show_global_keys`

### Changed (2025-12-10)

#### Performance Optimizations
- **Significant performance improvements** across all widgets (8-24x faster in some cases)
- Replaced `String.concat` with buffer-based rendering throughout codebase
- Introduced `Helpers.pad_to_width` eliminating O(n²) padding allocations
- Optimized pager widget: 9.1s → 1.2s (8x faster)
- Optimized layout widget: 9.0s → 0.8s (12x faster)
- Optimized card_sidebar: 15.1s → 1.0s (15x faster)
- All other widgets show 20-40% performance improvements

### Breaking Changes (2025-12-11)

#### ⚠️ PAGE_SIG Requires `handled_keys` Function

**Impact:** All page implementations must be updated.

**What changed:**
```ocaml
module type PAGE_SIG = sig
  (* ... existing fields ... *)
  
  (* NEW - REQUIRED *)
  val handled_keys : unit -> Keys.t list
end
```

**Migration guide:**

For **minimal migration**, add this to every page:
```ocaml
let handled_keys () = []
```

For **proper key declaration** (recommended):
```ocaml
let handled_keys () = [
  Keys.Char "a";      (* Declare all keys your page handles *)
  Keys.Enter;
  Keys.Up;
  Keys.Down;
  (* ... *)
]
```

**Why this change?**
- Enables compile-time key conflict detection
- Self-documents key bindings
- Foundation for auto-generated help system
- Enables future page registry and navigation features

**Compiler error you'll see:**
```
Error: Signature mismatch:
       The value `handled_keys' is required but not provided
       File "src/miaou_core/tui_page.mli", line 38, characters 2-40:
         Expected declaration
```

**Benefits:**
- ✅ Type-safe key handling (variants, not strings)
- ✅ Prevents global key conflicts automatically
- ✅ Runtime validation catches inter-page conflicts
- ✅ Clear error messages when conflicts occur

## [Previous Releases]

<!-- Previous changelog entries would go here -->
