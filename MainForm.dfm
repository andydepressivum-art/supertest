object FormMain: TFormMain
  Left = 0
  Top = 0
  Caption = 'Frutti-Fall (Borland C++ Builder 6)'
  ClientHeight = 640
  ClientWidth = 520
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  KeyPreview = True
  OldCreateOrder = False
  OnCreate = FormCreate
  OnKeyDown = FormKeyDown
  PixelsPerInch = 96
  TextHeight = 13
  object PaintBoxBoard: TPaintBox
    Left = 8
    Top = 8
    Width = 300
    Height = 600
    OnPaint = PaintBoxBoardPaint
  end
  object LabelScore: TLabel
    Left = 328
    Top = 24
    Width = 80
    Height = 24
    Caption = 'Punkte: 0'
  end
  object LabelLevel: TLabel
    Left = 328
    Top = 56
    Width = 55
    Height = 24
    Caption = 'Level: 1'
  end
  object LabelStatus: TLabel
    Left = 328
    Top = 88
    Width = 95
    Height = 24
    Caption = 'Status: Laeuft'
  end
  object ButtonReset: TButton
    Left = 328
    Top = 128
    Width = 145
    Height = 33
    Caption = 'Neustarten (R)'
    TabOrder = 0
    OnClick = ButtonResetClick
  end
  object TimerDrop: TTimer
    Interval = 650
    OnTimer = TimerDropTimer
    Left = 400
    Top = 192
  end
end
