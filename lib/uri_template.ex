defmodule UriTemplate do
  @moduledoc """

    [RFC 6570](https://tools.ietf.org/html/rfc6570) compliant URI template
    processor. Currently supports level 3 completely and parts of level 4.
  """
  alias UriTemplate.VarSpec, as: VarSpec

  @doc """
    Expand a RFC 6570 compliant URI template in to a full URI.

    ## Examples

        iex> UriTemplate.expand("http://example.com/{id}", id: 42)
        "http://example.com/42"

        iex> UriTemplate.expand("http://example.com?q={terms}", terms: ["fiz", "buzz"])
        "http://example.com?q=fiz,buzz"

        iex> UriTemplate.expand("http://example.com?{k}", k: [one: 1, two: 2])
        "http://example.com?one,1,two,2"

        iex> UriTemplate.expand("http://example.com/test", id: 42)
        "http://example.com/test"

        iex> UriTemplate.expand("http://example.com/{lat,lng}", lat: 40, lng: -105)
        "http://example.com/40,-105"

        iex> UriTemplate.expand("http://example.com/{;lat,lng}", lat: 40, lng: -105)
        "http://example.com/;lat=40;lng=-105"

        iex> UriTemplate.expand("http://example.com/{?lat,lng}", lat: 40, lng: -105)
        "http://example.com/?lat=40&lng=-105"

        iex> UriTemplate.expand("http://example.com/?test{&lat,lng}", lat: 40, lng: -105)
        "http://example.com/?test&lat=40&lng=-105"

        iex> UriTemplate.expand("http://example.com{/lat,lng}", lat: 40, lng: -105)
        "http://example.com/40/-105"

        iex> UriTemplate.expand("http://example.com/test{.fmt}", fmt: "json")
        "http://example.com/test.json"

        iex> UriTemplate.expand("http://example.com{#lat,lng}", lat: 40, lng: -105)
        "http://example.com#40,-105"

  """
  def expand(tmpl, vars) do
    Regex.scan(~r/([^{]*)(?:{([^}]+)})?/, tmpl, capture: :all_but_first)
    |> Enum.flat_map(&expand_part(vars, &1))
    |> Enum.join
  end

  defp expand_part(vars, [prefix, expr]) do
    [prefix, expand_expression(expr, vars)]
  end

  defp expand_part(_, [prefix]) do
    [prefix]
  end

  defp expand_expression(expression, vars) do
    {op, leaders, varspecs} = parse_expression(expression)

    varspecs
    |> Enum.map(&expand_varspec(&1, vars, op))
    |> Stream.zip(leaders)
    |> Enum.flat_map(fn {expanded_varspec, leader} -> [leader, expanded_varspec] end)
    |> Enum.join
  end

  defp expand_varspec(varspec, vars, op) do
    cond do
      name_value_pair_op?(op) -> expand_nvp_varspec(varspec, vars, op == ";")
      op in ["+", "#"]        -> raw_expand_varspec(varspec, vars)
      true                    -> expand_basic_varspec(varspec, vars)
    end
  end

  defp expand_nvp_varspec(varspec, vars, skip_eq_if_blank) do
    val = expand_basic_varspec(varspec, vars)
    case {VarSpec.fetch(vars, varspec), skip_eq_if_blank} do
      {{:ok, val}, _}   -> "#{varspec.name}=#{val}"
      {:missing, true}  -> varspec.name
      {:missing, false} -> "#{varspec.name}="
    end
  end

  defp expand_basic_varspec(varspec, vars) do
    VarSpec.get(vars, varspec, "")
  end

  defp raw_expand_varspec(varspec, vars) do
    VarSpec.get(vars, varspec, "", false)
  end

  defp parse_expression(expression) do
    %{"op" => op, "vars" => varlist} =
      Regex.named_captures(~r/(?<op>[+\#.\/;?&=,!@|]?)(?<vars>.*)/, expression)

    varspecs = String.split(varlist, ",") |> Enum.map(&VarSpec.from_string/1)

    {op, leaders_stream_for(op), varspecs}
  end

  defp name_value_pair_op?(op), do: Enum.member?([";","?","&"], op)

  defp leaders_stream_for(op) do
    case op do
      ""  -> Stream.iterate("",  fn _ -> "," end)
      "#" -> Stream.iterate("#", fn _ -> "," end)
      "+" -> Stream.iterate("",  fn _ -> "," end)
      "?" -> Stream.iterate("?", fn _ -> "&" end)
      _   -> Stream.cycle([op])
    end
  end
end
