#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'Listen2/Listen2/Listen2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find the main target
target = project.targets.find { |t| t.name == 'Listen2' }

# Find or create ASRModels group
resources_group = project.main_group.groups.find { |g| g.name == 'Resources' } ||
                  project.main_group.new_group('Resources')
asr_models_group = resources_group.groups.find { |g| g.name == 'ASRModels' } ||
                   resources_group.new_group('ASRModels', 'Listen2/Listen2/Listen2/Resources/ASRModels')

# Create nemo-ctc group
nemo_group = asr_models_group.new_group('nemo-ctc-conformer-small',
                                         'Listen2/Listen2/Listen2/Resources/ASRModels/nemo-ctc-conformer-small')

# Add model files
model_file = nemo_group.new_file('Listen2/Listen2/Listen2/Resources/ASRModels/nemo-ctc-conformer-small/model.int8.onnx')
tokens_file = nemo_group.new_file('Listen2/Listen2/Listen2/Resources/ASRModels/nemo-ctc-conformer-small/tokens.txt')

# Add to resources build phase
resources_phase = target.resources_build_phase
resources_phase.add_file_reference(model_file)
resources_phase.add_file_reference(tokens_file)

project.save

puts "✅ Added NeMo CTC model files to Xcode project"
