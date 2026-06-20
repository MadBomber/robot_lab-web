# frozen_string_literal: true

require_relative "lib/robot_lab/web/version"

Gem::Specification.new do |spec|
  spec.name = "robot_lab-web"
  spec.version = RobotLab::Web::VERSION
  spec.authors = ["Dewayne VanHoozer"]
  spec.email = ["dvanhoozer@gmail.com"]

  spec.summary = "Browser console for robot_lab: stream a robot's run over Server-Sent Events."
  spec.description = "A Rails-free Sinatra + HTMX + SSE web interface for robot_lab. " \
                     "Register robots, chat with them from the browser, and watch each " \
                     "lifecycle event (tool calls, results, errors) stream in real time " \
                     "via robot_lab's hook system."
  spec.homepage = "https://github.com/madbomber/robot_lab-web"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Uncomment the line below to require MFA for gem pushes.
  # This helps protect your gem from supply chain attacks by ensuring
  # no one can publish a new version without multi-factor authentication.
  # See: https://guides.rubygems.org/mfa-requirement-opt-in/
  # spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "robot_lab", ">= 0.1"
  spec.add_dependency "sinatra", "~> 4.0"
  spec.add_dependency "falcon", ">= 0.47"
  spec.add_dependency "phlex", "~> 2.0"
  spec.add_dependency "phlex-sinatra", ">= 0.5"
  spec.add_dependency "phlex-icons-hero", ">= 2.0"
  spec.add_dependency "rackup", "~> 2.1"
end
