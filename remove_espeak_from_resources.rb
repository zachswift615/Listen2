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

puts "Looking for espeak-ng-data in Resources Build Phase..."

# Get resources phase
resources_phase = main_target.resources_build_phase

# Find espeak-ng-data files
espeak_files = resources_phase.files.select do |build_file|
  file_ref = build_file.file_ref
  file_ref && file_ref.path && file_ref.path.include?('espeak-ng-data')
end

if espeak_files.empty?
  puts "❌ No espeak-ng-data found in Resources Build Phase"
  exit 0
end

puts "✅ Found #{espeak_files.size} espeak-ng-data reference(s)"

espeak_files.each do |build_file|
  file_ref = build_file.file_ref
  puts "  Removing: #{file_ref.path}"

  # Remove the build file from the resources phase
  resources_phase.files.delete(build_file)

  # Also remove the file reference from the project
  file_ref.remove_from_project if file_ref.referrers.empty?
end

# Save the project
project.save

puts "\n✅ Successfully removed espeak-ng-data from Resources Build Phase"
puts "The files will still be included via the File System Synchronized Group"
puts "\nNow rebuild the project!"
