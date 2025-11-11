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

puts "Analyzing build phases for target: #{main_target.name}"
puts "=" * 60

# Check Copy Files phases
copy_phases = main_target.copy_files_build_phases
puts "\n📦 Copy Files Build Phases: #{copy_phases.size}"
copy_phases.each_with_index do |phase, idx|
  puts "\nPhase #{idx + 1}: #{phase.name || 'Unnamed'}"
  puts "  Destination: #{phase.dst_subfolder_spec}"
  puts "  Files: #{phase.files_references.size}"

  # Look for espeak-ng-data files
  espeak_files = phase.files_references.select { |f| f.path && f.path.include?('espeak-ng-data') }
  if espeak_files.any?
    puts "  ⚠️  Found #{espeak_files.size} espeak-ng-data files"
    espeak_files.first(5).each do |f|
      puts "    - #{f.path}"
    end
    puts "    ... and #{espeak_files.size - 5} more" if espeak_files.size > 5
  end
end

# Check Resources phase
resources_phase = main_target.resources_build_phase
puts "\n📦 Resources Build Phase:"
puts "  Total files: #{resources_phase.files_references.size}"

# Look for espeak-ng-data files in resources
espeak_files = resources_phase.files_references.select { |f| f.path && f.path.include?('espeak-ng-data') }
if espeak_files.any?
  puts "  ⚠️  Found #{espeak_files.size} espeak-ng-data files"
  espeak_files.first(5).each do |f|
    puts "    - #{f.path}"
  end
  puts "    ... and #{espeak_files.size - 5} more" if espeak_files.size > 5
end

# Check for PBXFileSystemSynchronizedRootGroup
puts "\n📁 Checking for File System Synchronized Groups:"
synchronized_groups = project.objects.select { |obj| obj.isa == 'PBXFileSystemSynchronizedRootGroup' }
puts "  Found #{synchronized_groups.size} synchronized groups"
synchronized_groups.each do |group|
  puts "  - #{group.path}"
end

puts "\n" + "=" * 60
puts "\n💡 Analysis:"
puts "If espeak-ng-data files appear in BOTH:"
puts "  1. A File System Synchronized Group AND"
puts "  2. The Resources Build Phase"
puts "Then we have duplicates that need to be removed from one location."
