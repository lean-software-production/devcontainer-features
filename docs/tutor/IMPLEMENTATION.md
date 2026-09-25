# Tutor MVP: implementation map

This is the builders' shared map for the MVP on branch `tutor/mvp`. It says who owns which files,
and it pins down every contract between them. [`DESIGN.md`](DESIGN.md) says what to build and
[`CHANGELOG-from-design.md`](CHANGELOG-from-design.md) overrides it where they differ. The UX is
[`mockups.html`](mockups.html), round 2, with these picks: sidebar **1B**, lesson page **2A**
(`ThreadChat layout="document"`), coach moments **3A**, and example states **6B**. Choice buttons
(3B) are not built.

The plugin is `src/tutor/plugin` (npm `bb-plugin-tutor`, plugin id `tutor`). It targets bb-app
0.43.4 and pins `@get-bb/plugin-sdk` to exactly 0.5.9.

## Ownership

Four builders work in parallel. Each one writes only inside their own paths. Everything else is
read-only to them. If a contract below has to change, stop and report it; don't edit someone
else's file.

| Path (under `src/tutor/plugin/` unless absolute) | Owner | Notes |
|---|---|---|
| `package.json`, `package-lock.json`, `tsconfig.json`, `.gitignore`, `components.json` | skeleton | Frozen. Every runtime dependency is already installed (see [Dependencies](#dependencies)). |
| `shared/**` | skeleton | Read only. The contracts. |
| `components/`, `lib/`, `hooks/` | skeleton | Vendored BB UI (shadcn model). The frontend may *use* these, and may add new files under `components/ui/`. |
| `README.md`, `PLUGIN_OVERVIEW.md` | skeleton | Builders can suggest changes in their report. |
| `server/course/**` | **CONTENT** | Implements `CourseSource`. Also owns Homework 0's content. |
| `server.ts`, `server/progress/**`, `server/coach/**`, `server/rpc/**`, `test/**` (plugin-level integration tests), `skills/tutor/SKILL.md` | **BACKEND** | Replaces the stub `server.ts`. |
| `app.tsx`, `app/**` (including `paper.css` and `fonts/`) | **FRONTEND** | Replaces the stub `app.tsx`. Component CSS goes in `app/styles/`. |
| `src/tutor/{devcontainer-feature.json,install.sh,bin/,README.md,NOTES.md}`, `test/tutor/**` (repo root), `.devcontainer/tutor/**`, `test/tutor/fixtures/scripted-provider/` | **FEATURE** | The feature, its tests, the codespace entry point, and the end-to-end fixture. |

Everyone may read the course repo at `work/tutorial`, but must not modify it. The containerised BB
harness is `scripts/tutor-dev/`. Keep its README's rules, and don't change the scripts; ask
instead.

## Rules for everyone

- **Quality bar:** TypeScript strict (plus `noUncheckedIndexedAccess`), small focused modules, no
  dead code, and comments only where something isn't obvious.
- **Tests:** unit tests for all logic, run with `node --test`. Put them next to the code as
  `*.test.ts`. `npm test` picks up `shared/**`, `server/**`, `app/**` and `test/**`.
- **Imports:** relative imports carry their extension (`../shared/model.ts`), so node can run the
  sources directly. The `@/…` alias only works in bundled `.tsx`. Type-only imports use
  `import type`; `verbatimModuleSyntax` enforces this. Only erasable TypeScript is allowed: no
  enums, namespaces or parameter properties.
- **Node can't run `.tsx`.** Frontend logic goes in plain `.ts` modules (view models, formatters,
  routing) with tests. Keep the `.tsx` components thin. Nothing that a node test imports may
  import `@get-bb/plugin-sdk/app` or React at runtime.
- **Before you report:** `npm ci`, `npm run typecheck`, `npm test` and `bb plugin build .` must
  all pass. Build inside the harness: `TUTOR_DEV_CWD=$PWD/src/tutor/plugin
  scripts/tutor-dev/bb.sh plugin build $PWD/src/tutor/plugin`. For live checks, run
  `scripts/tutor-dev/install-plugin.sh src/tutor/plugin` and then `node scripts/tutor-dev/shot.mjs …`.
- **Hard rules** (from the brief): never touch the host BB at 127.0.0.1:38886, never copy provider
  credentials, never commit, and only write inside `work/` and `$TMPDIR`.

## Dependencies

The skeleton owns these, and they are all installed. Don't add any.

| Package | For |
|---|---|
| `@cucumber/gherkin`, `@cucumber/messages` | Parsing feature files (CONTENT). `new Parser(new AstBuilder(IdGenerator.uuid()), new GherkinClassicTokenMatcher())` |
| `yaml` | course.yaml, lexicon.yaml (CONTENT); PROGRESS.yaml (BACKEND) |
| `diff` (v9, typed) | `factoryDiff` line diff (CONTENT) |
| `zod` (v4) | Schemas in `shared/`; RPC and tool validation |
| `@get-bb/plugin-sdk` 0.5.9 (dev) | Types, `defineRpcContract`, `@get-bb/plugin-sdk/testing` (`createFakePluginHost`) |
| Vendored-UI deps (`@radix-ui/*`, `@hugeicons/*`, `clsx`, …) | Already used by `components/ui/` |

## The shared modules

| Module | Holds | Runtime import allowed from the frontend? |
|---|---|---|
| `shared/constants.ts` | Plugin, skill, tool, realtime-channel, directive, slot and setting names; env and config paths; factory and course file paths; `BUILTIN_HOMEWORK_ID`; `coachThreadTitle()` | yes |
| `shared/keys.ts` | `slugify`, `uniqueSlugs`, `featureSlugFromPath`, `ruleKey`, `exampleKey`, `parseExampleKey`, `ruleKeyOfExample`, key patterns | yes |
| `shared/model.ts` | zod schemas and types for Course → Homework → FeatureFile → Rule → Example → Step, LexiconEntry, IterationState, ProgressFile, ExampleProgress, StudentState, CoachThreadMetadata, and the derived enums and counts | **type only** |
| `shared/derive.ts` | `exampleStatus`, `countExamples`, `ruleStatus`, `homeworkExamples`, `findHomework`, `nextHomework`, `findRule`, `findExample`, `resolveCurrent`, `homeworkStatus` | yes (pure; imports only types from the model) |
| `shared/rpc.ts` | `rpcContract`, plus payload schemas and types (Overview, Lesson, Completion, Binding, TutorThread, …) and `StateChangedSignal` | **type only** |
| `shared/tools.ts` | `toolParameterSchemas` for the six coach tools, and length limits | backend only |
| `shared/directives.ts` | `parseProgressCard`, `formatProgressCard`, `parseTermRef`, `formatTermRef` (zod-free) | yes |
| `shared/routes.ts` | `parseRoute` and `formatRoute` for the navPanel sub-paths | yes |
| `shared/ports.ts` | `CourseSource`, `ProgressStore`, `CourseLoadError` | backend only |
| `shared/fixtures.ts` | Schema-valid fixtures: `fixtureCourse` (000–003), `fixtureStudent` (002 WIP), `fixtureFreshStudent`, `fixtureOverview`, `fixtureOverviewUnbound`, `fixtureLesson`, `fixtureCompletion`, `fixtureCandidates`, `fixtureLexicon`, `fixtureThreads`, `fakeHash` | tests and the stub only |

## Contracts

### Keys, slugs and hashes (CONTENT produces, everyone consumes)

- **Rule key:** `<feature-file-slug>/<rule-slug>`. **Example key:**
  `<feature-file-slug>/<rule-slug>/<example-slug>`. The feature-file slug is the file's basename
  without `.feature`, slugified. Rule and Example slugs are their names, slugified, then made unique
  among siblings in file order with `uniqueSlugs` (`-2`, `-3`, …). Always use the helpers in
  `shared/keys.ts`; never hand-roll a key.
- Examples directly under a Feature, outside any Rule, are grouped into a synthetic Rule. Its slug
  is `LOOSE_EXAMPLES_RULE_SLUG` (`general`), its name is the Feature's name, and it comes first.
- A Scenario Outline is one Example. It is not expanded.
- **Example text hash:** `sha256:` followed by the lowercase hex SHA-256 of the UTF-8 text built
  like this, with lines joined by `\n`:
  1. the Example's name;
  2. for each step, `<keyword> <text>`, keyword as written (`Given`, `And`, …);
  3. for a docstring, a line `"""<mediaType or empty>`, then its content lines, then `"""`;
  4. for a data table, each row as its cells joined by ` | `.

  Every line has its whitespace runs collapsed to one space and is then trimmed. Tags, the
  description, line numbers and Background steps are left out. So rewording a step changes the
  hash, and re-indenting or moving the Example doesn't.
- **Novelty** compares each homework with the previous homework in course order, as documented on
  `noveltySchema`. Everything in Homework 0 and in the first real homework is `new`.
- **`suggestedRuleOrder`:** every Rule key exactly once. Rules that are not `unchanged` come
  first, then the rest, each group in file order. Files are sorted by path.
- **`factoryDiff`:** the FACTORY.md line diff against the previous non-builtin homework. It is
  `null` for Homework 0 and for the first real homework.
- **`dek`:** the first prose paragraph of README.md, skipping the `#` title and any italic
  *Set after…* line.

### Course loading (CONTENT implements `CourseSource`)

`createCourseSource(): CourseSource` is exported from `server/course/index.ts`. The backend
imports only that file. `loadCourse(coursePath)` works as follows:

1. **`course.yaml`**, when present, has the shape given in DESIGN.md: `id`, `title`, optional
   `description`, `coach`, optional `lexicon`, and `homeworks[]` with `{ id, title, set, dir }`.
2. **Otherwise the ledger fallback.** Parse the table in `docs/iterations/README.md`: the
   `Iteration` column is the id, the `Spec` link text is the title and its target's directory is
   `dir`, and `Set after` is `set`. Then `id` is `slugify(basename(coursePath))`, `title` is the
   course README's first `#` heading (or the id), `description` is null, `coach` is
   `.agents/coach-me.md` if it exists, and `lexicon` is `docs/lexicon.yaml` if it exists.
3. **Homework 0** ("Using your tutor", id `000`, set `Start here`, `builtin: true`) comes first. Its
   content lives in `server/course/builtin/`: a `course.yaml` naming `homework-0/`, which holds
   `README.md`, `features/*.feature` and a short `FACTORY.md`. Find its directory from `import.meta.url`, not the working directory. Its
   Examples teach the interface, for example "When you spin off a side thread from a Rule, then it
   appears under that Rule".
4. **Lexicon:** each YAML key becomes `{ id, term, definition }`. A missing lexicon gives `[]`.
5. **Errors:** throw `CourseLoadError` with a message the student can read, naming the file and line
   where there is one.

Test against small fixture courses under `server/course/fixtures/`. Gate an integration test on
the real tutorial repo behind `TUTOR_TEST_COURSE=/path/to/tutorial`, and skip it when that is unset.

### Where things are (FEATURE writes, BACKEND reads)

- **Course path** is resolved in this order: the `coursePath` setting, then the
  `TUTOR_COURSE_PATH` env var, then `course` in `/usr/local/etc/tutor/config.json`, then
  `/workspaces/tutorial`.
- **Factory hint:** the `TUTOR_FACTORY_PATH` env var, then `factory` in the config file. It is used
  only to pre-select a candidate project whose default local source path matches.
- **Binding** is always a BB project id, stored in the `factoryProject` setting (`type:
  "project"`), which `confirmFactory` writes with `settings.experimental_set`. The plugin never
  creates projects. When nothing is bound, the binding is `unbound`. A stored id whose project, or
  whose local source, has gone is `missing`.
- **The feature's `install.sh`** writes the config file as JSON
  `{ "course": "…", "factory": "…", "dataDir": "…" }`, leaving out any key whose option is empty.
  `dataDir` is the bb Feature's BB state directory (or `$_REMOTE_USER_HOME/.bb` when that option is
  empty), the last fallback for the heartbeat below. It also path-installs the plugin in a
  `postStartCommand` that runs after `bb-feature-autostart`, from a user-owned copy at
  `<dataDir>/.tutor-feature/plugin-<digest>` (BB rebuilds `dist/` on every path install, so the
  root-owned image copy cannot be installed directly), and skips the install when the plugin is
  already installed from that path. If BB exposes a way to select the course rail under
  Settings → Appearance → Sidebar, the feature does that too. Otherwise the first-run page tells the
  student how.

- **Activity heartbeat (shared with the feature's keep-alive).** `<BB data dir>/.tutor-feature/activity`
  (`ACTIVITY_FILE`) holds one line, an ISO-8601 UTC timestamp of the last time the student was
  actively using BB. The plugin's `heartbeat` RPC writes it atomically, creating the directory
  0700, at most every 30 s; the data dir is `bb.server.experimental_dataDir`, then `BB_DATA_DIR`,
  then `dataDir` in the config file. The app-wide content script `activity` (`app/activity.ts`)
  calls it at most every 45 s while the page is visible and the student interacted in the last
  60 s. `/usr/local/bin/tutor-keepalive`, run by `.devcontainer/tutor`'s `postAttachCommand`,
  treats a stamp under 120 s old as active and prints a line to its terminal every 30 s.
- **Once per BB state directory, the feature's start-up hook** also switches off the plugins in its
  `disablePlugins` option (recorded per id in `.tutor-feature/plugins-disabled`, so a student can
  turn one back on) and selects the `theme` option (`plugin:tutor:paper`) while BB's default theme
  is active (`.tutor-feature/theme-selected`).

### Student state (BACKEND implements `ProgressStore` in `server/progress/`)

- **`spec/ITERATION`** is one line, `NNN WIP` or `NNN Done`. It is canonical (decision 1) and is
  never written for Homework 0.
- **`spec/PROGRESS.yaml`** follows `progressFileSchema`. It extends the design with four additive
  fields: `adopted` (when the iteration was adopted), `summary` (the coach's text from
  `tutor_complete_iteration`), per Example `carriedFrom`, and `history`: on adopt, the previous
  homework's `adopted`, `summary` and Example entries (without `evidence`) are kept under its id, so
  done homeworks' lesson and completion pages stay truthful. Write it with the ids quoted
  (`iteration: "003"`), so YAML never reads them as numbers. Keep a stable key order: `iteration`,
  `focus`, `adopted`, `summary`, `examples`, `history`. Sort `examples` by key and `history` by id.
  Write it atomically. Only the coach tools write it.
- **Reading never throws.** Malformed content goes into `StudentState.problems`, with the part that
  couldn't be read set to null.
- **Stale progress:** when `progress.iteration` differs from the current homework (see
  `resolveCurrent`), treat the progress map as `{}` for that homework. Read-side views of a done
  homework use its `history` entry instead.
- **Current homework:** `resolveCurrent` and `homeworkStatus` in `shared/derive.ts` decide it. The
  backend must not reimplement them. Homework 0 is under way when PROGRESS.yaml says `"000"`, and it
  is Done once all of its Examples are passing or skipped. With no state at all, the student is on
  Homework 0 and `not-started`.
- **Carry-over on adopt:** every Example of the new homework whose hash matches a **passing** entry
  in the previous PROGRESS.yaml, under any key, starts as `passing`. It keeps that entry's
  `evidence` and `at`, and gets `carriedFrom: <entry.carriedFrom ?? previous iteration>`. Every
  other Example has no entry, which means pending. The focus becomes the first entry of
  `suggestedRuleOrder`.
- The backend re-reads state on `thread.idle` for Tutor threads and on every RPC call. When the
  state changes, it publishes `REALTIME_CHANNELS.stateChanged` with a `StateChangedSignal`.

### Coach threads and tools (BACKEND, `server/coach/`)

- **Main thread per homework:** `bb.sdk.threads.spawn({ projectId: <bound>, environment: { type:
  "host", hostId: <factory source's host>, workspace: { type: "unmanaged", path: <factory root> } },
  title: coachThreadTitle(id), pluginMetadata: { course, iteration, role: "main" }, prompt })`. The
  unmanaged workspace guarantees the coach edits the folder Tutor reads, even when the project
  defaults to worktrees. Find it again with `threads.list({ originPluginId: bb.pluginId })` filtered
  by metadata. If there are several, the newest one that isn't archived wins.
- **Side threads:** the same call plus `parentThreadId: <main>`, with `role: "side"` and an optional
  `ruleKey`. They share the working tree with the main thread.
- **Metadata is untrusted.** It is fine for listing threads and filling rails. It must never be used
  to authorise anything.
- **`configure`** is synchronous. It offers `ALL_TOOL_NAMES` and `SKILL_ID` only when
  `ctx.origin.pluginId === bb.pluginId`.
- **Every `execute()`** re-checks that `threads.get(threadId)` has `originPluginId === bb.pluginId`,
  and returns `{ content: [{ type: "text", text }], isError: true }` otherwise. Everything else it
  needs (homework, factory root) is re-derived from the binding and the repo, never from metadata.
  Tool output stays bounded: a few KB.
- **Tools** use the parameter schemas in `shared/tools.ts`:

  | Tool | Does | Returns |
  |---|---|---|
  | `tutor_status` | Current homework, focus, and each Rule's Examples with key, status and name | Compact text the coach can act on, listing keys |
  | `tutor_focus_rule` | Sets `focus`. Main thread only; side threads get `isError` | A `formatProgressCard({ kind: "focus", … })` line for the coach to echo |
  | `tutor_mark_example` | Sets one Example's status; `evidence` is required for passing and `note` for not-yet (the schema enforces this) | The matching `::tutor-progress` line: `rule-passing` when the Rule just went all-green, otherwise `example-passing` or `not-yet` |
  | `tutor_adopt_iteration` | Only the homework after a Done one, or the first. Copies README.md, FACTORY.md and features/ into `spec/` exactly, copies `spec.md` into `seeds/` as coach-me does, writes ITERATION `NNN WIP` and a fresh PROGRESS.yaml with carry-over. Homework 0 writes only PROGRESS.yaml. **Does not commit**: the coach commits, following coach-me | Summary, and the `git show --stat` hint |
  | `tutor_complete_iteration` | Writes ITERATION `NNN Done` and PROGRESS `summary`. Homework 0 instead requires every Example to be passing or skipped | A `homework-complete` card line |
  | `tutor_side_thread` | Spawns a side thread (see above) | The new thread id |

- **Dispatch guard:** an `experimental_hooks` `message.dispatch` handler queues, with a reason, the
  turn of any Tutor thread whose project has another Tutor thread still running.
- **Prompts:** the main thread's first prompt names the homework and tells the coach to follow the
  `tutor` skill. For `startNextHomework`, it also tells the coach to call `tutor_adopt_iteration`
  first.
- **The skill** (`skills/tutor/SKILL.md`) explains the BB-specific behaviour: the tools, the
  evidence rules, when to emit `::tutor-progress` and `::term{id=…}` (lexicon ids only), side
  threads, and that only the main thread moves the cursor. It tells the coach to follow the
  course's `coach` file as its coaching method, and that "jfdi" remains a phrase the student types.

### RPC (BACKEND serves `server/rpc/`, FRONTEND calls)

`shared/rpc.ts` is the contract. It includes the semantics of each method, and every payload shape
is a zod schema. The methods are `getOverview`, `getLesson`, `getCompletion`, `getThreadContext`,
`getLexicon`, `listCandidateProjects`, `confirmFactory`, `openCoach`, `startNextHomework`,
`startSideThread`, `redirectFocus` and `heartbeat` (records student activity; never an error the
student sees). Handlers fail by throwing an `Error` whose message the
student can read. When the course is missing, `getOverview` must still succeed, returning
`course: null` and `courseError`. It never throws for an unbound factory.

### Realtime

There is one channel, `REALTIME_CHANNELS.stateChanged` (`"state-changed"`), whose payload is a
`StateChangedSignal`. Frontends refetch whatever they show when it fires; the payload is a hint,
not data.

### Frontend surfaces (FRONTEND, `app/`)

| Slot (ids in `SLOT_IDS`) | Screen | Data |
|---|---|---|
| `experimental_threadList` `course-rail` | 1B: brand, days strip (homeworks grouped by `set`), progress card, the current homework's features and Rules with ✓ ! ○ ● glyphs, a Conversations tray (Tutor threads, with side threads under the coach), Earlier homeworks, Other threads | `getOverview`, plus `experimental_useSidebarThreads` for live status and non-Tutor threads. The rail works out the active homework from the route (`parseRoute`), because `activeThreadId` is null on plugin pages. |
| `navPanel` `course` at path `course` | `""` redirects to the current lesson or to `welcome`; `lesson/NNN` is 2A (the paper lesson as `ThreadChat` `leadingContent`, `layout="document"`, inside a page-owned `.tutor-grid` scroller, with 6B annotated Gherkin for the Rule in focus and completed Rules collapsed); `complete/NNN` is 7; `welcome` is 8 | `getLesson`, `getCompletion`, `listCandidateProjects`, `confirmFactory`, `openCoach`, `startNextHomework`, `redirectFocus` |
| `messageDirective` `tutor-progress` and `term` | 3A cards, and lexicon chips with pop-ups | `parseProgressCard` / `parseTermRef` (render nothing unvalidated; return the plain source when parsing fails), `getLexicon` (cache it) |
| `threadPanelAction` `rule-tab` | 2C / 4: the Rule in focus (or the side thread's `ruleKey`), with Back to coach / Open lesson | `getThreadContext`, `getLesson` |
| `homepageSection` `continue` | 5: Continue with your coach / Open the lesson | `getOverview` (finds the coach thread itself; `projectId` is usually null) |
| `experimental_sidebarNavigation` `simple-nav` | BB's own navigation rows minus Plugins and Skills, activated through BB; renders BB's original while the `simpleNavigation` setting (boolean, default true) is off or loading | `useSettings` |
| content script `activity` | none: reports activity for the keep-alive (see "Where things are") | `heartbeat` |

- **Theme:** `bb.themes` contributes `paper` (`THEME_ID`; BB lists it as `plugin:tutor:paper`), a
  light and dark mapping of the workbook palette onto BB's tokens, with Archivo inlined.
  `themes/paper.css` is generated from `app/theme/paper.palette.css` by `npm run fonts`.
- **Lost connection:** `useTutorRpc` turns a response that is not one of BB's JSON errors (for
  example the Codespaces port-forwarding proxy's empty 401) or a fetch `TypeError` into
  `ConnectionLostError` (`app/model/rpc-errors.ts`); every error surface then says the connection
  to the Codespace was lost and offers Reload, never a raw "HTTP 401".

- **CSS:** `app/paper.css` holds the fonts and tokens. Wrap plugin-owned markup in
  `.tutor-paper`. Use `.tutor-grid` for grid-paper backgrounds that may contain BB components; it
  sets nothing that inherits. `.tutor-nav` is a third root, for the simple navigation, which uses
  BB's tokens and no paper typography. Classes are `tp-*` and tokens are `--tp-*`: BB's theme uses unprefixed
  names such as `--ink`, and a bare token would leak into BB's own components. Never style BB's
  chat. Light mode only.
- **Fonts:** `app/fonts/fonts.css` is generated (`npm run fonts`), because `bb plugin build` has no
  loader for `.woff2`. A test checks that it is current.
- **Directives are leaf directives:** each one sits on its own line and renders as a block. So
  `::term` is a small chip that pops up the definition. It cannot be an inline word in a sentence
  as mocked.

### End-to-end (FEATURE)

- The credential-free provider is the spike's scripted provider, copied to
  `test/tutor/fixtures/scripted-provider/` (repo root). It echoes `::` lines as assistant markdown,
  and a `CALL <tool> {json}` line makes a real tool call whose JSON matches
  `toolParameterSchemas`. Real Claude Code and Codex are never used in tests.
- The feature's scenarios live in `test/tutor/` and follow the `test/bb/` conventions. The
  codespace entry point is `.devcontainer/tutor/devcontainer.json`: `bb`, the `claude-code`,
  `codex` and `pi` agent CLIs, and `tutor`, cloning the public tutorial repo at start-up.
  `sync-features.sh` copies every `./features/<id>` it names from `src/<id>`.

## Stubs to replace

- `server.ts`: `TODO(backend)`. It serves the fixtures over the real contract, registers the six
  tools (which refuse), and scopes `configure`.
- `app.tsx`: `TODO(frontend)`. It registers every slot with a placeholder.
- `skills/tutor/SKILL.md`: `TODO(backend)`.
