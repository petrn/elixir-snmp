defmodule Snmp.Instrumentation do
  @moduledoc """
  Describes behaviour for module implementing MIB instrumentation functions
  """
  require Record

  Record.defrecord(:me, Record.extract(:me, from_lib: "snmp/include/snmp_types.hrl"))

  @type row_index :: [integer()]
  @type col() :: integer()
  @type oid() :: [integer()]
  @type varname :: atom()

  @type gen_err :: :genErr
  @type get_err :: {:noValue, :noSuchObject | :noSuchInstance}
  @type get_ret :: {:value, term()} | get_err()
  @type is_set_ok_err ::
          :noAccess | :noCreation | :inconsistentValue | :resourceUnavailable | :inconsistentName
  @type is_set_ok_ret :: :noError | is_set_ok_err()
  @type undo_err :: :undoFailed
  @type set_err :: :commitFailed | :undoFailed

  @callback init(any()) :: any()

  @callback new(varname(), any()) :: :ok

  @callback delete(varname(), any()) :: :ok

  @callback new_table(varname(), any()) :: :ok

  @callback delete_table(varname(), any()) :: :ok

  @callback get(varname(), any()) :: get_ret() | gen_err()

  @callback get(varname(), row_index(), [col()], any()) :: [get_ret()] | get_err() | gen_err()

  @callback get_next(varname(), row_index(), [col()], any()) ::
              [{oid(), term()} | :endOfTable] | {:genErr, integer()}

  @callback is_set_ok(varname(), term(), any()) :: is_set_ok_ret() | gen_err()

  @callback is_set_ok(varname(), row_index(), [{col(), term()}], any()) ::
              {:noError, 0} | {is_set_ok_err(), col()}

  @callback undo(varname(), term(), any()) :: :noError | undo_err() | gen_err()

  @callback undo(varname(), row_index(), [{col(), term()}], any()) ::
              {:noError, 0} | {undo_err(), col()}

  @callback set(varname(), term(), any()) :: :noError | set_err() | gen_err()

  @callback set(varname(), row_index(), [{col(), term()}], any()) ::
              {:noError, 0} | {set_err(), col()}

  @optional_callbacks new: 2,
                      delete: 2,
                      new_table: 2,
                      delete_table: 2,
                      is_set_ok: 3,
                      is_set_ok: 4,
                      undo: 3,
                      undo: 4

  defmacro __using__(_opts) do
    quote do
      @behaviour Snmp.Instrumentation

      @doc false
      def init(s), do: s

      defoverridable init: 1
    end
  end

  defmacro __before_compile__(env) do
    variables = env.module |> Module.get_attribute(:variable)
    tables = env.module |> Module.get_attribute(:table)

    env.module
    |> Module.get_attribute(:instrumentation)
    |> gen_instrumentation(variables, tables, env)
  end

  @doc false
  def __after_compile__(env, _bytecode) do
    missing_varfuns =
      env.module
      |> apply(:__mib__, [:varfuns])
      |> Enum.reject(&Module.defines?(env.module, &1, :def))

    missing_tablefuns =
      env.module
      |> apply(:__mib__, [:tablefuns])
      |> Enum.reject(&Module.defines?(env.module, &1, :def))

    case missing_varfuns ++ missing_tablefuns do
      [] ->
        :ok

      missing ->
        mib_name = apply(env.module, :__mib__, [:name])

        err =
          """
          Following instrumentation functions are missing for module #{env.module} (mib #{mib_name}):
          """ <> (missing |> Enum.map(&"\t* #{elem(&1, 0)}: #{elem(&1, 1)}") |> Enum.join("\n"))

        Mix.shell().error(err)
        Mix.raise "Error compiling #{env.module}"
    end
  end

  defp gen_instrumentation(_instr, [], [], _env), do: []

  defp gen_instrumentation({mod, opts}, varfuns, tablefuns, env) do
    if mod == env.module do
      [gen_impl()]
    else
      [gen_instrumentation_init(mod, opts)] ++
        Enum.map(varfuns, &gen_varfun/1) ++
        Enum.map(tablefuns, &gen_tablefun/1)
    end
  end

  defp gen_impl() do
    quote do
      @after_compile Snmp.Instrumentation
    end
  end

  defp gen_instrumentation_init(mod, opts) do
    quote do
      require unquote(mod)
      @instr_mod unquote(mod)
      @instr_opts apply(unquote(mod), :init, [unquote(opts)])
    end
  end

  defp gen_varfun(me(aliasname: varname)) do
    quote do
      def unquote(varname)(op) when op in [:new, :delete, :get],
        do: apply(@instr_mod, op, [unquote(varname), @instr_opts])

      def unquote(varname)(op, val) when op in [:is_set_ok, :undo, :set],
        do: apply(@instr_mod, op, [unquote(varname), val, @instr_opts])
    end
  end

  defp gen_tablefun(me(aliasname: varname)) do
    quote do
      def unquote(varname)(:new),
        do: apply(@instr_mod, :new_table, [unquote(varname), @instr_opts])

      def unquote(varname)(:delete),
        do: apply(@instr_mod, :delete_table, [unquote(varname), @instr_opts])

      def unquote(varname)(:get),
        do: apply(@instr_mod, :get, [unquote(varname), @instr_opts])

      def unquote(varname)(op, row_index, cols)
          when op in [:get, :get_next, :is_set_ok, :undo, :set],
          do: apply(@instr_mod, op, [unquote(varname), row_index, cols, @instr_opts])
    end
  end
end
