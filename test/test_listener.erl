-module(test_listener).

-bahaviour(gen_server).

-export([start_link/0, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2]).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() -> ok.

init([]) ->
  {ok, {test_listener}}.

handle_info({ event, connected, OverlayName, Subscriptions }, LoopData) ->
  gossiperl_client_log:info("Listener received `connected` to ~p with ~p.",
                            [ OverlayName, Subscriptions ]),
  {noreply, LoopData};

handle_info({ event, disconnected, OverlayName }, LoopData) ->
  gossiperl_client_log:info("Listener received `disconnected` from ~p.",
                            [ OverlayName ]),
  {noreply, LoopData};

handle_info({ subscribed, { OverlayName, EventTypes, _Heartbeat } }, LoopData) ->
  gossiperl_client_log:info("Listener received `subscribed` to ~p at overlay ~p.",
                            [ EventTypes, OverlayName ]),
  {noreply, LoopData};

handle_info({ unsubscribed, { OverlayName, EventTypes, _Heartbeat } }, LoopData) ->
  gossiperl_client_log:info("Listener received `unsubscribed` from ~p at overlay ~p.",
                            [ EventTypes, OverlayName ]),
  {noreply, LoopData};

handle_info({ event, { OverlayName, EventTypes, _Heartbeat } }, LoopData) ->
  gossiperl_client_log:info("Listener received `event` from ~p from overlay ~p.",
                            [ EventTypes, OverlayName ]),
  {noreply, LoopData};

handle_info({ forwarded_ack, { OverlayName, EventTypes, ReplyId } }, LoopData) ->
  gossiperl_client_log:info("Listener received `forwarded ack` from ~p from overlay ~p. Digest ID: ~p.",
                            [ EventTypes, OverlayName, ReplyId ]),
  {noreply, LoopData};

handle_info({ forwarded, { OverlayName, EventTypes, ReplyId } }, LoopData) ->
  gossiperl_client_log:info("Listener received `forwarded ack` from ~p from overlay ~p. Digest ID: ~p.",
                            [ EventTypes, OverlayName, ReplyId ]),
  {noreply, LoopData};

handle_info({ forwarded, { OverlayName, DigestType, _DigestEnvelope, DigestId } }, LoopData) ->
  gossiperl_client_log:info("Listener received `forwarded` digest ~p from ~p. Digest ID: ~p.",
                            [ DigestType, OverlayName, DigestId ]),
  {noreply, LoopData};

handle_info({ failed, { OverlayName, Reason } }, LoopData) ->
  gossiperl_client_log:info("Listener received message deserialization failure. Message came from ~p. Reason: ~p.",
                            [ OverlayName, Reason ]),
  {noreply, LoopData}.

handle_call(_Msg, _From, LoopData) ->
  {noreply, LoopData}.

handle_cast(_Msg, LoopData) ->
  {noreply, LoopData}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

terminate(_Reason, _LoopData) ->
  {ok}.