# Capturing errors

Once `{Imison, ...}` is in your supervision tree, errors are captured without
code changes. This guide covers what is captured, how to report errors you
rescue yourself, and how to keep noise and secrets out.

## What is captured

| Source | How | Context stored |
|---|---|---|
| Phoenix requests | The `[:phoenix, :router_dispatch, :exception]` telemetry event | Method, path, params and headers |
| Oban jobs | The `[:oban, :job, :exception]` telemetry event, when your app runs Oban | Worker, queue, args and attempt |
| Crashed processes | A `:logger` handler that receives crash reports, e.g. a `GenServer` or `Task` that raises or exits | The crashed process's pid and registered name |
| Rescued exceptions | `Imison.report/3`, see below | The metadata you pass |

Every occurrence also stores the node it happened on and, when you set the
`release` option, your release label.

Oban isn't a dependency of Imison: the handler just does nothing when your app
doesn't emit Oban events. Crash reports logged by Imison itself and by the
HTTP servers (`:cowboy`, `:bandit`) are skipped. The HTTP servers' reports
duplicate the Phoenix event, and skipping Imison's own keeps a broken database
from turning into an endless loop of errors about recording errors.

## Grouping

Occurrences are grouped into errors by a fingerprint: the exception module
plus the function (module, name and arity) of the first stack frame from your
own code. When no frame is from your code, the first frame is used instead.

- **Messages don't count.** `invalid order id: "abc"` and
  `invalid order id: "xyz"` are one error with two occurrences.
- **Lines don't count either.** Two `ArgumentError`s raised on different
  lines of the same function are one error. The error keeps the location of
  its first occurrence; each occurrence's own stack trace shows its line.

A frame is "your code" when its module belongs to the OTP application of the
repo Imison is configured with (`MyApp.Repo` → `:my_app`). In an umbrella
project, frames from your other apps count as dependency frames.

Tail calls drop frames from the stack, so a function that ends by calling a
dependency, like `def find(code), do: Repo.query!(...)`, may not appear in
the stack trace at all. The error is then grouped and located at the
dependency's frame. That is how the BEAM works, not something Imison
controls.

## Reporting rescued exceptions

An exception your code rescues never crashes anything, so nothing captures
it. Report it yourself with `Imison.report/3`:

```elixir
try do
  MyApp.Payments.charge(order)
rescue
  exception ->
    Imison.report(exception, __STACKTRACE__, %{order_id: order.id})
    {:error, :charge_failed}
end
```

- `metadata` is a map or a keyword list, and it is optional. It is shown
  under "Logger metadata" on the error's page and filtered like every other
  context.
- A value that isn't an exception, such as an Erlang error term, is
  normalized to its exception first.
- `report/3` always returns `:ok`. It never raises and never blocks, and it
  does nothing when no Imison instance is running.
- It reports to the default instance, named `Imison`.

## Imison never slows your app down

Capturing runs in the process that failed, so it does as little as possible
there: it builds the event and sends it to Imison's worker process. The
worker filters the event, writes it to the database and sends notifications.

- If the worker falls behind by 1,000 events, for example during a crash
  storm, new events are dropped instead of queued, so memory stays bounded.
- If recording fails, for example because the database is down, the failure
  is logged under the `:imison` logger domain and your app carries on.
  Imison never captures its own failures.

## Keeping secrets out: `filter`

Before an occurrence is stored, every key in its params, headers and metadata
is checked against the `filter` words. When the key contains a filter word
(case-insensitively), its value is replaced with `[FILTERED]`. Nested maps,
lists and structs are walked too.

The default words are `password`, `token`, `secret`, `authorization` and
`cookie`. So `password_confirmation`, `api_token` and `x-auth-token` are all
filtered.

Setting `filter` replaces the list, so repeat the defaults you want to
keep:

```elixir
config :my_app, Imison,
  filter: ~w(password token secret authorization cookie card iban ssn)
```

Exception messages aren't filtered. Don't put secrets in them.

## Skipping expected exceptions: `ignore`

Some exceptions are part of normal operation, such as `Ecto.NoResultsError`,
which Phoenix turns into a 404 page. List their modules in `ignore` and they
are never recorded:

```elixir
config :my_app, Imison,
  ignore: [Ecto.NoResultsError, Phoenix.NotAcceptableError]
```

This applies to every source, including `Imison.report/3`. An error that's
already listed and that you don't want to see is better set to Ignored on the
dashboard: it keeps counting, so you can tell if it explodes.

## Tagging releases: `release`

Set `release` to your app's version or git SHA, and each occurrence shows it
under Runtime. You can then tell whether an error that came back happened
before or after a deploy.

```elixir
# config/runtime.exs
config :my_app, Imison, release: System.get_env("RELEASE_SHA")
```

## Turning capture off: `enabled`

```elixir
# config/test.exs
config :my_app, Imison, enabled: false
```

With `enabled: false` the instance still starts and `Imison.config/1` still
works, but it attaches no handler and starts no worker, pruner or daily summary. Crashes,
Phoenix and Oban exceptions, and `Imison.report/3` calls record nothing.
`mix imison.install` sets this for the test environment, so tests that crash
on purpose don't fill your database.
