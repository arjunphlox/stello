---
name: brief-style
description: Use when writing a brief, hand-off prompt, sub-agent or Grok task, child-session prompt, CLAUDE.md rule or memory note — any text an agent will act on. Applies the instruction rules of Simplified Technical English (ASD-STE100). Not for social posts, cover letters, portfolio, design-system copy or chat replies.
---
<!-- Synced from arjunphlox/arjun-ai-gems harness/skills/brief-style/SKILL.md @ 8332d4a. Edit it there; this copy is overwritten. -->

# Brief style (from ASD-STE100)

Write agent-facing instructions in the controlled style of [Simplified Technical English](https://github.com/0xpili/simplified-technical-english). Vague or contradictory wording caused most brief failures. Short imperative sentences expose those gaps before the agent starts.

## Rules

1. Use the imperative for steps. Write "Remove the wedge", not "The wedge should be removed".
2. Write one instruction in each sentence.
3. Keep step sentences at 20 words or fewer. Keep descriptive sentences at 25 words or fewer.
4. Use only "must", "can" and "will". Do not use "should", "may", "might" or "would".
5. Use the active voice. Name who does the action.
6. Use one word for one thing. Do not rename a file, gate or component inside a brief.
7. Keep paragraphs to 6 sentences or fewer, with one topic each.
8. Do not use "-ing" verb forms ("ensuring", "checking"). Write the verb as a command.

## Scope

- Apply to: briefs, hand-offs, `/delegate` and `/handoff` output, CLAUDE.md rules, memory notes.
- Do not apply to: social posts, cover letters, portfolio copy, design-system content, chat replies.
- Keep code, paths, commands and quoted text as they are.

## Optional check

Run the upstream checker on a draft (Python 3 only):

    git clone --depth 1 https://github.com/0xpili/simplified-technical-english /tmp/ste
    python3 /tmp/ste/scripts/ste_check.py --mode procedural brief.md

Act on the length, voice, semicolon and helping-verb findings. Treat word-list findings as hints.
