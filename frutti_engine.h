#ifndef FruttiEngineH
#define FruttiEngineH

#include <vector>
#include <utility>

struct Piece {
    int X;
    int Y;
    int Values[3];
};

class TFruttiEngine {
public:
    static const int Cols = 10;
    static const int Rows = 20;
    static const int ItemCount = 6;

    TFruttiEngine();

    void Reset();
    void Tick();
    void MoveLeft();
    void MoveRight();
    void SoftDrop();
    void HardDrop();
    void Rotate();

    const std::vector<std::vector<int> >& GetBoard() const;
    Piece GetActivePiece() const;
    int GetScore() const;
    int GetLevel() const;
    bool IsGameOver() const;

private:
    std::vector<std::vector<int> > FBoard;
    Piece FActive;
    int FScore;
    int FLevel;
    bool FGameOver;

    int RandomItem() const;
    Piece CreatePiece() const;
    bool Collides(const Piece& PieceRef, int DX, int DY) const;
    void LockPiece();
    void SpawnPiece();
    void SettleAndClear();
    void ApplyGravity();
    std::vector<std::pair<int, int> > FindMatches() const;
};

#endif
