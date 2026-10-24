defmodule HeexSvelte.SyncTest do
  # Fails when a component marked @svelte and its .svelte file have drifted
  # apart, the same check as `mix app.svelte --check`
  use ExUnit.Case, async: true

  test "every @svelte component's file is up to date" do
    {components, problems} = HeexSvelte.components(:app)
    problems = problems ++ HeexSvelte.check(components) ++ HeexSvelte.orphans(components)

    assert problems == [], Enum.map_join(problems, "\n", &HeexSvelte.describe/1)
  end
end
