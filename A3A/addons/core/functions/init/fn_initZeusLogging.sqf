/*
    Author: [Killerswin2]
    Description:
        inits the zeus logging.

    Argument:
    None

    Return Value:
    <nil>

    Scope: scheduled
    Environment: client
    Public: no
    Dependencies:


    License: MIT License
*/

#include "..\..\script_component.hpp"
FIX_LINE_NUMBERS()

params ["_curatorModules"];


{
    private _logEventId = [];
    _x addEventHandler ["CuratorFeedbackMessage", {
        params ["_curator", "_errorID"];
        ServerInfo_3("Event: CuratorFeedbackMessage, Curator: %1, STEAMID64: %2, ErrorID: %3",name player,getPlayerUID player,_errorID);
    }];

    _x addEventHandler ["CuratorGroupDoubleClicked", {
        params ["_curator", "_group"];
        ServerInfo_3("Event: CuratorGroupDoubleClicked, Curator: %1, STEAMID64: %2, Group: %3",name player,getPlayerUID player,_group);
    }];

    _x addEventHandler ["CuratorGroupPlaced", {
        params ["_curator", "_group"];
        ServerInfo_3("Event: CuratorGroupPlaced, Curator: %1, STEAMID64: %2, Group: %3",name player,getPlayerUID player,_group);
    }];
/*
    _x addEventHandler ["CuratorGroupSelectionChanged", {
        params ["_curator", "_group"];
        ServerInfo_3("Event: CuratorGroupSelectionChanged, Curator: %1, STEAMID64: %2, Group: %3",name player,getPlayerUID player,_group);
    }];
*/
    _x addEventHandler ["CuratorMarkerDeleted", {
        params ["_curator", "_marker"];
        ServerInfo_3("Event: CuratorMarkerDeleted, Curator: %1, STEAMID64: %2, Marker: %3",name player,getPlayerUID player,_marker);
    }];

    _x addEventHandler ["CuratorMarkerDoubleClicked", {
        params ["_curator", "_marker"];
        ServerInfo_3("Event: CuratorMarkerDoubleClicked, Curator: %1, STEAMID64: %2, Marker: %3",name player,getPlayerUID player,_marker);
    }];

    _x addEventHandler ["CuratorMarkerEdited", {
        params ["_curator", "_marker"];
        ServerInfo_3("Event: CuratorMarkerEdited, Curator: %1, STEAMID64: %2, Marker: %3",name player,getPlayerUID player,_marker);
    }];

    _x addEventHandler ["CuratorMarkerPlaced", {
        params ["_curator", "_marker"];
        ServerInfo_3("Event: CuratorMarkerPlaced, Curator: %1, STEAMID64: %2, Marker: %3",name player,getPlayerUID player,_marker);
    }];
/*
    _x addEventHandler ["CuratorMarkerSelectionChanged", {
        params ["_curator", "_marker"];
        ServerInfo_3("Event: CuratorMarkerSelectionChanged, Curator: %1, STEAMID64: %2, Marker: %3",name player,getPlayerUID player,_marker);
    }];
*/
    _x addEventHandler ["CuratorObjectDeleted", {
        params ["_curator", "_entity"];
        ServerInfo_4("Event: CuratorObjectDeleted, Curator: %1, STEAMID64: %2, Object: %3, Object Type: %4",name player,getPlayerUID player,str str _entity,typeOf _entity);
    }];

    _x addEventHandler ["CuratorObjectDoubleClicked", {
        params ["_curator", "_entity"];
        ServerInfo_4("Event: CuratorObjectDoubleClicked, Curator: %1, STEAMID64: %2, Object: %3, Object Type: %4",name player,getPlayerUID player,str str _entity,typeOf _entity);
    }];

    _x addEventHandler ["CuratorObjectEdited", {
        params ["_curator", "_entity"];
        ServerInfo_4("Event: CuratorObjectEdited, Curator: %1, STEAMID64: %2, Object: %3, Object Type: %4",name player,getPlayerUID player,str str _entity,typeOf _entity);
    }];

    _x addEventHandler ["CuratorObjectPlaced", {
        params ["_curator", "_entity"];
        ServerInfo_4("Event: CuratorObjectPlaced, Curator: %1, STEAMID64: %2, Object: %3, Object Type: %4",name player,getPlayerUID player,str str _entity,typeOf _entity);

        // CHAOS: a utility item that arrives through the curator has never been
        // through A3A_fnc_initObject, so it carries none of Antistasi's state -
        // no A3A_canGarage, no price, and above all none of the scroll actions,
        // which is why a mission container relocated in Zeus loses its menu and
        // never gets it back. The curator places a NEW object; the actions were
        // added to the old one and went with it.
        //
        // Guarded to the curator's own machine: this file installs its handlers
        // on every client for every curator module, and one initObject request
        // per player would be one Error line per player.
        if (_curator isEqualTo getAssignedCuratorLogic player
            && {typeOf _entity in A3A_utilityItemHM}) then {
            // One frame later, so that an object the mission itself created and
            // is about to initialise wins the race and is skipped here.
            [{
                params ["_entity"];
                if (isNull _entity) exitWith {};
                if (!isNil {_entity getVariable "A3A_canGarage"}) exitWith {};
                [_entity] remoteExecCall ["A3A_fnc_initObject", 2];
            }, [_entity], 0] call CBA_fnc_waitAndExecute;
        };
    }];
/*
    _x addEventHandler ["CuratorObjectSelectionChanged", {
        params ["_curator", "_entity"];
        ServerInfo_4("Event: CuratorObjectSelectionChanged, Curator: %1, STEAMID64: %2, Object: %3, Object Type: %4",name player,getPlayerUID player,str str _entity,typeOf _entity);
    }];
*/
/*
    _x addEventHandler ["CuratorPinged", {
        params ["_curator", "_playerPing"];
        ServerInfo_3("Event: CuratorPinged, Curator: %1, STEAMID64: %2, Player: %3",name player,getPlayerUID player,name _playerPing);
    }];
*/
    _x addEventHandler ["CuratorWaypointDeleted", {
        params ["_curator", "_waypoint"];
        ServerInfo_3("Event: CuratorWaypointDeleted, Curator: %1, STEAMID64: %2, Waypoint: %3",name player,getPlayerUID player,_waypoint);
    }];

    _x addEventHandler ["CuratorWaypointDoubleClicked", {
        params ["_curator", "_waypoint"];
        ServerInfo_3("Event: CuratorWaypointDoubleClicked, Curator: %1, STEAMID64: %2, Waypoint: %3",name player,getPlayerUID player,_waypoint);
    }];

    _x addEventHandler ["CuratorWaypointEdited", {
        params ["_curator", "_waypoint"];
        ServerInfo_3("Event: CuratorWaypointEdited, Curator: %1, STEAMID64: %2, Waypoint: %3",name player,getPlayerUID player,_waypoint);
    }];

    _x addEventHandler ["CuratorWaypointPlaced", {
        params ["_curator", "_group", "_waypointID"];
        ServerInfo_4("Event: CuratorWaypointPlaced, Curator: %1, STEAMID64: %2, Group: %3, WaypointID: %4",name player,getPlayerUID player,_group,_waypointID);
    }];
/*
    _x addEventHandler ["CuratorWaypointSelectionChanged", {
        params ["_curator", "_waypoint"];
        ServerInfo_3("Event: CuratorWaypointSelectionChanged, Curator: %1, STEAMID64: %2, Waypoint: %3",name player,getPlayerUID player,_waypoint);
    }];
*/
} forEach _curatorModules;