# Stello design tokens (exact)

Port these verbatim into the native theme system. Values are the Radix Colors used by the web app. Each accent + the neutral "sand" scale has a light and a dark palette (steps 1-12, plus an alpha step `a3`). The accent's **step 9** is the primary `--accent`.

Default theme: **mode = dark, accent = amber**.

## Semantic mapping (per active accent)
- `accent`        = `{accent}-9`
- `accentHover`   = `{accent}-10`
- `accentSubtle`  = `{accent}-a3`
- `accentContrast`: lime `#37401c` · amber `#4f3422` · iris `#ffffff`  (fixed, do NOT derive from step-12)
- Neutral text/surfaces use the **sand** scale (e.g. background `sand-1`, subtle `sand-3`, border `sand-6`, secondary text `sand-11`, primary text `sand-12`).

Accent swatch (for the picker dots): lime `#bdee63` · amber `#ffc53d` · iris `#5b5bd6`.

## Sand (neutral)
Light: 1 `#fdfdfc` · 2 `#f9f9f8` · 3 `#f1f0ef` · 4 `#e9e8e6` · 5 `#e2e1de` · 6 `#dad9d6` · 7 `#cfceca` · 8 `#bcbbb5` · 9 `#8d8d86` · 10 `#82827c` · 11 `#63635e` · 12 `#21201c`
Dark:  1 `#111110` · 2 `#191918` · 3 `#222221` · 4 `#2a2a28` · 5 `#31312e` · 6 `#3b3a37` · 7 `#494844` · 8 `#62605b` · 9 `#6f6d66` · 10 `#7c7b74` · 11 `#b5b3ad` · 12 `#eeeeec`

## Lime
Light: 1 `#fcfdfa` · 2 `#f8faf3` · 3 `#eef6d6` · 4 `#e2f0bd` · 5 `#d3e7a6` · 6 `#c2da91` · 7 `#abc978` · 8 `#8db654` · 9 `#bdee63` · 10 `#b0e64c` · 11 `#5c7c2f` · 12 `#37401c` · a3 `#96c80029`
Dark:  1 `#11130c` · 2 `#151a10` · 3 `#1f2917` · 4 `#29371d` · 5 `#334423` · 6 `#3d522a` · 7 `#496231` · 8 `#577538` · 9 `#bdee63` · 10 `#d4ff70` · 11 `#bde56c` · 12 `#e3f7ba` · a3 `#9bfd4c1a`

## Amber (default accent)
Light: 1 `#fefdfb` · 2 `#fefbe9` · 3 `#fff7c2` · 4 `#ffee9c` · 5 `#fbe577` · 6 `#f3d673` · 7 `#e9c162` · 8 `#e2a336` · 9 `#ffc53d` · 10 `#ffba18` · 11 `#ab6400` · 12 `#4f3422` · a3 `#ffde003d`
Dark:  1 `#16120c` · 2 `#1d180f` · 3 `#302008` · 4 `#3f2700` · 5 `#4d3000` · 6 `#5c3d05` · 7 `#714f19` · 8 `#8f6424` · 9 `#ffc53d` · 10 `#ffd60a` · 11 `#ffca16` · 12 `#ffe7b3` · a3 `#fa820022`

## Iris
Light: 1 `#fdfdff` · 2 `#f8f8ff` · 3 `#f0f1fe` · 4 `#e6e7ff` · 5 `#dadcff` · 6 `#cbcdff` · 7 `#b8baf8` · 8 `#9b9ef0` · 9 `#5b5bd6` · 10 `#5151cd` · 11 `#5753c6` · 12 `#272962` · a3 `#0011ee0f`
Dark:  1 `#13131e` · 2 `#171625` · 3 `#202248` · 4 `#262a65` · 5 `#303374` · 6 `#3d3e82` · 7 `#4a4a95` · 8 `#5958b1` · 9 `#5b5bd6` · 10 `#6e6ade` · 11 `#b1a9ff` · 12 `#e0dffe` · a3 `#525bff3b`

## Native notes
- Map mode -> `preferredColorScheme`; pick the light or dark palette accordingly.
- Liquid Glass: prefer system materials (`.regularMaterial`, `Glass` effects) layered over `sand` surfaces; the accent drives identity (header/active states), not whole backgrounds — keep it tasteful on iOS.
- Persist the chosen `{mode, accent}` (e.g. `@AppStorage`); later sync to CloudKit.
