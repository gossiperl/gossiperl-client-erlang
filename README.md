# Erlang gossiperl client

This is a **very early** version of the Erlang [gossiperl](https://github.com/radekg/gossiperl) client library.

## Installation

Add this to `rebar.config` file:

    {gossiperl_client, ".*",
      {git, "https://github.com/radekg/gossiperl-client-erlang.git", "master"}},

Run `rebar get-deps`, the application should be installed.

## Running

    application:start(asn1)
    application:start(crypto),
    application:start(public_key),
    application:start(jsx),
    application:start(erlsha2),
    application:start(thrift),
    application:start(quickrand),
    application:start(uuid),
    application:start(lager),
    lager:start(),
    application:start(gossiperl_client).

## Connecting to an overlay

To connect a client to an overlay:

    gossiperl_client_sup:connect( [
              { overlay_name, <<"overlay-name">> },
              { overlay_port, OverlayPort },
              { client_name, <<"client-name">> },
              { client_port, ClientPort },
              { client_secret, <<"client-secret">> },
              { symmetric_key, <<"symmetric-key">> },
              { listener, ListenerPid } ] ).

`listener` option is optional.

A client may be connected to multiple overlays.

## Subscribing / unsubscribing

Subscribing:

    gossiperl_client_sup:subscribe( <<"overlay-name">>,
                                    [ event, event ] ).

Unsubscribing:

    gossiperl_client_sup:unsubscribe( <<"overlay-name">>,
                                      [ event, event ] ).

## Disconnecting from an overlay

    gossiperl_client_sup:disconnect( <<"overlay-name">> ).

This will attempt a graceful exit from an overlay.

## Additional operations

### Checking current client state

    gossiperl_client_sup:check_state( <<"overlay-name">> ).

### Getting the list of current subscriptions

    gossiperl_client_sup:subscriptions( <<"overlay-name">> ).

## Receiving notifications

To receive notifications a connection with the ListenerPid needs to be started. An example is provided with unit tests, in `test/test_listener.erl` file.

## Sending arbitrary digests

    gossiperl_client_sup:send( <<"overlay-name">>, DigestType, DigestData ).

where

- `DigestType` is a digest type atom, other than one of the internally recognised digest types
- `DigestData` is a structure describing Thrift packet, values, types and positions

### Thrift packet structures

An example of a structure describing a simple packet with 2 properties:

- `some_data` of type `string`
- `some_port_number` of type `integer`

    DigestData = [ { some_data, <<"some data to send">>, string, 1 },
                   { some_port_number, 1234, i32, 2 } ].

Each item of the list maps to: `{ field_name, value_to_send, data_type, order }`. Supported Thrift types:

- `bool`
- `byte`
- `double`
- `i16`
- `i32`
- `i64`
- `string`

### Reading custom digests

Once a forwarded message is recieved, it can be read in the following manner (assuming the message presented in the above `DigestData`):

    gossiperl_client_sup:read( DigestType, BinaryEnvelope, DigestInfo ).

Where:

- `DigestType` is an atom representing expected digest type
- `BinaryEnvelope` and envelope received as forwarded message
- `DigestInfo` is a Thrift data structure, example below

    DigestInfo = [ { 1, string },
                   { 2, i32 } ].

## Running tests

    ./rebar clean get-deps compile eunit

Tests assume an overlay with the details specified in the `test/gossiperl_client_test.erl` running.

## License

The MIT License (MIT)

Copyright (c) 2014 Radoslaw Gruchalski <radek@gruchalski.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.