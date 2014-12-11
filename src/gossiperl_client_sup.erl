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
-export([ connect/6,
          connect/7,
          disconnect/1,
          check_state/1,
          subscriptions/1,
          subscribe/2,
          unsubscribe/2 ]).

-include("records.hrl").

start_link() ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
  ets:new(?CONFIG_ETS, [set, named_table, public]),
  gossiperl_client_log:info("Gossiperl client application running."),
  {ok, {{one_for_all, 10, 10}, []}}.

%% CONNECTIVITY

connect(OverlayName, Port, OverlayPort, Name, Secret, { SymmetricKey, IV }) ->
  connect(OverlayName, Port, OverlayPort, Name, Secret, { SymmetricKey, IV }, undefined).

connect(OverlayName, Port, OverlayPort, Name, Secret, { SymmetricKey, IV }, Listener)
  when is_pid(Listener) orelse Listener =:= undefined ->
  case gossiperl_client_configuration:configure( OverlayName, Port, OverlayPort, Name, Secret, { SymmetricKey, IV }, Listener) of
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

disconnect(OverlayName) ->
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

check_state(OverlayName) ->
  case gossiperl_client_configuration:for_overlay( OverlayName ) of
    { ok, { _, Config } } ->
      gen_fsm:sync_send_all_state_event(?FSM(Config), { state });
    { error, Reason } ->
      { error, Reason }
  end.

subscriptions(OverlayName) ->
  case gossiperl_client_configuration:for_overlay( OverlayName ) of
    { ok, { _, Config } } ->
      gen_fsm:sync_send_all_state_event(?FSM(Config), { subscriptions });
    { error, Reason } ->
      { error, Reason }
  end.

%% SUBSCRIPTIONS

subscribe(OverlayName, EventTypes) ->
  case gossiperl_client_configuration:for_overlay( OverlayName ) of
    { ok, { _, Config } } ->
      gen_fsm:sync_send_all_state_event(?FSM(Config), { subscribe, EventTypes });
    { error, Reason } ->
      { error, Reason }
  end.

unsubscribe(OverlayName, EventTypes) ->
  case gossiperl_client_configuration:for_overlay( OverlayName ) of
    { ok, { _, Config } } ->
      gen_fsm:sync_send_all_state_event(?FSM(Config), { unsubscribe, EventTypes });
    { error, Reason } ->
      { error, Reason }
  end.