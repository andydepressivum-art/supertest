# Frutti-Fall fuer Borland C++ Builder 6.0

Diese Version ist gezielt fuer **Borland C++ Builder 6.0 (VCL, ANSI)** geschrieben.

## Was wurde fuer BCB6 angepasst?

- Kein Unicode-/Emoji-Rendering mehr (BCB6 ist ANSI-basiert): statt Emojis werden kurze Symbol-Codes gezeichnet (`AP`, `BA`, `GR`, `CA`, `BR`, `CO`).
- `WinMain`-Entry-Point ohne neuere VCL-Eigenschaften.
- BCB6-kompatibler Code-Stil ohne moderne Sprachfeatures.

## Projektdateien

- `FruttiFall.bpr` - BCB6-Projektdatei (direkt in der IDE oeffnen)
- `FruttiFall.cpp` - Einstiegspunkt
- `MainForm.h/.cpp/.dfm` - VCL-Form, Rendering, Eingaben, HUD
- `frutti_engine.h/.cpp` - Spiel-Engine (Tetris/Columns-Hybrid)

## In Borland C++ Builder 6.0 verwenden

1. C++ Builder 6 starten.
2. **File -> Open Project...** und `FruttiFall.bpr` oeffnen.
3. Falls noetig Suchpfade pruefen (`Project -> Options`).
4. Build + Run.

## Steuerung

- `Pfeil links/rechts`: bewegen
- `Pfeil runter`: Soft Drop
- `Pfeil hoch`: Reihenfolge rotieren
- `Leertaste`: Hard Drop
- `R`: Neustart

## Regeln

- Fallende Teile bestehen aus 3 Symbolen.
- 3+ gleiche Symbole in horizontaler, vertikaler oder diagonaler Linie werden entfernt.
- Danach wirkt Gravitation (Ketten moeglich).
- Punkte erhoehen das Level, hoehere Level erhoehen die Fallgeschwindigkeit.
