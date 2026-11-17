defmodule Imison.Analytics.Bot do
  @moduledoc false

  @bot_tokens ~w(
    bot crawl spider slurp scraper archiver
    headless lighthouse phantomjs selenium puppeteer playwright
    monitor pingdom uptime statuscake
    preview facebookexternalhit whatsapp embedly
    curl wget httpie python-requests python-urllib aiohttp httpx httpclient go-http-client okhttp
    axios node-fetch undici java/ libwww-perl guzzlehttp ruby faraday req/ finch hackney
  )

  @browser_tokens_with_bot_tokens ~w(cubot)

  @spec bot?(String.t() | nil) :: boolean()
  def bot?(nil), do: true

  def bot?(user_agent) when is_binary(user_agent) do
    normalized = user_agent |> String.trim() |> String.downcase() |> String.replace(@browser_tokens_with_bot_tokens, "")
    normalized == "" or String.contains?(normalized, @bot_tokens)
  end
end
