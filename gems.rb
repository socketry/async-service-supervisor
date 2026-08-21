# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025-2026, by Samuel Williams.

source "https://rubygems.org"

gemspec

# I don't know why this is needed, but otherwise bundler in GitHub actions fails.
gem "falcon"

group :maintenance, optional: true do
	gem "bake-gem"
	gem "bake-modernize"
	gem "bake-releases"
	
	gem "agent-context"
	
	gem "utopia-project"
	
	gem "decode"
end

group :test do
	gem "sus"
	gem "covered"
	gem "rubocop"
	gem "rubocop-md"
	gem "rubocop-socketry"
	
	gem "sus-fixtures-async"
	gem "sus-fixtures-console"
	
	gem "bake-test"
	
	gem "metrics"
	gem "traces"
end
