# A fixed port lets yesterday's server answer for today's test

The e2e transport block started a stand-in server on a fixed port. A server from
an earlier manual run was still bound to it. The suite passed — against the
wrong process, with the script's own logfile never written.

## What happened

A live e2e case looked green while the harness's wire log stayed empty. The
reason: the old server answered every request, so the new one never bound, and
the assertions read a log the working process had never touched.

## Cause

A fixed port is a global name. Anything already holding it wins, silently, and
the test cannot tell "my server answered" from "someone's server answered".

## Fix

- Bind port `0` and let the operating system choose; write the chosen port to a
  file and poll for it before running cases.
- Assert on the wire log (what the server received) so an answer from a foreign
  process cannot satisfy the case.
- If the server does not come up, record the case as **skipped**, counted
  separately — never as a pass.

## Rule

A test that owns a socket must ask the OS for the port and prove *its own*
process is the one talking. "Passed" against an unknown process is worse than a
failure: it trains you to trust a lie.
