# Fixtures

Test fixtures used to validate Customs' detector.

## `customs-demo-exfil`

A **positive control**. It deliberately reads decoy credential paths and POSTs the
contents to a remote host, so the detector can be shown firing on behaviour we control.

This is the standard way to validate a detection instrument: you need a known-positive
to prove the instrument works at all, alongside real-world negatives to prove it does not
cry wolf. The positive control is **not** the headline finding — the real-package results are.

It is `"private": true`, never published, and only ever executes inside a disposable
container with no access to the host filesystem.
