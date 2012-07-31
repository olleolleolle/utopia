
Dir.chdir("../") do
	require './lib/utopia/version'

	Gem::Specification.new do |s|
		s.name = "utopia"
		s.version = Utopia::VERSION::STRING
		s.author = "Samuel Williams"
		s.email = "samuel.williams@oriontransfer.co.nz"
		s.homepage = "http://www.oriontransfer.co.nz/software/utopia"
		s.platform = Gem::Platform::RUBY
		s.summary = "Utopia is a framework for building websites."
		s.files = FileList["{ext,lib,bin}/**/*"].to_a
		s.require_path = "lib"

		s.executables << 'utopia'

		s.add_dependency("mime-types")
		s.add_dependency("rack")

		s.add_dependency("rack-cache")
		s.add_dependency("rack-contrib")

		s.add_dependency("rmagick")

		# s.extensions << "ext/xnode/extconf.rb"
	end
end