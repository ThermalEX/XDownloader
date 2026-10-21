# Flutter Contributor Notes

Read the root `AGENTS.md` and `BUILDING.md`. Android is the accepted platform.

- Repositories own persistent state. Use queued atomic edits and invalidate stale asynchronous results.
- Native Android owns background transfers and APK installation; UI polling only displays state.
- Deleting a video must preserve download history. Clearing history must preserve files and active tasks.
- Privacy must protect titles, links, previews, semantics and delayed actions.
- Use Material 3, safe areas and at least 48dp interactive targets; test 320dp and doubled text.
- Run formatting, analysis, offline tests and relevant isolated device probes before releasing.
- Production must exclude probe methods and generated probe APK assets. Never change or publish the official signing key.
