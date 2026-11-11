defmodule Imison.Web.Assets do
  @moduledoc """
  Serves the dashboard's stylesheet, fonts and script from Imison itself.

  The assets are read at compile time: `priv/static/app.css`, the WOFF2 fonts
  in `priv/static/fonts/`, and one script made of Phoenix's and Phoenix
  LiveView's own minified JavaScript followed by `priv/static/imison.js`,
  which connects the LiveView socket. Their URLs carry a digest of all of
  them, so they are cached for a year and change whenever an asset does. The
  stylesheet links its fonts with relative URLs, which resolve next to it.

  The routes sit in the host's `:browser` pipeline, whose CSRF protection
  refuses JavaScript to `<script>` tags; the script holds no secrets, so it
  is served past that check, as Phoenix LiveDashboard serves its own.
  """

  @behaviour Plug

  import Plug.Conn

  @static_path Application.app_dir(:imison, "priv/static")
  @stylesheet_path Path.join(@static_path, "app.css")
  @script_paths [
    Application.app_dir(:phoenix, "priv/static/phoenix.min.js"),
    Application.app_dir(:phoenix_live_view, "priv/static/phoenix_live_view.min.js"),
    Path.join(@static_path, "imison.js")
  ]
  @font_paths @static_path |> Path.join("fonts/*.woff2") |> Path.wildcard() |> Enum.sort()

  for path <- [@stylesheet_path | @script_paths ++ @font_paths] do
    @external_resource path
  end

  @assets Map.new(
            [
              {["app.css"], %{content_type: "text/css; charset=utf-8", body: File.read!(@stylesheet_path)}},
              {["app.js"],
               %{
                 content_type: "text/javascript; charset=utf-8",
                 body: Enum.map_join(@script_paths, ";\n", &File.read!/1)
               }}
            ] ++
              Enum.map(@font_paths, &{["fonts", Path.basename(&1)], %{content_type: "font/woff2", body: File.read!(&1)}})
          )

  @digest @assets
          |> Enum.sort()
          |> Enum.map(fn {asset, %{body: body}} -> [asset, body] end)
          |> :erlang.md5()
          |> Base.encode16(case: :lower)

  @doc """
  Returns the URL path of the stylesheet or the script of a dashboard mounted at `dashboard_path`.
  """
  @spec path(String.t(), :stylesheet | :script) :: String.t()
  def path(dashboard_path, :stylesheet), do: Path.join([dashboard_path, "assets", @digest, "app.css"])
  def path(dashboard_path, :script), do: Path.join([dashboard_path, "assets", @digest, "app.js"])

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with %{"digest" => @digest, "asset" => asset} <- conn.path_params,
         {:ok, %{content_type: content_type, body: body}} <- fetch_asset(asset) do
      conn
      |> put_resp_header("content-type", content_type)
      |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
      |> put_private(:plug_skip_csrf_protection, true)
      |> send_resp(200, body)
      |> halt()
    else
      _not_served -> not_found(conn)
    end
  end

  for {asset, served} <- @assets do
    defp fetch_asset(unquote(asset)), do: {:ok, unquote(Macro.escape(served))}
  end

  defp fetch_asset(_asset), do: :error

  defp not_found(conn) do
    conn
    |> send_resp(404, "Not found")
    |> halt()
  end
end
