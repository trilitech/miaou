# Driver Refactoring Plan

## Current State

### What Exists
- `miaou_driver_common` library with:
  - `Driver_common.Make` functor for basic event loop
  - `Modal_utils` for modal overlay rendering
  - `Page_transition_utils` for page transitions
  
### What's Not Used Yet
- Neither `lambda_term_driver.ml` (934 lines) nor `sdl_driver.ml` (721 lines) use the functor
- Both implement their own custom event loops with advanced features

### Key Challenges
1. **SDL-specific features not in common code:**
   - Chart context management for SDL rendering
   - Advanced transitions with text capture
   - Pixel-based rendering coordination
   
2. **Terminal-specific features:**
   - LambdaTerm integration
   - Terminal size detection
   - Raw mode handling

## Refactoring Strategy

### Phase 1: Extract More Common Utilities (DONE)
- ✅ Modal rendering logic
- ✅ Page transition coordination
- ✅ Basic event loop structure

### Phase 2: Extend Common Infrastructure (TODO)
The `Driver_common.Make` functor needs to support advanced driver features:

```ocaml
module type DRIVER_BACKEND = sig
  (* ... existing fields ... *)
  
  (** Optional: Called before and after page transitions *)
  val prepare_transition : unit -> unit
  val cleanup_transition : unit -> unit
  
  (** Optional: Backend-specific rendering extensions *)
  val before_render : unit -> unit  
  val after_render : unit -> unit
end
```

### Phase 3: Migrate Drivers to Use Functor (TODO)
1. Create `Sdl_backend` module implementing `DRIVER_BACKEND`
2. Create `Term_backend` module implementing `DRIVER_BACKEND`
3. Replace custom loops with `Driver_common.Make(Backend).run`
4. Test thoroughly - transitions, modals, charts, etc.

### Phase 4: Further Size Reduction (TODO)
Once drivers use the common loop:
- `sdl_driver.ml` should drop to ~300-400 lines (init, backend impl, cleanup)
- `lambda_term_driver.ml` should drop to ~400-500 lines

## Benefits

1. **Reduced duplication:** ~400 lines of event loop logic shared
2. **Easier maintenance:** Bug fixes in one place
3. **Consistent behavior:** Modal/transition handling identical across drivers
4. **Future drivers:** New backends (e.g., Web, native GUI) can reuse infrastructure

## Risks

1. **Regression potential:** Complex refactoring of critical code
2. **Feature parity:** Must preserve all existing functionality
3. **Testing burden:** Need comprehensive tests for both drivers

## Recommendation

This refactoring is **valuable but non-urgent**. The current code works correctly, and the size reduction through earlier module extraction is already substantial. 

Consider doing Phase 2-3 in a future dedicated refactoring sprint with:
- Comprehensive test coverage first
- Feature freeze during refactoring
- Thorough QA of transitions, charts, and modal behavior
