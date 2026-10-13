require 'xcodeproj'

root = File.expand_path('..', __dir__)
project_path = File.join(root, 'EasyTrack.xcodeproj')
project = Xcodeproj::Project.new(project_path)
project.root_object.compatibility_version = 'Xcode 16.0'
project.root_object.attributes['LastUpgradeCheck'] = '2650'

target = project.new_target(:application, 'EasyTrack', :ios, '17.0')
target.product_reference.name = 'EasyTrack.app'

group = project.main_group.new_group('EasyTrack', 'EasyTrack')
Dir.glob(File.join(root, 'EasyTrack', '**', '*.swift')).sort.each do |path|
  relative = path.delete_prefix(File.join(root, 'EasyTrack') + '/')
  components = relative.split('/')
  file_group = components[0...-1].inject(group) do |parent, name|
    parent.groups.find { |child| child.display_name == name } || parent.new_group(name, name)
  end
  reference = file_group.new_file(components.last)
  target.source_build_phase.add_file_reference(reference)
end

resources = group.new_group('Resources', 'Resources')
%w[Icon-60@2x.png Icon-60@3x.png].each do |name|
  target.resources_build_phase.add_file_reference(resources.new_file(name))
end

project.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
end

ui_target = project.new_target(:ui_test_bundle, 'EasyTrackUITests', :ios, '17.0')
ui_target.add_dependency(target)
ui_group = project.main_group.new_group('EasyTrackUITests', 'EasyTrackUITests')
Dir.glob(File.join(root, 'EasyTrackUITests', '*.swift')).sort.each do |path|
  ui_target.source_build_phase.add_file_reference(ui_group.new_file(File.basename(path)))
end
ui_target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'local.easytrack.finance.uitests',
    'PRODUCT_NAME' => 'EasyTrackUITests',
    'SWIFT_VERSION' => '5.0',
    'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
    'TARGETED_DEVICE_FAMILY' => '1',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'TEST_TARGET_NAME' => 'EasyTrack',
    'CODE_SIGN_STYLE' => 'Automatic'
  })
end

target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'local.easytrack.finance',
    'PRODUCT_NAME' => 'EasyTrack',
    'SWIFT_VERSION' => '5.0',
    'IPHONEOS_DEPLOYMENT_TARGET' => '17.0',
    'TARGETED_DEVICE_FAMILY' => '1',
    'GENERATE_INFOPLIST_FILE' => 'NO',
    'INFOPLIST_FILE' => 'EasyTrack/Info.plist',
    'OTHER_LDFLAGS' => '$(inherited) -lsqlite3',
    'CODE_SIGN_STYLE' => 'Automatic',
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'YES'
  })
end

project.save
scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(target, ui_target)
scheme.save_as(project_path, 'EasyTrack', true)
