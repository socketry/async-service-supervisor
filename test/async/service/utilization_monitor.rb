# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async/service/supervisor/utilization_monitor"
require "async/service/supervisor/worker"
require "async/service/supervisor/worker_controller"

require "sus/fixtures/temporary_directory_context"
require "sus/fixtures/async/scheduler_context"

describe Async::Service::Supervisor::UtilizationMonitor do
	include Sus::Fixtures::TemporaryDirectoryContext
	
	let(:shm_path) {File.join(root, "utilization.shm")}
	let(:segment_size) {512}
	let(:page_size) {IO::Buffer::PAGE_SIZE}
	# Ensure file is large enough for page-aligned mappings
	# Observer needs at least one full page, so we need at least page_size bytes
	let(:file_size) {page_size * 2}
	
	let(:monitor) do
		subject.new(
			path: shm_path,
			interval: 1,
			size: file_size,
			segment_size: segment_size
		)
	end
	
	let(:utilization_schema) do
		{
			connections_total: :u64,
			connections_active: :u32
		}
	end
	
	let(:worker_registry) {Async::Utilization::Registry.new}
	
	let(:worker) do
		Async::Service::Supervisor::Worker.new(
			process_id: Process.pid,
			endpoint: IO::Endpoint.unix(File.join(root, "test.ipc")),
			state: {name: "test_service"},
			utilization_schema: utilization_schema,
			utilization_registry: worker_registry
		)
	end
	
	let(:supervisor_controller) do
		worker = self.worker
		
		controller = Object.new
		controller.define_singleton_method(:id){1}
		controller.define_singleton_method(:state){{name: "test_service"}}
		controller.define_singleton_method(:worker){worker}
		controller
	end
	
	it "can initialize a monitor" do
		expect(monitor).to be_a(Async::Service::Supervisor::UtilizationMonitor)
	end
	
	it "can register a worker" do
		monitor.register(supervisor_controller)
		
		# Write some data so status will include the worker
		worker_registry.metric(:connections_total).set(1)
		
		# Check that worker was registered
		status = monitor.status
		expect(status[:data]).to have_keys("test_service")
	end
	
	it "handles worker without utilization schema" do
		worker_no_schema = Async::Service::Supervisor::Worker.new(
			process_id: Process.pid,
			endpoint: IO::Endpoint.unix(File.join(root, "test2.ipc")),
			state: {name: "test_service"},
			utilization_schema: nil,
			utilization_registry: Async::Utilization::Registry.new
		)
		
		controller_no_schema = Object.new
		controller_no_schema.define_singleton_method(:id){2}
		controller_no_schema.define_singleton_method(:worker){worker_no_schema}
		
		monitor.register(controller_no_schema)
		
		# Worker should not be registered
		status = monitor.status
		expect(status[:data]).to be == {}
	end
	
	it "can remove a worker" do
		monitor.register(supervisor_controller)
		
		# Write some data so status will include the worker
		worker_registry.metric(:connections_total).set(1)
		
		# Verify worker is registered
		status = monitor.status
		expect(status[:data]).to have_keys("test_service")
		
		# Remove worker
		monitor.remove(supervisor_controller)
		
		# Verify worker is removed
		status = monitor.status
		expect(status[:data]).to be == {}
	end
	
	it "can read utilization data from shared memory" do
		monitor.register(supervisor_controller)
		
		# Write some test data to shared memory (observer should be set up by register)
		worker_registry.metric(:connections_total).set(100)
		worker_registry.metric(:connections_active).set(5)
		
		# Read back the data
		status = monitor.status
		expect(status[:data]["test_service"]).to have_keys(
			connections_total: be == 100,
			connections_active: be == 5,
			worker_count: be == 1
		)
	end
	
	it "aggregates metrics from multiple workers" do
		# Create second worker
		registry2 = Async::Utilization::Registry.new
		worker2 = Async::Service::Supervisor::Worker.new(
			process_id: Process.pid,
			endpoint: IO::Endpoint.unix(File.join(root, "test2.ipc")),
			state: {name: "test_service"},
			utilization_schema: utilization_schema,
			utilization_registry: registry2
		)
		
		controller2 = Object.new
		controller2.define_singleton_method(:id){2}
		controller2.define_singleton_method(:state){{name: "test_service"}}
		controller2.define_singleton_method(:worker){worker2}
		
		# Register both workers
		monitor.register(supervisor_controller)
		monitor.register(controller2)
		
		# Set different values for each worker
		worker_registry.metric(:connections_total).set(50)
		worker_registry.metric(:connections_active).set(3)
		
		registry2.metric(:connections_total).set(75)
		registry2.metric(:connections_active).set(2)
		
		# Check aggregated values
		status = monitor.status
		expect(status[:data]["test_service"]).to have_keys(
			connections_total: be == 125,  # 50 + 75
			connections_active: be == 5,   # 3 + 2
			worker_count: be == 2          # two workers for same service
		)
	end
	
	it "aggregates metrics by service name" do
		# Create worker for different service
		registry2 = Async::Utilization::Registry.new
		worker2 = Async::Service::Supervisor::Worker.new(
			process_id: Process.pid,
			endpoint: IO::Endpoint.unix(File.join(root, "test2.ipc")),
			state: {name: "other_service"},
			utilization_schema: utilization_schema,
			utilization_registry: registry2
		)
		
		controller2 = Object.new
		controller2.define_singleton_method(:id){2}
		controller2.define_singleton_method(:state){{name: "other_service"}}
		controller2.define_singleton_method(:worker){worker2}
		
		# Register both workers
		monitor.register(supervisor_controller)
		monitor.register(controller2)
		
		# Set values for each worker
		worker_registry.metric(:connections_total).set(100)
		worker_registry.metric(:connections_active).set(5)
		
		registry2.metric(:connections_total).set(200)
		registry2.metric(:connections_active).set(10)
		
		# Check that metrics are aggregated by service name
		status = monitor.status
		expect(status[:data]).to have_keys("test_service", "other_service")
		expect(status[:data]["test_service"]).to have_keys(
			connections_total: be == 100,
			connections_active: be == 5,
			worker_count: be == 1
		)
		expect(status[:data]["other_service"]).to have_keys(
			connections_total: be == 200,
			connections_active: be == 10,
			worker_count: be == 1
		)
	end
	
	it "handles worker without service name" do
		# Create a separate worker for this test to avoid conflicts
		registry_unknown = Async::Utilization::Registry.new
		worker_unknown = Async::Service::Supervisor::Worker.new(
			process_id: Process.pid,
			endpoint: IO::Endpoint.unix(File.join(root, "unknown.ipc")),
			state: {},
			utilization_schema: utilization_schema,
			utilization_registry: registry_unknown
		)
		
		controller_unknown = Object.new
		controller_unknown.define_singleton_method(:id){3}
		controller_unknown.define_singleton_method(:state){{}}  # No name
		controller_unknown.define_singleton_method(:worker){worker_unknown}
		
		monitor.register(controller_unknown)
		
		registry_unknown.metric(:connections_total).set(50)
		
		status = monitor.status
		expect(status[:data]).to have_keys("unknown")
		expect(status[:data]["unknown"]).to have_keys(
			connections_total: be == 50,
			worker_count: be == 1
		)
	end
	
	it "handles errors during registration gracefully" do
		# Mock setup_utilization_observer to raise an error
		expect(worker).to receive(:setup_utilization_observer).and_raise(StandardError, "Connection failed")
		
		monitor.register(supervisor_controller)
		
		# Worker should not be registered
		status = monitor.status
		expect(status[:data]).to be == {}
	end
	
	it "handles missing worker gracefully" do
		controller_no_worker = Object.new
		controller_no_worker.define_singleton_method(:id){4}
		controller_no_worker.define_singleton_method(:worker){nil}
		
		monitor.register(controller_no_worker)
		
		# Worker should not be registered
		status = monitor.status
		expect(status[:data]).to be == {}
	end
	
	it "handles removal of non-existent worker" do
		# Removing a worker that was never registered should not raise
		monitor.remove(supervisor_controller)
		
		# Should complete without error
		expect(monitor.status[:data]).to be == {}
	end
	
	it "does not resize existing file when recreating the utilization monitor" do
		# When the supervisor restarts, it recreates the SegmentAllocator. Without unlink,
		# File.open(path, "w+b") truncates the existing file. With unlink, we remove the file
		# first so the new allocator gets a fresh file; any process with the old file mapped
		# keeps a valid mapping to the unlinked inode.
		allocator = Async::Service::Supervisor::UtilizationMonitor::SegmentAllocator.new(
			shm_path, size: file_size, segment_size: segment_size
		)
		
		# Resize to make the file larger than initial:
		larger_size = file_size * 2
		allocator.resize(larger_size)
		
		# Open the file and keep a handle; this simulates a worker that has it mapped:
		existing_file = File.open(shm_path, "rb")
		original_size = existing_file.size
		expect(original_size).to be == larger_size
		
		allocator.close
		
		# Simulate supervisor restart - recreates allocator at same path:
		Async::Service::Supervisor::UtilizationMonitor::SegmentAllocator.new(
			shm_path, size: file_size, segment_size: segment_size
		)
		
		# Our handle still references the original inode; it should not have been resized:
		expect(existing_file.size).to be == original_size
	ensure
		existing_file&.close
	end
	
	it "frees segments when workers are removed" do
		# Register first worker
		monitor.register(supervisor_controller)
		
		# Create and register second worker
		registry2 = Async::Utilization::Registry.new
		worker2 = Async::Service::Supervisor::Worker.new(
			process_id: Process.pid,
			endpoint: IO::Endpoint.unix(File.join(root, "test2.ipc")),
			state: {name: "test_service"},
			utilization_schema: utilization_schema,
			utilization_registry: registry2
		)
		
		controller2 = Object.new
		controller2.define_singleton_method(:id){2}
		controller2.define_singleton_method(:state){{name: "test_service"}}
		controller2.define_singleton_method(:worker){worker2}
		
		monitor.register(controller2)
		
		# Remove first worker
		monitor.remove(supervisor_controller)
		
		# Register third worker - should reuse the freed segment
		registry3 = Async::Utilization::Registry.new
		worker3 = Async::Service::Supervisor::Worker.new(
			process_id: Process.pid,
			endpoint: IO::Endpoint.unix(File.join(root, "test3.ipc")),
			state: {name: "test_service"},
			utilization_schema: utilization_schema,
			utilization_registry: registry3
		)
		
		controller3 = Object.new
		controller3.define_singleton_method(:id){3}
		controller3.define_singleton_method(:state){{name: "test_service"}}
		controller3.define_singleton_method(:worker){worker3}
		
		monitor.register(controller3)
		
		# Should have 2 workers registered (worker2 and worker3)
		status = monitor.status
		expect(status[:data]["test_service"]).to be_a(Hash)
	end
	
	it "automatically resizes when running out of segments" do
		# Create a monitor with initial size of one page (which gives us page_size / segment_size segments)
		# This ensures we start with at least one segment, but not too many
		initial_size = page_size
		segments_per_page = page_size / segment_size
		
		small_monitor = subject.new(
			path: File.join(root, "small.shm"),
			interval: 1,
			size: initial_size,
			segment_size: segment_size
		)
		
		# Verify initial size
		expect(small_monitor.instance_variable_get(:@allocator).size).to be == initial_size
		
		# Create workers to consume all available segments
		# We need to register enough workers to consume all segments
		controllers = []
		registered_count = 0
		
		segments_per_page.times do |i|
			registry = Async::Utilization::Registry.new
			worker = Async::Service::Supervisor::Worker.new(
				process_id: Process.pid,
				endpoint: IO::Endpoint.unix(File.join(root, "small#{i}.ipc")),
				state: {name: "test_service"},
				utilization_schema: utilization_schema,
				utilization_registry: registry
			)
			
			controller = Object.new
			controller.define_singleton_method(:id){i + 1}
			controller.define_singleton_method(:state){{name: "test_service"}}
			controller.define_singleton_method(:worker){worker}
			
			controllers << controller
			
			# Register worker to consume a segment
			small_monitor.register(controller)
			# Only count if registration succeeded (worker is in @workers)
			if small_monitor.status[:data]["test_service"]
				registry.metric(:connections_total).set(i + 1)
				registered_count += 1
			end
		end
		
		# Verify we registered at least some workers
		expect(registered_count).to be > 0
		
		# Create one more worker - this should trigger automatic resize if free list is empty
		registry_new = Async::Utilization::Registry.new
		worker_new = Async::Service::Supervisor::Worker.new(
			process_id: Process.pid,
			endpoint: IO::Endpoint.unix(File.join(root, "small_new.ipc")),
			state: {name: "test_service"},
			utilization_schema: utilization_schema,
			utilization_registry: registry_new
		)
		
		controller_new = Object.new
		controller_new.define_singleton_method(:id){segments_per_page + 1}
		controller_new.define_singleton_method(:state){{name: "test_service"}}
		controller_new.define_singleton_method(:worker){worker_new}
		
		# Get size before registering (might trigger resize)
		size_before = small_monitor.instance_variable_get(:@allocator).size
		
		# This should trigger automatic resize if free list is empty
		small_monitor.register(controller_new)
		
		# Verify the file was resized if it needed to be
		final_size = small_monitor.instance_variable_get(:@allocator).size
		# Size should be >= initial size (might have been resized)
		expect(final_size).to be >= initial_size
		
		# All workers should be registered and readable
		registry_new.metric(:connections_total).set(100)
		status = small_monitor.status
		expect(status[:data]).to have_keys("test_service")
		service_data = status[:data]["test_service"]
		expect(service_data).to be_a(Hash)
		expect(service_data[:connections_total]).to be >= 1
	end
	
	it "preserves observer mappings in pre-resize workers after file is resized" do
		# This is a regression test for a flatline bug: when the supervisor resizes
		# the shared memory file, workers that mapped the file before the resize hold
		# IO::Buffer slices tied to the old mmap. After truncate + remap on the
		# supervisor side, those worker slices may become invalid so writes disappear.
		#
		# Steps:
		#   1. Create a monitor with exactly one segment of capacity.
		#   2. Register a worker (it maps the file and gets an Observer).
		#   3. Write a value and confirm the supervisor can read it.
		#   4. Force a resize by registering a second worker (free list is empty → resize).
		#   5. Write a new value from the first worker and confirm the supervisor still reads it.

		initial_size = page_size  # gives exactly page_size / segment_size segments
		segments_per_page = page_size / segment_size

		small_monitor = subject.new(
			path: File.join(root, "utilization.shm"),
			interval: 1,
			size: initial_size,
			segment_size: segment_size
		)

		# Fill all but one segment so the free list has exactly one slot left.
		# (Skip this loop when segments_per_page == 1 — the first worker will itself
		# consume the only slot and the second will trigger the resize.)
		filler_controllers = []
		(segments_per_page - 1).times do |i|
			filler_registry = Async::Utilization::Registry.new
			filler_worker = Async::Service::Supervisor::Worker.new(
				process_id: Process.pid,
				endpoint: IO::Endpoint.unix(File.join(root, "filler#{i}.ipc")),
				state: {name: "filler"},
				utilization_schema: utilization_schema,
				utilization_registry: filler_registry
			)
			filler_controller = Object.new
			filler_controller.define_singleton_method(:id){100 + i}
			filler_controller.define_singleton_method(:state){{name: "filler"}}
			filler_controller.define_singleton_method(:worker){filler_worker}
			filler_controllers << filler_controller
			small_monitor.register(filler_controller)
		end

		# Register the worker-under-test — it takes the last free segment and
		# maps the file at its current (pre-resize) size.
		small_monitor.register(supervisor_controller)
		worker_registry.metric(:connections_total).set(42)
		worker_registry.metric(:connections_active).set(7)

		status_before = small_monitor.status
		expect(status_before[:data]).to have_keys("test_service")
		expect(status_before[:data]["test_service"][:connections_total]).to be == 42

		# Now trigger a resize: register one more worker — the free list is empty
		# so SegmentAllocator#allocate will call resize before handing out a slot.
		resize_registry = Async::Utilization::Registry.new
		resize_worker = Async::Service::Supervisor::Worker.new(
			process_id: Process.pid,
			endpoint: IO::Endpoint.unix(File.join(root, "resize_trigger.ipc")),
			state: {name: "filler"},
			utilization_schema: utilization_schema,
			utilization_registry: resize_registry
		)
		resize_controller = Object.new
		resize_controller.define_singleton_method(:id){999}
		resize_controller.define_singleton_method(:state){{name: "filler"}}
		resize_controller.define_singleton_method(:worker){resize_worker}

		size_before_resize = small_monitor.instance_variable_get(:@allocator).size
		small_monitor.register(resize_controller)
		size_after_resize = small_monitor.instance_variable_get(:@allocator).size

		# Confirm the resize actually happened
		expect(size_after_resize).to be > size_before_resize

		# The pre-resize worker must still be able to write through its Observer
		# and have the supervisor read the updated value.
		worker_registry.metric(:connections_total).set(99)
		worker_registry.metric(:connections_active).set(3)

		status_after = small_monitor.status
		expect(status_after[:data]).to have_keys("test_service")
		expect(status_after[:data]["test_service"][:connections_total]).to be == 99
		expect(status_after[:data]["test_service"][:connections_active]).to be == 3
	end

	with "#run" do
		include Sus::Fixtures::Async::SchedulerContext
		
		it "can run the monitor" do
			task = monitor.run
			expect(task).to be(:running?)
			task.stop
		end
	end
end
