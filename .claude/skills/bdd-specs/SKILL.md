---
name: bdd-specs
description: >-
  Behavior-driven design for Elixir/Phoenix: write executable ExUnit specs
  BEFORE implementation code, from the agreed acceptance criteria (a tracker
  issue or a /brainstorm conversation). Tests go in the endpoint's file
  (controllers/<controller>/<action>_test.exs), the LiveView's file or the
  module's file, never a story-named file; flat top-level tests (no describe,
  no setup), each test arranging its own data with the project's factories or
  fixtures and asserting one behaviour; happy paths first, sad paths after.
  New specs are never skipped: they run red until built. At least one test per
  Feature goes through the real entry point (router, LiveView or Oban worker
  perform/1). Use when asked to "spec out", "write the tests first", do
  BDD/TDD, or turn stories into a test suite.
---

# Behavior-Driven Design: Specifications First (ExUnit)

Specs are written **before** implementation. They encode the intended
behaviour from the agreed acceptance criteria, start red, and become the
definition of done. Don't write implementation code under this skill.

## 🎯 Why: Design for Change

Specs are the safety net that makes change possible. One behaviour per test
means a failing test names exactly what broke; happy/sad ordering means you
can change one behaviour without re-reading the whole file.

## Repo facts come from `.claude/project.md`

Read it first. It names the endpoint and data test case modules, the test
file layout, the factory or fixture modules, the Mox mocks (if any), the
access rules and the test-data rules. Never assume them. The rules below are
the kit's default house style; `.claude/project.md` may override a style rule
under *Style overrides*; follow it when it does.

## The workflow (in order)

### 1. Require agreed acceptance criteria
They come from the issue (tracker in `.claude/project.md`) or from the
`/brainstorm` conversation, written to `.claude/work/<slug>/stories.md`
(inside `/implement`, the task's criteria are passed to you). If there are
none, or they're too vague to assert on, stop and ask. Never invent
criteria. Each story is one Feature; each acceptance criterion is a group of
tests.

### 2. Read what exists
Read the endpoint's, LiveView's and module's existing test files. Append to
them. Change or remove an existing test only when the agreed acceptance
criteria change the behaviour it asserts (a `fix:` or behaviour-change task),
and name each such test in your report; never to make other code pass.

### 3. Pick the case template and location
- HTTP behaviour → `use` the endpoint test case from `.claude/project.md`
  with `async: true`, in the endpoint's file. The endpoint test file path and
  its module naming are in `.claude/project.md` (shape:
  `controllers/<controller>/<action>_test.exs`, e.g.
  `test/shop_web/controllers/product_controller/index_test.exs`). If the file
  exists, append the story's tests to it; otherwise create it. A story that
  spans several endpoints puts each endpoint's tests in that endpoint's file.
- LiveView behaviour → the endpoint test case, in the LiveView's file
  (e.g. `test/shop_web/live/<live_view>_test.exs`), driven with
  `Phoenix.LiveViewTest` (`live/2`, `element/2`, `has_element?/2`).
- Context, query or worker behaviour → the data test case from
  `.claude/project.md` with `async: true` (or `ExUnit.Case` with no DB), in
  the module test file layout from `.claude/project.md` (mirroring the
  `lib/` path of the module under test).
- Never name a file after a story or an issue id. The
  `.claude/work/<slug>/plan.md` lists which test files prove which task.

### 4. Generate, then stop
Write the files from `templates/feature_test.exs` (swap the `Shop`/`ShopWeb`
names for the app and web modules in `.claude/project.md`), then present them
for review. No implementation until the user approves.

**Inside `/implement`** (you are the `builder` subagent): don't stop. The user
approved the plan by running `/implement`. Run the new tests, confirm they
fail for the right reason, then go on to the implementation.

## The spec shape (mandatory)

Illustrative app `:shop`; adapt module names to your repo.

```elixir
defmodule ShopWeb.Controllers.ProductController.IndexTest do
  use ShopWeb.ConnCase, async: true

  test "a premium member sees the member price", %{conn: conn} do
    customer = insert(:customer)
    insert(:membership, customer: customer, tier: :premium)
    product = insert(:product, price: Decimal.new("20.00"), member_price: Decimal.new("15.00"))

    response =
      conn
      |> log_in_customer(customer)
      |> get(~p"/api/products")
      |> json_response(200)

    assert [%{"id" => id, "member_price" => "15.00"}] = response["data"]
    assert id == product.id
  end
end
```

(With fixtures instead of a factory, the arrange step reads
`ShopFixtures.product_fixture(%{member_price: Decimal.new("15.00")})`.)

Hard rules for every generated file:

1. **Files belong to endpoints, LiveViews or modules, not stories.** A
   story's tests go into the file of the endpoint, LiveView or module they
   exercise. No story ids in files, test names or comments.
2. **Flat top-level `test` blocks.** No `describe`, no `setup`/`setup_all`.
3. **Each test arranges its own data inline.** If `.claude/project.md` lists
   a factory (ExMachina), arrange data with `insert(:factory)`; otherwise use
   the project's context functions or fixture modules in `test/support/`
   (e.g. `ShopFixtures.product_fixture/1`, as `phx.gen` creates).
   Non-assert fixture builders (`defp`, placed below all tests) are allowed
   when arrangement repeats; helpers containing assertions are not.
4. **One behaviour per test.** Prefer a single pattern-match `assert`. Multiple
   asserts only when they check facets of the same behaviour.
5. **Tests are named by behaviour** in plain words. No "Q1:", no ids, no
   "Scenario:" prefixes.
6. **Happy path first and exhaustive**, then sad paths (validation, not found,
   unauthorized, denied by the access rules in `.claude/project.md`).
   Never interleaved.
7. **Never skipped:** no `@tag :skip`, no exclusion tag, no commenting out.
   New tests run and stay red until the builder implements the behaviour.
   Tests that already pass are guards for existing behaviour; keep them.
8. **At least one test per Feature goes through the real entry point**: the
   router via the endpoint test case, the LiveView via `live/2`, or
   `Worker.perform/1` for Oban work (e.g.
   `Shop.Workers.SyncSupplierProducts.perform/1`). If the project mocks
   external APIs with Mox (listed in `.claude/project.md`), use
   `stub/3`/`expect/4`; otherwise use the seam the project has for that API,
   never hit the network. Never mock the app's own modules.
9. **Data rules:** reference records you created (`product.id`, or the
   project's public identifier), never hardcoded IDs; use factory sequences
   or unique fixture values. Never `Repo.delete_all` seeded reference data.
   Follow the repo's test-data rules in `.claude/project.md`.
10. **Log capture per test only:** never `@moduletag capture_log: true`; put
    `@tag :capture_log` on the individual tests that actually print logs.
    No DB tricks (triggers, DDL, spoofed constraint names) to force failures.
11. Use the domain-language terms (`CONTEXT.md`, per `.claude/project.md`) in
    test names, not generic synonyms (e.g. in Shop: Customer, not user;
    member price, not discount).

## Templates

- `templates/feature_test.exs`: the shape above with happy and sad paths.

See `references/workflow.md` for the story → tests mapping worked through.
