#!/usr/bin/env ruby
require 'xcodeproj'

# Navigate to project directory (relative to script location)
script_dir = File.expand_path(File.dirname(__FILE__))
project_dir = File.join(script_dir, 'Listen2', 'Listen2')
Dir.chdir(project_dir)

# Open the project
project_path = 'Listen2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the test target
test_target = project.targets.find { |t| t.name == 'Listen2Tests' }

unless test_target
  puts "ERROR: Could not find Listen2Tests target"
  exit 1
end

puts "🔧 Adding ASRModelLoadingTests.swift to Listen2Tests target..."

# Test file path (relative to project directory)
test_file_path = 'Listen2Tests/Services/ASRModelLoadingTests.swift'

# Check if file already exists in project
existing_ref = project.files.find { |f| f.path&.include?('ASRModelLoadingTests.swift') }

if existing_ref
  puts "⏭️  ASRModelLoadingTests.swift already in project"
else
  # Find or create Services test group
  tests_group = project.main_group.children.find { |c| c.display_name == 'Listen2Tests' }

  unless tests_group
    puts "ERROR: Could not find Listen2Tests group"
    exit 1
  end

  services_group = tests_group.children.find { |c| c.display_name == 'Services' }

  unless services_group
    services_group = tests_group.new_group('Services')
    puts "✅ Created Services group in Listen2Tests"
  end

  # Add file reference
  file_ref = services_group.new_file(test_file_path)

  # Add to test target's sources build phase
  test_target.source_build_phase.add_file_reference(file_ref)

  puts "✅ Added ASRModelLoadingTests.swift to Listen2Tests target"
end

# Verify file exists on disk
if File.exist?(test_file_path)
  file_size_kb = File.size(test_file_path) / 1024.0
  puts "\n📋 Test file verified: #{file_size_kb.round(1)} KB"
else
  puts "\n❌ Test file NOT FOUND on disk: #{test_file_path}"
end

# Save the project
project.save
puts "\n🎉 Xcode project updated successfully!"
puts "📍 Project: #{project_path}"
