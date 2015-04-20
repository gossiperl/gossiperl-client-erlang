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

-module(gossiperl_client_messaging).

-behaviour(gen_server).

-export([start_link/1, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2]).

-include("records.hrl").

%% @doc Starts messaging module.
start_link(Config) ->
  gen_server:start_link({local, ?MESSAGING(Config)}, ?MODULE, [Config], []).

%% @doc Stops messaging module.
stop() -> gen_server:cast(?MODULE, stop).

%% @doc Initializes messaging module.
-spec init( [ gossiperl_client_configuration:client_config() ] ) -> { ok, { messaging, gossiperl_client_configuration:client_config() } } | { error, term() }.
init([Config]) ->
  gossiperl_log:info("[~p] Attempting to start a client server at ~p.", [Config#clientConfig.name, Config#clientConfig.port]),
  case gen_udp:open(Config#clientConfig.port, [ binary,
                                                {ip, {127,0,0,1}},
                                                {recbuf, Config#clientConfig.thrift_window_size},
                                                {sndbuf, Config#clientConfig.thrift_window_size} ]) of
    {ok, Socket} ->
      gossiperl_log:info("[~p] Client server listening with config ~p.", [Config#clientConfig.name, Config]),
      {ok, {messaging, gossiperl_client_configuration:client_socket( Socket, Config ) }};
    {error, Reason} ->
      gossiperl_log:info("[~p] Error while starting client server. Reason: ~p.", [Config#clientConfig.name, Reason]),
      {error, Reason}
  end.

%% @doc Send given digest out.
handle_cast({ send_digest, DigestType, Digest }, { messaging, Config }) ->
  { ok, DigestType, SerializedDigest } = gen_server:call( gossiperl_client_serialization,
                                                          { serialize, DigestType, Digest } ),
  { ok, EncryptedDigest } = gen_server:call( ?ENCRYPTION(Config), { maybe_encrypt, SerializedDigest } ),
  gen_udp:send(
    Config#clientConfig.socket,
    {127,0,0,1},
    Config#clientConfig.overlay_port,
    EncryptedDigest ),
  {noreply, {messaging, Config}};

%% OUTGOING DIGESTS

%% @doc Send a digest out.
handle_cast({ digest }, { messaging, Config }) ->
  Digest = #digest{
    name = Config#clientConfig.name,
    port = Config#clientConfig.port,
    heartbeat = gossiperl_client_common:get_timestamp(),
    id = uuid:uuid_to_string(uuid:get_v4()),
    secret = Config#clientConfig.secret },
  gen_server:cast(?MESSAGING(Config), { send_digest, digest, Digest }),
  {noreply, {messaging, Config}};

%% @doc Send a digestSubscribe out.
handle_cast({ digestSubscribe, EventTypes }, { messaging, Config }) ->
  Digest = #digestSubscribe{
    name = Config#clientConfig.name,
    heartbeat = gossiperl_client_common:get_timestamp(),
    id = uuid:uuid_to_string(uuid:get_v4()),
    event_types = [ list_to_binary(atom_to_list(Item)) || Item <- EventTypes ],
    secret = Config#clientConfig.secret },
  gen_server:cast(?MESSAGING(Config), { send_digest, digestSubscribe, Digest }),
  {noreply, {messaging, Config}};

%% @doc Send a digestUnsubscribe out.
handle_cast({ digestUnsubscribe, EventTypes }, { messaging, Config }) ->
  Digest = #digestUnsubscribe{
    name = Config#clientConfig.name,
    heartbeat = gossiperl_client_common:get_timestamp(),
    id = uuid:uuid_to_string(uuid:get_v4()),
    event_types = [ list_to_binary(atom_to_list(Item)) || Item <- EventTypes ],
    secret = Config#clientConfig.secret },
  gen_server:cast(?MESSAGING(Config), { send_digest, digestUnsubscribe, Digest }),
  {noreply, {messaging, Config}};

% INCOMING DIGESTS:

%% @doc Hanlde incoming digest.
handle_cast({ digest, DecodedPayload }, { messaging, Config }) ->
  Digest = #digestAck{
    name = Config#clientConfig.name,
    heartbeat = gossiperl_client_common:get_timestamp(),
    reply_id = DecodedPayload#digest.id,
    membership = [] },
  gen_server:cast(?MESSAGING(Config), { send_digest, digestAck, Digest }),
  {noreply, {messaging, Config}};

%% @doc Hanlde incoming digestAck.
handle_cast({ digestAck, _DecodedPayload }, { messaging, Config }) ->
  gen_fsm:sync_send_all_state_event(?FSM(Config), { digestAck }),
  {noreply, {messaging, Config}};

%% @doc Hanlde incoming digestSubscribeAck.
handle_cast({ digestSubscribeAck, DecodedPayload }, { messaging, Config }) ->
  ( Config#clientConfig.listener ):subscribed( Config#clientConfig.overlay,
                                               DecodedPayload#digestSubscribeAck.event_types,
                                               DecodedPayload#digestSubscribeAck.heartbeat ),
  {noreply, {messaging, Config}};

%% @doc Hanlde incoming digestUnsubscribeAck.
handle_cast({ digestUnsubscribeAck, DecodedPayload }, { messaging, Config }) ->
  (Config#clientConfig.listener):unsubscribed( Config#clientConfig.overlay,
                                               DecodedPayload#digestUnsubscribeAck.event_types,
                                               DecodedPayload#digestUnsubscribeAck.heartbeat ),
  {noreply, {messaging, Config}};


%% @doc Hanlde incoming digestEvent.
handle_cast({ digestEvent, DecodedPayload }, { messaging, Config }) ->
  (Config#clientConfig.listener):event( Config#clientConfig.overlay,
                                        DecodedPayload#digestEvent.event_type,
                                        DecodedPayload#digestEvent.event_object,
                                        DecodedPayload#digestEvent.heartbeat ),
  {noreply, {messaging, Config}};

%% @doc Hanlde incoming digestForwardedAck.
handle_cast({ digestForwardedAck, DecodedPayload }, { messaging, Config }) ->
  (Config#clientConfig.listener):forward_ack( Config#clientConfig.overlay,
                                              DecodedPayload#digestForwardedAck.name,
                                              DecodedPayload#digestForwardedAck.reply_id ),
  {noreply, {messaging, Config}};

%% FORWARDABLES:

%% @doc Hanlde forwarded digest.
handle_cast({ forwardable, UnsupportedDigestType, DigestEnvelopeBin, DigestId }, {messaging, Config}) ->
  ( Config#clientConfig.listener ):forward( Config#clientConfig.overlay,
                                            UnsupportedDigestType,
                                            DigestEnvelopeBin,
                                            DigestId ),
  gen_server:cast( ?MESSAGING(Config), { send_digest,
                                         digestForwardedAck,
                                         #digestForwardedAck{
                                          name = Config#clientConfig.name,
                                          reply_id = DigestId,
                                          secret = Config#clientConfig.secret } } ),
  {noreply, {messaging, Config}};

%% @doc Hanlde stop digest.
handle_cast(stop, LoopData) ->
  {noreply, LoopData}.

%% @doc Hanlde incoming UDP data.
handle_info({udp, _ClientSocket, _ClientIp, _ClientPort, Msg}, {messaging, Config}) ->
  case gen_server:call( ?ENCRYPTION(Config), { maybe_decrypt, Msg } ) of
    { ok, DecryptedMsg } ->
      case gen_server:call(gossiperl_client_serialization, { deserialize, DecryptedMsg }) of
        {ok, DecodedPayloadType, DecodedPayload} ->
          gen_server:cast( ?MESSAGING(Config), { DecodedPayloadType, DecodedPayload } );
        { forwardable, UnsupportedDigestType, DigestEnvelopeBin, DigestId } ->
          gen_server:cast( ?MESSAGING(Config), { forwardable, UnsupportedDigestType, DigestEnvelopeBin, DigestId } );
        {error, Reason} ->
          (Config#clientConfig.listener):failed( Config#clientConfig.overlay, Reason )
      end;
    { error, Reason } ->
      gossiperl_log:warn("[~p] Message could not be decrypted. Reason: ~p.", [ Config#clientConfig.name, Reason ])
  end,
  {noreply, {messaging, Config}}.

%% @doc Send given digest out.
handle_call({ send_digest, DigestType, DigestData, DigestId }, From, { messaging, Config }) ->
  case gen_server:call( gossiperl_client_serialization,
                        { serialize_arbitrary, DigestType, DigestData, DigestId } ) of
    { ok, digestEnvelope, SerializedDigest } ->
      gen_server:cast( ?MESSAGING(Config), { send_digest, digestEnvelope, SerializedDigest } ),
      gen_server:reply( From, ok );
    { error, Reason } ->
      gen_server:reply( From, { error, Reason } )
  end,
  {noreply, {messaging, Config}};

%% @doc Send digestExit out synchronously.
handle_call({ digestExit }, From, { messaging, Config }) ->
  Digest = #digestExit{
    name = Config#clientConfig.name,
    heartbeat = gossiperl_client_common:get_timestamp(),
    secret = Config#clientConfig.secret },
  gen_server:cast(?MESSAGING(Config), { send_digest, digestExit, Digest }),
  gen_server:reply(From, ok),
  {noreply, {messaging, Config}}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

terminate(_Reason, LoopData) ->
  {ok, LoopData}.
