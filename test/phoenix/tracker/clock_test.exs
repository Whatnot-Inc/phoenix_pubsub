defmodule Phoenix.TrackerClockTest do
  use ExUnit.Case
  alias Phoenix.Tracker.Clock

  test "dominates?" do
    clock1 = %{a: 1, b: 2, c: 3}
    clock2 = %{b: 2, c: 3, d: 1}
    clock3 = %{a: 1, b: 2}
    assert Clock.dominates?(clock1, clock3)
    refute Clock.dominates?(clock3, clock1)
    refute Clock.dominates?(clock1, clock2)
    assert Clock.dominates?(clock1, clock1)
  end

  test "dominates_on_shared?" do
    # Equal clocks dominate each other on shared replicas.
    assert Clock.dominates_on_shared?(%{a: 1}, %{a: 1})

    # On shared replicas only, a clock with all-greater-or-equal values
    # dominates regardless of any missing replicas in either direction.
    assert Clock.dominates_on_shared?(%{a: 1, b: 2, c: 3}, %{b: 2, c: 3, d: 1})
    assert Clock.dominates_on_shared?(%{b: 2, c: 3, d: 1}, %{a: 1, b: 2, c: 3})

    # If a shared replica's value is strictly smaller, dominance fails.
    refute Clock.dominates_on_shared?(%{a: 1, b: 1}, %{a: 1, b: 2})

    # Replicas missing from c1 are ignored — not treated as zero.
    assert Clock.dominates_on_shared?(%{}, %{a: 5})
    assert Clock.dominates_on_shared?(%{a: 1}, %{b: 5})
  end

  test "append_clock trims clocks dominated on shared replicas" do
    clock1 = {:a, %{a: 1, b: 2, c: 3}}
    clock2 = {:b, %{b: 2, c: 3, d: 1}}
    clock3 = {:c, %{a: 1, b: 2}}

    # append_clock uses intersection-based dominance: replicas present in
    # one clock but missing from the other are ignored when comparing.
    # That is what allows the clockset to collapse here even though
    # clock1 lacks `d` and clock2/clock3 each lack other keys.

    # clock1's values match the upperbound of clock2 + clock3 on every
    # shared replica (a, b, c); the unshared `d` is ignored. clock1
    # dominates the combined and replaces the set.
    assert [clock1] == Clock.append_clock([clock2, clock3], clock1)

    # Same idea for the other replacements: the new clock's values match
    # the combined on shared replicas, so it replaces the set.
    assert [clock3] == Clock.append_clock([clock1, clock2], clock3)
    assert [clock1] == Clock.append_clock([clock1, clock2], clock1)
    assert [clock2] == Clock.append_clock([clock1, clock2], clock2)
    assert [clock2] == Clock.append_clock([clock1, clock3], clock2)
  end

  test "append_clock keeps incomparable clocks" do
    # When neither clock dominates the other on shared replicas, both are
    # retained.
    higher_a = {:x, %{a: 3, b: 1}}
    higher_b = {:y, %{a: 1, b: 3}}

    result = [higher_a] |> Clock.append_clock(higher_b) |> Enum.sort()
    assert result == Enum.sort([higher_a, higher_b])
  end

  test "upperbound" do
    assert Clock.upperbound(%{a: 1, b: 2, c: 2}, %{a: 3, b: 1, d: 2}) ==
      %{a: 3, b: 2, c: 2, d: 2}

    assert Clock.upperbound(%{}, %{a: 3, b: 1, d: 2}) == %{a: 3, b: 1, d: 2}
    assert Clock.upperbound(%{a: 3, b: 1, d: 2}, %{}) == %{a: 3, b: 1, d: 2}
  end

  test "lowerbound" do
    assert Clock.lowerbound(%{a: 1, b: 2, c: 2}, %{a: 3, b: 1, d: 2}) ==
      %{a: 1, b: 1, c: 2, d: 2}

    assert Clock.lowerbound(%{}, %{a: 3, b: 1, d: 2}) == %{a: 3, b: 1, d: 2}
    assert Clock.lowerbound(%{a: 3, b: 1, d: 2}, %{}) == %{a: 3, b: 1, d: 2}
  end

  test "filter replicas" do
    assert Clock.filter_replicas(%{a: 1, b: 2, c: 3}, [:a, :b]) == %{a: 1, b: 2}
    assert Clock.filter_replicas(%{a: 1, b: 2, c: 3}, [:a, :c]) == %{a: 1, c: 3}
    assert Clock.filter_replicas(%{a: 1, b: 2, c: 3}, [:a, :d]) == %{a: 1}
    assert Clock.filter_replicas(%{a: 1, b: 2, c: 3}, [:d]) == %{}
  end

  test "replicas" do
    assert Clock.replicas(%{}) == []
    assert Clock.replicas(%{a: 1}) == [:a]
    assert Clock.replicas(%{a: 1, b: 2}) == [:a, :b]
  end
end
