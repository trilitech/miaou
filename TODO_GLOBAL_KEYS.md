# Global Keys API Implementation Plan

**Branch:** `feature/global-keys-api`  
**Started:** 2025-12-11 00:10 UTC  
**Estimated:** 3-4 hours

## Goal
Implement type-safe, variant-based global keyboard handling that:
- Prevents key conflicts at compile time
- Self-documents available keys
- Enables auto-generated help system
- Foundation for page registry and navigation

## Tasks

- [ ] 1. Create `miaou_core/keys.ml` - Define key variant type (~30 min)
- [ ] 2. Update `PAGE_SIG` with `handled_keys` field (~15 min)
- [ ] 3. Add `Registry.register` validation (~30 min)
- [ ] 4. Update driver key parsing to use variants (~45 min)
- [ ] 5. Write tests for conflict detection (~30 min)
- [ ] 6. Update README with keys API docs (~20 min)
- [ ] 7. Run full build/test/coverage (~10 min)
- [ ] 8. Clean commit and push (~10 min)

## Design

### Key Type (variant-based)
```ocaml
type t =
  (* Global reserved keys *)
  | Settings | Help | Menu | Quit
  
  (* Navigation *)
  | Up | Down | Left | Right
  | PageUp | PageDown | Home | End
  | Enter | Escape | Tab | Backspace
  
  (* Available for pages *)
  | Char of char
  | Digit of int
  | Function of int  (* F1-F12 *)
  | Ctrl of char
  | Alt of char
```

### Page Signature Extension
```ocaml
module type PAGE_SIG = sig
  type t
  val name : string
  val handled_keys : Keys.t list  (* NEW *)
  val create : unit -> t
  val update : t -> event -> t * status
  val view : t -> string
end
```

### Validation at Registration
```ocaml
let register (module P : PAGE_SIG) =
  (* Check for conflicts with global keys *)
  let conflicts = List.filter is_global_key P.handled_keys in
  if conflicts <> [] then
    failwith (sprintf "Page %s conflicts with global keys: %s" 
      P.name (show_keys conflicts));
  (* Register page *)
  pages := (module P) :: !pages
```

## Success Criteria
- ✅ Build passes with no warnings
- ✅ All tests pass
- ✅ Coverage maintained/increased
- ✅ Conflict detection works (test with intentional conflict)
- ✅ README updated with example
- ✅ Demo/examples use new API

---
**Progress will be tracked here. Delete after completion.**
