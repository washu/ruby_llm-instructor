#!/bin/bash
set -e

# Extract version from version.rb
VERSION=$(ruby -r ./lib/ruby_llm/instructor/version.rb -e "puts RubyLLM::Instructor::VERSION")

echo "Building gem version ${VERSION}..."
gem build ruby_llm-instructor.gemspec

echo "Pushing to RubyGems..."
gem push ruby_llm-instructor-${VERSION}.gem

echo "Done!"
