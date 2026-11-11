%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "config/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      plugins: [{ExSlop, []}],
      strict: true,
      checks: %{
        extra: [
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Refactor.AppendSingleItem, []},
          {Credo.Check.Refactor.DoubleBooleanNegation, []},
          {Credo.Check.Refactor.MapMap, []},
          {Credo.Check.Refactor.FilterFilter, []},
          {Credo.Check.Refactor.RejectReject, []},
          {Credo.Check.Refactor.FilterCount, []},
          {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig, [metadata_keys: [:domain]]}
        ],
        disabled: [
          # Styler handles these
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []}
        ]
      }
    }
  ]
}
