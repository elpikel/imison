defmodule Imison.Test.Mailer do
  @moduledoc """
  The host's Swoosh mailer in tests, on the `Swoosh.Adapters.Test` adapter.

  Delivery runs in a task Imison starts, not in the test process, so tests
  that deliver call `Swoosh.TestAssertions.set_swoosh_global/1` to receive
  the emails.
  """

  use Swoosh.Mailer, otp_app: :imison
end
