#!/usr/bin/env ruby
require 'xcodeproj'

# Navigate to project directory
script_dir = File.expand_path(File.dirname(__FILE__))
project_dir = File.join(script_dir, 'Listen2', 'Listen2')
Dir.chdir(project_dir)

# Open the project
project_path = 'Listen2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the app target
app_target = project.targets.find { |t| t.name == 'Listen2' }

unless app_target
  puts "ERROR: Could not find Listen2 target"
  exit 1
end

puts "🔧 Adding PhonemeAlignmentService to Listen2 project..."

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

# Add PhonemeAlignmentService.swift to app target
service_path = 'Listen2/Services/TTS/PhonemeAlignmentService.swift'
existing_service = project.files.find { |f| f.path&.include?('PhonemeAlignmentService.swift') }

if existing_service
  puts "⏭️  PhonemeAlignmentService.swift already in project"
else
  if File.exist?(service_path)
    file_ref = tts_group.new_file(service_path)
    app_target.source_build_phase.add_file_reference(file_ref)
    puts "✅ Added PhonemeAlignmentService.swift to Listen2 target"
  else
    puts "⚠️  PhonemeAlignmentService.swift not found at #{service_path}"
    puts "   Create the file first, then run this script again."
  end
end

# Save the project
project.save
puts "\n🎉 Xcode project updated successfully!"
puts "📍 Project: #{project_path}"
puts ""
puts "Next steps:"
puts "  1. Update PiperTTSProvider.swift to use PhonemeAlignmentService"
puts "  2. Build and test Listen2"
