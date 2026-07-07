# Debugging Monkey C over the Debug Adapter Protocol

Reference notes on how Connect IQ apps are debugged: how the official VS Code
extension does it and what the Connect IQ SDK ships. It starts from debugger
fundamentals so it stands on its own.

## Background: debuggers and DAP

A source-level debugger has three moving parts:

1. A **client** (the editor) that shows breakpoints, the call stack, variables,
   and controls like step/continue.
2. A **runtime** running the program. For Connect IQ that is the **simulator**,
   which runs the compiled app (`.prg`).
3. A **debug adapter** between them. The runtime speaks its own private protocol;
   the editor speaks a standard one. The adapter translates.

The standard the editor speaks is the **Debug Adapter Protocol (DAP)**, the same
JSON-RPC protocol VS Code uses. Messages are framed like LSP
(`Content-Length: N\r\n\r\n{json}`) and normally flow over the adapter's
stdin/stdout. Typical requests: `initialize`, `launch`, `setBreakpoints`,
`configurationDone`, `continue`, `next` (step over), `stepIn`, `stepOut`,
`stackTrace`, `scopes`, `variables`, `evaluate`. Typical events back: `stopped`
(hit a breakpoint), `output`, `terminated`.

**Breakpoints** are the subtle part. Clicking line 42 sends
`setBreakpoints { source: "Foo.mc", lines: [42] }`. The adapter turns "line 42 of
Foo.mc" into "this address in the compiled program", installs it in the runtime,
and when execution stops there, translates the runtime's raw stack (addresses,
registers) back into source files, line numbers, and variable names. That
translation needs a **debug-info file** mapping source to compiled code. For
Monkey C that file is `<app>.prg.debug.xml`, emitted next to the `.prg` on every
non-release build.

In short: client and adapter speak DAP; adapter and simulator speak Garmin's
private protocol; the `.prg.debug.xml` is the map that lets the adapter answer
"where am I in the source right now".

## How the VS Code extension debugs

Evidence from `garmin.monkey-c-1.1.3/dist/extension.js` and the SDK.

The extension registers a debugger type `monkeyc` (launch only, no attach):

```js
e.debug.registerDebugAdapterDescriptorFactory("monkeyc", new Fr());
```

The factory returns a `DebugAdapterExecutable`, so the adapter is a **separate
program run over stdio**, not code inside the extension:

```js
createInstance(t){
  const n = S();                                  // the java executable
  const r = a.resolve(__dirname, "../jars");
  const i = ["-classpath", a.join(r, "DebugServer.jar")];
  i.push("com.garmin.monkeybrains.monkeydodo.DebugAdapterProtocol");
  t = new e.DebugAdapterExecutable(n, i);          // java -cp DebugServer.jar <main>
}
```

So the debug adapter is:

```sh
java -classpath <ext>/jars/DebugServer.jar com.garmin.monkeybrains.monkeydodo.DebugAdapterProtocol
```

On the simulator side, the extension waits for the simulator by connecting to a
TCP socket on **`127.0.0.1`, ports 1234-1238** (it scans the range) and checking
the reply contains `"A garmin device"`, retrying for up to 40 seconds before
giving up ("Unable to connect to simulator."). The debug engine then talks to
the running simulator over that connection. The `shell` binary in the SDK bin is
that simulator debug shell; `connectiq` / `ConnectIQ.app` is the simulator GUI.
(The simulator picks a dynamic port; `40000` seen elsewhere is a red herring, it
is the 40-second `4e4` timeout budget, not a port.)

## What the SDK ships

`DebugServer.jar` is bundled only with the VS Code extension, not in the SDK bin.
The classes it runs are **also present in the SDK's `monkeybrains.jar`**:

- `com/garmin/monkeybrains/monkeydodo/DebugAdapterProtocol.class` (the DAP `main`)
- `com/garmin/monkeybrains/monkeydodo/DebugServer.class` (the DAP request handler)
- 198 classes under `monkeydodo/` total, including `BreakpointManager`,
  `CommandController`, `variables/`, `values/`.

Related SDK bin tools:

- `mdd` -> `java -classpath monkeybrains.jar com.garmin.monkeybrains.monkeydodo.MonkeyDoDo`,
  a command-line debugger. Its options show the core inputs: `-d/--device`,
  `-e` (the CIQ executable / `.prg`), `-x/--debug-xml`. It refuses to run with
  "Debugging is not supported by the SDK. Please download a newer SDK
  (>= 2.3.0)".
- `monkeydo` -> `MonkeyDoDeux` (the plain run/simulate tool).
- `shell` (simulator debug shell), `connectiq` / `ConnectIQ.app` (simulator).

`DebugAdapterProtocol` is built on **Eclipse LSP4J's DAP support**
(`org.eclipse.lsp4j.jsonrpc.debug.DebugLauncher`), the same widely used library
behind many language servers, so it is a conformant DAP server rather than a
bespoke protocol.

### Running the adapter from the SDK alone

`monkeybrains.jar` already contains `org/eclipse/lsp4j/debug` (294 classes) but
not `com.google.gson` (0 classes), which the adapter needs to parse JSON. That is
why the extension ships the fat `DebugServer.jar`. In the SDK, `gson` is in
`LanguageServer.jar` (188 gson classes). With both on the classpath, the adapter
runs straight from the SDK, no VS Code extension required:

```sh
java -classpath "<sdk>/bin/monkeybrains.jar:<sdk>/bin/LanguageServer.jar" \
     com.garmin.monkeybrains.monkeydodo.DebugAdapterProtocol
```

Sending a DAP `initialize` to that process returns a valid response:

```json
{
  "type": "response",
  "command": "initialize",
  "success": true,
  "body": {
    "supportsConfigurationDoneRequest": true,
    "supportsEvaluateForHovers": true,
    "supportsRestartRequest": false,
    "supportsTerminateRequest": true
  }
}
```

(On Windows the classpath separator is `;` instead of `:`.)

## The launch request

`DebugServer` implements these DAP requests: `setBreakpoints`, `stackTrace`,
`threads`, `scopes`, `variables`, `evaluate`, `continue`, `next`, `stepIn`,
`stepOut`, `pause`, `restart`, `terminate`, `disconnect`, `source`,
`configurationDone`. The `launch` request reads these argument keys (from the
class's string constants):

| key                     | meaning                                                  |
| ----------------------- | -------------------------------------------------------- |
| `device`                | device id to simulate (e.g. `fenix7`)                    |
| `prg`                   | path to the built `.prg`                                 |
| `prgDebugXml`           | path to the matching `.prg.debug.xml`                    |
| `stopAtLaunch`          | break immediately on start                               |
| `runNativePairing`      | run in sensor (ANT/BLE) native pairing mode              |
| `runTests`              | run unit tests instead of the app                        |
| `tests`                 | optional array of test names                             |
| `settingsJson`          | app settings                                             |
| `additionalPrg`         | secondary app `.prg` (complication publisher/subscriber) |
| `additionalPrgDebugXml` | debug xml for the secondary app                          |
| `noDebug`               | standard DAP flag: run without stopping at breakpoints   |

It resolves the active SDK from `current-sdk.cfg`. The exact JSON shape a client
sends (nesting, required vs optional, how `settingsJson` is encoded) can be
captured with a DAP trace against the VS Code extension.

## What the adapter supports

The `initialize` response advertises a deliberately small capability set:
`supportsConfigurationDoneRequest`, `supportsEvaluateForHovers`, and
`supportsTerminateRequest` are true; `supportsRestartRequest` is false (the
`restart` method exists but the capability is not advertised, so clients fall
back to terminate + relaunch).

Supported in practice:

- Line breakpoints (`setBreakpoints`).
- Stepping: step over (`next`), step in, step out, `continue`, `pause`.
- Call stack (`stackTrace`), threads, scopes, and variables (read-only).
- Expression `evaluate` in the current stopped frame, used for hovers, watches,
  and the REPL.
- Program output (e.g. `Toybox.System.println`) delivered as DAP `output`
  events.

Not implemented, so unavailable:

- `setVariable` / `setExpression`: variables cannot be edited at runtime; the
  variable view is read-only.
- Conditional breakpoints, hit-count breakpoints, and logpoints: only plain
  line breakpoints exist, and a condition set on one is ignored.
- Function breakpoints and exception breakpoints.
- Completions: no expression/REPL completion.

## Debugging a complication publisher + subscriber

A complication publisher and subscriber are debugged in one session: the launch
sends `prg` (the subscriber, a watch face) and `additionalPrg` (the publisher, a
device app), so the sim runs the watch face as the foreground face and loads the
publisher alongside. The adapter reads each prg's manifest permissions
(`ComplicationSubscriber` / `ComplicationPublisher`) to sort the roles.

Getting values to actually flow is not obvious, and none of it is specific to
this adapter (the VS Code extension behaves identically):

- The publisher must publish from a **background service**
  (`System.ServiceDelegate.onTemporalEvent`). While the watch face is the
  foreground app, a foreground timer in the publisher never runs, so only the
  background service can update the complication.
- In the simulator, a publish is fired manually with
  **Simulation > Background Event > Temporal Event**, targeting the publisher
  app (the dialog lets you choose which app's service runs). On a real device
  the temporal event fires automatically, at most every 5 minutes
  (`Background.registerForTemporalEvent`'s floor).
- The subscriber cannot construct the publisher's complication `Id` from a
  constant. It iterates `Complications.getComplications()`, finds the custom
  entry (`COMPLICATION_TYPE_INVALID`) whose `longLabel` matches, and subscribes
  to that complication's `complicationId`.

`subscribeToUpdates` and `getComplication` throw when a complication is not
available, so a subscriber must guard them or it crashes.

The `mdd` CLI (`com.garmin.monkeybrains.monkeydodo.MonkeyDoDo`, `-d`/`-e`/`-x`)
debugs a single app only; it has no flag for a second app, so the two-app
publisher/subscriber case only exists through the DAP `launch` request's
`additionalPrg` field.
