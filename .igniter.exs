# Configuration for igniter, the library behind the code generators in
# priv/code_generators. See `mix help igniter.setup` and
# https://hexdocs.pm/igniter/Igniter.Project.IgniterConfig.html
[
  module_location: :outside_matching_folder,
  extensions: [],
  deps_location: :last_list_literal,
  source_folders: ["lib", "test/support"],
  # Igniter moves a module to the folder that matches its name, so
  # `MyAppWeb.DashboardLive` would end up in lib/my_app_web/. Phoenix keeps
  # LiveViews and their tests in a live/ folder, so those stay where the
  # generator put them.
  dont_move_files: [~r"lib/mix", ~r"/live/", ~r"priv/code_generators"],
  module_names: []
]
