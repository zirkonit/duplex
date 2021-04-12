defmodule M1 do
  @moduledoc """
    M1
  """
  def f(a, b) do
    if b != 0 do
      if a > b do
        a = a - b
      else
        b = b - a
      end

      f(a, b)
    else
      a
    end
  end
end
