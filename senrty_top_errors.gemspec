Gem::Specification.new do |s|
  s.name              = "sentry_top_errors"
  s.version           = "0.1.4"
  s.summary           = "Generate top errors report for sentry"
  s.description       = ""
  s.author            = "Pavel Evstigneev"
  s.email             = "pavel.evst@gmail.com"
  s.homepage          = "http://github.com/Paxa/sentry_top_errors"
  s.executables       = ["sentry_top_errors"]
  s.files             = `git ls-files`.split("\n")
  s.licenses          = ['MIT', 'GPL-2.0']

  s.add_runtime_dependency 'excon', "~> 0.100.0"
  s.add_runtime_dependency 'progress_bar', '>= 1.0.5', '< 2.0.0'
end
