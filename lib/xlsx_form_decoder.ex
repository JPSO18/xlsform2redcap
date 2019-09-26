defmodule Redcap.XLSXFormDecoder do
    @moduledoc """
    Este módulo faz a construção de uma estrutura a partir de um formulário xls, que tem três chaves
    `:row_number`, `:content`, `:indexes`, que são respectivamente o numero da linha, o conteúdo da
    linha, e um mapa onde tem o index como chave e o valor é a coluna desse index.
    """

    @not_allowed_chars ["/", "-"]

    @doc """
    Constrói a estrutura que vai guardar as linhas do xlsform

    Returns `%Redcap.XLSXFormDecoder{row_number: Interger.t, content: List, indexes: Map}`
    """
    defstruct [:row_number, :content, :indexes]

    @doc """
    Recebe a primeira linha do arquivo de xlsform e transforma na estrutura de dados

    Returns `%Redcap.XLSXFormDecoder{row_number: Interger.t, content: List, indexes: Map}`
    """
    def build_struct(row) do
        struct(__MODULE__,
            row_number: 0,
            content: map_columns(row),
            indexes: map_indexes(row))
    end

    defp map_columns(row) do
        Enum.map(row, fn column ->
            {:"#{column}", nil}
        end)
        |> Enum.into(%{})
    end

    defp map_indexes(row) do
        {map, acc} = Enum.map_reduce(row, 0, fn column, acc -> {{:"#{acc}", column}, acc + 1} end)
        map
        |> Enum.into(%{})
    end

    def parse([nil | _tail], _row, _columns, _row_number) do
        nil
    end

    @doc """
    Recebe a linha, a Estrutura da linha, um mapa de escolhas referente a linha(se existir) e o
    número da linha no arquivo. Com isso a função constrói uma estrutura com a linha passada onde
    cada chave é a coluna referente ao index que o campo tá na `List` e passa essa estrutura para
    ser traduzida para uma linha do Redcap pela função `RedcapEncoder.build_struct_from_encoder/3`

    Returns `%RedcapEncoder{ campos }`
    """
    def parse(row, struct, choices_map, row_number) do
        struct = %{Enum.reduce(row, struct, fn field, acc -> merge_map_by_index(row, field, acc) end) | row_number: row_number}
        RedcapEncoder.build_struct_from_encoder(struct, choices_map, struct.content.type)
    end

    @doc """
    Recebe uma `List` de escolhas gerada a partir da leitura do arquivo de xlsform da aba choices.
    Apartir dessa `List` é criado um `Map` onde a chave é o name da choice, e o valor é uma `String`
    que segue o padrão `choice_value, choice_label|` para cada uma das escolhas definidas no arquivo
    original

    Returns `%{choice_name: "choice_value_1, choice_label_1 | choice_value_2, choice_label_2"}`
    """
    def parse_choices([nil | _tail], map), do: map
    def parse_choices([_, nil | _tail], map), do: map
    def parse_choices([_, _, nil | _tail], map), do: map
    def parse_choices([choice_name, value, label], map) do
        Map.get_and_update(map, :"#{choice_name}", fn current_value ->
            case current_value do
                nil ->
                    new_value = concat_choices("", value, label)
                    {current_value, new_value}
                string ->
                    new_value = string |> concat_choices(value, label)
                    {current_value, new_value}
            end
        end)
        |> elem(1)

    end
    def parse_choices([choice_name, value, label | _tail], map), do: parse_choices([choice_name, value, label], map)

    defp concat_choices(string, value, label) do
        value =
            if is_binary(value) do
                value
                |> String.normalize(:nfd)
                |> String.replace(~r/[^A-z\s0-9]/u, "")
                |> String.replace(@not_allowed_chars, "_")
            else
                value
            end

        string <> "#{value}" <> ", " <> "#{label}" <> "|"
    end

    defp merge_map_by_index(row, field, struct) do
        if field != nil do
            column = Map.get(struct, :indexes)[:"#{Enum.find_index(row, fn n -> n == field end)}"]
            Map.update!(struct, :content, &Map.update!(&1, :"#{column}", fn _ -> field end))
        else
            struct
        end
    end
end
