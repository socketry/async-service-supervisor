# Memory Diagnostics

This guide explains how to capture Ruby heap dumps and garbage collection profiles from supervised workers, then use them to investigate memory growth.

## Overview

Use the diagnostic Bake tasks when a worker's memory grows unexpectedly and you need to understand what it is retaining. A typical investigation combines:

- {ruby Async::Service::Supervisor::MemoryMonitor} or process metrics to identify sustained growth.
- Heap dumps to compare the objects present before and after representative load.
- Garbage collection profiles to measure time spent collecting objects.
- Scheduler and thread dumps to correlate memory growth with stuck or unusually long-running work.

These operations run inside the selected worker. They are intended for diagnosis rather than continuous monitoring.

## Finding a Worker

Run Bake from the service root where `supervisor.ipc` is located, then list the registered workers:

```bash
$ bake async:service:supervisor:workers
```

The result contains supervisor-assigned connection IDs. These IDs are not process IDs and may change whenever a worker or supervisor restarts. List the workers again if an operation reports that the connection no longer exists.

When workers are interchangeable, choose one ID and use that same worker throughout an investigation. If a worker restarts between snapshots, its replacement has a new heap and a new connection ID, so the snapshots are not directly comparable.

## Capturing a Heap Dump

Choose a path that is writable from the worker and has enough free space:

```bash
$ bake async:service:supervisor:memory_dump \
    connection_id=1 \
    path=/var/tmp/worker-1-before.json
```

The returned path identifies the file written by the worker:

```text
{:path=>"/var/tmp/worker-1-before.json"}
```

The path is resolved in the worker's filesystem namespace, not the shell running Bake. For a containerized or remote worker, retrieve the file from that worker or write it to a shared volume.

Ruby heap dumps use newline-delimited JSON: each line describes an object, root, or heap record. They are not a single JSON array.

### Operational Safety

A full heap dump calls `ObjectSpace.dump_all`. Before running it in production, consider the following:

- Dumping a large heap is slow and blocks the selected worker while Ruby walks its object space.
- The output can be much larger than the worker's resident memory. Check available disk space first.
- Heap records may contain application strings and other sensitive data. Store and transfer dumps accordingly.
- Avoid capturing every worker at once. Start with one representative worker during a low-risk period.
- The dump includes objects present at that instant, including garbage that Ruby has not collected yet. For retained-growth comparisons, capture snapshots shortly after comparable GC activity when possible.

## Analyzing Heap Dumps

Capture a baseline, exercise the suspected workload, then capture the same worker again:

```bash
$ bake async:service:supervisor:memory_dump \
    connection_id=1 \
    path=/var/tmp/worker-1-before.json

# Run representative traffic or wait through the suspected growth period.

$ bake async:service:supervisor:memory_dump \
    connection_id=1 \
    path=/var/tmp/worker-1-after.json
```

Use [Shopify's `heap-profiler`](https://github.com/Shopify/heap-profiler) to turn each heap dump into a report. It reads `ObjectSpace.dump_all` output directly and summarizes memory and object counts by class, gem, file, and allocation location. Install it on the system where you will analyze the dumps; it does not need to be installed in the worker:

```bash
$ gem install heap-profiler
$ heap-profiler /var/tmp/worker-1-before.json
$ heap-profiler /var/tmp/worker-1-after.json
```

Use `--max` to show more entries when the default report is too short:

```bash
$ heap-profiler --max=100 /var/tmp/worker-1-after.json
```

Compare the reports for classes, locations, or repeated strings whose object count and memory continue to increase. In particular, look for:

- Collection classes whose object count or shallow memory continually grows.
- Repeated strings or payloads that should have expired.
- Application classes associated with registries, caches, queues, or other long-lived state.
- Growth that remains across multiple snapshots captured after comparable GC activity.

The reported memory is shallow size and does not include every object referenced by a container. Treat a two-snapshot increase as evidence of growth, not necessarily a leak. Capture a third snapshot after another comparable workload and GC cycle to confirm that the same classes or allocation locations continue growing.

## Recording Allocation Locations

By default, a heap dump may not contain allocation source locations. To record them, enable ObjectSpace allocation tracing in the worker before the workload you want to investigate:

```ruby
require "objspace"
ObjectSpace.trace_object_allocations_start
```

Allocation tracing adds runtime and memory overhead, so enable it selectively and measure its impact before using it in production. When tracing is enabled, heap records can include `file`, `line`, `method`, and allocation generation fields. `heap-profiler` automatically includes breakdowns by gem, file, and location when this information is present.

High allocation counts identify hot allocation sites. Compare the `heap-profiler` reports and focus on locations whose objects remain present and continue accumulating, rather than sites that merely allocate many short-lived objects.

## Profiling Garbage Collection

Start the Ruby GC profiler on the same worker you are investigating:

```bash
$ bake async:service:supervisor:garbage_profile_start connection_id=1
```

Exercise the workload, then stop profiling and write the report:

```bash
$ bake async:service:supervisor:garbage_profile_stop \
    connection_id=1 \
    path=/var/tmp/worker-1-gc.txt
```

The start and stop commands must target the same live connection ID. The report is written in the worker's filesystem namespace.

GC profiling helps distinguish several patterns:

- Growing heap size and increasing GC time can indicate retained objects or a cache without a bound.
- High GC time without retained heap growth usually indicates allocation churn rather than a leak.
- Heap growth with little GC activity may mean the workload has not yet forced collection; compare snapshots after similar GC activity.

GC profiling records collection timing and heap statistics. It does not identify which objects retain memory, so use it alongside heap dumps.

## Capturing Scheduler and Thread State

Memory growth can be caused by queued work, blocked requests, or fibers retaining large request graphs. Capture scheduler and thread state from the same worker:

```bash
$ bake async:service:supervisor:scheduler_dump \
    connection_id=1 \
    path=/var/tmp/worker-1-scheduler.txt

$ bake async:service:supervisor:thread_dump \
    connection_id=1 \
    path=/var/tmp/worker-1-threads.txt
```

Without `path`, scheduler and thread dumps are returned to Bake instead of being written by the worker. A path is usually more convenient for large diagnostic output.

Look for fibers or threads that remain in every snapshot, queues that never drain, and repeated backtraces corresponding to the workload that causes memory growth.

## Suggested Investigation Workflow

1. Confirm sustained growth with the `MemoryMonitor`, `ProcessMonitor`, or external process metrics.
2. List worker connection IDs and select one representative worker.
3. Capture a baseline heap dump after normal warm-up.
4. Start GC profiling.
5. Run representative traffic or wait through the suspected leak interval.
6. Capture scheduler and thread dumps if work appears stuck or backlogged.
7. Stop GC profiling and capture a second heap dump from the same worker.
8. Compare heap types, allocation locations when tracing is enabled, and retained reference paths.
9. Repeat across another workload interval to distinguish sustained retention from normal cache warm-up.

Use the {ruby Async::Service::Supervisor::MemoryMonitor} to protect production from unbounded growth, but complete diagnostics before its configured limit restarts the worker. A restarted worker receives a new connection ID and loses the heap state you were observing.
