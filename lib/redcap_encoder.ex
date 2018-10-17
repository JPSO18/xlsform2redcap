defmodule RedcapEncoder do

    @relevant_regex

    @csv_header [:"Variable / Field Name", :"Form Name", :"Section Header", :"Field Type",
               :"Field Label", :"Choices, Calculations, OR Slider Labels", :"Field Note",
               :"Text Validation, Type OR Show Slider Number", :"Text Validation Min",
               :"Text Validation Max", :"Identifier?", :"Branching Logic (Show field only if...)",
               :"Required Field?", :"Custom Alignment", :"Question Number (surveys only)",
               :"Matrix Group Name", :"Matrix Ranking?", :"Field Annotation"]

    defstruct @csv_header

    def list_csv_headers, do: @csv_header

    def build_struct_from_encoder(%{content: content}, choices, "text") do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": content.type,
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Required Field?": content.required, "Branching Logic (Show field only if...)": content.relevant |> tranlate_relevant()}
    end

    def build_struct_from_encoder(%{content: content}, choices, "integer") do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "text",
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Text Validation, Type OR Show Slider Number": "integer",
                    "Required Field?": content.required |> required_field}
    end

    def build_struct_from_encoder(%{content: content}, choices, "decimal") do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "text",
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Text Validation, Type OR Show Slider Number": "number",
                    "Required Field?": content.required |> required_field}
    end

    def build_struct_from_encoder(%{content: content}, choices, "date") do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "text",
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Text Validation, Type OR Show Slider Number": "date_dmy",
                    "Required Field?": content.required |> required_field}
    end

    def build_struct_from_encoder(%{content: content}, choices, "select_one " <> choice) do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "dropdown",
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Choices, Calculations, OR Slider Labels": choices[:"#{choice}"],
                    "Required Field?": content.required |> required_field}
    end

    def build_struct_from_encoder(%{content: content}, choices, "select_multiple " <> choice) do
        %__MODULE__{"Variable / Field Name": content.name, "Field Type": "checkbox",
                    "Field Label": content.label, "Form Name": choices[:form_name], "Field Note": content.hint,
                    "Choices, Calculations, OR Slider Labels": choices[:"#{choice}"],
                    "Required Field?": content.required |> required_field}
    end

    def build_struct_from_encoder(_, _, _struct) do
        nil
    end

    defp tranlate_relevant(relevant) when is_binary(relevant) do
    end

    defp required_field("yes"), do: "Y"
    defp required_field("Yes"), do: "Y"
    defp required_field("YES"), do: "Y"
    defp required_field(_), do: nil

end
