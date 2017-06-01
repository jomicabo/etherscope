-----------------------------------------------------------------------
--  etherscope-display -- Display manager
--  Copyright (C) 2016, 2017 Stephane Carrez
--  Written by Stephane Carrez (Stephane.Carrez@gmail.com)
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
-----------------------------------------------------------------------
with HAL.Bitmap;

with Net;

with UI.Buttons;
with UI.Graphs;
with EtherScope.Stats;
package EtherScope.Display is

   --  Color to draw a separation line.
   Line_Color : HAL.Bitmap.Bitmap_Color := HAL.Bitmap.Blue;

   B_ETHER : constant UI.Buttons.Button_Index := 1;
   B_IPv4  : constant UI.Buttons.Button_Index := 2;
   B_IGMP  : constant UI.Buttons.Button_Index := 3;
   --  B_ICMP  : constant UI.Buttons.Button_Index := 4;
   --  B_UDP   : constant UI.Buttons.Button_Index := 5;
   B_TCP   : constant UI.Buttons.Button_Index := 4;

   Buttons : UI.Buttons.Button_Array (B_ETHER .. B_TCP) :=
     (B_ETHER => (Name => "Ether", State => UI.Buttons.B_PRESSED, others => <>),
      B_IPv4  => (Name => "Proto", others => <>),
      --  B_ICMP  => (Name => "ICMP ", others => <>),
      B_IGMP  => (Name => "IGMP ", others => <>),
      --  B_UDP   => (Name => "UDP  ", others => <>),
      B_TCP   => (Name => "TCP  ", others => <>));

   package Use_Graph is new UI.Graphs (Value_Type => Net.Uint64,
                                       Graph_Size => 1024);
   subtype Graph_Type is Use_Graph.Graph_Type;

   type Graph_Array is array (EtherScope.Stats.Graph_Kind) of Graph_Type;

   Graphs  : Graph_Array;

   --  Initialize the display.
   procedure Initialize;

   --  Draw the layout presentation frame.
   procedure Draw_Frame (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class);

   --  Draw the display buttons.
   procedure Draw_Buttons (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class);

   --  Refresh the graph and draw it.
   procedure Refresh_Graphs (Buffer     : in out HAL.Bitmap.Bitmap_Buffer'Class;
                             Graph_Mode : in EtherScope.Stats.Graph_Kind);

   --  Display devices found on the network.
   procedure Display_Devices (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class);

   --  Display devices found on the network.
   procedure Display_Protocols (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class);

   --  Display TCP/IP information found on the network.
   procedure Display_TCP (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class);

   --  Display IGMP groups found on the network.
   procedure Display_Groups (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class);

   --  Display a performance summary indicator.
   procedure Display_Summary (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class);

end EtherScope.Display;
