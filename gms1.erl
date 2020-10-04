-module(gms1).

-export([start/1, start/2]).


%% starting a single node
%% adding of more nodes
%%

%% Starts the 1st Node
start(Id)->
    Self= self(),
    {ok, spawn_link(fun()-> init(Id, Self) end)}.


init(Id, Master)->
    leader(Id,Master,[], [Master]).


%% Sends requests for other Nodes to join the Group
start(Id, Grp)->
    Self= self(),
    {ok, spawn_link(fun()-> init(Id, Grp, Self) end)}.


%%
init(Id, Grp, Master)->
    Self= self(),
    Grp ! {join, Master, Self},
    receive
        {view, [Leader|Slaves], Group}->
            Master ! {view, Group},
            slave(Id, Master, Leader, Slaves, Group)
    end.


leader(Id, Master, Slaves, Group)->
    receive

        %% Msg multicasted to all peers and send to application lever (Master)
        {mcast,Msg}->
            bcast(Id,{msg, Msg}, Slaves),
            Master ! Msg,
            leader(Id, Master, Slaves, Group);

        %% Handles request to join the group
        {join, Wrk, Peer}->
            Slaves2 = lists:append(Slaves, [Peer]),    %%ordered
            Group2 = lists:append(Group,[Wrk]),
            bcast(Id, {view, [self()|Slaves2], Group2}, Slaves2),
            Master ! {view, Group2},
            leader(Id, Master, Slaves2, Group2);

        stop->
            ok
    end.

%% Sends message to each of the processes in a list
bcast(_Id, Msg, Slaves)->
    lists:foreach(fun(Slave)-> Slave ! Msg end, Slaves).

%% forwarding messages from Master to the leader and vice verse
%% state is the same as it´s leader but keeps explicit track of the leader

slave(Id, Master, Leader, Slaves, Group) ->
    receive

        %% Handles request from master to multicast msg. Forwards to Leader
        {mcast, Msg}->
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, Slaves, Group);

        %% Handles request from Master to allow new Node to join the group
        {join, Wrk, Peer}->
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, Slaves, Group);

        %% Forwards message to the Leader
        {msg, Msg}->
            Master! Msg,
            slave(Id, Master, Leader, Slaves, Group);

        %% Gets view from the Leader. Delivers vie to Master process
        {view, [Leader|Slaves2], Group2}->
            Master ! {view, Group2},
            slave(Id, Master, Leader, Slaves2, Group2);

        stop->
            ok
    end.
