#include <vcl.h>
#pragma hdrstop

#include <algorithm>
#include <set>
#include <utility>
#include <stdlib.h>
#include <time.h>

#include "frutti_engine.h"

#pragma package(smart_init)

TFruttiEngine::TFruttiEngine() {
    srand((unsigned)time(NULL));
    Reset();
}

void TFruttiEngine::Reset() {
    FBoard.assign(Rows, std::vector<int>(Cols, -1));
    FScore = 0;
    FLevel = 1;
    FGameOver = false;
    SpawnPiece();
}

int TFruttiEngine::RandomItem() const {
    return rand() % 6;
}

Piece TFruttiEngine::CreatePiece() const {
    Piece P;
    P.X = Cols / 2;
    P.Y = -2;
    P.Values[0] = RandomItem();
    P.Values[1] = RandomItem();
    P.Values[2] = RandomItem();
    return P;
}

bool TFruttiEngine::Collides(const Piece& PieceRef, int DX, int DY) const {
    for (int i = 0; i < 3; i++) {
        int nx = PieceRef.X + DX;
        int ny = PieceRef.Y + i + DY;

        if (nx < 0 || nx >= Cols || ny >= Rows) {
            return true;
        }
        if (ny >= 0 && FBoard[ny][nx] != -1) {
            return true;
        }
    }
    return false;
}

void TFruttiEngine::SpawnPiece() {
    FActive = CreatePiece();
    if (Collides(FActive, 0, 0)) {
        FGameOver = true;
    }
}

void TFruttiEngine::LockPiece() {
    for (int i = 0; i < 3; i++) {
        int y = FActive.Y + i;
        if (y < 0) {
            FGameOver = true;
            return;
        }
        FBoard[y][FActive.X] = FActive.Values[i];
    }
    SettleAndClear();
    SpawnPiece();
}

std::vector<std::pair<int, int> > TFruttiEngine::FindMatches() const {
    std::set<std::pair<int, int> > Marked;
    const int dirs[4][2] = { {1,0}, {0,1}, {1,1}, {1,-1} };

    for (int y = 0; y < Rows; y++) {
        for (int x = 0; x < Cols; x++) {
            int value = FBoard[y][x];
            if (value == -1) continue;

            for (int d = 0; d < 4; d++) {
                std::vector<std::pair<int, int> > chain;
                chain.push_back(std::make_pair(x, y));
                int nx = x + dirs[d][0];
                int ny = y + dirs[d][1];
                while (nx >= 0 && nx < Cols && ny >= 0 && ny < Rows && FBoard[ny][nx] == value) {
                    chain.push_back(std::make_pair(nx, ny));
                    nx += dirs[d][0];
                    ny += dirs[d][1];
                }
                if ((int)chain.size() >= 3) {
                    for (size_t i = 0; i < chain.size(); i++) {
                        Marked.insert(chain[i]);
                    }
                }
            }
        }
    }

    return std::vector<std::pair<int, int> >(Marked.begin(), Marked.end());
}

void TFruttiEngine::ApplyGravity() {
    for (int x = 0; x < Cols; x++) {
        std::vector<int> values;
        for (int y = Rows - 1; y >= 0; y--) {
            if (FBoard[y][x] != -1) values.push_back(FBoard[y][x]);
        }
        for (int y = Rows - 1, idx = 0; y >= 0; y--, idx++) {
            if (idx < (int)values.size()) FBoard[y][x] = values[idx];
            else FBoard[y][x] = -1;
        }
    }
}

void TFruttiEngine::SettleAndClear() {
    int combo = 0;
    while (true) {
        std::vector<std::pair<int, int> > matches = FindMatches();
        if (matches.empty()) break;
        combo++;

        for (size_t i = 0; i < matches.size(); i++) {
            FBoard[matches[i].second][matches[i].first] = -1;
        }

        FScore += (int)matches.size() * 10 * combo;
        FLevel = std::max(1, (FScore / 700) + 1);
        ApplyGravity();
    }
}

void TFruttiEngine::Tick() {
    if (FGameOver) return;
    SoftDrop();
}

void TFruttiEngine::MoveLeft() {
    if (!FGameOver && !Collides(FActive, -1, 0)) FActive.X--;
}

void TFruttiEngine::MoveRight() {
    if (!FGameOver && !Collides(FActive, 1, 0)) FActive.X++;
}

void TFruttiEngine::SoftDrop() {
    if (FGameOver) return;
    if (!Collides(FActive, 0, 1)) FActive.Y++;
    else LockPiece();
}

void TFruttiEngine::HardDrop() {
    if (FGameOver) return;
    while (!Collides(FActive, 0, 1)) {
        FActive.Y++;
    }
    LockPiece();
}

void TFruttiEngine::Rotate() {
    if (FGameOver) return;
    int temp = FActive.Values[2];
    FActive.Values[2] = FActive.Values[1];
    FActive.Values[1] = FActive.Values[0];
    FActive.Values[0] = temp;
}

const std::vector<std::vector<int> >& TFruttiEngine::GetBoard() const {
    return FBoard;
}

Piece TFruttiEngine::GetActivePiece() const {
    return FActive;
}

int TFruttiEngine::GetScore() const {
    return FScore;
}

int TFruttiEngine::GetLevel() const {
    return FLevel;
}

bool TFruttiEngine::IsGameOver() const {
    return FGameOver;
}
