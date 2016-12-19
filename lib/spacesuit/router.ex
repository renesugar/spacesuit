defmodule Spacesuit.Router do
  require Logger

  @routes_file "routes.yaml"

  def load_routes do
    [routes] = :yamerl_constr.file(@routes_file)
    # Let's validate what we got and at least fail to start if it's busted
    if !valid_routes?(routes) do
      raise "Invalid routes! #{inspect(routes)}"
    end
    transform_routes(routes)
  end

  def valid_routes?(routes) do
    try do
      Enum.all?(routes, fn(r) ->
        {_host, entries} = r
        Enum.all?(entries, fn(e) ->
          {_route, items} = e
          List.keymember?(items, 'description', 0) && (
            List.keymember?(items, 'map', 0) || List.keymember?(items, 'destination', 0)
          )
        end)
      end)
    rescue
      e in MatchError ->
        Logger.error "Bad routes! Cannot parse structure: #{e}"
        false
    end
  end

  def transform_routes(source) do
    Enum.map(source, fn({host, routes}) ->
      {host, Enum.map(routes, &transform_one_route/1)}
    end)
  end

  def transform_one_route(source) do
    {route, opts} = source

    # We have to turn this nastiness into something we can use
    atomized_opts = opts |> Enum.map(
      fn({k, v}) ->
        { String.to_atom(to_string(k)), v }
      end)

    handler_opts = case Dict.fetch(atomized_opts, :map) do
      {:ok, route_map} -> 
        Dict.merge(atomized_opts, compile(route_map))
      _ ->
        atomized_opts
    end

    {route, Spacesuit.ProxyHandler, handler_opts}
  end

  # Returns a function that will handle the route substitution
  def func_for_key(key) do
    case key do
      # When beginning with a colon we know it's a substitution
      ":" <> lookup_key_str ->
        lookup_key = String.to_atom(lookup_key_str) 

        fn(bindings) ->
          Dict.fetch!(bindings, lookup_key)
        end
      _ ->
        # Otherwise it's just text
        fn(_) -> key end
    end
  end

  def build(route_map, bindings) do
    uri = Dict.get(route_map, :uri)
    map = Dict.get(route_map, :map)

    path = map
      |> Enum.map(fn(x) -> x.(bindings) end)
      |> Enum.join("/")

    URI.to_string(%{ uri | path: path })
  end

  def compile(route_map) do
    uri = URI.parse(to_string(route_map))

    map = if uri.path != nil do
      String.split(uri.path, "/")
        |> Enum.map(&func_for_key/1)
    else
      [] 
    end

    %{ map: map, uri: uri }
  end
end
