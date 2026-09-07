Code.require_file("support/test_identity.exs", __DIR__)
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(AnsibleAppview.Repo, :manual)
