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

-include_lib("thrift/include/thrift_constants.hrl").
-include_lib("thrift/include/thrift_protocol.hrl").
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
  {ok, {serialization}}.

handle_call({ serialize, digestEnvelope, Digest }, From, { serialization }) ->
  gen_server:reply( From, { ok, digestEnvelope, Digest }),
  { noreply, { serialization } };

handle_call({ serialize, DigestType, Digest }, From, { serialization }) ->
  {ok, OutThriftTransport} = thrift_memory_buffer:new(),
  {ok, OutThriftProtocol} = thrift_binary_protocol:new(OutThriftTransport),
  gen_server:reply( From, { ok, DigestType, digest_to_binary(
                                              #digestEnvelope{
                                                payload_type = atom_to_list(DigestType),
                                                bin_payload = base64:encode(digest_to_binary( Digest,
                                                                                gossiperl_types:struct_info(DigestType),
                                                                                OutThriftProtocol)),
                                                id = uuid:uuid_to_string(uuid:get_v4()) },
                                                gossiperl_types:struct_info(digestEnvelope),
                                                OutThriftProtocol ) } ),
  { noreply, { serialization } };

handle_call({ serialize, DigestType, DigestData, DigestId }, From, { serialization }) ->
  case serialize_arbitrary( DigestType, DigestData ) of
    { ok, BinaryDigest } ->
      Envelope = #digestEnvelope{ payload_type = atom_to_list(DigestType),
                                  bin_payload = base64:encode(BinaryDigest),
                                  id = DigestId },
      {ok, OutThriftTransport} = thrift_memory_buffer:new(),
      {ok, OutThriftProtocol} = thrift_binary_protocol:new(OutThriftTransport),
      gen_server:reply( From, { ok, DigestType, digest_to_binary( Envelope,
                                                                  gossiperl_types:struct_info(digestEnvelope),
                                                                  OutThriftProtocol ) } );
    { error, Reason } ->
      gen_server:reply( From, { error, Reason } )
  end,
  { noreply, { serialization } };

handle_call({ deserialize, BinaryDigest }, From, { serialization }) ->
  try
    case digest_from_binary(digestEnvelope, BinaryDigest) of
      {ok, DecodedResult} ->
        case digest_type_as_atom(DecodedResult#digestEnvelope.payload_type) of
          { ok, PayloadTypeAtom } ->
            case digest_from_binary(PayloadTypeAtom, base64:decode(DecodedResult#digestEnvelope.bin_payload)) of
              { ok, DecodedResult2 } -> gen_server:reply(From, { ok, PayloadTypeAtom, DecodedResult2 });
              _                      -> gen_server:reply(From, { error, DecodedResult })
            end;
          { error, UnsupportedPayloadType } ->
            gen_server:reply(From, { forwardable, UnsupportedPayloadType,
                                                  BinaryDigest,
                                                  DecodedResult#digestEnvelope.id })
        end;
      _ -> gen_server:reply(From, {error, BinaryDigest})
    end
  catch
    _:Reason -> gen_server:reply(From, { error, { decode, Reason } })
  end,
  { noreply, { serialization } };

handle_call({ deserialize, DigestType, BinaryDigest, DigestInfo }, From, { serialization }) when is_atom(DigestType) ->
  try
    case digest_from_binary(digestEnvelope, BinaryDigest) of
      {ok, DecodedEnvelope} ->
        gen_server:reply(From, deserialize_arbitrary( DigestType,
                                                      base64:decode(DecodedEnvelope#digestEnvelope.bin_payload),
                                                      DigestInfo ) );
      _ -> gen_server:reply(From, {error, BinaryDigest})
    end
  catch
    _:Reason -> gen_server:reply(From, { error, { decode, Reason } })
  end,
  { noreply, { serialization } }.

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

%% CUSTOM SERIALIZATION / DESERIALIZATION

%% @doc Deserialize arbitrary digest using provided structure.
-spec deserialize_arbitrary( atom(), binary(), list() ) -> { ok, atom(), term() } | { error, tuple() }.
deserialize_arbitrary( DigestType, Binary, DigestInfo )
  when is_binary(Binary) andalso is_list(DigestInfo)
                         andalso is_atom( DigestType ) ->
  try
    { ok, CustomDigestTrans } = thrift_memory_buffer:new(Binary),
    { ok, CustomDigestProto } = thrift_binary_protocol:new( CustomDigestTrans ),
    { _, { ok, Result } } = thrift_protocol:read( CustomDigestProto, { struct, DigestInfo } ),
    { ok, DigestType, Result }
  catch
    _:Reason ->
      { error, { deserialize_arbitrary, Reason } }
  end.

%% @doc Serialize arbitrary digest.
-spec serialize_arbitrary( atom(), list() ) -> { ok, binary() } | { error, tuple() }.
serialize_arbitrary( DigestType, DigestData )
  when is_atom(DigestType) andalso is_list(DigestData) ->
  try
    { ok, CustomDigestTrans } = thrift_memory_buffer:new(),
    { ok, CustomDigestProto } = thrift_binary_protocol:new( CustomDigestTrans ),
    { CustomDigestProto, ok } = thrift_protocol:write(CustomDigestProto, #protocol_struct_begin{name = DigestType}),
    case serialize_field( DigestData, CustomDigestProto ) of
      { CustomDigestProtoFields, ok } ->
        { CustomDigestProtoFieldsStop, ok } = thrift_protocol:write( CustomDigestProtoFields, field_stop ),
        { CustomDigestProtoFinal, ok } = thrift_protocol:write( CustomDigestProtoFieldsStop, struct_end ),
        {protocol, _, OutProtocol} = CustomDigestProtoFinal,
        {transport, _, OutTransport} = OutProtocol#binary_protocol.transport,
        BinaryDigest = iolist_to_binary(OutTransport#memory_buffer.buffer),
        { ok, BinaryDigest };
      { error, Reason } ->
        { error, Reason }
    end
  catch
    _Error:SerializeErrorReason ->
      { error, { serialization, SerializeErrorReason } }
  end.

%% @doc Serialize single field of a custom digest.
-spec serialize_field( list(), term() ) -> { term(), ok } | { error, tuple() }.
serialize_field([ H | T ], Proto) ->
  try
    { FieldName, Value, Type, Order } = H,
    case serializable_thrift_type( Type ) of
      {ok, ThriftType} ->
        try
          { Proto2, ok } = thrift_protocol:write( Proto, #protocol_field_begin{ name=FieldName, type=ThriftType, id=Order } ),
          { Proto3, ok } = thrift_protocol:write( Proto2, { Type, Value } ),
          { Proto3, ok } = thrift_protocol:write( Proto3, field_end ),
          serialize_field( T, Proto3 )
        catch
          _:Reason ->
            { error, { not_serializable, { FieldName, Value, Reason } } }
        end;
      { error, Reason } ->
        { error, Reason }
    end
  catch
    _:SerializeFieldErrorReason ->
      { error, { field_serialize, H, SerializeFieldErrorReason } }
  end;

serialize_field([], Proto) ->
  { Proto, ok }.

%% @doc Get Thrift type as integer. Only support simple types.
-spec serializable_thrift_type( atom() ) -> { ok, non_neg_integer() } | { error, tuple() }.
serializable_thrift_type( string )   -> { ok, ?tType_STRING };
serializable_thrift_type( byte )     -> { ok, ?tType_BYTE };
serializable_thrift_type( bool )     -> { ok, ?tType_BOOL };
serializable_thrift_type( double )   -> { ok, ?tType_DOUBLE };
serializable_thrift_type( i16 )      -> { ok, ?tType_I16 };
serializable_thrift_type( i32 )      -> { ok, ?tType_I32 };
serializable_thrift_type( i64 )      -> { ok, ?tType_I64 };
serializable_thrift_type( AnyOther ) -> { error, { not_serializable, AnyOther } }.
