# The database-name suffix for this git worktree, so two parallel sessions never
# share a database. Empty in the main checkout.
#
# Evaluated rather than imported: `import_config` merges configuration and
# cannot hand a value to `config/dev.exs` and `config/test.exs`, and a config
# file cannot call a project module because it runs before compilation.
case System.cmd("git", ["rev-parse", "--absolute-git-dir"], stderr_to_stdout: true) do
  {dir, 0} ->
    dir = String.trim(dir)

    if Path.basename(Path.dirname(dir)) == "worktrees",
      do: "_" <> String.replace(Path.basename(dir), ~r/\D/, ""),
      else: ""

  _ ->
    ""
end
