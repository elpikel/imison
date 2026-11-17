defmodule Imison.Analytics.BotTest do
  use ExUnit.Case, async: true

  alias Imison.Analytics.Bot

  test "browsers are not bots" do
    browsers = [
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.5; rv:132.0) Gecko/20100101 Firefox/132.0",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
      "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36",
      "Mozilla/5.0 (Linux; Android 10; CUBOT_X30) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36",
      "Mozilla/5.0 (Linux; Android 9; CUBOT KINGKONG 5 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
      "Mozilla/5.0 (X11; Linux Mint/20.3; Linux x86_64; rv:98.0) Gecko/20100101 Firefox/98.0"
    ]

    assert Enum.reject(browsers, &Bot.bot?/1) == browsers
  end

  test "a missing or blank user agent is a bot" do
    assert Bot.bot?(nil)
    assert Bot.bot?("")
    assert Bot.bot?("   ")
  end

  test "search engine crawlers are bots" do
    crawlers = [
      "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
      "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
      "Mozilla/5.0 (compatible; Yahoo! Slurp; http://help.yahoo.com/help/us/ysearch/slurp)",
      "Mozilla/5.0 (compatible; Baiduspider/2.0; +http://www.baidu.com/search/spider.html)",
      "CCBot/2.0 (https://commoncrawl.org/faq/)"
    ]

    assert Enum.filter(crawlers, &Bot.bot?/1) == crawlers
  end

  test "headless browsers and auditing tools are bots" do
    tools = [
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/130.0.0.0 Safari/537.36",
      "Mozilla/5.0 (Linux; Android 11; moto g power (2022)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36 Chrome-Lighthouse"
    ]

    assert Enum.filter(tools, &Bot.bot?/1) == tools
  end

  test "uptime monitors are bots" do
    monitors = [
      "Pingdom.com_bot_version_1.4_(http://www.pingdom.com/)",
      "Mozilla/5.0+(compatible; UptimeRobot/2.0; http://www.uptimerobot.com/)",
      "Site24x7 Monitor"
    ]

    assert Enum.filter(monitors, &Bot.bot?/1) == monitors
  end

  test "link previews are bots" do
    previews = [
      "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
      "Slackbot-LinkExpanding 1.0 (+https://api.slack.com/robots)",
      "Mozilla/5.0 (compatible; Discordbot/2.0; +https://discordapp.com)",
      "WhatsApp/2.23.20.0 A",
      "Mozilla/5.0 (en-us) AppleWebKit/525.13 (KHTML, like Gecko; Google Web Preview) Version/3.1 Safari/525.13"
    ]

    assert Enum.filter(previews, &Bot.bot?/1) == previews
  end

  test "HTTP libraries and command line tools are bots" do
    clients = [
      "curl/8.7.1",
      "Wget/1.21.4",
      "python-requests/2.32.3",
      "Go-http-client/2.0",
      "okhttp/4.12.0",
      "axios/1.7.7",
      "node-fetch/1.0 (+https://github.com/bitinn/node-fetch)",
      "Java/17.0.2",
      "Apache-HttpClient/4.5.14 (Java/17.0.2)"
    ]

    assert Enum.filter(clients, &Bot.bot?/1) == clients
  end

  test "bot tokens are matched whatever their case" do
    assert Bot.bot?("SOMECRAWLER/1.0")
    assert Bot.bot?("my-SPIDER")
  end
end
