$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'model_schema'

require 'minitest/autorun'
require 'minitest/hooks/test'

class BaseTest < Minitest::Test
  include Minitest::Hooks
end
