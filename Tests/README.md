# Regression checks

From the project root, run:

```sh
bash Tests/run-regressions.sh
```

Requires Xcode command-line tools and an active macOS desktop session. The runner compiles the production drawing, overlay, timer, and hotkey code into a temporary executable, then removes the temporary build directory. No Xcode project changes or test dependencies are needed.

Checks cover PNG export after erase/undo, drawing cache invalidation, screen/window coordinate conversion, right-aligned text, overlay input isolation, text-to-crop transitions, timer delivery during menu tracking and delays, hotkey suspension/restoration, immediate Escape during animations and text/crop input, responder cancellation, focus-loss cleanup, native Carbon Escape delivery without a key window, Escape during menu tracking, registration failure, timer shortcut release/restoration, and normal overlay window levels. Native shortcut tests dispatch Carbon events; physical keyboard delivery requires a manual check. Focus changes are tested through AppKit notifications. Temporary overlay windows are hidden or made transparent immediately; screen capture and clipboard export are not invoked. Live screen capture, physical display arrangements, and the Save panel still require manual checks.

A nonzero exit status indicates a compilation error or failed check. To run against another source checkout, pass its absolute path as the first argument.
