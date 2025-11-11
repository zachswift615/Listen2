#!/usr/bin/env ruby
require 'xcodeproj'

# Navigate to project directory
Dir.chdir('/Users/zachswift/projects/Listen2/Listen2/Listen2')

# Open the project
project_path = 'Listen2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

puts "Scanning for duplicate file references..."

# Track all file references by their path
file_paths = Hash.new { |h, k| h[k] = [] }

# Collect all file references
project.files.each do |file_ref|
  next unless file_ref.path
  file_paths[file_ref.path] << file_ref
end

# Find duplicates
duplicates = file_paths.select { |path, refs| refs.size > 1 }

if duplicates.empty?
  puts "No duplicate file references found!"
  exit 0
end

puts "Found #{duplicates.size} duplicate file paths:"
duplicates.each do |path, refs|
  puts "  - #{path} (#{refs.size} references)"
end

puts "\nRemoving duplicate references..."
removed_count = 0

duplicates.each do |path, refs|
  # Keep the first reference, remove the rest
  refs[1..-1].each do |ref|
    puts "  Removing duplicate: #{path}"
    ref.remove_from_project
    removed_count += 1
  end
end

puts "\nRemoved #{removed_count} duplicate file references"

# Save the project
project.save

puts "✅ Project saved successfully!"
puts "\nNow run: xcodebuild clean && xcodebuild build"
