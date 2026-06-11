defmodule ExRatatui.SubscriptionTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Subscription

  doctest ExRatatui.Subscription

  test "constructors and normalize support every subscription shape" do
    interval = Subscription.interval(:heartbeat, 10, :tick)
    once = Subscription.once(:boot, 5, :fire_once)

    assert Subscription.none() == []
    assert once == %Subscription{id: :boot, kind: :once, interval_ms: 5, message: :fire_once}
    assert Subscription.normalize(nil) == []
    assert Subscription.normalize([]) == []
    assert Subscription.normalize(once) == [once]
    assert Subscription.normalize([interval, once]) == [interval, once]
  end

  test "normalize raises on unsupported subscription terms" do
    assert_raise ArgumentError, "unsupported ExRatatui subscription: :bad", fn ->
      Subscription.normalize(:bad)
    end
  end
end
