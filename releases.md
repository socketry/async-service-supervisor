# Releases

## Unreleased

  - Improve robustness and error handling of default monitors and server loop, ensuring that monitor failures either completely crash the server or retry appropriately, rather than leaving the server in a broken state.

## v0.14.0

  - Add `Worker#make_controller` as an override point for providing a custom worker controller with additional RPCs.

## v0.13.1

  - Unlink shared memory file before opening on supervisor restart, preventing SIGBUS when workers still have the file mapped.

## v0.13.0

  - Add `worker_count` to `UtilizationMonitor` aggregated metrics per service, indicating how many workers contributed to each service's metrics (useful for utilization denominator).

## v0.12.0

  - Introduce `UtilizationMonitor`, that uses shared memory to track worker utilization metrics, like total and active requests, connections, etc.

## v0.11.0

  - Add `state` attribute to `SupervisorController` to store per-worker metadata (e.g., service name).
  - Add `state` parameter to `Worker#initialize` to allow workers to provide state during registration.
  - State is now accessible via `supervisor_controller.state` instead of `connection.state` (as it was in `Async::Container::Supervisor`).

## v0.10.0

  - Serialize `register`/`remove` and `check!` operations in `MemoryMonitor` to prevent race conditions.
  - Remove `memory_sample` functionality - it wasn't very useful and added a lot of complexity.
  - Add support for `Memory::Leak::Cluster` `free_size_minimum:` option.
  - Remove extraneous "Memory leak detected\!" logs.

## v0.9.1

  - Close `Call` queue if asynchronous call fails during dispatch - further messages will fail with `ClosedQueueError`.

## v0.9.0

  - Better handling of write failures in `Connection::Call.dispatch`, ensuring we don't leak calls.
  - Robust monitor loop handling - restart on failure, and align loop iterations.
  - Disable memory sampler by default and use text output format.
      - Introduce support for redirecting dump output to logs.

## v0.8.0

  - Add `Async::Service::Supervisor::ProcessMonitor` for logging CPU and memory metrics periodically.
  - Fix documentation to use correct `maximum_size_limit:` parameter name for `MemoryMonitor` (was incorrectly documented as `limit:`).

## v0.7.0

  - If a memory leak is detected, sample memory usage for 60 seconds before exiting.

## v0.6.4

  - Make client task (in supervised worker) transient, so that it doesn't keep the reactor alive unnecessarily. It also won't be stopped by default when SIGINT is received, so that the worker will remain connected to the supervisor until the worker is completely terminated.

## v0.6.3

  - Add agent context documentation.

## v0.6.2

  - Fix timed out RPCs and subsequent responses which should be ignored.

## v0.6.0

  - Add `async:container:supervisor:reload` command to restart the container (blue/green deployment).

## v0.1.0

  - Initial implementation.
