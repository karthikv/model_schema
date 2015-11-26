require 'test_helper'

class VersionTest < BaseTest
  def test_version
    refute_nil ModelSchema::VERSION
  end
end
