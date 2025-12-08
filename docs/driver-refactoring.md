# Driver Refactoring Analysis

## Overview

The TUI (lambda_term) and SDL drivers have significant code duplication in their event loop logic, modal handling, and page transition management. This document analyzes the duplication and proposes refactoring strategies.

## Current State

### File Sizes
- `lambda_term_driver.ml`: 938 lines
- `sdl_driver.ml`: 718 lines
- `driver_common.ml`: 105 lines (initial shared code)

### Identified Duplication

#### 1. Main Event Loop Structure
Both drivers implement nearly identical event loops:
- Poll for events (keyboard, refresh, quit)
- Render current page view
- Handle modal overlays
- Route key presses to modals or pages
- Manage page transitions via Registry lookup
- Handle service cycles for periodic updates

**Location:**
- TUI: `lambda_term_driver.ml` lines 523-700
- SDL: `sdl_driver.ml` lines 575-710

#### 2. Modal Rendering Logic
Direct copy-paste of modal overlay rendering:
- Check if modal is active via `Modal_manager.has_active()`
- Call `Modal_renderer.render_overlay` with base view
- Return overlaid view or original if no modal

**Location:**
- TUI: `lambda_term_driver.ml` lines 118-127
- SDL: `sdl_driver.ml` lines 400-410

#### 3. Key Press Routing
Identical decision tree:
1. Check if modal is active → send to `Modal_manager`
2. Otherwise, dispatch to page:
   - `Up`/`Down` → `Page.move`
   - `Enter` → `Page.enter`  
   - `q`/`Q` → quit
   - Other → `Page.handle_key`
3. Check `Page.next_page` for transitions

**Location:**
- TUI: `lambda_term_driver.ml` lines 566-680
- SDL: `sdl_driver.ml` lines 616-710

#### 4. Page Transition Handling
When `next_page` returns `Some page_name`:
- Look up page in `Registry.find`
- Initialize new page state with `Next.init()`
- Recursively call loop with new page module and state
- Handle special `__QUIT__` page name

**Location:**
- TUI: `lambda_term_driver.ml` lines 583-614
- SDL: `sdl_driver.ml` lines 584-615, 675-705 (repeated 3 times!)

## Initial Refactoring: Common Library

Created `miaou_driver_common` library with:

### Modal_utils Module
```ocaml
val render_with_modal_overlay : view:string -> rows:int -> cols:int -> string
```
Shared helper for modal overlay rendering (eliminates duplication #2).

### DRIVER_BACKEND Signature
```ocaml
module type DRIVER_BACKEND = sig
  type size = {rows : int; cols : int}
  type event = Quit | Refresh | Key of string
  
  val poll_event : unit -> event
  val render : view:string -> size:size -> unit
  val detect_size : unit -> size
  val init : unit -> unit
  val cleanup : unit -> unit
end
```

### Make Functor
```ocaml
module Make (Backend : DRIVER_BACKEND) : sig
  val run : (module PAGE_SIG) -> [`Quit | `SwitchTo of string]
end
```

Provides shared event loop logic.

## Limitations of Current Approach

The initial refactoring addresses ~20% of duplication but has limitations:

### 1. **Simplified Event Loop**
Current functor doesn't handle:
- Key handler stacks (`Khs` module in TUI driver)
- Footer hints generation from key bindings
- Narrow terminal warnings
- Frame caching (to avoid unnecessary redraws)
- Resize detection and handling

### 2. **No Transition Support**
SDL driver has complex transition effects (fade, slide, explode) that require:
- Capturing page views as text during transition
- Disabling SDL chart rendering temporarily
- Calling `perform_transition` with before/after states

TUI driver has simpler but still custom transition handling.

### 3. **Different Refresh Mechanisms**
- TUI: Service cycle with throttling, explicit refresh events
- SDL: Timeout-based polling with immediate updates

### 4. **Backend-Specific Features**
- TUI: Raw terminal mode, SIGWINCH handling, pager integration
- SDL: Window management, font rendering, SDL context state

## Recommended Next Steps

### Phase 1: Extract More Utilities (Low Risk)
Extract smaller, independent helpers:

```ocaml
module Page_transition_utils : sig
  val handle_transition :
    from_page:(module PAGE_SIG with type state = 's) ->
    from_state:'s ->
    to_name:string ->
    [`Quit | `Continue of (module PAGE_SIG) * 'state]
end
```

**Benefit:** Eliminate duplication #4 without changing driver structure.  
**Effort:** ~1 day  
**Risk:** Low

### Phase 2: Parameterized Event Loop (Medium Risk)
Extend `Make` functor to accept hooks:

```ocaml
module type DRIVER_BACKEND = sig
  (* existing fields *)
  
  val on_resize : unit -> unit  
  val on_render_start : unit -> unit
  val on_transition : from:string -> to:string -> unit
  (* ... *)
end
```

**Benefit:** Share 60-70% of loop logic while preserving customization.  
**Effort:** ~3-5 days  
**Risk:** Medium (requires careful testing of both drivers)

### Phase 3: Full Unification (High Risk)
Make drivers thin wrappers around common implementation:

```ocaml
(* In lambda_term_driver.ml *)
include Driver_common.Make(struct
  (* ~50 lines of backend impl *)
end)

(* In sdl_driver.ml *)  
include Driver_common.Make(struct
  (* ~80 lines of backend impl *)
end)
```

**Benefit:** DRY principle fully satisfied, ~1400 lines → ~600 lines.  
**Effort:** ~1-2 weeks  
**Risk:** High (major refactoring, extensive testing needed)

## Trade-offs Analysis

### Current Duplication (Do Nothing)
**Pros:**
- Each driver is self-contained and understandable
- No risk of breaking changes
- Backend-specific optimizations are easy

**Cons:**
- Bug fixes must be applied twice
- New features (like modals) require dual implementation
- Maintenance burden increases over time

### Partial Refactoring (Recommended)
**Pros:**
- Eliminate most obvious duplication (modal utils, transitions)
- Low risk, incremental improvements
- Drivers remain customizable

**Cons:**
- Still some duplication in main loops
- Requires discipline to use shared code

### Full Unification
**Pros:**
- Maximum code reuse
- Single source of truth for driver logic
- Easier to add new backends (e.g., HTML, image export)

**Cons:**
- Upfront effort is significant
- May constrain backend-specific optimizations
- Functor complexity may confuse contributors

## Decision: Start with Phase 1

**Rationale:**
1. **Low risk:** Extract utilities without changing core structure
2. **Quick wins:** Immediate reduction in duplication
3. **Foundation:** Sets up for Phase 2 if benefits are clear
4. **Reversible:** Can abandon if approach doesn't work

**Next Concrete Steps:**
1. Extract `Page_transition_utils` module
2. Update both drivers to use it
3. Write tests for the shared utilities
4. Measure impact (LOC reduction, bug surface area)
5. Decide on Phase 2 based on results

## Metrics for Success

Track these to evaluate refactoring value:

- **LOC reduction:** Target 10-15% in Phase 1
- **Bug reduction:** Track driver-related bugs before/after
- **Contributor feedback:** Survey maintainability perception
- **Build time:** Ensure no significant regression
- **Test coverage:** Maintain or improve coverage %

## References

- [Original review](context:driver-duplication-analysis)
- [Driver common library](../src/miaou_driver_common/)
- [PAGE_SIG interface](../src/miaou_core/tui_page.mli)
