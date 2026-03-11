# Async::Service::Supervisor

Provides a supervisor service for

[![Development Status](https://github.com/socketry/async-service-supervisor/workflows/Test/badge.svg)](https://github.com/socketry/async-service-supervisor/actions?workflow=Test)

## Features

  - Supports multi-process, multi-thread and hybrid containers.
  - Automatic scalability based on physical hardware.
  - Direct integration with [systemd](https://www.freedesktop.org/software/systemd/man/sd_notify.html) using `$NOTIFY_SOCKET`.
  - Internal process readiness protocol for handling state changes.
  - Automatic restart of failed processes.

## Usage

Please see the [project documentation](https://socketry.github.io/async-service-supervisor/) for more details.

  - [Getting Started](https://socketry.github.io/async-service-supervisor/guides/getting-started/index) - This guide explains how to get started with `async-service-supervisor` to supervise and monitor worker processes in your Ruby applications.

  - [Migration Guide](https://socketry.github.io/async-service-supervisor/guides/migration/index) - This guide explains how to migrate from `async-container-supervisor` to `async-service-supervisor`. The new version provides a cleaner API built on `Async::Bus` for improved reliability and maintainability.

  - [Memory Monitor](https://socketry.github.io/async-service-supervisor/guides/memory-monitor/index) - This guide explains how to use the <code class="language-ruby">Async::Service::Supervisor::MemoryMonitor</code> to detect and restart workers that exceed memory limits or develop memory leaks.

  - [Process Monitor](https://socketry.github.io/async-service-supervisor/guides/process-monitor/index) - This guide explains how to use the <code class="language-ruby">Async::Service::Supervisor::ProcessMonitor</code> to log CPU and memory metrics for your worker processes.

  - [Utilization Monitor](https://socketry.github.io/async-service-supervisor/guides/utilization-monitor/index) - This guide explains how to use the <code class="language-ruby">Async::Service::Supervisor::UtilizationMonitor</code> to collect and aggregate application-level utilization metrics from your worker processes.

## Releases

Please see the [project releases](https://socketry.github.io/async-service-supervisor/releases/index) for all releases.

### v0.12.0

  - Introduce `UtilizationMonitor`, that uses shared memory to track worker utilization metrics, like total and active requests, connections, etc.

### v0.11.0

  - Add `state` attribute to `SupervisorController` to store per-worker metadata (e.g., service name).
  - Add `state` parameter to `Worker#initialize` to allow workers to provide state during registration.
  - State is now accessible via `supervisor_controller.state` instead of `connection.state` (as it was in `Async::Container::Supervisor`).

### v0.10.0

  - Serialize `register`/`remove` and `check!` operations in `MemoryMonitor` to prevent race conditions.
  - Remove `memory_sample` functionality - it wasn't very useful and added a lot of complexity.
  - Add support for `Memory::Leak::Cluster` `free_size_minimum:` option.
  - Remove extraneous "Memory leak detected\!" logs.

### v0.9.1

  - Close `Call` queue if asynchronous call fails during dispatch - further messages will fail with `ClosedQueueError`.

### v0.9.0

  - Better handling of write failures in `Connection::Call.dispatch`, ensuring we don't leak calls.
  - Robust monitor loop handling - restart on failure, and align loop iterations.
  - Disable memory sampler by default and use text output format.
      - Introduce support for redirecting dump output to logs.

### v0.8.0

  - Add `Async::Service::Supervisor::ProcessMonitor` for logging CPU and memory metrics periodically.
  - Fix documentation to use correct `maximum_size_limit:` parameter name for `MemoryMonitor` (was incorrectly documented as `limit:`).

### v0.7.0

  - If a memory leak is detected, sample memory usage for 60 seconds before exiting.

### v0.6.4

  - Make client task (in supervised worker) transient, so that it doesn't keep the reactor alive unnecessarily. It also won't be stopped by default when SIGINT is received, so that the worker will remain connected to the supervisor until the worker is completely terminated.

### v0.6.3

  - Add agent context documentation.

### v0.6.2

  - Fix timed out RPCs and subsequent responses which should be ignored.

## Contributing

We welcome contributions to this project.

1.  Fork it.
2.  Create your feature branch (`git checkout -b my-new-feature`).
3.  Commit your changes (`git commit -am 'Add some feature'`).
4.  Push to the branch (`git push origin my-new-feature`).
5.  Create new Pull Request.

### Developer Certificate of Origin

In order to protect users of this project, we require all contributors to comply with the [Developer Certificate of Origin](https://developercertificate.org/). This ensures that all contributions are properly licensed and attributed.

### Community Guidelines

This project is best served by a collaborative and respectful environment. Treat each other professionally, respect differing viewpoints, and engage constructively. Harassment, discrimination, or harmful behavior is not tolerated. Communicate clearly, listen actively, and support one another. If any issues arise, please inform the project maintainers.
