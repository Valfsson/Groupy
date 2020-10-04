-module(gms2).
-export([start/1, start/2]).
-define(timeout, 5000).
-define(arghh, 100).


%% Starts the 1st Node
start(Id) ->
    Rnd = random:uniform(1000),
    Self= self(),
    {ok, spawn_link(fun()-> init(Id, Rnd, Self) end)}.


init(Id, Rnd, Master) ->
    random:seed(Rnd, Rnd, Rnd),
    leader(Id,Master,[], [Master]).


%% Sends requests for other Nodes to join the Group
start(Id, Grp) ->
    Rnd = random:uniform(1000),
    Self= self(),
    {ok, spawn_link(fun()-> init(Id, Grp, Rnd, Self) end)}.


%%
init(Id, Grp, Rnd, Master)->

    random:seed(Rnd, Rnd, Rnd),
    Self= self(),
    Grp ! {join, Master, Self},
    receive
        {view, [Leader|Slaves], Group} ->
            Master ! {view, Group},
            erlang:monitor(process, Leader),
            slave(Id, Master, Leader, Slaves, Group)

    end.


leader(Id, Master, Slaves, Group) ->
    receive

        %% Msg multicasted to all peers and send to application lever (Master)
        {mcast,Msg} ->
            bcast(Id,{msg, Msg}, Slaves),
            Master ! Msg,
            leader(Id, Master, Slaves, Group);

        %% Handles request to join the group
        {join, Wrk, Peer} ->
            Slaves2 = lists:append(Slaves, [Peer]),    %%ordered
            Group2 = lists:append(Group,[Wrk]),
            bcast(Id, {view, [self()|Slaves2], Group2}, Slaves2),
            Master ! {view, Group2},
            leader(Id, Master, Slaves2, Group2);

        stop ->
            ok
    end.

%% Sends message to each of the processes in a list
%%bcast(_Id, Msg, Slaves)->
%%    lists:foreach(fun(Slave)-> Slave ! Msg end, Slaves).
bcast(Id, Msg, Nodes)->
    lists:foreach(fun(Node)-> Node! Msg, crash(Id) end, Nodes).

crash(Id) ->
    case random:uniform(?arghh) of
          ?arghh ->
              io:format("leader ~w: crash~n", [Id]),
              exit(no_luck);
          _ ->
                ok
    end.


%% forwarding messages from Master to the leader and vice verse
%% state is the same as it´s leader but keeps explicit track of the leader

slave(Id, Master, Leader, Slaves, Group) ->
    receive

        %% Handles request from master to multicast msg. Forwards to Leader
        {mcast, Msg} ->
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, Slaves, Group);

        %% Handles request from Master to allow new Node to join the group
        {join, Wrk, Peer} ->
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, Slaves, Group);

        %% Forwards message to the Leader
        {msg, Msg} ->
            Master! Msg,
            slave(Id, Master, Leader, Slaves, Group);

        %% Gets view from the Leader. Delivers vie to Master process
        {view, [Leader|Slaves2], Group2} ->
            Master ! {view, Group2},
            slave(Id, Master, Leader, Slaves2, Group2);

        {'DOWN', _Ref, process, Leader, _Reason} ->
            election(Id, Master, Slaves, Group);

        stop ->
            ok

        after ?timeout ->
            Master ! {error, "no reply from leader"}

    end.

%% Elects new Leader node (1st Node in the Slaves/ Peers list)
election(Id, Master, Slaves, [_|Group])->
    Self=self(),
    case Slaves of
        %%process itself is first in the list. New leader.
        [Self| Rest] ->
            bcast(Id, {view, Slaves, Group}, Rest),
            Master !{view, Group},
            leader(Id, Master, Rest, Group);

        [Leader|Rest]->
              erlang:monitor(process, Leader),
              slave(Id, Master, Leader,Rest, Group)
    end.
