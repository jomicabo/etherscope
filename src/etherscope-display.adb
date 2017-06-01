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
with Ada.Real_Time;

with STM32.Board;
with Bitmapped_Drawing;
with BMP_Fonts;
with Interfaces;
with Net.Utils;
with UI.Texts;

with EtherScope.Analyzer.Ethernet;
with EtherScope.Analyzer.IPv4;
with EtherScope.Analyzer.IGMP;
with EtherScope.Analyzer.TCP;
with EtherScope.Analyzer.Base;
with EtherScope.Receiver;

package body EtherScope.Display is

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use UI.Texts;
   use type Net.Uint16;

   --  Convert the integer to a string without a leading space.
   function Image (Value : in Net.Uint32) return String;
   function Image (Value : in Net.Uint64) return String;
   function Format_Packets (Value : in Net.Uint32) return String;
   function Format_Bytes (Value : in Net.Uint64) return String;
   function Format_Bandwidth (Value : in Net.Uint32) return String;

   --  Kb, Mb, Gb units.
   KB : constant Net.Uint64 := 1024;
   MB : constant Net.Uint64 := KB * KB;
   GB : constant Net.Uint64 := MB * MB;

   Devices   : Analyzer.Base.Device_Stats;
   Protocols : Analyzer.Base.Protocol_Stats;
   Groups    : Analyzer.Base.Group_Stats;
   TCP_Ports : Analyzer.Base.TCP_Stats;

   --  Convert the integer to a string without a leading space.
   function Image (Value : in Net.Uint32) return String is
      Result : constant String := Net.Uint32'Image (Value);
   begin
      return Result (Result'First + 1 .. Result'Last);
   end Image;

   function Image (Value : in Net.Uint64) return String is
      Result : constant String := Net.Uint64'Image (Value);
   begin
      return Result (Result'First + 1 .. Result'Last);
   end Image;

   function Format_Packets (Value : in Net.Uint32) return String is
   begin
      return Net.Uint32'Image (Value);
   end Format_Packets;

   function Format_Bytes (Value : in Net.Uint64) return String is
   begin
      if Value < 10 * KB then
         return Image (Net.Uint32 (Value));
      elsif Value < 10 * MB then
         return Image (Value / KB) & "." & Image (((Value mod KB) * 10) / KB) & "Kb";
      elsif Value < 10 * GB then
         return Image (Value / MB) & "." & Image (((Value mod MB) * 10) / MB) & "Mb";
      else
         return Image (Value / GB) & "." & Image (((Value mod GB) * 10) / GB) & "Gb";
      end if;
   end Format_Bytes;

   function Format_Bandwidth (Value : in Net.Uint32) return String is
   begin
      if Value < Net.Uint32 (KB) then
         return Image (Value);
      elsif Value < Net.Uint32 (MB) then
         return Image (Value / Net.Uint32 (KB)) & "."
           & Image (((Value mod Net.Uint32 (KB)) * 10) / Net.Uint32 (KB)) & "Kbs";
      else
         return Image (Value / Net.Uint32 (MB)) & "."
           & Image (((Value mod Net.Uint32 (MB)) * 10) / Net.Uint32 (MB)) & "Mbs";
      end if;
   end Format_Bandwidth;

   --  ------------------------------
   --  Initialize the display.
   --  ------------------------------
   procedure Initialize is
   begin
      STM32.Board.Display.Initialize;
      STM32.Board.Display.Initialize_Layer (1, HAL.Bitmap.ARGB_1555);

      --  Initialize touch panel
      STM32.Board.Touch_Panel.Initialize;

      for I in Graphs'Range loop
         EtherScope.Display.Use_Graph.Initialize (Graphs (I),
                                                  X      => 100,
                                                  Y      => 200,
                                                  Width  => 380,
                                                  Height => 72,
                                                  Rate   => Ada.Real_Time.Milliseconds (1000));
      end loop;
   end Initialize;

   --  ------------------------------
   --  Draw the layout presentation frame.
   --  ------------------------------
   procedure Draw_Frame (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class) is
   begin
      Buffer.Set_Source (UI.Texts.Background);
      Buffer.Fill;
      Draw_Buttons (Buffer);
      Buffer.Set_Source (Line_Color);
      Buffer.Draw_Vertical_Line (Pt     => (98, 0),
                                 Height => Buffer.Height);
   end Draw_Frame;

   --  ------------------------------
   --  Draw the display buttons.
   --  ------------------------------
   procedure Draw_Buttons (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class) is
   begin
      UI.Buttons.Draw_Buttons (Buffer => Buffer,
                               List   => Buttons,
                               X      => 0,
                               Y      => 0,
                               Width  => 95,
                               Height => 34);
   end Draw_Buttons;

   --  ------------------------------
   --  Refresh the graph and draw it.
   --  ------------------------------
   procedure Refresh_Graphs (Buffer     : in out HAL.Bitmap.Bitmap_Buffer'Class;
                             Graph_Mode : in EtherScope.Stats.Graph_Kind) is
      Now     : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
      Samples : EtherScope.Stats.Graph_Samples;
   begin
      EtherScope.Analyzer.Base.Update_Graph_Samples (Samples, True);
      for I in Samples'Range loop
         Use_Graph.Add_Sample (Graphs (I), Samples (I), Now);
      end loop;
      Use_Graph.Draw (Buffer, Graphs (Graph_Mode));
   end Refresh_Graphs;

   --  ------------------------------
   --  Display devices found on the network.
   --  ------------------------------
   procedure Display_Devices (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class) is
      use EtherScope.Analyzer.Base;

      Y      : Natural := 15;
   begin
      EtherScope.Analyzer.Base.Get_Devices (Devices);
      Buffer.Set_Source (UI.Texts.Background);
      Buffer.Fill_Rect (Area => (Position => (100, 0),
                                 Width  => Buffer.Width - 100,
                                 Height => Buffer.Height));
      for I in 1 .. Devices.Count loop
         declare
            Ethernet : EtherScope.Analyzer.Ethernet.Device_Stats renames Devices.Ethernet (I);
            IP       : EtherScope.Analyzer.IPv4.Device_Stats renames Devices.IPv4 (I);
         begin
            UI.Texts.Draw_String (Buffer, (100, Y), 200, Net.Utils.To_String (Ethernet.Mac));
            UI.Texts.Draw_String (Buffer, (300, Y), 150, Net.Utils.To_String (IP.Ip), RIGHT);
            UI.Texts.Draw_String (Buffer, (100, Y + 20), 100, Format_Packets (Ethernet.Stats.Packets), RIGHT);
            UI.Texts.Draw_String (Buffer, (200, Y + 20), 200, Format_Bytes (Ethernet.Stats.Bytes), RIGHT);
            UI.Texts.Draw_String (Buffer, (400, Y + 20), 80, Format_Bandwidth (Ethernet.Stats.Bandwidth));
         end;
         Buffer.Set_Source (Line_Color);
         Buffer.Draw_Horizontal_Line (Pt    => (100, Y + 45),
                                      Width => Buffer.Width - 100);
         Y := Y + 50;
         exit when Y + 60 >= Buffer.Height;
      end loop;
   end Display_Devices;

   --  ------------------------------
   --  Display devices found on the network.
   --  ------------------------------
   procedure Display_Protocols (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class) is
      use EtherScope.Analyzer.Base;
      procedure Display_Protocol (Name : in String;
                                  Stat : in EtherScope.Stats.Statistics);

      Y      : Natural := 0;

      procedure Display_Protocol (Name : in String;
                                  Stat : in EtherScope.Stats.Statistics) is
      begin
         UI.Texts.Draw_String (Buffer, (100, Y), 150, Name);
         UI.Texts.Draw_String (Buffer, (150, Y), 100, Format_Packets (Stat.Packets), RIGHT);
         UI.Texts.Draw_String (Buffer, (250, Y), 100, Format_Bytes (Stat.Bytes), RIGHT);
         UI.Texts.Draw_String (Buffer, (350, Y), 100, Format_Bandwidth (Stat.Bandwidth), RIGHT);
         Buffer.Set_Source (Line_Color);
         Buffer.Draw_Horizontal_Line (Pt    => (100, Y + 23),
                                      Width => Buffer.Width - 100);
         Y := Y + 30;
      end Display_Protocol;

   begin
      EtherScope.Analyzer.Base.Get_Protocols (Protocols);
      Buffer.Set_Source (UI.Texts.Background);
      Buffer.Fill_Rect (Area => (Position => (100, 0),
                                 Width  => Buffer.Width - 100,
                                 Height => Buffer.Height));

      --  Draw some column header.
      UI.Texts.Draw_String (Buffer, (100, Y), 150, "Protocol");
      UI.Texts.Draw_String (Buffer, (150, Y), 100, "Packets", RIGHT);
      UI.Texts.Draw_String (Buffer, (250, Y), 100, "Bytes", RIGHT);
      UI.Texts.Draw_String (Buffer, (350, Y), 100, "BW", RIGHT);
      Buffer.Set_Source (Line_Color);
      Buffer.Draw_Horizontal_Line (Pt    => (100, Y + 14),
                                   Width => Buffer.Width - 100);
      Y := Y + 18;

      UI.Texts.Foreground := HAL.Bitmap.Green;
      Display_Protocol ("ICMP", Protocols.ICMP);
      Display_Protocol ("IGMP", Protocols.IGMP);
      Display_Protocol ("UDP", Protocols.UDP);
      Display_Protocol ("TCP", Protocols.TCP);

      Display_Protocol ("Others", Protocols.Unknown);
      UI.Texts.Foreground := HAL.Bitmap.White;
   end Display_Protocols;

   --  ------------------------------
   --  Display IGMP groups found on the network.
   --  ------------------------------
   procedure Display_Groups (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class) is
      use EtherScope.Analyzer.Base;
      procedure Display_Group (Group : in EtherScope.Analyzer.IGMP.Group_Stats);

      Y : Natural := 0;

      procedure Display_Group (Group : in EtherScope.Analyzer.IGMP.Group_Stats) is
      begin
         UI.Texts.Draw_String (Buffer, (105, Y), 175, Net.Utils.To_String (Group.Ip));
         UI.Texts.Draw_String (Buffer, (180, Y + 30), 100, Format_Packets (Group.UDP.Packets), RIGHT);
         UI.Texts.Draw_String (Buffer, (280, Y + 30), 100, Format_Bytes (Group.UDP.Bytes), RIGHT);
         UI.Texts.Draw_String (Buffer, (380, Y), 100, Format_Bandwidth (Group.UDP.Bandwidth), RIGHT);
         Buffer.Set_Source (Line_Color);
         Buffer.Draw_Horizontal_Line (Pt    => (100, Y + 55),
                                      Width => Buffer.Width - 100);
         Y := Y + 60;
      end Display_Group;

   begin
      EtherScope.Analyzer.Base.Get_Groups (Groups);
      Buffer.Set_Source (UI.Texts.Background);
      Buffer.Fill_Rect (Area => (Position => (100, 0),
                                 Width  => Buffer.Width - 100,
                                 Height => Buffer.Height));

      --  Draw some column header.
      UI.Texts.Draw_String (Buffer, (105, Y), 175, "IP");
      UI.Texts.Draw_String (Buffer, (180, Y), 100, "Packets", RIGHT);
      UI.Texts.Draw_String (Buffer, (280, Y), 100, "Bytes", RIGHT);
      UI.Texts.Draw_String (Buffer, (380, Y), 100, "Bandwidth", RIGHT);
      Buffer.Set_Source (Line_Color);
      Buffer.Draw_Horizontal_Line (Pt    => (100, Y + 14),
                                   Width => Buffer.Width - 100);
      Y := Y + 18;

      UI.Texts.Foreground := HAL.Bitmap.Green;
      for I in 1 .. Groups.Count loop
         Display_Group (Groups.Groups (I));
         exit when Y + 60 >= Buffer.Height;
      end loop;
      UI.Texts.Foreground := HAL.Bitmap.White;
   end Display_Groups;

   --  ------------------------------
   --  Display TCP/IP information found on the network.
   --  ------------------------------
   procedure Display_TCP (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class) is
      use EtherScope.Analyzer.Base;
      procedure Display_Port (Port : in EtherScope.Analyzer.TCP.TCP_Stats);

      Y : Natural := 0;

      procedure Display_Port (Port : in EtherScope.Analyzer.TCP.TCP_Stats) is
      begin
         --  Ok, this is a simple port lookup conversion!
         if Port.Port = 80 then
            UI.Texts.Draw_String (Buffer, (105, Y), 175, "http");
         elsif Port.Port = 25 then
            UI.Texts.Draw_String (Buffer, (105, Y), 175, "smtp");
         elsif Port.Port = 443 then
            UI.Texts.Draw_String (Buffer, (105, Y), 175, "https");
         elsif Port.Port = 22 then
            UI.Texts.Draw_String (Buffer, (105, Y), 175, "ssh");
         else
            UI.Texts.Draw_String (Buffer, (105, Y), 175, Image (Net.Uint32 (Port.Port)));
         end if;
         UI.Texts.Draw_String (Buffer, (180, Y), 100, Format_Packets (Port.TCP.Packets), RIGHT);
         UI.Texts.Draw_String (Buffer, (280, Y), 100, Format_Bytes (Port.TCP.Bytes), RIGHT);
         UI.Texts.Draw_String (Buffer, (380, Y), 100, Format_Bandwidth (Port.TCP.Bandwidth), RIGHT);
         Buffer.Set_Source (Line_Color);
         Buffer.Draw_Horizontal_Line (Pt    => (100, Y + 25),
                                      Width => Buffer.Width - 100);
         Y := Y + 30;
      end Display_Port;

   begin
      EtherScope.Analyzer.Base.Get_TCP (TCP_Ports);
      Buffer.Set_Source (UI.Texts.Background);
      Buffer.Fill_Rect (Area  => (Position => (100, 0),
                                  Width  => Buffer.Width - 100,
                                  Height => Buffer.Height));

      --  Draw some column header.
      UI.Texts.Draw_String (Buffer, (105, Y), 175, "TCP Port");
      UI.Texts.Draw_String (Buffer, (180, Y), 100, "Packets", RIGHT);
      UI.Texts.Draw_String (Buffer, (280, Y), 100, "Bytes", RIGHT);
      UI.Texts.Draw_String (Buffer, (380, Y), 100, "Bandwidth", RIGHT);
      Buffer.Set_Source (Line_Color);
      Buffer.Draw_Horizontal_Line (Pt    => (100, Y + 14),
                                   Width => Buffer.Width - 100);
      Y := Y + 18;

      UI.Texts.Foreground := HAL.Bitmap.Green;
      UI.Texts.Draw_String (Buffer, (105, Y), 175, "All");
      UI.Texts.Draw_String (Buffer, (180, Y), 100, Format_Packets (TCP_Ports.TCP.Packets), RIGHT);
      UI.Texts.Draw_String (Buffer, (280, Y), 100, Format_Bytes (TCP_Ports.TCP.Bytes), RIGHT);
      UI.Texts.Draw_String (Buffer, (380, Y), 100, Format_Bandwidth (TCP_Ports.TCP.Bandwidth), RIGHT);

      Buffer.Set_Source (Line_Color);
      Buffer.Draw_Horizontal_Line (Pt    => (100, 25),
                                   Width => Buffer.Width - 100);
      Y := Y + 30;

      for I in 1 .. TCP_Ports.Count loop
         Display_Port (TCP_Ports.Ports (I));
         exit when Y + 30 >= Buffer.Height;
      end loop;
      UI.Texts.Foreground := HAL.Bitmap.White;
   end Display_TCP;

   use Ada.Real_Time;
   Prev_Time : Ada.Real_Time.Time := Ada.Real_Time.Clock;
   Deadline  : Ada.Real_Time.Time := Prev_Time + Ada.Real_Time.Seconds (1);
   Speed      : Net.Uint32 := 0;
   Bandwidth  : Natural := 0;
   Pkts       : Net.Uint32 := 0;
   Bytes      : Net.Uint64 := 0;
   ONE_MS : constant Ada.Real_Time.Time_Span := Ada.Real_Time.Milliseconds (1);

   --  ------------------------------
   --  Display a performance summary indicator.
   --  ------------------------------
   procedure Display_Summary (Buffer : in out HAL.Bitmap.Bitmap_Buffer'Class) is
      Now       : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
      Cur_Pkts  : Net.Uint32;
      Cur_Bytes : Net.Uint64;
      D         : Net.Uint32;
      C         : Net.Uint32;
   begin
      if Deadline < Now then
         Cur_Bytes := EtherScope.Receiver.Ifnet.Rx_Stats.Bytes;
         Cur_Pkts  := EtherScope.Receiver.Ifnet.Rx_Stats.Packets;
         C := Net.Uint32 ((Now - Prev_Time) / ONE_MS);
         D := Net.Uint32 (Cur_Pkts - Pkts);
         Speed := Net.Uint32 (D * 1000) / C;
         Bandwidth := Natural (((Cur_Bytes - Bytes) * 8000) / Net.Uint64 (C));
         Prev_Time := Now;
         Deadline := Deadline + Ada.Real_Time.Seconds (1);
         Pkts := Cur_Pkts;
         Bytes := Cur_Bytes;
      end if;
      Buffer.Set_Source (UI.Texts.Background);
      Buffer.Fill_Rect (Area  => (Position => (0, 160),
                                  Width  => 99,
                                  Height => Buffer.Height - 160));

      Bitmapped_Drawing.Draw_String
           (Buffer,
            Start      => (3, 220),
            Msg        => "pkts/s",
            Font       => BMP_Fonts.Font12x12,
            Foreground => UI.Texts.Foreground,
            Background => UI.Texts.Background);

      Bitmapped_Drawing.Draw_String
           (Buffer,
            Start      => (3, 160),
            Msg        => "bps",
            Font       => BMP_Fonts.Font12x12,
            Foreground => UI.Texts.Foreground,
            Background => UI.Texts.Background);

      Bitmapped_Drawing.Draw_String
           (Buffer,
            Start      => (0, 250),
            Msg        => Image (Speed),
            Font       => BMP_Fonts.Font16x24,
            Foreground => UI.Texts.Foreground,
            Background => UI.Texts.Background);

      Bitmapped_Drawing.Draw_String
           (Buffer,
            Start      => (0, 180),
            Msg        => Format_Bandwidth (Interfaces.Unsigned_32 (Bandwidth)),
            Font       => BMP_Fonts.Font16x24,
            Foreground => UI.Texts.Foreground,
            Background => UI.Texts.Background);
   end Display_Summary;

end EtherScope.Display;
