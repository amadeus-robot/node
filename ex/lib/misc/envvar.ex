defmodule Envvar do
  @moduledoc """
  Docs for `Envar`; Environment Variable checker/getter.
  Variable names are logged to improve developer experience.
  The _values_ of Environment Variables should _never_ be logged here.
  If an App needs to debug a variable, it can log it locally.
  """

  @doc """
  `get/2` gets an environment variable by name
  with an _optional_ second argument `default_value`
  which, as it's name suggests, defines the default value
  for the evironment variable if it is not set.
  ## Examples
      iex> System.put_env("HELLO", "world")
      iex> Envar.get("HELLO")
      "world"
      iex> Envar.get("FOO", "bar")
      "bar"
  """
  @spec get(binary, binary | nil) :: binary | nil
  def get(varname, default \\ nil) do
    System.get_env(varname, default)
  end

  @doc """
  `is_set/1` binary check that an environment variable is defined by name
  e.g: `Envar.is_set?("HEROKU")` will return `false`
  if the `HEROKU` environment variable is not set.
  When a particular variable is set, it will return `true`.
  ## Examples
      iex> Envar.is_set?("HEROKU")
      false
      iex> System.put_env("HELLO", "world")
      iex> Envar.is_set?("HELLO")
      true
  """
  @spec is_set?(binary) :: boolean
  def is_set?(varname) do
    case System.get_env(varname) do
      nil ->
        false

      _ ->
        true
    end
  end

  @doc """
  `is_set_all/1` binary check that ***ALL***
  environment variable in a `List` are defined.
  e.g: `Envar.is_set_all?(~w/HEROKU FLYIO/)` will return `false`
  if _both_ the `HEROKU` and `FLYIO` environment variables are _not_ set.
  When _all_ of the environment variables in the list are set,
  it will return `true`.
  It's the equivalent of writing:
  `Envar.is_set?("HEROKU") && Envar.is_set?("FLYIO")`.
  ## Examples
      iex> Envar.is_set_all?(["HEROKU", "AWS"])
      false
      iex> Envar.set("HELLO", "world")
      iex> Envar.set("GOODBYE", "au revoir")
      iex> Envar.is_set_all?(["HELLO",  "GOODBYE"])
      true
  """
  @spec is_set_all?(list) :: boolean
  def is_set_all?(list) do
    Enum.all?(list, fn var -> is_set?(var) end)
  end

  @doc """
  `is_set_any/1` binary check that any
  environment variable in a `List` is defined.
  e.g: `Envar.is_set_any?(["HEROKU", "FLYIO"])` will return `false`
  if _both_ the `HEROKU` and `FLYIO` environment variables are _not_ set.
  When any of the environment variables in the list are set,
  it will return `true`.
  It's the equivalent of writing:
  `Envar.is_set?("HEROKU") || Envar.is_set?("FLYIO")`.
  ## Examples
      iex> Envar.is_set_any?(["HEROKU", "AWS"])
      false
      iex> System.put_env("HELLO", "world")
      iex> Envar.is_set_any?(["HELLO",  "GOODBYE"])
      true
  """
  @spec is_set_any?(list) :: boolean
  def is_set_any?(list) do
    Enum.any?(list, fn var -> is_set?(var) end)
  end

  @doc """
  `set/2` set the `value` of an environment variable `varname`.
  Accepts two `String` parameters: `varname` and `value`.
  ## Examples
      iex> Envar.set("API_KEY", "YourSuperLongAPIKey")
      :ok
  """
  @spec set(binary, binary) :: :ok
  def set(varname, value) do
    System.put_env(varname, value)
  end

  @doc """
  `load/1` load a file containing a line-separated list
  of environment variables e.g: `.env`
  Set the `value` of each environment variable.
  ## Examples
      iex> Envar.load(".env")
      :ok
  """
  @spec load(binary) :: :ok
  def load(filename) do
    env = read(filename)
    Enum.each(env, fn {k, v} -> set(k, v) end)
    env
  end

  @doc """
  `require_env_file/1` load a file containing a line-separated list
  of environment variables e.g: `.env`
  Set the `value` of each environment variable.
  Log an Error if the file is not available
  ## Examples
      iex> Envar.require_env_file(".env")
      :ok
      iex> Envar.require_env_file(".env_not_there")
      :error
  """
  @spec require_env_file(binary) :: :ok | :error
  def require_env_file(filename) do
    # check if the file exists:
    {:ok, cwd} = File.cwd()
    path = Path.join(cwd, filename)

    if File.exists?(path) do
      load(filename)
    else
      :error
    end
  end


  @spec keys(binary) :: list
  def keys(filename) do
    read(filename) |> Map.keys()
  end

  @spec values(binary) :: list
  def values(filename) do
    read(filename) |> Map.values()
  end

  @doc """
  `read/1` reads a file containing a line-separated list
  of environment variables e.g: `.env`
  Returns a Map in the form %{ KEY: value, MYVAR: value2 }
  ## Examples
      iex> Envar.read(".env")
      %{
        "ADMIN_EMAIL" => "alex@gmail.com",
        "EVERYTHING" => "awesome!",
        "SECRET" => "master plan"
      }
  """
  @spec read(binary) :: map
  def read(path) do
    data = File.read!(path)

    data
    |> String.trim()
    |> String.split("\n")
    |> Enum.filter(& &1 != "")
    |> Enum.reduce(%{}, fn line, acc ->
      line = String.trim(line)

      with line <- String.replace(line, ["export ", "'"], ""),
           [key, value] <- :binary.split(line, "=") do
        if String.length(value) > 0 do
          Map.put(acc, key, value)
        else
          acc
        end
      end
    end)
  end
end
