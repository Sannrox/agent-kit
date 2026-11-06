# Gallery and visual proof

## States gallery

One HTML page that shows every state of the components a change affects, so a
reviewer judges concrete examples instead of a description.

1. **Derive the states from the components and their data contracts.** Cover
   each one that applies:
   - normal;
   - loading;
   - empty or first run;
   - error;
   - unavailable (a backend capability is missing or switched off);
   - no permission;
   - selected and expanded;
   - long text and dense content;
   - phone width.

   Show mutually exclusive states as separate examples. Label any proposed
   state that the implementation does not support yet.
2. **Prefer real components rendered with mock fixtures.** When an example is
   a static or approximate rendering, label it, and link the running UI for
   interactions it cannot show.
3. **Give every example a stable ID** in the form `<surface>/<state>`, for
   example `agents/unavailable`, with a short state label. Reviewers reply by
   ID. Keep the same file, IDs and order across iterations so feedback stays
   comparable, and apply feedback to both the gallery and the implementation.
4. **Check it before asking for feedback.** Inspect the rendered gallery at the
   relevant viewports. Report states you could not show and why.

The gallery is for design feedback. Behavior proof stays in browser tests, and
final captures stay separate from the evolving gallery.

## Visual proof

1. **Capture a settled frame.**
   - Wait on an asserted state, never on a fixed sleep.
   - Wait for fonts and visible images to load.
   - Disable animations and transitions for the capture.
   - Freeze time-dependent content (clocks, relative times) with the test
     runner's clock control.
2. **Make before and after comparable.** Use the same viewport, data, theme and
   scroll position, the base branch for before, and the change for after.
3. **Crop from the same frame.** Element crops come from the single page
   capture they belong to, so they show the same moment.
4. **Inspect every capture yourself** before reporting it. A capture that shows
   a broken state is a failing result, not evidence. Fix the behavior, add or
   update a test, and capture again.
5. **Store captures as artifacts, not commits.** Use a per-process directory
   under the repository's artifact root, or the system temp directory with the
   process id and a unique suffix. Keep failed and passing attempts, together
   with the trace and the URL. Never clear a shared artifact parent.
6. **Sanitize before sharing.** No hostnames, addresses, account names, tokens
   or private content in a capture that leaves the machine. Use synthetic data
   in mock captures.

For a short video of a flow, record a browser context with a fixed viewport.
Close the context before reporting the video path, and inspect the finished
file.
