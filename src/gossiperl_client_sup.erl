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

-module(gossiperl_client_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).
-export([ connect/1,
          disconnect/1,
          check_state/1,
          subscriptions/1,
          subscribe/2,
          unsubscribe/2,
          send/3,
          read/3 ]).

-include("records.hrl").

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  ets:new(?CONFIG_ETS, [set, named_table, public]),
  gossiperl_client_log:info("Gossiperl client application running."),
  {ok, {{one_for_all, 10, 10}, [{
    gossiperl_client_serialization,
    {gossiperl_client_serialization, start_link, []},
    permanent,
    1000,
    worker,
    []
  }]}}.

%% CONNECTIVITY

%% @doc Connect to an overlay with listener.
-spec connect( [ { configuration_option(), term() } ] ) -> { ok, pid() } | { error, term() }.
connect( Options ) when is_list( Options ) ->
  case gossiperl_client_configuration:configure( Options ) of
    { ok, PreparedConfig } ->
      supervisor:start_child(?MODULE, {
        ?CLIENT(PreparedConfig),
        {gossiperl_client_overlay_sup, start_link, [ PreparedConfig ]},
        permanent,
        1000,
        supervisor,
        []
      });
    { error, Reason } ->
      {error, Reason}
  end.

%% @doc Disconnect from an overlay.
-spec disconnect( binary() ) -> ok | { error, term() }.
disconnect(OverlayName) when is_binary(OverlayName) ->
  case gossiperl_client_configuration:for_overlay( OverlayName ) of
    { ok, { _, Config } } ->
      ok   = gen_fsm:sync_send_all_state_event(?FSM(Config), { disconnect }),
      true = gossiperl_client_configuration:remove_configuration(Config),
      case supervisor:terminate_child(?MODULE, ?CLIENT(Config)) of
        ok ->
          supervisor:delete_child(?MODULE, ?CLIENT(Config));
        {error, Reason} ->
          {error, Reason}
      end;
    { error, Reason } ->
      {error, Reason}
  end.

%% STATE

%% @doc Check state of the connection.
-spec check_state( binary() ) -> atom() | { error, term() }.
check_state(OverlayName) when is_binary(OverlayName) ->
  case gossiperl_client_configuration:for_overlay( OverlayName ) of
    { ok, { _, Config } } ->
      gen_fsm:sync_send_all_state_event(?FSM(Config), { state });
    { error, Reason } ->
      { error, Reason }
  end.

%% @doc Check current subscriptions.
-spec subscriptions( binary() ) -> [ atom() ] | { error, term() }.
subscriptions(OverlayName) when is_binary(OverlayName) ->
  case gossiperl_client_configuration:for_overlay( OverlayName ) of
    { ok, { _, Config } } ->
      gen_fsm:sync_send_all_state_event(?FSM(Config), { subscriptions });
    { error, Reason } ->
      { error, Reason }
  end.

%% SUBSCRIPTIONS

%% @doc Subscribe to one or more event types.
-spec subscribe( binary(), [ atom() ] ) -> { ok, [ atom() ] } | { error, term() }.
subscribe(OverlayName, EventTypes) when is_binary(OverlayName) andalso is_list(EventTypes) ->
  case gossiperl_client_configuration:for_overlay( OverlayName ) of
    { ok, { _, Config } } ->
      gen_fsm:sync_send_all_state_event(?FSM(Config), { subscribe, EventTypes });
    { error, Reason } ->
      { error, Reason }
  end.

%% @doc Unsubscribe from one or more event types.
-spec unsubscribe( binary(), [ atom() ] ) -> { ok, [ atom() ] } | { error, term() }.
unsubscribe(OverlayName, EventTypes) when is_binary(OverlayName) andalso is_list(EventTypes) ->
  case gossiperl_client_configuration:for_overlay( OverlayName ) of
    { ok, { _, Config } } ->
      gen_fsm:sync_send_all_state_event(?FSM(Config), { unsubscribe, EventTypes });
    { error, Reason } ->
      { error, Reason }
  end.

%% @doc Send a custom digest to the overlay.
-spec send( binary(), atom(), [ { atom(), term(), atom(), non_neg_integer() } ] ) -> { ok, binary() } | { error, term() }.
send(OverlayName, DigestType, DigestData) when is_binary(OverlayName) andalso is_atom(DigestType) ->
  case gossiperl_client_configuration:for_overlay( OverlayName ) of
    { ok, { _, Config } } ->
      DigestId = list_to_binary(uuid:uuid_to_string(uuid:get_v4())),
      case gen_server:call( ?MESSAGING(Config), { send_digest, DigestType, DigestData, DigestId } ) of
        ok ->
          { ok, DigestId };
        { error, SerializerErrorReason } ->
          { error, SerializerErrorReason }
      end;
    { error, Reason } ->
      { error, Reason }
  end.

%% @doc Read custom digest, most likely received as a forwarded message.
-spec read( binary(), atom(), [ { non_neg_integer(), atom() } ] ) -> { ok, atom(), tuple() } | { error, term() }.
read(DigestType, BinaryEnvelope, DigestInfo) when is_binary(BinaryEnvelope) andalso is_atom(DigestType) andalso is_list(DigestInfo) ->
  gen_server:call( gossiperl_client_serialization, { deserialize, DigestType, BinaryEnvelope, DigestInfo } ).
