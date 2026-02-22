# frozen_string_literal: true

module CartographerFixtureHelpers
  def fixture_repo(name)
    File.expand_path("../fixtures/repos/#{name}", __dir__)
  end
end

RSpec.configure do |config|
  config.include CartographerFixtureHelpers, file_path: %r{/spec/spurline/cartographer/}
end
