---
name: design-principles
description: >-
  Design principles for Elixir/Phoenix/Ecto code: coupling and cohesion
  (incl. connascence), DRY, YAGNI, KISS, separation of concerns, information
  hiding, Tell Don't Ask, Law of Demeter, composition of functions and
  behaviours, programming to a behaviour, Command–Query Separation, least
  astonishment, and fail fast with ok/error tuples. Use when designing or
  reshaping context modules, deciding where a function or query belongs,
  drawing a seam around an external API, reviewing a diff for coupling,
  duplication or leaky contexts, or deciding whether an abstraction earns
  its keep.
---

# Design Principles for Elixir

The heuristics that decide where code lives and what it may know about other
code — applied to contexts, schemas, controllers, Oban workers and behaviours.

## 🎯 Why: Design for Change

The goal of writing software is to be able to **change it safely**. Coupling
is the cost of the next change; cohesion is its locality. Tell-Don't-Ask,
Demeter and information hiding exist to shrink the blast radius of an edit.
DRY and YAGNI cut both ways: too little abstraction and a change ripples; too
much and the seam is in the wrong place. Pick the shape that makes the *next*
diff small.

## How to use this skill

1. Match the symptom in the decision guide to a principle.
2. Open `references/principles.md` for that principle's wrong/right Elixir
   example and its "when this is over-engineering" note.
3. Apply the smallest change that removes real pain. The principles trade off
   (DRY vs. coupling, YAGNI vs. extensibility); resolve in favour of the code
   that is cheapest to change *now*.

All examples follow the project conventions in `.claude/agents/builder.md`.
Examples use an illustrative `Shop` app; adapt names to your repo.

## The principles

| Principle | One-line intent |
|---|---|
| **Coupling** | Minimise what one module must know about another; measure it with connascence. |
| **Cohesion** | A module has one reason to change; group what changes together. |
| **DRY** | Every piece of *knowledge* has one authoritative home. |
| **YAGNI** | Don't build it until a real requirement demands it. |
| **KISS** | Prefer the simplest design that works; complexity must be earned. |
| **Separation of Concerns** | Controller parses, context decides, query fetches, view renders. |
| **Information Hiding** | A context's schemas and queries are its private business. |
| **Tell, Don't Ask** | Ask the owning module for the answer; don't pull its data out to decide. |
| **Law of Demeter** | Don't navigate another context's associations or structs. |
| **Composition** | Build behaviour from small functions and behaviours; there is no inheritance. |
| **Program to a Behaviour** | External systems sit behind a `@callback` contract, swapped by config. |
| **Command–Query Separation** | A function either changes state or answers a question, not both. |
| **Least Astonishment** | Names, return shapes and `!` match what the caller expects. |
| **Fail Fast** | Reject bad input at the boundary; let impossible states crash. |

## Decision guide — symptom → principle

| You notice… | Apply |
|---|---|
| Changing one context forces edits in three others | **Coupling** (find the connascence) |
| A `helpers.ex` of unrelated functions used by different callers | **Cohesion** |
| The same business rule encoded in three modules | **DRY** |
| Two functions look identical but model different concepts | *Stop* — false DRY |
| A behaviour, config key or option with exactly one implementation and no test seam | **YAGNI** |
| A macro or generic pipeline nobody can explain | **KISS** |
| Controller builds Ecto queries, or a context reads `conn.params` | **Separation of Concerns** |
| Another module joins on this context's schema directly | **Information Hiding** |
| Callers fetch a struct then branch on its fields to decide policy | **Tell, Don't Ask** |
| `order.customer.membership.plan.discount_rate` chains | **Law of Demeter** |
| `use SomeBase` macros injecting overridable functions | **Composition** |
| A context calls an HTTP client module directly, untestable without the network | **Program to a Behaviour** |
| `get_*` that inserts, or an upsert whose return value drives control flow | **CQS** |
| `fetch_product/1` returning `nil`, or a non-`!` function that raises | **Least Astonishment** |
| A `nil` discovered three calls deep, far from the request | **Fail Fast** |

## Elixir-specific guidance

- **Contexts are the public API.** `<context root>/<context>.ex` (context
  root in `.claude/project.md`) is what other code
  calls. Schemas and query modules underneath are private by convention; no
  other context joins on them. Cross-context data goes through a function.
- **Behaviours at external boundaries only.** Each external API has a
  `@callback` module whose implementation is resolved via
  `Application.get_env/3`; tests swap in a Mox mock if `.claude/project.md`
  lists Mox, otherwise a test implementation of the behaviour. Don't add behaviours
  for the app's own modules — test those for real against the sandboxed DB.
- **Connascence of position is the common smell.** Positional args beyond
  three become a map of named params; tuples bundling data become maps.
- **Pattern-match in function heads** to make the accepted shapes explicit,
  and let unmatched shapes crash (Fail Fast for free).
- **`with` for dependent steps** that can each fail; a pipe for steps that
  can't.
- **Structs for domain values with invariants** (`@enforce_keys`, e.g. a
  `Shop.Accounts.Membership`); plain maps for transient, request-shaped data.
- **A GenServer is a runtime decision, not a code-organisation tool.** Use one
  only for state that must live across calls or serialised access. Pure logic
  belongs in plain modules; scheduled work belongs in Oban (or the repo's
  job runner, per *Background jobs* in `.claude/project.md`).
- **DRY is about knowledge, not characters.** Rule of Three before extracting.
