class A3A_RequestMissionDialog : A3A_DefaultDialog
{
  idd = A3A_IDD_REQUESTMISSIONDIALOG;

  class Controls
  {
    class TitlebarText : A3A_TitlebarText
    {
      idc = -1;
      text = $STR_antistasi_dialogs_mission_request_titlebar;
      x = DIALOG_X;
      y = DIALOG_Y - 5 * GRID_H;
      w = DIALOG_W * GRID_W;
      h = 5 * GRID_H;
    };

    // Main content
    class MainContent : A3A_DefaultControlsGroup
    {
      idc = A3A_IDC_REQUESTMISSIONMAIN;

      class Controls
      {
        // Conquest
        class ConquestIcon : A3A_Picture
        {
          idc = -1;
          colorBackground[] = A3A_COLOR_TRANSPARENT;
          text = A3A_Icon_Conquest;
          x = 15 * GRID_W;
          y = 14 * GRID_H;
          w = 16 * GRID_W;
          h = 16 * GRID_H;
        };

        class ConquestButton : A3A_Button
        {
          idc = -1;
          text = $STR_antistasi_dialogs_mission_request_conquest;
          onButtonClick = "closeDialog 0; [""missionButtonClicked"", [""CON""]] call A3A_GUI_fnc_requestMissionDialog;";
          sizeEx = GUI_TEXT_SIZE_LARGE;
          x = 7 * GRID_W;
          y = 34 * GRID_H;
          w = 32 * GRID_W;
          h = 12 * GRID_H;
        };

        // Destroy
        class DestroyIcon : A3A_Picture
        {
          idc = -1;
          colorBackground[] = A3A_COLOR_TRANSPARENT;
          text = A3A_Icon_Destroy;
          x = 53 * GRID_W;
          y = 14 * GRID_H;
          w = 16 * GRID_W;
          h = 16 * GRID_H;
        };

        class DestroyButton : A3A_Button
        {
          idc = -1;
          text = $STR_antistasi_dialogs_mission_request_destroy;
          onButtonClick = "closeDialog 0; [""missionButtonClicked"", [""DES""]] call A3A_GUI_fnc_requestMissionDialog;";
          sizeEx = GUI_TEXT_SIZE_LARGE;
          x = 45 * GRID_W;
          y = 34 * GRID_H;
          w = 32 * GRID_W;
          h = 12 * GRID_H;
        };

        // Assasination
        class AssassinationIcon : A3A_Picture
        {
          idc = -1;
          text = A3A_Icon_Assassination;
          x = 91 * GRID_W;
          y = 14 * GRID_H;
          w = 16 * GRID_W;
          h = 16 * GRID_H;
        };

        class AssassinationButton : A3A_Button
        {
          idc = -1;
          text = $STR_antistasi_dialogs_mission_request_assassination;
          onButtonClick = "closeDialog 0; [""missionButtonClicked"", [""AS""]] call A3A_GUI_fnc_requestMissionDialog;";
          sizeEx = GUI_TEXT_SIZE_LARGE;
          x = 83 * GRID_W;
          y = 34 * GRID_H;
          w = 32 * GRID_W;
          h = 12 * GRID_H;
        };

        // Convoy
        class ConvoyIcon : A3A_Picture
        {
          idc = -1;
          colorBackground[] = A3A_COLOR_TRANSPARENT;
          text = A3A_Icon_Convoy_Ambush;
          x = 129 * GRID_W;
          y = 14 * GRID_H;
          w = 16 * GRID_W;
          h = 16 * GRID_H;
        };

        class ConvoyButton : A3A_Button
        {
          idc = -1;
          text = $STR_antistasi_dialogs_mission_request_convoy;
          onButtonClick = "closeDialog 0; [""missionButtonClicked"", [""CONVOY""]] call A3A_GUI_fnc_requestMissionDialog;";
          sizeEx = GUI_TEXT_SIZE_LARGE;
          x = 121 * GRID_W;
          y = 34 * GRID_H;
          w = 32 * GRID_W;
          h = 12 * GRID_H;
        };

        // Rescue
        class RescueIcon : A3A_Picture
        {
          idc = -1;
          colorBackground[] = A3A_COLOR_TRANSPARENT;
          text = A3A_Icon_Rescue;
          x = 15 * GRID_W;
          y = 56 * GRID_H;
          w = 16 * GRID_W;
          h = 16 * GRID_H;
        };

        class RescueButton : A3A_Button
        {
          idc = -1;
          text = $STR_antistasi_dialogs_mission_request_rescue;
          onButtonClick = "closeDialog 0; [""missionButtonClicked"", [""RES""]] call A3A_GUI_fnc_requestMissionDialog;";
          sizeEx = GUI_TEXT_SIZE_LARGE;
          x = 7 * GRID_W;
          y = 76 * GRID_H;
          w = 32 * GRID_W;
          h = 12 * GRID_H;
        };

        // Logistics
        class LogisticsIcon : A3A_Picture
        {
          idc = -1;
          colorBackground[] = A3A_COLOR_TRANSPARENT;
          text = A3A_Icon_Logistics;
          x = 53 * GRID_W;
          y = 56 * GRID_H;
          w = 16 * GRID_W;
          h = 16 * GRID_H;
        };

        class LogisticsButton : A3A_Button
        {
          idc = -1;
          text = $STR_antistasi_dialogs_mission_request_logistics;
          onButtonClick = "closeDialog 0; [""missionButtonClicked"", [""LOG""]] call A3A_GUI_fnc_requestMissionDialog;";
          sizeEx = GUI_TEXT_SIZE_LARGE;
          x = 45 * GRID_W;
          y = 76 * GRID_H;
          w = 32 * GRID_W;
          h = 12 * GRID_H;
        };

        // Support
        class SupportIcon : A3A_Picture
        {
          idc = -1;
          colorBackground[] = A3A_COLOR_TRANSPARENT;
          text = A3A_Icon_Support;
          x = 91 * GRID_W;
          y = 56 * GRID_H;
          w = 16 * GRID_W;
          h = 16 * GRID_H;
        };

        class SupportButton : A3A_Button
        {
          idc = -1;
          text = $STR_antistasi_dialogs_mission_request_support;
          onButtonClick = "closeDialog 0; [""missionButtonClicked"", [""SUPP""]] call A3A_GUI_fnc_requestMissionDialog;";
          sizeEx = GUI_TEXT_SIZE_LARGE;
          x = 83 * GRID_W;
          y = 76 * GRID_H;
          w = 32 * GRID_W;
          h = 12 * GRID_H;
        };

        // Economy (CHAOS)
        // Row 2 used to hold three buttons centred on the dialog (x 26/64/102) while
        // row 1 held four (x 7/45/83/121). Adding a fourth here means both rows can
        // share row 1's column positions, so the grid finally lines up.
        class EconomyIcon : A3A_Picture
        {
          idc = -1;
          colorBackground[] = A3A_COLOR_TRANSPARENT;
          text = A3A_Icon_Economy;
          x = 129 * GRID_W;
          y = 56 * GRID_H;
          w = 16 * GRID_W;
          h = 16 * GRID_H;
        };

        class EconomyButton : A3A_Button
        {
          idc = -1;
          text = $STR_antistasi_dialogs_mission_request_economy;
          onButtonClick = "closeDialog 0; [""missionButtonClicked"", [""ECON""]] call A3A_GUI_fnc_requestMissionDialog;";
          sizeEx = GUI_TEXT_SIZE_LARGE;
          x = 121 * GRID_W;
          y = 76 * GRID_H;
          w = 32 * GRID_W;
          h = 12 * GRID_H;
        };

      };
    };

    class CloseButton : A3A_CloseButton
    {
      idc = -1;
      x = DIALOG_X + DIALOG_W * GRID_W - 5 * GRID_W;
      y = DIALOG_Y - 5 * GRID_H;
    };
  };
};
