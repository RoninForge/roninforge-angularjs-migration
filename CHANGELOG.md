# Changelog

## v0.1.0 - 2026-05-19

First release. Single-artifact submission to `github/awesome-copilot`:
`instructions/angularjs-to-angular-18.instructions.md`.

### Added

- `dist/angularjs-to-angular-18.instructions.md` - migration guidance covering
  Angular 18 canonical patterns (standalone, signals, control flow, deferrable
  views, function-based interceptors / guards, provideHttpClient + provideRouter,
  inject(), typed reactive forms, Vitest); the AngularJS 1.x EOL state and three
  migration paths (big-bang, ngUpgrade hybrid, strangler-fig); and 62 anti-patterns
  with BAD/CORRECT pairs across three failure modes (AngularJS-1.x-emitted-for-Angular,
  Angular-2-17-emitted-for-Angular-18, migration-specific mistakes)
- `scripts/validate-awesome-copilot-submission.sh` - reusable local validator
  that mirrors every blocking CI gate in github/awesome-copilot (frontmatter,
  naming, line endings, codespell, README regeneration via npm start, gh-aw
  compile for workflows)
- `scripts/submit-to-awesome-copilot.sh` - reusable submitter that forks
  github/awesome-copilot, branches from staged (NEVER from main), copies
  artifacts from dist/, runs npm start, opens PR with `🤖🤖🤖` AI-author marker
- `META.yml` describing the package (slug, type, version, target paths) for
  the submit script
- Project tree per `strategy/awesome-copilot-pipeline-spec.md` Section 7:
  `src/` for authoring, `dist/` for exact awesome-copilot-shape output, `tests/`
  for golden-file diffs, `scripts/` for the reusable pipeline

### Pin floors

- AngularJS final version: 1.8.3 (April 7 2022, README-only "ultimate-farewell"
  release; LTS ended Dec 31 2021)
- Angular 18 (May 22 2024) is the migration target. Latest 18.x patch
  recommended for `ng update` schematic stability
- Node 20 LTS minimum (Angular 18 requirement)
- RxJS 7.5+ minimum (Angular 18 peer)
- TypeScript 5.4+ minimum (Angular 18 peer)
- AVOID: AngularJS-era packages no longer maintained (angular-ui-bootstrap,
  ng-storage, ng-flow, angular-translate-loader-static-files); plain `lucide`
  package without Angular bindings; Karma + Jasmine for new test files (Vitest
  via `ng add @analogjs/vitest-angular`)
