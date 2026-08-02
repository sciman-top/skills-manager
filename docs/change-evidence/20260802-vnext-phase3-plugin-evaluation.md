# Phase 3 layered plugin evaluation

## Result

- `SMV-P3-005 = done` at repo/fixture scope.
- Static lint and deterministic skill behavior fixture are blocking; optional model snapshot is non-blocking.
- Host load and live workflow remain separate `not_run` layers.

## Evidence

- Valid static/behavior fixture passed with model=`not_run`.
- A model pass could not override invalid static metadata; a model fail could not override valid deterministic gates.
- Generated CLI `plugin-eval`: exit 0, pass=true, model/host/live=`not_run`, provider_calls=0.

## Boundary and rollback

No online model was called and no quality claim extends beyond the representative fixtures. Remove evaluation functions/tests/route and rebuild to roll back.
