defmodule M4 do
  @moduledoc """
    M4
  """
  def f(a, b) do
    if b != 0 do
      if a > b do
        a = a - b
      else
        b = b - a
        # 1
      end

      f(a, b)
    else
      a
      # 2
    end

    # 3
  end

  # 4
end
