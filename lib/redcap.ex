defmodule Redcap do
    @moduledoc """
    Este é o módulo principal da Aplicação. Nele podemos verificar dois processos principais.
    O primeiro deles é a tradução dos formulários xls para o data dictionary do Redcap. Nesse
    primeiro processo o ponto de entrada é a função `Redcap.xlsx_to_redcap/1` com um path de arquivo xlsform,
    e que culmina na criação de um arquivo de data dictionary. O segundo processo é a migração de
    dados do formato xlsform para o data dictionary. Nesse processo temos dois pontos de entrada,
    o primeiro pela função `Redcap.migrate_data_in_folder/1` onde ela pega um path de uma pasta e
    traduz os arquivos daquela pasta para o template de importação do Redcap. O segundo ponto de
    entrada é a função `Redcap.migrate_data_odk_to_redcap/2` que pega um arquivo específico e traduz ele
    para o formato de entrada de dados do Redcap.
    """
    alias Redcap.XLSXFormDecoder, as: XFD

    @not_allowed_chars ["/", "-"]
    @first_column 0
    @second_column 1
    @event_field "redcap_event_name"
    @default_event "tratamento_tb_arm_1"
    @events_map %{
      "M0" => "triagem_arm_1",
      "M1" => "mes_1_arm_1",
      "M2" => "mes_2_arm_1",
      "END" => "visita_end_arm_1",
      "OFF" => "visita_off_arm_1",
      @event_field => @event_field
    }
    @doc """
    Esta função Recebe como argumento um path para um arquivo xlsform. É utilizada para traduzir
    formulários xls em formulários do Redcap. E isso é feito por meio de uma tradução linha a linha
    do xls para uma estrutura de data dictionary.

    Returns `:ok || {:ok, worksheet} || {:error, reason}`
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

    @doc """
    Esta função recebe como parâmetro um caminho para uma pasta, ou não recebe nenhum parâmetro e
    nesse caso pega o caminho `./priv/before_data` como parâmetro. Neste caminho a função pega todos
    os arquivos `.csv` e passa cada um desses arquivos para a função `Redcap.migrate_data_odk_to_redcap/2`
    junto com o nome do arquivo original com o prefixo `import_`.

    Returns `:ok`
    """
    def migrate_data_in_folder(folder_path \\ "./priv/before_data") do
      Path.wildcard(folder_path <> "/*.csv")
      |> Enum.each(fn data_path ->
        file_name = "priv/after_data/" <> (String.split(data_path, "/") |> List.last())
        migrate_data_odk_to_redcap(data_path, file_name)
      end)
    end

    @doc """
    Esta função recebe dois argumentos o caminho para o arquivos dos dados, e o nome que vai ser
    dado ao arquivo que foi gerado pela função. Outro ponto importante é que essa função utiliza um
    outro arquivo que o path tem que estar no arquivo `config/config.exs` na chave de `:data_guide_path`.
    Esse arquivo é utilizado para mapear qual coluna de dados do Redcap corresponde qual coluna
    do arquivo de dados originais.

    Na função os dois arquivos citados anteriormente são lidos e transformados em `Map` (estrutura
    de dados de fácil acesso) o data_guide, e o arquivo de dados é transformado em uma `List` de
    listas, onde cada item da lista principal é uma linha de dado.Depois disso é feito uma
    substituição dos headers da lista pelos seur correspondentes no data_guide.

    Antes de escrever o arquivo algumas funções auxiliares são chamadas pela função `Redcap.check_redcap_requirements/1`
    para avaliar a estrutura de dados geradas e fazer as últimas lapidações para que esses dados
    entrem no Redcap sem problemas. Após essa checagem os dados são tranformados em um csv pronto
    para ser importado no Redcap.

    Returns `:ok`
    """
    def migrate_data_odk_to_redcap(odk_data_path, file_name) do
      data_guide_map =
        Application.get_env(:redcap, :data_guide_path)
        |> csv_mapper(:data_guideline)

      stream =
        odk_data_path
        |> File.stream!()
        |> CSV.decode!(headers: false)

      {headers, nil_indexes} = build_header(stream, data_guide_map)
      body = build_body(stream, nil_indexes)

      file = file_name |> File.open!([:write, :utf8, :append])

      headers
      |> unify_header_and_body(body)
      |> check_redcap_requirements()
      |> CSV.encode()
      |> Enum.each(&IO.write(file, &1))
    end

    defp unify_header_and_body(headers, body) do
      [headers] ++ body
      |> Enum.map(fn row ->
        Enum.reject(row, fn field -> field == "nil" end)
      end)
    end

    defp check_redcap_requirements(records) do
      records
      |> put_identifier_in_first_column()
      |> erase_rows_without_identifier()
      |> check_redcap_event()
    end

    defp put_identifier_in_first_column(records) do
      identifier_index =
        records
        |> List.first()
        |> Enum.find_index(fn field -> field == Application.get_env(:redcap, :record_identifier) end)

      Enum.map(records, &change_element_index_in_list(&1, identifier_index, @first_column))
    end

    defp change_element_index_in_list(list, nil, _intended_index), do: list
    defp change_element_index_in_list(list, present_index, intended_index) do
      list
      |> List.delete_at(present_index)
      |> List.insert_at(intended_index, list |> Enum.at(present_index, :error))
    end

    defp erase_rows_without_identifier(records) do
      records
      |> Enum.reject(fn record_row ->
        record_row |> List.first() == nil or record_row |> List.first() == ""
      end)
    end

    defp check_redcap_event([]), do: []
    defp check_redcap_event(records) do
      records
      |> List.first()
      |> Enum.find_index(&(@event_field == &1))
      |> handle_redcap_events(records)
    end

    defp handle_redcap_events(nil, [header | body]) do
      header = header |> List.insert_at(@second_column, @event_field)

      body =
        body
        |> Enum.map(&List.insert_at(&1, @second_column, @default_event))

      [header] ++ body
    end

    defp handle_redcap_events(event_index, records) do
      records
      |> Enum.map(fn row -> List.update_at(row, event_index, &Map.get(@events_map, &1)) end)
    end

    defp build_header(stream, data_guide_map) do
      stream
      |> Enum.take(1)
      # why line below? stream |> -> [[header]] -> List.flatten(stream) -> [header]
      |> List.flatten()
      |> Enum.map(fn n -> header_exchange(data_guide_map[:"#{n}"]) end)
      |> get_nil_indexes()
    end

    defp get_nil_indexes(row) do
      {_last_index, nil_indexes} =
        Enum.reduce(row, {0, []}, fn row_field, {index, nil_indexes} ->
          nil_indexes =
            if row_field == "nil" do
              List.insert_at(nil_indexes, -1, index)
            else
              nil_indexes
            end
          {index + 1, nil_indexes}
        end)
      {row, nil_indexes}
    end

    defp header_exchange(""), do: "nil"
    defp header_exchange(nil), do: "nil"
    defp header_exchange(header), do: header

    defp build_body(stream, nil_indexes) do
      stream
      |> Enum.map(fn n -> n |> normalize() end)
      |> List.delete_at(0)
      |> Enum.reduce([], fn row, acc ->
        List.insert_at(acc, -1, nilify_elements_in_list(row, nil_indexes))
      end)
    end

    defp nilify_elements_in_list(list, indexes_to_be_nilled) do
      Enum.reduce(indexes_to_be_nilled, list, fn index, acc ->
        List.replace_at(acc, index, "nil")
      end)
    end

    defp normalize(column) when column |> is_list() do
      Enum.map(column, fn field ->
        field
        |> check_form()
      end)
    end

    defp check_form(field) when field |> is_binary() do
      case field do
        "True" -> 1
        "False" -> 0
        "n/a" -> nil
        any -> any |> check_for_not_allowed_char()
      end
    end

    defp check_for_not_allowed_char(value) do
      if value |> is_date?() do
        value
      else
        value
        |> String.normalize(:nfd)
        |> String.replace(~r/[^A-z\s0-9.]/u, "")
        |> String.replace(@not_allowed_chars, "_")
      end
    end

    def is_date?(date) do
      case Date.from_iso8601(date) do
        {:ok, _} -> true
        _ -> false
      end
    end

    defp csv_mapper(nil, _atom), do: nil
    defp csv_mapper('', _atom), do: nil
    defp csv_mapper(data_guide_path, atom) do
      data_guide_path
      |> File.stream!()
      |> CSV.decode!()
      |> Enum.reduce(%{}, &handle_mapping(&1, &2, atom))
    end
    # 'p1' stands for parameter 1, and so on
    defp handle_mapping(p1, p2, :data_guideline), do: map_guideline(p1, p2)
    defp handle_mapping(p1, p2, :data), do: map_form_data(p1, p2)

    # defp map_guideline([c1, c2, c3 | rest], acc), do: map_guideline([c1, c2, c3], acc)
    defp map_guideline([col1, col2, _col3 | _rest], acc) do
      [{:"#{col1}", col2}]
      |> Map.new()
      |> Map.merge(acc)
    end

    def map_form_data(cols, acc) do
      if acc == %{} do
        Enum.reduce(cols, {0, %{}}, fn(col, {counter, map}) ->
          map_1 =
              map
              |> Map.put(:"#{col}", [])
              |> Map.update(:position_key, Map.new([{:"#{counter}", col}]), &Map.put(&1, :"#{counter}", col))
          counter = counter + 1
          {counter, map_1}
        end)
        |> elem(1)
      else
        length_cols = Enum.count(cols) - 1
        new_map =
          Enum.map(0..length_cols, fn n ->
            atom = :"#{acc.position_key[:"#{n}"]}"
            {atom, acc[atom] ++ [Enum.at(cols, n)]}
          end)
          |> Map.new()

        Map.merge(acc, new_map)
      end
    end
end
