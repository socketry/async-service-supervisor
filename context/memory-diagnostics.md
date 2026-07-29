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

Different tools answer different questions about a heap dump:

| Tool | Best for | Snapshots |
| --- | --- | --- |
| [`heap-profiler`](https://github.com/Shopify/heap-profiler) | Aggregate memory and object counts by class, gem, file, and location | One |
| [`sheap`](https://github.com/jhawthorn/sheap) | Finding objects retained across snapshots and tracing paths back to roots | Two or three |
| [Reap](https://github.com/oxidize-rb/reap) | Finding objects that dominate and retain large portions of a heap | One |

Install and run these tools on a trusted analysis system after retrieving the dumps from the worker. The dumps can contain sensitive application data.

### Aggregate Reports with `heap-profiler`

Capture a heap dump and pass it directly to `heap-profiler`:

```bash
$ bake async:service:supervisor:memory_dump \
    connection_id=1 \
    path=/var/tmp/worker-1.json

$ gem install heap-profiler
$ heap-profiler /var/tmp/worker-1.json
```

Use `--max` to show more entries when the default report is too short:

```bash
$ heap-profiler --max=100 /var/tmp/worker-1.json
```

The report is a useful overview of the largest classes, strings, and allocation locations in one snapshot. It does not calculate a delta between arbitrary Bake snapshots. Capture reports at comparable points in the workload if you want to compare their aggregate counts manually.

### Retention Diffs with `sheap`

Capture a baseline and two later snapshots from the same worker. The third snapshot distinguishes objects that remain retained from temporary allocations present only in the second dump:

```bash
$ bake async:service:supervisor:memory_dump connection_id=1 path=/var/tmp/worker-1-before.json

# Run representative traffic or wait through the suspected growth period.
$ bake async:service:supervisor:memory_dump connection_id=1 path=/var/tmp/worker-1-after.json

# Run another comparable workload and GC cycle.
$ bake async:service:supervisor:memory_dump connection_id=1 path=/var/tmp/worker-1-later.json
```

Install `sheap` and open an interactive two-snapshot diff:

```bash
$ gem install sheap
$ sheap /var/tmp/worker-1-before.json /var/tmp/worker-1-after.json
```

The command opens IRB with `$before`, `$after`, and `$diff` available. For example:

```ruby
# Count newly retained objects by Ruby heap type:
$diff.retained.map(&:type_str).tally.sort_by(&:last).last(20)

# Inspect a large retained collection and find its path from a heap root:
large_array = $diff.retained.arrays.max_by(&:length)
$after.find_path(large_array)
```

Use the library API for a three-snapshot diff:

```ruby
three_way = Sheap::Diff.new(
	"/var/tmp/worker-1-before.json",
	"/var/tmp/worker-1-after.json",
	"/var/tmp/worker-1-later.json"
)

three_way.retained.map(&:type_str).tally.sort_by(&:last).last(20)
```

`sheap` identifies objects by heap address and type. Heap compaction can move objects, while freed addresses can be reused, so disable automatic compaction during the investigation and prefer a three-snapshot diff. Always compare dumps from the same live worker.

Look for:

- Collection classes whose object count or shallow memory continually grows.
- Repeated strings or payloads that should have expired.
- Paths from roots through registries, caches, queues, or other long-lived state.
- Objects that remain in the three-snapshot diff after comparable GC activity.

### Dominator Analysis with Reap

Reap builds a dominator tree from a single heap's reference graph. An object dominates another object when every path from a heap root to the second object passes through the first. This makes Reap useful for finding a small cache, queue, thread, or registry that keeps a much larger object graph alive.

Reap does not currently accept Ruby's address-less `SHAPE` records. Disable them when capturing a dump for Reap:

```bash
$ bake async:service:supervisor:memory_dump \
    connection_id=1 \
    path=/var/tmp/worker-1-reap.json \
    shapes=false
```

Install Reap with Cargo, then print the largest dominators and optionally generate an inverted flame graph:

```bash
$ cargo install reap
$ reap /var/tmp/worker-1-reap.json \
    --count 20 \
    --flamegraph /var/tmp/worker-1-retained.svg
```

The report separates an object's shallow size from the total memory it dominates. Use `--root ADDRESS` to repeat the analysis for a suspicious subtree, or `--dot FILE` to write its dominator graph. Dumps captured with `shapes=false` remain compatible with `heap-profiler` and `sheap`.

Reap does not compare snapshots or use allocation generations. Combine it with a `sheap` diff when you need both evidence of continued retention and the aggregate size of the retained graph.

## Recording Allocation Locations

By default, a heap dump may not contain allocation source locations. Start tracing on the selected worker before the workload you want to investigate:

```bash
$ bake async:service:supervisor:allocation_trace_start connection_id=1
```

Exercise the workload, then stop tracing and write the heap dump:

```bash
$ bake async:service:supervisor:allocation_trace_stop \
    connection_id=1 \
    path=/var/tmp/worker-1-traced.json
```

The stop operation disables tracing before dumping the heap, then clears the allocation metadata after the dump is complete. Start and stop must target the same live connection ID. Use `shapes=false` with the stop task when the dump will be analyzed by Reap.

Allocation tracing is process-global and adds runtime and memory overhead, so enable it selectively and measure its impact before using it in production. The start task refuses to run if tracing is already active, avoiding interference with another profiler. While tracing is enabled, heap records can include `file`, `line`, `method`, and allocation generation fields. `heap-profiler` automatically includes breakdowns by gem, file, and location when this information is present.

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
3. Enable allocation tracing before the workload if its overhead is acceptable.
4. Capture a baseline heap dump after normal warm-up, using `shapes=false` if you plan to use Reap.
5. Start GC profiling and run representative traffic or wait through the suspected leak interval.
6. Capture scheduler and thread dumps if work appears stuck or backlogged.
7. Stop GC profiling and capture the second heap dump from the same worker.
8. Repeat the workload and capture a third dump for a stronger `sheap` retention signal.
9. Use `heap-profiler` for aggregate counts, `sheap` for retained objects and root paths, and Reap for dominator sizes.
10. Repeat the experiment if necessary to distinguish sustained retention from normal cache warm-up.

Use the {ruby Async::Service::Supervisor::MemoryMonitor} to protect production from unbounded growth, but complete diagnostics before its configured limit restarts the worker. A restarted worker receives a new connection ID and loses the heap state you were observing.
