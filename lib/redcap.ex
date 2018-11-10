defmodule Redcap do
    alias Redcap.XLSXFormDecoder, as: XFD
    @moduledoc """
    Documentation for Redcap.
    """

    @doc """
    Hello world.

    ## Examples

    iex> Redcap.hello
        :world

    """

    def xlsx_to_redcap(path) when path |> is_binary(), do: do_parse(Xlsxir.multi_extract(path))

    defp do_parse({:ok, worksheet}) do
        {:ok, worksheet}
    end


    defp do_parse([{:ok, worksheet}, {:ok, worksheet_2}, {:ok, worksheet_3}]) do
        worksheet_1 = worksheet |> Xlsxir.get_list()
        worksheet_2 = worksheet_2 |> Xlsxir.get_list()
        [_form_name, [form_name, _file_name, _]] = worksheet_3 |> Xlsxir.get_list()
        form_name = form_name
                    |> String.downcase()
                    |> String.normalize(:nfd)
                    |> String.replace(~r/[^A-z\s]/u, "")
                    |> String.replace(" ", "_")

        struct_1 = worksheet_1 |> List.first() |> XFD.build_struct()

        file =  File.open!("datadic.csv", [:write, :utf8, :append])

        choices_map =
            worksheet_2
            |> List.delete(0)
            |> Enum.reduce(%{}, fn row, acc -> row |> XFD.parse_choices(acc) end)
            |> Map.put(:form_name, form_name)


        Enum.map_reduce(worksheet_1, 0, fn row, acc ->
            {XFD.parse(row, struct_1, choices_map, acc), acc + 1}
        end)
        |> elem(0)
        |> Enum.filter(fn n -> n != nil end)
        |> CSV.encode(headers: RedcapEncoder.list_csv_headers)
        |> Enum.each(&IO.write(file, &1))
    end

    defp do_parse({:error, reason}) do
        {:error, reason}
    end
end
