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

-module(gossiperl_client_serialization).

-behaviour(gen_server).

-export([start_link/0, stop/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, code_change/3, terminate/2]).

-include("records.hrl").

-record(binary_protocol, {transport,
                          strict_read=true,
                          strict_write=true
                         }).
-record(memory_buffer, {buffer}).

start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() -> gen_server:cast(?MODULE, stop).

init([]) ->
  {ok, OutThriftTransport} = thrift_memory_buffer:new(),
  {ok, OutThriftProtocol} = thrift_binary_protocol:new(OutThriftTransport),
  {ok, {serialization, OutThriftProtocol}}.

handle_call({ serialize, DigestType, Digest }, From, { serialization, OutThriftProtocol }) ->
  gen_server:reply( From, { ok, DigestType, digest_to_binary(
                                              #digestEnvelope{
                                                payload_type = atom_to_list(DigestType),
                                                bin_payload = digest_to_binary( Digest,
                                                                                gossiperl_types:struct_info(DigestType),
                                                                                OutThriftProtocol),
                                                id = uuid:uuid_to_string(uuid:get_v4()) },
                                                gossiperl_types:struct_info(digestEnvelope),
                                                OutThriftProtocol ) } ),
  { noreply, { serialization, OutThriftProtocol } };

handle_call({ serialize, DigestType, Digest, StructInfo, DigestId }, From, { serialization, OutThriftProtocol }) ->
  gen_server:reply( From, { ok, DigestType, digest_to_binary(
                                              #digestEnvelope{
                                                payload_type = atom_to_list(DigestType),
                                                bin_payload = digest_to_binary( Digest, StructInfo, OutThriftProtocol),
                                                id = DigestId },
                                                gossiperl_types:struct_info(digestEnvelope),
                                                OutThriftProtocol ) } ),
  { noreply, { serialization, OutThriftProtocol } };

handle_call({ deserialize, BinaryDigest }, From, { serialization, OutThriftProtocol }) ->
  try
    case digest_from_binary(digestEnvelope, BinaryDigest) of
      {ok, DecodedResult} ->
        case digest_type_as_atom(DecodedResult#digestEnvelope.payload_type) of
          { ok, PayloadTypeAtom } ->
            case digest_from_binary(PayloadTypeAtom, DecodedResult#digestEnvelope.bin_payload) of
              { ok, DecodedResult2 } -> gen_server:reply(From, { ok, PayloadTypeAtom, DecodedResult2});
              _                      -> gen_server:reply(From, {error, DecodedResult})
            end;
          { error, UnsupportedPayloadType } ->
            gen_server:reply(From, { forwardable, UnsupportedPayloadType, BinaryDigest, DecodedResult#digestEnvelope.id })
        end;
      _ -> gen_server:reply(From, {error, BinaryDigest})
    end
  catch
    _:Reason -> gen_server:reply(From, { error, { decode, Reason } })
  end,
  { noreply, { serialization, OutThriftProtocol } }.

handle_cast(stop, LoopData) ->
  {stop, normal, LoopData}.

handle_info(_, LoopData) ->
  {noreply, LoopData}.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

terminate(_Reason, _LoopData) ->
  {ok}.

%% @doc Serializes Erlang term to Thrift
-spec digest_to_binary( term(), term(), term() ) -> binary().
digest_to_binary(Digest, StructInfo, OutThriftProtocol) ->
  {PacketThrift, ok} = thrift_protocol:write(OutThriftProtocol, {{struct, element(2, StructInfo)}, Digest}),
  {protocol, _, OutProtocol} = PacketThrift,
  {transport, _, OutTransport} = OutProtocol#binary_protocol.transport,
  iolist_to_binary(OutTransport#memory_buffer.buffer).

%% @doc Deserializes Thrift data to Erlang term.
-spec digest_from_binary( atom(), binary() ) -> { ok, term() } | { error, not_thrift }.
digest_from_binary(DigestType, BinaryDigest) ->
  {ok, InTransport} = thrift_memory_buffer:new(BinaryDigest),
  {ok, InProtocol} = thrift_binary_protocol:new(InTransport),
  case thrift_protocol:read( InProtocol, {struct, element(2, gossiperl_types:struct_info(DigestType))}, DigestType) of
    {_, {ok, DecodedResult}} ->
      {ok, DecodedResult};
    _ ->
      {error, not_thrift}
  end.

%% @doc Get digest type as atom. Avoid convertion to atoms using erlang functions.
-spec digest_type_as_atom( binary() ) -> { ok, atom() } | { error, binary() }.
digest_type_as_atom(<<"digestError">>)                 -> {ok, digestError};
digest_type_as_atom(<<"digestForwardedAck">>)          -> {ok, digestForwardedAck};
digest_type_as_atom(<<"digest">>)                      -> {ok, digest};
digest_type_as_atom(<<"digestAck">>)                   -> {ok, digestAck};
digest_type_as_atom(<<"digestExit">>)                  -> {ok, digestExit};
digest_type_as_atom(<<"digestSubscribe">>)             -> {ok, digestSubscribe};
digest_type_as_atom(<<"digestUnsubscribe">>)           -> {ok, digestUnsubscribe};
digest_type_as_atom(<<"digestSubscribeAck">>)          -> {ok, digestSubscribeAck};
digest_type_as_atom(<<"digestUnsubscribeAck">>)        -> {ok, digestUnsubscribeAck};
digest_type_as_atom(<<"digestEvent">>)                 -> {ok, digestEvent};
digest_type_as_atom(AnyOther) when is_binary(AnyOther) -> {error, AnyOther}.
