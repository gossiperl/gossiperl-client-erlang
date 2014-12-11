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

-export([encode_message/2, decode_message/1, encode_message/3]).

-include("records.hrl").

-record(binary_protocol, {transport,
                          strict_read=true,
                          strict_write=true
                         }).
-record(memory_buffer, {buffer}).

encode_message(DigestType, Digest) ->
  case DigestType of
    digestEnvelope ->
      Digest;
    _ ->
      encode_message( DigestType, Digest, gossiperl_types:struct_info(DigestType) )
  end.

encode_message(DigestType, Digest, StructInfo) ->
  digest_to_binary( #digestEnvelope{
                          payload_type = atom_to_list(DigestType),
                          bin_payload = digest_to_binary(Digest, StructInfo),
                          id = uuid:uuid_to_string(uuid:get_v4()) },
                    gossiperl_types:struct_info(digestEnvelope) ).

decode_message(BinaryDigest) ->
  try
    case digest_from_binary(digestEnvelope, BinaryDigest) of
      {ok, DecodedResult} ->
        case digest_type_as_atom(DecodedResult#digestEnvelope.payload_type) of
          { ok, PayloadTypeAtom } ->
            case digest_from_binary(PayloadTypeAtom, DecodedResult#digestEnvelope.bin_payload) of
              { ok, DecodedResult2 } ->
                { ok, PayloadTypeAtom, DecodedResult2};
              _ ->
                {error, DecodedResult}
            end;
          { error, UnsupportedPayloadType } ->
            { forwardable, UnsupportedPayloadType, BinaryDigest, DecodedResult#digestEnvelope.id }
        end;
      _ ->
        {error, BinaryDigest}
    end
  catch
    _:_ -> { error, decode }
  end.

digest_to_binary(Digest, StructInfo) ->
  {ok, Transport} = thrift_memory_buffer:new(),
  {ok, Protocol} = thrift_binary_protocol:new(Transport),
  {PacketThrift, ok} = thrift_protocol:write (Protocol,
    {{struct, element(2, StructInfo)}, Digest}),
  {protocol, _, OutProtocol} = PacketThrift,
  {transport, _, OutTransport} = OutProtocol#binary_protocol.transport,
  iolist_to_binary(OutTransport#memory_buffer.buffer).

digest_from_binary(DigestType, BinaryDigest) ->
  {ok, InTransport} = thrift_memory_buffer:new(BinaryDigest),
  {ok, InProtocol} = thrift_binary_protocol:new(InTransport),
  case thrift_protocol:read( InProtocol, {struct, element(2, gossiperl_types:struct_info(DigestType))}, DigestType) of
    {_, {ok, DecodedResult}} ->
      {ok, DecodedResult};
    _ ->
      {error, not_thrift}
  end.

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
