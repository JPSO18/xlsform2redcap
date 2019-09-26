defmodule RedcapEncoder do
    @moduledoc """
    Neste módulo é onde acontece a codificação dos valores extraidos de um arquivo xlsform para a
    linguagem implementada pelo Redcap em seu data dictionary.
    """

    @initial_dolar_brace ~r/\${/
    @final_brace ~r/}/
    @not_selected_regex ~r/not selected(.+,.+)/
    @selected_regex ~r/selected\((.+), ?(.+)\)/
    @pow_regex ~r/pow\((.+?), ?(.+?)\)/

    @csv_header [:"Variable / Field Name", :"Form Name", :"Section Header", :"Field Type",
               :"Field Label", :"Choices, Calculations, OR Slider Labels", :"Field Note",
               :"Text Validation, Type OR Show Slider Number", :"Text Validation Min",
               :"Text Validation Max", :"Identifier?", :"Branching Logic (Show field only if...)",
               :"Required Field?", :"Custom Alignment", :"Question Number (surveys only)",
               :"Matrix Group Name", :"Matrix Ranking?", :"Field Annotation"]
    @doc """
    Cria uma estrutura para o cabeçalho utilizado no data dictionary

    Retorns `%RedcapEncoder{ campos }`
    """
    defstruct @csv_header

    @doc """
    Retorna lista de campos do data dictionary

    Returns `List`
    """
    def list_csv_headers, do: @csv_header

    @doc """
    Nesta função é onde linha a linha do xlsform é traduzida para cada tipo de campo do Redcap, ou
    o mais próximo disso dentro do universo do Redcap. Cada uma das funções cuida de um 'type'
    específico do xlsform fazendo os tratamentos necessários para a tradução desse 'type' para um
    'FieldType' do Redcap.

    Returns `%RedcapEncoder{ campos }`
    """
    def build_struct_from_encoder(%{content: content}, choices, "note") do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "descriptive",
                    "Field Label": content.label |> translate_get_fields(), "Form Name": choices[:form_name],
                    "Branching Logic (Show field only if...)": content.relevant |> translate_get_fields() |> translate_relevant()}
    end

    def build_struct_from_encoder(%{content: content}, choices, "image") do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "file",
        "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
        "Required Field?": content.required |> required_field(),
        "Branching Logic (Show field only if...)": content.relevant |> translate_get_fields() |> translate_relevant()}
    end

    def build_struct_from_encoder(%{content: content}, choices, "text") do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": content.type,
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Required Field?": content.required |> required_field(),
                    "Branching Logic (Show field only if...)": content.relevant |> translate_get_fields() |> translate_relevant()}
    end

    def build_struct_from_encoder(%{content: content}, choices, "integer") do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "text",
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Text Validation, Type OR Show Slider Number": "integer",
                    "Required Field?": content.required |> required_field,
                    "Branching Logic (Show field only if...)": content.relevant |> translate_get_fields() |> translate_relevant()}
    end

    def build_struct_from_encoder(%{content: content}, choices, "decimal") do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "text",
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Text Validation, Type OR Show Slider Number": "number",
                    "Required Field?": content.required |> required_field,
                    "Branching Logic (Show field only if...)": content.relevant |> translate_get_fields() |> translate_relevant()}
    end

    def build_struct_from_encoder(%{content: content}, choices, "date") do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "text",
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Text Validation, Type OR Show Slider Number": "date_dmy",
                    "Required Field?": content.required |> required_field,
                    "Branching Logic (Show field only if...)": content.relevant |> translate_get_fields() |> translate_relevant()}
    end

    def build_struct_from_encoder(%{content: content}, choices, "select_" <> choice),
        do: build_struct_from_select(content, choices, choice |> String.trim_leading("_"))
    def build_struct_from_encoder(%{content: content}, choices, "select " <> choice),
        do: build_struct_from_select(content, choices, choice |> String.trim_leading())

    def build_struct_from_encoder(%{content: content}, choices, "calculate") do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "calc",
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Choices, Calculations, OR Slider Labels": content.calculation |> translate_get_fields() |> translate_calc(),
                    "Required Field?": content.required |> required_field,
                    "Branching Logic (Show field only if...)": content.relevant |> translate_get_fields() |> translate_relevant()}
    end

    def build_struct_from_encoder(_, _, _struct) do
        nil
    end

    defp build_struct_from_select(content, choices, "one" <> choice) do
        choice = choice |> String.trim_leading()
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "dropdown",
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Choices, Calculations, OR Slider Labels": choices[:"#{choice}"],
                    "Required Field?": content.required |> required_field,
                    "Branching Logic (Show field only if...)": content.relevant |> translate_get_fields() |> translate_relevant()}
    end

    defp build_struct_from_select(content, choices, "multiple" <> choice) do
        choice = choice |> String.trim_leading()
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "checkbox",
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Choices, Calculations, OR Slider Labels": choices[:"#{choice}"],
                    "Required Field?": content.required |> required_field,
                    "Branching Logic (Show field only if...)": content.relevant |> translate_get_fields() |> translate_relevant()}
    end

    defp translate_get_fields(nil), do: nil
    defp translate_get_fields(string) when is_binary(string) do
        rel_mod = Regex.replace(@initial_dolar_brace, string, "[")
        Regex.replace(@final_brace, rel_mod, "]")
        # |> change_simple_quote()
    end

    defp translate_relevant(nil), do: nil
    defp translate_relevant(relevant) do
        relevant
        |> relevant_chooser(@not_selected_regex)
        |> relevant_chooser(@selected_regex)
    end

    defp relevant_chooser(relevant, regex) do
        Regex.replace(regex, relevant, fn _n, field_name, choice ->
            String.replace(field_name, "]", "(#{choice})]=1")
        end)
    end

    defp translate_calc(calc) do
        calc
        |> String.replace("div", "/")
        |> calc_regex()
    end

    defp calc_regex(calc) do
        Regex.replace(@pow_regex, calc,
            fn _, number, pow ->
                number <> "^" <> pow
            end)
    end

    defp change_simple_quote(string) do
        string |> String.replace("'", "\"")
    end

    defp required_field("yes"), do: "Y"
    defp required_field("Yes"), do: "Y"
    defp required_field("YES"), do: "Y"
    defp required_field(_), do: nil
end
