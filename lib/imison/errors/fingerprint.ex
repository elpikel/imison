defmodule Imison.Errors.Fingerprint do
  @moduledoc false

  alias Imison.Errors.Frame

  @type t :: %{fingerprint: String.t(), location: String.t() | nil}

  @spec from_frames(String.t(), [Frame.t()], atom()) :: t()
  def from_frames(kind, frames, otp_app) do
    frame = grouping_frame(frames, otp_app)

    %{fingerprint: hash(kind, frame), location: location(frame)}
  end

  defp grouping_frame(frames, otp_app) do
    Enum.find(frames, List.first(frames), &application_frame?(&1, otp_app))
  end

  defp application_frame?(%Frame{module: module}, otp_app) do
    :application.get_application(module) == {:ok, otp_app}
  end

  defp hash(kind, frame) do
    :sha256
    |> :crypto.hash([kind | frame_identity(frame)])
    |> Base.encode16(case: :lower)
  end

  defp frame_identity(nil), do: []

  defp frame_identity(%Frame{module: module, function: function, arity: arity}) do
    [
      "\n",
      Atom.to_string(module),
      "\n",
      Atom.to_string(function),
      "\n",
      Integer.to_string(arity)
    ]
  end

  defp location(nil), do: nil

  defp location(%Frame{module: module, function: function, arity: arity, file: file, line: line}) do
    mfa = Exception.format_mfa(module, function, arity)

    case {file, line} do
      {nil, _line} -> mfa
      {file, nil} -> "#{mfa} (#{file})"
      {file, line} -> "#{mfa} (#{file}:#{line})"
    end
  end
end
