# Used by "mix format"
locals_without_parens = [imison_dashboard: 1, imison_dashboard: 2]

[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  plugins: [Styler],
  inputs: ["{mix,.formatter,.credo}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
