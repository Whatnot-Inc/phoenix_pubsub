defmodule Phoenix.Tracker.Clock do
  @moduledoc false
  alias Phoenix.Tracker.State

  @type context :: State.context
  @type clock :: {State.name, context}

  @doc """
  Returns a list of replicas from a list of contexts.
  """
  @spec clockset_replicas([clock]) :: [State.name]
  def clockset_replicas(clockset) do
    for {replica, _} <- clockset, do: replica
  end

  @doc """
  Adds a replicas context to a clockset, keeping only dominate contexts.

  Dominance is evaluated on the intersection of replicas the two clocks have
  in common (see `dominates_on_shared?/2`). Replicas present in one clock but
  not the other are treated as "ignored" for the comparison. This avoids
  spurious transfer requests when peers drop different replicas from their
  broadcast clocks at slightly different times (e.g. during independent
  down-detection of the same dead peer).
  """
  @spec append_clock([clock], clock) :: [clock]
  def append_clock(clockset, {_, clock}) when map_size(clock) == 0, do: clockset
  def append_clock(clockset, {node, clock}) do
    big_clock = combine_clocks(clockset)
    cond do
      dominates_on_shared?(clock, big_clock) -> [{node, clock}]
      dominates_on_shared?(big_clock, clock) -> clockset
      true -> filter_clocks(clockset, {node, clock})
    end
  end

  @doc """
  Checks if one clock causally dominates the other for all replicas.

  Strict dominance: `c1` dominates `c2` iff `c1` has every replica `c2` has
  with a value at least as large. A replica missing from `c1` is treated as
  having value 0, so a smaller clock cannot dominate a larger one.
  """
  @spec dominates?(context, context) :: boolean
  def dominates?(c1, c2) when map_size(c1) < map_size(c2), do: false
  def dominates?(c1, c2) do
    Enum.reduce_while(c2, true, fn {replica, clock}, true ->
      if Map.get(c1, replica, 0) >= clock do
        {:cont, true}
      else
        {:halt, false}
      end
    end)
  end

  @doc """
  Checks if `c1` dominates `c2` considering only replicas they share.

  Unlike `dominates?/2`, replicas present in `c2` but absent from `c1` are
  treated as ignored (vacuously matched) rather than as zero. This is the
  semantics `append_clock/2` and `filter_clocks/2` use, so that two peers'
  clocks can agree on the live replicas they share even when one has
  dropped a down or permdowned replica that the other still tracks.
  """
  @spec dominates_on_shared?(context, context) :: boolean
  def dominates_on_shared?(c1, c2) do
    Enum.reduce_while(c2, true, fn {replica, clock}, true ->
      case c1 do
        %{^replica => c1_clock} when c1_clock >= clock -> {:cont, true}
        %{^replica => _} -> {:halt, false}
        _ -> {:cont, true}
      end
    end)
  end

  @doc """
  Checks if one clock causally dominates the other for their shared replicas.
  """
  def dominates_or_equal?(c1, c2) when c1 == %{} and c2 == %{}, do: true
  def dominates_or_equal?(c1, _c2) when c1 == %{}, do: false
  def dominates_or_equal?(c1, c2) do
    Enum.reduce_while(c1, true, fn {replica, clock}, true ->
      if clock >= Map.get(c2, replica, 0) do
        {:cont, true}
      else
        {:halt, false}
      end
    end)
  end

  @doc """
  Returns the upper bound causal context of two clocks.
  """
  def upperbound(c1, c2) do
    Map.merge(c1, c2, fn _, v1, v2 -> max(v1, v2) end)
  end

  @doc """
  Returns the lower bound causal context of two clocks.
  """
  def lowerbound(c1, c2) do
    Map.merge(c1, c2, fn _, v1, v2 -> min(v1, v2) end)
  end

  @doc """
  Returns the clock with just provided replicas.
  """
  def filter_replicas(c, replicas), do: Map.take(c, replicas)

  @doc """
  Returns replicas from the given clock.
  """
  def replicas(c), do: Map.keys(c)

  defp filter_clocks(clockset, {node, clock}) do
    clockset
    |> Enum.reduce({[], false}, fn {node2, clock2}, {set, insert} ->
      if dominates_on_shared?(clock, clock2) do
        {set, true}
      else
        {[{node2, clock2}| set], insert || !dominates_on_shared?(clock2, clock)}
      end
    end)
    |> case do
      {new_clockset, true} -> [{node, clock} | new_clockset]
      {new_clockset, false} -> new_clockset
    end
  end

  defp combine_clocks(clockset) do
    clockset
    |> Enum.map(fn {_, clocks} -> clocks end)
    |> Enum.reduce(%{}, &upperbound(&1, &2))
  end
end
