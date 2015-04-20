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
-export([contact_overlay/2, operational/2, disconnected/2]).
 
-include("records.hrl").

-record(state, {
  config :: #clientConfig{},
  subscriptions = [] :: list(),
  last_ack :: integer() }).

%% @doc Starts client FSM.
start_link(Config) ->
  gen_fsm:start_link({local, ?FSM(Config)}, ?MODULE, [Config], []).

%% @doc Initializes client FSM.
init([Config]) ->
  gossiperl_log:info("[~p] FSM running.", [Config#clientConfig.name]),
  { ok, contact_overlay,
    {gossiperl_client, #state{ config=Config, last_ack=gossiperl_client_common:get_timestamp() }},
    500 }.

handle_info(_AnyInfo, State, LoopData) ->
  { next_state, State, LoopData, 0 }.

handle_event(stop, _StateName, StateData) ->
  {stop, normal, StateData}.

%% @doc Attempt notifying the overlay about an intent of disconnection.
handle_sync_event({disconnect}, From, _State,
  {gossiperl_client, S=#state{ config=Config, subscriptions=Subscriptions }}) ->
  subscription_action(digestUnsubscribe, Config, Subscriptions),
  ok = gen_server:call(?MESSAGING(Config), { digestExit }),
  gen_fsm:reply(From, ok),
  { next_state, disconnected, {gossiperl_client, S#state{ subscriptions=[] }}, 0 };

%% @doc Get the current FSM state.
handle_sync_event({state}, From, State, {gossiperl_client, S=#state{}}) ->
  gen_fsm:reply(From, State),
  { next_state, State, {gossiperl_client, S}, 0 };

%% @doc Get current list of subscriptions.
handle_sync_event({subscriptions}, From, State,
  {gossiperl_client, S=#state{ subscriptions=Subscriptions }}) ->
  gen_fsm:reply(From, Subscriptions),
  { next_state, State, {gossiperl_client, S}, 0 };

%% @doc Subscribe to one or more events.
handle_sync_event({subscribe, EventTypes}, From, State,
  {gossiperl_client, S=#state{ config=Config, subscriptions=Subscriptions }}) ->
  case subscription_action(digestSubscribe, Config, EventTypes) of
    { ok, EventTypes } ->
      gen_fsm:reply( From, { ok, EventTypes } ),
      { next_state, State, {gossiperl_client, S#state{ subscriptions=lists:usort(Subscriptions ++ EventTypes)}}, 0 };
    { error, Reason } ->
      gen_fsm:reply( From, { error, Reason } ),
      { next_state, State, {gossiperl_client, S}, 0 }
  end;

%% @doc Unsubscribe from every event.
handle_sync_event({unsubscribe, every}, From, State, 
  {gossiperl_client, S=#state{ config=Config, subscriptions=Subscriptions }}) ->
  case subscription_action(digestUnsubscribe, Config, Subscriptions) of
    { ok, Subscriptions } ->
      gen_fsm:reply( From, { ok, Subscriptions } ),
      { next_state, State, {gossiperl_client, S#state{ subscriptions=[] }}, 0 };
    { error, Reason } ->
      gen_fsm:reply( From, { error, Reason } ),
      { next_state, State, {gossiperl_client, S}, 0 }
  end;

%% @doc Unsubscribe from one or more events.
handle_sync_event({unsubscribe, EventTypes}, From, State,
  {gossiperl_client, S=#state{ config=Config, subscriptions=Subscriptions }}) ->
  case subscription_action(digestUnsubscribe, Config, EventTypes) of
    { ok, EventTypes } ->
      gen_fsm:reply( From, { ok, EventTypes } ),
      { next_state, State, {gossiperl_client, S#state{ subscriptions=(Subscriptions -- EventTypes) }}, 0 };
    { error, Reason } ->
      gen_fsm:reply( From, { error, Reason } ),
      { next_state, State, {gossiperl_client, S}, 0 }
  end;

handle_sync_event({digestAck}, From, disconnected,
  {gossiperl_client, S=#state{ config=Config, subscriptions=Subscriptions }}) ->
  (Config#clientConfig.listener):connected( Config#clientConfig.overlay, Subscriptions ),
  subscription_action(digestSubscribe, Config, Subscriptions),
  gen_fsm:reply(From, ok),
  { next_state, operational, {gossiperl_client, S#state{ last_ack=gossiperl_client_common:get_timestamp() }}, 2000 };

handle_sync_event({digestAck}, From, operational, {gossiperl_client, S=#state{}}) ->
  gen_fsm:reply(From, ok),
  { next_state, operational, {gossiperl_client, S#state{ last_ack=gossiperl_client_common:get_timestamp() }}, 2000 }.

code_change(_OldVsn, StateName, StateData, _Extra) ->
  {ok, StateName, StateData}.

terminate(_Reason, _State, _LoopData) ->
  {ok}.

contact_overlay(timeout, {gossiperl_client, S=#state{ config=Config }}) ->
  gen_server:cast(?MESSAGING(Config), { digest }),
  { next_state, disconnected, {gossiperl_client, S}, 5000 }.

operational(timeout, {gossiperl_client, S=#state{ config=Config, last_ack=LastAckTs }}) ->
  Diff = gossiperl_client_common:get_timestamp() - LastAckTs,
  if
    (Diff >= 5000) -> { next_state, disconnected, {gossiperl_client, S}, 0 };
    true           -> gen_server:cast(?MESSAGING(Config), { digest }),
                      { next_state, operational, {gossiperl_client, S}, 5000 }
  end.

disconnected(_, {gossiperl_client, S=#state{ config=Config }}) ->
  (Config#clientConfig.listener):disconnected( Config#clientConfig.overlay ),
  { next_state, contact_overlay, {gossiperl_client, S}, 2500 }.

subscription_action(Action, _Config, []) when is_atom(Action) ->
  { ok, [] };
subscription_action(Action, Config, EventTypes) when is_atom(Action) andalso is_list(EventTypes) ->
  IsAllAtoms = lists:foldl(fun(Item, State) ->
    case is_atom(Item) of
      true  -> State;
      false -> { error, { not_atom, Item } }
    end
  end, { ok, EventTypes }, EventTypes ),
  case IsAllAtoms of
    { ok, ListOfAtoms } -> gen_server:cast(?MESSAGING(Config), { Action, ListOfAtoms }),
                           { ok, ListOfAtoms };
    { error, Reason }   -> { error, Reason }
  end.
