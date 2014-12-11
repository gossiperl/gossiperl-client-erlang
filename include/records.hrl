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

-ifndef(_gossiperl_client_records_included).
-define(_gossiperl_client_records_included, yeah).

-include("gossiperl_types.hrl").

-record(clientNames, {
          client :: atom(),
          fsm :: atom(),
          messaging :: atom() }).

-record(clientConfig, {
          overlay :: atom(),
          port = 41000 :: integer(),
          name :: binary(),
          secret :: binary(),
          symmetric_key :: binary(),
          iv :: binary(),
          overlay_port = 6666 :: integer(),
          socket :: pid(),
          names :: #clientNames{},
          listener :: pid() | atom() }).

-define(CONFIG_ETS, ets_gossiperl_client_configuration).
-define(AES_PAD(Bin), <<Bin/binary, 0:(( 32 - ( byte_size(Bin) rem 32 ) ) *8 )>>).

-define(FSM(Config), Config#clientConfig.names#clientNames.fsm).
-define(CLIENT(Config), Config#clientConfig.names#clientNames.client).
-define(MESSAGING(Config), Config#clientConfig.names#clientNames.messaging).

-endif.