#include <vcl.h>
#pragma hdrstop

#include "MainForm.h"
#pragma package(smart_init)
#pragma resource "*.dfm"

TFormMain *FormMain;

static const int CellSize = 30;
static const wchar_t* Icons[6] = { L"🍎", L"🍌", L"🍇", L"🥕", L"🥦", L"🌽" };
static const TColor Colors[6] = {
    (TColor)0x006B6BFF, (TColor)0x003DD9FF, (TColor)0x00FF668F,
    (TColor)0x00439FFF, (TColor)0x0057D97E, (TColor)0x0065D3F6
};

__fastcall TFormMain::TFormMain(TComponent* Owner)
    : TForm(Owner)
{
}

void __fastcall TFormMain::FormCreate(TObject *Sender)
{
    DoubleBuffered = true;
    KeyPreview = true;
    Engine.Reset();
    UpdateHud();
}

void TFormMain::UpdateHud() {
    LabelScore->Caption = L"Punkte: " + IntToStr(Engine.GetScore());
    LabelLevel->Caption = L"Level: " + IntToStr(Engine.GetLevel());
    LabelStatus->Caption = Engine.IsGameOver() ? L"Status: Game Over" : L"Status: Läuft";

    int interval = 650 - (Engine.GetLevel() - 1) * 50;
    if (interval < 120) interval = 120;
    TimerDrop->Interval = interval;
}

void TFormMain::DrawCell(int X, int Y, int Value) {
    if (Value < 0 || Value > 5) return;

    int px = X * CellSize;
    int py = Y * CellSize;

    PaintBoxBoard->Canvas->Brush->Color = Colors[Value];
    PaintBoxBoard->Canvas->FillRect(Rect(px + 1, py + 1, px + CellSize - 1, py + CellSize - 1));

    PaintBoxBoard->Canvas->Brush->Color = (TColor)0x00404040;
    PaintBoxBoard->Canvas->FillRect(Rect(px + 4, py + 4, px + CellSize - 4, py + CellSize - 4));

    PaintBoxBoard->Canvas->Font->Name = L"Segoe UI Emoji";
    PaintBoxBoard->Canvas->Font->Size = 11;
    PaintBoxBoard->Canvas->Font->Color = clWhite;
    PaintBoxBoard->Canvas->TextOutW(px + 6, py + 5, Icons[Value]);
}

void __fastcall TFormMain::PaintBoxBoardPaint(TObject *Sender)
{
    const std::vector<std::vector<int> >& board = Engine.GetBoard();

    PaintBoxBoard->Canvas->Brush->Color = (TColor)0x0021130E;
    PaintBoxBoard->Canvas->FillRect(PaintBoxBoard->ClientRect);

    for (int y = 0; y < TFruttiEngine::Rows; y++) {
        for (int x = 0; x < TFruttiEngine::Cols; x++) {
            if (board[y][x] >= 0) {
                DrawCell(x, y, board[y][x]);
            }
            PaintBoxBoard->Canvas->Pen->Color = (TColor)0x00242424;
            PaintBoxBoard->Canvas->Rectangle(x * CellSize, y * CellSize, (x + 1) * CellSize, (y + 1) * CellSize);
        }
    }

    if (!Engine.IsGameOver()) {
        Piece p = Engine.GetActivePiece();
        for (int i = 0; i < 3; i++) {
            int y = p.Y + i;
            if (y >= 0) DrawCell(p.X, y, p.Values[i]);
        }
    }
}

void __fastcall TFormMain::TimerDropTimer(TObject *Sender)
{
    Engine.Tick();
    UpdateHud();
    PaintBoxBoard->Repaint();
}

void __fastcall TFormMain::FormKeyDown(TObject *Sender, WORD &Key, TShiftState Shift)
{
    if (Key == 'R') {
        Engine.Reset();
    } else if (!Engine.IsGameOver()) {
        switch (Key) {
            case VK_LEFT: Engine.MoveLeft(); break;
            case VK_RIGHT: Engine.MoveRight(); break;
            case VK_DOWN: Engine.SoftDrop(); break;
            case VK_UP: Engine.Rotate(); break;
            case VK_SPACE: Engine.HardDrop(); break;
        }
    }

    UpdateHud();
    PaintBoxBoard->Repaint();
}

void __fastcall TFormMain::ButtonResetClick(TObject *Sender)
{
    Engine.Reset();
    UpdateHud();
    PaintBoxBoard->Repaint();
}
