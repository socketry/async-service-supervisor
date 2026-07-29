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

## Comparing Snapshots

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

Start by summarizing object counts and shallow memory size by Ruby heap type. The following shell function processes the dump as a stream, so `jq` does not need to load the entire heap into memory:

```bash
summarize_heap() {
    jq -r 'select(.type != null) | [.type, (.memsize // 0)] | @tsv' "$1" |
        awk -F '\t' '
            {count[$1] += 1; bytes[$1] += $2}
            END {
                for (type in count)
                    printf "%s\t%d\t%d\n", type, count[type], bytes[type]
            }
        ' |
        sort
}

summarize_heap /var/tmp/worker-1-before.json > before.types
summarize_heap /var/tmp/worker-1-after.json > after.types
diff -u before.types after.types
```

The columns are heap type, object count, and total shallow `memsize`. Large increases in types such as `STRING`, `ARRAY`, `HASH`, `OBJECT`, or `DATA` provide a direction for deeper analysis. The `class` field is an address; heap-analysis tools resolve it through the corresponding `CLASS` record to recover the Ruby class name. Shallow size does not include all objects referenced by a container, so counts and reference graphs matter as much as byte totals.

Heap records contain addresses and `references` arrays that heap-analysis tools can use to build an object graph. When investigating retention, look for:

- Collections whose referenced object count continually grows.
- Repeated strings or payloads that should have expired.
- Objects reachable from long-lived roots, class variables, registries, caches, or queues.
- Growth that remains across multiple snapshots captured after comparable GC activity.

A two-snapshot difference is evidence of growth, not necessarily a leak. Confirm that the same classes continue growing across several workload and GC cycles.

## Recording Allocation Locations

By default, a heap dump may not contain allocation source locations. To record them, enable ObjectSpace allocation tracing in the worker before the workload you want to investigate:

```ruby
require "objspace"
ObjectSpace.trace_object_allocations_start
```

Allocation tracing adds runtime and memory overhead, so enable it selectively and measure its impact before using it in production. When tracing is enabled, heap records can include `file`, `line`, `method`, and allocation generation fields.

Summarize traced allocation locations with:

```bash
$ jq -r \
    'select(.file != null) | [.file, (.line // 0), (.memsize // 0)] | @tsv' \
    /var/tmp/worker-1-after.json |
    awk -F '\t' '
        {location = $1 ":" $2; count[location] += 1; bytes[location] += $3}
        END {
            for (location in count)
                printf "%12d %12d %s\n", count[location], bytes[location], location
        }
    ' |
    sort -nr |
    head -50
```

High allocation counts identify hot allocation sites. Compare snapshots and focus on locations whose objects remain present and continue accumulating, rather than sites that merely allocate many short-lived objects.

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
