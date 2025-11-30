#!/usr/bin/env ruby
require 'xcodeproj'

# Open project
project_path = File.join(Dir.pwd, 'Listen2', 'Listen2', 'Listen2.xcodeproj')
project = Xcodeproj::Project.open(project_path)

# Get main target
target = project.targets.find { |t| t.name == 'Listen2' }

unless target
  puts "ERROR: Could not find Listen2 target"
  exit 1
end

# Check if package already exists
existing_package = project.root_object.package_references.find do |ref|
  ref.requirement.to_s.include?('SWCompression')
end

if existing_package
  puts "✅ SWCompression package already exists"
  exit 0
end

# Add package reference
package_ref = project.root_object.add_package_reference(
  'https://github.com/tsolomko/SWCompression',
  kind: 'remote',
  requirement: {
    kind: 'upToNextMajorVersion',
    minimumVersion: '4.8.6'
  }
)

puts "✅ Added SWCompression package reference"

# Add package product dependency to target
target.package_product_dependencies << project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency).tap do |dep|
  dep.package = package_ref
  dep.product_name = 'SWCompression'
end

puts "✅ Added SWCompression to target dependencies"

# Save project
project.save

puts "\n✅ Successfully added SWCompression to project!"
