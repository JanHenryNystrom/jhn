%%==============================================================================
%% Copyright 2013 Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%==============================================================================

%%%-------------------------------------------------------------------
%%% @doc
%%%   An example frequency server using the jhn_server behaviour.
%%%
%%%   Implements the frequency server from "ERLANG Programming" by
%%%   Francesco Cesarini and Simon Thompson ISBN: 0596518188
%%% @end
%%%
%% @author Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%% @copyright (C) 2013, Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%%%-------------------------------------------------------------------
-module(frequency).
-copyright('Jan Henry Nystrom <JanHenryNystrom@gmail.com>').
-behaviour(jhn_server).

%% Management API
-export([start/0, stop/0]).

%% API
-export([allocate/0, deallocate/1]).


%% jhn_server callbacks
-export([init/1,
         handle_req/2,
         terminate/2,
         code_change/3
        ]).

%% Records
-record(state, {free = [1, 2, 3, 4, 5] :: [integer()],
                allocated = [] :: integer()
               }).

%%====================================================================
%% Management API
%%====================================================================

%%--------------------------------------------------------------------
%% Function: start() -> {ok, Pid}
%% @doc
%%   Starts the frequency server.
%% @end
%%--------------------------------------------------------------------
-spec start() -> {ok, pid()} | ignore | {error, _}.
%%--------------------------------------------------------------------
start() -> jhn_server:start(?MODULE, [{name, ?MODULE}]).

%%--------------------------------------------------------------------
%% Function: stop() -> ok
%% @doc
%%   Stops the frequency server.
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok.
%%--------------------------------------------------------------------
stop() -> jhn_server:cast(?MODULE, stop).

%%====================================================================
%% API
%%====================================================================

%%--------------------------------------------------------------------
%% Function: allocate() -> {ok, Frequency} | {error, no_frequencies}
%% @doc
%%   Tries to allocate a frequency.
%% @end
%%--------------------------------------------------------------------
-spec allocate() -> {ok, integer()} | {error, no_frequencies}.
%%--------------------------------------------------------------------
allocate() -> jhn_server:call(?MODULE, allocate).

%%--------------------------------------------------------------------
%% Function: deallocate(Frequency) -> ok.
%% @doc
%%   Deallocates a frequency, if it was not allocated a message is sent
%%   to the calling process informing it of the error.
%% @end
%%--------------------------------------------------------------------
-spec deallocate(integer()) -> ok.
%%--------------------------------------------------------------------
deallocate(Freq) -> jhn_server:cast(?MODULE, {deallocate, Freq}).

%%====================================================================
%% jhn_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec init(no_arg) -> jhn_server:init_return(#state{}).
%%--------------------------------------------------------------------
init(no_arg) -> {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec handle_req(allocate | {deallocate, integer()}, #state{}) ->
          jhn_server:return(#state{}).
%%--------------------------------------------------------------------
handle_req(allocate, State = #state{free = []}) ->
    jhn_server:reply({error, no_frequencies}),
    {ok, State};
handle_req(allocate, State = #state{free = [Freq | F], allocated = A}) ->
    jhn_server:reply({ok, Freq}),
    {ok, State#state{free = F, allocated = [Freq | A]}};
handle_req({deallocate, Freq}, State = #state{free = F, allocated = A}) ->
    case lists:member(Freq, A) of
        true ->
            {ok,
             State#state{free = [Freq | F], allocated = lists:delete(Freq, A)}};
        false ->
            jhn_server:reply({?MODULE, error, {not_allocated, Freq}}),
            {ok, State}
    end;
handle_req(stop, _State) ->
    {stop, normal}.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec terminate(_, #state{}) -> ok.
%%--------------------------------------------------------------------
terminate(_Reason, _State) -> ok.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec code_change(_, #state{}, _) -> jhn_server:return(#state{}).
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) -> {ok, State}.
