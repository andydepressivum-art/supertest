# Frutti-Fall für Borland/Embarcadero C++ Builder

Dieses Projekt wurde von der Browser-Version auf eine **C++-Builder (VCL)**-Version umgestellt.

## Inhalt

- `FruttiFall.cpp` – Projekt-Entry-Point
- `MainForm.h/.cpp/.dfm` – VCL-UI (Spielfeld, HUD, Timer, Eingaben)
- `frutti_engine.h/.cpp` – Spiel-Engine (Tetris/Columns-Hybrid mit Obst & Gemüse)

## In C++ Builder öffnen

1. Starte Borland/Embarcadero C++ Builder (VCL).
2. Erstelle ein neues **VCL Forms Application**-Projekt.
3. Ersetze die erzeugten Form-Dateien durch `MainForm.h/.cpp/.dfm`.
4. Ersetze/ergänze die `Project1.cpp` mit `FruttiFall.cpp`.
5. Füge `frutti_engine.h/.cpp` zum Projekt hinzu.
6. Build + Run.

## Steuerung

- `←` / `→`: bewegen
- `↓`: Soft Drop
- `↑`: Reihenfolge rotieren
- `Space`: Hard Drop
- `R`: Neustart

## Regeln

- Fallende Teile bestehen aus 3 Symbolen.
- 3+ gleiche Symbole in horizontaler, vertikaler oder diagonaler Linie werden entfernt.
- Danach wirkt Gravitation (Ketten möglich).
- Punkte erhöhen das Level, höhere Level erhöhen die Fallgeschwindigkeit.
