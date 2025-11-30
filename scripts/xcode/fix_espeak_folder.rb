#!/usr/bin/env ruby
require 'xcodeproj'

# Navigate to project directory
Dir.chdir('/Users/zachswift/projects/Listen2/.worktrees/feature-piper-tts-integration/Listen2/Listen2')

# Open the project
project_path = 'Listen2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
main_target = project.targets.find { |t| t.name == 'Listen2' }

unless main_target
  puts "ERROR: Could not find Listen2 target"
  exit 1
end

puts "🔧 Fixing espeak-ng-data directory structure..."

# Note: PBXFileSystemSynchronizedRootGroup will flatten files, but when we add
# espeak-ng-data as a separate folder reference, it will preserve its structure

# Step 1: Add espeak-ng-data as a folder reference (preserves directory structure)
espeak_source_path = 'Listen2/Resources/PiperModels/espeak-ng-data'
full_espeak_path = File.expand_path(espeak_source_path, Dir.pwd)

unless File.directory?(full_espeak_path)
  puts "ERROR: espeak-ng-data directory not found at #{full_espeak_path}"
  exit 1
end

# Check if espeak-ng-data folder reference already exists
existing_folder = project.main_group.recursive_children.find do |child|
  child.respond_to?(:path) && child.path && child.path.to_s.include?('espeak-ng-data')
end

if existing_folder
  puts "⏭️  espeak-ng-data folder reference already exists"
  folder_ref = existing_folder
else
  # Create folder reference (blue folder in Xcode)
  # Use source_tree 'SOURCE_ROOT' and set path relative to project
  folder_ref = project.main_group.new_reference(espeak_source_path)
  folder_ref.last_known_file_type = 'folder'
  folder_ref.source_tree = 'SOURCE_ROOT'

  puts "✅ Added espeak-ng-data as folder reference (preserves structure)"
end

# Step 2: Add to Copy Bundle Resources build phase
resources_build_phase = main_target.resources_build_phase

# Check if already in build phase
already_in_build_phase = resources_build_phase.files.any? do |build_file|
  build_file.file_ref == folder_ref
end

if already_in_build_phase
  puts "⏭️  espeak-ng-data already in Copy Bundle Resources"
else
  resources_build_phase.add_file_reference(folder_ref)
  puts "✅ Added espeak-ng-data to Copy Bundle Resources"
end

# Save the project
project.save
puts "✅ Project saved successfully"

puts "\n🎉 espeak-ng-data will now preserve its directory structure!"
puts "📍 Project: #{project_path}"
puts "\n⚠️  IMPORTANT: You may need to:"
puts "   1. Clean build folder in Xcode (Cmd+Shift+K)"
puts "   2. Remove espeak-ng-data files from Resources if duplicated"
puts "   3. Rebuild the app"
