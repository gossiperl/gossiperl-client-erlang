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

start_link(Config) ->
  gen_server:start_link({local, ?MESSAGING(Config)}, ?MODULE, [Config], []).

stop() -> gen_server:cast(?MODULE, stop).

init([Config]) ->
  gossiperl_client_log:info("[~p] Attempting to start a client server at ~p.", [Config#clientConfig.name, Config#clientConfig.port]),
  case gen_udp:open(Config#clientConfig.port, [binary, {ip, {127,0,0,1}}]) of
    {ok, Socket} ->
      gossiperl_client_log:info("[~p] Client server listening with config ~p.", [Config#clientConfig.name, Config]),
      {ok, {messaging, gossiperl_client_configuration:client_socket( Socket, Config ) }};
    {error, Reason} ->
      gossiperl_client_log:info("[~p] Error while starting client server. Reason: ~p.", [Config#clientConfig.name, Reason]),
      {error, Reason}
  end.

handle_cast({ send_digest, DigestType, Digest }, { messaging, Config }) ->
  SerializedDigest = gossiperl_client_serialization:encode_message( DigestType, Digest ),
  EncryptedDigest  = gossiperl_client_encryption:maybe_encrypt( SerializedDigest, Config ),
  gen_udp:send(
    Config#clientConfig.socket,
    {127,0,0,1},
    Config#clientConfig.overlay_port,
    EncryptedDigest ),
  {noreply, {messaging, Config}};

handle_cast({ digest }, { messaging, Config }) ->
  Digest = #digest{
    name = Config#clientConfig.name,
    port = Config#clientConfig.port,
    heartbeat = gossiperl_client_common:get_timestamp(),
    id = uuid:uuid_to_string(uuid:get_v4()),
    secret = Config#clientConfig.secret },
  gen_server:cast(?MESSAGING(Config), { send_digest, digest, Digest }),
  {noreply, {messaging, Config}};

handle_cast({ digestSubscribe, EventTypes }, { messaging, Config }) ->
  Digest = #digestSubscribe{
    name = Config#clientConfig.name,
    heartbeat = gossiperl_client_common:get_timestamp(),
    id = uuid:uuid_to_string(uuid:get_v4()),
    event_types = [ list_to_binary(atom_to_list(Item)) || Item <- EventTypes ],
    secret = Config#clientConfig.secret },
  gen_server:cast(?MESSAGING(Config), { send_digest, digestSubscribe, Digest }),
  {noreply, {messaging, Config}};

handle_cast({ digestUnsubscribe, EventTypes }, { messaging, Config }) ->
  Digest = #digestUnsubscribe{
    name = Config#clientConfig.name,
    heartbeat = gossiperl_client_common:get_timestamp(),
    id = uuid:uuid_to_string(uuid:get_v4()),
    event_types = [ list_to_binary(atom_to_list(Item)) || Item <- EventTypes ],
    secret = Config#clientConfig.secret },
  gen_server:cast(?MESSAGING(Config), { send_digest, digestUnsubscribe, Digest }),
  {noreply, {messaging, Config}};

handle_cast(stop, LoopData) ->
  {noreply, LoopData}.

handle_info({ digestAck, Payload }, { messaging, Config }) ->
  Digest = #digestAck{
    name = Config#clientConfig.name,
    heartbeat = gossiperl_client_common:get_timestamp(),
    reply_id = Payload#digest.id,
    membership = [] },
  self() ! { send_digest, digestAck, Digest },
  {noreply, {messaging, Config}};

handle_info({udp, ClientSocket, ClientIp, ClientPort, Msg}, {messaging, Config}) ->
  handle_received_message({udp, ClientSocket, ClientIp, ClientPort, Msg}, Config),
  {noreply, {messaging, Config}}.

handle_received_message({udp, _ClientSocket, _ClientIp, _ClientPort, Msg}, Config) ->
  case gossiperl_client_serialization:decode_message(
            gossiperl_client_encryption:maybe_decrypt(Msg, Config) ) of
    {ok, DecodedPayloadType, DecodedPayload} ->
      case DecodedPayloadType of
        digest ->
          self() ! { digestAck, DecodedPayload };
        digestAck ->
          Config#clientConfig.names#clientNames.fsm ! { DecodedPayloadType, DecodedPayload };
        digestSubscribeAck ->
          case is_pid( Config#clientConfig.listener ) of
            true ->
              Config#clientConfig.listener ! { subscribed, { Config#clientConfig.overlay,
                                                DecodedPayload#digestSubscribeAck.event_types,
                                                DecodedPayload#digestSubscribeAck.heartbeat } };
            false ->
              error_logger:info_msg("[EVENT] Subscribed: ~p", [DecodedPayload])
          end;
        digestUnsubscribeAck ->
          case is_pid( Config#clientConfig.listener ) of
            true ->
              Config#clientConfig.listener ! { unsubscribed, { Config#clientConfig.overlay,
                                                DecodedPayload#digestUnsubscribeAck.event_types,
                                                DecodedPayload#digestUnsubscribeAck.heartbeat } };
            false ->
              error_logger:info_msg("[EVENT] Unsubscribed: ~p", [DecodedPayload])
          end;
        digestEvent ->
          case is_pid( Config#clientConfig.listener ) of
            true ->
              Config#clientConfig.listener ! { event, { Config#clientConfig.overlay,
                                                DecodedPayload#digestEvent.event_type,
                                                DecodedPayload#digestEvent.event_object,
                                                DecodedPayload#digestEvent.heartbeat } };
            false ->
              error_logger:info_msg("[EVENT] Event: ~p", [DecodedPayload])
          end;
        digestForwardedAck ->
          case is_pid( Config#clientConfig.listener ) of
            true ->
              Config#clientConfig.listener ! { forwarded_ack, { Config#clientConfig.overlay,
                                                DecodedPayload#digestForwardedAck.name,
                                                DecodedPayload#digestForwardedAck.reply_id } };
            false ->
              error_logger:info_msg("[EVENT] Forwarded ack: ~p", [DecodedPayload])
          end;
        AnyOther ->
          case is_pid( Config#clientConfig.listener ) of
            true ->
              Config#clientConfig.listener ! { unsupported, { Config#clientConfig.overlay, AnyOther } };
            false ->
              error_logger:info_msg("[EVENT] Unsupported: ~p", [AnyOther])
          end
      end;
    { forwardable, UnsupportedDigestType, DigestEnvelopeBin, DigestId } ->
      case is_pid( Config#clientConfig.listener ) of
        true ->
          Config#clientConfig.listener ! { forwarded, { Config#clientConfig.overlay, UnsupportedDigestType, DigestEnvelopeBin, DigestId } };
        false ->
          error_logger:info_msg("[EVENT] Forwarded: ~p", [UnsupportedDigestType])
      end,
      self() ! {  send_digest,
                  digestForwardedAck,
                  #digestForwardedAck{
                    name = Config#clientConfig.name,
                    reply_id = DigestId,
                    secret = Config#clientConfig.secret } };
    {error, Reason} ->
      case is_pid( Config#clientConfig.listener ) of
        true ->
          Config#clientConfig.listener ! { failed, { Config#clientConfig.overlay, Reason } };
        false ->
          error_logger:info_msg("[EVENT] Failed: ~p", [Reason])
      end
  end.

handle_call({ digestExit }, From, { messaging, Config }) ->
  Digest = #digestExit{
    name = Config#clientConfig.name,
    heartbeat = gossiperl_client_common:get_timestamp(),
    secret = Config#clientConfig.secret },
  gen_server:cast(?MESSAGING(Config), { send_digest, digestExit, Digest }),
  gen_server:reply(From, ok),
  {noreply, {messaging, Config}};

handle_call(Message, From, LoopData) ->
  error_logger:info_msg("handle_call: from ~p, message is: ~p", [From, Message]),
  {reply, ok, LoopData}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

terminate(_Reason, LoopData) ->
  {ok, LoopData}.