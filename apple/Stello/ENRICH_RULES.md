# Stello rule-based tagging (exact port reference)

Verbatim from the web app's `src/lib/enrich-rules.js` + call-site params in `src/lib/supabase.js`. Port to Swift exactly — these are the deterministic, offline baseline tags (also the fallback when Apple Intelligence is unavailable). Match spelling/casing/hyphenation precisely.

## Pipeline (generateTagsFromMetadata)
Order, then sort by weight desc, then **cap to 12** total:
1. **format** tag (1) via `formatTagFor`.
2. **domain** tag (1): `{ name: hostname without leading "www.", category: "domain", weight: 0.6 }`.
3. **subject** mining from **title**: up to 5 — minLen 3, weightStart 0.8, weightStep 0.1, weightFloor 0.5, extraStops = existing tag names.
4. **subject** mining from **description/summary**: up to 3 — minLen 4, weightStart 0.5, weightStep 0, weightFloor 0.5, extraStops = existing names + STOP_WORDS_EXT + PLATFORM_NOISE.
5. **rule enrichment** (tool/style/mood/location) via `runRuleEnrichment` over `title + " " + description`.

## mineSubjectKeywords
- Lowercase the text, match words with regex `[a-zA-Z]{minLen,}` (global).
- Skip: duplicates (already seen), `STOP_WORDS`, `extraStops`, `PLATFORM_NOISE`.
- Weight = `max(weightFloor, round2(weightStart - count * weightStep))`.
- Stop after `limit` kept words. Category = `subject`.

## runRuleEnrichment
Lowercase text. For each table, test `\bpattern\b` (case-insensitive, regex-escaped pattern). Add tag if not already present (dedupe against existing names + added). Weights:
- tool `0.7` · style `0.65` · mood `0.55` · location(text) `0.6`
- TLD fallback: if `domain.endsWith(tld)` add location `0.3`.

## formatTagFor
- No source URL -> `{ text-note, format, 0.4 }`.
- Known host (key = domain without `www.`) -> `{ FORMAT_MAP[host], format, 0.5 }`.
- Else -> `{ website, format, 0.4 }`.

## wordBoundary
Escape regex metacharacters in the pattern, then match `\bESCAPED\b` case-insensitive.

---

## FORMAT_MAP (host -> format)
```
instagram.com=instagram · x.com=tweet · twitter.com=tweet · pinterest.com=pinterest ·
behance.net=behance · dribbble.com=dribbble · youtube.com=youtube · youtu.be=youtube ·
vimeo.com=vimeo · codepen.io=codepen · codesandbox.io=codesandbox · github.com=github ·
medium.com=article · substack.com=article · figma.com=figma · tiktok.com=tiktok ·
linkedin.com=linkedin · reddit.com=reddit · producthunt.com=producthunt · awwwards.com=awwwards ·
are.na=arena · notion.so=notion · notion.site=notion
```

## TOOL_RULES (pattern -> tool, weight 0.7)
```
figma=figma · framer=framer · webflow=webflow · "sketch app"=sketch · "sketch design"=sketch ·
"adobe illustrator"=illustrator · illustrator=illustrator · photoshop=photoshop ·
"after effects"=after-effects · aftereffects=after-effects · premiere=premiere · "final cut"=final-cut-pro ·
procreate=procreate · blender=blender · "cinema 4d"=cinema-4d · cinema4d=cinema-4d · c4d=cinema-4d ·
midjourney=midjourney · "stable diffusion"=stable-diffusion · "dall-e"=dall-e · dalle=dall-e ·
chatgpt=chatgpt · openai=openai · spline=spline · rive=rive · lottie=lottie · gsap=gsap ·
"three.js"=three-js · threejs=three-js · react=react · nextjs=nextjs · "next.js"=nextjs ·
tailwind=tailwind · swift=swift · swiftui=swiftui · visionos=visionos · "vision pro"=vision-pro ·
unity=unity · unreal=unreal-engine · notion=notion · obsidian=obsidian · linear=linear ·
airtable=airtable · zapier=zapier · wordpress=wordpress · shopify=shopify · vercel=vercel ·
supabase=supabase · firebase=firebase · claude=claude · cursor=cursor · "p5.js"=p5-js ·
"d3.js"=d3-js · "anime.js"=anime-js · origami=origami-studio · principle=principle ·
protopie=protopie · marvel=marvel · invision=invision · zeplin=zeplin · github=github ·
lightroom=lightroom · "davinci resolve"=davinci-resolve · capcut=capcut · canva=canva
```

## STYLE_RULES (pattern -> style, weight 0.65)
```
minimalist=minimalist · minimal=minimalist · brutalist=brutalist · editorial=editorial · retro=retro ·
vintage=vintage · futuristic=futuristic · geometric=geometric · organic=organic · flat=flat ·
skeuomorphic=skeuomorphic · neumorphic=neumorphism · glassmorphism=glassmorphism · gradient=gradient ·
monochrome=monochrome · isometric=isometric · 3d=3d · "hand-drawn"=hand-drawn · "hand drawn"=hand-drawn ·
handwritten=handwritten · grunge=grunge · clean=clean · bold=bold · serif=serif · "sans-serif"=sans-serif ·
display=display · script=script · calligraphy=calligraphic · pixel=pixel-art · voxel=voxel ·
wireframe=wireframe · "low-poly"=low-poly · abstract=abstract · swiss=swiss-style · bauhaus=bauhaus ·
"art deco"=art-deco · "art nouveau"=art-nouveau · psychedelic=psychedelic · neon=neon · glitch=glitch ·
halftone=halftone · stipple=stipple · watercolor=watercolor · collage=collage · photorealistic=photorealistic ·
cinematic=cinematic · animated=animated · interactive=interactive · responsive=responsive · modular=modular ·
grid=grid-based · typographic=typographic · experimental=experimental · generative=generative ·
procedural=procedural · parametric=parametric · "data-driven"=data-driven
```

## MOOD_RULES (pattern -> mood, weight 0.55)
```
dark=dark · light=light · vibrant=vibrant · colorful=vibrant · calm=calm · serene=calm · peaceful=calm ·
elegant=elegant · luxurious=luxurious · luxury=luxurious · premium=premium · playful=playful · fun=playful ·
whimsical=whimsical · energetic=energetic · dynamic=dynamic · professional=professional · corporate=corporate ·
friendly=friendly · warm=warm · cool=cool · moody=moody · dramatic=dramatic · mysterious=mysterious ·
dreamy=dreamy · nostalgic=nostalgic · techy=techy · craft=crafted · artisan=crafted · handmade=crafted ·
raw=raw · subtle=subtle · delicate=delicate
```

## LOCATION_RULES (pattern -> location, weight 0.6)
```
tokyo=japan · japan=japan · japanese=japan · india=india · indian=india · mumbai=india · bangalore=india ·
delhi=india · london=uk · british=uk · england=uk · berlin=germany · german=germany · paris=france ·
french=france · "new york"=usa · nyc=usa · "san francisco"=usa · california=usa · "los angeles"=usa ·
seattle=usa · portland=usa · brooklyn=usa · vancouver=canada · toronto=canada · canada=canada ·
amsterdam=netherlands · dutch=netherlands · copenhagen=denmark · danish=denmark · stockholm=sweden ·
swedish=sweden · helsinki=finland · finnish=finland · milan=italy · italian=italy · zurich=switzerland ·
swiss=switzerland · seoul=south-korea · korean=south-korea · singapore=singapore · sydney=australia ·
australian=australia · melbourne=australia · oslo=norway · norwegian=norway · barcelona=spain ·
spanish=spain · lisbon=portugal · portuguese=portugal · prague=czech-republic · jakarta=indonesia ·
bangkok=thailand · dubai=uae · "são paulo"=brazil · "sao paulo"=brazil · brazilian=brazil · mexico=mexico ·
china=china · chinese=china · beijing=china · shanghai=china · taiwan=taiwan · taipei=taiwan
```

## TLD_LOCATION (tld suffix -> location, weight 0.3)
```
.jp=japan · .de=germany · .fr=france · .uk=uk · .co.uk=uk · .it=italy · .nl=netherlands · .se=sweden ·
.dk=denmark · .no=norway · .fi=finland · .ch=switzerland · .kr=south-korea · .au=australia · .br=brazil ·
.mx=mexico · .cn=china · .tw=taiwan · .sg=singapore · .pt=portugal
```

## STOP_WORDS
```
the a an and or but in on at to for of with by from is are was were be been has have had do does did
will would could should may might can this that it its not no so if as into about up out all more also
how what when where who which than then just like over such very your my our their new one two three four
five first last most other some any each every both few many inside story part page view click here see
use using used make made get got know www http https com net org middot nbsp amp quot
```

## STOP_WORDS_EXT (extra stops for description mining)
```
this that with from have been will about more also your their which when what where years building based
tool looking find work best need help want take give keep thing
```

## PLATFORM_NOISE (resolved static set)
```
are awwwards behance codepen codesandbox dribbble figma github instagram linkedin medium notion
pinterest producthunt reddit substack tiktok twitter vimeo x youtube youtu
```

---

### Native notes
- Build a `RuleTagger` struct with these as Swift dictionaries/sets; pure + unit-testable. Keep it the offline baseline AND the fallback for non-Apple-Intelligence devices (Sprint 2b).
- Slug from title (lowercase, spaces->hyphens, strip non-alphanumerics); enforce per-store uniqueness in app logic.
- On capture, status stays `text_done` until 2b advances it via Foundation Models.
