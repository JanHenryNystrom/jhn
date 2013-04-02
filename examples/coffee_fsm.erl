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
%%%   An example coffee FSM using the jhn_server behaviour.
%%%
%%%   Implements the frequency server from "ERLANG Programming" by
%%%   Francesco Cesarini and Simon Thompson ISBN: 0596518188
%%% @end
%%%
%% @author Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%% @copyright (C) 2013, Jan Henry Nystrom <JanHenryNystrom@gmail.com>
%%%-------------------------------------------------------------------
-module(coffee_fsm).
-copyright('Jan Henry Nystrom <JanHenryNystrom@gmail.com>').
-behaviour(jhn_fsm).

%% Management API
-export([start/0, stop/0]).

%% API
-export([coffee/0, tea/0, cancel/0, pay/1, remove_cup/0]).

%% jhn_fsm callbacks
-export([init/1,
         handle_event/3,
%        handle_msg/3,
         terminate/3,
         code_change/4
        ]).

%% jhn_fsm state callbacks
-export([selection/2, payment/2, remove/2]).

%% Records
-record(state, {type, cost, total = 0}).

%%====================================================================
%% Management API
%%====================================================================

%%--------------------------------------------------------------------
%% Function: start() -> {ok, Pid}
%% @doc
%%   Starts the cofee FSM.
%% @end
%%--------------------------------------------------------------------
-spec start() -> {ok, pid()} | ignore | {error, _}.
%%--------------------------------------------------------------------
start() -> jhn_fsm:start(?MODULE, [{name, ?MODULE}]).

%%--------------------------------------------------------------------
%% Function: stop() -> ok
%% @doc
%%   Stops the coffee FSM.
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok.
%%--------------------------------------------------------------------
stop() -> jhn_fsm:call(?MODULE, stop).

%%====================================================================
%% API
%%====================================================================

%%====================================================================
%% jhn_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% Function: coffee() -> ok.
%% @doc
%%   Send a coffee selection event to the FSM.
%% @end
%%--------------------------------------------------------------------
-spec coffee() -> ok.
%%--------------------------------------------------------------------
coffee() -> jhn_fsm:event(?MODULE, {selection, coffee, 100}).

%%--------------------------------------------------------------------
%% Function: tea() -> ok.
%% @doc
%%   Send a tea selection event to the FSM.
%% @end
%%--------------------------------------------------------------------
-spec tea() -> ok.
%%--------------------------------------------------------------------
tea() -> jhn_fsm:event(?MODULE, {selection, tea, 50}).

%%--------------------------------------------------------------------
%% Function: cancel() -> ok.
%% @doc
%%   Send a cancel request event to the FSM.
%% @end
%%--------------------------------------------------------------------
-spec cancel() -> ok.
%%--------------------------------------------------------------------
cancel() -> jhn_fsm:event(?MODULE, cancel).

%%--------------------------------------------------------------------
%% Function: pay(Coin) -> ok.
%% @doc
%%   Send a payment event to the FSM.
%% @end
%%--------------------------------------------------------------------
-spec pay(integer()) -> ok.
%%--------------------------------------------------------------------
pay(Ammount) -> jhn_fsm:event(?MODULE, {pay, Ammount}).

%%--------------------------------------------------------------------
%% Function: remove_cup() -> ok.
%% @doc
%%   Send a cup has been removed event to the FSM.
%% @end
%%--------------------------------------------------------------------
-spec remove_cup() -> ok.
%%--------------------------------------------------------------------
remove_cup() -> jhn_fsm:event(?MODULE, remove_cup).


%%====================================================================
%% jhn_server callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec init(no_arg) -> {ok, atom(), #state{}}.
%%--------------------------------------------------------------------
init(no_arg) ->
    hw_reboot(),
    hw_display("Make your selection.", []),
    {ok, selection, #state{}}.

%%====================================================================
%% jhn_server state callbacks
%%====================================================================

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec selection(_, #state{}) -> {ok, #state{}}.
%%--------------------------------------------------------------------
selection({selection, Type, Cost}, State) ->
    hw_display("Please pay:~p", [Cost]),
    {ok, payment, State#state{type = Type, cost = Cost}};
selection({pay, Ammount}, State) ->
    hw_return(Ammount),
    {ok, selection, State};
selection(cancel, State) ->
    {ok, selection, State};
selection(remove_cup, State) ->
    {ok, selection, State}.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec payment(_, #state{}) -> {ok, #state{}}.
%%--------------------------------------------------------------------
payment({pay, Ammount}, State = #state{cost = Cost, total = Total})
  when Total + Ammount >= Cost ->
    hw_display("Making drink.", []),
    hw_drop_cup(),
    hw_make_drink(State#state.type),
    hw_return((Total + Ammount) - Cost),
    hw_display("Please remove the cup.", []),
    {ok, remove, #state{}};
payment({pay, Ammount}, State = #state{cost = Cost, total = Total}) ->
    NewTotal = Total + Ammount,
    hw_display("Please pay:~p", [Cost - NewTotal]),
    {ok, payment, State#state{total = NewTotal}};
payment(cancel, #state{total = Total}) ->
    hw_return(Total),
    hw_display("Make your selection.", []),
    {ok, selection, #state{}};
payment({selection, _, _}, State) ->
    {ok, payment, State}.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec remove(_, #state{}) -> {ok, #state{}}.
%%--------------------------------------------------------------------
remove(remove_cup, State) ->
    hw_display("Make your selection.", []),
    {ok, selection, State};
remove({pay, Ammount}, State) ->
    hw_return(Ammount),
    {ok, remove, State};
remove({selection, _, _}, State) ->
    {ok, remove, State};
remove(cancel, State) ->
    {ok, remove, State}.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec handle_event(stop, atom(), #state{}) -> {stop, normal}.
%%--------------------------------------------------------------------
handle_event(stop, _StateName, _State) ->
    jhn_fsm:reply(ok),
    {stop, normal}.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec terminate(_, atom(), #state{}) -> _.
%%--------------------------------------------------------------------
terminate(_, payment, #state{total = Total}) ->
    hw_return(Total),
    hw_display("~s", [" "]);
terminate(_, _, _) ->
    hw_display("~s", [" "]).

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec code_change(_, atom(), #state{}, _) -> {ok, atom(), #state{}}.
%%--------------------------------------------------------------------
code_change(_OldVsn, StateName, State, _Extras) ->
    {ok, StateName, State}.

%% ===================================================================
%% Internal functions.
%% ===================================================================

hw_reboot() -> io:format("Reboot~n").

hw_display(Fmt, Args) -> io:format("[" ++ Fmt ++ "]~n", Args).

hw_drop_cup() -> io:format("Drop cup~n").

hw_make_drink(Type) -> io:format("Make:~p~n", [Type]).

hw_return(0) -> ok;

hw_return(Ammount) -> io:format("Return:~p~n", [Ammount]).
