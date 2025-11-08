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

puts "🔧 Configuring Listen2 project for sherpa-onnx..."

# Step 1: Add the XCFramework
framework_path = '/private/tmp/sherpa-onnx/build-ios/sherpa-onnx.xcframework'

unless File.exist?(framework_path)
  puts "ERROR: sherpa-onnx.xcframework not found at #{framework_path}"
  exit 1
end

# Check if framework is already added
existing_framework = project.main_group.recursive_children.find do |child|
  child.path && child.path.include?('sherpa-onnx.xcframework')
end

if existing_framework
  puts "⏭️  sherpa-onnx.xcframework already in project"
else
  # Create a reference to the framework
  framework_ref = project.main_group.new_reference(framework_path)
  framework_ref.last_known_file_type = 'wrapper.xcframework'

  # Add to frameworks build phase (static linking)
  frameworks_build_phase = main_target.frameworks_build_phase
  frameworks_build_phase.add_file_reference(framework_ref)

  puts "✅ Added sherpa-onnx.xcframework to project"
end

# Ensure it's NOT in embed frameworks phase (static library - Do Not Embed)
embed_phase = main_target.copy_files_build_phases.find { |phase|
  phase.dst_subfolder_spec == Xcodeproj::Constants::COPY_FILES_BUILD_PHASE_DESTINATIONS[:frameworks]
}

if embed_phase
  removed = embed_phase.files.reject! do |file|
    file.file_ref&.path&.include?('sherpa-onnx.xcframework')
  end
  puts "✅ Ensured sherpa-onnx.xcframework is not embedded (static library)" if removed
end

# Step 2: Configure Build Settings
build_config_names = ['Debug', 'Release']

build_config_names.each do |config_name|
  config = main_target.build_configurations.find { |c| c.name == config_name }

  # Set Objective-C Bridging Header
  current_bridging_header = config.build_settings['SWIFT_OBJC_BRIDGING_HEADER']
  if current_bridging_header == 'Listen2/Listen2-Bridging-Header.h'
    puts "⏭️  #{config_name}: Bridging header already set"
  else
    config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'Listen2/Listen2-Bridging-Header.h'
    puts "✅ #{config_name}: Set bridging header to Listen2/Listen2-Bridging-Header.h"
  end

  # Add Framework Search Path
  framework_search_paths = config.build_settings['FRAMEWORK_SEARCH_PATHS'] || []
  framework_search_paths = [framework_search_paths] unless framework_search_paths.is_a?(Array)

  search_path = '/private/tmp/sherpa-onnx/build-ios'
  if framework_search_paths.include?(search_path)
    puts "⏭️  #{config_name}: Framework search path already includes #{search_path}"
  else
    framework_search_paths << search_path
    config.build_settings['FRAMEWORK_SEARCH_PATHS'] = framework_search_paths.uniq
    puts "✅ #{config_name}: Added framework search path"
  end
end

# Save the project
project.save
puts "✅ Project saved successfully"

puts "\n🎉 Xcode project configuration complete!"
puts "📍 Project: #{project_path}"
puts "\n🔨 Next: Building to verify configuration..."
