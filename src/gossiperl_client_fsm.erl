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

-module(gossiperl_client_fsm).

-behaviour(gen_fsm).

-export([start_link/1, init/1, handle_info/3, terminate/3, code_change/4, handle_sync_event/4, handle_event/3]).
-export([contact_overlay/2, operational/2, wait_for_reply/2, disconnected/2]).
 
-include("records.hrl").

start_link(Config) ->
  gen_fsm:start_link({local, ?FSM(Config)}, ?MODULE, [Config], []).

init([Config]) ->
  gossiperl_client_log:info("[~p] FSM running.", [Config#clientConfig.name]),
  { ok, contact_overlay, {gossiperl_client, Config, []}, 0 }.

handle_info({digestAck, _Digest}, contact_overlay, {gossiperl_client, Config, Subscriptions}) ->
  case is_pid( Config#clientConfig.listener ) of
    true ->
      Config#clientConfig.listener ! { event, connected, Config#clientConfig.overlay, Subscriptions };
    false ->
      error_logger:info_msg("[EVENT] Connected: ~p, ~p.", [Config#clientConfig.overlay, Subscriptions])
  end,
  subscription_action(digestSubscribe, Config, Subscriptions),
  { next_state, operational, {gossiperl_client, Config, Subscriptions}, 2500 };

handle_info({digestAck, _Digest}, wait_for_reply, {gossiperl_client, Config, Subscriptions}) ->
  { next_state, operational, {gossiperl_client, Config, Subscriptions}, 2000 };

handle_info(_AnyInfo, State, LoopData) ->
  { next_state, State, LoopData, 2500 }.

handle_event(stop, _StateName, StateData) ->
  {stop, normal, StateData}.

handle_sync_event({disconnect}, From, _State, {gossiperl_client, Config, Subscriptions}) ->
  subscription_action(digestUnsubscribe, Config, Subscriptions),
  ok = gen_server:call(?MESSAGING(Config), { digestExit }),
  gen_fsm:reply(From, ok),
  { next_state, disconnected, {gossiperl_client, Config, []}, 0 };

handle_sync_event({state}, From, State, {gossiperl_client, Config, Subscriptions}) ->
  gen_fsm:reply(From, State),
  { next_state, State, {gossiperl_client, Config, Subscriptions}, 0 };

handle_sync_event({subscriptions}, From, State, {gossiperl_client, Config, Subscriptions}) ->
  gen_fsm:reply(From, Subscriptions),
  { next_state, State, {gossiperl_client, Config, Subscriptions}, 0 };

handle_sync_event({subscribe, EventTypes}, From, State, {gossiperl_client, Config, Subscriptions}) ->
  case subscription_action(digestSubscribe, Config, EventTypes) of
    { ok, EventTypes } ->
      gen_fsm:reply( From, { ok, EventTypes } ),
      { next_state, State, {gossiperl_client, Config, lists:usort(Subscriptions ++ EventTypes)}, 0 };
    { error, Reason } ->
      gen_fsm:reply( From, { error, Reason } ),
      { next_state, State, {gossiperl_client, Config, Subscriptions}, 0 }
  end;

handle_sync_event({unsubscribe, every}, From, State, {gossiperl_client, Config, Subscriptions}) ->
  case subscription_action(digestUnsubscribe, Config, Subscriptions) of
    { ok, Subscriptions } ->
      gen_fsm:reply( From, { ok, Subscriptions } ),
      { next_state, State, {gossiperl_client, Config, []}, 0 };
    { error, Reason } ->
      gen_fsm:reply( From, { error, Reason } ),
      { next_state, State, {gossiperl_client, Config, Subscriptions}, 0 }
  end;

handle_sync_event({unsubscribe, EventTypes}, From, State, {gossiperl_client, Config, Subscriptions}) ->
  case subscription_action(digestUnsubscribe, Config, EventTypes) of
    { ok, EventTypes } ->
      gen_fsm:reply( From, { ok, EventTypes } ),
      { next_state, State, {gossiperl_client, Config, Subscriptions -- EventTypes}, 0 };
    { error, Reason } ->
      gen_fsm:reply( From, { error, Reason } ),
      { next_state, State, {gossiperl_client, Config, Subscriptions}, 0 }
  end.

code_change(_OldVsn, StateName, StateData, _Extra) ->
  {ok, StateName, StateData}.

terminate(_Reason, _State, _LoopData) ->
  {ok}.

contact_overlay(_, {gossiperl_client, Config, Subscriptions}) ->
  gen_server:cast(?MESSAGING(Config), { digest }),
  { next_state, contact_overlay, {gossiperl_client, Config, Subscriptions}, 2500 }.

operational(_, {gossiperl_client, Config, Subscriptions}) ->
  gen_server:cast(?MESSAGING(Config), { digest }),
  { next_state, wait_for_reply, {gossiperl_client, Config, Subscriptions}, 2500 }.

wait_for_reply(_, {gossiperl_client, Config, Subscriptions}) ->
  { next_state, disconnected, {gossiperl_client, Config, Subscriptions}, 2500 }.

disconnected(_, {gossiperl_client, Config, Subscriptions}) ->
  case is_pid( Config#clientConfig.listener ) of
    true ->
      Config#clientConfig.listener ! { event, disconnected, Config#clientConfig.overlay };
    false ->
      error_logger:info_msg("[EVENT] Disconnected: ~p.", [Config#clientConfig.overlay])
  end,
  { next_state, contact_overlay, {gossiperl_client, Config, Subscriptions}, 2500 }.

subscription_action(_Action, _Config, []) ->
  { ok, [] };
subscription_action(Action, Config, EventTypes) when is_list(EventTypes) ->
  IsAllAtoms = lists:foldl(fun(Item, State) ->
    case is_atom(Item) of
      true  -> State;
      false -> { error, { not_atom, Item } }
    end
  end, { ok, EventTypes }, EventTypes ),
  case IsAllAtoms of
    { ok, ListOfAtoms } ->
      gen_server:cast(?MESSAGING(Config), { Action, ListOfAtoms }),
      { ok, ListOfAtoms };
    { error, Reason } ->
      { error, Reason }
  end.
