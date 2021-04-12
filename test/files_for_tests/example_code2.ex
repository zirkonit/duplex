defmodule M2 do
  @moduledoc """
    M2
  """
  def f(n, m) do
    if m != 0 do
      if n > m do
        n = n - m
      else
        m = m - n
      end

      f(n, m)
    else
      n
    end
  end
end
