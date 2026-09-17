defmodule Phoenix.PubSub.UnitTest do
  use ExUnit.Case, async: true

  describe "child_spec/1" do
    test "expects a name" do
      {:error, {{:EXIT, {exception, _}}, _}} = start_supervised({Phoenix.PubSub, []})

      assert Exception.message(exception) ==
               "the :name option is required when starting Phoenix.PubSub"
    end

    test "pool_size can't be smaller than broadcast_pool_size" do
      opts = [name: name(), pool_size: 1, broadcast_pool_size: 2]

      {:error, {{:shutdown, {:failed_to_start_child, Phoenix.PubSub.PG2, message}}, _}} =
        start_supervised({Phoenix.PubSub, opts})

      assert ^message = "the :pool_size option must be greater than or equal to the :broadcast_pool_size option"
    end

    defp name do
      :"#{__MODULE__}_#{:crypto.strong_rand_bytes(8) |> Base.encode16()}"
    end
  end

  describe "group_by" do
    test "defaults to :pid, delivering one message per subscription" do
      name = :"ps_default_group_#{:erlang.unique_integer([:positive])}"
      start_supervised!({Phoenix.PubSub, name: name})

      assert :ok = Phoenix.PubSub.subscribe(name, "topic")
      assert :ok = Phoenix.PubSub.subscribe(name, "topic")

      Phoenix.PubSub.broadcast(name, "topic", :hello)

      assert_receive :hello
      assert_receive :hello
    end

    test ":pid delivers one message per subscription" do
      name = :"ps_pid_#{:erlang.unique_integer([:positive])}"
      start_supervised!({Phoenix.PubSub, name: name, group_by: :pid})

      assert :ok = Phoenix.PubSub.subscribe(name, "topic")
      assert :ok = Phoenix.PubSub.subscribe(name, "topic")

      Phoenix.PubSub.broadcast(name, "topic", :hello)

      assert_receive :hello
      assert_receive :hello
    end

    test "raises ArgumentError on an invalid value" do
      name = :"ps_bad_#{:erlang.unique_integer([:positive])}"

      {:error, {{%ArgumentError{} = exception, _stacktrace}, _child_info}} =
        start_supervised({Phoenix.PubSub, name: name, group_by: :bogus})

      assert Exception.message(exception) =~ "invalid :group_by option"
      assert Exception.message(exception) =~ ":bogus"
    end

    test ":key delivers one message per subscription" do
      name = :"ps_key_#{:erlang.unique_integer([:positive])}"
      start_supervised!({Phoenix.PubSub, name: name, group_by: :key})

      assert :ok = Phoenix.PubSub.subscribe(name, "topic")
      assert :ok = Phoenix.PubSub.subscribe(name, "topic")

      Phoenix.PubSub.broadcast(name, "topic", :hello)

      assert_receive :hello
      assert_receive :hello
    end
  end
end
