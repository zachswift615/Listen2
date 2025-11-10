#!/usr/bin/env ruby
require 'xcodeproj'

# Navigate to project directory (relative to script location)
script_dir = File.expand_path(File.dirname(__FILE__))
project_dir = File.join(script_dir, 'Listen2', 'Listen2', 'Listen2')
Dir.chdir(project_dir)

# Open the project
project_path = 'Listen2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
main_target = project.targets.find { |t| t.name == 'Listen2' }

unless main_target
  puts "ERROR: Could not find Listen2 target"
  exit 1
end

puts "🔧 Adding Whisper-tiny ASR model files to Listen2 project..."

# Since this project uses PBXFileSystemSynchronizedRootGroup (Xcode 15+),
# the files will be automatically detected once they're on disk.
# We just need to add folder references to ensure they're in the bundle.

# Model files to add (relative to project directory)
model_files = [
  'Listen2/Resources/ASRModels/whisper-tiny/tiny-encoder.int8.onnx',
  'Listen2/Resources/ASRModels/whisper-tiny/tiny-decoder.int8.onnx',
  'Listen2/Resources/ASRModels/whisper-tiny/tiny-tokens.txt'
]

# Get resources build phase
resources_build_phase = main_target.resources_build_phase

# Check if files are already in resources build phase
existing_files = resources_build_phase.files.map { |f| f.file_ref&.path }.compact

# Add folder reference for ASRModels directory
asr_models_path = 'Listen2/Resources/ASRModels'
existing_asr_ref = project.main_group.recursive_children.find do |child|
  child.path && child.path.include?('ASRModels')
end

if existing_asr_ref
  puts "⏭️  ASRModels folder reference already exists"
else
  # Add folder reference to a regular PBXGroup
  # Find or create a Resources group in the main PBXGroup
  resources_group = project.main_group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == 'Resources' }

  unless resources_group
    resources_group = project.main_group.new_group('Resources')
    puts "✅ Created Resources group"
  end

  # Add folder reference to ASRModels
  folder_ref = resources_group.new_reference(asr_models_path)
  folder_ref.last_known_file_type = 'folder'
  folder_ref.source_tree = '<group>'

  # Add to resources build phase
  resources_build_phase.add_file_reference(folder_ref)

  puts "✅ Added ASRModels folder reference to resources"
end

# Verify files exist on disk
puts "\n📋 Verifying model files on disk:"
total_size = 0
model_files.each do |file_path|
  file_name = File.basename(file_path)

  if File.exist?(file_path)
    file_size_mb = File.size(file_path) / (1024.0 * 1024.0)
    total_size += file_size_mb
    puts "  ✅ #{file_name} (#{file_size_mb.round(1)} MB)"
  else
    puts "  ❌ #{file_name} NOT FOUND"
  end
end

puts "\n📊 Total model size: #{total_size.round(1)} MB"

# Save the project
project.save
puts "\n🎉 Xcode project updated successfully!"
puts "📍 Project: #{project_path}"
puts "\n📦 ASRModels folder added to Copy Bundle Resources build phase"
puts "ℹ️  With PBXFileSystemSynchronizedRootGroup, files are auto-detected from disk"
