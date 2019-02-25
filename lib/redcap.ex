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

    def migrate_data_odk_to_redcap(odk_data_path, data_guideline_path, event \\ nil) do
      data_guide_map = csv_mapper(data_guideline_path, :data_guideline)
      # mapped_data = csv_mapper(odk_data_path, :data)

      stream =
        odk_data_path
        |> File.stream!()
        |> CSV.decode!(headers: false)

      body = stream |> Enum.map(fn n -> n end) |> List.delete_at(0)

      headers =
        stream
        |> Enum.take(1)
        |> List.flatten()
        |> Enum.map(fn n ->
          if data_guide_map[:"#{n}"] do
            data_guide_map[:"#{n}"]
          else
            n
          end
        end)

        file = File.open!("importtool.csv", [:write, :utf8, :append])

        [headers] ++ body
        |> CSV.encode()
        |> Enum.each(&IO.write(file, &1))
    end

    defp csv_mapper(nil, atom), do: nil
    defp csv_mapper('', atom), do: nil
    defp csv_mapper(data_guideline_path, atom) do
      data_guideline_path
      |> File.stream!()
      |> CSV.decode!()
      |> Enum.reduce(%{}, &handle_mapping(&1, &2, atom))
    end
    # 'p1' stands for parameter 1, and so on
    defp handle_mapping(p1, p2, :data_guideline), do: map_guideline(p1, p2)
    # defp handle_mapping(p1, p2, :data), do: map_form_data(p1, p2)

    defp map_guideline([col1, col2, col3], acc) do
      [{:"#{col1}", col2}]
      |> Map.new()
      |> Map.merge(acc)
    end

    def map_form_data(cols, acc) do
      if acc == %{} do
        header_map = Enum.map(cols, fn col -> {:"#{col}", []})
        acc = Map.merge(header_map, acc)
      else
        Enum.map(cols)

      end
    end

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
