#!/usr/bin/env ruby
require 'xcodeproj'

# Navigate to project directory
Dir.chdir('/Users/zachswift/projects/Listen2/.worktrees/feature-piper-tts-integration/Listen2/Listen2')

# Open the project
project_path = 'Listen2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get targets
main_target = project.targets.find { |t| t.name == 'Listen2' }
test_target = project.targets.find { |t| t.name == 'Listen2Tests' }

unless main_target && test_target
  puts "ERROR: Could not find targets"
  puts "Available targets: #{project.targets.map(&:name).join(', ')}"
  exit 1
end

puts "Found targets: #{main_target.name}, #{test_target.name}"

# Helper to find or create group
def find_or_create_group(parent, path_components)
  current = parent
  path_components.each do |component|
    existing = current.children.find { |child| child.is_a?(Xcodeproj::Project::Object::PBXGroup) && child.display_name == component }
    if existing
      current = existing
    else
      current = current.new_group(component)
    end
  end
  current
end

# Get the main Listen2 group
main_group = project.main_group['Listen2'] || project.main_group.new_group('Listen2')

# Create Services/TTS group
services_group = find_or_create_group(main_group, ['Services'])
tts_group = find_or_create_group(services_group, ['TTS'])

# Create Services/Voice group
voice_group = find_or_create_group(services_group, ['Voice'])

# Create Models group
models_group = find_or_create_group(main_group, ['Models'])

# Create Resources group
resources_group = find_or_create_group(main_group, ['Resources'])

# Add Swift files to appropriate groups
files_to_add = [
  {
    path: 'Listen2/Services/TTS/TTSProvider.swift',
    group: tts_group,
    target: main_target
  },
  {
    path: 'Listen2/Services/TTS/PiperTTSProvider.swift',
    group: tts_group,
    target: main_target
  },
  {
    path: 'Listen2/Services/Voice/VoiceManager.swift',
    group: voice_group,
    target: main_target
  },
  {
    path: 'Listen2/Models/Voice.swift',
    group: models_group,
    target: main_target
  }
]

files_to_add.each do |file_info|
  file_path = file_info[:path]
  next unless File.exist?(file_path)

  # Check if already added
  existing = file_info[:group].children.find { |c| c.display_name == File.basename(file_path) }
  if existing
    puts "⏭️  Skipping #{file_path} (already in project)"
    next
  end

  file_ref = file_info[:group].new_file(file_path)
  file_info[:target].add_file_references([file_ref])
  puts "✅ Added #{file_path} to #{file_info[:target].name}"
end

# Add test file
test_file_path = '../Listen2Tests/VoiceManagerTests.swift'
if File.exist?(test_file_path)
  tests_group = project.main_group['Listen2Tests'] || project.main_group.new_group('Listen2Tests')
  existing_test = tests_group.children.find { |c| c.display_name == 'VoiceManagerTests.swift' }

  unless existing_test
    test_file_ref = tests_group.new_file(test_file_path)
    test_target.add_file_references([test_file_ref])
    puts "✅ Added VoiceManagerTests.swift to #{test_target.name}"
  else
    puts "⏭️  Skipping VoiceManagerTests.swift (already in project)"
  end
end

# Add resource file
resource_path = 'Listen2/Resources/voice-catalog.json'
if File.exist?(resource_path)
  existing_resource = resources_group.children.find { |c| c.display_name == 'voice-catalog.json' }

  unless existing_resource
    resource_ref = resources_group.new_file(resource_path)
    main_target.add_file_references([resource_ref])
    # Add to resources build phase
    resources_build_phase = main_target.resources_build_phase
    resources_build_phase.add_file_reference(resource_ref)
    puts "✅ Added voice-catalog.json to resources"
  else
    puts "⏭️  Skipping voice-catalog.json (already in project)"
  end
end

# Save the project
project.save
puts "\n🎉 Xcode project updated successfully!"
puts "📍 Project: #{project_path}"
