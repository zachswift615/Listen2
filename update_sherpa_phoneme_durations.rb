#!/usr/bin/env ruby
require 'xcodeproj'

# Navigate to project directory
script_dir = File.expand_path(File.dirname(__FILE__))
project_dir = File.join(script_dir, 'Listen2', 'Listen2')
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

puts "🔧 Updating sherpa-onnx.xcframework with phoneme duration support..."

# Step 1: Remove old sherpa-onnx.xcframework reference if exists
old_framework = project.main_group.recursive_children.find do |child|
  child.path && child.path.include?('sherpa-onnx.xcframework')
end

if old_framework
  puts "📦 Found existing sherpa-onnx.xcframework reference"

  # Remove from frameworks build phase
  frameworks_build_phase = main_target.frameworks_build_phase
  frameworks_build_phase.files.each do |file|
    if file.file_ref&.path&.include?('sherpa-onnx.xcframework')
      frameworks_build_phase.remove_file_reference(file.file_ref)
      puts "✅ Removed old framework from build phase"
    end
  end

  # Remove file reference
  old_framework.remove_from_project
  puts "✅ Removed old framework reference"
else
  puts "⏭️  No existing sherpa-onnx.xcframework found"
end

# Step 2: Add new sherpa-onnx.xcframework (from our modified build)
new_framework_path = '/Users/zachswift/projects/sherpa-onnx/build-ios/sherpa-onnx.xcframework'

unless File.exist?(new_framework_path)
  puts "❌ ERROR: New sherpa-onnx.xcframework not found at #{new_framework_path}"
  puts "   Make sure the build completed successfully."
  exit 1
end

# Create a reference to the new framework
framework_ref = project.main_group.new_reference(new_framework_path)
framework_ref.last_known_file_type = 'wrapper.xcframework'

# Add to frameworks build phase
frameworks_build_phase = main_target.frameworks_build_phase
frameworks_build_phase.add_file_reference(framework_ref)

puts "✅ Added new sherpa-onnx.xcframework with phoneme duration support"

# Step 3: Ensure framework search path is correct
build_config_names = ['Debug', 'Release']

build_config_names.each do |config_name|
  config = main_target.build_configurations.find { |c| c.name == config_name }

  framework_search_paths = config.build_settings['FRAMEWORK_SEARCH_PATHS'] || []
  framework_search_paths = [framework_search_paths] unless framework_search_paths.is_a?(Array)

  search_path = '/Users/zachswift/projects/sherpa-onnx/build-ios'
  unless framework_search_paths.include?(search_path)
    framework_search_paths << search_path
    config.build_settings['FRAMEWORK_SEARCH_PATHS'] = framework_search_paths.uniq
    puts "✅ #{config_name}: Added framework search path"
  else
    puts "⏭️  #{config_name}: Framework search path already set"
  end
end

# Save the project
project.save
puts "\n🎉 Xcode project updated successfully!"
puts "📍 Project: #{project_path}"
puts ""
puts "Next steps:"
puts "  1. Wait for sherpa-onnx build to complete"
puts "  2. Run: ruby add_phoneme_alignment_service.rb"
puts "  3. Build and test Listen2"
