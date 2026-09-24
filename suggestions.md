# MusicAI - UX & Feature Suggestions

Analysis of the current codebase (2 tabs: **Create Playlist** and **Mash Up**, Claude or Apple Intelligence as the generator, MusicKit for matching and saving playlists). Target: iOS 27, SwiftUI, `@Observable`, MainActor-by-default.

Suggestions are grouped by priority. Each item notes *why* it matters and *where* in the code it applies.

---

## TL;DR - Top 10

| # | Suggestion | Impact | Effort |
|---|-----------|--------|--------|
| 1 | Add a **review step** before saving to Apple Music (remove, reorder, rename, then "Save") | Very high | Medium |
| 2 | **Stream results** so songs appear one by one instead of a long spinner | Very high | Medium |
| 3 | **Preview playback** (tap a song to hear it) + "Open in Apple Music" after saving | High | Low-Medium |
| 4 | **Resolve songs in parallel** (currently 15 sequential catalog searches) | High | Low |
| 5 | **Replace unmatched songs** automatically or with one tap | High | Medium |
| 6 | **History** of generated playlists (SwiftData) so results survive tab switches | High | Medium |
| 7 | **Refine / iterate** ("more upbeat", "no English songs", "more like #4") | High | Medium |
| 8 | **Empty state with prompt ideas** + recent prompts on the Create tab | Medium | Low |
| 9 | **Friendlier errors + first-run setup** (no key, no subscription, AI unavailable) | Medium | Low |
| 10 | Move the **API key to Keychain** | Medium (security) | Low |

---

## 1. Core flow UX (highest impact)

### 1.1 Don't auto-save - add a review step
**Today:** Tapping *Generate* immediately creates a playlist in the user's library (`CreatePlaylistView.swift:211`, `MashUpView.swift:439`). Every retry creates *another* playlist, so the library fills with near-duplicates, and users can't drop songs they dislike.

**Suggest:**
- Split into two phases: **Generate** → review list → **Save to Apple Music**.
- In review: swipe to delete, drag to reorder (`List` + `.onMove`/`.onDelete`), tap to swap a song.
- Editable playlist name (pre-filled, e.g. `🎵 Tropical Cumbia Jazz`, title-cased and truncated). Today the name is the raw prompt, which can be multi-line (`MusicKitService.swift:40`).
- Song count picker (10 / 15 / 25 / 50) instead of a hardcoded 15 (`ClaudeService.swift:33`, `FoundationModelsService.swift:6`, `SongMetadata.swift:27`). Note Claude's `max_tokens: 2048` will need to scale with the count.

### 1.2 Stream results progressively
**Today:** The user stares at "Asking Claude…" for the full generation, then all 15 rows pop in, then another wait for matching.

**Suggest:**
- **Apple Intelligence:** use `session.streamResponse(to:generating:)` - `GeneratedPlaylist.PartiallyGenerated` lets you render songs as they arrive.
- **Claude:** use `"stream": true` (SSE) and parse songs incrementally, or at minimum show skeleton rows (`.redacted(reason: .placeholder)`) while waiting.
- Start the MusicKit search for each song as soon as it arrives, so matching overlaps with generation.

### 1.3 Preview playback and open in Apple Music
- Tap a row to play a 30s preview (`song.previewAssets` with `AVPlayer`) or full playback via `ApplicationMusicPlayer.shared` for subscribers.
- "Play all" button on the results header.
- After saving, turn the success banner (`CreatePlaylistView.swift:134`) into an actionable card: **Open in Apple Music** (`playlist.url`), **Play**, **Share** (`ShareLink`).

### 1.4 Handle unmatched and mis-matched songs
**Today:** Unmatched rows are struck through. Worse, `searchSong` falls back to `response.songs.first` (`MusicKitService.swift:109`), so a *different* song by a *different* artist can be silently added to the playlist.

**Suggest:**
- Three states per row: **exact match**, **close match** (show the actual matched title/artist so the user can accept/reject), **not found**.
- Only accept the fallback if the artist matches; otherwise mark "close match".
- Normalize titles before comparing (strip `(feat. …)`, `- Remastered 2011`, punctuation, diacritics).
- **"Replace missing songs"** button: send the unmatched titles back to the model ("these weren't available, give N alternatives, excluding: …") and re-resolve just those.
- Per-row context menu: *Replace this song*, *More like this*, *Remove*.

### 1.5 Cancellation and input polish
- Store the generation `Task` and show a **Cancel** button while generating; cancel on disappear. Today, closing `SongDetailSheet` mid-generation still creates the playlist.
- `.onSubmit { generate() }` + `.submitLabel(.go)` on the prompt field, and dismiss the keyboard on generate (`@FocusState`).
- Haptics: `.sensoryFeedback(.success, trigger: successPlaylistName)` and `.error` on failure.

---

## 2. Onboarding, settings & errors

### 2.1 First-run experience
Today a new user with no API key and Apple Intelligence off only finds out after tapping Generate. Suggest:
- A short onboarding (or inline card) that detects state: *Apple Intelligence available?* → default to it; otherwise prompt for a Claude key with a link to the Anthropic Console.
- Check **Apple Music subscription** up front with `MusicSubscription.current` (`canPlayCatalogContent`, `hasCloudLibraryEnabled`). Creating playlists requires cloud library; present `.musicSubscriptionOffer(isPresented:)` when missing instead of a generic error.
- Request MusicKit authorization once, with an explanation screen, rather than inside every generate call (it's currently requested twice per generation: `CreatePlaylistView.swift:187` and again in `MusicKitService.swift:36`).

### 2.2 Settings
- Settings is only reachable from the Create tab (`CreatePlaylistView.swift:36`). Put it on both tabs, or make it a third tab.
- Auto-fallback: if Apple Intelligence is unavailable but a Claude key exists (or vice versa), fall back automatically and tell the user.
- **"Test key"** button that makes a cheap request and shows ✓/✗.
- Make the provider a single segmented choice (Apple Intelligence / Claude) instead of a toggle plus greyed-out sections - clearer mental model.
- Keep the model list current. Consider exposing the latest models (e.g. Sonnet 5 / Haiku 4.5) and moving model IDs to one place so updates are one-line changes (`SettingsManager.swift:3`).

### 2.3 Friendly error messages
- `ClaudeError.httpError` shows the raw body (`ClaudeService.swift:15`), e.g. `HTTP 401: {"type":"error",...}`. Map common codes: 401 → "Your API key looks invalid", 429 → "Rate limited, try again in a moment", 529/5xx → "Claude is busy", offline (`URLError.notConnectedToInternet`) → "You're offline - try Apple Intelligence".
- Add a **Retry** button to error banners.
- `PlaylistSongsView.loadSongs` swallows errors and shows "This playlist has no songs" (`MashUpView.swift:174`) - show the real error instead.

---

## 3. Mash Up tab

### 3.1 Make it a real mash-up
The tab is currently "seed from one song". The name promises blending. Suggest:
- **Multi-seed:** pick 2-5 songs (from any playlist or a library search) and blend them: "Latin jazz seed + 90s trip-hop seed".
- **Playlist blend:** pick two playlists → generate a bridge playlist that transitions between them.
- **Playlist extend:** "Add 10 more songs like this playlist" and append to the existing playlist (`MusicLibrary.shared.add(_:to:)`).
- **Seed from Now Playing:** read `SystemMusicPlayer.shared.queue.currentEntry` - one tap from whatever the user is listening to.

### 3.2 Browsing
- Add `.searchable` to the playlist list and song list; add library-wide song search (`MusicLibrarySearchRequest`) so users don't have to know which playlist a song lives in.
- Show track count / last played under each playlist name.
- Optionally hide or badge playlists created by MusicAI.
- `fetchSongs` enriches each track with `.with([.genres])` one at a time (`MusicKitService.swift:86`) - slow for big playlists. Load the list first, then fetch genres lazily when a song is tapped (the detail sheet is the only place that needs them).

### 3.3 Detail sheet
- Show the generation controls (count, "discovery vs familiar" slider) here too.
- `metadata` is a computed property that rebuilds on every access, and `RelativeDateTimeFormatter` is created per render (`MashUpView.swift:201`, `:261`). Minor, but cheap to cache.

---

## 4. New features

### 4.1 Refine by conversation
After generation, a chip row / text field: *More upbeat*, *Less mainstream*, *Only 70s*, *No English lyrics*, *Swap #4*. Keep the conversation in the Claude `messages` array or the `LanguageModelSession` transcript so refinements build on the previous result instead of starting over.

### 4.2 Structured controls (optional, alongside free text)
- Energy (chill → high), Era range, Language/region, Popularity (hits ↔ deep cuts), Explicit filter, Duration target ("~45 minutes").
- Feed them into the prompt as structured fields.

### 4.3 Personalization
- "Discovery mode": exclude songs already in the user's library (fetch library songs and pass exclusions / filter results).
- Use listening signals (`MusicRecentlyPlayedRequest`, heavy rotation, top genres) to tailor results - opt-in.

### 4.4 History & favorites (SwiftData)
- Persist each generation: prompt, provider/model, songs, matched IDs, saved playlist ID, date.
- History screen: re-open, re-save, regenerate, duplicate prompt. Star favourite prompts.
- Today, results vanish when switching tabs or dismissing the sheet.

### 4.5 Prompt inspiration
- Empty state on Create tab with tappable chips: "Rainy Sunday bossa nova", "Afrobeat meets house", "Soundtrack for a night drive in Tokyo".
- "Surprise me" button (random theme).
- Recent prompts list under the field.

### 4.6 System integration
- **App Intents / Shortcuts / Siri:** "Make a MusicAI playlist of <theme>" (`AppIntent` + `AppShortcutsProvider`).
- **Widget / Control:** "Playlist of the day" or a quick "Generate from Now Playing" control.
- **Share extension** or `ShareLink`: share the playlist link or a nicely rendered card image (`ImageRenderer`) with the artwork grid.
- **Playlist cover:** generate a cover with Image Playground (`ImagePlaygroundSheet`) from the theme.

---

## 5. Visual design & accessibility

- **Liquid Glass (iOS 26):** swap `.borderedProminent` for `.glassProminent` on primary actions, and consider a search tab (`Tab(role: .search)`) for library search.
- **iPad:** the app supports iPad but uses a phone layout. Use `NavigationSplitView` for Mash Up (playlists | songs | detail) and a two-column Create view (prompt | results).
- **VoiceOver:** `SongRowView` reads as many fragments. Add `.accessibilityElement(children: .combine)` and a label like "3. Title by Artist, Genre. Not found on Apple Music." Unmatched status relies on red/strikethrough - fine visually, but must be in the label.
- **Dynamic Type:** the index has a fixed `.frame(width: 20)` (`SongRowView.swift:36`) which clips at large sizes; genre capsule competes for width - move it under the artist at accessibility sizes (`ViewThatFits` or `@Environment(\.dynamicTypeSize)`).
- **Contrast:** white caption text on the purple→pink gradient capsules is borderline at `.caption2`; check against WCAG AA or darken the gradient slightly.
- **Consistency:** status messages use emoji on Create (`🤖 Asking Claude…`) but plain text on Mash Up (`Asking Claude...`). Pick one.
- **Localization:** move strings to a String Catalog; "favourite" in the prompt vs US English elsewhere.

---

## 6. Technical foundations (enable the above)

### 6.1 Remove duplication
`CreatePlaylistView` and `SongDetailSheet` duplicate the status/error/success/list sections and the whole generate → resolve → save pipeline (~150 lines each). Extract:
- A `@Observable PlaylistGenerator` (state: phase, songs, artworks, match results, error; methods: `generate`, `cancel`, `save`, `replaceUnmatched`).
- Shared views: `GenerationStatusView`, `ErrorBanner`, `SuccessCard`, `GeneratedSongList`.
- A `PlaylistProvider` protocol implemented by `ClaudeService` and `FoundationModelsService`, so views don't branch on `settings.useAppleIntelligence`.
- `ClaudeService.generatePlaylist` and `generateFromSeed` share ~40 identical lines of request code (`ClaudeService.swift:65-99` vs `:139-173`) - factor into one `send(system:user:)`.

### 6.2 Reliability of Claude output
- Replace the "return ONLY JSON" + markdown-fence stripping (`ClaudeService.swift:176`) with **structured outputs / tool use** (a JSON schema for the song array) so parsing can't fail on stray text.
- Decode the response envelope with `Codable` instead of `JSONSerialization` casting.
- Deduplicate songs: `SongItem.id` is `"artist - title"` (`SongItem.swift:4`), so a duplicate from the model causes a `ForEach` ID collision and rendering glitches. Dedupe after parsing and give items a UUID.
- Exclude songs the seed/playlist already contains after generation, not just via the prompt.

### 6.3 Performance
- Resolve songs concurrently with a bounded `withThrowingTaskGroup` (e.g. 4-5 at a time) instead of the sequential loop (`MusicKitService.swift:59`). Keep results ordered by index.
- One service instance per app (inject via `@Environment`) instead of new actors per view.

### 6.4 Security
- API key is stored in `UserDefaults` (`SettingsManager.swift:19`), which is plaintext and included in backups. Move to **Keychain** (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- Update the footer copy to match ("stored securely in your Keychain").
- For a public App Store release, consider a small backend proxy so users don't need their own key (and keys never ship in the app).

### 6.5 Tests
No test target exists. Add Swift Testing coverage for:
- `JSONObjectStreamScanner` (chunk boundaries, braces/quotes inside strings, markdown fences).
- `PlaylistPrompt.userMessage` / `SongMetadata.promptContext` output.
- Song-matching / title-normalization logic (once extracted from the actor).
- `PlaylistGenerator` state transitions with mocked providers.

## 7. Regional availability (Australian storefront)

**Problem:** Many AI-suggested songs aren't available on Apple Music in Australia, so playlists come back with several "Not found" rows.

**Why it happens:** Matching already uses the right catalog - `MusicCatalogSearchRequest` searches the storefront of the signed-in Apple Music account, so "Not found" means the song isn't in the AU catalog (or matching missed it). The models don't know regional licensing and mostly pick from a US-centric view of music. The on-device Apple Intelligence model also invents songs far more often than Claude, which inflates the miss rate.

### 7.1 Over-generate and backfill automatically (biggest win)
- Request ~40% more songs than the target (15 → ~21) in `PlaylistGenerator.runGeneration`, keep the first N that match, and hold the rest as a hidden "bench".
- Fill `.notFound` rows from the bench first; if it runs out, run the existing replacement flow (`runReplacement`) automatically for up to 2 rounds.
- Scale Claude's `max_tokens` with the larger count (`ClaudeService.streamSongs`). Keep the Apple Intelligence request within its context window (cap around 30).
- Trade-off: a slightly longer and more expensive Claude request.

### 7.2 Fall back to the same artist
- When a track isn't found but the artist is in the AU catalog, load the artist with `.topSongs` (`Artist.with([.topSongs])`) and use the best-fitting top song not already in the playlist.
- Add a `GeneratedTrack.Match` state such as `.substituted(Song, original: SongItem)` and show it as "Similar pick" in `TrackRowView`, so the user knows it isn't the AI's exact pick.
- Keeps the artist the AI chose for the theme while guaranteeing the track can be played.

### 7.3 Tell the AI the storefront
- Read `MusicDataRequest.currentCountryCode` once (e.g. "au") and add it in `PlaylistPrompt.userMessage`: "The listener uses Apple Music in Australia (storefront: au). Prefer songs available there."
- Cheap and somewhat helpful, but the AI has no reliable knowledge of regional licensing, so it isn't a fix on its own.

### 7.4 Let Claude check the catalog (only if 7.1–7.3 aren't enough)
- Give Claude a `search_apple_music` tool that runs `MusicKitService.findCatalogSong` and returns hit or miss, so it only suggests songs it has confirmed.
- Near-perfect matching, but noticeably slower and more expensive per playlist, and not feasible for the on-device model. Streaming would also need to account for the tool-use turns.

### 7.5 Diagnose before tuning
- Some misses may be matching, not availability: the stricter matching from Phase 1 rejects a result if the artist credit differs.
- Log the candidates each failed search returned (debug builds only) to see how misses split between the two causes.
- If matching accounts for many of them, add a **close match** state that shows what Apple Music actually has (a live version, a different credited artist) with Accept / Replace actions.

**Recommended:** 7.1 + 7.2 + 7.3 together (a few hours of work, no new setup). Measure first with 7.5; keep 7.4 in reserve.

**Done when:** with Claude, a 15-song playlist in the AU storefront almost always ends with 15 playable songs and no manual "Replace missing" step; any substitutions are visibly labelled.

---

## Suggested roadmap

**Phase 1 - Quick wins (1-2 days)** ✅ *Done*
Parallel song resolution · friendly errors + retry · Keychain · empty-state prompt chips · Settings on both tabs · onSubmit/keyboard/haptics · cancel button · accessibility labels · fix wrong-song fallback.

**Phase 2 - Core UX (≈1 week)** ✅ *Done*
Extract `PlaylistGenerator` + shared views · review-before-save with edit/reorder/rename · song count picker · preview playback + Open in Apple Music · replace unmatched songs · subscription check · streaming results.

**Phase 3 - Differentiators**
History (SwiftData) · conversational refinement · true multi-seed Mash Up + Now Playing seed · App Intents/Shortcuts · iPad split view · share cards & generated covers.

**Phase 4 - Regional availability**
Over-generate + automatic backfill · artist top-song fallback ("Similar pick") · storefront hint in prompts · miss diagnostics / close-match state · (optional) Claude catalog-search tool. See §7.
