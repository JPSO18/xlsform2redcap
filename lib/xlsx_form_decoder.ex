defmodule Redcap.XLSXFormDecoder do

    defstruct [:row_number, :content, :indexes]

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

    def parse(row, struct, choices_map, row_number) do
        struct = %{Enum.reduce(row, struct, fn field, acc -> merge_map_by_index(row, field, acc) end) | row_number: row_number}
        RedcapEncoder.build_struct_from_encoder(struct, choices_map, struct.content.type)
    end

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
