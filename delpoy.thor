require 'json'
class Deploy < Thor
  	include Thor::Actions
	desc "testflight", "builds, signs and uploads app to testflight --notify notifies users"
	method_options :notify => :boolean, :groups => :string, :notes => :string, :configuration => :string
	def testflight
		@team_token = ""
		@api_token = ""
		@testflight_url = "http://testflightapp.com/api/builds.json"
		@build_folder = "tempBuild"
		@scheme = "YOUR APP SCHEME"
		
		if options.notify?
			@notify = "True"
		else
			@notify = "False"
		end

		if options.groups? and options.groups.length
			@distribution_groups = options.groups.strip
		else
			@distribution_groups = "Default Distribution group"
		end

		if options.configuration? and options.configuration.length
			@configuration = options.configuration
		else
			@configuration = "Release"
		end

		set_git_root
		get_creds_for_testflight
		set_project_variables
		get_app_version
		get_release_notes
		build_app
		zip_dSYM
		convert_app_to_ipa
  		upload_to_testflight
  		increment_dev_version
	end
	no_tasks do
		def set_git_root
			@git_root = run "git rev-parse --show-toplevel", :capture => true
			@git_root.strip!
			say "Root is #{@git_root}"
		end
		def get_creds_for_testflight
			File.open( "#{@git_root}/creds.json", "r" ) do |f|
        		@json = JSON.load( f )
      		end
      		
      		@team_token = @json['team_token']
      		@api_token = @json['api_token']
      		if @team_token.length > 0 and @api_token.length > 0
      			say "Team token is #{@team_token}"
      		else
      			fail("Api Token and Team Token is required for testflight")
      			
      		end

		end
		def set_project_variables
			targetOrScheme = 0
			@targets = []
			@schemes = []
			say Dir.pwd
			Dir.chdir("#{@git_root}/ios")
			say Dir.pwd
			cmd = run "xcodebuild -list", :capture => true
			data = cmd.split("\n")
			for item in data
				if item.match('^\s*Information')
					item.scan(/project\s\"(.*)\":/){|w| @project_name = w[0]}
					say("project is #{@project_name}")
				end

				if item.match('^\s{4}.*:')
					if item.match("^\s{4}Targets:")
						targetOrScheme = 1
					elsif item.match("^\s{4}Schemes:")
						targetOrScheme = 2
					else
						targetOrScheme = 0
					end
				end
				
				if item.match("^\s{8}(.*)$")
					if targetOrScheme == 1
						@targets.push(item.strip)
					elsif targetOrScheme == 2
						@schemes.push(item.strip)
					end
				end
			end
			
			say "getting build settings"
			
			cmd = run "xcodebuild -showBuildSettings -scheme #{@scheme} -configuration #{@configuration}", :capture => true
			data = cmd.scan(/\s{4}PRODUCT_NAME\s=\s(.*)\n/){|w| @product_name = w[0]}
			data = cmd.scan(/\s{4}INFOPLIST_FILE\s=\s(.*)\n/){|w| @plist_path = w[0]}
			
			say "Plist Path #{@plist_path}"
			say "We have #{@targets.length} targets and #{@schemes.length} schemes"

		end
		
		def get_app_version
			@build_number = run "/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' #{@plist_path}", :capture => true
			version = run "/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' #{@plist_path}", :capture => true
			@app_version = "#{version.strip}-#{@build_number.strip}"
			say "version number is #{@app_version}"
		end
		
		def get_release_notes
			if options.notes? and options.notes.length
				@release_notes = options.notes
			else
				@release_notes = run "/usr/libexec/PlistBuddy -c 'Print :ReleaseNotes' #{@plist_path}", :capture => true
				@release_notes= @release_notes.gsub(/\r/,' ')
				@release_notes= @release_notes.gsub(/\n/,' ')
				@release_notes.strip!
			end

			say "release notes is #{@release_notes}***"
		end
		
		def build_app
			say "building App"
			say "check dir #{@git_root}/#{@build_folder}"
			if Dir[@build_folder].empty?
				say "making #{@git_root}/#{@build_folder}"
				run "mkdir #{@git_root}/#{@build_folder}"
			end
			run "xcodebuild -project #{@project_name}.xcodeproj -scheme #{@schemes[0]} -configuration #{@configuration} CONFIGURATION_BUILD_DIR=#{@git_root}/#{@build_folder}"
			
			

		end
		
		def zip_dSYM
			path = "#{@product_name}"
			Dir.chdir("#{@git_root}/#{@build_folder}") do
				ok = run "ditto -c -k --sequesterRsrc --keepParent #{path}.app.dSYM  #{path}.app.dSYM.zip"
				fail("Failed to zip") unless ok
			end
			Dir.chdir(@git_root)
		end
		
		def convert_app_to_ipa
			say "Signing App"
			
			ok = run "/usr/bin/xcrun -sdk iphoneos PackageApplication -v #{@git_root}/#{@build_folder}/#{@product_name}.app -o #{@git_root}/#{@build_folder}/#{@product_name}.ipa"
			fail("Failed to build IPA") unless ok
		end
		def upload_to_testflight
			
			say "Uploading to testflight #{@testflight_url}"
			apiString = <<-END.gsub(/^\s+/,'')
				curl #{@testflight_url} \
				-F file=@#{@git_root}/#{@build_folder}/#{@product_name}.ipa \
				-F dsym=@#{@git_root}/#{@build_folder}/#{@product_name}.app.dSYM.zip \
				-F api_token=#{@api_token} \
				-F team_token=#{@team_token} \
				-F notes='#{@release_notes}' \
				-F notify=#{@notify} \
				-F distribution_lists='#{@distribution_groups}'
			END
			
			say apiString
			
			ok = run apiString
			fail("Failed to upload to Testflight") unless ok
		end
		def increment_dev_version
		  if @app_version.length
			  #@arrayss = @app_version.split(".").map { |s| s.to_i }
			  #@arrayss[-1] += 1
			  #@dev_version = @arrayss.join(".")
			  @dev_version = @build_number.to_i + 1
			  say "New Dev version v#{@dev_version}"
			  Dir.chdir("#{@git_root}/ios")
              say "PWD: #{Dir.pwd}"
			  say "Saving app version #{@dev_version}..."
			  cmd = "Set :CFBundleVersion #{@dev_version}"
			  ok = run "/usr/libexec/PlistBuddy -c '#{cmd}' #{@plist_path}"
			  fail('not able to increment version') unless ok

		  end
		end
	end
end
