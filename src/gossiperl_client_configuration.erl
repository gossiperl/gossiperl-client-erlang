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

-export([configure/7, client_socket/2, for_overlay/1, remove_configuration/1]).

%% @doc Prepare configuration from given details.
-spec configure( binary(), non_neg_integer(),
                 non_neg_integer(), binary(), binary(),
                 encryption_data(), listener() ) -> { ok, client_config() }.
configure( OverlayName, Port, OverlayPort, Name, Secret, { SymmetricKey, IV }, Listener )
  when ( is_pid(Listener) orelse Listener =:= undefined ) andalso is_integer(Port)
                                                          andalso is_integer(OverlayPort)
                                                          andalso is_binary(Name)
                                                          andalso is_binary(Secret)
                                                          andalso is_binary(SymmetricKey)
                                                          andalso is_binary(IV) ->
  PreparedConfig = #clientConfig{
    overlay = OverlayName,
    port = Port,
    overlay_port = OverlayPort,
    name = Name,
    secret = Secret,
    symmetric_key = SymmetricKey,
    iv = IV,
    names = #clientNames{
      client     = list_to_atom(binary_to_list(<<"client_", OverlayName/binary>>)),
      fsm        = list_to_atom(binary_to_list(<<"fsm_", OverlayName/binary>>)),
      messaging  = list_to_atom(binary_to_list(<<"messaging_", OverlayName/binary>>)),
      encryption = list_to_atom(binary_to_list(<<"encryption_", OverlayName/binary>>)) },
    listener = Listener },
  { ok, store_config( PreparedConfig ) }.

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
