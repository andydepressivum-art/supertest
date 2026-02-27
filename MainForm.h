#ifndef MainFormH
#define MainFormH

#include <Classes.hpp>
#include <Controls.hpp>
#include <StdCtrls.hpp>
#include <Forms.hpp>
#include <ExtCtrls.hpp>
#include <Graphics.hpp>

#include "frutti_engine.h"

class TFormMain : public TForm
{
__published:
    TPaintBox *PaintBoxBoard;
    TTimer *TimerDrop;
    TLabel *LabelScore;
    TLabel *LabelLevel;
    TLabel *LabelStatus;
    TButton *ButtonReset;
    void __fastcall FormCreate(TObject *Sender);
    void __fastcall TimerDropTimer(TObject *Sender);
    void __fastcall PaintBoxBoardPaint(TObject *Sender);
    void __fastcall FormKeyDown(TObject *Sender, WORD &Key, TShiftState Shift);
    void __fastcall ButtonResetClick(TObject *Sender);
private:
    TFruttiEngine Engine;
    void UpdateHud();
    void DrawCell(int X, int Y, int Value);
public:
    __fastcall TFormMain(TComponent* Owner);
};

extern PACKAGE TFormMain *FormMain;

#endif
