#!/usr/bin/env ruby

# Fix duplicate resource copying issue in Xcode project
# The issue is caused by files being both explicitly in Resources build phase
# AND included via fileSystemSynchronizedGroups

require 'xcodeproj'

project_path = 'Listen2/Listen2/Listen2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main app target
main_target = project.targets.find { |t| t.name == 'Listen2' }

if main_target.nil?
  puts "ERROR: Could not find Listen2 target"
  exit 1
end

# Find the Resources build phase
resources_phase = main_target.resources_build_phase

if resources_phase.nil?
  puts "ERROR: Could not find Resources build phase"
  exit 1
end

# Files to remove from explicit Resources (they'll be included via synchronized folder)
files_to_remove = [
  'nemo-ctc-model.int8.onnx',
  'nemo-ctc-tokens.txt'
]

removed_count = 0

# Remove the explicit file references from Resources build phase
files_to_delete = []

resources_phase.files.each do |build_file|
  if build_file.file_ref
    file_name = build_file.file_ref.name || build_file.file_ref.path
    file_path = build_file.file_ref.path

    # Check both name and path for the files we want to remove
    if files_to_remove.any? { |f|
      (file_name&.include?(f) || file_path&.include?(f))
    }
      puts "Found file to remove: #{file_name || file_path}"
      files_to_delete << build_file
      removed_count += 1
    end
  end
end

# Actually delete the files (doing it outside the iteration to avoid issues)
files_to_delete.each do |build_file|
  resources_phase.files.delete(build_file)
  puts "Removed: #{build_file.file_ref.name || build_file.file_ref.path}"
end

if removed_count > 0
  puts "\n✅ Removed #{removed_count} duplicate resource references"
  puts "Saving project..."
  project.save
  puts "Project saved successfully!"
  puts "\nThe NeMo model files will still be included in the app bundle via fileSystemSynchronizedGroups."
  puts "This should resolve the 'Multiple commands produce' error."
else
  puts "⚠️  No duplicate references found to remove."
  puts "The files might have already been removed or the issue is different."
end

puts "\nNext steps:"
puts "1. Open Xcode"
puts "2. Clean Build Folder (Cmd+Shift+K)"
puts "3. Try building again"