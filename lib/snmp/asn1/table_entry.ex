defmodule Snmp.ASN1.TableEntry do
  @moduledoc """
  Use this module to build table entries creators
  """
  defmacro __using__({table_name, infos}) do
    %{indices: _indices, columns: columns, infos: infos} = infos

    quote bind_quoted: [
            table_name: table_name,
            columns: Macro.escape(columns),
            infos: Macro.escape(infos)
          ] do
      require Record
      alias Snmp.ASN1.Types

      defvals = elem(infos, 2)

      # By convention (?) SNMP tables' index is first field
      # Do not set default value for index column
      [{index, _} | attributes] =
        columns
        |> Enum.map(
          &{elem(&1, 3), Keyword.get_lazy(defvals, elem(&1, 3), fn -> Types.default(&1) end)}
        )

      Record.defrecord(:entry, table_name, [{index, nil} | attributes])

      @doc """
      Returns new record
      """
      def new, do: entry()

      @doc """
           Cast parameters into #{table_name} type

           # Parameters

           """ <> Enum.join(Enum.map(attributes, &"* `#{elem(&1, 0)}`"), "\n")
      def cast(entry \\ new(), params) do
        Enum.reduce(params, entry, &__cast_param__/2)
      end

      for {:me, _oid, _entrytype, col_name, _asn1_type, _access, _mfa, _imported, _assoc_list,
           _description, _units} = me <- columns do
        defp __cast_param__({unquote(col_name), nil}, acc), do: acc

        defp __cast_param__({unquote(col_name), value}, acc) do
          entry(acc, [{unquote(col_name), Types.cast(value, unquote(Macro.escape(me)))}])
        end
      end
    end
  end
end