# frozen_string_literal: true

require_relative "lib/async/service/supervisor/version"

Gem::Specification.new do |spec|
	spec.name = "async-service-supervisor"
	spec.version = Async::Service::Supervisor::VERSION
	
	spec.summary = "A supervisor for managing multiple container processes."
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"
	
	spec.cert_chain  = ["release.cert"]
	spec.signing_key = File.expand_path("~/.gem/release.pem")
	
	spec.homepage = "https://github.com/socketry/async-service-supervisor"
	
	spec.metadata = {
		"documentation_uri" => "https://socketry.github.io/async-service-supervisor/",
		"source_code_uri" => "https://github.com/socketry/async-service-supervisor.git",
	}
	
	spec.files = Dir.glob(["{bake,context,lib}/**/*", "*.md"], File::FNM_DOTMATCH, base: __dir__)
	
	spec.required_ruby_version = ">= 3.2"
	
	spec.add_dependency "async-bus"
	spec.add_dependency "async-service", "~> 0.15"
	spec.add_dependency "io-endpoint"
	spec.add_dependency "memory", "~> 0.7"
	spec.add_dependency "memory-leak", "~> 0.5"
	spec.add_dependency "process-metrics"
end
