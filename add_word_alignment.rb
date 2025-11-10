#!/usr/bin/env ruby
require 'xcodeproj'

# Navigate to project directory (relative to script location)
script_dir = File.expand_path(File.dirname(__FILE__))
project_dir = File.join(script_dir, 'Listen2', 'Listen2')
Dir.chdir(project_dir)

# Open the project
project_path = 'Listen2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the app and test targets
app_target = project.targets.find { |t| t.name == 'Listen2' }
test_target = project.targets.find { |t| t.name == 'Listen2Tests' }

unless app_target
  puts "ERROR: Could not find Listen2 target"
  exit 1
end

unless test_target
  puts "ERROR: Could not find Listen2Tests target"
  exit 1
end

puts "🔧 Adding WordAlignment files to Listen2 project..."

# Find the Services/TTS group
listen2_group = project.main_group.children.find { |c| c.display_name == 'Listen2' }
unless listen2_group
  puts "ERROR: Could not find Listen2 group"
  exit 1
end

services_group = listen2_group.children.find { |c| c.display_name == 'Services' }
unless services_group
  puts "ERROR: Could not find Services group"
  exit 1
end

tts_group = services_group.children.find { |c| c.display_name == 'TTS' }
unless tts_group
  puts "ERROR: Could not find TTS group"
  exit 1
end

# Add AlignmentResult.swift to app target
alignment_result_path = 'Listen2/Services/TTS/AlignmentResult.swift'
existing_alignment_result = project.files.find { |f| f.path&.include?('AlignmentResult.swift') }

if existing_alignment_result
  puts "⏭️  AlignmentResult.swift already in project"
else
  file_ref = tts_group.new_file(alignment_result_path)
  app_target.source_build_phase.add_file_reference(file_ref)
  puts "✅ Added AlignmentResult.swift to Listen2 target"
end

# Add WordAlignmentService.swift to app target
service_path = 'Listen2/Services/TTS/WordAlignmentService.swift'
existing_service = project.files.find { |f| f.path&.include?('WordAlignmentService.swift') }

if existing_service
  puts "⏭️  WordAlignmentService.swift already in project"
else
  file_ref = tts_group.new_file(service_path)
  app_target.source_build_phase.add_file_reference(file_ref)
  puts "✅ Added WordAlignmentService.swift to Listen2 target"
end

# Add WordAlignmentServiceTests.swift to test target
test_file_path = 'Listen2Tests/Services/WordAlignmentServiceTests.swift'
existing_test = project.files.find { |f| f.path&.include?('WordAlignmentServiceTests.swift') }

if existing_test
  puts "⏭️  WordAlignmentServiceTests.swift already in project"
else
  # Find or create Services test group
  tests_group = project.main_group.children.find { |c| c.display_name == 'Listen2Tests' }

  unless tests_group
    puts "ERROR: Could not find Listen2Tests group"
    exit 1
  end

  services_test_group = tests_group.children.find { |c| c.display_name == 'Services' }

  unless services_test_group
    services_test_group = tests_group.new_group('Services')
    puts "✅ Created Services group in Listen2Tests"
  end

  # Add file reference
  file_ref = services_test_group.new_file(test_file_path)
  test_target.source_build_phase.add_file_reference(file_ref)
  puts "✅ Added WordAlignmentServiceTests.swift to Listen2Tests target"
end

# Verify files exist on disk
files_to_check = [
  ['AlignmentResult.swift', alignment_result_path],
  ['WordAlignmentService.swift', service_path],
  ['WordAlignmentServiceTests.swift', test_file_path]
]

puts "\n📋 Verifying files on disk:"
files_to_check.each do |name, path|
  if File.exist?(path)
    file_size_kb = File.size(path) / 1024.0
    puts "  ✅ #{name}: #{file_size_kb.round(1)} KB"
  else
    puts "  ❌ #{name} NOT FOUND at: #{path}"
  end
end

# Save the project
project.save
puts "\n🎉 Xcode project updated successfully!"
puts "📍 Project: #{project_path}"
