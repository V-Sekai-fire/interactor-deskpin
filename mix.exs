defmodule Mix.Tasks.Compile.Deskpin do
  @moduledoc "Builds the `deskpin_nif` shared library with the C compiler on PATH."
  use Mix.Task

  @source "c_src/deskpin_nif.c"
  @target "priv/deskpin_nif.dll"

  @impl true
  def run(_args) do
    if stale?(), do: compile(), else: :noop
  end

  defp compile do
    cc =
      System.find_executable("gcc") || System.find_executable("cc") ||
        Mix.raise("deskpin: no C compiler (gcc or cc) on PATH")

    File.mkdir_p!("priv")
    args = ["-O2", "-Wall", "-shared", "-o", @target, @source, "-I#{erts_include()}", "-luser32"]

    case System.cmd(cc, args, stderr_to_stdout: true) do
      {_out, 0} ->
        Mix.shell().info("compiled #{@target}")
        :ok

      {out, code} ->
        Mix.raise("deskpin: #{Path.basename(cc)} exited #{code}\n#{out}")
    end
  end

  defp stale? do
    not File.exists?(@target) or
      Mix.Utils.last_modified(@source) > Mix.Utils.last_modified(@target)
  end

  defp erts_include do
    Path.join([to_string(:code.root_dir()), "erts-#{:erlang.system_info(:version)}", "include"])
  end
end

defmodule Deskpin.MixProject do
  use Mix.Project

  def project do
    [
      app: :deskpin,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      compilers: [:deskpin] ++ Mix.compilers(),
      aliases: [test: "test --no-start", icon: "run --no-start -e 'Deskpin.Icon.write!(\"priv\") |> Enum.each(&IO.puts/1)'"],
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :wx],
      mod: {Deskpin.Application, []}
    ]
  end

  defp deps, do: []
end
