#!/usr/bin/env ruby
require 'xcodeproj'

# Navigate to project directory
Dir.chdir('/Users/zachswift/projects/Listen2/Listen2/Listen2')

# Open the project
project_path = 'Listen2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get main target
main_target = project.targets.find { |t| t.name == 'Listen2' }

unless main_target
  puts "ERROR: Could not find Listen2 target"
  exit 1
end

puts "Checking for duplicate SherpaOnnx.swift references..."

# Get source build phase
sources_phase = main_target.source_build_phase

# Find SherpaOnnx.swift files
sherpa_files = sources_phase.files.select do |build_file|
  file_ref = build_file.file_ref
  file_ref && file_ref.path && file_ref.path.include?('SherpaOnnx.swift')
end

if sherpa_files.empty?
  puts "❌ No SherpaOnnx.swift found"
  exit 0
end

puts "Found #{sherpa_files.size} SherpaOnnx.swift reference(s)"
sherpa_files.each_with_index do |build_file, idx|
  file_ref = build_file.file_ref
  puts "  #{idx + 1}. #{file_ref.path} (UUID: #{file_ref.uuid})"
end

if sherpa_files.size > 1
  puts "\n⚠️  Found duplicate! Removing extras..."

  # Keep the first, remove the rest
  sherpa_files[1..-1].each do |build_file|
    puts "  Removing duplicate: #{build_file.file_ref.path}"
    sources_phase.files.delete(build_file)
  end

  # Save the project
  project.save
  puts "\n✅ Removed #{sherpa_files.size - 1} duplicate reference(s)"
else
  puts "\n✅ No duplicates found"
end
