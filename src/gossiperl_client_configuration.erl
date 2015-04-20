%% Copyright (c) 2014 Radoslaw Gruchalski <radek@gruchalski.com>
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.

-module(gossiperl_client_configuration).

-include("records.hrl").

-export([configure/1, client_socket/2, for_overlay/1, remove_configuration/1]).

-type client_config() :: #clientConfig{}.
-type configuration_option() :: overlay_name | overlay_port | client_name | client_port | client_secret | symmetric_key | listener.
-type configuration_validation_error() :: option_missing | needs_binary | needs_integer.

-export_type([ client_config/0,
               configuration_option/0,
               configuration_validation_error/0 ]).

%% @doc Prepare configuration from given details.
-spec configure( [ { configuration_option(), term() } ] ) -> { ok, client_config() } | { error, { configuration_validation_error(), term() } }.
configure( Options ) when is_list( Options ) ->
  case validate_required( Options ) of
    ok ->
      { overlay_name, OverlayName } = lists:keyfind( overlay_name, 1, Options ),
      { overlay_port, OverlayPort } = lists:keyfind( overlay_port, 1, Options ),
      { client_name, ClientName } = lists:keyfind( client_name, 1, Options ),
      { client_port, ClientPort } = lists:keyfind( client_port, 1, Options ),
      { client_secret, ClientSecret } = lists:keyfind( client_secret, 1, Options ),
      { symmetric_key, SymmetricKey } = lists:keyfind( symmetric_key, 1, Options ),
      BinaryOptions = [
        { overlay_name, OverlayName },
        { client_name, ClientName },
        { client_secret, ClientSecret },
        { symmetric_key, SymmetricKey } ],
      IntegerOptions = [
        { overlay_port, OverlayPort },
        { client_port, ClientPort } ],
      case validate_binary( BinaryOptions ) of
        ok ->
          case validate_integer( IntegerOptions ) of
            ok ->
              PreparedConfig = #clientConfig{
                overlay = OverlayName,
                port = ClientPort,
                overlay_port = OverlayPort,
                name = ClientName,
                secret = ClientSecret,
                symmetric_key = SymmetricKey,
                names = #clientNames{
                  client     = list_to_atom(binary_to_list(<<"client_", OverlayName/binary>>)),
                  fsm        = list_to_atom(binary_to_list(<<"fsm_", OverlayName/binary>>)),
                  messaging  = list_to_atom(binary_to_list(<<"messaging_", OverlayName/binary>>)),
                  encryption = list_to_atom(binary_to_list(<<"encryption_", OverlayName/binary>>)) },
                listener = proplists:get_value( listener, Options, gossiperl_client_listener ),
                thrift_window_size = proplists:get_value( thrift_window_size, Options, 16777216 ) },
              { ok, store_config( PreparedConfig ) };
            { error, { needs_integer, Option } } ->
              { error, { needs_integer, Option } }
          end;
        { error, { needs_binary, Option } } ->
          { error, { needs_binary, Option } }
      end;
    { error, { option_missing, Option } } ->
      { error, { option_missing, Option } }
  end.

%% @doc Store UDP socket on the configuration.
-spec client_socket( port(), client_config() ) -> client_config().
client_socket(Socket, Config) ->
  PreparedConfig = Config#clientConfig{ socket = Socket },
  store_config( PreparedConfig ),
  PreparedConfig.

%% @doc Store configuration in ETS.
-spec store_config( client_config() ) -> client_config().
store_config(Config) ->
  ets:insert(?CONFIG_ETS, { Config#clientConfig.overlay, Config }),
  Config.

%% @doc Get configuration for an overlay.
-spec for_overlay
      ( atom() ) -> { ok, client_config() } | { error, no_config };
      ( list() ) -> { ok, client_config() } | { error, no_config };
      ( binary() ) -> { ok, client_config() } | { error, no_config }.
for_overlay(OverlayName) when is_atom(OverlayName) ->
  for_overlay( atom_to_list( OverlayName ) );
for_overlay(OverlayName) when is_list(OverlayName) ->
  for_overlay( list_to_binary( OverlayName ) );
for_overlay(OverlayName) when is_binary(OverlayName) ->
  case lists:flatten(ets:lookup(?CONFIG_ETS, OverlayName)) of
    [ Config ] -> { ok, Config };
    []         -> { error, no_config }
  end.

%% @doc Remove overlay configuration.
-spec remove_configuration( client_config() ) -> true.
remove_configuration(Config) ->
  ets:delete(?CONFIG_ETS, Config#clientConfig.overlay).

%% @doc Validates configuration options, checks for required options.
-spec validate_required( [ { configuration_option(), term() } ] ) -> ok | { error, { configuration_validation_error(), atom() } }.
validate_required( Options ) when is_list(Options) ->
  RequiredOptions = [ overlay_name, overlay_port, client_name, client_secret, client_port, symmetric_key ],
  % check if all required options are here:
  lists:foldl(fun(RequiredOption, FoldResult) ->
    case FoldResult of
      ok ->
        case lists:keyfind( RequiredOption, 1, Options ) of
          false ->
            { error, { option_missing, RequiredOption } };
          _ ->
            ok
        end;
      { error, Reason } ->
        { error, Reason }
    end
  end, ok, RequiredOptions).

%% @doc Validates configuration options, check if option value is binary.
-spec validate_binary( [ term() ] ) -> ok | { error, { configuration_validation_error(), atom() } }.
validate_binary( Options ) when is_list(Options) ->
  % check if all required options are here:
  lists:foldl(fun({ OptionName, Value }, FoldResult) ->
    case FoldResult of
      ok ->
        case is_binary(Value) of
          false ->
            { error, { needs_binary, OptionName } };
          _ ->
            ok
        end;
      { error, Reason } ->
        { error, Reason }
    end
  end, ok, Options).

%% @doc Validates configuration options, check if option value is integer.
-spec validate_integer( [ term() ] ) -> ok | { error, { configuration_validation_error(), atom() } }.
validate_integer( Options ) when is_list(Options) ->
  % check if all required options are here:
  lists:foldl(fun({ OptionName, Value }, FoldResult) ->
    case FoldResult of
      ok ->
        case is_integer(Value) of
          false ->
            { error, { needs_integer, OptionName } };
          _ ->
            ok
        end;
      { error, Reason } ->
        { error, Reason }
    end
  end, ok, Options).
