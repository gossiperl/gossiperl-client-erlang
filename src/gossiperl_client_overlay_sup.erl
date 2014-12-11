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

-module(gossiperl_client_overlay_sup).

-behaviour(supervisor).

-export([start_link/1, init/1]).

-include("records.hrl").

%% @doc Start an overlay supervisor.
start_link(Config) ->
  supervisor:start_link({local, ?CLIENT(Config)}, ?MODULE, [Config]).

%% @doc Initialize an overlay supervisor.
init([Config]) ->
  {ok, {{one_for_all, 10, 10}, [
    ?MEMBER( ?ENCRYPTION(Config), gossiperl_client_encryption, Config ),
    ?MEMBER( ?MESSAGING(Config), gossiperl_client_messaging, Config ),
    ?MEMBER( ?FSM(Config), gossiperl_client_fsm, Config ) ]}}.